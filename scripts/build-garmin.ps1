param(
    [string]$DeveloperKey = $env:GARMIN_DEVELOPER_KEY,
    [switch]$Release
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$garminRoot = Join-Path $projectRoot 'garmin'
$outputRoot = Join-Path $garminRoot 'build'

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

if (-not $DeveloperKey -or -not (Test-Path $DeveloperKey)) {
    throw 'Set GARMIN_DEVELOPER_KEY to your Garmin developer_key file or pass -DeveloperKey.'
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$extension = if ($Release) { 'iq' } else { 'prg' }
$output = Join-Path $outputRoot "gymapp-fenix8-solar-47mm.$extension"
$compilerArgs = @(
    '-f', 'monkey.jungle',
    '-y', $DeveloperKey,
    '-o', $output,
    '-w'
)
if ($Release) {
    $compilerArgs += '-e'
} else {
    $compilerArgs += @('-d', 'fenix8solar47mm')
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
