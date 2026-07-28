# Wake-on-LAN (WoL) — Reinício Remoto do vvy

> Adicionado em Julho/2026

---

## 1. Visão Geral

Sistema para acordar e reiniciar o servidor vvy (casa) remotamente, a partir da Oracle Cloud VM ou de qualquer dispositivo externo. Não depende do Tailscale estar ativo — o magic packet viaja pela internet até o roteador, que faz port forwarding para a LAN.

| Item | Valor |
|---|---|
| MAC do vvy (nic0) | `22:13:5c:03:6f:51` |
| IP local do vvy | `<HOST_IP>` |
| IP público de casa | Dinâmico (DDNS: `vvy-server.ddns.net`) |
| Porta WoL | 9 UDP |
| WoL ativo na placa | `Wake-on: g` (magic packet) |
| Interface física | `nic0` (bridge `vmbr0`) |

## 2. Como Funciona

```
Dispositivo externo (Oracle VM / celular)
    → magic packet UDP porta 9
        → IP público de casa (vvy-server.ddns.net)
            → Roteador (port forwarding porta 9 → 192.168.1.255 broadcast)
                → Magic packet chega na LAN
                    → vvy (nic0) recebe e acorda (se estiver em sleep/S3)
```

### Por que não usar Tailscale para WoL

O WoL opera na **camada 2 (Ethernet)** — o magic packet precisa chegar na interface física (`nic0`). O Tailscale é **camada 3 (IP)** e entrega o pacote na interface virtual `tailscale0`, que não acorda a placa de rede física. Além disso, se o vvy estiver travado, o Tailscale também estar offline.

| Método | Funciona? | Motivo |
|---|---|---|
| Roteador (port forwarding WAN → broadcast LAN) | Sim | Magic packet chega na interface física `nic0` |
| Tailscale (unicast para <HOST_IP>:9) | Não | Pacote chega em `tailscale0`, não acorda a placa física |
| Tailscale (broadcast 192.168.1.255:9) | Não | Broadcast não atravessa túnel Tailscale |
| LAN local (broadcast direto) | Sim | Dispositivo na mesma rede envia broadcast |

## 3. Configuração do Roteador

O roteador de casa tem port forwarding configurado:

| Campo | Valor |
|---|---|
| Porta externa | 9 UDP |
| Endereço de transmissão | `192.168.1.255` (broadcast) |
| IP do dispositivo | `vvy-server.ddns.net` (DDNS) |

> O roteador recebe o magic packet na WAN (porta 9) e faz broadcast para `192.168.1.255` na LAN. Todos os dispositivos recebem, mas só o vvy com MAC `22:13:5c:03:6f:51` que suporta WoL acorda.

## 4. ddclient — DNS Dinâmico (NO-IP)

O IP público de casa é dinâmico. O `ddclient` no vvy mantém o `vvy-server.ddns.net` atualizado automaticamente.

| Item | Valor |
|---|---|
| Pacote | `ddclient` 3.11.2 (apt) |
| Config | `/etc/ddclient.conf` |
| Serviço | `ddclient.service` (systemd, habilitado no boot) |
| Intervalo | 300s (5 min) |
| Protocolo | NO-IP (`protocol=noip`) |
| Server | `dynupdate.noip.com` |
| Detecção de IP | `use=web, web=checkip.dyndns.org` |
| Login (DDNS Key) | `<NOIP_DDNS_KEY_USER>` |
| Senha (DDNS Key) | `<NOIP_DDNS_KEY_PASSWORD>` |
| Hostname | `vvy-server.ddns.net` |

> **Nota**: O NO-IP usa DDNS Key (credenciais separadas da senha de login do site). A DDNS Key foi gerada no painel my.noip.com > Account Settings > Dynamic DNS > Create Key.

### /etc/ddclient.conf

```conf
# /etc/ddclient.conf — NO-IP DDNS via DDNS Key
daemon=300
ssl=yes
use=web, web=checkip.dyndns.org, web-skip="Current IP Address"
protocol=noip
server=dynupdate.noip.com
login=<NOIP_DDNS_KEY_USER>
password=<NOIP_DDNS_KEY_PASSWORD>
vvy-server.ddns.net
```

### Comandos de gestão

```bash
# Status do serviço
systemctl status ddclient

# Reiniciar
systemctl restart ddclient

# Verificar IP atual do DDNS
dig +short vvy-server.ddns.net @8.8.8.8

# Atualização manual (forçar)
ddclient -daemon=0 -force

# Logs
journalctl -u ddclient --since "1 hour ago"
```

## 5. Scripts na Oracle VM

A Oracle VM tem scripts prontos para acordar e reiniciar o vvy remotamente.

### /opt/wol/wake-vvy.sh

Acorda o vvy enviando magic packet para o IP público de casa (via DDNS). Não depende do Tailscale.

```bash
#!/bin/bash
# Acorda o servidor vvy (casa) via Wake-on-LAN
# Envia magic packet para o IP publico de casa (vvy-server.ddns.net:9)
# O roteador faz port forwarding da porta 9 para <HOST_IP> na LAN
# Funciona mesmo se o vvy estiver travado (nao depende de Tailscale estar ativo)

MAC_VVY="22:13:5c:03:6f:51"
DDNS="vvy-server.ddns.net"
IP_VVY_TAILSCALE="<TAILSCALE_VVV_IP>"

# Resolver o IP atual do DDNS (usar Google DNS para evitar cache)
IP_ATUAL=$(dig +short $DDNS @8.8.8.8 | head -1)

if [ -z "$IP_ATUAL" ]; then
    echo "ERRO: Nao foi possivel resolver $DDNS"
    exit 1
fi

echo "IP atual de casa: $IP_ATUAL"

# Enviar magic packet
python3 -c "
import socket
mac = bytes.fromhex(\"22135c036f51\")
magic = b\"\xff\" * 6 + mac * 16
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.sendto(magic, (\"$IP_ATUAL\", 9))
s.close()
"

# Aguardar vvy responder via Tailscale
echo "Aguardando vvy responder via Tailscale ($IP_VVY_TAILSCALE)..."
for i in $(seq 1 12); do
    sleep 10
    if ping -c1 -W2 $IP_VVY_TAILSCALE > /dev/null 2>&1; then
        echo "vvy esta acordado! (respondeu em $((i*10))s)"
        exit 0
    fi
    echo "  Tentativa $i/12..."
done

echo "AVISO: vvy nao respondeu apos 120s."
exit 1
```

### /opt/wol/reboot-vvy.sh

Reinicia o vvy via SSH (Tailscale). O vvy precisa estar acordado.

```bash
#!/bin/bash
# Reinicia o servidor vvy via SSH (Tailscale)
# Uso: /opt/wol/reboot-vvy.sh (vvy precisa estar acordado)
#      /opt/wol/reboot-vvy.sh --wake (envia WoL primeiro)

IP_VVY_TAILSCALE="<TAILSCALE_VVV_IP>"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

if ! ping -c1 -W2 $IP_VVY_TAILSCALE > /dev/null 2>&1; then
    if [ "$1" = "--wake" ]; then
        /opt/wol/wake-vvy.sh
    else
        echo "ERRO: vvy offline. Use --wake para enviar WoL primeiro."
        exit 1
    fi
fi

ssh $SSH_OPTS root@$IP_VVY_TAILSCALE "reboot"
echo "Reboot enviado. Aguarde ~2-3 min."
```

### Como usar

```bash
# SSH na Oracle VM
ssh -i ~/.ssh/oracle-vm.key ubuntu@<ORACLE_PUBLIC_IP>

# Acordar o vvy
/opt/wol/wake-vvy.sh

# Reiniciar o vvy (já acordado)
/opt/wol/reboot-vvy.sh

# Acordar E reiniciar
/opt/wol/reboot-vvy.sh --wake
```

## 6. Configuração WoL no vvy

O WoL já estava configurado no vvy (confirmado em Jul/2026):

```bash
# Verificar suporte WoL
ethtool nic0 | grep -i wake
# Supports Wake-on: pumbg
# Wake-on: g        (g = magic packet ativo)

# Habilitar WoL (se necessário)
ethtool -s nic0 wol g

# Persistir após reboot (adicionar em /etc/network/interfaces ou systemd)
# post-up ethtool -s nic0 wol g
```

## 7. App WoL no Celular

O app de WoL no celular (Android) tem dois perfis configurados:

| Perfil | MAC | IP/Host | Como funciona |
|---|---|---|---|
| LOCAL | `22:13:5c:03:6f:51` | `<HOST_IP>` | Direto na LAN (Wi-Fi de casa) |
| REMOTO | `22:13:5c:03:6f:51` | `vvy-server.ddns.net` | Via internet → roteador → port forwarding |

## 8. Limitações

| Cenário | WoL funciona? |
|---|---|
| vvy em sleep/S3 | Sim — placa de rede mantém energia standby |
| vvy totalmente desligado (power off) | Depende da BIOS — placa mãe QIYIDA X79 precisa manter energia na porta de rede |
| vvy travado (hard freeze) | WoL não acorda — precisa de reboot físico. Mas o magic packet chega na placa |
| Roteador reiniciado | Sim — port forwarding persiste na config do roteador |
| DDNS desatualizado | Não — precisa do ddclient rodando para manter IP correto |

## 9. Troubleshooting

### Magic packet não chega no vvy

1. Verificar se o DDNS está atualizado: `dig +short vvy-server.ddns.net @8.8.8.8`
2. Comparar com IP público real: `curl -s ifconfig.me` (executado no vvy)
3. Se diferente, forçar atualização: `ddclient -daemon=0 -force`
4. Verificar port forwarding do roteador (porta 9 UDP → 192.168.1.255)

### WoL não acorda o vvy

1. Verificar se WoL está ativo: `ethtool nic0 | grep Wake-on` (deve mostrar `g`)
2. Verificar se a placa de rede suporta WoL: `Supports Wake-on: pumbg` (o `g` indica suporte a magic packet)
3. Se o vvy foi totalmente desligado (não sleep), a BIOS precisa manter energia na placa de rede

### ddclient falha com badauth

1. Verificar credenciais no `/etc/ddclient.conf` (DDNS Key, não senha de login)
2. Testar manualmente: `curl -s -u "<NOIP_DDNS_KEY_USER>:<NOIP_DDNS_KEY_PASSWORD>" "https://dynupdate.noip.com/nic/update?hostname=vvy-server.ddns.net&myip=$(curl -s ifconfig.me)"`
3. Se retornar `nochg <IP>`, está funcionando
