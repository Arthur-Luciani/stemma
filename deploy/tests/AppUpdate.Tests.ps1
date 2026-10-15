# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`).
# Testes do StemmaDeploy.AppUpdate.ps1.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
}

Describe 'Atualização pelo app: tarefas agendadas' {
    It 'nomes da instalação real e de um ensaio paralelo' {
        $real = Get-StemmaTaskNames -ServiceId 'stemma'
        $real.UpdateFull | Should -Be '\Stemma\Atualizar'
        $real.Tray | Should -Be 'Bandeja'
        $ensaio = Get-StemmaTaskNames -ServiceId 'stemma-ensaio'
        $ensaio.UpdateFull | Should -Be '\Stemma\Atualizar-stemma-ensaio'
        $ensaio.Tray | Should -Be 'Bandeja-stemma-ensaio'
        $real.YtDlpFull | Should -Be '\Stemma\AtualizarYtDlp'
        $ensaio.YtDlpFull | Should -Be '\Stemma\AtualizarYtDlp-stemma-ensaio'
    }

    It 'a tarefa roda o setup.ps1 do instalador no modo AppUpdate' {
        $arguments = Get-AppUpdateArguments -EngineDir 'C:\stemma\setup\engine' -Root 'C:\stemma' -ServiceId 'stemma'
        $arguments | Should -BeLike '*-File "C:\stemma\setup\engine\setup.ps1" -Mode AppUpdate -Root "C:\stemma" -ServiceId "stemma"'
        $arguments | Should -BeLike '-NoProfile -NonInteractive -ExecutionPolicy Bypass *'
        Get-AppUpdateArguments -EngineDir 'C:\e' -Root 'C:\stemma' -ServiceId 'stemma' -Mode YtDlpUpdate |
            Should -BeLike '*setup.ps1" -Mode YtDlpUpdate -Root *'
    }

    It 'a tarefa do yt-dlp é diária, de madrugada, como SYSTEM e roda assim que o PC ligar' {
        $root = Join-Path $TestDrive 'tarefas-ytdlp'
        New-Item -ItemType Directory -Force -Path $root | Out-Null
        Set-Content -LiteralPath (Join-Path $root '.env') -Encoding UTF8 -Value @('PORT=8000')
        Mock -ModuleName StemmaDeploy Register-ScheduledTask {}
        Register-StemmaTasks -Root $root -ServiceId 'stemma' -EngineDir (Join-Path $root 'setup\engine')
        Should -Invoke -ModuleName StemmaDeploy Register-ScheduledTask -Times 1 -ParameterFilter {
            $TaskName -eq 'AtualizarYtDlp' -and $Principal.LogonType -eq 'ServiceAccount' -and
            $Action[0].Arguments -like '*-Mode YtDlpUpdate *' -and
            $Trigger[0].DaysInterval -eq 1 -and ([datetime]$Trigger[0].StartBoundary).Hour -eq 5 -and
            $Settings.StartWhenAvailable -and $Settings.ExecutionTimeLimit -eq 'PT20M'
        }
        (Read-DotEnv -Path (Join-Path $root '.env'))['YTDLP_UPDATE_TASK'] | Should -Be '\Stemma\AtualizarYtDlp'
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

    It 'desinstalar remove as três tarefas' {
        Mock -ModuleName StemmaDeploy Get-ScheduledTask { [pscustomobject]@{ TaskName = $TaskName } }
        Mock -ModuleName StemmaDeploy Unregister-ScheduledTask {}
        Unregister-StemmaTasks -ServiceId 'stemma'
        foreach ($name in 'Atualizar', 'AtualizarYtDlp', 'Bandeja') {
            Should -Invoke -ModuleName StemmaDeploy Unregister-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskName -eq $name }
        }
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
