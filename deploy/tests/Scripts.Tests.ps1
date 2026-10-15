# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`).
# Testes dos scripts do deploy/ e do installer/ (sintaxe, BOM, caracteres de controle).

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
}

Describe 'Scripts' {
    BeforeDiscovery {
        # Relativos ao deploy/: todos os .ps1/.psm1 dele e dos testes, mais o build do instalador.
        $Scripts = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..') -File -Filter '*.ps*1' | ForEach-Object Name) +
            @(Get-ChildItem -LiteralPath $PSScriptRoot -File -Filter '*.ps1' | ForEach-Object { "tests\$($_.Name)" }) +
            '..\installer\build.ps1'
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

    It 'o StemmaDeploy.psm1 carrega todas as StemmaDeploy.*.ps1 (o instalador e o pacote levam todas)' {
        $deploy = Join-Path $PSScriptRoot '..'
        $line = @(Get-Content -LiteralPath (Join-Path $deploy 'StemmaDeploy.psm1') -Encoding UTF8 | Where-Object { $_ -match '^foreach \(\$part in ' })
        $line.Count | Should -Be 1
        $loaded = @([regex]::Matches($line[0], "'(\w+)'") | ForEach-Object { $_.Groups[1].Value })
        $parts = @(Get-ChildItem -LiteralPath $deploy -File -Filter 'StemmaDeploy.*.ps1' | ForEach-Object { $_.BaseName -replace '^StemmaDeploy\.', '' })
        $parts.Count | Should -BeGreaterThan 5
        ($loaded | Sort-Object) | Should -Be ($parts | Sort-Object)
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
