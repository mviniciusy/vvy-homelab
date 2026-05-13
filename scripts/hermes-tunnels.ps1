# Hermes Tunnels - Atalho para criar túneis SSH para o container Hermes Agent
# Uso: Abrir PowerShell como Administrador e executar: .\hermes-tunnels.ps1
# Ou colocar em C:\Scripts\Hermes\hermes-tunnels.ps1 e criar atalho

$HOST_IP = "192.168.1.104"
$USER = "root"

Write-Host "=== Hermes Tunnels ===" -ForegroundColor Cyan
Write-Host "Criando tuneis SSH para o container Hermes Agent ($HOST_IP)" -ForegroundColor Yellow
Write-Host ""

# Tunnel para o Dashboard Hermes (porta 9119)
Write-Host "[1/2] Dashboard Hermes: ssh -L 9119:localhost:9119 $USER@$HOST_IP -N" -ForegroundColor Green
Start-Process -WindowStyle Hidden -FilePath "ssh" -ArgumentList "-L 9119:localhost:9119 $USER@$HOST_IP -N"

Write-Host "[2/2] Tunnel criado! Acesse http://localhost:9119 no navegador." -ForegroundColor Green
Write-Host ""
Write-Host "Para encerrar, feche esta janela ou use: taskkill /F /IM ssh.exe" -ForegroundColor Yellow
Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")