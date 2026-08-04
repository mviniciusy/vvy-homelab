# Samba (host vvy)

> **Documento de referencia interna.** Nao copiar para repo publico (arquivo no .gitignore do privado).
> Mantenha este doc atualizado sempre que houver mudanca no smb.conf, shares, ou comportamento do Samba.
> A skill `proxmox-samba` (CT 104) referencia este arquivo como source of truth.

## Informacoes do servico

| Item | Valor |
|------|-------|
| Pacote | samba 4.22.10-Debian |
| Daemon | smbd + nmbd |
| Status | enabled, active |
| Config | /etc/samba/smb.conf |
| Logs | /var/log/samba/log.smbd, /var/log/samba/log.%m (por cliente) |
| Inicio | systemd (smbd.service, nmbd.service) |

## Shares configurados

| Share (Windows) | Path no servidor | Auth | Guest | Locking | Bind mounts (CTs) |
|-----------------|-------------------|------|-------|---------|--------------------|
| [HD-WD-500GB] | /mnt/pve/HD-WD500GB | root (auth) | nao | strict=no, oplocks=no | CT100 (raiz) |
| [HD-WD500GB] | /mnt/pve/HD-WD500GB/Dados-WD500GB | force user=root | sim | strict=no, oplocks=no | CT104 (Tiktok/work), CT105 (Dados) |
| [HD-SEA-1TB] | /mnt/pve/HD-SEA1TB | root (auth) | nao | strict=no, oplocks=no | CT100 |
| [HD-WD-1TB] | /mnt/HD-WD-1TB | root (auth) | nao | strict=no, oplocks=no | CT100, CT105 |
| [root] | /root | root only | nao | padrao | nenhum |

## Shares duplicados (nao unificados)

Existem dois shares apontando para o mesmo disco WD-500GB com paths diferentes:

- **[HD-WD-500GB]** aponta para `/mnt/pve/HD-WD500GB/` (raiz do disco). Windows ve: `Dados-WD500GB/` e `Tiktok/` na raiz.
- **[HD-WD500GB]** aponta para `/mnt/pve/HD-WD500GB/Dados-WD500GB/` (subpasta). Windows ve direto o conteudo de Dados-WD500GB.

**Por que nao unificar:** CTs dependem dos paths atuais.
- CT 100: mount point `/mnt/HD-WD500GB` <- bind de `/mnt/pve/HD-WD500GB` (raiz)
- CT 104: mount point `/mnt/tiktok` <- bind de `/mnt/pve/HD-WD500GB/Dados-WD500GB/Tiktok/work`
- CT 105: mount point `/mnt/wd500gb` <- bind de `/mnt/pve/HD-WD500GB/Dados-WD500GB`

Unificar os shares exigiria revisar todos os bind mounts e testar cada CT.

## Parametros globais relevantes

```ini
[global]
   workgroup = WORKGROUP
   socket options = TCP_NODELAY IPTOS_LOWDELAY
   server role = standalone server
   map to guest = bad user
   obey pam restrictions = yes
```

## Parametros de share (padrao aplicado em todos shares de disco)

```ini
   strict locking = no
   oplocks = no
   level2 oplocks = no
```

**Por que:** Sem `oplocks = no`, o Windows Explorer cacheia listings de diretorios de rede e nao atualiza quando arquivos sao criados no servidor. O usuario precisa fechar e reabrir o Explorer ou usar `dir` no cmd para ver o conteudo real. Com `oplocks = no` em todos shares, o Samba nao concede leases de cache e o Explorer sempre busca o listing fresco.

## Historico de mudancas

### 2026-08-01

- Adicionado `strict locking = no`, `oplocks = no`, `level2 oplocks = no` nos shares `[HD-WD-500GB]`, `[HD-SEA-1TB]`, `[HD-WD-1TB]` (nao tinham).
- Movido `socket options = TCP_NODELAY IPTOS_LOWDELAY` da secao `[HD-WD500GB]` para `[global]` (era parametro global declarado dentro de share, gerava warning no log).
- Backup: `/etc/samba/smb.conf.bak.20260801_160122`.
- Motivo: arquivos criados no servidor nao apareciam no Windows Explorer mesmo apos F5. Cache de oplock impedia refresh do listing.
