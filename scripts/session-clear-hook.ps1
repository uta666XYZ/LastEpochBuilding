# session-clear-hook.ps1 - PostToolUse hook: clear session after git push
# Environment: CLAUDE_TOOL_INPUT contains the Bash command that was run

$input = $env:CLAUDE_TOOL_INPUT
if ($input -and $input -match 'git\s+push') {
    $repoRoot = "C:\Users\yobk0\Documents\GitHub\LastEpochBuilding"
    $sessionFile = Join-Path $repoRoot ".claude\active_session.md"
    $obsidianSession = "C:\Users\yobk0\Documents\Obsidian\Last Epoch Building\active_session.md"

    if (Test-Path $sessionFile) { Remove-Item $sessionFile -Force }
    if (Test-Path $obsidianSession) { Remove-Item $obsidianSession -Force }

    Write-Host "Session context cleared (post-push)"
}
