[CmdletBinding()]
param(
    [string] $ClientRoot,
    [string] $ServerRoot,
    [switch] $SkipServerBuild
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$expectedExeSize = 45283960
$originalExeSha256 = 'A40E0E6D447AD65C3A1ADC906D83C0A56416A512BEC6D9A41EC4EB13929566DF'
$regionOnlyExeSha256 = 'EA58D8A91D665D189CFD0FD2132F3E8D51F83AA1E0F7F7E455744B3695BEA79A'
$encounterOnlyExeSha256 = 'FB58E49C4285AC76986B0453D098C04E220C4AA8BE918B81ED1D4E4DCB346145'
$combinedExeSha256 = 'E49D04E6DF97442D76B8DCD626AF19C88F627A470F9C27BE0D4088A26C39B9CD'
$droneReplacementSha256 = 'FB6F7333374345F131FEFB1AC114947BDB9C91816F1ADE2218CF30211D403ACC'
$exporterSha256 = '73A1E1D6C3A393FAACFE2B09446B25976C0737ECF251BCC4B0A5AD989090E970'
$exporterUrl = 'https://github.com/Puxtril/Warframe-Exporter/releases/download/v2.15/Warframe-Exporter-CLI_Windows.exe'
$builderPath = Join-Path $PSScriptRoot 'tools\BuildDroneReplacement.mjs'
$serverInstallerPath = Join-Path $PSScriptRoot 'tools\InstallServerSelector.mjs'

function Write-Step([string] $Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Get-KnownExeState([string] $ExecutablePath) {
    $item = Get-Item -LiteralPath $ExecutablePath
    if ($item.Length -ne $expectedExeSize) {
        return [pscustomobject]@{ Name = 'Unsupported'; Hash = ''; Detail = "size=$($item.Length)" }
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ExecutablePath).Hash
    $name = switch ($hash) {
        $originalExeSha256 { 'Original' }
        $regionOnlyExeSha256 { 'RegionOnly' }
        $encounterOnlyExeSha256 { 'EncounterOnly' }
        $combinedExeSha256 { 'Combined4Player' }
        default { 'Unsupported' }
    }
    [pscustomobject]@{ Name = $name; Hash = $hash; Detail = "size=$($item.Length)" }
}

function Find-ServerRoot([string] $RequestedRoot) {
    $candidates = [Collections.Generic.List[string]]::new()
    if ($RequestedRoot) { $candidates.Add($RequestedRoot) }
    if ($env:ARBITRATION4_SERVER_ROOT) { $candidates.Add($env:ARBITRATION4_SERVER_ROOT) }
    $cursor = Get-Item -LiteralPath $PSScriptRoot
    for ($i = 0; $i -lt 5 -and $null -ne $cursor; $i++) {
        $candidates.Add($cursor.FullName)
        $cursor = $cursor.Parent
    }
    $candidates.Add((Get-Location).Path)
    $candidates.Add('D:\Program Files\WF\SpaceNinjaServer')
    $candidates.Add('C:\Program Files\WF\SpaceNinjaServer')
    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        if ((Test-Path -LiteralPath (Join-Path $resolved 'package.json')) -and
            (Test-Path -LiteralPath (Join-Path $resolved 'src\services\worldStateService.ts'))) { return $resolved }
    }
    throw 'Could not locate SpaceNinjaServer. Pass -ServerRoot or set ARBITRATION4_SERVER_ROOT.'
}

function Find-ClientRoot([string] $RequestedRoot, [string] $ResolvedServerRoot) {
    $candidates = [Collections.Generic.List[string]]::new()
    if ($RequestedRoot) { $candidates.Add($RequestedRoot) }
    if ($env:ARBITRATION4_CLIENT_ROOT) { $candidates.Add($env:ARBITRATION4_CLIENT_ROOT) }
    foreach ($wfRoot in @((Split-Path -Parent $ResolvedServerRoot), 'D:\Program Files\WF', 'C:\Program Files\WF') | Select-Object -Unique) {
        if (-not $wfRoot -or -not (Test-Path -LiteralPath $wfRoot -PathType Container)) { continue }
        Get-ChildItem -Path (Join-Path $wfRoot 'install\*\*\Warframe.x64.exe') -File -ErrorAction SilentlyContinue |
            ForEach-Object { $candidates.Add($_.DirectoryName) }
    }
    $unsupported = @()
    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (-not $candidate -or -not (Test-Path -LiteralPath $candidate -PathType Container)) { continue }
        $resolved = (Resolve-Path -LiteralPath $candidate).Path
        $exe = Join-Path $resolved 'Warframe.x64.exe'
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
        $state = Get-KnownExeState $exe
        if ($state.Name -ne 'Unsupported') { return $resolved }
        $unsupported += "$resolved ($($state.Detail), SHA-256=$($state.Hash))"
    }
    if ($unsupported.Count) { throw "Only unsupported Warframe clients were found:`n$($unsupported -join "`n")" }
    throw 'Could not locate the supported Warframe client. Pass -ClientRoot or set ARBITRATION4_CLIENT_ROOT.'
}

function Assert-ClientStopped([string] $ExecutablePath) {
    $target = (Resolve-Path -LiteralPath $ExecutablePath).Path
    foreach ($process in Get-Process -Name 'Warframe.x64' -ErrorAction SilentlyContinue) {
        if ($process.Path -and $process.Path -eq $target) {
            throw 'Warframe is running. Exit the client completely, then run the installer again.'
        }
    }
}

function Install-ServerLauncher([string] $ResolvedServerRoot) {
    $launcherPath = Join-Path $ResolvedServerRoot 'START ARBITRATION4 SERVER.cmd'
    $launcher = @'
@echo off
setlocal
cd /d "%~dp0"

if not exist "build\src\index.js" (
    echo [Arbitration4] Server build was not found: "%CD%\build\src\index.js"
    echo Run the Arbitration4 installer successfully before using this launcher.
    pause
    exit /b 1
)

echo Starting SpaceNinjaServer without updating files...
node --enable-source-maps "build\src\index.js"
set "ARBITRATION4_SERVER_EXIT=%ERRORLEVEL%"
echo.
echo SpaceNinjaServer stopped with exit code %ARBITRATION4_SERVER_EXIT%.
pause
exit /b %ARBITRATION4_SERVER_EXIT%
'@
    Set-Content -LiteralPath $launcherPath -Value $launcher -Encoding Ascii
    if ((Get-Content -LiteralPath $launcherPath -Raw) -notmatch 'node --enable-source-maps "build\\src\\index\.js"') {
        throw 'Installed server launcher failed verification.'
    }
    Write-Host "Server launcher: $launcherPath" -ForegroundColor Green
}

function Ensure-ServerBuildDependencies([string] $ResolvedServerRoot) {
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
        throw 'npm.cmd is required to install and build SpaceNinjaServer.'
    }

    $requiredBins = @(
        (Join-Path $ResolvedServerRoot 'node_modules\.bin\tsgo.cmd'),
        (Join-Path $ResolvedServerRoot 'node_modules\.bin\ncp.cmd')
    )
    $missing = @($requiredBins | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count -gt 0) {
        Write-Step 'Installing required SpaceNinjaServer build dependencies'
        & npm.cmd --prefix $ResolvedServerRoot install --include=optional --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) {
            throw 'SpaceNinjaServer dependency installation failed.'
        }
    }

    $stillMissing = @($requiredBins | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($stillMissing.Count -gt 0) {
        throw "SpaceNinjaServer build dependencies are still missing after npm install:`n$($stillMissing -join "`n")"
    }
}

function Assert-Bytes([byte[]] $Image, [int64] $Offset, [byte[]] $Expected, [string] $Label) {
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Image[$Offset + $i] -ne $Expected[$i]) {
            throw ('{0} byte mismatch at file offset 0x{1:X}' -f $Label, ($Offset + $i))
        }
    }
}

function Install-ExecutablePatch([string] $ExecutablePath) {
    $state = Get-KnownExeState $ExecutablePath
    if ($state.Name -eq 'Combined4Player') {
        Write-Host 'Executable: already patched to four-player mode.' -ForegroundColor Green
        return
    }
    if ($state.Name -ne 'Original') {
        throw "The executable is unsupported or partially patched ($($state.Name)). Restore the original EXE first. SHA-256=$($state.Hash)"
    }
    [byte[]] $image = [IO.File]::ReadAllBytes($ExecutablePath)
    [byte[]] $regionOriginal = 0x48,0xC1,0xEE,0x03
    [byte[]] $globalOriginal = 0x48,0x0F,0x42,0xC1
    [byte[]] $clusterOriginal = @(
        0x44,0x8B,0x81,0x58,0x03,0x00,0x00,0x4C,0x8B,0xCA,
        0x48,0xB8,0xAB,0xAA,0xAA,0xAA,0xAA,0xAA,0xAA,0xAA,
        0x49,0xF7,0xE0,0x48,0xC1,0xEA,0x05,0x4C,0x3B,0xCA,
        0x73,0x13,0x48,0x8B,0x81,0x50,0x03,0x00,0x00,0x4B,
        0x8D,0x14,0x49,0x48,0x03,0xD2,0x8B,0x44,0xD0,0x28,
        0xC3,0x33,0xC0,0xC3
    )
    Assert-Bytes $image 0x01A5A23C $regionOriginal 'Region player count'
    Assert-Bytes $image 0x008A7CA7 $globalOriginal 'Global player count'
    Assert-Bytes $image 0x01707D20 $clusterOriginal 'Encounter cluster player count'

    [byte[]] $regionPatch = 0x6A,0x04,0x5E,0x90
    [byte[]] $globalPatch = 0xB0,0x04,0x90,0x90
    [byte[]] $clusterPatch = 0xB8,0x04,0x00,0x00,0x00,0xC3,0x33,0xC0,0xC3
    [Array]::Copy($regionPatch, 0, $image, 0x01A5A23C, $regionPatch.Length)
    [Array]::Copy($globalPatch, 0, $image, 0x008A7CA7, $globalPatch.Length)
    $image[0x01707D20 + 31] = 0x14
    [Array]::Copy($clusterPatch, 0, $image, 0x01707D20 + 46, $clusterPatch.Length)

    $stream = [IO.File]::Open($ExecutablePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($image, 0, $image.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    $patched = Get-KnownExeState $ExecutablePath
    if ($patched.Name -ne 'Combined4Player') {
        throw "Executable post-write verification failed: $($patched.Hash). Restore the original EXE by file replacement."
    }
    Write-Host 'Executable: four-player encounter and script counts installed.' -ForegroundColor Green
}

function Get-VerifiedExporter {
    $toolRoot = Join-Path $PSScriptRoot 'runtime\tools'
    New-Item -ItemType Directory -Force -Path $toolRoot | Out-Null
    $exporterPath = Join-Path $toolRoot 'Warframe-Exporter-CLI_Windows-v2.15.exe'
    if (Test-Path -LiteralPath $exporterPath) {
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $exporterPath).Hash -ne $exporterSha256) {
            throw "Existing exporter failed SHA-256 verification: $exporterPath"
        }
        return $exporterPath
    }
    $downloadPath = Join-Path $toolRoot ("Warframe-Exporter.download-" + [guid]::NewGuid().ToString('N') + '.exe')
    Write-Step 'Downloading pinned Warframe Exporter v2.15'
    Invoke-WebRequest -UseBasicParsing -Headers @{'User-Agent'='Arbitration4-Installer'} -Uri $exporterUrl -OutFile $downloadPath
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $downloadPath).Hash -ne $exporterSha256) {
        throw "Downloaded exporter failed SHA-256 verification and was left for inspection: $downloadPath"
    }
    Move-Item -LiteralPath $downloadPath -Destination $exporterPath
    $exporterPath
}

function Get-DroneState([string] $ResolvedClientRoot) {
    $directory = Join-Path $ResolvedClientRoot 'OpenWF\Content Replacements\0\Lotus\Scripts'
    $files = @(Get-ChildItem -LiteralPath $directory -File -Filter 'LotusGameRules.lua!75_*' -ErrorAction SilentlyContinue)
    $ours = @($files | Where-Object { (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash -eq $droneReplacementSha256 })
    [pscustomobject]@{ Directory=$directory; Files=$files; Ours=$ours }
}

function New-DroneReplacement([string] $ResolvedClientRoot, [string] $Workspace) {
    $cacheRoot = Join-Path $ResolvedClientRoot 'Cache.Windows'
    if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) { throw "Cache.Windows was not found: $cacheRoot" }
    $exporter = Get-VerifiedExporter
    $rawRoot = Join-Path $Workspace 'raw'
    New-Item -ItemType Directory -Force -Path $rawRoot | Out-Null
    Write-Step 'Extracting LotusGameRules.lua from the local client cache'
    & $exporter --write-raw --cache-dir $cacheRoot --package Font --internal-path '/Lotus/Scripts/LotusGameRules.lua' --output-path $rawRoot --game Warframe
    if ($LASTEXITCODE -ne 0) { throw "Warframe Exporter failed with exit code $LASTEXITCODE" }
    $header = Join-Path $rawRoot 'Debug\Lotus\Scripts\LotusGameRules.lua_H'
    $body = Join-Path $rawRoot 'Debug\Lotus\Scripts\LotusGameRules.lua_B'
    if (-not (Test-Path -LiteralPath $header) -or -not (Test-Path -LiteralPath $body)) {
        throw 'Warframe Exporter did not produce the expected LotusGameRules raw files.'
    }
    $generatedRoot = Join-Path $Workspace 'generated'
    $json = & node $builderPath --header $header --body $body --output-directory $generatedRoot
    if ($LASTEXITCODE -ne 0) { throw "Drone replacement builder failed with exit code $LASTEXITCODE" }
    $result = $json | ConvertFrom-Json
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $result.outputPath).Hash -ne $droneReplacementSha256) {
        throw 'Generated drone replacement failed final SHA-256 verification.'
    }
    $result
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is required.' }
$resolvedServerRoot = Find-ServerRoot $ServerRoot
$resolvedClientRoot = Find-ClientRoot $ClientRoot $resolvedServerRoot
$executablePath = Join-Path $resolvedClientRoot 'Warframe.x64.exe'
Assert-ClientStopped $executablePath
Write-Host "Client: $resolvedClientRoot"
Write-Host "Server: $resolvedServerRoot"

$exeState = Get-KnownExeState $executablePath
if ($exeState.Name -notin @('Original', 'Combined4Player')) {
    throw "Unsupported or partial executable state: $($exeState.Name), SHA-256=$($exeState.Hash)"
}
$droneState = Get-DroneState $resolvedClientRoot
if ($droneState.Files.Count -gt 0 -and -not ($droneState.Files.Count -eq 1 -and $droneState.Ours.Count -eq 1)) {
    throw 'Another LotusGameRules.lua replacement is installed. Refusing to create a conflicting replacement.'
}

Write-Step 'Checking SpaceNinjaServer structural compatibility'
& node $serverInstallerPath $resolvedServerRoot --check
if ($LASTEXITCODE -ne 0) { throw 'SpaceNinjaServer selector compatibility check failed.' }

# Resolve build tools before writing the executable or server source files. This
# prevents a missing optional npm dependency from leaving a partial installation.
Ensure-ServerBuildDependencies $resolvedServerRoot

$workspace = Join-Path $PSScriptRoot ("runtime\work\" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workspace -Force | Out-Null
$generated = if ($droneState.Ours.Count -eq 0) { New-DroneReplacement $resolvedClientRoot $workspace } else { $null }

Write-Step 'Installing Arbitration4 components'
Install-ExecutablePatch $executablePath
if ($generated) {
    New-Item -ItemType Directory -Force -Path $droneState.Directory | Out-Null
    $destination = Join-Path $droneState.Directory $generated.fileName
    Copy-Item -LiteralPath $generated.outputPath -Destination $destination
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -ne $droneReplacementSha256) {
        throw 'Installed drone replacement failed SHA-256 verification.'
    }
}
& node $serverInstallerPath $resolvedServerRoot
if ($LASTEXITCODE -ne 0) { throw 'SpaceNinjaServer selector installation failed.' }

if (-not $SkipServerBuild) {
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) { throw 'npm.cmd is required to build SpaceNinjaServer.' }
    Write-Step 'Verifying and rebuilding SpaceNinjaServer'
    & npm.cmd --prefix $resolvedServerRoot run verify
    if ($LASTEXITCODE -ne 0) { throw 'SpaceNinjaServer verification failed.' }
    & npm.cmd --prefix $resolvedServerRoot run build
    if ($LASTEXITCODE -ne 0) { throw 'SpaceNinjaServer build failed.' }
}

$finalExe = Get-KnownExeState $executablePath
$finalDrone = Get-DroneState $resolvedClientRoot
if ($finalExe.Name -ne 'Combined4Player' -or $finalDrone.Ours.Count -ne 1) {
    throw 'Final client component verification failed.'
}
Install-ServerLauncher $resolvedServerRoot
Write-Host "`nArbitration4 installation completed successfully." -ForegroundColor Green
Write-Host 'Restart SpaceNinjaServer and the Warframe client before testing.'
