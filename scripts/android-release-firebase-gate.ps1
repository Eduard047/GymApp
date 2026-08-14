$script:ReleaseFirebaseMaxConfigBytes = 1MB
$script:ReleaseFirebaseMaxDexEntryBytes = 64MB
$script:ReleaseFirebaseMaxDexBytes = 128MB

function Get-ReleaseFirebaseSha256Hex {
    param([byte[]]$Bytes)

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($Bytes)
    } finally {
        $sha256.Dispose()
    }
    return -join ($hash | ForEach-Object { $_.ToString('x2') })
}

function Test-ReleaseFirebaseContainsServerCredential {
    param([object]$Value)

    if ($null -eq $Value) {
        return $false
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $name = [string]$key
            $child = $Value[$key]
            if ($name -in @('private_key', 'private_key_id', 'client_email', 'token_uri')) {
                return $true
            }
            if ($name -eq 'type' -and [string]$child -eq 'service_account') {
                return $true
            }
            if (Test-ReleaseFirebaseContainsServerCredential $child) {
                return $true
            }
        }
        return $false
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -in @('private_key', 'private_key_id', 'client_email', 'token_uri')) {
                return $true
            }
            if ($property.Name -eq 'type' -and [string]$property.Value -eq 'service_account') {
                return $true
            }
            if (Test-ReleaseFirebaseContainsServerCredential $property.Value) {
                return $true
            }
        }
        return $false
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        foreach ($item in $Value) {
            if (Test-ReleaseFirebaseContainsServerCredential $item) {
                return $true
            }
        }
    }
    return $false
}

function Resolve-ReviewedReleaseFirebaseConfig {
    param(
        [string]$ProjectRoot,
        [string]$ConfigPath,
        [string]$ExpectedSha256,
        [string]$ExpectedPackageId,
        [bool]$IsWindowsPlatform
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath) -or
        [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
        throw "Production Android releases require an external reviewed Firebase config and SHA-256."
    }
    if ($ExpectedSha256 -cnotmatch '^[0-9a-fA-F]{64}$') {
        throw "The reviewed Firebase config SHA-256 is invalid."
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "The reviewed Firebase config is unavailable."
    }

    $configItem = Get-Item -LiteralPath $ConfigPath -Force
    $requestedConfigPath = [System.IO.Path]::GetFullPath($configItem.FullName)
    $resolvedConfigPath = $requestedConfigPath
    try {
        $linkTarget = [System.IO.File]::ResolveLinkTarget($resolvedConfigPath, $true)
        if ($null -ne $linkTarget) {
            $resolvedConfigPath = $linkTarget.FullName
        }
    } catch {
        throw "The reviewed Firebase config path could not be resolved safely."
    }
    $resolvedConfigPath = [System.IO.Path]::GetFullPath($resolvedConfigPath)
    $resolvedProjectRoot = [System.IO.Path]::GetFullPath(
        (Resolve-Path -LiteralPath $ProjectRoot).Path
    ).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $pathComparison = if ($IsWindowsPlatform) {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }
    $projectPrefix = $resolvedProjectRoot + [System.IO.Path]::DirectorySeparatorChar
    foreach ($pathToCheck in @($requestedConfigPath, $resolvedConfigPath)) {
        if ($pathToCheck.Equals($resolvedProjectRoot, $pathComparison) -or
            $pathToCheck.StartsWith($projectPrefix, $pathComparison)) {
            throw "The reviewed Firebase config must remain outside the repository."
        }
    }

    $configInfo = Get-Item -LiteralPath $resolvedConfigPath -Force
    if ($configInfo.Length -le 0 -or $configInfo.Length -gt $script:ReleaseFirebaseMaxConfigBytes) {
        throw "The reviewed Firebase config has an invalid size."
    }
    if ($IsWindowsPlatform) {
        throw "Production Firebase release input requires Unix owner-only mode 0600; Windows ACL validation is not implemented."
    }
    try {
        $actualMode = [System.IO.File]::GetUnixFileMode($resolvedConfigPath)
    } catch {
        throw "The reviewed Firebase config permissions could not be verified."
    }
    $expectedMode = [System.IO.UnixFileMode]::UserRead -bor
        [System.IO.UnixFileMode]::UserWrite
    if ($actualMode -ne $expectedMode) {
        throw "The reviewed Firebase config must use owner-only mode 0600."
    }

    try {
        $configBytes = [System.IO.File]::ReadAllBytes($resolvedConfigPath)
    } catch {
        throw "The reviewed Firebase config could not be read."
    }
    $actualSha256 = Get-ReleaseFirebaseSha256Hex $configBytes
    if ($actualSha256 -cne $ExpectedSha256.ToLowerInvariant()) {
        throw "The reviewed Firebase config SHA-256 does not match."
    }
    try {
        $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $configText = $strictUtf8.GetString($configBytes)
        $config = $configText | ConvertFrom-Json -Depth 20
    } catch {
        throw "The reviewed Firebase config is not valid bounded UTF-8 JSON."
    }
    if ($null -eq $config -or
        $config -isnot [System.Management.Automation.PSCustomObject] -or
        (Test-ReleaseFirebaseContainsServerCredential $config)) {
        throw "The reviewed Firebase config has a forbidden server credential shape."
    }

    $projectInfo = $config.project_info
    if ($projectInfo -isnot [System.Management.Automation.PSCustomObject]) {
        throw "The reviewed Firebase config project_info must be an object."
    }
    $projectId = [string]$projectInfo.project_id
    $senderId = [string]$projectInfo.project_number
    if ($projectId -cnotmatch '^[a-z][a-z0-9-]{4,28}[a-z0-9]$' -or
        $senderId -cnotmatch '^[0-9]{6,32}$') {
        throw "The reviewed Firebase config project identity is invalid."
    }
    if ($config.client -isnot [System.Array]) {
        throw "The reviewed Firebase config client must be an array."
    }
    $clients = @($config.client)
    if ($clients.Count -ne 1) {
        throw "The reviewed Firebase config must contain exactly one Android client."
    }
    $client = $clients[0]
    if ($client -isnot [System.Management.Automation.PSCustomObject]) {
        throw "The reviewed Firebase config Android client must be an object."
    }
    $packageId = [string]$client.client_info.android_client_info.package_name
    if ($packageId -cne $ExpectedPackageId) {
        throw "The reviewed Firebase config is not the production GymApp client."
    }
    $applicationId = [string]$client.client_info.mobilesdk_app_id
    if ($client.api_key -isnot [System.Array]) {
        throw "The reviewed Firebase config api_key must be an array."
    }
    $apiKeys = @($client.api_key)
    if ($apiKeys.Count -ne 1) {
        throw "The reviewed Firebase config must contain exactly one Android API key."
    }
    if ($apiKeys[0] -isnot [System.Management.Automation.PSCustomObject]) {
        throw "The reviewed Firebase config API key must be an object."
    }
    $apiKey = [string]$apiKeys[0].current_key
    $applicationIdMatch = [regex]::Match(
        $applicationId,
        '^1:(?<sender>[0-9]{6,32}):android:[0-9a-f]{16,64}$',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $applicationIdMatch.Success -or
        $applicationIdMatch.Groups['sender'].Value -cne $senderId -or
        $apiKey -cnotmatch '^AIza[A-Za-z0-9_-]{20,200}$') {
        throw "The reviewed Firebase config client identity is invalid."
    }

    return [pscustomobject]@{
        Path = $resolvedConfigPath
        Sha256 = $actualSha256
        ProjectId = $projectId
        SenderId = $senderId
        ApplicationId = $applicationId
        ApiKey = $apiKey
    }
}

function Assert-ReleaseFirebaseBuildConfig {
    param(
        [string]$BuildConfigPath,
        [object]$FirebaseConfig
    )

    if (-not (Test-Path -LiteralPath $BuildConfigPath -PathType Leaf)) {
        throw "Release Firebase BuildConfig was not generated."
    }
    $buildConfigInfo = Get-Item -LiteralPath $BuildConfigPath
    if ($buildConfigInfo.Length -le 0 -or $buildConfigInfo.Length -gt 256KB) {
        throw "Release Firebase BuildConfig has an invalid size."
    }
    $buildConfig = Get-Content -LiteralPath $BuildConfigPath -Raw
    $requiredDeclarations = @(
        'public static final boolean FIREBASE_CONFIGURED = true;',
        "public static final String FIREBASE_PROJECT_ID = `"$($FirebaseConfig.ProjectId)`";",
        "public static final String FIREBASE_APPLICATION_ID = `"$($FirebaseConfig.ApplicationId)`";",
        "public static final String FIREBASE_API_KEY = `"$($FirebaseConfig.ApiKey)`";",
        "public static final String FIREBASE_SENDER_ID = `"$($FirebaseConfig.SenderId)`";"
    )
    foreach ($declaration in $requiredDeclarations) {
        if ($buildConfig.IndexOf($declaration, [System.StringComparison]::Ordinal) -lt 0) {
            throw "Release Firebase BuildConfig is disabled or does not match the reviewed config."
        }
    }
}

function Assert-ReleaseFirebaseArtifact {
    param(
        [string]$ArchivePath,
        [ValidateSet('AAB', 'APK')]
        [string]$ArtifactKind,
        [object]$FirebaseConfig
    )

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    } catch {
        throw "The release artifact could not be opened for Firebase verification."
    }
    try {
        foreach ($entry in $archive.Entries) {
            $entryName = [System.IO.Path]::GetFileName($entry.FullName)
            if ([regex]::IsMatch(
                $entryName,
                '^google-services.*\.json$',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
                    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
            )) {
                throw "The Firebase source JSON must not be packaged in a release artifact."
            }
            if ($entryName.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase) -and
                $entry.Length -gt 0 -and
                $entry.Length -le $script:ReleaseFirebaseMaxConfigBytes) {
                $jsonStream = $entry.Open()
                try {
                    $jsonMemory = [System.IO.MemoryStream]::new([int]$entry.Length)
                    try {
                        $jsonStream.CopyTo($jsonMemory)
                        $jsonBytes = $jsonMemory.ToArray()
                    } finally {
                        $jsonMemory.Dispose()
                    }
                } finally {
                    $jsonStream.Dispose()
                }
                if ((Get-ReleaseFirebaseSha256Hex $jsonBytes) -cne $FirebaseConfig.Sha256) {
                    $jsonText = [System.Text.Encoding]::ASCII.GetString($jsonBytes)
                    $containsReviewedIdentity = $true
                    foreach ($expectedValue in @(
                        [string]$FirebaseConfig.ProjectId,
                        [string]$FirebaseConfig.SenderId,
                        [string]$FirebaseConfig.ApplicationId,
                        [string]$FirebaseConfig.ApiKey
                    )) {
                        if ($jsonText.IndexOf($expectedValue, [System.StringComparison]::Ordinal) -lt 0) {
                            $containsReviewedIdentity = $false
                            break
                        }
                    }
                    if (-not $containsReviewedIdentity) {
                        continue
                    }
                }
                throw "The reviewed Firebase source config must not be packaged under another name."
            }
        }
        $dexPattern = if ($ArtifactKind -eq 'AAB') {
            '^base/dex/classes(?:[0-9]+)?\.dex$'
        } else {
            '^classes(?:[0-9]+)?\.dex$'
        }
        $dexEntries = @($archive.Entries | Where-Object { $_.FullName -match $dexPattern })
        if ($dexEntries.Count -eq 0) {
            throw "The release artifact has no application DEX for Firebase verification."
        }
        $expectedValues = @(
            [string]$FirebaseConfig.ProjectId,
            [string]$FirebaseConfig.SenderId,
            [string]$FirebaseConfig.ApplicationId,
            [string]$FirebaseConfig.ApiKey
        )
        $found = New-Object bool[] $expectedValues.Count
        [long]$totalDexBytes = 0
        foreach ($entry in $dexEntries) {
            if ($entry.Length -le 0 -or $entry.Length -gt $script:ReleaseFirebaseMaxDexEntryBytes) {
                throw "The release artifact DEX is outside verification bounds."
            }
            $totalDexBytes += $entry.Length
            if ($totalDexBytes -gt $script:ReleaseFirebaseMaxDexBytes) {
                throw "The release artifact DEX set is outside verification bounds."
            }
            $stream = $entry.Open()
            try {
                $memory = [System.IO.MemoryStream]::new([int]$entry.Length)
                try {
                    $stream.CopyTo($memory)
                    $dexText = [System.Text.Encoding]::ASCII.GetString($memory.ToArray())
                } finally {
                    $memory.Dispose()
                }
            } finally {
                $stream.Dispose()
            }
            for ($index = 0; $index -lt $expectedValues.Count; $index++) {
                if (-not $found[$index] -and
                    $dexText.IndexOf($expectedValues[$index], [System.StringComparison]::Ordinal) -ge 0) {
                    $found[$index] = $true
                }
            }
        }
        if ($found -contains $false) {
            throw "The release artifact does not contain the reviewed Firebase client identity."
        }
    } finally {
        $archive.Dispose()
    }
}
