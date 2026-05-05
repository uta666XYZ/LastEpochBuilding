# Regression Guards

Index of `@leb-regression-guard` markers in the source tree.

A regression guard is a comment block placed directly above a fix that
- has a non-obvious correctness contract,
- has been broken-and-fixed at least once, and
- has a busted spec that locks in the invariant.

**Before editing code below an `@leb-regression-guard`, run the linked spec.**
If the spec passes after your edit, the invariant still holds and you're fine.
If it fails, your edit silently regressed a previous fix — read the linked
establishing commit and the spec rationale before forcing the change through.

To find every guard:

```sh
grep -rn '@leb-regression-guard' src/ spec/
```

## Active guards

### `affix-kind-roundtrip`

Sealed / corrupted / primordial affixes are routed into separate display
buckets via an `affix.kind` field. The tag must survive
`Import → BuildRaw → ParseRaw → Craft`. If any leg drops the tag, sealed
Legendary Affixes (purple in LETools) re-appear above unique inherent mods
instead of below them.

| Site | File | What it does |
|---|---|---|
| import (UNIQUE/LEGENDARY branch)   | `src/Classes/ImportTab.lua` (~line 1310) | Forwards `affix.kind` from `ConvertLEToolsItem.pushAffix` into `item.prefixes/suffixes` entry |
| import (Magic/Rare/Exalted branch) | `src/Classes/ImportTab.lua` (~line 1380) | Same, in the non-unique branch |
| serialize (BuildRaw)               | `src/Classes/Item.lua` (~line 990)       | Emits `Prefix: {kind:sealed}{range:...}<id>` ahead of the range tag |
| deserialize (ParseRaw)             | `src/Classes/Item.lua` (~line 444)       | Strips `{kind:...}` before `{range:...}` and forwards onto entry.kind |

**Spec:** `spec/System/TestItemParse_spec.lua`
- "Affix kind tag round-trips through BuildRaw/ParseRaw"

**Establishing commit:** `92db3d1d6` — _fix(items): preserve affix kind through import for sealed/corrupted bottom-of-list display_

### `affix-display-order`

`Item:Craft` assembles `explicitModLines` from six per-kind buckets and
appends them in canonical LE-tooltip / LETools order:

```
gear   : implicits → prefix1, prefix2 → suffix1, suffix2 → sealed → primordial → corrupted
unique : implicits → prefix1, prefix2 → suffix1, suffix2 → unique mods → corrupted
idol   : prefix1, prefix2 → suffix1, suffix2 → enchant1, enchant2 → corrupted
```

Routing rules: `specialAffixType==6 || kind=="corrupted"` → corrupted bucket;
`kind=="sealed"` → sealed; `kind=="primordial"` → primordial;
`specialAffixType==4` → enchant; otherwise prefix or suffix by `listIdx`.

| Site | File |
|---|---|
| bucket assembly | `src/Classes/Item.lua` `function ItemClass:Craft()` (~line 1149) |

**Spec:** `spec/System/TestItemParse_spec.lua`
- "Craft places sat==6 corrupted affix at the bottom of explicitModLines"

**Establishing commit:** `4a95318ac` — _fix(items): canonical affix display order via per-kind buckets in Craft()_

### `idol-altar-not-idol-slot`

The `"Idol Altar"` slot is the equipment slot for an Idol Altar base item
(e.g. Archaic Altar) — it is NOT one of the `Idol N` / `Omen Idol N` cells
in the idol grid. CalcSetup classifies corrupted equipment into three
buckets feeding StatThreshold tags:

- `CorruptedItemsEquipped` — all corrupted gear
- `CorruptedNonIdolItemsEquipped` — corrupted gear NOT in idol cells
- `CorruptedIdolItemsEquipped` — corrupted gear IN idol cells

A naive `slotName:sub(1, 5) == "Idol "` matches both `"Idol 1..N"` and
`"Idol Altar"`, putting a corrupted altar in the wrong bucket and breaking
`+N to All Attributes with at least N Corrupted non-Idol Items equipped`
(Shroud of Obscurity etc.). Independently, the three counters are emitted
into `modDB` only — `ModStore:GetStat` resolves StatThresholds against
`actor.output[stat]`, so without an explicit publish step the threshold
sees 0 and never trips.

| Site | File | What it does |
|---|---|---|
| classifier | `src/Modules/CalcSetup.lua` (~line 826) | Excludes `"Idol Altar"` from the idol-slot prefix match |
| publish    | `src/Modules/CalcPerform.lua` (~line 218) | Copies the three counters from `modDB:Sum` to `output` BEFORE the Attributes loop so StatThreshold tags resolve correctly |

**Spec:** `spec/System/TestModParse_spec.lua`
- "Corrupted Idol Altar counts as non-Idol for CorruptedNonIdolItemsEquipped"

**Establishing build:** Qqwv73q2 lv62 Warlock — Vit reported by LEB rose
from 35 to **47** after fix (live import via `HeadlessWrapper`, which uses
the in-game-matching floor rounding). LETools reports 44; the remaining
+3 is a LETools-side display difference on Legends Entwined
`+(2-5) per Complete Set`: byte=203, range=2-5, in-game tooltip shows
`+5 per Complete Set` and Ghidra-verified LE formula `2 + (203/256)*4 = 5.17 → 5`,
so LEB's 5 × 6 sets = 30 matches LE; LETools shows 4.5 × 6 = 27.
**No remaining residual** — earlier "+2 still under investigation" was a
phantom caused by reading the snapshot file (`.lua` regen output), which
uses LETools-compatible round-half-up rounding (`itemLib.useLEToolsRounding=true`,
introduced 2026-05-04 in `src/HeadlessWrapper.lua`) and naturally diverges
from live-import floor rounding by ±1 per affix using `applyRange`.

**Establishing commit:** `e9e4e64c5`

### `applyrange-rounding-mode-split`

`itemLib.useLEToolsRounding` is a two-mode switch for the per-affix
rounding of `% increased/reduced/more/less` lines:

- **`false` (default, production / live LEB GUI)** — floor, matches in-game
  tooltip per-affix display.
- **`true` (spec / Generate14 / snapshot regen)** — round-half-up, matches
  LETools / Maxroll display, which the `.lua` snapshot fixtures were
  generated against.

`Launch.lua` (the GUI entrypoint) does NOT flip this, so the default `false`
is what end-users see. `HeadlessWrapper.lua` flips it to `true` after
`OnInit` so every busted spec / snapshot regen runs in LETools-compat mode.

This means the same build can produce two different stat values:

| Path | Rounding | Example: Qqwv73q2 lv62 Warlock Vit |
|---|---|---:|
| Live LEB GUI (Launch.lua → no flip → default false) | floor | 47 (= in-game) |
| `busted --run=generate14` (HeadlessWrapper → flip to true) | round-half-up | 49 (= LETools-style) |

The split is intentional but easy to break in two ways:

1. Changing the default in `ItemTools.lua` to `true` silently shifts every
   live user's stat readout by ±1/affix and re-introduces the ShutFackUp
   Mercurial Shrine Boots `(20-24)% reduced` regression (LEB 79% vs
   in-game 78%, fixed 2026-05-04).
2. Removing the `HeadlessWrapper` flip de-syncs all `.lua` snapshots from
   LETools by the same ±1/affix and makes `node scripts/letools-diff.js`
   noisy with rounding artefacts; also causes phantom triangulation
   residuals like the Qqwv73q2 "+2 Vit unexplained" investigated and
   resolved on 2026-05-05.

| Site | File | What it does |
|---|---|---|
| default | `src/Modules/ItemTools.lua` (~line 21) | `itemLib.useLEToolsRounding = false` — production / GUI default |
| flip    | `src/HeadlessWrapper.lua` (~line 173) | After `OnInit`, sets it to `true` so spec/ keeps LETools-compat |
| consumer | `src/Modules/ItemTools.lua` (~line 232) | `applyRange` switches floor/round on this flag for `Integer` percent affixes |

**Spec:** `spec/System/TestItemTools_spec.lua` —
`describe("applyRange rounding mode (production vs LETools)")`
- "HeadlessWrapper enables LETools mode for spec/ runs"
- "production (floor) matches in-game tooltip on % reduced affix"
- "LETools mode (round-half-up) matches LETools display on the same affix"

**Establishing commits:** `73d6a712c` (rounding split), `d37e97271` (merge)

**Triangulation rule** (when comparing LEB ↔ in-game ↔ LETools):
- LEB live (GUI) value = floor = in-game match
- LEB snapshot (`.lua`) value = round-half-up = LETools-compat
- Don't compare snapshot value to in-game; don't compare live value to
  LETools by ±1/affix tolerance — they're meant to use different rounding.

### `set-bonus-breakdown-publish` / `set-bonus-breakdown-bridge`

The Calcs-tab "Set Bonuses" section is gated on `output.SetBreakdown`,
which is bridged from `env.itemModDB.setBreakdown` in CalcPerform. The
producer side (`CalcSetup.applySetBonuses`) builds that structured table
alongside the existing `multipliers["CompleteSetCount"]` counter:

```lua
env.itemModDB.setBreakdown = {
    completeSetCount = N,
    wildcardCount    = #wildcardItems,
    sets = { {setId, name, pieceCount, setSize, complete, bonuses}... },
}
```

Pure UI surface — no calc reads `output.SetBreakdown` or the breakdown
table, so a regression here never moves a stat number. That makes
TestBuilds snapshot diff blind to it: removing either the producer or
the bridge silently hides the entire section without any test-suite
signal. The paired guards exist precisely because this failure mode
has no other tripwire.

| Site | File | What it does |
|---|---|---|
| produce | `src/Modules/CalcSetup.lua` `applySetBonuses` (~line 215) | Builds and assigns `env.itemModDB.setBreakdown` after the `CompleteSetCount` multiplier |
| expose  | `src/Modules/CalcSetup.lua` (~line 250) | `calcs.applySetBonuses = applySetBonuses` so the spec can drive the function without spinning up the full env pipeline |
| bridge  | `src/Modules/CalcPerform.lua` (~line 234) | Copies `setBreakdown` to `output.SetBreakdown` / `output.CompleteSetCount` and assembles `breakdown.SetBreakdown` lines |
| render  | `src/Modules/CalcSections.lua` (~line 755) | Section gated on `haveOutput = "SetBreakdown"`, frame color `colorCodes.SET` |

**Spec:** `spec/System/TestSetBreakdown_spec.lua`
- "publishes empty-friendly state when no set items equipped"
- "publishes setBreakdown with sets[] and bonuses for one set piece"
- "flags a set complete and emits the tier-2 bonus when fully equipped"
- "counts wildcard items separately from real set pieces"

**Establishing commit:** `f7b598ede` — _feat(calcs): show equipped set bonuses in Calcs tab_

### `int-truncate-life-mana`

LE stores `BaseHealth.maxHealth` and `maxMana` as `int` (dump.cs:155378
and 178322). C# `float → int` assignment truncates toward zero, which
equals `floor` for positive values. So a build computing `1258 × 1.25 =
1572.5` shows **1572** in-game, not 1573.

LEB previously matched upstream PoB (`round`), which diverged from
in-game by +1 on every `.5`-exact total. Switching to `m_floor` is a
deliberate LEB-vs-PoB divergence for in-game parity, **not a port-back
candidate**.

The tripwire is the Acolyte lv1 default mana: `50 + 0.50506 + 2 = 52.5`
→ `floor = 52`, `round = 53`. Any revert to `round()` flips this
assertion immediately.

| Site | File | What it does |
|---|---|---|
| Life | `src/Modules/CalcPerform.lua` `doActorLifeMana` (~line 65) | `output.Life = m_max(m_floor(...), 1)` |
| Mana | `src/Modules/CalcPerform.lua` `doActorLifeMana` (~line 84) | `output.Mana = m_floor(calcLib.val(modDB, "Mana"))` |

**Spec:** `spec/System/TestModParse_spec.lua`
- "effect doubled" — assertions `Mana == 52` (default Acolyte) and `Mana == 952` (with `+900 maximum mana`). Both flip to 53/953 under `round`.

**Establishing commit:** `153d4e455` — _fix(calc): floor maxHealth/maxMana to match in-game truncation_

### `unique-req-level-override`

UNIQUE / LEGENDARY items can specify a lower required level than their
base type — Vaion's Chariot is lvl 50 even though its Solarum Greaves
base is lvl 67. Without an override, `Item.lua` falls back to
`self.base.req.level` and CalcSetup's LevelReq filter
(`CalcSetup.lua:858-865`) drops the entire item when
`character.level < base.req.level`, even at levels where the unique is
equippable in-game. This silently zeroes out every stat the item
contributes — implicits, unique mods, and crafted slammed mods — and
typically shows up as a missing slot row in the breakdown panel plus
a multi-stat resistance / armor / movement-speed deficit.

**Pattern B refinement (2026-05-05):** Extracted `overrideLevelRequirement`
flag from game data and gate the override on it. Pre-fix, the check
`if u.req and u.req.level` was truthy on Lua's `0`, so any unique whose
extracted entry had `req.level=0` (the placeholder for non-overriding
uniques) would collapse `requirements.level` to 0 — wiping the legitimate
base req. Game data shows 163/471 uniques have `overrideLevelRequirement
= false` (Snowdrift on Outcast Boots base 23, Horn of the Bone Wisp on
Ivory Wand base 31, etc.), so they must keep the base req.

The fix mirrors the existing SET item override (Item.lua:798) at two
sites: post-ParseRaw and inside `Item:Craft()`. Both sites must override
because Craft() resets `self.requirements.level = self.base.req.level`
unconditionally on every recraft pass (XML round-trip with crafted slots
re-runs Craft via `_craftingInternal`).

| Site | File | What it does |
|---|---|---|
| post-ParseRaw | `src/Classes/Item.lua` (~line 824 after the SET override) | Look up `data.uniques` by `u.name == self.title`; if `u.overrideLevelRequirement` AND `u.req.level` exists, override `self.requirements.level` |
| Craft()       | `src/Classes/Item.lua` (~line 1192 after the SET override in Craft) | Same override, re-applied after Craft resets to base req.level |

Sibling guard for SET items: `Item.lua:751, 778, 797, 1180` use
`e.req.level > 0` so SET entries with `req.level=0` (e.g. native
"The Last Bear's Scorn") fall back to base req.

**Specs:** `spec/System/TestItemParse_spec.lua`
- "Unique req.level overrides base req.level (UNIQUE/LEGENDARY)" — Vaion's Chariot (override=true, lv 50) on Solarum Greaves (base 67) → 50
- "Unique with overrideLevelRequirement=false keeps base req.level" — Snowdrift (override=false, placeholder 0) on Outcast Boots (base 23) → 23

Both specs assert immediately after `CreateDisplayItemFromRaw` and after
a follow-up `item:Craft()` call.

**Establishing commits:**
- `5a88e7161` — _fix(items): override base req.level with unique req.level for UNIQUE/LEGENDARY_
- _Pattern B fix_ — gate override on `overrideLevelRequirement` flag; SET sibling fix `> 0`

### `pattern-a-affix-level-req`

LE's in-game level requirement for an item is not just `base.req.level` —
it is `max(base, affix-tier-derived)`. The game function
`ItemData::CalculateLevelRequirementAfterShard` (decoded from
`GameAssembly.dll` RVA `0xeea910`) sums an inner-cost per contributing
affix tier, plus an outer-cost based on the highest contributing tier:

- **inner_cost** (0-indexed tier, T1=0..T7=6): `{0:1, 1:3, 2:6, 3:10, 4:14, 5:15, 6+:16}`
- **outer_cost** (0-indexed max tier): `{0:2, 1:6, 2:12, 3:20, 4:28, 5:30, 6+:32}`
- `fVar = -10 + sum(inner_cost[t] for t in contributing) + outer_cost[max_t]`
- `req = max(base_req, clamp(fVar, 1, 90))`

Affixes are "contributing" iff `specialAffixType == 0 AND sealedAffixType
== 0` — exactly mirroring `ItemAffix::CanContributeToLevelRequirement`
(RVA `0xf03620`, body: `return p->specialAffixType == 0 && p->sealedAffixType == 0`).
In LEB terms: the affix entry has no `kind` tag (sealed / primordial /
corrupted all set kind) AND the resolved mod's `specialAffixType` is 0
(excludes Reforged set affixes, idol enchant/weaver, sat==6 corruption-
only mods, etc.). Pre-fix, `Item.lua` left `requirements.level` at base, so
crafted items whose tiers pushed the in-game req to 77 / 80 / 95 displayed
as e.g. 41 (Scrivening Quill of Endurance) or 58 (Spidersilk Sash). The
LevelReq filter in CalcSetup let unwearable items contribute stats.

The fix lives in `computeAffixDerivedLevelReq` (Item.lua near top) and is
called from two sites — same dual-site pattern as `unique-req-level-override`:

| Site | File | What it does |
|---|---|---|
| post-ParseRaw | `src/Classes/Item.lua` after the unique override | Compute affix-derived req; if greater than current `requirements.level`, raise it |
| Craft()       | `src/Classes/Item.lua` after the unique override in Craft | Re-apply so the formula survives recraft / XML round-trip |

Tier is parsed from `affix.modId:match("_(%d+)$")` — LEB stores affix ids
as `"<baseId>_<tier>"` where tier is 0-indexed (matches game encoding at
`affix+0x12` byte).

**Specs:** `spec/System/TestItemParse_spec.lua`
- "Pattern A: affix tiers raise req.level above base req" — 4× tier-5 suffixes on Refuge Armor (base req=0) → 80
- "Pattern A: specialAffixType!=0 affix doesn't contribute to req" — sat==6 affix `1002_0` only → req stays at base
- "Pattern A: sealed/corrupted kind affixes don't contribute to req" — 3 plain + 1 sealed → 65

**Pattern C status (Runed Visage / Astrolabe small diffs):** Bakbr2Ne items
where LETools showed +2 / +3 over base were investigated. After applying
the decoded `AfterShard` formula (incl. exact `CanContributeToLevelRequirement`
filter), Astrolabe and Runed Visage compute to their base req unchanged
(Astrolabe 50, Runed Visage 63). The +2 / +3 LETools discrepancies do
NOT come from this in-game function and are most likely a LETools-side
display quirk — left as-is to match the in-game tooltip rather than
LETools. If a future fix targets LETools parity here it must NOT regress
the Pattern A specs.

**Establishing commits:**
- _Pattern A fix_ — port `CalculateLevelRequirementAfterShard` to Lua; raise `requirements.level` post-unique-override at both sites

### `unique-data-integrity`

Within-version invariants for hand-migrated unique data. When LE ships a
new patch and uniques are re-extracted from game files, copy-paste and
range-collapse mistakes have historically slipped in. The 1.4 migration
(2026-05-05) caught three:

- **Legends Entwined (id=423)** — wildcard line `"Counts as a part of every equipped item set"` listed twice in `mods`.
- **Raindance (id=147)** — `(10-13)% increased Movement Speed` listed twice (legitimate dual-MS uniques like 1_2/1_3 Raindance differ in *range*; same-text duplication is the bug).
- **Zeurial's Hunt (id=251)** — second penetration line was a copy-paste of the first with Bow/Throwing direction not swapped.

The guarded invariant:

**DUP_LINE** — no exact-string mod line appears twice in a single unique's
`mods` array. The two real cases where it looks like a dup (Zeurial's Hunt
direction-pair, Raindance dual-MS in 1_2/1_3) both differ in text or range,
so exact-string equality is the correct equivalence.

ROLLID_LEN (parallel `len(rollIds) == len(mods)`) is *not* checked from
Lua because JSON `null` becomes Lua `nil` and `#rollIds` becomes
unreliable on sparse arrays. That check lives in the Python audit
(`.tmp/audit_uniques_1_4_regression.py`) for one-shot use during
migration. Cross-version (1_3 → 1_4) `ROW_DROP` / `RANGE_COLLAPSE` checks
are also Python-only — they're false-positive heavy in 1.4 because boots
base implicits moved out of each unique into `bases_1_4.json`.

| Site | File | What it does |
|---|---|---|
| data | `src/Data/Uniques/uniques_1_4.json` | Source of truth for 1.4 uniques |

**Spec:** `spec/System/TestUniqueDataIntegrity_spec.lua`
- "no unique has duplicate mod lines (DUP_LINE)"

**One-shot audit:** `.tmp/audit_uniques_1_4_regression.py` — DUP_LINE + ROLLID_LEN + cross-version ROW_DROP + RANGE_COLLAPSE.

**Migration recipe for the next LE patch (1.5+)**, replaying the 1.4
playbook so the next person doesn't trip the same false positives:

1. Run the within-version spec: `bash scripts/regen-shards.sh` then
   `docker compose run --rm busted-tests busted --filter=TestUniqueDataIntegrity`.
   Catches DUP_LINE.
2. Run the Python audit (or copy `.tmp/audit_uniques_1_4_regression.py`
   to `.tmp/audit_uniques_1_5_regression.py` and rebind `P14`/`P13`).
   Triage real DUP_LINE / RANGE_COLLAPSE / ROLLID_LEN immediately.
3. ROW_DROP needs base-implicit subtraction. The 1.4 migration moved
   boots/quiver/sword implicits out of each unique into `bases_1_4.json`,
   so naive cross-version diff flagged 9 false positives (Eterra's Path,
   Suloron's Step, Transient Rest, Raindance, Snowdrift, Foot of the
   Mountain, Stealth, Clotho's Needle, Army of Skin). Use
   `.tmp/verify_base_implicit_migration.py` (or its 1_5 equivalent) to
   subtract base implicits — anything still flagged after subtraction is
   a real ROW_DROP. The verification script matches by
   `(baseTypeID, subTypeID)` and compares range-stripped shapes.
4. Use in-game tooltip screenshots from the user as the final ground
   truth for any unique that still looks suspicious after step 3.

### `regen-pct-shorthand-inc`

LE in-game text uses the shorthand `+N% Mana Regen` / `+N% Health Regen`
(without the word "increased") for what is, in the game's authoritative
`localized_master.json`, a `modifierType=1` (INC) modifier. ModParser's
`BASE_MORE` form classifier already had a per-stat exception for the same
shorthand on `Life` / `Mana` / `Ward`; without `ManaRegen` / `LifeRegen`
in that exception list, the form falls through to the default `BASE`
classification and the affix becomes flat `+N` regen instead of `N%
increased` regen.

Concretely on Qqwv73q2 lv62 Warlock: Keplahan's Cryolith Reforged Copper
Ring's sealed `+(8-9)% Mana Regen` was treated as `+8` flat BASE,
inflating Mana Regen by ~+15.5/s (LE 16.72 vs LEB 32.20 prior to fix).

| Site | File | What it does |
|---|---|---|
| classifier | `src/Modules/ModParser.lua` (~line 2017) | Adds `ManaRegen` / `LifeRegen` to the existing `Life`/`Mana`/`Ward` BASE→INC override under `BASE_MORE` form |

The override is gated on `not hasModSuffix` so flag-suffixed forms
(e.g. `+8% Mana Regen with X`) keep the explicit BASE/INC chosen by
their suffix descriptor.

**Spec:** `spec/System/TestModParse_spec.lua`
- "LE shorthand '+N% Mana Regen' parses as INC"
- "LE shorthand '+N% Health Regen' parses as INC"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `refracted-slot-overlap-only`

`ItemsTab:AutoPopulateOmenIdolSlots` decides which idols on the 5x5 layout
become Omen Idols. The contract: only idols whose footprint overlaps a
Refracted (`grid` cell type=2) cell qualify; idols that sit entirely on
type-1 cells are skipped even when Omen capacity is unfilled.

If overlapping idols exceed the altar's capacity (`omenIdolCapacity` +
`MaximumOmenIdols` sealed-affix bonus), only the lowest-numbered Idol slots
fit; the rest are dropped, matching the in-game rule that a 1x2 idol cannot
occupy a 1-cell remaining capacity.

A regression here silently mis-counts `+N per Idol in a Refracted Slot`,
`HealthPerEquippedOmenIdol`, and `cloneWithAltarBoost` prefix/suffix scaling
because every downstream consumer reads `Omen Idol N` slot contents.

| Site | File | What it does |
|---|---|---|
| auto-populate | `src/Classes/ItemsTab.lua` `AutoPopulateOmenIdolSlots` (~line 1186) | Walks IDOL_GRID_LAYOUT, tests footprint vs altar.grid type-2, fills Omen Idol N up to capacity by Idol-slot-number order |
| import path comment | `src/Classes/ImportTab.lua` (~line 2006) | Documents the refracted-only spec for future readers |

**Spec:** `spec/System/TestRefractedSlots_spec.lua`
- "places Grand Idol at (1,2) into Omen Idol 1 (covers refracted cell (1,3))"
- "excludes idols that do not touch any refracted cell"
- "with capacity 2, places Idol 1 and Idol 18 (both overlap), skips non-overlapping Idol 4"
- "when overlapping idols exceed capacity, drops higher-numbered Idol slots"
- "clears stale Omen Idol entries when no altar is active"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `idol-altar-capacity-tooltip`

The Idol Altar item tooltip carries an `Omen Idol capacity: N` line so the
user can read base capacity without opening the altar. The value MUST come
from `IDOL_ALTAR_LAYOUTS[baseName].omenIdolCapacity` — not from live slot
counts (which mutate with sealed `+(N) Maximum Omen Idols Equipped` bonuses)
and not from a hardcoded constant (which silently drifts when a 1.4+ patch
ships a new altar base).

A regression here either omits the line entirely (user can't see capacity)
or mis-reports a stale/hardcoded number (user trusts the wrong figure when
slotting idols in `AutoPopulateOmenIdolSlots`).

| Site | File | What it does |
|---|---|---|
| tooltip emit | `src/Classes/ItemsTab.lua` `AddItemTooltip` (~line 2467) | Looks up layout by `item.baseName`, emits `Omen Idol capacity: N` when present |

**Spec:** `spec/System/TestIdolAltarTooltip_spec.lua`
- "Archaic Altar tooltip shows base capacity 1"
- "tooltip omits capacity line when baseName is unknown to layout"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `regen-alias-coverage`

`ModParser.lua` aliases must register **both** the short (`Regen`) and long
(`Regeneration`) forms of regen affix nouns:

- `health regen` and `health regeneration` → `LifeRegen`
- `mana regen` and `mana regeneration` → `ManaRegen`

In-game tooltips use both forms — verified via screenshots (2026-05-05; see
Obsidian "Web版着手プラン.md"). Some tiers / bases (e.g. `Bountiful Small
Weaver Idol`, `Sentinel's Leather Helm of Life`) render as
`Regeneration`, while others (`Restful Small Weaver Idol`, Wand implicits,
unique mods) render as `Regen`. If only the short form is registered, all
`% increased Health Regeneration` / `% increased Mana Regeneration` affixes
silently drop from the calc (parses but maps to nothing → 0% applied).

| Site | File | What it does |
|---|---|---|
| alias table | `src/Modules/ModParser.lua` (~line 59-64) | Registers both `regen` and `regeneration` keys for Life and Mana |

**Spec:** `spec/System/TestRegenAlias_spec.lua`
- "'% increased Health Regen' parses to LifeRegen INC"
- "'% increased Health Regeneration' parses to LifeRegen INC"
- "'% increased Mana Regen' parses to ManaRegen INC"
- "'% increased Mana Regeneration' parses to ManaRegen INC"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `curse-spell-damage-stat`

`+N Curse Spell Damage` (e.g. Hexed Grand Bone Idol prefix, ModItem affix
49629 family; 1.3/1.4 unique rolls "+(66-91) Curse Spell Damage") must
parse cleanly with **no residual `extra`** so the item tooltip does not
render the line as red `UNSUPPORTED` text. The affix flows as flat spell
damage to skills with the Curse skill type (Bone Curse, Torment,
Decrepify, Anguish, Penance) via the existing
`skillModList:Sum("BASE", cfg, "Damage")` path in `CalcOffence.lua`.

Implemented as a tagged `modNameList` entry rather than a dedicated
`CurseSpellDamage` stat, so no new wiring is required:

```lua
["curse spell damage"] = { "Damage",
    keywordFlags = KeywordFlag.Spell,
    tag = { type = "SkillType", skillType = SkillType.Curse } },
```

Without this entry, `Curse` is left as residual after the parser matches
`Spell Damage` → `Damage` BASE, setting `modLine.extra = " Curse   "`
which `ItemTools.formatModLine` colors as `UNSUPPORTED` (`^xF05050`).

| Site | File | What it does |
|---|---|---|
| alias table | `src/Modules/ModParser.lua` (~line 311-323) | Registers `curse spell damage` with `Damage` name + Spell keyword + SkillType.Curse tag |

**Spec:** `spec/System/TestCurseSpellDamage_spec.lua`
- "'+8 Curse Spell Damage' parses to Damage BASE with no residual extra"
- "'+8 Curse Spell Damage' carries SkillType.Curse tag"
- "'+66 Curse Spell Damage' (uniques_1_4 high roll) parses cleanly"

**Note:** Stale `src/Data/ModCache.lua` entries pre-dating this fix were
stripped (10 entries with `extra=" Curse   "`). The cache is regenerated
on first GUI load.

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `potion-slots-no-character-base`

`output.PotionSlots` has NO character/class base — the only source is the
belt's `+N Potion Slots` implicit (and any sealed / crafted `+N Potion
Slots` mod). LE planner tooltip on Qqwv73q2 lv62 Warlock confirms: belt
`Isadora's Tomb Binding` implicit `+3 Potion Slots` → display
"Potion Slots: 3" (no character base added).

The previous `output.PotionSlots = 3 + modDB:Sum("BASE", nil, "PotionSlots")`
double-counted the belt mod (3 + 3 = 6 vs LE's 3) and would also report
3 for beltless builds vs LE's 0. Any revert to `K + modDB:Sum(...)` for
non-zero `K` immediately drifts every belted build by `+K` and every
beltless build away from in-game's 0 baseline.

| Site | File | What it does |
|---|---|---|
| compute | `src/Modules/CalcDefence.lua` (~line 1416) | `output.PotionSlots = modDB:Sum("BASE", nil, "PotionSlots")` — no constant |
| alias   | `src/Modules/ModParser.lua` (~line 154) | `["potion slots"] = "PotionSlots"` |

**Spec:** `spec/System/TestPotionSlots_spec.lua`
- "PotionSlots has no character base (default = 0 with no mods)"
- "PotionSlots equals sum of '+N Potion Slots' BASE mods (3)"
- "PotionSlots stacks BASE mods additively (3 + 2 = 5)"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `block-requires-shield`

LE only grants Block Chance / Block Effectiveness / Block Mitigation when a
Shield is equipped in the off-hand slot. Off-hand Catalyst (Sorcerer/Warlock),
Quiver, dual-wielded weapons, or empty off-hand all yield zero block stats
regardless of accumulated mods. The only documented bypass is the LE constant
`playerPropertyBlockChanceConvertedToParryWithoutShield` (=531) — when set, the
block chance is converted to parry chance instead. We model this as the
`BlockChanceConvertedToParryWithoutShield` / `BlockWithoutShield` flag.

Without the gate, Sorcerer/Warlock builds wearing an Off-Hand Catalyst plus
e.g. Flame Ward's Glacial Reinforcement node would report 10 % Block Chance
in LEB while LE shows 0 — a silent +30 % effective HP overstatement on the
defence sheet.

| Site | File | What it does |
|---|---|---|
| gate | `src/Modules/CalcDefence.lua` (~line 262) | Early-zeroes all Block outputs when neither Weapon 2/3 is `type == "Shield"` and no `BlockWithoutShield` flag is set |

**Spec:** `spec/System/TestBlockShield_spec.lua`
- "BlockChance is 0 with no shield even with +50% Block Chance mod"
- "BlockChance applies with no shield when BlockWithoutShield flag is set"

**Snapshot coverage:** `spec/System/TestBuilds_spec.lua` "test all builds #builds" via
`spec/TestBuilds/1.4/Bakbr2Ne lv86 Sorcerer.{xml,lua}` (Astrolabe off-hand, BlockChance=0).

**Establishing commit:** `df85f92e8`

### `flame-ward-block-toggle`

Flame Ward (treeId `fw3d`) is a 3-second duration defensive buff (LE class
`FlameWardMutator`, dump.cs: `additionalBlockChance` / `wardOnBlock` fields).
Its skill-tree node mods (e.g. `fw3d-8 "Glacial Reinforcement"` `+10% Block
Chance` from `notScalingStats`) are only granted while the buff is active.

LEB historically poured those mods into the player modDB unconditionally,
because Flame Ward fell through the existing `buffSkillTreePrefixes` gate.
The fix extends the gate with a `whileActiveBuffByTreeId` table — those
skills' tree nodes are only applied when the user enables the matching
`Condition:Have<X>` flag from the new `conditionHaveFlameWard` Config option.

**Subtle pitfall:** Flame Ward HAS `SkillType.Buff` set (skillTypeTags=131336
= Buff 131072 + Spell 256 + 8). Splitting the buffSkillTreePrefixes loop into
`if SkillType.Buff then ... else cond ... end` is wrong — Flame Ward enters
the Buff branch and silently bypasses the condition gate, leaking the entire
fw3d-* node set globally. In Bakbr2Ne (4 points in fw3d-7 Frostguard) this
manifested as a +800 Armour over-count (LEB 1926 vs LE 828, Δ+1098). The
correct structure ANDs `condName` into `enabled` regardless of the Buff
branch.

| Site | File | What it does |
|---|---|---|
| gate | `src/Modules/CalcSetup.lua` (~line 1404) | `whileActiveBuffByTreeId = { fw3d = "HaveFlameWard" }`; treeId-prefixed nodes go through the buff-prefix bucketing whose `enabled` is `group.enabled and conditionActive` |
| config | `src/Modules/ConfigOptions.lua` (~line 130) | `conditionHaveFlameWard` check; sets `Condition:HaveFlameWard` FLAG |

**Spec:** `spec/System/TestBlockShield_spec.lua` `describe("FlameWardTreeGate")`
"Bakbr2Ne Armour does not include fw3d tree-node leak when Flame Ward is
inactive" — loads the Bakbr2Ne XML directly and asserts `Armour < 1500`.
Reverting the gate immediately fails this with `Armour=1926`. The snapshot
diff in `TestBuilds_spec.lua` is a secondary runtime check.

**Snapshot coverage:** `spec/System/TestBuilds_spec.lua` "test all builds #builds" via
`spec/TestBuilds/1.4/Bakbr2Ne lv86 Sorcerer.{xml,lua}` — reverting the gate
makes BlockChance flip from 0 (LE-correct, snapshot value) to 10 (Glacial
Reinforcement contribution).

**Establishing commit:** `df85f92e8`

### `elemental-nova-spec-tree-gated-damage-type`

**Status: FIXED.**

Elemental Nova's Fire / Cold / Lightning damage are **tree-gated** in LE: a
type is granted ONLY when the matching "Enables X Nova" specialization node
is allocated (`en6-12` Fire, `en6-2` Ice/Cold, `en6-8` Lightning). LEB
previously treated all three as unconditional base damage in `skills.json`,
which leaked Fire damage onto builds that had not allocated `en6-12`.

Game-file evidence (`<LE_datamining>/extracted/`):

- `prefab_damage.json` — `ElementalNova` baseDamage `[Phys=0, Fire=8, Cold=8,
  Light=8, Necro=0, Void=0, Poison=0]` (the all-enabled template).
- `skills.json` field `skillTreeConversionDamageTags = 14` = Fire(2) +
  Cold(4) + Lightning(8) — LE flag indicating those types are tree-gated.
- `src/TreeData/1_4/tree_1.json` — `en6-2` "Ice Nova" / `en6-8` "Lightning
  Nova" / `en6-12` "Fire Nova" each list `" Enables {X} Nova"` in `stats`.

**Establishing build:** `Bakbr2Ne lv86 Sorcerer`. en6 allocations:
`en6-0,2,4,5,6,8,18,21,24,25,26` — Ice + Lightning, no Fire. LETools
shows Cold + Lightning only on Elemental Nova; LEB shows Fire + Cold +
Lightning. The Fire leak comes from
`src/Data/skills.json` `ElementalNova.stats.spell_base_fire_damage = 8`
unconditionally.

**Fix shape (applied):**
- Removed `spell_base_fire_damage` / `spell_base_cold_damage` /
  `spell_base_lightning_damage` from `src/Data/skills.json`
  `ElementalNova.stats`.
- Added `"+8 Spell {Cold,Lightning,Fire} Damage"` stats to the
  `en6-2` / `en6-8` / `en6-12` nodes in `src/TreeData/1_4/tree_1.json`,
  so each damage type only applies when its enabling node is allocated.
- Cleared the static `TREE_ID_DAMAGE_TYPES["en6"]` entry in
  `src/Classes/SkillsTab.lua` so spec-slot icons resolve via
  `GetDynamicDamageTypesByTreeId` (addSet picks up the per-node
  `"+N Spell <Type> Damage"` stats).

| Site | File | What it does |
|---|---|---|
| skill data | `src/Data/skills.json` `ElementalNova.stats` | No longer lists `spell_base_fire/cold/lightning_damage`; tree-gated instead |
| tree data | `src/TreeData/1_4/tree_1.json` `en6-2/8/12` | Each gate node's `stats` carries the damage grant |
| UI resolver | `src/Classes/SkillsTab.lua` `TREE_ID_DAMAGE_TYPES["en6"]` | Cleared so dynamic resolver drives the spec-slot icons |
| stat map cross-ref | `src/Data/SkillStatMap.lua` (~line 56) | `@leb-regression-guard:` marker; `spell_base_X_damage` keys are still mapped — the gate is achieved by ensuring those keys only appear under allocated tree nodes |

**Spec:** `spec/System/TestElementalNovaDamageType_spec.lua`
- "Bakbr2Ne (no Fire Nova node allocated) does not include Fire damage type on Elemental Nova"

**Establishing commit:** `0898aea9e`

### `tooltip-mod-line-wrap`

Item tooltips in the Items tab — including hover tooltips routed through
`TooltipHost` (item list rows, paperdoll slots, idol grid, etc.) — must
word-wrap long mod lines so they stay inside the tooltip box. Trigger:
the unique mod on `Horn of the Bone Wisp` (Ivory Wand) overflowed the
tooltip horizontally because only `displayItemTooltip` set `maxWidth`;
every other entry path left it unset, so `Tooltip:AddLine` skipped the
wrap branch.

A regression here either re-introduces horizontal overflow or under-counts
wrapped rows in `block.height` so the bottom border crops wrapped text.

| Site | File | What it does |
|---|---|---|
| default maxWidth | `src/Classes/ItemsTab.lua` `AddItemTooltip` (~line 2411) | Sets `tooltip.maxWidth = 458` when caller didn't, so wrap path activates for every item tooltip |
| wrap + height | `src/Classes/Tooltip.lua` `AddLine` | Routes through `main:WrapString` and grows `block.height` by `(size+2) * #wrapped` |

**Spec:** `spec/System/TestTooltipWrap_spec.lua`
- "AddLine wraps a long line at maxWidth into multiple visual rows"
- "AddItemTooltip sets a default maxWidth so item tooltips wrap on hover"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `ward-retention-negative-clamp`

Stable ward and ward-decay-per-second use the formula
`wardLost/s = (0.00005*(W-T)^2 + 0.2*(W-T)) / (1 + 0.5*R)` (verified against
game `ProtectionClass.Update` RVA 0x234B8C0). The game clamps WardRetention
at -90% before the divisor is computed; without that clamp, R <= -200%
drives the divisor to zero or negative and stable ward becomes non-finite
(division by zero / sqrt of negative). Trigger: switching LEB's stable ward
inversion from a tunklab approximation to the verified game formula
exposed this corner case across all four call sites.

A regression here drops `m_max(..., -90)` (or the equivalent clamp constant)
on `WardRetention` before it feeds the `(1 + 0.5 * R/100)` divisor, causing
NaN/Inf ward for builds with very large negative retention.

| Site | File | What it does |
|---|---|---|
| stable ward inversion | `src/Modules/CalcDefence.lua` (~line 404) | Clamps R at -90% before solving `wgain = wardLost/s` for W |
| display decay | `src/Modules/CalcDefence.lua` (~line 442) | Clamps R at -90% in the `wardDecay(W,R)` reporter |
| Sanguine Runestones path | `src/Modules/CalcDefence.lua` (~line 636) | Same clamp on the LifeRegenAppliesToWard recompute |
| post-offence recompute | `src/Modules/CalcPerform.lua` (~line 1268) | Same clamp in the ManaSpentGainedAsWard branch |

**Spec:** `spec/System/TestDefence_spec.lua`
- "ward retention clamped at -90% (negative retention)"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `martyrdom-minion-armour`

The Necromancer Dread Shade specialization node `ds4d3-3` ("Martyrdom")
grants Armour to **minions** per Vitality, not to the player. Verified
against in-game tooltip + LETools planner (the buff is a default-on toggle
that buffs the minion target). Trigger: parsing the raw stat string
`"30 Armour Per Vitality"` routed the bonus to the player's modDB, inflating
player Armour by ~3000 for a 99-Vit Necromancer (the Qdz2yXN3 worst-diff
build had `Tree:ds4d3-3 BASE=2970 PerStat:Vit` flowing into player armour).

A regression here drops the `Minion ` prefix from the stat string in
`tree_3.json`, OR rewrites the `ModCache.lua` entry to a non-`MinionModifier`
shape, OR adds a non-minion `c["NN Armour Per Vitality"]` line. Any of those
restores the player-armour bug.

| Site | File | What it does |
|---|---|---|
| 1.4 tree text | `src/TreeData/1_4/tree_3.json` (node `ds4d3-3`, ~line 10091) | Stat string is `"30 Minion Armour Per Vitality"` |
| 1.3 tree text | `src/TreeData/1_3/tree_3.json` (node `ds4d3-3`, ~line 10055) | Same `"30 Minion Armour Per Vitality"` |
| 1.2 tree text | `src/TreeData/1_2/tree_3.json` (node `ds4d3-3`, ~line 9180) | `"25 Minion Armour Per Vitality"` (older value) |
| ModCache | `src/Data/ModCache.lua` (~line 13730) | `c["25/30 Minion Armour Per Vitality"]` wrap mod in `MinionModifier` LIST |

**Spec:** `spec/System/TestMartyrdomMinion_spec.lua`
- "Martyrdom (ds4d3-3) grants Minion Armour, not player Armour"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `s4-converted-attr-no-base-inherit`

Season 4 introduced four converted attributes (Brutality, Guile, Apathy,
Rampancy) that replace the four base attributes for affected classes.
Earlier LEB releases applied the base-attribute global bonuses (e.g.
Strength's +4% Armour INC PerStat) to the converted attributes on the
false premise that converted attributes inherit base-attribute bonuses.
They do not — verified against in-game LE 1.4 tooltips: Brutality grants
"more melee damage per mana cost" + "reduced damage leeched as health"
only; no Armour INC. Each converted attribute has its own unique passive
effects driven by tooltip text, not by inheritance.

A regression here re-introduces any
`modDB:NewMod(<DefensiveStat>, ..., {type = "PerStat", stat = "<S4Attr>"})`
line in `calcs.initEnv`. For Qdz2yXN3 (Necromancer, Brutality=33) the
re-introduced +4% Armour INC PerStat:Brutality inflated player Armour
Increased by +132%, ~7x over the in-game value.

| Site | File | What it does |
|---|---|---|
| converted-attribute init | `src/Modules/CalcSetup.lua` (~line 659) | Holds the regression-guard comment block; ANY `PerStat:Brutality/Guile/Apathy/Rampancy` mod added here without in-game tooltip evidence is the regression |

**Spec:** `spec/System/TestS4ConvertedAttr_spec.lua`
- "Brutality does NOT grant Armour Increased"
- "Guile does NOT grant base Evasion"
- "Apathy does NOT grant base Mana"
- "Rampancy does NOT grant base Life"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `exulis-all-attributes-range`

The unique amulet `Exulis` (id 469) rolls `+(10-20) to All Attributes`.

**Evidence:**
1. Game data extract `uniques_v3.json` id=469 mod[1] (property=46, All
   Attributes) has `value=10.0, maxValue=20.0`.
2. LETools tooltip displays `+(10 to 20) to All Attributes`.
3. `applyRange` trace with (10-20) reproduces the in-game LEB display:
   byte=156 → `10 + 156/255 * (20-10+1) = 16.73 → floor 16`. Matches
   the user-observed +16 once data was corrected.

An earlier guard locked this as `(10-18)`, based on a misobservation:
a +18 roll seen in-game was actually `+16 from the amulet + 2 from a
separate quest reward`. Conflating those two sources produced the
wrong upper bound. Do NOT widen back to 18, and do NOT narrow further.

A regression here changes the upper bound away from `20` in either
uniques file.

| Site | File | What it does |
|---|---|---|
| 1.4 unique data | `src/Data/Uniques/uniques_1_4.json` (Exulis entry, ~line 9400) | `+(10-20) to All Attributes` |
| legacy unique data | `src/Data/Uniques/uniques.json` (Exulis id 469, ~line 10639) | `+(10-20) to All Attributes` |

Both entries also carry an inline `_leb_regression_guard` JSON field
that documents the source of truth at the data site itself.

**Spec:** `spec/System/TestExulisRange_spec.lua`
- "Data/Uniques/uniques_1_4.json has Exulis '+(10-20) to All Attributes'"
- "Data/Uniques/uniques.json has Exulis '+(10-20) to All Attributes'"

**Establishing commit:** `<unset; bump after first commit on this branch>`

## Adding a new guard

1. Above the fix in source, add a comment block:

   ```lua
   -- @leb-regression-guard: <kebab-case-id>
   -- One sentence on what this protects against.
   -- Test: <spec file> "<it-description>"
   -- Establishing commit: <sha>
   ```

2. Add the busted assertion(s) in `spec/System/TestItemParse_spec.lua` (or a
   sibling spec if a new domain). Tag them with the same comment header.

3. Append a row to this file under "Active guards".

## Layering vs canary strings

Canary strings (`@leb-canary v1 / id:leb-... / do-not-remove`) are file-level
markers that protect against entire modules being deleted or rewritten by a
mass refactor. Regression guards are block-level and protect specific
correctness invariants. Both should be present where they apply; they don't
substitute for each other.
