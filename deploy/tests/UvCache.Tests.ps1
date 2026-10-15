# Pester 5: Invoke-Pester deploy/tests (no CI roda no Windows PowerShell 5.1, job `installer`). Testes de StemmaDeploy.UvCache.ps1.

BeforeDiscovery {
    # Junction só existe no Windows; no CI (Linux) o teste fica pulado.
    $OnWindows = [Environment]::OSVersion.Platform -eq 'Win32NT'
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\StemmaDeploy.psm1') -Force
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
