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

### `idol-altar-canrollon-normalization`

Every entry in `src/Data/ModItem_IdolAltar_1_4.json` must carry
`canRollOn = [41]` (slot id 41 = "Idol Altar"; see
`src/Data/LEToolsImport/slot_mapping.lua` L45).

The Idol Altar mod consumer in `ItemsTabCraft.lua` (the craft-list
builder ~L1117 and the `canRollOnIdol` filter ~L1340) treats an
absent / empty `canRollOn` as **no restriction** — the mod would pass
for any `itemBaseTypeID`. Pre-2026-05-15, only 16 of 160 entries
(1095_* "Maximum Omen Idols Equipped" + 1108_* "Corrupted Idol Limit")
populated the field; the other 144 leaked into non-altar craft pools.

Game-file ground truth (LE 1.4 il2cpp re-extraction, 2026-05-15):
every Idol Altar affixId family used by LEB (1088, 1089, 1092-1109)
ships with `canRollOn: [41]` in
`LE_datamining/extracted/items/single_affixes_v3.json` and
`multi_affixes_v3.json`. The fix normalises the LEB JSON to the
game-file shape — no consumer logic changes.

| Site | File | What it does |
|---|---|---|
| Data | `src/Data/ModItem_IdolAltar_1_4.json` | All 160 entries (20 affixId families × tier counts) carry `canRollOn: [41]` |

**Spec:** `spec/System/TestIdolAltarCanRollOn_spec.lua` (1 test:
iterates `data.itemMods["Idol Altar"]`, asserts every entry has
`canRollOn = {41}`, no missing / no other value).

**Establishing commit:** (this commit)

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

| Site | File | What it does |
|---|---|---|
| classifier | `src/Modules/CalcSetup.lua` (~line 826) | Excludes `"Idol Altar"` from the idol-slot prefix match |
| publish    | `src/Modules/CalcPerform.lua` (~line 218) | Copies the three counters from `modDB:Sum` to `output` BEFORE the Attributes loop so StatThreshold tags resolve correctly |

**Spec:** `spec/System/TestModParse_spec.lua`
- "Corrupted Idol Altar counts as non-Idol for CorruptedNonIdolItemsEquipped"

**Establishing commit:** `e9e4e64c5`

### `equipped-corrupted-idol-multiplier`

Idol Altar corrupted/sealed prefixes such as Spire Altar's T7
`+10 Mana per Equipped Corrupted Idol` (game-data: `src/Data/ModItem.json`
line 65367, parsed in `src/Data/ModCache.lua` line 2036) are encoded with
`tag={type="Multiplier", var="EquippedCorruptedIdol"}`. Multipliers
resolve via `modDB:Sum("BASE", nil, "Multiplier:<var>")`, so without an
emission setting that var the affix evaluates to 0 and contributes
nothing to the host stat — silently. Sibling guard
`idol-altar-not-idol-slot` already counts corrupted items in idol cells
(`Idol N` / `Omen Idol N`) into the local `idol` accumulator and emits
`CorruptedIdolItemsEquipped` (a StatThreshold stat); this guard requires
the same `idol` count to ALSO be emitted as `Multiplier:EquippedCorruptedIdol`
(a Multiplier var) so per-corrupted-idol affixes scale correctly.

| Site | File | What it does |
|---|---|---|
| emission | `src/Modules/CalcSetup.lua` (~line 953) | Emits `Multiplier:EquippedCorruptedIdol = idol` inside the existing `if idol > 0 then` block |

**Spec:** `spec/System/TestEquippedCorruptedIdolMultiplier_spec.lua`
- "emits Multiplier:EquippedCorruptedIdol with BASE type and the idol count"
- "emission sits inside the same `if idol > 0 then` block as CorruptedIdolItemsEquipped"
- "'+10 Mana per Equipped Corrupted Idol' parses to Multiplier:EquippedCorruptedIdol"

### `omen-idol-slot-dedup-on-corruption-count`

Omen Idol slots are NOT independent inventory cells — they are secondary
references to the same physical idol items already placed in `Idol N` grid
cells. `ItemsTab:AutoPopulateOmenIdolSlots` mirrors any idol that overlaps
an Omen Refracted slot into the corresponding `Omen Idol N` slot
(see related guard `refracted-slot-overlap-only`). The Idol-Altar implicit
"+14 Mana per Idol in a Refracted Slot" tooltip explicitly says
"There is no additional benefit to having an idol in multiple refracted slots",
confirming per-physical-item semantics game-side.

The corrupted-item counting loop in `CalcSetup.lua` iterates `items` (and
the level-gated set) and would naively count the same corrupted idol item
twice when it appears under both `Idol N` and `Omen Idol N`. That double

| Site | File | What it does |
|---|---|---|
| dedup | `src/Modules/CalcSetup.lua` (`countItem` closure inside the corrupted-counting `do` block) | Tracks `seenIdolItem[key]` and skips repeated keys so Idol N ↔ Omen Idol N pairs don't double-tally |

**Spec:** `spec/System/TestOmenIdolSlotDedup_spec.lua`
- "declares a `seenIdolItem` table inside the corrupted-counting block"
- "the dedup applies inside the idol-slot branch (skips before incrementing)"
- "dedup state is shared across the active and level-gated iteration loops"

**Establishing commit:** `604eb9975`

### `non-unique-idol-stat-multiplier`

Reliquary Nest (unique relic, id=433, primordial baseTypeID=22 subTypeID=63)
carries property 98 (`nonUniqueIdolStatModifier`, dump.cs offset 0x1C14). The
runtime applies it as a flat (1 + N/100) multiplier on every mod sourced from
a non-unique idol item. Game tooltip text:
`Stats on your Non-Unique Idols have N% increased Effect`. Game-file
verification: `extracted/items/uniques_v3.json` Reliquary Nest entry has
`mods[0]: property=98, value=0.4, maxValue=0.6, type=0` and
`tooltipDescriptions[0]: "Stats on your Non-Unique Idols have [40,60,0]% increased Effect"`.
The runtime field is backed by `currentStatsFromNonUniqueIdolStatModifier`
and `excludedIDsFromNonUniqueIdolStatModifier` lists (per dump.cs); for
LEB's purposes the scaling is "all idol mods, exclude unique/set idols and
the Idol Altar".

| Site | File | What it does |
|---|---|---|
| parse | `src/Modules/ModParser.lua` (specialModList, near IdolRefracted entries) | Parses both forms to `Multiplier:NonUniqueIdolStatEffect` BASE = N |
| pre-scan | `src/Modules/CalcSetup.lua` (just before the orderedSlots merge loop) | Sums `Multiplier:NonUniqueIdolStatEffect` BASE across all items into `nonUniqueIdolEffectPercent`, derives `nonUniqueIdolScale = 1 + N/100` |
| scale | `src/Modules/CalcSetup.lua` (per-slot merge block, before `ScaleAddList(srcList, scale)`) | Multiplies `scale` by `nonUniqueIdolScale` for non-unique idol items |
| adopt | `src/Data/Uniques/uniques.json`, `uniques_1_2.json`, `uniques_1_3.json`, `uniques_1_4.json` | Reliquary Nest mod text uses the game tooltip wording |

**Spec:** `spec/System/TestNonUniqueIdolStatMultiplier_spec.lua`
- "ModParser parses both forms to Multiplier:NonUniqueIdolStatEffect BASE"
- "computes nonUniqueIdolScale = 1 + N/100"
- "excludes Idol Altar and unique/set rarity from the scale"
- "Reliquary Nest text adopts the game tooltip wording"

**Establishing commit:** `a3a279149`

### `corrupted-count-pre-levelreq`

`+N to All Attributes with at least 7 Corrupted non-Idol Items equipped`
(Shroud of Obscurity affix `1011`) and similar Corrupted-count-conditional
affixes use **equipped** semantics: an item occupying a slot is "equipped"
even when its `LevelReq` exceeds the character level (in-game: stats are
inactive but the slot is filled). LEB's `LevelReq` filter at
`CalcSetup.lua` removes such items from `items[slotName]` so their stats
do not contribute, which is correct for damage/defense calc — but the
corrupted-counter loop downstream then under-counts because it iterates
the post-filter `items` table.

| Site | File | What it does |
|---|---|---|
| capture     | `src/Modules/CalcSetup.lua` (~line 869) | Stash every level-gated item into `env._levelGatedAllItems` BEFORE deletion (parallel to `_levelGatedSetItems` for SET membership) |
| count       | `src/Modules/CalcSetup.lua` (~line 905) | Corrupted-counter loop iterates BOTH active `items` AND `env._levelGatedAllItems` so equipped-but-inactive corrupted gear still trips the threshold |

**Spec:** `spec/System/TestModParse_spec.lua`
- "Level-gated corrupted item still counts toward CorruptedNonIdolItemsEquipped"

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

| Site | File | Inline marker | What it does |
|---|---|---|---|
| default | `src/Modules/ItemTools.lua` (~line 21) | `@leb-regression-guard:rounding-mode-default-floor` | `itemLib.useLEToolsRounding = false` — production / GUI default |
| flip    | `src/HeadlessWrapper.lua` (~line 173) | `@leb-regression-guard:rounding-mode-headless-flip` | After `OnInit`, sets it to `true` so spec/ keeps LETools-compat |
| consumer | `src/Modules/ItemTools.lua` (~line 232) | (no marker — switch-site) | `applyRange` switches floor/round on this flag for `Integer` percent affixes |

**Spec:** `spec/System/TestItemTools_spec.lua` —
`describe("applyRange rounding mode (production vs LETools)")`
- "HeadlessWrapper enables LETools mode for spec/ runs"
- "production (floor) matches in-game tooltip on % reduced affix"
- "LETools mode (round-half-up) matches LETools display on the same affix"

**Establishing commits:** `73d6a712c` (rounding split), `d37e97271` (merge)

### `applyrange-fixed-tier-noop`

Affix tiers come in two shapes in the LEB mod data:

- **Fixed-value tiers** — mod text has no `(min-max)` pattern, e.g.
  `"+14 All Attributes with at least 7 Corrupted non-Idol Items equipped"`
  for `1011_6`.
- **Ranged tiers** — mod text has `(min-max)`, e.g.
  `"+(19-21) All Attributes ..."` for `1011_7` (T8, primordial-only).

`applyRange` only mutates lines that match the `(min-max)` regex; fixed
lines pass through untouched. The `range` / `r` byte on a LETools import
is therefore meaningless for fixed tiers — the value is whatever the data
file says, not `min + range/255 * span`.

| Site | File | What it does |
|---|---|---|
| pass-through | `src/Modules/ItemTools.lua` `applyRange` (~line 206) | The `(min-max)` gsub is the ONLY mutation site; fixed lines fall through unchanged |

**Spec:** `spec/System/TestItemTools_spec.lua` —
`describe("applyRange leaves fixed-value tier text unchanged")`
- "affix 1011 T7 (fixed +14) ignores the range byte"
- "affix 1011 T8 (range 19-21) still interpolates as expected"
- "a generic fixed flat-value line is unaffected by range bytes"

### `per-set-fractional-precision`

"per Complete Set" affixes scale with `Multiplier:CompleteSetCount` (the
number of complete sets equipped). LE quantizes the per-source rolled
value to **half-integer (0.5) steps**, multiplies by the set count, then
floors. LEB historically rounded the per-item rolled value to integer
first then multiplied — losing the `0.5×setCount` half-step contribution.

Empirical fit across two builds (2026-05-08), `+(2-5) to All Attributes
per Complete Set`:

| Site | File | What it does |
|---|---|---|
| half-step | `src/Modules/ItemTools.lua` `applyRange` (`precision=2` bump for `per Complete Set` + Integer rounding) | applyRange emits half-integer values (e.g. 2.5, 4.5) instead of integer floor |
| tag the multiplier | `src/Modules/ModParser.lua` `["per complete set"]` | Adds `roundAfterMultiply=true` to the `Multiplier:CompleteSetCount` tag |
| floor after multiply | `src/Classes/ModStore.lua` `EvalMod` (Multiplier branch) | When tag.roundAfterMultiply is set, `value = m_floor(value × mult)` so the half-step × setCount lands on integer |

### `set-bonus-breakdown-publish`

_Paired umbrella section — covers both `set-bonus-breakdown-publish`
(producer side, `CalcSetup.applySetBonuses` building
`env.itemModDB.setBreakdown`) and `set-bonus-breakdown-bridge`
(consumer side, `CalcPerform` copying it to `output.SetBreakdown`).
Both inline markers point here; see also the stub heading below._

The Calcs-tab "Set Bonuses" section is gated on `output.SetBreakdown`,
which is bridged from `env.itemModDB.setBreakdown` in CalcPerform. The
producer side (`CalcSetup.applySetBonuses`) builds that structured table
alongside the existing `multipliers["CompleteSetCount"]` counter:

```lua

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

### `set-bonus-breakdown-bridge`

Stub — see [`set-bonus-breakdown-publish`](#set-bonus-breakdown-publish)
above for the full umbrella description. This ID is the bridge half of
the paired guard: `CalcPerform` (~line 234) copies
`env.itemModDB.setBreakdown` to `output.SetBreakdown` /
`output.CompleteSetCount` and assembles `breakdown.SetBreakdown` lines.
The pair exists because the rendered Calcs section is UI-only and would
otherwise have no test tripwire if either half were removed.

### `set-bonus-dedup-by-uniqueid`

**Spec:** `spec/System/TestSetBreakdown_spec.lua`
- "dedups duplicate uniqueIDs (same set ring in both ring slots)" — two
  copies with identical `uniqueID` ⇒ `pieceCount == 1`.
- "dedups by title when uniqueID is absent (BuildAndParseRaw fallback)" —
  two copies with identical `title` and no `uniqueID` ⇒ `pieceCount == 1`.
- "distinct uniqueIDs in the same set still count separately" —
  guards against over-dedup of genuinely different set pieces.

**Establishing commit:** _(this commit — set-bonus dedup by uniqueID)_

### `set-bonus-wildcard-clamp`

**Spec:** `spec/System/TestSetBreakdown_spec.lua`
- "clamps wildcard contribution to +1 even with multiple wildcard items"
  — two wildcard items + 1 real piece ⇒ `pieceCount == 2`, not 3.
- (existing) "counts wildcard items separately from real set pieces" —
  one wildcard + 1 real piece ⇒ `pieceCount == 2`. Pair locks both the
  positive and the clamp behaviour together.

**Establishing commit:** _(this commit — set-bonus wildcard clamp)_

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

| Site | File | What it does |
|---|---|---|
| post-ParseRaw | `src/Classes/Item.lua` (~line 824 after the SET override) | Look up `data.uniques` by `u.name == self.title`; if `u.overrideLevelRequirement` AND `u.req.level` exists, override `self.requirements.level` |
| Craft()       | `src/Classes/Item.lua` (~line 1192 after the SET override in Craft) | Same override, re-applied after Craft resets to base req.level |

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

| Site | File | What it does |
|---|---|---|
| post-ParseRaw | `src/Classes/Item.lua` after the unique override | Compute affix-derived req; if greater than current `requirements.level`, raise it |
| Craft()       | `src/Classes/Item.lua` after the unique override in Craft | Re-apply so the formula survives recraft / XML round-trip |

**Establishing commits:**
- _Pattern A fix_ — port `CalculateLevelRequirementAfterShard` to Lua; raise `requirements.level` post-unique-override at both sites

### `legendary-affix-derived-levelreq`

Pattern A (above) targets crafted exalted/rare items where affix tiers
push req.level above the base — the in-game function
`CalculateLevelRequirementAfterShard` is what shows e.g. Lv77 / Lv95 on
high-tier crafts. **It must not apply to UNIQUE / LEGENDARY / SET items.**
Per LE rule, "unique + corrupted affix = unique" (corrupted affix does NOT
promote rarity), so a corrupted unique like Font of the Erased keeps its
base/unique req.level even though it carries a T7 corrupted minion-damage
affix. The unique definition (or base item) is the authoritative source
for these rarities — Pattern A would otherwise inflate req.level via
the high-tier slot and silently disqualify the item from the CalcSetup
LevelReq filter.

The gate lives at the very top of `computeAffixDerivedLevelReq`

**Establishing commits:**
- _Legendary affix-derived levelreq gate_ — exclude UNIQUE/LEGENDARY/SET from Pattern A; restore Font of the Erased Ring contribution on Qb6WlPE5

### `unique-data-integrity`

Within-version invariants for hand-migrated unique data. When LE ships a
new patch and uniques are re-extracted from game files, copy-paste and
range-collapse mistakes have historically slipped in. The 1.4 migration
(2026-05-05) caught three:

- **Legends Entwined (id=423)** — wildcard line `"Counts as a part of every equipped item set"` listed twice in `mods`.
- **Raindance (id=147)** — `(10-13)% increased Movement Speed` listed twice (legitimate dual-MS uniques like 1_2/1_3 Raindance differ in *range*; same-text duplication is the bug).
- **Zeurial's Hunt (id=251)** — second penetration line was a copy-paste of the first with Bow/Throwing direction not swapped.

A second wave (2026-05-09) caught two more during Q9J4w8PE Health-diff
triangulation:

- **Aaron's Will (id=272)** — game data has 8 mods; LEB had 10 because both

| Site | File | What it does |
|---|---|---|
| data | `src/Data/Uniques/uniques_1_4.json` | Source of truth for 1.4 uniques |
| data | `src/Data/Uniques/uniques_1_3.json`, `uniques_1_2.json`, `uniques.json` | Older-version unique data; same DUP_LINE / EXPECTED_COUNT invariants |
| data | `src/Data/Set/set_1_4.json` | Set-rarity entries merged into `data.uniques` by `src/Modules/Data.lua` (~line 625); same invariants apply |
| upstream | `LE_datamining/extracted/unique_overrides.json` | Hand-curated overrides applied by `apply_leb_rules.py`. Bugs fixed here (2026-05-09: Aaron's Will, Sunforged Greathelm, Raindance, Legends Entwined, Zeurial's Hunt) prevent regen from re-introducing them downstream |

**Spec:** `spec/System/TestUniqueDataIntegrity_spec.lua`
- "no unique has duplicate mod lines (DUP_LINE)"
- "expected mod counts match game data (EXPECTED_COUNT)"

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

**Spec:** `spec/System/TestModParse_spec.lua`
- "LE shorthand '+N% Mana Regen' parses as INC"
- "LE shorthand '+N% Health Regen' parses as INC"

**Establishing commit:** `7a5fed7e2`

### `butchers-crown-no-mana-regen`

The Butcher's Crown (uniqueID=449) carries a "you cannot regenerate mana"
clause. Game tooltip reads `"You do not Regenerate Mana"`
(`uniques.json` tooltipDescriptions[0]); LEB's unique JSON historically
encodes the same effect as `"100% Disabled Mana Regen"`. ModParser had
no handler for either form, so the line fell through to the generic
chain: the `BASE_MORE` form (`^([%+%-]?[%d%.]+)%%`) consumed the leading
`100%`, the trailing ` Disabled ` was discarded as unparsed text, and
`Mana Regen` was matched as the stat name — yielding a `+100 BASE
ManaRegen` mod, the exact opposite of the intended effect.

Both text variants must produce a `NoManaRegen` FLAG, which
`CalcDefence.lua:602` reads to short-circuit

| Site | File | What it does |
|---|---|---|
| pattern | `src/Modules/ModParser.lua` (~line 942) | `specialModList` entries for `^you do not regenerate mana$` and `^100%% disabled mana regen$` returning `flag("NoManaRegen")` |
| pre-cached entry | `src/Data/ModCache.lua` | Auto-generated `parseModCache` entry for `"100% Disabled Mana Regen"`; updated to the corrected `NoManaRegen` FLAG so historical cache hits don't bypass the new pattern (regenerated automatically by the next `SaveModCache` run) |
| consumer (already present) | `src/Modules/CalcDefence.lua` (~line 602) | `if modDB:Flag(nil, "NoManaRegen") then output.ManaRegen = 0` |

**Spec:** `spec/System/TestModParse_spec.lua`
- "'You do not Regenerate Mana' sets NoManaRegen flag"
- "'100% Disabled Mana Regen' (LEB JSON variant) sets NoManaRegen flag"

**Establishing commit:** `497eaa1cc`

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

**Establishing commit:** `275343209`

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

**Establishing commit:** `4afa13f23`

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

| Site | File | What it does |
|---|---|---|
| alias table | `src/Modules/ModParser.lua` (~line 59-64) | Registers both `regen` and `regeneration` keys for Life and Mana |

**Spec:** `spec/System/TestRegenAlias_spec.lua`
- "'% increased Health Regen' parses to LifeRegen INC"
- "'% increased Health Regeneration' parses to LifeRegen INC"
- "'% increased Mana Regen' parses to ManaRegen INC"
- "'% increased Mana Regeneration' parses to ManaRegen INC"

**Establishing commit:** `4afa13f23`

### `overkill-damage-leech-parser`

The affix `(N)% of Overkill Damage Leeched as Health` must parse to the
`OverkillLeech` summary modifier — **not** the generic `DamageLifeLeech`.
LE applies overkill leech only to damage exceeding the target's remaining
HP, so routing the affix through `DamageLifeLeech` (which `CalcOffence`
sums for every-hit leech) would over-leech every hit while leaving the
sidebar's Overkill Leech row at 0.

Before this guard, `modNameList` had no entry for the full phrase, so
`scan()` picked the generic `damage` name and the `leeched as health`
suffix flag combined to produce `DamageLifeLeech` with `" Overkill   "`
left as unconsumed text. Symptoms (G1 batch #1, 2026-05-07):

- `BgRrP5rr` `OverkillLeech` LE=16 LEB=0

| Site | File | What it does |
|---|---|---|
| alias table | `src/Modules/ModParser.lua` (~line 165-178) | Registers `overkill damage leeched as health` → `OverkillLeech` |

**Spec:** `spec/System/TestOverkillLeech_spec.lua`
- "'11% of Overkill Damage Leeched as Health' parses to OverkillLeech BASE 11"
- "'5% of Overkill Damage Leeched as Health' parses to OverkillLeech BASE 5"
- "does not emit DamageLifeLeech for the overkill affix wording"

**Establishing commit:** `5e0bd9abd`

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

| Site | File | What it does |
|---|---|---|
| alias table | `src/Modules/ModParser.lua` (~line 311-323) | Registers `curse spell damage` with `Damage` name + Spell keyword + SkillType.Curse tag |

**Spec:** `spec/System/TestCurseSpellDamage_spec.lua`
- "'+8 Curse Spell Damage' parses to Damage BASE with no residual extra"
- "'+8 Curse Spell Damage' carries SkillType.Curse tag"
- "'+66 Curse Spell Damage' (uniques_1_4 high roll) parses cleanly"

**Establishing commit:** `4afa13f23`

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

**Establishing commit:** `a379cba0f`

### `game-faithful-block-no-shield-gate`

**Supersedes** the retired `block-requires-shield` guard (see "Retired" note below).

LE has **NO automatic shield gate** on Block Chance / Block Effectiveness /
Block Mitigation. This was established by PyGhidra decompile of
`GameAssembly.dll` (Last Epoch 1.4), dumped to
`<LE_datamining>\extracted\block_decompile.txt`:

- `PrecalculatedStatsHolder.blockChanceForCharacterSheet` (RVA `0x2344F70`)
  returns `min(blockChance, maximumBlockChance)` gated **only** on
  `blockConversion == None`. No reference to shield, off-hand, or item slot.
- `PrecalculatedStatsHolder.GetBlockChance` (RVA `0x2344F00`, runtime roll)
  returns `min(blockChance + extra, maximumBlockChance)` unconditionally.
- `parryChanceForCharacterSheet` (RVA `0x2345390`) folds `blockChance` into
  parry only when `blockConversion == Parry`; again, no shield check.
- The dump.cs constant
  `CharacterMutator.playerPropertyBlockChanceConvertedToParryWithoutShield = 531`
  is the **mod identifier** for the opt-in "Block chance converted to parry
  while not using a shield" mod — it is a *mod-driven* flag that sets
  `blockConversion = Parry`, NOT an automatic LE gate that zeros block.

LEB therefore must accumulate Block Chance / Effectiveness / Mitigation and
LifeOnBlock / ManaOnBlock from item & passive mods unconditionally. Catalyst,
Quiver, dual-wield, and empty off-hand all receive block exactly as LE
computes it. A `Bakbr2Ne lv86 Sorcerer`-style build (Catalyst off-hand, no
block mods anywhere) naturally produces `BlockChance = 0` because the
`baseBlockChance + mods` sum is zero — no separate gate is needed or correct.

| Site | File | What it does |
|---|---|---|
| Block calc | `src/Modules/CalcDefence.lua` (~line 311) | Block Chance / Effectiveness / Mitigation aggregate from mods unconditionally |
| LifeOnBlock / ManaOnBlock (defence pass) | `src/Modules/CalcDefence.lua` (~line 595) | `LifeOnBlock` / `ManaOnBlock` aggregate from mods unconditionally |
| LifeOnBlock / ManaOnBlock (mirrored pass) | `src/Modules/CalcDefence.lua` (~line 836) | Same; mirrored after primary defences |

**Spec:** `spec/System/TestBlockShield_spec.lua` — locks the
game-faithful behavior: block accumulates from mods regardless of shield
equipment; `blockConversion` flag merely retargets the displayed stat.

**Snapshot coverage:** `spec/System/TestBuilds_spec.lua` "test all builds #builds":
- `Bakbr2Ne lv86 Sorcerer.{xml,lua}` (Astrolabe off-hand, no block mods → block=0 naturally)
- 5 G2 builds with Block Chance / Effectiveness on non-shield off-hands now
  surface non-zero block matching LE (BgRrekaR / ozwXn3D8 / AL07Kea4 /
  BOwJnY3Y / BOwJRDD2).

**Decompile artefact:** `LE_datamining/extracted/block_decompile.txt`
(generated by `LE_datamining/run_pyghidra_block.ps1` from
`LE_datamining/decompile_targets_block.json`).

**Establishing commit:** _this commit_ (game-faithful rewrite).

**Retired guard:** `block-requires-shield` — earlier guard introduced in
`df85f92e8` / `af1596c16` based on the misreading of `playerProperty 531` as
an automatic gate rather than a mod identifier. Removed once direct game-file
decompile contradicted the premise; the prior LETools comparison for
Bakbr2Ne (which appeared to confirm a gate) was coincidence — that build
simply has no block mods.

### `game-faithful-parry-conversion`

LE has a **mod-driven** Block→Parry conversion gated on `not UsingShield`,
sourced exclusively (as of LE 1.4) from the unique sword `Clotho's Needle`
(`uniques_1_4.json` #417, baseTypeID 16/15, mod text:
"+1 Block Chance converted to Parry Chance while not wielding a shield").

Game decompile (`LE_datamining/extracted/block_decompile.txt`):
- `CharacterMutator.playerPropertyBlockChanceConvertedToParryWithoutShield = 531`
  is a bool property set by the mod (NOT an automatic gate).
- `parryChanceForCharacterSheet` (RVA `0x2345390`): when
  `blockConversion == Parry`, returns
  `min(blockBase, maxBlock) + parryBonus`, capped at ParryCap
  (`DAT_183d81c00 = 75`). Field offsets: `0x58=blockBase`, `0x64=maxBlock`,
  `0x68=blockConversion`, `0xd0=parryBonus`.
- `blockChanceForCharacterSheet` (RVA `0x2344F70`): returns 0 when
  `blockConversion != None` (the character-sheet displays the converted
  value under Parry, not under Block).

LEB must:
1. Parse the mod into `BlockChance BASE +N` (so it joins the normal block
   pool used by the conversion math) plus a flag mod
   `BlockChanceConvertedToParryWithoutShield`.
2. In CalcDefence, when the flag is set AND `UsingShield` is false,
   set `ParryChance = min(min(BlockChanceTotal, BlockChanceMax) + parryBase, ParryCap)`
   and zero every Block-display stat (Block / ProjectileBlock / SpellBlock /
   SpellProjectileBlock / AverageBlockChance / BlockEffectiveness / BlockMitigation /
   BlockEffect / ShowBlockEffect / DamageTakenOnBlock).
3. Otherwise, fall back to vanilla `ParryChance = min(parryBase, ParryCap)`.

**Stale-parse trap (resolved):** Before this guard, `ModCache.lua` L1325
parsed the mod as a stray `BlockChance BASE +1` with residual unparsed text
`"  converted to Parry Chance while not wielding a shield "`. Item.lua's
non-empty-residue branch silently dropped the entire mod when the residue
lacked a recognized connector, so no current build was affected — but the
fix is required for any future Clotho's Needle equipper. The stale entry
was removed from `src/Data/ModCache.lua`; the explicit ModParser handler
ensures the cache regenerates correctly.

| Site | File | What it does |
|---|---|---|
| ModParser handler | `src/Modules/ModParser.lua` (~line 2068) | Parses the mod into `BlockChance BASE` + `flag("BlockChanceConvertedToParryWithoutShield")` |
| Conversion calc   | `src/Modules/CalcDefence.lua` (~line 1638)  | Routes Block→Parry when flag set + no shield; zeros Block display stats |

**Spec:** `spec/System/TestParryConversion_spec.lua` — 5 cases:
- ModParser emits BlockChance BASE + FLAG
- vanilla parry (no flag)
- conversion (flag + no shield, Parry = converted + 0)
- conversion + ParryBonus stacks under cap
- ParryCap (75) hit when converted+parryBase exceeds it

**Snapshot coverage:** No current build in `spec/TestBuilds/1.4/` equips
Clotho's Needle, so no snapshot exercises the conversion path directly.
The fix is latent-bug-prevention: it ensures the next imported Clotho's
Needle build will surface correct Parry instead of silently dropping
the mod.

**Decompile artefact:** `LE_datamining/extracted/block_decompile.txt`.

**Establishing commit:** _this commit_ (latent-bug fix during non-G2
Parry sweep — 18/19 non-G2 Parry builds verified game-faithful as-is;
this fix targets the latent Clotho's Needle path).

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

### `form-tree-nodes-gated-by-condition`

Druid/Lich Form skills (Werebear `wb8fo`, Spriggan `sf5rd`, Swarmblade `sbf4m`,
Reaper `rf1azz`) are LE Mutators whose `statsInForm` mod set is added in
`OnEnable` and removed in `OnDisable`. Their skill-tree nodes (e.g.
`wb8fo-*` Werebear specializations) are **only valid while the Form is
active in-game**.

LEB historically applied all Form tree-node mods unconditionally because the
4 Form treeIds were not registered in `whileActiveBuffByTreeId`. With
LETools-import default `socket-group enabled = true`, this leaked Form-only
armour / HP / damage / resistance bonuses into modDB even when the matching
"Are you in <X> Form?" Calcs checkbox was unchecked, inflating diffs against
LETools snapshots (which generate from Form-OFF state).

| Site | File | What it does |
|---|---|---|
| gate | `src/Modules/CalcSetup.lua` (~line 1423) | `whileActiveBuffByTreeId` extended with `wb8fo / sf5rd / sbf4m / rf1azz` |
| config | `src/Modules/ConfigOptions.lua` (L106-121) | `conditionInWerebearForm` / `InSprigganForm` / `InSwarmbladeForm` / `InReaperForm` checkboxes — already present, no change |

**Spec:** `spec/System/TestS5FormTreeNodeGate_spec.lua`
- `S5FormTreeNodeGate / CalcSetup whileActiveBuffByTreeId table contains the 4 player Forms` — asserts the 4 treeId → Condition entries plus the existing fw3d entry, plus the regression-guard comment block
- `S5FormTreeNodeGate / ConfigOptions Calcs-tab checkboxes still publish Condition:In<X>Form FLAG` — asserts each checkbox var + its FLAG mod

**Snapshot coverage:** existing `spec/System/TestBuilds_spec.lua` for any
Druid build that imports a Form skill enabled — reverting the gate
re-inflates Form tree-node contributions.

### `transform-cost-bypass`

LE Form/Transform abilities (Werebear `wb8fo`, Spriggan `sf5rd`, Swarmblade
`sbf4m`, Reaper `rf1azz`) are Mutators: entering Form swaps the player
resource (mana→rage for Werebear/Swarmblade, mana→nothing for Spriggan,
mana→soul-stack for Reaper) and the bar skills consumed in-Form are
auto-given child abilities not modeled in LEB's `skills.json`. The Form
ability **itself** carries no Mana cost, so CalcOffence must skip its entire
cost loop — otherwise a phantom Mana cost re-appears and inflates the
ManaCost diff vs LETools snapshots (which generate from a Form-OFF state).

The bypass relies on TWO sites cooperating:

1. **`src/Modules/DataProcess.lua`** mirrors `baseFlags.transform = true` →

| Site | File | What it does |
|---|---|---|
| flag mirror | `src/Modules/DataProcess.lua` (~line 102) | `flagToType.transform = SkillType.Transform` |
| bypass guard | `src/Modules/CalcOffence.lua` (~line 1296) | `if not skillModList:Flag(skillCfg, "HasNoCost") and not activeSkill.skillTypes[SkillType.Transform] then` |

**Spec:** `spec/System/TestS5TransformCostBypass_spec.lua`
- `S5TransformCostBypass / DataProcess maps baseFlags.transform -> SkillType.Transform` — locks the flagToType mapping + guard comment
- `S5TransformCostBypass / CalcOffence cost block is gated on \`not SkillType.Transform\`` — locks the AND-clause + HasNoCost co-existence + guard comment
- `S5TransformCostBypass / skills.json Form entries carry baseFlags.transform=true` — locks the data-side contract for Werebear/Spriggan/Reaper Form entries

**Snapshot coverage:** any Druid/Lich snapshot in `spec/TestBuilds/1.4/`
that imports a Form skill — reverting either side re-introduces a Mana
cost on the Form ability.

### `elemental-nova-spec-tree-gated-damage-type`

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

**Establishing commit:** `4406d2b51`

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

**Establishing commit:** `54598229f`

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
- "ds4d3-3 stat strings in tree_3.json carry the 'Minion' prefix"

**Establishing commit:** `6fadd1234`

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

| Site | File | What it does |
|---|---|---|
| converted-attribute init | `src/Modules/CalcSetup.lua` (~line 659) | Holds the regression-guard comment block; ANY `PerStat:Brutality/Guile/Apathy/Rampancy` mod added here without in-game tooltip evidence is the regression |

**Spec:** `spec/System/TestS4ConvertedAttr_spec.lua`
- "Brutality does NOT have a PerStat NewMod for Armour"
- "Guile does NOT have a PerStat NewMod for Evasion"
- "Apathy does NOT have a PerStat NewMod for Mana"
- "Rampancy does NOT have a PerStat NewMod for Life"

**Establishing commit:** `6fadd1234`

### `s4-perstat-base-includes-converted-twin`

Sibling to `s4-converted-attr-no-base-inherit`. Both guards must hold
together: converted attributes (Brutality / Guile / Madness / Apathy /
Rampancy) do **not** inherit base-attribute intrinsic bonuses, **but**
text-parsed `Per <BaseAttr>` mods on passive nodes / item affixes

| Site | File | What it does |
|---|---|---|
| twin lookup + EvalMod | `src/Classes/ModStore.lua` (top of file + EvalMod PerStat block) | `s4ConvertedTwin` table; both `tag.stat` and `tag.statList` branches sum the twin |
| Raw<Attr> publish | `src/Modules/CalcPerform.lua` (after the Str→Brutality conversion subtraction) | `output.RawStr = output.Str` (and Dex/Int/Att/Vit) |
| intrinsic targets | `src/Modules/CalcSetup.lua` (~line 650) | All 7 intrinsic NewMod calls use `PerStat:Raw<Attr>` |
| Druid form-OR parser | `src/Modules/ModParser.lua` (after "in reaper form") | `"in human or spriggan"` → Condition NAND on {Werebear, Swarmblade, Reaper}; `"in bear or swarmblade"` → Condition OR on {Werebear, Swarmblade} |
| ModCache entries | `src/Data/ModCache.lua` (~line 10521, 10543) | Aspects of Might Armour + Melee Damage rows carry the Condition tag, no `extra` leftover |

**Spec:** `spec/System/TestS4PerStatBaseTwin_spec.lua`
- "ModStore EvalMod sums converted twin for PerStat:<BaseAttr>" — declares table, scalar + statList lookups, all five base→twin pairs, and the regression-guard comment block
- "CalcSetup intrinsic bonuses reference Raw<Attr>" — all 7 NewMod calls match the `Raw<Attr>` regex
- "CalcPerform mirrors live attributes onto Raw<Attr> after conversion" — all 5 `output.RawX = output.X` assignments
- "ModCache entries for Druid OR-form conditionals carry the Condition tag" — Armour entry with `neg=true`, Melee Damage entry without `neg`, both with `extra=nil`

**Establishing commit:** `8ade47879`

### `exulis-all-attributes-range`

The unique amulet `Exulis` (id 469) rolls `+(10-20) to All Attributes`.

| Site | File | What it does |
|---|---|---|
| 1.4 unique data | `src/Data/Uniques/uniques_1_4.json` (Exulis entry, ~line 9400) | `+(10-20) to All Attributes` |
| legacy unique data | `src/Data/Uniques/uniques.json` (Exulis id 469, ~line 10639) | `+(10-20) to All Attributes` |

**Spec:** `spec/System/TestExulisRange_spec.lua`
- "Data/Uniques/uniques_1_4.json has Exulis '+(10-20) to All Attributes'"
- "Data/Uniques/uniques.json has Exulis '+(10-20) to All Attributes'"

**Establishing commit:** `6fadd1234`

### `exulis-shared-rollid`

The unique amulet `Exulis` (id 469) has TWO rolled mods that share
the same `rollID=0` in the game data, meaning they read the same byte
in the imported `ur` array.

| Site | File | What it does |
|---|---|---|
| 1.4 unique data | `src/Data/Uniques/uniques_1_4.json` (Exulis entry, ~line 9400) | `rollIds: [0, 0, null, null, null, null, null]` |
| legacy unique data | `src/Data/Uniques/uniques.json` (Exulis id 469, ~line 10639) | `rollIds: [0, 0, null, null, null, null, null]` |

**Spec:** `spec/System/TestExulisRange_spec.lua`
- "Data/Uniques/uniques_1_4.json has Exulis rollIds[0]==rollIds[1]==0 (shared rollID)"
- "Data/Uniques/uniques.json has Exulis rollIds[0]==rollIds[1]==0 (shared rollID)"

**Establishing commit:** `8d7a017cc`

### `sidebar-ward-stat-removal`

The Build.lua sidebar `displayStats` list was trimmed to drop the raw
`Ward` row and the `NetWardRegen` row. Both duplicated information
already exposed by `StableWard` and the Net Recovery breakdown rows
(NetLifeRegen / NetManaRegen / TotalNetRegen) and confused users.

After removal, TestBuilds snapshots (BjqdaPzE Sorcerer, o3Zlpkxd
Necromancer) were regenerated and the corresponding `<PlayerStat
stat="Ward"...>` / `<PlayerStat stat="NetWardRegen"...>` lines no
longer appear. A regression here re-adds either row to the sidebar
and silently drifts every snapshot.

| Site | File | What it does |
|---|---|---|
| sidebar config | `src/Modules/Build.lua` (`displayStats`, around the StableWard row) | only `StableWard` row remains |
| 1.4 sample snapshot | `spec/TestBuilds/1.4/BjqdaPzE lv99 Sorcerer.xml` | no Ward / NetWardRegen PlayerStat |
| 1.4 sample snapshot | `spec/TestBuilds/1.4/o3Zlpkxd lv98 Necromancer.xml` | no Ward / NetWardRegen PlayerStat |

**Spec:** `spec/System/TestSidebarWardStats_spec.lua`
- "Build.lua sidebar displayStats does not declare stat=\"Ward\""
- "TestBuilds snapshots reflect the removal (no Ward / NetWardRegen PlayerStat lines)"

**Establishing commit:** `708096bf7`

### `letools-diff-ward-regen-gross-mapping`

LE's planner "Ward Regen" tooltip shows the **gross** +Ward/sec sourced from
mods (e.g. Sanguine Runestones, Vessel of Strife's "X% of Health Regen also
applies to Ward"), not the net of +regen−decay. The LEB analogue is therefore
`output.WardPerSecond`, **not** `output.NetWardRegen` (which is `wps - decay`
and is ≈ 0 in steady state because ward retention auto-tunes wps and decay to
balance).

The local diff tool (`scripts/letools-diff.js`, gitignored) previously had a
duplicate map entry that overrode `'ward regen' → WardRegen` with
`'ward regen' → NetWardRegen`. Because LEB does not expose a top-level
`output.WardRegen` (the regen pipeline writes only `WardPerSecond`,
`WardDecayPerSecond`, `NetWardRegen`), the override silently reported every

**Spec:** `spec/System/TestWardRegenStatSemantics_spec.lua`
- "'(N)% of Health Regen also applies to Ward' parses to LifeRegenAppliesToWard BASE"
- "Vessel of Strife produces WardPerSecond (gross) > 0 and NetWardRegen ≈ 0 at steady state"

**Establishing commit:** `945dd7d42` (test) / `daa082671` (guard + dump)

### `letools-quest-reward-from-completed-quests`

LETools planner JSON exposes character quest completion via
`data.completedQuests` (a list of numeric quest IDs). Two of those quests
grant `+1 to all attributes`:

- `124` — Apophis and Majasa (Ch. 9)
- `151` — Temple of Eterra (Ch. 10)

Both the in-app `DownloadLEToolsPlannerBuild` flow and the
`spec/ImportLEToolsBuild.lua` snapshot driver MUST derive
`questApophisMajasa` / `questTempleOfEterra` from this list. Hardcoding
either flag — in either direction — silently drifts every imported
build's attribute totals by ±1..±2 across all 5 attributes.

| Site | File | What it does |
|---|---|---|
| shared helper | `src/Classes/ImportTab.lua` `ImportTabClass:DetectLEToolsQuestRewards` | Returns `(hasApophis, hasEterra)` from `data.completedQuests` |
| in-app import | `src/Classes/ImportTab.lua` (LETools download callback) | Calls the helper and assigns both flags |
| snapshot driver | `spec/ImportLEToolsBuild.lua` | Calls the helper and assigns both flags |

**Spec:** `spec/System/TestLEToolsQuestImport_spec.lua`
- "returns false,false when completedQuests is nil/missing"
- "returns false,false when completedQuests is empty"
- "detects Apophis (124) only"
- "detects Eterra (151) only"
- "detects both Apophis (124) and Eterra (151)"
- "ignores other quest IDs even when many are present"
- "does not match string '124' or '151' (numeric ID only)"

**Establishing commit:** `7675c0af2`

### `letools-import-form-condition-autoset`

LE planner displays "in-combat" stats: Druid Form skills (Werebear /
Swarmblade / Spriggan) are assumed active, and Beastmaster summoned
companions are alive. LEB's Config flags default to "out of combat",
so without explicit user input the importer leaves form/companion
multipliers off and every imported Druid / Beastmaster build under-reports
armor + resist + life + mana + dodge by hundreds of points
(cross-cutting drift). `ImportTabClass:ImportItemsAndSkills` MUST call
`AutoSetConfigFromAbilities(charData)` after the items pipeline finishes
so the Config tab matches LE's display convention.

Mapping (Druid ascendancy only — see class gate):

- `"Werebear Form"`   → `conditionInWerebearForm = true`

| Site | File | What it does |
|---|---|---|
| auto-set helper | `src/Classes/ImportTab.lua` `ImportTabClass:AutoSetConfigFromAbilities` | Scans `charData.abilities` and sets form / companion Config flags |
| importer hook   | `src/Classes/ImportTab.lua` `ImportTabClass:ImportItemsAndSkills` | Calls the helper before `buildFlag = true` |

**Spec:** `spec/System/TestLEToolsImportFormAutoset_spec.lua`
- "sets conditionInWerebearForm when Werebear Form is in abilities"
- "sets conditionInSwarmbladeForm and conditionInSprigganForm"
- "counts Beastmaster companion summons into multiplierCompanion"
- "does not set multiplierCompanion for non-Beastmaster classes"
- "is a no-op when no relevant abilities are present"
- "handles missing charData gracefully"
- "does not set Form flags for non-Druid classes (Form skill not always active)"

**Establishing commit:** `96e261da2`

### `stcdt-conversion-shapes`

Catalogues every stat / description prose shape that introduces, redirects,
or removes damage-type bits via skill-tree allocation. The parser is
text-driven against a long tail of nodes; adding a shape is easy but
*removing* one accidentally during a refactor (e.g. consolidating the
cascading `if not dst then` chain into a generic loop) silently regresses
Minion Tags / Scaling Tags / `+to X Skills` affix matching for whichever
skills depend on that shape. The spec keeps the catalogue runnable.

| Site | File | What it does |
|---|---|---|
| stcdt filter             | `src/Modules/CalcActiveSkill.lua` — `calcs.getActiveStcdtBits` | Returns `(activeBits, removedBits)` after scanning allocated nodes' stats + description |
| Scaling Tags mirror      | `src/Classes/SkillsTab.lua` — `GetDynamicDamageTypesByTreeId` | Same shape catalogue applied to the UI's base/conv set |
| caller wiring (minionKW) | `src/Modules/CalcSetup.lua` (~line 1793) | Captures `removedBits` and applies `bit.band(minionKW, bit.bnot(removedStcdt))` so post-conversion `+to <NewType> Skills` affixes match while the stripped source no longer matches its own tag |

**Spec:** `spec/System/TestStcdtParser_spec.lua`
- "getActiveStcdtBits #stcdt" (17 cases — one per shape + filter / treeId guards)

**Establishing commit:** `4515b56a5`

### `phase4-stun-aoe-melee-flag-isolation`

Phase 4 LETools-parity Calcs-tab additions surface character-aggregate
`StunChanceInc / MeleeStunChanceInc / AreaOfEffectInc / MeleeAreaOfEffectInc`.
The Melee* rows must equal the **melee-only delta**, computed as
`Sum(INC, {flags=Melee}, name) - Sum(INC, nil, name)`. `modDB:Sum` with a
flag set returns mods matching the flag set OR mods with no flags — NOT
melee-only mods. A naive rewrite to a direct melee-cfg call double-counts
the unflagged sum into the Melee row, silently inflating every build's
melee-stun / melee-AoE display.

| Site | File |
|---|---|
| Melee-flag isolation block | `src/Modules/CalcDefence.lua` (~line 1472, after `OverkillLeech`) |

**Spec:** `spec/System/TestPhase4LEToolsParity_spec.lua`
- "Melee* aggregates isolate the melee-tagged delta (no double-count of unflagged)"

**Establishing commit:** `46ff75230`

### `phase4-minion-modifier-bucket-aggregation`

Minion stat mods in LEB are routed via `MinionModifier` LIST entries
(consumed by `env.minion` in CalcPerform when an active minion skill
exists). The Minion* outputs on the Calcs tab must show even on builds
without an active minion skill, so `buildDefenceEstimations` walks the
MinionModifier LIST once and buckets inner mods by `(name, type)`. ~30
Minion* outputs read from this bucket map.

INVARIANT: every Minion* output reads via `sumMinion(name, type)` from
the bucket. Reverting any single output to a top-level `modDB:Sum(...,
"<name>")` silently returns 0 because the matching mods only exist
nested inside MinionModifier LIST values, not at the modDB top level.
This was already broken-and-fixed once for `MinionLifeInc`; the bucket

| Site | File |
|---|---|
| Bucket loop + sumMinion helper | `src/Modules/CalcDefence.lua` (~line 1525, `do … local minionMods = {}`) |

**Spec:** `spec/System/TestPhase4LEToolsParity_spec.lua`
- "Minion bucket aggregates MinionModifier LIST entries by (name,type)"
- "Phase 4 outputs default to 0 with no mods (no character base leak)"

**Establishing commit:** `46ff75230`

### `minion-bucket-evalmod-perstat`

The CalcDefence MinionModifier bucket must evaluate inner mods through
`modDB:EvalMod(m)` instead of summing raw `m.value`. PerStat / Multiplier
tags on `MinionModifier` inner mods carry the per-unit coefficient, not
the displayed scalar — for example Acolyte-59 "Grave Thorns" notScalingStat
`"4% Increased Minion Health Per Vitality"` wraps a `Life INC` mod with
`value = 4` and a `PerStat:Vit` tag. The bucket must multiply by player
Vit (4 × 65 = 260), not contribute the raw 4.

Symptom before fix (G1 fresh diff, 2026-05-11):
`BxvJKdPR lv97 Necromancer MinionLifeInc LE=384 LEB=128 Δ=-256`.
Aaron's Will body armor (148) + Acolyte-59 (raw 4 instead of 260) +
Acolyte-23 (-24) = 128 vs LE's 148 + 260 - 24 = 384.

| Site | File |
|---|---|
| Bucket loop EvalMod call | `src/Modules/CalcDefence.lua` (~line 1640, inside the phase4 bucket loop) |

**Spec:** `spec/System/TestMinionPerStatScaling_spec.lua`
- "'4% Increased Minion Health Per Vitality' wraps Life INC with PerStat:Vit"
- "CalcDefence MinionModifier bucket evaluates via EvalMod, not raw m.value"
- "Acolyte-59 tree_3.json carries the Per-Vitality notScalingStat"

**Establishing commit:** `f34161baa`

### `crits-abbreviation`

Sentinel class-tree passives (Sentinel-14 Patient Doom, Sentinel-42 Iron
Reflexes, Sentinel-114 Heaven's Bulwark) abbreviate "Critical Strikes" as
"Crits" in their stat strings. The parser must route "% reduced/less bonus
damage taken from crits" to `ReduceCritExtraDamage` BEFORE the generic
"from (.+)$" catch-all that returns `nsAny` (LEB_NotSupported).

`scan()` in `ModParser.lua` resolves overlapping patterns by **longest tail
wins**. The specific "from crits$" tail (5 chars + EOL) is one char longer
than "from (.+)$" (4 chars + EOL) so the specific pattern wins — but only as
long as nothing widens the catch-all or reorders entries. If this guard
fails, the original symptom returns: B4Xq8aG6 lv95 Paladin shows
`CritExtraDmgRed` Δ=-30 against LETools precalc (LE=58, LEB=28).

| Site | File | What it does |
|---|---|---|
| specific patterns | `src/Modules/ModParser.lua` (~line 1750-1758) | "from crits$" → `ReduceCritExtraDamage`, must precede "from (.+)$" `nsAny` |
| catch-all | `src/Modules/ModParser.lua` (~line 1764-1765) | "from (.+)$" → `nsAny` (only kept for unknown crit-source variants) |

**Spec:** `spec/System/TestModParse_spec.lua`
- "crits abbreviation reduces crit damage"

**Establishing commit:** `93d3dda3c`

### `crit-extra-damage-reduction-display-uncapped`

`output.CritExtraDamageReduction` mirrors LE's "Reduced Bonus Damage Taken
from Critical Strikes" sidebar value, which is the **raw sum** of every
`ReduceCritExtraDamage` BASE mod — uncapped. The 100% ceiling lives in the

| Site | File | What it does |
|---|---|---|
| display | `src/Modules/CalcDefence.lua:820-823` | output.CritExtraDamageReduction = raw `Sum("BASE", ..., "ReduceCritExtraDamage")` (uncapped) |
| effect | `src/Modules/CalcDefence.lua:927` | `EnemyCritEffect` applies `m_min(..., 100)` so the `(1 - X/100)` multiplier cannot go negative |

**Spec:** `spec/System/TestCritExtraDamageReduction_spec.lua`
- "display value is uncapped sum of ReduceCritExtraDamage BASE mods"
- "EnemyCritEffect clamps effective reduction at 100"

**Establishing commit:** `39c3f2bb9`

### `with-a-shield-condition`

Several Sentinel class-tree nodes phrase their shield-gated bonus as
"…With A Shield" rather than the long form "while using a shield". The
clearest example is Sentinel-90 "Sanctuary Guardian":
`+15% All Resistances With A Shield` lives in `notScalingStats` and
activates once 5 points are allocated.

`ModParser.modTagList` must contain BOTH spellings mapped to the same
`Condition: UsingShield` tag. If only the long form is present, the
trailing " with a shield" survives `scan()` as residual extra. The chain
is unforgiving:

1. `modLib.parseMod` returns `(modList, extra)` with extra non-nil.

| Site | File | What it does |
|---|---|---|
| condition mapping | `src/Modules/ModParser.lua` (~line 619-628) | Adds `["with a shield"] = { tag = Condition UsingShield }` next to "while using a shield" |
| cache invalidation | `src/Data/ModCache.lua` | Removed stale `c["+15% All Resistances With A Shield"]` entry so it re-parses with the new tag |
| consumer | `src/Classes/PassiveTree.lua:421-423` | Drops the entire mod when `extra` is non-nil (this is the silent failure mode) |

**Spec:** `spec/System/TestModParse_spec.lua`
- "with a shield condition tag"

**Establishing commit:** `952bff6a0`

### `while-with-a-shield-condition`

Sentinel-90 "Sanctuary Guardian" notScalingStats also uses the long form
`+50 Armor While With A Shield`. This is a different surface from the bare
"With A Shield" suffix: the leading word is "While". Without an explicit
`["while with a shield"]` entry in `ModParser.modTagList`, the trailing
" while with a shield" survives `scan()` as residual extra and the entire
mod is silently dropped via the same `node.extra=true` chain documented
under `with-a-shield-condition`.

Symptom on AVa9YEkg lv95 Paladin: Armour Δ ≈ -178 effective (50 BASE × INC
multiplier) with no Sentinel-90 contribution in the Armour breakdown.

`Data/ModCache.lua` previously cached the bad parse:

| Site | File | What it does |
|---|---|---|
| condition mapping | `src/Modules/ModParser.lua` (~line 629) | Adds `["while with a shield"] = { tag = Condition UsingShield }` next to "with a shield" |
| cache fix         | `src/Data/ModCache.lua` (~line 8061)    | `+50 Armor While With A Shield` entry now carries the UsingShield tag with nil residual |
| consumer          | `src/Classes/PassiveTree.lua:421-423`   | Drops the entire mod when `extra` is non-nil (silent failure mode) |

**Spec:** `spec/System/TestModParse_spec.lua`
- "while with a shield condition tag"

**Establishing commit:** `0cd7b394c`

### `per-1pct-increased-movement-speed`

The Unbroken Charge unique grants `+(11-30) Block Effectiveness per 1%
Increased Movement Speed` (and similarly the `0.2% Increased Damage per 1%
Increased Movement Speed` mod surfaces elsewhere). Two pieces are required
for the mod to take effect:

1. `ModParser.modTagList` needs a `["per 1%% increased movement speed"]`
   entry mapping to `Multiplier: MovementSpeedInc`. Without it the residual
   suffix drops the entire mod via `node.extra=true`.
2. `CalcSetup.lua` must inject `Multiplier:MovementSpeedInc` from
   `env.modDB:Sum("INC", nil, "MovementSpeed")` AFTER all MS INC mods have
   been added. Without injection, the matcher exists but the multiplier is
   always 0 so the mod contributes nothing.

| Site | File | What it does |
|---|---|---|
| matcher          | `src/Modules/ModParser.lua` (~line 636)              | `["per 1%% increased movement speed"] = { tag = Multiplier MovementSpeedInc }` |
| auto-injection   | `src/Modules/CalcSetup.lua` (~line 1539)             | Sums `INC` `MovementSpeed`, then `NewMod("Multiplier:MovementSpeedInc", "BASE", msInc)` |
| cache fix        | `src/Data/ModCache.lua` (~lines 4944, 10236)         | Both cached entries now carry the Multiplier tag with nil residual |
| consumer         | `src/Classes/PassiveTree.lua:421-423` / mod resolve | Drops the entire mod when `extra` is non-nil; Multiplier resolves at calc time |

**Spec:** `spec/System/TestModParse_spec.lua`
- "per 1% increased movement speed multiplier"

**Establishing commit:** `0cd7b394c`

### `traitors-tongue-offhand-crit-flat`

Traitor's Tongue (dual-wield dagger, unique id 342) carries TWO cross-slot
self-referential mods:

- `+(10-13)% Parry Chance with Traitor's Tongue equipped in the mainhand`
- `+(10-13)% Critical Strike Chance with Traitor's Tongue equipped in the offhand`

This is the only unique in the game (verified 2026-05-12 against
`LE_datamining/extracted/unique_mods_generated.json`) that uses the
"with X equipped in the offhand|mainhand" pattern.

Without matchers for these phrases, the trailing slot condition survives
`scan()` as residual extra and `Item.lua` `processModLine`'s

| Site | File | What it does |
|---|---|---|
| matcher (offhand) | `src/Modules/ModParser.lua` (~line 679)   | `["with (.-) equipped in the offhand"] = { tag = Condition OffhandHas:<name> }` |
| matcher (mainhand)| `src/Modules/ModParser.lua` (~line 680)   | `["with (.-) equipped in the mainhand"] = { tag = Condition MainHandHas:<name> }` |
| condition seed    | `src/Modules/CalcSetup.lua` (~line 1506) | Sets `conditions["OffhandHas:<weapon2.name:lower()>"]` / `MainHandHas:<weapon1.name:lower()>` when slot occupied |
| cache fix         | `src/Data/ModCache.lua` (~lines 2868, 2932) | Both cached entries now carry the Condition tag with nil residual |
| consumer          | `src/Classes/Item.lua:1716-1746` (`processModLine`) | Drops the entire mod when residual extra isn't connector-only; tag bypasses the drop |

**Spec:** `spec/System/TestModParse_spec.lua`
- "equipped in the offhand condition tag"
- "equipped in the mainhand condition tag"

**Establishing commit:** `6d363fc89` — _fix(mods): preserve offhand/mainhand condition tag on cross-slot uniques_

### `traitors-tongue-self-source-slot`

Sibling of `traitors-tongue-offhand-crit-flat` above. With the parser/cache fix
in place the mod is no longer dropped, but a global `Condition: MainHandHas:<name>`
/ `OffhandHas:<name>` tag double-fires when the same unique sits in both weapon
slots:

Symptom on QWXjqWJ2 lv100 Bladedancer (dual Traitor's Tongue): LETools tooltip
shows Parry Chance = 13% (`+10` unique + `+3` Spell Breaker), i.e. only ONE
mainhand-Parry fires. LEB with the global tag fired both copies → 24% (verified
via per-skill snapshot).

Game-data evidence (2026-05-12):

- `LE_datamining/extracted/items/uniques.json` (uniqueID 342) stores the four

| Site | File | What it does |
|---|---|---|
| per-slot filter   | `src/Modules/CalcSetup.lua` (~line 1303) | After loading `srcList`, drops mods whose `Condition.var` starts with the OTHER slot's prefix; uses `tag.var:sub(1, #dropPrefix) == dropPrefix` so the filter is generic across future cross-slot uniques |
| condition seed    | `src/Modules/CalcSetup.lua` (~line 1510) | Still seeds `OffhandHas:` / `MainHandHas:` so the kept mod's Condition tag evaluates true |
| producer (unchanged) | `src/Modules/ModParser.lua` (~line 691-692) | Still emits the `Condition: <Slot>Has:<name>` tag; matcher unchanged |

**Spec:** `spec/System/TestTraitorsTongueSelfSourceSlot_spec.lua`
- "filters srcList by slotName for Weapon 1 / Weapon 2"
- "matches the Condition tag prefix, not the full var"

**Establishing commit:** `29b08c740` — _fix(calcs): scope Traitor's Tongue cross-slot mods to source slot_

### `per-type-crit-multi-overview-keywordflags`

`Calcs.lua` exposes a per-damage-source Crit Multiplier overview
(`output.MeleeCritMultiplier` / `SpellCritMultiplier` / `BowCritMultiplier` /
`ThrowingCritMultiplier`) intended to mirror LETools' per-type crit-multi
columns for triangulation.

ModParser tags damage-source-prefixed CritMultiplier mods (e.g. Li'raka's
Claws `+(60-130)% Throwing Critical Strike Multiplier`) via
`keywordFlags = KeywordFlag.<Source>` — see the `DamageSourceTypes` loop in
`src/Modules/ModParser.lua`. `cfg.flags` and `cfg.keywordFlags` live in
different buckets in `ModStore:Sum`, so filtering via
`flags = ModFlag.<Source> + ModFlag.Hit` silently drops every such mod even
though `ModFlag.<Source>` and `KeywordFlag.<Source>` share the same numeric

| Site | File | What it does |
|---|---|---|
| overview cfg | `src/Modules/Calcs.lua` (~line 370) | Iterates `critTypeKeywordFlags = { Melee = KeywordFlag.Melee, ... }` and sums via `{ flags = ModFlag.Hit, keywordFlags = kwFlags }` so the Hit context and the damage-source filter land in the correct cfg buckets |
| producer    | `src/Modules/ModParser.lua` (DamageSourceTypes loop, ~line 456) | `modFlagList[damageSourceType:lower()] = { keywordFlags = ModFlag[damageSourceType] }` — the tag side that the consumer above must match |

**Spec:** `spec/System/TestPerTypeCritMultiOverview_spec.lua`
- "damage-source table is keyed to KeywordFlag.<Source>, not ModFlag.<Source>"
- "cfg passes Hit via flags and the damage-source via keywordFlags"

**Establishing commit:** `27306cda7` — _fix(calcs): per-type Crit Multi overview filters via keywordFlags_

### `eterras-path-player-ms`

Eterra's Path (unique boots, id 21) carries TWO Movement Speed mods in the
underlying game data: a player-side `+20% Movement Speed` (tags=0) and a
minion-side `+20% Minion Movement Speed` (tags=8192=Minion). The in-game
tooltip collapses both into one line: "You and your minions have 20%
increased movement speed".

LEB's `uniques_1_4.json` originally listed only the minion variant, dropping
the player MS entirely. This caused a -20% Movement Speed gap on every
Eterra's Path build vs LETools (e.g. Qb6WgDEp lv95 Beastmaster Δ=-25,
of which 20 came from this drop and 5 from a separate Predator BASE issue).

The "You and your minions have ..." tooltip pattern in LE always means

| Site | File | What it does |
|---|---|---|
| unique data | `src/Data/Uniques/uniques_1_4.json` (id `"21"`) | Lists both `"20% increased Movement Speed"` (player) and `"20% increased Minion Movement Speed"` (minion) with parallel `null` rollIds |

**Spec:** `spec/System/TestEterraPathPlayerMS_spec.lua`
- "uniques_1_4.json Eterra's Path has BOTH player and minion 20% MS mods"

**Establishing commit:** `a3c9dff26`

### `you-and-minions-dual-mods`

The Eterra's Path bug is one instance of a wider data class. Any LE unique
whose tooltip uses the wording **"for You and your Minions"** or **"You and
your minions have ..."** is backed by TWO mods in the underlying data
(tags=0 player + tags=8192 minion). LEB's `ModParser` does NOT have a
generic handler for the "for You and your Minions" suffix — leaving the
collapsed tooltip text as a single line in `uniques_<ver>.json` silently
parses as MinionModifier-only and drops the player side.

Confirmed affected uniques (game extract `extracted/items/uniques_v3.json`):

| Site | File | What it does |
|---|---|---|
| unique data | `src/Data/Uniques/uniques_1_4.json` (ids `"66"`, `"461"`, `"463"`) | Player mod and `Minion <stat>` mod listed as separate entries with parallel rollIds |

**Spec:** `spec/System/TestYouAndMinionsDualMods_spec.lua`
- "Hollow Finger (id 66) carries BOTH player and minion Cold/Phys resist"
- "Ash Wake (id 461) splits Ignite-on-hit into player and minion mods"
- "Rahyeh's Embrace (id 463) splits increased Health into player and minion mods"

**Establishing commit:** `a3c9dff26`

### `movement-speed-base-additive`

LE's Movement Speed formula is `(1 + (BASE + INC)/100) * More`. LEB
previously computed `output.MovementSpeedMod` via
`calcLib.mod(modDB, nil, "MovementSpeed")`, which returns only
`(1 + INC/100) * More` and silently drops the BASE term.

Passive nodes that grant `"+X% Movement Speed"` parse as
`MovementSpeed BASE X` (see ModCache: `"+1% Movement Speed"` →
`name="MovementSpeed", type="BASE", value=1`). Without the BASE term in
the formula, every such node — most notably Beastmaster's **Predator**
(+1% Movement Speed per point, up to 5 — hence -5% on every Beastmaster
build) — contributes nothing. Combined with the Eterra's Path bug, the
Qb6WgDEp lv95 Beastmaster snapshot was -25% short of LETools (61% vs 36%);

| Site | File | What it does |
|---|---|---|
| calc | `src/Modules/CalcDefence.lua` (output.MovementSpeedMod) | Formula expanded to `(1 + (BASE + INC)/100) * More`; BASE read via `modDB:Sum("BASE", nil, "MovementSpeed")` |

**Spec:** `spec/System/TestMovementSpeedBaseAdditive_spec.lua`
- "CalcDefence Movement Speed line includes BASE"
- "plain calcLib.mod is no longer used for the Movement Speed slot"

**Establishing commit:** `a3c9dff26`

### `lifeonhit-flag-aware-sum`

ModParser registers `LifeOnMeleeHit` (and `LifeOnHit`) BASE mods with
`flags = bor(ModFlag.Melee, ModFlag.Hit)` so they participate in per-skill
hit-rate filtering. The Calcs-tab character-aggregate row at the bottom of
`CalcDefence.UpdateLifeShield` originally summed these with `cfg = nil`,
which means `band(cfg.flags, mod.flags) == mod.flags` evaluates
`band(0, Melee|Hit) ~= Melee|Hit` → ModDB silently drops the mod.

Real-world hit: QDxZjL4J Paladin's main weapon **Palarus's Sacred Light**
suffix `+11 Health Gain on Melee Hit` was surfaced as `0` in LEB while
LETools displayed `11`. Fix passes the same flag bitmask in cfg so the
mod actually matches.

| Site | File | What it does |
|---|---|---|
| calc | `src/Modules/CalcDefence.lua` (output.LifeOnMeleeHit / LifeOnHit) | `Sum("BASE", { flags = bor(ModFlag.Melee, ModFlag.Hit) }, "LifeOnMeleeHit")` (and Hit-only for the Hit variant) |

**Spec:** `spec/System/TestLifeOnHit_spec.lua`
- "ModParser tags 'Health Gain on Melee Hit' with Melee+Hit flags"
- "BASE LifeOnMeleeHit surfaces on calcsOutput with Melee+Hit cfg"

**Establishing commit:** `e6e935ac5`

### `symbols-of-hope-inc-not-more`

Symbols of Hope grants `+20% Increased Health Regen` per active symbol
(LE: additive INC, not a separate MORE multiplier). The Meditation node
`si4lgl-24` doubles the per-symbol value to 40%. The per-symbol value is
itself scaled by `SymbolsOfHopeEffect` INC (e.g. Sentinel-119 Covenant of
Light grants +4%/pt for both Holy Aura and Symbols of Hope effect).

Pre-fix `CalcSetup.lua` injected the per-symbol value as `MORE LifeRegen`
outside the `applyBuffPrefix` scaling path, so:
- it stacked multiplicatively with global INC LifeRegen instead of additively, and
- `SymbolsOfHopeEffect` INC never reached it.

Real-world hit: QDxZjL4J Paladin's LETools snapshot shows `Health Regen

| Site | File | What it does |
|---|---|---|
| auto-injection | `src/Modules/CalcSetup.lua` (~line 1559) | `LifeRegen INC perSymbolPct × (1 + SymbolsOfHopeEffect/100)`, gated on `Multiplier:ActiveSymbol` |

**Spec:** `spec/System/TestSymbolsOfHope_spec.lua`
- "per-symbol value defaults to 20% INC and scales with SymbolsOfHopeEffect"
- "Meditation node doubles per-symbol value to 40"

**Establishing commit:** `804d333a4`

### `paladin-sentinel95-healthregen-partition`

Paladin tree node Sentinel-95 (Covenant of Protection) partitions its
bonuses across two arrays: scaling `stats` (Armor + ArmorAppliesToDoT)
and `notScalingStats` (`+5 Health Regen From Symbols Of Hope`), gated
on `noScalingPointThreshold=5`. The LE in-game tooltip (verified
2026-05-18, BgRrP5rr Paladin lv98) shows ONLY the two armor lines as
scaling — there is no `+6 Health Regen` scaling stat. The non-scaling
Health Regen bonus is a fixed +5 once the player allocates 5 points,
and the "From Symbols Of Hope" wording in this passive context scales
the BASE LifeRegen mod by the `Multiplier:ActiveSymbol` count (matching
the existing Symbols of Hope per-symbol INC LifeRegen convention).

Pre-fix state had two compounding errors:
1. `tree_2.json` (1_4) listed a stale `+6 Health Regen` in scaling
   `stats` (which would have produced +30 BASE at 5 points — wrong vs
   game tooltip). Fixed by `815761c3a` (game-canonical tooltip sync).
2. ModParser had no handler for the suffix `from symbols of hope`, so
   the `+5 Health Regen From Symbols Of Hope` notScalingStat fell into
   the ModParser residue and contributed 0 BASE LifeRegen. Fixed by
   adding `["from symbols of hope"] = { tag = { type="Multiplier",
   var="ActiveSymbol" } }` plus a regen of the affected ModCache entry.

Net effect on BgRrP5rr (5 ActiveSymbols): Sentinel-95 contributes
+25 BASE LifeRegen (5 × 5 from the ActiveSymbol multiplier), restoring
~33% of the +62 LifeRegen drift vs LETools.

| Site | File | What it does |
|---|---|---|
| tree data | `src/TreeData/1_4/tree_2.json` (Sentinel-95) | `stats` array omits `+6 Health Regen`; `notScalingStats` contains `+5 Health Regen From Symbols Of Hope` with `noScalingPointThreshold=5` |
| parser | `src/Modules/ModParser.lua` (`modTagList`, ~L654) | Maps "from symbols of hope" suffix to `Multiplier:ActiveSymbol` tag |
| cache | `src/Data/ModCache.lua` (~L7775) | `+5 Health Regen From Symbols Of Hope` cached as BASE LifeRegen value=5 with `Multiplier:ActiveSymbol` tag |

**Spec:** `spec/System/TestPaladinSentinel95LifeRegen_spec.lua`
- "ModParser tags '+5 Health Regen From Symbols Of Hope' with Multiplier:ActiveSymbol"
- "Sentinel-95 BASE LifeRegen mod reaches modDB tagged with Multiplier:ActiveSymbol"
- "tree_2.json Sentinel-95 stats omit '+6 Health Regen'"
- "tree_2.json Sentinel-95 notScalingStats contains '+5 Health Regen From Symbols Of Hope'"

**Establishing commit:** `388cf4e6d` (fix(passives): partition Sentinel-95 Health Regen by Symbols Of Hope)
**Supersedes:** `sentinel-95-base-health-regen` (804d333a4) — that guard
asserted the now-incorrect `+6 Health Regen` scaling stat. Replaced
because the game-canonical tooltip partitions the Health Regen as a
notScalingStat, not a scaling stat.

### `sentinel-93-mana-regen-from-holy-aura`

Paladin tree node Sentinel-93 (Covenant of Dominion) at 5 allocated points
activates the `notScalingStat` `25% Increased Mana Regen From Holy Aura`.
The cached parse in `src/Data/ModCache.lua` tags the resulting mod with
`SkillName=Holy Aura`, but `CalcDefence.lua:580` sums `ManaRegen` INC with
`cfg=nil` so the SkillName tag never matches and the bonus contributes 0.

The LE engine treats `From Holy Aura` as an always-on while-active condition
(Holy Aura is a permanent toggle skill): as long as Holy Aura is on the bar
and enabled, the bonus applies globally. The fix injects a clean (untagged)
`ManaRegen` INC mod scaled by `HolyAuraEffect` INC (Sentinel-119 Covenant of
Light: +4%/pt) when both Sentinel-93 (≥5pts) and Holy Aura (`ah443-`) are
active.

| Site | File | What it does |
|---|---|---|
| injection | `src/Modules/CalcSetup.lua` (~line 1576) | When Holy Aura enabled and Sentinel-93 ≥5pts, NewMod ManaRegen INC scaled by HolyAuraEffect |

**Spec:** `spec/System/TestSentinel93ManaRegen_spec.lua`
- "Sentinel-93 25% scales by HolyAuraEffect and surfaces as INC ManaRegen"
- "tree_2.json Sentinel-93 retains '25% Increased Mana Regen From Holy Aura' notScalingStat"

**Establishing commit:** `b7a43d221`

### `urzils-pride-mana-regen-per-uncapped-lightning-res`

Urzil's Pride (unique Iron Armor) carries the inherent mod
`1% Increased Mana Regeneration per 2% Uncapped Lightning Resistance`. The
mod was missing from `src/Data/Uniques/uniques*.json` entirely (LEB only had
the four legendary-affix slots). LE displays / LETools breakdown both treat
the per-2% step as **floored at integer percentage points**, not continuous
— so at `LightningResistTotal=129` the contribution is `floor(129/2)*1=64`%
INC, not 64.5%.

A naive PerStat tag (`{type="PerStat", stat="LightningResistTotal", div=2}`)
cannot be used because `ModStore.lua:GetStat` deliberately uses continuous
scaling for "per N stat" mods (justified at `ModStore.lua:414` for things
like Wisdom node `0.3% mana regen per 10 max mana`). Continuous scaling

| Site | File | What it does |
|---|---|---|
| data    | `src/Data/Uniques/uniques.json`,  `uniques_1_2.json`, `uniques_1_3.json`, `uniques_1_4.json` | Adds the missing mod line + roll-id null on Urzil's Pride |
| parser  | `src/Modules/ModParser.lua` (~line 897)            | Pattern emits `ManaRegenIncPerUncappedLightningRes_Per2` BASE |
| inject  | `src/Modules/CalcDefence.lua` (~line 262)          | Reads stat, floors div by 2, NewMod ManaRegen INC scaled by `LightningResistTotal` |

**Spec:** `spec/System/TestUrzilsPrideManaRegen_spec.lua`
- "Urzil's Pride floors mana regen INC per 2% uncapped lightning resistance"
- "Urzil's Pride mod parses to BASE ManaRegenIncPerUncappedLightningRes_Per2"
- "uniques_1_4.json Urzil's Pride retains the per-uncapped-lightning-res mod line"

**Establishing commit:** `280e66abc`

### `eterras-blessing-buff-gating`

Eterra's Blessing (Primalist, treeId `eb5656`) is a 4s-duration cast buff
(`skillTypeTags=131328` = `Buff(131072) | Spell(256)`), so DataProcess
unpacks `SkillType.Buff` from the bits and CalcSetup routes it into the
buff-tree bucket. Without an explicit entry in `whileActiveBuffByTreeId`
the `enabled` gate on those tree-node mods degrades from
`Condition:HaveEterrasBlessing` to `group.enabled` — i.e. "skill is on
the bar" instead of "buff is currently active". LE's Buffs panel shows
EB OFF by default (matching its 4s timed-duration semantics), so for
parity LEB must default it OFF too and require the condition flag to
turn it on.

Symptom before fix (BOwJnY3Y Beastmaster, eb5656-2 #3 "Safeguard"

| Site | File | What it does |
|---|---|---|
| gate | `src/Modules/CalcSetup.lua` (~line 1432, `whileActiveBuffByTreeId`) | Adds `["eb5656"] = "HaveEterrasBlessing"` next to Flame Ward / Werebear etc |

**Spec:** `spec/System/TestEterrasBlessingBuffGating_spec.lua`
- "LE_WHILE_ACTIVE_BUFF_BY_TREE_ID maps eb5656 to HaveEterrasBlessing"

**Establishing commit:** `54e35c701`

### `mourningfrost-per-dex-resist-penalty`

Mourningfrost (Leather Boots unique, id 19) carries a per-Dexterity
penalty `-1% Physical and Cold Resistance per point of Dexterity`
(per LE_datamining `unique_mods_generated.json` id=19). Before fix
`uniques_1_4.json` listed only the freeze-rate-multiplier and
movement-speed mods, so LEB's Cold/Phys totals were ~Dex points higher
than LE on every Mourningfrost build (e.g. Qdz2XagK Falconer Dex=91:
LEB Cold=72 / Phys=85, LE Cold=−19 / Phys=−5, both Δ≈+91).

Mod text was added as two separate lines `-1% Physical Resistance per
Dexterity` / `-1% Cold Resistance per Dexterity` to match LEB's existing
ModParser per-stat patterns (parses to `PhysicalResist|ColdResist BASE
-1` with `PerStat:Dex` tag).

| Site | File | What it does |
|---|---|---|
| data | `src/Data/Uniques/uniques_1_4.json` (id 19, Mourningfrost) | Adds the two missing per-Dex resist penalty mod lines |

**Spec:** `spec/System/TestMourningfrostMods_spec.lua`
- "uniques_1_4.json Mourningfrost has per-Dexterity Phys+Cold resist penalty"
- "ModParser parses '-1% Physical Resistance per Dexterity' as PerStat:Dex"
- "ModParser parses '-1% Cold Resistance per Dexterity' as PerStat:Dex"

**Establishing commit:** `97a25e5c3`

### `flat-damage-to-attacks-and-spells`

LE uses the phrasing `<N> <Type> Damage to/with Attacks and Spells` on flat-added
damage mods that should apply to BOTH attack-source skills (Melee|Throwing|Bow)
AND spell-source skills. Mourningfrost (id 19) carries
`+1 Cold Damage to Attacks and Spells per Dexterity` as one such case.

Without explicit `modFlagList` entries, the parser would either drop the keyword
or only catch the trailing word ("spells"), causing the attack side to silently
fall through and the mod to undercount on attack-skill builds. Four phrasing
permutations are registered (`to`/`with` × `Attacks and Spells`/`Spells and
Attacks`) so any LE wording lands on `KeywordFlag.Attack | KeywordFlag.Spell`.

| Site | File | What it does |
|---|---|---|
| parser | `src/Modules/ModParser.lua` (`modFlagList` near `to attacks and spells`) | Maps the four phrasings to `bor(KeywordFlag.Attack, KeywordFlag.Spell)` |
| data | `src/Data/Uniques/uniques_1_4.json` (id 19) | Carries the mod line that depends on the parser entry |

**Spec:** `spec/System/TestMourningfrostMods_spec.lua`
- "ModParser parses '+1 Cold Damage to Attacks and Spells per Dexterity' with Attack+Spell flags and PerStat:Dex"
- "uniques_1_4.json Mourningfrost has per-Dexterity Phys+Cold resist penalty" (extended to also cover the cold-damage mod line)

**Establishing commit:** `97a25e5c3`

### `quest-apophis-majasa-plus-one`

| Site | File | What it does |
|---|---|---|
| config | `src/Modules/ConfigOptions.lua` (`questApophisMajasa`) | Adds +1 BASE to each of Str/Dex/Int/Att/Vit |
| config | `src/Modules/ConfigOptions.lua` (`questTempleOfEterra`) | Adds +1 BASE to each of Str/Dex/Int/Att/Vit |

**Spec:** `spec/System/TestQuestApophisMajasa_spec.lua`
- "QuestApophisMajasa applies +1 BASE to all five attributes"
- "QuestTempleOfEterra applies +1 BASE to all five attributes"

**Establishing commit:** `69e160afc`

### `humble-idol-scalar-scale-first`

**Spec:** `spec/System/TestItemTools_spec.lua`
- `tests applyRange('+(3-7) Vitality', 221.00, 0.38)` → `+3 Vitality`
- `tests applyRange('+(3-7) Vitality', 98.00, 0.38)` → `+2 Vitality`

**Establishing commit:** `8d7a017cc`

### `apiarist-scalar-interpolate-first`

**Spec:** `spec/System/TestItemTools_spec.lua`
- `tests applyRange('+(11-13) to Strength', 57.00, 1.50)` → `+17 to Strength`

**Establishing commit:** `8d7a017cc`

### `body_armor-banker-rounding`

> **Type: JSON-comment-incompatible.** The protected sites live in
> `src/Data/ModItem_1_4.json`, which cannot carry inline
> `@leb-regression-guard:` markers (JSON has no comments). The 3-layer
> contract is preserved by the spec + this index entry; any new JSON
> mass-edit tool MUST reference this guard id in its commit message.
> See "JSON-comment-incompatible guards" at the bottom of this file.

| Site | File | What it does |
|---|---|---|
| data | `src/Data/ModItem_1_4.json` (22 entries listed above, body_armor.`"1"`) | Carries the banker-rounded min/max values |
| audit | `.tmp/audit_body_armor_rounding.py` | Reproducible enumerator: parses ModItem, joins canonical tiers, asserts banker(base×1.5) == stored within ±1 |
| canonical | `LE_datamining/extracted/items/single_affixes_v3.json` `tiers[].minRoll/maxRoll` | Source of canonical base; not in repo |
| canonical | `LE_datamining/extracted/items/equipmentItems.json` `BaseTypeName=Body Armor` `affixEffectModifier=0.5` | Source of the ×1.5 multiplier |

**Spec:** `spec/System/TestBodyArmorBankerRounding_spec.lua`
- Asserts representative keys across all 9 affix IDs match banker(base×1.5),
  with explicit "(was X) → (now Y)" pairs locked in.

**Establishing commit:** `b2c827401`

### `lament-base-damage-conversion`

Lament of the Lost Refuge (and any future unique using the same idiom)
carries the verbatim mod: *"100% of Volcanic Orb Base Damage Converted
to Void"*. Only the full **100%** form rewrites the skill's intrinsic
base-damage stat key — partial conversions (e.g. `50% of fire damage
converted to cold`) stay handled by the generic `"% damage converted"`
suffix chain elsewhere and must NOT route through this rewrite.

Two paired sites cover the same invariant: tag swap (so affix
targeting like "+X% to Void Damage" applies) and base-damage stat-key
rewrite (so `spell_base_fire_damage` flows into the destination type's
damage pool). The pattern `"100% of <Skill> Base Damage Converted to
<Type>"` is matched verbatim — adding an alternate phrasing requires

| Site | File | What it does |
|---|---|---|
| tag swap        | `src/Modules/CalcActiveSkill.lua` (~line 644) | Inside `getItemSkillTagConversions` — when the generic `"<Skill> is converted to <type>"` pattern misses, falls through to the `100% of <Skill> base damage converted to <type>` pattern so the skill's intrinsic damage tag also swaps |
| base-key rewrite | `src/Modules/CalcActiveSkill.lua` (~line 682, on `calcs.getItemSkillBaseDamageConversion`) | Returns the destination type lower-case ("void", "cold", …) used by `mergeSkillInstanceMods` to rewrite stat keys like `spell_base_fire_damage` → `spell_base_void_damage` |
| paired guard | (cross-ref) | [`lament-volcanic-orb-cannot-freeze`](#lament-volcanic-orb-cannot-freeze) uses the same trigger to suppress freeze on Volcanic Orb + Lament |

**Spec:** `spec/System/TestLamentVolcanicOrbCannotFreeze_spec.lua`
- "cannotFreeze trigger uses the base-damage-conversion helper"
  (locks the helper exists and gates correctly)
- "Lament of the Lost Refuge retains the 100% Volcanic Orb -> Void
  conversion line" (locks the verbatim mod text in `uniques.json`)

**Establishing commit:** `f1a9c3eaf` — _feat(calc): Lament of the Lost
Refuge full base damage conversion_

### `lament-volcanic-orb-cannot-freeze`

Lament of the Lost Refuge altText (verbatim): *"Volcanic Orb's base damage is
converted to void and scales with increases to void damage instead of fire or
cold. **It cannot freeze even if previously converted to cold.**"* The
freeze-suppression clause is implicit in altText only — there is no explicit
mod line for it in `uniques.json`.

Clause-to-code mapping (paste this verbatim quote in the source comment so
future edits cannot drift from the authoritative wording):

| Site | File | What it does |
|---|---|---|
| gate    | `src/Modules/CalcOffence.lua` (~line 1661)         | Zeros `FreezeRate` and `FreezeChance` when Volcanic Orb has any 100% base-damage conversion in effect via an equipped item |
| trigger | `src/Modules/CalcActiveSkill.lua` (~line 696)      | `getItemSkillBaseDamageConversion` returns the destination type (paired with `lament-base-damage-conversion`) |

**Spec:** `spec/System/TestLamentVolcanicOrbCannotFreeze_spec.lua`
- "regression-guard comment block is present"
- "FreezeRate assignment routes through the cannotFreeze gate"
- "FreezeChance assignment routes through the cannotFreeze gate"
- "cannotFreeze trigger uses the base-damage-conversion helper"
- "cannotFreeze does NOT inspect destination type" (locks against speculative re-introduction of `dst ~= "cold"`)
- "cannotFreeze gates on Volcanic Orb name"
- "Lament of the Lost Refuge retains the 100% Volcanic Orb -> Void conversion line"

### `slot-banker-rounding`

> **Type: JSON-comment-incompatible.** Sister guard to
> `body_armor-banker-rounding`; same rationale and 3-layer contract apply.

| Site | File | What it does |
|---|---|---|
| data | `src/Data/ModItem_1_4.json` (5 entries above) | Carries banker-rounded min/max for amulet/catalyst slots |
| audit | `.tmp/audit_slot_rounding.py` | Per-slot enumerator across amulet/shield/catalyst/idol/weapon |
| canonical | `LE_datamining/extracted/items/single_affixes_v3.json` `tiers[].minRoll/maxRoll` | Canonical base; not in repo |
| canonical | `LE_datamining/extracted/items/equipmentItems.json` `affixEffectModifier=0.17` | Source of the ×1.17 multiplier |
| canonical | `LE_datamining/extracted/rounding_decompile_raw.txt` | Decompiled `AscendingValueAfterPropertyRounding` (RVA 0x2307CC0) |

**Spec:** `spec/System/TestSlotBankerRounding_spec.lua`
- Asserts the 5 patched (affixId, tier, slot) triples match banker(base×1.17),
  with explicit "(was X)" hints locked in.

**Establishing commit:** `055e90f27`

### `block-chance-total-always-set` (renamed from `block-chance-total-no-shield-zero`)

`output.BlockChanceTotal` is the **uncapped** pre-cap total used by both the
LETools cross-build diff (`scripts/letools-diff.js` `'block chance' →
BlockChanceTotal`) and the Calcs detail panel. With the
`block-requires-shield` gate retired (see `game-faithful-block-no-shield-gate`),
the block calc branch is now unconditional and always assigns
`output.BlockChanceTotal`. When there are no block mods (e.g. Bakbr2Ne
Sorcerer with Catalyst off-hand and no block-affixed items), the natural
`baseBlockChance + mods` sum is `0`, which the unconditional branch writes
verbatim — `BlockChanceTotal` is never left `nil`.

The historical concern this guard addressed (62/68 G1 shield-less builds
showing "?" in `letools-diff.js`) is now satisfied by the unconditional
write, not by a no-shield zero branch.

| Site | File | What it does |
|---|---|---|
| unconditional set | `src/Modules/CalcDefence.lua` (~line 354) | `output.BlockChanceTotal = totalBlockChance` (uncapped pre-cap; `0` when no mods) |
| diff mapping    | `scripts/letools-diff.js` (~line 86) | `'block chance' → BlockChanceTotal` |

**Spec:** `spec/System/TestBlockShield_spec.lua` — locks
`BlockChanceTotal ~= nil` for builds with no block mods (value = 0, not nil).

**Snapshot coverage:** `spec/System/TestBuilds_spec.lua` "test all builds
#builds" — G1 builds without block mods serialize `BlockChanceTotal = 0`;
shield/non-shield builds with block mods serialize the actual total.

**Establishing commit:** `8c32b550e` (original no-shield zero);
_this commit_ (rename + game-faithful rationale).

### `ward-regen-canonical-key-wardpersecond`

The LETools cross-build diff label `'ward regen'` MUST map to the LEB output
key `WardPerSecond`, not to a synthetic `WardRegen` alias and not to
`NetWardRegen` (gross minus decay).

Game-data canonical naming (`LE_datamining/extracted/localization/ui_localization.json`):

```
StatsPanel_DefenseStats_WardPerSecond_Label = "Added Ward Per Second"
StatsPanel_DefenseStats_WardPerSecond_Description = "Added Ward Per Second"
```

The in-game stats panel and LETools tooltip both display this gross "ward per

| Site | File | What it does |
|---|---|---|
| diff mapping | `scripts/letools-diff.js` (~line 86) | `'ward regen' → key: 'WardPerSecond'` (with inline guard comment) |
| compute     | `src/Modules/CalcPerform.lua` (~line 1283, ~line 1308) | Writes `output.WardPerSecond` (base + INC/MORE; Sanguine Runestones bonus) |
| consume     | `src/Modules/CalcDefence.lua` (~line 415, ~line 690) | Reads `output.WardPerSecond` for ward / `NetWardRegen` derivation |

**Establishing commit:** `8c32b550e`

### `ward-decay-floor-zero-passive`

Game `ProtectionClass.Update` (RVA `0x234B8C0`, non-boss branch) clamps the
per-frame ward decay to `dt * minimumWardDecayWithoutRegen` (= `dt * 0.5`)
iff the passive ward-regen sum `wardRegen + wardRegenFromStats <= 0`. Event-
driven gains (e.g. ManaSpentGainedAsWard, WardOnHit, WardOnKill) are routed
through a separate `GainWard(amount)` call and do **not** count toward the
floor gate.

Verbatim source quote (`LE_datamining/extracted/ward_decompile.txt` L72-85):

```
fVar12 = (dt * (Q*(W-T)^2 + B*(W-T))) / (Rclamped * 0.5 + 1.0);   // smooth decay
fVar10 = floorRate;                                                // = 0.5

| Site | File | Inline marker | What it does |
|---|---|---|---|
| compute (passive snapshot + floor) | `src/Modules/CalcPerform.lua` (~line 1306-1340) | `@leb-regression-guard:ward-decay-floor-zero-passive` | Snapshots passive WPS before adding ManaSpent bonus; clamps `rawWardDecayPerSecond` at 0.5 when passive ≤ 0 |
| cross-reference | `src/Modules/CalcDefence.lua` (~line 454) | (comment reference) | Documents why the main/Sanguine decay sites cannot trigger the floor |

**Spec:** `spec/System/TestWardDecayFloor_spec.lua`
- "CalcPerform.lua snapshots passive WPS before adding ManaSpentGainedAsWard"
- "CalcPerform.lua applies 0.5/s decay floor when passive WPS <= 0"
- "CalcPerform.lua carries the inline regression-guard marker"
- "CalcDefence.lua documents why the floor cannot trigger at its decay sites"

### `ward-decay-gpp-constants`

Locks the three `GlobalPlayerProperties` ward-decay constants
(`linearWardDecay=0.2`, `quadraticWardDecay=5E-05`, retention-divisor
form `1 + 0.5*R/100`) verbatim into the LEB stable-ward inversion and
ward-decay-per-second formulas. The existing `ward-retention-negative-clamp`
guard only pins the R-clamp; the GPP coefficients themselves were unguarded
and a silent simplification (e.g. rounding `5E-05` to 0, dropping the
quadratic term, or swapping `0.2` for an older tunklab approximation) would
not be caught by the single-point clamp behaviour spec.

Verbatim source — `LE_datamining/extracted/typetree_dumps/GlobalPlayerProperties.json`:

```

| Site | File | Inline marker | What it does |
|---|---|---|---|
| passive stable-ward inversion | `src/Modules/CalcDefence.lua` (~line 471) | `@leb-regression-guard:ward-decay-gpp-constants` (passive stable-ward inversion) | Solves `wgain = wardLost/s` for W using verified GPP constants |
| display decay | `src/Modules/CalcDefence.lua` (~line 511) | `@leb-regression-guard:ward-decay-gpp-constants` (display-decay site) | Computes `WardDecayPerSecond` for tooltip |
| Sanguine Runestones recompute | `src/Modules/CalcDefence.lua` (~line 740) | `@leb-regression-guard:ward-decay-gpp-constants` (Sanguine Runestones recompute) | Recomputes Ward/Decay after `LifeRegenAppliesToWard` bonus |
| post-offence ManaSpentGainedAsWard | `src/Modules/CalcPerform.lua` (~line 1320) | `@leb-regression-guard:ward-decay-gpp-constants` (post-offence ManaSpentGainedAsWard path) | Recomputes Ward/Decay after `ManaSpentGainedAsWard` amortization |

**Spec:** `spec/System/TestWardGPPConstants_spec.lua`
- "CalcDefence.lua carries 3 inline guard markers (passive / display / Sanguine)"
- "CalcPerform.lua carries 1 inline guard marker (post-offence ManaSpentGainedAsWard)"
- "CalcDefence.lua passive stable-ward inversion uses the verified constants"
- "CalcPerform.lua post-offence stable-ward inversion uses the verified constants"
- "CalcDefence.lua stable-ward inversion appears at both passive + Sanguine sites"
- "CalcDefence.lua display-decay numerator = 0.2 * W + 0.00005 * W^2"
- "CalcDefence.lua decay numerator appears at both passive + Sanguine sites"
- "CalcPerform.lua post-offence decay numerator uses the verified constants"
- "CalcDefence.lua display-decay divisor uses retentionClamped at -90 floor"
- "Sanguine + CalcPerform divisor uses wardRetention at -90 floor"

### `ward-regen-resource-conversion`

Locks the parser + post-offence integration for the continuous resource→ward
conversion affixes. Before this guard the parser dropped these lines to
`LEB_NotSupported` (form `% of Y gained as Z`) or mis-parsed the `+N%` form
as `Life`/`Mana INC` (no `WardPerSecond` contribution at all). Both are
silent failures: the affected items lose their entire ward-regen budget with
no numeric diff that any existing spec catches.

**Spec:** `spec/System/TestWardRegenResourceConversion_spec.lua` (13 tests
covering parser pattern presence, mod-kind emission, post-offence fold-in
read of both mod kinds, marker counts, passive-snapshot composition, and
the breakdown publication).

### `ward-gained-per-second-alias`

Locks the `ModParser` nameMap alias for the idol affix
`(N) Ward gained per second while wielding a Staff`
(`src/Data/ModIdol_1_4.json` idol_900_0 Suffix, scales 1..18 across tiers).

Before this guard the parser only mapped the canonical `"ward per second"`
name to `WardPerSecond`. The actual affix wording uses `"Ward gained per
second"`, so the numeric BASE mod fell through to the bare `Ward` stat (max
ward) and the residue `"  gained per second  "` was left unparsed — equipping
the idol would grant `+N max Ward` instead of `+N Ward per Second`. Silent
failure that doesn't show up in any numeric Ward output diff.

**Spec:** `spec/System/TestWardGainedPerSecond_spec.lua` (3 tests covering
nameMap alias presence, the 7 corrected ModCache entries, and absence of the
stale `name="Ward"` + `"  gained per second  "` residue parse).

### `ward-gained-each-second-alias`

Locks the `ModParser` nameMap alias for the Wandering Spirit unique-mod
wording `(N) Ward gained each second per Active Wandering Spirit`. Two
unique items roll this mod:
- `src/Data/Uniques/uniques_1_4.json` L4631 — "Symbol of Hope"
- `src/Data/Uniques/uniques_1_4.json` L7464 — unique helmet

Same silent-failure shape as `ward-gained-per-second-alias`: without the
`"ward gained each second"` alias the numeric BASE mod fell through to
the bare `Ward` stat (max ward), the residue `"  gained each second  "`
was left unparsed, and the `per Active Wandering Spirit` multiplier was
glued to the wrong stat — equipping the unique granted `+N max Ward per
spirit` instead of `+N Ward per Second per spirit`. Invisible in any

**Spec:** `spec/System/TestWardGainedEachSecond_spec.lua` (4 tests
covering nameMap alias presence, the 2 corrected Wandering Spirit
ModCache entries, the `+1 Ward Gained Per 3 Int Per Second` PerStat
entry, and absence of the stale `name="Ward"` + `"  gained each second  "`
residue parse).

### `ward-per-n-seconds-tick`

Mage tree node "Decree of the Eternal Tundra" (Mage-94,
`src/TreeData/1_4/tree_1.json` L1900) carries the stat
`+10 Ward Per 2 Seconds` with description "You gain ward every 2 seconds."

Before this guard the line fell through to `name="Ward"` (max ward) with
residue `"  Per 2 Seconds "` — allocating the node granted +10 max Ward
instead of +5 Ward per Second. Silent failure invisible in any numeric
Ward output diff.

The handler models the tick as a continuous WardPerSecond contribution
with value = N / seconds. In-game tick granularity is below the planner's
steady-state resolution, so 10 over 2 s and 5 over 1 s yield the same

**Spec:** `spec/System/TestWardPerNSecondsTick_spec.lua` (3 tests covering
parser handler registration, the corrected ModCache entry, and absence of
the stale `name="Ward"` max-ward parse).

### `skill-grants-ward-per-second`

Rune Master node "Runes of Disintegration" (`src/TreeData/1_4/tree_1.json`
L10164) carries the stat `+40 Disintegrate Grants Ward Gain Per Second`
with description "channelling it while standing on your Glyph".

Before this guard the line fell through to `name="Ward"` (max ward) +
`SkillName:Disintegrate` tag with residue `"  Grants  Gain Per Second "`.
Allocating the node granted +40 max Ward attached to Disintegrate damage
instead of +40 WPS while channelling. Silent failure invisible in any
numeric Ward output diff.

The handler is registered inside the same per-skill loop that powers
`+N Ward per Second while channelling <skill>`, so it inherits the

**Spec:** `spec/System/TestSkillGrantsWardPerSecond_spec.lua` (3 tests
covering parser handler registration, the corrected ModCache entry, and
absence of the stale `name="Ward"` + `SkillName:Disintegrate` parse).

### `gon-rune-multiplier`

Rune Master tree node "Empowered Runes" (`src/TreeData/1_4/tree_1.json`
L12835, rn7iv-13) carries three per-rune-type stats:

```
"2% Increased Mana Regen per Rah Rune",
"+4 Ward Gain Per Second per Gon Rune",
"+8% Freeze Rate Multiplier per Heo Rune"
```

The ward-regen variant (`+4 Ward Gain Per Second per Gon Rune`) was
falling through to `name="Ward"` (max ward) BASE=4 with residue
`"  Gain Per Second per Gon Rune "`. Allocating the node granted

**Spec:** `spec/System/TestGonRuneMultiplier_spec.lua` (5 tests covering
the modTag entry, the nameMap alias, the Config option, the corrected
ModCache entry, and absence of the stale `name="Ward"` parse).

### `heo-rah-rune-multiplier`

Sibling of `gon-rune-multiplier`. The same Rune Master "Empowered Runes"
node carries Heo Rune and Rah Rune stats, and the corresponding affixes
on Runemaster gear were silently mis-parsed at the same time the ward
regen variant was. Symptoms:

- `+N Dodge Rating per Heo Rune` (affixes, ~17 tiers) parsed as bare
  `name="Evasion"` BASE=N with residue `"  per Heo Rune "`. The per-rune
  multiplier was dropped — flat dodge rating granted independent of the
  player's active Heo Rune count.
- `+8% Freeze Rate Multiplier per Heo Rune` (tree node) parsed as bare
  `name="FreezeRateMultiplier"` BASE=8 with the same residue. The freeze
  rate buff applied unconditionally instead of scaling per Heo Rune.

**Spec:** `spec/System/TestHeoRahRuneMultipliers_spec.lua` (10 tests
covering both modTag entries, both Config options, both tree-node
ModCache entries, a representative affix entry for each rune type, and
absence of any `"  per Heo Rune "` / `"  per Rah Rune "` residue).

### `wielding-weapon-conditions`

Covers two related "wielding a `<weapon>`" silent-failure parses on
Sentinel / Forge Guard / Spellblade gear.

**Spec:** `spec/System/TestWieldingWeaponConditions_spec.lua` (8 tests
covering the weapon list, both CalcSetup branches, the 2-Handed tagList
construction site, a representative Mace + 2-Handed Axe ModCache entry,
and absence of either stale residue string).

### `channelling-tree-node-auto-gate`

Channelled-buff skill tree nodes (Focus, Smelter's Wrath, Volcanic Orb,
Disintegrate et al.) must have every stripped mod auto-wrapped with
`Condition:Channelling` at tree-build time so stats described as
"while channeled" only contribute while the player is channelling
the buff.

Before the establishing commit (`eab24578b` —
_fix: gate channelling-skill tree node mods by Condition:Channelling_)
Focus tree stats like Everward "+50% Ward Retention" applied
unconditionally, inflating Ward Retention by +100% on BakypDvx
Runemaster (LEB 595% vs LETools 505%).

This tree-build-time gate is the **complement** of the ModParser-side

**Establishing commit:** `eab24578b`

### `channelling-per-second-stacking-buff`

Channelling-stacking-buff "Per Second" Damage nodes such as

- Smelter's Wrath "+5% Damage Per Second" (`src/TreeData/1_4/tree_2.json`
  L14336),
- Flurry "Accelerating Impact" "+3% Damage Per Second"
  (`src/TreeData/1_4/tree_4.json` node `flur3-14`, parent description
  "Flurry is now a channelled ability that costs mana per second to
  maintain."), and
- Volcanic Orb "+20% Damage Per Second" (`src/TreeData/1_4/tree_2.json`
  node `va53st-19`)

gain a stack each second while the player is channelling, granting +N%

**Spec:** `spec/System/TestChannellingPerSecondStackingBuff_spec.lua` (6
tests covering Config publication, ModParser pattern + handler, all
three patched ModCache entries, and absence of any stale unconditional
MORE form for the 3 patched values).

### `health-per-second-channelling`

The Focus tree node "Inner Growth" (Mage `tree_1.json` L17197 node
`vm53dx-14`) carries the stat `"6 Health Per Second"` with description
"Focus heals the target each second while channeled." and reminderText
"This effect is affected by increased healing effectiveness."

Before this guard the bare `"+N Health Per Second"` form fell through
to ModParser's generic `health` keyword and was parsed as
`name="Life"` `BASE=N` with residue `"  Per Second "` — silently
granting +N *maximum* Health, completely unrelated to the actual
mechanic (a channelled-skill life regen tick).

**Spec:** `spec/System/TestHealthPerSecondChannelling_spec.lua` (4
tests covering specialModList pattern presence, handler emission,
ModCache entry correctness, and absence of the stale `name="Life"`
parse + `"  Per Second "` residue).

### `ward-on-block-resource-conversion`

**Spec:** `spec/System/TestWardOnBlockResourceConversion_spec.lua` (covers
parser pattern presence, mod-kind emission, CalcDefence Sum + arithmetic +
breakdown publication, marker presence, and the CalcSections row wiring).

### `ward-on-potion-use-resource-conversion`

**Spec:** `spec/System/TestWardOnPotionUseResourceConversion_spec.lua`

### `ward-stop-moving-config-amortize`

Transient Rest unique affix
`(40-60)% of Current Mana gained as Ward when you stop moving (2 second cooldown)`
was a silent failure: ModCache L15263 carried the 50% form as
`LEB_NotSupported`. Game-side authority (dump.cs, il2cpp re-extraction):

- L95850 `public float currentManaGainedAsWardOnStopMoving; // 0xDB0`
- L95851 `private const float currentManaGainedAsWardOnStopMovingCooldown = 2;`
- Distinct field from the continuous variant `currentManaGainedAsWardPerSecond`
  (L95820 offset 0xD38).
- Event-driven sources feed `ProtectionClass.GainWard(amount)` separately from
  passive `wardRegen + wardRegenFromStats`; they are NOT part of the 0.5/s
  decay floor gate (see `LE_datamining/extracted/ward_formulas.md §2`).

LEB amortizes the affix as a steady-state continuous Ward per Second
contribution over the 2-second hard cooldown, gated on a Config tab toggle so
it does not perturb baseline parity with LETools UI (which omits event-driven
ward sources from its surface):

```
amortized wps = currentMana * pct / 100 / 2  -- only when conditionStoppedMoving is on
```

The contribution lands in `output.WardPerSecond` via the post-offence fold-in
block in `CalcPerform.lua`. Like `manaSpentContribution`, it is excluded from
the `passiveWardPerSecond` snapshot used by the floor-gate parity check
(event-driven mechanics live outside `wardRegen + wardRegenFromStats` in the
game-side decay path).

| Site | File | Inline marker | What it does |
|---|---|---|---|
| parser | `src/Modules/ModParser.lua` (after the on-block ward block) | `@leb-regression-guard:ward-stop-moving-config-amortize (parser site)` | Adds four `specialModList` patterns (with/without "of ", with/without "(2 second cooldown)" suffix) emitting BASE `CurrentManaGainedAsWardOnStopMoving` |
| config | `src/Modules/ConfigOptions.lua` (after `conditionStandingOnGlyphOfDominion`) | `@leb-regression-guard:ward-stop-moving-config-amortize (config site)` | `conditionStoppedMoving` check toggle; Combat-scoped FLAG `Condition:StoppedMoving` |
| fold-in | `src/Modules/CalcPerform.lua` (post-offence ward regen block) | `@leb-regression-guard:ward-stop-moving-config-amortize (fold-in site)` | Reads `CurrentManaGainedAsWardOnStopMoving`, gates on `Condition:StoppedMoving`, amortizes `(Mana * pct / 100 / 2)`, folds into `output.WardPerSecond` and adds a breakdown line; **excludes from `passiveWardPerSecond` snapshot** so the 0.5/s decay floor matches the game-side `wardRegen + wardRegenFromStats <= 0` gate |

**Spec:** `spec/System/TestWardStopMovingConfigAmortize_spec.lua`
- Parser pattern presence (both "of" / bare forms, both with-cooldown forms)
- `CurrentManaGainedAsWardOnStopMoving` mod-kind emission
- Config toggle definition + Combat-scoping
- CalcPerform Sum + Condition gate + `/2` amortization + total-contribution arithmetic
- Floor-gate parity: `passiveWardPerSecond` does NOT include `stopMovingContribution`
- All three inline `@leb-regression-guard` markers present

**Test build coverage:** o3Zlpkxd lv98 Necromancer wears Transient Rest; the
affix contributed 0 wps prior to this fix.

**Game-file backing:** `dump.cs` L95850-L95851 (field + cooldown constant);
`LE_datamining/extracted/ward_formulas.md §2` (event-driven vs passive floor
gate).

### `resist-display-round-half-up`

The 7-resist loop in `src/Modules/CalcDefence.lua` previously truncated the
total resistance via `math.modf` ("Fractional resistances are truncated").
LE actually stores resistance as `float` and renders the tooltip integer
with round-half-up:

```
dump.cs:156801
  public class PrecalculatedStatsHolder : MonoBehaviour {
      public float uncappedPhysicalResistance;     // 0x20  <-- float, not int
      public float uncappedFireResistance;         // 0x24
      ...
  }

**Establishing commit:** `f09b98359`

### `resist-base-high-precision`

`ScaleAddMod` in `src/Classes/ModStore.lua` calls `m_modf` (integer part)
on the scaled value when the mod's `(name, type)` pair is not registered
in `data.highPrecisionMods`. Resist-tree skill node mods like Holy Aura
`ah443-0` (`+15% Fire/Cold/Lightning Resistance`) get scaled by skill-buff
prefix INC mods (Sentinel-119 _Covenant of Light_: `HolyAuraEffect +4%/pt`)
through `CalcSetup.lua applyBuffPrefix → ScaleAddList → ScaleAddMod`.
Without precision=1, `15 * 1.04 = 15.6` truncates to `15` and the
resist-display round-half-up fix above can no longer recover the missing
0.6 — Δ=-0.6 / resist vs LE.

| Site | File | What it does |
|---|---|---|
| precision registration | `src/Modules/Data.lua` (`data.highPrecisionMods`) | `BASE = 1` for all 8 resist stat names so `ScaleAddMod` keeps fractional resistance after buff-tree scaling |

**Spec:** `spec/System/TestResistBaseHighPrecision_spec.lua`
- "registers BASE=1 precision for <stat>" (parameterized over the high-precision resist stat list)
- "Data.lua highPrecisionMods carries the @leb-regression-guard marker"

**Establishing commit:** `b7a3a3d54`

### `vshdm-percentage-units`

`itemLib.applyRangeStrict` is the LEB port of LE's `vshDm` /
`BaseStats.GetValueAfterRounding` (RVA 0x230B940). LE operates on

| Site | File | Inline marker | What it does |
|---|---|---|---|
| port core | `src/Modules/ItemTools.lua` (`applyRangeStrict`, ~line 449) | `@leb-regression-guard:vshdm-direct-port` | Numeric port of LE planner JS `vshDm` (= IL2CPP `BaseStats.GetValueAfterRounding`); shared interpolation kernel for all rounding modes |
| Hundredth ADDED branch | same (`applyRangeStrict`, ~line 437) | (within port core) | percentage-space formula `floor((d+1-c)*e + c + 0.1)`, clamp `v ≤ d` |
| Non-ADDED branch (INCREASED/MORE/QUOTIENT) | same | (within port core) | shares the percentage-space form (forced Hundredth) |
| Flat-integer router | `src/Modules/ItemTools.lua` (`applyRange`, ~line 337) | `@leb-regression-guard:flat-int-vshdm-strict` | Routes flat-int `+(N-N) <Stat>` affixes (no `%`) to the strict Integer vshDm path so scalar≤1.0 stays byte-identical with LE |

**Spec:** `spec/System/TestItemTools_spec.lua`
- "Hundredth-ADDED reproduces BEdKNL0j relic Phys Res 14-28 byte=100 = 19"
- "non-ADDED branch is forced to Hundredth+epsilon regardless of rounding arg"

**Establishing commit:** `411c1ce45`

### `banker-round-vshdm`

`applyRangeStrict` quantizes the (scaled) min/max **endpoints** with
banker's rounding (round half to even), matching LE's
`AscendingValueAfterPropertyRounding` (RVA 0x2307cc0) which calls
`FUN_18038f970` — the IL2CPP banker round helper that delegates to
`FUN_1803207e8` (modf) and biases by `±DAT_183d81f40` on parity. C#
`Math.Round` / `Mathf.RoundToInt` default to
`MidpointRounding.ToEven`, NOT half-up.

The divergence shows up only when `scalar*min` or `scalar*max` lands

| Site | File | What it does |
|---|---|---|
| helper | `src/Modules/ItemTools.lua` (`local function banker_round`, ~line 24) | round-half-to-even using `m_floor` + parity check |
| Hundredth/Integer/Tenth/Thousandth branches | `src/Modules/ItemTools.lua` (`applyRangeStrict`, ~line 482) | use `banker_round` for `c`, `d` endpoint quantization |

**Spec:** `spec/System/TestItemTools_spec.lua`
- `describe("banker-round-vshdm endpoints (round-half-to-even)")` —
  three cases: BgRrP5rr Void byte=93 → 99; banker(91.5)=92 +
  banker(112.5)=112; banker(0.5)=0 + banker(1.5)=2.

**Establishing commit:** `e60cdbd0f`

### `resist-vshdm-strict`

The seven elemental resistance affix lines plus the composite
`% Elemental Resistance` line all route through `applyRangeStrict`
Hundredth, not just Physical. The original `phys-res-vshdm-strict`
guard scoped the routing to one resist; the default `applyRange`
branch handled the other six but was missing LE's `+0.001` (fraction)
/ `+0.1` (percent) epsilon, so byte values in the middle of a range
floored down by 1. Combined with `vshdm-percentage-units` above, all
covered resistance affixes now match LE per source.

LE property reference: `extracted/items/property_list_v3.json`
property 52 "Elemental Resistance" → `roundingForAdded = 0` (Hundredth),
which is why the composite affix joins the strict path.

| Site | File | What it does |
|---|---|---|
| pattern routing | `src/Modules/ItemTools.lua` (`applyRange`, ~line 269) | `% (Cold|Fire|Lightning|Necrotic|Poison|Void|Physical|Elemental) Resistance` → `applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, 0)` |
| historical predecessor | `src/Modules/ItemTools.lua` (`applyRange`, marker `@leb-regression-guard: phys-res-vshdm-strict`) | Original single-resist scope (Physical only) — kept as a separate marker so a future revert that re-narrows the routing surfaces as a distinct guard hit rather than silently re-orphaning the six other resists |

**Spec:** indirectly covered by the `vshdm-percentage-units` cases
plus the AL07RL31 + QeY7962P G1 build snapshots. A dedicated spec is
intentionally omitted because the routing pattern is a single regex
and any future change to it will surface as a snapshot diff for the
covered resists across ~80 builds with at least one resist roll.

**Establishing commit:** `411c1ce45`

### `minion-movement-speed-vshdm-strict`

`% increased Minion Movement Speed` and `% reduced Minion Movement Speed`
affix rolls route through the LE-faithful vshDm Hundredth path
(`applyRangeStrict(..., modType=0, rounding=0)`). The legacy `applyRange`
default branch uses `span = max - min` and a round-half-up endpoint
fold for `% increased / % reduced` lines, which under-rounds bytes that
land in the middle of a small range by 1.

LE's actual formula (reverse-engineered from
`AscendingValueAfterPropertyRounding`, see `vshdm-percentage-units`)
adds the `+1/precision` span term — equivalently, the upper endpoint
contributes `d + 1` rather than `d`. For integer-rounded percent rolls
this becomes `floor((d + 1 - c) × byte/255 + c)`.

**Triangulation:** `BxvJP3g1 lv99 Necromancer` Pebbles' Collar Reforged
implicit `(6-16)% increased Minion Movement Speed` byte=186.

```
legacy round-half-up: floor((6 + 186/255 × 10) + 0.5) = floor(13.79) = 13
strict (vshDm):       floor((16 + 1 - 6) × 186/255 + 6) = floor(14.02) = 14
LETools planner Minion-tab "Movement Speed" = 14% ✓ matches strict
```

**Scope:** narrow — only the `Minion Movement Speed` substring routes
through strict. The player-scope `% increased Movement Speed` line is
intentionally NOT migrated here: the g1 boots rolls
`(15-18) byte=63 → legacy 16, strict 15` and
`(26-30) byte=153 → legacy 28, strict 29` sum to 44 either way, and the
g1 Player Movement Speed = 44 is already consistent with the LE in-game
display contract (the +1pt LETools shows is a separate LETools-side
display divergence not currently triangulated to a single mod).

| Site | File | What it does |
|---|---|---|
| pattern routing | `src/Modules/ItemTools.lua` (`applyRange`, after `resist-vshdm-strict` block) | `% (increased\|reduced) Minion Movement Speed` → `applyRangeStrict(minN, maxN, rollByte, valueScalar, 0, 0)` |

**Spec:** `spec/System/TestMinionMovementSpeedVshdmStrict_spec.lua`
- "Pebbles' Collar (6-16) byte=186 → 14 (matches LETools)"
- "low byte stays at min for narrow range"
- "top byte clamps at max"
- "'% reduced Minion Movement Speed' also routes through strict path"
- "player-scope '% increased Movement Speed' is NOT affected" (guards
  against an accidental broadening of the substring match)

**Establishing build:** `BxvJP3g1 lv99 Necromancer` — Minion-tab
`Movement Speed` 13 → 14 LETools parity.

**Establishing commit:** (pending)

### `corrupted-sealed-allres-round-half-up`

> **Type: JSON-comment-incompatible.** Protected files: `src/Data/ModItem.json`,
> `src/Data/ModItem_1_4.json` (affixId `1070_0`).

`Idol of Hope` and similar small idols carry a corrupted sealed
`All Resistances` affix (`affixId 1070`, `specialAffixType 6`).
Canonical `minRoll` / `maxRoll` in
`LE_datamining/extracted/items/multi_affixes_v3.json` is `0.008`
(raw float = 0.8%). LE displays the per-affix line with round-half-up
to `+1%` AND uses the rounded `1.0` value in the per-source resist sum
shown by LETools tooltips. LEB previously stored `+0.8%` to match the
raw float, producing ΔBASE=-0.2 / resist vs LE's stored sum.

The fix restores `+1% All Resistances` / `+1% Minion All Resistances` for

**Spec:** `spec/System/TestResistBaseHighPrecision_spec.lua`
- "<path> stores +1% (not +0.8%) on player and minion lines" (parameterized over ModItem.json and ModItem_1_4.json)
- (asserted for both `ModItem.json` and `ModItem_1_4.json`)

**Establishing commit:** `b7a3a3d54`

### `two-phase-floor-post-round-scalar`

`itemLib.applyRange`'s `postRoundScalar` argument multiplies the
already-quantized rolled value by an altar boost (Refracted-slot Weaver
Enchant 1.0–1.22) before rendering it as an integer/Tenth. LE renders
this post-boost value with **round-half-up**, not floor — verified by
comparing `LETools` tooltips against in-game UI on the
`owLmrO3a Spellblade lv99` idol-altar build.

Reverting any of the 5 `m_floor(x * postRoundScalar + 0.5)` sites in
`src/Modules/ItemTools.lua` to `m_floor(x * postRoundScalar)` silently
undershoots LE by 1 on every `(rolled * scalar)` whose fractional part
is `>= 0.5`.

Worked example — `owLmrO3a` Heretical Large Arcane Idol affix `897_4`

| Site | File | What it does |
|---|---|---|
| resist strict path | `src/Modules/ItemTools.lua` (~line 328) | `v = m_floor(v * postRoundScalar * precision + 0.5) / precision` |
| flat-int strict path | `src/Modules/ItemTools.lua` (~line 352) | `v = m_floor(v * postRoundScalar + 0.5)` |
| general interp-first | `src/Modules/ItemTools.lua` (~line 408) | `numVal = m_floor(numVal * postRoundScalar * precision + 0.5) / precision` plus matching `maxBoosted` clamp |
| single-value (Integer) | `src/Modules/ItemTools.lua` (~line 421) | `+ 0.5` before `m_floor` |
| single-value (other rounding) | `src/Modules/ItemTools.lua` (~line 427) | `+ 0.5` before `m_floor` |

**Spec:** `spec/System/TestPostRoundScalarRoundHalfUp_spec.lua`
- general interp-first: `+(2-9) Ward per Second` byte=255 scalar=1.22 → `+11`
- identity preservation: scalar=1.0 → `+9` unchanged
- flat-int strict path: `+(11-15) Vitality` byte=128 scalar=1.22 → `+16`
- resist strict path: `+(20-40)% Fire Resistance` byte=235 scalar=1.10 → `+43`

**Establishing commit:** `10651f048`

### `idol-altar-boost-subtype-rounding`

The Idol Altar refracted-slot boost (LE `SimpleBlessingType` property 4
`EffectOfIdolEnchantsInRefractedSlots`) applies to BOTH
`SpecialAffixType.IdolEnchantment` (=4) AND `SpecialAffixType.IdolWeaver`
(=5), but LE uses **subtype-dependent rounding** on the resulting
post-round value:

| Site | File | Branch |
|---|---|---|
| resist strict | `src/Modules/ItemTools.lua` (~L332) | `postRoundFloor` → floor, else round-half-up |
| flat-int strict | `src/Modules/ItemTools.lua` (~L355) | ditto |
| general interp + maxBoosted | `src/Modules/ItemTools.lua` (~L411) | ditto + matching maxBoosted clamp |
| single-value scalar≠1 | `src/Modules/ItemTools.lua` (~L425) | ditto |
| single-value scalar=1 zero-numbers | `src/Modules/ItemTools.lua` (~L431) | ditto |

**Spec:** `spec/System/TestIdolAltarBoostSubtypeRounding_spec.lua`

**Establishing commit:** (pending)

### `affix-effect-modifier-formula`

LEB applies the affix display multiplier as

```
modScalar = (1 + base.affixEffectModifier) / (1 + mod.standardAffixEffectModifier)
```

per the LE 1.4 IL2CPP dump (`AffixList.Affix.standardAffixEffectModifier`,
`il2cpp_dump_v142` line 164779):

> "if this is 0.5, then an item with affix effect modifier of 0.5 will
> have the stated values, and an item with affix effect modifier 0 will
> have 66.7% of the stated values."

| Site | File | What it does |
|---|---|---|
| `Item:Craft` (default + slotOverride) | `src/Classes/Item.lua` (~line 1351) | Computes `modScalar` for affixes during craft |
| `Item:Craft` (Omen Idol bypass)       | `src/Classes/Item.lua` (~line 1393) | Same, on Omen Idol bases (AEM penalty bypassed but standardAEM division preserved) |
| `ItemsTabCraft:Craft` (GUI)           | `src/Classes/ItemsTabCraft.lua` (~line 741) | Same, in the in-app craft tab path |

**Spec:** `spec/System/TestAffixEffectModifierFormula_spec.lua`
- "Item.lua / ItemsTabCraft.lua use division (not subtraction)"
- "Item.lua: +0.17 Solar-Idol-parity fudge is removed"
- "Guard markers are present"

**Establishing commit:** `7bb3625f8`

### `double-glancing-blow-if-not-hit`

Rogue passive `Rogue-104` ("Poise") declares a `notScalingStat` of
`" Double Glancing Blow Chance If Not Hit"` (leading space; threshold
of 5/5 points). After `PassiveTree.lua` trims and feeds the line to
`modLib.parseMod`, the bare wording `"Double Glancing Blow Chance If
Not Hit"` previously fell through to the generic parser, which emitted
empty mods plus leftover text — i.e. the stat was silently dropped.

LE applies this stat as `+100 INC GlancingBlowChance` while the player
has NOT been hit recently (LE's "If Not Hit" condition). The LETools
tooltip for `Qdz2PGqp lv88 Falconer` literally lists `Falconer Passive
Tree (Poise): 100% more Chance to receive a Glancing Blow when hit`,
which is the same +100% magnitude in display terms.

**Spec:** `spec/System/TestDoubleGlancingBlowIfNotHit_spec.lua`
- "'Double Glancing Blow Chance If Not Hit' parses to GlancingBlowChance INC 100"
- "BASE 12 + INC 100 produces 24 by default (BeenHitRecently off)"

**Establishing commit:** `a33401fc9`

### `chance-to-receive-glancing-blow-when-hit`

Item affixes worded as `(min-max)% Chance to receive a Glancing Blow when
hit` (e.g. ModItem_1_4 entry `933_*` "Glancing Blow chance and Increased
Dodge Rating") previously failed to parse: the form scanner consumed
`N% chance` as the CHANCE form, leaving the tail `to receive a glancing
blow when hit`, which had no `modNameList` entry. The mod silently
dropped, and stale `ModCache.lua` rows preserved the failure across runs
(`c["1% Chance to receive a Glancing Blow when hit"]={{}, "..."}`).

LE applies the affix as flat BASE GlancingBlowChance. LEB now aliases
the post-CHANCE-form tail to the existing `GlancingBlowChance` stat in
`modNameList` (`src/Modules/ModParser.lua` line ~92). The affix
accumulates as BASE alongside other Glancing Blow sources.

**Spec:** `spec/System/TestChanceToReceiveGlancingBlow_spec.lua`
- "'24% Chance to receive a Glancing Blow when hit' parses to GlancingBlowChance BASE 24"
- "no row in src/Data/ModCache.lua matches '% Chance to receive a Glancing Blow when hit'"

**Establishing commit:** `b2ad53f60`

### `dodge-more-multiplier`

**Spec:** `spec/System/TestDodgeMoreMultiplier_spec.lua`
- "parser strips '(multiplicative with other modifiers)' suffix and emits MORE Evasion"
- "displayed Evasion applies BASE × (1+INC) × MORE"
- "INC-only path still works when no MORE source is present"

**Establishing commit:** `bc702571e`

### `tree-rank-per-stat-divisor`

**Spec:** `spec/System/TestTreeRankPerStatDivisor_spec.lua`
- "regression-guard comment is present"
- "rank-scaling protects 'per N <attr>' divisors via [Pp]er pattern split"
- "does NOT apply a bare `stat:gsub(\"(%d[%d.]*)\", value * node.alloc)` over the whole string"
- "'+15 Ward Per Second Per 15 Intelligence' parses to PerStat Int div=15"
- "'+15 Ward Per Second Per 75 Intelligence' (bugged form) parses to div=75"

### `with-attribute-threshold`

**Spec:** `spec/System/TestWithAttributeThreshold_spec.lua`
- "'+24 Ward per Second with 60 Intelligence' → StatThreshold Int 60"
- "works for abbreviated attribute names too ('with 30 Str')"

### `additional-flavor-strip`

**Spec:** `spec/System/TestWithAttributeThreshold_spec.lua`
- "'+24 Additional Ward per Second with 60 Intelligence' parses (alias strips 'Additional')"

### `boneclamor-barbute-ward-per-uncapped-necrotic-res`

**Spec:** `spec/System/TestBoneclamorBarbute_spec.lua`
- "'1 Ward per Second per 3% uncapped Necrotic Resistance' parses cleanly"
- "'2 Ward per Second per 3% uncapped Necrotic Resistance' scales linearly"

### `skills-tab-buff-toggle-config-sync`

**Spec:** `spec/System/TestSkillsTabBuffToggleConfigSync_spec.lua`
- "every LE_WHILE_ACTIVE_BUFF_BY_TREE_ID entry has a matching condition<X> ConfigOptions check"
- "SkillsTab.lua buff toggle reads LE_WHILE_ACTIVE_BUFF_BY_TREE_ID and writes configTab.input"

### `while-active-buff-tree-id-map`

| Site | File | Role |
|------|------|------|
| registry | `src/Data/Global.lua` (`LE_WHILE_ACTIVE_BUFF_BY_TREE_ID`) | Single source of truth: treeId → Condition flag name |
| consumer (calc gate) | `src/Modules/CalcSetup.lua` (~L1668, `whileActiveBuffByTreeId`) | Reads the map to gate buff-tree contributions on `Condition:Have<X>` in addition to `sg.enabled` |
| consumer (UI toggle) | `src/Classes/SkillsTab.lua` (~L1769) | Reads the same map so the buff toggle syncs with ConfigTab's `condition<X>` checkbox |

**Spec:** `spec/System/TestEterrasBlessingBuffGating_spec.lua` and
`spec/System/TestSkillsTabBuffToggleConfigSync_spec.lua` both read the
registry directly, so removing or renaming an entry breaks them.

**Establishing commit:** `c75a34a34 feat(ui): sync SkillsTab buff/form
toggle with ConfigTab condition checkbox` (extracted the inline list
in CalcSetup.lua to the shared `Data/Global.lua` registry so SkillsTab
could read it without forking).

### `properties-loader-init`

`src/Data/Properties/Loader.lua` exposes the LE `PropertyList`
ScriptableObject (extracted from `resources.assets` via
TypeTreeGeneratorAPI) to runtime Lua, so `itemLib.applyRangeStrict`
callers can pick the correct rounding (Hundredth / Integer / Tenth /
Thousandth) per stat without re-encoding the heuristic.

The contract is initialization ordering: `Properties.load(ver)` must
be called before any access to `Properties.byName` / `Properties.bySP`.
The loader caches per-version — repeat `load()` with the same version
is a no-op; with a different version it overwrites both maps. Tests
that exercise the rounding path must call `load()` in `before_each`
(or once in `setup`) or they will silently read empty tables and fall

| Site | File | What it does |
|---|---|---|
| loader  | `src/Data/Properties/Loader.lua` (~line 21, marker on `Properties.load`) | Caches parsed JSON per version into `byName` / `bySP`; safe to call repeatedly with the same version |
| consumer | `src/Modules/ItemTools.lua` `applyRangeStrict` | Reads `Properties.byName[propName].roundingForAdded` to pick the rounding mode for vshDm |

**Spec:** `spec/System/TestPropertiesLoader_spec.lua`
- "loads property_list_1_4.json (110 entries)"
- "normalizes '1.4' and '1_4' to the same version"
- "'Physical Resistance' (SP=64) is Hundredth-ADDED"
- "bySP lookup matches byName lookup"
- "roundingForName / roundingForSP defaults to 0 for unknown stats"

**Establishing commit:** `79b1ee706` — _feat(properties): add runtime
loader for PropertyList SP/rounding lookup_

### `ailment-dps-steady-state-formula`

LEB models damaging ailments as steady-state DPS rather than per-tick
simulation. Three interlocking invariants must hold together; breaking any
one of them silently shifts every ailment DPS by a `durationMult` factor.

Verbatim source quote (`LE_datamining/extracted/dot_channel_formulas.md §3`,
referring to `Ailment.baseDamage` at offset `+0x88`):

> "Damage represents the total damage dealt over the duration"

And §4 on `Ailment.increasedDurationIncreasesDamage()` (RVA `0x21E0AD0`):

> "longer duration also means more total damage (i.e. the per-second damage

| Site | File | What it does |
|---|---|---|
| ailment DPS | `src/Modules/CalcOffence.lua` (~line 1795) | Computes per-stack damage, per-stack DPS, steady-state stacks, and clamped total DPS |
| cap constant | `src/Modules/Data.lua` (~line 105) | `DotDpsCap = (2^31 - 1) / 60` (game's int32 damage tick over 1 minute) |

**Spec:** `spec/System/TestAilmentDPSSteadyState_spec.lua`
- "CalcOffence.lua carries the inline regression-guard marker"
- "per-stack DPS divides by BASE duration (rate-preserved invariant)"
- "steady-state stack count uses applicationsPerSec * effDuration"
- "total DPS is clamped at data.misc.DotDpsCap"
- "dpsPerStack snapshot precedes stack-count derivation"

**Establishing commit:** (this commit)

### minion-modifier-type-narrowing

**Invariant:** When the parser builds a `MinionModifier` LIST entry from a
modifier-line carrying `misc.addToMinion`, it forwards
`misc.addToMinionType` and `misc.addToMinionTypes` onto the value table
as `type` / `minionTypes` so the dispatch gate in
`CalcPerform.lua` (`minion-modifier-multi-type-gate`, reads
`value.type` and `value.minionTypes`) can narrow application to a
specific `env.minion.type`. Without this forwarding any `addToMinion`
modifier silently applies to every minion regardless of type.

**Files:**
- `src/Modules/ModParser.lua` (assembly path for `misc.addToMinion`)
- `spec/System/TestMinionModifierTypeNarrowing_spec.lua`

**Establishing commit:** (this commit)

### shadow-skills-minion-scope

**Invariant:** The "for skills used by Shadows" phrase routes through
`addToMinion = true, addToMinionTypes = { "ShadowClone" }`, NOT the
older no-op `tag = { type = "Scope", scope = "minion" }` placeholder.
ModCache entries for the 38 known stat lines have been regenerated to
`MinionModifier LIST` with `minionTypes={[1]="ShadowClone"}`, with the
inner mod (`Damage` INC or `CritChance` BASE) preserved verbatim from
the previous shape.

**Files:**
- `src/Modules/ModParser.lua` (`modTagList["for skills used by shadows"]`)
- `src/Data/ModCache.lua` (38 affix entries regenerated)
- `spec/System/TestShadowMinionScope_spec.lua`

**Establishing commit:** (this commit)

### shadow-damage-minion-scope

**Invariant:** "Shadow Damage" parses as
`{ "Damage", addToMinion = true, addToMinionTypes = { "ShadowClone" } }`
and emits `MinionModifier LIST` with `minionTypes={"ShadowClone"}`. The
previous placeholder `Condition:ShadowDamageScope` (no consumer
anywhere) is removed from both parser and ModCache; the
`shadow-suffix-family-c6d` guard's older form is superseded by this
entry.

**Files:**
- `src/Modules/ModParser.lua` (`modNameList["shadow damage"]`)
- `src/Data/ModCache.lua` (2 affix entries regenerated)
- `spec/System/TestShadowMinionScope_spec.lua`

**Establishing commit:** (this commit)

### condition-tag-mult

**Invariant:** The `Condition` tag handler honours an optional
`tag.mult` field, mirroring the long-standing StatThreshold mult path
(~L520). Truth table:
- match=true,  mult unset -> pass value through (legacy)
- match=true,  mult set   -> `value = value * tag.mult`
- match=false, mult unset -> `return nil` (full gate, legacy)
- match=false, mult set   -> pass value through (no gate)

**Files:**
- `src/Classes/ModStore.lua` (Condition tag branch ~L590)
- `spec/System/TestConditionTagMult_spec.lua`

**Establishing commit:** (this commit)

### doubled-for-shadow-attack

**Invariant:** The trailing clause ", doubled for shadow attack"
emits `Condition{var="ShadowAttack", mult=2}`. The lone ModCache
entry "+25% Bleed Chance, Doubled for Shadow Attack" carries that
tag shape and empty residue (the trailing clause is fully consumed,
not left as `" , Doubled "` junk).

**Files:**
- `src/Modules/ModParser.lua` (`modTagList[", doubled for shadow attack"]`)
- `src/Data/ModCache.lua` (1 affix entry rewired)
- `spec/System/TestConditionTagMult_spec.lua`

**Establishing commit:** (this commit)

### doubled-with-bow

**Invariant:** The trailing clause ", doubled with bow" emits
`Condition{var="UsingBow", mult=2}`. The lone ModCache entry
"+34# Armor Shred Chance for Shadow Attack, Doubled with Bow" keeps
its base Condition{ShadowAttack} gate (entry [1]) and adds the
Bow-mult Condition tag (entry [2]={mult=2,...,var="UsingBow"}); the
residue collapses from `"#  , Doubled  "` to `"#  "`.

**Files:**
- `src/Modules/ModParser.lua` (`modTagList[", doubled with bow"]`)
- `src/Data/ModCache.lua` (1 affix entry rewired)
- `spec/System/TestConditionTagMult_spec.lua`

**Establishing commit:** (this commit)

### condition-shadow-attack-consumer

**Invariant:** `CalcOffence.offence` assigns
`skillCfg.skillCond["ShadowAttack"]` to `true` whenever the active
skill's `activeEffect.grantedEffect.name` is one of an allowlist of
player-castable Shadow Attack skills, and `false` otherwise. The
allowlist is `{"Shadow Cascade", "Shadow Daggers", "Shadow Rend"}`,
sourced from datamined `ability_keyed_array.json` and
`localized_master.json` in the LE_datamining workspace. Skills that
the ShadowClone minion uses (Shurikens, Arrowstorm) are deliberately
NOT included because their player-cast form is not a Shadow Attack
from the player's perspective; the minion's casts go through
`env.minion` scope and bypass this skillCfg. Without this wiring,
every affix carrying `tag={type="Condition", var="ShadowAttack"}`
(emitted by `modTagList["for shadow attack"]` and by the F4 trailing
clause `", doubled for shadow attack"`) silently full-gates to zero
on the player.

**Files:**
- `src/Modules/CalcOffence.lua` (per-skill init, after `SkillIsFocused`)
- `spec/System/TestConditionShadowAttackConsumer_spec.lua`

**Establishing commit:** (this commit)

### health-regen-applies-to-ward-plus-prefix

**Invariant:** Both anchored parser handlers MUST start with
`^%+?(%d+)` so the affix form (with a leading `+`) and the
Runemaster Sanguine Runestones form (without `+`) both resolve to
`LifeRegenAppliesToWard` BASE. Without the `%+?` the `+`-prefixed
input falls through to the generic `+N% health regen` handler,
silently emits `LifeRegen` INC (wrong stat) and strands `also
applies to Ward` in the parser residue, so the
`LifeRegenAppliesToWard` BASE that `CalcDefence.lua:641, :796`
consumes never fires. The ModCache entries for the 5 known affix
tiers must carry the `LifeRegenAppliesToWard BASE` shape with
`nil` residue.

**Files:**
- `src/Modules/ModParser.lua` (two anchored handlers for "(N)% [of] health regen also applies to ward")
- `src/Data/ModCache.lua` (5 entries: +2/+3/+4/+6/+9%)
- `spec/System/TestHealthRegenAppliesToWardPlusPrefix_spec.lua`

**Establishing commit:** (this commit)

### unique-hideintooltip-letools-artifact

**Invariant:** When a game-side unique mod has `hideInTooltip=true`
AND `descriptors.json` has no entry for its
`"<property>,<tags>,<specialTag>,<extraTag>"` key, the LEB string
for that mod is a LETools fallback-formatter artifact (typically
prefixed with `+N` where N is the raw `value` field). Two sub-cases,
both locked here:

**Files:**
- `src/Data/Uniques/uniques.json` / `uniques_1_2.json` / `uniques_1_3.json` / `uniques_1_4.json`
- `src/Data/ModCache.lua` (~L1655 wolves area)
- `spec/System/TestUniqueHideInTooltipLETools_spec.lua`

**Establishing commit:** (this commit)

### mirage-count-consumer

**Invariant:** The stat `MirageCount` (parser anchor:
`mirages-created-by-lethal-mirage` -- `"+N Mirages created by
Lethal Mirage"` idol affix family, ModItem.json statOrderKey=537,
tiers 0..7 emit +1/+2/+3) MUST be summed via
`skillModList:Sum("BASE", skillCfg, "MirageCount")` into
`output.MirageCount`, and CalcSections MUST have a
`haveOutput="MirageCount"` row formatting as an integer. Before
this wiring the value was parsed but never consumed -- silent
failure mirroring F1 (MaxShadows) and F10
(ChanceToApplyShadowDaggerOnHit). The `SkillName="Lethal Mirage"`
tag on the underlying mod ensures the count only resolves when
Lethal Mirage is the active skill.

**Files:**
- `src/Modules/CalcOffence.lua` (~L467 after `ActiveMineLimit`)
- `src/Modules/CalcSections.lua` (~L188 after `Active Trap Limit`)
- `spec/System/TestMirageCountConsumer_spec.lua`

**Establishing commit:** (this commit)

### cooldown-recovered-on-hit-consumer

**Invariant:** The two unique-mod families "+N% of Lethal Mirage's
remaining cooldown recovered on Melee Hit (up to M times)"
(Black Blade of Chaos Mod[4]) and "+N% chance to recover 8% of
Aerial Assault's remaining cooldown on Throwing Hit (up to M
times)" (Razorfall Mod[4]) MUST emit a paired BASE mod set:
`CooldownRecoveryOnHit` (percent recovered per qualifying hit;
for Razorfall = chance * 8 / 100 effective average) and
`CooldownRecoveryOnHitMaxPerCast` (the per-cast cap, resets when
the named skill is used -- see game `CharacterMutator`
`SinceLast<Skill>Use` counters in `dump.cs` L96712-96719). Both
mods carry a `SkillName=<skill>` tag so they only resolve when
that ability is the active skill (Option A: SkillName reused as
"affects-this-cooldown" target, paralleling F11
`MirageCount`/F10 `ChanceToApplyShadowDaggerOnHit` patterns).
CalcOffence MUST aggregate via `skillModList:Sum("BASE", skillCfg,
...)` into `output.CooldownRecoveryOnHit` and
`output.CooldownRecoveryOnHitMaxPerCast`, and CalcSections MUST
have two `haveOutput=...` rows surfacing them. Without this
wiring the values were parsed-but-unconsumed (silent failure
mirroring F1/F10/F11). Per-cast accumulator semantics are
visible-only at v1 -- combat-loop attribution is deferred.

**Files:**
- `src/Modules/ModParser.lua` (two anchored handlers after `mirages-created-by-lethal-mirage`)
- `src/Modules/CalcOffence.lua` (after F10 ChanceToApplyShadowDaggerOnHit)
- `src/Modules/CalcSections.lua` (after Shadow Dagger Apply Chance row)
- `src/Data/ModCache.lua` (Lethal Mirage 15%/12-times anchor + Aerial Assault 17%/3-times anchor)
- `spec/System/TestCooldownRecoveredOnHitConsumer_spec.lua`

**Establishing commit:** (this commit)

### mod6-v2-combat-loop

**Invariant:** The v1 pair (`CooldownRecoveryOnHit`,
`CooldownRecoveryOnHitMaxPerCast`) emitted by the
`cooldown-recovered-on-hit-consumer` parser anchors (Lethal Mirage
15%/12-times from Black Blade of Chaos; Aerial Assault 1.36%/3-times
chance-folded from Razorfall) MUST fold into an effective skill
cooldown using the closed-form equilibrium

    effectiveCD = baseCD * (1 - pct/100)^cap

published as `output.EffectiveCooldownFromOnHit` AND back-propagated
into `output.Cooldown` so the downstream Speed clamp
(`output.Speed = min(Speed, 1/output.Cooldown * Repeats)`) picks up
the recovery. Removing the fold-in regresses Lethal Mirage / Aerial
Assault DPS to the v1 surface-only state where the chase mod
appears in stat rows but has no impact on cast/hit frequency.

**Game-file authority (dump.cs il2cpp re-extraction):**
- L96712 `chanceToRecover8pOfRemainingAerialAssaultCooldownOnThrowingHit` (float, chance)
- L96714 `maxTimesToRecover12pOfRemainingAerialAssaultCooldownOnThrowingHit = 3` (const cap)
- L96716 `lethalMirageRemainingCooldownRecoveredOnMeleeHitUpTo12TimesPerUse` (float, pct)
- L96718 `lethalMirageMeleeHitCooldownRecoveryEventsSinceLastUse` (int counter; resets per cast)
- The per-skill `SinceLast<Skill>Use` counters are int event tallies, not float timers --
  the closed form approximates the per-cast reset semantics without a time-axis simulation.

**LEB strategy:** LEB is a PoB-flow static DPS engine with no
combat-loop / time-axis simulation. We approximate the steady-state
fixed point of the recovery loop assuming the cap is reached every
cast -- this is the affix's design intent (otherwise the cap would
be uninteresting) and a defensible best-case upper bound. The
closed form is the analytic limit of a per-tick simulation as the
hit rate goes to infinity.

**Why not Option B (per-tick simulation):** would require a new
combat-loop module, time-axis events, and convergence detection --
~10x the LoC of the closed form, for a 2-skill affix family.
Deferred indefinitely; if a future affix needs sub-equilibrium
behaviour, revisit.

**Files:**
- `src/Modules/CalcOffence.lua` (effective-cooldown site, immediately after `output.Cooldown = cooldown` at L1223)
- `src/Modules/CalcSections.lua` (section site, "Effective Cooldown (CD-on-Hit)" row, after Max CD-Recovery Hits)
- `spec/System/TestCooldownRecoveryOnHitV2_spec.lua`

**Establishing commit:** (this commit)

### silent-failure-affix-sweep

**Invariant:** The Phase 1 enumeration baseline of "silent failure"
ModCache rows MUST remain frozen until a category-specific Phase 3 PR
deliberately moves it. A "silent failure" row is one of the form
`c["<affix-string>"]={{},"<non-empty residue>"}` in
`src/Data/ModCache.lua` -- ModParser returned an empty modList yet
emitted residue text, so the affix was swallowed without surfacing
into calculations and without raising an error.

**Baseline (Phase 3a, this commit):**
- total ModCache rows           : 16,749
- parsed (non-empty modList)    : 13,591  (81.15%)
- neutralized (empty residue)   :  1,082  (was 367; +715 from Phase 3a)
- silent failure (residue text) :  2,076  (was 2,791; -715 from Phase 3a)
- combined recognition rate     : 87.61%  (parsed + neutralized / total)
- refined category split (dm-aware, post-3a):
    a1-pure-flavor   :   0   (bucket emptied by Phase 3a bulk neutralization)
    a2-numeric-real  : 634   (real numeric mods masquerading as flavor; DO NOT neutralize)
    b-dm-numeric     : 135   (dm-confirmed real LE-1.4 numeric, parser regex missing)
    b-parser-gap     : 466   (residue suggests numeric mod, no dm match)
    c-dm-infra       : 239   (dm-confirmed real LE-1.4 trigger/event, infra missing)
    c-infra-gap      : 602   (residue suggests trigger/event, no dm match)
- datamining cross-reference (ModItem_1_4.json + 3 siblings):
    moditem lines scanned    : 9,525
    moditem unique norms     : 986
    silent_failure matched   : 374 / 2,076 (18.0%)
    dm_gap (never reached LEB): 283  (affixes LEB has never attempted to parse)

**Why a guard:** ModParser regex regressions historically grow the
silent-failure pool silently (no error, no test failure, no LETools
diff on builds that don't carry the affix). Locking the baseline
turns any silent regrowth into a deliberate `busted` failure that
forces investigation. Conversely, when Phase 3 PRs wire / neutralise
real affixes, the count shrinks and the spec must be updated in the
same commit -- this becomes the audit trail for the sweep.

**Workflow when the count changes:**
1. Run `python spec/tools/enumerate_silent_failures.py`.
2. Inspect the diff on `spec/Data/silent-failure-affixes.json`.
3. Update the `EXPECTED_*` constants in
   `spec/System/TestSilentFailureSweep_spec.lua` and the baseline
   numbers in this section in the SAME commit as the parser change.
4. If the change is a regression, revert -- do NOT slap the baseline.

**Phase plan:** see `TODO.md` "Category B silent-failure affix sweep".
- Phase 1 (commit `ce0b5cdab`) -- enumeration + heuristic classification.
- Phase 2 (commit `da3fdc952`) -- ModItem cross-reference; dm-aware refined
  classifier; safe-to-neutralize bucket (a1-pure-flavor) isolated from
  a2-numeric-real masquerade.
- Phase 3a (this commit) -- bulk neutralize 715 a1-pure-flavor rows via
  `--emit-neutralization` mode; recognition 83.34% -> 87.61%.
- Phase 3b -- spawn-task per b-dm-numeric / c-dm-infra family (374 dm-matched).
- Phase 3c -- parser-gap / infra-gap unmatched (1,068) require build-source
  research before action.

**Files:**
- `spec/tools/enumerate_silent_failures.py` (carries `@leb-tooling: enumerate-silent-failures` + `@leb-regression-guard: silent-failure-affix-sweep (tool site)`)
- `spec/Data/silent-failure-affixes.json` (committed snapshot)
- `spec/System/TestSilentFailureSweep_spec.lua`

**Establishing commit:** (this commit)

### chance-to-apply-shadow-dagger-on-hit-consumer

**Invariant:** The stat `ChanceToApplyShadowDaggerOnHit` (parser:
`ModParser.lua` L399 `["chance to apply a shadow dagger on hit"]
= "ChanceToApplyShadowDaggerOnHit"`, mapped from the unique
suffix `"50% Chance to apply a Shadow Dagger on Hit with Lethal
Mirage"` and similar Lethal Mirage idol affixes) MUST be summed
via `skillModList:Sum("BASE", skillCfg, ...)` into
`output.ChanceToApplyShadowDaggerOnHit`, and CalcSections MUST
have a `haveOutput="ChanceToApplyShadowDaggerOnHit"` row
formatting as percent. Before this wiring the value was parsed
but never consumed -- silent failure mirroring F1. The
`SkillName="Lethal Mirage"` tag on the underlying mod ensures
the percentage only resolves when Lethal Mirage is the active
skill.

**Files:**
- `src/Modules/CalcOffence.lua` (~L466 after `ActiveMineLimit`)
- `src/Modules/CalcSections.lua` (~L188 after `Active Trap Limit`)
- `spec/System/TestChanceToApplyShadowDaggerOnHitConsumer_spec.lua`

**Establishing commit:** (this commit)

### condition-on-shadow-create-consume-config

**Invariant:** The Bladedancer Shadow event-time conditions
`OnShadowCreate` and `OnShadowConsume` are emitted by the parser
on the affix families "+N Ward Gained on Shadow Creation" (9+
tiers), "+N Health Gained on Shadow Creation" (8 tiers), and
"+N% Chance to gain a stack of Dusk Shroud when you consume a
Shadow" (multiple tiers). All ModCache entries already carry the
correct `Condition:OnShadow{Create,Consume}` tags. The
calc-consumer side is the two Config-tab `check` toggles in
`ConfigOptions.lua`: `conditionOnShadowCreate` (with
`ifCond="OnShadowCreate"`) and `conditionOnShadowConsume` (with
`ifCond="OnShadowConsume"`), each setting
`Condition:OnShadow{Create,Consume}` FLAG true and Combat-scoped
so they never leak outside the combat snapshot. Without these
toggles the tagged mods can never resolve, silently dropping
their Ward/Health/Dusk Shroud contributions from the player
breakdown.

**Files:**
- `src/Modules/ConfigOptions.lua` (two `check` toggles after `multiplierActiveShadow`)
- `spec/System/TestConditionOnShadowCreateConsumeConfig_spec.lua`

**Establishing commit:** (this commit)

### mirages-created-by-lethal-mirage

**Invariant:** The idol-affix line `+N Mirages created by Lethal
Mirage` (real affix: `src/Data/ModItem.json` `statOrderKey=537`,
tiers 0..7 emit +1/+2/+3, paired with a Mana Efficiency line)
MUST parse via the anchored handler
`^%+?(%d+) mirages? created by lethal mirage$` to a
`MirageCount` BASE mod tagged with `SkillName="Lethal Mirage"`.
Without this anchor the line fell through to nothing -- empty
`modList`, empty residue -- silently dropping the mirage-count
half of the affix. `MirageCount` is the calc-consumer target
that future F11 wiring (in `src/Modules/CalcMirages.lua`) will
read; the parser layer is locked here so F11 becomes a pure
calc-layer addition. The 3 known ModCache tiers must carry the
canonical `MirageCount BASE` shape with `nil` residue.

**Files:**
- `src/Modules/ModParser.lua` (anchored handler near end of `specialModList`)
- `src/Data/ModCache.lua` (3 entries: +1/+2/+3)
- `spec/System/TestMiragesCreatedByLethalMirage_spec.lua`

**Establishing commit:** (this commit)

### tabi-of-dusk-and-dawn-flags

**Invariant:** Tabi of Dusk and Dawn (uniqueID=458, boots; see
`src/Data/Uniques/uniques_1_4.json` L9266 and `uniques.json` L10380)
carries two paired Shadow-Rend-specific lines:
- `Shadow Rend no longer moves you`
- `Shadow Rend always manifests a melee shadow in front of you and a
  bow shadow behind you`

**Files:**
- `src/Modules/ModParser.lua` (two anchored `flag(...)` handlers in
  `specialModList`, after `cooldown-recovered-on-hit-consumer`)
- `src/Data/ModCache.lua` (2 FLAG-mod entries tagged
  `SkillName="Shadow Rend"`)
- `src/Modules/CalcOffence.lua` (dual-cast consumer at the Shadow Rend
  ShadowAttack condition block)
- `spec/System/TestTabiOfDuskAndDawnFlags_spec.lua`

**Establishing commit:** (this commit)

### orb-weavers-fang-descriptive

**Invariant:** Orb Weaver's Fang (uniqueID=405, sword; see
`src/Data/Uniques/uniques.json` L9088 and the 1_2/1_3/1_4 variants)
carries a single-source conditional self-mult line:

**Files:**
- `src/Modules/ModParser.lua` (anchored handler at end of
  `specialModList`, after `tabi-of-dusk-and-dawn-flags`)
- `src/Data/ModCache.lua` (1 neutralized entry: `{{}, ""}`)
- `spec/System/TestOrbWeaversFangDescriptive_spec.lua`

**Establishing commit:** (this commit)

### kuzons-fury-reforged-burning-dagger-chance

**Invariant:** Kuzon's Fury Reforged (affix="Kuzon's Fury Reforged",
statOrderKey=961, 8 tiers, specialAffixType=3,
`src/Data/ModItem.json` L67773-L67890) carries:

**Files:**
- `src/Modules/ModParser.lua` (specialModList anchors for tiers 0..6
  and the tier-7 outlier; modTagList entry kept inline -- the
  trailing clause is baked into the full-line anchor)
- `src/Data/ModCache.lua` (8 BurningDaggerChanceOnMeleeFire BASE
  entries + 1 deferred-empty tier-7 entry)
- `src/Modules/CalcOffence.lua` (dancingStrikesSkills allowlist +
  `output.BurningDaggerChanceOnMeleeFire` sum)
- `src/Modules/CalcSections.lua` (`Burning Dagger Throw Chance` row)
- `spec/System/TestKuzonsFuryReforged_spec.lua`

**Establishing commit:** (this commit)

### proc-rate-limit-metadata-v1

**Invariant:** The static localization suffix
`(up to N times per M seconds)` on chance-to-proc affixes is
surfaced as passive `RateLimit` metadata, NOT as an equilibrium
effective-procs/sec stat. LEB follows the game files: the game
exposes no planner-visible rate-capped chance stat -- the cap is
enforced at runtime only via `ProcTimeTracker`. LEB therefore
stores `(limit, interval)` as metadata and displays it
informationally, without fabricating a derived stat the game
itself does not surface.

**Files:**
- `src/Modules/ModParser.lua` (Burning Dagger full-line anchor:
  emits `RateLimit{limit=4, interval=1, var="BurningDaggerOnMeleeFire"}`
  alongside the `Condition{DancingStrikes, mult=2}` tag)
- `src/Data/ModCache.lua` (8 BurningDaggerChanceOnMeleeFire BASE
  entries carry the RateLimit metadata tag)
- `src/Classes/ModStore.lua` (NO handler for `RateLimit` -- the tag
  is pure metadata and must pass through `EvalMod` unchanged;
  guard locks against accidental handler addition AND against
  conflation with the existing `Limit` tag at L560 whose semantics
  are `value = m_min(value, tag.limit)`)
- `src/Modules/CalcOffence.lua` (harvester: reads tag.limit /
  tag.interval into `output.BurningDaggerChanceOnMeleeFire_RateLimit`
  and `_RateInterval` scalars)
- `src/Modules/CalcSections.lua` (informational `Burning Dagger
  Rate Limit` row, "N per M sec" format)
- `spec/System/TestProcRateLimitMetadata_spec.lua`

**Establishing commit:** (this commit)

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

## JSON-comment-incompatible guards


Some fixes live in JSON data files (`src/Data/*.json`) which cannot carry
inline `@leb-regression-guard:<id>` comments. The 3-layer contract
(inline marker + spec + this index) collapses to 2 layers for these guards.
To keep the contract enforceable use this template:

1. **Index entry**: prepend a callout block stating
   `> **Type: JSON-comment-incompatible.**` and naming the JSON file(s).
2. **Spec layer**: place the spec under `spec/System/`, with the
   `@leb-regression-guard:<id>` marker as its first comment line. The spec
   MUST load the JSON and assert specific keys / values, not just shape.
3. **Audit layer (recommended)**: a reproducible script under `.tmp/` or
   `scripts/` that re-derives the expected values from canonical sources
   (e.g. the LE_datamining workspace). Reference it from the index entry
   so a future maintainer can re-run the audit if canonical data shifts.
4. **Commit-message convention**: any commit that mass-edits the protected
   JSON file MUST mention the guard id in its body, e.g.
   `Refs: @leb-regression-guard:body_armor-banker-rounding`. This is the
   only way the marker travels with the change.

Existing JSON-comment-incompatible guards:
- `body_armor-banker-rounding` (`src/Data/ModItem_1_4.json`)
- `slot-banker-rounding` (`src/Data/ModItem_1_4.json`)
- `corrupted-sealed-allres-round-half-up` (`src/Data/ModItem.json`, `src/Data/ModItem_1_4.json`)

### `idol-affix-source-and-formula`

Idol affix entries live in `ModIdol_<ver>.json`, not `ModItem`. Pre-fix,
`Item.lua`'s affix lookup `data.itemMods[self.base.type]` fell through to
`data.itemMods.Item` (ModItem) for idol items, because no `data.itemMods`
entries existed for the idol type names. Shared affix IDs differ between the
two files (e.g. affix `1070_0` All Resistances: ModItem raw `+1%`, ModIdol
raw `+5%`). The ModItem entry was a legacy duplicate previously protected by
the `corrupted-sealed-allres-round-half-up` workaround.

Pair-fix: for **sealed/corrupted-kind** affixes on idol bases, `modScalar`
must NOT subtract `standardAffixEffectModifier`. The formula is
`displayed = raw × (1 + base.affixEffectModifier)` floored.

Detection note: ModIdol entries do **not** carry `specialAffixType=6` the

| Site | File | What it does |
|---|---|---|
| Data registration | `src/Modules/Data.lua` (~line 685) | Maps every idol type name to `verIdolMods.flat` so `data.itemMods[type]` resolves to idol affix data |
| modScalar computation | `src/Classes/Item.lua` (~line 1347) | When `isIdolBase and affix.kind in {corrupted, sealed}`, skip sAEM subtraction |
| modScalar Omen bypass | `src/Classes/Item.lua` (~line 1449) | Inside the Omen Idol `affixEffectModifier` bypass (`modScalar = 1`), the inner re-division by `(1 + sAEM)` is also gated on `not skipSaem`. Without this gate, sealed/corrupted-kind affixes on Omen Idols balloon by `1 / (1+sAEM)` (e.g. affix 1070_0 sAEM=-0.83 → 5.882× → +29% instead of +5%) |

**Spec:** `spec/System/TestIdolAffixSourceAndFormula_spec.lua`

**Game-data evidence (2026-05-12, online trade screenshots):** Affix
`1070_0` "All Resistances for you and your Minions" (ModIdol raw `+5%`,
sAEM `-0.83`):

| Base | aem | Predicted (5 × (1+aem) floor) | Observed in-game |
|---|---|---|---|
| Adorned | -0.05 | 4 (5×0.95=4.75 floor) | +4% |
| Huge | 0 | 5 | +5% |
| Grand/Large | -0.33 | 3 (5×0.67=3.35 floor) | +3% |
| Omen Idol (bypass) | n/a | 5 | +5% |

Throne of Ambition (Adorned Silver Idol unique) confirmed `+4%`.

**Affix scope:** sealed-corrupted-only. Non-sealed idol affix raw values
(post-routing-fix) have not been verified against in-game; their existing
`modScalar = (1 + base.aem) - sAEM` formula is preserved.

**Cross-build triangulation (2026-05-13):** Snapshot regen across all 71
builds touching idol sealed/corrupted affixes confirms zero regressions
outside this formula's scope. Verification breakdown:
- 4 manual deep-dives (BgRrekzd, BjqdmXnO, QDxZjPX8, o3Zl6gyy) — every
  changed stat traced to `raw × (1 + aem)` floor on a specific corrupted
  idol affix + downstream cascade.
- 67 bulk pattern-match builds — all significant diffs (resist ±1..±10,
  Minion all-res ±1..±9, CritExtraDamageReduction, FrenzyEffect/HasteEffect
  ±1) fit the documented formula. Largest case QDxZPWM9 (84 stats, Cold
  TakenHit -22%) is a multi-idol "All Resistances + Minion" stack pulling
  Minion all-res 2→11; postfix direction (resist up, TakenHit down) is
  correct.

**Establishing commit:** 47ae8743e (Omen Idol bypass row added 2026-05-17 in cherry-picked follow-up; see `src/Classes/Item.lua` ~L1449 `@leb-regression-guard:idol-affix-source-and-formula`).

### `slot-override-post-saem`

`slotOverrides` ranges in `ModItem_1_4.json` are LE-displayed values that have
already had BOTH the base `affixEffectModifier` AND the per-affix
`standardAffixEffectModifier` (sealed penalty) baked in. When the override is
selected, `Item.lua`'s `modScalar` must be 1 — no further scaling.

The earlier code zeroed the base aem but still subtracted
`standardAffixEffectModifier`, double-applying the sealed penalty (e.g. affix
1014_4 body_armor Mana shown as 47 × 0.83 = 39 instead of LE's 47).

| Site | File | What it does |
|---|---|---|
| modScalar computation | `src/Classes/Item.lua` (~line 1351) | When `usingSlotOverride`, set `modScalar = 1` unconditionally (do NOT subtract `standardAffixEffectModifier`) |

**Spec:** `spec/System/TestSlotOverridePostSaem_spec.lua`
- "usingSlotOverride branch does not subtract standardAffixEffectModifier"
- "guard comment block is present"

**Establishing commit:** a19b15126

### `idol-affix-tier-fallback`

Paired-with: `idol-affix-source-and-formula`.

`ModIdol_<ver>.json` currently carries **only tier 0** (`_0`) entries for
every affix (469 affixes, all T0). Idols routinely roll higher tiers
(e.g. enchanted `905_4` Mana Regen, suffix `901_3` Frostbite Chance).
Once `idol-affix-source-and-formula` rerouted idol affix lookups from
ModItem to `verIdolMods.flat`, every tier-N lookup missed and the affix
silently contributed zero.

Fix: chain `flat` to `verMods` via `setmetatable(flat, { __index = verMods })`
so a miss falls back to the ModItem entry (which carries full T0..T7
raw scaling). T0 corrections present in ModIdol (e.g. `1070_0` All

| Site | File | What it does |
|---|---|---|
| Fallback chain | `src/Modules/Data.lua` (~line 690) | `setmetatable(flat, { __index = verMods })` before publishing `verIdolMods.flat` |

**Spec:** `spec/System/TestIdolAffixTierFallback_spec.lua`

**Establishing commit:** (this commit)

### `crit-chance-for-skeletons-skeletal-mages`

Acolyte idol/ModItem affixes "+N% Critical Strike Chance for Skeletons"
and "+N% Critical Strike Chance for Skeletal Mages" must apply to the
minion family, not to the player's main-skill crit. Before the guard the
bare `CritChance BASE` mod leaked the +N% onto the PLAYER crit while
leaving residue " for Skeletons " / " for Skeletal Mages " in the
ModCache 3rd slot — a classic silent-failure parser fallthrough.

The "for Skeletons" line covers the full SummonedSkeleton family
(Warrior + Archer + Harvester + Vanguard + Rogue, per
`src/Data/minions.json`); the "for Skeletal Mages" line covers only
`SummonedSkeletonMage`.

| Site | File | What it does |
|---|---|---|
| Parser | `src/Modules/ModParser.lua` (~line 999) | Two `specialModList` entries emit `MinionModifier` LIST with `minionTypes` array (Skeletons) or single `type` (Mages) |
| Dispatch (primary) | `src/Modules/CalcPerform.lua` (~line 506) | Walks MinionModifier entries; matches when `value.type==env.minion.type` OR `value.minionTypes` array contains `env.minion.type` |
| Dispatch (buff mirror) | `src/Modules/CalcPerform.lua` (~line 1182) | Same logic at the buff-loop site so skill-buff-routed mods don't fall through |
| ModCache | `src/Data/ModCache.lua` | 24 entries (12 values × 2 lines) carry the MinionModifier wrapper with empty residue |

**Spec:** `spec/System/TestCritChanceForSkeletons_spec.lua`

**Establishing commit:** (this commit)

### `minion-modifier-multi-type-gate`

`MinionModifier` LIST dispatch supports three filter forms — applied to
all minions (no filter), single `value.type`, or `value.minionTypes`
array. Both CalcPerform dispatch sites (primary ~L506 and buff-loop
mirror ~L1182) must implement the same gate; if only the primary site is
updated, mods routed through skill buffs silently fall through.

| Site | File | What it does |
|---|---|---|
| Primary dispatch | `src/Modules/CalcPerform.lua` (~line 506) | `for _, mt in ipairs(value.minionTypes) do` array walk |
| Buff-loop mirror | `src/Modules/CalcPerform.lua` (~line 1182) | Same array walk; spec asserts count ≥ 2 |

**Spec:** `spec/System/TestCritChanceForSkeletons_spec.lua`
- "CalcPerform mirror dispatch site (buff loop) also matches value.minionTypes"

**Establishing commit:** (this commit)

### `crit-for-totems-per-int-and-multi`

Totem-family crit affixes — "+N% Critical Strike Chance for Totems per
Intelligence" and "+N% Critical Strike Multiplier for Totems" — must
apply to totem minions, not to the player's main-skill crit. Before the
guard the bare `CritChance` / `CritMultiplier` BASE mod leaked the +N%
onto the PLAYER crit while leaving residue " for Totems  " /
" for Totems " in the ModCache 3rd slot — silent-failure parser
fallthrough.

The per-Int line carries `actor = "parent"` on its PerStat:Int tag so
the mod scales on the **player's** Intelligence even though it is
dispatched onto `env.minion`, matching the in-game AltText "Scales with
your Intelligence" (Property_Player_175).

| Site | File | What it does |
|---|---|---|
| Parser | `src/Modules/ModParser.lua` (~line 1017) | Two `specialModList` entries emit `MinionModifier` LIST with `minionTypes` = 8-key totem family; per-Int inner mod carries `PerStat:Int actor="parent"` |
| Dispatch | `src/Modules/CalcPerform.lua` (~line 506 + ~line 1182) | Shared with `minion-modifier-multi-type-gate`; walks the `minionTypes` array against `env.minion.type` |
| ModCache | `src/Data/ModCache.lua` | 17 entries (8 per-Int + 9 Multi) carry the MinionModifier wrapper with empty residue |

**Spec:** `spec/System/TestCritForTotems_spec.lua`

**Establishing commit:** (this commit)

### `ward-per-second-and-retention-family`

13 ward-related affix lines — "Ward Per Second" (Charged Reflections,
Instruments of Death, Circle of Sacrifice, Rewarding Craft / Forged
Weapon, Warding Flames / per Firebrand stack, Faith alias, Arcane
Shielding, Holy Symbol), "Ward Retention" (Cloak of Solitude / per
Increased Area, Egg of the Forgotten / per uncapped Cold Resist,
Corrupted Heraldry / on Transform, Conjured Armor / from Increased
Armor), and "Ward Decay Threshold" (Imperishable / per 2% Necrotic
Resist) — must be gated by their referenced condition or multiplier.
Before the guard the parser left the conditional text in slot[2]
residue and emitted bare `WardPerSecond` / `WardRetention` /
`WardDecayThreshold` BASE mods, so the bonus leaked onto the
unconditional stat — silent-failure parser fallthrough.

| Site | File | What it does |
|---|---|---|
| Parser | `src/Modules/ModParser.lua` | 13 `specialModList` patterns + two `modTagList` suffixes ("on transform" / "when you transform") emit tagged inner mods or `MinionModifier` LIST (Forged Weapon → type=`ForgedWeapon`) |
| Config | `src/Modules/ConfigOptions.lua` | New `multiplierFirebrandStack` count config; existing `multiplierActiveSymbols` now also sets `Condition:HaveActiveSymbol` when val ≥ 1 (mirroring `HaveArcaneShield`) |
| Setup | `src/Modules/CalcSetup.lua` | Auto-populate `Multiplier:AreaInc` / `ArmourInc` / `UncappedResistTotal` from sum INC / BASE on AreaOfEffect / Armour / 7 resist stats |
| ModCache | `src/Data/ModCache.lua` | All 13 entries carry the tagged inner mod or `MinionModifier` wrapper with empty residue |
| Site | File | What it does |
|---|---|---|
| Parser | `src/Modules/ModParser.lua` (~L547) | New `modTagList["during profane veil"] = { tag = { type = "Condition", var = "DuringProfaneVeil" } }` (3-word match beats the 2-word SkillName eater) |
| Config | `src/Modules/ConfigOptions.lua` (~L152) | New `conditionDuringProfaneVeil` check toggle mirroring `conditionHaveEterrasBlessing`, emits `Condition:DuringProfaneVeil` FLAG |
| ModCache | `src/Data/ModCache.lua` | Entry regenerated with `Condition:DuringProfaneVeil` tag and empty residue |
| Site | File | What it does |
|---|---|---|
| Parser | `src/Modules/ModParser.lua` (~L549) | New `modTagList["for each curse affecting you"] = { tag = { type = "Multiplier", var = "CurseOnSelf" } }` |
| Config | `src/Modules/ConfigOptions.lua` (~L116) | New `multiplierCurseOnSelf` count toggle with `implyCond = "Cursed"`. Emits `Multiplier:CurseOnSelf` BASE plus `Condition:Cursed` FLAG when val >= 1 |
| ModCache | `src/Data/ModCache.lua` | Entry regenerated with the Multiplier tag and empty residue |

**Spec:** `spec/System/TestWardRegenFamily_spec.lua`
**Spec:** `spec/System/TestWardRegenFamily_spec.lua` (W2 section, 1
test sweeping all 16 entries).
**Spec:** `spec/System/TestWardRegenFamily_spec.lua` (W3 section, 2
tests: parser entry + 10 cache entries).
**Spec:** `spec/System/TestWardRegenFamily_spec.lua` (W4 section, 3
tests: parser entry, ConfigOptions wiring, cache entry).
**Spec:** `spec/System/TestWardRegenFamily_spec.lua` (W5 section, 3
tests: parser entry, ConfigOptions wiring, cache entry).
**Spec:** `spec/System/TestWardRegenFamily_spec.lua` (W6 section, 1
test asserting cache neutralization).

**Establishing commit:** (this commit)
**Establishing commit:** W2 sub-commit
**Establishing commit:** W3 sub-commit
**Establishing commit:** W4 sub-commit
**Establishing commit:** W5 sub-commit
**Establishing commit:** W5+W6 sub-commit

### `ward-one-shot-gain-family`

Companion to `ward-per-second-and-retention-family`. Locks the ~193
ModCache entries that emit `name="Ward",type="BASE"` (one-shot ward gain
on a trigger event: on Cast, on Dodge, on Crit, on Hit, on Rune consumed,
per Stack, at Low Life, etc.) against silent-failure residue. Each wave
(O1, O2, ...) addresses one sub-pattern; entries that share a residue
shape share a wave.

| Site | File | What it does |
|---|---|---|
| ModCache | `src/Data/ModCache.lua` | 10 entries regenerated with empty residue; tag unchanged |

**Spec:** `spec/System/TestWardOneShotGainFamily_spec.lua` (O1 section,
2 tests: count of 10 correctly-shaped entries + no stale residue).
**Spec:** `spec/System/TestWardOneShotGainFamily_spec.lua` (O2 section,
5 tests: 4 sub-pattern shape locks + 1 sweep asserting no stale residue).
**Spec:** `spec/System/TestWardOneShotGainFamily_spec.lua` (O3 section,
3 tests: bare-body zero-residue lock + 8-Overhealing-neutralized lock +
family-wide zero-stale invariant).

**Establishing commit:** O1 sub-commit
**Establishing commit:** O2 sub-commit
**Establishing commit:** O3 sub-commit

### `with-2h-suffix-family`

LEB passive-tree nodes use the colloquial "With 2h" / "With 2h Weapon" /
"With 2h \<Weapon\>" suffix (Sentinel Champion of the Forge / Master of
Arms, Warpath Battlemaster's Blade, Tempest Strike Heorot's Arsenal,
Rogue Expert Duelist). Before this guard the parser had a matcher for
"while wielding a 2 handed \<weapon\>" but no matcher for the colloquial
form — 7 ModCache entries kept the "With 2h" text in slot[2] residue
and applied the bonus to ANY weapon (or any weapon of the named
subtype, for "With 2h Sword"), silently dropping the 2-handed gate.

| Site | File | What it does |
|---|---|---|
| Parser | `src/Modules/ModParser.lua` (~line 806–) | New `modTagList["with 2h"]` and `["with 2h weapon"]` map to `Condition:UsingTwoHandedWeapon`; per-weapon `["with 2h <weapon>"]` inside the `DamageSourceWeapons` loop combines `Using<Weapon>` + `UsingTwoHandedWeapon` (mirrors existing "while wielding a 2 handed \<weapon\>" precedent) |
| ModCache | `src/Data/ModCache.lua` | 7 entries carry the `UsingTwoHandedWeapon` condition (plus subtype condition for `With 2h Sword`) with empty residue |

**Spec:** `spec/System/TestWith2hSuffix_spec.lua`

**Establishing commit:** (this commit)

### `dual-wield-pair-suffix-family`

Rogue-65 "Weapons of Choice" passive node emits 7 mods scoped to specific
dual-wield weapon pairs ("with a Mace and Dagger", "with an Axe and a
Sword", "with 2 Daggers", "with 2 Swords", "with an Axe and Dagger",
"with a Sword and Dagger", "with a Mace and Sword"). Before this guard
the parser had no matcher for the pair / "with 2 \<weapons\>" forms —
each of the 7 ModCache entries kept the pair/duo text in slot[2] residue
and applied the bonus unconditionally (or with at most one weapon
condition), silently dropping the dual-wield gate.

| Site | File | What it does |
|---|---|---|
| Parser | `src/Modules/ModParser.lua` | New nested `DamageSourceWeapons` loop emits `modTagList["with <a/an> <w1> and (a/an) <w2>"]` (168 ordered pairs, with article variations on `w2`) carrying `Using<W1>` + `Using<W2>` + `DualWielding`; same loop emits `modTagList["with 2 <w>s"]` for the 8 same-weapon forms carrying `Using<W>` + `DualWielding` |
| ModCache | `src/Data/ModCache.lua` | 7 Rogue "Weapons of Choice" entries carry the full 3-condition (or 2-condition for the same-weapon form) tagList with empty residue |

**Spec:** `spec/System/TestDualWieldPairSuffix_spec.lua`

**Establishing commit:** (this commit)

### `per-bleed-stack-suffix-family`

LEB passive-tree stats use 7 colloquial "per Bleed" / "per 10 Bleeds on
the target" / "per stack of bleed on you" / "per 10% Bleed chance"
suffix forms (Necromancer, Falconer, Druid Locust Swarm, Sentinel Bloody
Trail, Rogue Cinder Strike, etc.). Before this guard the parser only
had `["per bleed stack"]`, so the colloquial forms fell through —
"Bleed" was eaten as a SkillName tag and 22 ModCache entries kept the
"per Bleed" text in slot[2] residue, applying the inner mod
unconditionally (or scoped only to the "Bleed" skill, which is wrong).

| Site | File | What it does |
|---|---|---|
| Parser | `src/Modules/ModParser.lua` (~line 670–) | 7 new `modTagList` entries: `["per bleed"]` / `["per 10 bleeds on the target, up to 200 bleeds"]` / `["per 10 bleeds on enemy, up to 20%"]` / `["per stack of bleed on you"]` (actor=self) / `["per stack of bleed on the enemy releasing it"]` (limit=20) / `["per stack of bleed on the target"]` / `["per 10% bleed chance"]` (PerStat:BleedChance div=10) — all evaluated before the SkillName eater |
| ModCache | `src/Data/ModCache.lua` | 20 entries carry the correct `Multiplier:BleedStack` tag (with the right actor / div / limit) or composite `SkillName + BleedStack` with empty residue. 2 additional entries (`1% Chance per Bleed for Haste on Enemy Death`, `15% Maximum Damage Per Bleed`) are GATED only (see follow-ups below) |

**Spec:** `spec/System/TestPerBleedStackSuffix_spec.lua`

**Establishing commit:** (this commit)

### `shadow-suffix-family` (C6a..C6f, incremental)

Bladedancer / Falconer Shadow mechanics use 14 distinct suffix / scope
patterns scattered across ~130 ModCache silent-failure entries. The
guard is built incrementally across six sub-commits (C6a..C6f), each
locking one pattern cluster. The single spec
`spec/System/TestShadowsSuffixFamily_spec.lua` is extended in each
sub-commit; this entry documents the cumulative scope.

| Site | File | What it does |
|---|---|---|
| Parser modTagList | `src/Modules/ModParser.lua` (~line 596) | `["per shadow"]` → `Multiplier:ActiveShadow`; `["with at least 3 shadows"]` → `MultiplierThreshold:ActiveShadow threshold=3` |
| Parser modNameList | `src/Modules/ModParser.lua` (~line 203) | `["maximum shadows"]` / `["max shadows"]` → `MaxShadows` stat name |
| ModCache | `src/Data/ModCache.lua` | 3 "Per Shadow" damage/area scalers carry `Multiplier:ActiveShadow`, 3 "Maximum Shadows" entries parse to `MaxShadows BASE`, 1 "With At Least 3 Shadows" entry carries `MultiplierThreshold` |
| Site | File | What it does |
|---|---|---|
| Parser modTagList | `src/Modules/ModParser.lua` (~line 527) | `["for skills used by shadows"]` → `Scope: minion`; `["for shadow attack"]` → `Condition: ShadowAttack` |
| ModCache (P1) | `src/Data/ModCache.lua` | 35 percent-form "X% Increased Damage / Critical Strike Chance for skills used by Shadows" entries carry `Scope:minion` with empty residue; 3 no-% "+N Increased Damage" entries carry `Scope:minion` with `" Increased "` residue tolerated as a separate follow-up |
| ModCache (P7) | `src/Data/ModCache.lua` | 4 "for Shadow Attack" entries carry `Condition:ShadowAttack` (the 2 "Doubled" entries lose the doubling mult — see follow-ups) |
| Site | File | What it does |
|---|---|---|
| Parser modTagList | `src/Modules/ModParser.lua` (~line 540) | 5 new modTagList entries: `["gained on shadow creation"]` / `["gain on shadow creation"]` / `["gain per shadow"]` (Condition:OnShadowCreate); `["from subsequent shadows consumed"]` / `["when you consume a shadow"]` (Condition:OnShadowConsume). The 3-word `["gain per shadow"]` wins over the 2-word C6a `["per shadow"]` via scan() longest-match. |
| ModCache (P3) | `src/Data/ModCache.lua` | 27 Life/Ward BASE entries carry Condition:OnShadowCreate with empty residue |
| ModCache (P5) | `src/Data/ModCache.lua` | 2 entries (Damage MORE, Melee Area BASE) carry Condition:OnShadowConsume |
| ModCache (P8) | `src/Data/ModCache.lua` | 7 "Chance to gain a stack of Dusk Shroud when you consume a Shadow" entries promoted from `{{}}` empty mods to ChanceToTriggerOnHit_Ailment_DuskShroud BASE with Condition:OnShadowConsume |
| ModCache (deferred) | `src/Data/ModCache.lua` | `+3 Mana Gain Per Shadow` and `25 Ward Gain Per Shadow` carry Condition:OnShadowCreate (re-classified from C6a per-Shadow multiplier; surface "Per Shadow" form is misleading - actual mechanic is on-creation trigger) |
| Parser specialModList (`dusk-shroud-trigger-effect`) | `src/Modules/ModParser.lua` (~L1786) | `^consuming a shadow grants a stack of dusk shroud$` → `ChanceToTriggerOnHit_Ailment_DuskShroud BASE=100` + `Condition:OnShadowConsume`. Guaranteed-form (100% chance) counterpart of P8 chance-form affix family; powers Doppelganger's Facade (uniques.json L10257 / set_1_4.json L301). Game-file backing: dump.cs L22771 `RogueShadow.duskShroudChanceOnConsumption` (consumed in `ConsumeShadow()` L22808); dump.cs L123962 `AilmentID DuskShroud = 82`. Reuses the existing `conditionOnShadowConsume` Config toggle (ConfigOptions.lua L292) — no new accumulator. |
| ModCache (`dusk-shroud-trigger-effect`) | `src/Data/ModCache.lua` (~L16730) | Doppelganger's Facade `"Consuming a Shadow grants a stack of Dusk Shroud"` cache key promoted from `{{},""}` to mod-list shape carrying ChanceToTriggerOnHit_Ailment_DuskShroud BASE=100 + Condition:OnShadowConsume. |

**Spec:** `spec/System/TestShadowsSuffixFamily_spec.lua` (C6a section)
**Spec:** `spec/System/TestShadowsSuffixFamily_spec.lua` (C6b section)
**Spec:** `spec/System/TestShadowsSuffixFamily_spec.lua` (C6c section)
**Spec:** `spec/System/TestShadowsSuffixFamily_spec.lua` (C6d section)
**Spec:** `spec/System/TestShadowsSuffixFamily_spec.lua` (C6e section)
**Spec:** `spec/System/TestShadowsSuffixFamily_spec.lua` (C6f section)
**Spec:** `spec/System/TestShadowsSuffixFamily_spec.lua`
(C6 follow-ups: F8 + F7 + F2 + F12 section, 9 tests)

**Establishing commit:** C6a sub-commit
**Establishing commit:** C6b sub-commit
**Establishing commit:** C6c sub-commit
**Establishing commit:** C6d sub-commit
**Establishing commit:** C6e sub-commit
**Establishing commit:** C6f sub-commit
**Establishing commit:** C6 follow-up consolidation commit
**Establishing commit:** F7 Dusk Shroud trigger-effect (Doppelganger's Facade) commit

### `skill-level-false-positive-purge`

Companion to C6's F12 fix. F12 gated the SkillLevel fallback in
`ModParser.lua` (~L2643) on whitespace-only residue, stopping NEW false
positives at the parser level. But the ModCache already contained 287
stale entries baked before that gate -- each had body
`name="SkillLevel",type="BASE",value=N` plus a SkillName scope, but
non-empty residue indicating the actual stat was NOT a "+N to <Skill>"
form (Stacks / Charges / Immunity / Casts / Cooldown / "Seconds of <X>
after Traversal Skill" / etc.).

| Site | File | What it does |
|---|---|---|
| ModCache | `src/Data/ModCache.lua` | All 287 stale entries neutralized to `{{},""}` |

**Spec:** `spec/System/TestSkillLevelFalsePositives_spec.lua` (2 tests:
zero-residue invariant + representative sample shape lock).

**Establishing commit:** B sub-commit (skill-level-purge)

### `max-shadows-output-wiring`

C6's F1: the Bladedancer Shadow pool cap (`MaxShadows`) was parsed by
`ModParser.lua` (`["maximum shadows"] = "MaxShadows"`, L213-220, see
`shadow-suffix-family`) but had no consumer in CalcDefence -- a
silent-failure on the output side. Mod existed in modDB; nothing read it.

Two-site lock mirroring the `potion-slots-no-character-base` pattern:

| Site | File | What it does |
|---|---|---|
| calc-wiring | `src/Modules/CalcDefence.lua` (~L1730) | `output.MaxShadows = modDB:Sum("BASE", nil, "MaxShadows")` |
| display row | `src/Modules/CalcSections.lua` (~L883)  | `{ label = "Maximum Shadows", haveOutput = "MaxShadows", ... }` |

**Spec:** `spec/System/TestMaxShadowsOutput_spec.lua` (3 tests:
sum-from-BASE, no-leading-constant, display row exists).

**Establishing commit:** C6/F1 (max-shadows-output-wiring)

### `lament-scorn-reforged-tier-ranges`

"The Last Bear's Lament Reforged" (statOrderKey 802) and "The Last Bear's
Scorn Reforged" (statOrderKey 803) are tiered unique mods (T0..T7) on the
Last Bear set helmets. LE 1.4.5 silently bumped both families' Health
Regen / Endurance Threshold / Endurance % ranges. Without this guard,
regenerating ModItem from older datamining snapshots or a partial revert
would re-introduce the pre-1.4.5 ranges and silently underestimate
Endurance Threshold by roughly half on T6-T7.

Triangulation evidence (BxvJP3g1 lv99 Necromancer, 2026-05-13):
- LE in-game character sheet vs LEB calc showed Endurance Threshold short
  by ~130 until 802_6 (helmet suffix on Lament-tier T6 set helmet) was
  re-fitted to the LE 1.4.5 range (240-300 vs old 120-150). Remaining

| Site | File | What it does |
|---|---|---|
| Data | `src/Data/ModItem_1_4.json` keys `802_0..802_7`, `803_0..803_7` | Tier-by-tier `{rounding:Integer}+(lo-hi) Health Regen` / `+(lo-hi) Endurance Threshold` for 802; `+(lo-hi)% Endurance` (and Phys Leech) for 803 |

**Spec:** `spec/System/TestLamentScornReforgedTierRanges_spec.lua`

**Establishing commit:** (this commit)

### `stun-avoidance-base-and-tree`

`output.StunAvoidance` is built from two terms that have each silently
disappeared at least once in prior refactors:

1. **Class base** = `baseStunAvoidance + stunAvoidancePerLevel * Level`.
   Registered in `CalcSetup.lua` as a single BASE mod whose value is the
   per-level rate and whose `Multiplier{var=Level}` tag carries
   `base = baseStunAvoidance`. If the `base = ...` tag argument is dropped,
   the +250 lv1 floor vanishes while per-level scaling keeps working —
   nothing else in calc flags the loss.
2. **Aggregate Sum over BASE.** `CalcDefence.lua` reads
   `modDB:Sum("BASE", nil, "StunAvoidance")`. Passive nodes such as
   Acolyte-19 "Towering Death" (+50 / pt, up to 5 scaling points = +250)

| Site | File |
|---|---|
| class base mod registration | `src/Modules/CalcSetup.lua` (~line 688) |
| flat-sum read for stun threshold | `src/Modules/CalcDefence.lua` (~line 1502) |

**Spec:** `spec/System/TestStunAvoidanceBaseAndTree_spec.lua`
- "CalcSetup registers StunAvoidance with both base and per-level terms"
- "CalcDefence reads StunAvoidance via Sum over BASE (no item-only narrowing)"

**Establishing commit:** (this commit)

### `idol-refracted-weaver-enchant-boost`

The Idol Altar's property 4 (`EffectOfIdolEnchantsInRefractedSlots`,
"+N% Effect of Weaver Enchantment Affixes for Idols in Refracted Slots")
covers BOTH `SpecialAffixType.IdolEnchantment` (class-specific idol
enchants in the `enchanted` ModIdol section, e.g. 897 Ward per Second
on Acolyte idols) AND `SpecialAffixType.IdolWeaver` (weaver-tree
enchantments). Two independent bugs each silently produced a zero
boost:

1. **ModParser pattern coverage.** The in-game tooltip for the Weaver
   Enchantment variant omits "increased" and is prefixed with "+", e.g.
   `+(46-52)% Effect of Weaver Enchantment Affixes for Idols in Refracted Slots`.
   The Standard prefix / suffix variants instead read `(N-M)% increased

| Site | File |
|---|---|
| Weaver-enchant ModParser patterns | `src/Modules/ModParser.lua` (~line 1005) |
| `specialAffixType` enum normalisation in cloneWithAltarBoost | `src/Modules/CalcSetup.lua` (~line 1176) |

**Spec:** `spec/System/TestIdolRefractedWeaverEnchantBoost_spec.lua`
- "ModParser accepts both 'increased effect' and '+N% effect' weaver variants"
- "CalcSetup specialAffixType normalises numeric SpecialAffixType enum to its string form"
- "CalcSetup prefers the _0 entry for SpecialAffixType lookup (avoids tier-numeric leak)"

**Establishing commit:** (this commit)

### `minion-health-regen-per-second`

Acolyte tree node "Blood Armor" (`tree_3.json` `Acolyte-21`, present in
1_2/1_3/1_4 trees) carries scaling stat `+6 Minion Health Regen Per Second`
(plus a separate player-side `10% Increased Health Regen`). The "Minion"
prefix in the parser routes the line to `MinionModifier` and "Health Regen"
maps to `LifeRegen` via nameMap, but the trailing "Per Second" is not
consumed by any pattern. modLib.parseMod leaves it as residue, PassiveTree
sets `node.extra=true`, and the entire mod is silently dropped from modDB —
losing 6×ranks of minion health regen on every Necromancer / Lich / Warlock
build that takes Blood Armor.

The fix registers two explicit specialModList entries that consume the full
line directly:

| Site | File |
|---|---|
| specialModList minion regen "per second" patterns | `src/Modules/ModParser.lua` (~after `health per second` guard) |
| ModCache entry residue cleanup | `src/Data/ModCache.lua` (`+6 Minion Health Regen Per Second`) |

**Spec:** `spec/System/TestMinionHealthRegenPerSecond_spec.lua`
- "ModParser has explicit specialModList patterns for minion health/life regen per second"
- "ModCache entry for '+6 Minion Health Regen Per Second' has no residue (extra=nil)"

**Establishing commit:** (this commit)

### `letools-import-bio-level-mastery`

`ImportTabClass:BuildCharFromLETools` extracts character identity (level,
class, mastery) from the LETools planner JSON. The current API revision
returns these fields nested under `data.bio = {level, characterClass,
chosenMastery}`; top-level `jsonData.level / jsonData["class"] /
jsonData.mastery` are stale duplicates kept for backwards compatibility
and may be wrong or absent.

The resolution must therefore read `bio.*` first and fall back to the
top-level fields only when bio is missing:

```lua
local bio = data.bio or {}

| Site | File |
|---|---|
| bio→classId/mastery/level resolution | `src/Classes/ImportTab.lua` `function ImportTabClass:BuildCharFromLETools` (~line 996) |

**Spec:** `spec/System/TestLEToolsImportBioMastery_spec.lua`
- "resolves classId/mastery/level from data.bio"
- "bio.* takes precedence over top-level jsonData fields"
- "falls back to top-level jsonData when bio is missing"
- "resolves Rogue Falconer (mastery=3) correctly"
- "returns nil on unknown class" / "returns nil on unknown mastery"

**Establishing commit:** (this commit) — defensive guard added after
investigating a stale `QJWMRv53 lv73 Falconer.xml` artefact that did
not reproduce on current HEAD but whose failure mode (silent filename
corruption) warrants locking the bio-first resolution contract.

### `unique-mod-text-tooltip-audit`

A handful of unique `mods[]` strings in `uniques_1_4.json` were drifting
from their in-game tooltips. Upstream regen (and LETools cross-check)
re-introduced the bad text on each datamining pass. Audited against
screenshots on 2026-05-15:

- **Hand of Judgement**: regen emitted `-12 to -8 Judgement Mana Cost
  while Unarmed`. In-game tooltip reads `-12 to -8 Mana cost for
  Judgement while Unarmed` (note lowercase `cost`). Override added to
  `LE_datamining/extracted/unique_overrides.json`.
- **Pearls of the Swine (Blood, Fire)**: LEB carried a spurious
  `+100% ` prefix on the `Bone Curse also inflicts <X>` line. In-game
  tooltips do NOT show the prefix. The Poison (Acid Skin) variant was

| Site | File | What it does |
|---|---|---|
| data     | `src/Data/Uniques/uniques_1_4.json` (Hand of Judgement, ~line 5563; Pearls of the Swine Blood ~line 7657, Fire ~line 7682) | Tooltip-accurate mod strings |
| upstream | `LE_datamining/extracted/unique_overrides.json` (Hand of Judgement) | Override that survives `apply_leb_rules.py` regen |

**Spec:** `spec/System/TestUniqueDataIntegrity_spec.lua`
- "tooltip-audited mod text is preserved (TOOLTIP_TEXT)"

**Establishing commit:** (this commit) — added after a 2026-05-14 review
flagged 38 uniques where `regen_vs_leb_pairs.json` showed text deltas;
in-game screenshots confirmed which side was authoritative for each.

## Guards without inline markers

66 of the 148 indexed guards have no `@leb-regression-guard:<id>` comment
in `src/` or `spec/`. Their protection lives entirely in the busted spec
(listed below) and this index — a future refactor at the guarded site
will get no in-source signal to stop and run the spec. The grep workflow

```sh
grep -rn '@leb-regression-guard' src/ spec/
```

will not surface them.

Recovering from this requires per-guard judgment (locate the original
site from the establishing commit, decide whether an inline marker would
sit cleanly there) and is not done in bulk. Rows marked `(no spec file
found)` additionally lack a `**Spec:**` cross-reference in the index —
those are a separate gap (the guard claims protection but doesn't name
the test that locks it in).

| Guard ID | Spec file |
|---|---|
| `affix-kind-roundtrip` | `spec/System/TestItemParse_spec.lua` |
| `affix-display-order` | `spec/System/TestItemParse_spec.lua` |
| `idol-altar-not-idol-slot` | `spec/System/TestModParse_spec.lua` |
| `equipped-corrupted-idol-multiplier` | `spec/System/TestEquippedCorruptedIdolMultiplier_spec.lua` |
| `omen-idol-slot-dedup-on-corruption-count` | `spec/System/TestOmenIdolSlotDedup_spec.lua` |
| `non-unique-idol-stat-multiplier` | `spec/System/TestNonUniqueIdolStatMultiplier_spec.lua` |
| `corrupted-count-pre-levelreq` | `spec/System/TestModParse_spec.lua` |
| `applyrange-rounding-mode-split` | `spec/System/TestItemTools_spec.lua` |
| `applyrange-fixed-tier-noop` | `spec/System/TestItemTools_spec.lua` |
| `per-set-fractional-precision` | `(no spec file found)` |
| `set-bonus-breakdown-publish` | `spec/System/TestSetBreakdown_spec.lua` |
| `set-bonus-breakdown-bridge` | `(no spec file found)` |
| `int-truncate-life-mana` | `spec/System/TestModParse_spec.lua` |
| `unique-req-level-override` | `(no spec file found)` |
| `pattern-a-affix-level-req` | `(no spec file found)` |
| `unique-data-integrity` | `spec/System/TestUniqueDataIntegrity_spec.lua` |
| `regen-pct-shorthand-inc` | `spec/System/TestModParse_spec.lua` |
| `butchers-crown-no-mana-regen` | `spec/System/TestModParse_spec.lua` |
| `idol-altar-capacity-tooltip` | `spec/System/TestIdolAltarTooltip_spec.lua` |
| `regen-alias-coverage` | `spec/System/TestRegenAlias_spec.lua` |
| `curse-spell-damage-stat` | `spec/System/TestCurseSpellDamage_spec.lua` |
| `potion-slots-no-character-base` | `spec/System/TestPotionSlots_spec.lua` |
| `block-requires-shield` | `spec/System/TestBlockShield_spec.lua` |
| `flame-ward-block-toggle` | `spec/System/TestBlockShield_spec.lua` |
| `form-tree-nodes-gated-by-condition` | `spec/System/TestS5FormTreeNodeGate_spec.lua` |
| `transform-cost-bypass` | `spec/System/TestS5TransformCostBypass_spec.lua` |
| `elemental-nova-spec-tree-gated-damage-type` | `spec/System/TestElementalNovaDamageType_spec.lua` |
| `tooltip-mod-line-wrap` | `spec/System/TestTooltipWrap_spec.lua` |
| `exulis-all-attributes-range` | `spec/System/TestExulisRange_spec.lua` |
| `exulis-shared-rollid` | `spec/System/TestExulisRange_spec.lua` |
| `sidebar-ward-stat-removal` | `spec/System/TestSidebarWardStats_spec.lua` |
| `letools-diff-ward-regen-gross-mapping` | `spec/System/TestWardRegenStatSemantics_spec.lua` |
| `phase4-stun-aoe-melee-flag-isolation` | `spec/System/TestPhase4LEToolsParity_spec.lua` |
| `phase4-minion-modifier-bucket-aggregation` | `spec/System/TestPhase4LEToolsParity_spec.lua` |
| `eterras-path-player-ms` | `spec/System/TestEterraPathPlayerMS_spec.lua` |
| `you-and-minions-dual-mods` | `spec/System/TestYouAndMinionsDualMods_spec.lua` |
| `movement-speed-base-additive` | `spec/System/TestMovementSpeedBaseAdditive_spec.lua` |
| `lifeonhit-flag-aware-sum` | `spec/System/TestLifeOnHit_spec.lua` |
| `symbols-of-hope-inc-not-more` | `spec/System/TestSymbolsOfHope_spec.lua` |
| `sentinel-95-base-health-regen` | `spec/System/TestSentinel95Regen_spec.lua` |
| `sentinel-93-mana-regen-from-holy-aura` | `spec/System/TestSentinel93ManaRegen_spec.lua` |
| `urzils-pride-mana-regen-per-uncapped-lightning-res` | `spec/System/TestUrzilsPrideManaRegen_spec.lua` |
| `humble-idol-scalar-scale-first` | `spec/System/TestItemTools_spec.lua` |
| `apiarist-scalar-interpolate-first` | `spec/System/TestItemTools_spec.lua` |
| `lament-base-damage-conversion` | `spec/System/TestLamentVolcanicOrbCannotFreeze_spec.lua` |
| `lament-volcanic-orb-cannot-freeze` | `spec/System/TestLamentVolcanicOrbCannotFreeze_spec.lua` |
| `block-chance-total-no-shield-zero` | `spec/System/TestBlockShield_spec.lua` |
| `ward-regen-canonical-key-wardpersecond` | `(no spec file found)` |
| `ward-gained-per-second-alias` | `spec/System/TestWardGainedPerSecond_spec.lua` |
| `ward-gained-each-second-alias` | `spec/System/TestWardGainedEachSecond_spec.lua` |
| `channelling-tree-node-auto-gate` | `(no spec file found)` |
| `two-phase-floor-post-round-scalar` | `spec/System/TestPostRoundScalarRoundHalfUp_spec.lua` |
| `idol-altar-boost-subtype-rounding` | `spec/System/TestIdolAltarBoostSubtypeRounding_spec.lua` |
| `affix-effect-modifier-formula` | `spec/System/TestAffixEffectModifierFormula_spec.lua` |
| `boneclamor-barbute-ward-per-uncapped-necrotic-res` | `spec/System/TestBoneclamorBarbute_spec.lua` |
| `skills-tab-buff-toggle-config-sync` | `spec/System/TestSkillsTabBuffToggleConfigSync_spec.lua` |
| `properties-loader-init` | `spec/System/TestPropertiesLoader_spec.lua` |
| `unique-hideintooltip-letools-artifact` | `spec/System/TestUniqueHideInTooltipLETools_spec.lua` |
| `ward-one-shot-gain-family` | `spec/System/TestWardOneShotGainFamily_spec.lua` |
| `shadow-suffix-family` | `spec/System/TestShadowsSuffixFamily_spec.lua` |
| `dusk-shroud-trigger-effect` | `spec/System/TestShadowsSuffixFamily_spec.lua` (sub-section, 2 tests) |
| `idol-altar-canrollon-normalization` | `spec/System/TestIdolAltarCanRollOn_spec.lua` |
| `skill-level-false-positive-purge` | `spec/System/TestSkillLevelFalsePositives_spec.lua` |
| `max-shadows-output-wiring` | `spec/System/TestMaxShadowsOutput_spec.lua` |
| `lament-scorn-reforged-tier-ranges` | `spec/System/TestLamentScornReforgedTierRanges_spec.lua` |
| `stun-avoidance-base-and-tree` | `spec/System/TestStunAvoidanceBaseAndTree_spec.lua` |
| `idol-refracted-weaver-enchant-boost` | `spec/System/TestIdolRefractedWeaverEnchantBoost_spec.lua` |
| `unique-mod-text-tooltip-audit` | `spec/System/TestUniqueDataIntegrity_spec.lua` |

### `minion-skillid-scope-martyrdom`

`CalcSetup.buildModListForNodeList`'s `stripSkillId` branch (used by
`applyBuffPrefix` for buff-skill tree nodes) must **exempt
MinionModifier mods** from the SkillId strip. The buff-tree strip is
designed for player-side broadcast effects (e.g. Sentinel Covenant of
Light aura mods landing on player modDB without a per-skill scope),
but `MinionModifier` carries cross-actor mods routed via
`Modules/CalcPerform.lua` `env.player.mainSkill.skillModList:List(skillCfg, "MinionModifier")` → `minion.modDB.AddMod`.

If the SkillId tag is stripped, every active buff-skill's tree
MinionModifier leaks onto every minion's modDB. The decisive example
is Dread Shade tree node ds4d3-3 (Martyrdom):

> "30 Minion Armour Per Vitality" +
> "Dread Shade now grants minions armor based on your vitality, but
>  Dread Shade decays your minions faster."

The in-game description binds the effect to Dread Shade's target
minion, so cross-minion leakage is incorrect per game-data semantics.
ModStore.lua's SkillId tag filter (cfg.skillGrantedEffect.id gate) is
the only mechanism that preserves the per-skill scope, so the tag
must survive the strip path.

Symptoms before fix (BxvJP3g1 lv99 Necromancer, ds4d3-3 #3): with
Option A (PerStat→parent inject) trial-applied to expose the leak,
Skeleton.Armour ballooned to 1730 (= (30 BASE + 30 Vit × 30 BASE) ×
1.86 INC), proving Martyrdom was contaminating Skeleton's modDB even
though Skeleton is not Dread Shade's target. Layer 1 fix here stops
the contamination at source even before Layer 2 (PassiveTree
canonical-id alignment) and Layer 3 (buff-active gating) land.

| Site | File | What it does |
|---|---|---|
| MinionModifier strip exemption | `src/Modules/CalcSetup.lua` `function calcs.buildModListForNodeList` (~line 375) | `if stripSkillId and mod.name ~= "MinionModifier"` guards the SkillId-detection loop so MinionModifier mods retain their SkillId tag through the buff-tree strip path |

**Spec:** `spec/System/TestMinionSkillIdScopeMartyrdom_spec.lua`
- "CalcSetup.buildModListForNodeList exempts MinionModifier from SkillId strip"

**Triangulation note:** [[Minion Armor 三角測量 g1 調査]] (Obsidian) —
game-data ground truth (tree_3.json L10081-10109), the two-bug
masking structure, and the 3-Layer fix plan.

**Establishing commit:** (this commit) — Layer 1 of the Minion Armor
g1 triangulation; Layer 2 (PassiveTree canonical skill ID) and
Layer 3 (buff-active condition gating) deferred to future PRs and
will be triangulated against `BxvJP3g1` / `o3Zlpkxd` test builds.

### `minion-modifier-perstat-parent-actor`

**Problem.** LE minions don't carry primary attributes
(Vit/Str/Dex/Int/Att) of their own. Tree-passive text like
Acolyte-59 `notScalingStats[0]` `"2% Increased Minion Armor Per
Intelligence"` reads the *player's* Int, not the minion's. Without
intervention `ModStore.lua`'s PerStat resolve defaults
`target = self` → `minion.modDB`, `GetStat("Int")` returns 0, and
every `Per <PrimaryAttr>` contribution that should land on minions
via MinionModifier silently zeroes out.

In the g1 triangulation (BxvJP3g1 lv99 Necromancer, player.Int=43):
- Expected: 2% × 43 = 86% INC × 30 BASE = 55.8 ≈ LETools 57
- Before fix: Skeleton.Armour = 30, Bone_Golem.Armour = 30 (Δ-27, 47%)
- After fix: Skeleton.Armour = 56, Bone_Golem.Armour = 56 (Δ-1, 1.7% rounding noise)

**Mechanism.** The MinionModifier dispatch in `CalcPerform.lua`
walks `value.mod`'s tags before `env.minion.modDB:AddMod`. For
PerStat tags whose `stat` (or any entry in `statList`) appears in
`LE_MINION_PERSTAT_PARENT_ATTRS`, it sets `actor = "parent"` so
ModStore retargets the PerStat resolve to `minion.actor.parent`
(the player). An explicit prior `actor` binding is never
overwritten; the mod is shallow-copied before mutation so shared
`skillModList` references stay clean.

| Site | File | What it does |
|---|---|---|
| Parent-attribute registry | `src/Data/Global.lua` `LE_MINION_PERSTAT_PARENT_ATTRS` | Set of stat names ({Vit,Str,Dex,Int,Att} + Raw* twins) that must resolve against player when read via PerStat on a MinionModifier mod |
| PerStat→parent injection | `src/Modules/CalcPerform.lua` MinionModifier dispatch loop | Walks tags, copies the mod on first match, sets `injected[ti].actor = "parent"` for PerStat tags hitting the registry |

**Spec:** `spec/System/TestMinionModifierPerStatParentActor_spec.lua`
- "LE_MINION_PERSTAT_PARENT_ATTRS covers the five primary attributes and their Raw twins"
- "CalcPerform MinionModifier dispatch routes PerStat actor=parent for primary attrs"

**Triangulation note:** [[Minion Armor 三角測量 g1 調査]] (Obsidian) —
the 30 vs 57 gap closure. Layer 2/3 as originally framed (PassiveTree
canonical id + buff-active gating for Martyrdom Dread-Shade targeting)
turned out **not** needed for this gap; PassiveTree.lua L116 already
stores the canonical id (`skill.name` in tree_3.json *is* the canonical
field), and the Acolyte-59 `notScalingStats` route is independent of
Dread Shade buff-active. Layer 2/3 remain deferred as a separate
"which minion is Dread Shade buffing" problem requiring data-model
expansion, not part of this fix.

**Establishing commit:** (this commit)

### `minions-have-dread-shade-buff-gating`

**Problem.** In-game Dread Shade is implemented as
`DreadShadeMutator : AbilityMutator` (dump.cs L38327-38446) which
attaches a *per-target* Buff Component to each minion it touches
(`DelayedCastOnMinion`). The buff Component exposes `auraStats`,
`statsToParent`, and `addedArmorPerVit`, so tree-passive
contributions like Martyrdom's "30 Minion Armour per Vitality"
only land on minions that actually carry the buff. LEB's
buff-tree mod plumbing, however, treats the Dread Shade tree
scope as a single SkillId filter (`ModStore.lua` L750-753) and
therefore had no way to express the per-target nature of the
buff: every MinionModifier inner mod whose SkillId tag pointed at
`DreadShade` would unconditionally land on every spawned minion's
`modDB` once Layer 1's SkillId-stripping exception kept the tag
intact. The original triangulation closed the 30→57 Armor gap
via Option A (PerStat→parent), so this entry isn't about a
numeric drift — it's a correctness/visibility gap: a planner
can't *show* "this is conditional on Dread Shade" until the
condition exists.

**Mechanism.** Two registries plus one injection point:

| Site | File | What it does |
|---|---|---|
| Buff-tree gating registry | `src/Data/Global.lua` `LE_WHILE_ACTIVE_BUFF_BY_TREE_ID["ds4d3"]` = `"MinionsHaveDreadShade"` | Gates Dread Shade *tree* node contributions on the same condition (mirrors Flame Ward / Form gating) |
| Per-target minion buff registry | `src/Data/Global.lua` `LE_MINION_BUFF_SKILL_TO_CONDITION = { DreadShade = "MinionsHaveDreadShade" }` | Maps canonical buff-skill names to the Condition flag that must be set on `player.modDB` for the buff's minion-side contributions to apply |
| SkillId→ActorCondition injection | `src/Modules/CalcPerform.lua` MinionModifier dispatch loop | Walks `value.mod`'s tags, copies the mod on first injection, and appends an `ActorCondition` tag (`actor="parent"`, `var=<mapped condition>`) when a SkillId tag matches `LE_MINION_BUFF_SKILL_TO_CONDITION`. `ModStore.lua` L605-630 resolves the `ActorCondition` against `minion.actor.parent.modDB` so the gating reads the player's flag. |
| User-facing toggle | `src/Modules/ConfigOptions.lua` `conditionMinionsHaveDreadShade` | Lets the user flip `Condition:MinionsHaveDreadShade` on the player modDB. Default OFF → existing snapshots stay unchanged. |

`SkillsTab` already renders a toggle for every entry in
`LE_WHILE_ACTIVE_BUFF_BY_TREE_ID` (see
`while-active-buff-tree-id-map` guard), so adding the `ds4d3`
mapping auto-surfaces a "while Dread Shade active" gate for the
*tree node* contributions next to the existing Flame Ward / Form
toggles. The new `LE_MINION_BUFF_SKILL_TO_CONDITION` registry
extends that idea to the *per-target buff Component* path so the
Calcs breakdown can show each Dread-Shade-conditional row as a
distinct source rather than an unconditional minion mod.

**Spec:** `spec/System/TestMinionsHaveDreadShadeBuffGating_spec.lua`
- "LE_MINION_BUFF_SKILL_TO_CONDITION maps DreadShade to MinionsHaveDreadShade"
- "LE_WHILE_ACTIVE_BUFF_BY_TREE_ID carries the Dread Shade treeId"
- "CalcPerform MinionModifier dispatch appends ActorCondition for registered buff-skill SkillId tags"
- "ConfigOptions.lua exposes the MinionsHaveDreadShade toggle"

**Triangulation note:** [[Minion Armor 三角測量 g1 調査]] (Obsidian) —
follow-up to Option A. Game-data evidence
(dump.cs DreadShadeMutator) is the source of truth for the
per-target Buff Component model that motivates a Condition flag
over a skill-scope SkillId filter.

**Establishing commit:** (this commit)

### `minion-movespeed-passive-node-phrasings`

LE 1.4 passive-tree nodes use three inconsistent phrasings for minion
movement speed, and the original `specialQuickFixModList` patterns only
matched the canonical `"X% increased Minion Movement Speed"` form. The
other two phrasings parsed as `BASE` (with residue `"  Increased  "`)
instead of `INC`, so the `MinionMovementSpeed` aggregation in
`CalcDefence.lua:1814` (`sumMinion("MovementSpeed", "INC")`) silently
saw 0 from these nodes.

| Phrasing | Source node | Tree file |
|---|---|---|
| `+N% Minion Movespeed` | Primalist-22 "The Chase" | `src/TreeData/1_4/tree_0.json` |
| `+N% Increased Minion Movespeed` | Necromancer ascendancy "Ardent Touch" | `src/TreeData/1_4/tree_0.json` (already-correct, no fix needed) |
| `N% Minion Increased Movement Speed` | Acolyte-20 "Invigorated Dead" | `src/TreeData/1_4/tree_3.json` |

| Site | File | What it does |
|---|---|---|
| parser normalizers | `src/Modules/ModParser.lua` `specialQuickFixModList` (~line 1070) | Two `^...%%) Minion ...` patterns rewrite the broken phrasings into the canonical `increased Minion Movement Speed` shape *before* the form scanner. Pattern 2 is narrowly scoped to `"Minion Increased Movement Speed"` only — other `X% Minion Increased Y` stats (cast speed, healing effectiveness, etc.) have the same residue bug but fixing them changes more snapshots than this PR's scope warrants (see follow-up TODO). |
| pre-cached entry | `src/Data/ModCache.lua` | Two pre-cached rows (`"+4% Minion Movespeed"`, `"2% Minion Increased Movement Speed"`) were updated from `BASE` to `INC` so historical cache hits don't bypass the new normalizer; they regenerate naturally on the next `SaveModCache` run. |

**Spec:** `spec/System/TestMinionMovespeedNodeText_spec.lua`
- "'+24% Minion Movespeed' (node literal) accumulates"
- "'24% increased Minion Movement Speed' (canonical) accumulates"
- "'+6% Increased Minion Movespeed' (Ardent Touch) accumulates"
- "'2% Minion Increased Movement Speed' (Invigorated Dead) accumulates"
- "'2% Increased Minion Movement Speed' (post-normalize) accumulates"

**Triangulation:** Qqwvdex2 lv98 Beastmaster (LETools 24% / pre-fix LEB
0 → post-fix 24), oy4Jk2Y9 lv100 Beastmaster (32 → 32), oN2zNnaR lv100
Necromancer (27 / pre-fix 0 / post-fix still 0 — **separate bug**: the
Necromancer build's minion-movespeed feed flows through
`SkillStatMap["minion_movement_speed_+%"]`, not the text parser, so this
guard does not address it).

**Follow-up TODO:** Other `X% Minion Increased Y` phrasings in
ModCache.lua (cast speed, healing effectiveness, melee damage, cold
damage, etc.) carry the same `BASE + residue` parse and likely
under-attribute the corresponding stats on real builds. Investigate as a
separate PR with its own triangulation set so the snapshot drift is
properly scoped.

**Establishing commit:** (this commit)

### `buff-tree-cooldown-recovery-skill-local`

`CalcSetup.buildModListForNodeList`'s `stripSkillId` branch (used by
`applyBuffPrefix` for buff-skill tree nodes) must **exempt
CooldownRecovery mods** from the SkillId strip in addition to the
`MinionModifier` carve-out (see `minion-skillid-scope-martyrdom`).

Buff-tree CooldownRecovery nodes describe the buff-skill's **own**
cooldown ("Symbols of Hope has a shorter cooldown") and game-side
route through the ability's per-instance CD timer, NOT through the
player's `SP.IncreasedCooldownRecoverySpeed` (=70). Stripping the
SkillId tag globalises the mod and double-counts it: once via the
skill-local sum at `CalcOffence.lua` L241
(`skillModList:Sum("INC", skillCfg, "CooldownRecovery")`) — which
remains correct — and again via the global sum at `CalcDefence.lua`
L1700 (`modDB:Sum("INC", nil, "CooldownRecovery")`), inflating
every other cooldown on the build.

Game ground truth:
- `LE_datamining/extracted/items/globalTreeData.json` →
  `skillTrees[treeID=si4lgl].nodes[id=23]` internal name
  "Sigils Of Hope Cooldown Recovery" — the node text is
  skill-scoped, not player-scoped.
- `dump.cs` `IdolAltarPropertyID` enum has no aggregate
  "CDR-from-tree" property; CDR-on-skill is per-ability state.
- Audit of si4lgl / ah443 buff-tree node stats: si4lgl-23 is the
  only `CooldownRecovery`-named node; the other CDR-flavored nodes
  use `Cooldown` (cooldown duration), which is a different mod
  name and not affected.

Symptoms before fix (BgRrekMz lv92 Paladin, si4lgl-23 #2,
SymbolsOfHopeEffect +20%):

> 2 points × 25% × (1 + 0.20 SoH effect) = 60% leaked global CDR
> `output.CooldownRecovery` 19 → 79 (LETools shows 19; +60 overshoot)

After fix BgRrekMz exact-matches LETools (19). oy4Jk2Y9 lv100
Beastmaster and QWXjqWJ2 lv100 Bladedancer retain a +10 game-faithful
delta from the Pyramidal Altar conditional implicit
(`IdolAltarPropertyID = 21
ICRSIfThereAreNoLargerIdolsAboveSmallerOnes`, equipmentItems.json
L37788-37820), which LETools UI omits and LEB correctly keeps —
not addressed by this guard.

| Site | File | What it does |
|---|---|---|
| CooldownRecovery strip exemption | `src/Modules/CalcSetup.lua` `function calcs.buildModListForNodeList` (~line 386) | extends the AND-clause to `mod.name ~= "MinionModifier" and mod.name ~= "CooldownRecovery"` so buff-tree CDR nodes (e.g. si4lgl-23 Enduring Hope) stay scoped to their own skill |

**Spec:** `spec/System/TestBuffTreeCooldownRecoverySkillLocal_spec.lua`
- "CalcSetup.buildModListForNodeList exempts CooldownRecovery from SkillId strip"

**Triangulation note:** G2 CDR triangulation across BgRrekMz / oy4Jk2Y9
/ QWXjqWJ2 — only BgRrekMz carried the si4lgl-23 leak; the residual
+10 on the other two is the altar conditional implicit and is
game-faithful.

**Establishing commit:** (this commit)

### `ward-regen-passive-vs-event-split-pre-fix-baseline`

`CalcPerform.lua` post-offence Ward Regen fold-in writes `pOut.WardPerSecond
= baseWardPerSecond + totalContribution` (line 1441), which incorrectly
folds the **event-driven** `ManaSpentGainedAsWard` contribution into the
display stat. The display `WardPerSecond` is the gross passive WPS that
the game writes to `wardRegen + wardRegenFromStats`
(`ProtectionClass.Update` RVA 0x234B8C0, see `ward_decompile.txt`).
`ManaSpentGainedAsWard` is wired via the event-driven `GainWard` path
(invoked per spell cast), not the continuous regen tick — so it must NOT
appear in the displayed Ward Regen value, only in the local `wps`
inversion math that derives Ward / WardDecay caps.

Game ground truth:
- `ProtectionClass.Update` (LE_datamining `ward_decompile.txt`): the
  `wardRegen` field updated per tick is the SUM of passive sources only
  (base + LifeRegenAppliesToWard + CurrentManaGainedAsWardPerSecond +
  MissingHealthGainedAsWardPerSecond). `ManaSpentGainedAsWard` is
  applied via `GainWard(amount)` from the spell-cast event handler.
- LETools "Ward Regen" reads the same passive snapshot — that's why
  Sorcerer / Spellblade builds with non-zero ManaSpentGainedAsWard show
  large positive `LEB − LETools` deltas while LEB's display includes
  the event contribution and LETools' does not.

Symptoms (post-reimport 119 G1-G6 canonical, `.tmp/reimport119/stat_diff_table.md`):
7 builds account for ≈ 598 of the total Σ|Δ| on `WardPerSecond` (mean
|Δ|=6.36 across 110 ward-bearing builds, max=354.8, n>2%=27):

| Build | LETools | LEB | Δ | Sub-class hint |
|---|---:|---:|---:|---|
| QDxZjPX8 lv95 Sorcerer | 222 | 576.77 | +354.77 | Sorcerer |
| BZ37dR2l lv100 Sorcerer | 104 | 209.46 | +105.46 | Sorcerer |
| BgRrekOY lv82 Sorcerer | 101 | 143.16 | +42.16 | Sorcerer |
| Bakbr2Ne lv86 Sorcerer | 41 | 75.05 | +34.04 | Sorcerer |
| oR6qaLp4 lv80 Spellblade | 105 | 134.12 | +29.12 | Spellblade |
| Qdz2yXLk lv100 Warlock | 151 | 173.64 | +22.64 | Warlock |
| o3Zlpkxd lv98 Necromancer | 25 | 35.01 | +10.01 | Necromancer |

`oYEOpZmJ lv87 Spellblade` (+10.14) is a candidate pending source
verification (which mod grants ManaSpentGainedAsWard on Spellblade).

| Site | File | What it does |
|---|---|---|
| Passive vs event split for display | `src/Modules/CalcPerform.lua` line ~1441 (in `do … end` block from L1418) | Display `pOut.WardPerSecond` MUST equal `passiveWardPerSecond` (base + CurrentMana + MissingHealth contributions). The event-driven `manaSpentContribution` is added to the **local** `wps` (line ~1466) which is used only for the Ward / WardDecay inversion. |

**Recommended fix:**
```lua
-- L1441 (current, INCORRECT for display):
pOut.WardPerSecond = baseWardPerSecond + totalContribution
-- Should be (passive-only for display; event-driven only in local `wps`):
pOut.WardPerSecond = passiveWardPerSecond
local wps = passiveWardPerSecond + manaSpentContribution
```

This is a **pre-fix snapshot freeze**: the 7 builds above are
re-imported and committed in their current (Lane A) state so the next
commit that flips the display split can be validated by snapshot diff.
Post-fix expectation: Σ|Δ| on `WardPerSecond` drops from ≈ 598 to ≈ 6
(Lane B / Necromancer residual only).

**Establishing commit:** (this commit)

### `altar-property-3-standard-only-gate`

The Idol Altar's properties 1 / 2 / 3 (`PrefixAndSuffix`, `Prefix`,
`Suffix` — `IdolAltarPropertyID` enum values 1/2/3 in
`dump.cs` L240052-240070) gate ONLY on
`SpecialAffixType.Standard` (sat=0). They MUST NOT boost
`SpecialAffixType.IdolEnchantment` (sat=4), `IdolWeaver` (sat=5),
`Corrupted` (sat=6), `Set` (sat=3), `Personal` (sat=2), or
`Experimental` (sat=1) affixes. The IdolEnchantment / IdolWeaver
families are reached by property 4 (`EffectOfIdolEnchantsInRefractedSlots`)
ONLY; corrupted/set/personal/experimental affixes receive no altar
boost.

LE's authoritative gate is the il2cpp method
`IsAffectedByAffectOfStandardPrefixesOrSuffixes(SpecialAffixType)`
(`dump.cs` L151678; header-only dump so the body is not directly
visible, but the enum partition + property-4 design pattern make the
gate's intent unambiguous). LEB's matching gate lives in
`CalcSetup.lua` `cloneWithAltarBoost`:

```lua
-- L1224-1230
local sat = specialAffixType(affix.modId)
if sat == "Standard" then
    boost = altarCommon + (specificBoost or 0)
elseif sat == "IdolEnchantment" or sat == "IdolWeaver" then
    boost = altarBoostEnchant
end -- Corrupted/Set/Personal/Experimental → boost stays 0
```

The two prefix/suffix lanes route via separate scale lists at
L1265-1266 so a mismatched sat cannot leak across the prefix↔suffix
boundary:

```lua
scaleAffixList(clone.prefixes, altarBoostPrefix)
scaleAffixList(clone.suffixes, altarBoostSuffix)
```

Any future refactor that:

- Collapses the `if sat == "Standard"` branch into an
  unconditional `boost = altarCommon + altarBoostPrefix` /
  `altarBoostSuffix`, OR
- Treats the property-3 suffix scalar as applying to "all suffix
  affixes" rather than "Standard suffix affixes", OR
- Allows `altarBoostPrefix` / `altarBoostSuffix` to feed into the
  `boost` variable when `sat ~= "Standard"`,

reintroduces the LETools-shaped over-application that the
oN2zWaYX triangulation surfaced.

Triangulation case study (inference-based — see Obsidian
`LEB vs LETools stat 比較.md` "2026-05-16 partial verification
report" under oN2zWaYX for the full reasoning): oN2zWaYX lv100
Spellblade carries a Sunset Auric Altar with property 3 ≈ 36%
("(33-39)% increased Effect of Suffixes for Idols in Refracted
Slots") and two Chitin Small Weaver Idols whose `837_0` "of
Chitin" suffix is tagged `specialAffixType: 5` (IdolWeaver) in
`src/Data/ModItem_1_4.json` L96488-96526. LEB reports
PhysicalResistTotal = 77 and MinionPhysicalResist = 20; LETools
reports 84 / 27 (Δ-7 on both halves of the compound affix, exactly
the +36% boost that LETools applies and LEB withholds). Because
LE's `IsAffectedByAffectOfStandardPrefixesOrSuffixes` gate is
documented in the il2cpp header and the SpecialAffixType enum
partition leaves IdolWeaver outside the "standard prefixes or
suffixes" naming, LEB's behaviour is the correctness-preserving
read; LETools is the deviation.

This guard is **inference-based**: no live LE client run was
performed (the user does not own a playable matching character;
test builds are LETools planner imports). Disposition is locked
on (1) the il2cpp method name + (2) the SpecialAffixType enum
shape + (3) the existence of a separate property 4 specifically
for IdolEnchantment/IdolWeaver. If a future LE client trace
contradicts the gate, this guard should be revisited.

| Site | File |
|---|---|
| Standard-only sat gate (boost selection) | `src/Modules/CalcSetup.lua` `cloneWithAltarBoost` (~L1224-1230) |
| Prefix/suffix routing separation | `src/Modules/CalcSetup.lua` `cloneWithAltarBoost` (~L1265-1266) |
| `specialAffixType` _0-first resolver | `src/Modules/CalcSetup.lua` `specialAffixType` (shared with `idol-refracted-weaver-enchant-boost`) |
| `IdolAltarPropertyID` enum reference | `LE_datamining/il2cpp_dump_v142/dump.cs` L240052-240070 |
| `IsAffectedByAffectOfStandardPrefixesOrSuffixes` reference | `LE_datamining/il2cpp_dump_v142/dump.cs` L151678 |
| Compound-suffix data fixture | `src/Data/ModItem_1_4.json` `837_0` "of Chitin" (sat=5) |

**Spec:** existing `idol-refracted-weaver-enchant-boost` spec
covers the positive sat=4/5 + property 4 routing; the negative
case (sat=5 must NOT receive property 1/2/3) is implied by the
`if/elseif` partition and is currently not asserted by a dedicated
spec. A defensive spec asserting
`cloneWithAltarBoost(weaverIdolWithProperty3Altar).suffixes[1].modScalar`
matches the un-boosted scalar would lock this gate explicitly —
deferred to the follow-up that lands the new spec alongside
oN2zWaYX snapshot stabilisation.

**Establishing commit:** (this commit) — inference close for the
G2 minion-stat drill Lane D (oN2zWaYX). See Obsidian
`LEB vs LETools stat 比較.md` "G2 canonical Minion-tab drift
drill (2026-05-16 closeout)" table row Lane D for the full case
record.

### `ward-regen-passive-vs-event-split`

Display Ward Regen (`pOut.WardPerSecond`) must equal the **passive**
sum only — base + `LifeRegenAppliesToWard` + `CurrentManaGainedAsWardPerSecond`
+ `MissingHealthGainedAsWardPerSecond`. The event-driven
`ManaSpentGainedAsWard` contribution must NOT be folded into the
display stat; it belongs only in the local `wps` value used for the
Ward / WardDecay inversion math.

Game ground truth:
- `ProtectionClass.Update` (RVA 0x234B8C0, LE_datamining
  `ward_decompile.txt`): the `wardRegen` field updated per tick is
  the SUM of passive sources only. `ManaSpentGainedAsWard` is applied
  via `GainWard(amount)` from the spell-cast event handler — it
  never participates in the displayed Ward Regen.
- LETools "Ward Regen" reads the same passive snapshot — that's why
  Sorcerer / Spellblade builds with non-zero ManaSpentGainedAsWard
  used to show large positive `LEB − LETools` deltas while LEB's
  display included the event contribution and LETools' did not.

Pre-fix evidence (post-reimport 119 G1-G6 canonical,
`.tmp/reimport119/stat_diff_table.md`): 7 builds accounted for
≈ 598 of the total Σ|Δ| on `WardPerSecond`:

| Build | LETools | LEB (pre-fix) | Δ |
|---|---:|---:|---:|
| QDxZjPX8 lv95 Sorcerer | 222 | 576.77 | +354.77 |
| BZ37dR2l lv100 Sorcerer | 104 | 209.46 | +105.46 |
| BgRrekOY lv82 Sorcerer | 101 | 143.16 | +42.16 |
| Bakbr2Ne lv86 Sorcerer | 41 | 75.05 | +34.04 |
| oR6qaLp4 lv80 Spellblade | 105 | 134.12 | +29.12 |
| Qdz2yXLk lv100 Warlock | 151 | 173.64 | +22.64 |
| o3Zlpkxd lv98 Necromancer | 25 | 35.01 | +10.01 |

| Site | File | What it does |
|---|---|---|
| Display = passive only | `src/Modules/CalcPerform.lua` ~L1448 (`do … end` block from L1418) | `pOut.WardPerSecond = passiveWardPerSecond`. `passiveWardPerSecond` = base + CurrentMana + MissingHealth contributions. |
| Event-driven in local wps | `src/Modules/CalcPerform.lua` ~L1449 | `local wps = passiveWardPerSecond + manaSpentContribution`. `wps` is used only by the Ward / WardDecay inversion math and NetWardRegen. |
| Breakdown split | `src/Modules/CalcPerform.lua` ~L1455-1474 | Breakdown surfaces passive total, then separately the event-driven mana-spent line + effective WPS including it. |
| Floor gate keys on passive | `src/Modules/CalcPerform.lua` ~L1495 | `if passiveWardPerSecond <= 0 then rawWardDecayPerSecond = m_max(..., 0.5)` — game-faithful (event-driven mana-spent doesn't suppress the 0.5 floor). |

**Spec:** `spec/System/TestWardRegenPassiveVsEventSplit_spec.lua`
asserts (1) the display assignment uses `passiveWardPerSecond`, not
the previous `baseWardPerSecond + totalContribution`; (2) the local
`wps` adds `manaSpentContribution` after the display assignment;
(3) the inline `@leb-regression-guard:ward-regen-passive-vs-event-split`
marker is present at the assignment site.

**Cross-refs:**
- `ward-regen-canonical-key-wardpersecond` — LETools label "Ward Regen"
  maps to LEB output key `WardPerSecond`, NOT `NetWardRegen` /
  `WardRegen`. This guard depends on that mapping being correct.
- `ward-regen-resource-conversion` — the three passive contributions
  (CurrentMana, MissingHealth, ManaSpent) and the breakdown surface
  remain at their post-offence fold-in site; this guard splits only
  the display vs inversion-math destination of each contribution.
- `ward-decay-floor-zero-passive` — the 0.5 floor is gated on
  `passiveWardPerSecond` (not full `wps`), matching the game floor
  gate which keys on `wardRegen + wardRegenFromStats <= 0`.
- Obsidian `Worktree Notes/determined-hawking-2a827c.md` →
  `2026-05-17 (post-merge) G1-G6 119 builds 全 re-import + 全 stat diff
  aggregate` section.

**Establishing commit:** (this commit)

**Post-fix residual analysis (2026-05-17, hawking worktree):** After
applying the split, 4 of 7 builds converged on `WardPerSecond`
(QDxZjPX8 / BgRrekOY / Bakbr2Ne / o3Zlpkxd). The remaining 3 still
drift, but the residuals are **LETools UI display-side omissions**
of other passive `wardRegenFromStats` contributors that LEB correctly
folds into the display per `ProtectionClass.Update`, not LEB bugs:

| Build | LEB WPS | LETools | Δ | Source (per DumpWardRegen) |
|---|---:|---:|---:|---|
| Qdz2yXLk lv100 Warlock | 173.644 | 151 | +22.64 | `CurrentManaGainedAsWardPerSecond=5` × Mana 434 / 100 (+21.7) + `LifeRegenAppliesToWard=4` × LifeRegen 23.6 / 100 (+0.94). `ManaSpentGainedAsWard` modDB is empty for this build — the fix had no effect because the drift never originated from event-driven ward. |
| oR6qaLp4 lv80 Spellblade | 127.5 | 105 | +22.5 | `CurrentManaGainedAsWardPerSecond=6` × Mana 375 / 100 = +22.5 (exact). `ManaSpentGainedAsWard=22%` is present but correctly routed only to local `wps`, not display. |
| BZ37dR2l lv100 Sorcerer | 101 | 104 | -3 | Smaller than +/-5%; mod-list inspection shows `Sunrise Pyramidal Altar of Depravity BASE=3 × Mult:EquippedHereticalIdol(0)=0` and an inactive `Apex of Thought BASE=87 cond:StandingOnGlyphOfDominion=nil`. LETools likely applies the altar bonus assuming a Heretical idol is equipped. |

Game-faithful per `ward_decompile.txt` L38-41 (`wardRegen +
wardRegenFromStats`): the `wardRegenFromStats` accumulator includes
ALL stat-derived passive ward sources, including
`CurrentManaGainedAsWardPerSecond` and `LifeRegenAppliesToWard`. The
LETools "Ward Regen" UI field renders only the static `Sum BASE
WardPerSecond` and omits these dynamic converters — the same UI
display-style mismatch family as `letools-armor-display-negative-on-shred-build`
below.

**Action:** No further LEB code change. The Lane A split is fully
closed; the 3 residuals are recorded here so future diff sweeps
don't re-investigate them. If a future LETools update starts
including the converters, these residuals will auto-converge.

**Post-fix residual analysis #2 (2026-05-18, hawking worktree):** A
fourth residual surfaced on `BgRrP5rr lv98 Paladin` after the Lane A
split shipped, but it is a different family from the 3 above. LEB
`WardPerSecond=3.712`, LETools `Ward Regen="4"`, Δ=−0.288. Per
`DumpWardRegen`:

```
Sum BASE WardPerSecond  = 0
LifeRegenAppliesToWard  = BASE 2 (Item:18 Throne of Ambition)
output.LifeRegen        = 185.6
```

Game-faithful per Lane A: passiveWPS = base + LifeRegenAppliesToWard
× LifeRegen / 100 = 0 + 2 × 185.6 / 100 = **3.712** (exact match,
no LEB bug). The Δ is purely a LETools UI display-rounding quirk:
unlike the sibling regen rows (`Health Regen="185.92"`, `Mana
Regen="13.95"`), the LETools planner renders "Ward Regen" as
integer-only — so the underlying 3.71x value is floored/rounded
to "4" in the JSON snapshot before serialization.

`scripts/letools-diff.js` already absorbs this class of noise via
`TOL_ABS = 0.5` (~L16, ~L191). The Python sibling `spec/tools/diff_letools.py`
was missing the same absolute-tolerance floor, so a sub-1.0 float
delta inflated to a fake 7.2% drift purely because percentage rises
unbounded for small denominators. Fixed in the establishing commit
of `diff-letools-abs-tolerance-floor`: a `TOL_ABS = 0.5` constant
mirroring the JS tool is applied alongside the existing percentage
threshold. This:

- Clears the BgRrP5rr WardPerSecond noise (|D|=0.288 ≤ 0.5).
- Does NOT mask the 3 Lane A residuals (Qdz2yXLk +22.64, oR6qaLp4
  +22.5, BZ37dR2l −3 are all far above 0.5).
- Does NOT mask the remaining BgRrP5rr drifts (CooldownRecovery
  |D|=1, PoisonResistTotal |D|=3 stay flagged).
- Matches LETools UI's own integer-display convention for stats
  like Ward Regen / Block Chance / Endurance.

| Build | LEB WPS | LETools | Δ | Family |
|---|---:|---:|---:|---|
| BgRrP5rr lv98 Paladin | 3.712 | 4 | −0.288 | LETools integer-display rounding (LifeRegenAppliesToWard=2 × LifeRegen=185.6 / 100, exact). Below TOL_ABS=0.5 noise floor in `spec/tools/diff_letools.py`. |

**Cross-ref:** `diff-letools-abs-tolerance-floor` — the comparison
floor in `spec/tools/diff_letools.py` that absorbs this class.

### `diff-letools-abs-tolerance-floor`

`spec/tools/diff_letools.py` (Python LEB↔LETools stat-diff tool) must
match the absolute-tolerance behavior of its JavaScript sibling
`scripts/letools-diff.js`. Both apply a `TOL_ABS = 0.5` floor on
`|LEB − LETools|` before percentage-threshold filtering, because
several LETools UI stat fields are integer-rounded for display
(Ward Regen, Block Chance, Endurance, …) while LEB stores the
underlying floats. Without the floor, sub-1.0 float diffs inflate
to fake double-digit percentage drifts on small-magnitude integer
stats, masking real drifts elsewhere by noise.

Game ground truth: LETools' planner serializes its rendered UI
strings, not raw engine floats. The "Ward Regen" Defense-tab field
renders `"4"` even when the underlying value is 3.71x — see
`spec/TestBuilds/1.4/BgRrP5rr lv98 Paladin.letools.json` Defense
tab where `Health Regen` renders `"185.92"` and `Mana Regen` renders
`"13.95"` (both 2-decimal) but `Ward Regen` renders `"4"` (integer
only) on the same build.

Pre-fix evidence:
- BgRrP5rr lv98 Paladin: LEB WardPerSecond=3.712 (exact: 2 × 185.6 /
  100 from Throne of Ambition LifeRegenAppliesToWard), LETools "4",
  Δ=−0.288, |D%|=7.2% (above default --threshold 2.0).

Post-fix: |D|=0.288 ≤ TOL_ABS=0.5 → row dropped → CooldownRecovery
and PoisonResistTotal remain the only flagged rows for BgRrP5rr.

| Site | File | What it does |
|---|---|---|
| TOL_ABS const | `spec/tools/diff_letools.py` ~L177 | `TOL_ABS = 0.5` with `@leb-regression-guard:diff-letools-abs-tolerance-floor` marker block documenting LETools integer-rounding and naming the JS sibling tool. |
| Filter check | `spec/tools/diff_letools.py` ~L210 | `if not args.all and abs(d) <= TOL_ABS: continue` (after the `pct <= threshold` check). `--all` bypasses both floors so the user can still inspect sub-floor rows when intentionally widening. |
| JS counterpart | `scripts/letools-diff.js` L15-16, L191 | `const TOL_ABS = 0.5` + `if (d <= TOL_ABS) return 'OK'`. The Python tool mirrors this exactly. |

**Spec:** `spec/System/TestDiffLetoolsAbsToleranceFloor_spec.lua`
(a busted-pinned synthetic asserting the Python tool's behavior is
self-consistent — see file).

**Cross-refs:**
- `ward-regen-passive-vs-event-split` post-fix residual #2 entry
  documenting BgRrP5rr as the originating triangulation case for
  this guard.

**Establishing commit:** (this commit)

### `letools-armor-display-negative-on-shred-build` (docs-only)

LETools' planner UI sometimes reports the player's own `Armor`
stat as a **negative** value on Rogue / Bladedancer builds that
stack `Chance to Shred Armor on Hit` affixes. Game-faithfully,
"Armor Shred" is an **offensive** ailment applied to enemies; it
must not subtract from the casting player's defensive armor. A
negative armor value is physically impossible in `ProtectionClass`
(min clamp at 0 — see `LE_datamining/il2cpp_dump_v142/dump.cs`
ProtectionClass enumeration), and LEB's `CalcDefence.lua` armor
chain never produces a negative output either.

The displayed-vs-reality gap is a **LETools UI artifact**, not a
LEB bug. This guard records the triangulation case so future
diff sweeps don't waste cycles on it.

**Triangulation case study** (QJWMRv53 lv98 Bladedancer,
2026-05-17 sweep, see `spec/TestBuilds/1.4/QJWMRv53 lv98 Bladedancer.lua`
post-fix snapshot):

| Stat | LETools display | LEB output | Notes |
|---|---:|---:|---|
| `Armor` | **-260** | 660 | LETools negative → impossible in game |
| `Armor Mitigation` | **-31%** | (n/a sign) | derived from negative armor |
| `FireResistTotal` | 90 | 114 | gap +24 = blessing 19 + Rogue-60 5 |
| `ColdResistTotal` | 104 | 128 | same +24 split |
| `LightningResistTotal` | 153 | 177 | same +24 split |
| `PhysicalResistTotal` | 107 | 131 | same +24 split |
| `VoidResistTotal` | 131 | 155 | same +24 split |
| `NecroticResistTotal` | 102 | 121 | gap +19 = blessing only |
| `PoisonResistTotal` | 79 | 98 | gap +19 = blessing only |

The resistance gap pattern is symmetric: LETools is missing
- `Grand Resolve of Humanity` blessing `+19% to All Resistances`
  (lands on Item:27 in the XML) → -19 on all 7 types, AND
- `Rogue-60 Grit` passive (`+1% All Resistances` per pt × 5 pts)
  → -5 on F/C/L/Phys/Void only (LETools' UI happens to not
  subtract this on Necrotic/Poison; the symmetric break is
  uninvestigated and out of scope — game-faithfully Grit applies
  to all 7).

LEB's `DumpResAll` (`spec/DumpResAll.lua`) confirms every
listed mod sums to LEB's reported total (e.g. Fire
16+12+19+11+11+29+5+6+5 = 114). The passive-tree data file
`src/TreeData/1_4/tree_4.json` `Rogue-60` "Grit" has
`"stats": ["+1% All Resistances", "+2% Endurance"]`,
`"maxPoints": 5` — game-faithful per source.

The Σ|Δ|=1270 outlier originally flagged in `SKILL_STATUS.md`
PENDING is therefore decomposed into:

1. ~+920 from the impossible-negative `Armor` display (LETools UI)
2. ~+155 from blessing + passive-node display omission (LETools UI)
3. ~+15 from Vit -5 / Int -5 residual (deferred — small magnitude)

| Site | File |
|---|---|
| Player armor floor (game) | `LE_datamining/il2cpp_dump_v142/dump.cs` ProtectionClass armor accumulation |
| Rogue-60 Grit definition | `src/TreeData/1_4/tree_4.json` node `Rogue-60` |
| LEB armor accumulation | `src/Modules/CalcDefence.lua` `output.Armour` chain |
| LEB resist accumulation | `src/Modules/CalcDefence.lua` per-element `*ResistTotal` |
| Dump script | `spec/DumpResAll.lua` |
| Diff tooling | `spec/tools/diff_letools.py` |

**Spec:** none — this is a docs-only guard. LEB's own armor /
resist calcs are locked by their respective specs
(`TestArmourFull_spec.lua`, `TestResistanceCaps_spec.lua` and
related). The guard exists so that the negative-armor display
pattern is recognised as a known LETools artifact when it
re-surfaces on other Rogue / Bladedancer builds.

**Establishing commit:** (this commit) — QJWMRv53 triangulation
closeout. See Obsidian `SKILL_STATUS.md` PENDING #4
"QJWMRv53 Bladedancer Armour/BlockEffectiveness outlier"
for the originating sweep context.

### `paladin-sentinel70-dedication-mana-regen`

Paladin tree node Sentinel-70 (Dedication) carries a `notScalingStat`
`"1% Increased Mana Regen Per 1% Block Chance Above 50%"` with
`noScalingPointThreshold: 5`. The cached parse in `src/Data/ModCache.lua`
splits the stat into a `PerStat:BlockChance` `ManaRegen` INC mod **plus a
leftover parser `extra = "   Above 50% "`**. `PassiveTree.lua:458` gates
mod insertion on `if mod.list and not mod.extra then`, so the entire mod
is silently dropped — Sentinel-70 contributes **0** to `ManaRegen` despite
being allocated past threshold.

LE applies the bonus on raw (uncapped) block chance, not the capped value.
For BgRrP5rr (BlockChanceTotal=92, BlockChance=75 after cap), the LE engine
yields `max(0, 92 - 50) = 42%` INC ManaRegen. The fix injects a clean INC
ManaRegen mod from `CalcDefence` after the block calc sets
`output.BlockChanceTotal` (~L353) and before the regen loop at ~L680 / the
`output.ManaRegenInc` sum at ~L1725 — both downstream sites pick up the
contribution from the same `modDB:Sum("INC", nil, "ManaRegen")` site.

Real-world hit: `BgRrP5rr` lv98 Paladin LETools snapshot shows
`manaRegen=13.95`; pre-fix LEB produced `10.5` (Δ=-24.7%). Post-fix:
INC=73 (was 31), `output.ManaRegen=13.8` (Δ<1%).

| Site | File | What it does |
|---|---|---|
| handler | `src/Modules/CalcDefence.lua` (~line 416) | After block calc, if `env.allocNodes["Sentinel-70"].alloc >= noScalingPointThreshold (5)`, NewMod `ManaRegen` INC = `max(0, output.BlockChanceTotal - 50)` |
| tree data | `src/TreeData/1_4/tree_2.json` (Sentinel-70) | `notScalingStats: ["1% Increased Mana Regen Per 1% Block Chance Above 50%"]`, `noScalingPointThreshold: 5` |

**Spec:** `spec/System/TestPaladinSentinel70DedicationManaRegen_spec.lua`
- "CalcDefence handler injects ManaRegen INC = max(0, BlockChanceTotal - 50) when Sentinel-70 alloc >= threshold"
- "Sentinel-70 below threshold contributes 0 to ManaRegen"
- "handler uses BlockChanceTotal (uncapped), not BlockChance (capped)"
- "tree_2.json Sentinel-70 retains notScalingStat with noScalingPointThreshold"

**Establishing commit:** (this commit) — BgRrP5rr Paladin ManaRegen 10.5→13.8 Δ<1%

## Layering vs canary strings


Canary strings (`@leb-canary v1 / id:leb-... / do-not-remove`) are file-level
markers that protect against entire modules being deleted or rewritten by a
mass refactor. Regression guards are block-level and protect specific
correctness invariants. Both should be present where they apply; they don't
substitute for each other.
