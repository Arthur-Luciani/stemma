<#
.SYNOPSIS
  Atualiza o Stemma para outra release, com backup, migration e rollback automático
  (ADR 0007). Rode como administrador. O instalador da versão nova faz o mesmo; este script
  fica para diagnóstico, rollback manual e o yt-dlp.

.DESCRIPTION
  1. confere as ferramentas de <Root>\tools; baixa o zip da release e confere o SHA256 (ou usa -ZipPath);
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
  ... update.ps1 -Version v1.4.1
.EXAMPLE
  ... update.ps1 -Rollback       # volta para a release anterior
.EXAMPLE
  ... update.ps1 -YtDlpOnly      # só atualiza o yt-dlp do venv atual

.PARAMETER Version
  Tag de destino (ex.: v1.4.1). Padrão: a última release.
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
try {
    if ($YtDlpOnly) {
        Update-StemmaYtDlp -Root $Root -ServiceId $ServiceId -HealthTimeoutSec $HealthTimeoutSec
        Write-Host '    O próximo update volta o yt-dlp para a versão do uv.lock da release.'
    }
    elseif ($Rollback) {
        Invoke-StemmaRollback -Root $Root -ServiceId $ServiceId -HealthTimeoutSec $HealthTimeoutSec | Out-Null
    }
    else {
        Invoke-StemmaUpdate -Root $Root -ServiceId $ServiceId -Version $Version -ZipPath $ZipPath `
            -SimulateFailure:$SimulateFailure -HealthTimeoutSec $HealthTimeoutSec | Out-Null
    }
}
catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}
