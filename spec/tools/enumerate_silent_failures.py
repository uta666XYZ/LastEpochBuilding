#!/usr/bin/env python3
# @leb-tooling: enumerate-silent-failures
# @leb-regression-guard: silent-failure-affix-sweep (tool site)
#
# Enumerate "silent failure" affix rows in src/Data/ModCache.lua: keys where
# ModParser returned an empty modList yet emitted non-empty residue text,
# meaning a real-looking affix string was swallowed without surfacing into
# calculations and without raising an error.
#
# Primary source : src/Data/ModCache.lua  (every line LEB has ever parsed)
# Secondary src  : src/Data/ModItem_1_4.json + ModItem_IdolAltar_1_4.json +
#                  ModIdol_1_4.json + ModIdolAffixes_1_4.json -- the
#                  canonical LE-1.4 affix mod-line texts (Phase 2 cross-
#                  reference + dm_gap detection)
#
# Output         : spec/Data/silent-failure-affixes.json
#                  { metadata: {...}, silent_failures: [...], dm_gap: [...] }
#
# Categorisation heuristics (Phase 1 is scaffolding -- exact a/b/c/d
# refinement is Phase 2):
#   a-descriptive  : residue has no digits, no '%', no 'Per ' / 'Chance' /
#                    'Increased' / 'More' / 'Reduced' anchors -- pure
#                    flavour text the parser correctly ignores
#   b-parser-gap   : residue contains a numeric or recognisable mod-verb
#                    (Increased / Reduced / More / Less / Per / Chance /
#                    %) -- parser regex is missing
#   c-infra-gap    : residue looks like a trigger / on-event / unique
#                    behaviour ('When', 'On', 'After', 'While', 'Grants',
#                    'Summon', 'Trigger') -- requires new infra to wire
#   d-unknown      : residue does not match any of the above buckets
#
# Phase 2 will refine these by datamining cross-reference.

import json, os, re, sys
try: sys.stdout.reconfigure(encoding='utf-8')
except Exception: pass

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MODCACHE = os.path.join(ROOT, "src", "Data", "ModCache.lua")
OUT_DIR  = os.path.join(ROOT, "spec", "Data")
OUT_JSON = os.path.join(OUT_DIR, "silent-failure-affixes.json")
MODITEM_FILES = [
    os.path.join(ROOT, "src", "Data", "ModItem_1_4.json"),
    os.path.join(ROOT, "src", "Data", "ModItem_IdolAltar_1_4.json"),
    os.path.join(ROOT, "src", "Data", "ModIdol_1_4.json"),
    os.path.join(ROOT, "src", "Data", "ModIdolAffixes_1_4.json"),
]

# Lua row formats observed in ModCache.lua (one row per line):
#   c["<key>"]={{},""}                                 -- neutralized
#   c["<key>"]={{},"<residue>"}                        -- silent failure
#   c["<key>"]={{[1]={...},...},""}                    -- fully parsed (skip)
#   c["<key>"]={{[1]={...}},"<extras>"}                -- partial parse (skip
#                                                          for this sweep)
KEY_RE        = re.compile(r'^c\["((?:[^"\\]|\\.)*)"\]=\{')
NEUTRAL_SUFFX = '={{},""}'
SILENT_RE     = re.compile(r'=\{\{\},"((?:[^"\\]|\\.)+)"\}\s*$')

def classify(residue: str, key: str = "", has_dm_match: bool = False) -> str:
    """
    Phase 2 refined classifier.

    Inputs:
      residue       -- text ModParser left unparsed
      key           -- the original ModCache key (full affix string)
      has_dm_match  -- True if the key normalises to a ModItem_1_4 line

    Buckets:
      a1-pure-flavor   -- no digit, no %, no parser-verb in residue AND
                          no datamining match AND no leading numeric in
                          key.  Almost certainly skill-tree node names or
                          unique-line flavour echo; safe-to-neutralize.
      a2-numeric-real  -- residue lacks verbs but key has +/digit/%; the
                          parser fed back a stripped residue but the
                          affix is a real numeric mod.  DO NOT neutralize.
      b-parser-gap     -- residue contains a numeric/verb anchor; missing
                          regex entry.  Phase 3 candidate for parser
                          extension.
      c-infra-gap      -- residue contains a trigger/event/grant anchor;
                          needs new infra to wire.
      dm-confirmed     -- has_dm_match overrides everything (real LE-1.4
                          affix line); routes to b or c by residue
                          content.  Surfaced under b-dm or c-dm so the
                          spawn-task workflow can target them first.
    """
    s = residue.strip()
    low = s.lower()
    key_low = key.lower()
    key_has_numeric_prefix = bool(re.match(r"^\s*[+\d]", key))
    infra_anchors = ("when ", " when ", " on ", "after ", "while ", "grants",
                     "summon", "trigger", "consume", "every ", " whenever")
    parser_verbs = ("increased", "reduced", "more", "less", "added",
                    "per ", "chance", "doubled", "multiplied",
                    " leech", "penetration", "resistance", "regen")
    has_digit   = any(ch.isdigit() for ch in s)
    has_pct     = "%" in s
    has_verb    = any(v in low for v in parser_verbs)
    has_infra   = any(a in (" " + key_low + " ") for a in infra_anchors)

    if has_dm_match:
        # Authoritative real LE-1.4 affix line. Route by content.
        if has_infra:
            return "c-dm-infra"
        return "b-dm-numeric"
    if has_infra:
        return "c-infra-gap"
    if has_digit or has_pct or has_verb:
        return "b-parser-gap"
    if key_has_numeric_prefix:
        # Key starts with + or digit but residue is bare -- likely a
        # real numeric mod whose stem was stripped. Mark separately so
        # Phase 3 doesn't bulk-neutralize.
        return "a2-numeric-real"
    if not s:
        return "z-whitespace"
    return "a1-pure-flavor"


def main():
    if not os.path.isfile(MODCACHE):
        print(f"ERR: missing {MODCACHE}", file=sys.stderr); return 2

    total = parsed = neutralized = silent = malformed = 0
    silent_failures = []  # {key, residue, category, ...}
    silent_norm_to_idx = {}   # norm(key) -> silent_failures index
    parsed_norms = set()      # norm(key) for parsed rows
    all_norms    = set()      # union of all ModCache keys (any status)

    def norm(s: str) -> str:
        # Strip digits / signs / percent / common LE placeholders, collapse
        # whitespace, lowercase. Designed so "+(3-4) Health Regen" /
        # "+4 Health Regen" / " Health Regen " all map to the same form.
        s = re.sub(r"\([^)]*\)", "", s)       # drop (N-M) ranges
        s = re.sub(r"[\d.%+\-]", "", s)
        s = re.sub(r"\s+", " ", s).strip().lower()
        return s

    with open(MODCACHE, encoding="utf-8") as f:
        for line in f:
            if not line.startswith("c["):
                continue
            total += 1
            stripped = line.rstrip("\n").rstrip()
            km = KEY_RE.match(stripped)
            if not km:
                malformed += 1
                continue
            key = km.group(1)
            nkey = norm(key)
            all_norms.add(nkey)
            if stripped.endswith(NEUTRAL_SUFFX):
                neutralized += 1
                continue
            sm = SILENT_RE.search(stripped)
            if sm:
                residue = sm.group(1)
                silent += 1
                idx = len(silent_failures)
                silent_failures.append({
                    "key": key,
                    "residue": residue,
                    "category": None,   # filled after dm cross-reference
                })
                silent_norm_to_idx.setdefault(nkey, idx)
                continue
            # Anything else has a non-empty modList -> at least partially
            # parsed. We don't subcategorise here; this sweep targets total
            # silent failures.
            parsed += 1
            parsed_norms.add(nkey)

    # (sort happens after Phase 2 classification below)

    # ---- Phase 2 datamining cross-reference --------------------------------
    # Source: src/Data/ModItem_1_4.json (+ idol siblings). Each entry's
    # numeric-string keys ("1", "2", ...) carry the canonical LE mod-line
    # text -- the same string ModParser receives at runtime. We index every
    # such line by its normalised form so each silent failure can be tagged
    # with its authoritative affixId (entry_key) + affixName.
    dm_lookup = {}    # norm(text) -> {source, entry_key, line_key, raw, affixName}
    dm_total_lines = 0
    for path in MODITEM_FILES:
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as f:
            try:
                data = json.load(f)
            except Exception:
                continue
        if not isinstance(data, dict):
            continue
        src = os.path.basename(path)
        for entry_key, entry in data.items():
            if not isinstance(entry, dict):
                continue
            affix_name = entry.get("affixName") or entry.get("affix") or ""
            for line_key, line_val in entry.items():
                if not (line_key.isdigit() and isinstance(line_val, str)):
                    continue
                dm_total_lines += 1
                n = norm(line_val)
                if not n:
                    continue
                # First-wins: keep the earliest source so the JSON stays
                # deterministic and minimal.
                dm_lookup.setdefault(n, {
                    "source": src,
                    "entry_key": entry_key,
                    "line_key": line_key,
                    "raw": line_val,
                    "affixName": affix_name,
                })

    # Enrich silent_failures with datamining match, then classify with
    # the dm-aware refined heuristic.
    matched_silent = 0
    for sf in silent_failures:
        n = norm(sf["key"])
        m = dm_lookup.get(n)
        if m:
            sf["datamining_match"] = m
            matched_silent += 1
        sf["category"] = classify(sf["residue"], sf["key"], m is not None)

    silent_failures.sort(key=lambda e: (e["category"], e["key"]))

    # dm_gap: every ModItem line whose normalised form does not appear as
    # ANY ModCache key (parsed, neutralized, OR silent). These are affixes
    # LEB has never attempted to parse -- the worst kind of gap.
    dm_gap = []
    for n, info in dm_lookup.items():
        if n in all_norms:
            continue
        dm_gap.append({
            "source": info["source"],
            "entry_key": info["entry_key"],
            "line_key": info["line_key"],
            "raw": info["raw"],
            "affixName": info["affixName"],
            "norm": n,
        })
    dm_gap.sort(key=lambda e: (e["source"], e["entry_key"], e["line_key"]))

    recognition_pct = ((parsed + neutralized) / total * 100.0) if total else 0.0
    parsed_pct      = (parsed / total * 100.0) if total else 0.0
    silent_pct      = (silent / total * 100.0) if total else 0.0
    by_cat = {}
    for e in silent_failures:
        by_cat[e["category"]] = by_cat.get(e["category"], 0) + 1

    metadata = {
        "tool": "enumerate_silent_failures",
        "modcache_path": "src/Data/ModCache.lua",
        "total_rows": total,
        "parsed_rows": parsed,
        "neutralized_rows": neutralized,
        "silent_failure_rows": silent,
        "malformed_rows": malformed,
        "recognition_rate_pct": round(recognition_pct, 2),
        "parsed_pct": round(parsed_pct, 2),
        "silent_failure_pct": round(silent_pct, 2),
        "by_category": by_cat,
        "phase": 2,
        "datamining": {
            "moditem_files": [os.path.basename(p) for p in MODITEM_FILES],
            "moditem_lines_scanned": dm_total_lines,
            "moditem_unique_norms": len(dm_lookup),
            "silent_failure_matched": matched_silent,
            "silent_failure_unmatched": silent - matched_silent,
            "dm_gap_count": len(dm_gap),
        },
        "notes": [
            "Phase 2 deliverable: + datamining cross-reference (ModItem_1_4 et al).",
            "silent_failures[*].datamining_match attaches affixId / affixName when matched.",
            "dm_gap[]: ModItem affix lines that never reach ModCache as a key.",
            "Lock the totals via spec/System/TestSilentFailureSweep_spec.lua.",
        ],
    }

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"metadata": metadata,
                   "silent_failures": silent_failures,
                   "dm_gap": dm_gap},
                  f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write("\n")

    print(f"wrote {OUT_JSON}")
    print(f"total rows         : {total}")
    print(f"  parsed (non-empty modList) : {parsed}  ({recognition_pct:.2f}%)")
    print(f"  neutralized (empty residue): {neutralized}")
    print(f"  silent failure (residue)   : {silent}")
    print(f"  malformed (parser skip)    : {malformed}")
    print(f"silent-failure breakdown:")
    for k in sorted(by_cat):
        print(f"  {k:18s}: {by_cat[k]}")
    print(f"datamining cross-reference:")
    print(f"  moditem lines scanned     : {dm_total_lines}")
    print(f"  moditem unique norms      : {len(dm_lookup)}")
    print(f"  silent_failure matched    : {matched_silent}/{silent}")
    print(f"  silent_failure unmatched  : {silent - matched_silent}")
    print(f"  dm_gap (never reached LEB): {len(dm_gap)}")

    # ---- Phase 3a: optional neutralization of a1-pure-flavor rows ---------
    # When `--emit-neutralization` is passed, rewrite ModCache.lua in place,
    # promoting every silent-failure row whose category is `a1-pure-flavor`
    # (no dm match, no digit/pct/verb, no leading numeric in key) from
    #   c["<key>"]={{},"<residue>"}
    # to
    #   c["<key>"]={{},""}
    # so the parser's residue is no longer dangled. dm-matched and
    # numeric/infra rows are NEVER touched -- those need parser/infra wiring,
    # not neutralization. Spec baselines in TestSilentFailureSweep_spec.lua
    # must be updated in the same commit.
    if "--emit-neutralization" in sys.argv:
        a1_keys = {sf["key"] for sf in silent_failures
                   if sf["category"] == "a1-pure-flavor"}
        with open(MODCACHE, encoding="utf-8", newline="") as f:
            src = f.read()
        rewritten_lines = []
        rewritten_count = 0
        for line in src.splitlines(keepends=True):
            nl_stripped = line.rstrip("\n").rstrip("\r")
            trailing = line[len(nl_stripped):]
            if nl_stripped.startswith("c["):
                km = KEY_RE.match(nl_stripped)
                if km and km.group(1) in a1_keys and SILENT_RE.search(nl_stripped):
                    new_body = SILENT_RE.sub('={{},""}', nl_stripped)
                    line = new_body + trailing
                    rewritten_count += 1
            rewritten_lines.append(line)
        with open(MODCACHE, "w", encoding="utf-8", newline="") as f:
            f.writelines(rewritten_lines)
        print(f"neutralized {rewritten_count} a1-pure-flavor rows in {MODCACHE}")
        if rewritten_count != by_cat.get("a1-pure-flavor", 0):
            print(f"WARN: expected {by_cat.get('a1-pure-flavor', 0)} rewrites, "
                  f"got {rewritten_count}", file=sys.stderr)
            return 3
    return 0


if __name__ == "__main__":
    sys.exit(main())
