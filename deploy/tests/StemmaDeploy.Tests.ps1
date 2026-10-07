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

    It 'troca um valor (nova tentativa de instalação vale a porta escolhida agora)' {
        $file = Join-Path $TestDrive 'tentativa.env'
        Set-Content -LiteralPath $file -Encoding UTF8 -Value @('# x', 'PORT=8000', 'STORAGE_ROOT=D:\a')
        Set-DotEnvValue -Path $file -Key 'PORT' -Value '8002'
        Set-DotEnvValue -Path $file -Key 'LOG_LEVEL' -Value 'INFO'
        $values = Read-DotEnv -Path $file
        $values['PORT'] | Should -Be '8002'
        $values['STORAGE_ROOT'] | Should -Be 'D:\a'
        $values['LOG_LEVEL'] | Should -Be 'INFO'
        (Get-Content -LiteralPath $file -Encoding UTF8)[0] | Should -Be '# x'
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
        # Mesmo arquivo: a ACL protegida do link aparece também no cache do usuário.
        Get-Content -LiteralPath (Join-Path $dst 'archive-v0\abc\torch.py') | Should -Be 'original'
        (Get-Acl -LiteralPath (Join-Path $src 'archive-v0\abc\torch.py')).AreAccessRulesProtected | Should -BeTrue
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

Describe 'Semeadura seletiva do cache' {
    BeforeAll {
        function New-FakeCache([string]$Path, [hashtable]$Archives, [hashtable]$Pointers) {
            # Archives: id → arquivos; Pointers: 'pacote\versão-tags' → id.
            foreach ($id in $Archives.Keys) {
                $dir = Join-Path $Path "archive-v0\$id"
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
                foreach ($file in $Archives[$id]) { Set-Content -LiteralPath (Join-Path $dir $file) -Value $file }
            }
            foreach ($pointer in $Pointers.Keys) {
                $file = Join-Path $Path "wheels-v6\index\abc\$pointer"
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
                [IO.File]::WriteAllText($file, "archive-v0/$($Pointers[$pointer])")
                Set-Content -LiteralPath "$file.http" -Value 'metadados'
            }
            New-Item -ItemType Directory -Force -Path (Join-Path $Path 'simple-v24') | Out-Null
            Set-Content -LiteralPath (Join-Path $Path 'simple-v24\indice') -Value 'x'
        }
        $script:lockText = @'
version = 1

[[package]]
name = "Torch"
version = "2.7.1+cu118"
source = { registry = "https://download.pytorch.org/whl/cu118" }
wheels = [
    { url = "https://download-r2.pytorch.org/whl/cu118/torch-2.7.1%2Bcu118-cp312-cp312-manylinux_2_28_x86_64.whl", hash = "sha256:aa" },
    { url = "https://download-r2.pytorch.org/whl/cu118/torch-2.7.1%2Bcu118-cp312-cp312-win_amd64.whl", hash = "sha256:bb" },
]

[[package]]
name = "typing-extensions"
version = "4.15.0"
source = { registry = "https://pypi.org/simple" }
sdist = { url = "https://files.pythonhosted.org/x/typing_extensions-4.15.0.tar.gz", hash = "sha256:cc", size = 100 }
wheels = [
    { url = "https://files.pythonhosted.org/x/typing_extensions-4.15.0-py3-none-any.whl", hash = "sha256:dd", size = 44000 },
]

[[package]]
name = "triton"
version = "3.3.1"
source = { registry = "https://pypi.org/simple" }
wheels = [
    { url = "https://files.pythonhosted.org/x/triton-3.3.1-cp312-cp312-manylinux_2_27_x86_64.whl", hash = "sha256:ee", size = 9000 },
]

[[package]]
name = "so-sdist"
version = "1.0"
source = { registry = "https://pypi.org/simple" }
sdist = { url = "https://files.pythonhosted.org/x/so_sdist-1.0.tar.gz", hash = "sha256:ff", size = 5000 }

[[package]]
name = "stemma"
version = "1.4.1"
source = { editable = "." }
'@
    }

    It 'lê do uv.lock a wheel do Windows, o tamanho e o que é preciso' {
        $lock = Join-Path $TestDrive 'uv.lock'
        Set-Content -LiteralPath $lock -Value $script:lockText -Encoding UTF8
        $packages = @(Get-UvLockPackages -Path $lock)
        $packages.Count | Should -Be 5
        $torch = $packages | Where-Object Name -EQ 'Torch'
        $torch.Key | Should -Be 'torch|2.7.1+cu118'
        $torch.Wheel | Should -Be 'torch-2.7.1+cu118-cp312-cp312-win_amd64.whl'
        $torch.Size | Should -BeNullOrEmpty
        ($packages | Where-Object Name -EQ 'typing-extensions').Size | Should -Be 44000
        ($packages | Where-Object Name -EQ 'so-sdist').Needed | Should -BeTrue
        ($packages | Where-Object Name -EQ 'so-sdist').Size | Should -Be 5000
        # Só de Linux e o próprio projeto: fora.
        ($packages | Where-Object Name -EQ 'triton').Needed | Should -BeFalse
        ($packages | Where-Object Name -EQ 'stemma').Needed | Should -BeFalse
    }

    It 'semeia só os archives do lock (mais as pastas pequenas)' {
        $cache = Join-Path $TestDrive 'cache-plano'
        New-FakeCache $cache @{ 'idTorch' = @('a.py'); 'idOutroTorch' = @('b.py'); 'idOutroProjeto' = @('c.py') } @{
            'torch\2.7.1+cu118-cp312-cp312-win_amd64' = 'idTorch'
            'torch\2.6.0-cp312-cp312-win_amd64'       = 'idOutroTorch'
            'requests\2.32.0-py3-none-any'            = 'idOutroProjeto'
        }
        $lock = Join-Path $TestDrive 'uv-plano.lock'
        Set-Content -LiteralPath $lock -Value $script:lockText -Encoding UTF8
        $plan = Get-UvCacheSeedPlan -Source $cache -LockPath $lock
        $plan.Selective | Should -BeTrue
        $plan.Archives | Should -Be 1
        $plan.Roots | Should -Contain 'archive-v0/idTorch'
        $plan.Roots | Should -Contain 'wheels-v6'
        $plan.Roots | Should -Contain 'simple-v24'
        $plan.Roots | Should -Not -Contain 'archive-v0'
    }

    It 'semeia também o build backend do projeto, que não está no lock (qualquer versão)' {
        $dir = Join-Path $TestDrive 'projeto-build'
        $cache = Join-Path $TestDrive 'cache-build'
        New-FakeCache $cache @{ 'idHatch' = @('h.py'); 'idPluggy' = @('p.py'); 'idTomlkit' = @('t.py'); 'idOutro' = @('o.py') } @{
            'hatchling\1.32.4-py3-none-any' = 'idHatch'
            'pluggy\1.6.0-py3-none-any'     = 'idPluggy'
            'tomlkit\0.15.1-py3-none-any'   = 'idTomlkit'
            'requests\2.32.0-py3-none-any'  = 'idOutro'
        }
        # Dependências do hatchling vêm do METADATA da wheel no cache (as de extras não).
        foreach ($meta in @(
                @('idHatch', 'hatchling-1.32.4', @('Requires-Dist: pluggy>=1.0.0', 'Requires-Dist: Tomlkit>=0.11.1', 'Requires-Dist: requests; extra == "web"')),
                @('idPluggy', 'pluggy-1.6.0', @()))) {
            $info = Join-Path $cache "archive-v0\$($meta[0])\$($meta[1]).dist-info"
            New-Item -ItemType Directory -Force -Path $info | Out-Null
            Set-Content -LiteralPath (Join-Path $info 'METADATA') -Value (@('Metadata-Version: 2.4', "Name: $($meta[1])") + $meta[2] + @('', 'Requires-Dist: requests'))
        }
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'uv.lock') -Value $script:lockText -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $dir 'pyproject.toml') -Encoding UTF8 -Value @(
            '[build-system]', 'requires = ["hatchling>=1.25"]', 'build-backend = "hatchling.build"'
        )
        $names = Get-BuildBackendNames -PyprojectPath (Join-Path $dir 'pyproject.toml')
        $names | Should -Contain 'hatchling'
        $names | Should -Contain 'editables'  # pedido só no build editável
        $plan = Get-UvCacheSeedPlan -Source $cache -LockPath (Join-Path $dir 'uv.lock')
        $plan.Roots | Should -Contain 'archive-v0/idHatch'
        $plan.Roots | Should -Contain 'archive-v0/idPluggy'
        $plan.Roots | Should -Contain 'archive-v0/idTomlkit'
        $plan.Roots | Should -Not -Contain 'archive-v0/idOutro'
    }

    It 'cache reconhecido, mas sem nada do Stemma: só as pastas pequenas, nunca o cache inteiro' {
        $cache = Join-Path $TestDrive 'cache-de-outros'
        New-FakeCache $cache @{ 'idOutroProjeto' = @('c.py') } @{ 'requests\2.32.0-py3-none-any' = 'idOutroProjeto' }
        $lock = Join-Path $TestDrive 'uv-outros.lock'
        Set-Content -LiteralPath $lock -Value $script:lockText -Encoding UTF8
        $plan = Get-UvCacheSeedPlan -Source $cache -LockPath $lock
        $plan.Selective | Should -BeTrue
        $plan.Roots | Should -Not -Contain 'archive-v0'
        @($plan.Roots | Where-Object { $_ -like 'archive-v0*' }).Count | Should -Be 0
    }

    It 'lê o requires só da seção [build-system]' {
        $file = Join-Path $TestDrive 'pyproject-secoes.toml'
        Set-Content -LiteralPath $file -Encoding UTF8 -Value @(
            '[build-system]', 'build-backend = "flit_core.buildapi"', '',
            '[tool.outro]', 'requires = ["nao-e-backend"]'
        )
        Get-BuildBackendNames -PyprojectPath $file | Should -BeNullOrEmpty
        Set-Content -LiteralPath $file -Encoding UTF8 -Value @('[project]', 'name = "x"', '', '[build-system]', 'requires = ["Flit_Core>=3"]')
        Get-BuildBackendNames -PyprojectPath $file | Should -Be @('flit-core')
    }

    It 'na atualização, a estimativa usa só o cache da instalação (o do usuário não é semeado)' {
        $root = Join-Path $TestDrive 'raiz-caches'
        $user = Join-Path $TestDrive 'cache-do-usuario'
        New-Item -ItemType Directory -Force -Path $user | Out-Null
        Mock -ModuleName StemmaDeploy Test-SameVolume { $true }
        Get-StemmaCacheDirs -Root $root -UserCache $user | Should -Be @($user)
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'cache\uv\wheels-v6') | Out-Null
        Get-StemmaCacheDirs -Root $root -UserCache $user | Should -Be @((Join-Path $root 'cache\uv'))
    }

    It 'sem ponteiros (formato do cache mudou) semeia o archive inteiro' {
        $cache = Join-Path $TestDrive 'cache-sem-ponteiro'
        New-FakeCache $cache @{ 'id1' = @('a.py') } @{}
        $lock = Join-Path $TestDrive 'uv-sem.lock'
        Set-Content -LiteralPath $lock -Value $script:lockText -Encoding UTF8
        $plan = Get-UvCacheSeedPlan -Source $cache -LockPath $lock
        $plan.Selective | Should -BeFalse
        $plan.Roots | Should -Contain 'archive-v0'
    }

    It 'liga só o que o lock usa, e o arquivo ligado ganha uma ACL protegida (Usuários só leitura)' -Skip:(-not $OnWindows) {
        $src = Join-Path $TestDrive 'cache-acl'
        $dst = Join-Path $TestDrive 'cache-acl-destino'
        New-FakeCache $src @{ 'idTorch' = @('torch.py'); 'idOutroProjeto' = @('outro.py') } @{
            'torch\2.7.1+cu118-cp312-cp312-win_amd64' = 'idTorch'
            'requests\2.32.0-py3-none-any'            = 'idOutroProjeto'
        }
        $file = Join-Path $src 'archive-v0\idTorch\torch.py'
        # Entrada explícita no arquivo de origem (como as do perfil do usuário).
        $acl = Get-Acl -LiteralPath $file
        $everyone = [Security.Principal.SecurityIdentifier]::new('S-1-1-0')
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($everyone, 'Modify', 'Allow'))
        Set-Acl -LiteralPath $file -AclObject $acl
        (Get-Acl -LiteralPath $file).Access.Where({ -not $_.IsInherited }).Count | Should -BeGreaterThan 0
        $lock = Join-Path $TestDrive 'uv-acl.lock'
        Set-Content -LiteralPath $lock -Value $script:lockText -Encoding UTF8
        Mock -ModuleName StemmaDeploy Write-Step {}

        $summary = Copy-UvCacheSeed -Source $src -Dest $dst -LockPath $lock 6>$null
        $summary.Selective | Should -BeTrue
        $summary.Failed | Should -Be 0
        Test-Path -LiteralPath (Join-Path $dst 'archive-v0\idTorch\torch.py') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $dst 'archive-v0\idOutroProjeto') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $dst 'wheels-v6\index\abc\torch\2.7.1+cu118-cp312-cp312-win_amd64') | Should -BeTrue
        # Mesmo arquivo dos dois lados: sem herança (uma propagação pelo perfil do usuário não o
        # abre de novo) e só SYSTEM, Administradores e Usuários (leitura).
        foreach ($path in (Join-Path $dst 'archive-v0\idTorch\torch.py'), $file) {
            $acl = Get-Acl -LiteralPath $path
            $acl.AreAccessRulesProtected | Should -BeTrue
            $rules = @($acl.Access | ForEach-Object {
                    [pscustomobject]@{ Sid = $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value; Rights = $_.FileSystemRights.ToString() }
                })
            @($rules | ForEach-Object Sid | Sort-Object) | Should -Be @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-32-545')
            ($rules | Where-Object Sid -EQ 'S-1-5-32-545').Rights | Should -Not -Match 'Write|Modify|FullControl'
        }
    }

    It 'estima o download pelo que falta nos caches (torch sem tamanho no lock = ~2,9 GB)' {
        $lock = Join-Path $TestDrive 'uv-estimativa.lock'
        Set-Content -LiteralPath $lock -Value $script:lockText -Encoding UTF8
        $root = Join-Path $TestDrive 'raiz-estimativa'
        $vazio = Get-StemmaSpaceEstimate -Root $root -LockPath $lock
        $vazio.Needed | Should -Be 3
        $vazio.Missing | Should -Be 3
        $vazio.DownloadBytes | Should -Be ([long]2.9GB + 44000 + 5000)
        $vazio.NeedRootBytes | Should -Be (2 * $vazio.DownloadBytes + 600MB)

        $cache = Join-Path $TestDrive 'cache-estimativa'
        New-FakeCache $cache @{ 'idTorch' = @('a.py') } @{ 'torch\2.7.1+cu118-cp312-cp312-win_amd64' = 'idTorch' }
        $comCache = Get-StemmaSpaceEstimate -Root $root -LockPath $lock -CacheDirs @($cache)
        $comCache.Missing | Should -Be 2
        $comCache.DownloadBytes | Should -Be (44000 + 5000)
    }
}

Describe 'Progresso por etapas' {
    BeforeEach { Set-StemmaProgressProtocol $true }
    AfterEach { Set-StemmaProgressProtocol $false }

    It 'calcula o avanço pelo peso das etapas' {
        $stages = @([pscustomobject]@{ Weight = 1 }, [pscustomobject]@{ Weight = 3 })
        Get-StemmaProgressValue -Stages $stages -Index 0 | Should -Be 0
        Get-StemmaProgressValue -Stages $stages -Index 1 | Should -Be 250
        Get-StemmaProgressValue -Stages $stages -Index 1 -Fraction 0.5 | Should -Be 625
        Get-StemmaProgressValue -Stages $stages -Index 1 -Fraction 2 | Should -Be 1000
    }

    It 'numera as etapas e a barra só anda para a frente' {
        $output = & {
            Start-StemmaProgress -Stages @(
                @{ Id = 'a'; Text = 'Primeira'; Weight = 1 }
                @{ Id = 'b'; Text = 'Segunda'; Weight = 1 }
            )
            Enter-StemmaStage 'a'
            Set-StemmaStageProgress 0.5
            Set-StemmaStageProgress 0.4  # não volta
            Enter-StemmaStage 'b'
            Set-StemmaStageProgress 0.5
            Complete-StemmaProgress
        } 6>&1 | ForEach-Object { "$_" }
        $output | Should -Contain '##STAGE Etapa 1 de 2: Primeira'
        $output | Should -Contain '##STAGE Etapa 2 de 2: Segunda'
        $values = @($output | Where-Object { $_ -like '##PROGRESS *' } | ForEach-Object { [int]($_ -split ' ')[1] })
        $values | Should -Be @(0, 250, 500, 750, 1000)
    }

    It 'repesar uma etapa mantém o que a barra já mostra e ela continua andando' {
        $output = & {
            Start-StemmaProgress -Stages @(
                @{ Id = 'a'; Text = 'Antes'; Weight = 3 }
                @{ Id = 'download'; Text = 'Download'; Weight = 1 }
                @{ Id = 'c'; Text = 'Depois'; Weight = 1 }
            )
            Enter-StemmaStage 'a'
            Set-StemmaStageProgress 1   # 600
            # Vai baixar muito: o download passa a pesar 30.
            Set-StemmaStageWeight -Id 'download' -Weight 30
            Enter-StemmaStage 'download'  # continua 600
            Set-StemmaStageProgress 0.1   # tem de andar logo, sem esperar o valor antigo
        } 6>&1 | ForEach-Object { "$_" }
        $values = @($output | Where-Object { $_ -like '##PROGRESS *' } | ForEach-Object { [int]($_ -split ' ')[1] })
        $values[1] | Should -Be 600
        $values[-1] | Should -BeGreaterThan 600
        $values[-1] | Should -BeLessThan 700
    }

    It 'sem o protocolo não escreve ##PROGRESS e a etapa vira um Write-Step' {
        Set-StemmaProgressProtocol $false
        $output = & {
            Start-StemmaProgress -Stages @(@{ Id = 'a'; Text = 'Única'; Weight = 1 })
            Enter-StemmaStage 'a'
            Complete-StemmaProgress
        } 6>&1 | ForEach-Object { "$_" }
        $output | Should -Be @('==> Etapa 1 de 1: Única')
    }

    It 'acompanha o download do uv pelas linhas Downloading/Downloaded' {
        $tracker = New-UvDownloadTracker
        Update-UvDownloadTracker -Tracker $tracker -Line 'Resolved 80 packages in 3ms' | Should -BeFalse
        Update-UvDownloadTracker -Tracker $tracker -Line 'Downloading torch (3.0GiB)' | Should -BeTrue
        Update-UvDownloadTracker -Tracker $tracker -Line 'Downloading numpy (1.0GiB)' | Should -BeTrue
        Update-UvDownloadTracker -Tracker $tracker -Line ' Downloaded numpy' | Should -BeTrue
        $status = Get-UvDownloadStatus -Tracker $tracker
        $status.Total | Should -Be 4GB
        $status.Fraction | Should -Be 0.25
        Format-StemmaSize $status.Done | Should -Be '1,0 GB'
        Format-StemmaSize 340MB | Should -Be '340 MB'
        ConvertFrom-ByteSize '915.5KiB' | Should -Be ([long](915.5 * 1KB))
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

Describe 'Atualização pelo app: tarefas agendadas' {
    It 'nomes da instalação real e de um ensaio paralelo' {
        $real = Get-StemmaTaskNames -ServiceId 'stemma'
        $real.UpdateFull | Should -Be '\Stemma\Atualizar'
        $real.Tray | Should -Be 'Bandeja'
        $ensaio = Get-StemmaTaskNames -ServiceId 'stemma-ensaio'
        $ensaio.UpdateFull | Should -Be '\Stemma\Atualizar-stemma-ensaio'
        $ensaio.Tray | Should -Be 'Bandeja-stemma-ensaio'
    }

    It 'a tarefa roda o setup.ps1 do instalador no modo AppUpdate' {
        $arguments = Get-AppUpdateArguments -EngineDir 'C:\stemma\setup\engine' -Root 'C:\stemma' -ServiceId 'stemma'
        $arguments | Should -BeLike '*-File "C:\stemma\setup\engine\setup.ps1" -Mode AppUpdate -Root "C:\stemma" -ServiceId "stemma"'
        $arguments | Should -BeLike '-NoProfile -NonInteractive -ExecutionPolicy Bypass *'
    }

    It 'registra as duas tarefas e grava o UPDATE_TASK no .env' {
        $root = Join-Path $TestDrive 'tarefas'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root '.env') -Encoding UTF8 -Value @('PORT=8000')
        Mock -ModuleName StemmaDeploy Register-ScheduledTask {}
        Register-StemmaTasks -Root $root -ServiceId 'stemma' -EngineDir (Join-Path $root 'setup\engine')
        Should -Invoke -ModuleName StemmaDeploy Register-ScheduledTask -Times 1 -ParameterFilter {
            $TaskName -eq 'Atualizar' -and $TaskPath -eq '\Stemma\' -and $Principal.LogonType -eq 'ServiceAccount' -and $Principal.RunLevel -eq 'Highest'
        }
        Should -Invoke -ModuleName StemmaDeploy Register-ScheduledTask -Times 1 -ParameterFilter {
            $TaskName -eq 'Bandeja' -and $Principal.LogonType -eq 'Group' -and $Action[0].Execute -like '*\setup\Stemma.exe'
        }
        $values = Read-DotEnv -Path (Join-Path $root '.env')
        $values['UPDATE_TASK'] | Should -Be '\Stemma\Atualizar'
        $values['PORT'] | Should -Be '8000'
    }
}

Describe 'ConvertFrom-InstallerResult' {
    It 'sucesso com a versão' {
        $result = ConvertFrom-InstallerResult "ok|v1.5.1`r`n"
        $result.Ok | Should -BeTrue
        $result.Text | Should -Be 'v1.5.1'
    }

    It 'erro com o motivo (que pode ter |)' {
        $result = ConvertFrom-InstallerResult 'erro|A atualização para v1.5.1 falhou (a|b). A v1.5.0 continua no ar.'
        $result.Ok | Should -BeFalse
        $result.Text | Should -Be 'A atualização para v1.5.1 falhou (a|b). A v1.5.0 continua no ar.'
    }

    It 'vazio ou estranho' {
        (ConvertFrom-InstallerResult '').Ok | Should -BeFalse
        (ConvertFrom-InstallerResult '').Text | Should -BeNullOrEmpty
        (ConvertFrom-InstallerResult 'erro|').Text | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-StemmaAppUpdate' {
    BeforeEach {
        $script:AppRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:AppRoot | Out-Null
        $script:FakeExe = Join-Path $TestDrive 'Stemma-Setup-v9.9.9.exe'
        Mock -ModuleName StemmaDeploy Get-StemmaUpdateTarget { '9.9.9' }
        Mock -ModuleName StemmaDeploy Get-StemmaInstaller { $script:FakeExe }
        Mock -ModuleName StemmaDeploy Get-CurrentRelease { 'C:\stemma\releases\v9.9.9' }
        Mock -ModuleName StemmaDeploy Set-StemmaToolEnv {}
        Mock -ModuleName StemmaDeploy Import-DotEnv {}
        Mock -ModuleName StemmaDeploy Invoke-StemmaCli {}
        Mock -ModuleName StemmaDeploy Start-ScheduledTask {}
        Mock -ModuleName StemmaDeploy Write-Step {}
    }

    It 'sucesso: grava succeeded com a release no ar e reabre a bandeja' {
        Mock -ModuleName StemmaDeploy Invoke-StemmaInstaller {
            [IO.File]::WriteAllText((Join-Path $script:AppRoot 'logs\app-update-result.txt'), "ok|v9.9.9`r`n")
            0
        }
        $outcome = Invoke-StemmaAppUpdate -Root $script:AppRoot -ServiceId 'stemma'
        $outcome.State | Should -Be 'succeeded'
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaInstaller -Times 1 -ParameterFilter {
            ($Arguments -contains '/VERYSILENT') -and ($Arguments -contains '/NOTRAY') -and
            ($Arguments -contains '/SERVICEID=stemma') -and -not ($Arguments -contains '/SIMULATEFAILURE')
        }
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1 -ParameterFilter {
            $ReleaseDir -eq 'C:\stemma\releases\v9.9.9' -and ($Arguments -join ' ') -eq 'update-result --state succeeded'
        }
        Should -Invoke -ModuleName StemmaDeploy Start-ScheduledTask -Times 1 -ParameterFilter { $TaskName -eq 'Bandeja' }
        # Exatamente a versão que o app gravou, e não a "latest" do GitHub.
        Should -Invoke -ModuleName StemmaDeploy Get-StemmaInstaller -Times 1 -ParameterFilter { $Version -eq '9.9.9' }
    }

    It 'sem versão escolhida pelo app: não baixa nada e grava a falha' {
        Mock -ModuleName StemmaDeploy Get-StemmaUpdateTarget { throw 'o app não registrou qual versão instalar' }
        Mock -ModuleName StemmaDeploy Invoke-StemmaInstaller { 0 }
        $outcome = Invoke-StemmaAppUpdate -Root $script:AppRoot -ServiceId 'stemma'
        $outcome.Message | Should -Be 'A atualização não começou: o app não registrou qual versão instalar.'
        Should -Invoke -ModuleName StemmaDeploy Get-StemmaInstaller -Times 0
    }

    It 'aspas duplas do motivo viram simples (o 5.1 quebraria o argumento)' {
        Mock -ModuleName StemmaDeploy Invoke-StemmaInstaller {
            [IO.File]::WriteAllText((Join-Path $script:AppRoot 'logs\app-update-result.txt'), 'erro|Falha ao copiar "C:\x y".')
            1
        }
        Invoke-StemmaAppUpdate -Root $script:AppRoot -ServiceId 'stemma' | Out-Null
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1 -ParameterFilter {
            $Arguments[-1] -eq "Falha ao copiar 'C:\x y'."
        }
    }

    It 'falha do instalador: grava o motivo que ele deu' {
        Mock -ModuleName StemmaDeploy Invoke-StemmaInstaller {
            [IO.File]::WriteAllText((Join-Path $script:AppRoot 'logs\app-update-result.txt'), 'erro|A v9.9.9 falhou. A v1.0.0 continua no ar.')
            1
        }
        $outcome = Invoke-StemmaAppUpdate -Root $script:AppRoot -ServiceId 'stemma' -SimulateFailure
        $outcome.State | Should -Be 'failed'
        $outcome.Message | Should -Be 'A v9.9.9 falhou. A v1.0.0 continua no ar.'
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaInstaller -Times 1 -ParameterFilter { $Arguments -contains '/SIMULATEFAILURE' }
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1 -ParameterFilter {
            ($Arguments -join '|') -eq 'update-result|--state|failed|--message|A v9.9.9 falhou. A v1.0.0 continua no ar.'
        }
    }

    It 'instalador que sai sem arquivo de resultado: código e log na mensagem' {
        Mock -ModuleName StemmaDeploy Invoke-StemmaInstaller { 2 }
        $outcome = Invoke-StemmaAppUpdate -Root $script:AppRoot -ServiceId 'stemma'
        $outcome.State | Should -Be 'failed'
        $outcome.Message | Should -BeLike 'O instalador da v9.9.9 parou com código 2. Veja *update-v9.9.9.log.'
    }

    It 'resultado velho de outra atualização não conta' {
        New-Item -ItemType Directory -Force -Path (Join-Path $script:AppRoot 'logs') | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:AppRoot 'logs\app-update-result.txt'), 'ok|v9.9.8')
        Mock -ModuleName StemmaDeploy Invoke-StemmaInstaller { 0 }
        (Invoke-StemmaAppUpdate -Root $script:AppRoot -ServiceId 'stemma').State | Should -Be 'failed'
    }

    It 'download ou SHA256 errado: não roda o instalador e grava a falha' {
        Mock -ModuleName StemmaDeploy Get-StemmaInstaller { throw 'SHA256 não confere.' }
        Mock -ModuleName StemmaDeploy Invoke-StemmaInstaller { 0 }
        $outcome = Invoke-StemmaAppUpdate -Root $script:AppRoot -ServiceId 'stemma'
        $outcome.State | Should -Be 'failed'
        $outcome.Message | Should -Be 'A atualização não começou: SHA256 não confere.'
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaInstaller -Times 0
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1
    }

    It 'sem conseguir gravar no banco, não lança' {
        Mock -ModuleName StemmaDeploy Invoke-StemmaInstaller { 0 }
        Mock -ModuleName StemmaDeploy Get-CurrentRelease { $null }
        { Invoke-StemmaAppUpdate -Root $script:AppRoot -ServiceId 'stemma' -WarningAction SilentlyContinue } | Should -Not -Throw
    }
}

Describe 'Get-ReleaseAssets' {
    BeforeAll {
        $script:Release = [pscustomobject]@{
            tag_name = 'v1.5.1'
            assets   = @(
                [pscustomobject]@{ name = 'stemma-v1.5.1.zip'; browser_download_url = 'https://x/zip' }
                [pscustomobject]@{ name = 'stemma-v1.5.1.zip.sha256'; browser_download_url = 'https://x/zip.sha256' }
                [pscustomobject]@{ name = 'Stemma-Setup-v1.5.1.exe'; browser_download_url = 'https://x/exe' }
                [pscustomobject]@{ name = 'Stemma-Setup-v1.5.1.exe.sha256'; browser_download_url = 'https://x/exe.sha256' }
            )
        }
    }

    It 'instalador de uma tag escolhida (o que o app mostrou)' {
        Mock -ModuleName StemmaDeploy Invoke-RestMethod { $script:Release }
        $asset = Get-ReleaseAssets -Version '1.5.1' -Kind 'installer'
        $asset.Tag | Should -Be 'v1.5.1'
        $asset.Url | Should -Be 'https://x/exe'
        $asset.ShaUrl | Should -Be 'https://x/exe.sha256'
        Should -Invoke -ModuleName StemmaDeploy Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -like '*/releases/tags/v1.5.1' }
    }

    It 'zip da última release (padrão)' {
        Mock -ModuleName StemmaDeploy Invoke-RestMethod { $script:Release }
        (Get-ReleaseAssets).ZipUrl | Should -Be 'https://x/zip'
        Should -Invoke -ModuleName StemmaDeploy Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -like '*/releases/latest' }
    }

    It 'release ainda sem o instalador' {
        Mock -ModuleName StemmaDeploy Invoke-RestMethod {
            [pscustomobject]@{ tag_name = 'v1.6.0'; assets = @([pscustomobject]@{ name = 'stemma-v1.6.0.zip' }) }
        }
        { Get-ReleaseAssets -Version 'v1.6.0' -Kind 'installer' } | Should -Throw '*Stemma-Setup-v1.6.0.exe*'
    }
}

Describe 'Optimize-StemmaUvCache' {
    BeforeEach {
        $script:PruneRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $cache = Join-Path $script:PruneRoot 'cache\uv'
        foreach ($dir in "$cache\archive-v0\usado", "$cache\archive-v0\sobra", "$script:PruneRoot\releases\v1.5.0\backend") {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
        Set-Content -LiteralPath "$cache\archive-v0\usado\a.dll" -Value 'a'
        Set-Content -LiteralPath "$cache\archive-v0\sobra\b.dll" -Value 'b'
        Set-Content -LiteralPath "$script:PruneRoot\releases\v1.5.0\backend\uv.lock" -Value 'version = 1'
        Mock -ModuleName StemmaDeploy Write-Step {}
    }

    It 'troca o cache por um só com o que o uv.lock usa e apaga o antigo' {
        Mock -ModuleName StemmaDeploy Get-UvCacheSeedPlan { [pscustomobject]@{ Selective = $true; Roots = @('archive-v0/usado'); Archives = 1 } }
        Mock -ModuleName StemmaDeploy Copy-UvCacheSeed {
            New-Item -ItemType Directory -Force -Path "$Dest\archive-v0\usado" | Out-Null
            Copy-Item -LiteralPath "$Source\archive-v0\usado\a.dll" -Destination "$Dest\archive-v0\usado\a.dll"
        }
        $result = Optimize-StemmaUvCache -Root $script:PruneRoot
        $result.Before | Should -Be 2
        $result.After | Should -Be 1
        Test-Path "$script:PruneRoot\cache\uv\archive-v0\usado\a.dll" | Should -BeTrue
        Test-Path "$script:PruneRoot\cache\uv\archive-v0\sobra" | Should -BeFalse
        Test-Path "$script:PruneRoot\cache\uv.antigo" | Should -BeFalse
        Test-Path "$script:PruneRoot\cache\uv.novo" | Should -BeFalse
        Should -Invoke -ModuleName StemmaDeploy Copy-UvCacheSeed -Times 1 -ParameterFilter { $LockPath -like '*v1.5.0\backend\uv.lock' }
    }

    It 'formato de cache desconhecido: não mexe' {
        Mock -ModuleName StemmaDeploy Get-UvCacheSeedPlan { [pscustomobject]@{ Selective = $false; Roots = @(); Archives = 0 } }
        Mock -ModuleName StemmaDeploy Copy-UvCacheSeed {}
        Optimize-StemmaUvCache -Root $script:PruneRoot | Should -BeNullOrEmpty
        Test-Path "$script:PruneRoot\cache\uv\archive-v0\sobra\b.dll" | Should -BeTrue
        Should -Invoke -ModuleName StemmaDeploy Copy-UvCacheSeed -Times 0
    }

    It 'sem versão instalada: não mexe' {
        Remove-Item -LiteralPath "$script:PruneRoot\releases" -Recurse -Force
        Mock -ModuleName StemmaDeploy Copy-UvCacheSeed {}
        Optimize-StemmaUvCache -Root $script:PruneRoot | Should -BeNullOrEmpty
        Should -Invoke -ModuleName StemmaDeploy Copy-UvCacheSeed -Times 0
    }
}
