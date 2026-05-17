#!/usr/bin/env python3
# @leb-tooling: diff-letools
# Compare LEB snapshot (.lua) vs LETools JSON (.letools.json) for a 1.4 testbuild.
#
# Usage:
#   python spec/tools/diff_letools.py "<build basename without extension>"
#   python spec/tools/diff_letools.py "BxvJP3g1 lv99 Necromancer"
#
# Options:
#   --threshold N   hide stats with |delta%| <= N (default 2)
#   --all           print all mapped stats, do not filter
#   --root PATH     base dir for spec/TestBuilds/1.4 (default: auto-detect)
#
# Key principle for resistance / endurance: use *Total keys (raw, pre-cap) from
# the LEB snapshot. The bare keys (FireResist, Endurance) are POST-cap (75 / 60)
# and will mask all real diffs as cap noise. This script already maps to the
# raw totals where they exist.
#
# Minion resistance has no *Total variant in LEB output; the bare MinionFireResist
# etc. are already raw. See: Obsidian note "LEB vs LETools stat 比較.md".

import argparse, json, os, re, sys
try: sys.stdout.reconfigure(encoding='utf-8')
except Exception: pass

NUM_RE = re.compile(r'\["([^"]+)"\]\s*=\s*([-\d.]+)\s*,')

def find_root(start):
    cur = os.path.abspath(start)
    for _ in range(8):
        if os.path.isdir(os.path.join(cur, "spec", "TestBuilds", "1.4")):
            return cur
        nxt = os.path.dirname(cur)
        if nxt == cur: break
        cur = nxt
    return None

def extract_output(path):
    with open(path, encoding='utf-8') as f: text = f.read()
    m = re.search(r'output\s*=\s*\{', text)
    if not m: return {}
    i = m.end(); depth = 1; n = len(text)
    while i < n and depth > 0:
        c = text[i]
        if c == '{': depth += 1
        elif c == '}': depth -= 1
        i += 1
    body = text[m.end():i-1]
    out = {}
    for mm in NUM_RE.finditer(body):
        try: out[mm.group(1)] = float(mm.group(2))
        except: pass
    return out

def parse_letools(path):
    with open(path, encoding='utf-8') as f: data = json.load(f)
    rows = {}
    for tab, blocks in data['tabs'].items():
        rows[tab] = {}
        for blk in blocks:
            if blk.get('type') == 'kv':
                for k, v in blk.get('rows', []):
                    rows[tab][k] = v
    return rows

def num(s):
    s = str(s).strip().rstrip('%').replace(',', '')
    try: return float(s)
    except: return None

# (tab, letools_name) -> leb_key
# IMPORTANT: resistance/endurance use *Total (raw, pre-cap) to enable real comparison.
MAPPING = {
    ('General','Strength'):'Str', ('General','Dexterity'):'Dex',
    ('General','Intelligence'):'Int', ('General','Attunement'):'Attr',
    ('General','Vitality'):'Vit',
    ('General','Health'):'Life', ('General','Mana'):'Mana',
    ('General','Health Regen'):'LifeRegen', ('General','Mana Regen'):'ManaRegen',
    ('General','Movement Speed'):'MovementSpeed',
    # Player resists: *Total = raw, bare key = post-cap (75)
    ('General','Fire Resistance'):'FireResistTotal',
    ('General','Cold Resistance'):'ColdResistTotal',
    ('General','Lightning Resistance'):'LightningResistTotal',
    ('General','Physical Resistance'):'PhysicalResistTotal',
    ('General','Necrotic Resistance'):'NecroticResistTotal',
    ('General','Poison Resistance'):'PoisonResistTotal',
    ('General','Void Resistance'):'VoidResistTotal',
    ('General','Dodge Rating'):'DodgeRating',
    ('General','Dodge Chance'):'DodgeChance',
    ('General','Armor'):'Armour',
    ('General','Armor Mitigation'):'ArmourMitigation',
    # Block Chance: *Total = raw uncapped (used by LETools planner display),
    # bare BlockChance = capped at BlockChanceMax (75 default). LETools shows
    # uncapped so build planners can see over-cap headroom (mirror of how it
    # treats Endurance below). LE's own character-sheet shows capped via
    # PrecalculatedStatsHolder.blockChanceForCharacterSheet (block_decompile.txt
    # RVA 0x2344F70) — but that's an LE display detail, not what LETools serializes.
    ('General','Block Chance'):'BlockChanceTotal',
    ('General','Block Effectiveness'):'BlockEffectiveness',
    ('General','Block Mitigation'):'BlockMitigation',
    # Endurance: *Total = raw, bare = post-cap (60)
    ('Defense','Endurance'):'EnduranceTotal',
    ('Defense','Endurance Threshold'):'EnduranceThreshold',
    ('Defense','Glancing Blow Chance'):'GlancingBlowChance',
    ('Defense','Critical Strike Avoidance'):'CritStrikeAvoid',
    ('Defense','Reduced Bonus Damage Taken From Critical Strikes'):'CriticalStrikesTakenReduction',
    ('Defense','Parry Chance'):'ParryChance',
    # @leb-regression-guard:ward-regen-canonical-key-wardpersecond
    # LETools "Ward Regen" maps to LEB output `WardPerSecond` (gross passive WPS,
    # the property game writes to `wardRegen + wardRegenFromStats` per
    # `ProtectionClass.Update` RVA 0x234B8C0 in `ward_decompile.txt`).
    # `NetWardRegen` is gross − decay (display field) and would introduce phantom
    # diffs ≈ per-build decay rate. `WardRegen` is not an LEB output key.
    # Mirror of `scripts/letools-diff.js` mapping (~line 86).
    # See also REGRESSION_GUARDS.md §ward-regen-passive-vs-event-split for the
    # display-only vs local-wps inversion-math split that consumes this mapping.
    ('Defense','Ward Regen'):'WardPerSecond',
    ('Defense','Ward Retention'):'WardRetention',
    ('Defense','Ward Decay Threshold'):'WardDecayThreshold',
    # ('Defense','Stun Avoidance'):'StunAvoidance',
    # ^^ Excluded: LETools UI omission, not a bug. LEB's output.StunAvoidance
    # is built from three terms that all reach the player stat: class base
    # (baseStunAvoidance + stunAvoidancePerLevel * Level), passive tree
    # (e.g. Acolyte-19 "Towering Death" +50/pt up to +250 via Sum BASE), and
    # items. BxvJP3g1 lv99 Necromancer triangulation (commit 659bc8e16):
    # LEB total 1557 ≡ LE datamining 745 base + 250 tree + 562 items, while
    # LETools' left panel showed 1075 due to its own UI omitting passive
    # contributions. Locked by regression guard `stun-avoidance-base-and-tree`
    # (REGRESSION_GUARDS.md §stun-avoidance-base-and-tree).
    # See Obsidian "LEB vs LETools stat 比較.md" (既知の比較除外 stat).
    ('Defense','Damage Taken'):'DamageTaken',
    ('Defense','Damage Over Time Taken'):'DotTaken',
    # Minion: no *Total variants; bare keys are raw.
    ('Minion','Maximum Companions'):'MaximumCompanions',
    ('Minion','Increased Health'):'MinionLife',
    ('Minion','Health Regen'):'MinionLifeRegen',
    ('Minion','Increased Health Regen'):'MinionLifeRegenIncrease',
    ('Minion','Dodge Rating'):'MinionDodgeRating',
    # ('Minion','Armor'):'MinionArmour',
    # ^^ Excluded: aggregation-scope mismatch, not a bug. LEB's output.MinionArmour
    # sums the "MinionModifier > Armour BASE" pool granted by passive/skill tree
    # (e.g. Dread Shade > Martyrdom "30 Minion Armour per Vitality" → 900 with
    # Vit=30 for BxvJP3g1), while LETools' Minion tab "Armor" shows the resolved
    # per-minion armor on the representative minion. The two are not comparable.
    # See Obsidian "LEB vs LETools stat 比較.md" (既知の比較除外 stat).
    ('Minion','Critical Strike Avoidance'):'MinionCritStrikeAvoid',
    ('Minion','Reduced Bonus Damage Taken From Critical Strikes'):'MinionCriticalStrikesTakenReduction',
    # ('Minion','Movement Speed'):'MinionMovementSpeed',
    # ('Minion','Fire Resistance'):'MinionFireResist',
    # ('Minion','Cold Resistance'):'MinionColdResist',
    # ('Minion','Lightning Resistance'):'MinionLightningResist',
    # ('Minion','Physical Resistance'):'MinionPhysicalResist',
    # ('Minion','Necrotic Resistance'):'MinionNecroticResist',
    # ('Minion','Poison Resistance'):'MinionPoisonResist',
    # ('Minion','Void Resistance'):'MinionVoidResist',
    # ('Minion','Increased Cooldown Recovery Speed'):'MinionCooldownRecovery',
    # ^^ Excluded (2026-05-17): same aggregation-scope mismatch as MinionArmour
    # above. The full pool of Minion* outputs in CalcDefence.lua L1752-1795 walks
    # `modDB:List(nil, "MinionModifier")`, runs each inner mod through EvalMod,
    # and accumulates by (name, type) bucket — so every bare `output.MinionXxx`
    # is a *modifier-pool aggregate*, not a per-minion resolved value. LETools'
    # Minion tab shows the resolved-on-representative-minion stat (prefab base +
    # applied pool + per-minion-prefab adjustments), capped at 75% for resists.
    # The two are not comparable apples-to-apples. Observed drift pattern:
    # mean |Δ%| 10-23%, max 480% (single-digit LETools vs full-pool LEB).
    # For MovementSpeed the additional gap is the engine-hardcoded sp=9
    # player-MovementSpeed → minion auto-forward (LE_datamining/bepinex/
    # MinionStatDumper Phase 7 runtime surface), which LEB's MinionModifier
    # bucket cannot observe. For CooldownRecovery the n is only 3 builds and
    # mean drift is sub-percent (Lane C noise).
    # Game-faithful per `affix_tag_surface.json` (156 mods / 32 props with
    # tag=8192 MINION) — these affixes ARE routed via MinionModifier list,
    # matching LEB. Locked semantics, no fix needed; LETools display style
    # mismatch only.
    # See Obsidian "LEB vs LETools stat 比較.md" + "SKILL_STATUS.md" ALLOWED.
    ('Other','Increased Cooldown Recovery Speed'):'CooldownRecovery',
}

# Stats with a known semantic gap between LEB and LETools. Surfacing a diff here
# is not necessarily a LEB bug — the comparison itself is asymmetric. We still
# emit the row (so regressions don't hide), but append a footnote when shown.
#
# Keyed by (tab, letools_name) to match MAPPING entries exactly.
KNOWN_SEMANTIC_GAPS = {
    ('Defense','Ward Regen'):
        "LEB folds event-driven ward-conversion mods (Mana Spent Gained as Ward, "
        "Current Mana Gained as Ward per Second, Missing Health Gained as Ward "
        "per Second) into output.WardPerSecond via CalcPerform's manaSpent/"
        "currentMana/missingHealth fold-in. LETools' static 'Ward Regen' shows "
        "only the raw +X Ward per Second mod sources (gear/passive/idol). For "
        "builds with ward-conversion gear (e.g. o3Zlpkxd: 50% Mana Spent + "
        "25.3 mana/s skill cost -> ~12.7 wps fold-in), LEB > LETools is expected. "
        "Investigation: 'Ward Regen o3Zlpkxd 乖離調査' (Obsidian).",
}

# @leb-regression-guard: diff-letools-abs-tolerance-floor
# Mirror of `scripts/letools-diff.js` TOL_ABS=0.5 (~L16). LETools renders
# several integer-display stats (Ward Regen, Block Chance, Endurance, …) by
# rounding to nearest integer in the UI even though their underlying values
# are floats — Ward Regen in particular shows as int while sibling Health/Mana
# Regen show 2 decimals (see e.g. BgRrP5rr .letools.json Defense tab: Ward
# Regen="4" vs Health Regen="185.92"). Without an absolute tolerance floor a
# sub-1.0 float diff (e.g. LEB WardPerSecond=3.712 vs LETools "4") inflates
# to a fake 7.2% drift purely because the LETools UI rounded its display.
# 0.5 is the half-step of integer-rounded display = exactly the noise floor
# below which no real-world LEB regression could ever hide. See
# REGRESSION_GUARDS.md §ward-regen-passive-vs-event-split (post-fix residual
# analysis 2026-05-18 entry).
TOL_ABS = 0.5

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('build', help='Build basename (without .lua / .letools.json)')
    ap.add_argument('--threshold', type=float, default=2.0)
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--root', default=None)
    args = ap.parse_args()

    root = args.root or find_root(os.path.dirname(os.path.abspath(__file__)))
    if not root:
        print("ERROR: could not find spec/TestBuilds/1.4 dir", file=sys.stderr); sys.exit(2)
    base = os.path.join(root, 'spec', 'TestBuilds', '1.4', args.build)
    lua_path = base + '.lua'
    json_path = base + '.letools.json'
    for p in (lua_path, json_path):
        if not os.path.isfile(p):
            print(f"ERROR: not found: {p}", file=sys.stderr); sys.exit(2)

    leb = extract_output(lua_path)
    letools = parse_letools(json_path)

    rows = []
    for (tab, name), key in MAPPING.items():
        lt = num(letools.get(tab, {}).get(name))
        lv = leb.get(key)
        if lt is None or lv is None: continue
        d = lv - lt
        pct = abs(d) / abs(lt) * 100 if abs(lt) > 1e-9 else (float('inf') if abs(d) > 1e-9 else 0)
        if not args.all and pct <= args.threshold: continue
        # @leb-regression-guard:diff-letools-abs-tolerance-floor (consume site).
        # Drop sub-TOL_ABS rows: LETools UI integer-rounding noise floor.
        if not args.all and abs(d) <= TOL_ABS: continue
        rows.append((tab, name, key, lt, lv, d, pct))

    rows.sort(key=lambda r: -r[6])
    hdr = f"{'Tab':8s} {'Stat':40s} {'LEB key':32s} {'LETools':>10} {'LEB':>10} {'D':>10} {'|D%|':>8}"
    print(hdr); print('-' * len(hdr))
    shown_gaps = []
    for tab, name, key, lt, lv, d, p in rows:
        ps = f"{p:.1f}" if p != float('inf') else 'inf'
        marker = ' *' if (tab, name) in KNOWN_SEMANTIC_GAPS else ''
        print(f"{tab:8s} {name:40s} {key:32s} {lt:>10.4g} {lv:>10.4g} {d:>+10.4g} {ps:>8}{marker}")
        if (tab, name) in KNOWN_SEMANTIC_GAPS:
            shown_gaps.append((tab, name))
    print(f"\n{len(rows)} / {len(MAPPING)} stats shown (threshold |D%| > {args.threshold})")
    if shown_gaps:
        print("\n* Known semantic gap (not necessarily a LEB bug):")
        for tab, name in shown_gaps:
            print(f"  [{tab}] {name}:")
            for line in KNOWN_SEMANTIC_GAPS[(tab, name)].splitlines():
                print(f"    {line}")

if __name__ == '__main__':
    main()
