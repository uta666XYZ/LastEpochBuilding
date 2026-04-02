# session-clear.ps1 - Clear session context after push (work is done)

$repoRoot = "<HOME>\Documents\GitHub\LastEpochBuilding"
$sessionFile = Join-Path $repoRoot ".claude\active_session.md"
$obsidianDir = "<HOME>\Documents\Obsidian\Last Epoch Building"
$obsidianSession = Join-Path $obsidianDir "active_session.md"

if (Test-Path $sessionFile) {
    Remove-Item $sessionFile -Force
}

if (Test-Path $obsidianSession) {
    Remove-Item $obsidianSession -Force
}

Write-Host "Session context cleared (post-push)"
