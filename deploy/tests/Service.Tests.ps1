# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`). Testes de StemmaDeploy.Service.ps1.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
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
