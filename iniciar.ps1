# The Dragon Tool - lanzador. Uso (PowerShell):
#   irm https://raw.githubusercontent.com/TU_USUARIO/TheDragonTool/main/iniciar.ps1 | iex
# Descarga la herramienta a %LOCALAPPDATA%\TheDragonTool y la abre como administrador.
$ErrorActionPreference = 'Stop'
$base = 'https://raw.githubusercontent.com/TU_USUARIO/TheDragonTool/main'
$dir  = Join-Path $env:LOCALAPPDATA 'TheDragonTool'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $stamp = [guid]::NewGuid().ToString('N')
    Invoke-WebRequest -UseBasicParsing -Uri "${base}/TheDragonTool.ps1?v=$stamp" -OutFile (Join-Path $dir 'TheDragonTool.ps1')
    try { Invoke-WebRequest -UseBasicParsing -Uri "${base}/logo.png?v=$stamp" -OutFile (Join-Path $dir 'logo.png') } catch { }
    Unblock-File -Path (Join-Path $dir 'TheDragonTool.ps1') -ErrorAction SilentlyContinue
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"' + (Join-Path $dir 'TheDragonTool.ps1') + '"'))
} catch {
    Write-Host "No se pudo iniciar The Dragon Tool: $($_.Exception.Message)" -ForegroundColor Red
}
