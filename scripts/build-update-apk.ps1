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

$versionCode = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$versionName = (Get-Date).ToString("yyyy.MM.dd.HHmm")

Write-Host "Building debug APK with versionCode=$versionCode versionName=$versionName"

& "$projectRoot\gradlew.bat" :app:assembleDebug "-PappVersionCode=$versionCode" "-PappVersionName=$versionName"
if ($LASTEXITCODE -ne 0) {
    throw "Gradle build failed."
}

$apkSource = Join-Path $projectRoot "app\build\outputs\apk\debug\app-debug.apk"
$apkTarget = Join-Path $projectRoot "app-debug.apk"

if (-not (Test-Path $apkSource)) {
    throw "APK not found at: $apkSource"
}

Copy-Item -Path $apkSource -Destination $apkTarget -Force
Write-Host "Copied APK to: $apkTarget"
Write-Host "Install update command: adb install -r app-debug.apk"
