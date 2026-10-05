# The Dragon Tool - lanzador. Uso (PowerShell):
#   irm https://raw.githubusercontent.com/adrianalexander1611/TheDragonTool/main/iniciar.ps1 | iex
# Descarga SIEMPRE la ultima version (por numero de commit, sin cache) a
# %LOCALAPPDATA%\TheDragonTool y la abre como administrador.

# ---- Cambia SOLO estas 3 lineas ----
$usuario = 'TU_USUARIO'
$repo    = 'TheDragonTool'
$rama    = 'main'
# ------------------------------------

$ErrorActionPreference = 'Stop'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $dir = Join-Path $env:LOCALAPPDATA 'TheDragonTool'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $destino = Join-Path $dir 'TheDragonTool.ps1'

    # 1) Averigua el commit mas reciente: la URL con el codigo del commit nunca esta en cache
    $ref = $main
    try {
        $info = Invoke-RestMethod -UseBasicParsing -Headers @{ 'User-Agent' = 'DragonTool' } -Uri "https://api.github.com/repos/$adrianalexander1611/$TheDragonTool/commits/$main"
        $ref = $info.sha
        Write-Host ("Ultima version en GitHub: " + $ref.Substring(0, 7) + " (" + $info.commit.committer.date + ")") -ForegroundColor Cyan
    } catch {
        Write-Host "No se pudo consultar el ultimo commit; se usa la rama '$main' (puede tardar unos minutos en actualizarse)." -ForegroundColor Yellow
    }
    $base = "https://raw.githubusercontent.com/$adrianalexander1611/$TheDragonTool/$ref"

    # 2) Descarga (si la copia anterior esta abierta/bloqueada, avisa)
    try { if (Test-Path $destino) { Remove-Item $destino -Force } }
    catch { throw "La herramienta anterior sigue abierta. Cierrala (y cualquier ventana de PowerShell suya) y vuelve a ejecutar el comando." }
    Invoke-WebRequest -UseBasicParsing -Uri "$base/TheDragonTool.ps1" -OutFile $destino
    try { Invoke-WebRequest -UseBasicParsing -Uri "$base/logo.png" -OutFile (Join-Path $dir 'logo.png') } catch { }
    Unblock-File -Path $destino -ErrorAction SilentlyContinue
    $tam = [math]::Round((Get-Item $destino).Length / 1KB)
    Write-Host "Descargado TheDragonTool.ps1 ($tam KB). Abriendo..." -ForegroundColor Green

    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"' + $destino + '"'))
} catch {
    Write-Host "No se pudo iniciar The Dragon Tool: $($_.Exception.Message)" -ForegroundColor Red
}
