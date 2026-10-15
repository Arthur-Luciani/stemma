# StemmaDeploy: versões, releases instaladas, download e verificação (SHA256), pacote e junction current.
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

$script:Repo = 'Arthur-Luciani/stemma'

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
