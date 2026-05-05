# 🔍 Server Freeze Diagnosis - Kit de Diagnóstico de Travamento

Kit de ferramentas para diagnosticar travamentos intermitentes em servidores Linux onde o sistema congela completamente (nem SSH responde) e só volta com hard reboot.

## Estrutura

```
scripts-server-freeze/
├── README.md                          # Este arquivo
├── docs/
│   └── server-freeze-diagnosis.md     # Plano detalhado de diagnóstico (5 fases)
└── bash/
    ├── install.sh                     # Instalador completo (executar primeiro)
    ├── server-watchdog.sh             # Monitoramento a cada 1 min (via cron)
    └── post-reboot-diagnosis.sh       # Diagnóstico após reboot (executar após travamento)
```

## Instalação Rápida

```bash
# 1. Copiar os scripts para o servidor (scp, git clone, etc.)
scp -r scripts-server-freeze/ root@seu-servidor:/root/scripts-server-freeze/

# 2. No servidor, executar o instalador como root
cd /root/scripts-server-freeze
sudo bash bash/install.sh
```

O instalador faz tudo automaticamente:
- ✅ Instala o script de monitoramento watchdog (cron a cada 1 min)
- ✅ Configura swap se não existir (2GB por padrão)
- ✅ Configura persistência de logs (kern.log + journald)
- ✅ Habilita Magic SysRq para emergências
- ✅ Instala watchdog de hardware se disponível (compatível com Proxmox VE)
- ✅ Instala ferramentas de diagnóstico (sysstat, smartmontools, memtester)
- ✅ Copia script de diagnóstico pós-reboot

### Instalação Parcial

```bash
# Apenas configurar swap
sudo bash bash/install.sh --swap-only

# Apenas instalar watchdog de monitoramento
sudo bash bash/install.sh --watchdog-only
```

## Após um Travamento

Quando o servidor travar e você fizer o hard reboot, execute **imediatamente**:

```bash
sudo /usr/local/bin/post-reboot-diagnosis.sh
```

Opcionalmente, salve a saída em arquivo para análise posterior:

```bash
sudo /usr/local/bin/post-reboot-diagnosis.sh > diagnostico-$(date +%Y%m%d-%H%M%S).txt 2>&1
```

## O que cada script faz

### `bash/server-watchdog.sh` — Monitoramento Preventivo

Registrado via cron a cada 1 minuto, salva em `/var/log/watchdog/server-state.log`:
- Uso de memória e swap
- Load average
- Top 10 processos por CPU e memória
- Disk I/O
- Espaço em disco e inodes
- Conexões de rede
- Processos zombie
- Mensagens críticas do kernel
- Evidências de OOM Killer

Se o servidor travar, os **últimos registros** antes do travamento mostram o que estava acontecendo.

### `bash/post-reboot-diagnosis.sh` — Diagnóstico Pós-Reboot

Executado após o servidor voltar, verifica:
1. Evidências de OOM Killer (falta de RAM)
2. Kernel panic ou erros de kernel
3. Estado de memória e swap
4. Espaço em disco e inodes
5. Erros de filesystem
6. Processos pesados (CPU/memória)
7. Load average
8. Últimos logs do journal
9. Logs do watchdog (se instalado)
10. Hardware (SMART dos discos, erros ECC)

Gera um resumo com ações recomendadas.

### `bash/install.sh` — Instalador

Configura tudo automaticamente. Veja [Instalação Rápida](#instalação-rápida).

### `docs/server-freeze-diagnosis.md` — Plano de Diagnóstico

Documento completo com 5 fases de diagnóstico, causas prováveis, fluxograma de decisão e checklist de execução.

## Causas Mais Comuns

| Causa | Sintoma nos Logs | Solução |
|-------|-----------------|---------|
| Falta de RAM | OOM Killer nos logs | Adicionar swap, aumentar RAM, corrigir vazamento de memória |
| CPU 100% | Load average alto no watchdog | Identificar e corrigir processo descontrolado |
| Disco cheio | df mostra 100% | Limpar disco, rotacionar logs |
| Inodes esgotados | df -i mostra 100% | Remover arquivos pequenos desnecessários |
| Kernel panic | Stack trace no kern.log | Atualizar kernel ou driver com bug |
| Disco com I/O saturado | iowait alto no watchdog | Verificar saúde do disco (SMART), otimizar I/O |
| Hardware defeituoso | Erros ECC, bad sectors | Substituir componente |

## Compatibilidade

- ✅ Debian / Ubuntu
- ✅ Proxmox VE (detecta e evita conflito com meta-pacote `proxmox-ve`)
- ✅ CentOS / RHEL
- ✅ Qualquer Linux com systemd

## Em Caso de Emergência (Servidor Travado)

Se tiver acesso ao console (IPMI/iLO/KVM/Proxmox GUI), use Magic SysRq **antes** do hard reboot:

```
Alt+SysRq+t → Dump de tarefas (mostra o que está travado)
Alt+SysRq+m → Dump de memória
Alt+SysRq+s → Sync discos (salvar dados)
Alt+SysRq+u → Remontar discos como read-only
Alt+SysRq+b → Reboot seguro
```

Isso preserva evidências e evita corrupção de filesystem.

## Arquivos Importantes no Servidor

| Arquivo | Descrição |
|---------|-----------|
| `/var/log/watchdog/server-state.log` | Logs do watchdog (estado a cada 1 min) |
| `/var/log/kern.log` | Logs de kernel persistentes |
| `/var/log/journal/` | Logs do systemd journal (persistente) |
| `/usr/local/bin/server-watchdog.sh` | Script de monitoramento |
| `/usr/local/bin/post-reboot-diagnosis.sh` | Script de diagnóstico pós-reboot |
