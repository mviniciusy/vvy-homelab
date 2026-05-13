# Ansible – Configuração como Código no Proxmox

> **Versão:** Maio/2026 | **Autor:** Vinícius Souza

---

## 1. Visão Geral

O **Ansible** está instalado diretamente no host Proxmox para automação de configuração e orquestração de tarefas nos containers LXC, VMs e no próprio host. Ele complementa o Terraform (que provisiona infraestrutura) com configuração pós-criação.

## 2. Instalação

|Item|Valor|
|---|---|
|**Binário**|`/usr/bin/ansible`|
|**Versão Core**|2.19.4|
|**Python module**|`/usr/lib/python3/dist-packages/ansible`|
|**Instalação**|Via pacote APT (Debian Trixie)|

### Paths do Ansible

|Item|Caminho|
|---|---|
|Config file|Nenhum (usar `-c` ou `ANSIBLE_CONFIG`)|
|Module search path|`/root/.ansible/plugins/modules`, `/usr/share/ansible/plugins/modules`|
|Collection location|`/root/.ansible/collections`, `/usr/share/ansible/collections`|

## 3. Diretório de Trabalho

|Item|Valor|
|---|---|
|**Caminho**|`/root/iac/ansible/`|
|**Arquivos**|`hosts.ini`, `playbook.yml`|

> ⚠️ Os arquivos estão vazios atualmente — são placeholders para início da configuração.

## 4. Inventário (hosts.ini)

O inventário deve listar todos os containers e VMs do homelab:

```ini
[proxmox_host]
vvy ansible_host=<HOST_IP>

[lxc_containers]
nextcloud ansible_host=<NEXTCLOUD_IP>
pihole    ansible_host=<PIHOLE_IP>
ollama    ansible_host=<OLLAMA_IP>
n8n       ansible_host=<N8N_IP>
hermes    ansible_host=<HERMES_IP>
qbit      ansible_host=<QBITTORRENT_IP>
zabbix    ansible_host=<ZABBIX_IP>
grafana   ansible_host=<GRAFANA_IP>

[vms]
docker-host ansible_host=<DOCKER_VM_IP>

[all:vars]
ansible_user=root
ansible_ssh_common_args=-o StrictHostKeyChecking=no
```

## 5. Comandos Úteis

| Ação | Comando |
|------|---------|
| Ping em todos os hosts | `cd ~/iac/ansible && ansible all -i hosts.ini -m ping` |
| Executar playbook | `ansible-playbook -i hosts.ini playbook.yml` |
| Executar playbook (dry-run) | `ansible-playbook -i hosts.ini playbook.yml --check` |
| Executar comando ad-hoc | `ansible all -i hosts.ini -a "uptime"` |
| Listar hosts do inventário | `ansible all -i hosts.ini --list-hosts` |
| Verificar sintaxe do playbook | `ansible-playbook -i hosts.ini playbook.yml --syntax-check` |

## 6. Integração com o Ecossistema

- **Terraform + Ansible:** O Terraform provisiona containers/VMs, o Ansible configura-os após a criação
- **Proxmox host:** Pode ser gerenciado diretamente via Ansible (módulos `community.general.proxmox_*`)
- **LXC containers:** Configuração via SSH ou `pct exec` (módulo `community.general.pct`)
- **Diretório `~/iac/`:** Pasta de testes — mover para repositório Git quando estabilizar

## 7. Observações

- O Ansible roda no host Proxmox e se conecta aos containers via SSH
- Containers LXC precisam ter SSH habilitado para conexão direta
- Alternativamente, usar `ansible_connection=community.general.pct` para containers LXC sem SSH
- Configurar `ansible.cfg` no diretório de trabalho para definir defaults (inventory, roles_path, etc.)
