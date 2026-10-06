# Funções compartilhadas pelo install.ps1, update.ps1 e start.ps1 (ADR 0007).
# Compatível com o Windows PowerShell 5.1. Salvo com BOM (acentos).

Set-StrictMode -Version Latest

$script:Repo = 'Arthur-Luciani/stemma'

# WinSW 2.12.0 (x64), conferido pelo SHA256 antes de usar.
$script:WinSWUrl = 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe'
$script:WinSWSha256 = '05b82d46ad331cc16bdc00de5c6332c1ef818df8ceefcd49c726553209b3a0da'

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# --- .env --------------------------------------------------------------------

function Read-DotEnv {
    <# Lê `CHAVE=valor` (ignora comentários e linhas vazias; tira aspas). #>
    param([Parameter(Mandatory)][string]$Path)
    $values = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $eq = $trimmed.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $trimmed.Substring(0, $eq).Trim()
        $value = $trimmed.Substring($eq + 1).Trim()
        if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$key] = $value
    }
    return $values
}

function Import-DotEnv {
    <# Põe as variáveis do .env no ambiente deste processo (e dos filhos). #>
    param([Parameter(Mandatory)][string]$Path)
    $values = Read-DotEnv -Path $Path
    foreach ($key in $values.Keys) {
        [Environment]::SetEnvironmentVariable($key, $values[$key], 'Process')
    }
    return $values
}

function Get-StemmaPort {
    param([System.Collections.IDictionary]$EnvValues)
    if ($EnvValues -and $EnvValues.Contains('PORT') -and $EnvValues['PORT']) {
        return [int]$EnvValues['PORT']
    }
    return 8000
}

# --- versões e releases ------------------------------------------------------

function ConvertTo-StemmaVersion {
    <# 'v1.2.3' ou '1.2.3' → [version]; $null se não for X.Y.Z. #>
    param([string]$Text)
    if ($Text -match '^v?(\d+)\.(\d+)\.(\d+)$') {
        return [version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3])
    }
    return $null
}

function Get-VersionFromZipName {
    param([Parameter(Mandatory)][string]$Path)
    # Separa por \ e / (no pwsh do Linux, o GetFileName não entende \).
    $name = ($Path -split '[\\/]')[-1]
    if ($name -match '^stemma-(v\d+\.\d+\.\d+)\.zip$') { return $Matches[1] }
    throw "Nome de pacote inesperado: '$name' (esperado stemma-vX.Y.Z.zip)."
}

function Get-InstalledReleases {
    <# Pastas `releases\vX.Y.Z`, da mais nova para a mais antiga. #>
    param([Parameter(Mandatory)][string]$Root)
    $dir = Join-Path $Root 'releases'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $items = foreach ($child in Get-ChildItem -LiteralPath $dir -Directory) {
        $version = ConvertTo-StemmaVersion $child.Name
        if ($version) { [pscustomobject]@{ Name = $child.Name; Version = $version; Path = $child.FullName } }
    }
    return @($items | Sort-Object -Property Version -Descending)
}

function Get-PreviousRelease {
    <# A release instalada mais nova abaixo de `$Current` (para o rollback manual). #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Current)
    $currentVersion = ConvertTo-StemmaVersion $Current
    $older = @(Get-InstalledReleases -Root $Root | Where-Object { $_.Version -lt $currentVersion })
    if ($older.Count -eq 0) { return $null }
    return $older[0]
}

function Select-ReleasesToRemove {
    <# Mantém as `$Keep` mais novas e nunca remove as protegidas (atual e anterior). #>
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Names,
        [int]$Keep = 3,
        [string[]]$Protect = @()
    )
    $sorted = @($Names | Where-Object { ConvertTo-StemmaVersion $_ } |
        Sort-Object -Property { ConvertTo-StemmaVersion $_ } -Descending)
    $kept = @($sorted | Select-Object -First $Keep)
    return @($sorted | Where-Object { $kept -notcontains $_ -and $Protect -notcontains $_ })
}

# --- download e verificação --------------------------------------------------

function Get-Sha256FromFile {
    <# Formato do `sha256sum`: `<hash>  <arquivo>`. #>
    param([Parameter(Mandatory)][string]$Path)
    $line = (Get-Content -LiteralPath $Path -TotalCount 1).Trim()
    $hash = ($line -split '\s+')[0]
    if ($hash -notmatch '^[0-9a-fA-F]{64}$') { throw "Arquivo de SHA256 inválido: $Path" }
    return $hash.ToLowerInvariant()
}

function Assert-Sha256 {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Expected)
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected.ToLowerInvariant()) {
        throw "SHA256 não confere para $([IO.Path]::GetFileName($Path)): esperado $Expected, veio $actual."
    }
}

function Invoke-Download {
    param([Parameter(Mandatory)][string]$Url, [Parameter(Mandatory)][string]$Dest)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $previous = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'  # a barra de progresso do 5.1 deixa o download lento
    try { Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing }
    finally { $ProgressPreference = $previous }
}

function Get-ReleaseAssets {
    <# URLs do zip e do .sha256 de uma tag (ou da última release). #>
    param([string]$Version)
    $api = "https://api.github.com/repos/$script:Repo/releases"
    if ($Version) {
        $tag = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
        $url = "$api/tags/$tag"
    }
    else { $url = "$api/latest" }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'stemma-deploy' }
    $tagName = $release.tag_name
    $zip = $release.assets | Where-Object { $_.name -eq "stemma-$tagName.zip" }
    $sha = $release.assets | Where-Object { $_.name -eq "stemma-$tagName.zip.sha256" }
    if (-not $zip -or -not $sha) { throw "A release $tagName não tem o pacote stemma-$tagName.zip e o .sha256." }
    return [pscustomobject]@{ Tag = $tagName; ZipUrl = $zip.browser_download_url; ShaUrl = $sha.browser_download_url }
}

function Get-StemmaPackage {
    <# Baixa (ou usa o `-ZipPath` local) e confere o SHA256. Devolve tag e caminho do zip. #>
    param([Parameter(Mandatory)][string]$Root, [string]$Version, [string]$ZipPath)
    if ($ZipPath) {
        $zip = (Resolve-Path -LiteralPath $ZipPath).Path
        $tag = Get-VersionFromZipName $zip
        $shaFile = "$zip.sha256"
        if (-not (Test-Path -LiteralPath $shaFile)) { throw "Falta $shaFile ao lado do zip." }
        Assert-Sha256 -Path $zip -Expected (Get-Sha256FromFile $shaFile)
        return [pscustomobject]@{ Tag = $tag; Zip = $zip }
    }
    $assets = Get-ReleaseAssets -Version $Version
    $downloads = Join-Path $Root 'downloads'
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null
    $zip = Join-Path $downloads "stemma-$($assets.Tag).zip"
    $shaFile = "$zip.sha256"
    Write-Step "Baixando $($assets.Tag)"
    Invoke-Download -Url $assets.ShaUrl -Dest $shaFile
    Invoke-Download -Url $assets.ZipUrl -Dest $zip
    Assert-Sha256 -Path $zip -Expected (Get-Sha256FromFile $shaFile)
    return [pscustomobject]@{ Tag = $assets.Tag; Zip = $zip }
}

function Expand-StemmaPackage {
    <# Extrai para `releases\<tag>` (lado a lado com as outras). O zip tem a pasta `stemma-<tag>`. #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Zip, [Parameter(Mandatory)][string]$Tag)
    $releases = Join-Path $Root 'releases'
    $dest = Join-Path $releases $Tag
    $staging = Join-Path $releases ".tmp-$Tag"
    foreach ($dir in $staging, $dest) {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    }
    New-Item -ItemType Directory -Force -Path $staging | Out-Null
    Expand-Archive -LiteralPath $Zip -DestinationPath $staging
    $inner = Join-Path $staging "stemma-$Tag"
    if (-not (Test-Path -LiteralPath (Join-Path $inner 'backend'))) { throw "Pacote sem a pasta stemma-$Tag\backend." }
    Move-Item -LiteralPath $inner -Destination $dest
    Remove-Item -LiteralPath $staging -Recurse -Force
    return $dest
}

# --- Python da release ---------------------------------------------------------

function Invoke-Native {
    <#
      Roda um executável, mostra a saída (stdout e stderr) no console e falha se o exit code
      não for 0. No 5.1, com a saída redirecionada (serviço), cada linha de stderr vira um
      ErrorRecord; com ErrorActionPreference=Stop isso derrubaria o script por um simples log
      (uv, alembic e uvicorn escrevem no stderr). Por isso só o exit code decide.
    #>
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(), [string]$WorkingDirectory)
    if ($WorkingDirectory) { Push-Location -LiteralPath $WorkingDirectory }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $FilePath @Arguments 2>&1 | ForEach-Object { "$_" } | Out-Host
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
        if ($WorkingDirectory) { Pop-Location }
    }
    if ($code -ne 0) { throw "'$([IO.Path]::GetFileName($FilePath)) $($Arguments -join ' ')' falhou (código $code)." }
}

function Get-ReleasePython([string]$ReleaseDir) {
    return Join-Path $ReleaseDir 'backend\.venv\Scripts\python.exe'
}

function Sync-ReleaseEnvironment {
    <# venv próprio da release (`backend\.venv`); torch vem do cache do uv por hardlink. #>
    param([Parameter(Mandatory)][string]$ReleaseDir)
    $backend = Join-Path $ReleaseDir 'backend'
    Write-Step "uv sync em $backend"
    Invoke-Native -FilePath 'uv' -Arguments @('sync', '--project', $backend, '--frozen', '--no-dev', '--group', 'api', '--group', 'pipeline')
}

function Invoke-Alembic {
    param([Parameter(Mandatory)][string]$ReleaseDir, [Parameter(Mandatory)][string[]]$Arguments)
    Invoke-Native -FilePath (Get-ReleasePython $ReleaseDir) -Arguments (@('-m', 'alembic') + $Arguments) `
        -WorkingDirectory (Join-Path $ReleaseDir 'backend')
}

function Get-AlembicHead {
    <# Revisão head das migrations de uma release (`abc123 (head)` → `abc123`). #>
    param([Parameter(Mandatory)][string]$ReleaseDir)
    Push-Location -LiteralPath (Join-Path $ReleaseDir 'backend')
    try {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $output = & (Get-ReleasePython $ReleaseDir) -m alembic heads 2>$null
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
        Pop-Location
    }
    if ($code -ne 0) { throw "alembic heads falhou em $ReleaseDir." }
    return ConvertFrom-AlembicHeads $output
}

function ConvertFrom-AlembicHeads {
    param([AllowEmptyCollection()][string[]]$Lines)
    $heads = @($Lines | Where-Object { $_ -match '^\s*(\w+) \(head\)' } | ForEach-Object { ($_ -split '\s+')[0] })
    if ($heads.Count -ne 1) { throw "Esperava 1 head do alembic, achei $($heads.Count)." }
    return $heads[0]
}

function Invoke-StemmaCli {
    param([Parameter(Mandatory)][string]$ReleaseDir, [Parameter(Mandatory)][string[]]$Arguments)
    Invoke-Native -FilePath (Get-ReleasePython $ReleaseDir) -Arguments (@('-m', 'app.cli') + $Arguments) `
        -WorkingDirectory (Join-Path $ReleaseDir 'backend')
}

# --- junction `current` --------------------------------------------------------

function Get-CurrentRelease {
    <# Pasta para onde `current` aponta, ou $null. #>
    param([Parameter(Mandatory)][string]$Root)
    $link = Join-Path $Root 'current'
    if (-not (Test-Path -LiteralPath $link)) { return $null }
    $target = @((Get-Item -LiteralPath $link -Force).Target)[0]
    if (-not $target) { throw "$link existe mas não é uma junction." }
    return [IO.Path]::GetFullPath($target)
}

function Set-CurrentRelease {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$ReleaseDir)
    $link = Join-Path $Root 'current'
    if (Test-Path -LiteralPath $link) {
        # Remove só o link, nunca o conteúdo da release.
        [IO.Directory]::Delete($link, $false)
    }
    New-Item -ItemType Junction -Path $link -Target $ReleaseDir | Out-Null
}

# --- serviço e /health ----------------------------------------------------------

function Wait-StemmaHealth {
    <# Espera o /health responder com a versão esperada. Devolve $true/$false. #>
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [int]$TimeoutSec = 180,
        [int]$IntervalSec = 2
    )
    $expected = $ExpectedVersion.TrimStart('v')
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = 'sem resposta'
    do {
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5
            if ($health.version -eq $expected) {
                Write-Host "    /health: versão $($health.version), status $($health.status), gpu $($health.gpu), yt-dlp $($health.ytdlp)"
                return $true
            }
            $last = "versão $($health.version)"
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

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Rode este script num PowerShell como administrador (o serviço do Windows exige).'
    }
}

Export-ModuleMember -Function *-*
