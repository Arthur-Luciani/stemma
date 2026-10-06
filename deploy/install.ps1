<#
.SYNOPSIS
  Primeira instalação do Stemma como serviço do Windows, por linha de comando (rode como
  administrador). O caminho normal é o instalador (Stemma-Setup-vX.Y.Z.exe); este script faz
  o mesmo sem as telas e serve para ensaio e diagnóstico.

.DESCRIPTION
  Baixa uv, FFmpeg, Deno e Python para <Root>\tools (SHA256 fixado), semeia o cache do uv com
  o do usuário (hardlink), baixa a release (ou usa -ZipPath) e confere o SHA256, extrai em
  <Root>\releases\vX.Y.Z, cria o venv, o .env e o serviço (WinSW, LocalSystem), espera o
  /health e configura o `tailscale serve` na 443. Detalhes em docs/operacao.md.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\stemma-v1.4.0\deploy\install.ps1 -ZipPath .\stemma-v1.4.0.zip

.PARAMETER Version
  Tag a instalar (ex.: v1.4.0). Padrão: a última release.
.PARAMETER ZipPath
  Pacote local (stemma-vX.Y.Z.zip, com o .sha256 ao lado) em vez de baixar.
.PARAMETER Root
  Raiz da instalação. Padrão: C:\stemma.
.PARAMETER DataRoot
  STORAGE_ROOT gravado no .env novo. Padrão: D:\stemma-data (C:\stemma-data se não houver D:).
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
    [string]$DataRoot,
    [string]$ServiceId = 'stemma',
    [int]$Port = 8000,
    [switch]$SkipTailscale
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'StemmaDeploy.psm1') -Force

Assert-Admin
Invoke-StemmaInstall -Root $Root -DataRoot $DataRoot -Port $Port -ServiceId $ServiceId `
    -Version $Version -ZipPath $ZipPath -SkipTailscale:$SkipTailscale | Out-Null
