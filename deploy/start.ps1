<#
.SYNOPSIS
  Sobe o Stemma de produção. Chamado pelo serviço (WinSW); não precisa rodar à mão.

.DESCRIPTION
  Carrega <Root>\.env, aplica as migrations e inicia o uvicorn (1 worker, 127.0.0.1)
  com o Python do venv desta release, servindo o frontend\dist dela.
  Para testar no console: powershell -File C:\stemma\current\deploy\start.ps1

.PARAMETER Root
  Raiz da instalação (onde ficam .env, releases\ e current\). Padrão: C:\stemma.
#>
param([string]$Root = 'C:\stemma')

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'StemmaDeploy.psm1') -Force

# A release é a pasta deste script (current\deploy\.. ou releases\vX\deploy\..).
$release = Split-Path -Parent $PSScriptRoot
# uv, FFmpeg e Deno de <Root>	ools no PATH (o serviço roda como LocalSystem; ADR 0014).
Set-StemmaToolEnv -Root $Root
$envValues = Import-DotEnv -Path (Join-Path $Root '.env')
$port = Get-StemmaPort $envValues
# O frontend servido é sempre o desta release.
$env:SERVE_FRONTEND_DIR = Join-Path $release 'frontend\dist'
$env:PYTHONUTF8 = '1'

Write-Step "Stemma em $release (porta $port)"
Invoke-Alembic -ReleaseDir $release -Arguments @('upgrade', 'head')

# 1 worker só: o EventBus é em memória (ADR 0002).
Invoke-Native -FilePath (Get-ReleasePython $release) -WorkingDirectory (Join-Path $release 'backend') -Arguments @(
    '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', "$port", '--workers', '1',
    '--proxy-headers', '--forwarded-allow-ips', '127.0.0.1'
)
