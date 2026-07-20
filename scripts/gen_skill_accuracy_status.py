#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate src/Data/SkillAccuracyStatus.lua from maintainer-supplied status data.

WHY THIS EXISTS
---------------
The LEB "accuracy honesty" UI badge (@leb-regression-guard:ui-accuracy-honesty-badge)
labels a build's ACTIVE skill with a two-axis honesty tag when LEB's DPS for that
skill has NOT been in-game ±5%-verified. The badge is DISPLAY-ONLY and never
touches calc / mainOutput (corpus byte-identical).

The per-skill accuracy status lives in the input file's `meta_coverage` map
(the "meta-43" list: 18 S-tier + 25 A-tier community reference builds). That map
is keyed by human BUILD names ("Shadow Rend BD", "Heartseeker Mksm") with a single
letter status code, NOT by the runtime key the UI has, which is
`socketGroup.grantedEffect.name` (e.g. "Shadow Rend", "Heartseeker"). This tool
bridges the two: it applies the fixed letter->axis mapping, resolves each flagged
build to its exact grantedEffect.name via the curated BUILD_TO_SKILL table below,
validates every produced key against Data/skills.json (no fabricated skills, same
discipline as SubSkillGrants), and emits the Lua lookup table.

SOURCE DATA
-----------
The maintainer supplies a verification-status JSON file with
`meta_coverage.{stier,atier}`. The runtime does not read that source file, so the
generated Lua table is committed. Re-run this tool when the status data changes.

LETTER CODE -> HONESTY AXIS (fixed; approved taxonomy, do not change here)
-------------------------------------------------------------------------
  meta_coverage legend:  v=OK ±5%-verified  g=RE/feature-gated  w=gap-open
                         x=rig-unmeasurable  n=N/A(offline)  (blank=uncaptured)
  Two-axis badge:
    approximate (amber)  <-  g and w   -- model intentionally incomplete / known gap
    unverified  (gray)   <-  x, n, blank  -- number may be fine but is unconfirmed
    (no badge)           <-  v          -- ±5% verified

COLLISION RULE: verified-wins
-----------------------------
If a grantedEffect.name appears in BOTH a verified (v) build AND a flagged build,
the skill MODEL is considered verified and gets NO badge; any residual gap is
variant-specific (a build mechanic), not a skill-model gap. In the current board
this affects exactly ONE skill: "Hammer Throw" (Crit Hammerdin=v vs Bleed
Hammerdin=g) -> omitted by the verified-wins rule.

OMISSIONS (documented, intentional)
-----------------------------------
  * Reflect Shaman (n / offline): a reflect-damage defensive build with no single
    keyable active skill -> omitted (produces no badge).
  * Bleed Hammerdin (g): its active skill is "Hammer Throw" (Bleed is an ailment,
    not a skill); Hammer Throw is verified via Crit Hammerdin -> omitted per the
    verified-wins rule above.

Run:  python scripts/gen_skill_accuracy_status.py \
        [--board "<status-data.json>"] \
        [--skills src/Data/skills.json] \
        [--out src/Data/SkillAccuracyStatus.lua]
"""
import argparse
import json
import os
import sys

# Curated resolution of each NON-verified meta build -> its exact
# grantedEffect.name(s) in Data/skills.json. Only builds that must produce a
# badge appear here; verified builds are not listed (they emit no badge and,
# per the verified-wins rule, none of the skills below collide with a verified
# build). Each key is validated against skills.json before emission.
#   build display name (meta_coverage `n`)  ->  [grantedEffect.name, ...]
BUILD_TO_SKILL = {
    # --- S-tier ---
    "Shadow Rend BD":        ["Shadow Rend"],       # g count-state
    "Flay Mana Lich":        ["Flay"],              # g proc/transform-dominated
    "Shatter Totem Druid":   ["Shatter Totem"],     # g totem-count fold deferred
    "Profane Veil Warlock":  ["Profane Veil", "Profane Orb"],  # w Profane Orb x2 UNDER
    # --- A-tier ---
    "Harvest Flay Lich":     ["Harvest"],           # g proc/transform-dominated
    "Sabertooth BM":         ["Summon Sabertooth"], # g source-data gap
    "Hydrahedron RM":        ["Hydrahedron"],        # g
    "Heartseeker Mksm":      ["Heartseeker"],        # x crit-attribution wall
    "Raptor BM":             ["Summon Raptor"],      # x measurement unavailable
    "Javelin Paladin":       ["Javelin"],            # x crit-attribution wall
    # NOTE: "Bleed Hammerdin" (g) -> Hammer Throw is intentionally ABSENT
    #       (verified-wins vs Crit Hammerdin). "Reflect Shaman" (n) is absent
    #       (offline, no keyable active skill).
}

# meta_coverage single-letter status -> two-axis badge (or None = no badge).
CODE_TO_AXIS = {
    "v": None,           # OK ±5% verified
    "g": "approximate",  # RE / feature-gated
    "w": "approximate",  # gap-open / permanent-defer
    "x": "unverified",   # rig-unmeasurable
    "n": "unverified",   # N/A (offline)
    # (a future blank/"uncaptured" code, if added to the board, is "unverified")
}

# Axis-severity for the "worst wins" aggregation when one grantedEffect.name is
# produced by several flagged builds (approximate is the more-honest / stronger
# claim of a KNOWN gap, so it outranks unverified).
AXIS_RANK = {"unverified": 1, "approximate": 2}

# The source location is maintainer-specific and is intentionally not committed.
# Point $LEB_BOARD_DATA at the file or pass --board.
def _default_board():
    explicit = os.environ.get("LEB_BOARD_DATA")
    if explicit:
        return explicit
    return None


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, ".."))  # scripts/ is one level below repo root
    ap = argparse.ArgumentParser()
    ap.add_argument("--board", default=_default_board())
    ap.add_argument("--skills", default=os.path.join(repo, "src", "Data", "skills.json"))
    ap.add_argument("--out", default=os.path.join(repo, "src", "Data", "SkillAccuracyStatus.lua"))
    args = ap.parse_args()

    if not args.board:
        print("ERROR: status data path unknown. Set $LEB_BOARD_DATA or pass "
              "--board <path>.", file=sys.stderr)
        return 1

    with open(args.board, encoding="utf-8") as f:
        board = json.load(f)
    mc = board["meta_coverage"]
    builds = [("S", b) for b in mc["stier"]] + [("A", b) for b in mc["atier"]]

    with open(args.skills, encoding="utf-8") as f:
        skills = json.load(f)
    skill_names = {v.get("name") for v in skills.values()}

    # 1) sanity: every letter code seen is known.
    for _tier, b in builds:
        code = b["s"]
        if code not in CODE_TO_AXIS:
            print(f"ERROR: unknown meta_coverage status code {code!r} for {b['n']!r}",
                  file=sys.stderr)
            return 2

    # 2) sanity: every flagged (non-v) build is accounted for -- either mapped in
    #    BUILD_TO_SKILL or explicitly documented as an omission -- so a newly
    #    flagged board build cannot silently vanish from the UI.
    KNOWN_OMISSIONS = {"Bleed Hammerdin", "Reflect Shaman"}
    for _tier, b in builds:
        if CODE_TO_AXIS[b["s"]] is None:
            continue  # verified -> no badge, no mapping needed
        name = b["n"]
        if name not in BUILD_TO_SKILL and name not in KNOWN_OMISSIONS:
            print(f"ERROR: flagged build {name!r} (code {b['s']!r}) is neither mapped "
                  f"in BUILD_TO_SKILL nor a KNOWN_OMISSION -- update this generator.",
                  file=sys.stderr)
            return 3

    # 3) build the per-skill table from the mapped flagged builds, worst-wins.
    table = {}   # grantedEffect.name -> axis
    origin = {}  # grantedEffect.name -> "build (code)"
    for _tier, b in builds:
        axis = CODE_TO_AXIS[b["s"]]
        if axis is None or b["n"] not in BUILD_TO_SKILL:
            continue
        for gname in BUILD_TO_SKILL[b["n"]]:
            if gname not in skill_names:
                print(f"ERROR: {gname!r} (from {b['n']!r}) is not a name in skills.json",
                      file=sys.stderr)
                return 4
            prev = table.get(gname)
            if prev is None or AXIS_RANK[axis] > AXIS_RANK[prev]:
                table[gname] = axis
                origin[gname] = f'{b["n"]} ({b["s"]})'

    # 4) verified-wins guard: a produced key must not be a known verified skill.
    #    (Hammer Throw is excluded upstream by omission; this catches a future
    #    regression where a mapped skill collides with a verified build.)
    if "Hammer Throw" in table:
        print("ERROR: 'Hammer Throw' leaked into the table (verified-wins violated)",
              file=sys.stderr)
        return 5

    version = board.get("version", "?")
    last = str(board.get("last_updated", "")).split("。")[0].split(" (")[0].strip()

    lines = []
    lines.append("-- Skill accuracy honesty status (display-only UI badge source).")
    lines.append("--")
    lines.append("-- @leb-regression-guard:ui-accuracy-honesty-badge")
    lines.append("--")
    lines.append("-- GENERATED FILE -- DO NOT HAND-EDIT.")
    lines.append("-- Regenerate with:  python scripts/gen_skill_accuracy_status.py")
    lines.append("-- Generated from maintainer-supplied verification status data.")
    lines.append(f"-- Source version: {version}   (last_updated: {last})")
    lines.append("--")
    lines.append("-- Maps a runtime socketGroup.grantedEffect.name to a two-axis honesty tag:")
    lines.append('--   "approximate" (amber) = board RE/feature-gated (g) or gap-open (w)')
    lines.append("--                            -- model intentionally incomplete / known gap.")
    lines.append('--   "unverified"  (gray)  = board rig-unmeasurable (x) or offline (n)')
    lines.append("--                            -- number may be right but is unconfirmed.")
    lines.append("-- Skills that are ±5%-verified (v), or verified-in-some-build (verified-wins,")
    lines.append("-- e.g. Hammer Throw), are ABSENT here -> no badge. This table is the ALLOW-LIST")
    lines.append("-- of skills that MUST show a badge; absence = verified/untracked = no claim.")
    lines.append("--")
    lines.append("-- DPS-NEUTRAL: this is static reference data (like colorCodes). It is read only")
    lines.append("-- by GUI draw code; it never enters modList / calcsTab.mainOutput, so corpus")
    lines.append("-- snapshots are byte-identical. See REGRESSION_GUARDS.md ui-accuracy-honesty-badge.")
    lines.append("return {")
    for gname in sorted(table):
        axis = table[gname]
        # escape any embedded quotes/backslashes defensively
        key = gname.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f'\t["{key}"] = "{axis}",\t-- {origin[gname]}')
    lines.append("}")
    out = "\n".join(lines) + "\n"

    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)

    print(f"wrote {args.out} with {len(table)} skill(s):")
    for gname in sorted(table):
        print(f"  {gname!r} -> {table[gname]}  [{origin[gname]}]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
