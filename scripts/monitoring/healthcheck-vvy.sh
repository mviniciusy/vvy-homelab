#!/bin/bash
# ============================================================================
# healthcheck-vvy.sh — Verificação de saúde do Proxmox vvy
# Executado via cronjob do Hermes a cada 2h
# Silencioso se tudo OK, só alerta se encontrar problemas
# ============================================================================

HOST="root@192.168.1.100"
ALERTS=""

# 1. heartbeat-watchdog — verificar restart counter
RESTART_COUNT=$(ssh "$HOST" 'systemctl show heartbeat-watchdog.service -p NRestarts --value 2>/dev/null')
if [ -n "$RESTART_COUNT" ] && [ "$RESTART_COUNT" -gt 5 ]; then
    ALERTS="${ALERTS}\n[CRITICO] heartbeat-watchdog restart counter = ${RESTART_COUNT} (deve ser < 5)"
fi

# 2. Verificar se WatchdogSec voltou pro service file (regressão)
HAS_WATCHDOG_SEC=$(ssh "$HOST" 'grep -c "^WatchdogSec=" /etc/systemd/system/heartbeat-watchdog.service 2>/dev/null')
if [ -n "$HAS_WATCHDOG_SEC" ] && [ "$HAS_WATCHDOG_SEC" -gt 0 ]; then
    ALERTS="${ALERTS}\n[CRITICO] WatchdogSec re-adicionado ao heartbeat-watchdog.service! Isso causa crash loop."
fi

# 3. Verificar watchdog de hardware (iTCO_wdt)
WD_IDENTITY=$(ssh "$HOST" 'cat /sys/class/watchdog/watchdog0/identity 2>/dev/null')
if [ -z "$WD_IDENTITY" ]; then
    ALERTS="${ALERTS}\n[CRITICO] Nenhum watchdog de hardware detectado em /sys/class/watchdog/watchdog0/identity"
elif [ "$WD_IDENTITY" != "iTCO_wdt" ]; then
    ALERTS="${ALERTS}\n[ALERTA] Watchdog de hardware inesperado: ${WD_IDENTITY} (esperado: iTCO_wdt)"
fi
WD_NOWAYOUT=$(ssh "$HOST" 'cat /sys/class/watchdog/watchdog0/nowayout 2>/dev/null')
if [ -n "$WD_NOWAYOUT" ] && [ "$WD_NOWAYOUT" -ne 1 ]; then
    ALERTS="${ALERTS}\n[CRITICO] Watchdog nowayout=0! Se o processo morrer, o watchdog e desarmado sem reboot."
fi
WD_STATE=$(ssh "$HOST" 'cat /sys/class/watchdog/watchdog0/state 2>/dev/null')
if [ -n "$WD_STATE" ] && [ "$WD_STATE" != "active" ]; then
    ALERTS="${ALERTS}\n[ALERTA] Watchdog de hardware nao esta ativo: state=${WD_STATE}"
fi

# 4. Verificar NMI watchdog desativado
NMI=$(ssh "$HOST" 'sysctl -n kernel.nmi_watchdog 2>/dev/null')
if [ -n "$NMI" ] && [ "$NMI" -ne 0 ]; then
    ALERTS="${ALERTS}\n[ALERTA] NMI watchdog ativo (kernel.nmi_watchdog=${NMI}). Deve ser 0 para evitar consumo de PMU counter."
fi

# 5. Load average
LOAD=$(ssh "$HOST" 'cat /proc/loadavg 2>/dev/null | awk "{print \$1}"')
LOAD_INT=$(echo "$LOAD" | awk -F. '{print $1}')
if [ -n "$LOAD_INT" ] && [ "$LOAD_INT" -gt 15 ]; then
    ALERTS="${ALERTS}\n[ALERTA] Load average alto: ${LOAD} (threshold: 15)"
fi

# 6. SMART — verificar se algum disco falhou
SMART_FAIL=$(ssh "$HOST" 'for disk in sda sdb sdc sdd; do smartctl -H /dev/$disk 2>&1 | grep -c "FAILED"; done' 2>/dev/null | awk '{s+=$1} END{print s}')
if [ -n "$SMART_FAIL" ] && [ "$SMART_FAIL" -gt 0 ]; then
    ALERTS="${ALERTS}\n[CRITICO] SMART disk failure detectado! Verificar imediatamente."
fi

# 7. Kernel messages novas (OOM, MCE, hardware)
KERNEL_ERRORS=$(ssh "$HOST" 'dmesg -T 2>/dev/null | grep -ciE "oom|killed process|MCE|hardware error"')
if [ -n "$KERNEL_ERRORS" ] && [ "$KERNEL_ERRORS" -gt 0 ]; then
    ALERTS="${ALERTS}\n[ALERTA] Kernel messages suspeitas: ${KERNEL_ERRORS} ocorrencias de OOM/MCE/hardware error"
fi

# 8. Uptime — verificar se servidor reiniciou recentemente (possível travamento)
UPTIME_SEC=$(ssh "$HOST" 'cat /proc/uptime 2>/dev/null | awk "{print \$1}" | cut -d. -f1')
if [ -n "$UPTIME_SEC" ] && [ "$UPTIME_SEC" -lt 600 ]; then
    ALERTS="${ALERTS}\n[ALERTA] Servidor reiniciou ha menos de 10 minutos! Possivel travamento. Uptime: ${UPTIME_SEC}s"
fi

# Output — silencioso se OK, alertas se problemas
if [ -z "$ALERTS" ]; then
    echo "OK — vvy saudavel (load: ${LOAD}, watchdog: ${WD_IDENTITY:-?}, heartbeat restarts: ${RESTART_COUNT})"
    exit 0
else
    echo "PROBLEMAS DETECTADOS no vvy:"
    echo -e "$ALERTS"
    echo ""
    echo "Diagnostico rapido:"
    echo "  heartbeat: $(ssh "$HOST" 'systemctl status heartbeat-watchdog.service 2>&1 | head -5')"
    echo "  watchdog: $(ssh "$HOST" 'cat /sys/class/watchdog/watchdog0/identity /sys/class/watchdog/watchdog0/state /sys/class/watchdog/watchdog0/nowayout /sys/class/watchdog/watchdog0/timeout 2>&1 | paste -sd" " -')"
    echo "  uptime: $(ssh "$HOST" 'uptime')"
    echo "  memoria: $(ssh "$HOST" 'free -h | head -2')"
    exit 1
fi