# Oracle Cloud Free Tier — VM vvy-vnic

> **Versão:** Julho/2026 | **Autor:** Vinícius Souza

---

## 1. Visão Geral

VM na Oracle Cloud Free Tier (São Paulo) que atua como extensão remota do homelab Proxmox vvy. Servidor de suporte e testes com arquitetura Arm (aarch64).

|Parâmetro|Valor|
|---|---|
|Hostname|`vvy-vnic`|
|Plataforma|Oracle Cloud Infrastructure (OCI)|
|Region|São Paulo (sa-saopaulo-1)|
|Compartimento|mviniciusy (raiz)|
|Tenancy|<OCI_TENANCY_EMAIL>|
|Data de criação|26 de julho de 2026|

---

## 2. Hardware

|Recurso|Especificação|
|---|---|
|Shape|`VM.Standard.A1.Flex` (Arm Ampere)|
|CPU|2x Neoverse-N1 (aarch64)|
|RAM|12 GB|
|Swap|0 B|
|Disco|200 GB (`/dev/sda`)|
|Virtualização|KVM (QEMU)|
|Firmware|UEFI 1.6.6|

### Particionamento

```
sda       200G  disk
├─sda1    199G  part /            (ext4)
├─sda15   99M   part /boot/efi    (vfat)
└─sda16   923M  part /boot        (ext4)
```

---

## 3. Sistema Operacional

|Campo|Valor|
|---|---|
|OS|Ubuntu 24.04.4 LTS (Noble Numbat)|
|Kernel|`6.17.0-1018-oracle` (aarch64)|
|Arquitetura|arm64 / aarch64|
|Timezone|UTC — pendente ajustar para `America/Sao_Paulo`|
|Cloud-init|done (completo)|
|Oracle Cloud Agent|ativo (snap)|

---

## 4. Rede

### IPs

|Tipo|IP|Observação|
|---|---|---|
|IP público|`<ORACLE_PUBLIC_IP>`|Efêmero — pode mudar se a VM for reiniciada|
|IP privado|`<ORACLE_PRIVATE_IP>/24`|VCN vvy-vcn, subnet-publica|
|Gateway|`10.0.0.1`||
|DNS|`127.0.0.53` (systemd-resolved)|Search domain: `vvyvcn.oraclevcn.com`|
|MAC|`<ORACLE_VM_MAC>`||
|Interface|`enp0s6`|MTU 9000 (jumbo frames)|

### VCN — Oracle Cloud

|Campo|Valor|
|---|---|
|Nome|`vvy-vcn`|
|CIDR|`<ORACLE_VCN_CIDR>`|
|Subnet|`subnet-publica` (`<ORACLE_SUBNET_CIDR>`) — pública|
|Route Table|`Default Route Table for vvy-vcn`|
|Internet Gateway|`ig-quick-action-IGW`|
|Route rule|`0.0.0.0/0` -> Internet Gateway|

### Security List — Ingress

|Source|Protocolo|Porta|Descrição|
|---|---|---|---|
|0.0.0.0/0|TCP|22|SSH|
|0.0.0.0/0|ICMP|3,4|Destino Inacessível: Fragmentação|
|<ORACLE_VCN_CIDR>|ICMP|3|Destino Inacessível|

> ICMP echo (ping) não liberado no Security List.

### Security List — Egress

|Destination|Protocolo|Observação|
|---|---|---|
|0.0.0.0/0|All|Todo tráfego de saída liberado|

---

## 5. Acesso

### SSH (internet)

```bash
ssh -i /root/.ssh/oracle-vm.key ubuntu@<ORACLE_PUBLIC_IP>
```

|Item|Valor|
|---|---|
|Usuário|`ubuntu` (UID 1001)|
|Autenticação|Chave SSH (RSA) + senha (cloud-init)|
|Senha|`<ORACLE_VM_PASSWORD>` (definida via cloud-init)|
|Porta|22|

### Chaves SSH

|Item|Caminho|
|---|---|
|Chave privada (CT 104)|`/root/.ssh/oracle-vm.key`|
|Chave privada (servidor vvy)|`/mnt/pve/HD-WD500GB/Dados-WD500GB/Oracle/ssh-key-2026-07-25.key`|
|Chave do console serial (servidor vvy)|`/mnt/pve/HD-WD500GB/Dados-WD500GB/Oracle/ssh-key-2026-07-26.key`|

---

## 6. Firewall Interno (iptables INPUT)

|#|Target|Protocolo|Match|Observação|
|---|---|---|---|---|
|1|ACCEPT|icmp|—|Inserido manualmente|
|2|ACCEPT|tcp|dpt:22|Inserido manualmente|
|3|ACCEPT|all|state RELATED,ESTABLISHED|Oracle default|
|4|ACCEPT|icmp|—|Oracle default|
|5|ACCEPT|all|—|Oracle default|
|6|ACCEPT|tcp|state NEW dpt:22|Oracle default|
|7|REJECT|all|—|reject-with icmp-host-prohibited|

---

## 7. Software

|Software|Estado|
|---|---|
|Docker|NÃO instalado|
|Snap|instalado (oracle-cloud-agent, core18, snapd)|
|cloud-init|completo|
|oracle-cloud-agent|ativo (snap)|

---

## 8. Cloud-Init

Configuração aplicada na criação:

```yaml
#cloud-config
ssh_pwauth: true
chpasswd:
  list: |
    ubuntu:<ORACLE_VM_PASSWORD>
  expire: false
```

---

## 9. Histórico de Problemas

### Problema 1 — SSH inacessível

|Item|Detalhe|
|---|---|
|Sintoma|Porta 22 timed out, ping 100% packet loss|
|Causa raiz|Route Table da VCN sem regra `0.0.0.0/0` -> Internet Gateway|
|Correção|Criar IG + route rule via quick action "Conectar sub-rede pública à internet"|

### Problema 2 — Console serial sem login

|Item|Detalhe|
|---|---|
|Sintoma|Console serial pede login mas nenhum usuário tem senha|
|Causa raiz|Imagem Ubuntu da Oracle usa autenticação por chave apenas|
|Correção|Recriar VM com cloud-init definindo senha para `ubuntu`|

---

## 10. Proximos Passos

- [ ] Hardening: desabilitar PasswordAuthentication
- [ ] Timezone: `America/Sao_Paulo`
- [ ] Instalar Docker + ferramentas
- [ ] Configurar Tailscale
- [ ] Limpar regras iptables duplicadas
- [ ] Configurar IP reservado
- [ ] Anti-idle: cron heartbeat
- [ ] Configurar UFW
