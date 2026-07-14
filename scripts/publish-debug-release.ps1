param(
    [string]$TargetBranch = "test",
    [string]$CommitMessage,
    [string]$TagName,
    [string]$ReleaseTitle,
    [switch]$Draft,
    [switch]$Prerelease
)

$ErrorActionPreference = "Stop"

throw "Debug APK publication is disabled by repository security policy. Build and inspect artifacts locally; do not upload APK or AAB files to GitHub Releases."
