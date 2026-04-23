# claude-bisio SessionStart hook (Windows).
# Writes banner directly to the console host. Never touches stdout.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $bannerPath = Join-Path $PSScriptRoot 'banner.txt'
    if (-not (Test-Path $bannerPath)) { exit 0 }

    $banner = Get-Content -Raw -Path $bannerPath

    # Write-Host bypasses the PowerShell success stream (stdout)
    # and renders directly to the host — invisible to CC's hook capture.
    Write-Host ""
    Write-Host $banner
    Write-Host ""
} catch {
    # Never block session start.
}

exit 0
