# StemmaDeploy: atualização pelo app (ADR 0015): tarefas agendadas e o instalador.
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

# --- atualização pelo app (ADR 0015) ---------------------------------------------------

function Get-StemmaTaskNames {
    <#
      Tarefas agendadas da instalação: `\Stemma\Atualizar` (SYSTEM, roda o instalador da versão
      nova), `\Stemma\AtualizarYtDlp` (SYSTEM, diária e sob demanda, só o yt-dlp; ADR 0016) e
      `\Stemma\Bandeja` (abre o Stemma.exe na sessão de quem está logado). Um ensaio paralelo
      (outro ServiceId) leva o id no nome.
    #>
    param([Parameter(Mandatory)][string]$ServiceId)
    $suffix = if ($ServiceId -eq 'stemma') { '' } else { "-$ServiceId" }
    return [pscustomobject]@{
        Path       = '\Stemma\'
        Update     = "Atualizar$suffix"
        YtDlp      = "AtualizarYtDlp$suffix"
        Tray       = "Bandeja$suffix"
        UpdateFull = "\Stemma\Atualizar$suffix"
        YtDlpFull  = "\Stemma\AtualizarYtDlp$suffix"
    }
}

function Get-AppUpdateArguments {
    <# Linha de comando das tarefas `Atualizar` e `AtualizarYtDlp`: o setup.ps1 que o instalador deixou em <raiz>\setup\engine. #>
    param(
        [Parameter(Mandatory)][string]$EngineDir,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ServiceId,
        [ValidateSet('AppUpdate', 'YtDlpUpdate')][string]$Mode = 'AppUpdate'
    )
    $setup = Join-Path $EngineDir 'setup.ps1'
    return "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$setup`" -Mode $Mode -Root `"$Root`" -ServiceId `"$ServiceId`""
}

function Register-StemmaTasks {
    <#
      Cria (ou recria) as tarefas e grava `UPDATE_TASK` e `YTDLP_UPDATE_TASK` no .env, para o
      backend saber que pode atualizar. Chamado pelo instalador antes de (re)iniciar o serviço.
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

    # yt-dlp: todo dia às 5h (ou assim que o PC ligar, se estava desligado) e quando o app pede.
    # Até 20 min (o backend dá a atualização por perdida com 30).
    $ytdlp = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (Get-AppUpdateArguments -EngineDir $EngineDir -Root $Root -ServiceId $ServiceId -Mode YtDlpUpdate)
    $daily = New-ScheduledTaskTrigger -Daily -At '05:00'
    $ytdlpSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskPath $names.Path -TaskName $names.YtDlp -Action $ytdlp -Trigger $daily -Principal $system `
        -Settings $ytdlpSettings -Description 'Atualiza o yt-dlp do Stemma (todo dia e quando o app pede).' -Force | Out-Null

    $tray = Join-Path $Root 'setup\Stemma.exe'
    $trayAction = New-ScheduledTaskAction -Execute $tray -Argument "--root `"$Root`" --service `"$ServiceId`""
    # Grupo Usuários (SID, para não depender do idioma do Windows): roda na sessão de quem está logado.
    $users = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
    $traySettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskPath $names.Path -TaskName $names.Tray -Action $trayAction -Principal $users `
        -Settings $traySettings -Description 'Abre o ícone do Stemma na bandeja depois de atualizar pelo app.' -Force | Out-Null

    $envFile = (Get-StemmaPaths -Root $Root).EnvFile
    Set-DotEnvValue -Path $envFile -Key 'UPDATE_TASK' -Value $names.UpdateFull
    Set-DotEnvValue -Path $envFile -Key 'YTDLP_UPDATE_TASK' -Value $names.YtDlpFull
}

function Unregister-StemmaTasks {
    param([Parameter(Mandatory)][string]$ServiceId)
    $names = Get-StemmaTaskNames -ServiceId $ServiceId
    foreach ($name in $names.Update, $names.YtDlp, $names.Tray) {
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
