<#
.SYNOPSIS
  Compila o instalador (Stemma-Setup-vX.Y.Z.exe + .sha256) a partir do pacote da release.

.DESCRIPTION
  Usado pelo release.yml, pelo CI de PR e localmente. Junta o zip da release (com o .sha256)
  e a wheel do segno (SHA256 fixado) numa pasta de payload e roda o ISCC (Inno Setup 6.3+).

.EXAMPLE
  bash scripts/package.sh v1.4.0 build            # gera build/stemma-v1.4.0.zip (+ .sha256)
  powershell -ExecutionPolicy Bypass -File installer\build.ps1 -ZipPath build\stemma-v1.4.0.zip

.PARAMETER ZipPath
  stemma-vX.Y.Z.zip, com o .sha256 ao lado.
.PARAMETER OutDir
  Onde gravar o .exe. Padrão: a pasta do zip.
.PARAMETER Iscc
  Caminho do ISCC.exe. Padrão: PATH ou as pastas de instalação do Inno Setup 6.
#>
param(
    [Parameter(Mandatory)][string]$ZipPath,
    [string]$OutDir,
    [string]$Iscc
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\deploy\StemmaDeploy.psm1') -Force

# segno (QR code em Python puro, MIT) para a tela final do instalador.
$SegnoUrl = 'https://files.pythonhosted.org/packages/d6/02/12c73fd423eb9577b97fc1924966b929eff7074ae6b2e15dd3d30cb9e4ae/segno-1.6.6-py3-none-any.whl'
$SegnoSha256 = '28c7d081ed0cf935e0411293a465efd4d500704072cdb039778a2ab8736190c7'

function Find-Iscc {
    $candidates = @()
    $cmd = Get-Command iscc -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $candidates += $cmd.Source }
    foreach ($base in ${env:ProgramFiles(x86)}, $env:ProgramFiles, (Join-Path $env:LOCALAPPDATA 'Programs')) {
        if ($base) { $candidates += Join-Path $base 'Inno Setup 6\ISCC.exe' }
    }
    foreach ($path in $candidates) { if (Test-Path -LiteralPath $path) { return $path } }
    throw 'ISCC.exe (Inno Setup 6) não encontrado. Instale com: winget install JRSoftware.InnoSetup'
}

$zip = (Resolve-Path -LiteralPath $ZipPath).Path
$tag = Get-VersionFromZipName $zip
$version = $tag.TrimStart('v')
Assert-Sha256 -Path $zip -Expected (Get-Sha256FromFile "$zip.sha256")
if (-not $OutDir) { $OutDir = Split-Path -Parent $zip }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
if (-not $Iscc) { $Iscc = Find-Iscc }

$payload = Join-Path ([IO.Path]::GetTempPath()) "stemma-payload-$tag"
if (Test-Path -LiteralPath $payload) { Remove-Item -LiteralPath $payload -Recurse -Force }
New-Item -ItemType Directory -Force -Path $payload | Out-Null
Copy-Item -LiteralPath $zip, "$zip.sha256" -Destination $payload

# Ícone da bandeja (Stemma.exe), com o csc do .NET Framework 4 que vem em todo Windows.
Write-Step 'Compilando o Stemma.exe (bandeja)'
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
Invoke-Native -FilePath $csc -Arguments @(
    '/nologo', '/target:winexe', '/optimize+', '/warnaserror+',
    "/win32icon:$(Join-Path $PSScriptRoot 'stemma.ico')",
    "/win32manifest:$(Join-Path $PSScriptRoot 'tray\Stemma.manifest')",
    '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll', '/r:System.ServiceProcess.dll',
    "/out:$(Join-Path $payload 'Stemma.exe')", (Join-Path $PSScriptRoot 'tray\StemmaTray.cs')
)

$wheel = Join-Path $payload (($SegnoUrl -split '/')[-1])
Write-Step 'Baixando o segno'
Invoke-Download -Url $SegnoUrl -Dest $wheel
Assert-Sha256 -Path $wheel -Expected $SegnoSha256

Write-Step "Compilando o instalador $tag"
Invoke-Native -FilePath $Iscc -Arguments @(
    '/Qp', "/DAppVersion=$version", "/DPayloadDir=$payload", "/O$OutDir",
    (Join-Path $PSScriptRoot 'stemma.iss')
)
$exe = Join-Path $OutDir "Stemma-Setup-$tag.exe"
$hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$exe.sha256", "$hash  $(Split-Path -Leaf $exe)`n", [Text.UTF8Encoding]::new($false))
Remove-Item -LiteralPath $payload -Recurse -Force
Write-Step "Pronto: $exe"
