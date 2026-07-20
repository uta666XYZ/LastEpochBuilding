#!/usr/bin/env bash
# Run the busted spec suite locally, the way that actually works.
#
# WHY THIS EXISTS
# ---------------
# Two traps have repeatedly cost hours, and neither announces itself:
#
# 1. `.busted` sets `coverage = true` under `_all`, because CI reports coverage to
#    coveralls (see .github/workflows/test.yml). Locally that instrumentation is pure
#    tax: measured on this repo, the full suite is ~94s with --no-coverage and many
#    minutes with it, for a BYTE-IDENTICAL result (3037 ok / 16 env-only failures
#    either way). Coverage does not affect calc results.
#
# 2. Two luajit processes running the suite at once make one of them die SILENTLY:
#    exit 1, no Lua error, output truncated mid-test. It reads exactly like a hang, so
#    the natural reaction is to wait longer, which is the one thing that never helps.
#    `.busted`'s own comment records the same signature for snapshot regen ("truncated
#    at ~20KB / exit 1"). This script refuses to start in that state rather than let
#    you discover it 70 minutes later.
#
# USAGE
#   scripts/run-specs.sh                          # full suite, no coverage (fast)
#   scripts/run-specs.sh ../spec/System/Foo_spec.lua   # a subset
#   scripts/run-specs.sh --coverage               # opt in (matches CI)
#
# Everything after the flags is passed through to busted. Note .busted sets
# `directory = "src"`, so spec paths are relative to src/ -- i.e. ../spec/System/...
#
# ESCAPE HATCH
#   LEB_ALLOW_CONCURRENT_SPECS=1  -- skip the concurrency check. Only when you know the
#                                   other luajit is something you want running.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Test with -f, not -x: Git Bash does not set the executable bit on .bat files, so -x
# silently falls through to a bare `busted` that is not on PATH ("command not found").
BUSTED="$HOME/.luarocks/bin/busted.bat"
if [ ! -f "$BUSTED" ]; then
	BUSTED="$HOME/.luarocks/bin/busted"
	[ -f "$BUSTED" ] || BUSTED="busted"
fi
command -v "$BUSTED" >/dev/null 2>&1 || [ -f "$BUSTED" ] || {
	echo "busted not found (looked in ~/.luarocks/bin and PATH)" >&2; exit 127; }

COVERAGE=0
ARGS=()
for a in "$@"; do
	case "$a" in
		--coverage|-c) COVERAGE=1 ;;
		*) ARGS+=("$a") ;;
	esac
done

# --- Trap 2: refuse to race another luajit -----------------------------------------
if [ "${LEB_ALLOW_CONCURRENT_SPECS:-0}" != "1" ]; then
	others=""
	if command -v tasklist >/dev/null 2>&1; then
		others="$(tasklist 2>/dev/null | grep -ci '^luajit\.exe' || true)"
	elif command -v pgrep >/dev/null 2>&1; then
		others="$(pgrep -c luajit 2>/dev/null || true)"
	fi
	if [ -n "$others" ] && [ "$others" -gt 0 ] 2>/dev/null; then
		echo "REFUSING TO START: $others luajit process(es) already running." >&2
		echo "" >&2
		echo "  Concurrent suite runs kill each other silently (exit 1, no error," >&2
		echo "  output truncated mid-test -- it looks like a hang, not a crash)." >&2
		echo "" >&2
		echo "  Wait for the other run to finish, or if you are sure it is unrelated:" >&2
		echo "    LEB_ALLOW_CONCURRENT_SPECS=1 scripts/run-specs.sh $*" >&2
		exit 2
	fi
fi

# --- Trap 3: a green that tested nothing -------------------------------------------
# @leb-regression-guard:run-specs-no-vacuous-green
# `.busted` excludes the `builds` and `allSkills` tags by default, so asking for a
# tagged spec BY NAME runs the file's untagged tests only and exits 0 in ~5s having
# tested none of what you asked for. This guard refuses that vacuous-green state.
# Test: spec/System/TestRunSpecsNoVacuousGreen_spec.lua
EXCLUDE_TAGS="$(sed -n 's/.*\["exclude-tags"\][[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' .busted 2>/dev/null | head -1)"
if [ -z "$EXCLUDE_TAGS" ]; then
	# Never fail open in silence: if this stops parsing, the guard is dead and every
	# run below is unguarded. The spec locks the .busted format this reads.
	echo "[run-specs] WARNING: could not read exclude-tags from .busted -- the" >&2
	echo "[run-specs]          vacuous-green check is NOT active. Fix the parser." >&2
fi
asked_for_tags=0
for a in ${ARGS[@]+"${ARGS[@]}"}; do
	case "$a" in --tags*|-t) asked_for_tags=1 ;; esac
done
if [ -n "$EXCLUDE_TAGS" ] && [ "$asked_for_tags" = "0" ]; then
	IFS=',' read -ra _extags <<< "$EXCLUDE_TAGS"
	for a in ${ARGS[@]+"${ARGS[@]}"}; do
		case "$a" in -*) continue ;; esac
		f="${a#../}"                      # args are relative to src/ (.busted directory)
		[ -f "$f" ] || continue
		for t in "${_extags[@]}"; do
			# A tag only counts inside a busted block's TITLE -- `expose("... #builds",`.
			# Matching a bare "#builds" anywhere flags any file that merely mentions the
			# tag (a comment, or this guard's own spec), and a false refusal here would
			# teach everyone to reach past this check the way it teaches them to reach
			# for LEB_SKIP_CONVENTION_GATES.
			if grep -qE "^[[:space:]]*(describe|it|expose|insulate)[[:space:]]*\([[:space:]]*[\"'][^\"']*#$t([^A-Za-z0-9_-]|[\"'])" "$f"; then
				echo "REFUSING TO START: $f is tagged #$t, and .busted excludes '$EXCLUDE_TAGS'." >&2
				echo "" >&2
				echo "  Run as-is, busted would skip every #$t test, report a handful of" >&2
				echo "  untagged successes and exit 0 in a few seconds. That green means" >&2
				echo "  NOTHING was tested -- it is the failure this check exists to stop." >&2
				echo "" >&2
				echo "  Ask for the tag explicitly:" >&2
				echo "    scripts/run-specs.sh --tags=$t --exclude-tags=allSkills" >&2
				echo "" >&2
				echo "  (The corpus run takes ~900-1100s. If it finishes in seconds, it lied.)" >&2
				exit 3
			fi
		done
	done
fi

# --- Trap 4: asking for the corpus where the corpus does not exist -----------------
# @leb-regression-guard:run-specs-no-vacuous-green
# `spec/TestBuilds/` is gitignored and exists ONLY in the main repo. A worktree run of
# the builds tag enumerates zero builds and passes vacuously -- measured tell: ~100s
# instead of ~900s. Same class as Trap 3: a green with nothing behind it.
if [ "$asked_for_tags" = "1" ] && [ ! -d "spec/TestBuilds" ]; then
	for a in ${ARGS[@]+"${ARGS[@]}"}; do
		case "$a" in
			*tags=*builds*|*tags*builds*)
				echo "REFUSING TO START: you asked for the builds tag, but this checkout has" >&2
				echo "  no spec/TestBuilds/ (gitignored -- it lives only in the main repo)." >&2
				echo "" >&2
				echo "  The suite would enumerate ZERO builds and pass vacuously." >&2
				echo "  Junction the corpus in first (git ignores it):" >&2
				echo "    New-Item -ItemType Junction -Path '<this-worktree>\\spec\\TestBuilds' \\" >&2
				echo "             -Target '<main-repo>\\spec\\TestBuilds'" >&2
				echo "  Remove it after with 'cmd /c rmdir <path>' (link only -- never rm -rf:" >&2
				echo "  that can recurse into the target, and the corpus is not in git)." >&2
				exit 3
				;;
		esac
	done
fi

# --- Trap 1: coverage off unless asked ---------------------------------------------
COV_FLAG="--no-coverage"
if [ "$COVERAGE" = "1" ]; then
	COV_FLAG="--coverage"
	echo "[run-specs] coverage ON (CI parity) -- expect this to take several times longer."
else
	echo "[run-specs] coverage OFF (use --coverage for CI parity)."
fi

START=$(date +%s)
"$BUSTED" "$COV_FLAG" "${ARGS[@]+"${ARGS[@]}"}"
STATUS=$?
echo "[run-specs] finished in $(( $(date +%s) - START ))s (busted exit $STATUS)"

# A worktree has no spec/TestBuilds/ and no spec/tools/ (both gitignored), so specs that
# read them fail for environmental reasons, not because of your change. On this repo that
# is a known, stable set -- do not chase them.
if [ "$STATUS" -ne 0 ] && [ ! -d "spec/TestBuilds" ]; then
	echo "[run-specs] NOTE: no spec/TestBuilds/ here (optional local artifact)." >&2
	echo "[run-specs]       Failures reading TestBuilds snapshots or spec/tools/*.py are" >&2
	echo "[run-specs]       environmental. Compare against a clean run before blaming a diff." >&2
fi

exit $STATUS
