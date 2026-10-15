# StemmaDeploy: yt-dlp: piso da release e atualização sem nova versão do Stemma (ADR 0016).
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

# --- yt-dlp (ADR 0016) -----------------------------------------------------------------

function ConvertTo-YtDlpVersion {
    <# `2025.07.06` ou `2025.10.22.1` → [version], que compara sem ligar para os zeros à esquerda do PyPI; outra coisa → $null. #>
    param([AllowEmptyString()][string]$Text)
    $value = "$Text".Trim()
    if ($value -notmatch '^\d+(\.\d+){2,3}$') { return $null }
    return [version]$value
}

function Get-ReleaseYtDlpVersion {
    <# yt-dlp instalado no venv de uma release (ex.: 2026.08.19), ou $null. #>
    param([Parameter(Mandatory)][string]$ReleaseDir)
    $python = Get-ReleasePython $ReleaseDir
    if (-not (Test-Path -LiteralPath $python)) { return $null }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $python -c 'from yt_dlp.version import __version__; print(__version__)' 2>$null
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0 -or -not $output) { return $null }
    return "$(@($output)[-1])".Trim()
}

function Install-ReleaseYtDlp {
    <# Instala exatamente essa versão do yt-dlp (com os extras do `[default]`) no venv da release. #>
    param([Parameter(Mandatory)][string]$ReleaseDir, [Parameter(Mandatory)][string]$Version)
    Invoke-Native -FilePath 'uv' -Arguments @('pip', 'install', '--python', (Get-ReleasePython $ReleaseDir), "yt-dlp[default]==$Version")
}

function Sync-StemmaYtDlpFloor {
    <#
      Venv da release nova: se a anterior tem um yt-dlp mais novo que o do uv.lock (atualizado
      pelo app ou pela tarefa diária), instala esse. Assim atualizar o Stemma nunca volta o
      yt-dlp. Falha só avisa: a tarefa diária corrige. Devolve a versão instalada, ou $null.
    #>
    param([Parameter(Mandatory)][string]$ReleaseDir, [Parameter(Mandatory)][string]$PreviousDir)
    try {
        $previous = Get-ReleaseYtDlpVersion -ReleaseDir $PreviousDir
        $locked = Get-ReleaseYtDlpVersion -ReleaseDir $ReleaseDir
        $previousVersion = ConvertTo-YtDlpVersion $previous
        $lockedVersion = ConvertTo-YtDlpVersion $locked
        if (-not $previousVersion -or -not $lockedVersion -or $previousVersion -le $lockedVersion) { return $null }
        Write-Step "Mantendo o yt-dlp $previous da versão anterior (o uv.lock traz o $locked)"
        Install-ReleaseYtDlp -ReleaseDir $ReleaseDir -Version $previous
        return $previous
    }
    catch {
        Write-Warning "Não deu para manter o yt-dlp da versão anterior ($($_.Exception.Message)). A atualização diária resolve."
        return $null
    }
}

function ConvertFrom-YtDlpBegin {
    <# Saída do CLI `ytdlp-begin`: `run|<atual>|<alvo>` ou `skip|<motivo>` (as outras linhas são log). #>
    param([AllowEmptyCollection()][string[]]$Lines)
    foreach ($line in $Lines) {
        $text = "$line".Trim()
        if ($text -match '^run\|([^|]+)\|([^|]+)$') {
            return [pscustomobject]@{ Run = $true; From = $Matches[1]; Target = $Matches[2]; Reason = $null }
        }
        if ($text -match '^skip\|(.*)$') {
            return [pscustomobject]@{ Run = $false; From = $null; Target = $null; Reason = $Matches[1] }
        }
    }
    throw 'o CLI ytdlp-begin não disse o que fazer'
}

function Get-StemmaYtDlpPlan {
    <# Roda o CLI `ytdlp-begin` da release no ar (que grava `running` se for atualizar). #>
    param([Parameter(Mandatory)][string]$ReleaseDir)
    $lines = [Collections.Generic.List[string]]::new()
    Invoke-Native -FilePath (Get-ReleasePython $ReleaseDir) -Arguments @('-m', 'app.cli', 'ytdlp-begin') `
        -WorkingDirectory (Join-Path $ReleaseDir 'backend') -OnLine { param($line) $lines.Add($line) }
    return ConvertFrom-YtDlpBegin @($lines)
}

function Invoke-StemmaYtDlpUpdate {
    <#
      Tarefa `\Stemma\AtualizarYtDlp` (ADR 0016): diária, sob demanda pelo app e pelo
      `update.ps1 -YtDlpOnly`. O CLI `ytdlp-begin` decide se atualiza (pedido do app, ou versão
      nova sem job ativo) e para qual versão, e grava `running`. Aqui: para o serviço, instala
      essa versão exata (com o serviço parado nenhum arquivo do venv fica preso), sobe e confere
      o /health com o yt-dlp novo. Falhou → volta a versão anterior. O resultado vai para o
      banco (`ytdlp-result`). Não lança: devolve State = skipped, succeeded ou failed.
    #>
    param([string]$Root = 'C:\stemma', [string]$ServiceId = 'stemma', [int]$HealthTimeoutSec = 180)
    $state = 'failed'
    $message = $null
    $context = $null
    $begin = $null
    try {
        Set-StemmaToolEnv -Root $Root
        Import-DotEnv -Path (Join-Path $Root '.env') | Out-Null
        $context = Get-StemmaContext -Root $Root
        if (-not $context.Current) { throw "nenhuma release em $Root\current" }
        $begin = Get-StemmaYtDlpPlan -ReleaseDir $context.Current
    }
    catch { $message = "A atualização do yt-dlp não começou: $($_.Exception.Message.TrimEnd('.'))." }
    if ($begin -and -not $begin.Run) {
        Write-Step "yt-dlp: nada a fazer ($($begin.Reason))"
        return [pscustomobject]@{ State = 'skipped'; Message = $begin.Reason }
    }

    if ($begin) {
        Write-Step "Atualizando o yt-dlp $($begin.From) → $($begin.Target)"
        try {
            Stop-StemmaService -ServiceId $ServiceId
            try { Install-ReleaseYtDlp -ReleaseDir $context.Current -Version $begin.Target }
            finally { Start-StemmaService -ServiceId $ServiceId }
            if (-not (Wait-StemmaHealth -Port $context.Port -ExpectedVersion $context.CurrentTag -ExpectedYtDlp $begin.Target -TimeoutSec $HealthTimeoutSec)) {
                throw "o Stemma não voltou com o yt-dlp $($begin.Target)"
            }
            $state = 'succeeded'
        }
        catch {
            $message = "A atualização do yt-dlp para $($begin.Target) falhou: $($_.Exception.Message.TrimEnd('.'))."
            Write-Warning $message
            $message += ' ' + (Restore-StemmaYtDlp -Context $context -ServiceId $ServiceId -Version $begin.From -HealthTimeoutSec $HealthTimeoutSec)
        }
    }
    Write-Step "Resultado: $state $message"

    # Sem pedido gravado (o begin falhou antes), o CLI não muda nada.
    if ($context -and $context.Current) {
        try {
            $cliArgs = @('ytdlp-result', '--state', $state)
            if ($message) { $cliArgs += @('--message', (ConvertTo-CliText $message)) }
            Invoke-StemmaCli -ReleaseDir $context.Current -Arguments $cliArgs
        }
        catch { Write-Warning "Não deu para gravar o resultado no banco: $($_.Exception.Message)" }
    }
    return [pscustomobject]@{ State = $state; Message = $message }
}

function Restore-StemmaYtDlp {
    <# Depois de uma falha: volta o yt-dlp anterior e sobe o serviço. Devolve o complemento da mensagem. #>
    param([Parameter(Mandatory)]$Context, [string]$ServiceId, [string]$Version, [int]$HealthTimeoutSec)
    try {
        Stop-StemmaService -ServiceId $ServiceId
        try { Install-ReleaseYtDlp -ReleaseDir $Context.Current -Version $Version }
        finally { Start-StemmaService -ServiceId $ServiceId }
        if (Wait-StemmaHealth -Port $Context.Port -ExpectedVersion $Context.CurrentTag -ExpectedYtDlp $Version -TimeoutSec $HealthTimeoutSec) {
            return "O yt-dlp $Version continua no ar."
        }
        return "O Stemma não voltou com o yt-dlp ${Version}: veja os logs."
    }
    catch {
        Write-Warning "Voltar o yt-dlp ${Version}: $($_.Exception.Message)"
        try { Start-StemmaService -ServiceId $ServiceId } catch { Write-Warning "Serviço: $($_.Exception.Message)" }
        return "Não deu para voltar o yt-dlp ${Version}: veja os logs."
    }
}
