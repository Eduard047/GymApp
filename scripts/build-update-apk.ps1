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
        $resolvedJavaHome = Split-Path -Parent (Split-Path -Parent $javaExePath)
        $env:JAVA_HOME = $resolvedJavaHome
        Write-Host "JAVA_HOME set from PATH: $resolvedJavaHome"
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
            Write-Host "JAVA_HOME set from fallback path: $javaHomeCandidate"
            break
        }
    }
}

if (-not $javaExePath) {
    throw "Java not found. Set JAVA_HOME or install a JDK."
}

$versionBase = [DateTimeOffset]::Parse("2026-01-01T00:00:00Z")
$versionCode = 2000000000 + [int][Math]::Floor(([DateTimeOffset]::UtcNow - $versionBase).TotalMinutes)
$versionName = (Get-Date).ToString("yyyy.MM.dd.HHmm")

Write-Host "Building debug APKs with versionCode=$versionCode versionName=$versionName"

& "$projectRoot\gradlew.bat" :app:assembleDebug :wear:assembleDebug "-PappVersionCode=$versionCode" "-PappVersionName=$versionName" "-PwearVersionCode=$versionCode" "-PwearVersionName=$versionName"
if ($LASTEXITCODE -ne 0) {
    throw "Gradle build failed."
}

$phoneApkSource = Join-Path $projectRoot "app\build\outputs\apk\debug\app-debug.apk"
$phoneApkTarget = Join-Path $projectRoot "gymapp-phone-debug.apk"
$wearApkSource = Join-Path $projectRoot "wear\build\outputs\apk\debug\wear-debug.apk"
$wearApkTarget = Join-Path $projectRoot "gymapp-watch-debug.apk"

if (-not (Test-Path $phoneApkSource)) {
    throw "Phone APK not found at: $phoneApkSource"
}

if (-not (Test-Path $wearApkSource)) {
    throw "Watch APK not found at: $wearApkSource"
}

Copy-Item -Path $phoneApkSource -Destination $phoneApkTarget -Force
Copy-Item -Path $wearApkSource -Destination $wearApkTarget -Force

$metadataDir = Join-Path $projectRoot "tmp"
New-Item -ItemType Directory -Path $metadataDir -Force | Out-Null
$metadataPath = Join-Path $metadataDir "last-build-apk.json"
[ordered]@{
    versionCode = $versionCode
    versionName = $versionName
    phoneApk = $phoneApkTarget
    watchApk = $wearApkTarget
} | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8

Write-Host "Copied phone APK to: $phoneApkTarget"
Write-Host "Copied watch APK to: $wearApkTarget"
Write-Host "Build metadata written to: $metadataPath"
Write-Host "Phone install command: adb install -r gymapp-phone-debug.apk"
Write-Host "Watch install command: adb install -r gymapp-watch-debug.apk"
