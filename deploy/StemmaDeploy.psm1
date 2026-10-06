# Funções compartilhadas pelo instalador (setup.ps1), install.ps1, update.ps1 e start.ps1
# (ADRs 0007 e 0014). Compatível com o Windows PowerShell 5.1. Salvo com BOM (acentos).

Set-StrictMode -Version Latest

$script:Repo = 'Arthur-Luciani/stemma'

# WinSW 2.12.0 (x64), conferido pelo SHA256 antes de usar.
$script:WinSWUrl = 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe'
$script:WinSWSha256 = '05b82d46ad331cc16bdc00de5c6332c1ef818df8ceefcd49c726553209b3a0da'

# Ferramentas portáteis em <Root>\tools (ADR 0014). Versão e SHA256 fixados; trocar a versão
# exige trocar o hash junto. `Strip`: o zip tem uma pasta de topo que é removida.
$script:Tools = [ordered]@{
    uv     = @{
        Version = '0.12.7'
        Url     = 'https://github.com/astral-sh/uv/releases/download/0.12.7/uv-x86_64-pc-windows-msvc.zip'
        Sha256  = 'bf1518af459a3915511a11fdc6e2f43ef9a2afa138b9d498eeb9642fe9d85218'
        Strip   = $false
        Exe     = 'uv.exe'
    }
    ffmpeg = @{
        Version = '9.0.2'
        Url     = 'https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-essentials_build.zip'
        Sha256  = '60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba'
        Strip   = $true
        Exe     = 'bin\ffmpeg.exe'
    }
    deno   = @{
        Version = '2.9.7'
        Url     = 'https://github.com/denoland/deno/releases/download/v2.9.7/deno-x86_64-pc-windows-msvc.zip'
        Sha256  = 'a0c3101b4158d1dfb7d6a78a7bf0f3de80c96bb423c152beec8beb22786f2238'
        Strip   = $false
        Exe     = 'deno.exe'
    }
}
$script:PythonVersion = '3.12'

# Tailscale: MSI oficial numa versão fixa (depois ele se atualiza sozinho).
$script:TailscaleMsiUrl = 'https://pkgs.tailscale.com/stable/tailscale-setup-1.102.4-amd64.msi'
$script:TailscaleMsiSha256 = '80eb007e39dfebe17299fa1a09c79a8e1d934f76e0246c0817ebe3af675b7ef6'
$script:TailscaleAdminDns = 'https://login.tailscale.com/admin/dns'

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
    <#
      venv próprio da release (`backend\.venv`); torch vem do cache do uv por hardlink.
      Com -PreferOffline tenta antes só com o cache (`--offline`) e, se faltar algo, baixa.
      Devolve 'cache' ou 'download'.
    #>
    param([Parameter(Mandatory)][string]$ReleaseDir, [switch]$PreferOffline)
    $backend = Join-Path $ReleaseDir 'backend'
    $arguments = @('sync', '--project', $backend, '--frozen', '--no-dev', '--group', 'api', '--group', 'pipeline')
    if ($PreferOffline) {
        Write-Step 'Procurando os componentes no PC (sem baixar)'
        try {
            Invoke-Native -FilePath 'uv' -Arguments ($arguments + '--offline')
            Write-Step 'Componentes encontrados no PC'
            return 'cache'
        }
        catch { Write-Host "    Faltou algo no cache ($($_.Exception.Message))." }
    }
    Write-Step 'Baixando componentes (~3 GB na primeira vez)'
    Invoke-Native -FilePath 'uv' -Arguments $arguments
    return 'download'
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

# --- ferramentas em <Root>\tools (ADR 0014) --------------------------------------

function Get-StemmaToolCatalog {
    <# Cópia do catálogo (nome → versão, URL, SHA256, Strip, Exe). #>
    $copy = [ordered]@{}
    foreach ($name in $script:Tools.Keys) { $copy[$name] = $script:Tools[$name].Clone() }
    return $copy
}

function Get-StemmaPaths {
    <# Caminhos fixos de uma instalação. #>
    param([Parameter(Mandatory)][string]$Root)
    $tools = Join-Path $Root 'tools'
    return [pscustomobject]@{
        Tools     = $tools
        Uv        = Join-Path $tools 'uv\uv.exe'
        Ffmpeg    = Join-Path $tools 'ffmpeg\bin\ffmpeg.exe'
        Python    = Join-Path $tools 'python'
        UvCache   = Join-Path $Root 'cache\uv'
        EnvFile   = Join-Path $Root '.env'
        InstallInfo = Join-Path $Root 'install.json'
        PathDirs  = @((Join-Path $tools 'uv'), (Join-Path $tools 'ffmpeg\bin'), (Join-Path $tools 'deno'))
    }
}

function Set-StemmaToolEnv {
    <#
      Ambiente deste processo (e dos filhos) para usar só o que está em <Root>\tools:
      uv, FFmpeg e Deno no começo do PATH, Python gerenciado em tools\python e cache do uv
      em <Root>\cache\uv (mesmo volume dos venvs, para o hardlink funcionar).
    #>
    param([Parameter(Mandatory)][string]$Root)
    $paths = Get-StemmaPaths -Root $Root
    $current = @($env:PATH -split ';' | Where-Object { $_ -and $paths.PathDirs -notcontains $_ })
    $env:PATH = (@($paths.PathDirs) + $current) -join ';'
    $env:UV_CACHE_DIR = $paths.UvCache
    $env:UV_PYTHON_INSTALL_DIR = $paths.Python
    $env:UV_PYTHON_PREFERENCE = 'only-managed'
    $env:UV_PYTHON_INSTALL_BIN = '0'
    $env:UV_PYTHON_INSTALL_REGISTRY = '0'
    $env:UV_NO_PROGRESS = '1'
}

function Test-StemmaToolInstalled {
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][hashtable]$Tool)
    $marker = Join-Path $Dir '.stemma-tool'
    if (-not (Test-Path -LiteralPath $marker) -or -not (Test-Path -LiteralPath (Join-Path $Dir $Tool.Exe))) { return $false }
    return (Get-Content -LiteralPath $marker -TotalCount 1).Trim() -eq "$($Tool.Version) $($Tool.Sha256)"
}

function Install-StemmaTool {
    <# Baixa, confere o SHA256 e extrai em <Root>\tools\<nome>. Pula se a mesma versão já está lá. #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Name, [hashtable]$Tool)
    if (-not $Tool) { $Tool = $script:Tools[$Name] }
    $toolsDir = Join-Path $Root 'tools'
    $dest = Join-Path $toolsDir $Name
    if (Test-StemmaToolInstalled -Dir $dest -Tool $Tool) { return Join-Path $dest $Tool.Exe }

    Write-Step "Baixando $Name $($Tool.Version)"
    $downloads = Join-Path $toolsDir '.download'
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null
    $archive = Join-Path $downloads (($Tool.Url -split '/')[-1])
    if (-not ((Test-Path -LiteralPath $archive) -and
            (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -eq $Tool.Sha256)) {
        Invoke-Download -Url $Tool.Url -Dest "$archive.part"
        Assert-Sha256 -Path "$archive.part" -Expected $Tool.Sha256
        Move-Item -LiteralPath "$archive.part" -Destination $archive -Force
    }
    $staging = Join-Path $toolsDir ".tmp-$Name"
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    Expand-Archive -LiteralPath $archive -DestinationPath $staging
    $content = $staging
    if ($Tool.Strip) {
        $inner = @(Get-ChildItem -LiteralPath $staging -Directory)
        if ($inner.Count -ne 1) { throw "Esperava uma pasta de topo em $archive." }
        $content = $inner[0].FullName
    }
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    Move-Item -LiteralPath $content -Destination $dest
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
    Set-Content -LiteralPath (Join-Path $dest '.stemma-tool') -Value "$($Tool.Version) $($Tool.Sha256)" -Encoding ASCII
    Remove-Item -LiteralPath $archive -Force
    return Join-Path $dest $Tool.Exe
}

function Install-StemmaTools {
    <# Todas as ferramentas + Python gerenciado; deixa o ambiente do processo apontando para elas. #>
    param([Parameter(Mandatory)][string]$Root)
    foreach ($name in $script:Tools.Keys) { Install-StemmaTool -Root $Root -Name $name | Out-Null }
    Set-StemmaToolEnv -Root $Root
    Write-Step "Python $script:PythonVersion"
    # Sem executável no ~\.local\bin nem registro no HKCU: nada do Stemma no perfil do usuário.
    Invoke-Native -FilePath (Get-StemmaPaths -Root $Root).Uv -Arguments @('python', 'install', $script:PythonVersion, '--no-bin', '--no-registry')
}

# --- cache do uv: semear a partir do cache do usuário ------------------------------

function Find-UserUvCache {
    <#
      Cache do uv do usuário que rodou o instalador (elevado, mas no perfil dele). Chame antes
      do Set-StemmaToolEnv, que troca o UV_CACHE_DIR deste processo. $null se não houver.
    #>
    $candidates = @()
    if ($env:UV_CACHE_DIR) { $candidates += $env:UV_CACHE_DIR }
    $uv = Get-Command uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($uv) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $dir = & $uv.Source cache dir 2>$null; if ($LASTEXITCODE -eq 0 -and $dir) { $candidates += "$dir".Trim() } }
        catch { Write-Verbose "uv cache dir falhou: $_" }
        finally { $ErrorActionPreference = $previous }
    }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'uv\cache' }
    foreach ($dir in $candidates) {
        if ($dir -and (Test-Path -LiteralPath $dir -PathType Container)) { return [IO.Path]::GetFullPath($dir) }
    }
    return $null
}

function Test-SameVolume([string]$A, [string]$B) {
    return [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($A)) -eq [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($B))
}

function Initialize-HardLinkSeeder {
    if ('Stemma.CacheSeeder' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
namespace Stemma {
    public static class CacheSeeder {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, IntPtr lpSecurityAttributes);

        // Recria a árvore de `source` em `dest` com hardlinks (cópia se o link falhar).
        // Arquivos que já existem em `dest` ficam como estão. Pastas que são junction (formatos
        // antigos do cache) não são atravessadas: um processo elevado recusa junctions criadas
        // pelo usuário ("untrusted mount point"). Uma pasta ilegível não aborta o resto.
        // Devolve {linked, copied, skipped, failed}.
        public static long[] Seed(string source, string dest) {
            long[] counts = new long[4];
            source = Path.GetFullPath(source).TrimEnd('\\');
            dest = Path.GetFullPath(dest).TrimEnd('\\');
            var pending = new System.Collections.Generic.Stack<string>();
            pending.Push(source);
            while (pending.Count > 0) {
                string dir = pending.Pop();
                string targetDir = dest + dir.Substring(source.Length);
                string[] files, dirs;
                try {
                    Directory.CreateDirectory(targetDir);
                    files = Directory.GetFiles(dir);
                    dirs = Directory.GetDirectories(dir);
                }
                catch (Exception) { counts[3]++; continue; }
                foreach (string sub in dirs) {
                    if ((File.GetAttributes(sub) & FileAttributes.ReparsePoint) != 0) { counts[2]++; continue; }
                    pending.Push(sub);
                }
                foreach (string file in files) {
                    string target = targetDir + file.Substring(dir.Length);
                    if (File.Exists(target)) { counts[2]++; continue; }
                    if (CreateHardLink(target, file, IntPtr.Zero)) { counts[0]++; continue; }
                    try { File.Copy(file, target); counts[1]++; }
                    catch (Exception) { counts[3]++; }
                }
            }
            return counts;
        }
    }
}
'@
}

function Copy-UvCacheSeed {
    <#
      Semeia <Root>\cache\uv com o cache do usuário por hardlink (segundos, sem espaço extra; um
      `uv cache clean` do usuário não afeta). Em outro volume não semeia: copiar o cache inteiro
      (dezenas de GB) sai mais caro que baixar o que falta. Devolve um resumo ou $null.
    #>
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Dest)
    $src = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    $dst = [IO.Path]::GetFullPath($Dest).TrimEnd('\')
    if ($src -eq $dst) { return $null }
    if (-not (Test-SameVolume $src $dst)) {
        Write-Host "    Cache do uv em outro volume ($src): sem semear."
        return $null
    }
    Write-Step 'Reaproveitando os componentes já baixados neste PC'
    Initialize-HardLinkSeeder
    $counts = [Stemma.CacheSeeder]::Seed($src, $dst)
    $summary = [pscustomobject]@{ Linked = $counts[0]; Copied = $counts[1]; Skipped = $counts[2]; Failed = $counts[3] }
    Write-Host "    $($summary.Linked) arquivos ligados, $($summary.Copied) copiados, $($summary.Skipped) já estavam, $($summary.Failed) falharam."
    return $summary
}

# --- .env e dados da instalação ---------------------------------------------------

function Get-DefaultDataRoot {
    if (Test-Path -LiteralPath 'D:\') { return 'D:\stemma-data' }
    return 'C:\stemma-data'
}

function Write-DotEnvLines([string]$Path, [string[]]$Lines) {
    [IO.File]::WriteAllLines($Path, $Lines, [Text.UTF8Encoding]::new($false))
}

function New-StemmaEnvFile {
    <# .env de produção novo. FFMPEG_BIN absoluto: o serviço não depende do PATH de ninguém. #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][string]$FfmpegBin
    )
    Write-DotEnvLines $Path @(
        '# Configuração de produção do Stemma (variáveis em .env.example da release).',
        "PORT=$Port",
        "STORAGE_ROOT=$DataRoot",
        "FFMPEG_BIN=$FfmpegBin",
        'LOG_LEVEL=INFO'
    )
}

function Update-StemmaEnvFile {
    <# Acrescenta as chaves que faltam (ex.: FFMPEG_BIN de uma instalação antiga), sem mexer nas outras. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][System.Collections.IDictionary]$Defaults)
    $values = Read-DotEnv -Path $Path
    $missing = @($Defaults.Keys | Where-Object { -not $values.Contains($_) })
    if ($missing.Count -eq 0) { return @() }
    $lines = @()
    if (Test-Path -LiteralPath $Path) { $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8) }
    foreach ($key in $missing) { $lines += "$key=$($Defaults[$key])" }
    Write-DotEnvLines $Path $lines
    return $missing
}

function Get-StemmaInstallInfo {
    <# install.json: o que o instalador precisa lembrar (serviço, porta da 443 no tailscale). #>
    param([Parameter(Mandatory)][string]$Root)
    $path = (Get-StemmaPaths -Root $Root).InstallInfo
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Set-StemmaInstallInfo {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$ServiceId, [bool]$TailscaleServe)
    $info = [ordered]@{ serviceId = $ServiceId; tailscaleServe = $TailscaleServe }
    [IO.File]::WriteAllText((Get-StemmaPaths -Root $Root).InstallInfo, ($info | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

# --- Tailscale ----------------------------------------------------------------------

function Get-TailscaleExe {
    $default = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if ($env:ProgramFiles -and (Test-Path -LiteralPath $default)) { return $default }
    $cmd = Get-Command tailscale -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

function ConvertFrom-TailscaleStatus {
    <#
      `tailscale status --json` → estado para o instalador:
      needslogin | stopped | starting | nohttps | ready, com o nome HTTPS do PC.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Json)
    $status = $Json | ConvertFrom-Json
    $backend = "$($status.BackendState)"
    $dnsName = ''
    if ($status.PSObject.Properties['Self'] -and $status.Self -and $status.Self.PSObject.Properties['DNSName']) {
        $dnsName = "$($status.Self.DNSName)".TrimEnd('.')
    }
    $certDomains = @()
    if ($status.PSObject.Properties['CertDomains'] -and $status.CertDomains) { $certDomains = @($status.CertDomains) }
    $authUrl = if ($status.PSObject.Properties['AuthURL']) { "$($status.AuthURL)" } else { '' }
    $state = switch ($backend) {
        'Running' { if ($certDomains.Count -gt 0) { 'ready' } else { 'nohttps' } }
        'NeedsLogin' { 'needslogin' }
        'NeedsMachineAuth' { 'needslogin' }
        'NoState' { 'needslogin' }
        'Stopped' { 'stopped' }
        default { 'starting' }
    }
    $hostName = if ($certDomains.Count -gt 0) { "$($certDomains[0])" } else { $dnsName }
    return [pscustomobject]@{ State = $state; Host = $hostName; AuthUrl = $authUrl }
}

function Get-TailscaleState {
    $exe = Get-TailscaleExe
    if (-not $exe) { return [pscustomobject]@{ State = 'missing'; Host = ''; AuthUrl = '' } }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $json = (& $exe status --json 2>$null) -join "`n" }
    finally { $ErrorActionPreference = $previous }
    if (-not $json) { return [pscustomobject]@{ State = 'starting'; Host = ''; AuthUrl = '' } }
    return ConvertFrom-TailscaleStatus -Json $json
}

function Install-Tailscale {
    <# MSI oficial (versão fixa, SHA256 conferido), silencioso. #>
    param([Parameter(Mandatory)][string]$Root)
    $downloads = Join-Path $Root 'downloads'
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null
    $msi = Join-Path $downloads (($script:TailscaleMsiUrl -split '/')[-1])
    Write-Step 'Baixando o Tailscale'
    Invoke-Download -Url $script:TailscaleMsiUrl -Dest $msi
    Assert-Sha256 -Path $msi -Expected $script:TailscaleMsiSha256
    Write-Step 'Instalando o Tailscale'
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', "`"$msi`"", '/qn', '/norestart') -Wait -PassThru
    if (@(0, 3010) -notcontains $process.ExitCode) { throw "A instalação do Tailscale falhou (código $($process.ExitCode))." }
    Remove-Item -LiteralPath $msi -Force
}

function Start-TailscaleLogin {
    <# `tailscale up` em segundo plano e abre no navegador a página de login que ele gerar. #>
    $exe = Get-TailscaleExe
    if (-not $exe) { throw 'Tailscale não instalado.' }
    Start-Process -FilePath $exe -ArgumentList 'up' -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(20)
    do {
        Start-Sleep -Seconds 1
        $state = Get-TailscaleState
        if ($state.AuthUrl) { Start-Process $state.AuthUrl; return $state }
        if ($state.State -in 'ready', 'nohttps') { return $state }
    } while ((Get-Date) -lt $deadline)
    return Get-TailscaleState
}

function Set-TailscaleServe {
    param([Parameter(Mandatory)][int]$Port)
    Write-Step 'Publicando no Tailscale (HTTPS na 443)'
    Invoke-Native -FilePath (Get-TailscaleExe) -Arguments @('serve', '--bg', '--https=443', "http://127.0.0.1:$Port")
}

function Remove-TailscaleServe {
    $exe = Get-TailscaleExe
    if (-not $exe) { return }
    Write-Step 'Desligando o tailscale serve da 443'
    Invoke-Native -FilePath $exe -Arguments @('serve', '--https=443', 'off')
}

function Test-NvidiaGpu {
    $smi = Get-Command nvidia-smi -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $smi) { return $false }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $smi.Source -L 2>$null | Out-Null; return $LASTEXITCODE -eq 0 }
    finally { $ErrorActionPreference = $previous }
}

# --- fluxos: instalar, atualizar, voltar, desinstalar -------------------------------

function Get-StemmaContext {
    <# Estado de uma instalação existente: .env, porta, release no ar e STORAGE_ROOT. #>
    param([Parameter(Mandatory)][string]$Root)
    $envValues = Read-DotEnv -Path (Join-Path $Root '.env')
    $current = Get-CurrentRelease -Root $Root
    return [pscustomobject]@{
        EnvValues   = $envValues
        Port        = Get-StemmaPort $envValues
        Current     = $current
        CurrentTag  = if ($current) { Split-Path -Leaf $current } else { $null }
        StorageRoot = if ($envValues.Contains('STORAGE_ROOT') -and $envValues['STORAGE_ROOT']) { $envValues['STORAGE_ROOT'] } else { Get-DefaultDataRoot }
    }
}

function Test-StemmaDatabase {
    <# Há banco para fazer backup? (DATABASE_URL próprio ou o stemma.db padrão.) #>
    param([Parameter(Mandatory)]$Context)
    $custom = $Context.EnvValues.Contains('DATABASE_URL') -and $Context.EnvValues['DATABASE_URL']
    return [bool]($custom -or (Test-Path -LiteralPath (Join-Path $Context.StorageRoot 'stemma.db')))
}

function New-BackupPath([string]$StorageRoot, [string]$Label) {
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    return Join-Path $StorageRoot "backups\stemma-$Label-$stamp.db"
}

function Initialize-StemmaRuntime {
    <# Ferramentas em tools\, ambiente do processo e chaves novas no .env de uma instalação existente. #>
    param([Parameter(Mandatory)][string]$Root)
    Install-StemmaTools -Root $Root
    $paths = Get-StemmaPaths -Root $Root
    if (Test-Path -LiteralPath $paths.EnvFile) {
        $added = Update-StemmaEnvFile -Path $paths.EnvFile -Defaults ([ordered]@{ FFMPEG_BIN = $paths.Ffmpeg })
        if ($added) { Write-Host "    .env: acrescentado $($added -join ', ')" }
    }
}

function Invoke-StemmaInstall {
    <#
      Primeira instalação: ferramentas, cache semeado, release (venv), .env, migrations, serviço
      (LocalSystem), /health e tailscale serve. Devolve a tag instalada.
    #>
    param(
        [string]$Root = 'C:\stemma',
        [string]$DataRoot,
        [int]$Port = 8000,
        [string]$ServiceId = 'stemma',
        [string]$Version,
        [string]$ZipPath,
        [switch]$SkipTailscale,
        [int]$HealthTimeoutSec = 180
    )
    if (Test-StemmaService $ServiceId) { throw "O serviço '$ServiceId' já existe. Use a atualização." }
    if (-not $DataRoot) { $DataRoot = Get-DefaultDataRoot }
    $userCache = Find-UserUvCache  # antes do Set-StemmaToolEnv, que troca o UV_CACHE_DIR
    foreach ($dir in $Root, (Join-Path $Root 'releases'), (Join-Path $Root 'logs'), $DataRoot) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $paths = Get-StemmaPaths -Root $Root
    Initialize-StemmaRuntime -Root $Root
    if ($userCache) { Copy-UvCacheSeed -Source $userCache -Dest $paths.UvCache | Out-Null }

    if (-not (Test-Path -LiteralPath $paths.EnvFile)) {
        Write-Step "Criando $($paths.EnvFile)"
        New-StemmaEnvFile -Path $paths.EnvFile -Port $Port -DataRoot $DataRoot -FfmpegBin $paths.Ffmpeg
    }
    $context = Get-StemmaContext -Root $Root

    $package = Get-StemmaPackage -Root $Root -Version $Version -ZipPath $ZipPath
    Write-Step "Extraindo $($package.Tag)"
    $release = Expand-StemmaPackage -Root $Root -Zip $package.Zip -Tag $package.Tag
    Sync-ReleaseEnvironment -ReleaseDir $release -PreferOffline | Out-Null

    Write-Step 'Migrations'
    Import-DotEnv -Path $paths.EnvFile | Out-Null
    Invoke-Alembic -ReleaseDir $release -Arguments @('upgrade', 'head')
    Set-CurrentRelease -Root $Root -ReleaseDir $release

    Register-StemmaService -Root $Root -ServiceId $ServiceId -ReleaseDir $release
    Set-StemmaInstallInfo -Root $Root -ServiceId $ServiceId -TailscaleServe (-not $SkipTailscale)
    Start-StemmaService -ServiceId $ServiceId
    if (-not (Wait-StemmaHealth -Port $context.Port -ExpectedVersion $package.Tag -TimeoutSec $HealthTimeoutSec)) {
        throw "O serviço subiu mas o /health não confirmou a versão. Veja os logs em $(Join-Path $Root 'logs')."
    }
    if (-not $SkipTailscale) { Set-TailscaleServe -Port $context.Port }
    Write-Step "Stemma $($package.Tag) instalado em $Root"
    return $package.Tag
}

function Restart-StemmaAndCheck {
    param([string]$ServiceId, [int]$Port, [string]$Tag, [int]$HealthTimeoutSec)
    Stop-StemmaService -ServiceId $ServiceId
    Start-StemmaService -ServiceId $ServiceId
    return Wait-StemmaHealth -Port $Port -ExpectedVersion $Tag -TimeoutSec $HealthTimeoutSec
}

function Invoke-StemmaUpdate {
    <#
      Atualiza para outra release (ADR 0007): baixa/confere, extrai lado a lado, venv (serviço
      no ar), para, backup, migrations, `current`, sobe e confere o /health. Falha depois de
      parar → restaura o banco, volta o `current` e sobe a anterior; aí lança o erro.
      Devolve a tag no ar.
    #>
    param(
        [string]$Root = 'C:\stemma',
        [string]$ServiceId = 'stemma',
        [string]$Version,
        [string]$ZipPath,
        [switch]$SimulateFailure,
        [int]$HealthTimeoutSec = 180
    )
    $context = Get-StemmaContext -Root $Root
    if (-not $context.Current) { throw "Nenhuma release em $Root\current. Faça a instalação primeiro." }
    $current = $context.Current
    $currentTag = $context.CurrentTag
    Initialize-StemmaRuntime -Root $Root
    $context = Get-StemmaContext -Root $Root  # o .env pode ter ganhado chaves

    $package = Get-StemmaPackage -Root $Root -Version $Version -ZipPath $ZipPath
    $target = $package.Tag
    if ($target -eq $currentTag) {
        Write-Step "Já está na $target"
        return $target
    }

    Write-Step "Atualizando $currentTag → $target"
    $release = Expand-StemmaPackage -Root $Root -Zip $package.Zip -Tag $target
    Sync-ReleaseEnvironment -ReleaseDir $release -PreferOffline | Out-Null
    Import-DotEnv -Path (Join-Path $Root '.env') | Out-Null

    Stop-StemmaService -ServiceId $ServiceId
    $backup = $null
    try {
        if (Test-StemmaDatabase $context) {
            Write-Step 'Backup do banco'
            $dest = New-BackupPath $context.StorageRoot "$currentTag-to-$target"
            Invoke-StemmaCli -ReleaseDir $release -Arguments @('backup', '--dest', $dest)
            # Só depois do sucesso: o rollback restaura deste arquivo.
            $backup = $dest
        }
        else { Write-Host '    Banco ainda não existe: sem backup.' }
        Write-Step 'Migrations'
        Invoke-Alembic -ReleaseDir $release -Arguments @('upgrade', 'head')
        Set-CurrentRelease -Root $Root -ReleaseDir $release
        Start-StemmaService -ServiceId $ServiceId
        $expected = if ($SimulateFailure) { 'v0.0.0' } else { $target }
        if ($SimulateFailure) { Write-Warning 'SimulateFailure: a checagem do /health vai falhar de propósito.' }
        if (-not (Wait-StemmaHealth -Port $context.Port -ExpectedVersion $expected -TimeoutSec $HealthTimeoutSec)) {
            throw "A $target não confirmou a versão no /health."
        }
    }
    catch {
        $reason = $_.Exception.Message.TrimEnd('.')
        Write-Warning "Falhou: $reason"
        Write-Step "Voltando para $currentTag"
        Stop-StemmaService -ServiceId $ServiceId
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            Write-Step 'Restaurando o banco do backup'
            Invoke-StemmaCli -ReleaseDir $current -Arguments @('restore', '--src', $backup)
        }
        Set-CurrentRelease -Root $Root -ReleaseDir $current
        Start-StemmaService -ServiceId $ServiceId
        if (Wait-StemmaHealth -Port $context.Port -ExpectedVersion $currentTag -TimeoutSec $HealthTimeoutSec) {
            throw "A atualização para $target falhou ($reason). A $currentTag continua no ar."
        }
        throw "A atualização falhou ($reason) e a $currentTag não confirmou no /health. Veja $Root\logs."
    }

    Write-Step 'Limpando releases antigas'
    $names = @(Get-InstalledReleases -Root $Root | ForEach-Object { $_.Name })
    foreach ($name in (Select-ReleasesToRemove -Names $names -Keep 3 -Protect @($target, $currentTag))) {
        Write-Host "    removendo $name"
        Remove-Item -LiteralPath (Join-Path $Root "releases\$name") -Recurse -Force
    }
    Write-Step "Stemma $target no ar"
    return $target
}

function Invoke-StemmaRollback {
    <# Volta para a release instalada anterior, desfazendo as migrations. Lança erro se falhar. #>
    param([string]$Root = 'C:\stemma', [string]$ServiceId = 'stemma', [int]$HealthTimeoutSec = 180)
    $context = Get-StemmaContext -Root $Root
    if (-not $context.Current) { throw "Nenhuma release em $Root\current." }
    $current = $context.Current
    $currentTag = $context.CurrentTag
    Set-StemmaToolEnv -Root $Root
    Import-DotEnv -Path (Join-Path $Root '.env') | Out-Null
    $previous = Get-PreviousRelease -Root $Root -Current $currentTag
    if (-not $previous) { throw "Não há release instalada anterior a $currentTag." }
    $targetHead = Get-AlembicHead -ReleaseDir $previous.Path
    $currentHead = Get-AlembicHead -ReleaseDir $current
    Stop-StemmaService -ServiceId $ServiceId
    $backup = $null
    try {
        if (Test-StemmaDatabase $context) {
            Write-Step 'Backup do banco'
            $dest = New-BackupPath $context.StorageRoot "$currentTag-rollback"
            Invoke-StemmaCli -ReleaseDir $current -Arguments @('backup', '--dest', $dest)
            $backup = $dest
        }
        if ($targetHead -ne $currentHead) {
            Write-Step "Desfazendo migrations até $targetHead"
            Invoke-Alembic -ReleaseDir $current -Arguments @('downgrade', $targetHead)
        }
        Set-CurrentRelease -Root $Root -ReleaseDir $previous.Path
        Start-StemmaService -ServiceId $ServiceId
        if (-not (Wait-StemmaHealth -Port $context.Port -ExpectedVersion $previous.Name -TimeoutSec $HealthTimeoutSec)) {
            throw "A $($previous.Name) não confirmou a versão no /health."
        }
    }
    catch {
        # Desfaz o rollback: banco e `current` como estavam, e a versão atual no ar de novo.
        $reason = $_.Exception.Message.TrimEnd('.')
        Write-Warning "Rollback falhou: $reason"
        Stop-StemmaService -ServiceId $ServiceId
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            Invoke-StemmaCli -ReleaseDir $current -Arguments @('restore', '--src', $backup)
        }
        Set-CurrentRelease -Root $Root -ReleaseDir $current
        Start-StemmaService -ServiceId $ServiceId
        $back = Wait-StemmaHealth -Port $context.Port -ExpectedVersion $currentTag -TimeoutSec $HealthTimeoutSec
        $state = if ($back) { "Continua na $currentTag." } else { "E a $currentTag não confirmou no /health; veja $Root\logs." }
        throw "Rollback para $($previous.Name) falhou ($reason). $state"
    }
    Write-Step "Voltou para $($previous.Name)"
    return $previous.Name
}

function Update-StemmaYtDlp {
    <# Só o yt-dlp do venv atual (até o próximo update, que volta para o do uv.lock). #>
    param([string]$Root = 'C:\stemma', [string]$ServiceId = 'stemma', [int]$HealthTimeoutSec = 180)
    $context = Get-StemmaContext -Root $Root
    if (-not $context.Current) { throw "Nenhuma release em $Root\current." }
    Set-StemmaToolEnv -Root $Root
    Write-Step "Atualizando o yt-dlp de $($context.CurrentTag)"
    Invoke-Native -FilePath 'uv' -Arguments @('pip', 'install', '--python', (Get-ReleasePython $context.Current), '--upgrade', 'yt-dlp[default]')
    if (-not (Restart-StemmaAndCheck -ServiceId $ServiceId -Port $context.Port -Tag $context.CurrentTag -HealthTimeoutSec $HealthTimeoutSec)) {
        throw 'O serviço não voltou depois de atualizar o yt-dlp. Veja os logs.'
    }
}

function Remove-StemmaTree {
    <# Apaga uma pasta grande (o cache tem centenas de milhares de arquivos); junctions só como link. #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($Path, $false); return }
    if (-not $item.PSIsContainer) { Remove-Item -LiteralPath $Path -Force; return }
    # O rd não segue junctions (só remove o link), e é bem mais rápido que o Remove-Item.
    Invoke-Native -FilePath 'cmd.exe' -Arguments @('/c', 'rd', '/s', '/q', "`"$Path`"")
}

function Invoke-StemmaUninstall {
    <#
      Para e remove o serviço, desliga o tailscale serve da 443 (se foi o instalador que
      ligou) e apaga <Root>, menos as pastas em -Keep (a do desinstalador). Com -RemoveData
      apaga também o STORAGE_ROOT.
    #>
    param(
        [string]$Root = 'C:\stemma',
        [string]$ServiceId,
        [string[]]$Keep = @(),
        [switch]$RemoveData
    )
    $context = Get-StemmaContext -Root $Root
    $info = Get-StemmaInstallInfo -Root $Root
    if (-not $ServiceId) { $ServiceId = if ($info) { $info.serviceId } else { 'stemma' } }
    Unregister-StemmaService -Root $Root -ServiceId $ServiceId
    if ($info -and $info.tailscaleServe) {
        try { Remove-TailscaleServe } catch { Write-Warning "tailscale serve: $($_.Exception.Message)" }
    }
    $current = Join-Path $Root 'current'
    if (Test-Path -LiteralPath $current) { [IO.Directory]::Delete($current, $false) }
    Write-Step "Apagando $Root"
    foreach ($child in @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue)) {
        if ($Keep -contains $child.Name) { continue }
        Remove-StemmaTree -Path $child.FullName
    }
    if ($RemoveData -and $context.StorageRoot -and (Test-Path -LiteralPath $context.StorageRoot)) {
        Write-Step "Apagando os dados em $($context.StorageRoot)"
        Remove-StemmaTree -Path $context.StorageRoot
    }
}

Export-ModuleMember -Function *-*
