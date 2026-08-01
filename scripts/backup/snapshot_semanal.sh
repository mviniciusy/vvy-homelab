#!/bin/bash
# snapshot_semanal.sh — Backup semanal de CTs/VMs (101,199,200,160,161) via vzdump
#
# Fluxo para cada vmid: vzdump <vmid> → upload rclone (via CT 105) → retention local (1) + remota (14d)
#
# Cron:    DOM 01:00   (0 0 1 * * 0 root /root/scripts/backup/snapshot_semanal.sh)
# Storage: backup-dump (dir:/mnt/pve/HD-WD500GB/Dados-WD500GB/vzdump, content=backup)
# Drive:   1. vvy/vvy-server-backup/SSD-{NVMe|SATA}-128GB/CT-<id>-<hostname>/
#
#   NVMe:  CT-199-minecraft, VM-200-debian
#   SATA:  CT-101-pihole, CT-160-zabbix, CT-161-grafana
#
set -euo pipefail

# ============================================================================
# Configuração
# ============================================================================
SCRIPT_NAME="snapshot_semanal"
CT_RCLONE=105                            # CT backup-manager (rclone + gdrive:)

DUMP_DIR_BASE="/mnt/pve/HD-WD500GB/Dados-WD500GB/vzdump/dump"     # caminho no host vvy
RCLONE_SRC_BASE="/mnt/wd500gb/vzdump/dump"          # mesmo dir, visto do CT 105
RCLONE_REMOTE="gdrive"
REMOTE_BASE_ROOT="1. vvy/vvy-server-backup"

RET_LOCAL_KEEP=1                         # manter 1 arquivo local mais recente
RET_REMOTE_DAYS=14                        # deletar do Drive arquivos com 14+ dias (≈2 semanais)

LOG="/var/log/${SCRIPT_NAME}.log"
LOCK="/tmp/${SCRIPT_NAME}.lock"

# Tabela vmid|tipo|hostname|ssd_dir
#   tipo: CT usa pct config, VM usa qm config (hostname em `name`)
#   O vzdump funciona para ambos, mas o nome do arquivo difere:
#     CT  → vzdump-lxc-<vmid>_<ts>.tar.zst
#     VM  → vzdump-qemu-<vmid>_<ts>.vma.zst
#   --include "vzdump-*<vmid>*" cobre ambos os padrões.
ENTRIES=(
    "101|CT|pihole|SSD-SATA-128GB"
    "199|CT|minecraft|SSD-NVMe-128GB"
    "200|VM|debian|SSD-NVMe-128GB"
    "160|CT|zabbix|SSD-SATA-128GB"
    "161|CT|grafana|SSD-SATA-128GB"
)

# ============================================================================
# Lock (flock)
# ============================================================================
exec 9>"$LOCK"
if ! flock -n 9; then
    echo "[$(date '+%F %T')] [ERROR] Outra instância já está rodando ($LOCK). Abortando." | tee -a "$LOG"
    exit 1
fi
trap 'rm -f "$LOCK"' EXIT INT TERM

# ============================================================================
# Logging
# ============================================================================
log() {
    echo "[$(date '+%F %T')] [$1] $2" | tee -a "$LOG"
}
mkdir -p "$(dirname "$LOG")"
log "INFO" "==== Início ${SCRIPT_NAME} ===="

# ============================================================================
# 1. Validação do storage backup-dump
# ============================================================================
log "INFO" "Validando storage backup-dump..."
if ! pvesm status 2>/dev/null | awk '{print $1}' | grep -qx "backup-dump"; then
    log "ERROR" "Storage backup-dump não encontrado. Abortando."
    exit 1
fi
log "INFO" "Storage backup-dump OK."
mkdir -p "$DUMP_DIR_BASE"

# ============================================================================
# Loop principal — processa cada CT/VM
# ============================================================================
TOTAL_OK=0
TOTAL_FAIL=0

for entry in "${ENTRIES[@]}"; do
    IFS='|' read -r VMID VTYPE VHOST SSD_DIR <<< "$entry"
    CT_DEST="${VTYPE}-${VMID}-${VHOST}"
    REMOTE_PATH="${REMOTE_BASE_ROOT}/${SSD_DIR}/${CT_DEST}"
    DUMP_DIR="${DUMP_DIR_BASE}"
    RCLONE_SRC="${RCLONE_SRC_BASE}"

    log "INFO" "---- Processando ${CT_DEST} (SSD: ${SSD_DIR}) ----"

    # --- 2. vzdump ---------------------------------------------------------
    log "INFO" "vzdump ${VMID}..."
    if vzdump "$VMID" \
            --storage backup-dump \
            --compress zstd \
            --mode snapshot \
            --remove 0 \
            2>&1 | tee -a "$LOG"; then
        log "INFO" "vzdump ${VMID} OK."
    else
        RC=${PIPESTATUS[0]}
        log "ERROR" "vzdump ${VMID} falhou (exit ${RC}). Pulando para próximo."
        TOTAL_FAIL=$((TOTAL_FAIL + 1))
        continue
    fi

    # --- 3. Upload rclone (via CT 105) ------------------------------------
    log "INFO" "Upload rclone: ${RCLONE_SRC} → '${REMOTE_PATH}/'"
    if pct exec "$CT_RCLONE" -- rclone copy "${RCLONE_SRC}/" \
            "${RCLONE_REMOTE}:'${REMOTE_PATH}/'" \
            --include "vzdump-*${VMID}*" \
            --transfers=4 \
            --drive-chunk-size=64M \
            2>&1 | tee -a "$LOG"; then
        log "INFO" "Upload ${CT_DEST} OK."
    else
        RC=${PIPESTATUS[0]}
        log "ERROR" "Upload ${CT_DEST} falhou (exit ${RC}). Continuando para retention."
    fi

    # --- 4. Retention local — manter N mais recentes -----------------------
    log "INFO" "Retention local ${CT_DEST}: manter ${RET_LOCAL_KEEP} arquivo(s)."
    mapfile -t OLD_FILES < <(find "$DUMP_DIR" -maxdepth 1 -type f -name "vzdump-*${VMID}*" \
        -printf '%T@\t%p\n' | sort -rn | tail -n +"$((RET_LOCAL_KEEP + 1))" | cut -f2-)
    if [ "${#OLD_FILES[@]}" -gt 0 ]; then
        for f in "${OLD_FILES[@]}"; do
            rm -f -- "$f" && log "INFO" "  removido local: $(basename "$f")"
        done
    else
        log "INFO" "  nada a remover localmente (≤ ${RET_LOCAL_KEEP} arquivo(s))."
    fi

    # --- 5. Retention remota — deletar arquivos 14+ dias ------------------
    log "INFO" "Retention remota ${CT_DEST}: deletar ${RET_REMOTE_DAYS}+ dias."
    if pct exec "$CT_RCLONE" -- rclone delete "${RCLONE_REMOTE}:'${REMOTE_PATH}'/" \
            --min-age "${RET_REMOTE_DAYS}d" \
            --rmdirs \
            2>&1 | tee -a "$LOG"; then
        log "INFO" "Retention remota ${CT_DEST} OK."
    else
        RC=${PIPESTATUS[0]}
        log "WARN" "Retention remota ${CT_DEST}: exit ${RC} (sem arquivos a deletar?)."
    fi

    TOTAL_OK=$((TOTAL_OK + 1))
    log "INFO" "---- ${CT_DEST} concluído ----"
done

log "INFO" "==== Fim ${SCRIPT_NAME} — OK: ${TOTAL_OK}, FALHOU: ${TOTAL_FAIL} ===="

# Exit não-zero se alguma VM falhou, para alertar via cron
[ "$TOTAL_FAIL" -eq 0 ] && exit 0 || exit 1
