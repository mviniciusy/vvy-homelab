#!/usr/bin/env bash
# rclone_keep.sh — mantém apenas os N backups mais recentes de uma pasta rclone remota.
# Uso: rclone_keep.sh <remote-dir> <keep>
#
# - Lista arquivos (depth 1, files only) via `rclone lsf`
# - Conta como "backup" apenas arquivos de backup (vzdump-*.tar.zst / *.vma.zst /
#   *.tar.gz) — arquivos .log NÃO ocupam slot de retenção
# - Ordena por nome: nomes gerados pelos backups têm timestamp embutido
#   (ex: vzdump-lxc-104-2026_08_17-02_45_03.tar.zst, etc-pve-2026-08-17.tar.gz),
#   então sort lexicográfico = ordem cronológica (mais antigo primeiro)
# - Mantém os K backups mais recentes; deleta backups mais antigos E logs
#   que ficaram sem o backup correspondente
#
# Exit: 0 = ok / nada a fazer | 1 = falha ao listar OU ao deletar
#
# Validado: 17/08/2026 (teste com rclone real contra pasta local /tmp — não toca o Drive)

set -euo pipefail

REMOTE_DIR="${1:?remote dir required}"
KEEP="${2:-3}"

if ! files=$(rclone lsf "$REMOTE_DIR" --max-depth 1 --files-only 2>/tmp/rclone_keep.err | sort); then
    echo "  rclone_keep: ERRO ao listar $REMOTE_DIR (nada deletado). Detalhe:"
    cat /tmp/rclone_keep.err 2>/dev/null | head -5 >&2 || true
    exit 1
fi

[ -z "$files" ] && { echo "  rclone_keep: pasta vazia, nada a fazer."; exit 0; }

# Lista em ordem cronológica (mais antigo → mais novo). Novos primeiro = tac.
newest_first=$(printf "%s\n" "$files" | grep -v '^$' | tac)

# Percorre do mais novo ao mais antigo; mantém os K primeiros arquivos de backup.
# Arquivos .log NÃO contam como backup — entram no descarte se o backup
# correspondente já tiver sido podado (ou se sobrarem depois dos K backups).
keep_pending="$KEEP"
to_delete=""
kept_backups=""

while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
        *.log)
            # log: só sobrevive se o backup correspondente foi mantido
            base="${f%.log}"
            if printf "%s\n" "$kept_backups" | grep -qx "$base"; then
                true   # mantém (backup correspondente está entre os K)
            else
                to_delete="${to_delete}${f}"$'\n'
            fi
            ;;
        *)
            # arquivo de backup
            if [ "$keep_pending" -gt 0 ]; then
                keep_pending=$((keep_pending - 1))
                base="${f%.tar.zst}"; base="${base%.vma.zst}"; base="${base%.tar.gz}"
                kept_backups="${kept_backups}${base}"$'\n'
            else
                to_delete="${to_delete}${f}"$'\n'
            fi
            ;;
    esac
done <<< "$newest_first"

to_delete=$(printf "%s" "$to_delete" | grep -v '^$' || true)

if [ -z "$to_delete" ]; then
    echo "  rclone_keep: ${KEEP} (ou menos) backup(s), nada a deletar."
    exit 0
fi

n_del=$(printf "%s\n" "$to_delete" | grep -c . || true)
echo "  rclone_keep: deletando $n_del arquivo(s) antigo(s) em $REMOTE_DIR (keep=$KEEP)"
fail=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    if rclone deletefile "$REMOTE_DIR$f"; then
        echo "    remoto deletado: $f"
    else
        echo "    ERRO ao deletar: $f" >&2
        fail=1
    fi
done <<< "$to_delete"

exit $fail