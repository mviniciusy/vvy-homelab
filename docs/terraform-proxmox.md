# Terraform – Infraestrutura como Código no Proxmox

> **Versão:** Maio/2026 | **Autor:** Vinícius Souza

---

## 1. Visão Geral

O **Terraform** está instalado diretamente no host Proxmox para provisionamento de infraestrutura como código (IaC). Ele permite criar e gerenciar containers LXC e VMs do Proxmox de forma declarativa, versionada e reproduzível.

## 2. Instalação

|Item|Valor|
|---|---|
|**Binário**|`/usr/bin/terraform`|
|**Versão**|v1.15.2|
|**Plataforma**|linux_amd64|
|**Instalação**|Via pacote APT (HashiCorp repository)|

## 3. Provider Proxmox

O provider utilizado é o **bpg/proxmox**, que se conecta à API do Proxmox VE:

|Item|Valor|
|---|---|
|**Provider**|`bpg/proxmox`|
|**Versão**|`~> 0.60`|
|**Endpoint**|`https://<HOST_IP>:8006/`|
|**Autenticação**|API Token (`root@pam!terraform`)|
|**Insecure**|`true` (self-signed certificate)|

## 4. Diretório de Trabalho

|Item|Valor|
|---|---|
|**Caminho**|`/root/iac/terraform/`|
|**Arquivos**|`provider.tf`, `main.tf`|

### 4.1 provider.tf

```hcl
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.60"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://<HOST_IP>:8006/"
  api_token = "root@pam!terraform=<TOKEN>"
  insecure  = true
}
```

### 4.2 main.tf (exemplo de uso)

```hcl
resource "proxmox_lxc" "teste" {
  target_node  = "vvy"
  vmid         = 201
  hostname     = "container-teste"
  description  = "Criado e gerenciado por Terraform"
  ostemplate   = "HD-WD500GB:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  unprivileged = true
  cores        = 1
  memory       = 512
  swap         = 256

  rootfs {
    storage = "local-lvm"
    size    = "4G"
  }

  network {
    name    = "eth0"
    bridge  = "vmbr0"
    ip      = "dhcp"
    gw      = "192.168.1.1"
  }

  tags = "teste;iac"
}
```

## 5. Comandos Úteis

| Ação | Comando |
|------|---------|
| Inicializar | `cd ~/iac/terraform && terraform init` |
| Planejar mudanças | `terraform plan` |
| Aplicar mudanças | `terraform apply` |
| Aplicar (auto-aprovar) | `terraform apply -auto-approve` |
| Destruir recursos | `terraform destroy` |
| Ver estado | `terraform state list` |
| Validar config | `terraform validate` |
| Formatar código | `terraform fmt` |

## 6. Observações

- O API Token do Proxmox deve ser criado na GUI: **Datacenter → Permissions → API Tokens**
- O token precisa de privilégios `PVEVMAdmin` no path `/`
- O diretório `~/iac/terraform/` é de testes — mover para repositório Git quando estabilizar
- Templates de OS devem estar disponíveis no storage antes de usar (ex: `HD-WD500GB:vztmpl/`)
