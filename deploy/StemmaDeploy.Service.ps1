# StemmaDeploy: serviço do Windows (WinSW) e /health.
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

# WinSW 2.12.0 (x64), conferido pelo SHA256 antes de usar.
$script:WinSWUrl = 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe'
$script:WinSWSha256 = '05b82d46ad331cc16bdc00de5c6332c1ef818df8ceefcd49c726553209b3a0da'

# --- serviço e /health ----------------------------------------------------------

function Wait-StemmaHealth {
    <#
      Espera o /health responder com a versão esperada (e, com -ExpectedYtDlp, com esse
      yt-dlp). Devolve $true/$false.
    #>
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [string]$ExpectedYtDlp,
        [int]$TimeoutSec = 180,
        [int]$IntervalSec = 2
    )
    $expected = $ExpectedVersion.TrimStart('v')
    $ytdlp = if ($ExpectedYtDlp) { ConvertTo-YtDlpVersion $ExpectedYtDlp } else { $null }
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = 'sem resposta'
    do {
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5
            $ytdlpOk = (-not $ytdlp) -or ((ConvertTo-YtDlpVersion "$($health.ytdlp)") -eq $ytdlp)
            if ($health.version -eq $expected -and $ytdlpOk) {
                Write-Host "    /health: versão $($health.version), status $($health.status), gpu $($health.gpu), yt-dlp $($health.ytdlp)"
                return $true
            }
            $last = "versão $($health.version), yt-dlp $($health.ytdlp)"
        }
        catch { $last = $_.Exception.Message }
        Start-Sleep -Seconds $IntervalSec
    } while ((Get-Date) -lt $deadline)
    Write-Warning "/health não respondeu com a versão $expected em $TimeoutSec s (último: $last)."
    return $false
}

function Stop-StemmaService {
    param([Parameter(Mandatory)][string]$ServiceId)
    $service = Get-Service -Name $ServiceId -ErrorAction SilentlyContinue
    if (-not $service) { throw "Serviço '$ServiceId' não existe. Rode o install.ps1." }
    if ($service.Status -ne 'Stopped') {
        Write-Step "Parando o serviço $ServiceId"
        Stop-Service -Name $ServiceId -Force
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
    }
}

function Start-StemmaService {
    param([Parameter(Mandatory)][string]$ServiceId)
    Write-Step "Iniciando o serviço $ServiceId"
    Start-Service -Name $ServiceId
}

function Get-WinSW {
    param([Parameter(Mandatory)][string]$Dest)
    if (Test-Path -LiteralPath $Dest) {
        Assert-Sha256 -Path $Dest -Expected $script:WinSWSha256
        return
    }
    Write-Step 'Baixando o WinSW 2.12.0'
    $tmp = "$Dest.download"
    Invoke-Download -Url $script:WinSWUrl -Dest $tmp
    Assert-Sha256 -Path $tmp -Expected $script:WinSWSha256
    Move-Item -LiteralPath $tmp -Destination $Dest -Force
}

function New-ServiceXml {
    <# Gera o XML do WinSW a partir do modelo da release, trocando id e nome. #>
    param([Parameter(Mandatory)][string]$Template, [Parameter(Mandatory)][string]$ServiceId, [Parameter(Mandatory)][string]$Dest)
    $xml = Get-Content -LiteralPath $Template -Raw -Encoding UTF8
    $xml = $xml.Replace('{{SERVICE_ID}}', $ServiceId)
    [IO.File]::WriteAllText($Dest, $xml, [Text.UTF8Encoding]::new($false))
}

function Test-StemmaService([string]$ServiceId) {
    return [bool](Get-Service -Name $ServiceId -ErrorAction SilentlyContinue)
}

function Register-StemmaService {
    <# Registra o serviço com o WinSW, como LocalSystem (sem pedir conta nem senha; ADR 0014). #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$ServiceId, [Parameter(Mandatory)][string]$ReleaseDir)
    Write-Step "Registrando o serviço $ServiceId"
    $winswDir = Join-Path $Root 'winsw'
    New-Item -ItemType Directory -Force -Path $winswDir | Out-Null
    $exe = Join-Path $winswDir "$ServiceId.exe"
    Get-WinSW -Dest $exe
    New-ServiceXml -Template (Join-Path $ReleaseDir 'deploy\stemma-service.xml') -ServiceId $ServiceId `
        -Dest (Join-Path $winswDir "$ServiceId.xml")
    Invoke-Native -FilePath $exe -Arguments @('install')
}

function Disable-StemmaService {
    <# "Parar o Stemma" (Menu Iniciar): para e deixa manual, para não voltar quando o Windows reiniciar. #>
    param([Parameter(Mandatory)][string]$ServiceId)
    Stop-StemmaService -ServiceId $ServiceId
    Invoke-Native -FilePath 'sc.exe' -Arguments @('config', $ServiceId, 'start=', 'demand')
}

function Enable-StemmaService {
    <# "Iniciar o Stemma": volta ao início automático (atrasado, como o WinSW registra) e sobe. #>
    param([Parameter(Mandatory)][string]$ServiceId)
    Invoke-Native -FilePath 'sc.exe' -Arguments @('config', $ServiceId, 'start=', 'delayed-auto')
    $service = Get-Service -Name $ServiceId
    if ($service.Status -ne 'Running') { Start-StemmaService -ServiceId $ServiceId }
}

function Unregister-StemmaService {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$ServiceId)
    if (-not (Test-StemmaService $ServiceId)) { return }
    Stop-StemmaService -ServiceId $ServiceId
    $exe = Join-Path $Root "winsw\$ServiceId.exe"
    Write-Step "Removendo o serviço $ServiceId"
    if (Test-Path -LiteralPath $exe) { Invoke-Native -FilePath $exe -Arguments @('uninstall') }
    else { Invoke-Native -FilePath 'sc.exe' -Arguments @('delete', $ServiceId) }
}
