#!/usr/bin/env bash
#
# sync_wd500gb.sh — Sync espelhado do HD-WD500GB para Google Drive via rclone
#
# Uso: bash sync_wd500gb.sh [--dry-run]
#
# O que faz:
#   rclone sync do HD-WD500GB (ext4, /mnt/wd500gb) -> gdrive:"1. vvy/vvy-server-backup"/HD-WD500GB/
#   Arquivos removidos localmente -> movidos para lixeira com timestamp (NÃO deletados)
#
# Retenção da lixeira: 14 dias (ver clean_lixeira.sh)
#
# Proteções:
#   - set -euo pipefail: aborta em erro, variável indefinida ou pipe quebrado
#   - trap: limpa lockfile em EXIT/INT/TERM
#   - flock: previne execuções concorrentes (cron overlap)
#   - --dry-run: parâmetro para preview sem alterar nada
#   - Log com timestamp em /var/log/sync_wd500gb.log
#
set -euo pipefail

# === Configuração ===
DRIVE_BASE="gdrive:1. vvy/vvy-server-backup"
SOURCE="/mnt/wd500gb"
DEST="${DRIVE_BASE}/HD-WD500GB/"
TODAY=$(date +%Y-%m-%d)
BACKUP_DIR="${DRIVE_BASE}/lixeira/HD-WD500GB/${TODAY}"
LOGFILE="/var/log/sync_wd500gb.log"
LOCKFILE="/tmp/sync_wd500gb.lock"

RCLONE_OPTS="--verbose --transfers=4 --drive-chunk-size=64M --checkers=8"

# === Parsing de argumentos ===
if [[ "${1:-}" == "--dry-run" ]]; then
    RCLONE_OPTS="${RCLONE_OPTS} --dry-run"
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
echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Iniciando sync HD-WD500GB ===" | tee -a "$LOGFILE"

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

echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Sync HD-WD500GB concluído ===" | tee -a "$LOGFILE"
