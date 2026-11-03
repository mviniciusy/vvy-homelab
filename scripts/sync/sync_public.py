#!/usr/bin/env python3
"""
============================================
sync_public.py — Sincroniza repo privado -> repo publico com sanitizacao
============================================
Uso: python sync_public.py [--dry-run] [--commit-msg "mensagem"] [--no-push]

--dry-run     : Mostra o que seria feito sem executar
--commit-msg  : Mensagem customizada para o commit
--no-push     : Faz commit mas nao faz push

O script le o sanitization-map.conf do repo privado, copia os arquivos
do privado para o publico, substitui dados reais por placeholders nos
arquivos de texto, e gera a versao sanitizada do sanitization-map.conf
para o repo publico.

Apos o sync, executa verificacao automatica de vazamentos (leak check)
procurando por IPs, credenciais e tokens que nao foram sanitizados.
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

# Arquivos que existem no privado mas NAO devem ser publicados (caminho relativo a raiz do repo).
# O .gitignore do privado nao impede a copia; este filtro impede.
PRIVATE_ONLY_PATHS = {"docs/samba.md"}

ITEMS_TO_COPY: List[str] = [
    "docs",
    "oracle",
    "timelog",
    "scripts",
    "README.md",
    "LICENSE",
]

# Extensoes de arquivo que sao sanitizadas (nao so .md)
SANITIZE_EXTENSIONS = {".md", ".conf", ".sh", ".yaml", ".yml", ".ps1"}

# Cabecalho do sanitization-map.conf publico
PUBLIC_MAP_HEADER = """\
# ============================================
# Referencia de Placeholders da Documentacao
# ============================================
# Este arquivo lista os placeholders utilizados
# na documentacao publica. Os valores reais sao
# mantidos apenas no repositorio privado.
# ============================================
"""

# ANSI color codes
_RED = "\033[0;31m"
_GREEN = "\033[0;32m"
_YELLOW = "\033[1;33m"
_BLUE = "\033[0;34m"
_NC = "\033[0m"


# ---------------------------------------------------------------------------
# Logging colorado
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
        description="Sincroniza repo privado -> repo publico com sanitizacao"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Mostra o que seria feito sem executar",
    )
    parser.add_argument(
        "--commit-msg",
        default="sync: atualizacao do repo publico",
        help="Mensagem customizada para o commit",
    )
    parser.add_argument(
        "--no-push",
        action="store_true",
        help="Faz commit mas nao faz push",
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Validacoes
# ---------------------------------------------------------------------------

def validate_environment(priv_dir: Path, pub_dir: Path, map_file: Path) -> None:
    if not priv_dir.is_dir():
        log_err(f"Diretorio privado nao encontrado: {priv_dir}")
        sys.exit(1)
    if not pub_dir.is_dir():
        log_err(f"Diretorio publico nao encontrado: {pub_dir}")
        sys.exit(1)
    if not map_file.is_file():
        log_err(f"Arquivo de mapeamento nao encontrado: {map_file}")
        sys.exit(1)
    if not (pub_dir / ".git").is_dir():
        log_err(f"Repo publico nao e um repositorio git: {pub_dir}")
        sys.exit(1)


# ---------------------------------------------------------------------------
# 1. Leitura e ordenacao do mapa de sanitizacao
# ---------------------------------------------------------------------------

def read_sanitization_map(map_file: Path) -> List[Tuple[str, str]]:
    """Le o arquivo de mapeamento e retorna lista de (valor_real, placeholder)."""
    rules: List[Tuple[str, str]] = []
    seen_placeholders: dict = {}  # placeholder -> valor_real (para detectar duplicatas)
    seen_real_vals: set = set()

    for line in map_file.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        # Remover espacos ao redor do =
        normalized = re.sub(r"\s*=\s*", "=", stripped, count=1)
        if "=" not in normalized:
            log_warn(f"Linha ignorada (formato invalido): {line}")
            continue
        real_val, placeholder = normalized.split("=", 1)
        if not real_val or not placeholder:
            log_warn(f"Linha ignorada (formato invalido): {line}")
            continue

        # Validar duplicatas
        if placeholder in seen_placeholders:
            existing = seen_placeholders[placeholder]
            if existing != real_val:
                log_warn(f"Placeholder duplicado: {placeholder} mapeia para '{existing}' e '{real_val}'")
        if real_val in seen_real_vals:
            log_warn(f"Valor real duplicado no mapa: {real_val}")
        seen_placeholders[placeholder] = real_val
        seen_real_vals.add(real_val)

        rules.append((real_val, placeholder))
    return rules


def sort_rules_by_length(rules: List[Tuple[str, str]]) -> List[Tuple[str, str]]:
    """Ordena regras por tamanho decrescente do valor real (evita substituicoes parciais)."""
    return sorted(rules, key=lambda r: len(r[0]), reverse=True)


# ---------------------------------------------------------------------------
# 2. Copia seletiva de arquivos
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
    log_info("Copiando arquivos do privado para o publico...")
    for item in items_to_copy:
        if should_skip(item, skip_items):
            if dry_run:
                log_dry(f"Pulando (nao copiado): {item}")
            continue
        src = priv_dir / item
        dst = pub_dir / item
        if not src.exists():
            log_warn(f"Nao encontrado no privado: {src}")
            continue
        if dry_run:
            log_dry(f"Copiaria: {src} -> {dst}")
        else:
            if src.is_dir():
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(
                    src, dst,
                    ignore=lambda d, names: [
                        n for n in names
                        if str((Path(d) / n).relative_to(priv_dir)) in PRIVATE_ONLY_PATHS
                    ],
                )
            else:
                shutil.copy2(src, dst)
            log_ok(f"Copiado: {item}")


# ---------------------------------------------------------------------------
# 3. Geracao do sanitization-map.conf publico
# ---------------------------------------------------------------------------

def placeholder_to_description(placeholder: str) -> str:
    """Gera descricao automatica a partir do nome do placeholder.
    Ex: <NEXTCLOUD_IP> -> 'Nextcloud Ip'
    """
    name = placeholder.strip("<>")
    words = name.replace("_", " ").split()
    return " ".join(w.capitalize() for w in words)


def generate_public_map(map_file: Path, pub_dir: Path, dry_run: bool) -> None:
    log_info("Gerando sanitization-map.conf sanitizado para o publico...")
    if dry_run:
        log_dry(f"Geraria versao sanitizada em: {pub_dir / 'sanitization-map.conf'}")
        return

    output_path = pub_dir / "sanitization-map.conf"
    lines: List[str] = [PUBLIC_MAP_HEADER]

    current_section: str = ""
    for line in map_file.read_text(encoding="utf-8").splitlines():
        # Detectar secoes (linhas de comentario com ---)
        section_match = re.match(r"^\s*#\s*---", line)
        if section_match:
            if line != current_section:
                current_section = line
                lines.append("")
                lines.append(line)
            continue

        # Ignorar linhas vazias e comentarios gerais
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
# 4. Sanitizacao dos arquivos de texto
# ---------------------------------------------------------------------------

def escape_regex(value: str) -> str:
    r"""Escapa caracteres especiais de regex para uso em re.sub()."""
    return re.escape(value)


def sanitize_text_files(
    pub_dir: Path,
    sorted_rules: List[Tuple[str, str]],
    dry_run: bool,
) -> None:
    """Sanitiza TODOS os arquivos de texto relevantes (.md, .conf, .sh, .yaml, .yml)."""
    log_info("Aplicando sanitizacao nos arquivos do repo publico...")
    if dry_run:
        log_dry(f"Aplicaria substituicoes nos arquivos ({', '.join(SANITIZE_EXTENSIONS)})")
        return

    files_to_sanitize: List[Path] = []
    for ext in SANITIZE_EXTENSIONS:
        files_to_sanitize.extend(sorted(pub_dir.glob(f"**/*{ext}")))

    for f in files_to_sanitize:
        if not f.is_file():
            continue
        content = f.read_text(encoding="utf-8")
        original_content = content
        for real_val, placeholder in sorted_rules:
            pattern = escape_regex(real_val)
            # Substituicao case-insensitive para emails (contem @)
            if "@" in real_val:
                content = re.sub(pattern, placeholder, content, flags=re.IGNORECASE)
            else:
                content = re.sub(pattern, placeholder, content)
        if content != original_content:
            f.write_text(content, encoding="utf-8")
            log_ok(f"Sanitizado: {f.name}")


# ---------------------------------------------------------------------------
# 5. Verificacao de vazamentos (leak check) — pos-sync
# ---------------------------------------------------------------------------

# Padroes de credenciais/secret para detectar vazamentos pos-sanitizacao
# IPs que NAO sao sensíveis — ignorar no leak check
IP_WHITELIST = {
    "127.0.0.1",    # localhost
    "0.0.0.0",      # bind all
    "8.8.8.8",      # Google DNS
    "8.8.4.4",      # Google DNS
    "1.1.1.1",      # Cloudflare DNS
    "1.0.0.1",      # Cloudflare DNS
    "9.9.9.9",      # Quad9 DNS
    "192.168.1.0",  # CIDR base
    "192.168.1.1",  # roteador/gateway
    "192.168.1.255",# broadcast
    "10.0.0.0",     # CIDR base Oracle
    "10.0.0.1",     # gateway Oracle
    "127.0.0.53",   # systemd-resolved
}

LEAK_PATTERNS = [
    # IPs que nao foram substituidos (nao envolvidos por <...>)
    (r"\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b(?![^<]*>)", "IP address nao sanitizado"),
    # Private keys
    (r"-----BEGIN\s+(RSA|EC|OPENSSH|PGP)\s+PRIVATE\s+KEY-----", "Private key"),
    # JWT tokens
    (r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}", "JWT token"),
    # AWS keys
    (r"AKIA[0-9A-Z]{16}", "AWS Access Key"),
    # SSH fingerprints
    (r"SHA256:[A-Za-z0-9+/]{43,}", "SSH fingerprint"),
]


def check_leaks(pub_dir: Path, dry_run: bool = False) -> List[Tuple[str, str]]:
    """Verifica arquivos do repo publico por credenciais/IPs nao sanitizados.
    Retorna lista de (arquivo, descricao_do_leak)."""
    leaks: List[Tuple[str, str]] = []

    files_to_check: List[Path] = []
    for ext in SANITIZE_EXTENSIONS:
        files_to_check.extend(sorted(pub_dir.glob(f"**/*{ext}")))

    for f in files_to_check:
        if not f.is_file():
            continue
        content = f.read_text(encoding="utf-8")
        for pattern, desc in LEAK_PATTERNS:
            matches = re.finditer(pattern, content)
            for m in matches:
                matched_val = m.group(1) if m.lastindex else m.group()
                # Ignorar IPs da whitelist
                if "IP address" in desc and matched_val in IP_WHITELIST:
                    continue
                # Ignar se ja esta dentro de um placeholder <...>
                start = max(0, m.start() - 30)
                context = content[start:m.end() + 5]
                if ">" in context[m.start() - start:]:
                    continue
                rel_path = str(f.relative_to(pub_dir))
                leaks.append((rel_path, f"{desc}: {matched_val[:50]}"))

    return leaks


def run_leak_check(pub_dir: Path, dry_run: bool, did_push: bool) -> None:
    """Executa verificacao de vazamentos apos o sync. Se encontrar leaks reais,
    alerta e instrui sobre remedio."""
    log_info("Verificando vazamentos de credenciais no repo publico...")

    if dry_run:
        log_dry("Verificacao de vazamentos seria executada aqui")
        return

    leaks = check_leaks(pub_dir)

    # Filtrar falsos positivos: remover entradas que contenham <...> placeholders
    real_leaks = [(f, d) for f, d in leaks if "<" not in d and ">" not in d]

    if not real_leaks:
        log_ok("Nenhum vazamento detectado — repo publico esta limpo")
        return

    log_err(f"ATENCAO: {len(real_leaks)} possivel(is) vazamento(s) detectado(s)!")
    for filepath, desc in real_leaks:
        log_err(f"  {filepath}: {desc}")

    if did_push:
        log_warn("O commit ja foi enviado para o GitHub publico.")
        log_warn("REMEDIO:")
        log_warn("  1. Adicionar o valor real ao sanitization-map.conf")
        log_warn("  2. Re-executar: python3 /root/scripts/sync_public.py --commit-msg 'fix: sanitiza vazamento'")
        log_warn("  3. Se a credencial e sensivel (senha, token), considera-la comprometida e rotaciona-la")
        log_warn("  4. Para remover do historico: git reset --soft HEAD~1 no repo publico + re-sync + force push")
    else:
        log_warn("Commit realizado sem push. Corrigir antes de pushar:")
        log_warn("  1. Adicionar o valor real ao sanitization-map.conf")
        log_warn("  2. Re-executar sync_public.py")


# ---------------------------------------------------------------------------
# 6. Git add, commit e push
# ---------------------------------------------------------------------------

def git_operations(
    pub_dir: Path,
    commit_msg: str,
    no_push: bool,
    dry_run: bool,
) -> bool:
    """Executa git add, commit e push. Retorna True se fez push."""
    log_info("Preparando commit no repo publico...")

    if dry_run:
        log_dry(f"Executaria: cd {pub_dir} && git add . && git commit -m \"{commit_msg}\"")
        if not no_push:
            log_dry("Executaria: git push origin main")
        return False

    # git add .
    subprocess.run(["git", "add", "."], cwd=pub_dir, check=True)

    # Verificar se ha alteracoes staged
    result = subprocess.run(
        ["git", "diff", "--staged", "--quiet"],
        cwd=pub_dir,
        capture_output=True,
    )
    if result.returncode == 0:
        log_info("Nenhuma alteracao detectada")
        return False
    else:
        subprocess.run(
            ["git", "commit", "-m", commit_msg],
            cwd=pub_dir,
            check=True,
        )
        if not no_push:
            log_info("Fazendo push para o repo publico...")
            subprocess.run(
                ["git", "push", "origin", "main"],
                cwd=pub_dir,
                check=True,
            )
            log_ok("Push concluido")
            return True
        else:
            log_info("Commit realizado (sem push)")
            return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    args = parse_args()
    dry_run: bool = args.dry_run
    commit_msg: str = args.commit_msg
    no_push: bool = args.no_push

    validate_environment(PRIV_DIR, PUB_DIR, MAP_FILE)

    # 1. Ler e ordenar regras de sanitizacao
    log_info(f"Lendo mapa de sanitizacao: {MAP_FILE}")
    rules = read_sanitization_map(MAP_FILE)
    sorted_rules = sort_rules_by_length(rules)
    log_ok(f"Carregadas {len(sorted_rules)} regras de sanitizacao")

    if dry_run:
        log_dry("Regras de sanitizacao (ordenadas por tamanho decrescente):")
        for real_val, placeholder in sorted_rules:
            log_dry(f"  {real_val} -> {placeholder}")

    # 2. Copiar arquivos do privado para o publico
    copy_items(PRIV_DIR, PUB_DIR, ITEMS_TO_COPY, SKIP_ITEMS, dry_run)

    # 3. Gerar sanitization-map.conf sanitizado para o publico
    generate_public_map(MAP_FILE, PUB_DIR, dry_run)

    # 4. Sanitizar arquivos de texto do repo publico
    sanitize_text_files(PUB_DIR, sorted_rules, dry_run)

    # 5. Git add, commit e push
    did_push = git_operations(PUB_DIR, commit_msg, no_push, dry_run)

    # 6. Verificacao de vazamentos pos-sync
    run_leak_check(PUB_DIR, dry_run, did_push)

    log_ok("Sincronizacao concluida!")


if __name__ == "__main__":
    main()
