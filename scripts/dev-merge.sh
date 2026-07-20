#!/bin/sh
# @leb-dev-merge-guard
# Deliberate gate for merging a feature branch into LOCAL 'dev'.
#
#   sh scripts/dev-merge.sh <branch>            -> PREVIEW then STOP (default)
#   sh scripts/dev-merge.sh <branch> --confirm  -> actually merge (--no-ff)
#
# The default run prints the commits / files / pre-merge checklist and STOPS
# without touching dev. Only --confirm sets LEB_DEV_MERGE_OK=1 (which the
# pre-merge-commit hook requires) and performs `git merge --no-ff`. This is the
# only sanctioned path; a bare `git merge <branch>` into dev is blocked by the
# hook. After a successful merge, NOTIFY the user (SHA + suite + blast, 1 line).
#
# HUMAN-IN-THE-LOOP GATE: even --confirm does not merge on its own. A live
# operator must type the exact branch name into /dev/tty. Non-interactive callers
# fail closed unless LEB_DEV_MERGE_HUMAN_OK=1 was explicitly authorized for this
# one merge. The override is never standing or blanket authorization.
set -e

BRANCH="$1"
CONFIRM="$2"

if [ -z "$BRANCH" ]; then
	echo "usage: sh scripts/dev-merge.sh <branch> [--confirm]" >&2
	exit 2
fi

CUR=$(git symbolic-ref --short HEAD 2>/dev/null)
if [ "$CUR" != "dev" ]; then
	echo "STOP: current branch is '$CUR', not 'dev'. Run from the repo with dev checked out." >&2
	exit 2
fi
if ! git rev-parse --verify --quiet "$BRANCH" >/dev/null; then
	echo "STOP: branch '$BRANCH' not found." >&2
	exit 2
fi
if git merge-base --is-ancestor "$BRANCH" HEAD 2>/dev/null; then
	echo "Nothing to do: '$BRANCH' is already contained in dev." >&2
	exit 0
fi

echo "=== dev-merge gate: $BRANCH -> dev ==="
echo "--- commits (dev..$BRANCH) ---"
git log --oneline "dev..$BRANCH"
echo "--- files changed ---"
git diff --stat "dev..$BRANCH"
echo "--- pre-merge checklist (confirm each BEFORE --confirm) ---"
echo "  [ ] relevant guard spec(s) GREEN"
echo "  [ ] gitleaks clean (pre-commit enforces; re-check if unsure)"
echo "  [ ] corpus blast known: snapshot regen done, OR corpus-neutral"

# ---------------------------------------------------------------------------
# @leb-dev-merge-guard: automated convention gates (fail-closed, added 2026-07-17)
#
# WHY THESE ARE HERE AND NOT ELSEWHERE.
# The 3-layer guard convention was violated on THREE consecutive branches
# (2026-07-16/17) by three different sessions -- one of them the session that had
# just re-read the convention note. Documentation demonstrably does not hold this
# line.
#
# The scrub rule already HAD a gate: scripts/hooks/pre-push-guard-internal-block.sh.
# But it fires on `git push`, and local dev is NEVER pushed (see
# project_no_push_public_mainline_lock) -- so it had never fired for local work at
# all. The leak would only surface at release, from CI, long after the fact. This
# merge is the one choke point every change actually passes through.
#
# Both gates are DELTA gates: they judge only the lines the branch ADDS. dev already
# carries pre-existing HIGH findings (avalanche RVA refs), and a blanket "tree must
# be clean" gate would block every merge forever and get disabled within a day.
# Their job is to block re-growth, not to force unrelated cleanup during a merge.
#
# Escape hatch: LEB_SKIP_CONVENTION_GATES=1 (say why in the merge notification).
# ---------------------------------------------------------------------------
if [ "${LEB_SKIP_CONVENTION_GATES:-0}" != "1" ]; then
	# Exclusions, each for a reason -- do not prune them:
	#   src/Data, src/TreeData  -- JSON DATA VALUES. In-game ability tooltip text lives
	#                              here (e.g. "disassembles"); neutralizing a data value
	#                              would corrupt game data. Never scan these.
	#   guard-forensic-archive  -- the neutralizer's own local archive of originals.
	#   scripts/dev-merge.sh    -- THIS FILE. Its own pattern string necessarily contains
	#                              the very tokens it hunts for (verified: 2 self-hits),
	#                              so without this a future edit to the gate blocks itself.
	ADDED=$(git diff "dev...$BRANCH" -- \
		':(exclude)src/Data' ':(exclude)src/TreeData' \
		':(exclude)scripts/guard-forensic-archive' ':(exclude)scripts/dev-merge.sh' \
		| grep '^+' | grep -v '^+++' || true)

	# Gate 1 -- internal RE forensics must not enter tracked source.
	# Match `decompil` WITH the l: decompose/decomposition are legitimate English and
	# constant in DPS analysis. src/Data and src/TreeData are excluded above so
	# in-game tooltip strings in JSON data values (e.g. "disassembles") are never hit.
	LEAK=$(printf '%s\n' "$ADDED" \
		| grep -nE 'dump\.cs|RVA 0x|il2cpp|Ghidra|decompil|disasm|GameAssembly|decompiled_[0-9]|@0x[0-9a-fA-F]{2,}' \
		|| true)
	if [ -n "$LEAK" ]; then
		echo "" >&2
		echo "BLOCKED: this branch bakes internal RE forensics into tracked files." >&2
		echo "  This is a public repository. Move reproduction details to maintainer notes." >&2
		echo "  Replace (don't delete) with 'datamined game source' / 'datamined offset':" >&2
		echo "    python scripts/neutralize-guard-forensic.py --all-comments --apply <file>" >&2
		echo "    (.md is whole-file mode and needs an explicit --md; diff the result)" >&2
		echo "  Verify with: python scripts/scan-guard-internal-info.py --strict" >&2
		echo "" >&2
		printf '%s\n' "$LEAK" | head -12 >&2
		echo "" >&2
		echo "  (override: LEB_SKIP_CONVENTION_GATES=1, and say why in the notification)" >&2
		exit 4
	fi

	# Gate 2 -- a NEW guard section must be compact AND must really have 3 layers.
	# @leb-regression-guard: dev-merge-guard-gate-matching
	# The two layer lookups below must stay tolerant of every inline marker spelling
	# in the tree, and must keep Layer 1 = non-test code / Layer 2 = *_spec.lua.
	# Narrowing either one turns this fail-closed gate into a blocker for correct
	# work. Locked by spec/System/TestDevMergeGuardGateMatching_spec.lua.
	NEW_GUARDS=$(git diff "dev...$BRANCH" -- REGRESSION_GUARDS.md \
		| grep -E '^\+### `' | sed -E 's/^\+### `([^`]*)`.*/\1/' || true)
	if [ -n "$NEW_GUARDS" ]; then
		FORENSIC=$(git diff "dev...$BRANCH" -- REGRESSION_GUARDS.md \
			| grep -E '^\+\*\*(Why|Triangulation|Establishing build|Background|Rationale):\*\*' || true)
		if [ -n "$FORENSIC" ]; then
			echo "" >&2
			echo "BLOCKED: a new REGRESSION_GUARDS.md section carries forensic prose." >&2
			echo "  Layer 3 is compact: heading + summary + Sites table +" >&2
			echo "  **Files:** / **Invariant:** / **Spec:** / **Snapshot coverage:** / **Establishing commit:**" >&2
			echo "  Why / Triangulation / Background belong in private maintainer notes." >&2
			printf '%s\n' "$FORENSIC" | head -6 >&2
			exit 4
		fi
		# The inline marker has THREE spellings in the tree (measured on dev 5b58330cd):
		#   "@leb-regression-guard:<id>"   1282 sites
		#   "@leb-regression-guard: <id>"   404 sites
		#   "@leb-regression-guard <id>"     55 sites
		# An exact "<marker>:$gid" match sees only the first, so a guard written in
		# either other style reads as "Layer 1 missing" while being perfectly well
		# formed. Match all three, and require a non-id char after the id so `foo-bar`
		# does not satisfy a lookup for `foo`.
		guard_inline_re() { printf '@leb-regression-guard:? *%s([^A-Za-z0-9_-]|$)' "$1"; }

		for gid in $NEW_GUARDS; do
			# The grep demands the closing `**`, so a marker mangled into prose
			# (e.g. `**Establishing reference: see git log`) fails it too -- that
			# exact breakage went unnoticed across ~350 sections while this gate
			# only looked at Invariant/Spec.
			for marker in 'Invariant' 'Spec' 'Establishing commit'; do
				if ! git show "$BRANCH:REGRESSION_GUARDS.md" \
					| awk -v g="### \`$gid\`" '$0==g{f=1;next} /^### `/{f=0} f' \
					| grep -q "^\*\*$marker:\*\*"; then
					echo "" >&2
					echo "BLOCKED: guard '$gid' has no well-formed **$marker:** marker in REGRESSION_GUARDS.md." >&2
					if [ "$marker" = "Establishing commit" ]; then
						echo "  Use: **Establishing commit:** <see git log>" >&2
						echo "  (placeholder is deliberate -- no real SHAs on a public fork)." >&2
					fi
					exit 4
				fi
			done
			# Layer 1 = the inline comment on the CODE BEING PROTECTED. That code is
			# usually under src/, but not always: spec/ also holds non-test driver code
			# (spec/RegenFilterEnv.lua, spec/Generate*.lua) and scripts/ holds tooling,
			# and their guards are just as real -- `regen-filter-env-fail-fast` is
			# registered and lives entirely in spec/. An earlier src/-only check here
			# would have BLOCKED that legitimate guard; a false positive in a fail-closed
			# gate is worse than no gate, because it teaches everyone to reach for
			# LEB_SKIP_CONVENTION_GATES=1 and then it catches nothing. So: accept any
			# tracked non-test file, and let Layer 2 below enforce the test separately.
			# @leb-regression-guard:dev-merge-guard-gate-matching
			# .gitignore is listed for the same reason: it is a tracked non-test file
			# that takes comments, and for an ignore rule it IS the protected site --
			# nothing in-tree consumes it (git does), so there is no "consuming code"
			# to host the marker the way ImportTab.lua hosts the JSON guards. Omitting
			# it made `handoffs-not-in-repo` unmergeable despite a correct Layer 1.
			# Keep this narrow: the repo-root .gitignore, not dotfiles at large.
			if ! git grep -qE "$(guard_inline_re "$gid")" "$BRANCH" -- src/ spec/ scripts/ .gitignore ':(exclude)*_spec.lua' 2>/dev/null; then
				echo "" >&2
				echo "BLOCKED: guard '$gid' has no inline @leb-regression-guard marker on the code it protects (Layer 1 missing)." >&2
				echo "  Expected in a non-test file under src/, spec/ or scripts/, or in .gitignore" >&2
				echo "  (e.g. src/Modules/Foo.lua, spec/RegenFilterEnv.lua, scripts/dev-merge.sh)." >&2
				echo "  The inline comment is what stops the next editor; an index entry alone does not." >&2
				echo "" >&2
				echo "  Protecting values in a JSON data file? JSON takes no comments, but this" >&2
				echo "  gate still requires Layer 1 -- put the marker on the code that CONSUMES" >&2
				echo "  the invariant (the reader that breaks if the data changes meaning), e.g." >&2
				echo "  unique-shared-rollids-not-independent -> src/Classes/ImportTab.lua." >&2
				echo "  That is the correct home for it, not a workaround. Do NOT reach for" >&2
				echo "  LEB_SKIP_CONVENTION_GATES=1; see 'JSON-comment-incompatible guards' in" >&2
				echo "  REGRESSION_GUARDS.md." >&2
				exit 4
			fi
			# Layer 2 must be an actual TEST. Matching all of spec/ would let the Layer 1
			# comment in a spec/ driver satisfy this check by itself -- a false negative
			# that registers a 3-layer guard with only 2 layers. Require a *_spec.lua.
			if ! git grep -qE "$(guard_inline_re "$gid")" "$BRANCH" -- '*_spec.lua' 2>/dev/null; then
				echo "" >&2
				echo "BLOCKED: guard '$gid' has no *_spec.lua referencing it (Layer 2 missing)." >&2
				echo "  Layer 2 is the only layer that actually fails; without it this is just a comment." >&2
				exit 4
			fi
		done
		echo "  [x] guard convention gates PASSED for: $(echo $NEW_GUARDS | tr '\n' ' ')"
	fi
	echo "  [x] no new internal-info leakage in added lines"
fi

if [ "$CONFIRM" != "--confirm" ]; then
	echo ""
	echo "STOP (preview only). Re-run with --confirm to merge. This gate is intentional."
	exit 0
fi

# --- human-in-the-loop confirmation (mandatory) ---
# A live operator must type the exact branch name at /dev/tty. No TTY (CI or
# piped stdin) means abort unless an operator explicitly authorized this merge
# and the caller set LEB_DEV_MERGE_HUMAN_OK=1 for this merge only.
if [ "${LEB_DEV_MERGE_HUMAN_OK:-0}" = "1" ]; then
	echo ""
	echo ">>> LEB_DEV_MERGE_HUMAN_OK=1 set: proceeding on explicit operator authorization."
else
	REPLY_CONFIRM=""
	if [ -r /dev/tty ]; then
		printf 'CONFIRM MERGE into dev: type the branch name exactly to proceed> '
		IFS= read -r REPLY_CONFIRM < /dev/tty 2>/dev/null || REPLY_CONFIRM=""
	fi
	if [ "$REPLY_CONFIRM" != "$BRANCH" ]; then
		echo "" >&2
		echo "STOP: dev merge NOT performed (nothing changed)." >&2
		echo "  --confirm requires a live human to type the branch name at an interactive terminal." >&2
		echo "  No matching confirmation was received$( [ -r /dev/tty ] && echo ' (mismatch)' || echo ' (no TTY attached)')." >&2
		echo "  Let a live operator run --confirm, or -- only after explicit authorization" >&2
		echo "  for this specific merge -- re-run with" >&2
		echo "  LEB_DEV_MERGE_HUMAN_OK=1. (See @leb-dev-merge-guard.)" >&2
		exit 3
	fi
fi

echo ""
echo ">>> merging --no-ff ..."
LEB_DEV_MERGE_OK=1 git merge --no-ff --no-edit "$BRANCH"
echo ""
echo "MERGED $BRANCH -> dev @ $(git rev-parse --short HEAD)"
echo "REMINDER: notify the user now (SHA + suite result + blast, 1 line)."
