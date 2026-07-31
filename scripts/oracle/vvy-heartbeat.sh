#!/bin/bash
# ==============================================================================
# vvy-heartbeat.sh — Monitora o vvy via Tailscale e alerta via Telegram
#
# Roda a cada 1 min via cron na Oracle VM.
# Se o vvy não responder após 3 pings consecutivos (3 min), considera offline
# e envia alerta Telegram. Reenvia lembrete a cada 30 min offline.
# Quando vvy volta, envia alerta de recuperação.
#
# Instalação:
#   /opt/vvy-monitor/vvy-heartbeat.sh
#   Cron: * * * * * /opt/vvy-monitor/vvy-heartbeat.sh
# ==============================================================================

# --- Config ---
VVY_IP="<TAILSCALE_VVV_IP>"
BOT_TOKEN="<TELEGRAM_BOT_TOKEN_ID>:AAGcV_5-HUpg8FI_mz0_qw1TVF4wVj_ou_g"
CHAT_ID="<TELEGRAM_CHAT_ID>"
LOG="/var/log/vvy-monitor.log"
STATE_FILE="/var/lib/vvy-monitor/state"
MAX_FAILS=3
REMINDER_INTERVAL=30  # minutos entre lembretes

mkdir -p /var/lib/vvy-monitor
touch "$STATE_FILE"

# --- Proteção contra execução simultânea ---
LOCKFILE="/var/lock/vvy-heartbeat.lock"
exec 200>"$LOCKFILE"
flock -n 200 || exit 0

# --- Rotação de log (manter últimas 5000 linhas) ---
if [ -f "$LOG" ]; then
    lines=$(wc -l < "$LOG")
    if [ "$lines" -gt 5000 ]; then
        tail -2500 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
    fi
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

send_telegram() {
    local msg="$1"
    local http_code
    local attempt=0
    local max_attempts=3

    while [ "$attempt" -lt "$max_attempts" ]; do
        attempt=$((attempt + 1))
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 \
            "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "text=${msg}" \
            -d "parse_mode=HTML" 2>/dev/null)

        if [ "$http_code" = "200" ]; then
            log "Telegram OK (tentativa ${attempt}/${max_attempts}, HTTP ${http_code})"
            return 0
        fi

        log "Telegram FALHOU (tentativa ${attempt}/${max_attempts}, HTTP ${http_code})"
        [ "$attempt" -lt "$max_attempts" ] && sleep 2
    done

    log "Telegram FALHOU apos ${max_attempts} tentativas — mensagem PERDIDA"
    return 1
}

# --- Ler estado anterior ---
prev_state=$(cat "$STATE_FILE" 2>/dev/null || echo "ONLINE")
fail_count=$(echo "$prev_state" | grep -oP 'FAILS=\K\d+' || echo "0")
current_state=$(echo "$prev_state" | grep -oP 'STATE=\K\w+' || echo "ONLINE")
offline_since=$(echo "$prev_state" | grep -oP 'SINCE=\K[\d-]+ [\d:]+' || echo "")
last_reminder=$(echo "$prev_state" | grep -oP 'REMINDER=\K[\d-]+ [\d:]+' || echo "")
offline_minutes=0

# --- Ping vvy ---
if ping -c1 -W5 "$VVY_IP" > /dev/null 2>&1; then
    # vvy está online
    if [ "$current_state" = "OFFLINE" ]; then
        # Voltou! Calcular duração do offline
        now=$(date '+%Y-%m-%d %H:%M:%S')
        if [ -n "$offline_since" ]; then
            # Calcular minutos offline
            offline_epoch=$(date -d "$offline_since" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            offline_minutes=$(( (now_epoch - offline_epoch) / 60 ))
            duration_msg="após ${offline_minutes}min offline"
        else
            duration_msg="após queda"
        fi
        send_telegram "🟢 <b>vvy voltou</b> às ${now} (${duration_msg})"
        log "vvy VOLTOU (${duration_msg})"
    fi
    echo "STATE=ONLINE FAILS=0 SINCE= REMINDER=" > "$STATE_FILE"
else
    # vvy não respondeu
    fail_count=$((fail_count + 1))
    now=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$fail_count" -ge "$MAX_FAILS" ]; then
        # Confirmado offline
        if [ "$current_state" = "ONLINE" ]; then
            # Primeira detecção de queda
            send_telegram "🔴 <b>ALERTA: vvy offline</b> às ${now}
Falhas consecutivas: ${fail_count}
IP Tailscale: ${VVY_IP}
Tentando WoL automático em 5 min..."
            log "vvy OFFLINE detectado (${fail_count} falhas)"
            echo "STATE=OFFLINE FAILS=${fail_count} SINCE=${now} REMINDER=${now}" > "$STATE_FILE"
        else
            # Já estava offline — verificar se é hora de lembrete
            if [ -n "$last_reminder" ]; then
                reminder_epoch=$(date -d "$last_reminder" +%s 2>/dev/null || echo 0)
                now_epoch=$(date +%s)
                minutes_since_reminder=$(( (now_epoch - reminder_epoch) / 60 ))
                if [ "$minutes_since_reminder" -ge "$REMINDER_INTERVAL" ]; then
                    if [ -n "$offline_since" ]; then
                        offline_epoch=$(date -d "$offline_since" +%s 2>/dev/null || echo 0)
                        offline_minutes=$(( (now_epoch - offline_epoch) / 60 ))
                    fi
                    send_telegram "🟡 <b>vvy ainda offline</b> — ${offline_minutes}min desde o alerta"
                    log "Lembrete enviado (${offline_minutes}min offline)"
                    echo "STATE=OFFLINE FAILS=${fail_count} SINCE=${offline_since} REMINDER=${now}" > "$STATE_FILE"
                fi
            fi
        fi
    else
        # Ainda não chegou no limite de falhas
        log "Falha ${fail_count}/${MAX_FAILS} — aguardando"
        echo "STATE=${current_state} FAILS=${fail_count} SINCE=${offline_since} REMINDER=${last_reminder}" > "$STATE_FILE"
    fi
fi
