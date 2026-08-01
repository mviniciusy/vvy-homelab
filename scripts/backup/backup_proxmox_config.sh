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
#   2. Copia o tar para /mnt/pve/HD-WD500GB/Dados-WD500GB/vzdump/dump/ (storage do backup-dump)
#      que e montado no CT 105 como /mnt/wd500gb/vzdump/dump/
#   3. Upload para Google Drive via rclone rodando no CT 105
#   4. Retention: 7 dias local, 30 dias no Drive
#
# Frequencia: diario 02:00 (crontab do root)
# Log: /var/log/backup_proxmox_config.log
#
# Referencia: Plano_Backup.md secao 3.4
#

set -euo pipefail

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
GDRIVE_PATH="'1. vvy/vvy-server-backup/Proxmox-Config/'"

# Lockfile e log
LOCKFILE="/tmp/backup_proxmox_config.lock"
LOGFILE="/var/log/backup_proxmox_config.log"

# Arquivos temporarios
TMP_CRONTAB="/tmp/root-crontab-${DATE}.txt"
TMP_TAR="/tmp/${TAR_NAME}"

# Retention
LOCAL_RETENTION_DAYS=7
REMOTE_RETENTION_DAYS=30

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
# O CT 105 ve o storage em $CT_STORAGE_DIR (mp0=/mnt/wd500gb).
# GDRIVE_PATH ja vem com as aspas simples embutidas (espaco no nome da pasta).
if ! pct exec "$CT_ID" -- rclone copy \
    "${CT_STORAGE_DIR}/${TAR_NAME}" \
    "${GDRIVE_REMOTE}:${GDRIVE_PATH}"; then
    err "Falha no upload rclone para ${GDRIVE_REMOTE}:${GDRIVE_PATH}"
    exit 5
fi
log "  upload concluido: ${GDRIVE_REMOTE}:${GDRIVE_PATH}${TAR_NAME}"

# ----------------------------------------------------------------------------
# 6. Retention local (7 dias)
# ----------------------------------------------------------------------------
log "Retention local: removendo etc-pve-*.tar.gz com mais de ${LOCAL_RETENTION_DAYS} dias"
if ! find "$STORAGE_DIR" -maxdepth 1 -name 'etc-pve-*.tar.gz' -mtime +"${LOCAL_RETENTION_DAYS}" -delete; then
    log "AVISO: find falhou ou nada a remover na retention local"
else
    log "  retention local aplicada"
fi

# ----------------------------------------------------------------------------
# 7. Retention remota (30 dias no Drive)
# ----------------------------------------------------------------------------
log "Retention remota: removendo arquivos com mais de ${REMOTE_RETENTION_DAYS}d no Drive"
if ! pct exec "$CT_ID" -- rclone delete \
    "${GDRIVE_REMOTE}:${GDRIVE_PATH}" \
    --min-age "${REMOTE_RETENTION_DAYS}d" \
    --rmdirs; then
    log "AVISO: falha na retention remota (rclone delete --min-age)"
else
    log "  retention remota aplicada"
fi

# ----------------------------------------------------------------------------
# Fim
# ----------------------------------------------------------------------------
log "===== Backup de configuracao do Proxmox concluido ====="
exit 0
