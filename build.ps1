# Build the OPPO Sans Magisk module zip.
#
#   .\build.ps1                 -> dist\OPPOSans-Android11-<version>.zip         (正文 400 = Regular)
#   .\build.ps1 -Profile medium -> dist\OPPOSans-Android11-<version>-Medium.zip  (正文 400 = Medium)
#   .\build.ps1 -All            -> both zips
#
# system/etc/fonts.xml in the repo is the regular variant; the medium variant is
# derived from it by swapping only the weight="400" file name.

param(
    [ValidateSet("regular", "medium")][string]$Profile = "regular",
    [switch]$All
)

$ErrorActionPreference = "Stop"

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# weight -> OPPO Sans file. 300/500/600/700 are the same in every profile.
$fixedWeights = @{
    300 = "OPPOSans-Light.ttf"
    500 = "OPPOSans-Medium.ttf"
    600 = "OPPOSans-SemiBold.ttf"
    700 = "OPPOSans-Bold.ttf"
}
$profiles = @{
    regular = @{ 400 = "OPPOSans-Regular.ttf" }
    # Bumping the body weight to Medium would otherwise leave the 500 slot on
    # Medium as well (two identical steps), so 500 moves up to SemiBold.
    medium  = @{ 400 = "OPPOSans-Medium.ttf"; 500 = "OPPOSans-SemiBold.ttf" }
}

$props = @{}
Get-Content (Join-Path $root "module.prop") | ForEach-Object {
    if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') { $props[$matches[1]] = $matches[2].Trim() }
}
$version = $props["version"]
if (-not $version) { throw "module.prop has no version= line" }

$required = @("module.prop", "customize.sh", "system/etc/fonts.xml", "META-INF/com/google/android/update-binary")
foreach ($rel in $required) {
    if (-not (Test-Path (Join-Path $root $rel))) { throw "Missing required file: $rel" }
}

function New-Stage {
    param([string]$Name)

    $stage = Join-Path $env:TEMP "opencode\opposans-build-$Name"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null

    foreach ($item in @("module.prop", "customize.sh", "README.md", "OPPO-Sans-LICENSE.txt", "META-INF")) {
        $src = Join-Path $root $item
        if (-not (Test-Path $src)) { continue }
        Copy-Item $src (Join-Path $stage $item) -Recurse -Force
    }

    $fonts = Join-Path $stage "system\fonts"
    New-Item -ItemType Directory -Force -Path $fonts | Out-Null
    $etc = Join-Path $stage "system\etc"
    New-Item -ItemType Directory -Force -Path $etc | Out-Null

    $map = @{}
    foreach ($w in $fixedWeights.Keys) { $map[$w] = $fixedWeights[$w] }
    foreach ($w in $profiles[$Name].Keys) { $map[$w] = $profiles[$Name][$w] }

    $xml = Get-Content (Join-Path $root "system/etc/fonts.xml") -Raw
    $xml = $xml -replace "`r`n", "`n"

    if ($Name -ne "regular") {
        # Rewrite just the slots this profile moves, keeping every other line
        # of the shared font table byte-identical.
        foreach ($w in $profiles[$Name].Keys) {
            $pattern = ('(?<=<font weight="{0}" style="normal">)OPPOSans-[A-Za-z]+\.ttf(?=</font>)' -f $w)
            $xml = $xml -replace $pattern, $profiles[$Name][$w]
        }
    }

    # Every declared slot must exist in the list, and every file it names must
    # match the profile so a build can never ship the wrong default weight.
    foreach ($w in $map.Keys) {
        $needle = '<font weight="{0}" style="normal">{1}</font>' -f $w, $map[$w]
        if (-not $xml.Contains($needle)) { throw "$Name profile: no weight=""$w"" slot uses $($map[$w])" }
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $etc "fonts.xml"), $xml, $utf8NoBom)

    # Ship only the fonts this profile references.
    $needed = [regex]::Matches($xml, '>(OPPOSans-[A-Za-z]+\.ttf)<') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    foreach ($name in $needed) {
        $src = Join-Path $root "system\fonts\$name"
        if (-not (Test-Path $src)) { throw "fonts.xml references $name but system/fonts/$name is missing" }
        Copy-Item $src (Join-Path $fonts $name) -Force
    }

    return $stage
}

function New-Zip {
    param([string]$Stage, [string]$OutPath)

    if (Test-Path $OutPath) { Remove-Item $OutPath -Force }

    $files = Get-ChildItem $Stage -Recurse -File
    $zip = [System.IO.Compression.ZipFile]::Open($OutPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($Stage.Length).TrimStart('\', '/').Replace('\', '/')
            $entry = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $f.LastWriteTime

            $dest = $entry.Open()
            $src = [System.IO.File]::OpenRead($f.FullName)
            try { $src.CopyTo($dest) } finally { $src.Dispose(); $dest.Dispose() }

            # Keep unix permissions sane for people flashing the zip from a custom recovery.
            $isExec = $f.Extension -eq ".sh" -or $f.Name -eq "update-binary"
            $mode = if ($isExec) { 0x81ED } else { 0x81A4 }   # 100755 / 100644
            $entry.ExternalAttributes = $mode -shl 16
        }
    } finally {
        $zip.Dispose()
    }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$outDir = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$targets = if ($All) { @("regular", "medium") } else { @($Profile) }
foreach ($p in $targets) {
    $suffix = if ($p -eq "medium") { "-Medium" } else { "" }
    $zipPath = Join-Path $outDir ("OPPOSans-Android11-{0}{1}.zip" -f $version, $suffix)
    $stage = New-Stage -Name $p
    New-Zip -Stage $stage -OutPath $zipPath
    $mb = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host ("Built {0} ({1} MB, 400 -> {2})" -f $zipPath, $mb, $profiles[$p][400])
}
