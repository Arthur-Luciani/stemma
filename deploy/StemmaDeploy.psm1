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

# --- progresso por etapas (instalar e atualizar) -------------------------------------
# Com o protocolo ligado (setup.ps1, lido pelo instalador), cada etapa sai como
# `##STAGE Etapa i de n: texto` e o avanço como `##PROGRESS 0..1000`. Sem ele (scripts de
# console), a etapa sai como um Write-Step e o avanço não aparece.

$script:ProgressProtocol = $false
$script:Progress = $null

function Set-StemmaProgressProtocol([bool]$Enabled) { $script:ProgressProtocol = $Enabled }

function Start-StemmaProgress {
    <# Etapas de um fluxo longo: cada uma com Id, Text e Weight (peso relativo no tempo). #>
    param([Parameter(Mandatory)][object[]]$Stages)
    $list = @(foreach ($stage in $Stages) { [pscustomobject]@{ Id = $stage.Id; Text = $stage.Text; Weight = [double]$stage.Weight } })
    $script:Progress = [pscustomobject]@{ Stages = $list; Index = -1; Last = -1 }
    Write-StemmaProgress 0
}

function Get-StemmaProgressValue {
    <# 0..1000: o peso das etapas anteriores mais a fração da atual. #>
    param([Parameter(Mandatory)][object[]]$Stages, [Parameter(Mandatory)][int]$Index, [double]$Fraction = 0)
    $total = 0.0
    $before = 0.0
    for ($i = 0; $i -lt $Stages.Count; $i++) {
        $total += $Stages[$i].Weight
        if ($i -lt $Index) { $before += $Stages[$i].Weight }
    }
    if ($total -le 0) { return 0 }
    $fraction = [Math]::Min(1.0, [Math]::Max(0.0, $Fraction))
    return [int][Math]::Floor(1000 * ($before + $Stages[$Index].Weight * $fraction) / $total)
}

function Write-StemmaProgress([int]$Value) {
    # Nunca volta (uma etapa repesada não pode fazer a barra andar para trás).
    if (-not $script:ProgressProtocol -or -not $script:Progress) { return }
    if ($Value -le $script:Progress.Last) { return }
    $script:Progress.Last = $Value
    Write-Host "##PROGRESS $Value"
}

function Write-StemmaStage([string]$Text) {
    # Também para etapas fora da lista (ex.: o rollback de uma atualização que falhou).
    if ($script:ProgressProtocol) { Write-Host "##STAGE $Text" } else { Write-Step $Text }
}

function Enter-StemmaStage {
    <# Começa a etapa `$Id` ("Etapa 3 de 9: …"). Sem progresso iniciado, só mostra o texto. #>
    param([Parameter(Mandatory)][string]$Id)
    if (-not $script:Progress) { return }
    $stages = $script:Progress.Stages
    $index = -1
    for ($i = 0; $i -lt $stages.Count; $i++) { if ($stages[$i].Id -eq $Id) { $index = $i } }
    if ($index -lt 0) { throw "Etapa desconhecida: $Id" }
    $script:Progress.Index = $index
    Write-StemmaStage "Etapa $($index + 1) de $($stages.Count): $($stages[$index].Text)"
    Write-StemmaProgress (Get-StemmaProgressValue -Stages $stages -Index $index)
}

function Set-StemmaStageProgress {
    <# Fração (0..1) da etapa atual; fora de uma etapa não faz nada. #>
    param([Parameter(Mandatory)][double]$Fraction)
    if (-not $script:Progress -or $script:Progress.Index -lt 0) { return }
    Write-StemmaProgress (Get-StemmaProgressValue -Stages $script:Progress.Stages -Index $script:Progress.Index -Fraction $Fraction)
}

function Set-StemmaStageWeight {
    <#
      Repesa uma etapa (ex.: componentes, quando se sabe se vai baixar). As anteriores são
      reescaladas por (novo + resto) / (antigo + resto), o que mantém exatamente o que a barra
      já mostra: sem isso, um peso maior derrubaria o valor atual, e a barra (que nunca volta)
      ficaria parada até o download alcançá-lo.
    #>
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][double]$Weight)
    if (-not $script:Progress) { return }
    $stages = $script:Progress.Stages
    $index = -1
    for ($i = 0; $i -lt $stages.Count; $i++) { if ($stages[$i].Id -eq $Id) { $index = $i } }
    if ($index -lt 0) { return }
    $rest = 0.0
    for ($i = $index + 1; $i -lt $stages.Count; $i++) { $rest += $stages[$i].Weight }
    $old = $stages[$index].Weight
    if ($old + $rest -gt 0) {
        $scale = ($Weight + $rest) / ($old + $rest)
        for ($i = 0; $i -lt $index; $i++) { $stages[$i].Weight *= $scale }
    }
    $stages[$index].Weight = $Weight
}

function Complete-StemmaProgress {
    Write-StemmaProgress 1000
    $script:Progress = $null
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
    <# URLs do pacote (zip) ou do instalador (.exe), e do .sha256, de uma tag (ou da última release). #>
    param([string]$Version, [ValidateSet('zip', 'installer')][string]$Kind = 'zip')
    $api = "https://api.github.com/repos/$script:Repo/releases"
    if ($Version) {
        $tag = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
        $url = "$api/tags/$tag"
    }
    else { $url = "$api/latest" }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent' = 'stemma-deploy' }
    $tagName = $release.tag_name
    $name = if ($Kind -eq 'zip') { "stemma-$tagName.zip" } else { "Stemma-Setup-$tagName.exe" }
    $file = $release.assets | Where-Object { $_.name -eq $name }
    $sha = $release.assets | Where-Object { $_.name -eq "$name.sha256" }
    if (-not $file -or -not $sha) { throw "A release $tagName não tem o $name e o .sha256." }
    return [pscustomobject]@{ Tag = $tagName; Url = $file.browser_download_url; ZipUrl = $file.browser_download_url; ShaUrl = $sha.browser_download_url }
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
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory,
        # Chamado com cada linha de saída (ex.: progresso do download do uv).
        [scriptblock]$OnLine
    )
    if ($WorkingDirectory) { Push-Location -LiteralPath $WorkingDirectory }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $FilePath @Arguments 2>&1 | ForEach-Object {
            $line = "$_"
            Out-Host -InputObject $line
            if ($OnLine) { & $OnLine $line }
        }
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

function ConvertFrom-ByteSize {
    <# '2.3GiB', '12.0MiB', '915KiB' (formato do uv) → bytes. #>
    param([Parameter(Mandatory)][string]$Text)
    if ($Text -notmatch '^([\d.]+)\s*(B|KiB|MiB|GiB|TiB)$') { return 0 }
    $units = @{ B = 1; KiB = 1KB; MiB = 1MB; GiB = 1GB; TiB = 1TB }
    return [long]([double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture) * $units[$Matches[2]])
}

function New-UvDownloadTracker {
    return [pscustomobject]@{ Announced = @{}; Done = @{} }
}

function Update-UvDownloadTracker {
    <#
      Lê uma linha do uv: `Downloading torch (2.3GiB)` e ` Downloaded torch` (o uv só anuncia
      os pacotes grandes). Devolve $true se a linha mudou o progresso.
    #>
    param([Parameter(Mandatory)]$Tracker, [AllowEmptyString()][string]$Line)
    if ($Line -match '^\s*Downloading (\S+) \(([^)]+)\)\s*$') {
        $Tracker.Announced[$Matches[1]] = ConvertFrom-ByteSize $Matches[2]
        return $true
    }
    if ($Line -match '^\s*Downloaded (\S+)\s*$' -and $Tracker.Announced.ContainsKey($Matches[1])) {
        $Tracker.Done[$Matches[1]] = $true
        return $true
    }
    return $false
}

function Get-UvDownloadStatus {
    <# Bytes baixados / anunciados e a fração (0..1). #>
    param([Parameter(Mandatory)]$Tracker)
    [long]$total = 0
    [long]$done = 0
    foreach ($name in $Tracker.Announced.Keys) {
        $total += $Tracker.Announced[$name]
        if ($Tracker.Done.ContainsKey($name)) { $done += $Tracker.Announced[$name] }
    }
    $fraction = if ($total -gt 0) { $done / $total } else { 0.0 }
    return [pscustomobject]@{ Done = $done; Total = $total; Fraction = $fraction }
}

function Format-StemmaSize {
    <# Bytes → '2,9 GB' / '340 MB' (para as mensagens do instalador). #>
    param([Parameter(Mandatory)][double]$Bytes)
    $culture = [Globalization.CultureInfo]::GetCultureInfo('pt-BR')
    if ($Bytes -le 0) { return '0 MB' }
    if ($Bytes -ge 1GB) { return ($Bytes / 1GB).ToString('0.0', $culture) + ' GB' }
    return [Math]::Max(1, [Math]::Round($Bytes / 1MB)).ToString($culture) + ' MB'
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
    Write-Step 'Baixando o que falta dos componentes (~3 GB na primeira vez)'
    $tracker = New-UvDownloadTracker
    Invoke-Native -FilePath 'uv' -Arguments $arguments -OnLine {
        param($line)
        if (Update-UvDownloadTracker -Tracker $tracker -Line $line) {
            $status = Get-UvDownloadStatus -Tracker $tracker
            # O resto da etapa (instalar no venv) é rápido: o download vale 95%.
            Set-StemmaStageProgress ($status.Fraction * 0.95)
            Write-Step "Baixados $(Format-StemmaSize $status.Done) de $(Format-StemmaSize $status.Total)"
        }
    }
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
    if (-not (Test-IsAdmin)) {
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
    # Marcador vazio (escrita interrompida) = reinstalar.
    $line = Get-Content -LiteralPath $marker -TotalCount 1
    if (-not $line) { return $false }
    return "$line".Trim() -eq "$($Tool.Version) $($Tool.Sha256)"
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
    <#
      Ferramentas (todas, ou só as de -Names) + Python gerenciado; deixa o ambiente do processo
      apontando para elas. Na atualização, o FFmpeg e o Deno (usados pelo serviço) só são
      trocados com o serviço parado: -Names uv antes, -Names ffmpeg,deno -SkipPython depois.
    #>
    param([Parameter(Mandatory)][string]$Root, [string[]]$Names, [switch]$SkipPython)
    if (-not $Names) { $Names = @($script:Tools.Keys) }
    $done = 0
    foreach ($name in $Names) {
        Install-StemmaTool -Root $Root -Name $name | Out-Null
        $done++
        Set-StemmaStageProgress ($done / $Names.Count)
    }
    Set-StemmaToolEnv -Root $Root
    if ($SkipPython) { return }
    Install-StemmaPython -Root $Root
}

function Install-StemmaPython {
    <# Python gerenciado pelo uv em <Root>\tools\python (depois do Set-StemmaToolEnv). #>
    param([Parameter(Mandatory)][string]$Root)
    Write-Step "Python $script:PythonVersion"
    # Sem executável no ~\.local\bin nem registro no HKCU: nada do Stemma no perfil do usuário.
    Invoke-Native -FilePath (Get-StemmaPaths -Root $Root).Uv -Arguments @('python', 'install', $script:PythonVersion, '--no-bin', '--no-registry')
}

function Protect-StemmaDirectory {
    <#
      O serviço roda como SYSTEM e executa o que está em <Root> (scripts, tools, venvs) e carrega
      o que está nos dados (modelos do torch). Sem isto, a pasta herdaria "Usuários autenticados:
      Modificar" da raiz do drive, e qualquer processo sem elevação ganharia SYSTEM editando um
      arquivo. Fica: SYSTEM e Administradores com controle total, Usuários só leitura (o ícone
      da bandeja lê o .env e o setup\). A troca propaga para os arquivos ligados por hardlink do
      cache do usuário, que passam a ser só leitura para ele também (o cache do uv é imutável).
    #>
    param([Parameter(Mandatory)][string]$Path, [switch]$Force)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not $Force -and (Get-Acl -LiteralPath $Path).AreAccessRulesProtected) { return }
    Write-Step "Protegendo $Path (só administradores alteram)"
    # 1) a pasta: sem herança de cima, com entradas que os filhos herdam;
    Invoke-Native -FilePath 'icacls.exe' -Arguments @(
        $Path, '/inheritance:r', '/grant:r',
        '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-32-545:(OI)(CI)RX', '/Q'
    )
    if (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1) {
        # 2) os filhos só herdam (some qualquer entrada explícita, como as do cache do usuário);
        Invoke-Native -FilePath 'icacls.exe' -Arguments @((Join-Path $Path '*'), '/reset', '/T', '/C', '/Q')
    }
    # 3) o dono pode reescrever a ACL sem elevação, e os arquivos ligados do cache são do usuário.
    Invoke-Native -FilePath 'icacls.exe' -Arguments @($Path, '/setowner', '*S-1-5-32-544', '/T', '/C', '/Q')
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
    if ('Stemma.UvCacheSeeder' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
namespace Stemma {
    public static class UvCacheSeeder {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, IntPtr lpSecurityAttributes);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
        static extern uint SetNamedSecurityInfoW(string pObjectName, int objectType, uint securityInfo,
            byte[] psidOwner, IntPtr psidGroup, byte[] pDacl, IntPtr pSacl);

        const int SE_FILE_OBJECT = 1;
        const uint OWNER_SECURITY_INFORMATION = 0x1;
        const uint DACL_SECURITY_INFORMATION = 0x4;
        const uint PROTECTED_DACL_SECURITY_INFORMATION = 0x80000000;
        const int FILE_ALL_ACCESS = 0x1F01FF;
        const int FILE_READ_EXECUTE = 0x1200A9;

        static byte[] Sid(string value) {
            var sid = new SecurityIdentifier(value);
            byte[] bytes = new byte[sid.BinaryLength];
            sid.GetBinaryForm(bytes, 0);
            return bytes;
        }

        // Um hardlink é o mesmo arquivo do cache do usuário, com um descritor de segurança só,
        // e herdar a ACL do destino não basta: uma propagação de herança pelo outro caminho
        // (o perfil do usuário) o abriria de novo. Grava uma ACL própria e protegida (sem
        // herança): SYSTEM e Administradores com controle total, Usuários só leitura; com
        // setOwner, Administradores como dono. Um arquivo por vez, ao ligar: nada de percorrer
        // o cache inteiro com o icacls depois.
        public static bool Protect(string path, bool setOwner) {
            var acl = new RawAcl(GenericAcl.AclRevision, 3);
            acl.InsertAce(0, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, FILE_ALL_ACCESS, new SecurityIdentifier("S-1-5-18"), false, null));
            acl.InsertAce(1, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, FILE_ALL_ACCESS, new SecurityIdentifier("S-1-5-32-544"), false, null));
            acl.InsertAce(2, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, FILE_READ_EXECUTE, new SecurityIdentifier("S-1-5-32-545"), false, null));
            byte[] dacl = new byte[acl.BinaryLength];
            acl.GetBinaryForm(dacl, 0);
            uint info = DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION;
            byte[] owner = null;
            if (setOwner) {
                owner = Sid("S-1-5-32-544");
                info |= OWNER_SECURITY_INFORMATION;
            }
            return SetNamedSecurityInfoW(path, SE_FILE_OBJECT, info, owner, IntPtr.Zero, dacl, IntPtr.Zero) == 0;
        }

        // Recria em `dest` as subpastas `roots` de `source` (caminhos relativos) com hardlinks
        // (cópia se o link falhar), cada arquivo ligado com a ACL protegida acima. Se a ACL
        // não puder ser trocada, o link é desfeito (o uv baixa o que faltar). Arquivos que já
        // existem em `dest` ficam como estão. Pastas que são junction (formatos antigos do
        // cache) não são atravessadas: um processo elevado recusa junctions criadas pelo usuário
        // ("untrusted mount point"). Uma pasta ilegível não aborta o resto. Primeiro lista,
        // depois liga, avisando `progress(feitos, total)`.
        // Devolve {linked, copied, skipped, failed}.
        public static long[] Seed(string source, string dest, string[] roots, bool setOwner, Action<long, long> progress) {
            long[] counts = new long[4];
            source = Path.GetFullPath(source).TrimEnd('\\');
            dest = Path.GetFullPath(dest).TrimEnd('\\');
            var files = new List<string>();
            var pending = new Stack<string>();
            foreach (string root in roots) {
                string relative = root.Replace('/', '\\').Trim('\\');
                pending.Push(relative.Length == 0 ? source : source + "\\" + relative);
            }
            while (pending.Count > 0) {
                string dir = pending.Pop();
                string[] found, dirs;
                try {
                    Directory.CreateDirectory(dest + dir.Substring(source.Length));
                    found = Directory.GetFiles(dir);
                    dirs = Directory.GetDirectories(dir);
                }
                catch (Exception) { counts[3]++; continue; }
                foreach (string sub in dirs) {
                    try {
                        if ((File.GetAttributes(sub) & FileAttributes.ReparsePoint) != 0) { counts[2]++; continue; }
                    }
                    catch (Exception) { counts[3]++; continue; }
                    pending.Push(sub);
                }
                files.AddRange(found);
            }
            long total = files.Count, done = 0;
            foreach (string file in files) {
                string target = dest + file.Substring(source.Length);
                if (File.Exists(target)) {
                    // Já estava (nova tentativa, cache de uma versão anterior): protege de novo,
                    // porque a ACL pode ter sido mudada pelo outro caminho do mesmo arquivo.
                    Protect(target, setOwner);
                    counts[2]++;
                }
                else if (CreateHardLink(target, file, IntPtr.Zero)) {
                    if (Protect(target, setOwner)) { counts[0]++; }
                    else {
                        try { File.Delete(target); } catch (Exception) { }
                        counts[3]++;
                    }
                }
                else {
                    // A cópia é um arquivo novo: já nasce com a ACL herdada do destino.
                    try { File.Copy(file, target); counts[1]++; }
                    catch (Exception) { counts[3]++; }
                }
                done++;
                if (progress != null && (done % 500 == 0 || done == total)) { progress(done, total); }
            }
            return counts;
        }
    }
}
'@
}

function Test-IsAdmin {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-UvPackageKey {
    <# Chave nome|versão (nome normalizado como no PEP 503). #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Version)
    return (ConvertTo-UvPackageName $Name) + '|' + $Version
}

function Get-UvLockPackages {
    <#
      Pacotes do uv.lock com o que interessa no Windows x64: a wheel (`win_amd64` ou `any`) e o
      tamanho dela, quando o índice informa (o do PyTorch não informa). Needed = há wheel para
      o Windows ou só sdist; pacotes só de Linux (nvidia-*, triton) e o próprio projeto ficam fora.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $text = [IO.File]::ReadAllText($Path)
    foreach ($block in @($text -split '(?m)^\[\[package\]\]\s*$' | Select-Object -Skip 1)) {
        if ($block -notmatch '(?m)^name = "([^"]+)"') { continue }
        $name = $Matches[1]
        if ($block -notmatch '(?m)^version = "([^"]+)"') { continue }
        $version = $Matches[1]
        $wheel = $null
        $size = $null
        $wheelLines = [regex]::Matches($block, '\{ url = "([^"]+\.whl)"[^\r\n]*')
        foreach ($match in $wheelLines) {
            $file = [Uri]::UnescapeDataString(($match.Groups[1].Value -split '/')[-1])
            if ($file -match '-(win_amd64|any)\.whl$') {
                $wheel = $file
                if ($match.Value -match 'size = (\d+)') { $size = [long]$Matches[1] }
                break
            }
        }
        $sdistOnly = $wheelLines.Count -eq 0 -and $block -match '(?m)^sdist = '
        if ($sdistOnly -and $block -match '(?m)^sdist = .*size = (\d+)') { $size = [long]$Matches[1] }
        [pscustomobject]@{
            Name    = $name
            Version = $version
            Key     = ConvertTo-UvPackageKey $name $version
            Wheel   = $wheel
            Size    = $size
            Needed  = [bool]($wheel -or $sdistOnly)
        }
    }
}

function Get-UvCachePointers {
    <#
      Ponteiros do cache do uv: `wheels-v*\…\<pacote>\<versão>-<tags>` é um arquivo texto com
      `archive-v0/<id>` (a wheel descompactada). Devolve chave nome|versão → archives que existem.
      Depende do formato interno do uv: se mudar, não acha nada, e quem chama cai no caminho
      completo (semear tudo, baixar o que faltar).
    #>
    param([Parameter(Mandatory)][string]$Cache)
    $result = @{}
    if (-not (Test-Path -LiteralPath $Cache -PathType Container)) { return $result }
    $pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    foreach ($bucket in @(Get-ChildItem -LiteralPath $Cache -Directory -Force -Filter 'wheels-v*' -ErrorAction SilentlyContinue)) {
        if (-not ($bucket.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $pending.Push($bucket) }
    }
    while ($pending.Count -gt 0) {
        $dir = $pending.Pop()
        try { $children = $dir.GetFileSystemInfos() }
        catch { continue }
        foreach ($child in $children) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($child -is [IO.DirectoryInfo]) { $pending.Push($child); continue }
            if ($child.Name -match '\.(http|lock|msgpack|rev)$' -or $child.Length -gt 256) { continue }
            try { $line = "$([IO.File]::ReadAllText($child.FullName))".Trim() }
            catch { continue }
            if ($line -notmatch '^archive-v\d+/[\w-]+$') { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $Cache $line) -PathType Container)) { continue }
            $key = ConvertTo-UvPackageKey $child.Directory.Name ($child.Name -split '-')[0]
            if (-not $result.ContainsKey($key)) { $result[$key] = [Collections.Generic.List[string]]::new() }
            $result[$key].Add($line)
        }
    }
    return $result
}

function ConvertTo-UvPackageName([string]$Name) { return $Name.ToLowerInvariant() -replace '[-_.]+', '-' }

function Get-BuildBackendNames {
    <# Nomes (normalizados) do `[build-system] requires` do pyproject (ex.: hatchling). #>
    param([Parameter(Mandatory)][string]$PyprojectPath)
    $names = @()
    if (Test-Path -LiteralPath $PyprojectPath) {
        $text = [IO.File]::ReadAllText($PyprojectPath)
        # Só dentro da seção [build-system] (até o próximo cabeçalho), nunca de outra seção.
        $section = if ($text -match '(?ms)^\[build-system\][ \t]*\r?\n(.*?)(?=^\[|\z)') { $Matches[1] } else { '' }
        if ($section -match '(?ms)^requires\s*=\s*\[([^\]]*)\]') {
            foreach ($item in [regex]::Matches($Matches[1], '"([A-Za-z0-9._-]+)')) {
                $names += ConvertTo-UvPackageName $item.Groups[1].Value
            }
        }
    }
    # O uv instala o projeto como editável, e o hatchling pede o `editables` só nessa hora
    # (get_requires_for_build_editable): não está no METADATA dele.
    if ($names -contains 'hatchling') { $names += 'editables' }
    return @($names | Sort-Object -Unique)
}

function Get-WheelRequires {
    <#
      Dependências (nomes normalizados) de uma wheel descompactada no cache, pelo `Requires-Dist`
      do METADATA. Pula as de extras; mantém as com outros marcadores (sobra pouco, nunca falta).
    #>
    param([Parameter(Mandatory)][string]$ArchiveDir)
    $metadata = @(Get-ChildItem -LiteralPath $ArchiveDir -Directory -Filter '*.dist-info' -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'METADATA' } | Where-Object { Test-Path -LiteralPath $_ })
    if ($metadata.Count -eq 0) { return @() }
    $names = foreach ($line in [IO.File]::ReadAllLines($metadata[0])) {
        if ($line -eq '') { break }  # fim do cabeçalho
        if ($line -match '^Requires-Dist:\s*([A-Za-z0-9._-]+)' -and $line -notmatch 'extra\s*==') {
            ConvertTo-UvPackageName $Matches[1]
        }
    }
    return @($names | Sort-Object -Unique)
}

function Get-BuildBackendArchives {
    <#
      Archives do build backend (que o uv usa para construir o próprio projeto no sync e que não
      está no uv.lock) e das dependências dele, lidas do METADATA no cache, em qualquer versão.
    #>
    param([Parameter(Mandatory)][string]$Cache, [Parameter(Mandatory)][hashtable]$Pointers, [string[]]$Names)
    $byName = @{}
    foreach ($key in $Pointers.Keys) {
        $name = ($key -split '\|')[0]
        if (-not $byName.ContainsKey($name)) { $byName[$name] = [Collections.Generic.List[string]]::new() }
        foreach ($archive in $Pointers[$key]) { $byName[$name].Add($archive) }
    }
    $seen = @{}
    $archives = [Collections.Generic.List[string]]::new()
    $pending = [Collections.Generic.Queue[string]]::new()
    foreach ($name in $Names) { $pending.Enqueue($name) }
    while ($pending.Count -gt 0) {
        $name = $pending.Dequeue()
        if ($seen.ContainsKey($name)) { continue }
        $seen[$name] = $true
        if (-not $byName.ContainsKey($name)) { continue }
        foreach ($archive in $byName[$name]) {
            $archives.Add($archive)
            foreach ($dep in (Get-WheelRequires -ArchiveDir (Join-Path $Cache $archive))) { $pending.Enqueue($dep) }
        }
    }
    return @($archives)
}

function Get-UvCacheSeedPlan {
    <#
      O que semear do cache do usuário: as pastas pequenas inteiras (tudo menos `archive-v*`) e,
      dos archives, só os dos pacotes do uv.lock (o cache do usuário tem os de todos os projetos
      dele: 225 mil arquivos contra ~25 mil do Stemma). Sem lock, ou num formato de cache que não
      conhece (sem ponteiros): tudo.
    #>
    param([Parameter(Mandatory)][string]$Source, [string]$LockPath)
    $roots = [Collections.Generic.List[string]]::new()
    $archiveDirs = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $Source -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($dir.Name -match '^archive-v\d+$') { $archiveDirs += $dir.Name } else { $roots.Add($dir.Name) }
    }
    $pointers = @{}
    $archives = @()
    if ($LockPath -and (Test-Path -LiteralPath $LockPath)) {
        $pointers = Get-UvCachePointers -Cache $Source
        $fromLock = @(foreach ($package in @(Get-UvLockPackages -Path $LockPath)) {
                if ($pointers.ContainsKey($package.Key)) { $pointers[$package.Key] }
            })
        # O uv constrói o próprio projeto no sync, e o build backend não está no uv.lock (sem
        # ele, o --offline falha só por causa do hatchling e das dependências dele).
        $build = @(Get-BuildBackendNames -PyprojectPath (Join-Path (Split-Path -Parent $LockPath) 'pyproject.toml'))
        $fromBuild = @(Get-BuildBackendArchives -Cache $Source -Pointers $pointers -Names $build)
        $archives = @(@($fromLock + $fromBuild) | Sort-Object -Unique)
    }
    # Seletivo sempre que o formato foi reconhecido (há ponteiros), mesmo sem nenhum pacote do
    # Stemma no cache: aí semeia só as pastas pequenas, e não o cache inteiro do usuário.
    $selective = $archives.Count -gt 0 -or $pointers.Count -gt 0
    if (-not $selective) { $archives = $archiveDirs }
    foreach ($archive in $archives) { $roots.Add($archive) }
    return [pscustomobject]@{ Roots = @($roots); Selective = $selective; Archives = @($archives).Count }
}

function Copy-UvCacheSeed {
    <#
      Semeia <Root>\cache\uv com o cache do usuário por hardlink (segundos, sem espaço extra; um
      `uv cache clean` do usuário não afeta), só com o que o -LockPath usa. Cada arquivo ligado
      ganha uma ACL própria e protegida (só administradores alteram), que vale também no cache
      do usuário, porque é o mesmo arquivo. Em outro volume não semeia:
      copiar o cache inteiro (dezenas de GB) sai mais caro que baixar o que falta. Devolve um
      resumo ou $null.
    #>
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Dest, [string]$LockPath)
    $src = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    $dst = [IO.Path]::GetFullPath($Dest).TrimEnd('\')
    if ($src -eq $dst) { return $null }
    if (-not (Test-SameVolume $src $dst)) {
        Write-Host "    Cache do uv em outro volume ($src): sem semear."
        return $null
    }
    $plan = Get-UvCacheSeedPlan -Source $src -LockPath $LockPath
    if ($plan.Selective) { Write-Step "Reaproveitando os componentes já baixados neste PC ($($plan.Archives) pacotes)" }
    else { Write-Step 'Reaproveitando os componentes já baixados neste PC (cache inteiro)' }
    Initialize-HardLinkSeeder
    $progress = [Action[long, long]] { param($done, $total) Set-StemmaStageProgress ($done / [Math]::Max(1, $total)) }
    $counts = [Stemma.UvCacheSeeder]::Seed($src, $dst, [string[]]$plan.Roots, (Test-IsAdmin), $progress)
    $summary = [pscustomobject]@{
        Linked = $counts[0]; Copied = $counts[1]; Skipped = $counts[2]; Failed = $counts[3]; Selective = $plan.Selective
    }
    Write-Host "    $($summary.Linked) arquivos ligados, $($summary.Copied) copiados, $($summary.Skipped) já estavam, $($summary.Failed) falharam."
    return $summary
}

function Optimize-StemmaUvCache {
    <#
      Deixa em <Root>\cache\uv só o que os uv.lock das versões instaladas usam. A instalação
      da v1.4.0 semeou o cache do usuário inteiro (pacotes de todos os projetos dele): esses
      arquivos não ocupam espaço a mais enquanto o cache do usuário também os tem, mas ficam
      presos aqui quando ele limpa o dele. Monta um cache novo por hardlink a partir do atual
      (mesmo volume: segundos, sem espaço extra), troca e apaga o antigo. Os venvs não mudam
      (cada arquivo deles é outro link). Num formato de cache sem ponteiros não mexe em nada.
    #>
    param([Parameter(Mandatory)][string]$Root)
    $paths = Get-StemmaPaths -Root $Root
    $cache = $paths.UvCache
    if (Test-EmptyDirectory $cache) { return $null }
    $locks = @(Get-InstalledReleases -Root $Root | ForEach-Object { Join-Path $_.Path 'backend\uv.lock' } |
            Where-Object { Test-Path -LiteralPath $_ })
    if ($locks.Count -eq 0) { return $null }
    foreach ($lock in $locks) {
        if (-not (Get-UvCacheSeedPlan -Source $cache -LockPath $lock).Selective) {
            Write-Host '    Cache do uv num formato desconhecido: mantido como está.'
            return $null
        }
    }
    $fresh = "$cache.novo"
    $old = "$cache.antigo"
    foreach ($dir in $fresh, $old) { Remove-StemmaTree -Path $dir }
    Write-Step 'Enxugando o cache de componentes (só o que as versões instaladas usam)'
    foreach ($lock in $locks) { Copy-UvCacheSeed -Source $cache -Dest $fresh -LockPath $lock | Out-Null }
    [IO.Directory]::Move($cache, $old)
    [IO.Directory]::Move($fresh, $cache)
    $before = @(Get-ChildItem -LiteralPath $old -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $after = @(Get-ChildItem -LiteralPath $cache -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    Remove-StemmaTree -Path $old
    Write-Host "    cache do uv: $before → $after arquivos"
    return [pscustomobject]@{ Before = $before; After = $after }
}

function Get-StemmaCacheDirs {
    <#
      Caches que a instalação vai usar: o dela, se já tiver algo (a atualização só semeia de um
      cache vazio); senão, o do usuário no mesmo volume, que será semeado.
    #>
    param([Parameter(Mandatory)][string]$Root, [string]$UserCache)
    $own = (Get-StemmaPaths -Root $Root).UvCache
    if (-not (Test-EmptyDirectory $own)) { return @($own) }
    if ($UserCache -and (Test-SameVolume $UserCache $Root)) { return @($UserCache) }
    return @()
}

# Wheels sem tamanho no uv.lock (o índice do PyTorch não informa).
$script:UnknownWheelSizes = @{ torch = [long]2.9GB }
$script:UnknownWheelSize = 20MB
# Ferramentas + Python em <Root>\tools, com folga (medido: ~0,5 GB).
$script:ToolsBytes = 600MB

function Get-StemmaSpaceEstimate {
    <#
      Antes de instalar ou atualizar: quanto vai ser baixado (pacotes do uv.lock que não estão nos
      caches) e quanto ocupa no drive da raiz (ferramentas, se faltarem, e os pacotes
      descompactados, ~2x o download). Estimativa, com folga.
    #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$LockPath, [string[]]$CacheDirs = @())
    $present = @{}
    foreach ($cache in $CacheDirs) {
        foreach ($key in (Get-UvCachePointers -Cache $cache).Keys) { $present[$key] = $true }
    }
    $needed = @(Get-UvLockPackages -Path $LockPath | Where-Object { $_.Needed })
    $missing = @($needed | Where-Object { -not $present.ContainsKey($_.Key) })
    [long]$download = 0
    foreach ($package in $missing) {
        if ($null -ne $package.Size) { $download += $package.Size }
        elseif ($script:UnknownWheelSizes.ContainsKey($package.Name)) { $download += $script:UnknownWheelSizes[$package.Name] }
        else { $download += $script:UnknownWheelSize }
    }
    [long]$need = 2 * $download
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'tools\uv\uv.exe'))) { $need += $script:ToolsBytes }
    return [pscustomobject]@{
        DownloadBytes = $download
        NeedRootBytes = $need
        Missing       = $missing.Count
        Needed        = $needed.Count
    }
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

function Set-DotEnvValue {
    <# Troca (ou acrescenta) `CHAVE=valor`, mantendo o resto do arquivo. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    $lines = @()
    if (Test-Path -LiteralPath $Path) { $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8) }
    $found = $false
    $lines = @(foreach ($line in $lines) {
            if ($line -match "^\s*$([regex]::Escape($Key))\s*=") { $found = $true; "$Key=$Value" } else { $line }
        })
    if (-not $found) { $lines += "$Key=$Value" }
    Write-DotEnvLines $Path $lines
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
    $info = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    # Instalações da v1.4.0 não gravavam a porta HTTPS: era sempre a 443.
    if (-not $info.PSObject.Properties['httpsPort']) { $info | Add-Member -NotePropertyName httpsPort -NotePropertyValue 443 }
    return $info
}

function Set-StemmaInstallInfo {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ServiceId,
        [bool]$TailscaleServe,
        [int]$HttpsPort = 443
    )
    $info = [ordered]@{ serviceId = $ServiceId; tailscaleServe = $TailscaleServe; httpsPort = $HttpsPort }
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

function Get-StemmaServeTarget([int]$Port) {
    <# O que o tailscale serve aponta quando publica o Stemma desta porta. #>
    return "http://127.0.0.1:$Port"
}

function ConvertFrom-TailscaleServeStatus {
    <#
      `tailscale serve status --json` → o que a porta HTTPS `$HttpsPort` publica: o proxy do
      "/", '(outro)' (site que não é um proxy simples), '(outro: TCP)' (serve --tcp ou
      --tls-terminated-tcp), '(desconhecido)' (saída que não é JSON) ou $null se está livre.
    #>
    param([AllowEmptyString()][string]$Json, [Parameter(Mandatory)][int]$HttpsPort)
    if (-not $Json -or -not $Json.Trim()) { return $null }
    try { $status = $Json | ConvertFrom-Json }
    catch { return '(desconhecido)' }
    if (-not $status) { return $null }
    if ($status.PSObject.Properties['Web'] -and $status.Web) {
        foreach ($site in $status.Web.PSObject.Properties) {
            if ($site.Name -notmatch ":$HttpsPort$") { continue }
            $handlers = $site.Value.Handlers
            if ($handlers -and $handlers.PSObject.Properties['/'] -and $handlers.'/'.PSObject.Properties['Proxy']) {
                return "$($handlers.'/'.Proxy)"
            }
            return '(outro)'
        }
    }
    # Sem site web nessa porta, ela ainda pode estar num encaminhamento TCP.
    if ($status.PSObject.Properties['TCP'] -and $status.TCP -and $status.TCP.PSObject.Properties["$HttpsPort"]) {
        return '(outro: TCP)'
    }
    return $null
}

function Get-TailscaleServeJson {
    <# Saída de `tailscale serve status --json` (vazia sem Tailscale). Leia uma vez e consulte várias portas. #>
    $exe = Get-TailscaleExe
    if (-not $exe) { return '' }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { return (& $exe serve status --json 2>$null) -join "`n" }
    finally { $ErrorActionPreference = $previous }
}

function Get-TailscaleServeTarget {
    param([int]$HttpsPort = 443, [AllowEmptyString()][string]$Json)
    if (-not $PSBoundParameters.ContainsKey('Json')) { $Json = Get-TailscaleServeJson }
    return ConvertFrom-TailscaleServeStatus -Json $Json -HttpsPort $HttpsPort
}

function Get-ServePortState {
    <#
      Regra única (instalador, atualização e desinstalador): a porta HTTPS do Tailscale está
      'free', já publica este Stemma ('ours', pela porta local) ou publica outro app ('other').
    #>
    param([AllowEmptyString()][AllowNull()][string]$Target, [Parameter(Mandatory)][int]$Port)
    if (-not $Target) { return 'free' }
    if ($Target -eq (Get-StemmaServeTarget $Port)) { return 'ours' }
    return 'other'
}

function Set-TailscaleServe {
    param([Parameter(Mandatory)][int]$Port, [int]$HttpsPort = 443)
    $exe = Get-TailscaleExe
    if (-not $exe) { throw 'Tailscale não instalado: instale e faça login, ou use -SkipTailscale.' }
    Write-Step "Publicando no Tailscale (HTTPS na $HttpsPort)"
    Invoke-Native -FilePath $exe -Arguments @('serve', '--bg', "--https=$HttpsPort", (Get-StemmaServeTarget $Port))
}

function Remove-TailscaleServe {
    <#
      Desliga a porta HTTPS só se ela ainda publica este Stemma. Chame depois de remover o
      serviço: se ainda há alguém escutando na porta local, outra instalação usa o mesmo
      endereço (ex.: um ensaio na mesma porta), e a porta HTTPS é dela.
    #>
    param([Parameter(Mandatory)][int]$Port, [int]$HttpsPort = 443)
    $exe = Get-TailscaleExe
    if (-not $exe) { return }
    $target = Get-TailscaleServeTarget -HttpsPort $HttpsPort
    switch (Get-ServePortState -Target $target -Port $Port) {
        'free' { return }
        'other' {
            Write-Host "    A $HttpsPort do Tailscale publica '$target', não este Stemma: fica como está."
            return
        }
    }
    $usage = Get-PortUsage -Port $Port
    if ($usage) {
        Write-Host "    A porta $Port continua $($usage): outro app usa a $HttpsPort do Tailscale, fica como está."
        return
    }
    Write-Step "Desligando o tailscale serve da $HttpsPort"
    Invoke-Native -FilePath $exe -Arguments @('serve', "--https=$HttpsPort", 'off')
}

# --- portas locais ------------------------------------------------------------------

function ConvertFrom-ExcludedPortRanges {
    <# Saída do `netsh int ipv4 show excludedportrange protocol=tcp` → faixas {Start, End}. #>
    param([AllowEmptyCollection()][string[]]$Lines)
    return @(foreach ($line in $Lines) {
            if ($line -match '^\s*(\d+)\s+(\d+)') { [pscustomobject]@{ Start = [int]$Matches[1]; End = [int]$Matches[2] } }
        })
}

function Get-ExcludedPortRanges {
    <# Faixas que o Windows reserva (Hyper-V, WSL, Docker): escutar nelas falha com "acesso negado". #>
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $lines = & netsh.exe int ipv4 show excludedportrange protocol=tcp 2>$null }
    finally { $ErrorActionPreference = $previous }
    return ConvertFrom-ExcludedPortRanges $lines
}

function Get-ListeningPorts {
    <# Porta → PID de quem escuta (uma consulta só; para varrer muitas portas). #>
    $map = @{}
    foreach ($connection in @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)) {
        if ($connection) { $map[[int]$connection.LocalPort] = $connection.OwningProcess }
    }
    return $map
}

function Get-PortUsage {
    <# Por que a porta não serve ("em uso por python (PID 123)", "reservada pelo Windows…") ou $null se está livre. #>
    param([Parameter(Mandatory)][int]$Port, [object[]]$ExcludedRanges, [hashtable]$Listening)
    if ($null -eq $ExcludedRanges) { $ExcludedRanges = Get-ExcludedPortRanges }
    if ($null -eq $Listening) { $Listening = Get-ListeningPorts }
    if ($Listening.ContainsKey($Port)) {
        $owner = $Listening[$Port]
        $process = Get-Process -Id $owner -ErrorAction SilentlyContinue
        $name = if ($process) { $process.ProcessName } else { 'outro programa' }
        return "em uso por $name (PID $owner)"
    }
    foreach ($range in $ExcludedRanges) {
        if ($Port -ge $range.Start -and $Port -le $range.End) {
            return "reservada pelo Windows ($($range.Start)–$($range.End): Hyper-V, WSL ou Docker)"
        }
    }
    return $null
}

function Find-FreePort {
    <# A primeira porta livre a partir de `$Start` (até 200 adiante), com uma consulta só. #>
    param([int]$Start = 8000)
    $ranges = Get-ExcludedPortRanges
    $listening = Get-ListeningPorts
    for ($port = $Start; $port -lt $Start + 200 -and $port -le 65535; $port++) {
        if (-not (Get-PortUsage -Port $port -ExcludedRanges $ranges -Listening $listening)) { return $port }
    }
    return $null
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

function Assert-StemmaDataRoot {
    <# A pasta de dados não pode ser a raiz de um drive: o desinstalador (-RemoveData) a apaga inteira. #>
    param([Parameter(Mandatory)][string]$Path)
    # "D:" sozinho é o diretório atual do drive para o GetFullPath, mas o desinstalador o leria como o drive.
    if ($Path.Trim() -match '^[A-Za-z]:\\?$') { $full = $Path.Trim().Substring(0, 2) }
    else { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    if ($full.Length -le 2 -or [IO.Path]::GetPathRoot("$full\") -eq "$full\") {
        throw "Escolha uma pasta para os dados (ex.: D:\stemma-data), não a raiz do drive ($Path)."
    }
}

function Test-EmptyDirectory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    return -not (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)
}

function Initialize-StemmaRuntime {
    <# Ferramentas em tools\, ambiente do processo e chaves novas no .env de uma instalação existente. #>
    param([Parameter(Mandatory)][string]$Root, [string[]]$Names, [switch]$SkipPython)
    Install-StemmaTools -Root $Root -Names $Names -SkipPython:$SkipPython
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
        [int]$HttpsPort = 443,
        [int]$HealthTimeoutSec = 180,
        # Pasta do setup.ps1 do instalador: cria as tarefas da atualização pelo app (ADR 0015).
        [string]$EngineDir
    )
    $userCache = Find-UserUvCache  # antes do Set-StemmaToolEnv, que troca o UV_CACHE_DIR
    $seed = $userCache -and (Test-SameVolume $userCache $Root)
    # Pesos ~ dezenas de segundos medidos na instalação real; os componentes são repesados
    # depois de semear, quando se sabe quanto falta baixar.
    $stages = @(
        @{ Id = 'check'; Text = 'Conferindo o PC'; Weight = 1 }
        @{ Id = 'protect'; Text = 'Protegendo as pastas'; Weight = 1 }
        @{ Id = 'package'; Text = 'Extraindo o Stemma'; Weight = 2 }
        @{ Id = 'tools'; Text = 'Baixando as ferramentas (uv, FFmpeg, Deno)'; Weight = 5 }
        @{ Id = 'python'; Text = 'Python 3.12'; Weight = 3 }
    )
    if ($seed) { $stages += @{ Id = 'seed'; Text = 'Reaproveitando os componentes deste PC'; Weight = 3 } }
    $stages += @(
        @{ Id = 'components'; Text = 'Componentes do Stemma'; Weight = 2 }
        @{ Id = 'database'; Text = 'Banco de dados'; Weight = 1 }
        @{ Id = 'service'; Text = 'Iniciando o serviço'; Weight = 5 }
    )
    Start-StemmaProgress -Stages $stages
    Enter-StemmaStage 'check'
    if (Test-StemmaService $ServiceId) { throw "O serviço '$ServiceId' já existe. Use a atualização." }
    if (-not $DataRoot) { $DataRoot = Get-DefaultDataRoot }
    Assert-StemmaDataRoot $DataRoot
    # A porta vem livre do assistente, mas pode ter sido tomada até aqui: passa para a próxima
    # livre (não há tela de porta para o usuário escolher outra).
    $usage = Get-PortUsage -Port $Port
    if ($usage) {
        $free = Find-FreePort -Start ($Port + 1)
        if (-not $free) { throw "A porta $Port está $usage, e não achei outra livre até a $($Port + 200)." }
        Write-Host "    A porta $Port está $($usage): usando a $free."
        $Port = $free
    }
    if (-not $SkipTailscale) {
        # Antes de tudo: sem isto, a instalação iria até o fim e falharia no último passo.
        $tailscale = Get-TailscaleState
        if ($tailscale.State -ne 'ready') {
            throw "O Tailscale não está pronto ($($tailscale.State)): instale, faça login e ative o HTTPS, ou use -SkipTailscale."
        }
    }

    # Antes de criar qualquer coisa dentro: tudo o que vier depois (ferramentas, releases, venv)
    # já nasce herdando a ACL certa, e não é preciso percorrer tudo com o icacls. Os arquivos
    # ligados do cache do usuário não herdam (hardlink); o seeder protege cada um ao ligar.
    Enter-StemmaStage 'protect'
    foreach ($dir in $Root, $DataRoot) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Protect-StemmaDirectory -Path $Root
    Protect-StemmaDirectory -Path $DataRoot
    foreach ($dir in (Join-Path $Root 'releases'), (Join-Path $Root 'logs')) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $paths = Get-StemmaPaths -Root $Root

    Enter-StemmaStage 'package'
    $package = Get-StemmaPackage -Root $Root -Version $Version -ZipPath $ZipPath
    Write-Step "Extraindo $($package.Tag)"
    $release = Expand-StemmaPackage -Root $Root -Zip $package.Zip -Tag $package.Tag
    $lock = Join-Path $release 'backend\uv.lock'

    Enter-StemmaStage 'tools'
    Initialize-StemmaRuntime -Root $Root -SkipPython
    Enter-StemmaStage 'python'
    Install-StemmaPython -Root $Root
    if ($seed) {
        Enter-StemmaStage 'seed'
        Copy-UvCacheSeed -Source $userCache -Dest $paths.UvCache -LockPath $lock | Out-Null
    }

    if (-not (Test-Path -LiteralPath $paths.EnvFile)) {
        Write-Step "Criando $($paths.EnvFile)"
        New-StemmaEnvFile -Path $paths.EnvFile -Port $Port -DataRoot $DataRoot -FfmpegBin $paths.Ffmpeg
    }
    else {
        # Nova tentativa depois de uma instalação que falhou: vale o que foi escolhido agora.
        Set-DotEnvValue -Path $paths.EnvFile -Key 'PORT' -Value "$Port"
        Set-DotEnvValue -Path $paths.EnvFile -Key 'STORAGE_ROOT' -Value $DataRoot
    }
    $context = Get-StemmaContext -Root $Root

    Set-ComponentsStageWeight -Root $Root -LockPath $lock
    Enter-StemmaStage 'components'
    Sync-ReleaseEnvironment -ReleaseDir $release -PreferOffline | Out-Null

    Enter-StemmaStage 'database'
    Import-DotEnv -Path $paths.EnvFile | Out-Null
    Invoke-Alembic -ReleaseDir $release -Arguments @('upgrade', 'head')
    Set-CurrentRelease -Root $Root -ReleaseDir $release

    Enter-StemmaStage 'service'
    # Antes de subir o serviço: ele lê o UPDATE_TASK do .env ao iniciar.
    if ($EngineDir) { Register-StemmaTasks -Root $Root -ServiceId $ServiceId -EngineDir $EngineDir }
    Register-StemmaService -Root $Root -ServiceId $ServiceId -ReleaseDir $release
    Set-StemmaInstallInfo -Root $Root -ServiceId $ServiceId -TailscaleServe (-not $SkipTailscale) -HttpsPort $HttpsPort
    Start-StemmaService -ServiceId $ServiceId
    if (-not (Wait-StemmaHealth -Port $context.Port -ExpectedVersion $package.Tag -TimeoutSec $HealthTimeoutSec)) {
        throw "O serviço subiu mas o /health não confirmou a versão. Veja os logs em $(Join-Path $Root 'logs')."
    }
    # A escolha entre substituir a 443 de outro app ou usar a 8443 é feita antes (tela do Tailscale).
    if (-not $SkipTailscale) { Set-TailscaleServe -Port $context.Port -HttpsPort $HttpsPort }
    try { Optimize-StemmaUvCache -Root $Root | Out-Null }
    catch { Write-Warning "Cache do uv não foi enxugado: $($_.Exception.Message)" }
    Complete-StemmaProgress
    Write-Step "Stemma $($package.Tag) instalado em $Root"
    return $package.Tag
}

function Set-ComponentsStageWeight {
    <# Repesa a etapa dos componentes pelo que falta no cache da instalação (~5 MB/s de download). #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$LockPath)
    try {
        $estimate = Get-StemmaSpaceEstimate -Root $Root -LockPath $LockPath -CacheDirs @((Get-StemmaPaths -Root $Root).UvCache)
        Set-StemmaStageWeight -Id 'components' -Weight (2 + $estimate.DownloadBytes / 50MB)
    }
    catch { Write-Verbose "Estimativa dos componentes: $_" }
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
        [int]$HealthTimeoutSec = 180,
        # Pasta do setup.ps1 do instalador: (re)cria as tarefas da atualização pelo app (ADR 0015).
        [string]$EngineDir
    )
    $context = Get-StemmaContext -Root $Root
    if (-not $context.Current) { throw "Nenhuma release em $Root\current. Faça a instalação primeiro." }
    $current = $context.Current
    $currentTag = $context.CurrentTag
    $paths = Get-StemmaPaths -Root $Root
    $userCache = Find-UserUvCache  # antes do Set-StemmaToolEnv, que troca o UV_CACHE_DIR
    # Instalação feita pelos scripts da F5 (cache no perfil do usuário): semeia como na instalação.
    $seed = $userCache -and (Test-EmptyDirectory $paths.UvCache) -and (Test-SameVolume $userCache $Root)
    $stages = @(
        @{ Id = 'check'; Text = 'Conferindo a instalação'; Weight = 1 }
        @{ Id = 'tools'; Text = 'Ferramentas'; Weight = 2 }
        @{ Id = 'package'; Text = 'Extraindo a versão nova'; Weight = 2 }
    )
    if ($seed) { $stages += @{ Id = 'seed'; Text = 'Reaproveitando os componentes deste PC'; Weight = 3 } }
    $stages += @(
        @{ Id = 'components'; Text = 'Componentes da versão nova'; Weight = 2 }
        @{ Id = 'stop'; Text = 'Parando o Stemma'; Weight = 1 }
        @{ Id = 'backup'; Text = 'Backup do banco'; Weight = 1 }
        @{ Id = 'database'; Text = 'Atualizando o banco'; Weight = 1 }
        @{ Id = 'service'; Text = 'Iniciando a versão nova'; Weight = 4 }
        @{ Id = 'cleanup'; Text = 'Limpando versões antigas'; Weight = 1 }
    )
    Start-StemmaProgress -Stages $stages
    Enter-StemmaStage 'check'
    # Antes de criar qualquer coisa: o que vier depois já herda a ACL (rápido se já protegida).
    Protect-StemmaDirectory -Path $Root
    Protect-StemmaDirectory -Path $context.StorageRoot
    Enter-StemmaStage 'tools'
    # Com o serviço no ar, só o uv e o Python (o serviço usa FFmpeg e Deno; eles vêm depois de parar).
    Initialize-StemmaRuntime -Root $Root -Names @('uv')
    # Antes de reiniciar o serviço (ele lê o UPDATE_TASK do .env ao iniciar). Instalações
    # anteriores à F5c ganham as tarefas aqui.
    if ($EngineDir) { Register-StemmaTasks -Root $Root -ServiceId $ServiceId -EngineDir $EngineDir }
    $context = Get-StemmaContext -Root $Root  # o .env pode ter ganhado chaves

    Enter-StemmaStage 'package'
    $package = Get-StemmaPackage -Root $Root -Version $Version -ZipPath $ZipPath
    $target = $package.Tag
    if ($target -eq $currentTag) {
        # Mesma versão (ex.: instalação que falhou no meio e foi rodada de novo): só confere
        # ferramentas, serviço e /health.
        Enter-StemmaStage 'service'
        Write-Step "Já está na $($target): conferindo"
        Import-DotEnv -Path (Join-Path $Root '.env') | Out-Null
        $running = (Get-Service -Name $ServiceId).Status -eq 'Running'
        if (-not $running) { Initialize-StemmaRuntime -Root $Root -Names @('ffmpeg', 'deno') -SkipPython }
        if (-not $running) { Start-StemmaService -ServiceId $ServiceId }
        if (-not (Wait-StemmaHealth -Port $context.Port -ExpectedVersion $target -TimeoutSec $HealthTimeoutSec)) {
            throw "A $target não respondeu no /health. Veja os logs em $Root\logs."
        }
        Complete-StemmaProgress
        return $target
    }

    Write-Step "Atualizando $currentTag → $target"
    $release = Expand-StemmaPackage -Root $Root -Zip $package.Zip -Tag $target
    $lock = Join-Path $release 'backend\uv.lock'
    if ($seed) {
        Enter-StemmaStage 'seed'
        Copy-UvCacheSeed -Source $userCache -Dest $paths.UvCache -LockPath $lock | Out-Null
    }
    Set-ComponentsStageWeight -Root $Root -LockPath $lock
    Enter-StemmaStage 'components'
    Sync-ReleaseEnvironment -ReleaseDir $release -PreferOffline | Out-Null
    Import-DotEnv -Path (Join-Path $Root '.env') | Out-Null

    Enter-StemmaStage 'stop'
    Stop-StemmaService -ServiceId $ServiceId
    $backup = $null
    try {
        # Com o serviço parado: FFmpeg e Deno podem ser trocados (nenhum processo os usa).
        Initialize-StemmaRuntime -Root $Root -Names @('ffmpeg', 'deno') -SkipPython
        Enter-StemmaStage 'backup'
        if (Test-StemmaDatabase $context) {
            Write-Step 'Backup do banco'
            $dest = New-BackupPath $context.StorageRoot "$currentTag-to-$target"
            Invoke-StemmaCli -ReleaseDir $release -Arguments @('backup', '--dest', $dest)
            # Só depois do sucesso: o rollback restaura deste arquivo.
            $backup = $dest
        }
        else { Write-Host '    Banco ainda não existe: sem backup.' }
        Enter-StemmaStage 'database'
        Write-Step 'Migrations'
        Invoke-Alembic -ReleaseDir $release -Arguments @('upgrade', 'head')
        Set-CurrentRelease -Root $Root -ReleaseDir $release
        Enter-StemmaStage 'service'
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
        Write-StemmaStage "Deu errado: voltando para $currentTag"
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

    Enter-StemmaStage 'cleanup'
    Write-Step 'Limpando releases antigas'
    $names = @(Get-InstalledReleases -Root $Root | ForEach-Object { $_.Name })
    foreach ($name in (Select-ReleasesToRemove -Names $names -Keep 3 -Protect @($target, $currentTag))) {
        Write-Host "    removendo $name"
        Remove-Item -LiteralPath (Join-Path $Root "releases\$name") -Recurse -Force
    }
    # A versão nova já está no ar: um problema aqui só deixa o cache maior.
    try { Optimize-StemmaUvCache -Root $Root | Out-Null }
    catch { Write-Warning "Cache do uv não foi enxugado: $($_.Exception.Message)" }
    Complete-StemmaProgress
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

# --- atualização pelo app (ADR 0015) ---------------------------------------------------

function Get-StemmaTaskNames {
    <#
      Tarefas agendadas da instalação: `\Stemma\Atualizar` (SYSTEM, roda o instalador da versão
      nova) e `\Stemma\Bandeja` (abre o Stemma.exe na sessão de quem está logado). Um ensaio
      paralelo (outro ServiceId) leva o id no nome.
    #>
    param([Parameter(Mandatory)][string]$ServiceId)
    $suffix = if ($ServiceId -eq 'stemma') { '' } else { "-$ServiceId" }
    return [pscustomobject]@{
        Path       = '\Stemma\'
        Update     = "Atualizar$suffix"
        Tray       = "Bandeja$suffix"
        UpdateFull = "\Stemma\Atualizar$suffix"
    }
}

function Get-AppUpdateArguments {
    <# Linha de comando da tarefa `Atualizar`: o setup.ps1 que o instalador deixou em <raiz>\setup\engine. #>
    param([Parameter(Mandatory)][string]$EngineDir, [Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$ServiceId)
    $setup = Join-Path $EngineDir 'setup.ps1'
    return "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$setup`" -Mode AppUpdate -Root `"$Root`" -ServiceId `"$ServiceId`""
}

function Register-StemmaTasks {
    <#
      Cria (ou recria) as tarefas e grava `UPDATE_TASK` no .env, para o backend saber que pode
      atualizar. Chamado pelo instalador antes de (re)iniciar o serviço.
    #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$ServiceId, [Parameter(Mandatory)][string]$EngineDir)
    $names = Get-StemmaTaskNames -ServiceId $ServiceId
    $update = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (Get-AppUpdateArguments -EngineDir $EngineDir -Root $Root -ServiceId $ServiceId)
    $system = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    # Sem limite de bateria; até 3 h (download do torch se ele mudar de versão); uma de cada vez.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 3) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskPath $names.Path -TaskName $names.Update -Action $update -Principal $system `
        -Settings $settings -Description 'Atualiza o Stemma para a última versão (pedido pelo app).' -Force | Out-Null

    $tray = Join-Path $Root 'setup\Stemma.exe'
    $trayAction = New-ScheduledTaskAction -Execute $tray -Argument "--root `"$Root`" --service `"$ServiceId`""
    # Grupo Usuários (SID, para não depender do idioma do Windows): roda na sessão de quem está logado.
    $users = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
    $traySettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskPath $names.Path -TaskName $names.Tray -Action $trayAction -Principal $users `
        -Settings $traySettings -Description 'Abre o ícone do Stemma na bandeja depois de atualizar pelo app.' -Force | Out-Null

    Set-DotEnvValue -Path (Get-StemmaPaths -Root $Root).EnvFile -Key 'UPDATE_TASK' -Value $names.UpdateFull
}

function Unregister-StemmaTasks {
    param([Parameter(Mandatory)][string]$ServiceId)
    $names = Get-StemmaTaskNames -ServiceId $ServiceId
    foreach ($name in $names.Update, $names.Tray) {
        $task = Get-ScheduledTask -TaskPath $names.Path -TaskName $name -ErrorAction SilentlyContinue
        if ($task) { Unregister-ScheduledTask -TaskPath $names.Path -TaskName $name -Confirm:$false }
    }
}

function Get-StemmaInstaller {
    <# Baixa o instalador da versão escolhida pelo app para <raiz>\downloads e confere o SHA256 (ou usa -InstallerPath, ensaio). #>
    param([Parameter(Mandatory)][string]$Root, [string]$Version, [string]$InstallerPath)
    if ($InstallerPath) {
        $exe = (Resolve-Path -LiteralPath $InstallerPath).Path
        if (Test-Path -LiteralPath "$exe.sha256") { Assert-Sha256 -Path $exe -Expected (Get-Sha256FromFile "$exe.sha256") }
        return $exe
    }
    $asset = Get-ReleaseAssets -Version $Version -Kind 'installer'
    $downloads = Join-Path $Root 'downloads'
    New-Item -ItemType Directory -Force -Path $downloads | Out-Null
    # Instaladores de atualizações anteriores não servem mais.
    Get-ChildItem -LiteralPath $downloads -Filter 'Stemma-Setup-*' -ErrorAction SilentlyContinue | Remove-Item -Force
    $exe = Join-Path $downloads "Stemma-Setup-$($asset.Tag).exe"
    Write-Step "Baixando o instalador $($asset.Tag)"
    Invoke-Download -Url $asset.ShaUrl -Dest "$exe.sha256"
    Invoke-Download -Url $asset.Url -Dest $exe
    Assert-Sha256 -Path $exe -Expected (Get-Sha256FromFile "$exe.sha256")
    return $exe
}

function ConvertFrom-InstallerResult {
    <# Arquivo do /RESULTFILE= do instalador: `ok|v1.5.1` ou `erro|motivo`. #>
    param([AllowEmptyString()][string]$Text)
    $line = "$Text".Trim()
    $bar = $line.IndexOf('|')
    if ($bar -lt 0) { return [pscustomobject]@{ Ok = $false; Text = $null } }
    $value = $line.Substring($bar + 1).Trim()
    return [pscustomobject]@{ Ok = ($line.Substring(0, $bar) -eq 'ok'); Text = $(if ($value) { $value } else { $null }) }
}

function Get-StemmaUpdateTarget {
    <# Versão que o app escolheu (CLI `update-target` da release no ar), ex.: 1.5.1. #>
    param([Parameter(Mandatory)][string]$Root)
    $current = Get-CurrentRelease -Root $Root
    if (-not $current) { throw "nenhuma release em $Root\current" }
    $found = [Collections.Generic.List[string]]::new()
    Invoke-Native -FilePath (Get-ReleasePython $current) -Arguments @('-m', 'app.cli', 'update-target') `
        -WorkingDirectory (Join-Path $current 'backend') -OnLine { param($line) if ($line -match '^\d+\.\d+\.\d+$') { $found.Add($line) } }
    if ($found.Count -eq 0) { throw 'o app não registrou qual versão instalar' }
    return $found[0]
}

function ConvertTo-CliText {
    <# O Windows PowerShell 5.1 não escapa aspas duplas em argumentos de executáveis: viram simples. #>
    param([AllowEmptyString()][string]$Text)
    return "$Text".Replace('"', "'")
}

function Invoke-StemmaInstaller {
    <# Roda o instalador e devolve o código de saída. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Arguments)
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -PassThru
    # WaitForExit, e não -Wait: o -Wait do 5.1 espera também os processos que sobram.
    $process.WaitForExit()
    return $process.ExitCode
}

function Invoke-StemmaAppUpdate {
    <#
      Tarefa `\Stemma\Atualizar` (ADR 0015): baixa o instalador da última release, roda em modo
      silencioso (backup, migrations e rollback são dele) e grava o resultado no banco com o CLI
      da release que ficou no ar. Por fim reabre o ícone da bandeja. Não lança: o resultado vai
      para o banco, que o app lê.
    #>
    param(
        [string]$Root = 'C:\stemma',
        [string]$ServiceId = 'stemma',
        [string]$InstallerPath,
        [switch]$SimulateFailure
    )
    $logs = Join-Path $Root 'logs'
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    $resultFile = Join-Path $logs 'app-update-result.txt'
    $state = 'failed'
    $message = $null
    try {
        Set-StemmaToolEnv -Root $Root
        Import-DotEnv -Path (Join-Path $Root '.env') | Out-Null
        # Exatamente a versão que o app mostrou e gravou (não a "latest" do GitHub agora).
        $target = if ($InstallerPath) { $null } else { Get-StemmaUpdateTarget -Root $Root }
        $exe = Get-StemmaInstaller -Root $Root -Version $target -InstallerPath $InstallerPath
        if (Test-Path -LiteralPath $resultFile) { Remove-Item -LiteralPath $resultFile -Force }
        $tag = [IO.Path]::GetFileNameWithoutExtension($exe) -replace '^Stemma-Setup-', ''
        $installerLog = Join-Path $logs "update-$tag.log"
        $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOTRAY',
            "/ROOT=`"$Root`"", "/SERVICEID=$ServiceId", "/RESULTFILE=`"$resultFile`"", "/LOG=`"$installerLog`"")
        if ($SimulateFailure) { $arguments += '/SIMULATEFAILURE' }
        Write-Step "Rodando o instalador $tag"
        $code = Invoke-StemmaInstaller -Path $exe -Arguments $arguments
        $text = if (Test-Path -LiteralPath $resultFile) { Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 } else { '' }
        $result = ConvertFrom-InstallerResult $text
        if ($code -eq 0 -and $result.Ok) { $state = 'succeeded' }
        elseif ($result.Text -and -not $result.Ok) { $message = $result.Text }
        else { $message = "O instalador da $tag parou com código $code. Veja $installerLog." }
    }
    catch { $message = "A atualização não começou: $($_.Exception.Message.TrimEnd('.'))." }
    Write-Step "Resultado: $state $message"

    # Grava com a release no ar agora (a nova, ou a anterior depois do rollback).
    try {
        $current = Get-CurrentRelease -Root $Root
        if (-not $current) { throw "nenhuma release em $Root\current" }
        $cliArgs = @('update-result', '--state', $state)
        if ($message) { $cliArgs += @('--message', (ConvertTo-CliText $message)) }
        Invoke-StemmaCli -ReleaseDir $current -Arguments $cliArgs
    }
    catch { Write-Warning "Não deu para gravar o resultado no banco: $($_.Exception.Message)" }

    try { Start-ScheduledTask -TaskPath '\Stemma\' -TaskName (Get-StemmaTaskNames -ServiceId $ServiceId).Tray }
    catch { Write-Warning "Ícone da bandeja: $($_.Exception.Message)" }
    return [pscustomobject]@{ State = $state; Message = $message }
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
    try { Unregister-StemmaTasks -ServiceId $ServiceId }
    catch { Write-Warning "Tarefas agendadas: $($_.Exception.Message)" }
    if ($info -and $info.tailscaleServe) {
        try { Remove-TailscaleServe -Port $context.Port -HttpsPort $info.httpsPort }
        catch { Write-Warning "tailscale serve: $($_.Exception.Message)" }
    }
    $current = Join-Path $Root 'current'
    if (Test-Path -LiteralPath $current) { [IO.Directory]::Delete($current, $false) }
    Write-Step "Apagando $Root"
    foreach ($child in @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue)) {
        if ($Keep -contains $child.Name) { continue }
        Remove-StemmaTree -Path $child.FullName
    }
    if ($RemoveData -and $context.StorageRoot -and (Test-Path -LiteralPath $context.StorageRoot)) {
        Assert-StemmaDataRoot $context.StorageRoot  # nunca apagar um drive inteiro
        Write-Step "Apagando os dados em $($context.StorageRoot)"
        Remove-StemmaTree -Path $context.StorageRoot
    }
}

Export-ModuleMember -Function *-*
