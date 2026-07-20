<#
.SYNOPSIS
    Create a new Claude Code worktree with .claude/settings.local.json pre-installed.

.DESCRIPTION
    `git worktree add` does not copy gitignored files (.claude/ is gitignored), so newly
    created worktrees start without bypassPermissions / deny rules. This wrapper:
      1. Creates the worktree under .claude/worktrees/<name> from origin/dev
      2. Copies the project root .claude/settings.local.json into the new worktree
      3. Validates the JSON

.USAGE
    .\scripts\new-claude-worktree.ps1 <name>
    .\scripts\new-claude-worktree.ps1 -Name <name> [-Base origin/dev]

.EXAMPLE
    .\scripts\new-claude-worktree.ps1 my-task
    # -> .claude/worktrees/my-task on branch claude/my-task, settings copied
#>

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$Name,

    [string]$Base = "origin/dev"
)

$ErrorActionPreference = "Stop"

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    $repoRoot = git rev-parse --git-common-dir 2>$null | Split-Path
}
if (-not $repoRoot) {
    Write-Host "ERROR: not inside a git repo" -ForegroundColor Red
    exit 1
}

$srcSettings = Join-Path $repoRoot ".claude\settings.local.json"
if (-not (Test-Path $srcSettings)) {
    Write-Host "ERROR: source settings not found: $srcSettings" -ForegroundColor Red
    exit 1
}

$wtPath     = Join-Path $repoRoot ".claude\worktrees\$Name"
$branchName = "claude/$Name"
$dstSettings = Join-Path $wtPath ".claude\settings.local.json"

if (Test-Path $wtPath) {
    Write-Host "ERROR: worktree path already exists: $wtPath" -ForegroundColor Red
    exit 1
}

Write-Host "Fetching $Base..." -ForegroundColor Cyan
git -C $repoRoot fetch origin dev | Out-Null

Write-Host "Creating worktree: $wtPath (branch $branchName from $Base)" -ForegroundColor Cyan
git -C $repoRoot worktree add -b $branchName $wtPath $Base
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: git worktree add failed" -ForegroundColor Red
    exit 1
}

$dstDir = Split-Path $dstSettings -Parent
if (-not (Test-Path $dstDir)) {
    New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
}

Copy-Item $srcSettings $dstSettings -Force
try {
    Get-Content $dstSettings -Raw | ConvertFrom-Json | Out-Null
    Write-Host "Settings copied + JSON valid: $dstSettings" -ForegroundColor Green
} catch {
    Write-Host "WARNING: copied settings failed JSON validation: $_" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Done. cd into worktree:" -ForegroundColor Green
Write-Host "  cd `"$wtPath`""
