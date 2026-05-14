#!/bin/bash
# ============================================================================
# post-reboot-diagnosis.sh - Diagnóstico imediato após reboot do servidor
#
# Execute este script LOGO APÓS o servidor voltar de um travamento/hard reboot.
# Ele coleta todas as evidências possíveis antes que os logs sejam sobrescritos.
#
# Uso:
#   sudo bash post-reboot-diagnosis.sh
#   sudo bash post-reboot-diagnosis.sh > diagnostico-$(date +%Y%m%d-%H%M%S).txt
# ============================================================================

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SEPARATOR="============================================================"

echo "${SEPARATOR}"
echo "  DIAGNÓSTICO PÓS-REBOOT - $(date '+%Y-%m-%d %H:%M:%S')"
echo "${SEPARATOR}"
echo ""

# ---------------------------------------------------------------------------
# 1. OOM Killer
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${RED}[1] VERIFICAÇÃO DE OOM KILLER${NC}"
echo "${SEPARATOR}"
echo ""

oom_found=0

echo ">>> dmesg -T | grep -i oom"
if dmesg -T 2>/dev/null | grep -i "oom\|killed process\|out of memory" | tail -20; then
    oom_found=1
    echo -e "  ${RED}⚠ OOM KILLER ENCONTRADO! Processos foram mortos por falta de memória.${NC}"
else
    echo -e "  ${GREEN}✓ Nenhuma evidência de OOM Killer no dmesg.${NC}"
fi

echo ""
echo ">>> journalctl -k --since '1 day ago' | grep -i oom"
if journalctl -k --since "1 day ago" 2>/dev/null | grep -i "oom\|killed process\|out of memory" | tail -20; then
    oom_found=1
    echo -e "  ${RED}⚠ OOM KILLER ENCONTRADO no journal!${NC}"
else
    echo -e "  ${GREEN}✓ Nenhuma evidência de OOM Killer no journal.${NC}"
fi

echo ""

# ---------------------------------------------------------------------------
# 2. Kernel Panic / Erros de Kernel
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${RED}[2] VERIFICAÇÃO DE KERNEL PANIC / ERROS${NC}"
echo "${SEPARATOR}"
echo ""

echo ">>> dmesg -T | grep -i 'panic\|error\|bug\|hung_task\|lockup\|NMI\|MCE'"
dmesg -T 2>/dev/null | grep -i "panic\|error\|bug\|hung_task\|lockup\|NMI\|MCE" | tail -30 || echo "  (nenhum resultado)"

echo ""
echo ">>> journalctl -k --since '1 day ago' | grep -i 'panic\|error\|bug\|hung_task\|lockup'"
journalctl -k --since "1 day ago" 2>/dev/null | grep -i "panic\|error\|bug\|hung_task\|lockup" | tail -30 || echo "  (nenhum resultado)"

echo ""

# ---------------------------------------------------------------------------
# 3. Memória e Swap
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${YELLOW}[3] ESTADO DE MEMÓRIA E SWAP${NC}"
echo "${SEPARATOR}"
echo ""

echo ">>> free -h"
free -h

echo ""
echo ">>> swapon --show"
swapon --show 2>/dev/null || echo -e "  ${RED}⚠ NENHUM SWAP CONFIGURADO! Isso é perigoso - o servidor pode travar por falta de RAM.${NC}"

echo ""
echo ">>> swappiness atual"
swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "N/A")
echo "  vm.swappiness = ${swappiness}"

echo ""

# ---------------------------------------------------------------------------
# 4. Disco e Inodes
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${YELLOW}[4] ESPAÇO EM DISCO E INODES${NC}"
echo "${SEPARATOR}"
echo ""

echo ">>> df -h"
df -h

echo ""
echo ">>> df -i"
df -i

echo ""

# Verificar se algum filesystem está 100% cheio
full_disks=$(df -h | awk 'NR>1 && $5=="100%" {print $6}')
if [ -n "${full_disks}" ]; then
    echo -e "  ${RED}⚠ DISCO CHEIO EM:${NC}"
    echo "${full_disks}"
else
    echo -e "  ${GREEN}✓ Nenhum disco 100% cheio.${NC}"
fi

full_inodes=$(df -i | awk 'NR>1 && $5=="100%" {print $6}')
if [ -n "${full_inodes}" ]; then
    echo -e "  ${RED}⚠ INODES ESGOTADOS EM:${NC}"
    echo "${full_inodes}"
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Erros de Filesystem
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${YELLOW}[5] ERROS DE FILESYSTEM${NC}"
echo "${SEPARATOR}"
echo ""

echo ">>> dmesg -T | grep -i 'ext4\|xfs\|btrfs\|remount.*ro\|corrupt\|I/O error'"
dmesg -T 2>/dev/null | grep -i "ext4.*error\|xfs.*error\|btrfs.*error\|remount.*ro\|corrupt\|I/O error\|read-only" | tail -20 || echo "  (nenhum resultado)"

echo ""

# ---------------------------------------------------------------------------
# 6. Processos Pesados
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${YELLOW}[6] PROCESSOS POR CPU E MEMÓRIA${NC}"
echo "${SEPARATOR}"
echo ""

echo ">>> Top 15 por CPU"
ps aux --sort=-%cpu | head -16

echo ""
echo ">>> Top 15 por Memória"
ps aux --sort=-%mem | head -16

echo ""

# ---------------------------------------------------------------------------
# 7. Load Average e Uptime
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${YELLOW}[7] LOAD AVERAGE E UPTIME${NC}"
echo "${SEPARATOR}"
echo ""

echo ">>> uptime"
uptime

echo ""

# ---------------------------------------------------------------------------
# 8. Últimos logs do journal antes do travamento
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${YELLOW}[8] ÚLTIMOS LOGS DO JOURNAL (últimas 2 horas antes do reboot)${NC}"
echo "${SEPARATOR}"
echo ""

echo ">>> journalctl --since '1 day ago' | tail -100"
journalctl --since "1 day ago" 2>/dev/null | tail -100 || echo "  (journal não disponível ou vazio)"

echo ""

# ---------------------------------------------------------------------------
# 9. Watchdog logs (se instalado)
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${YELLOW}[9] LOGS DO WATCHDOG (se instalado)${NC}"
echo "${SEPARATOR}"
echo ""

if [ -f /var/log/watchdog/server-state.log ]; then
    echo ">>> Últimos 50 registros do watchdog"
    tail -50 /var/log/watchdog/server-state.log
elif [ -f /var/log/watchdog/server-state.log.old ]; then
    echo -e "  ${YELLOW}⚠ Log principal não encontrado, mas existe .old${NC}"
    echo ">>> Últimos 50 registros do watchdog (.old)"
    tail -50 /var/log/watchdog/server-state.log.old
else
    echo -e "  ${YELLOW}⚠ Watchdog não instalado. Recomende-se instalar para capturar dados antes do próximo travamento.${NC}"
fi

echo ""

# ---------------------------------------------------------------------------
# 10. Hardware - SMART e Memória
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${YELLOW}[10] VERIFICAÇÃO DE HARDWARE${NC}"
echo "${SEPARATOR}"
echo ""

echo ">>> Erros de ECC/EDAC na memória"
if [ -d /sys/devices/system/edac/mc ]; then
    grep -r . /sys/devices/system/edac/mc/ 2>/dev/null | grep -v "size\|max_location" || echo "  (sem erros EDAC reportados)"
else
    echo "  (EDAC não disponível neste sistema)"
fi

echo ""
echo ">>> SMART dos discos"
if command -v smartctl &>/dev/null; then
    for disk in $(ls /dev/sd? /dev/vd? /dev/nvme?n1 2>/dev/null); do
        echo "--- ${disk} ---"
        smartctl -a "${disk}" 2>/dev/null | grep -E "Reallocated_Sector|Current_Pending|Offline_Uncorrectable|SMART overall|SMART Health" || echo "  (não foi possível ler SMART de ${disk})"
    done
else
    echo "  smartctl não instalado. Instale com: apt install smartmontools"
fi

echo ""

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
echo "${SEPARATOR}"
echo -e "  ${YELLOW}RESUMO DO DIAGNÓSTICO${NC}"
echo "${SEPARATOR}"
echo ""

if [ "${oom_found}" -eq 1 ]; then
    echo -e "  ${RED}❌ OOM KILLER detectado - O servidor provavelmente travou por falta de RAM${NC}"
    echo "     Ação: Adicionar mais swap, investigar processo consumidor de memória, ou aumentar RAM"
fi

if [ -n "${full_disks}" ]; then
    echo -e "  ${RED}❌ Disco(s) cheio(s) detectado(s)${NC}"
    echo "     Ação: Liberar espaço em disco imediatamente"
fi

if [ -n "${full_inodes}" ]; then
    echo -e "  ${RED}❌ Inodes esgotados${NC}"
    echo "     Ação: Remover arquivos pequenos/desnecessários"
fi

if ! swapon --show 2>/dev/null | grep -q .; then
    echo -e "  ${RED}❌ Nenhum swap configurado${NC}"
    echo "     Ação: Criar arquivo de swap (ver plano de diagnóstico)"
fi

echo ""
echo "  Para o plano completo de ação, consulte: plans/server-freeze-diagnosis.md"
echo ""
echo "${SEPARATOR}"
