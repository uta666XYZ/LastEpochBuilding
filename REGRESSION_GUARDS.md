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

The two emissions are NOT redundant: StatThreshold and Multiplier are
two different lookup paths in `ModStore`. A future refactor that
consolidates them into one emission must keep both var names live.

| Site | File | What it does |
|---|---|---|
| emission | `src/Modules/CalcSetup.lua` (~line 953) | Emits `Multiplier:EquippedCorruptedIdol = idol` inside the existing `if idol > 0 then` block |

**Spec:** `spec/System/TestEquippedCorruptedIdolMultiplier_spec.lua`
- "emits Multiplier:EquippedCorruptedIdol with BASE type and the idol count"
- "emission sits inside the same `if idol > 0 then` block as CorruptedIdolItemsEquipped"
- "'+10 Mana per Equipped Corrupted Idol' parses to Multiplier:EquippedCorruptedIdol"

**Establishing build:** B7GrkJrK lv100 Lich/Reaper — equips Spire Altar
(corrupted Idol Altar) with T7 prefix `+10 Mana per Equipped Corrupted Idol`
plus 16 corrupted items in idol cells. Reaper-form Mana before fix:
LEB **1373** vs LE 1607.21 (Δ=-234). After emitting the multiplier:
LEB **1548** (Δ=-59, ~75% of the gap closed). The residual ~59 is a
separate unrelated issue: the Reliquary Nest unique relic
`+(40-60)% Non-Unique Idol Stat Multiplier` (uniques_1_4.json id 433) is
not yet recognised by ModParser and contributes 0; tracked separately.

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
count flows into `CorruptedIdolItemsEquipped` (StatThreshold) and the
sibling `Multiplier:EquippedCorruptedIdol` emission, inflating any
"+N <stat> per Equipped Corrupted Idol" affix.

The guard requires the counting loop to dedup by item identity (`item.id`
when present, else the table reference) before incrementing the `idol`
accumulator, so each physical corrupted idol contributes once regardless
of how many slot names reference it.

| Site | File | What it does |
|---|---|---|
| dedup | `src/Modules/CalcSetup.lua` (`countItem` closure inside the corrupted-counting `do` block) | Tracks `seenIdolItem[key]` and skips repeated keys so Idol N ↔ Omen Idol N pairs don't double-tally |

**Spec:** `spec/System/TestOmenIdolSlotDedup_spec.lua`
- "CalcSetup deduplicates corrupted idol items by identity inside the corrupted-counting block"
- "the dedup table is scoped to the corrupted-counting block (not leaked across loads)"
- "the same `seenIdolItem` set covers both the active items loop and the level-gated items loop"

**Establishing build:** B7GrkJrK lv100 Lich/Reaper — equips Spire Altar
with T7 corrupted prefix `+10 Mana per Equipped Corrupted Idol` AND has 2
corrupted idol items appearing in both `Idol N` and `Omen Idol N` slots
(item.id 21 → Idol 23 / Omen Idol 2; item.id 30 → Idol 25 / Omen Idol 3).
Pre-dedup: 16 corrupted-idol count → Reaper Mana = 1548 vs LETools breakdown
Idol-Altar-Sealed line of 134 (LETools-derived count = 14). Post-dedup:
14 corrupted-idol count → Mana = 1526 (matches the LETools 134 breakdown
line exactly). Sibling guard `equipped-corrupted-idol-multiplier` emits
the multiplier; this guard fixes the count source for it.

**Establishing commit:** `604eb9975`

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

**Establishing build:** `Qqwv73q2 lv62 Warlock` — Silver Grail relic
(LevelReq=68 > charLevel=62) is corrupted. Pre-fix `nonIdol` counter
returned 6 (threshold 7 not met → Shroud's +14 All Attributes affix not
applied → Vit/Str/Dex/Int/Att each LEB-vs-source delta = -14). Post-fix
`nonIdol = 7`, threshold met, all 5 attributes gain +14 from Shroud's
affix `1011_6` (T7, fixed value — `range`/`r` is meaningless for
fixed-value tiers; LETools T1-T7 are fixed 8/9/10/11/12/13/14, only
the primordial-only T8 has a `(19-21)` roll range).

**Why not just keep level-gated items in `items[]`?** Because their
non-conditional stats (resistances, damage, etc.) must NOT contribute
to active calc — that's the entire point of the `LevelReq` filter. The
parallel `_levelGatedAllItems` table preserves the equipped/inactive
distinction the game itself draws.

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

This caught us out 2026-05-08: an earlier version of this file claimed
`1011_6 @ range 221 → +11`, treating the byte as if it scaled the fixed
value. That implied LEB had a bug that didn't exist (LEB matches LETools
and game data at +14). Game-data verification:
`extracted/items/singleAffixes.json` affix id 1011 ships
T1-T7 = `8/9/10/11/12/13/14` (fixed) and T8 = `19-21` (range, primordial
only). `src/Data/ModItem_1_4.json` `1011_0..1011_6` are flat lines and
`1011_7` is the ranged line — so the data already encodes the
fixed/ranged split.

| Site | File | What it does |
|---|---|---|
| pass-through | `src/Modules/ItemTools.lua` `applyRange` (~line 206) | The `(min-max)` gsub is the ONLY mutation site; fixed lines fall through unchanged |

**Spec:** `spec/System/TestItemTools_spec.lua` —
`describe("applyRange leaves fixed-value tier text unchanged")`
- "affix 1011 T7 (fixed +14) ignores the range byte"
- "affix 1011 T8 (range 19-21) still interpolates as expected"
- "a generic fixed flat-value line is unaffected by range bytes"

**Why the guard:** any future patch tempted to "scale fixed values too"
(e.g. interpreting `r` as a sub-tier modifier, or chasing a phantom
`+11` reading) would break Shroud of Obscurity, every fixed-tier
corrupted attribute affix, and any unique whose mod data omits the
`(min-max)` pattern by design. The spec pins the no-op contract directly
so the regression has somewhere to fail loudly.

### `per-set-fractional-precision`

"per Complete Set" affixes scale with `Multiplier:CompleteSetCount` (the
number of complete sets equipped). LE quantizes the per-source rolled
value to **half-integer (0.5) steps**, multiplies by the set count, then
floors. LEB historically rounded the per-item rolled value to integer
first then multiplied — losing the `0.5×setCount` half-step contribution.

Empirical fit across two builds (2026-05-08), `+(2-5) to All Attributes
per Complete Set`:

| build | byte | numVal (precision=2, span=3.5) | × setCount | floor | LE |
|---|---|---|---|---|---|
| BxvJP3g1 lv99 Necromancer | 41 | 2.5 | × 3 = 7.5 | 7 ✓ | 7 |
| Qqwv73q2 lv62 Warlock | 203 | 4.5 | × 6 = 27.0 | 27 ✓ | 27 |

`precision=1` (old) → BxvJP3g1 gets `2×3=6` (Δ=-1). `precision=1000`
(intermediate, never shipped) → Qqwv73q2 gets `floor(4.388×6)=26`
(Δ=-1). Only `precision=2` (half-step) matches both data points.

LE precalc_data: BxvJP3g1 `{str:41, dex:11, int:43, att:11, vit:30}`,
Qqwv73q2 LETools display `{str:45, dex:43, int:66, att:47, vit:44}` —
LEB matched both after fix.

| Site | File | What it does |
|---|---|---|
| half-step | `src/Modules/ItemTools.lua` `applyRange` (`precision=2` bump for `per Complete Set` + Integer rounding) | applyRange emits half-integer values (e.g. 2.5, 4.5) instead of integer floor |
| tag the multiplier | `src/Modules/ModParser.lua` `["per complete set"]` | Adds `roundAfterMultiply=true` to the `Multiplier:CompleteSetCount` tag |
| floor after multiply | `src/Classes/ModStore.lua` `EvalMod` (Multiplier branch) | When tag.roundAfterMultiply is set, `value = m_floor(value × mult)` so the half-step × setCount lands on integer |

**Why the guard:** any future "simplify applyRange — round at the source"
refactor, or any change that drops the `roundAfterMultiply` tag from the
ModParser table-driven mapping, regresses BxvJP3g1 (and every Legends
Entwined wearer) by 1 per attribute per complete set. The fix is also
narrow on purpose:

- `+1 to All Skills per Complete Set` (no range, value=1) is unaffected:
  `floor(1×N) = N`.
- `+(2-5)% to All Resistances per Complete Set` is NOT yet covered —
  the `{rounding:Integer}` directive isn't on that line, so the
  precision bump is gated by `rounding == "Integer"`. LE behavior on
  the % line was not verified at fix time; revisit if a resistance Δ
  surfaces.
- byte=0 → `+2` exact and byte=255 → clamped to `+5` go through the old
  ModCache integer keys, but produce the same answer (`floor(N×M) = N×M`
  for integer N).

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
- "Pattern A: UNIQUE rarity skips affix-derived level req" — UNIQUE with same 4× T5 suffixes → req stays at 0 (see `legendary-affix-derived-levelreq` below)
- "Pattern A: LEGENDARY rarity skips affix-derived level req" — same, LEGENDARY → 0
- "Pattern A: SET rarity skips affix-derived level req" — same, SET → 0

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
(`src/Classes/Item.lua`):

```lua
if item.rarity == "UNIQUE" or item.rarity == "LEGENDARY" or item.rarity == "SET" then
    return nil
end
```

Returning `nil` makes both call sites (post-ParseRaw and `Craft()`) leave
`requirements.level` untouched, deferring entirely to the unique-req-level
override path (`unique-req-level-override` guard) or the base item's req.

**Establishing build:** `Qb6WlPE5 lv52 Lich` — Font of the Erased Ring 1
(corrupted Legendary, T7 corrupted minion-damage affix). Pre-fix LEB
computed `req.level=79` (sumInner 57 + outer 32 - 10) — both rings were
filtered out by CalcSetup's LevelReq filter, dropping the +22% Phys Res
suffix and producing `PhysicalResistTotal=40` (Helmet 30 + Boots 10) vs
LE's 62%. After this gate, rings are equipped at lv52 and PhysRes total
matches LE exactly.

**Specs:** `spec/System/TestItemParse_spec.lua`
- "Pattern A: UNIQUE rarity skips affix-derived level req"
- "Pattern A: LEGENDARY rarity skips affix-derived level req"
- "Pattern A: SET rarity skips affix-derived level req"

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
  `(10-24)% increased Health` and `(100-240)% increased Minion Health` were
  duplicated. Q9J4w8PE lv99 Necromancer registered +325 Health from the
  player-Health dup. Caught by DUP_LINE on exact-string equality.
- **Sunforged Greathelm (id=87, set entry 19)** — trailing
  `(25-35)% increased Armor` duplicated the leading mod. Lived in
  `set_1_4.json` (set-rarity entry merged into `data.uniques` by
  `Modules/Data.lua`) and in `uniques_1_2.json` / `uniques_1_3.json`.
  Surfaced via the new EXPECTED_COUNT invariant after DUP_LINE missed it
  (the "20-30" 1_2/1_3 vs "25-35" 1_4 wording diverged enough to slip
  exact-string equality on at least one rev).

The guarded invariants:

**DUP_LINE** — no exact-string mod line appears twice in a single unique's
`mods` array. The two real cases where it looks like a dup (Zeurial's Hunt
direction-pair, Raindance dual-MS in 1_2/1_3) both differ in text or range,
so exact-string equality is the correct equivalence.

**EXPECTED_COUNT** — hand-curated allow-list of uniques whose `mods` array
length has been audited at least once against the game data
(`uniques_v3.json`). Pinning the count means a future regen that re-introduces
upstream dups (e.g. the 2026-05-09 Aaron's Will +325 health regression where
mods drifted from 8 → 10) trips the spec instead of silently shifting
downstream snapshots. Add a new entry to the `expected` table whenever you
fix a unique whose row count was wrong. Currently pinned: Aaron's Will (8),
Sunforged Greathelm (4), Raindance (6), Legends Entwined (5), Zeurial's
Hunt (5).

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
| data | `src/Data/Uniques/uniques_1_3.json`, `uniques_1_2.json`, `uniques.json` | Older-version unique data; same DUP_LINE / EXPECTED_COUNT invariants |
| data | `src/Data/Set/set_1_4.json` | Set-rarity entries merged into `data.uniques` by `src/Modules/Data.lua` (~line 625); same invariants apply |
| upstream | `LE_datamining/extracted/unique_overrides.json` | Hand-curated overrides applied by `apply_leb_rules.py`. Bugs fixed here (2026-05-09: Aaron's Will, Sunforged Greathelm, Raindance, Legends Entwined, Zeurial's Hunt) prevent regen from re-introducing them downstream |

**Spec:** `spec/System/TestUniqueDataIntegrity_spec.lua`
- "no unique has duplicate mod lines (DUP_LINE)"
- "expected mod counts match game data (EXPECTED_COUNT)"

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
`output.ManaRegen = 0`:

```lua
if modDB:Flag(nil, "No"..resource.."Regen") or modDB:Flag(nil, "CannotGain"..resource) then
    output[resource.."Regen"] = 0
```

Concretely on QDxZPWM9 lv99 Sorcerer: the bug inflated Mana Regen by
~+87/s and pushed `ManaOnHit` (this unique grants `1 Mana per 12%
increased mana regen`) into a positive feedback loop. The matched LE
calculation correctly zeros mana regen and zeros that derived ManaOnHit.

| Site | File | What it does |
|---|---|---|
| pattern | `src/Modules/ModParser.lua` (~line 942) | `specialModList` entries for `^you do not regenerate mana$` and `^100%% disabled mana regen$` returning `flag("NoManaRegen")` |
| pre-cached entry | `src/Data/ModCache.lua` | Auto-generated `parseModCache` entry for `"100% Disabled Mana Regen"`; updated to the corrected `NoManaRegen` FLAG so historical cache hits don't bypass the new pattern (regenerated automatically by the next `SaveModCache` run) |
| consumer (already present) | `src/Modules/CalcDefence.lua` (~line 602) | `if modDB:Flag(nil, "NoManaRegen") then output.ManaRegen = 0` |

**Spec:** `spec/System/TestModParse_spec.lua`
- "'You do not Regenerate Mana' sets NoManaRegen flag"
- "'100% Disabled Mana Regen' (LEB JSON variant) sets NoManaRegen flag"

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
- `Q9J4wvmD` `OverkillLeech` LE=9 LEB=0

Fix: register the 4-word phrase in `modNameList`. `scan()` chooses the
earliest+longest match, so the new entry wins over `damage` and consumes
the whole right-hand side, leaving no suffix and no residual.

| Site | File | What it does |
|---|---|---|
| alias table | `src/Modules/ModParser.lua` (~line 165-178) | Registers `overkill damage leeched as health` → `OverkillLeech` |

**Spec:** `spec/System/TestOverkillLeech_spec.lua`
- "'11% of Overkill Damage Leeched as Health' parses to OverkillLeech BASE 11"
- "'5% of Overkill Damage Leeched as Health' parses to OverkillLeech BASE 5"
- "does not emit DamageLifeLeech for the overkill affix wording"

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
| LifeOnBlock / ManaOnBlock gate | `src/Modules/CalcDefence.lua` (~line 514, ~line 700) | Same gate also applies to "Health/Mana Gained on Block" — without it, Sentinel-89 Shield Wall's `+4 Health Gained on Block` per point bleeds into LEB even on no-shield Paladins (e.g. QDxZjL4J Δ +16 phantom) |

**Spec:** `spec/System/TestBlockShield_spec.lua`
- "BlockChance is 0 with no shield even with +50% Block Chance mod"
- "BlockChance applies with no shield when BlockWithoutShield flag is set"
- "LifeOnBlock / ManaOnBlock are 0 with no shield (block disabled)"
- "LifeOnBlock applies with no shield when BlockWithoutShield flag is set"

**Snapshot coverage:** `spec/System/TestBuilds_spec.lua` "test all builds #builds" via
`spec/TestBuilds/1.4/Bakbr2Ne lv86 Sorcerer.{xml,lua}` (Astrolabe off-hand, BlockChance=0)
and `QDxZjL4J lv97 Paladin.{xml,lua}` (dual-wield, LifeOnBlock=0).

**Establishing commit:** `df85f92e8` (block stats); `<branch>` (LifeOnBlock/ManaOnBlock extension)

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

The fix extends the existing `whileActiveBuffByTreeId` gate (introduced for
Flame Ward in `flame-ward-block-toggle`) with the four Form treeIds, mapping
each to its existing `Condition:In<X>Form` FLAG published from
`ConfigOptions.lua` L106-121. No new Config options were needed — only the
treeId → Condition wiring was missing.

**Game-data confirmation** (`<LE_datamining>/extracted/ability_keyed_array.json`):

| playerAbilityID (treeId) | abilityName | unityObjectName | class / mastery |
|---|---|---|---|
| `wb8fo` | Werebear Form | `WerebearForm` | Primalist / Druid |
| `sf5rd` | Spriggan Form | `SprigganForm` | Primalist / Druid |
| `sbf4m` | Swarmblade Form | `Swarmblade Form` | Primalist / Druid |
| `rf1azz` | Reaper Form | `ReaperForm` | Acolyte / Lich |

**Subtle pitfall:** the 4 Form skills DO have `SkillType.Buff` in
`skillTypeTags`. Splitting `buffSkillTreePrefixes` into "Buff branch / Cond
branch" with mutually-exclusive logic re-introduces the FlameWard-class
leak: the Form skill enters the Buff branch and bypasses the gate entirely.
The correct structure ANDs `condName` into `enabled` regardless of the Buff
branch, exactly as `flame-ward-block-toggle` documents.

**Default-OFF policy (Obsidian: `Test Build Suite.md` "Buff / Transform
スキルの ON/OFF デフォルト方針"):** while-active duration buffs (Form,
FlameWard, etc.) default OFF (gated by Condition); generic ever-on auras
(HolyAura, SymbolsOfHope, MarkForDeath) stay default ON since the LE engine
auto-maintains them in combat. Adding a new while-active duration buff
follows the same recipe: register its treeId in `whileActiveBuffByTreeId`
+ add a `conditionHave<X>` / `conditionIn<X>Form` Calcs checkbox.

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
   `SkillType.Transform` in the `flagToType` table. Form entries in
   `src/Data/skills.json` have `skillTypeTags = 0` plus
   `baseFlags.transform = true`, so without this mirror the Transform bit
   never reaches `activeSkill.skillTypes` and the cost-loop guard fires on a
   nil value (i.e. fails open and re-attributes Mana cost).
2. **`src/Modules/CalcOffence.lua`** tests
   `not activeSkill.skillTypes[SkillType.Transform]` to short-circuit the
   Mana/Rage/Soul/Life cost loop. Removing this AND-clause regresses the
   bypass even if (1) is intact.

This is a **separate mechanism** from `form-tree-nodes-gated-by-condition`:
- `form-tree-nodes-gated-by-condition` gates skill-tree NODE MODS behind a
  Calcs-tab Condition checkbox (controls whether the Form's tree-node
  bonuses leak into modDB while the checkbox is unchecked).
- `transform-cost-bypass` gates the SELF cost calculation of the Form
  skill itself (controls whether a phantom Mana cost shows up on the Form
  ability's Calcs panel regardless of checkbox state).

Both are required for clean LETools diffs on Druid/Lich Form builds.

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

### `s4-perstat-base-includes-converted-twin`

Sibling to `s4-converted-attr-no-base-inherit`. Both guards must hold
together: converted attributes (Brutality / Guile / Madness / Apathy /
Rampancy) do **not** inherit base-attribute intrinsic bonuses, **but**
text-parsed `Per <BaseAttr>` mods on passive nodes / item affixes
**do** count the converted twin alongside the base attribute. In
in-game terms: Strength's intrinsic +4% Armour does not double up onto
Brutality, but the Druid passive "1% Increased Armor Per Strength In
Human Or Spriggan" sees `Strength + Brutality` and a fully-converted
Druid (Str=0, Brutality=198) gets ~198% INC, not 0%.

Implementation splits the two semantics:

- The seven intrinsic bonuses registered programmatically in
  `calcs.initEnv` use `PerStat:Raw<Attr>` (RawStr / RawDex / RawInt /
  RawAtt / RawVit). `CalcPerform` mirrors `output.Raw<Attr> =
  output.<Attr>` after the Str→Brutality (etc.) subtraction so
  Raw<Attr> never includes the converted twin. → preserves
  `s4-converted-attr-no-base-inherit`.
- All other PerStat:<BaseAttr> mods (passive node / item affix text
  going through ModParser → ModCache) keep `tag.stat = "Str"` (Dex /
  Int / Att / Vit), and `ModStore:EvalMod` adds the converted twin's
  value at evaluation time via the module-scope lookup
  `s4ConvertedTwin = { Str="Brutality", Dex="Guile", Int="Madness",
  Att="Apathy", Vit="Rampancy" }`. Covers both the scalar `tag.stat`
  branch and the `tag.statList` branch.

Form OR-conditionals on Druid mastery nodes ("In Human Or Spriggan",
"In Bear Or Swarmblade") parse to a `Condition` tag with `varList`
covering the named forms — NAND for Human/Spriggan (negate against
the three transform forms), positive OR for Bear/Swarmblade. Cache
entries with unparsed leftover (e.g. `extra=" In Human Or Spriggan "`)
were silently dropped by `PassiveTree.lua` (`if not list then
node.unknown = true; elseif extra then node.extra = true ... if
mod.list and not mod.extra then`), so the cache rows must carry the
Condition tag with `extra=nil`.

A regression here:

- Drops the `s4ConvertedTwin` table or the `s4ConvertedTwin[tag.stat]`
  / `s4ConvertedTwin[stat]` lookups in `ModStore:EvalMod` → all
  "Per Strength" passives silently revert to 0% on fully-converted
  Druids (Qb6WlbxD Armour 1320 vs LE 3161, Δ-1841).
- Switches any of the seven `CalcSetup` intrinsics back to
  `PerStat:<liveAttr>` → Brutality/Guile/Apathy/Rampancy regrow the
  base-attribute bonuses and `s4-converted-attr-no-base-inherit`
  fails.
- Drops `output.Raw<Attr>` from `CalcPerform` → the intrinsic mods
  see 0 and the +4% Armour / +4 Evasion / etc. silently disappear.
- Re-introduces `extra=" In Human Or Spriggan "` on the ModCache row
  → PassiveTree drops the entire mod and Aspects of Might silently
  contributes 0%.

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

**Establishing build:** Qb6WlbxD lv100 Druid (Str=0 / Brutality=198 via
Exulis 100% Str→Brutality conversion). Pre-fix `output.Armour=1320` (LE
3161, Δ-1841). Post-fix `output.Armour=3110` (residual ≈ -1.6%, likely
unrelated body-armor display rounding). The `.tmp/dump_armour_full.sh`
trace shows `[10] INC Armour val=1 src=Tree:Primalist-111
tags={PerStat stat=Str}{Condition varList=... neg=true}` and
`Sum INC Armour = 244` (was 46, jumped by +198 = Brutality count).

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `exulis-all-attributes-range`

The unique amulet `Exulis` (id 469) rolls `+(10-20) to All Attributes`.

**Evidence:**
1. Game data extract `uniques_v3.json` id=469 mod[1] (property=46, All
   Attributes) has `value=10.0, maxValue=20.0`.
2. LETools tooltip displays `+(10 to 20) to All Attributes`.
3. `applyRange` trace with (10-20) reproduces the in-game LEB display
   when the rollIds bug below is also fixed: byte=193 (shared with
   Skills) → `floor((10 + 193/255*10) + 0.5) = floor(18.07) = 18`,
   matching LETools display for build AL07Kea4 (Spellblade lv97).

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

### `exulis-shared-rollid`

The unique amulet `Exulis` (id 469) has TWO rolled mods that share
the same `rollID=0` in the game data, meaning they read the same byte
in the imported `ur` array.

**Evidence:**
1. Game data extract `uniques_v3.json` id=469:
   - mod[0] `canRoll=true, rollID=0, property=88` (+(1-2) to Skills)
   - mod[1] `canRoll=true, rollID=0, property=46` (+(10-20) to All Attributes)
   Both share `rollID=0`.
2. LETools planner_data for build AL07Kea4 returns `ur=[193, 27, ...]`.
   With shared rollID=0 both mods read `ur[1]=193`:
   - Skills: `floor((1 + 193/255*1) + 0.5) = 2` (matches LE display +2)
   - All Attrs: `floor((10 + 193/255*10) + 0.5) = 18` (matches LE display +18)
3. Earlier extraction wrongly produced `rollIds: [0, 1, ...]`, making
   All Attributes read the unrelated `ur[2]=27` byte → +11 (off by 7
   from LE truth). This caused a uniform Δ=-7 gap on every attribute
   in AL07Kea4.

A regression here re-splits the rollIds. `rollIds[0]` and `rollIds[1]`
MUST both be `0`.

| Site | File | What it does |
|---|---|---|
| 1.4 unique data | `src/Data/Uniques/uniques_1_4.json` (Exulis entry, ~line 9400) | `rollIds: [0, 0, null, null, null, null, null]` |
| legacy unique data | `src/Data/Uniques/uniques.json` (Exulis id 469, ~line 10639) | `rollIds: [0, 0, null, null, null, null, null]` |

Both entries carry an inline `_leb_regression_guard: exulis-shared-rollid`
field documenting the source of truth at the data site itself.

**Spec:** `spec/System/TestExulisRange_spec.lua`
- "Data/Uniques/uniques_1_4.json has Exulis rollIds[0]==rollIds[1]==0"
- "Data/Uniques/uniques.json has Exulis rollIds[0]==rollIds[1]==0"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

Regression history this guard prevents:

- Hardcoding both ON  (commit `d19abfe34`, pre-2026-05-04) → +1..+2
  over-shoot for 0/2 and 1/2 builds.
- Hardcoding both OFF (2026-05-04 reaction to the above) → -1..-2
  under-shoot for 1/2 and 2/2 builds. Empirically: 36 of 38 G1
  ATTR_UNIFORM_OTHER builds showed uniform Δ=-2 across every
  attribute, and all 36 had `{124, 151} ⊂ completedQuests`.

The numeric quest IDs are stable across the planner API JSON, the
LETools DOM `quest-id` attribute, and the in-app save-file quest IDs.

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

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

Shapes covered:
- **A1**: `<Src> -> <Dst> Damage`
- **A2**: `<Src> Damage -> <Dst> Damage`
- **A3**: `<Src> -> <Dst> Conversion` suffix
- **A4**: bare `<Dst> Conversion`
- **A5**: multi-source AND-join `<Src1> and <Src2> -> <Dst> Damage` (svz81-23 Horrific Vessels)
- **A6**: multi-source AND-join `... -> <Dst> Conversion` suffix
- **A7**: `<Delivery> Base Damage -> <Dst>` (bg36nl-7 Pyre Golem)
- **A8b**: bare `<Src> -> <Dst>` no-Damage suffix (fw3d-10 Lightning Ward)
- **A12**: modifier-only `Increased <Src> Damage -> <Dst> Damage` (ds4d3-32 Vile Ghast — promotes destination as scaling tag without removing source)
- **A13**: `<X> -> Elemental Damage` filtered out — Oil Coating cstri-22 is a buff modifier, not a skill-damage conversion
- **B1**: `Enables <Type> Nova` addition (en6 Elemental Nova)
- **D-prose / source removal**: unconditional `<Skill> loses its {X} tag` triggers Q3=(a) full-conversion source removal. Conditional `if ...` lines (sw1 Swipe, srk21-25 Shurikens) are skipped — partial-state aware removal is intentionally not handled

**Spec:** `spec/System/TestStcdtParser_spec.lua`
- "getActiveStcdtBits #stcdt" (17 cases — one per shape + filter / treeId guards)

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
loop generalises that fix.

| Site | File |
|---|---|
| Bucket loop + sumMinion helper | `src/Modules/CalcDefence.lua` (~line 1525, `do … local minionMods = {}`) |

**Spec:** `spec/System/TestPhase4LEToolsParity_spec.lua`
- "Minion bucket aggregates MinionModifier LIST entries by (name,type)"
- "Phase 4 outputs default to 0 with no mods (no character base leak)"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

ModCache.lua holds parser results keyed by mod string, so a fresh regen
without `LEB_FORCE=1` may still load the stale `LEB_NotSupported` cache
entry. The spec exercises the parser directly via `customMods`, so it
catches the regression even when the cache hides it from build snapshots.

| Site | File | What it does |
|---|---|---|
| specific patterns | `src/Modules/ModParser.lua` (~line 1750-1758) | "from crits$" → `ReduceCritExtraDamage`, must precede "from (.+)$" `nsAny` |
| catch-all | `src/Modules/ModParser.lua` (~line 1764-1765) | "from (.+)$" → `nsAny` (only kept for unknown crit-source variants) |

**Spec:** `spec/System/TestModParse_spec.lua`
- "crits abbreviation reduces crit damage"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
2. `PassiveTree.lua:421-423` checks `if extra then node.extra = true`
   and SKIPS adding the mods to `node.modList`.
3. The +15 to all seven resists silently disappears from `modDB`.

Symptom on B4Xq8aG6 lv95 Paladin: every resist shows roughly Δ-10 vs
LETools precalc, with no Tree:Sentinel-90 entry in any resist breakdown.

`Data/ModCache.lua` caches the parsed result keyed by raw text, so after
fixing `modTagList` the stale entry must also be removed (the affected
line was `c["+15% All Resistances With A Shield"]={…,"  With A Shield "}`).
The spec exercises `customMods` directly so the parser path is verified
even if the cache later regrows.

| Site | File | What it does |
|---|---|---|
| condition mapping | `src/Modules/ModParser.lua` (~line 619-628) | Adds `["with a shield"] = { tag = Condition UsingShield }` next to "while using a shield" |
| cache invalidation | `src/Data/ModCache.lua` | Removed stale `c["+15% All Resistances With A Shield"]` entry so it re-parses with the new tag |
| consumer | `src/Classes/PassiveTree.lua:421-423` | Drops the entire mod when `extra` is non-nil (this is the silent failure mode) |

**Spec:** `spec/System/TestModParse_spec.lua`
- "with a shield condition tag"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
`c["+50 Armor While With A Shield"]={…,"  While With A Shield "}` — patched
in place to add the `Condition: UsingShield` tag and clear the residual.

| Site | File | What it does |
|---|---|---|
| condition mapping | `src/Modules/ModParser.lua` (~line 629) | Adds `["while with a shield"] = { tag = Condition UsingShield }` next to "with a shield" |
| cache fix         | `src/Data/ModCache.lua` (~line 8061)    | `+50 Armor While With A Shield` entry now carries the UsingShield tag with nil residual |
| consumer          | `src/Classes/PassiveTree.lua:421-423`   | Drops the entire mod when `extra` is non-nil (silent failure mode) |

**Spec:** `spec/System/TestModParse_spec.lua`
- "while with a shield condition tag"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

The injection pattern mirrors the existing `Multiplier:ActiveSymbol` logic
for Symbols of Hope a few lines above.

Symptom on AVa9YEkg lv95 Paladin: Block Effectiveness Δ ≈ -401 vs LETools
with no Unbroken Charge contribution in the BlockEffectiveness breakdown.

`Data/ModCache.lua` cached `c["+21 Block Effectiveness per 1% Increased
Movement Speed"]` and `c["0.2% Increased Damage per 1% Increased Movement
Speed"]` with bad residuals — both patched in place.

| Site | File | What it does |
|---|---|---|
| matcher          | `src/Modules/ModParser.lua` (~line 636)              | `["per 1%% increased movement speed"] = { tag = Multiplier MovementSpeedInc }` |
| auto-injection   | `src/Modules/CalcSetup.lua` (~line 1539)             | Sums `INC` `MovementSpeed`, then `NewMod("Multiplier:MovementSpeedInc", "BASE", msInc)` |
| cache fix        | `src/Data/ModCache.lua` (~lines 4944, 10236)         | Both cached entries now carry the Multiplier tag with nil residual |
| consumer         | `src/Classes/PassiveTree.lua:421-423` / mod resolve | Drops the entire mod when `extra` is non-nil; Multiplier resolves at calc time |

**Spec:** `spec/System/TestModParse_spec.lua`
- "per 1% increased movement speed multiplier"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
**two underlying mods**. When importing/transcribing such uniques into
`uniques_<ver>.json`, list BOTH the player and minion variants. Do not
collapse them to a single line.

| Site | File | What it does |
|---|---|---|
| unique data | `src/Data/Uniques/uniques_1_4.json` (id `"21"`) | Lists both `"20% increased Movement Speed"` (player) and `"20% increased Minion Movement Speed"` (minion) with parallel `null` rollIds |

**Spec:** `spec/System/TestEterraPathPlayerMS_spec.lua`
- "uniques_1_4.json Eterra's Path has BOTH player and minion 20% MS mods"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `you-and-minions-dual-mods`

The Eterra's Path bug is one instance of a wider data class. Any LE unique
whose tooltip uses the wording **"for You and your Minions"** or **"You and
your minions have ..."** is backed by TWO mods in the underlying data
(tags=0 player + tags=8192 minion). LEB's `ModParser` does NOT have a
generic handler for the "for You and your Minions" suffix — leaving the
collapsed tooltip text as a single line in `uniques_<ver>.json` silently
parses as MinionModifier-only and drops the player side.

Confirmed affected uniques (game extract `extracted/items/uniques_v3.json`):

| id | Name | Stats with dropped player side |
|---|---|---|
| 21  | Eterra's Path     | 20% increased Movement Speed (fixed: see `eterras-path-player-ms`) |
| 66  | Hollow Finger     | +(7-13)% Cold Resistance, +(7-13)% Physical Resistance (both pairs) |
| 461 | Ash Wake          | +(50-90)% Chance to Ignite on Hit |
| 463 | Rahyeh's Embrace  | (30-44)% increased Health |

When transcribing such uniques into `uniques_<ver>.json`, list BOTH the
player and minion variants as separate mod text lines. Never use the
collapsed "for You and your Minions" wording — it loses the player mod.

| Site | File | What it does |
|---|---|---|
| unique data | `src/Data/Uniques/uniques_1_4.json` (ids `"66"`, `"461"`, `"463"`) | Player mod and `Minion <stat>` mod listed as separate entries with parallel rollIds |

**Spec:** `spec/System/TestYouAndMinionsDualMods_spec.lua`
- "Hollow Finger (id 66) carries BOTH player and minion Cold/Phys resist"
- "Ash Wake (id 461) splits Ignite-on-hit into player and minion mods"
- "Rahyeh's Embrace (id 463) splits increased Health into player and minion mods"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
after this fix the snapshot matches at 61%.

| Site | File | What it does |
|---|---|---|
| calc | `src/Modules/CalcDefence.lua` (output.MovementSpeedMod) | Formula expanded to `(1 + (BASE + INC)/100) * More`; BASE read via `modDB:Sum("BASE", nil, "MovementSpeed")` |

**Spec:** `spec/System/TestMovementSpeedBaseAdditive_spec.lua`
- "CalcDefence Movement Speed line includes BASE"
- "plain calcLib.mod is no longer used for the Movement Speed slot"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
240% Increased` from 10 active symbols (`20 × 1.20 SymbolsOfHopeEffect ×
10`); pre-fix LEB rendered the contribution as MORE 200%, producing
`baseRegen × (1 + globalInc) × 3.0 ≈ 453` instead of `~295`.

| Site | File | What it does |
|---|---|---|
| auto-injection | `src/Modules/CalcSetup.lua` (~line 1559) | `LifeRegen INC perSymbolPct × (1 + SymbolsOfHopeEffect/100)`, gated on `Multiplier:ActiveSymbol` |

**Spec:** `spec/System/TestSymbolsOfHope_spec.lua`
- "per-symbol value defaults to 20% INC and scales with SymbolsOfHopeEffect"
- "Meditation node doubles per-symbol value to 40"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `sentinel-95-base-health-regen`

Paladin tree node Sentinel-95 (Covenant of Protection) grants
`+6 Health Regen` per allocated point in addition to its armor stats.
The LE node's internal name in
`LE_datamining/extracted/items/globalTreeData.json` is
`Paladin Armor Health Regen And Armor Applies To DoT`, which explicitly
includes the Health Regen line.

Pre-fix `tree_2.json` (1_4) listed only `8% Increased Armor` and
`2% Armor Mitigation Applies To Damage Over Time` in `stats`, so 5
allocated points dropped `+30 BASE Health Regen` entirely. QDxZjL4J
Paladin's LETools snapshot shows `+30 BASE Health Regen` from this node.

| Site | File | What it does |
|---|---|---|
| tree data | `src/TreeData/1_4/tree_2.json` (Sentinel-95) | `stats` array contains `+6 Health Regen` |

**Spec:** `spec/System/TestSentinel95Regen_spec.lua`
- "tree_2.json Sentinel-95 stats include '+6 Health Regen'"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

QDxZjL4J Paladin's LETools snapshot shows `manaRegen=18.32`; pre-fix LEB
showed `10.8` (Δ=-7.52). The Sentinel-93 bug accounts for ~30% INC of that
gap; remaining residual is tracked separately.

| Site | File | What it does |
|---|---|---|
| injection | `src/Modules/CalcSetup.lua` (~line 1576) | When Holy Aura enabled and Sentinel-93 ≥5pts, NewMod ManaRegen INC scaled by HolyAuraEffect |

**Spec:** `spec/System/TestSentinel93ManaRegen_spec.lua`
- "Sentinel-93 25% scales by HolyAuraEffect and surfaces as INC ManaRegen"
- "tree_2.json Sentinel-93 retains '25% Increased Mana Regen From Holy Aura' notScalingStat"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
produces 64.5 here and surfaces as `ManaRegen=18.4` instead of the
LETools-expected `18.32`.

The fix instead emits an intermediate BASE stat
`ManaRegenIncPerUncappedLightningRes_Per2` from ModParser, which CalcDefence
reads after the resist totals are computed (line ~262, between resist loop
end and Block computation), floors `LightningResistTotal / 2`, and injects
the resulting `ManaRegen` INC mod via `modDB:NewMod`. This mirrors the
established Sentinel Defiance pattern (`EnduranceThresholdPerUncappedEleRes`).

QDxZjL4J Paladin: pre-fix `ManaRegen=13.2 / Inc=65`; post-fix `18.3 / 129`.

| Site | File | What it does |
|---|---|---|
| data    | `src/Data/Uniques/uniques.json`,  `uniques_1_2.json`, `uniques_1_3.json`, `uniques_1_4.json` | Adds the missing mod line + roll-id null on Urzil's Pride |
| parser  | `src/Modules/ModParser.lua` (~line 897)            | Pattern emits `ManaRegenIncPerUncappedLightningRes_Per2` BASE |
| inject  | `src/Modules/CalcDefence.lua` (~line 262)          | Reads stat, floors div by 2, NewMod ManaRegen INC scaled by `LightningResistTotal` |

**Spec:** `spec/System/TestUrzilsPrideManaRegen_spec.lua`
- "Urzil's Pride floors mana regen INC per 2% uncapped lightning resistance"
- "Urzil's Pride mod parses to BASE ManaRegenIncPerUncappedLightningRes_Per2"
- "uniques_1_4.json Urzil's Pride retains the per-uncapped-lightning-res mod line"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
+15% Elemental + +15% Poison Resistance per point):

| Stat | LE | LEB | Δ |
|---|---|---|---|
| FireResist   | 56  | 101 | +45 |
| ColdResist   | 80  | 125 | +45 |
| LightResist  | 179 | 224 | +45 |
| PoisonResist | 1   | 46  | +45 |

| Site | File | What it does |
|---|---|---|
| gate | `src/Modules/CalcSetup.lua` (~line 1432, `whileActiveBuffByTreeId`) | Adds `["eb5656"] = "HaveEterrasBlessing"` next to Flame Ward / Werebear etc |

**Spec:** `spec/System/TestEterrasBlessingBuffGating_spec.lua`
- "CalcSetup whileActiveBuffByTreeId maps eb5656 to HaveEterrasBlessing"

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `quest-apophis-majasa-plus-one`

**Protects:** the magnitude of the "Apophis and Majasa?" quest reward AND
the "Temple of Eterra?" quest reward. Each grants `+1 to all 5 attributes`
(Str/Dex/Int/Att/Vit). Confirmed via the in-game Completed Quests panel
screenshot 2026-05-08, which shows `Attribute Points: 1` on each row for
Apophis and Majasa (Ch. 9) and Temple of Eterra (Ch. 10), with the panel
total reading `2/2` when both quests are complete.

Regression history this guard prevents:

- 2026-05-07 commit `f820d0c63` removed the +1 from Temple of Eterra under
  the (incorrect) assumption that only Apophis grants the bonus. Under-shot
  attributes by 1 on every 2/2 build.
- 2026-05-08 commit `810eafe2f` doubled Apophis to +2 to compensate for the
  missing Eterra bonus. Over-shot 1/2 (Apophis-only, Eterra-not-yet) builds
  by 1, and was internally inconsistent because the Vitality breakdown
  screenshot it cited had been taken on a 2/2 character.

The correct model: `Apophis +1` AND `Eterra +1`, never `+2/0` or `0/+2`.
Quest order is Apophis (Ch. 9) → Eterra (Ch. 10), so `Apophis 0 / Eterra +N`
is unreachable in-game.

| Site | File | What it does |
|---|---|---|
| config | `src/Modules/ConfigOptions.lua` (`questApophisMajasa`) | Adds +1 BASE to each of Str/Dex/Int/Att/Vit |
| config | `src/Modules/ConfigOptions.lua` (`questTempleOfEterra`) | Adds +1 BASE to each of Str/Dex/Int/Att/Vit |

**Spec:** `spec/System/TestQuestApophisMajasa_spec.lua`
- "QuestApophisMajasa applies +1 BASE to all five attributes"
- "QuestTempleOfEterra applies +1 BASE to all five attributes"

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `humble-idol-scalar-scale-first`

**Protects:** `itemLib.applyRange` in `src/Modules/ItemTools.lua` — the
scale-first branch for idol-size scaling (`valueScalar < 1.0`).

LE scales an affix on a smaller idol by rounding the canonical endpoints
to integers first, THEN interpolating within the scaled span. The general
`applyRange` path interpolates first then scales, which under-rounds for
small scalars.

Evidence (AL07Kea4 Spellblade, Humble Weaver Idols, scalar 0.38, line
`+(3-7) Vitality`):

| Idol id | byte | interpolate-first | scale-first | LE truth |
|---------|------|-------------------|-------------|----------|
| 12      | 221  | (3+221/255·5)·0.38 = 2.79 → **+2** | round(1.14)=1, round(2.66)=3; 1+221/255·3 = 3.60 → **+3** | **+3** |
| 15      | 98   | (3+98/255·5)·0.38 = 1.87 → **+1**  | 1+98/255·3 = 2.15 → **+2**                                | **+2** |

Discriminator: `not useRound and valueScalar < 1.0`. Scalars `>= 1.0`
(uniques like Apiarist's Suit at 1.5) keep the existing interpolate-first
path — see the sibling guard `apiarist-scalar-interpolate-first`.

**Sites:**

| layer | path | role |
|-------|------|------|
| code  | `src/Modules/ItemTools.lua` (`applyRange`) | The scale-first branch |
| spec  | `spec/System/TestItemTools_spec.lua` | applyRange parametric tests |

**Spec:** `spec/System/TestItemTools_spec.lua`
- `tests applyRange('+(3-7) Vitality', 221.00, 0.38)` → `+3 Vitality`
- `tests applyRange('+(3-7) Vitality', 98.00, 0.38)` → `+2 Vitality`

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `apiarist-scalar-interpolate-first`

**Protects:** `itemLib.applyRange` — the >=1.0 valueScalar path that
interpolates first then scales (the original behavior; promoted to a named
guard alongside `humble-idol-scalar-scale-first`).

Apiarist's Suit unique (`scalar 1.5`) Strength `+(11-13)` at byte 57:

| approach | calculation | result | LE truth |
|----------|-------------|--------|----------|
| interpolate-first | (11 + 57/255·3)·1.5 = 17.51 → floor | **+17** | **+17** |
| scale-first       | round(16.5)=16, round(19.5)=19; 16 + 57/255·4 = 16.89 → floor | +16 | (wrong) |

Phys Resistance scaling (1.17, e.g. ShutFackUp Cursed Coin) takes the
existing `% Physical Resistance` `skipSpanBump` branch in the same `>=1.0`
path; that guard is `applyrange-fixed-tier-noop`-adjacent and described
inline in `applyRange`.

**Spec:** `spec/System/TestItemTools_spec.lua`
- `tests applyRange('+(11-13) to Strength', 57.00, 1.50)` → `+17 to Strength`

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `body_armor-banker-rounding`

> **Type: JSON-comment-incompatible.** The protected sites live in
> `src/Data/ModItem_1_4.json`, which cannot carry inline
> `@leb-regression-guard:` markers (JSON has no comments). The 3-layer
> contract is preserved by the spec + this index entry; any new JSON
> mass-edit tool MUST reference this guard id in its commit message.
> See "JSON-comment-incompatible guards" at the bottom of this file.

**Protects:** the `body_armor` `slotOverride` min/max values for every affix
that has a body_armor variant in `ModItem_1_4.json`.

In LE, body_armor multiplies the canonical affix base roll by `(1 + affixEffectModifier)`
where `affixEffectModifier = 0.5` for body_armor (verified against
`equipmentItems.json` `BaseTypeName: "Body Armor"`, baseTypeID 1) — i.e. **×1.5**.
The result is rounded with **banker's rounding (round half to even)**, not
half-up. LEB previously stored pre-multiplied values with half-up rounding,
producing min OR max values one higher than the in-game tooltip on every
`.5`-boundary tier.

Originally noticed on Vitality T5 (`505_4` displayed as 11–12, in-game 10–12);
expanded to all body_armor slotOverrides via `.tmp/audit_body_armor_rounding.py`.
The audit found exactly 22 mismatches, all off-by-1 in the half-up direction.

**Patched affixes (22 entries across 9 affix IDs):**

| affixId | Name | Tiers patched (LEB internal) |
|---|---|---|
| 8   | Dodge Rating       | T1, T6 |
| 25  | Health             | T0 |
| 31  | Armor (flat)       | T1, T2 |
| 34  | Mana               | T1, T3, T6 |
| 382 | Ward per Second    | T6 |
| 501 | Strength           | T2, T4, T5 |
| 502 | Intelligence       | T2, T4, T5 |
| 503 | Dexterity          | T2, T4, T5 |
| 504 | Attunement         | T2, T4, T5 |
| 505 | Vitality           | T2, T4, T5 |

Worked example (Strength T4): canonical base 7–8 → ×1.5 = 10.5–12.0 →
banker round = **10–12** (LEB previously stored 11–12; half-up would round
10.5 up to 11).

| Site | File | What it does |
|---|---|---|
| data | `src/Data/ModItem_1_4.json` (22 entries listed above, body_armor.`"1"`) | Carries the banker-rounded min/max values |
| audit | `.tmp/audit_body_armor_rounding.py` | Reproducible enumerator: parses ModItem, joins canonical tiers, asserts banker(base×1.5) == stored within ±1 |
| canonical | `LE_datamining/extracted/items/single_affixes_v3.json` `tiers[].minRoll/maxRoll` | Source of canonical base; not in repo |
| canonical | `LE_datamining/extracted/items/equipmentItems.json` `BaseTypeName=Body Armor` `affixEffectModifier=0.5` | Source of the ×1.5 multiplier |

**Spec:** `spec/System/TestBodyArmorBankerRounding_spec.lua`
- Asserts representative keys across all 9 affix IDs match banker(base×1.5),
  with explicit "(was X) → (now Y)" pairs locked in.

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `slot-banker-rounding`

> **Type: JSON-comment-incompatible.** Sister guard to
> `body_armor-banker-rounding`; same rationale and 3-layer contract apply.

**Protects:** the `amulet`/`shield`/`catalyst` `slotOverride` min/max values
in `src/Data/ModItem_1_4.json`. Each of these slots has
`affixEffectModifier = 0.17` (verified against `equipmentItems.json`
`BaseTypeName="Amulet"`/`"Shield"`/`"Catalyst"`) → **×1.17**, rounded with
**banker's rounding** (same as body_armor).

LEB previously stored five entries with half-up rounding, producing min OR
max one higher than the in-game tooltip on `.5`-boundary tiers. Discovered
by extending the body_armor audit; reproducible via
`.tmp/audit_slot_rounding.py`.

Game-file evidence: `AscendingValueAfterPropertyRounding` (RVA 0x2307CC0)
decompile in `LE_datamining/extracted/rounding_decompile_raw.txt` — the
slot-scalar × base integer-rounding step happens upstream in affix data
prep; this guard locks the empirically banker-rounded values to match
the existing 22-row body_armor case set.

**Patched affixes (5 entries):**

| affixId | Name | Slot | Tier | Base | banker(×1.17) | was |
|---|---|---|---|---|---|---|
| 8  | Dodge Rating    | amulet   | T3 | 50–65 | 58–76 | 59–76 |
| 8  | Dodge Rating    | catalyst | T3 | 50–65 | 58–76 | 59–76 |
| 34 | Mana            | amulet   | T4 | 36–50 | 42–58 | 42–59 |
| 34 | Mana            | catalyst | T4 | 36–50 | 42–58 | 42–59 |
| 88 | Throwing Damage | amulet   | T7 | 50–65 | 58–76 | 59–76 |

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

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `block-chance-total-no-shield-zero`

`output.BlockChanceTotal` is the **uncapped** pre-cap total used by both the
LETools cross-build diff (`scripts/letools-diff.js` `'block chance' →
BlockChanceTotal`) and the Calcs detail panel. The shield-equipped branch in
`CalcDefence.lua` writes it via `output.BlockChanceTotal = totalBlockChance`,
but the no-shield branch historically only zeroed `BlockChance` and friends.
With `BlockChanceTotal` left nil, `letools-diff.js status()` flagged 62/68
shield-less G1 builds as "?" (LEB value missing), burying the entire
no-shield majority of the cross-build coverage.

The fix is one line: `output.BlockChanceTotal = 0` next to `output.BlockChance
= 0` inside the `if not hasShield and not blockAllowedWithoutShield then`
branch. Removing it silently regresses the diff to "?" for 62 builds — no Lua
error fires.

| Site | File | What it does |
|---|---|---|
| no-shield zero  | `src/Modules/CalcDefence.lua` (~line 294) | `output.BlockChanceTotal = 0` alongside `BlockChance = 0` |
| shield-equip set | `src/Modules/CalcDefence.lua` (~line 335) | `output.BlockChanceTotal = totalBlockChance` (uncapped) |
| diff mapping    | `scripts/letools-diff.js` (~line 86) | `'block chance' → BlockChanceTotal` |

**Spec:** `spec/System/TestBlockShield_spec.lua`
- "BlockChanceTotal is 0 (not nil) with no shield"

**Snapshot coverage:** `spec/System/TestBuilds_spec.lua` "test all builds
#builds" — 62 of 68 G1 builds have no shield and would surface
`BlockChanceTotal = 0` in the .lua snapshot. Reverting the no-shield zero
makes these snapshots drop the field entirely (Lua serializer omits nil),
which the diff then re-flags as "?".

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
second" rate. `output.WardPerSecond` is set by `src/Modules/CalcPerform.lua`
(~line 1283 stat-loop and ~line 1308 Sanguine Runestones bonus) and consumed
by `src/Modules/CalcDefence.lua` to drive ward calculations. `NetWardRegen`
is a derived presentation field (gross − rawWardDecayPerSecond) — it does
NOT correspond to the game's "Ward per Second" stat and using it as the diff
target produces phantom diffs equal to the per-build decay rate.

| Site | File | What it does |
|---|---|---|
| diff mapping | `scripts/letools-diff.js` (~line 86) | `'ward regen' → key: 'WardPerSecond'` (with inline guard comment) |
| compute     | `src/Modules/CalcPerform.lua` (~line 1283, ~line 1308) | Writes `output.WardPerSecond` (base + INC/MORE; Sanguine Runestones bonus) |
| consume     | `src/Modules/CalcDefence.lua` (~line 415, ~line 690) | Reads `output.WardPerSecond` for ward / `NetWardRegen` derivation |

**Spec coverage:** Diff/snapshot layer is the primary lock — reverting the
mapping to `WardRegen` re-flags ~57 G1 builds as "?" (LEB has no
`output.WardRegen` key). Reverting it to `NetWardRegen` introduces non-zero
Δ on every ward-using build proportional to that build's decay rate.

> **Type: JSON-comment-incompatible (JS).** The inline guard comment lives in
> `scripts/letools-diff.js` directly above the `'ward regen'` MAP entry.
> Source of truth for the canonical name: the `ui_localization.json` quoted
> above, sourced from the LE_datamining workspace.

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
```

Per-source LETools tooltip values match `round(stored_float)` exactly:
- Body Armor mod stored 16.83 → LETools "Body Armor (Suffix): +17%"
- BgRrP5rr Necropolis Robes 30.14 → "+30%", Apostate's 21.89 → "+22%"
- Cleric's Eterran Idol 6.7 → "+7%", Weaver Idol 0.8 → "+1%"

Total tooltips match `round(sum_of_floats)`:
- Qdz2yM9k: stored sum 16.83 → "Physical Resistance: 17%" (LEB: 16 ✗)
- BgRrP5rr: stored sum 131.53 → "Physical Resistance: 132%" (LEB: 131 ✗)

Replacing `math.modf` with `math.floor(v + 0.5)` reproduces both. Verified
across 7 G1 builds with phys-resist Δ=-1 (`AL07RL31`, `BgRrP5rr`,
`BOwJnY3Y`, `BZ37WdmV`, `Q9J4wvmD`, `Qdz2yM9k`, `Qqwv6zGN`). The loop
iterates all 7 resist types so the same off-by-one applied across
phys/fire/cold/light/void/poison/necrotic (~345 DIFF lines in
`.tmp/diff-after-g1-reimport.log` pre-fix).

`min` / `max` / `totemMax` come from data integers so round-half-up and
floor agree; updated for symmetry / future-proof against a fractional
`MaxResistCap`.

**Spec / verification:** G1 build snapshot regen + letools-diff. After
regen, builds whose underlying float sum already matched LE flip from
Δ=-1 to Δ=0 (Q9J4wvmD: 7/7 resists OK; BgRrP5rr phys: 131→132;
Qdz2yM9k phys: 16→17). Builds where the float sum itself is below
LE's stored float (Idol of Hope sealed +1% stored as 0.8 in LEB,
Holy Aura skill-tree node stored 15 vs LE 15.6, etc.) still show
Δ=-1 on the affected resist types — those are upstream base-value
bugs unmasked by this fix, not regressions of this guard. Compare
`output.<elem>ResistTotal` to `round(modDB:Sum("BASE", nil,
"<elem>Resist") + INC)` — they must match exactly.

**Establishing build:** `Qdz2yM9k lv56 Necromancer` — single-source
phys-resist (Body Armor suffix only, stored 16.83), output flips
16 → 17 to match LE / LETools.

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

The 7 stat names registered (LEB-internal short forms used by
`ModParser` and `modDB:Sum`): `FireResist`, `ColdResist`,
`LightningResist`, `NecroticResist`, `PoisonResist`, `VoidResist`,
`PhysicalResist`. Elemental Resistance fans out to Fire/Cold/Lightning
at parse time, so no separate `ElementalResist` key is needed.

**Spec:** `spec/System/TestResistBaseHighPrecision_spec.lua`
- "Data.lua highPrecisionMods registers BASE=1 precision for <stat>"
- "Data.lua highPrecisionMods carries the @leb-regression-guard marker"

**Establishing build:** `BgRrP5rr lv98 Paladin` — Cold Resistance LE total
97.6 → display 98; LEB stored 96.8 → 97 pre-fix. ah443-0 contribution
flips 15 → 15.6 after Holy Aura `+4%` scaling.

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `vshdm-percentage-units`

`itemLib.applyRangeStrict` is the LEB port of LE's `vshDm` /
`BaseStats.GetValueAfterRounding` (RVA 0x230B940). LE operates on
**fractions** (0.05 = 5%) internally and multiplies the result by 100
for display. LEB callers store **percentage** values (5 = 5%), so the
direct port previously kept LE's fraction-unit constants (`+0.01`,
`+0.001`, `floor(100*x+0.5)/100` endpoint quantization) while feeding
percentage inputs. This worked for cases that landed near a
1-percent boundary but drifted by 1 elsewhere — e.g. Phys Resistance
`+(3-9)% byte=106` returned `5.49` (display 5) when LE returns 6%.

Percentage-space equivalent of LE's
`floor(100*((d_f+0.01-c_f)*e + c_f + 0.001)) / 100` × 100 (display) is
`floor((d_pct+1-c_pct)*e + c_pct + 0.1)` with
`c_pct = floor(min_pct + 0.5)`, `d_pct = floor(max_pct + 0.5)`.

| Site | File | What it does |
|---|---|---|
| Hundredth ADDED branch | `src/Modules/ItemTools.lua` (`applyRangeStrict`, ~line 437) | percentage-space formula `floor((d+1-c)*e + c + 0.1)`, clamp `v ≤ d` |
| Non-ADDED branch (INCREASED/MORE/QUOTIENT) | same | shares the percentage-space form (forced Hundredth) |

**Spec:** `spec/System/TestItemTools_spec.lua`
- "applyRangeStrict (vshDm direct port) — Hundredth-ADDED ... = 19"
- "applyRangeStrict (vshDm direct port) — non-ADDED branch is forced to Hundredth+epsilon ..."

**Establishing build:** `AL07RL31 lv52 Spellblade` — Cold Resist 39→40,
Phys Resist 58→59 after the fix. 23 of 29 G1 resist Δ=±1 rows resolved
in one pass; Σ|Δ|/G1 dropped from 34 to 6.

**Establishing commit:** `<unset; bump after first commit on this branch>`

### `banker-round-vshdm`

`applyRangeStrict` quantizes the (scaled) min/max **endpoints** with
banker's rounding (round half to even), matching LE's
`AscendingValueAfterPropertyRounding` (RVA 0x2307cc0) which calls
`FUN_18038f970` — the IL2CPP banker round helper that delegates to
`FUN_1803207e8` (modf) and biases by `±DAT_183d81f40` on parity. C#
`Math.Round` / `Mathf.RoundToInt` default to
`MidpointRounding.ToEven`, NOT half-up.

The divergence shows up only when `scalar*min` or `scalar*max` lands
**exactly** on `.5` (single-precision float). For all other inputs
banker and half-up agree, which is why the original `vshdm-direct-port`
formula passed dozens of byte-roll regressions before this case
surfaced.

Worked example — `BgRrP5rr lv98 Paladin` body_armor void resist suffix
`(61-75)% scalar=1.5 byte=93`:
- scaled: `91.5 .. 112.5`
- half-up: `c=92, d=113, span+1=22`, `floor(22*93/255 + 92) = 100`
- banker: `c=banker(91.5)=92` (f=91 odd → 92), `d=banker(112.5)=112`
  (f=112 even → 112), `span+1=21`, `floor(21*93/255 + 92) = 99`
- LE in-game tooltip: **99%** → banker is correct.

LE constants (verified from `GameAssembly.dll` `.rdata` 2026-05-10 via
`LE_datamining/extracted/dispatch_decompile_raw.txt` and
`rounding_consts.txt`):
- `DAT_183d81c50 = 255.0` (byte divisor)
- `DAT_183d81f48 = 100.0` (Hundredth scale), `DAT_183d81ddc = 0.01`
- `DAT_183d81e0c = 10.0`, `DAT_183d81de8 = 0.1` (Tenth)
- `DAT_183d81e84 = 1000.0`, `DAT_183d81bdc = 0.001` (Thousandth)
- `FUN_180322480` = `Math.Floor` (signed truncate, post-rounding ascending dispatch)
- `FUN_18038f970` = banker round-half-to-even (used for endpoint quantization)

| Site | File | What it does |
|---|---|---|
| helper | `src/Modules/ItemTools.lua` (`local function banker_round`, ~line 24) | round-half-to-even using `m_floor` + parity check |
| Hundredth/Integer/Tenth/Thousandth branches | `src/Modules/ItemTools.lua` (`applyRangeStrict`, ~line 482) | use `banker_round` for `c`, `d` endpoint quantization |

**Spec:** `spec/System/TestItemTools_spec.lua`
- `describe("banker-round-vshdm endpoints (round-half-to-even)")` —
  three cases: BgRrP5rr Void byte=93 → 99; banker(91.5)=92 +
  banker(112.5)=112; banker(0.5)=0 + banker(1.5)=2.

**Establishing build:** `BgRrP5rr lv98 Paladin` — body_armor Void
Resistance affix overshoot (LEB 100% vs LE 99%) on the G1 top-12
diff list.

**Establishing commit:** `<unset; bump after first commit on this branch>`

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

**Spec:** indirectly covered by the `vshdm-percentage-units` cases
plus the AL07RL31 + QeY7962P G1 build snapshots. A dedicated spec is
intentionally omitted because the routing pattern is a single regex
and any future change to it will surface as a snapshot diff for the
covered resists across ~80 builds with at least one resist roll.

**Establishing build:** see `vshdm-percentage-units`.

**Establishing commit:** `<unset; bump after first commit on this branch>`

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
`1070_0` in both ModItem JSON files. Each entry carries an
`_leb_regression_guard` field so the marker travels with the value.

**Spec:** `spec/System/TestResistBaseHighPrecision_spec.lua`
- "ModItem.json affixId 1070_0 stores +1% (not +0.8%) on player and minion lines"
- (asserted for both `ModItem.json` and `ModItem_1_4.json`)

**Audit:** `LE_datamining/extracted/items/multi_affixes_v3.json` →
`affixId == 1070`, `tiers[0].minRoll == tiers[0].maxRoll == 0.008`,
`property == 30 (All Resistances)`. The 0.8 → 1 promotion is LE's
display contract, not a data overwrite.

**Establishing build:** `BgRrP5rr lv98 Paladin` — Idol of Hope
contributes `+1% Cold Resistance` per LETools per-source breakdown;
LEB stored `0.8` pre-fix.

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

## Layering vs canary strings

Canary strings (`@leb-canary v1 / id:leb-... / do-not-remove`) are file-level
markers that protect against entire modules being deleted or rewritten by a
mass refactor. Regression guards are block-level and protect specific
correctness invariants. Both should be present where they apply; they don't
substitute for each other.
