# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`).
# Testes do StemmaDeploy.Network.ps1.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
}

Describe 'ConvertFrom-TailscaleStatus' {
    It 'logado e com HTTPS → ready, com o nome do certificado' {
        $json = '{"BackendState":"Running","Self":{"DNSName":"pc.tail1.ts.net."},"CertDomains":["pc.tail1.ts.net"]}'
        $state = ConvertFrom-TailscaleStatus -Json $json
        $state.State | Should -Be 'ready'
        $state.Host | Should -Be 'pc.tail1.ts.net'
    }

    It 'logado sem HTTPS → nohttps' {
        $json = '{"BackendState":"Running","Self":{"DNSName":"pc.tail1.ts.net."},"CertDomains":null}'
        $state = ConvertFrom-TailscaleStatus -Json $json
        $state.State | Should -Be 'nohttps'
        $state.Host | Should -Be 'pc.tail1.ts.net'
    }

    It 'sem login → needslogin, com a URL de login quando houver' {
        $state = ConvertFrom-TailscaleStatus -Json '{"BackendState":"NeedsLogin","AuthURL":"https://login.tailscale.com/a/x","Self":null}'
        $state.State | Should -Be 'needslogin'
        $state.AuthUrl | Should -Be 'https://login.tailscale.com/a/x'
        (ConvertFrom-TailscaleStatus -Json '{"BackendState":"NoState"}').State | Should -Be 'needslogin'
    }

    It 'desligado → stopped; outros → starting' {
        (ConvertFrom-TailscaleStatus -Json '{"BackendState":"Stopped"}').State | Should -Be 'stopped'
        (ConvertFrom-TailscaleStatus -Json '{"BackendState":"Starting"}').State | Should -Be 'starting'
    }
}

Describe 'Portas HTTPS do Tailscale' {
    BeforeAll {
        $script:ServeJson = @'
{
  "TCP": { "443": { "HTTPS": true }, "5183": { "HTTPS": true } },
  "Web": {
    "pc.tail1.ts.net:443": { "Handlers": { "/": { "Proxy": "http://127.0.0.1:8001" } } },
    "pc.tail1.ts.net:5183": { "Handlers": { "/": { "Proxy": "http://127.0.0.1:5183" } } },
    "pc.tail1.ts.net:8443": { "Handlers": { "/": { "Path": "C:\\site" } } }
  }
}
'@
    }

    It 'lê para onde cada porta HTTPS aponta' {
        ConvertFrom-TailscaleServeStatus -Json $script:ServeJson -HttpsPort 443 | Should -Be 'http://127.0.0.1:8001'
        ConvertFrom-TailscaleServeStatus -Json $script:ServeJson -HttpsPort 5183 | Should -Be 'http://127.0.0.1:5183'
        ConvertFrom-TailscaleServeStatus -Json $script:ServeJson -HttpsPort 8443 | Should -Be '(outro)'
        ConvertFrom-TailscaleServeStatus -Json $script:ServeJson -HttpsPort 10000 | Should -BeNullOrEmpty
        ConvertFrom-TailscaleServeStatus -Json '{}' -HttpsPort 443 | Should -BeNullOrEmpty
        ConvertFrom-TailscaleServeStatus -Json '' -HttpsPort 443 | Should -BeNullOrEmpty
    }

    It 'o desinstalador só desliga a 443 se ela ainda publica este Stemma' {
        Mock -ModuleName StemmaDeploy Get-TailscaleExe { 'tailscale.exe' }
        Mock -ModuleName StemmaDeploy Get-TailscaleServeTarget { 'http://127.0.0.1:8001' }
        Mock -ModuleName StemmaDeploy Get-PortUsage { $null }
        Mock -ModuleName StemmaDeploy Invoke-Native {}
        Mock -ModuleName StemmaDeploy Write-Step {}

        Remove-TailscaleServe -Port 8000 6>$null
        Should -Invoke -ModuleName StemmaDeploy Invoke-Native -Times 0 -Exactly

        Remove-TailscaleServe -Port 8001
        Should -Invoke -ModuleName StemmaDeploy Invoke-Native -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'serve --https=443 off' }
    }

    It 'mesma porta local que outra instalação (ex.: ensaio e real): não desliga' {
        Mock -ModuleName StemmaDeploy Get-TailscaleExe { 'tailscale.exe' }
        Mock -ModuleName StemmaDeploy Get-TailscaleServeTarget { 'http://127.0.0.1:8001' }
        # O serviço desta instalação já foi removido; quem escuta na 8001 é a outra.
        Mock -ModuleName StemmaDeploy Get-PortUsage { 'em uso por python (PID 4120)' }
        Mock -ModuleName StemmaDeploy Invoke-Native {}
        Remove-TailscaleServe -Port 8001 6>$null
        Should -Invoke -ModuleName StemmaDeploy Invoke-Native -Times 0 -Exactly
    }

    It 'nada publicado: não faz nada' {
        Mock -ModuleName StemmaDeploy Get-TailscaleExe { 'tailscale.exe' }
        Mock -ModuleName StemmaDeploy Get-TailscaleServeTarget { $null }
        Mock -ModuleName StemmaDeploy Invoke-Native {}
        Remove-TailscaleServe -Port 8001 6>$null
        Should -Invoke -ModuleName StemmaDeploy Invoke-Native -Times 0 -Exactly
    }

    It 'estado da porta HTTPS: livre, deste Stemma ou de outro app' {
        Get-ServePortState -Target $null -Port 8000 | Should -Be 'free'
        Get-ServePortState -Target 'http://127.0.0.1:8000' -Port 8000 | Should -Be 'ours'
        Get-ServePortState -Target 'http://127.0.0.1:9000' -Port 8000 | Should -Be 'other'
        Get-ServePortState -Target '(outro: TCP)' -Port 8000 | Should -Be 'other'
    }

    It 'encaminhamento TCP e saída que não é JSON contam como ocupada' {
        ConvertFrom-TailscaleServeStatus -Json '{"TCP":{"443":{"TCPForward":"127.0.0.1:5432"}}}' -HttpsPort 443 | Should -Be '(outro: TCP)'
        ConvertFrom-TailscaleServeStatus -Json 'Tailscale is starting...' -HttpsPort 443 | Should -Be '(desconhecido)'
    }

    It 'publica na porta HTTPS escolhida' {
        Mock -ModuleName StemmaDeploy Get-TailscaleExe { 'tailscale.exe' }
        Mock -ModuleName StemmaDeploy Invoke-Native {}
        Mock -ModuleName StemmaDeploy Write-Step {}
        Set-TailscaleServe -Port 8000 -HttpsPort 8443
        Should -Invoke -ModuleName StemmaDeploy Invoke-Native -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'serve --bg --https=8443 http://127.0.0.1:8000' }
    }

    It 'install.json antigo (v1.4.0) vale como 443' {
        $root = Join-Path $TestDrive 'info-antigo'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'install.json') -Value '{ "serviceId": "stemma", "tailscaleServe": true }'
        (Get-StemmaInstallInfo -Root $root).httpsPort | Should -Be 443
        Set-StemmaInstallInfo -Root $root -ServiceId 'stemma' -TailscaleServe $true -HttpsPort 8443
        (Get-StemmaInstallInfo -Root $root).httpsPort | Should -Be 8443
    }
}

Describe 'Portas locais' {
    It 'lê as faixas reservadas pelo Windows' {
        $lines = @(
            'Protocol tcp Port Exclusion Ranges', '', 'Start Port    End Port', '----------    --------',
            '      5357        5357', '     50000       50059     *', '', '* - Administered port exclusions.'
        )
        $ranges = ConvertFrom-ExcludedPortRanges $lines
        $ranges.Count | Should -Be 2
        $ranges[1].Start | Should -Be 50000
        $ranges[1].End | Should -Be 50059
    }

    It 'diz quem usa a porta, ou que o Windows a reserva' {
        Mock -ModuleName StemmaDeploy Get-NetTCPConnection { @([pscustomobject]@{ LocalPort = 8001; OwningProcess = 4120 }) }
        Mock -ModuleName StemmaDeploy Get-Process { [pscustomobject]@{ ProcessName = 'python' } }
        $ranges = @([pscustomobject]@{ Start = 50000; End = 50059 })

        Get-PortUsage -Port 8001 -ExcludedRanges $ranges | Should -Be 'em uso por python (PID 4120)'
        Get-PortUsage -Port 50010 -ExcludedRanges $ranges | Should -Match 'reservada pelo Windows'
        Get-PortUsage -Port 8000 -ExcludedRanges $ranges | Should -BeNullOrEmpty
    }

    It 'sugere a próxima porta livre' {
        Mock -ModuleName StemmaDeploy Get-ExcludedPortRanges { @() }
        Mock -ModuleName StemmaDeploy Get-NetTCPConnection {
            @([pscustomobject]@{ LocalPort = 8000; OwningProcess = 1 }, [pscustomobject]@{ LocalPort = 8001; OwningProcess = 2 })
        }
        Mock -ModuleName StemmaDeploy Get-Process { $null }
        Find-FreePort -Start 8000 | Should -Be 8002
        # Uma consulta só, por mais portas que varra.
        Should -Invoke -ModuleName StemmaDeploy Get-NetTCPConnection -Times 1 -Exactly
    }

    It 'a instalação sem nenhuma porta livre falha antes de mexer em qualquer coisa' {
        Mock -ModuleName StemmaDeploy Test-StemmaService { $false }
        Mock -ModuleName StemmaDeploy Get-PortUsage { 'em uso por python (PID 4120)' }
        Mock -ModuleName StemmaDeploy Find-FreePort { $null }
        Mock -ModuleName StemmaDeploy Initialize-StemmaRuntime {}
        $root = Join-Path $TestDrive 'porta-ocupada'
        { Invoke-StemmaInstall -Root $root -DataRoot (Join-Path $TestDrive 'dados') -Port 8001 -SkipTailscale 6>$null } |
            Should -Throw '*porta 8001 está em uso por python*não achei outra livre*'
        Should -Invoke -ModuleName StemmaDeploy Initialize-StemmaRuntime -Times 0 -Exactly
        Test-Path -LiteralPath $root | Should -BeFalse
    }

    It 'porta tomada entre o assistente e a instalação: usa a próxima livre (sem tela de porta)' {
        $root = Join-Path $TestDrive 'porta-trocada'
        Mock -ModuleName StemmaDeploy Test-StemmaService { $false }
        Mock -ModuleName StemmaDeploy Get-PortUsage { if ($Port -eq 8001) { 'em uso por python (PID 4120)' } }
        Mock -ModuleName StemmaDeploy Find-FreePort { 8002 }
        Mock -ModuleName StemmaDeploy Find-UserUvCache { $null }
        Mock -ModuleName StemmaDeploy Protect-StemmaDirectory {}
        Mock -ModuleName StemmaDeploy Get-StemmaPackage { [pscustomobject]@{ Tag = 'v1.0.0'; Zip = 'x.zip' } }
        Mock -ModuleName StemmaDeploy Expand-StemmaPackage { Join-Path $root 'releases\v1.0.0' }
        Mock -ModuleName StemmaDeploy Initialize-StemmaRuntime {}
        Mock -ModuleName StemmaDeploy Install-StemmaPython {}
        Mock -ModuleName StemmaDeploy Set-ComponentsStageWeight {}
        Mock -ModuleName StemmaDeploy Sync-ReleaseEnvironment { 'cache' }
        Mock -ModuleName StemmaDeploy Invoke-Alembic {}
        Mock -ModuleName StemmaDeploy Set-CurrentRelease {}
        Mock -ModuleName StemmaDeploy Register-StemmaService {}
        Mock -ModuleName StemmaDeploy Start-StemmaService {}
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $true }
        Mock -ModuleName StemmaDeploy Write-Step {}

        Invoke-StemmaInstall -Root $root -DataRoot (Join-Path $TestDrive 'dados-porta') -Port 8001 -SkipTailscale 6>$null | Should -Be 'v1.0.0'
        (Read-DotEnv -Path (Join-Path $root '.env'))['PORT'] | Should -Be '8002'
        Should -Invoke -ModuleName StemmaDeploy Wait-StemmaHealth -ParameterFilter { $Port -eq 8002 }
    }
}
