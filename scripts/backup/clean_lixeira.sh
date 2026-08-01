#!/usr/bin/env bash
#
# clean_lixeira.sh — Limpeza da lixeira do Google Drive (rclone)
#
# Uso: bash clean_lixeira.sh [--dry-run]
#
# O que faz:
#   rclone delete --rmdirs na pasta de lixeira do backup, removendo arquivos
#   e pastas com mais de 14 dias de idade.
#
# Retenção: 14 dias (arquivos movidos pelo --backup-dir dos scripts de sync)
#
# Proteções:
#   - set -euo pipefail
#   - flock: previne execuções concorrentes
#   - --dry-run: parâmetro para preview sem deletar nada
#   - --rmdirs: remove pastas vazias após deletar arquivos
#   - --min-age 14d: só remove arquivos com mais de 14 dias
#   - Log em /var/log/clean_lixeira.log
#
set -euo pipefail

# === Configuração ===
DRIVE_BASE="gdrive:1. vvy/vvy-server-backup"
LIXEIRA="${DRIVE_BASE}/lixeira/"
RETENTION_DAYS="14d"
LOGFILE="/var/log/clean_lixeira.log"
LOCKFILE="/tmp/clean_lixeira.lock"

RCLONE_OPTS="--verbose --min-age ${RETENTION_DAYS} --rmdirs"

# === Parsing de argumentos ===
if [[ "${1:-}" == "--dry-run" ]]; then
    RCLONE_OPTS="${RCLONE_OPTS} --dry-run"
    echo ">>> MODO DRY-RUN (simulação) — nada será deletado" | tee -a "$LOGFILE"
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
echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Iniciando limpeza da lixeira (retenção ${RETENTION_DAYS}) ===" | tee -a "$LOGFILE"

# === Delete ===
rclone delete "$LIXEIRA" \
    $RCLONE_OPTS 2>&1 | tee -a "$LOGFILE"

RC=${PIPESTATUS[0]}
if [[ $RC -ne 0 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERRO: rclone saiu com código $RC" | tee -a "$LOGFILE"
    exit $RC
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Limpeza da lixeira concluída ===" | tee -a "$LOGFILE"
