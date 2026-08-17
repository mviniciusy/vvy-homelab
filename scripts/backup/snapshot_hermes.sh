#!/bin/bash
# snapshot_hermes.sh — Backup diário do CT 104 (hermes-agent) via vzdump
#
# Fluxo:  vzdump 104 → upload rclone (via CT 105) → retention local (2) + remota (7 dias)
#
# Cron:    DIÁRIO 02:30   (0 30 2 * * * root /root/scripts/backup/snapshot_hermes.sh)
# Storage: backup-dump    (dir:/mnt/pve/HD-WD500GB/vzdump, content=backup)
# Drive:   1. vvy/vvy-server-backup/SSD-NVMe-128GB/CT-104-hermes-agent/
#
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# ============================================================================
# Configuração
# ============================================================================
SCRIPT_NAME="snapshot_hermes"
VMID=104
HOSTNAME="hermes-agent"
SSD_TIPO="NVMe"                          # NVMe | SATA
SSD_DIR="SSD-NVMe-128GB"
CT_DEST="CT-${VMID}-${HOSTNAME}"

DUMP_DIR="/mnt/pve/HD-WD500GB/Dados-WD500GB/vzdump/dump" # caminho no host vvy
RCLONE_SRC="/mnt/wd500gb/vzdump/dump"                # mesmo dir, visto do CT 105
RCLONE_REMOTE="gdrive"
REMOTE_BASE="1. vvy/vvy-server-backup/${SSD_DIR}/${CT_DEST}"

CT_RCLONE=105                            # CT backup-manager (rclone + gdrive:)

RET_LOCAL_KEEP=3                         # manter 3 backups locais mais recentes
RET_REMOTE_KEEP=3                        # manter 3 backups mais recentes no Drive

LOG="/var/log/${SCRIPT_NAME}.log"
LOCK="/tmp/${SCRIPT_NAME}.lock"

# ============================================================================
# Lock (flock) — evita execução simultânea
# ============================================================================
exec 9>"$LOCK"
if ! flock -n 9; then
    echo "[$(date '+%F %T')] [ERROR] Outra instância já está rodando ($LOCK). Abortando." | tee -a "$LOG"
    exit 1
fi
# Limpa o lockfile ao sair (EXIT/INT/TERM)
trap 'rm -f "$LOCK"' EXIT INT TERM

# ============================================================================
# Logging
# ============================================================================
log() {
    echo "[$(date '+%F %T')] [$1] $2" | tee -a "$LOG"
}

mkdir -p "$(dirname "$LOG")"
log "INFO" "==== Início ${SCRIPT_NAME} (CT ${VMID} ${HOSTNAME}) ===="

# ============================================================================
# 1. Validação do storage backup-dump
# ============================================================================
log "INFO" "Validando storage backup-dump (até 8 tentativas × 20s = 160s)..."
STORAGE_OK=0
for attempt in 1 2 3 4 5 6 7 8; do
    # pvesm list é mais resiliente que pvesm status|awk|grep sob concorrência
    # pmxcfs (corosync/pve-ha-crm inactive em single-node sem HA).
    # Primary: pvesm list  /  Fallback: pvesm status | awk | grep -qx
    if pvesm list backup-dump >/dev/null 2>&1 || pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "backup-dump"; then
        STORAGE_OK=1
        log "INFO" "Storage backup-dump OK (tentativa ${attempt}/8)."
        break
    fi
    log "WARN" "Tentativa ${attempt}/8: storage não disponível. Aguardando 20s..."
    sleep 20
done
if [ $STORAGE_OK -ne 1 ]; then
    log "ERROR" "Storage backup-dump não encontrado após 8 tentativas (160s). Abortando."
    exit 1
fi
log "INFO" "Storage backup-dump OK."

# Confirma que o dir de dump existe (vzdump cria subpasta dump/)
mkdir -p "$DUMP_DIR"

# ============================================================================
# 2. vzdump — snapshot em modo snapshot, compressão zstd, sem remover (remove 0)
# ============================================================================
log "INFO" "Executando vzdump ${VMID} (snapshot + zstd)..."
if vzdump "$VMID" \
        --storage backup-dump \
        --compress zstd \
        --mode snapshot \
        --remove 0 \
        2>&1 | tee -a "$LOG"; then
    log "INFO" "vzdump ${VMID} concluído com sucesso."
else
    RC=$?
    log "ERROR" "vzdump ${VMID} falhou (exit ${RC}). Abortando."
    exit "$RC"
fi

# ============================================================================
# 3. Upload para Google Drive via rclone no CT 105
# ============================================================================
log "INFO" "Upload rclone: ${RCLONE_SRC} → ${RCLONE_REMOTE}: '${REMOTE_BASE}/'"
# pct exec não preserva aspas em paths com espaços; usar bash -c com args posicionais
if pct exec "$CT_RCLONE" -- bash -c '
        rclone copy "$1/" "$2" \
        --include "vzdump-*$3*" \
        --verbose \
        --transfers=4 \
        --drive-chunk-size=64M
    ' _ "$RCLONE_SRC" "${RCLONE_REMOTE}:${REMOTE_BASE}/" "$VMID" \
        2>&1 | tee -a "$LOG"; then
    log "INFO" "Upload rclone concluído."
else
    RC=$?
    log "ERROR" "Upload rclone falhou (exit ${RC}). Continuando para retention."
fi

# ============================================================================
# 4. Retention local — manter N backups mais recentes (por contagem, não mtime)
#    Somente arquivos de backup (.tar.zst/.vma.zst) contam — .log NÃO ocupa slot.
#    Remove também o log correspondente a backups podados.
# ============================================================================
log "INFO" "Retention local: manter ${RET_LOCAL_KEEP} backup(s) mais recente(s)."
mapfile -t OLD_FILES < <(find "$DUMP_DIR" -maxdepth 1 -type f \( -name "vzdump-*${VMID}*.tar.zst" -o -name "vzdump-*${VMID}*.vma.zst" \) -printf '%T@\t%p\n' \
    | sort -rn \
    | tail -n +"$((RET_LOCAL_KEEP + 1))" \
    | cut -f2-)

if [ "${#OLD_FILES[@]}" -gt 0 ]; then
    log "INFO" "Removendo ${#OLD_FILES[@]} backup(s) local(is) antigo(s):"
    for f in "${OLD_FILES[@]}"; do
        rm -f -- "$f" && log "INFO" "  removido: $(basename "$f")"
        base="${f%.*}"; base="${base%.*}"
        rm -f -- "${base}.log" 2>/dev/null || true
    done
else
    log "INFO" "Nenhum backup local a remover (≤ ${RET_LOCAL_KEEP} backup(s))."
fi

# ============================================================================
# 5. Retention remota — manter K backups mais recentes no Drive
# ============================================================================
log "INFO" "Retention remota: manter ${RET_REMOTE_KEEP} backup(s) mais recente(s) em '${REMOTE_BASE}/'"
if pct exec "$CT_RCLONE" -- bash -c '/root/backup-manager/app/rclone_keep.sh "$1" "$2" 2>&1' \
    _ "${RCLONE_REMOTE}:${REMOTE_BASE}/" "$RET_REMOTE_KEEP" \
    2>&1 | tee -a "$LOG"; then
    log "INFO" "Retention remota concluída."
else
    RC=$?
    log "WARN" "Retention remota reportou exit ${RC}."
fi

log "INFO" "==== Fim ${SCRIPT_NAME} (CT ${VMID}) ===="
exit 0
