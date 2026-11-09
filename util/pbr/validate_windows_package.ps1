[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageRoot
)

$ErrorActionPreference = "Stop"
$rootInput = (Resolve-Path -LiteralPath $PackageRoot).Path
$executables = @(Get-ChildItem -LiteralPath $rootInput -Filter "luanti.exe" -File -Recurse |
    Where-Object { $_.Directory.Name -eq "bin" })
if ($executables.Count -ne 1) {
    throw "Expected exactly one bin/luanti.exe under package root; found $($executables.Count)."
}

$exe = $executables[0].FullName
$package = Split-Path -Parent (Split-Path -Parent $exe)

$requiredFiles = @(
    "builtin/init.lua",
    "builtin/settingtypes.txt",
    "client/shaders/nodes_shader/opengl_vertex.glsl",
    "client/shaders/nodes_shader/opengl_fragment.glsl",
    "games/devtest/game.conf",
    "games/devtest/mods/basenodes/init.lua",
    "doc/pbr.md",
    "doc/devtest_texture_mapping.json"
)
foreach ($relative in $requiredFiles) {
    $full = Join-Path $package $relative
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        throw "Portable package is missing required file: $relative"
    }
}

$settings = Get-Content -LiteralPath (Join-Path $package "builtin/settingtypes.txt") -Raw
foreach ($setting in @("enable_pbr", "enable_pbr_parallax",
        "pbr_parallax_samples", "pbr_parallax_height_scale")) {
    if ($settings -notmatch "(?m)^$setting\s") {
        throw "PBR setting '$setting' is not present in packaged builtin/settingtypes.txt"
    }
}

$manifest = Get-Content -LiteralPath (Join-Path $package "doc/devtest_texture_mapping.json") -Raw |
    ConvertFrom-Json
if ($manifest.schema_version -ne 1 -or $manifest.mappings.Count -lt 1) {
    throw "Packaged Devtest texture mapping manifest is invalid."
}

Write-Output "PACKAGE_ROOT=$package"
Write-Output "PORTABLE_FILES_CHECK=passed"
Write-Output "PBR_SETTINGS_CHECK=passed"
Write-Output "TEXTURE_MAPPING_MANIFEST_CHECK=passed"

$versionOutput = & $exe --version 2>&1
$versionExitCode = $LASTEXITCODE
$versionOutput | ForEach-Object { Write-Output $_ }
if ($versionExitCode -ne 0) {
    throw "Packaged luanti.exe --version failed with exit code $versionExitCode"
}
Write-Output "PORTABLE_STARTUP_TEST=passed"
