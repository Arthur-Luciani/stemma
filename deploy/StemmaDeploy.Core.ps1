# StemmaDeploy: console, progresso por etapas e utilitários (processos, administrador, GPU, apagar pastas).
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

# --- console -------------------------------------------------------------------

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

# --- utilitários ----------------------------------------------------------------

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

function Assert-Admin {
    if (-not (Test-IsAdmin)) {
        throw 'Rode este script num PowerShell como administrador (o serviço do Windows exige).'
    }
}

function Test-IsAdmin {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-NvidiaGpu {
    $smi = Get-Command nvidia-smi -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $smi) { return $false }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $smi.Source -L 2>$null | Out-Null; return $LASTEXITCODE -eq 0 }
    finally { $ErrorActionPreference = $previous }
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
