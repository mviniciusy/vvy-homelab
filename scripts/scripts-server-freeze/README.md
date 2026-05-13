# 🔍 Server Freeze Diagnosis - Kit de Diagnóstico de Travamento

Kit de ferramentas para diagnosticar e recuperar automaticamente de travamentos intermitentes em servidores Linux onde o sistema congela completamente (nem SSH responde).

## Estrutura

```
scripts-server-freeze/
├── README.md                          # Este arquivo
├── docs/
│   └── server-freeze-diagnosis.md     # Plano detalhado de diagnóstico (5 fases)
└── bash/
    ├── install.sh                     # Instalador completo (executar primeiro)
    ├── server-watchdog.sh             # Monitoramento a cada 1 min (via cron) — inclui GPU
    ├── post-reboot-diagnosis.sh       # Diagnóstico após reboot (executar após travamento)
    ├── heartbeat-watchdog.sh          # Heartbeat de reboot automático (softdog + SysRq)
    └── nvidia-fan-control.sh          # Controle de fans GPU RTX 3060 (fixado em 70%)
```

## Scripts em Uso no Servidor

| Script | Localização no servidor | Função |
|--------|------------------------|--------|
| `server-watchdog.sh` | `/usr/local/bin/server-watchdog.sh` | Cron a cada 1 min — registra memória, CPU, disco, rede, GPU |
| `post-reboot-diagnosis.sh` | `/usr/local/bin/post-reboot-diagnosis.sh` | Diagnóstico completo após reboot |
| `heartbeat-watchdog.sh` | `/usr/local/bin/heartbeat-watchdog.sh` | Serviço systemd — ping no softdog a cada 10s, reboot automático se travar |
| `nvidia-fan-control.sh` | `/usr/local/bin/nvidia-fan-control.sh` | Serviço systemd — fixa fans da RTX 3060 em 70% |
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
- ✅ Instala controle de fans NVIDIA (Xorg headless + nvidia-settings, fans a 70%)

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
Softdog (kernel) → timeout de 60s sem ping
     ↓
Kernel reinicia automaticamente
```

**Configuração do softdog:**
- `nowayout=1` — mesmo que o processo morra, o watchdog não é desarmado
- `soft_noboot=0` — o softdog REINICIA a máquina (não apenas loga)
- `soft_active_on_boot=1` — ativa automaticamente no boot
- `soft_margin=60` — timeout de 60 segundos

> ⚠️ **CRÍTICO — softdog é BUILT-IN no kernel Proxmox:** O softdog é compilado como built-in (`CONFIG_SOFT_WATCHDOG=y`), não como módulo. Isso significa que `/etc/modprobe.d/softdog.conf` e `/etc/modules-load.d/softdog.conf` **NÃO têm efeito**. Os parâmetros DEVEM ser passados via kernel cmdline no GRUB. Adicione ao `/etc/default/grub` na variável `GRUB_CMDLINE_LINUX_DEFAULT`:
> ```
> softdog.nowayout=1 softdog.soft_noboot=0 softdog.soft_active_on_boot=1 softdog.soft_margin=60
> ```
> Depois execute `update-grub` e reinicie o servidor. Verifique com `cat /proc/cmdline | grep softdog` após o reboot.

**Proteções extras no heartbeat:**
- Se load average > 200 → forçar reboot (SysRq)
- Se GPU temp > 95°C → forçar reboot (SysRq)
- Se não consegue abrir `/dev/watchdog` → usa mecanismo alternativo (SysRq)

**IMPORTANTE:** O `watchdog-mux` do Proxmox HA foi mascarado porque:
1. Não há HA configurado no servidor
2. Ele ocupava `/dev/watchdog` com `nowayout=0` (não reiniciava)
3. Os serviços `pve-ha-lrm` e `pve-ha-crm` também foram mascarados

## Controle de Fans NVIDIA (nvidia-fancontrol)

O `nvidia-fancontrol.service` roda um Xorg headless para controlar as fans da GPU via `nvidia-settings`. As fans são fixadas em 70% para evitar superaquecimento.

> ⚠️ **O serviço DEVE usar `Restart=always`** (não `Restart=on-failure`). O Xorg pode encerrar com exit code 0 ao perder as telas DRM (ex: GPU reconfigurada pelo driver), e o `on-failure` NÃO reinicia nesse caso — as fans voltam a 0% e a GPU superaquece.

## Após um Travamento

Quando o servidor travar, o heartbeat deve reiniciá-lo em ~60 segundos. Após o reboot, execute:

```bash
sudo /usr/local/bin/post-reboot-diagnosis.sh
```

## Causas Mais Comuns

| Causa | Sintoma nos Logs | Solução |
|-------|-----------------|---------|
| GPU superaquecendo | Fans paradas, temp alta no watchdog | Corrigir nvidia-fan-control.sh (fans em 70%) |
| Driver NVIDIA instável | Firmware gsp error, GPU idle mas trava | Manter driver atualizado, monitorar firmware errors |
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
| `/usr/local/bin/heartbeat-watchdog.sh` | Heartbeat de reboot automático |
| `/usr/local/bin/nvidia-fan-control.sh` | Controle de fans da GPU |
| `/etc/default/grub` | ⚠️ Configuração REAL do softdog (kernel cmdline) |
| `/etc/modprobe.d/softdog.conf` | ⚠️ OBSOLETO — softdog é built-in, não módulo |
| `/etc/modules-load.d/softdog.conf` | ⚠️ OBSOLETO — softdog é built-in, não módulo |
