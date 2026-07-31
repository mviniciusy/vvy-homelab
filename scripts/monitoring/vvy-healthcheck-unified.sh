#!/bin/bash
# ==============================================================================
# vvy-healthcheck-unified.sh — Healthcheck + MCE/EDAC em uma mensagem
# Substitui: healthcheck-vvy.sh + mce-monitor.sh
# Roda via cronjob do Hermes a cada 2h (no_agent=true)
# ==============================================================================

HOST="root@<HOST_IP>"
ALERTS=""

# === PARTE 1: MCE/EDAC ===
MCE_OUTPUT=$(ssh -o ConnectTimeout=5 "$HOST" '
echo "MCE/EDAC: CE=$(cat /sys/devices/system/edac/mc/mc0/ce_count 2>/dev/null || echo 0) UE=$(cat /sys/devices/system/edac/mc/mc0/ue_count 2>/dev/null || echo 0)"
for d in /sys/devices/system/edac/mc/mc0/dimm*/; do
    loc=$(cat "$d/dimm_location" 2>/dev/null | tr -d "\n")
    ce=$(cat "$d/dimm_ce_count" 2>/dev/null || echo 0)
    sz=$(cat "$d/size" 2>/dev/null || echo 0)
    echo "  $loc ${sz}MB CE=$ce"
done
' 2>&1)

# Extrair CE total para checar alerta
CE_TOTAL=$(echo "$MCE_OUTPUT" | head -1 | grep -oP 'CE=\K\d+' || echo "0")

# === PARTE 2: Healthcheck ===

# 1. heartbeat-watchdog restart counter
RESTART_COUNT=$(ssh -o ConnectTimeout=5 "$HOST" 'systemctl show heartbeat-watchdog.service -p NRestarts --value 2>/dev/null' 2>/dev/null)
if [ -n "$RESTART_COUNT" ] && [ "$RESTART_COUNT" -gt 5 ]; then
    ALERTS="${ALERTS}⚠ heartbeat-watchdog restarts=${RESTART_COUNT}\n"
fi

# 2. WatchdogSec regression
HAS_WATCHDOG_SEC=$(ssh -o ConnectTimeout=5 "$HOST" 'grep -c "^WatchdogSec=" /etc/systemd/system/heartbeat-watchdog.service 2>/dev/null' 2>/dev/null)
if [ -n "$HAS_WATCHDOG_SEC" ] && [ "$HAS_WATCHDOG_SEC" -gt 0 ]; then
    ALERTS="${ALERTS}⚠ WatchdogSec re-adicionado ao heartbeat!\n"
fi

# 3. Load average
LOAD=$(ssh -o ConnectTimeout=5 "$HOST" 'cat /proc/loadavg 2>/dev/null | awk "{print \$1}"' 2>/dev/null)
LOAD_INT=$(echo "$LOAD" | awk -F. '{print $1}')
if [ -n "$LOAD_INT" ] && [ "$LOAD_INT" -gt 15 ]; then
    ALERTS="${ALERTS}⚠ Load alto: ${LOAD}\n"
fi

# 4. SMART
SMART_FAIL=$(ssh -o ConnectTimeout=5 "$HOST" 'for disk in sda sdb sdc sdd; do smartctl -H /dev/$disk 2>&1 | grep -c "FAILED"; done' 2>/dev/null | awk '{s+=$1} END{print s}')
if [ -n "$SMART_FAIL" ] && [ "$SMART_FAIL" -gt 0 ]; then
    ALERTS="${ALERTS}⚠ SMART disk failure!\n"
fi

# 5. Kernel errors
KERNEL_ERRORS=$(ssh -o ConnectTimeout=5 "$HOST" 'dmesg -T 2>/dev/null | grep -ciE "oom|killed process|MCE|hardware error"' 2>/dev/null)
if [ -n "$KERNEL_ERRORS" ] && [ "$KERNEL_ERRORS" -gt 0 ]; then
    ALERTS="${ALERTS}⚠ Kernel: ${KERNEL_ERRORS} msgs OOM/MCE/hardware\n"
fi

# 6. Uptime
UPTIME_SEC=$(ssh -o ConnectTimeout=5 "$HOST" 'cat /proc/uptime 2>/dev/null | awk "{print \$1}" | cut -d. -f1' 2>/dev/null)
UPTIME_STR=$(ssh -o ConnectTimeout=5 "$HOST" 'uptime -p 2>/dev/null' 2>/dev/null)
if [ -n "$UPTIME_SEC" ] && [ "$UPTIME_SEC" -lt 600 ]; then
    ALERTS="${ALERTS}⚠ Servidor reiniciou ha <10min! Possivel travamento.\n"
fi

# 7. CE da RAM aumentou
if [ "$CE_TOTAL" -gt 0 ]; then
    ALERTS="${ALERTS}⚠ RAM CE=${CE_TOTAL} (verificar EDAC)\n"
fi

# 8. Memoria
MEM=$(ssh -o ConnectTimeout=5 "$HOST" 'free -h | grep Mem' 2>/dev/null)

# === OUTPUT UNIFICADO ===

if [ -z "$ALERTS" ]; then
    # Tudo OK — mensagem compacta
    echo "✓ vvy saudavel — ${UPTIME_STR} | load: ${LOAD} | RAM CE: ${CE_TOTAL} | heartbeat restarts: ${RESTART_COUNT}"
else
    # Tem alertas — mensagem detalhada
    echo "⚠ vvy — ALERTAS:"
    echo -e "$ALERTS"
    echo "MCE/EDAC:"
    echo "$MCE_OUTPUT"
    echo "Uptime: ${UPTIME_STR}"
    echo "Mem: ${MEM}"
fi
