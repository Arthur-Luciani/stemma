# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`).
# Testes do StemmaDeploy.Config.ps1.

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
