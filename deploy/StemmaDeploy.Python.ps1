# StemmaDeploy: Python da release: uv sync, Alembic e CLI do backend.
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

# --- Python da release ---------------------------------------------------------

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
