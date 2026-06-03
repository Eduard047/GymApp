param(
    [string]$TargetBranch = "test",
    [string]$CommitMessage,
    [string]$TagName,
    [string]$ReleaseTitle,
    [switch]$Draft,
    [switch]$Prerelease
)

$ErrorActionPreference = "Stop"
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $projectRoot

$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghCommand) {
    throw "GitHub CLI not found. Install gh or add it to PATH."
}

$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCommand) {
    throw "Git not found. Install git or add it to PATH."
}

git fetch origin
if ($LASTEXITCODE -ne 0) {
    throw "git fetch failed."
}

$localBranchExists = (& git branch --list $TargetBranch).Trim()
$remoteBranchExists = (& git branch --remotes --list "origin/$TargetBranch").Trim()
if ($localBranchExists) {
    git switch $TargetBranch
} elseif ($remoteBranchExists) {
    git switch --track "origin/$TargetBranch"
} else {
    git switch -c $TargetBranch
}

if ($LASTEXITCODE -ne 0) {
    throw "Could not switch to branch: $TargetBranch"
}

& (Join-Path $PSScriptRoot "build-update-apk.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "APK build failed."
}

$metadataPath = Join-Path $projectRoot "tmp\last-build-apk.json"
if (-not (Test-Path $metadataPath)) {
    throw "Build metadata not found at: $metadataPath"
}

$metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
$phoneApk = $metadata.phoneApk
$watchApk = $metadata.watchApk

if (-not (Test-Path $phoneApk)) {
    throw "Phone APK not found at: $phoneApk"
}

if (-not (Test-Path $watchApk)) {
    throw "Watch APK not found at: $watchApk"
}

$currentBranch = (& git branch --show-current).Trim()
if (-not $currentBranch) {
    throw "Could not determine the current git branch."
}

if ($currentBranch -ne $TargetBranch) {
    throw "Expected branch '$TargetBranch', but current branch is '$currentBranch'."
}

if (-not $TagName) {
    $TagName = "debug-$($metadata.versionName)"
}

if (-not $ReleaseTitle) {
    $ReleaseTitle = "Debug APKs $($metadata.versionName)"
}

if (-not $CommitMessage) {
    $CommitMessage = "Update debug APK release $($metadata.versionName)"
}

git add -A
if ($LASTEXITCODE -ne 0) {
    throw "git add failed."
}

$stagedChanges = (& git diff --cached --name-only)
if ($stagedChanges) {
    git commit -m $CommitMessage
    if ($LASTEXITCODE -ne 0) {
        throw "git commit failed."
    }
} else {
    Write-Host "No tracked code changes to commit."
}

git push -u origin $TargetBranch
if ($LASTEXITCODE -ne 0) {
    throw "git push failed."
}

$existingRelease = (& gh release view $TagName --json tagName 2>$null)
if ($LASTEXITCODE -eq 0 -and $existingRelease) {
    gh release upload $TagName $phoneApk $watchApk --clobber
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub release upload failed."
    }
    Write-Host "Updated GitHub release assets for tag: $TagName"
} else {
    $releaseArgs = @(
        "release",
        "create",
        $TagName,
        $phoneApk,
        $watchApk,
        "--title",
        $ReleaseTitle,
        "--notes",
        "Debug APK build with versionCode=$($metadata.versionCode) versionName=$($metadata.versionName)."
    )

    if ($Draft) {
        $releaseArgs += "--draft"
    }

    if ($Prerelease) {
        $releaseArgs += "--prerelease"
    }

    gh @releaseArgs
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub release creation failed."
    }
    Write-Host "Created GitHub release: $TagName"
}

Write-Host "Published branch: $TargetBranch"
Write-Host "Release tag: $TagName"
