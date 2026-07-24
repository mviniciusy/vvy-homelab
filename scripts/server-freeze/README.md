# Server Freeze Diagnosis - Kit de Diagnóstico de Travamento

Kit de ferramentas para diagnosticar e recuperar automaticamente de travamentos intermitentes em servidores Linux onde o sistema congela completamente (nem SSH responde).

## Estrutura

```
scripts-server-freeze/
├── README.md                          # Este arquivo
├── docs/
│   ├── server-freeze-diagnosis.md     # Plano detalhado de diagnóstico (5 fases)
│   └── Incidentes-Modificações/
│       ├── incident-2026-07-22.md     # Incidente: C-states + MCE inicial
│       └── incident-2026-07-23.md     # Incidente: Causa raiz confirmada (MCE/EDAC pente 16GB)
└── bash/
    ├── install.sh                     # Instalador completo (executar primeiro)
    ├── server-watchdog.sh             # Monitoramento a cada 1 min (via cron)
    ├── post-reboot-diagnosis.sh       # Diagnóstico após reboot (executar após travamento)
    ├── heartbeat-watchdog.sh          # Heartbeat de reboot automático (iTCO_wdt + softdog backup + SysRq)
    ├── mce-collector.sh              # Coleta métricas MCE/EDAC para análise LLM (cron Hermes 5 min)
```

## Scripts em Uso no Servidor

| Script | Localização no servidor | Função |
|--------|------------------------|--------|
| `server-watchdog.sh` | `/usr/local/bin/server-watchdog.sh` | Cron a cada 1 min — registra memória, CPU, disco, rede |
| `post-reboot-diagnosis.sh` | `/usr/local/bin/post-reboot-diagnosis.sh` | Diagnóstico completo após reboot |
| `heartbeat-watchdog.sh` | `/usr/local/bin/heartbeat-watchdog.sh` | Serviço systemd — ping no iTCO_wdt (hardware watchdog) a cada 10s, reboot automático se travar |
| `mce-collector.sh` | `/usr/local/bin/mce-collector.sh` | Coleta métricas EDAC/MCE → JSON para análise por LLM (cron Hermes 5 min) |
| `install.sh` | (usado apenas na instalação) | Instala todos os componentes acima |

## Instalação Rápida

```bash
# No servidor, executar o instalador como root
cd /root/scripts-server-freeze
sudo bash bash/install.sh
```

O instalador faz tudo automaticamente:
- ✅ Instala o script de monitoramento watchdog (cron a cada 1 min)
- ✅ Configura swap se não existir (2GB por padrão)
- ✅ Configura persistência de logs (kern.log + journald)
- ✅ Habilita Magic SysRq para emergências
- ✅ Instala ferramentas de diagnóstico (sysstat, smartmontools, memtester)
- ✅ Copia script de diagnóstico pós-reboot

**Após install.sh, instalar também o heartbeat-watchdog:**
```bash
sudo bash /usr/local/bin/heartbeat-watchdog.sh --install
```

## Reboot Automático (heartbeat-watchdog)

O `heartbeat-watchdog.sh` resolve o problema do servidor ficar congelado por horas:

```
Sistema rodando → heartbeat ping /dev/watchdog a cada 10s
     ↓
Sistema trava → heartbeat para de pingar
     ↓
iTCO_wdt (hardware) → timeout de 60s sem ping
     ↓
Hardware reinicia automaticamente (timer independente do kernel)
```

**Dispositivo: iTCO_wdt (Intel TCO Watchdog Timer)**
- Timer de hardware na ponte Intel Panther Point (chipset C216/HM70)
- Funciona mesmo em hard freeze — o timer é independente do kernel
- `nowayout=1` — mesmo que o processo morra, o watchdog não é desarmado
- `heartbeat=60` — timeout de 60 segundos

**Configuração persistente:**
- Módulo: `/etc/modules-load.d/iTCO_wdt.conf` (carrega no boot)
- Parâmetros: `/etc/modprobe.d/iTCO_wdt.conf` (`options iTCO_wdt nowayout=1 heartbeat=60`)
- Script: `/usr/local/bin/heartbeat-watchdog.sh --daemon` (serviço systemd)

> **Anotação — Migração softdog → iTCO_wdt (21/Jun/2026):**
> O softdog era um watchdog 100% software — seu timer roda no kernel. Em hard freezes onde o kernel trava, o timer do softdog também congela, impedindo o reboot. O iTCO_wdt tem timer de hardware independente. O servidor ficava "travado mas não desligava" porque o softdog não conseguiu disparar o reboot.
>
> Arquivos obsoletos do softdog (NÃO remover, mas são ignorados pelo kernel):
> - `/etc/modprobe.d/softdog.conf` — softdog é built-in, modprobe não funciona
> - `/etc/modules-load.d/softdog.conf` — idem
> - Parâmetros `softdog.*` no GRUB cmdline — ainda presentes mas sem efeito com iTCO_wdt

**NMI watchdog reativado (23/Jul/2026):**
O `nmi_watchdog` foi reativado (`nmi_watchdog=1` no GRUB cmdline) para detectar hard lockups da CPU — o que inclui os MCE storms que causavam freeze sem logar nada. O sysctl `/etc/sysctl.d/99-disable-nmi-watchdog.conf` tornou-se obsoleto e pode ser removido. Ver `docs/Incidentes-Modificações/incident-2026-07-23.md` para detalhes.

**kdump configurado (23/Jul/2026):**
`kdump-tools` instalado com `crashkernel=256M` no GRUB. Se o kernel panicar, um kexec kernel captura o dump de memória em `/var/crash/`. Estado: `ready to kdump`.

**softdog como backup (23/Jul/2026):**
`softdog` carregado via `modprobe softdog soft_margin=60 nowayout=1` como camada adicional. O iTCO_wdt continua primário (hardware independente do kernel), softdog é secundário.

**sysctl de panic (23/Jul/2026):**
`/etc/sysctl.d/99-watchdog.conf` com `kernel.panic=10`, `kernel.panic_on_oops=1`, `kernel.hung_task_timeout_secs=60`. Se houver panic, reboot em 10s em vez de ficar travado.

**IMPORTANTE:** O `watchdog-mux` do Proxmox HA foi mascarado porque:
1. Não há HA configurado no servidor
2. Ele ocupava `/dev/watchdog` com `nowayout=0` (não reiniciava)
3. Os serviços `pve-ha-lrm` e `pve-ha-crm` também foram mascarados

## Após um Travamento

Quando o servidor travar, o heartbeat deve reiniciá-lo em ~60 segundos. Após o reboot, execute:

```bash
sudo /usr/local/bin/post-reboot-diagnosis.sh
```

## Monitoramento MCE/EDAC (mce-collector.sh)

O `mce-collector.sh` coleta métricas de erro de memória ECC e as grava em JSON para análise:

```
mce-collector.sh → /var/log/mce-snapshot.json → Cron job Hermes (5 min)
                                              → LLM analisa (nvidia/nemotron-3-ultra-550b-a55b)
                                              → Alerta Telegram se preciso
                                              → Silencioso se tudo OK
```

**Métricas coletadas:**
- Contadores EDAC: CE (Correctable) e UE (Uncorrectable) por pente de RAM
- Últimos MCE do dmesg
- Uptime, load average, memória disponível
- Temperatura dos HDs e NVMe
- Boot count nas últimas 72h

**Regras de alerta do cron job:**

| Condição | Nível |
|---|---|
| CE > 10 em 5 min | CRÍTICO — storm de MCE que causa freeze |
| UE > 0 | CRÍTICO — memória corrompendo dados |
| Temperatura > 50°C | WARNING |
| Load > 10 | WARNING |
| Memória < 2GB livre | WARNING |
| > 10 boots em 72h | WARNING — instabilidade |

**Pré-requisito do modelo:** `chat_template_kwargs.enable_thinking=false` (nemotron-3 precisa disso senão reasoning vaza dentro de content).

## Causas Mais Comuns

| Causa | Sintoma nos Logs | Solução |
|-------|-----------------|---------|
| MCE/EDAC de memória | `EDAC MC0: CE memory read error ... OVERFLOW` no dmesg | Substituir pente de RAM com erro (ver `mce-collector.sh`) |
| MCE storm (hard lockup) | `mce_notify_irq: N callbacks suppressed` + freeze sem log | Mesmo que MCE — resolver pente defeituoso |
| Falta de RAM | OOM Killer nos logs | Adicionar swap, aumentar RAM |
| CPU 100% | Load average alto no watchdog | Identificar e corrigir processo descontrolado |
| Disco cheio | df mostra 100% | Limpar disco, rotacionar logs |
| Kernel panic | Stack trace no kern.log | Atualizar kernel ou driver com bug |
| Softdog sem nowayout | Travamento sem reboot automático | Configurar via GRUB cmdline (não modprobe.d) |

## Compatibilidade

- ✅ Debian / Ubuntu
- ✅ Proxmox VE (detecta e evita conflito com meta-pacote `proxmox-ve`)
- ✅ CentOS / RHEL
- ✅ Qualquer Linux com systemd

## Em Caso de Emergência (Servidor Travado)

Se tiver acesso ao console do Proxmox (GUI web), use Magic SysRq **antes** do hard reboot:

```
Alt+SysRq+t → Dump de tarefas (mostra o que está travado)
Alt+SysRq+m → Dump de memória
Alt+SysRq+s → Sync discos (salvar dados)
Alt+SysRq+u → Remontar discos como read-only
Alt+SysRq+b → Reboot seguro
```

## Arquivos Importantes no Servidor

| Arquivo | Descrição |
|---------|-----------|
| `/var/log/watchdog/server-state.log` | Logs do watchdog (estado a cada 1 min) |
| `/var/log/watchdog/heartbeat.log` | Logs do heartbeat watchdog |
| `/var/log/mce-snapshot.json` | Snapshot das métricas MCE/EDAC (atualizado a cada 5 min pelo mce-collector.sh) |
| `/var/crash/` | Diretório de crash dumps do kdump (se kernel panicar) |
| `/var/log/kern.log` | Logs de kernel persistentes |
| `/var/log/journal/` | Logs do systemd journal (persistente) |
| `/usr/local/bin/server-watchdog.sh` | Script de monitoramento |
| `/usr/local/bin/post-reboot-diagnosis.sh` | Script de diagnóstico pós-reboot |
| `/usr/local/bin/heartbeat-watchdog.sh` | Heartbeat de reboot automático (iTCO_wdt + softdog) |
| `/usr/local/bin/mce-collector.sh` | Coletor de métricas MCE/EDAC para análise LLM |
| `/etc/default/grub` | Configuração do kernel cmdline (inclui `nmi_watchdog=1 crashkernel=256M panic=10`) |
| `/etc/sysctl.d/99-watchdog.conf` | Sysctl: `kernel.panic=10`, `panic_on_oops=1`, `hung_task_timeout_secs=60` |
| `/etc/modules-load.d/iTCO_wdt.conf` | Carregamento do módulo iTCO_wdt no boot |
| `/etc/modprobe.d/iTCO_wdt.conf` | Parâmetros do iTCO_wdt (`nowayout=1 heartbeat=60`) |
| `/etc/sensors.d/nct6779-ignore.conf` | Sensores fantasmas NCT6779 ignorados |
| `/etc/sysctl.d/99-disable-nmi-watchdog.conf` | OBSOLETO — NMI watchdog reativado em 23/Jul/2026 |
| `/etc/modprobe.d/softdog.conf` | OBSOLETO — softdog é built-in, carregado via modprobe manual |
| `/etc/modules-load.d/softdog.conf` | OBSOLETO — idem |
