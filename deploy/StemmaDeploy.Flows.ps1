# StemmaDeploy: fluxos: instalar, atualizar, voltar (backup e migrations) e desinstalar.
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

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
    # O uv.lock da versão nova pode trazer um yt-dlp mais velho que o atualizado pelo app.
    Sync-StemmaYtDlpFloor -ReleaseDir $release -PreviousDir $current | Out-Null
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
    # Backups além dos BACKUPS_KEEP mais novos (o desta atualização é o mais novo, nunca sai).
    try { Invoke-StemmaCli -ReleaseDir $release -Arguments @('prune-backups') }
    catch { Write-Warning "Backups antigos não foram podados: $($_.Exception.Message)" }
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
