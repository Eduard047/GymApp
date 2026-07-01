param(
    [string]$VersionName,
    [int]$VersionCode
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

$javaExePath = $null
if ($env:JAVA_HOME) {
    $candidate = Join-Path $env:JAVA_HOME "bin\java.exe"
    if (Test-Path $candidate) {
        $javaExePath = $candidate
    }
}

if (-not $javaExePath) {
    $javaCommand = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCommand) {
        $javaExePath = $javaCommand.Source
        $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $javaExePath)
    }
}

if (-not $javaExePath) {
    $fallbackHomes = @(
        "$env:ProgramFiles\Android\Android Studio\jbr",
        "$env:ProgramFiles\Java\jdk-21",
        "$env:ProgramFiles\Java\jdk-17"
    )

    foreach ($javaHomeCandidate in $fallbackHomes) {
        $candidate = Join-Path $javaHomeCandidate "bin\java.exe"
        if (Test-Path $candidate) {
            $env:JAVA_HOME = $javaHomeCandidate
            $javaExePath = $candidate
            break
        }
    }
}

if (-not $javaExePath) {
    throw "Java not found. Set JAVA_HOME or install a JDK."
}

$keystorePropertiesPath = Join-Path $projectRoot "keystore.properties"
if (-not (Test-Path $keystorePropertiesPath)) {
    throw "keystore.properties not found. Create a local release keystore before building the Play Store AAB."
}

if (-not $VersionCode) {
    $versionBase = [DateTimeOffset]::Parse("2026-01-01T00:00:00Z")
    $VersionCode = 2000000000 + [int][Math]::Floor(([DateTimeOffset]::UtcNow - $versionBase).TotalMinutes)
}

if (-not $VersionName) {
    $VersionName = (Get-Date).ToString("yyyy.MM.dd.HHmm")
}

Write-Host "Building Play release AAB with versionCode=$VersionCode versionName=$VersionName"

& "$projectRoot\gradlew.bat" :app:bundleRelease "-PappVersionCode=$VersionCode" "-PappVersionName=$VersionName" "-PdevApplicationIdSuffix=false"
if ($LASTEXITCODE -ne 0) {
    throw "Gradle build failed."
}

$bundleSource = Join-Path $projectRoot "app\build\outputs\bundle\release\app-release.aab"
$bundleTarget = Join-Path $projectRoot "gymapp-play-release.aab"

if (-not (Test-Path $bundleSource)) {
    throw "Play release AAB not found at: $bundleSource"
}

Copy-Item -Path $bundleSource -Destination $bundleTarget -Force

$metadataDir = Join-Path $projectRoot "tmp"
New-Item -ItemType Directory -Path $metadataDir -Force | Out-Null
$metadataPath = Join-Path $metadataDir "last-play-release-aab.json"
[ordered]@{
    versionCode = $VersionCode
    versionName = $VersionName
    bundle = $bundleTarget
} | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8

Write-Host "Copied Play release AAB to: $bundleTarget"
Write-Host "Build metadata written to: $metadataPath"
