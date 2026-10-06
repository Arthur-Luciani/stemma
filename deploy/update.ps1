<#
.SYNOPSIS
  Atualiza o Stemma para outra release, com backup, migration e rollback automático
  (ADR 0007). Rode como administrador.

.DESCRIPTION
  1. baixa o zip da release e confere o SHA256 (ou usa -ZipPath);
  2. extrai em <Root>\releases\vX.Y.Z e cria o venv dela (com o serviço ainda no ar);
  3. para o serviço, faz backup do banco (API de backup do SQLite) e roda as migrations;
  4. aponta <Root>\current para a release nova, sobe o serviço e espera o /health
     responder com a versão nova;
  5. se algo falhar depois do serviço parar: restaura o banco, volta o `current`,
     sobe a versão anterior e confere o /health dela;
  6. mantém as 3 releases mais novas (nunca apaga a atual nem a anterior).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File C:\stemma\current\deploy\update.ps1
.EXAMPLE
  ... update.ps1 -Version v1.3.1
.EXAMPLE
  ... update.ps1 -Rollback       # volta para a release anterior
.EXAMPLE
  ... update.ps1 -YtDlpOnly      # só atualiza o yt-dlp do venv atual

.PARAMETER Version
  Tag de destino (ex.: v1.3.1). Padrão: a última release.
.PARAMETER ZipPath
  Pacote local (stemma-vX.Y.Z.zip, com o .sha256 ao lado) em vez de baixar.
.PARAMETER Rollback
  Volta para a release instalada imediatamente anterior, desfazendo as migrations dela.
.PARAMETER YtDlpOnly
  Atualiza só o yt-dlp do venv atual e reinicia o serviço.
.PARAMETER SimulateFailure
  Teste do rollback: faz a checagem do /health da versão nova falhar.
#>
[CmdletBinding(DefaultParameterSetName = 'Update')]
param(
    [Parameter(ParameterSetName = 'Update')][string]$Version,
    [Parameter(ParameterSetName = 'Update')][string]$ZipPath,
    [Parameter(ParameterSetName = 'Update')][switch]$SimulateFailure,
    [Parameter(ParameterSetName = 'Rollback', Mandatory)][switch]$Rollback,
    [Parameter(ParameterSetName = 'YtDlp', Mandatory)][switch]$YtDlpOnly,
    [string]$Root = 'C:\stemma',
    [string]$ServiceId = 'stemma',
    [int]$HealthTimeoutSec = 180
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'StemmaDeploy.psm1') -Force

Assert-Admin
$envValues = Import-DotEnv -Path (Join-Path $Root '.env')
$port = Get-StemmaPort $envValues
$current = Get-CurrentRelease -Root $Root
if (-not $current) { throw "Nenhuma release em $Root\current. Rode o install.ps1." }
$currentTag = Split-Path -Leaf $current
$storageRoot = if ($envValues.Contains('STORAGE_ROOT')) { $envValues['STORAGE_ROOT'] } else { 'D:\stemma-data' }

function Restart-AndCheck([string]$Tag) {
    Stop-StemmaService -ServiceId $ServiceId
    Start-StemmaService -ServiceId $ServiceId
    return Wait-StemmaHealth -Port $port -ExpectedVersion $Tag -TimeoutSec $HealthTimeoutSec
}

function New-BackupPath([string]$Label) {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    return Join-Path $storageRoot "backups\stemma-$Label-$stamp.db"
}

# --- só o yt-dlp ---------------------------------------------------------------
if ($YtDlpOnly) {
    Write-Step "Atualizando o yt-dlp de $currentTag"
    Invoke-Native -FilePath 'uv' -Arguments @('pip', 'install', '--python', (Get-ReleasePython $current), '--upgrade', 'yt-dlp[default]')
    if (-not (Restart-AndCheck $currentTag)) { throw 'O serviço não voltou depois de atualizar o yt-dlp. Veja os logs.' }
    Write-Host '    O próximo update.ps1 volta o yt-dlp para a versão do uv.lock da release.'
    return
}

# --- rollback manual -----------------------------------------------------------
if ($Rollback) {
    $previous = Get-PreviousRelease -Root $Root -Current $currentTag
    if (-not $previous) { throw "Não há release instalada anterior a $currentTag." }
    $targetHead = Get-AlembicHead -ReleaseDir $previous.Path
    Stop-StemmaService -ServiceId $ServiceId
    Write-Step 'Backup do banco'
    Invoke-StemmaCli -ReleaseDir $current -Arguments @('backup', '--dest', (New-BackupPath "$currentTag-rollback"))
    if ($targetHead -ne (Get-AlembicHead -ReleaseDir $current)) {
        Write-Step "Desfazendo migrations até $targetHead"
        Invoke-Alembic -ReleaseDir $current -Arguments @('downgrade', $targetHead)
    }
    Set-CurrentRelease -Root $Root -ReleaseDir $previous.Path
    Start-StemmaService -ServiceId $ServiceId
    if (-not (Wait-StemmaHealth -Port $port -ExpectedVersion $previous.Name -TimeoutSec $HealthTimeoutSec)) {
        throw "Rollback para $($previous.Name) feito, mas o /health não confirmou. Veja os logs em $Root\logs."
    }
    Write-Step "Voltou para $($previous.Name)"
    return
}

# --- atualização -----------------------------------------------------------------
$package = Get-StemmaPackage -Root $Root -Version $Version -ZipPath $ZipPath
$target = $package.Tag
if ($target -eq $currentTag) {
    Write-Step "Já está na $target"
    return
}

Write-Step "Atualizando $currentTag → $target"
$release = Expand-StemmaPackage -Root $Root -Zip $package.Zip -Tag $target
Sync-ReleaseEnvironment -ReleaseDir $release

Stop-StemmaService -ServiceId $ServiceId
$backup = $null
try {
    $customDb = $envValues.Contains('DATABASE_URL') -and $envValues['DATABASE_URL']
    if (-not $customDb -and -not (Test-Path -LiteralPath (Join-Path $storageRoot 'stemma.db'))) {
        Write-Host '    Banco ainda não existe: sem backup.'
    }
    else {
        Write-Step 'Backup do banco'
        $backup = New-BackupPath "$currentTag-to-$target"
        Invoke-StemmaCli -ReleaseDir $release -Arguments @('backup', '--dest', $backup)
    }
    Write-Step 'Migrations'
    Invoke-Alembic -ReleaseDir $release -Arguments @('upgrade', 'head')
    Set-CurrentRelease -Root $Root -ReleaseDir $release
    Start-StemmaService -ServiceId $ServiceId
    $expected = if ($SimulateFailure) { 'v0.0.0' } else { $target }
    if ($SimulateFailure) { Write-Warning 'SimulateFailure: a checagem do /health vai falhar de propósito.' }
    if (-not (Wait-StemmaHealth -Port $port -ExpectedVersion $expected -TimeoutSec $HealthTimeoutSec)) {
        throw "A $target não confirmou a versão no /health."
    }
}
catch {
    $reason = $_.Exception.Message
    Write-Warning "Falhou: $reason"
    Write-Step "Rollback para $currentTag"
    Stop-StemmaService -ServiceId $ServiceId
    if ($backup -and (Test-Path -LiteralPath $backup)) {
        Write-Step 'Restaurando o banco do backup'
        Invoke-StemmaCli -ReleaseDir $current -Arguments @('restore', '--src', $backup)
    }
    Set-CurrentRelease -Root $Root -ReleaseDir $current
    Start-StemmaService -ServiceId $ServiceId
    if (Wait-StemmaHealth -Port $port -ExpectedVersion $currentTag -TimeoutSec $HealthTimeoutSec) {
        Write-Error "Atualização para $target falhou ($reason). Voltou para $currentTag." -ErrorAction Continue
    }
    else {
        Write-Error "Atualização falhou ($reason) e o rollback para $currentTag não confirmou no /health. Veja $Root\logs." -ErrorAction Continue
    }
    exit 1
}

Write-Step 'Limpando releases antigas'
$names = @(Get-InstalledReleases -Root $Root | ForEach-Object { $_.Name })
foreach ($name in (Select-ReleasesToRemove -Names $names -Keep 3 -Protect @($target, $currentTag))) {
    Write-Host "    removendo $name"
    Remove-Item -LiteralPath (Join-Path $Root "releases\$name") -Recurse -Force
}
Write-Step "Stemma $target no ar"
