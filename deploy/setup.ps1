<#
.SYNOPSIS
  Motor do instalador (installer/stemma.iss). Toda a lógica fica aqui e no StemmaDeploy.psm1;
  o Inno Setup só mostra as telas e repassa os parâmetros (ADR 0014).

.DESCRIPTION
  Protocolo com o instalador, pela saída padrão (UTF-8):
    ==> texto        etapa (vira o texto da tela de progresso)
    ##RESULT k=v     resultado para o instalador
    ##ERROR texto    falha (com exit code 1)
    ##STAGE texto    etapa numerada de Install/Update ("Etapa 3 de 9: …")
    ##PROGRESS n     avanço total de Install/Update, de 0 a 1000
  Modos:
    Check             estado do PC: release instalada, porta, pasta de dados, Tailscale, GPU,
                      porta livre sugerida e o que a 443/8443 do Tailscale já publicam; com
                      -LockPath, quanto vai ser baixado e o espaço no drive da raiz (MB)
    CheckPort         -Port N: se está livre (portuse=motivo) e a próxima livre (freeport)
    TailscaleInstall  instala o Tailscale (MSI oficial)
    TailscaleLogin    abre o login do Tailscale no navegador
    Install           instalação nova (ferramentas, release, serviço, tailscale serve)
    Update            atualização com backup e rollback (-SimulateFailure para testar)
    Uninstall         remove serviço, tailscale serve e <Root> (-RemoveData apaga os dados)
    AppUpdate         tarefa agendada \Stemma\Atualizar (ADR 0015): baixa o instalador da última
                      release, roda em modo silencioso e grava o resultado no banco
                      (-InstallerPath usa um .exe local, para ensaio)
    Start / Stop      "Iniciar o Stemma" / "Parar o Stemma" do ícone da bandeja (Stemma.exe): pedem
                      administrador (UAC) sozinhos e mostram um aviso no fim
#>
param(
    [Parameter(Mandatory)]
    [ValidateSet('Check', 'CheckPort', 'TailscaleInstall', 'TailscaleLogin', 'Install', 'Update', 'Uninstall', 'AppUpdate', 'Start', 'Stop')]
    [string]$Mode,
    [string]$Root = 'C:\stemma',
    [string]$ServiceId = 'stemma',
    [string]$DataRoot,
    [int]$Port = 8000,
    [int]$HttpsPort = 443,
    [string]$ZipPath,
    [string]$QrPath,
    [string]$LockPath,
    [string]$Keep,
    [string]$InstallerPath,
    [switch]$SkipTailscale,
    [switch]$SimulateFailure,
    [switch]$RemoveData
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Text.UTF8Encoding]::new($false)
Import-Module (Join-Path $PSScriptRoot 'StemmaDeploy.psm1') -Force

function Write-Result([string]$Key, [string]$Value) { Write-Host "##RESULT $Key=$Value" }

function Get-StemmaUrl([int]$PortNumber, [bool]$UseTailscale, [int]$Https = 443) {
    if ($UseTailscale) {
        $state = Get-TailscaleState
        if ($state.Host) { return $(if ($Https -eq 443) { "https://$($state.Host)" } else { "https://$($state.Host):$Https" }) }
    }
    return "http://127.0.0.1:$PortNumber"
}

function Write-ServeResults([int]$LocalPort) {
    <# serve443/serve8443 (o que publicam) e serve443state/serve8443state (free | ours | other). #>
    $json = Get-TailscaleServeJson
    foreach ($https in 443, 8443) {
        $target = Get-TailscaleServeTarget -HttpsPort $https -Json $json
        Write-Result "serve$https" "$target"
        Write-Result "serve$($https)state" (Get-ServePortState -Target $target -Port $LocalPort)
    }
}

function Write-StemmaQr([string]$Url) {
    <#
      QR code do endereço (BMP) para a tela final, com o Python da release e o segno ao lado do
      qr.py. Só para o endereço do Tailscale: um QR de 127.0.0.1 não abre nada no celular.
    #>
    if (-not $QrPath -or -not $Url.StartsWith('https://')) { return }
    $script = Join-Path $PSScriptRoot 'qr.py'
    $release = Get-CurrentRelease -Root $Root
    if (-not (Test-Path -LiteralPath $script) -or -not $release) { return }
    try {
        Invoke-Native -FilePath (Get-ReleasePython $release) -Arguments @($script, $Url, $QrPath)
        Write-Result 'qr' $QrPath
    }
    catch { Write-Warning "QR code: $($_.Exception.Message)" }
}

function Show-Popup([string]$Text, [int]$Icon) {
    # 64 = informação, 16 = erro (WScript.Shell.Popup).
    (New-Object -ComObject WScript.Shell).Popup($Text, 0, 'Stemma', $Icon) | Out-Null
}

# Ações do ícone da bandeja: sem janela de console e com UAC só aqui.
if ($Mode -in 'Start', 'Stop') {
    $identity = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Mode $Mode -Root `"$Root`" -ServiceId `"$ServiceId`""
        try { Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden }
        catch { Show-Popup 'É preciso permitir (administrador) para iniciar ou parar o Stemma.' 16 }
        exit 0
    }
    try {
        $info = Get-StemmaInstallInfo -Root $Root
        if ($info) { $ServiceId = $info.serviceId }
        if ($Mode -eq 'Stop') {
            Disable-StemmaService -ServiceId $ServiceId
            Show-Popup "O Stemma está parado e não vai subir sozinho com o Windows.`n`nPara voltar: ícone do Stemma perto do relógio → Iniciar o Stemma." 64
        }
        else {
            Enable-StemmaService -ServiceId $ServiceId
            $context = Get-StemmaContext -Root $Root
            if (-not (Wait-StemmaHealth -Port $context.Port -ExpectedVersion $context.CurrentTag -TimeoutSec 120)) {
                throw "o serviço subiu, mas não respondeu. Veja os logs em $Root\logs."
            }
            $useTailscale = if ($info) { [bool]$info.tailscaleServe } else { $true }
            $https = if ($info) { [int]$info.httpsPort } else { 443 }
            Show-Popup "O Stemma está no ar e volta a subir sozinho com o Windows.`n`n$(Get-StemmaUrl -PortNumber $context.Port -UseTailscale $useTailscale -Https $https)" 64
        }
        exit 0
    }
    catch {
        Show-Popup "Não deu certo: $($_.Exception.Message)" 16
        exit 1
    }
}

$transcript = $null
if ($Mode -in 'Install', 'Update') { Set-StemmaProgressProtocol $true }
if ($Mode -in 'Install', 'Update', 'Uninstall', 'AppUpdate') {
    $logDir = if ($Mode -eq 'Uninstall') { $env:TEMP } else { Join-Path $Root 'logs' }
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $transcript = Join-Path $logDir ("setup-{0}-{1}.log" -f $Mode.ToLowerInvariant(), (Get-Date).ToString('yyyyMMdd-HHmmss'))
    Start-Transcript -LiteralPath $transcript | Out-Null
    Write-Result 'log' $transcript
}

try {
    switch ($Mode) {
        'Check' {
            $context = Get-StemmaContext -Root $Root
            Write-Result 'installed' "$($context.CurrentTag)"
            $info = Get-StemmaInstallInfo -Root $Root
            $id = if ($info) { $info.serviceId } else { $ServiceId }
            Write-Result 'service' $(if (Test-StemmaService $id) { 'yes' } else { 'no' })
            Write-Result 'port' "$($context.Port)"
            Write-Result 'dataroot' $(if ($context.CurrentTag) { $context.StorageRoot } else { Get-DefaultDataRoot })
            $tailscale = Get-TailscaleState
            Write-Result 'tailscale' $tailscale.State
            Write-Result 'host' $tailscale.Host
            Write-Result 'gpu' $(if (Test-NvidiaGpu) { 'ok' } else { 'missing' })
            # Instalação nova: sugere a primeira porta livre a partir da 8000.
            $freePort = $null
            if (-not $context.CurrentTag) { $freePort = Find-FreePort -Start 8000; Write-Result 'freeport' "$freePort" }
            # O que as portas HTTPS do Tailscale publicam, e se é este Stemma (pela porta local:
            # a instalada, a -Port que o assistente está usando ou a livre que ele vai usar).
            $localPort = if ($context.CurrentTag) { $context.Port } elseif ($PSBoundParameters.ContainsKey('Port') -or -not $freePort) { $Port } else { $freePort }
            Write-ServeResults -LocalPort $localPort
            # Página "Pronto para instalar": download previsto e espaço no drive da raiz.
            if ($LockPath -and (Test-Path -LiteralPath $LockPath)) {
                try {
                    $caches = Get-StemmaCacheDirs -Root $Root -UserCache (Find-UserUvCache)
                    $estimate = Get-StemmaSpaceEstimate -Root $Root -LockPath $LockPath -CacheDirs $caches
                    Write-Result 'downloadmb' ([long][Math]::Ceiling($estimate.DownloadBytes / 1MB))
                    Write-Result 'needrootmb' ([long][Math]::Ceiling($estimate.NeedRootBytes / 1MB))
                }
                catch { Write-Warning "Estimativa de espaço: $($_.Exception.Message)" }
            }
        }
        'CheckPort' {
            $usage = Get-PortUsage -Port $Port
            Write-Result 'portuse' "$usage"
            if ($usage) { Write-Result 'freeport' "$(Find-FreePort -Start ($Port + 1))" }
            Write-ServeResults -LocalPort $Port
        }
        'TailscaleInstall' {
            Assert-Admin
            Install-Tailscale -Root $Root
            Write-Result 'tailscale' (Get-TailscaleState).State
        }
        'TailscaleLogin' {
            $state = Start-TailscaleLogin
            Write-Result 'tailscale' $state.State
        }
        'Install' {
            Assert-Admin
            $tag = Invoke-StemmaInstall -Root $Root -DataRoot $DataRoot -Port $Port -ServiceId $ServiceId `
                -ZipPath $ZipPath -SkipTailscale:$SkipTailscale -HttpsPort $HttpsPort -EngineDir $PSScriptRoot
            $url = Get-StemmaUrl -PortNumber (Get-StemmaContext -Root $Root).Port -UseTailscale (-not $SkipTailscale) -Https $HttpsPort
            Write-Result 'version' $tag
            Write-Result 'url' $url
            Write-StemmaQr $url
        }
        'Update' {
            Assert-Admin
            $info = Get-StemmaInstallInfo -Root $Root
            if ($info) { $ServiceId = $info.serviceId }
            $tag = Invoke-StemmaUpdate -Root $Root -ServiceId $ServiceId -ZipPath $ZipPath -SimulateFailure:$SimulateFailure `
                -EngineDir $PSScriptRoot
            $useTailscale = if ($info) { [bool]$info.tailscaleServe } else { -not $SkipTailscale }
            $https = if ($info) { [int]$info.httpsPort } else { $HttpsPort }
            $port = (Get-StemmaContext -Root $Root).Port
            # Refaz o serve se ele sumiu (instalação que falhou antes dele, outro desinstalador),
            # mas nunca toma a porta HTTPS de outro app.
            if ($useTailscale) {
                # A atualização já terminou: nada aqui pode virar "falhou".
                try {
                    $target = Get-TailscaleServeTarget -HttpsPort $https
                    switch (Get-ServePortState -Target $target -Port $port) {
                        'free' { Set-TailscaleServe -Port $port -HttpsPort $https }
                        'other' { Write-Warning "A $https do Tailscale publica '$target', não o Stemma: não mexi nela." }
                    }
                }
                catch { Write-Warning "tailscale serve: $($_.Exception.Message)" }
            }
            $url = Get-StemmaUrl -PortNumber $port -UseTailscale $useTailscale -Https $https
            Write-Result 'version' $tag
            Write-Result 'url' $url
            Write-StemmaQr $url
        }
        'AppUpdate' {
            Assert-Admin
            $outcome = Invoke-StemmaAppUpdate -Root $Root -ServiceId $ServiceId -InstallerPath $InstallerPath `
                -SimulateFailure:$SimulateFailure
            if ($outcome.State -ne 'succeeded') { throw $outcome.Message }
        }
        'Uninstall' {
            Assert-Admin
            $keepList = @($Keep -split ',' | Where-Object { $_ })
            Invoke-StemmaUninstall -Root $Root -Keep $keepList -RemoveData:$RemoveData
        }
    }
    exit 0
}
catch {
    Write-Host "##ERROR $($_.Exception.Message)"
    exit 1
}
finally {
    if ($transcript) { Stop-Transcript | Out-Null }
}
