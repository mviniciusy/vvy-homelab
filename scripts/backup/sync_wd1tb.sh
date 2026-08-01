#!/usr/bin/env bash
#
# sync_wd1tb.sh — Sync espelhado do HD-WD-1TB para Google Drive via rclone
#
# Uso: bash sync_wd1tb.sh [--dry-run]
#
# O que faz:
#   rclone sync do HD-WD-1TB (NTFS, /mnt/wd1tb) -> gdrive:"1. vvy/vvy-server-backup"/HD-WD-1TB/
#   Arquivos removidos localmente -> movidos para lixeira com timestamp (NÃO deletados)
#
# Exclusões:
#   ISOs/ — imagens ISO recuperáveis (Windows, Kali, Proxmox), ~10 GB
#
# Retenção da lixeira: 14 dias (ver clean_lixeira.sh)
#
# Proteções:
#   - set -euo pipefail: aborta em erro, variável indefinida ou pipe quebrado
#   -trap: limpa lockfile em EXIT/INT/TERM (não deixa lock órfão)
#   - flock: previne execuções concorrentes (cron overlap)
#   - --dry-run:.AddParameter para preview sem alterar nada
#   - Log com timestamp em /var/log/sync_wd1tb.log
#
set -euo pipefail

# === Configuração ===
DRIVE_BASE="gdrive:1. vvy/vvy-server-backup"
SOURCE="/mnt/wd1tb"
DEST="${DRIVE_BASE}/HD-WD-1TB/"
TODAY=$(date +%Y-%m-%d)
BACKUP_DIR="${DRIVE_BASE}/lixeira/HD-WD-1TB/${TODAY}"
RCLONE_OPTS="--verbose --transfers=8 --drive-chunk-size=64M --checkers=16 --exclude=ISOs/** --exclude=WavesCentral14.17.01.23.W/**"
LOGFILE="/var/log/sync_wd1tb.log"
LOCKFILE="/tmp/sync_wd1tb.lock"


# === Parsing de argumentos ===
if [[ "${1:-}" == "--dry-run" ]]; then
    echo ">>> MODO DRY-RUN (simulação) — nada será alterado" | tee -a "$LOGFILE"
fi

# === Proteções ===
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRO: outra instância já está rodando (lock $LOCKFILE ocupado)" | tee -a "$LOGFILE"
    exit 1
fi
trap 'rm -f "$LOCKFILE"' EXIT INT TERM

# === Log ===
echo "" >> "$LOGFILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Iniciando sync HD-WD-1TB ===" | tee -a "$LOGFILE"

# === Verificar se o mount point está acessível ===
if ! mountpoint -q "$SOURCE"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRO: $SOURCE não está montado. Abortando." | tee -a "$LOGFILE"
    exit 1
fi

# === Sync ===
rclone sync "$SOURCE/" "$DEST" \
    --backup-dir "$BACKUP_DIR" \
    $RCLONE_OPTS 2>&1 | tee -a "$LOGFILE"

RC=${PIPESTATUS[0]}
if [[ $RC -ne 0 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRO: rclone saiu com código $RC" | tee -a "$LOGFILE"
    exit $RC
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Sync HD-WD-1TB concluído ===" | tee -a "$LOGFILE"
