# StemmaDeploy: Tailscale (login, serve) e portas locais.
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

# Tailscale: MSI oficial numa versão fixa (depois ele se atualiza sozinho).
$script:TailscaleMsiUrl = 'https://pkgs.tailscale.com/stable/tailscale-setup-1.102.4-amd64.msi'
$script:TailscaleMsiSha256 = '80eb007e39dfebe17299fa1a09c79a8e1d934f76e0246c0817ebe3af675b7ef6'
$script:TailscaleAdminDns = 'https://login.tailscale.com/admin/dns'

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
