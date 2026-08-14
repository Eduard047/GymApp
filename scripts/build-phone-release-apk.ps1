param(
    [string]$VersionName,
    [int]$VersionCode,
    [string]$FirebaseConfigFile = $env:ORG_GRADLE_PROJECT_gymappFirebaseConfigFile,
    [string]$FirebaseConfigSha256 = $env:GYMAPP_FIREBASE_CONFIG_SHA256
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "android-release-firebase-gate.ps1")

$expectedPackageId = "com.setforge.gymapp"

function ConvertFrom-JavaPropertyEscapes {
    param([string]$Value)

    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        if ($character -ne '\' -or $index + 1 -ge $Value.Length) {
            [void]$builder.Append($character)
            continue
        }

        $index++
        $escaped = $Value[$index]
        switch ($escaped) {
            't' { [void]$builder.Append("`t") }
            'r' { [void]$builder.Append("`r") }
            'n' { [void]$builder.Append("`n") }
            'f' { [void]$builder.Append([char]12) }
            'u' {
                if ($index + 4 -ge $Value.Length) {
                    throw "Invalid Unicode escape in keystore.properties."
                }
                $hex = $Value.Substring($index + 1, 4)
                $codePoint = 0
                if (-not [int]::TryParse(
                    $hex,
                    [System.Globalization.NumberStyles]::HexNumber,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref]$codePoint
                )) {
                    throw "Invalid Unicode escape in keystore.properties."
                }
                [void]$builder.Append([char]$codePoint)
                $index += 4
            }
            default { [void]$builder.Append($escaped) }
        }
    }
    return $builder.ToString()
}

function Read-ReleaseKeystoreProperties {
    param([string]$Path)

    $properties = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(storeFile|storePassword|keyAlias|storeType)\s*[=:]\s*(.*)$') {
            $properties[$matches[1]] = ConvertFrom-JavaPropertyEscapes $matches[2]
        }
    }
    foreach ($requiredName in @('storeFile', 'storePassword', 'keyAlias')) {
        if ([string]::IsNullOrWhiteSpace($properties[$requiredName])) {
            throw "keystore.properties is missing required release signing configuration."
        }
    }
    return $properties
}

function Get-Sha256Hex {
    param([byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($Bytes)
    } finally {
        $sha256.Dispose()
    }
    return -join ($hash | ForEach-Object { $_.ToString('x2') })
}

function Get-ReleaseKeystoreCertificateSha256 {
    param(
        [string]$KeytoolPath,
        [string]$KeystorePath,
        [string]$KeyAlias,
        [string]$StorePassword,
        [string]$StoreType
    )

    $passwordEnvironmentName = "GYMAPP_RELEASE_STOREPASS_$PID"
    $previousPassword = [Environment]::GetEnvironmentVariable($passwordEnvironmentName, 'Process')
    try {
        [Environment]::SetEnvironmentVariable(
            $passwordEnvironmentName,
            $StorePassword,
            'Process'
        )
        $keytoolArguments = @(
            '-J-Duser.language=en',
            '-J-Duser.country=US',
            '-exportcert',
            '-rfc',
            '-keystore', $KeystorePath,
            '-alias', $KeyAlias,
            '-storepass:env', $passwordEnvironmentName
        )
        if (-not [string]::IsNullOrWhiteSpace($StoreType)) {
            $keytoolArguments += @('-storetype', $StoreType)
        }
        $certificateOutput = @(& $KeytoolPath @keytoolArguments 2>&1)
        $keytoolExitCode = $LASTEXITCODE
    } finally {
        [Environment]::SetEnvironmentVariable(
            $passwordEnvironmentName,
            $previousPassword,
            'Process'
        )
    }

    if ($keytoolExitCode -ne 0) {
        throw "Could not read the configured release signing certificate."
    }
    $certificateText = $certificateOutput -join "`n"
    $certificateMatch = [regex]::Match(
        $certificateText,
        '(?s)-----BEGIN CERTIFICATE-----\s*(?<body>[A-Za-z0-9+/=\r\n]+?)\s*-----END CERTIFICATE-----'
    )
    if (-not $certificateMatch.Success) {
        throw "Could not parse the configured release signing certificate."
    }
    $certificateBase64 = $certificateMatch.Groups['body'].Value -replace '\s', ''
    try {
        $certificateBytes = [Convert]::FromBase64String($certificateBase64)
    } catch {
        throw "Could not parse the configured release signing certificate."
    }
    return (Get-Sha256Hex $certificateBytes)
}

function Resolve-AndroidSdkPath {
    param([string]$ProjectRoot)

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($environmentPath in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)) {
        if (-not [string]::IsNullOrWhiteSpace($environmentPath)) {
            $candidates.Add($environmentPath)
        }
    }

    $localPropertiesPath = Join-Path $ProjectRoot 'local.properties'
    if (Test-Path -LiteralPath $localPropertiesPath) {
        foreach ($line in Get-Content -LiteralPath $localPropertiesPath) {
            if ($line -match '^\s*sdk\.dir\s*=\s*(.+)$') {
                $candidates.Add((ConvertFrom-JavaPropertyEscapes $matches[1]))
            }
        }
    }

    $userProfilePath = [Environment]::GetFolderPath('UserProfile')
    if ($isWindowsPlatform -and $env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Android\Sdk'))
    } elseif (-not [string]::IsNullOrWhiteSpace($userProfilePath)) {
        $candidates.Add((Join-Path $userProfilePath 'Library/Android/sdk'))
        $candidates.Add((Join-Path $userProfilePath 'Android/Sdk'))
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'build-tools'))) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Android SDK build tools were not found for release verification."
}

function Resolve-AndroidBuildTool {
    param(
        [string]$AndroidSdkPath,
        [string]$ToolName
    )

    $buildToolsRoot = Join-Path $AndroidSdkPath 'build-tools'
    $candidates = Get-ChildItem -LiteralPath $buildToolsRoot -Directory |
        Sort-Object {
            try { [version]$_.Name } catch { [version]'0.0' }
        } -Descending
    $executableNames = if ($isWindowsPlatform) {
        @("$ToolName.exe", "$ToolName.bat", $ToolName)
    } else {
        @($ToolName)
    }
    foreach ($candidate in $candidates) {
        foreach ($executableName in $executableNames) {
            $toolPath = Join-Path $candidate.FullName $executableName
            if (Test-Path -LiteralPath $toolPath -PathType Leaf) {
                return $toolPath
            }
        }
    }
    throw "Android SDK tool '$ToolName' was not found for release verification."
}

function Assert-ZipArchiveEntries {
    param(
        [string]$ArchivePath,
        [string[]]$RequiredEntries
    )

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    } catch {
        throw "Release APK is not a valid ZIP archive."
    }
    try {
        if ($archive.Entries.Count -eq 0) {
            throw "Release APK is empty."
        }
        foreach ($requiredEntry in $RequiredEntries) {
            if ($null -eq $archive.GetEntry($requiredEntry)) {
                throw "Release APK is missing a required entry."
            }
        }
        $buffer = New-Object byte[] 81920
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName.EndsWith('/')) {
                continue
            }
            $stream = $entry.Open()
            try {
                while ($stream.Read($buffer, 0, $buffer.Length) -gt 0) {
                    # Reading every entry to EOF detects truncated/invalid compressed data.
                }
            } finally {
                $stream.Dispose()
            }
        }
    } finally {
        $archive.Dispose()
    }
}

function Assert-ReleaseOutputMetadata {
    param(
        [string]$MetadataPath,
        [string]$ExpectedOutputFile,
        [int]$ExpectedVersionCode,
        [string]$ExpectedVersionName
    )

    if (-not (Test-Path -LiteralPath $MetadataPath)) {
        throw "Release APK metadata was not generated."
    }
    try {
        $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
    } catch {
        throw "Release APK metadata is invalid."
    }
    $elements = @($metadata.elements)
    if ($metadata.artifactType.type -ne 'APK' -or
        $metadata.applicationId -ne $expectedPackageId -or
        $metadata.variantName -ne 'release' -or
        $elements.Count -ne 1 -or
        [string]($elements[0].outputFile) -ne $ExpectedOutputFile -or
        [long]($elements[0].versionCode) -ne [long]$ExpectedVersionCode -or
        [string]($elements[0].versionName) -cne $ExpectedVersionName) {
        throw "Release APK metadata does not match the requested production build."
    }
}

function Assert-AaptReleaseIdentity {
    param(
        [string]$Aapt2Path,
        [string]$ArtifactPath,
        [int]$ExpectedVersionCode,
        [string]$ExpectedVersionName
    )

    $badgingOutput = @(& $Aapt2Path dump badging $ArtifactPath 2>&1)
    $aaptExitCode = $LASTEXITCODE
    if ($aaptExitCode -ne 0) {
        throw "Could not inspect the release APK manifest."
    }
    $badgingText = $badgingOutput -join "`n"
    $packageMatch = [regex]::Match(
        $badgingText,
        "(?m)^package: name='(?<package>[^']+)' versionCode='(?<code>[0-9]+)' versionName='(?<name>[^']*)'"
    )
    if (-not $packageMatch.Success -or
        $packageMatch.Groups['package'].Value -ne $expectedPackageId -or
        [long]$packageMatch.Groups['code'].Value -ne [long]$ExpectedVersionCode -or
        $packageMatch.Groups['name'].Value -cne $ExpectedVersionName) {
        throw "Release APK manifest does not match the requested production build."
    }
    if ($badgingText -match '(?m)^application-debuggable(?:\s|$)' -or
        $badgingText -match '(?m)^application-testOnly(?:\s|$)') {
        throw "Release APK must be non-debuggable and non-test-only."
    }
}

function Assert-ApkSignature {
    param(
        [string]$ApkSignerPath,
        [string]$ApkPath,
        [string]$ExpectedCertificateSha256
    )

    $signatureOutput = @(& $ApkSignerPath verify --verbose --print-certs $ApkPath 2>&1)
    $signatureExitCode = $LASTEXITCODE
    if ($signatureExitCode -ne 0) {
        throw "Release APK signature verification failed."
    }
    $signatureText = $signatureOutput -join "`n"
    if ($signatureText -notmatch '(?im)^Verified using v2 scheme \(APK Signature Scheme v2\): true\s*$') {
        throw "Release APK is missing the required APK Signature Scheme v2 signature."
    }
    $certificateMatches = [regex]::Matches(
        $signatureText,
        '(?im)^(?:Signer #[0-9]+|V[0-9.]+ Signer:)\s+certificate SHA-256 digest:\s*(?<digest>[0-9a-f]{64})\s*$'
    )
    $artifactDigests = @(
        $certificateMatches |
            ForEach-Object { $_.Groups['digest'].Value.ToLowerInvariant() } |
            Sort-Object -Unique
    )
    if ($artifactDigests.Count -ne 1 -or
        $artifactDigests[0] -cne $ExpectedCertificateSha256.ToLowerInvariant()) {
        throw "Release APK signer does not match the configured release keystore."
    }
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

$isWindowsPlatform = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
$firebaseConfig = Resolve-ReviewedReleaseFirebaseConfig `
    -ProjectRoot $projectRoot `
    -ConfigPath $FirebaseConfigFile `
    -ExpectedSha256 $FirebaseConfigSha256 `
    -ExpectedPackageId $expectedPackageId `
    -IsWindowsPlatform $isWindowsPlatform
$javaExecutableName = if ($isWindowsPlatform) { "java.exe" } else { "java" }
$gradleWrapperPath = Join-Path $projectRoot $(if ($isWindowsPlatform) { "gradlew.bat" } else { "gradlew" })
$javaExePath = $null
if ($env:JAVA_HOME) {
    $candidate = Join-Path $env:JAVA_HOME "bin/$javaExecutableName"
    if (Test-Path $candidate) {
        $javaExePath = $candidate
    }
}

if (-not $javaExePath) {
    $fallbackHomes = if ($isWindowsPlatform) {
        @(
            "$env:ProgramFiles\Android\Android Studio\jbr",
            "$env:ProgramFiles\Java\jdk-21",
            "$env:ProgramFiles\Java\jdk-17"
        )
    } else {
        @(
            "/Applications/Android Studio.app/Contents/jbr/Contents/Home",
            "/opt/android-studio/jbr",
            "/usr/lib/jvm/java-21-openjdk"
        )
    }

    foreach ($javaHomeCandidate in $fallbackHomes) {
        $candidate = Join-Path $javaHomeCandidate "bin/$javaExecutableName"
        if (Test-Path $candidate) {
            $env:JAVA_HOME = $javaHomeCandidate
            $javaExePath = $candidate
            Write-Host "JAVA_HOME set from fallback path: $javaHomeCandidate"
            break
        }
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
    throw "Java not found. Set JAVA_HOME or install a JDK."
}

$javaBinPath = Split-Path -Parent $javaExePath
$keytoolExecutableName = if ($isWindowsPlatform) { 'keytool.exe' } else { 'keytool' }
$keytoolPath = Join-Path $javaBinPath $keytoolExecutableName
if (-not (Test-Path -LiteralPath $keytoolPath)) {
    throw "keytool was not found next to the selected Java runtime."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

if (-not (Test-Path $gradleWrapperPath)) {
    throw "Gradle wrapper not found at: $gradleWrapperPath"
}

$keystorePropertiesPath = Join-Path $projectRoot "keystore.properties"
if (-not (Test-Path $keystorePropertiesPath)) {
    throw "keystore.properties not found. Create a local release keystore before building release APKs."
}
$keystoreProperties = Read-ReleaseKeystoreProperties $keystorePropertiesPath
$keystorePath = $keystoreProperties['storeFile']
if (-not [System.IO.Path]::IsPathRooted($keystorePath)) {
    $keystorePath = Join-Path $projectRoot $keystorePath
}
if (-not (Test-Path -LiteralPath $keystorePath -PathType Leaf)) {
    throw "The configured release keystore file was not found."
}

$gradlePropertiesPath = Join-Path $projectRoot "gradle.properties"
if (-not (Test-Path $gradlePropertiesPath)) {
    throw "gradle.properties not found at: $gradlePropertiesPath"
}
$releaseProperties = @{}
foreach ($line in Get-Content $gradlePropertiesPath) {
    if ($line -match '^\s*([^#!\s][^=]*)=(.*)$') {
        $releaseProperties[$matches[1].Trim()] = $matches[2].Trim()
    }
}

if (-not $VersionCode) {
    $configuredVersionCode = 0
    if (-not [int]::TryParse($releaseProperties['appVersionCode'], [ref]$configuredVersionCode) -or
        $configuredVersionCode -le 0) {
        throw "appVersionCode must be a positive integer in gradle.properties or supplied with -VersionCode."
    }
    $VersionCode = $configuredVersionCode
}

if (-not $VersionName) {
    $VersionName = $releaseProperties['appVersionName']
}

if ($VersionCode -le 0 -or $VersionCode -gt 2100000000) {
    throw "VersionCode must be between 1 and 2100000000."
}
if ([string]::IsNullOrWhiteSpace($VersionName) -or
    $VersionName.Length -gt 64 -or
    $VersionName -match '[\x00-\x1F\x7F]') {
    throw "VersionName must be 1-64 visible characters."
}

Write-Host "Building phone release APK with versionCode=$VersionCode versionName=$VersionName"

& $gradleWrapperPath :app:assembleRelease "-PappVersionCode=$VersionCode" "-PappVersionName=$VersionName" "-PdevApplicationIdSuffix=false" "-PgymappRequireReviewedFirebaseConfig=true" "-PgymappFirebaseConfigFile=$($firebaseConfig.Path)" "-PgymappFirebaseConfigSha256=$($firebaseConfig.Sha256)"
if ($LASTEXITCODE -ne 0) {
    throw "Gradle build failed."
}

$phoneApkSource = Join-Path $projectRoot "app\build\outputs\apk\release\app-release.apk"
$phoneApkTarget = Join-Path $projectRoot "gymapp-phone-release.apk"

if (-not (Test-Path $phoneApkSource)) {
    throw "Phone release APK not found at: $phoneApkSource"
}

$androidSdkPath = Resolve-AndroidSdkPath $projectRoot
$aapt2Path = Resolve-AndroidBuildTool $androidSdkPath 'aapt2'
$apkSignerPath = Resolve-AndroidBuildTool $androidSdkPath 'apksigner'
$keystoreCertificateArguments = @{
    KeytoolPath = $keytoolPath
    KeystorePath = $keystorePath
    KeyAlias = $keystoreProperties['keyAlias']
    StorePassword = $keystoreProperties['storePassword']
    StoreType = $keystoreProperties['storeType']
}
$expectedCertificateSha256 = Get-ReleaseKeystoreCertificateSha256 @keystoreCertificateArguments
$apkMetadataPath = Join-Path $projectRoot 'app/build/outputs/apk/release/output-metadata.json'
Assert-ZipArchiveEntries $phoneApkSource @('AndroidManifest.xml')
$metadataArguments = @{
    MetadataPath = $apkMetadataPath
    ExpectedOutputFile = (Split-Path -Leaf $phoneApkSource)
    ExpectedVersionCode = $VersionCode
    ExpectedVersionName = $VersionName
}
Assert-ReleaseOutputMetadata @metadataArguments
Assert-AaptReleaseIdentity $aapt2Path $phoneApkSource $VersionCode $VersionName
Assert-ApkSignature $apkSignerPath $phoneApkSource $expectedCertificateSha256
$firebaseBuildConfigPath = Join-Path $projectRoot 'app/build/generated/source/buildConfig/release/com/example/gymapp/BuildConfig.java'
Assert-ReleaseFirebaseBuildConfig $firebaseBuildConfigPath $firebaseConfig
Assert-ReleaseFirebaseArtifact $phoneApkSource 'APK' $firebaseConfig

Copy-Item -Path $phoneApkSource -Destination $phoneApkTarget -Force

$metadataDir = Join-Path $projectRoot "tmp"
New-Item -ItemType Directory -Path $metadataDir -Force | Out-Null
$metadataPath = Join-Path $metadataDir "last-phone-release-apk.json"
[ordered]@{
    versionCode = $VersionCode
    versionName = $VersionName
    phoneApk = $phoneApkTarget
} | ConvertTo-Json | Set-Content -Path $metadataPath -Encoding UTF8

Write-Host "Copied phone release APK to: $phoneApkTarget"
Write-Host "Build metadata written to: $metadataPath"
Write-Host "Phone install command: adb install -r gymapp-phone-release.apk"
