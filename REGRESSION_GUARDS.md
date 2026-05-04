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
