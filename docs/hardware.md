# Hardware

> **Versão:** Abril/2026 | **Autor:** Vinícius Souza

---

## 2. Hardware do Host (PC SERVIDOR)

### Processador

|Modelo|Núcleos|Threads|Clock Base|Clock Max|Cache L3|
|---|---|---|---|---|---|
|Intel Xeon E5-2470 v2|10|20 (HT)|2.40 GHz|3.2 GHz|25 MiB|

### Memória RAM

| Total | Tipo | Slot 1 | Slot 2 | ECC |
| ----- | -------------- | ---------------- | --------------- | --------------- |
| 24 GB | DDR3 1600 MT/s | 16 GB Registered | 8 GB Registered | Multi-bit Ativo |

### Armazenamento de Sistema (SSDs – ambos 128 GB)

|Disco|Capacidade|Uso|
|---|---|---|
|**sda** (SATA SSD)|128 GB|Instalação do Proxmox, Swap e containers base (local / local-lvm)|
|**nvme128** (NVMe M.2)|128 GB|Pool exclusivo para containers e VMs de alta performance|

---

## 3. Hardware Cliente e Infraestrutura de Rede

### PC Principal: ACER NITRO V15

|Componente|Especificação|
|---|---|
|CPU|Intel Core i5 13420H|
|RAM|24 GB DDR5 5200 MHz|
|Armazenamento|2x SSD 512 GB|

### Rede

|Conexão|Velocidade|Roteadores|
|---|---|---|
|Fibra Óptica|450 Mbps|ZTE F670L (Principal) + MERCUSYS F670L (Secundário via cabo)|
