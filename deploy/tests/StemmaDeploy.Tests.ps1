# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`).

BeforeDiscovery {
    # Junction só existe no Windows; no CI (Linux) o teste fica pulado.
    $OnWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
}

Describe 'Read-DotEnv' {
    It 'lê chaves, ignora comentários e tira aspas' {
        $file = Join-Path $TestDrive '.env'
        Set-Content -LiteralPath $file -Encoding UTF8 -Value @(
            '# comentário',
            '',
            'PORT=8000',
            'STORAGE_ROOT="D:\stemma-data"',
            "LOG_LEVEL='DEBUG'",
            'VAZIO=',
            'sem_igual'
        )
        $values = Read-DotEnv -Path $file
        $values['PORT'] | Should -Be '8000'
        $values['STORAGE_ROOT'] | Should -Be 'D:\stemma-data'
        $values['LOG_LEVEL'] | Should -Be 'DEBUG'
        $values['VAZIO'] | Should -Be ''
        $values.Contains('sem_igual') | Should -BeFalse
    }

    It 'arquivo ausente devolve vazio' {
        (Read-DotEnv -Path (Join-Path $TestDrive 'nao-existe')).Count | Should -Be 0
    }
}

Describe 'Get-StemmaPort' {
    It 'usa o PORT do .env ou 8000' {
        Get-StemmaPort @{ PORT = '8123' } | Should -Be 8123
        Get-StemmaPort @{} | Should -Be 8000
    }
}

Describe 'Versões' {
    It 'aceita vX.Y.Z e X.Y.Z' {
        ConvertTo-StemmaVersion 'v1.10.2' | Should -Be ([version]'1.10.2')
        ConvertTo-StemmaVersion '1.2.3' | Should -Be ([version]'1.2.3')
    }

    It 'recusa o resto' {
        ConvertTo-StemmaVersion '.tmp-v1.2.3' | Should -BeNullOrEmpty
        ConvertTo-StemmaVersion 'v1.2' | Should -BeNullOrEmpty
        ConvertTo-StemmaVersion 'v1.2.3-rc1' | Should -BeNullOrEmpty
    }

    It 'tira a tag do nome do zip' {
        Get-VersionFromZipName 'C:\x\stemma-v1.3.0.zip' | Should -Be 'v1.3.0'
        Get-VersionFromZipName '/tmp/x/stemma-v1.3.0.zip' | Should -Be 'v1.3.0'
        { Get-VersionFromZipName 'outra-coisa.zip' } | Should -Throw
    }
}

Describe 'Releases instaladas' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        foreach ($name in 'v1.2.0', 'v1.10.0', 'v1.3.0', '.tmp-v1.4.0', 'lixo') {
            New-Item -ItemType Directory -Force -Path (Join-Path $root "releases\$name") | Out-Null
        }
    }

    It 'lista só vX.Y.Z, da mais nova para a mais antiga (ordem numérica)' {
        (Get-InstalledReleases -Root $root).Name | Should -Be @('v1.10.0', 'v1.3.0', 'v1.2.0')
    }

    It 'acha a anterior à atual' {
        (Get-PreviousRelease -Root $root -Current 'v1.10.0').Name | Should -Be 'v1.3.0'
        Get-PreviousRelease -Root $root -Current 'v1.2.0' | Should -BeNullOrEmpty
    }
}

Describe 'Select-ReleasesToRemove' {
    It 'mantém as 3 mais novas' {
        Select-ReleasesToRemove -Names @('v1.0.0', 'v1.3.0', 'v1.1.0', 'v1.2.0', 'v0.9.0') |
            Should -Be @('v1.0.0', 'v0.9.0')
    }

    It 'nunca remove as protegidas' {
        Select-ReleasesToRemove -Names @('v1.0.0', 'v1.3.0', 'v1.1.0', 'v1.2.0') -Protect @('v1.0.0') |
            Should -BeNullOrEmpty
    }

    It 'aceita lista vazia' {
        Select-ReleasesToRemove -Names @() | Should -BeNullOrEmpty
    }
}

Describe 'SHA256' {
    It 'lê o formato do sha256sum e confere o arquivo' {
        $file = Join-Path $TestDrive 'stemma-v1.0.0.zip'
        Set-Content -LiteralPath $file -Value 'conteúdo' -NoNewline
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        Set-Content -LiteralPath "$file.sha256" -Value "$hash  stemma-v1.0.0.zip"

        Get-Sha256FromFile "$file.sha256" | Should -Be $hash
        { Assert-Sha256 -Path $file -Expected $hash } | Should -Not -Throw
        { Assert-Sha256 -Path $file -Expected ('0' * 64) } | Should -Throw '*não confere*'
    }

    It 'recusa arquivo de hash inválido' {
        $file = Join-Path $TestDrive 'ruim.sha256'
        Set-Content -LiteralPath $file -Value 'abc  x.zip'
        { Get-Sha256FromFile $file } | Should -Throw
    }
}

Describe 'Pacote local' {
    It 'extrai lado a lado em releases\<tag>' {
        $root = Join-Path $TestDrive 'root'
        $stage = Join-Path $TestDrive 'stage\stemma-v2.0.0'
        New-Item -ItemType Directory -Force -Path (Join-Path $stage 'backend') | Out-Null
        Set-Content -LiteralPath (Join-Path $stage 'backend\pyproject.toml') -Value 'x'
        $zip = Join-Path $TestDrive 'stemma-v2.0.0.zip'
        Compress-Archive -Path $stage -DestinationPath $zip
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        Set-Content -LiteralPath "$zip.sha256" -Value "$hash  stemma-v2.0.0.zip"

        $package = Get-StemmaPackage -Root $root -ZipPath $zip
        $package.Tag | Should -Be 'v2.0.0'
        $dest = Expand-StemmaPackage -Root $root -Zip $package.Zip -Tag $package.Tag

        $dest | Should -Be (Join-Path $root 'releases\v2.0.0')
        Test-Path (Join-Path $dest 'backend\pyproject.toml') | Should -BeTrue
        Test-Path (Join-Path $root 'releases\.tmp-v2.0.0') | Should -BeFalse
    }

    It 'falha sem o .sha256' {
        $zip = Join-Path $TestDrive 'stemma-v3.0.0.zip'
        Set-Content -LiteralPath $zip -Value 'x'
        { Get-StemmaPackage -Root $TestDrive -ZipPath $zip } | Should -Throw '*sha256*'
    }
}

Describe 'Invoke-Native' {
    BeforeAll {
        function Invoke-Shell([string]$Script) {
            if ([Environment]::OSVersion.Platform -eq 'Win32NT') { Invoke-Native -FilePath 'cmd.exe' -Arguments @('/c', $Script) }
            else { Invoke-Native -FilePath 'sh' -Arguments @('-c', $Script) }
        }
    }

    It 'stderr com exit 0 não derruba o script (log do uv/alembic)' {
        $ErrorActionPreference = 'Stop'
        { Invoke-Shell 'echo log-no-stderr 1>&2' 6>$null } | Should -Not -Throw
    }

    It 'exit code diferente de 0 falha' {
        { Invoke-Shell 'exit 3' } | Should -Throw '*código 3*'
    }
}

Describe 'ConvertFrom-AlembicHeads' {
    It 'pega a revisão head' {
        ConvertFrom-AlembicHeads @('INFO  [alembic] algo', 'a1b2c3d4e5f6 (head)') | Should -Be 'a1b2c3d4e5f6'
    }

    It 'falha sem head ou com várias' {
        { ConvertFrom-AlembicHeads @() } | Should -Throw
        { ConvertFrom-AlembicHeads @('aaa (head)', 'bbb (head)') } | Should -Throw
    }
}

Describe 'Wait-StemmaHealth' {
    It 'devolve $true quando a versão bate' {
        Mock -ModuleName StemmaDeploy Invoke-RestMethod { [pscustomobject]@{ version = '1.3.0'; status = 'ok'; gpu = 'ok'; ytdlp = 'x' } }
        Wait-StemmaHealth -Port 8000 -ExpectedVersion 'v1.3.0' -TimeoutSec 1 -IntervalSec 0 | Should -BeTrue
    }

    It 'devolve $false se a versão não bate até o prazo' {
        Mock -ModuleName StemmaDeploy Invoke-RestMethod { [pscustomobject]@{ version = '1.2.0' } }
        Mock -ModuleName StemmaDeploy Start-Sleep {}
        Wait-StemmaHealth -Port 8000 -ExpectedVersion 'v1.3.0' -TimeoutSec 0 -WarningAction SilentlyContinue | Should -BeFalse
    }
}

Describe 'New-ServiceXml' {
    It 'troca o id e gera XML válido' {
        $dest = Join-Path $TestDrive 'teste.xml'
        New-ServiceXml -Template (Join-Path $PSScriptRoot '..\stemma-service.xml') -ServiceId 'stemma-teste' -Dest $dest
        $xml = [xml](Get-Content -LiteralPath $dest -Raw -Encoding UTF8)
        $xml.service.id | Should -Be 'stemma-teste'
        $xml.service.arguments | Should -Match 'current\\deploy\\start\.ps1'
    }
}

Describe 'Junction current' {
    It 'aponta e reaponta sem apagar a release' -Skip:(-not $OnWindows) {
        $root = Join-Path $TestDrive 'j'
        $a = New-Item -ItemType Directory -Force -Path (Join-Path $root 'releases\v1.0.0')
        $b = New-Item -ItemType Directory -Force -Path (Join-Path $root 'releases\v1.1.0')
        Set-Content -LiteralPath (Join-Path $a.FullName 'marca.txt') -Value 'a'

        Get-CurrentRelease -Root $root | Should -BeNullOrEmpty
        Set-CurrentRelease -Root $root -ReleaseDir $a.FullName
        Get-CurrentRelease -Root $root | Should -Be $a.FullName
        Set-CurrentRelease -Root $root -ReleaseDir $b.FullName
        Get-CurrentRelease -Root $root | Should -Be $b.FullName
        Test-Path (Join-Path $a.FullName 'marca.txt') | Should -BeTrue
    }
}

Describe 'Scripts' {
    BeforeDiscovery {
        $Scripts = @('install.ps1', 'update.ps1', 'start.ps1', 'setup.ps1', 'StemmaDeploy.psm1', '..\installer\build.ps1')
    }

    It '<_> não tem erro de sintaxe' -ForEach $Scripts {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "..\$_"), [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It '<_> tem BOM (o Windows PowerShell 5.1 lê sem BOM como ANSI)' -ForEach $Scripts {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot "..\$_"))
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'sem caracteres de controle (um "\b" vira backspace e quebra caminhos)' {
        $repo = Join-Path $PSScriptRoot '..\..'
        $files = @(Get-ChildItem -LiteralPath (Join-Path $repo 'deploy'), (Join-Path $repo 'installer'), (Join-Path $repo '.github\workflows') -Recurse -File |
                Where-Object { $_.Extension -in '.ps1', '.psm1', '.iss', '.cs', '.yml', '.xml' })
        $files.Count | Should -BeGreaterThan 5
        foreach ($file in $files) {
            $bad = @([IO.File]::ReadAllBytes($file.FullName) | Where-Object { $_ -lt 32 -and $_ -notin 9, 10, 13 })
            $bad.Count | Should -Be 0 -Because $file.FullName
        }
    }

    It 'o .iss tem BOM (o Inno lê sem BOM como ANSI)' {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot '..\..\installer\stemma.iss'))
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }

    It 'o modelo do serviço não define conta (LocalSystem)' {
        $xml = [xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\stemma-service.xml') -Raw -Encoding UTF8)
        $xml.service.SelectSingleNode('serviceaccount') | Should -BeNullOrEmpty
    }
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

Describe '.env da instalação' {
    It 'cria com FFMPEG_BIN absoluto' {
        $file = Join-Path $TestDrive 'novo.env'
        New-StemmaEnvFile -Path $file -Port 8001 -DataRoot 'D:\dados' -FfmpegBin 'C:\stemma\tools\ffmpeg\bin\ffmpeg.exe'
        $values = Read-DotEnv -Path $file
        $values['PORT'] | Should -Be '8001'
        $values['STORAGE_ROOT'] | Should -Be 'D:\dados'
        $values['FFMPEG_BIN'] | Should -Be 'C:\stemma\tools\ffmpeg\bin\ffmpeg.exe'
    }

    It 'acrescenta só o que falta e preserva o resto' {
        $file = Join-Path $TestDrive 'antigo.env'
        Set-Content -LiteralPath $file -Encoding UTF8 -Value @('# meu comentário', 'PORT=8123', 'FFMPEG_BIN=ffmpeg')
        $added = Update-StemmaEnvFile -Path $file -Defaults ([ordered]@{ FFMPEG_BIN = 'C:\x\ffmpeg.exe'; LOG_LEVEL = 'INFO' })
        $added | Should -Be @('LOG_LEVEL')
        $content = Get-Content -LiteralPath $file -Encoding UTF8
        $content[0] | Should -Be '# meu comentário'
        (Read-DotEnv -Path $file)['FFMPEG_BIN'] | Should -Be 'ffmpeg'
        (Read-DotEnv -Path $file)['LOG_LEVEL'] | Should -Be 'INFO'
        Update-StemmaEnvFile -Path $file -Defaults ([ordered]@{ LOG_LEVEL = 'DEBUG' }) | Should -BeNullOrEmpty
    }
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

Describe 'Copy-UvCacheSeed' {
    It 'liga os arquivos por hardlink e pula os que já existem' -Skip:(-not $OnWindows) {
        $src = Join-Path $TestDrive 'cache-usuario'
        $dst = Join-Path $TestDrive 'cache-stemma'
        New-Item -ItemType Directory -Force -Path (Join-Path $src 'archive-v0\abc'), (Join-Path $dst 'archive-v0\abc') | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'archive-v0\abc\torch.py') -Value 'original'
        Set-Content -LiteralPath (Join-Path $src 'archive-v0\abc\ja.py') -Value 'do usuário'
        Set-Content -LiteralPath (Join-Path $dst 'archive-v0\abc\ja.py') -Value 'já estava'
        Mock -ModuleName StemmaDeploy Write-Step {}

        $summary = Copy-UvCacheSeed -Source $src -Dest $dst 6>$null
        $summary.Linked | Should -Be 1
        $summary.Skipped | Should -Be 1
        # Mesmo arquivo: mudar por um lado aparece do outro.
        Add-Content -LiteralPath (Join-Path $dst 'archive-v0\abc\torch.py') -Value 'mais'
        (Get-Content -LiteralPath (Join-Path $src 'archive-v0\abc\torch.py')) | Should -Be @('original', 'mais')
        Get-Content -LiteralPath (Join-Path $dst 'archive-v0\abc\ja.py') | Should -Be 'já estava'
    }

    It 'não atravessa junctions (formato antigo do cache) e segue com o resto' -Skip:(-not $OnWindows) {
        $src = Join-Path $TestDrive 'cache-junction'
        $dst = Join-Path $TestDrive 'cache-junction-destino'
        New-Item -ItemType Directory -Force -Path (Join-Path $src 'archive-v0\xyz'), (Join-Path $src 'wheels-v3') | Out-Null
        Set-Content -LiteralPath (Join-Path $src 'archive-v0\xyz\mod.py') -Value 'x'
        New-Item -ItemType Junction -Path (Join-Path $src 'wheels-v3\pkg') -Target (Join-Path $src 'archive-v0\xyz') | Out-Null
        Mock -ModuleName StemmaDeploy Write-Step {}

        $summary = Copy-UvCacheSeed -Source $src -Dest $dst 6>$null
        $summary.Linked | Should -Be 1
        $summary.Failed | Should -Be 0
        Test-Path -LiteralPath (Join-Path $dst 'archive-v0\xyz\mod.py') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $dst 'wheels-v3\pkg') | Should -BeFalse
    }

    It 'não semeia em outro volume nem de si mesmo' {
        Mock -ModuleName StemmaDeploy Test-SameVolume { $false }
        Copy-UvCacheSeed -Source (Join-Path $TestDrive 'a') -Dest (Join-Path $TestDrive 'b') 6>$null | Should -BeNullOrEmpty
        Copy-UvCacheSeed -Source (Join-Path $TestDrive 'a') -Dest (Join-Path $TestDrive 'a') | Should -BeNullOrEmpty
    }
}

Describe 'Sync-ReleaseEnvironment -PreferOffline' {
    BeforeEach { Mock -ModuleName StemmaDeploy Write-Step {} }

    It 'usa só o cache quando o --offline passa' {
        Mock -ModuleName StemmaDeploy Invoke-Native {}
        Sync-ReleaseEnvironment -ReleaseDir 'C:\r' -PreferOffline | Should -Be 'cache'
        Should -Invoke -ModuleName StemmaDeploy Invoke-Native -Times 1 -Exactly -ParameterFilter { $Arguments -contains '--offline' }
    }

    It 'baixa quando falta algo no cache' {
        Mock -ModuleName StemmaDeploy Invoke-Native { throw 'falta' } -ParameterFilter { $Arguments -contains '--offline' }
        Mock -ModuleName StemmaDeploy Invoke-Native {} -ParameterFilter { $Arguments -notcontains '--offline' }
        Sync-ReleaseEnvironment -ReleaseDir 'C:\r' -PreferOffline 6>$null | Should -Be 'download'
        Should -Invoke -ModuleName StemmaDeploy Invoke-Native -Times 1 -Exactly -ParameterFilter { $Arguments -notcontains '--offline' }
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

    It 'com falha simulada restaura o banco, volta o current e avisa que a anterior continua' {
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $ExpectedVersion -eq 'v1.0.0' }
        { Invoke-StemmaUpdate -Root $root -ServiceId 'teste' -SimulateFailure -WarningAction SilentlyContinue 6>$null } |
            Should -Throw '*v1.0.0 continua no ar*'
        Should -Invoke -ModuleName StemmaDeploy Wait-StemmaHealth -ParameterFilter { $ExpectedVersion -eq 'v0.0.0' }
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'restore' -and $ReleaseDir -eq $script:current }
        Should -Invoke -ModuleName StemmaDeploy Set-CurrentRelease -Times 1 -Exactly -ParameterFilter { $ReleaseDir -eq $script:current }
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
        Mock -ModuleName StemmaDeploy Initialize-StemmaRuntime {}
        $root = Join-Path $TestDrive 'nada'
        { Invoke-StemmaInstall -Root $root -DataRoot (Join-Path $TestDrive 'dados') } | Should -Throw '*Tailscale não está pronto*'
        Should -Invoke -ModuleName StemmaDeploy Initialize-StemmaRuntime -Times 0 -Exactly
        Test-Path -LiteralPath $root | Should -BeFalse
    }
}

Describe 'Parar e iniciar (Menu Iniciar)' {
    BeforeEach {
        Mock -ModuleName StemmaDeploy Invoke-Native {}
        Mock -ModuleName StemmaDeploy Stop-StemmaService {}
        Mock -ModuleName StemmaDeploy Start-StemmaService {}
    }

    It 'parar deixa o serviço manual' {
        Disable-StemmaService -ServiceId 'stemma-teste'
        Should -Invoke -ModuleName StemmaDeploy Stop-StemmaService -Times 1 -Exactly
        Should -Invoke -ModuleName StemmaDeploy Invoke-Native -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'config stemma-teste start= demand' }
    }

    It 'iniciar volta ao automático e sobe se estiver parado' {
        Mock -ModuleName StemmaDeploy Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        Enable-StemmaService -ServiceId 'stemma-teste'
        Should -Invoke -ModuleName StemmaDeploy Invoke-Native -Times 1 -Exactly -ParameterFilter { ($Arguments -join ' ') -eq 'config stemma-teste start= delayed-auto' }
        Should -Invoke -ModuleName StemmaDeploy Start-StemmaService -Times 1 -Exactly
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
