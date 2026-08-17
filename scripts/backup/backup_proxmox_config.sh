#!/usr/bin/env bash
#
# backup_proxmox_config.sh
#
# Backup diario da configuracao critica do Proxmox VE (host vvy):
#   - /etc/pve/         (coracao do Proxmox: containers, VMs, storage, rede)
#   - /etc/samba/smb.conf
#   - crontab do root
#   - /root/iac/        (Terraform + Ansible)
#
# Fluxo:
#   1. Cria tar.gz no host (necessario: /etc/pve/ so existe no host)
#   2. Copia o tar para /mnt/pve/HD-WD500GB/vzdump/dump/ (storage do backup-dump)
#      que e montado no CT 105 como /mnt/wd500gb/vzdump/dump/
#   3. Upload para Google Drive via rclone rodando no CT 105
#   4. Retention: manter 3 backups mais recentes (local e Google Drive)
#
# Frequencia: diario 02:00 (crontab do root)
# Log: /var/log/backup_proxmox_config.log
#
# Referencia: Plano_Backup.md secao 3.4
#

set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# ----------------------------------------------------------------------------
# Configuracao
# ----------------------------------------------------------------------------
HOST_NAME="vvy"
CT_ID="105"
DATE="$(date +%Y-%m-%d)"
TAR_NAME="etc-pve-${DATE}.tar.gz"

# Diretorios
STORAGE_DIR="/mnt/pve/HD-WD500GB/Dados-WD500GB/vzdump/dump"          # no host (storage HD-WD500GB)
CT_STORAGE_DIR="/mnt/wd500gb/vzdump/dump"             # mesmo ponto, visto do CT 105
GDRIVE_REMOTE="gdrive"
GDRIVE_PATH="1. vvy/vvy-server-backup/Proxmox-Config/"

# Lockfile e log
LOCKFILE="/tmp/backup_proxmox_config.lock"
LOGFILE="/var/log/backup_proxmox_config.log"

# Arquivos temporarios
TMP_CRONTAB="/tmp/root-crontab-${DATE}.txt"
TMP_TAR="/tmp/${TAR_NAME}"

# Retention (contagem — manter N backups mais recentes)
RET_LOCAL_KEEP=3
RET_REMOTE_KEEP=3

# ----------------------------------------------------------------------------
# Funcoes de log
# ----------------------------------------------------------------------------
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRO: $*" | tee -a "$LOGFILE" >&2
}

cleanup() {
    local rc=$?
    rm -f "$LOCKFILE" "$TMP_CRONTAB" "$TMP_TAR" 2>/dev/null || true
    if [ $rc -ne 0 ]; then
        log "Backup ENCERRADO COM ERRO (exit code: $rc)"
    else
        log "Backup concluido com sucesso"
    fi
    exit $rc
}

# ----------------------------------------------------------------------------
# Inicio
# ----------------------------------------------------------------------------
# Lock com flock (nao bloqueante: falha se outra instancia estiver rodando)
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    err "Outra instancia ja em execucao (lock $LOCKFILE ocupado). Saindo."
    exit 1
fi
trap cleanup EXIT INT TERM

log "===== Inicio backup_proxmox_config.sh em ${HOST_NAME} ====="

# ----------------------------------------------------------------------------
# 1. Coletar crontab do root
# ----------------------------------------------------------------------------
log "Coletando crontab do root..."
if crontab -l > "$TMP_CRONTAB" 2>/dev/null; then
    log "  crontab salvo em $TMP_CRONTAB ($(wc -l < "$TMP_CRONTAB") linhas)"
else
    # crontab vazio / ausente nao e erro fatal
    log "  AVISO: crontab -l falhou ou vazio. Criando arquivo vazio."
    : > "$TMP_CRONTAB"
fi

# ----------------------------------------------------------------------------
# 2. Listar itens para o tar
# ----------------------------------------------------------------------------
TAR_ITEMS=()
TAR_ITEMS+=("/etc/pve/")
TAR_ITEMS+=("/etc/samba/smb.conf")
TAR_ITEMS+=("$TMP_CRONTAB")

# /root/iac/ so se existir
if [ -d "/root/iac/" ]; then
    TAR_ITEMS+=("/root/iac/")
    log "Incluindo /root/iac/ (Terraform + Ansible)"
else
    log "AVISO: /root/iac/ nao existe. Pulando."
fi

# ----------------------------------------------------------------------------
# 3. Criar tar.gz no host (/etc/pve/ so existe no host)
# ----------------------------------------------------------------------------
log "Criando tar.gz: $TMP_TAR"
# O TMP_CRONTAB entra no tar com path /tmp/...; usamos --transform para renomear
# para um nome estavel dentro do tar (root-crontab.txt), independente da data.
# O sed do GNU tar precisa de separador que colida com o path: usamos | .
if ! tar -czf "$TMP_TAR" \
    --transform="s|^tmp/root-crontab-${DATE}\.txt|root-crontab.txt|" \
    "${TAR_ITEMS[@]}"; then
    err "Falha ao criar tar $TMP_TAR"
    exit 2
fi

TAR_SIZE=$(du -h "$TMP_TAR" | cut -f1)
log "  tar criado: $TMP_TAR ($TAR_SIZE)"

# ----------------------------------------------------------------------------
# 4. Copiar tar para o storage (visivel do CT 105)
# ----------------------------------------------------------------------------
log "Copiando tar para storage $STORAGE_DIR"
if [ ! -d "$STORAGE_DIR" ]; then
    err "Storage dir $STORAGE_DIR nao existe"
    exit 3
fi
if ! cp -a "$TMP_TAR" "$STORAGE_DIR/${TAR_NAME}"; then
    err "Falha ao copiar tar para $STORAGE_DIR"
    exit 4
fi
log "  copiado para $STORAGE_DIR/${TAR_NAME}"

# ----------------------------------------------------------------------------
# 5. Upload para Google Drive via rclone no CT 105
# ----------------------------------------------------------------------------
log "Upload para Google Drive via rclone (CT 105)..."
# pct exec não preserva aspas em paths com espaços; usar bash -c com args posicionais
# --verbose + 2>&1 para capturar stderr do rclone no log (sem isso, erro real é perdido)
if ! pct exec "$CT_ID" -- bash -c 'rclone copy "$1" "$2" --verbose 2>&1' \
    _ "${CT_STORAGE_DIR}/${TAR_NAME}" "${GDRIVE_REMOTE}:${GDRIVE_PATH}" | tee -a "$LOGFILE"; then
    err "Falha no upload rclone para ${GDRIVE_REMOTE}:${GDRIVE_PATH}"
    exit 5
fi
log "  upload concluido: ${GDRIVE_REMOTE}:${GDRIVE_PATH}${TAR_NAME}"

# ----------------------------------------------------------------------------
# 6. Retention local (manter N mais recentes)
# ----------------------------------------------------------------------------
log "Retention local: manter ${RET_LOCAL_KEEP} arquivo(s) etc-pve-*.tar.gz mais recente(s)"
mapfile -t OLD_CFG < <(find "$STORAGE_DIR" -maxdepth 1 -type f -name 'etc-pve-*.tar.gz' -printf '%T@\t%p\n' \
    | sort -rn | tail -n +"$((RET_LOCAL_KEEP + 1))" | cut -f2-)
if [ "${#OLD_CFG[@]}" -gt 0 ]; then
    for f in "${OLD_CFG[@]}"; do
        rm -f -- "$f" && log "  removido local: $(basename "$f")"
    done
else
    log "  retention local: nada a remover (≤ ${RET_LOCAL_KEEP})"
fi

# ----------------------------------------------------------------------------
# 7. Retention remota (manter N mais recentes no Drive)
# ----------------------------------------------------------------------------
log "Retention remota: manter ${RET_REMOTE_KEEP} backup(s) mais recente(s) no Drive"
if ! pct exec "$CT_ID" -- bash -c '/root/backup-manager/app/rclone_keep.sh "$1" "$2" 2>&1' \
    _ "${GDRIVE_REMOTE}:${GDRIVE_PATH}" "$RET_REMOTE_KEEP" | tee -a "$LOGFILE"; then
    log "AVISO: falha na retention remota (rclone_keep.sh)"
else
    log "  retention remota aplicada"
fi

# ----------------------------------------------------------------------------
# Fim
# ----------------------------------------------------------------------------
log "===== Backup de configuracao do Proxmox concluido ====="
exit 0
