#!/bin/bash
# ============================================================================
# mce-collector.sh — Coleta métricas de MCE/EDAC para análise por LLM
#
# Executado a cada 5 min via cron. Grava snapshot num arquivo JSON que o
# cron job do Hermes lê e envia pro LLM analisar.
# ============================================================================

OUTPUT="/var/log/mce-snapshot.json"

# Coletar contadores EDAC
CE_TOTAL=$(cat /sys/devices/system/edac/mc/mc0/ce_count 2>/dev/null || echo 0)
UE_TOTAL=$(cat /sys/devices/system/edac/mc/mc0/ue_count 2>/dev/null || echo 0)

# Coletar per-dimm
DIMMS=""
for d in /sys/devices/system/edac/mc/mc0/dimm*/; do
    loc=$(cat "$d/dimm_location" 2>/dev/null | tr -d '\n')
    ce=$(cat "$d/dimm_ce_count" 2>/dev/null || echo 0)
    sz=$(cat "$d/size" 2>/dev/null || echo 0)
    DIMMS="${DIMMS}{\"location\":\"${loc}\",\"ce\":${ce},\"size_mb\":${sz}},"
done
DIMMS=${DIMMS%,}

# Últimos MCE do dmesg
MCE_RECENT=$(dmesg -T 2>/dev/null | grep -i "mce\|edac\|machine check\|hardware error" | tail -10 | sed 's/"/\\"/g' | sed 's/\t/    /g')

# Uptime e load
UPTIME_SEC=$(cat /proc/uptime | awk '{print int($1)}')
LOAD_1=$(awk '{print $1}' /proc/loadavg)
LOAD_5=$(awk '{print $2}' /proc/loadavg)
LOAD_15=$(awk '{print $3}' /proc/loadavg)

# Memória
MEM_TOTAL=$(awk '/MemTotal/{print $2}' /proc/meminfo)
MEM_FREE=$(awk '/MemAvailable/{print $2}' /proc/meminfo)

# Último reboot
LAST_BOOT=$(who -b | awk '{print $3" "$4}')

# Temperatura HDs
TEMP_SDB=$(smartctl -A /dev/sdb 2>/dev/null | grep "194 Temperature" | awk '{print $10}')
TEMP_SDC=$(smartctl -A /dev/sdc 2>/dev/null | grep "194 Temperature" | awk '{print $10}')
TEMP_SDD=$(smartctl -A /dev/sdd 2>/dev/null | grep "194 Temperature" | awk '{print $10}')
TEMP_NVME=$(smartctl -A /dev/nvme0 2>/dev/null | grep "Temperature:" | head -1 | awk '{print $2}')

# Contagem de freezes (boots que terminaram sem shutdown limpo nas últimas 72h)
FREEZE_COUNT=$(journalctl --list-boots --since "3 days ago" --no-pager 2>/dev/null | wc -l)
BOOTS_72H=$(journalctl --list-boots --since "3 days ago" --no-pager 2>/dev/null | wc -l)

# Montar JSON
cat > "$OUTPUT" << JSONEOF
{
  "timestamp": "$(date -Iseconds)",
  "hostname": "$(hostname)",
  "uptime_seconds": ${UPTIME_SEC},
  "uptime_human": "$(uptime -p)",
  "last_boot": "${LAST_BOOT}",
  "edac": {
    "ce_total": ${CE_TOTAL},
    "ue_total": ${UE_TOTAL},
    "dimms": [${DIMMS}]
  },
  "mce_recent": "${MCE_RECENT}",
  "load": {
    "1min": ${LOAD_1},
    "5min": ${LOAD_5},
    "15min": ${LOAD_15}
  },
  "memory": {
    "total_kb": ${MEM_TOTAL},
    "available_kb": ${MEM_FREE}
  },
  "temperatures": {
    "sdb_wd500": ${TEMP_SDB:-0},
    "sdc_seagate": ${TEMP_SDC:-0},
    "sdd_wd_ntfs": ${TEMP_SDD:-0},
    "nvme": ${TEMP_NVME:-0}
  },
  "boots_last_72h": ${BOOTS_72H}
}
JSONEOF

echo "$OUTPUT"
