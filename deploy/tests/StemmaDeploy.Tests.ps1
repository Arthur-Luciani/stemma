# Pester 5: Invoke-Pester deploy/tests (no CI roda no pwsh do Linux).

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
    It '<_> não tem erro de sintaxe' -ForEach @('install.ps1', 'update.ps1', 'start.ps1', 'StemmaDeploy.psm1') {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot "..\$_"), [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It '<_> tem BOM (o Windows PowerShell 5.1 lê sem BOM como ANSI)' -ForEach @('install.ps1', 'update.ps1', 'start.ps1', 'StemmaDeploy.psm1') {
        $bytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot "..\$_"))
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
    }
}
