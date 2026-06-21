# Server Freeze Diagnosis - Kit de Diagnóstico de Travamento

Kit de ferramentas para diagnosticar e recuperar automaticamente de travamentos intermitentes em servidores Linux onde o sistema congela completamente (nem SSH responde).

## Estrutura

```
scripts-server-freeze/
├── README.md                          # Este arquivo
├── docs/
│   └── server-freeze-diagnosis.md     # Plano detalhado de diagnóstico (5 fases)
└── bash/
    ├── install.sh                     # Instalador completo (executar primeiro)
    ├── server-watchdog.sh             # Monitoramento a cada 1 min (via cron)
    ├── post-reboot-diagnosis.sh       # Diagnóstico após reboot (executar após travamento)
    ├── heartbeat-watchdog.sh          # Heartbeat de reboot automático (softdog + SysRq)
    └── nvidia-fan-control.sh          # Controle de fans GPU RTX 3060 (fixado em 70%)
```

## Scripts em Uso no Servidor

| Script | Localização no servidor | Função |
|--------|------------------------|--------|
| `server-watchdog.sh` | `/usr/local/bin/server-watchdog.sh` | Cron a cada 1 min — registra memória, CPU, disco, rede |
| `post-reboot-diagnosis.sh` | `/usr/local/bin/post-reboot-diagnosis.sh` | Diagnóstico completo após reboot |
| `heartbeat-watchdog.sh` | `/usr/local/bin/heartbeat-watchdog.sh` | Serviço systemd — ping no iTCO_wdt (hardware watchdog) a cada 10s, reboot automático se travar |
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

**NMI watchdog desativado via GRUB:**
O `nmi_watchdog=0` foi adicionado ao `GRUB_CMDLINE_LINUX_DEFAULT` (não apenas sysctl). O sysctl `/etc/sysctl.d/99-disable-nmi-watchdog.conf` chega tarde demais — o NMI watchdog já consome um PMU counter no boot antes do sysctl ser aplicado.

**IMPORTANTE:** O `watchdog-mux` do Proxmox HA foi mascarado porque:
1. Não há HA configurado no servidor
2. Ele ocupava `/dev/watchdog` com `nowayout=0` (não reiniciava)
3. Os serviços `pve-ha-lrm` e `pve-ha-crm` também foram mascarados

## Após um Travamento

Quando o servidor travar, o heartbeat deve reiniciá-lo em ~60 segundos. Após o reboot, execute:

```bash
sudo /usr/local/bin/post-reboot-diagnosis.sh
```

## Causas Mais Comuns

| Causa | Sintoma nos Logs | Solução |
|-------|-----------------|---------|
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
| `/var/log/kern.log` | Logs de kernel persistentes |
| `/var/log/journal/` | Logs do systemd journal (persistente) |
| `/usr/local/bin/server-watchdog.sh` | Script de monitoramento |
| `/usr/local/bin/post-reboot-diagnosis.sh` | Script de diagnóstico pós-reboot |
| `/usr/local/bin/heartbeat-watchdog.sh` | Heartbeat de reboot automático (iTCO_wdt) |
| `/etc/default/grub` | Configuração do kernel cmdline (inclui `nmi_watchdog=0`) |
| `/etc/modules-load.d/iTCO_wdt.conf` | Carregamento do módulo iTCO_wdt no boot |
| `/etc/modprobe.d/iTCO_wdt.conf` | Parâmetros do iTCO_wdt (`nowayout=1 heartbeat=60`) |
| `/etc/sensors.d/nct6779-ignore.conf` | Sensores fantasmas NCT6779 ignorados |
| `/etc/modprobe.d/softdog.conf` | OBSOLETO — softdog é built-in, não módulo |
| `/etc/modules-load.d/softdog.conf` | OBSOLETO — softdog é built-in, não módulo |
