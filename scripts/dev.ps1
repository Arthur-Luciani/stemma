<#
.SYNOPSIS
  Sobe o ambiente de desenvolvimento do Stemma: backend (uvicorn --reload, porta 8010)
  e frontend (Vite, porta 5183, com proxy de /api, /ws e /health para o backend).

.DESCRIPTION
  Ctrl+C encerra os dois. Para abrir no celular via Tailscale (uma vez só):
    tailscale serve --bg --https=5183 http://127.0.0.1:5183
  e acesse https://<maquina>.<tailnet>.ts.net:5183
  Para desfazer: tailscale serve --https=5183 off

.PARAMETER SkipInstall
  Não roda `uv sync` nem `npm ci` antes de subir.
#>
param([switch]$SkipInstall)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repo 'backend'
$frontendDir = Join-Path $repo 'frontend'

foreach ($cmd in 'uv', 'npm') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "Comando '$cmd' não encontrado no PATH."
    }
}

if (-not $SkipInstall) {
    Write-Host '==> uv sync (api + dev)' -ForegroundColor Cyan
    # --inexact: não remove o grupo `pipeline` (torch/demucs) se ele estiver instalado.
    uv sync --project $backendDir --inexact --group api --group dev
    if ($LASTEXITCODE -ne 0) { throw 'uv sync falhou.' }

    if (-not (Test-Path (Join-Path $frontendDir 'node_modules'))) {
        Write-Host '==> npm ci' -ForegroundColor Cyan
        Push-Location $frontendDir
        try { npm ci; if ($LASTEXITCODE -ne 0) { throw 'npm ci falhou.' } } finally { Pop-Location }
    }
}

Write-Host '==> backend em http://127.0.0.1:8010' -ForegroundColor Cyan
$backend = Start-Process -FilePath 'uv' -WorkingDirectory $backendDir -NoNewWindow -PassThru `
    -ArgumentList 'run', 'uvicorn', 'app.main:app', '--reload', '--host', '127.0.0.1', '--port', '8010'

try {
    Write-Host "==> frontend em http://127.0.0.1:5183" -ForegroundColor Cyan
    Push-Location $frontendDir
    npm run dev
}
finally {
    Pop-Location
    if (-not $backend.HasExited) {
        Write-Host '==> encerrando backend' -ForegroundColor Cyan
        # /T derruba também o processo filho do --reload.
        taskkill /PID $backend.Id /T /F | Out-Null
    }
}
