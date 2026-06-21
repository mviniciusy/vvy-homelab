#!/bin/bash
# ============================================================================
# heartbeat-watchdog.sh - Heartbeat de reboot automatico para travamentos
#
# FUNCIONAMENTO:
# - Roda como servico systemd continuo
# - A cada 10 segundos, escreve um "ping" no /dev/watchdog
# - Se este processo parar de pingar (sistema travou), o iTCO_wdt
#   reinicia a maquina automaticamente em 60 segundos
# - Com nowayout=1, mesmo que o processo morra, o watchdog NAO e desarmado
#
# DISPOSITIVO: /dev/watchdog (iTCO_wdt em hardware Intel)
# ============================================================================

HEARTBEAT_FILE="/tmp/heartbeat-watchdog"
LOG="/var/log/watchdog/heartbeat.log"

mkdir -p /var/log/watchdog

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG}" 2>/dev/null
}

# --- Modo de instalacao ---
if [ "${1:-}" = "--install" ]; then
    echo "Carregando iTCO_wdt..."
    modprobe iTCO_wdt nowayout=1 heartbeat=60 2>/dev/null || true

    echo "Criando /dev/watchdog..."
    rm -f /dev/watchdog
    mknod /dev/watchdog c 243 0 2>/dev/null
    chmod 600 /dev/watchdog

    echo "Instalando servico systemd..."
    cat > /etc/systemd/system/heartbeat-watchdog.service <<'SVCEOF'
[Unit]
Description=Heartbeat Watchdog - Keep system alive, reboot on freeze
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/heartbeat-watchdog.sh --daemon
Restart=always
RestartSec=3

# Alta prioridade - nao pode ser morto por OOM
OOMScoreAdjust=-1000
Nice=-5

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable heartbeat-watchdog.service
    systemctl start heartbeat-watchdog.service

    echo "Heartbeat watchdog instalado com iTCO_wdt!"
    echo "O servidor reiniciara por hardware se travar por mais de 60 segundos."
    exit 0
fi

# --- Modo daemon (rodando continuamente via systemd) ---
if [ "${1:-}" = "--daemon" ]; then
    log "Heartbeat watchdog daemon iniciado (PID $$)"

    # Abrir /dev/watchdog (iTCO_wdt)
    if exec 3<>/dev/watchdog 2>/dev/null; then
        log "/dev/watchdog aberto com sucesso (fd 3) - iTCO_wdt"
        USE_WATCHDOG=1
    else
        log "ERRO: Nao foi possivel abrir /dev/watchdog"
        exit 1
    fi

    # Loop principal
    while true; do
        # Ping no watchdog de hardware
        if [ "${USE_WATCHDOG}" = "1" ]; then
            # Escrever keepalive no watchdog (qquer char exceto 'V')
            printf '1' >&3 2>/dev/null || {
                log "ERRO: Falha ao pingar /dev/watchdog - tentando SysRq reboot"
                echo b > /proc/sysrq-trigger 2>/dev/null
                /sbin/reboot -f 2>/dev/null
            }
        fi

        # Atualizar heartbeat file
        date '+%s' > "${HEARTBEAT_FILE}"

        sleep 10
    done
fi

# Se chamado sem argumento, mostrar ajuda
echo "Uso: $0 --install | --daemon"
echo "  --install  : Instalar e configurar o servico"
echo "  --daemon   : Rodar como daemon (usado pelo systemd)"
exit 1