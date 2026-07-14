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
    $localDeveloperKey = Join-Path $projectRoot 'garmin-keys\developer_key.der'
    if (Test-Path $localDeveloperKey) {
        $DeveloperKey = $localDeveloperKey
    }
}

if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    $androidStudioJbr = 'C:\Program Files\Android\Android Studio\jbr'
    if (Test-Path (Join-Path $androidStudioJbr 'bin\java.exe')) {
        $env:JAVA_HOME = $androidStudioJbr
        $env:Path = "$(Join-Path $androidStudioJbr 'bin');$env:Path"
    } else {
        throw 'Java not found. Install a JDK or Android Studio before building the Garmin app.'
    }
}

$monkeycCommand = Get-Command monkeyc -ErrorAction SilentlyContinue
$monkeycPath = if ($monkeycCommand) { $monkeycCommand.Source } else { $null }
if (-not $monkeycPath) {
    $currentSdk = Join-Path $env:APPDATA 'Garmin\ConnectIQ\current-sdk.cfg'
    if (Test-Path $currentSdk) {
        $sdkPath = (Get-Content $currentSdk -Raw).Trim()
        $candidate = Join-Path $sdkPath 'bin\monkeyc.bat'
        if (Test-Path $candidate) {
            $monkeycPath = $candidate
        }
    }
}

if (-not $monkeycPath) {
    throw 'Connect IQ SDK not found. Install it with Garmin Connect IQ SDK Manager, then run this script again.'
}

$deviceRoot = Join-Path $env:APPDATA 'Garmin\ConnectIQ\Devices'
$devicePath = Join-Path $deviceRoot $Device
if (-not (Test-Path $devicePath)) {
    throw "Connect IQ device '$Device' is not installed. Open Garmin SDK Manager, install the device package, then rerun with -Device $Device."
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
    $compilerArgs += '-e'
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
