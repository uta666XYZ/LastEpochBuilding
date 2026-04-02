# session-save.ps1 - Stop hook: save session context to active_session.md
# Called automatically when Claude Code stops responding

$repoRoot = "C:\Users\yobk0\Documents\GitHub\LastEpochBuilding"
$sessionFile = Join-Path $repoRoot ".claude\active_session.md"
$obsidianDir = "C:\Users\yobk0\Documents\Obsidian\Last Epoch Building"
$obsidianSession = Join-Path $obsidianDir "active_session.md"

Set-Location $repoRoot

# Gather git state
$branch = git branch --show-current 2>$null
$status = git status --short 2>$null
$recentLog = git log --oneline -5 2>$null
$diffStat = git diff --stat 2>$null
$stagedStat = git diff --cached --stat 2>$null
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Build content (keep under 30 lines)
$lines = @()
$lines += "# Active Session Context"
$lines += ""
$lines += "Updated: $timestamp"
$lines += "Branch: $branch"
$lines += ""

if ($stagedStat) {
    $lines += "## Staged Changes"
    $lines += $stagedStat | Select-Object -Last 1
    $lines += ""
}

if ($diffStat) {
    $lines += "## Unstaged Changes"
    $lines += $diffStat | Select-Object -Last 1
    $lines += ""
}

if ($status) {
    $lines += "## Modified Files"
    # Show max 10 files to keep it compact
    $statusLines = ($status -split "`n") | Select-Object -First 10
    $lines += $statusLines
    $total = ($status -split "`n").Count
    if ($total -gt 10) { $lines += "... and $($total - 10) more" }
    $lines += ""
}

$lines += "## Recent Commits"
$lines += $recentLog
$lines += ""

# Read existing session notes (the "## Session Notes" section) to preserve them
if (Test-Path $sessionFile) {
    $existing = Get-Content $sessionFile -Raw
    $notesMatch = [regex]::Match($existing, '(?s)(## Session Notes.+)')
    if ($notesMatch.Success) {
        $lines += $notesMatch.Groups[1].Value
    }
}

$content = $lines -join "`n"

# Write to .claude/active_session.md
$content | Out-File -FilePath $sessionFile -Encoding utf8 -Force

# Also copy to Obsidian vault
if (Test-Path $obsidianDir) {
    $content | Out-File -FilePath $obsidianSession -Encoding utf8 -Force
}

Write-Host "Session context saved ($timestamp)"
