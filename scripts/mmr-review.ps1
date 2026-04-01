<#
.SYNOPSIS
    MMR Review Helper - Prepares git diff for Claude review after Qwen edits.
.DESCRIPTION
    Generates a compact diff summary suitable for pasting into Claude Code
    to minimize token consumption during review.
.USAGE
    .\scripts\mmr-review.ps1                  # diff against dev
    .\scripts\mmr-review.ps1 -Base main       # diff against main
    .\scripts\mmr-review.ps1 -Full            # include full diff (not just stat)
#>

param(
    [string]$Base = "dev",
    [switch]$Full,
    [switch]$Check
)

$ErrorActionPreference = "Stop"

# --- CJK Check ---
if ($Check -or $true) {
    Write-Host "=== CJK Character Check ===" -ForegroundColor Cyan
    $diffContent = git diff $Base -- '*.lua' '*.json' 2>$null
    if ($diffContent) {
        $cjkPattern = '[\u4E00-\u9FFF\u3040-\u309F\u30A0-\u30FF\uFF00-\uFFEF]'
        $lines = $diffContent -split "`n"
        $cjkFound = $false
        foreach ($line in $lines) {
            if ($line -match '^\+' -and $line -match $cjkPattern) {
                Write-Host "  WARNING: CJK found: $line" -ForegroundColor Red
                $cjkFound = $true
            }
        }
        if (-not $cjkFound) {
            Write-Host "  OK: No CJK characters in added lines" -ForegroundColor Green
        }
    } else {
        Write-Host "  No lua/json changes found" -ForegroundColor Yellow
    }
    Write-Host ""
}

# --- Diff Summary ---
Write-Host "=== Diff Summary ($Base...HEAD) ===" -ForegroundColor Cyan
git diff --stat $Base
Write-Host ""

# --- File list for Claude review prompt ---
Write-Host "=== Claude Review Prompt ===" -ForegroundColor Cyan
$stats = git diff --stat $Base | Select-Object -SkipLast 1
$fileCount = ($stats | Measure-Object).Count

Write-Host @"
--- Copy below into Claude Code ---

Review these Qwen-made changes ($fileCount files).
Check for: logic errors, LE domain correctness, pattern consistency.

``````
$(git diff --stat $Base)
``````

"@

if ($Full) {
    Write-Host "Full diff:"
    Write-Host '```'
    git diff $Base
    Write-Host '```'
} else {
    Write-Host "(Run with -Full to include complete diff)" -ForegroundColor DarkGray
    Write-Host ""
    # Show compact diff (added/removed lines only, no context)
    Write-Host "=== Compact Diff (changes only) ===" -ForegroundColor Cyan
    git diff $Base -U0 --no-color
}
