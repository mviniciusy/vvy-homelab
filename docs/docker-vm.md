# VM Debian para Docker

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 14. VM Debian para Docker (docker-host)

|Parâmetro|Valor|
|---|---|
|ID da VM|200|
|Nome|debian|
|vCPUs|8|
|RAM|4 GB|
|Disco de sistema|32 GB (storage `nvme128`)|
|Disco de dados|100 GB (storage `HD-WD500GB`, montado em `/mnt/dados`)|
|Sistema operacional|Debian 12.12 (Bookworm), sem interface gráfica|
|IP|`<DOCKER_VM_IP>` (DHCP, reservado via roteador)|
|MAC address|`<DOCKER_VM_MAC>`|
|Acesso SSH|`debian@<DOCKER_VM_IP>`|
|Docker|versão estável (via repositório oficial)|
|Portainer|`https://<DOCKER_VM_IP>:9443` (interface web de gerenciamento Docker)|
|Data de criação|Abril/2026|
