# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`). Testes de StemmaDeploy.YtDlp.ps1.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
}

Describe 'yt-dlp: versões' {
    It 'compara sem ligar para os zeros à esquerda do PyPI' {
        (ConvertTo-YtDlpVersion '2025.07.06') -eq (ConvertTo-YtDlpVersion '2025.7.6') | Should -BeTrue
        (ConvertTo-YtDlpVersion '2025.10.22.1') -gt (ConvertTo-YtDlpVersion '2025.10.22') | Should -BeTrue
        (ConvertTo-YtDlpVersion '2025.10.22') -gt (ConvertTo-YtDlpVersion '2025.9.30') | Should -BeTrue
    }

    It 'texto estranho vira $null' {
        ConvertTo-YtDlpVersion 'nightly' | Should -BeNullOrEmpty
        ConvertTo-YtDlpVersion '' | Should -BeNullOrEmpty
        ConvertTo-YtDlpVersion '2025.10' | Should -BeNullOrEmpty
    }

    It 'lê o plano do CLI ytdlp-begin no meio do log' {
        $plan = ConvertFrom-YtDlpBegin @('2026-10-14 INFO algo', 'run|2025.07.06|2025.10.22')
        $plan.Run | Should -BeTrue
        $plan.From | Should -Be '2025.07.06'
        $plan.Target | Should -Be '2025.10.22'
        $skip = ConvertFrom-YtDlpBegin @('skip|há 1 job(s) na fila ou rodando')
        $skip.Run | Should -BeFalse
        $skip.Reason | Should -Be 'há 1 job(s) na fila ou rodando'
        { ConvertFrom-YtDlpBegin @('nada') } | Should -Throw '*não disse o que fazer*'
    }

    It 'o /health só vale com o yt-dlp esperado' {
        Mock -ModuleName StemmaDeploy Invoke-RestMethod { [pscustomobject]@{ version = '1.3.0'; status = 'ok'; gpu = 'ok'; ytdlp = '2025.10.22' } }
        Mock -ModuleName StemmaDeploy Start-Sleep {}
        Wait-StemmaHealth -Port 8000 -ExpectedVersion 'v1.3.0' -ExpectedYtDlp '2025.10.22' -TimeoutSec 1 -IntervalSec 0 6>$null | Should -BeTrue
        Wait-StemmaHealth -Port 8000 -ExpectedVersion 'v1.3.0' -ExpectedYtDlp '2025.11.1' -TimeoutSec 0 -WarningAction SilentlyContinue | Should -BeFalse
    }
}

Describe 'Sync-StemmaYtDlpFloor' {
    BeforeEach {
        Mock -ModuleName StemmaDeploy Install-ReleaseYtDlp {}
        Mock -ModuleName StemmaDeploy Write-Step {}
    }

    It 'a anterior mais nova que o uv.lock: instala a dela no venv novo' {
        Mock -ModuleName StemmaDeploy Get-ReleaseYtDlpVersion { if ($ReleaseDir -eq 'C:\r\v1') { '2025.10.22' } else { '2025.07.06' } }
        Sync-StemmaYtDlpFloor -ReleaseDir 'C:\r\v2' -PreviousDir 'C:\r\v1' | Should -Be '2025.10.22'
        Should -Invoke -ModuleName StemmaDeploy Install-ReleaseYtDlp -Times 1 -Exactly -ParameterFilter {
            $ReleaseDir -eq 'C:\r\v2' -and $Version -eq '2025.10.22'
        }
    }

    It 'o uv.lock igual ou mais novo: não mexe' {
        Mock -ModuleName StemmaDeploy Get-ReleaseYtDlpVersion { if ($ReleaseDir -eq 'C:\r\v1') { '2025.7.6' } else { '2025.07.06' } }
        Sync-StemmaYtDlpFloor -ReleaseDir 'C:\r\v2' -PreviousDir 'C:\r\v1' | Should -BeNullOrEmpty
        Mock -ModuleName StemmaDeploy Get-ReleaseYtDlpVersion { if ($ReleaseDir -eq 'C:\r\v1') { '2025.07.06' } else { '2025.10.22' } }
        Sync-StemmaYtDlpFloor -ReleaseDir 'C:\r\v2' -PreviousDir 'C:\r\v1' | Should -BeNullOrEmpty
        Should -Invoke -ModuleName StemmaDeploy Install-ReleaseYtDlp -Times 0 -Exactly
    }

    It 'sem saber uma das versões: não mexe' {
        Mock -ModuleName StemmaDeploy Get-ReleaseYtDlpVersion { $null }
        Sync-StemmaYtDlpFloor -ReleaseDir 'C:\r\v2' -PreviousDir 'C:\r\v1' | Should -BeNullOrEmpty
        Should -Invoke -ModuleName StemmaDeploy Install-ReleaseYtDlp -Times 0 -Exactly
    }

    It 'falha ao instalar só avisa (a tarefa diária corrige)' {
        Mock -ModuleName StemmaDeploy Get-ReleaseYtDlpVersion { if ($ReleaseDir -eq 'C:\r\v1') { '2025.10.22' } else { '2025.07.06' } }
        Mock -ModuleName StemmaDeploy Install-ReleaseYtDlp { throw 'sem rede' }
        Sync-StemmaYtDlpFloor -ReleaseDir 'C:\r\v2' -PreviousDir 'C:\r\v1' -WarningVariable warned -WarningAction SilentlyContinue |
            Should -BeNullOrEmpty
        "$warned" | Should -BeLike '*sem rede*'
    }
}

Describe 'Invoke-StemmaYtDlpUpdate' {
    BeforeEach {
        $script:YtRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:YtRoot | Out-Null
        Set-Content -LiteralPath (Join-Path $script:YtRoot '.env') -Value @('PORT=8001')
        $script:YtRelease = Join-Path $script:YtRoot 'releases\v1.6.0'
        Mock -ModuleName StemmaDeploy Get-CurrentRelease { $script:YtRelease }
        Mock -ModuleName StemmaDeploy Set-StemmaToolEnv {}
        Mock -ModuleName StemmaDeploy Import-DotEnv {}
        Mock -ModuleName StemmaDeploy Write-Step {}
        Mock -ModuleName StemmaDeploy Invoke-StemmaCli {}
        $script:YtCalls = [Collections.Generic.List[string]]::new()
        Mock -ModuleName StemmaDeploy Stop-StemmaService { $script:YtCalls.Add('stop') }
        Mock -ModuleName StemmaDeploy Start-StemmaService { $script:YtCalls.Add('start') }
        Mock -ModuleName StemmaDeploy Install-ReleaseYtDlp { $script:YtCalls.Add("install:$Version") }
        Mock -ModuleName StemmaDeploy Get-StemmaYtDlpPlan {
            [pscustomobject]@{ Run = $true; From = '2025.07.06'; Target = '2025.10.22'; Reason = $null }
        }
    }

    It 'nada a fazer: não para o serviço nem grava resultado' {
        Mock -ModuleName StemmaDeploy Get-StemmaYtDlpPlan {
            [pscustomobject]@{ Run = $false; From = $null; Target = $null; Reason = 'o yt-dlp 2025.10.22 já é o mais recente' }
        }
        $outcome = Invoke-StemmaYtDlpUpdate -Root $script:YtRoot -ServiceId 'stemma'
        $outcome.State | Should -Be 'skipped'
        Should -Invoke -ModuleName StemmaDeploy Stop-StemmaService -Times 0 -Exactly
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 0 -Exactly
    }

    It 'sucesso: instala com o serviço parado, confere o /health e grava succeeded' {
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $true }
        $outcome = Invoke-StemmaYtDlpUpdate -Root $script:YtRoot -ServiceId 'stemma'
        $outcome.State | Should -Be 'succeeded'
        $script:YtCalls | Should -Be @('stop', 'install:2025.10.22', 'start')
        Should -Invoke -ModuleName StemmaDeploy Wait-StemmaHealth -Times 1 -Exactly -ParameterFilter {
            $Port -eq 8001 -and $ExpectedVersion -eq 'v1.6.0' -and $ExpectedYtDlp -eq '2025.10.22'
        }
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1 -Exactly -ParameterFilter {
            $ReleaseDir -eq $script:YtRelease -and ($Arguments -join ' ') -eq 'ytdlp-result --state succeeded'
        }
    }

    It 'o serviço não volta com o novo: reinstala o anterior e grava a falha' {
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $ExpectedYtDlp -eq '2025.07.06' }
        $outcome = Invoke-StemmaYtDlpUpdate -Root $script:YtRoot -ServiceId 'stemma' -WarningAction SilentlyContinue
        $outcome.State | Should -Be 'failed'
        $outcome.Message | Should -Be 'A atualização do yt-dlp para 2025.10.22 falhou: o Stemma não voltou com o yt-dlp 2025.10.22. O yt-dlp 2025.07.06 continua no ar.'
        $script:YtCalls | Should -Be @('stop', 'install:2025.10.22', 'start', 'stop', 'install:2025.07.06', 'start')
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1 -Exactly -ParameterFilter {
            $Arguments[0] -eq 'ytdlp-result' -and $Arguments[2] -eq 'failed' -and $Arguments[4] -like '*continua no ar.'
        }
    }

    It 'a instalação falha: o serviço sobe de novo mesmo assim' {
        Mock -ModuleName StemmaDeploy Install-ReleaseYtDlp {
            $script:YtCalls.Add("install:$Version")
            if ($Version -eq '2025.10.22') { throw "'uv pip install' falhou (código 2)." }
        }
        Mock -ModuleName StemmaDeploy Wait-StemmaHealth { $true }
        $outcome = Invoke-StemmaYtDlpUpdate -Root $script:YtRoot -ServiceId 'stemma' -WarningAction SilentlyContinue
        $outcome.State | Should -Be 'failed'
        $outcome.Message | Should -BeLike "*'uv pip install' falhou (código 2). O yt-dlp 2025.07.06 continua no ar."
        $script:YtCalls | Should -Be @('stop', 'install:2025.10.22', 'start', 'stop', 'install:2025.07.06', 'start')
    }

    It 'o CLI falha antes de decidir: grava a falha (um pedido do app não fica preso)' {
        Mock -ModuleName StemmaDeploy Get-StemmaYtDlpPlan { throw 'o CLI ytdlp-begin não disse o que fazer' }
        $outcome = Invoke-StemmaYtDlpUpdate -Root $script:YtRoot -ServiceId 'stemma'
        $outcome.State | Should -Be 'failed'
        $outcome.Message | Should -Be 'A atualização do yt-dlp não começou: o CLI ytdlp-begin não disse o que fazer.'
        Should -Invoke -ModuleName StemmaDeploy Stop-StemmaService -Times 0 -Exactly
        Should -Invoke -ModuleName StemmaDeploy Invoke-StemmaCli -Times 1 -Exactly -ParameterFilter { $Arguments[0] -eq 'ytdlp-result' }
    }
}
