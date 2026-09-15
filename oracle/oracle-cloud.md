# Oracle Cloud — VM vvy-vnic

> **Versão:** Setembro/2026 (shape 4 OCPU / 24 GB, Pay-As-You-Go) | **Autor:** Vinícius Souza

---

## 1. Visão Geral

VM na Oracle Cloud (São Paulo, conta Pay-As-You-Go) que atua como extensão remota do homelab Proxmox vvy. Servidor de suporte e testes com arquitetura Arm (aarch64).

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
|OCPU|4x Neoverse-N1 (aarch64)|
|RAM|24 GB|
|Billing|Always Free expandido — teto atual do A1 Flex e 4 OCPU / 24 GB gratis (conta PAYG, shape dentro do free)|
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
|Kernel|`6.17.0-1020-oracle` (aarch64)|
|Arquitetura|arm64 / aarch64|
|Timezone|America/Sao_Paulo (-03)|
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

## 4.5 Console OCI por API (oci-cli)

Gerenciamento da nuvem sem browser: Security List, reserva de IP, shape, leitura de estado da VCN.

| Item | Valor |
|---|---|
| OCI CLI | venv `/opt/oci-venv`, bin `/usr/local/bin/oci` (3.92.1) |
| Config | `/root/.oci/config` (perfil DEFAULT) |
| Chave privada | `/root/.oci/oci_api_key.pem` |
| PEM + docs das chaves | host vvy: `2 Oracle/API KEY/` (FORA do git) |
| Region | `sa-saopaulo-1` |
| Tenancy OCID | `<OCI_TENANCY_OCID>` |
| User OCID | `<OCI_USER_OCID>` |
| Fingerprint (chave vigente) | `<OCI_API_FINGERPRINT>` |
| Instância `vvy-oracle-server` | `<OCI_INSTANCE_OCID>` |
| Default Security List (vvy-vcn) | `<OCI_SECLIST_OCID>` |
| Subnet publica | `<OCI_SUBNET_OCID>` |
| VNIC | `<OCI_VNIC_OCID>` |

Comandos de exemplo:

```bash
oci compute instance list --compartment-id $TENANCY -o table
oci network security-list get --security-list-id $SL > sl.json
# editar JSON (full replace!) e aplicar:
oci network security-list update --security-list-id $SL \
  --ingress-security-rules file:///root/sl_rules.json --force
```

> **Pitfalls:** (1) `update` substitui TODAS as ingress rules — sempre GET → editar → UPDATE. (2) `--force` por extenso (`-O` nao existe na 3.92.1). (3) Porta fica aninhada em `tcp-options`/`udp-options`; destination-port-range em branco no console = TODAS as portas. (4) API key so funciona apos ser ANEXADA ao usuario no console (download sem confirmar = 401). (5) A PEM do console e PKCS#8 — `file` diz "OpenSSH private key" e engana; fingerprint derivavel com `openssl pkey -in k.pem -pubout -outform DER | openssl md5 -c`.

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

Verificado Set/2026 — regras atuais (netfilter-persistent):

|#|Target|Protocolo|Match|Observação|
|---|---|---|---|---|
|1|ts-input|—|—|Cadeia do Tailscale|
|2–3|ACCEPT|icmp / tcp|dpt:22|Regras manuais (legado)|
|4–7|ACCEPT|mixed|RELATED,ESTABLISHED, icmp, all, NEW dpt:22|Oracle default|
|8–9|ACCEPT|tcp|dpt:443, dpt:80|Vaultwarden/Caddy|
|10|REJECT|all|—|reject-with icmp-host-prohibited|
|11–16|ufw-before/after-…|—|—|Chains orfas do UFW (ja removido — inofensivas, podem ser limpas)|
|17–21|duplicatas|—|—|Bloco duplicado das regras Oracle (persistido em dobro — sem impacto funcional)|

> UFW **não** está instalado. O catch-all REJECT fica na linha 10; novas portas exigem `iptables -I INPUT <n<10>` + `netfilter-persistent save`.

---

## 7. Software

Verificado Set/2026:

|Software|Versão|Estado|
|---|---|---|
|Docker|29.6.2|instalado, ativo|
|Docker Compose|v5.3.1|plugin|
|Tailscale|1.102.2|conectado, `--accept-routes`|
|fail2ban|1.0.2|jail sshhd ativo|
|Containers|vaultwarden + caddy|rodando (healthy)|
|Snap|—|oracle-cloud-agent ativo|
|cloud-init|—|completo|

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
- [x] Timezone: `America/Sao_Paulo` (feito)
- [x] Instalar Docker + ferramentas (feito)
- [x] Configurar Tailscale (feito)
- [ ] Limpar regras iptables duplicadas + chains orfas do UFW
- [ ] Configurar IP reservado (atual e efemero)
- [x] Anti-idle: cron heartbeat (feito — atenção: PAYG reduz risco de reclaim, mas anti-idle mantem utilidade de monitoramento)
- [x] Avaliar servidor de jogo (Project Zomboid — ver secao Proximos Projetos)

> **NUNCA instalar UFW** — conflita com iptables-persistent da Oracle (ver skill oracle-cloud).
