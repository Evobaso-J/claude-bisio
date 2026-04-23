# claude-bisio SessionStart hook (Windows).
# Picks a banner tier matching the terminal's dimensions.
# Writes to the console host so stdout stays empty (zero model-context cost).

$ErrorActionPreference = 'SilentlyContinue'

try {
    $cols = try { $Host.UI.RawUI.WindowSize.Width }  catch { 80 }
    $rows = try { $Host.UI.RawUI.WindowSize.Height } catch { 24 }

    $tier = switch ($true) {
        (($rows -ge 55) -and ($cols -ge 90))  { 'lg'; break }
        (($rows -ge 40) -and ($cols -ge 65))  { 'md'; break }
        (($rows -ge 30) -and ($cols -ge 48))  { 'sm'; break }
        default                                { 'xs' }
    }

    $bannerPath = Join-Path $PSScriptRoot "banner-$tier.txt"
    if (-not (Test-Path $bannerPath)) {
        $bannerPath = Join-Path $PSScriptRoot 'banner-xs.txt'
    }
    if (-not (Test-Path $bannerPath)) { exit 0 }

    $banner = Get-Content -Raw -Path $bannerPath

    Write-Host ""
    Write-Host $banner
    Write-Host ""
} catch {
    # Never block session start.
}

exit 0
