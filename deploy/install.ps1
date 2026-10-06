<#
.SYNOPSIS
  Primeira instalação do Stemma como serviço do Windows (rode como administrador).

.DESCRIPTION
  Baixa a release do GitHub (ou usa -ZipPath), confere o SHA256, extrai em
  <Root>\releases\vX.Y.Z, cria o venv da release (uv sync), cria <Root>\.env,
  aponta <Root>\current, registra o serviço (WinSW, conta do usuário), configura
  o `tailscale serve` na 443 e espera o /health. Detalhes em docs/operacao.md.

.EXAMPLE
  # Baixe e extraia o zip da release e rode o install.ps1 de dentro dele:
  powershell -ExecutionPolicy Bypass -File .\stemma-v1.3.0\deploy\install.ps1

.PARAMETER Version
  Tag a instalar (ex.: v1.3.0). Padrão: a última release.
.PARAMETER ZipPath
  Pacote local (stemma-vX.Y.Z.zip, com o .sha256 ao lado) em vez de baixar.
.PARAMETER Root
  Raiz da instalação. Padrão: C:\stemma.
.PARAMETER DataRoot
  STORAGE_ROOT gravado no .env novo. Padrão: D:\stemma-data.
.PARAMETER ServiceId
  Nome do serviço. Padrão: stemma (outro nome só para ensaio).
.PARAMETER Port
  Porta do uvicorn gravada no .env novo. Padrão: 8000.
.PARAMETER SkipTailscale
  Não mexe no `tailscale serve` (ensaio).
#>
param(
    [string]$Version,
    [string]$ZipPath,
    [string]$Root = 'C:\stemma',
    [string]$DataRoot = 'D:\stemma-data',
    [string]$ServiceId = 'stemma',
    [int]$Port = 8000,
    [switch]$SkipTailscale
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'StemmaDeploy.psm1') -Force

Assert-Admin
if (Get-Service -Name $ServiceId -ErrorAction SilentlyContinue) {
    throw "O serviço '$ServiceId' já existe. Para atualizar use o update.ps1."
}

Write-Step 'Pré-requisitos'
$required = @('uv', 'ffmpeg')
if (-not $SkipTailscale) { $required += 'tailscale' }
foreach ($cmd in $required) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "Comando '$cmd' não encontrado no PATH." }
}
if (-not ((Get-Command deno -ErrorAction SilentlyContinue) -or (Get-Command node -ErrorAction SilentlyContinue))) {
    Write-Warning 'Nem deno nem node no PATH: o yt-dlp pode falhar no YouTube (o /health vai acusar).'
}

foreach ($dir in $Root, (Join-Path $Root 'releases'), (Join-Path $Root 'logs'), (Join-Path $Root 'winsw'), $DataRoot) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}

$envFile = Join-Path $Root '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Step "Criando $envFile"
    $lines = @(
        '# Configuração de produção do Stemma (variáveis em .env.example da release).',
        "PORT=$Port",
        "STORAGE_ROOT=$DataRoot",
        'LOG_LEVEL=INFO'
    )
    [IO.File]::WriteAllLines($envFile, $lines, [Text.UTF8Encoding]::new($false))
}
$envValues = Import-DotEnv -Path $envFile
$port = Get-StemmaPort $envValues

$package = Get-StemmaPackage -Root $Root -Version $Version -ZipPath $ZipPath
Write-Step "Extraindo $($package.Tag)"
$release = Expand-StemmaPackage -Root $Root -Zip $package.Zip -Tag $package.Tag
Sync-ReleaseEnvironment -ReleaseDir $release

Write-Step 'Migrations'
Invoke-Alembic -ReleaseDir $release -Arguments @('upgrade', 'head')
Set-CurrentRelease -Root $Root -ReleaseDir $release

Write-Step "Registrando o serviço $ServiceId"
$winswDir = Join-Path $Root 'winsw'
$exe = Join-Path $winswDir "$ServiceId.exe"
Get-WinSW -Dest $exe
New-ServiceXml -Template (Join-Path $release 'deploy\stemma-service.xml') -ServiceId $ServiceId `
    -Dest (Join-Path $winswDir "$ServiceId.xml")
Write-Host '    O WinSW vai pedir a conta do Windows que roda o serviço (a sua, ex.: .\Dell)'
Write-Host '    e a senha, e se pode conceder "logon como serviço" (responda y).'
Invoke-Native -FilePath $exe -Arguments @('install', '/p')
Start-StemmaService -ServiceId $ServiceId

if (-not (Wait-StemmaHealth -Port $port -ExpectedVersion $package.Tag)) {
    throw "O serviço subiu mas o /health não confirmou a versão. Veja os logs em $(Join-Path $Root 'logs')."
}

if (-not $SkipTailscale) {
    Write-Step 'tailscale serve (HTTPS na 443 → 127.0.0.1)'
    Invoke-Native -FilePath 'tailscale' -Arguments @('serve', '--bg', '--https=443', "http://127.0.0.1:$port")
    tailscale serve status
}

Write-Step "Stemma $($package.Tag) instalado em $Root"
