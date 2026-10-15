# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`).
# Testes do StemmaDeploy.Releases.ps1.

BeforeDiscovery {
    # Junction só existe no Windows; no CI (Linux) o teste fica pulado.
    $OnWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
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
