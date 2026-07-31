# BIOS QIYIDA X79 — Configuração e Alterações

**Servidor:** vvy (Proxmox VE 9.2.5)
**Placa-mãe:** QIYIDA X79 (AMI BIOS 4.6.5.4, Project Version X79V3 0.01 x64)
**CPU:** Intel Xeon E5-2470 v2 (10C/20T, 2.40GHz, LGA 1356, Ivy Bridge-EP, 95W TDP)
**RAM:** 24GB DDR3 ECC (16GB Micron channel 1 slot 0 + 8GB Samsung channel 3 slot 0)
**Data da análise:** 31/Jul/2026
**Origem das fotos:** 32 imagens da BIOS transcritas via Gemini

---

## 1. Contexto do Problema

O servidor apresenta **hard freezes** intermitentes desde Mai/2026. Dois padrões:

1. **Sob carga multi-core** (HandBrake 16 cores) — VRM marginal confirmado (Vcore droop −48mV), placa sem heatsink de VRM
2. **Em idle** (31/Jul 06:42, após 1h44 de operação normal) — hipótese primária: ZFS module/userspace mismatch (já desativado)

**Mitigações já aplicadas antes da análise da BIOS:**
- ZFS desativado (rmmod + blacklist + disable services)
- iTCO_wdt reativado com hook permanente
- VM 200 reduzida de 8 → 4 cores
- CT 112 reduzido de 16 → 6 cores
- Heartbeat externo (Oracle VM → Telegram)

**Esta análise da BIOS** visa mitigar a Hipótese 3 (VRM marginal) e eliminar variáveis de transição de energia que podem causar freeze em idle.

---

## 2. Configuração Original da BIOS (antes das alterações)

Transcrição completa dos 32 screenshots da BIOS, organizada por menu.

### Aba: Main
| Campo | Valor |
|---|---|
| BIOS Vendor | American Megatrends |
| Core Version | 4.6.5.4 |
| Compliancy | UEFI 2.3.1; PI 1.2 |
| Project Version | X79V3 0.01 x64 |
| Total Memory | 24576 MB (DDR3) |
| System Language | English |
| System Date | Fri 07/31/2026 |
| Access Level | Administrator |

### Aba: Advanced — Menu Principal

Submenus disponíveis:
- PCI Subsystem Settings
- ACPI Settings
- RTC Configuration
- CPU Configuration
- SATA Configuration
- USB Configuration
- Smart Fan Function
- NCT5532D Super IO Configuration
- NCT5532D HW Monitor
- MISC Features
- Network Stack Configuration
- Realtek PCIe GBE Family Controller (MAC: 22:13:5C:03:6F:51)

### Aba: Advanced > PCI Subsystem Settings

| Campo | Valor original |
|---|---|
| PCI Bus Driver Version | V 2.05.02 |
| Above 4G Decoding | Disabled |
| PCI Latency Timer | 32 PCI Bus Clocks |
| VGA Palette Snoop | Disabled |
| PERR# Generation | Disabled |
| SERR# Generation | Disabled |

Submenus: PCI Express Settings, PCI Express GEN 2 Settings

### Aba: Advanced > PCI Express Settings

| Campo | Valor original |
|---|---|
| Relaxed Ordering | Disabled |
| Extended Tag | Disabled |
| No Snoop | Enabled |
| Maximum Payload | Auto |
| Maximum Read Request | Auto |
| ASPM Support | Disabled (aviso: may cause some PCI-E devices to fail) |
| Extended Synch | Disabled |
| Link Training Retry | 5 |
| Link Training Timeout (uS) | 100 |
| Unpopulated Links | Keep Link ON |
| Restore PCIE Registers | Disabled |

### Aba: Advanced > PCI Express GEN 2 Settings

| Campo | Valor original |
|---|---|
| Completion Timeout | Default |
| ARI Forwarding | Disabled |
| AtomicOp Requester Enable | Disabled |
| AtomicOp Egress Blocking | Disabled |
| IDO Request Enable | Disabled |
| IDO Completion Enable | Disabled |
| LTR Mechanism Enable | Disabled |
| End-End TLP Prefix Blocking | Disabled |
| Target Link Speed | Force to 5.0 GT/s |
| Clock Power Management | Disabled |
| Compliance SOS | Disabled |
| Hardware Autonomous Width | Enabled |
| Hardware Autonomous Speed | Enabled |

### Aba: Advanced > ACPI Settings

| Campo | Valor original |
|---|---|
| Enable ACPI Auto Configuration | Disabled |
| **Enable Hibernation** | **Enabled** ← alterado |
| ACPI Sleep State | S1 only (CPU Stop Cl...) |
| Lock Legacy Resources | Disabled |
| S3 Video Repost | Disabled |

### Aba: Advanced > RTC Configuration

| Campo | Valor original |
|---|---|
| RTC Power On Function | Disabled |

### Aba: Boot

| Campo | Valor original |
|---|---|
| Setup Prompt Timeout | 1 |
| Bootup NumLock State | On |
| Quiet Boot | Disabled |
| Fast Boot | Disabled |
| Boot Option #1 | P0: SWR128G-N01H |
| Boot Option #2 | Windows Boot Manager |
| Boot Option #3 | UEFI OS (P0: SWR128...) |

Submenus: Hard Drive BBS Priorities, CSM16 Parameters, CSM Parameters

### Aba: Security

| Campo | Valor original |
|---|---|
| Administrator Password | (não definido) |
| User Password | (não definido) |

HDD Security: P0: SWR128G-N01H, P2: WDC WD10SPZX, P4: ST1000LM024, P5: WDC WD10SPZX

### Aba: Advanced > CPU Configuration

| Campo | Valor original |
|---|---|
| CPU Speed | 2400 MHz |
| 64-bit | Supported |
| Hyper-threading | Enabled |
| Active Processor Cores | All |
| Limit CPUID Maximum | Disabled |
| Execute Disable Bit | Enabled |
| Hardware Prefetcher | Enabled |
| Adjacent Cache Line Prefetch | Enabled |
| DCU Streamer Prefetcher | Enabled |
| DCU IP Prefetcher | Enabled |
| Intel Virtualization Technology | Enabled |
| PPIN Support | Disabled |

Submenus: Socket 0 CPU Information, CPU Power Management Configuration

### Aba: Advanced > Socket 0 CPU Information

| Campo | Valor |
|---|---|
| CPU | Intel Xeon E5-2470 v2 @ 2.40GHz |
| CPU Signature | 306e4 |
| Microcode Patch | 428 |
| Max CPU Speed | 2400 MHz |
| Min CPU Speed | 1200 MHz |
| Processor Cores | 10 |
| Intel HT Technology | Supported |
| Intel VT-x Technology | Supported |
| Intel SMX Technology | Supported |
| L1 Data Cache | 32 KB x 10 |
| L1 Code Cache | 32 KB x 10 |
| L2 Cache | 256 KB x 10 |
| L3 Cache | 25600 KB (25 MB) |

### Aba: Advanced > CPU Power Management Configuration

| Campo | Valor original | Valor atual |
|---|---|---|
| Power Technology | Custom | Custom |
| EIST | Enabled | Enabled |
| Turbo Mode | Enabled | Enabled |
| P-STATE Coordination | HW_ALL | HW_ALL |
| **CPU C3 Report** | **Disabled** | **Enabled** |
| **CPU C6 report** | **Enabled** | **Enabled** |
| **Package C State limit** | **No Limit** | **No Limit** |
| Energy Performance | Balanced Performance | Balanced Performance |
| Factory long duration power limit | 95 Watts | 95 Watts |
| **Long duration power limit** | **0 (unlimited)** | **95** |
| Factory long duration maintained | 10 s | 10 s |
| **Long duration maintained** | **0 (unlimited)** | **10** |
| Recommended short duration power limit | 1.2 * Long Duration | 1.2 * Long Duration |
| **Short duration power limit** | **0 (unlimited)** | **114** |

### Aba: Advanced > SATA Configuration

| Campo | Valor |
|---|---|
| SATA Port0 | SWR128G-N01H (128.0GB) |
| SATA Port1 | Not Present |
| SATA Port2 | WDC WD10SPZX-3 (1000.2GB) |
| SATA Port3 | Not Present |
| SATA Port4 | ST1000LM024 HN (1000.2GB) |
| SATA Port5 | WDC WD10SPZX-3 (1000.2GB) |
| SATA Mode | AHCI Mode |
| Aggressive Link Power Management | Enabled |
| Hot Plug (Portas 0-5) | All Disabled |
| External SATA (Portas 0-5) | All Disabled |

### Aba: Advanced > NCT5532D Super IO Configuration

| Campo | Valor |
|---|---|
| Super IO Chip | NCT5532D |

Submenu: Serial Port 0 Configuration

### Aba: Advanced > Serial Port 0 Configuration

| Campo | Valor |
|---|---|
| Serial Port | Enabled |
| Device Settings | IO=3F8h; IRQ=4 |
| Change Settings | Auto |

### Aba: Advanced > MISC Feature Settings

| Campo | Valor |
|---|---|
| Onboard Lan | Auto |
| Azalia HD Audio | Enabled |
| Power Loss | Last State |

### Aba: Advanced > Network Stack

| Campo | Valor |
|---|---|
| Network Stack | Disabled |

### Aba: Advanced > Realtek PCIe GBE Family Controller

| Campo | Valor |
|---|---|
| Driver Name | Realtek UEFI UNDI Driver |
| Driver Version | 2.056 |
| Driver Released Date | 2021/04/30 |
| Device Name | Realtek PCIe GBE Family |
| PCI Slot | 05:00:00 |
| MAC Address | 22:13:5C:03:6F:51 |

### Aba: Chipset — Menu Principal

Submenus: North Bridge, South Bridge, ME Subsystem

### Aba: Chipset > North Bridge (Memory & IOH)

| Campo | Valor original |
|---|---|
| Compatibility RID | Enabled |
| Total Memory | 24576 MB (DDR3) |
| Current Memory Mode | Independent |
| Current Memory Speed | 1600 MHz |
| Mirroring | Not Possible |
| Sparing | Not Possible |
| Memory Mode | Independent |
| DRAM RAPL BWLIMIT | 1 |
| Perfmon and DFX devices | HIDE |
| DRAM RAPL MODE | Disabled |
| Enforce POR | Disabled |
| Pdg Length | Short |
| DDR Speed | Force DDR3 1600 |
| Channel Interleaving | Auto |
| Rank Interleaving | Auto |
| Patrol Scrub | Enabled |
| Demand Scrub | Enabled |

Submenus: IOH Configuration, QPI Configuration, DIMM Information

### Aba: Chipset > North Bridge > Memory Configuration (continuação)

| Campo | Valor |
|---|---|
| Data Scrambling | Enabled |
| Device Tagging | Disabled |
| Rank Margin | Disabled |
| Thermal Throttling | CLTT |
| OLTT Peak BW % | 50 |
| Altitude | 300 M |
| Serial Message Debug Level | Minimum |

### Aba: Chipset > North Bridge > QPI Configuration

| Campo | Valor original | Valor atual |
|---|---|---|
| Current QPI Link Speed | Slow | Slow |
| Current QPI Link Freq | Unknown | Unknown |
| Isoc | Auto | Auto |
| MesegEn | Auto | Auto |
| QPI Link Speed Mode | Fast | Fast |
| **QPI Link Frequency Select** | **Auto** | **8.0 GT/s** |
| QPI Link0s | Disabled | Disabled |
| QPI Link0p | Disabled | Disabled |
| QPI Link1 | Enabled | Enabled |
| **Snoop Mode** | **Auto** | **Home Snoop** |

### Aba: Chipset > North Bridge > IOH Configuration (Intel VT for Directed I/O)

| Campo | Valor |
|---|---|
| Intel(R) I/OAT | Enabled |
| DCA Support | Enabled |
| VGA Priority | Offboard |
| TargetVGA | Vga From CPU 0 |
| Gen3 Equalization WA's | Enabled |
| Gen3 Equalization Fail WA | Disabled |
| Gen3 Equalization Phase 2/3 WA | Disabled |
| Gen3 Equalization Redoing WA | Disabled |
| IOH Resource Selection Type | Auto |
| No Snoop Optimization | VC1 |
| MMIOH Size | 64G |
| MMCFG BASE | 0x80000000 |

IOH 0 PCIe port Bifurcation Control:
| Porta | Config | Link Speed |
|---|---|---|
| IOU1 | x4x4 | PORT 1A: GEN3, PORT 1B: GEN3 |
| IOU2 | x16 | PORT 2A: GEN3 |
| IOU3 | x16 | PORT 3A: GEN3 |

IOH 0 PCIe port Data Direct I/O Control:
| Porta | Estado |
|---|---|
| PORT 0A | Disabled |
| PORT 1A | Enabled |
| PORT 1B | Enabled |
| PORT 2A | Enabled |
| PORT 3A | Enabled |

### Aba: Chipset > Intel(R) VT-d

| Campo | Valor |
|---|---|
| Coherency Support | Disabled |
| ATS Support | Enabled |

### Aba: Chipset > ME Subsystem Configuration

| Campo | Valor |
|---|---|
| ME Version | 7.1.13.1088 |
| ME Subsystem | Enabled |
| ME Temporary Disable | Disabled |
| End of Post Message | Enabled |
| Execute MEBx | Enabled |

### Aba: Chipset > South Bridge Configuration

| Campo | Valor |
|---|---|
| PCH Name | HM70 |
| PCH Stepping | 04/C1 |
| PCH Compatibility RID | Disabled |
| SMBus Controller | Enabled |
| SW SMI Timer | Auto |
| GbE Controller | Enabled |
| Wake on Lan from S5 | Enabled |
| USB WakeOnDev insertion | Disabled |
| Restore AC Power Loss | Last State |
| SLP_S4 Assertion Stretch Enable | Enabled |
| SLP_S4 Assertion Width | 4-5 Seconds |
| Deep Sx | Disabled |
| Onboard SATA RAID Oprom/Driver | Enabled |
| Azalia HD Audio | Enabled |
| Azalia internal HDMI codec | Disabled |
| High Precision Timer | Enabled |

Submenus: PCI Express Ports Configuration, USB Configuration

### Aba: Chipset > South Bridge > PCI Express Ports Configuration

| Porta | Estado | PME SCI |
|---|---|---|
| PCI Express Port 1 | Auto | Disabled |
| PCI Express Port 2 | Auto | Disabled |
| Onboard Lan | Auto | Disabled |
| PCI Express Port 4 | Auto | Disabled |
| PCI Express Port 5 | Auto | Disabled |
| PCI Express Port 6 | Auto | Disabled |
| PCI Express Port 7 | Auto | Disabled |
| PCI Express Port 8 | Auto | Disabled |
| PCIe Sub Decode | Disabled | — |
| DMI Vc1 Control | Enabled | — |
| DMI Vcp Control | Enabled | — |
| DMI Vcm Control | Enabled | — |

### Aba: Chipset > South Bridge > USB Configuration

| Campo | Valor |
|---|---|
| All USB Devices | Enabled |
| EHCI Controller 1 | Enabled |
| EHCI Controller 2 | Enabled |
| USB Port 0-13 | Enabled (todos) |

### Aba: Boot > CSM16 Parameters

| Campo | Valor |
|---|---|
| CSM16 Module Version | 07.71 |
| GateA20 Active | Upon Request |
| Option ROM Messages | Force BIOS |
| INT19 Trap Response | Immediate |

### Aba: Boot > CSM Parameters

| Campo | Valor |
|---|---|
| Launch CSM | Enabled |
| Boot option filter | UEFI and Legacy |
| Launch PXE OpROM policy | Do not launch |
| Launch Storage OpROM policy | Legacy only |
| Launch Video OpROM policy | Legacy only |
| Other PCI device ROM priority | Legacy OpROM |

---

## 3. Alterações Realizadas (31/Jul/2026)

### Prioridade 1 — Limitar potência (mitigar VRM)

Objetivo: limitar o pico de corrente que satura o VRM sem heatsink, evitando colapso de tensão (Vcore droop) sob carga multi-core.

| Setting | Valor original | Valor atual | Motivo |
|---|---|---|---|
| `Advanced > CPU Power Management > Long duration power limit` | 0 (unlimited) | **95** (TDP do E5-2470 v2) | Limita potência contínua ao TDP nominal |
| `Advanced > CPU Power Management > Short duration power limit` | 0 (unlimited) | **114** (1.2 x TDP) | Permite burst curto mas limitado |
| `Advanced > CPU Power Management > Long duration maintained` | 0 (unlimited) | **10** (segundos) | Janela de burst controlada de 10s |

### Prioridade 2 — Desativar Hibernação

Objetivo: reduzir complexidade de ACPI em servidor 24/7 que não hiberna.

| Setting | Valor original | Valor atual | Motivo |
|---|---|---|---|
| `Advanced > ACPI Settings > Enable Hibernation` | Enabled | **Disabled** | Servidor Proxmox não hiberna; reduz variáveis ACPI |

### Prioridade 3 — C-States (Fase A: transições suaves)

Objetivo: permitir transições de C-state consistentes (C3 estava disabled, C6 enabled — configuração incompleta que afeta idle pós-carga).

| Setting | Valor original | Valor atual | Motivo |
|---|---|---|---|
| `Advanced > CPU Power Management > CPU C3 Report` | Disabled | **Disabled** | Opção C: C-states controlados via BIOS (C0 only), intel_idle.max_cstate=1 removido do GRUB |

> **Fase B (APLICADA 31/Jul):** C3 e C6 desabilitados, Package C State = C0 na BIOS. `intel_idle.max_cstate=1` removido do GRUB. C-states agora controlados pela BIOS (C0 only), não pelo kernel cmdline. Consome ~20W a mais em idle mas elimina 100% das transições de C-state como variável.

### QPI — Fixar frequência e modo snoop

Objetivo: eliminar flutuação de QPI que pode causar hard freeze em idle. A BIOS reportava `Current QPI Link Speed: Slow` com `Mode: Fast` — inconsistência. Snoop Mode em Auto pode alternar entre modos durante transições de carga/idle.

| Setting | Valor original | Valor atual | Motivo |
|---|---|---|---|
| `Chipset > North Bridge > QPI Configuration > QPI Link Frequency Select` | Auto | **8.0 GT/s** | Frequência nativa do E5-2470 v2 (LGA 1356 Ivy Bridge-EP); elimina flutuação |
| `Chipset > North Bridge > QPI Configuration > Snoop Mode` | Auto | **Home Snoop** | Previsível, não flutua; mais usado em single-socket Ivy Bridge-EP |

> Early Snoop = mais agressivo (menos latência) mas gera mais variações de corrente. Home Directory Snoop = mais complexo, sem benefício em single-socket. Auto = evitar (pode alternar).

---

## 4. Configuração ATUAL da BIOS (resumo pós-alterações)

### CPU Power Management (estado atual)
```
Power Technology:           Custom
EIST:                       Enabled
Turbo Mode:                 Enabled
P-STATE Coordination:       HW_ALL
CPU C3 Report:              Disabled     ← ALTERADO (Opção C: era Disabled, foi Enabled brevemente, voltou para Disabled)
CPU C6 report:               Disabled    ← ALTERADO (era Enabled)
Package C State limit:      C0          ← ALTERADO (era No Limit)
Energy Performance:         Balanced Performance
Long duration power limit:  95           ← ALTERADO (era 0)
Short duration power limit: 114          ← ALTERADO (era 0)
Long duration maintained:   10           ← ALTERADO (era 0)
```

### ACPI (estado atual)
```
Enable ACPI Auto Configuration:  Disabled
Enable Hibernation:              Disabled  ← ALTERADO (era Enabled)
ACPI Sleep State:                S1 only
```

### QPI (estado atual)
```
Isoc:                       Auto
MesegEn:                    Auto
QPI Link Speed Mode:        Fast
QPI Link Frequency Select:  8.0 GT/s    ← ALTERADO (era Auto)
QPI Link0s:                 Disabled
QPI Link0p:                 Disabled
QPI Link1:                  Enabled
Snoop Mode:                 Home Snoop  ← ALTERADO (era Auto)
```

### Tudo que NÃO foi alterado (mantido do original)
- PCI Subsystem Settings (Above 4G Decoding: Disabled, ASPM: Disabled)
- PCI Express GEN 2 Settings (Target Link Speed: 5.0 GT/s, Clock Power Management: Disabled)
- CPU Configuration (Hyper-threading: Enabled, Active Cores: All, VT-x: Enabled, Prefetchers: todos Enabled)
- SATA Configuration (AHCI Mode, ALPM: Enabled)
- Memory Configuration (Independent mode, DDR3 1600, Patrol/Demand Scrub: Enabled)
- USB (tudo Enabled)
- Boot (Fast Boot: Disabled, Quiet Boot: Disabled, CSM: Enabled)
- South Bridge (WoL: Enabled, Restore AC Power Loss: Last State)
- IOH Bifurcation (IOU1: x4x4, IOU2: x16, IOU3: x16, todos GEN3)
- ME Subsystem (Enabled, Default)
- RTC Power On Function: Disabled
- Network Stack: Disabled
- Serial Port 0: Enabled
- MISC Features (Onboard Lan: Auto, HD Audio: Enabled, Power Loss: Last State)
- VT-d (Coherency: Disabled, ATS: Enabled)
- High Precision Timer: Enabled

---

## 5. Plano de Validação

### Verificação pós-reboot (executar imediatamente após o vvy voltar)
```bash
# 1. Confirmar kernel
ssh root@<HOST_IP> 'uname -r'
# Esperado: 6.17.13-21-pve (vvy subiu no kernel -21 no reboot de 31/Jul)

# 2. iTCO_wdt carregou?
ssh root@<HOST_IP> 'cat /sys/class/watchdog/watchdog0/identity'
# Esperado: iTCO_wdt

# 3. VM 200 com 4 cores?
ssh root@<HOST_IP> 'qm config 200 | grep cores'
# Esperado: cores: 4

# 4. Kernel clean?
ssh root@<HOST_IP> 'journalctl -b 0 -k | grep -iE "tsc|watchdog|zfs|iTCO"'
# Esperado: sem erros ZFS, iTCO_wdt carregado, TSC warp normal

# 5. Vcore idle após power limits
ssh root@<HOST_IP> 'sensors | grep -i vcore'
# Comparar com leitura anterior (idle era 1040mV)

# 6. C-states ativos no Linux
ssh root@<HOST_IP> 'cat /sys/devices/system/cpu/cpu0/cpuidle/state*/name'
# Esperado: POLL, C1 (C0 only via BIOS; intel_idle.max_cstate removido)

# 7. QPI frequency confirmada
ssh root@<HOST_IP> 'dmesg -T | grep -i "qpi\|quickpath"'
# Verificar se reporta 8.0 GT/s
```

### Observação 24-48h
- Heartbeat Oracle VM deve reportar uptime crescente sem alertas de offline
- Healthcheck unificado (cronjob Hermes a cada 2h) deve reportar OK
- Se freeze em idle persistir: aplicar Fase B (desabilitar C3/C6/Package C State)
- Se freeze sob carga persistir: power limits não foram suficientes — considerar undervolt adicional ou troca de placa-mãe

### Decisão de hardware (após observação)
| Cenário | Ação |
|---|---|
| Freeze para (ZFS era causa) | Reativar ZFS com kernel -21 (módulo 2.4.3). Sem troca de hardware. |
| Freeze para com 4 vCPUs (QEMU era causa) | Investigar bug pve-qemu-kvm 11.0.2-2. Manter 4 cores. |
| Freeze persiste (VRM degradação) | BIOS undervolt/underclock adicional ou trocar placa-mãe |
| Troca de placa considerada | Machinist X99 MR9A-H + E5-2630 v4 + DDR4. VRM 6+1 com heatsink. |

---

## 6. Reversão

Todas as alterações são reversíveis via BIOS:

| Alteração | Como reverter |
|---|---|
| Long/Short duration power limit | Voltar para 0 (unlimited) |
| Long duration maintained | Voltar para 0 |
| Enable Hibernation | Voltar para Enabled |
| CPU C3 Report | Voltar para Disabled |
| QPI Link Frequency Select | Voltar para Auto |
| Snoop Mode | Voltar para Auto |
| `intel_idle.max_cstate=1` no GRUB | Re-adicionar em `/etc/default/grub` + `update-grub` |
| CPU C6 Report | Voltar para Enabled |
| Package C State limit | Voltar para No Limit |

## 7. Referências

- Contexto completo do problema: `vvy-hard-freeze-contexto-completo.md` (incluído no hermes-export.tar.gz)
- Skill de diagnóstico: `proxmox/references/proxmox-stability-diagnosis.md`
- Documentação master do servidor: `/root/1 Documentação Privada/PROXMOX_VVY.md` (no host vvy)
- Fotos originais da BIOS: pasta `bios/` (32 arquivos .jpg)
- Transcrição original via Gemini: `BIOS.txt` (esta pasta)
