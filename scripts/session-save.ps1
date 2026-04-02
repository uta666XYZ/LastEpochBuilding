# session-save.ps1 - Stop hook: save session context to active_session.md
# Called automatically when Claude Code stops responding

$repoRoot = "C:\Users\yobk0\Documents\GitHub\LastEpochBuilding"
$sessionFile = Join-Path $repoRoot ".claude\active_session.md"
$obsidianDir = "C:\Users\yobk0\Documents\Obsidian\Last Epoch Building"
$obsidianSession = Join-Path $obsidianDir "active_session.md"
$logFile = Join-Path $repoRoot ".claude\session-hook.log"

# Detect worktree: use CLAUDE_WORKING_DIRECTORY if available, else try CWD
$workDir = $env:CLAUDE_WORKING_DIRECTORY
if (-not $workDir) { $workDir = $PWD.Path }

# If workDir looks like a worktree, use it; otherwise use repoRoot
if ($workDir -match '\.claude[\\/]worktrees[\\/]') {
    $gitDir = $workDir
} else {
    $gitDir = $repoRoot
}

Set-Location $gitDir

# Gather git state from actual working directory
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
$lines += "WorkDir: $gitDir"
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

# Log for debugging (append, keep last 20 lines)
$logEntry = "$timestamp | Branch: $branch | WorkDir: $gitDir | OK"
$logEntry | Out-File -FilePath $logFile -Encoding utf8 -Append
# Trim log to last 20 lines
if (Test-Path $logFile) {
    $logLines = Get-Content $logFile
    if ($logLines.Count -gt 20) {
        $logLines | Select-Object -Last 20 | Out-File -FilePath $logFile -Encoding utf8 -Force
    }
}

Write-Host "Session context saved ($timestamp) from $gitDir"
