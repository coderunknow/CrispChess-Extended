param(
  [Parameter(Mandatory=$true)][string]$Destination
)
$ErrorActionPreference = 'Stop'
if (!(Test-Path $Destination)) { throw "Destination does not exist: $Destination" }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (!(Test-Path $vswhere)) { throw 'vswhere.exe was not found' }
$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($vsPath)) { throw 'Visual Studio with the C++ toolset was not found' }
$redistRoot = Join-Path $vsPath 'VC\Redist\MSVC'
if (!(Test-Path $redistRoot)) { throw "Visual C++ redist directory not found: $redistRoot" }

function Find-RedistDir([string]$Pattern) {
  foreach ($version in (Get-ChildItem $redistRoot -Directory | Sort-Object Name -Descending)) {
    $arch = Join-Path $version.FullName 'x64'
    if (!(Test-Path $arch)) { continue }
    $dir = Get-ChildItem $arch -Directory -Filter $Pattern | Select-Object -First 1
    if ($null -ne $dir) { return $dir.FullName }
  }
  return $null
}

$crt = Find-RedistDir 'Microsoft.VC*.CRT'
if ($null -eq $crt) { throw 'No x64 Microsoft.VC*.CRT redist directory was found' }
foreach ($name in @('vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll')) {
  if (!(Test-Path (Join-Path $crt $name))) { throw "Required MSVC runtime file is missing: $crt\$name" }
}
$omp = Find-RedistDir 'Microsoft.VC*.OpenMP'
if ($null -eq $omp) { throw 'No x64 Microsoft.VC*.OpenMP redist directory was found' }
if (!(Test-Path (Join-Path $omp 'vcomp140.dll'))) { throw "Required OpenMP runtime file is missing: $omp\vcomp140.dll" }

foreach ($source in @($crt, $omp)) {
  Get-ChildItem $source -Filter '*.dll' | ForEach-Object {
    $target = Join-Path $Destination $_.Name
    Copy-Item $_.FullName -Destination $target -Force
    if (!(Test-Path $target)) { throw "Failed to copy $($_.Name)" }
  }
}
Write-Host "Bundled MSVC runtime from $crt and OpenMP runtime from $omp into $Destination"
