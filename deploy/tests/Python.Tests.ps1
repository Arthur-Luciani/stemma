# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`).
# Testes do StemmaDeploy.Python.ps1.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
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
