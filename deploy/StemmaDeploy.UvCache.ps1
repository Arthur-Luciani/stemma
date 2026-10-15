# StemmaDeploy: cache do uv: semear por hardlink a partir do cache do usuário e estimar o espaço.
# Carregado pelo StemmaDeploy.psm1 (dot-source, escopo do módulo). Salvo com BOM (acentos).

# --- cache do uv: semear a partir do cache do usuário ------------------------------

function Find-UserUvCache {
    <#
      Cache do uv do usuário que rodou o instalador (elevado, mas no perfil dele). Chame antes
      do Set-StemmaToolEnv, que troca o UV_CACHE_DIR deste processo. $null se não houver.
    #>
    $candidates = @()
    if ($env:UV_CACHE_DIR) { $candidates += $env:UV_CACHE_DIR }
    $uv = Get-Command uv -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($uv) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $dir = & $uv.Source cache dir 2>$null; if ($LASTEXITCODE -eq 0 -and $dir) { $candidates += "$dir".Trim() } }
        catch { Write-Verbose "uv cache dir falhou: $_" }
        finally { $ErrorActionPreference = $previous }
    }
    if ($env:LOCALAPPDATA) { $candidates += Join-Path $env:LOCALAPPDATA 'uv\cache' }
    foreach ($dir in $candidates) {
        if ($dir -and (Test-Path -LiteralPath $dir -PathType Container)) { return [IO.Path]::GetFullPath($dir) }
    }
    return $null
}

function Test-SameVolume([string]$A, [string]$B) {
    return [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($A)) -eq [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($B))
}

function Initialize-HardLinkSeeder {
    if ('Stemma.UvCacheSeeder' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
namespace Stemma {
    public static class UvCacheSeeder {
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, IntPtr lpSecurityAttributes);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode)]
        static extern uint SetNamedSecurityInfoW(string pObjectName, int objectType, uint securityInfo,
            byte[] psidOwner, IntPtr psidGroup, byte[] pDacl, IntPtr pSacl);

        const int SE_FILE_OBJECT = 1;
        const uint OWNER_SECURITY_INFORMATION = 0x1;
        const uint DACL_SECURITY_INFORMATION = 0x4;
        const uint PROTECTED_DACL_SECURITY_INFORMATION = 0x80000000;
        const int FILE_ALL_ACCESS = 0x1F01FF;
        const int FILE_READ_EXECUTE = 0x1200A9;

        static byte[] Sid(string value) {
            var sid = new SecurityIdentifier(value);
            byte[] bytes = new byte[sid.BinaryLength];
            sid.GetBinaryForm(bytes, 0);
            return bytes;
        }

        // Um hardlink é o mesmo arquivo do cache do usuário, com um descritor de segurança só,
        // e herdar a ACL do destino não basta: uma propagação de herança pelo outro caminho
        // (o perfil do usuário) o abriria de novo. Grava uma ACL própria e protegida (sem
        // herança): SYSTEM e Administradores com controle total, Usuários só leitura; com
        // setOwner, Administradores como dono. Um arquivo por vez, ao ligar: nada de percorrer
        // o cache inteiro com o icacls depois.
        public static bool Protect(string path, bool setOwner) {
            var acl = new RawAcl(GenericAcl.AclRevision, 3);
            acl.InsertAce(0, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, FILE_ALL_ACCESS, new SecurityIdentifier("S-1-5-18"), false, null));
            acl.InsertAce(1, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, FILE_ALL_ACCESS, new SecurityIdentifier("S-1-5-32-544"), false, null));
            acl.InsertAce(2, new CommonAce(AceFlags.None, AceQualifier.AccessAllowed, FILE_READ_EXECUTE, new SecurityIdentifier("S-1-5-32-545"), false, null));
            byte[] dacl = new byte[acl.BinaryLength];
            acl.GetBinaryForm(dacl, 0);
            uint info = DACL_SECURITY_INFORMATION | PROTECTED_DACL_SECURITY_INFORMATION;
            byte[] owner = null;
            if (setOwner) {
                owner = Sid("S-1-5-32-544");
                info |= OWNER_SECURITY_INFORMATION;
            }
            return SetNamedSecurityInfoW(path, SE_FILE_OBJECT, info, owner, IntPtr.Zero, dacl, IntPtr.Zero) == 0;
        }

        // Recria em `dest` as subpastas `roots` de `source` (caminhos relativos) com hardlinks
        // (cópia se o link falhar), cada arquivo ligado com a ACL protegida acima. Se a ACL
        // não puder ser trocada, o link é desfeito (o uv baixa o que faltar). Arquivos que já
        // existem em `dest` ficam como estão. Pastas que são junction (formatos antigos do
        // cache) não são atravessadas: um processo elevado recusa junctions criadas pelo usuário
        // ("untrusted mount point"). Uma pasta ilegível não aborta o resto. Primeiro lista,
        // depois liga, avisando `progress(feitos, total)`.
        // Devolve {linked, copied, skipped, failed}.
        public static long[] Seed(string source, string dest, string[] roots, bool setOwner, Action<long, long> progress) {
            long[] counts = new long[4];
            source = Path.GetFullPath(source).TrimEnd('\\');
            dest = Path.GetFullPath(dest).TrimEnd('\\');
            var files = new List<string>();
            var pending = new Stack<string>();
            foreach (string root in roots) {
                string relative = root.Replace('/', '\\').Trim('\\');
                pending.Push(relative.Length == 0 ? source : source + "\\" + relative);
            }
            while (pending.Count > 0) {
                string dir = pending.Pop();
                string[] found, dirs;
                try {
                    Directory.CreateDirectory(dest + dir.Substring(source.Length));
                    found = Directory.GetFiles(dir);
                    dirs = Directory.GetDirectories(dir);
                }
                catch (Exception) { counts[3]++; continue; }
                foreach (string sub in dirs) {
                    try {
                        if ((File.GetAttributes(sub) & FileAttributes.ReparsePoint) != 0) { counts[2]++; continue; }
                    }
                    catch (Exception) { counts[3]++; continue; }
                    pending.Push(sub);
                }
                files.AddRange(found);
            }
            long total = files.Count, done = 0;
            foreach (string file in files) {
                string target = dest + file.Substring(source.Length);
                if (File.Exists(target)) {
                    // Já estava (nova tentativa, cache de uma versão anterior): protege de novo,
                    // porque a ACL pode ter sido mudada pelo outro caminho do mesmo arquivo.
                    Protect(target, setOwner);
                    counts[2]++;
                }
                else if (CreateHardLink(target, file, IntPtr.Zero)) {
                    if (Protect(target, setOwner)) { counts[0]++; }
                    else {
                        try { File.Delete(target); } catch (Exception) { }
                        counts[3]++;
                    }
                }
                else {
                    // A cópia é um arquivo novo: já nasce com a ACL herdada do destino.
                    try { File.Copy(file, target); counts[1]++; }
                    catch (Exception) { counts[3]++; }
                }
                done++;
                if (progress != null && (done % 500 == 0 || done == total)) { progress(done, total); }
            }
            return counts;
        }
    }
}
'@
}

function ConvertTo-UvPackageKey {
    <# Chave nome|versão (nome normalizado como no PEP 503). #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Version)
    return (ConvertTo-UvPackageName $Name) + '|' + $Version
}

function Get-UvLockPackages {
    <#
      Pacotes do uv.lock com o que interessa no Windows x64: a wheel (`win_amd64` ou `any`) e o
      tamanho dela, quando o índice informa (o do PyTorch não informa). Needed = há wheel para
      o Windows ou só sdist; pacotes só de Linux (nvidia-*, triton) e o próprio projeto ficam fora.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $text = [IO.File]::ReadAllText($Path)
    foreach ($block in @($text -split '(?m)^\[\[package\]\]\s*$' | Select-Object -Skip 1)) {
        if ($block -notmatch '(?m)^name = "([^"]+)"') { continue }
        $name = $Matches[1]
        if ($block -notmatch '(?m)^version = "([^"]+)"') { continue }
        $version = $Matches[1]
        $wheel = $null
        $size = $null
        $wheelLines = [regex]::Matches($block, '\{ url = "([^"]+\.whl)"[^\r\n]*')
        foreach ($match in $wheelLines) {
            $file = [Uri]::UnescapeDataString(($match.Groups[1].Value -split '/')[-1])
            if ($file -match '-(win_amd64|any)\.whl$') {
                $wheel = $file
                if ($match.Value -match 'size = (\d+)') { $size = [long]$Matches[1] }
                break
            }
        }
        $sdistOnly = $wheelLines.Count -eq 0 -and $block -match '(?m)^sdist = '
        if ($sdistOnly -and $block -match '(?m)^sdist = .*size = (\d+)') { $size = [long]$Matches[1] }
        [pscustomobject]@{
            Name    = $name
            Version = $version
            Key     = ConvertTo-UvPackageKey $name $version
            Wheel   = $wheel
            Size    = $size
            Needed  = [bool]($wheel -or $sdistOnly)
        }
    }
}

function Get-UvCachePointers {
    <#
      Ponteiros do cache do uv: `wheels-v*\…\<pacote>\<versão>-<tags>` é um arquivo texto com
      `archive-v0/<id>` (a wheel descompactada). Devolve chave nome|versão → archives que existem.
      Depende do formato interno do uv: se mudar, não acha nada, e quem chama cai no caminho
      completo (semear tudo, baixar o que faltar).
    #>
    param([Parameter(Mandatory)][string]$Cache)
    $result = @{}
    if (-not (Test-Path -LiteralPath $Cache -PathType Container)) { return $result }
    $pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    foreach ($bucket in @(Get-ChildItem -LiteralPath $Cache -Directory -Force -Filter 'wheels-v*' -ErrorAction SilentlyContinue)) {
        if (-not ($bucket.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $pending.Push($bucket) }
    }
    while ($pending.Count -gt 0) {
        $dir = $pending.Pop()
        try { $children = $dir.GetFileSystemInfos() }
        catch { continue }
        foreach ($child in $children) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($child -is [IO.DirectoryInfo]) { $pending.Push($child); continue }
            if ($child.Name -match '\.(http|lock|msgpack|rev)$' -or $child.Length -gt 256) { continue }
            try { $line = "$([IO.File]::ReadAllText($child.FullName))".Trim() }
            catch { continue }
            if ($line -notmatch '^archive-v\d+/[\w-]+$') { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $Cache $line) -PathType Container)) { continue }
            $key = ConvertTo-UvPackageKey $child.Directory.Name ($child.Name -split '-')[0]
            if (-not $result.ContainsKey($key)) { $result[$key] = [Collections.Generic.List[string]]::new() }
            $result[$key].Add($line)
        }
    }
    return $result
}

function ConvertTo-UvPackageName([string]$Name) { return $Name.ToLowerInvariant() -replace '[-_.]+', '-' }

function Get-BuildBackendNames {
    <# Nomes (normalizados) do `[build-system] requires` do pyproject (ex.: hatchling). #>
    param([Parameter(Mandatory)][string]$PyprojectPath)
    $names = @()
    if (Test-Path -LiteralPath $PyprojectPath) {
        $text = [IO.File]::ReadAllText($PyprojectPath)
        # Só dentro da seção [build-system] (até o próximo cabeçalho), nunca de outra seção.
        $section = if ($text -match '(?ms)^\[build-system\][ \t]*\r?\n(.*?)(?=^\[|\z)') { $Matches[1] } else { '' }
        if ($section -match '(?ms)^requires\s*=\s*\[([^\]]*)\]') {
            foreach ($item in [regex]::Matches($Matches[1], '"([A-Za-z0-9._-]+)')) {
                $names += ConvertTo-UvPackageName $item.Groups[1].Value
            }
        }
    }
    # O uv instala o projeto como editável, e o hatchling pede o `editables` só nessa hora
    # (get_requires_for_build_editable): não está no METADATA dele.
    if ($names -contains 'hatchling') { $names += 'editables' }
    return @($names | Sort-Object -Unique)
}

function Get-WheelRequires {
    <#
      Dependências (nomes normalizados) de uma wheel descompactada no cache, pelo `Requires-Dist`
      do METADATA. Pula as de extras; mantém as com outros marcadores (sobra pouco, nunca falta).
    #>
    param([Parameter(Mandatory)][string]$ArchiveDir)
    $metadata = @(Get-ChildItem -LiteralPath $ArchiveDir -Directory -Filter '*.dist-info' -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'METADATA' } | Where-Object { Test-Path -LiteralPath $_ })
    if ($metadata.Count -eq 0) { return @() }
    $names = foreach ($line in [IO.File]::ReadAllLines($metadata[0])) {
        if ($line -eq '') { break }  # fim do cabeçalho
        if ($line -match '^Requires-Dist:\s*([A-Za-z0-9._-]+)' -and $line -notmatch 'extra\s*==') {
            ConvertTo-UvPackageName $Matches[1]
        }
    }
    return @($names | Sort-Object -Unique)
}

function Get-BuildBackendArchives {
    <#
      Archives do build backend (que o uv usa para construir o próprio projeto no sync e que não
      está no uv.lock) e das dependências dele, lidas do METADATA no cache, em qualquer versão.
    #>
    param([Parameter(Mandatory)][string]$Cache, [Parameter(Mandatory)][hashtable]$Pointers, [string[]]$Names)
    $byName = @{}
    foreach ($key in $Pointers.Keys) {
        $name = ($key -split '\|')[0]
        if (-not $byName.ContainsKey($name)) { $byName[$name] = [Collections.Generic.List[string]]::new() }
        foreach ($archive in $Pointers[$key]) { $byName[$name].Add($archive) }
    }
    $seen = @{}
    $archives = [Collections.Generic.List[string]]::new()
    $pending = [Collections.Generic.Queue[string]]::new()
    foreach ($name in $Names) { $pending.Enqueue($name) }
    while ($pending.Count -gt 0) {
        $name = $pending.Dequeue()
        if ($seen.ContainsKey($name)) { continue }
        $seen[$name] = $true
        if (-not $byName.ContainsKey($name)) { continue }
        foreach ($archive in $byName[$name]) {
            $archives.Add($archive)
            foreach ($dep in (Get-WheelRequires -ArchiveDir (Join-Path $Cache $archive))) { $pending.Enqueue($dep) }
        }
    }
    return @($archives)
}

function Get-UvCacheSeedPlan {
    <#
      O que semear do cache do usuário: as pastas pequenas inteiras (tudo menos `archive-v*`) e,
      dos archives, só os dos pacotes do uv.lock (o cache do usuário tem os de todos os projetos
      dele: 225 mil arquivos contra ~25 mil do Stemma). Sem lock, ou num formato de cache que não
      conhece (sem ponteiros): tudo.
    #>
    param([Parameter(Mandatory)][string]$Source, [string]$LockPath)
    $roots = [Collections.Generic.List[string]]::new()
    $archiveDirs = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $Source -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($dir.Name -match '^archive-v\d+$') { $archiveDirs += $dir.Name } else { $roots.Add($dir.Name) }
    }
    $pointers = @{}
    $archives = @()
    if ($LockPath -and (Test-Path -LiteralPath $LockPath)) {
        $pointers = Get-UvCachePointers -Cache $Source
        $fromLock = @(foreach ($package in @(Get-UvLockPackages -Path $LockPath)) {
                if ($pointers.ContainsKey($package.Key)) { $pointers[$package.Key] }
            })
        # O uv constrói o próprio projeto no sync, e o build backend não está no uv.lock (sem
        # ele, o --offline falha só por causa do hatchling e das dependências dele).
        $build = @(Get-BuildBackendNames -PyprojectPath (Join-Path (Split-Path -Parent $LockPath) 'pyproject.toml'))
        $fromBuild = @(Get-BuildBackendArchives -Cache $Source -Pointers $pointers -Names $build)
        $archives = @(@($fromLock + $fromBuild) | Sort-Object -Unique)
    }
    # Seletivo sempre que o formato foi reconhecido (há ponteiros), mesmo sem nenhum pacote do
    # Stemma no cache: aí semeia só as pastas pequenas, e não o cache inteiro do usuário.
    $selective = $archives.Count -gt 0 -or $pointers.Count -gt 0
    if (-not $selective) { $archives = $archiveDirs }
    foreach ($archive in $archives) { $roots.Add($archive) }
    return [pscustomobject]@{ Roots = @($roots); Selective = $selective; Archives = @($archives).Count }
}

function Copy-UvCacheSeed {
    <#
      Semeia <Root>\cache\uv com o cache do usuário por hardlink (segundos, sem espaço extra; um
      `uv cache clean` do usuário não afeta), só com o que o -LockPath usa. Cada arquivo ligado
      ganha uma ACL própria e protegida (só administradores alteram), que vale também no cache
      do usuário, porque é o mesmo arquivo. Em outro volume não semeia:
      copiar o cache inteiro (dezenas de GB) sai mais caro que baixar o que falta. Devolve um
      resumo ou $null.
    #>
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Dest, [string]$LockPath)
    $src = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    $dst = [IO.Path]::GetFullPath($Dest).TrimEnd('\')
    if ($src -eq $dst) { return $null }
    if (-not (Test-SameVolume $src $dst)) {
        Write-Host "    Cache do uv em outro volume ($src): sem semear."
        return $null
    }
    $plan = Get-UvCacheSeedPlan -Source $src -LockPath $LockPath
    if ($plan.Selective) { Write-Step "Reaproveitando os componentes já baixados neste PC ($($plan.Archives) pacotes)" }
    else { Write-Step 'Reaproveitando os componentes já baixados neste PC (cache inteiro)' }
    Initialize-HardLinkSeeder
    $progress = [Action[long, long]] { param($done, $total) Set-StemmaStageProgress ($done / [Math]::Max(1, $total)) }
    $counts = [Stemma.UvCacheSeeder]::Seed($src, $dst, [string[]]$plan.Roots, (Test-IsAdmin), $progress)
    $summary = [pscustomobject]@{
        Linked = $counts[0]; Copied = $counts[1]; Skipped = $counts[2]; Failed = $counts[3]; Selective = $plan.Selective
    }
    Write-Host "    $($summary.Linked) arquivos ligados, $($summary.Copied) copiados, $($summary.Skipped) já estavam, $($summary.Failed) falharam."
    return $summary
}

function Optimize-StemmaUvCache {
    <#
      Deixa em <Root>\cache\uv só o que os uv.lock das versões instaladas usam. A instalação
      da v1.4.0 semeou o cache do usuário inteiro (pacotes de todos os projetos dele): esses
      arquivos não ocupam espaço a mais enquanto o cache do usuário também os tem, mas ficam
      presos aqui quando ele limpa o dele. Monta um cache novo por hardlink a partir do atual
      (mesmo volume: segundos, sem espaço extra), troca e apaga o antigo. Os venvs não mudam
      (cada arquivo deles é outro link). Num formato de cache sem ponteiros não mexe em nada.
    #>
    param([Parameter(Mandatory)][string]$Root)
    $paths = Get-StemmaPaths -Root $Root
    $cache = $paths.UvCache
    if (Test-EmptyDirectory $cache) { return $null }
    $locks = @(Get-InstalledReleases -Root $Root | ForEach-Object { Join-Path $_.Path 'backend\uv.lock' } |
            Where-Object { Test-Path -LiteralPath $_ })
    if ($locks.Count -eq 0) { return $null }
    foreach ($lock in $locks) {
        if (-not (Get-UvCacheSeedPlan -Source $cache -LockPath $lock).Selective) {
            Write-Host '    Cache do uv num formato desconhecido: mantido como está.'
            return $null
        }
    }
    $fresh = "$cache.novo"
    $old = "$cache.antigo"
    foreach ($dir in $fresh, $old) { Remove-StemmaTree -Path $dir }
    Write-Step 'Enxugando o cache de componentes (só o que as versões instaladas usam)'
    foreach ($lock in $locks) { Copy-UvCacheSeed -Source $cache -Dest $fresh -LockPath $lock | Out-Null }
    [IO.Directory]::Move($cache, $old)
    [IO.Directory]::Move($fresh, $cache)
    $before = @(Get-ChildItem -LiteralPath $old -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    $after = @(Get-ChildItem -LiteralPath $cache -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    Remove-StemmaTree -Path $old
    Write-Host "    cache do uv: $before → $after arquivos"
    return [pscustomobject]@{ Before = $before; After = $after }
}

function Get-StemmaCacheDirs {
    <#
      Caches que a instalação vai usar: o dela, se já tiver algo (a atualização só semeia de um
      cache vazio); senão, o do usuário no mesmo volume, que será semeado.
    #>
    param([Parameter(Mandatory)][string]$Root, [string]$UserCache)
    $own = (Get-StemmaPaths -Root $Root).UvCache
    if (-not (Test-EmptyDirectory $own)) { return @($own) }
    if ($UserCache -and (Test-SameVolume $UserCache $Root)) { return @($UserCache) }
    return @()
}

# Wheels sem tamanho no uv.lock (o índice do PyTorch não informa).
$script:UnknownWheelSizes = @{ torch = [long]2.9GB }
$script:UnknownWheelSize = 20MB
# Ferramentas + Python em <Root>\tools, com folga (medido: ~0,5 GB).
$script:ToolsBytes = 600MB

function Get-StemmaSpaceEstimate {
    <#
      Antes de instalar ou atualizar: quanto vai ser baixado (pacotes do uv.lock que não estão nos
      caches) e quanto ocupa no drive da raiz (ferramentas, se faltarem, e os pacotes
      descompactados, ~2x o download). Estimativa, com folga.
    #>
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$LockPath, [string[]]$CacheDirs = @())
    $present = @{}
    foreach ($cache in $CacheDirs) {
        foreach ($key in (Get-UvCachePointers -Cache $cache).Keys) { $present[$key] = $true }
    }
    $needed = @(Get-UvLockPackages -Path $LockPath | Where-Object { $_.Needed })
    $missing = @($needed | Where-Object { -not $present.ContainsKey($_.Key) })
    [long]$download = 0
    foreach ($package in $missing) {
        if ($null -ne $package.Size) { $download += $package.Size }
        elseif ($script:UnknownWheelSizes.ContainsKey($package.Name)) { $download += $script:UnknownWheelSizes[$package.Name] }
        else { $download += $script:UnknownWheelSize }
    }
    [long]$need = 2 * $download
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'tools\uv\uv.exe'))) { $need += $script:ToolsBytes }
    return [pscustomobject]@{
        DownloadBytes = $download
        NeedRootBytes = $need
        Missing       = $missing.Count
        Needed        = $needed.Count
    }
}
