# StemmaDeploy: .env (leitura e escrita) e dados da instalação (install.json).
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

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
