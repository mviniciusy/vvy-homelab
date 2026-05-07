#!/usr/bin/env python3
"""
============================================
sync_public.py — Sincroniza repo privado → repo público com sanitização
============================================
Uso: python sync_public.py [--dry-run] [--commit-msg "mensagem"] [--no-push]

--dry-run     : Mostra o que seria feito sem executar
--commit-msg  : Mensagem customizada para o commit
--no-push     : Faz commit mas não faz push

O script lê o sanitization-map.conf do repo privado, copia os arquivos
do privado para o público, substitui dados reais por placeholders nos .md,
e gera a versão sanitizada do sanitization-map.conf para o repo público.
============================================
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple


# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

PRIV_DIR = Path("/root/1 Documentação Privada")
PUB_DIR = Path("/root/1 Documentação GITHUB")
MAP_FILE = PRIV_DIR / "sanitization-map.conf"

SKIP_ITEMS: List[str] = [
    "PROXMOX_VVY.md",
    ".gitignore",
    ".git",
]

ITEMS_TO_COPY: List[str] = [
    "docs",
    "scripts",
    "README.md",
    "LICENSE",
]

# Cabeçalho do sanitization-map.conf público
PUBLIC_MAP_HEADER = """\
# ============================================
# Referência de Placeholders da Documentação
# ============================================
# Este arquivo lista os placeholders utilizados
# na documentação pública. Os valores reais são
# mantidos apenas no repositório privado.
# ============================================
"""

# ANSI color codes
_RED = "\033[0;31m"
_GREEN = "\033[0;32m"
_YELLOW = "\033[1;33m"
_BLUE = "\033[0;34m"
_NC = "\033[0m"


# ---------------------------------------------------------------------------
# Logging colorido
# ---------------------------------------------------------------------------

def log_info(msg: str) -> None:
    print(f"{_BLUE}[INFO]{_NC} {msg}")


def log_warn(msg: str) -> None:
    print(f"{_YELLOW}[WARN]{_NC} {msg}")


def log_dry(msg: str) -> None:
    print(f"{_YELLOW}[DRY]{_NC} {msg}")


def log_ok(msg: str) -> None:
    print(f"{_GREEN}[OK]{_NC} {msg}")


def log_err(msg: str) -> None:
    print(f"{_RED}[ERRO]{_NC} {msg}")


# ---------------------------------------------------------------------------
# Argumentos de linha de comando
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sincroniza repo privado → repo público com sanitização"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Mostra o que seria feito sem executar",
    )
    parser.add_argument(
        "--commit-msg",
        default="sync: atualização do repo público",
        help="Mensagem customizada para o commit",
    )
    parser.add_argument(
        "--no-push",
        action="store_true",
        help="Faz commit mas não faz push",
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Validações
# ---------------------------------------------------------------------------

def validate_environment(priv_dir: Path, pub_dir: Path, map_file: Path) -> None:
    if not priv_dir.is_dir():
        log_err(f"Diretório privado não encontrado: {priv_dir}")
        sys.exit(1)
    if not pub_dir.is_dir():
        log_err(f"Diretório público não encontrado: {pub_dir}")
        sys.exit(1)
    if not map_file.is_file():
        log_err(f"Arquivo de mapeamento não encontrado: {map_file}")
        sys.exit(1)
    if not (pub_dir / ".git").is_dir():
        log_err(f"Repo público não é um repositório git: {pub_dir}")
        sys.exit(1)


# ---------------------------------------------------------------------------
# 1. Leitura e ordenação do mapa de sanitização
# ---------------------------------------------------------------------------

def read_sanitization_map(map_file: Path) -> List[Tuple[str, str]]:
    """Lê o arquivo de mapeamento e retorna lista de (valor_real, placeholder)."""
    rules: List[Tuple[str, str]] = []
    for line in map_file.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # Remover espaços ao redor do =
        normalized = re.sub(r"\s*=\s*", "=", stripped, count=1)
        if "=" not in normalized:
            log_warn(f"Linha ignorada (formato inválido): {line}")
            continue
        real_val, placeholder = normalized.split("=", 1)
        if not real_val or not placeholder:
            log_warn(f"Linha ignorada (formato inválido): {line}")
            continue
        rules.append((real_val, placeholder))
    return rules


def sort_rules_by_length(rules: List[Tuple[str, str]]) -> List[Tuple[str, str]]:
    """Ordena regras por tamanho decrescente do valor real (evita substituições parciais)."""
    return sorted(rules, key=lambda r: len(r[0]), reverse=True)


# ---------------------------------------------------------------------------
# 2. Cópia seletiva de arquivos
# ---------------------------------------------------------------------------

def should_skip(item: str, skip_items: List[str]) -> bool:
    return item in skip_items


def copy_items(
    priv_dir: Path,
    pub_dir: Path,
    items_to_copy: List[str],
    skip_items: List[str],
    dry_run: bool,
) -> None:
    log_info("Copiando arquivos do privado para o público...")
    for item in items_to_copy:
        if should_skip(item, skip_items):
            if dry_run:
                log_dry(f"Pulando (não copiado): {item}")
            continue
        src = priv_dir / item
        dst = pub_dir / item
        if not src.exists():
            log_warn(f"Não encontrado no privado: {src}")
            continue
        if dry_run:
            log_dry(f"Copiaria: {src} → {dst}")
        else:
            if src.is_dir():
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(src, dst)
            else:
                shutil.copy2(src, dst)
            log_ok(f"Copiado: {item}")


# ---------------------------------------------------------------------------
# 3. Geração do sanitization-map.conf público
# ---------------------------------------------------------------------------

def placeholder_to_description(placeholder: str) -> str:
    """Gera descrição automática a partir do nome do placeholder.
    Ex: <NEXTCLOUD_IP> → 'Nextcloud Ip'
    """
    name = placeholder.strip("<>")
    words = name.replace("_", " ").split()
    return " ".join(w.capitalize() for w in words)


def generate_public_map(map_file: Path, pub_dir: Path, dry_run: bool) -> None:
    log_info("Gerando sanitization-map.conf sanitizado para o público...")
    if dry_run:
        log_dry(f"Geraria versão sanitizada em: {pub_dir / 'sanitization-map.conf'}")
        return

    output_path = pub_dir / "sanitization-map.conf"
    lines: List[str] = [PUBLIC_MAP_HEADER]

    current_section: str = ""
    for line in map_file.read_text(encoding="utf-8").splitlines():
        # Detectar seções (linhas de comentário com ---)
        section_match = re.match(r"^\s*#\s*---", line)
        if section_match:
            if line != current_section:
                current_section = line
                lines.append("")
                lines.append(line)
            continue

        # Ignorar linhas vazias e comentários gerais
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        # Extrair placeholder (lado direito do =)
        normalized = re.sub(r"\s*=\s*", "=", stripped, count=1)
        if "=" not in normalized:
            continue
        real_val, placeholder = normalized.split("=", 1)
        if placeholder and real_val:
            desc = placeholder_to_description(placeholder)
            lines.append(f"{placeholder:<22} # {desc}")

    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    log_ok("sanitization-map.conf sanitizado gerado")


# ---------------------------------------------------------------------------
# 4. Sanitização dos arquivos .md
# ---------------------------------------------------------------------------

def escape_regex(value: str) -> str:
    r"""Escapa caracteres especiais de regex para uso em re.sub().

    Equivalente ao ``sed 's/[[\.*^$()+?{|\\]/\\&/g'`` do Bash.
    """
    return re.escape(value)


def sanitize_markdown_files(
    pub_dir: Path,
    sorted_rules: List[Tuple[str, str]],
    dry_run: bool,
) -> None:
    log_info("Aplicando sanitização nos arquivos .md do repo público...")
    if dry_run:
        log_dry("Aplicaria substituições nos arquivos .md do repo público")
        return

    docs_dir = pub_dir / "docs"
    if not docs_dir.is_dir():
        log_warn(f"Diretório docs não encontrado: {docs_dir}")
        return

    md_files = sorted(docs_dir.glob("*.md"))
    for md_file in md_files:
        if not md_file.is_file():
            continue
        content = md_file.read_text(encoding="utf-8")
        for real_val, placeholder in sorted_rules:
            pattern = escape_regex(real_val)
            content = re.sub(pattern, placeholder, content)
        md_file.write_text(content, encoding="utf-8")
        log_ok(f"Sanitizado: {md_file.name}")


# ---------------------------------------------------------------------------
# 5. Git add, commit e push
# ---------------------------------------------------------------------------

def git_operations(
    pub_dir: Path,
    commit_msg: str,
    no_push: bool,
    dry_run: bool,
) -> None:
    log_info("Preparando commit no repo público...")

    if dry_run:
        log_dry(f"Executaria: cd {pub_dir} && git add . && git commit -m \"{commit_msg}\"")
        if not no_push:
            log_dry("Executaria: git push origin main")
        return

    # git add .
    subprocess.run(["git", "add", "."], cwd=pub_dir, check=True)

    # Verificar se há alterações staged
    result = subprocess.run(
        ["git", "diff", "--staged", "--quiet"],
        cwd=pub_dir,
        capture_output=True,
    )
    if result.returncode == 0:
        log_info("Nenhuma alteração detectada")
    else:
        subprocess.run(
            ["git", "commit", "-m", commit_msg],
            cwd=pub_dir,
            check=True,
        )
        if not no_push:
            log_info("Fazendo push para o repo público...")
            subprocess.run(
                ["git", "push", "origin", "main"],
                cwd=pub_dir,
                check=True,
            )
            log_ok("Push concluído")
        else:
            log_info("Commit realizado (sem push)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    args = parse_args()
    dry_run: bool = args.dry_run
    commit_msg: str = args.commit_msg
    no_push: bool = args.no_push

    validate_environment(PRIV_DIR, PUB_DIR, MAP_FILE)

    # 1. Ler e ordenar regras de sanitização
    log_info(f"Lendo mapa de sanitização: {MAP_FILE}")
    rules = read_sanitization_map(MAP_FILE)
    sorted_rules = sort_rules_by_length(rules)
    log_ok(f"Carregadas {len(sorted_rules)} regras de sanitização")

    if dry_run:
        log_dry("Regras de sanitização (ordenadas por tamanho decrescente):")
        for real_val, placeholder in sorted_rules:
            log_dry(f"  {real_val} → {placeholder}")

    # 2. Copiar arquivos do privado para o público
    copy_items(PRIV_DIR, PUB_DIR, ITEMS_TO_COPY, SKIP_ITEMS, dry_run)

    # 3. Gerar sanitization-map.conf sanitizado para o público
    generate_public_map(MAP_FILE, PUB_DIR, dry_run)

    # 4. Sanitizar arquivos .md do repo público
    sanitize_markdown_files(PUB_DIR, sorted_rules, dry_run)

    # 5. Git add, commit e push
    git_operations(PUB_DIR, commit_msg, no_push, dry_run)

    log_ok("Sincronização concluída!")


if __name__ == "__main__":
    main()
