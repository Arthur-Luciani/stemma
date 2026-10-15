# StemmaDeploy: ferramentas portáteis em <Root>\tools (ADR 0014), pastas e ACLs.
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

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
