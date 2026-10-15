# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`).
# Testes do StemmaDeploy.Flows.ps1.

BeforeDiscovery {
    # Junction só existe no Windows; no CI (Linux) o teste fica pulado.
    $OnWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
}

Describe 'Assert-StemmaDataRoot' {
    It 'recusa a raiz de um drive (o desinstalador apagaria o drive)' {
        { Assert-StemmaDataRoot 'D:\' } | Should -Throw '*raiz do drive*'
        { Assert-StemmaDataRoot 'D:' } | Should -Throw '*raiz do drive*'
    }

    It 'aceita uma pasta' {
        { Assert-StemmaDataRoot 'D:\stemma-data' } | Should -Not -Throw
        { Assert-StemmaDataRoot 'D:\stemma-data\' } | Should -Not -Throw
    }
}

Describe 'Invoke-StemmaUpdate' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $data = Join-Path $root 'dados'
        New-Item -ItemType Directory -Force -Path $data | Out-Null
        Set-Content -LiteralPath (Join-Path $data 'stemma.db') -Value 'db'
        Set-Content -LiteralPath (Join-Path $root '.env') -Value @('PORT=8001', "STORAGE_ROOT=$data")
        $script:current = Join-Path $root 'releases\v1.0.0'
        $script:next = Join-Path $root 'releases\v1.1.0'
        New-Item -ItemType Directory -Force -Path $script:current, $script:next | Out-Null
        Mock -ModuleName StemmaDeploy Get-CurrentRelease { $script:current }
        $script:calls = [Collections.Generic.List[string]]::new()
        Mock -ModuleName StemmaDeploy Initialize-StemmaRuntime { $script:calls.Add("tools:$($Names -join ',')") }
        Mock -ModuleName StemmaDeploy Find-UserUvCache { $null }
        Mock -ModuleName StemmaDeploy Protect-StemmaDirectory {}
        Mock -ModuleName StemmaDeploy Get-StemmaPackage { [pscustomobject]@{ Tag = 'v1.1.0'; Zip = 'x.zip' } }
        Mock -ModuleName StemmaDeploy Expand-StemmaPackage { $script:next }
        Mock -ModuleName StemmaDeploy Sync-ReleaseEnvironment { 'cache' }
        Mock -ModuleName StemmaDeploy Stop-StemmaService { $script:calls.Add('stop') }
        Mock -ModuleName StemmaDeploy Start-StemmaService {}
        # O backup de verdade cria o arquivo; o rollback só restaura se ele existir.
        Mock -ModuleName StemmaDeploy Invoke-StemmaCli {
            if ($Arguments[0] -eq 'backup') { New-Item -ItemType File -Force -Path $Arguments[2] | Out-Null }
        }
        Mock -ModuleName StemmaDeploy Invoke-Alembic {}
        Mock -ModuleName StemmaDeploy Set-CurrentRelease {}
        Mock -ModuleName StemmaDeploy Write-Step {}
    }

    It 'faz backup, migra, troca o current e confere a versão nova' {
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $true }
        Invoke-StemmaUpdate -Root $root -ServiceId 'teste' 6>$null | Should -Be 'v1.1.0'
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'backup' -and $ReleaseDir -eq $script:next }
        Should -Invoke -ModuleName StemmaDeploy Set-CurrentRelease -Times 1 -Exactly -ParameterFilter { $ReleaseDir -eq $script:next }
        Should -Invoke -ModuleName StemmaDeploy Wait-StemmaHealth -Times 1 -Exactly -ParameterFilter { $Port -eq 8001 -and $ExpectedVersion -eq 'v1.1.0' }
    }

    It 'poda os backups antigos só depois da versão nova no ar, com o CLI dela' {
        $script:order = [Collections.Generic.List[string]]::new()
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $script:order.Add('health'); $true }
        Mock -ModuleName StemmaDeploy Invoke-StemmaCli {
            $script:order.Add($Arguments[0])
            if ($Arguments[0] -eq 'backup') { New-Item -ItemType File -Force -Path $Arguments[2] | Out-Null }
        }
        Invoke-StemmaUpdate -Root $root -ServiceId 'teste' 6>$null | Out-Null
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'prune-backups' -and $ReleaseDir -eq $script:next }
        $script:order | Should -Be @('backup', 'health', 'prune-backups')
    }

    It 'falha ao podar os backups só avisa: a atualização continua concluída' {
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $true }
        Mock -ModuleName StemmaDeploy Invoke-StemmaCli {
            if ($Arguments[0] -eq 'backup') { New-Item -ItemType File -Force -Path $Arguments[2] | Out-Null }
            if ($Arguments[0] -eq 'prune-backups') { throw 'disco ocupado' }
        }
        $saida = @(Invoke-StemmaUpdate -Root $root -ServiceId 'teste' 3>&1 6>$null)
        $saida | Where-Object { $_ -is [string] } | Should -Be 'v1.1.0'
        $avisos = @($saida | Where-Object { $_ -is [Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
        ($avisos -join ' ') | Should -BeLike '*Backups antigos não foram podados*disco ocupado*'
    }

    It 'com falha simulada restaura o banco, volta o current e avisa que a anterior continua' {
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $ExpectedVersion -eq 'v1.0.0' }
        { Invoke-StemmaUpdate -Root $root -ServiceId 'teste' -SimulateFailure -WarningAction SilentlyContinue 6>$null } |
            Should -Throw '*v1.0.0 continua no ar*'
        Should -Invoke -ModuleName StemmaDeploy Wait-StemmaHealth -ParameterFilter { $ExpectedVersion -eq 'v0.0.0' }
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'restore' -and $ReleaseDir -eq $script:current }
        Should -Invoke -ModuleName StemmaDeploy Set-CurrentRelease -Times 1 -Exactly -ParameterFilter { $ReleaseDir -eq $script:current }
        # Atualização que deu errado nunca poda backups: o rollback precisa deles.
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 0 -Exactly -ParameterFilter { $Arguments[0] -eq 'prune-backups' }
    }

    It 'mantém no venv novo o yt-dlp da anterior, se for mais novo que o do uv.lock' {
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $true }
        Mock -ModuleName StemmaDeploy Sync-StemmaYtDlpFloor { $script:calls.Add('ytdlp') }
        Invoke-StemmaUpdate -Root $root -ServiceId 'teste' 6>$null | Out-Null
        Should -Invoke -ModuleName StemmaDeploy Sync-StemmaYtDlpFloor -Times 1 -Exactly -ParameterFilter {
            $ReleaseDir -eq $script:next -and $PreviousDir -eq $script:current
        }
        # Com o serviço ainda no ar: o venv novo não está em uso.
        $script:calls.IndexOf('ytdlp') | Should -BeLessThan $script:calls.IndexOf('stop')
    }

    It 'troca FFmpeg e Deno só com o serviço parado (o uv antes)' {
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $true }
        Invoke-StemmaUpdate -Root $root -ServiceId 'teste' 6>$null | Out-Null
        $script:calls | Should -Be @('tools:uv', 'stop', 'tools:ffmpeg,deno')
    }

    It 'mesma versão não para o serviço, mas confere o /health (instalação que falhou no meio)' {
        Mock -ModuleName StemmaDeploy Get-StemmaPackage { [pscustomobject]@{ Tag = 'v1.0.0'; Zip = 'x.zip' } }
        Mock -ModuleName StemmaDeploy Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $true }
        Invoke-StemmaUpdate -Root $root -ServiceId 'teste' 6>$null | Should -Be 'v1.0.0'
        Should -Invoke -ModuleName StemmaDeploy Stop-StemmaService -Times 0 -Exactly
        Should -Invoke -ModuleName StemmaDeploy Start-StemmaService -Times 1 -Exactly
        Should -Invoke -ModuleName StemmaDeploy Wait-StemmaHealth -Times 1 -Exactly -ParameterFilter { $ExpectedVersion -eq 'v1.0.0' }
    }

    It 'mesma versão sem /health falha' {
        Mock -ModuleName StemmaDeploy Get-StemmaPackage { [pscustomobject]@{ Tag = 'v1.0.0'; Zip = 'x.zip' } }
        Mock -ModuleName StemmaDeploy Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $false }
        { Invoke-StemmaUpdate -Root $root -ServiceId 'teste' 6>$null } | Should -Throw '*não respondeu*'
    }
}

Describe 'Invoke-StemmaInstall' {
    It 'sem o Tailscale pronto falha antes de mexer em qualquer coisa' {
        Mock -ModuleName StemmaDeploy Test-StemmaService { $false }
        Mock -ModuleName StemmaDeploy Get-TailscaleState { [pscustomobject]@{ State = 'needslogin'; Host = ''; AuthUrl = '' } }
        Mock -ModuleName StemmaDeploy Get-PortUsage { $null }
        Mock -ModuleName StemmaDeploy Initialize-StemmaRuntime {}
        $root = Join-Path $TestDrive 'nada'
        { Invoke-StemmaInstall -Root $root -DataRoot (Join-Path $TestDrive 'dados') } | Should -Throw '*Tailscale não está pronto*'
        Should -Invoke -ModuleName StemmaDeploy Initialize-StemmaRuntime -Times 0 -Exactly
        Test-Path -LiteralPath $root | Should -BeFalse
    }

    It 'protege as pastas antes de criar qualquer coisa e semeia com o lock da release' {
        $root = Join-Path $TestDrive 'ordem'
        $script:calls = [Collections.Generic.List[string]]::new()
        Mock -ModuleName StemmaDeploy Test-StemmaService { $false }
        Mock -ModuleName StemmaDeploy Get-PortUsage { $null }
        Mock -ModuleName StemmaDeploy Find-UserUvCache { 'C:\cache-usuario' }
        Mock -ModuleName StemmaDeploy Test-SameVolume { $true }
        Mock -ModuleName StemmaDeploy Protect-StemmaDirectory { $script:calls.Add("protect:$(Split-Path -Leaf $Path)") }
        Mock -ModuleName StemmaDeploy Get-StemmaPackage { [pscustomobject]@{ Tag = 'v1.0.0'; Zip = 'x.zip' } }
        Mock -ModuleName StemmaDeploy Expand-StemmaPackage { $script:calls.Add('package'); Join-Path $root 'releases\v1.0.0' }
        Mock -ModuleName StemmaDeploy Initialize-StemmaRuntime { $script:calls.Add('tools') }
        Mock -ModuleName StemmaDeploy Install-StemmaPython { $script:calls.Add('python') }
        Mock -ModuleName StemmaDeploy Copy-UvCacheSeed { $script:calls.Add("seed:$(Split-Path -Leaf $LockPath)") }
        Mock -ModuleName StemmaDeploy Set-ComponentsStageWeight {}
        Mock -ModuleName StemmaDeploy Sync-ReleaseEnvironment { $script:calls.Add('sync'); 'cache' }
        Mock -ModuleName StemmaDeploy Invoke-Alembic {}
        Mock -ModuleName StemmaDeploy Set-CurrentRelease {}
        Mock -ModuleName StemmaDeploy Register-StemmaService {}
        Mock -ModuleName StemmaDeploy Start-StemmaService {}
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $true }
        Mock -ModuleName StemmaDeploy Write-Step {}

        Invoke-StemmaInstall -Root $root -DataRoot (Join-Path $TestDrive 'dados-ordem') -SkipTailscale 6>$null | Should -Be 'v1.0.0'
        $script:calls | Should -Be @('protect:ordem', 'protect:dados-ordem', 'package', 'tools', 'python', 'seed:uv.lock', 'sync')
    }
}

Describe 'Invoke-StemmaUninstall' {
    It 'remove serviço e pastas, mantém a do desinstalador e os dados' -Skip:(-not $OnWindows) {
        $root = Join-Path $TestDrive 'raiz'
        $data = Join-Path $TestDrive 'dados'
        foreach ($dir in 'setup', 'releases\v1.0.0', 'tools\uv', 'cache\uv') {
            New-Item -ItemType Directory -Force -Path (Join-Path $root $dir) | Out-Null
        }
        New-Item -ItemType Directory -Force -Path $data | Out-Null
        Set-Content -LiteralPath (Join-Path $root '.env') -Value "STORAGE_ROOT=$data"
        Set-StemmaInstallInfo -Root $root -ServiceId 'stemma-teste' -TailscaleServe $true
        Set-CurrentRelease -Root $root -ReleaseDir (Join-Path $root 'releases\v1.0.0')
        Mock -ModuleName StemmaDeploy Unregister-StemmaService {}
        Mock -ModuleName StemmaDeploy Remove-TailscaleServe {}
        Mock -ModuleName StemmaDeploy Write-Step {}

        Invoke-StemmaUninstall -Root $root -Keep @('setup')

        Should -Invoke -ModuleName StemmaDeploy Unregister-StemmaService -ParameterFilter { $ServiceId -eq 'stemma-teste' }
        Should -Invoke -ModuleName StemmaDeploy Remove-TailscaleServe -Times 1 -Exactly
        @(Get-ChildItem -LiteralPath $root -Force).Name | Should -Be @('setup')
        Test-Path -LiteralPath $data | Should -BeTrue
    }
}
