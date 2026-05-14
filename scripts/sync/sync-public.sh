#!/bin/bash
# ============================================
# sync-public.sh — Sincroniza repo privado → repo público com sanitização
# ============================================
# Uso: ./sync-public.sh [--dry-run] [--commit-msg "mensagem"] [--no-push]
#
# --dry-run     : Mostra o que seria feito sem executar
# --commit-msg  : Mensagem customizada para o commit
# --no-push     : Faz commit mas não faz push
#
# O script lê o sanitization-map.conf do repo privado, copia os arquivos
# do privado para o público, substitui dados reais por placeholders nos .md,
# e gera a versão sanitizada do sanitization-map.conf para o repo público.
# ============================================

set -euo pipefail

# --- Configuração ---
PRIV_DIR="/root/1 Documentação Privada"
PUB_DIR="/root/1 Documentação GITHUB"
MAP_FILE="$PRIV_DIR/sanitization-map.conf"

# Arquivos/dirs que NÃO são copiados do privado para o público
SKIP_ITEMS=(
    "PROXMOX_VVY.md"
    ".gitignore"
    ".git"
)

# --- Parse de argumentos ---
DRY_RUN=false
COMMIT_MSG="sync: atualização do repo público"
NO_PUSH=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --commit-msg)
            COMMIT_MSG="$2"
            shift 2
            ;;
        --no-push)
            NO_PUSH=true
            shift
            ;;
        *)
            echo "❌ Argumento desconhecido: $1"
            echo "Uso: $0 [--dry-run] [--commit-msg \"mensagem\"] [--no-push]"
            exit 1
            ;;
    esac
done

# --- Cores ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Funções ---
log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_dry()   { echo -e "${YELLOW}[DRY]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_err()   { echo -e "${RED}[ERRO]${NC} $1"; }

# --- Validações ---
if [[ ! -d "$PRIV_DIR" ]]; then
    log_err "Diretório privado não encontrado: $PRIV_DIR"
    exit 1
fi

if [[ ! -d "$PUB_DIR" ]]; then
    log_err "Diretório público não encontrado: $PUB_DIR"
    exit 1
fi

if [[ ! -f "$MAP_FILE" ]]; then
    log_err "Arquivo de mapeamento não encontrado: $MAP_FILE"
    exit 1
fi

if [[ ! -d "$PUB_DIR/.git" ]]; then
    log_err "Repo público não é um repositório git: $PUB_DIR"
    exit 1
fi

# ============================================
# 1. Ler o mapa de sanitização e ordenar por tamanho
# ============================================
log_info "Lendo mapa de sanitização: $MAP_FILE"

declare -a REAL_VALUES=()
declare -a PLACEHOLDERS=()

while IFS= read -r line; do
    # Ignorar linhas vazias e comentários
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Remover espaços ao redor do =
    line=$(echo "$line" | sed 's/[[:space:]]*=[[:space:]]*/=/')
    # Extrair valor_real e placeholder
    real_val="${line%%=*}"
    placeholder="${line#*=}"
    # Validar
    if [[ -z "$real_val" || -z "$placeholder" ]]; then
        log_warn "Linha ignorada (formato inválido): $line"
        continue
    fi
    REAL_VALUES+=("$real_val")
    PLACEHOLDERS+=("$placeholder")
done < "$MAP_FILE"

# Ordenar por tamanho do valor real (decrescente) para evitar substituições parciais
declare -a SORTED_INDICES=()
for i in "${!REAL_VALUES[@]}"; do
    SORTED_INDICES+=("$i")
done

# Bubble sort por tamanho decrescente (simples, poucos elementos)
for ((i=0; i<${#SORTED_INDICES[@]}-1; i++)); do
    for ((j=i+1; j<${#SORTED_INDICES[@]}; j++)); do
        idx_i=${SORTED_INDICES[$i]}
        idx_j=${SORTED_INDICES[$j]}
        if [[ ${#REAL_VALUES[$idx_i]} -lt ${#REAL_VALUES[$idx_j]} ]]; then
            tmp=${SORTED_INDICES[$i]}
            SORTED_INDICES[$i]=${SORTED_INDICES[$j]}
            SORTED_INDICES[$j]=$tmp
        fi
    done
done

log_ok "Carregadas ${#REAL_VALUES[@]} regras de sanitização"

if $DRY_RUN; then
    log_dry "Regras de sanitização (ordenadas por tamanho decrescente):"
    for idx in "${SORTED_INDICES[@]}"; do
        log_dry "  ${REAL_VALUES[$idx]} → ${PLACEHOLDERS[$idx]}"
    done
fi

# ============================================
# 2. Copiar arquivos do privado para o público
# ============================================
log_info "Copiando arquivos do privado para o público..."

# Função para verificar se um item deve ser pulado
should_skip() {
    local item="$1"
    for skip in "${SKIP_ITEMS[@]}"; do
        if [[ "$item" == "$skip" ]]; then
            return 0
        fi
    done
    return 1
}

# Copiar docs/, scripts/, README.md, LICENSE
ITEMS_TO_COPY=("docs" "scripts" "README.md" "LICENSE")

for item in "${ITEMS_TO_COPY[@]}"; do
    src="$PRIV_DIR/$item"
    dst="$PUB_DIR/$item"
    
    if should_skip "$item"; then
        if $DRY_RUN; then log_dry "Pulando (não copiado): $item"; fi
        continue
    fi
    
    if [[ ! -e "$src" ]]; then
        log_warn "Não encontrado no privado: $src"
        continue
    fi
    
    if $DRY_RUN; then
        log_dry "Copiaria: $src → $dst"
    else
        if [[ -d "$src" ]]; then
            rm -rf "$dst"
            cp -r "$src" "$dst"
        else
            cp -f "$src" "$dst"
        fi
        log_ok "Copiado: $item"
    fi
done

# ============================================
# 3. Gerar versão sanitizada do sanitization-map.conf para o público
# ============================================
log_info "Gerando sanitization-map.conf sanitizado para o público..."

if $DRY_RUN; then
    log_dry "Geraria versão sanitizada em: $PUB_DIR/sanitization-map.conf"
else
    cat > "$PUB_DIR/sanitization-map.conf" << 'HEADER'
# ============================================
# Referência de Placeholders da Documentação
# ============================================
# Este arquivo lista os placeholders utilizados
# na documentação pública. Os valores reais são
# mantidos apenas no repositório privado.
# ============================================

HEADER

# Gerar versão sanitizada: copiar estrutura, remover valores reais
    current_section=""
    while IFS= read -r line; do
        # Detectar seções (linhas de comentário com ---): copiar diretamente
        if [[ "$line" =~ ^[[:space:]]*#\ *--- ]]; then
            if [[ "$line" != "$current_section" ]]; then
                current_section="$line"
                echo "" >> "$PUB_DIR/sanitization-map.conf"
                echo "$line" >> "$PUB_DIR/sanitization-map.conf"
            fi
            continue
        fi

        # Ignorar linhas vazias e comentários gerais
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Extrair placeholder (lado direito do =)
        line_clean=$(echo "$line" | sed 's/[[:space:]]*=[[:space:]]*/=/')
        placeholder="${line_clean#*=}"
        real_val="${line_clean%%=*}"

        if [[ -n "$placeholder" && -n "$real_val" ]]; then
            # Gerar descrição automática a partir do nome do placeholder
            desc=$(echo "$placeholder" | sed 's/<//g; s/>//g; s/_/ /g; s/  */ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
            printf "%-22s # %s\n" "$placeholder" "$desc" >> "$PUB_DIR/sanitization-map.conf"
        fi
    done < "$MAP_FILE"

    log_ok "sanitization-map.conf sanitizado gerado"
fi

# ============================================
# 4. Aplicar sanitização nos arquivos .md do público
# ============================================

log_info "Aplicando sanitização nos arquivos .md do repo público..."

if $DRY_RUN; then
    log_dry "Aplicaria substituições nos arquivos .md do repo público"
else
    # Aplicar substituições nos arquivos .md do repo público
    for md_file in "$PUB_DIR"/docs/*.md; do
        if [[ -f "$md_file" ]]; then
            for idx in "${SORTED_INDICES[@]}"; do
                real_val="${REAL_VALUES[$idx]}"
                placeholder="${PLACEHOLDERS[$idx]}"
                # Escapar caracteres especiais do sed (. * ^ $ [ ] \ /)
                escaped_real=$(printf '%s\n' "$real_val" | sed 's/[[\.*^$()+?{|\\]/\\&/g; s/\//\\\//g')
                # Substituir valor real pelo placeholder (delimitador # para evitar conflito com /)
                sed -i "s#${escaped_real}#${placeholder}#g" "$md_file"
            done
            log_ok "Sanitizado: $(basename "$md_file")"
        fi
    done
fi

# ============================================
# 5. Git add, commit e push no repo público
# ============================================

log_info "Preparando commit no repo público..."

if $DRY_RUN; then
    log_dry "Executaria: cd $PUB_DIR && git add . && git commit -m \"$COMMIT_MSG\""
    if ! $NO_PUSH; then
        log_dry "Executaria: git push origin main"
    fi
else
    cd "$PUB_DIR"
    git add .
    if git diff --staged --quiet; then
        log_info "Nenhuma alteração detectada"
    else
        git commit -m "$COMMIT_MSG"
        if ! $NO_PUSH; then
            log_info "Fazendo push para o repo público..."
            git push origin main
            log_ok "Push concluído"
        else
            log_info "Commit realizado (sem push)"
        fi
    fi
fi

log_ok "Sincronização concluída!"
exit 0
