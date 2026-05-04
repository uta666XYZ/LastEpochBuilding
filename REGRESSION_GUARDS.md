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
from 35 to 49 after fix (LETools 44; remaining −5 is the unrelated
`CompleteSetCount` discrepancy).

**Establishing commit:** `<pending>`

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
