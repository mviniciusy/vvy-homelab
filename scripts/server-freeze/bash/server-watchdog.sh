#!/bin/bash
# ============================================================================
# server-watchdog.sh - Monitoramento preventivo para diagnóstico de travamento
#
# Registra o estado do sistema a cada execução (via cron a cada 1 minuto).
# Se o servidor travar, os últimos registros antes do travamento mostrarão
# o que estava acontecendo.
#
# Instalação:
#   sudo cp server-watchdog.sh /usr/local/bin/
#   sudo chmod +x /usr/local/bin/server-watchdog.sh
#   sudo ./scripts/install.sh  (configura o cron automaticamente)
# ============================================================================

LOG_DIR="/var/log/watchdog"
LOG="${LOG_DIR}/server-state.log"
MAX_LINES=10000

# Criar diretório de logs se não existir
mkdir -p "${LOG_DIR}"

# Rotacionar log se ficar muito grande
if [ -f "${LOG}" ] && [ "$(wc -l < "${LOG}")" -gt "${MAX_LINES}" ]; then
    mv "${LOG}" "${LOG}.old"
fi

echo "===== $(date '+%Y-%m-%d %H:%M:%S') =====" >> "${LOG}"

# --- Memória e Swap ---
echo "--- MEMORY ---" >> "${LOG}"
free -h >> "${LOG}" 2>&1
echo "--- SWAP ---" >> "${LOG}"
swapon --show >> "${LOG}" 2>&1

# --- Load Average ---
echo "--- LOAD ---" >> "${LOG}"
uptime >> "${LOG}" 2>&1

# --- Top 10 processos por CPU ---
echo "--- TOP CPU ---" >> "${LOG}"
ps aux --sort=-%cpu | head -11 >> "${LOG}" 2>&1

# --- Top 10 processos por Memória ---
echo "--- TOP MEM ---" >> "${LOG}"
ps aux --sort=-%mem | head -11 >> "${LOG}" 2>&1

# --- CPU stats (para calcular I/O wait posteriormente) ---
echo "--- CPU STAT ---" >> "${LOG}"
grep "^cpu " /proc/stat >> "${LOG}" 2>&1

# --- Disk I/O ---
echo "--- DISK IO ---" >> "${LOG}"
if command -v iostat &>/dev/null; then
    iostat -x 1 1 >> "${LOG}" 2>&1
else
    cat /proc/diskstats >> "${LOG}" 2>&1
fi

# --- Espaço em disco ---
echo "--- DISK SPACE ---" >> "${LOG}"
df -h >> "${LOG}" 2>&1

# --- Inodes ---
echo "--- INODES ---" >> "${LOG}"
df -i >> "${LOG}" 2>&1

# --- Conexões de rede ---
echo "--- NETWORK CONNS ---" >> "${LOG}"
ss -s >> "${LOG}" 2>&1

# --- Processos zombie ---
echo "--- ZOMBIES ---" >> "${LOG}"
ps aux | awk '$8=="Z"' >> "${LOG}" 2>&1
zombie_count=$(ps aux | awk '$8=="Z"' | wc -l)
echo "Zombie count: ${zombie_count}" >> "${LOG}" 2>&1

# --- Últimas mensagens críticas do kernel ---
echo "--- DMESG TAIL ---" >> "${LOG}"
dmesg -T 2>/dev/null | tail -5 >> "${LOG}" 2>&1

# --- Verificar se OOM Killer atuou recentemente ---
echo "--- OOM CHECK ---" >> "${LOG}"
dmesg -T 2>/dev/null | grep -i "oom\|killed process" | tail -3 >> "${LOG}" 2>&1

echo "" >> "${LOG}"
