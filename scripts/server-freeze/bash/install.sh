#!/bin/bash
# ============================================================================
# install.sh - Instalação e configuração do monitoramento de travamento
#
# Este script instala o watchdog de monitoramento, configura a persistência
# de logs, habilita SysRq para emergências, e aplica mitigações imediatas.
#
# Uso:
#   sudo bash install.sh              # instalação completa
#   sudo bash install.sh --swap-only  # apenas configura swap
#   sudo bash install.sh --watchdog-only  # apenas instala watchdog
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWAP_SIZE="2G"
SWAP_FILE="/swapfile"
SWAPPINESS=10

# ---------------------------------------------------------------------------
# Funções auxiliares
# ---------------------------------------------------------------------------

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "Este script deve ser executado como root (sudo)."
        exit 1
    fi
}

detect_distro() {
    if [ -f /etc/pve/local/pve-ssl.pem ] || [ -f /etc/proxmox-ve ]; then
        echo "proxmox"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

is_proxmox() {
    [ -f /etc/pve/local/pve-ssl.pem ] || [ -f /etc/proxmox-ve ] || grep -q "proxmox" /etc/os-release 2>/dev/null
}

# ---------------------------------------------------------------------------
# Instalação do Watchdog
# ---------------------------------------------------------------------------

install_watchdog() {
    info "Instalando script de monitoramento watchdog..."

    # Copiar script
    cp "${SCRIPT_DIR}/server-watchdog.sh" /usr/local/bin/server-watchdog.sh
    chmod +x /usr/local/bin/server-watchdog.sh

    # Criar diretório de logs
    mkdir -p /var/log/watchdog

    # Configurar cron (a cada 1 minuto)
    CRON_LINE="* * * * * /usr/local/bin/server-watchdog.sh"
    if crontab -l 2>/dev/null | grep -q "server-watchdog"; then
        warn "Cron do watchdog já existe, pulando..."
    else
        (crontab -l 2>/dev/null; echo "${CRON_LINE}") | crontab -
        ok "Cron do watchdog configurado (a cada 1 minuto)"
    fi

    # Testar execução
    /usr/local/bin/server-watchdog.sh
    if [ -f /var/log/watchdog/server-state.log ]; then
        ok "Watchdog executado com sucesso. Log em /var/log/watchdog/server-state.log"
    else
        error "Falha ao executar watchdog. Verifique permissões."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Configurar Swap
# ---------------------------------------------------------------------------

configure_swap() {
    info "Verificando configuração de swap..."

    # Verificar se já tem swap
    if swapon --show 2>/dev/null | grep -q .; then
        current_swap=$(swapon --show --noheadings | awk '{sum+=$3} END {printf "%.0fM", sum/1024}')
        ok "Swap já configurado: ${current_swap}"
        return 0
    fi

    warn "Nenhum swap encontrado! Configurando swap de ${SWAP_SIZE}..."

    # Verificar se há espaço em disco suficiente
    available=$(df / | awk 'NR==2 {print $4}')
    available_mb=$((available / 1024))
    if [ "${available_mb}" -lt 2500 ]; then
        error "Espaço em disco insuficiente para criar swap de ${SWAP_SIZE}. Disponível: ${available_mb}MB"
        return 1
    fi

    # Criar arquivo de swap
    fallocate -l "${SWAP_SIZE}" "${SWAP_FILE}" 2>/dev/null || dd if=/dev/zero of="${SWAP_FILE}" bs=1M count=2048 status=progress
    chmod 600 "${SWAP_FILE}"
    mkswap "${SWAP_FILE}"
    swapon "${SWAP_FILE}"

    # Adicionar ao fstab se não existir
    if ! grep -q "${SWAP_FILE}" /etc/fstab; then
        echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
        ok "Swap adicionado ao /etc/fstab"
    fi

    # Configurar swappiness
    sysctl vm.swappiness="${SWAPPINESS}" 2>/dev/null || true
    if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
        echo "vm.swappiness=${SWAPPINESS}" >> /etc/sysctl.conf
    else
        sed -i "s/vm.swappiness=.*/vm.swappiness=${SWAPPINESS}/" /etc/sysctl.conf
    fi

    ok "Swap de ${SWAP_SIZE} configurado com sucesso!"
    swapon --show
}

# ---------------------------------------------------------------------------
# Configurar persistência de logs
# ---------------------------------------------------------------------------

configure_log_persistence() {
    info "Configurando persistência de logs..."

    DISTRO=$(detect_distro)

    # --- rsyslog: garantir kern.log persistente ---
    if command -v rsyslogd &>/dev/null || [ -f /etc/rsyslog.conf ]; then
        if ! grep -q "kern\.\*" /etc/rsyslog.conf 2>/dev/null; then
            echo "kern.*                          /var/log/kern.log" >> /etc/rsyslog.conf
            ok "kern.log configurado no rsyslog"
        else
            ok "kern.log já configurado no rsyslog"
        fi

        # Reiniciar rsyslog se estiver rodando
        if systemctl is-active --quiet rsyslog 2>/dev/null; then
            systemctl restart rsyslog
            ok "rsyslog reiniciado"
        fi
    else
        warn "rsyslog não encontrado. Instalando..."
        if [ "${DISTRO}" = "debian" ] || [ "${DISTRO}" = "proxmox" ]; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" rsyslog
        elif [ "${DISTRO}" = "rhel" ]; then
            yum install -y rsyslog
        fi
        systemctl enable rsyslog
        systemctl start rsyslog
        ok "rsyslog instalado e iniciado"
    fi

    # --- journald: configurar modo persistente ---
    if [ -f /etc/systemd/journald.conf ]; then
        # Backup
        cp /etc/systemd/journald.conf /etc/systemd/journald.conf.bak.$(date +%Y%m%d%H%M%S)

        # Configurar Storage=persistent se não estiver
        if grep -q "^#Storage=" /etc/systemd/journald.conf || ! grep -q "^Storage=" /etc/systemd/journald.conf; then
            sed -i 's/^#Storage=.*/Storage=persistent/' /etc/systemd/journald.conf
        fi

        # Criar diretório de logs persistentes
        mkdir -p /var/log/journal
        systemd-tmpfiles --create --prefix /var/log/journal 2>/dev/null || true

        # Reiniciar journald
        systemctl restart systemd-journald
        ok "journald configurado para modo persistente"
    else
        warn "journald.conf não encontrado, pulando configuração do journal"
    fi
}

# ---------------------------------------------------------------------------
# Configurar SysRq para emergências
# ---------------------------------------------------------------------------

configure_sysrq() {
    info "Configurando Magic SysRq para emergências..."

    # Habilitar SysRq
    echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || warn "Não foi possível habilitar SysRq via /proc"

    # Persistir via sysctl.conf
    if ! grep -q "kernel.sysrq" /etc/sysctl.conf; then
        echo "kernel.sysrq = 1" >> /etc/sysctl.conf
        ok "SysRq habilitado via sysctl.conf"
    else
        sed -i 's/kernel.sysrq.*/kernel.sysrq = 1/' /etc/sysctl.conf
        ok "SysRq atualizado via sysctl.conf"
    fi

    info "Comandos SysRq de emergência (via console/IPMI se servidor travar):"
    info "  Alt+SysRq+t  -> dump de tarefas (mostra o que está travado)"
    info "  Alt+SysRq+m  -> dump de memória"
    info "  Alt+SysRq+e  -> SIGTERM para todos os processos"
    info "  Alt+SysRq+i  -> SIGKILL para todos os processos"
    info "  Alt+SysRq+s  -> sync discos"
    info "  Alt+SysRq+u  -> remontar discos como read-only"
    info "  Alt+SysRq+b  -> reboot seguro"
}

# ---------------------------------------------------------------------------
# Instalar watchdog de hardware (se disponível)
# ---------------------------------------------------------------------------

install_hw_watchdog() {
    info "Verificando watchdog de hardware..."

    if [ ! -e /dev/watchdog ]; then
        warn "Nenhum watchdog de hardware detectado (/dev/watchdog não existe)"
        info "Se este for um VPS, o watchdog de hardware pode não estar disponível."
        info "O script de monitoramento via cron servirá como alternativa."
        return 0
    fi

    ok "Watchdog de hardware detectado: /dev/watchdog"

    # No Proxmox, o pacote 'watchdog' do apt tenta remover proxmox-ve.
    # Pular a instalação do pacote e configurar o watchdog via systemd embutido.
    if is_proxmox; then
        warn "Proxmox VE detectado - pulando instalação do pacote 'watchdog' (conflita com proxmox-ve)"
        info "Configurando watchdog via systemd embutido..."

        # Criar serviço systemd para o watchdog de hardware
        cat > /etc/systemd/system/hw-watchdog.service <<'EOF'
[Unit]
Description=Hardware Watchdog Daemon
After=systemd-modules-load.service

[Service]
Type=notify
ExecStart=/usr/bin/systemd-watchdogd
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        # Alternativa: usar o watchdog embutido do kernel via systemd
        # Configurar no /etc/systemd/system.conf
        if grep -q "^#RuntimeWatchdogSec=" /etc/systemd/system.conf; then
            sed -i 's/^#RuntimeWatchdogSec=.*/RuntimeWatchdogSec=30/' /etc/systemd/system.conf
            sed -i 's/^#RebootWatchdogSec=.*/RebootWatchdogSec=120/' /etc/systemd/system.conf
            ok "Watchdog systemd configurado (RuntimeWatchdogSec=30, RebootWatchdogSec=120)"
        elif ! grep -q "^RuntimeWatchdogSec=" /etc/systemd/system.conf; then
            echo "RuntimeWatchdogSec=30" >> /etc/systemd/system.conf
            echo "RebootWatchdogSec=120" >> /etc/systemd/system.conf
            ok "Watchdog systemd configurado (RuntimeWatchdogSec=30, RebootWatchdogSec=120)"
        else
            ok "Watchdog systemd já configurado"
        fi

        # Recarregar systemd
        systemctl daemon-reload
        ok "Watchdog de hardware configurado via systemd (sem pacote adicional)"
        return 0
    fi

    DISTRO=$(detect_distro)
    if [ "${DISTRO}" = "debian" ]; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" watchdog
    elif [ "${DISTRO}" = "rhel" ]; then
        yum install -y watchdog
    else
        warn "Distro desconhecida. Instale o pacote 'watchdog' manualmente."
        return 0
    fi

    # Configurar watchdog.conf
    WD_CONF="/etc/watchdog.conf"
    if [ -f "${WD_CONF}" ]; then
        cp "${WD_CONF}" "${WD_CONF}.bak.$(date +%Y%m%d%H%M%S)"

        # Descomentar linhas necessárias
        sed -i 's/^#watchdog-device/watchdog-device/' "${WD_CONF}"
        sed -i 's/^#interval/interval/' "${WD_CONF}"
        sed -i 's/^#max-load-1/max-load-1/' "${WD_CONF}"
        sed -i 's/^#min-memory/min-memory/' "${WD_CONF}"

        # Garantir valores seguros
        grep -q "^max-load-1" "${WD_CONF}" || echo "max-load-1 = 24" >> "${WD_CONF}"
        grep -q "^min-memory" "${WD_CONF}" || echo "min-memory = 1" >> "${WD_CONF}"
    fi

    systemctl enable watchdog
    systemctl start watchdog
    ok "Watchdog de hardware instalado e ativo"
}

# ---------------------------------------------------------------------------
# Instalar ferramentas de diagnóstico
# ---------------------------------------------------------------------------

install_diagnostic_tools() {
    info "Instalando ferramentas de diagnóstico..."

    DISTRO=$(detect_distro)

    TOOLS=""
    for tool in iostat smartctl memtester; do
        if ! command -v "${tool}" &>/dev/null; then
            case "${tool}" in
                iostat) TOOLS="${TOOLS} sysstat" ;;
                smartctl) TOOLS="${TOOLS} smartmontools" ;;
                memtester) TOOLS="${TOOLS} memtester" ;;
            esac
        fi
    done

    if [ -n "${TOOLS}" ]; then
        if [ "${DISTRO}" = "debian" ] || [ "${DISTRO}" = "proxmox" ]; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" ${TOOLS}
        elif [ "${DISTRO}" = "rhel" ]; then
            yum install -y ${TOOLS}
        else
            warn "Distro desconhecida. Instale manualmente: ${TOOLS}"
            return 0
        fi
        ok "Ferramentas instaladas: ${TOOLS}"
    else
        ok "Todas as ferramentas de diagnóstico já estão instaladas"
    fi
}

# ---------------------------------------------------------------------------
# Copiar script de diagnóstico pós-reboot
# ---------------------------------------------------------------------------

install_post_reboot() {
	info "Instalando script de diagnóstico pós-reboot..."

	cp "${SCRIPT_DIR}/post-reboot-diagnosis.sh" /usr/local/bin/post-reboot-diagnosis.sh
	chmod +x /usr/local/bin/post-reboot-diagnosis.sh

	ok "Script de diagnóstico instalado em /usr/local/bin/post-reboot-diagnosis.sh"
	info "Após o próximo travamento, execute: sudo /usr/local/bin/post-reboot-diagnosis.sh"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
	check_root

	echo ""
	echo "============================================================"
	echo " INSTALAÇÃO DO MONITORAMENTO DE TRAVAMENTO DO SERVIDOR"
	echo "============================================================"
	echo ""

	case "${1:-all}" in
	--swap-only)
		configure_swap
		;;
	--watchdog-only)
		install_watchdog
		;;
	all)
		install_watchdog
		echo ""
		configure_swap
		echo ""
		configure_log_persistence
		echo ""
		configure_sysrq
		echo ""
		install_hw_watchdog
		echo ""
		install_diagnostic_tools
		echo ""
		install_post_reboot
		echo ""
		;;
	*)
		echo "Uso: $0 [--swap-only|--watchdog-only|all]"
		exit 1
		;;
	esac

	echo ""
	echo "============================================================"
	echo -e " ${GREEN}INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
	echo "============================================================"
	echo ""
	echo "Próximos passos:"
	echo " 1. O watchdog está registrando o estado a cada 1 minuto"
	echo " 2. Se o servidor travar novamente, após o reboot execute:"
	echo "    sudo /usr/local/bin/post-reboot-diagnosis.sh"
	echo " 3. Os logs do watchdog estarão em /var/log/watchdog/"
	echo " 4. Os logs de kernel estarão em /var/log/kern.log"
	echo " 5. Instale também o heartbeat-watchdog para reboot automático:"
	echo "    sudo bash /usr/local/bin/heartbeat-watchdog.sh --install"
	echo ""
}

main "$@"
