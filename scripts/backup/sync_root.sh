#!/bin/bash
# ============================================================================
# sync_root.sh — Backup das pastas de /root do host vvy para Google Drive
# ----------------------------------------------------------------------------
# Executa no HOST vvy. Cria tar.gz de cada pasta de /root, copia para
# o staging no CT 105 (via mount point /mnt/wd500gb), e faz upload via
# "pct exec 105 -- rclone copy" para o Google Drive.
#
# Destino remoto: gdrive:1. vvy/vvy-server-backup/Host-Root/
# Política: rclone copy (NÃO sync) — /root é aditivo, evitar deleções
# Retention: 30 dias no destino (--min-age 30d --rmdirs)
#
# Cronjob: semanal, quartas-feiras às 03:00  →  0 3 * * 3
# ============================================================================

set -euo pipefail

# --- Configuração ---
LOG="/var/log/sync_root.log"
LOCKFILE="/tmp/sync_root.lock"
HOSTNAME=$(hostname)
CT_ID=105

# Diretório de staging (acessível pelo CT 105 via mount point mp0)
# No host:  /mnt/pve/HD-WD500GB/Dados-WD500GB/vvy-server-backup/staging/
# No CT105: /mnt/wd500gb/vvy-server-backup/staging/
STAGING_DIR="/mnt/pve/HD-WD500GB/Dados-WD500GB/vvy-server-backup/staging"

# Destino remoto no Google Drive (rclone remote gdrive, configurado no CT 105)
REMOTE_DST='gdrive:1. vvy/vvy-server-backup/Host-Root/'

# Retention: remover arquivos com mais de N dias no destino remoto
RETENTION_DAYS=30

# Lista das 8 pastas de /root para backup
DIRS=(
    "1 Documentação Privada"
    "1 Documentação GITHUB"
    "1 Obsidian"
    "2 Oracle"
    "iac"
    "logs"
    "scripts"
)

# --- Cores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Funções de log ---
log()     { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
log_info() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]${NC} $*" | tee -a "$LOG"; }
log_ok()   { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] [OK ]${NC} $*" | tee -a "$LOG"; }
log_warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]${NC} $*" | tee -a "$LOG"; }
log_err()  { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [ERRO]${NC} $*" | tee -a "$LOG"; }

# --- Lock + trap (execução única) ---
exec 200>"$LOCKFILE"
if ! flock -n 200; then
    echo -e "${RED}[ERRO]${NC} Outra instância já está em execução (lock em $LOCKFILE)." | tee -a "$LOG"
    exit 1
fi

cleanup() {
    local exit_code=$?
    # Limpar tarballs temporários locais (não os do staging)
    rm -f /tmp/root-backup-*.tar.gz 2>/dev/null || true
    rm -f "$LOCKFILE" 2>/dev/null || true
    log "Limpeza concluída (exit_code=$exit_code)."
}
trap cleanup EXIT

# --- Sanitização de nome de pasta para nome de arquivo ---
sanitize_name() {
    local name="$1"
    # Acentos -> ASCII, espaços -> underscore, lowercase
    echo "$name" \
        | sed 's/á/a/g; s/Á/A/g; s/â/a/g; s/ã/a/g; s/à/a/g' \
        | sed 's/é/e/g; s/É/E/g; s/ê/e/g' \
        | sed 's/í/i/g; s/Í/I/g' \
        | sed 's/ó/o/g; s/Ó/O/g; s/ô/o/g; s/õ/o/g' \
        | sed 's/ú/u/g; s/Ú/U/g; s/ü/u/g' \
        | sed 's/ç/c/g; s/Ç/C/g' \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/ \+/_/g; s/[^a-z0-9_.-]//g'
}

# --- Início ---
log_info "=============================================="
log_info "Iniciando backup de /root no host $HOSTNAME"
log_info "Destino: $REMOTE_DST"
log_info "Staging: $STAGING_DIR"
log_info "Retention: ${RETENTION_DAYS} dias no destino"
log_info "=============================================="

# --- Validar staging ---
if [ ! -d "$STAGING_DIR" ]; then
    log_info "Criando diretório de staging..."
    mkdir -p "$STAGING_DIR"
fi

if [ ! -w "$STAGING_DIR" ]; then
    log_err "Staging não é gravável: $STAGING_DIR"
    exit 1
fi

# --- Validar acesso ao CT 105 ---
log_info "Validando acesso ao CT $CT_ID..."
if ! pct status "$CT_ID" 2>/dev/null | grep -q "status: running"; then
    log_err "CT $CT_ID não está em execução."
    exit 1
fi
if ! pct exec "$CT_ID" -- rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
    log_err "Remote gdrive não encontrado no CT $CT_ID."
    exit 1
fi
log_ok "CT $CT_ID acessível e remote gdrive OK."

# --- Limpar staging de arquivos .tar.gz anteriores ---
log_info "Limpando staging de tarballs anteriores..."
rm -f "${STAGING_DIR}"/root-backup-*.tar.gz 2>/dev/null || true

# --- Variáveis de controle ---
ERRORS=0
SUCCESS=0
SKIPPED=0

# --- Backup de cada pasta ---
for dir in "${DIRS[@]}"; do
    src="/root/${dir}"

    if [ ! -d "$src" ]; then
        log_warn "Pasta não encontrada (pulando): $src"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    safe_name=$(sanitize_name "$dir")
    tarball="/tmp/root-backup-${safe_name}.tar.gz"
    staging_file="${STAGING_DIR}/root-backup-${safe_name}.tar.gz"

    log_info "Processando: '$dir' → root-backup-${safe_name}.tar.gz"

    # Criar tar.gz (preservar permissões; excluir .git não é necessário — é backup)
    if ! tar czf "$tarball" -C /root "$dir" 2>/dev/null; then
        log_err "Falha ao criar tar.gz de: $dir"
        rm -f "$tarball" 2>/dev/null || true
        ERRORS=$((ERRORS + 1))
        continue
    fi

    local_size=$(du -h "$tarball" | cut -f1)
    log_info "Tarball criado: ${tarball} (${local_size})"

    # Copiar para staging (visível no CT 105)
    if ! cp -f "$tarball" "$staging_file"; then
        log_err "Falha ao copiar para staging: $staging_file"
        rm -f "$tarball" 2>/dev/null || true
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # Limpar tarball temporário local
    rm -f "$tarball" 2>/dev/null || true

    log_ok "Staging OK: ${staging_file}"
    SUCCESS=$((SUCCESS + 1))
done

# --- Resumo do empacotamento ---
log_info "Empacotamento: ${SUCCESS} OK, ${SKIPPED} puladas, ${ERRORS} erros"

if [ "$SUCCESS" -eq 0 ]; then
    log_err "Nenhum tarball gerado. Abortando upload."
    exit 1
fi

# --- Upload via rclone no CT 105 ---
log_info "Iniciando upload para Google Drive..."
log_info "Origem (no CT 105): /mnt/wd500gb/vvy-server-backup/staging/"
log_info "Destino: $REMOTE_DST"

if pct exec "$CT_ID" -- rclone copy \
        /mnt/wd500gb/vvy-server-backup/staging/ \
        "$REMOTE_DST" \
        --include 'root-backup-*.tar.gz' \
        --transfers=2 \
        --checkers=4 \
        --contimeout=60s \
        --timeout=300s \
        --retries=3 \
        --retries-sleep=10s \
        --log-file=/tmp/rclone-root-backup.log \
        --log-level=INFO; then
    log_ok "Upload concluído."
else
    log_err "Falha no upload via rclone (exit=$?). Verifique /tmp/rclone-root-backup.log no CT $CT_ID."
    ERRORS=$((ERRORS + 1))
fi

# --- Limpar staging após upload ---
log_info "Limpando staging após upload..."
rm -f "${STAGING_DIR}"/root-backup-*.tar.gz 2>/dev/null || true

# --- Retention no destino remoto (30 dias) ---
log_info "Aplicando retention: removendo arquivos com > ${RETENTION_DAYS} dias no destino..."
if pct exec "$CT_ID" -- rclone delete \
        "$REMOTE_DST" \
        --min-age "${RETENTION_DAYS}d" \
        --rmdirs \
        --verbose 2>&1 | tee -a "$LOG"; then
    log_ok "Retention aplicada."
else
    log_warn "Retention falhou (exit=$?) — não aborta, apenas avisa."
fi

# --- Resumo final ---
log_info "=============================================="
log_info "Backup de /root finalizado."
log_info "Pastas: ${SUCCESS} OK, ${SKIPPED} puladas, ${ERRORS} erros"
log_info "Destino: $REMOTE_DST"
log_info "=============================================="

if [ "$ERRORS" -gt 0 ]; then
    log_err "Backup concluído com ${ERRORS} erro(s)."
    exit 1
fi

log_ok "Backup concluído com sucesso."
exit 0
