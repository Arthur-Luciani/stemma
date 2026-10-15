# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`).
# Testes do StemmaDeploy.Core.ps1.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
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
