# generate-changelog.ps1
# Usage: .\scripts\generate-changelog.ps1 -Version "0.11.0"
#
# What this script does:
#   1. Reads feat:/fix: commits since the last git tag
#   2. Generates CHANGELOG.md and changelog.txt entries (draft for review)
#   3. Updates version in manifest.xml and changelog.txt
#
# The script ONLY writes files after you confirm the draft looks correct.

param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

# --- Validate version format ---
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error "Version must be in format X.Y.Z (e.g. 0.11.0)"
    exit 1
}

# --- Get last tag ---
$lastTag = git -C $repoRoot describe --tags --abbrev=0 2>$null
if (-not $lastTag) {
    Write-Error "No git tags found. Create an initial tag first."
    exit 1
}
Write-Host "Last tag: $lastTag"
Write-Host "New version: v$Version"
Write-Host ""

# --- Collect commits since last tag (on dev branch) ---
$rawCommits = git -C $repoRoot log "$lastTag..dev" --oneline --no-merges 2>$null

$featLines = @()
$fixLines  = @()

foreach ($line in $rawCommits) {
    # Strip the short hash prefix
    $msg = $line -replace '^\w+\s+', ''

    if ($msg -match '^feat:\s*(.+)') {
        $featLines += $Matches[1].Trim()
    }
    elseif ($msg -match '^fix:\s*(.+)') {
        $fixLines += $Matches[1].Trim()
    }
    # chore/data/docs are intentionally skipped
}

if ($featLines.Count -eq 0 -and $fixLines.Count -eq 0) {
    Write-Host "No feat: or fix: commits found since $lastTag. Nothing to generate."
    exit 0
}

# --- Build draft text ---
$today = Get-Date -Format "yyyy/MM/dd"
$ghRepo = "uta666XYZ/LastEpochBuilding"

$mdLines = @()
$mdLines += "## [v$Version](https://github.com/$ghRepo/tree/v$Version) ($today)"
$mdLines += ""
$mdLines += "[Full Changelog](https://github.com/$ghRepo/compare/$lastTag...v$Version)"
$mdLines += ""

$txLines = @()
$txLines += "VERSION[$Version][$today]"
$txLines += ""

if ($featLines.Count -gt 0) {
    $mdLines += "### New Features"
    $txLines += "--- New Features ---"
    foreach ($f in $featLines) {
        $mdLines += "- $f"
        $txLines += "- $f"
    }
    $mdLines += ""
    $txLines += ""
}

if ($fixLines.Count -gt 0) {
    $mdLines += "### Fixed"
    $txLines += "--- Fixed ---"
    foreach ($f in $fixLines) {
        $mdLines += "- $f"
        $txLines += "- $f"
    }
    $mdLines += ""
    $txLines += ""
}

# --- Show draft for review ---
Write-Host "========== DRAFT (changelog.txt format) =========="
$txLines | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "========== DRAFT (CHANGELOG.md format) =========="
$mdLines | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "NOTE: Edit the draft above by modifying this script's output, then confirm."
Write-Host ""

$confirm = Read-Host "Write these changes to files? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Aborted. No files were modified."
    exit 0
}

# --- Update manifest.xml ---
$manifestPath = Join-Path $repoRoot "manifest.xml"
$manifestContent = Get-Content $manifestPath -Raw
$oldVersion = ($manifestContent | Select-String -Pattern 'Version number="([\d.]+)"').Matches[0].Groups[1].Value
$manifestContent = $manifestContent -replace "Version number=""$oldVersion""", "Version number=""$Version"""
Set-Content $manifestPath $manifestContent -NoNewline
Write-Host "manifest.xml: $oldVersion -> $Version"

# --- Prepend to changelog.txt ---
$changelogTxtPath = Join-Path $repoRoot "changelog.txt"
$existingTxt = Get-Content $changelogTxtPath -Raw
$newTxt = ($txLines -join "`n") + "`n`n" + $existingTxt
Set-Content $changelogTxtPath $newTxt -NoNewline
Write-Host "changelog.txt: prepended v$Version section"

# --- Prepend to CHANGELOG.md ---
$changelogMdPath = Join-Path $repoRoot "CHANGELOG.md"
$existingMd = Get-Content $changelogMdPath -Raw
# Insert after the "# Changelog" header line
$newMd = $existingMd -replace "(# Changelog\s*\n)", "`$1`n" + ($mdLines -join "`n") + "`n---`n`n"
Set-Content $changelogMdPath $newMd -NoNewline
Write-Host "CHANGELOG.md: prepended v$Version section"

Write-Host ""
Write-Host "Done. Review the files, then commit and tag:"
Write-Host "  git add manifest.xml changelog.txt CHANGELOG.md"
Write-Host "  git commit -m `"chore: prepare v$Version release`""
Write-Host "  git tag v$Version"
