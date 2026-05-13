$HOST_IP = "192.168.1.104"
$USER = "root"

# Opcional: derruba sessões ssh anteriores para evitar duplicidade
taskkill /F /IM ssh.exe 2>$null

Start-Process -WindowStyle Hidden -FilePath "ssh" -ArgumentList "-o ControlMaster=no -o ControlPath=none -L 9119:localhost:9119 $USER@$HOST_IP -N"
Start-Process -WindowStyle Hidden -FilePath "ssh" -ArgumentList "-o ControlMaster=no -o ControlPath=none -L 8642:localhost:8642 $USER@$HOST_IP -N"

Write-Host "Túneis SSH independentes criados." -ForegroundColor Green