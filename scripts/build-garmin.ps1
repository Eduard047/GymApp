param(
    [string]$DeveloperKey = $env:GARMIN_DEVELOPER_KEY,
    [string]$Device = 'fenix8solar47mm',
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$garminRoot = Join-Path $projectRoot 'garmin'
$outputRoot = Join-Path $garminRoot 'build'

if (-not $DeveloperKey) {
    $localDeveloperKey = Join-Path (Join-Path $projectRoot 'garmin-keys') 'developer_key.der'
    if (Test-Path $localDeveloperKey) {
        $DeveloperKey = $localDeveloperKey
    }
}

$javaCommand = Get-Command java -ErrorAction SilentlyContinue
$javaWorks = $false
if ($javaCommand) {
    & $javaCommand.Source -version 2>$null
    $javaWorks = $LASTEXITCODE -eq 0
}
if (-not $javaWorks) {
    $jbrCandidates = @(
        $env:JAVA_HOME,
        'C:\Program Files\Android\Android Studio\jbr',
        '/Applications/Android Studio.app/Contents/jbr/Contents/Home'
    ) | Where-Object { $_ }
    foreach ($jbr in $jbrCandidates) {
        $javaName = if ($env:OS -eq 'Windows_NT') { 'java.exe' } else { 'java' }
        $javaPath = Join-Path (Join-Path $jbr 'bin') $javaName
        if (Test-Path $javaPath) {
            $env:JAVA_HOME = $jbr
            $env:Path = "$(Join-Path $jbr 'bin')$([IO.Path]::PathSeparator)$env:Path"
            $javaWorks = $true
            break
        }
    }
}
if (-not $javaWorks) {
    throw 'Java not found. Install a JDK or Android Studio before building the Garmin app.'
}

$userProfile = [Environment]::GetFolderPath('UserProfile')
$connectIqRoot = if ($env:APPDATA) {
    Join-Path $env:APPDATA 'Garmin\ConnectIQ'
} else {
    Join-Path $userProfile 'Library/Application Support/Garmin/ConnectIQ'
}

$monkeycCommand = Get-Command monkeyc -ErrorAction SilentlyContinue
$monkeycPath = if ($monkeycCommand) { $monkeycCommand.Source } else { $null }
if (-not $monkeycPath) {
    $currentSdk = Join-Path $connectIqRoot 'current-sdk.cfg'
    if (Test-Path $currentSdk) {
        $sdkPath = (Get-Content $currentSdk -Raw).Trim()
        $monkeycName = if ($env:OS -eq 'Windows_NT') { 'monkeyc.bat' } else { 'monkeyc' }
        $candidate = Join-Path (Join-Path $sdkPath 'bin') $monkeycName
        if (Test-Path $candidate) {
            $monkeycPath = $candidate
        }
    }
}

if (-not $monkeycPath) {
    throw 'Connect IQ SDK not found. Install it with Garmin Connect IQ SDK Manager, then run this script again.'
}

$deviceRoot = Join-Path $connectIqRoot 'Devices'
if (-not $Release) {
    $devicePath = Join-Path $deviceRoot $Device
    if (-not (Test-Path $devicePath)) {
        throw "Connect IQ device '$Device' is not installed. Open Garmin SDK Manager, install the device package, then rerun with -Device $Device."
    }
}

if (-not $DeveloperKey -or -not (Test-Path $DeveloperKey)) {
    throw 'Set GARMIN_DEVELOPER_KEY to your Garmin developer_key file or pass -DeveloperKey.'
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$outputName = if ($Release) { 'gymapp-garmin-connect-iq.iq' } else { "gymapp-$Device.prg" }
$output = Join-Path $outputRoot $outputName
$compilerArgs = @(
    '-f', 'monkey.jungle',
    '-y', $DeveloperKey,
    '-o', $output,
    '-w'
)
if ($Release) {
    $compilerArgs += @('-r', '-e')
} else {
    $compilerArgs += @('-d', $Device)
}

Push-Location $garminRoot
try {
    & $monkeycPath @compilerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Garmin build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host "Garmin build: $output"
