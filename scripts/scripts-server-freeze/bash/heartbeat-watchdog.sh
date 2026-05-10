#!/bin/bash
# ============================================================================
# heartbeat-watchdog.sh - Heartbeat de reboot automático para travamentos
#
# FUNCIONAMENTO:
# - Roda como serviço systemd contínuo
# - A cada 10 segundos, escreve um "ping" no /dev/watchdog
# - Se este processo parar de pingar (sistema travou), o softdog do kernel
#   reinicia a máquina automaticamente em 60 segundos
# - Com nowayout=1, mesmo que o processo morra, o watchdog NÃO é desarmado
#
# IMPORTANTE: O softdog deve estar configurado com:
#   nowayout=1 soft_noboot=0 soft_active_on_boot=1 soft_margin=60
#
# INSTALAÇÃO:
#   sudo bash /usr/local/bin/heartbeat-watchdog.sh --install
# ============================================================================

HEARTBEAT_FILE="/tmp/heartbeat-watchdog"
LOG="/var/log/watchdog/heartbeat.log"

mkdir -p /var/log/watchdog

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG}" 2>/dev/null
}

# --- Modo de instalação ---
if [ "${1:-}" = "--install" ]; then
    echo "Instalando heartbeat-watchdog..."

    # Configurar softdog
    echo "options softdog soft_noboot=0 nowayout=1 soft_margin=60 soft_active_on_boot=1" > /etc/modprobe.d/softdog.conf
    echo "softdog" > /etc/modules-load.d/softdog.conf

    # Criar serviço systemd
    cat > /etc/systemd/system/heartbeat-watchdog.service <<'EOF'
[Unit]
Description=Heartbeat Watchdog - Keep system alive, reboot on freeze
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/heartbeat-watchdog.sh --daemon
Restart=always
RestartSec=3

# Alta prioridade - não pode ser morto por OOM
OOMScoreAdjust=-1000
Nice=-5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable heartbeat-watchdog.service
    systemctl start heartbeat-watchdog.service

    echo "Heartbeat watchdog instalado!"
    echo "O servidor reiniciará automaticamente se travar por mais de 60 segundos."
    echo "REBOOT NECESSÁRIO para aplicar as mudanças no softdog."
    exit 0
fi

# --- Modo daemon (rodando continuamente via systemd) ---
if [ "${1:-}" = "--daemon" ]; then
    log "Heartbeat watchdog daemon iniciado (PID $$)"

    # Tentar abrir /dev/watchdog
    # Se estiver ocupado (watchdog-mux), usar mecanismo alternativo
    if exec 3<>/dev/watchdog 2>/dev/null; then
        log "/dev/watchdog aberto com sucesso (fd 3) - modo softdog"
        USE_WATCHDOG=1
    else
        log "AVISO: /dev/watchdog ocupado - usando mecanismo alternativo (SysRq)"
        USE_WATCHDOG=0
    fi

    # Loop principal
    while true; do
        # Ping no watchdog de hardware
        if [ "${USE_WATCHDOG}" = "1" ]; then
            # Escrever magic character 'V' no /dev/watchdog (keepalive)
            # Qualquer write reseta o timer do softdog
            printf 'V' >&3 2>/dev/null || {
                log "ERRO: Falha ao pingar /dev/watchdog"
                # Tentar SysRq reboot como fallback
                echo b > /proc/sysrq-trigger 2>/dev/null
                reboot -f 2>/dev/null
            }
        fi

        # Atualizar heartbeat file
        date '+%s' > "${HEARTBEAT_FILE}"

        # Verificar saúde básica do sistema
        # Se o load average estiver > 200, algo está muito errado
        load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
        load_int=$(echo "${load}" | awk -F. '{print $1}')
        if [ "${load_int:-0}" -gt 200 ]; then
            log "CRÍTICO: Load average ${load} - forçando reboot!"
            echo b > /proc/sysrq-trigger 2>/dev/null
            reboot -f 2>/dev/null
        fi

        # Verificar se a GPU está em temperatura crítica
        if command -v nvidia-smi &>/dev/null; then
            gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
            if [ -n "${gpu_temp}" ] && [ "${gpu_temp}" -gt 95 ]; then
                log "CRÍTICO: GPU temperatura ${gpu_temp}°C - forçando reboot!"
                echo b > /proc/sysrq-trigger 2>/dev/null
                reboot -f 2>/dev/null
            fi
        fi

        sleep 10
    done
fi

# --- Modo verificação (via cron como backup) ---
date '+%s' > "${HEARTBEAT_FILE}"
