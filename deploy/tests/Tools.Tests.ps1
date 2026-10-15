# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`). Testes de StemmaDeploy.Tools.ps1.

BeforeDiscovery {
    # Junction só existe no Windows; no CI (Linux) o teste fica pulado.
    $OnWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
}

Describe 'Catálogo de ferramentas' {
    It '<_> tem versão, URL https e SHA256' -ForEach @('uv', 'ffmpeg', 'deno') {
        $tool = (Get-StemmaToolCatalog)[$_]
        $tool.Version | Should -Not -BeNullOrEmpty
        $tool.Url | Should -Match '^https://'
        $tool.Url | Should -Match ([regex]::Escape($tool.Version))
        $tool.Sha256 | Should -Match '^[0-9a-f]{64}$'
    }

    It 'devolve uma cópia (o catálogo do módulo não muda)' {
        (Get-StemmaToolCatalog)['uv'].Version = 'x'
        (Get-StemmaToolCatalog)['uv'].Version | Should -Not -Be 'x'
    }
}

Describe 'Install-StemmaTool' {
    BeforeAll {
        # Zip falso com uma pasta de topo, como o do FFmpeg.
        $stage = Join-Path $TestDrive 'fonte\ferramenta-1.0\bin'
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        Set-Content -LiteralPath (Join-Path $stage 'tool.exe') -Value 'binário'
        $script:FakeZip = Join-Path $TestDrive 'ferramenta-1.0.zip'
        Compress-Archive -Path (Join-Path $TestDrive 'fonte\ferramenta-1.0') -DestinationPath $script:FakeZip
        $script:FakeSha = (Get-FileHash -LiteralPath $script:FakeZip -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        Mock -ModuleName StemmaDeploy Invoke-Download { Copy-Item -LiteralPath $script:FakeZip -Destination $Dest } `
            -ParameterFilter { $true }
        Mock -ModuleName StemmaDeploy Write-Step {}
    }

    It 'baixa, confere, tira a pasta de topo e é idempotente' {
        $tool = @{ Version = '1.0'; Url = 'https://x/ferramenta-1.0.zip'; Sha256 = $script:FakeSha; Strip = $true; Exe = 'bin\tool.exe' }
        $exe = Install-StemmaTool -Root $root -Name 'ferramenta' -Tool $tool
        $exe | Should -Be (Join-Path $root 'tools\ferramenta\bin\tool.exe')
        Test-Path -LiteralPath $exe | Should -BeTrue
        Install-StemmaTool -Root $root -Name 'ferramenta' -Tool $tool | Out-Null
        Should -Invoke -ModuleName StemmaDeploy Invoke-Download -Times 1 -Exactly
    }

    It 'troca quando a versão muda' {
        $tool = @{ Version = '1.0'; Url = 'https://x/ferramenta-1.0.zip'; Sha256 = $script:FakeSha; Strip = $true; Exe = 'bin\tool.exe' }
        Install-StemmaTool -Root $root -Name 'ferramenta' -Tool $tool | Out-Null
        $tool.Version = '1.1'
        Install-StemmaTool -Root $root -Name 'ferramenta' -Tool $tool | Out-Null
        Should -Invoke -ModuleName StemmaDeploy Invoke-Download -Times 2 -Exactly
        Get-Content -LiteralPath (Join-Path $root 'tools\ferramenta\.stemma-tool') | Should -Match '^1\.1 '
    }

    It 'marcador vazio (escrita interrompida) reinstala em vez de quebrar' {
        $tool = @{ Version = '1.0'; Url = 'https://x/ferramenta-1.0.zip'; Sha256 = $script:FakeSha; Strip = $true; Exe = 'bin\tool.exe' }
        Install-StemmaTool -Root $root -Name 'ferramenta' -Tool $tool | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'tools\ferramenta\.stemma-tool') -Value '' -NoNewline
        Test-StemmaToolInstalled -Dir (Join-Path $root 'tools\ferramenta') -Tool $tool | Should -BeFalse
    }

    It 'SHA256 errado falha e não instala' {
        $tool = @{ Version = '1.0'; Url = 'https://x/ferramenta-1.0.zip'; Sha256 = ('0' * 64); Strip = $true; Exe = 'bin\tool.exe' }
        { Install-StemmaTool -Root $root -Name 'ferramenta' -Tool $tool } | Should -Throw '*não confere*'
        Test-Path -LiteralPath (Join-Path $root 'tools\ferramenta') | Should -BeFalse
    }
}

Describe 'Set-StemmaToolEnv' {
    BeforeEach {
        $saved = @{}
        foreach ($key in 'PATH', 'UV_CACHE_DIR', 'UV_PYTHON_INSTALL_DIR', 'UV_PYTHON_PREFERENCE', 'UV_PYTHON_INSTALL_BIN', 'UV_PYTHON_INSTALL_REGISTRY', 'UV_NO_PROGRESS') {
            $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        }
    }
    AfterEach {
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    }

    It 'põe tools\ no começo do PATH, sem duplicar, e fixa o cache e o Python do uv' {
        Set-StemmaToolEnv -Root 'C:\stemma'
        Set-StemmaToolEnv -Root 'C:\stemma'
        $parts = $env:PATH -split ';'
        $parts[0..2] | Should -Be @('C:\stemma\tools\uv', 'C:\stemma\tools\ffmpeg\bin', 'C:\stemma\tools\deno')
        @($parts | Where-Object { $_ -eq 'C:\stemma\tools\uv' }).Count | Should -Be 1
        $env:UV_CACHE_DIR | Should -Be 'C:\stemma\cache\uv'
        $env:UV_PYTHON_INSTALL_DIR | Should -Be 'C:\stemma\tools\python'
        $env:UV_PYTHON_PREFERENCE | Should -Be 'only-managed'
        # Nada no perfil do usuário (~\.local\bin, HKCU).
        $env:UV_PYTHON_INSTALL_BIN | Should -Be '0'
        $env:UV_PYTHON_INSTALL_REGISTRY | Should -Be '0'
    }
}

Describe 'Protect-StemmaDirectory' {
    BeforeDiscovery {
        $IsAdmin = $OnWindows -and ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    It 'tira a herança, deixa Usuários só com leitura e Administradores como dono' -Skip:(-not $IsAdmin) {
        $dir = Join-Path $TestDrive 'protegida'
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'sub') | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'sub\a.txt') -Value 'x'
        Mock -ModuleName StemmaDeploy Write-Step {}

        Protect-StemmaDirectory -Path $dir

        $acl = Get-Acl -LiteralPath (Join-Path $dir 'sub\a.txt')
        $acl.Owner | Should -Match 'Administra'
        $users = @($acl.Access | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-545' })
        $users.Count | Should -BeGreaterThan 0
        $users | ForEach-Object { $_.FileSystemRights.ToString() | Should -Not -Match 'Write|Modify|FullControl' }
        @($acl.Access | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-11' }).Count | Should -Be 0
        (Get-Acl -LiteralPath $dir).AreAccessRulesProtected | Should -BeTrue
    }
}
