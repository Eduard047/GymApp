param(
    [string]$DeveloperKey = $env:GARMIN_DEVELOPER_KEY,
    [string]$Device = 'fenix8solar47mm',
    [string]$ExpectedPublicKeySha256 = $env:GARMIN_RELEASE_PUBLIC_KEY_SHA256,
    [switch]$Release,
    [switch]$CompileOnly
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7 or newer is required. Install it, then run: pwsh -File .\scripts\build-garmin.ps1'
}

$trustedReleasePublicKeySha256 = '926b106c47125ddc97aef9801ffd4812f54562140122bb30f792493ed92adb47'
$projectRoot = Split-Path -Parent $PSScriptRoot
$garminRoot = Join-Path $projectRoot 'garmin'
$outputRoot = Join-Path $garminRoot 'build'

if ($Release -and $CompileOnly) {
    throw 'Choose at most one mode: -Release or -CompileOnly.'
}

if (-not $DeveloperKey) {
    $localDeveloperKey = Join-Path (Join-Path $projectRoot 'garmin-keys') 'developer_key.der'
    if (Test-Path -LiteralPath $localDeveloperKey -PathType Leaf) {
        $DeveloperKey = $localDeveloperKey
    }
}
if (-not $DeveloperKey -or -not (Test-Path -LiteralPath $DeveloperKey -PathType Leaf)) {
    throw 'Set GARMIN_DEVELOPER_KEY to your Garmin developer_key.der file or pass -DeveloperKey.'
}

function Get-GarminReleaseKeyIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    [byte[]]$keyBytes = [System.IO.File]::ReadAllBytes($Path)
    if ($keyBytes.Length -lt 512 -or $keyBytes.Length -gt 32768) {
        throw 'Garmin release developer key has an invalid DER size.'
    }

    $rsa = [System.Security.Cryptography.RSA]::Create()
    try {
        $bytesRead = 0
        try {
            $rsa.ImportPkcs8PrivateKey($keyBytes, [ref]$bytesRead)
        } catch {
            $rsa.Dispose()
            $rsa = [System.Security.Cryptography.RSA]::Create()
            $bytesRead = 0
            try {
                $rsa.ImportRSAPrivateKey($keyBytes, [ref]$bytesRead)
            } catch {
                throw 'Garmin release developer key must be a valid DER private key.'
            }
        }
        if ($bytesRead -ne $keyBytes.Length) {
            throw 'Garmin release developer key contains trailing data.'
        }
        [byte[]]$publicKey = $rsa.ExportSubjectPublicKeyInfo()
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            [byte[]]$digest = $sha256.ComputeHash($publicKey)
        } finally {
            $sha256.Dispose()
        }
        [pscustomobject]@{
            KeySize = $rsa.KeySize
            PublicKeySha256 = ([System.BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
        }
    } finally {
        $rsa.Dispose()
    }
}

$javaCommand = Get-Command java -ErrorAction SilentlyContinue
$javaWorks = $false
$javaPath = $null
if ($javaCommand) {
    & $javaCommand.Source -version 2>$null
    $javaWorks = $LASTEXITCODE -eq 0
    if ($javaWorks) { $javaPath = $javaCommand.Source }
}
if (-not $javaWorks) {
    $jbrCandidates = if ($env:OS -eq 'Windows_NT') {
        @($env:JAVA_HOME, 'C:\Program Files\Android\Android Studio\jbr')
    } else {
        @($env:JAVA_HOME, '/Applications/Android Studio.app/Contents/jbr/Contents/Home')
    }
    $jbrCandidates = $jbrCandidates | Where-Object { $_ }
    foreach ($jbr in $jbrCandidates) {
        $javaName = if ($env:OS -eq 'Windows_NT') { 'java.exe' } else { 'java' }
        $candidateJavaPath = Join-Path (Join-Path $jbr 'bin') $javaName
        if (Test-Path -LiteralPath $candidateJavaPath -PathType Leaf) {
            $env:JAVA_HOME = $jbr
            $env:Path = "$(Join-Path $jbr 'bin')$([IO.Path]::PathSeparator)$env:Path"
            $javaWorks = $true
            $javaPath = $candidateJavaPath
            break
        }
    }
}
if (-not $javaWorks -or -not $javaPath) {
    throw 'Java not found. Install a JDK or Android Studio before building the Garmin app.'
}
if (
    [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::OSX
    ) -and
    $env:JAVA_TOOL_OPTIONS -notmatch '(?:^|\s)-Djava\.awt\.headless='
) {
    $env:JAVA_TOOL_OPTIONS = if ($env:JAVA_TOOL_OPTIONS) {
        "$env:JAVA_TOOL_OPTIONS -Djava.awt.headless=true"
    } else {
        '-Djava.awt.headless=true'
    }
}

$userProfile = [Environment]::GetFolderPath('UserProfile')
$connectIqRoot = if ($env:APPDATA) {
    Join-Path $env:APPDATA 'Garmin\ConnectIQ'
} else {
    Join-Path $userProfile 'Library/Application Support/Garmin/ConnectIQ'
}

$monkeycCommand = Get-Command monkeyc -ErrorAction SilentlyContinue
$monkeycPath = if ($monkeycCommand) { $monkeycCommand.Source } else { $null }
$sdkPath = $null
if (-not $monkeycPath) {
    $currentSdk = Join-Path $connectIqRoot 'current-sdk.cfg'
    if (Test-Path -LiteralPath $currentSdk -PathType Leaf) {
        $sdkPath = (Get-Content $currentSdk -Raw).Trim()
        $monkeycName = if ($env:OS -eq 'Windows_NT') { 'monkeyc.bat' } else { 'monkeyc' }
        $candidate = Join-Path (Join-Path $sdkPath 'bin') $monkeycName
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $monkeycPath = $candidate
        }
    }
}
if (-not $sdkPath -and $monkeycPath) {
    $sdkPath = Split-Path -Parent (Split-Path -Parent $monkeycPath)
}
if (-not $monkeycPath) {
    throw 'Connect IQ SDK not found. Install it with Garmin Connect IQ SDK Manager, then run this script again.'
}

$deviceRoot = Join-Path $connectIqRoot 'Devices'
if (-not $Release) {
    $devicePath = Join-Path $deviceRoot $Device
    if (-not (Test-Path -LiteralPath $devicePath -PathType Container)) {
        throw "Connect IQ device '$Device' is not installed. Open Garmin SDK Manager, install the device package, then rerun with -Device $Device."
    }
}

if ($Release) {
    $localFingerprintPath = Join-Path (Join-Path $projectRoot 'garmin-keys') 'release_public_key.sha256'
    if ([string]::IsNullOrWhiteSpace($ExpectedPublicKeySha256) -and
        (Test-Path -LiteralPath $localFingerprintPath -PathType Leaf)) {
        if ((Get-Item -LiteralPath $localFingerprintPath).Length -gt 256) {
            throw 'Local Garmin release fingerprint file is malformed.'
        }
        $ExpectedPublicKeySha256 = Get-Content -LiteralPath $localFingerprintPath -Raw
    }
    $expectedFingerprint = if ([string]::IsNullOrWhiteSpace($ExpectedPublicKeySha256)) {
        $trustedReleasePublicKeySha256
    } else {
        ($ExpectedPublicKeySha256 -replace '[:\s]', '').ToLowerInvariant()
    }
    if ($expectedFingerprint -notmatch '^[0-9a-f]{64}$') {
        throw 'Expected Garmin release public-key SHA-256 must contain exactly 64 hexadecimal digits.'
    }
    if ($expectedFingerprint -cne $trustedReleasePublicKeySha256) {
        throw 'Expected Garmin release signer does not match the pinned Store identity.'
    }
    $keyIdentity = Get-GarminReleaseKeyIdentity -Path $DeveloperKey
    if ($keyIdentity.KeySize -ne 4096) {
        throw 'Garmin release developer key must use RSA-4096.'
    }
    if ($keyIdentity.PublicKeySha256 -cne $expectedFingerprint) {
        throw 'Garmin release developer key does not match the trusted public-key fingerprint.'
    }
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$outputName = if ($Release) { 'gymapp-garmin-connect-iq.iq' } else { "gymapp-$Device.prg" }
$output = Join-Path $outputRoot $outputName
$releaseStagingRoot = $null
if ($Release) {
    $releaseStagingRoot = Join-Path $outputRoot (
        '.gymapp-garmin-release-' + [Guid]::NewGuid().ToString('N')
    )
    $rawReleaseRoot = Join-Path $releaseStagingRoot 'raw'
    $sanitizedReleaseRoot = Join-Path $releaseStagingRoot 'sanitized'
    [System.IO.Directory]::CreateDirectory($rawReleaseRoot) | Out-Null
    [System.IO.Directory]::CreateDirectory($sanitizedReleaseRoot) | Out-Null
    # monkeyc derives every internal PRG filename from the -o leaf name. Keep
    # that leaf canonical while isolating raw and sanitized packages by folder.
    $temporaryOutput = Join-Path $rawReleaseRoot $outputName
    $sanitizedReleaseOutput = Join-Path $sanitizedReleaseRoot $outputName
} else {
    $temporaryOutput = Join-Path $outputRoot ".gymapp-$Device.$PID.prg"
    $sanitizedReleaseOutput = $null
}
$temporarySettings = $null
$temporaryDebug = $null
if (Test-Path -LiteralPath $temporaryOutput) {
    Remove-Item -LiteralPath $temporaryOutput -Force
}
if ($sanitizedReleaseOutput -and (Test-Path -LiteralPath $sanitizedReleaseOutput)) {
    Remove-Item -LiteralPath $sanitizedReleaseOutput -Force
}
if (-not $Release) {
    $temporaryBase = $temporaryOutput.Substring(0, $temporaryOutput.Length - 4)
    $temporarySettings = "$temporaryBase-settings.json"
    $temporaryDebug = "$temporaryOutput.debug.xml"
    foreach ($temporarySidecar in @($temporarySettings, $temporaryDebug)) {
        if ([System.IO.File]::Exists($temporarySidecar)) {
            Remove-Item -LiteralPath $temporarySidecar -Force
        }
    }
}
$compilerArgs = @(
    '-f', 'monkey.jungle',
    '-y', $DeveloperKey,
    '-o', $temporaryOutput,
    '-w'
)
if ($Release) {
    $compilerArgs += @('-r', '-e')
} else {
    $compilerArgs += @('-d', $Device)
    # CIQ 3.4 watch apps on these products have a 96 KiB ceiling. SDK 9.2 debug
    # metadata exceeds that cap even though the compact runtime code fits.
    $lowMemoryDevices = @(
        'descentg1',
        'instinct2',
        'instinct2s',
        'instinct2x',
        'instinctcrossover'
    )
    if ($lowMemoryDevices -contains $Device) {
        $compilerArgs += '-r'
    }
}

$releaseGateFailure = $null
try {
    Push-Location $garminRoot
    try {
        if ($Release) {
            $releaseGateFailure = 'Garmin release compilation failed.'
            & $monkeycPath @compilerArgs *> $null
            if ($LASTEXITCODE -ne 0) {
                throw [System.InvalidOperationException]::new('Release gate failed.')
            }
            $releaseGateFailure = $null
        } else {
            & $monkeycPath @compilerArgs
            if ($LASTEXITCODE -ne 0) {
                throw "Garmin build failed with exit code $LASTEXITCODE"
            }
        }
    } finally {
        Pop-Location
    }

    if (-not [System.IO.File]::Exists($temporaryOutput) -or
        ([System.IO.FileInfo]::new($temporaryOutput)).Length -le 0) {
        if ($Release) {
            $releaseGateFailure = 'Garmin release compiler did not produce an output.'
            throw [System.InvalidOperationException]::new('Release gate failed.')
        }
        throw 'Garmin compiler did not produce a non-empty output.'
    }
    if ($Release) {
        $monkeybrainsPath = Join-Path (Join-Path $sdkPath 'bin') 'monkeybrains.jar'
        $verifierPath = Join-Path $projectRoot 'scripts/VerifyGarminIq.java'
        if (-not (Test-Path -LiteralPath $monkeybrainsPath -PathType Leaf)) {
            $releaseGateFailure = 'Connect IQ SDK package reader not found; release readback cannot run.'
            throw [System.InvalidOperationException]::new('Release gate failed.')
        }
        $releaseGateFailure = 'Garmin IQ debug-path sanitization failed.'
        & $javaPath '-cp' $monkeybrainsPath $verifierPath '--sanitize-debug-paths' $temporaryOutput $sanitizedReleaseOutput $projectRoot *> $null
        if ($LASTEXITCODE -ne 0) {
            throw [System.InvalidOperationException]::new('Release gate failed.')
        }
        $releaseGateFailure = $null
        if (-not [System.IO.File]::Exists($sanitizedReleaseOutput) -or
            ([System.IO.FileInfo]::new($sanitizedReleaseOutput)).Length -le 0) {
            $releaseGateFailure = 'Garmin IQ sanitization did not produce a non-empty output.'
            throw [System.InvalidOperationException]::new('Release gate failed.')
        }
        $releaseGateFailure = 'Garmin IQ structural/signature readback failed.'
        & $javaPath '-cp' $monkeybrainsPath $verifierPath $sanitizedReleaseOutput *> $null
        if ($LASTEXITCODE -ne 0) {
            throw [System.InvalidOperationException]::new('Release gate failed.')
        }
        $releaseGateFailure = $null
        $releaseGateFailure = 'Garmin IQ atomic output replacement failed.'
        [System.IO.File]::Move($sanitizedReleaseOutput, $output, $true)
        $sanitizedReleaseOutput = $null
        $releaseGateFailure = $null
    } else {
        $finalBase = $output.Substring(0, $output.Length - 4)
        if ([System.IO.File]::Exists($temporarySettings)) {
            [System.IO.File]::Move($temporarySettings, "$finalBase-settings.json", $true)
        }
        if ([System.IO.File]::Exists($temporaryDebug)) {
            [System.IO.File]::Move($temporaryDebug, "$output.debug.xml", $true)
        }
        [System.IO.File]::Move($temporaryOutput, $output, $true)
    }
} catch {
    if (-not $releaseGateFailure) {
        throw
    }
} finally {
    if (Test-Path -LiteralPath $temporaryOutput -PathType Leaf) {
        Remove-Item -LiteralPath $temporaryOutput -Force
    }
    if ($sanitizedReleaseOutput -and
        (Test-Path -LiteralPath $sanitizedReleaseOutput -PathType Leaf)) {
        Remove-Item -LiteralPath $sanitizedReleaseOutput -Force
    }
    foreach ($temporarySidecar in @($temporarySettings, $temporaryDebug)) {
        if ($temporarySidecar -and [System.IO.File]::Exists($temporarySidecar)) {
            Remove-Item -LiteralPath $temporarySidecar -Force
        }
    }
    if ($releaseStagingRoot -and
        [System.IO.Directory]::Exists($releaseStagingRoot)) {
        [System.IO.Directory]::Delete($releaseStagingRoot, $true)
    }
}
if ($releaseGateFailure) {
    [Console]::Error.WriteLine($releaseGateFailure)
    exit 1
}

if ($Release) {
    Write-Host 'Garmin build: garmin/build/gymapp-garmin-connect-iq.iq'
} else {
    Write-Host "Garmin build: $output"
}
