# Changelog

## [Unreleased]

---

## [v0.13.2](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.13.2) (2026/04/30)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.13.1...v0.13.2)

### Notable Changes
- **LETools URL direct import — supported** (revert of the v0.13.0 deprecation note). The Creator was mistaken: planner URL import has been working all along and is not affected by Cloudflare encryption rotations. The earlier deprecation notice referred to the (now-retired) LETools account-scraping path, which has since been replaced by the Maxroll account API. Paste `https://www.lastepochtools.com/planner/XXXXX` URLs directly into the Import dialog. Share-box prompts have also been tidied.
- **Fontin tooltip fonts** — tooltips now use Fontin / Fontin SC to match the in-game Last Epoch look. The bundled `runtime/SimpleGraphic.dll` has been updated from upstream PathOfBuilding-SimpleGraphic to add the required font support.

### Skill / Damage Type / Tag Fixes
- **Flame Ward** — Lightning conversion (Static Aegis tree) now applies correctly; multi-paragraph descriptions are gated so unrelated paragraphs no longer leak into tag detection. Skill icon also corrected.
- **Healing Hands** — Melee/Fire tag promotion through tree damage producers; Symbols of Hope default tagging fixed.
- **Warcry** — Cold scaling now propagates from tree damage producers; the Wolf companion picks up the Cold minion tag in matching builds.
- **Forge Strike** — Minion Tags now include Fire when expected. Reverted the prior `SP=88` ceil rule that caused incorrect rounding for some affixes.
- **Item-mod conversions** — the destination damage type now surfaces as the base damage type for downstream tag and affix matching.
- **Lich / Reaper Form** — comprehensive support and tooltip/order fixes: Reap parent skill, Form parent routing, `+Minion Skills` across summon/form parents, level-cap display on the slot.
- **Skill-tag parser** — source-less `<X> Conversion` tree-swap stats are now parsed.
- **DataProcess** — composite `SkillType` bits require a full-mask match (prevents spurious tag hits).
- **Global** — canonical AT enum `SkillType` bit layout restored (e.g. Disintegrate=DoT, Detonating Arrow=Bow). Bitmaps unchanged; only labels were corrected.

### Skill Level / Affix Matching
- `+N to <Skill>` / `+N to <Category> Skills` matching now mirrors LE in-game logic across the board:
  - per-skill delivery conversion applied to the level cap and tooltip
  - `stcdt` (skill-tree conversion damage tag) excluded from level-of-skills affix gating, but consumed for tag and affix matching
  - tree damage-type swaps excluded from cap matching, while tree tag swaps still apply in the cap-summing `SkillLevel` pass
  - split-effect damage type additions on specialization trees detected
  - Minion Skill affix matching corrected, with the level cap now displayed on the skill slot
  - tree-injected tag additions surfaced for minion-side affix matching
- `+N to <Skill/Cat>` SP affixes ceil-round their `(N–N)` midpoints to integers (matches the `SP=88` contract for affix integers).

### SkillsTab UI
- **Scaling Tags** displayed on the skill slot and on tree root hover, conversion-aware, in plain white text, using the canonical AT enum tag set (now including Area).
- **Minion Tags** row added; the Area tag is moved into it when a skill is totem-converted.
- `fakeTags` merged into the displayed tag set; `+Spells` affix matching now surfaces correctly.

### Data
- `skills.json` — added `fakeTags`, `areaTagDisplay`, `minionTagsDisplay`, and `instantCastForPlayer` fields.
- `ModCache.lua` — 43 poisoned `per player <Attr>` entries busted; stale `+1 to Elemental Spells` and `+X to <Cat> Skills` caches purged.
- `ModParser.lua` — long `modTags` whose tail overlaps a protected `modName` are now allowed; dispatcher extended with `Spells` / per-Complete-Set handlers.
- Uniques — removed the bogus `Evolution's End +(1-2) to All Skills` entry.

### Uniques / Items
- **Julra's Obsession** — implemented `+100% Stats on your gloves also apply to your minions` (glove → minion stat propagation). The companion "stats also apply to minions" line is tagged **not supported** where the calc path is incomplete, so users see the limitation explicitly rather than receiving a silently-wrong number.

---

## [v0.13.1](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.13.1) (2026/04/28)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.13.0...v0.13.1)

### Compatibility
- Verified compatible with game v1.4.6 — bug-fix-only patch (no balance, item, affix, or skill data changes per official notes); no LEB data updates required.

### Bug Fixes
- **Dual-resistance corrupted affixes garbled on import** — affixes that grant two resistances on a single corrupted T-tier line (e.g., Cold + Void Resistance) imported with the second line mangled into flavor text such as `+27% Reduces all cold damage you take. Capped at 75%. Void Resistance` instead of `+27% Void Resistance`. Root cause: in the affix data, the second resistance line had been stored with the first resistance's flavor text (`Reduces all <element> damage you take. Capped at 75%.`) concatenated in front of the actual stat string. As a result, the second resistance was never recognized and silently dropped. Affected LETools URL imports and Save-import flows. Fixed for all 40 affected entries (Phys/Cold/Lightning/Fire × Void/Poison/Necrotic, 8 tiers each). Reported by a community user.
- **`+X to <Category> Skills` affixes not applying correctly** — affixes that grant additional skill levels filtered by category (damage type, skill type, attribute, DoT, or "all") were not being recognized for many parent skills, so the level bonus was silently dropped or under-applied. Fix touches the skill metadata pipeline (`DataProcess.lua` mirrors `baseFlags` into `skillTypes` and exposes `keywordFlags`), the calc context (`CalcSetup.lua` includes `skillTypes`/`keywordFlags` in `skillCfg`), the mod parser (`ModParser.lua` adds a generic `+N to <Cat> Skills` handler covering damage types, skill types, attributes, DoT, and `all`, plus a minion DoT variant), the SkillsTab rounding (half-up on range-affix midpoints so e.g. `+3.5` yields an integer cap), and removes 9 stale `ModCache.lua` entries whose semantics changed.

---

## [v0.13.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.13.0) (2026/04/27)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.12.1...v0.13.0)

### Notable Changes
- **Steps (Leveling Order)** — leveling order numbers on passive and skill tree nodes, with All / Min display modes (LEB-only feature)
- **Base class 20-point gate** — 20 points must be allocated in the base class before any subclass node can be allocated (matches in-game rule)
- **F5 restart** — opened to all users (was previously dev-only); planned to be removed once errors become rare
- **LETools URL direct import — deprecated**; please use build code paste or Maxroll import instead
- **Maxroll URL direct import** — still in beta; please report issues so hotfixes can be issued promptly

#### Craft UI Redesign
- New 2-stage flow: Stage1 modal base/unique/set picker → Stage2 inline editor on ItemsTab
- Item preview tooltip on base dropdown (Stage1)
- Inline editor with vertical layout (action buttons → editor → preview)
- Paperdoll always-visible with slot-filtered Craft UI shortcut and tier color coding
- All Items list: category sort, single-click edit, type / primordial / corrupted icon rows
- Edit existing items: Edit button reopens craft editor for non-crafted, imported, EXALTED, and LEGENDARY items
- Cross-tier slider with tier markers and rich tooltip for affix rolls
- Implicit / unique mod / set roll sliders (all rarities)
- Multi-mod affix unified to single slider + tooltip layout
- Collapsible group headers in affix dropdown
- Unique prefix/suffix shown above unique mods
- Set info panel integrated into inline editor; equipped set members highlighted (orange)
- Per-item limit enforcement for set / champion + global primordial
- Primordial slot locked to T8 with primordial / corrupted icon indicators
- Idol Altar: corrupted expands to full 20 affixes; sealed/primordial filtered
- Class / type filtering, class-specific base items, Weaver's Will support, legacy item filter
- Off-Hand filter, T7 cap display
- DPS / stat diff hover tooltip on item preview

#### S4 Attributes
- S4 attributes shown in sidebar stat list
- Attribute display reordered to Str/Dex/Int/Att/Vit
- Damage type display reordered to Fire/Cold/Lightning/Phys/Necro/Poison/Void
- Base attribute row hidden when fully converted to S4 attribute
- S4 converted attributes placed in the slot of the base attribute they replace

#### Idol Altar
- Per-type idol multipliers, omen capacity, grid condition recognition
- Refracted slot effect ('per Idol in a Refracted Slot') recognition
- Altar-boosted values shown in Omen Idol slot tooltips and reflected in DPS
- Idol Altar support in Craft UI
- Idol container frame + altar empty circle icon
- Defiance ET per uncapped elemental resistance

#### Set / Reforged
- Reforged Set crafting and item set tooltip
- Themed set bonuses + Legends Entwined "Counts as a part" (wildcard set membership)
- Per-Complete-Set scaling for affixes
- Maximum Symbols auto-detect from Paladin passives, Active Symbols multiplier

#### Import
- Maxroll planner: items, idols, blessings import
- Sealed / primordial / corrupted affix import
- Quest reward auto-apply from savedQuests on character import
- In-app error reporting: rich dialog with build-include checkbox, action log, copy-to-clipboard

#### Steps (Leveling Order)
- Steps — leveling order numbers on passive and skill tree nodes
- Allocation order step numbers with All / Min display modes
- History bar with mastery colors, hover interactions, expand mode
- Auto-switch passive mastery on hover
- Per-mastery reset dropdown in passive tree header
- Isolated passive/skill history and step numbering

#### Other
- Calcs tab search bar
- Ward Decay Per Second breakdown
- Runebolt Cold/Lightning skill variants + Tri-Elemental average DPS
- Holy Aura base buff + per-prefix effect scaling
- Buff toggle UI + F5 restart for all users
- New conditions: NearEnemy, Blocking, Channelling, Standing on Glyph of Dominion, Arcane Momentum, Arcane Shield, Time Rotting, StunnedEnemyRecently, Concentration
- Corruption config option (scales enemy HP and damage)
- Ailment Overload / Haste / Frenzy / Lightning Aegis conditions wired to Config toggles
- Weapon slot ghost sprite based on equipped item type
- Equipped slot rows show type / primordial / corrupted icons
- Sidebar stat labels aligned with in-game terminology
- Config tab: tooltips for all options + Reset to Defaults button

### Calculations
- DPS integration series (#1–#10): area-level scaling, while-channelling, while-buff, +N to skill,
  per-active/per-equipped multipliers, per-arrow/per-projectile, ailment/charge on hit,
  damage-taken with source, mana-spent-as-ward conversion, compound 'doubled if...' conditionals
- Base skill damage now correctly calculated (was 0 for all skills due to missing stat mappings)
- Corruption scaling formula implemented
- S4 attribute grants now apply to PerStat bonuses
- Recently / Transformation conditions fixed
- Conditional DamageTaken mods now apply with correct type and conditions
- Shock stacks correctly increase enemy damage taken by 5% per stack
- Enemy ailment stack multipliers now use Config settings
- Ailment stack caps corrected (Shock=10, Doom=4, Time Rot=12; Shock/Chill/Slow visual stacks at 3)
- Endurance Threshold systematic underestimation fixed
- Blessing double-apply removed (resists / armor)
- Rusted Cleaver "Intelligence Equals Strength" implemented
- Complete Set mechanic implemented
- Ward Retention: S4 corruption-only conversion affixes now materialise on auto-derive
- Mage-76 Elixir of Knowledge interpreted as INC
- Damage Taken From Mana Before Health
- Stun Chance / Freeze Chance proper formulas
- Bladedancer Evasion overcounting + CritMultiplier base fix
- Block Chance handles "+X% per Y% Endurance above Cap"
- Uncapped Endurance percent (EnduranceTotal) tracked
- Ward equilibrium formula corrected (uses CalcPerform-computed Ward stats)
- Cooldown cap applied to skills with NoCooldown tree nodes
- Capped PerStat Dodge Rating for Spellblade Illusory Combatant
- Forge Guard / Falconer passive bonuses corrected
- World Splitter CritMult restricted to Melee Attack
- Average Full DPS for cycling skill groups (Runebolt Tri-Elemental)
- 20 base class passive point requirement enforced before subclass nodes
- PoE legacy code removed (Impale, Spell Suppression, Guard, PvP scaling)

### Mod Recognition
- Idol altar mod recognition (skill damage, cooldown, damage-taken, refracted slots)
- Catch-all recognition for remaining red-text idol mods
- Item affix gap recognition with shadowing guards
- "(NOT SUPPORTED IN LEB YET)" annotation for unsupported mods
- New patterns: "+N to <skill>", "X% of Health Regen also applies to Ward",
  "per point of <attribute>", "per N max mana", abbreviated attribute names

### Data
- 16 unique items audited and corrected (phantom mods removed; Stormtide / Foot of the Mountain /
  Blood of the Exile / Eterra's Path / Snowdrift / Stealth / Suloron's Step / Transient Rest /
  Raindance / Clotho's Needle / Army of Skin / Tabi of Dusk and Dawn / Ash Wake)
- Yrun's Wisdom missing mods added
- The Last Bear's Lament Reforged T5 affix values corrected
- Sentinel-89 stats corrected; restored "Less Stun Duration"
- Druid mastery start stat split to apply +20% Health/Mana
- Falconer ascendancy +12 Dexterity restored
- Anomaly Exacerbate node gate corrected
- Heat Flux node text corrected
- Tyrant Crown / Abyssal Echoes / Devouring Orb icons fixed
- Bladedancer badge upgraded to 256x256
- Primordial / Corrupted icons updated to in-game tooltip bullet sprites
- 5 skills' base damage corrected via reference data
- Cinder Strike critChance and base CritMult added
- Skill tree node positions corrected, typo fixes
- Idol affix filter for universal idols
- Slot-dependent range overrides for ~150 affixes (T0–T7, multi-slot affixes)
- 63 missing item images added
- Ascendancy passive texts synced with game v1.4.3
- Large Idol [1x3] Jagged prefix added
- Legacy base items flagged

### Fixed
- base85 partial-group decode (offline code / URL import)
- Ephemeral blessings persisted through XML save/reload
- Auto-derive corrupted before recraft so S4 conversion affixes materialise
- Apophis + Temple of Eterra quest rewards applied on import
- Maxroll URL with fragment suffix (e.g. `#2`) imports correctly
- Maxroll planner: numeric item references resolved
- Maxroll idol coords are 1-indexed
- Reforged Set items recognised on import
- Imported items (crafted=true, no craftState) routed through preset path
- Edit button opens craft editor for non-crafted / imported items
- EXALTED / LEGENDARY rarities supported in OpenCraftEditorForItem
- Idol affix value parity with reference data (applyRange round + class-specific scalar)
- Crafted affixLimit raised 6 → 10 so Corrupted/Primordial slots land
- Stale ModCache entries purged (Lightning Aegis, Leeched as Health, channelling)
- Skill icon hex-mask in skill bar / skill grid; level badge hidden when skill unlocked
- Channelling-skill tree node mods gated by Condition:Channelling
- Mastery skills: central passive tree icon now hidden after allocation
- Craft UI: %mod decimal precision auto-detected
- Cerulean and Sanguine Runestones 6-point bonuses apply
- Dev mode detection by `.git/HEAD`; works from git worktree
- Numerous Craft UI crash / nil-guard fixes (gsub, tier color, mod text wrap)

### Special Thanks
- WarMachine237 — LEB's very first supporter

#### 🏆 v0.13 Test Build MVP — u/SottoSopra666

Dear u/SottoSopra666,

Your build *KoraWasteTime lv91 Spellblade* almost broke my heart.
It was pure PAIN to implement — but hey, you cooked such a complex build. Congrats.

*One person, five builds — single-handedly broke the Blessing system, broke the Crit calc, and made me question every Resist value.*

Thank you for making LEB stronger. 💛

— the Creator

---

## [v0.12.1](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.12.1) (2026/04/15)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.12.0...v0.12.1)

### Fixed
- Auto-updater re-downloading all files on every launch
- Version label incorrectly showing "(Dev)" on released builds

---

## [v0.12.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.12.0) (2026/04/14)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.11.0...v0.12.0)

### New Features
- New desktop app icon
- Online character import now uses Maxroll's character import (note: may be a bit slow)
- Build sharing — generate a short link or offline code to share your build
- Node search (Ctrl+F) in passive tree, skill tree, and skill selection
  — also searches node names of unequipped skills
- Import UI redesigned into 3 sections (offline and online)

### Improvements
- Icon quality overhaul — passive nodes, skill icons, blessings, and idols

### Data
- Updated to game version 1.4.3

### Fixed
- Online import: skill slots empty and wrong relic after import
- Online import: Weaver's Will items now correctly recognized (fingers crossed — please report if issues persist!)
- Online import: Season 2 characters (format v2) now supported
- Skill icon fixes

### Mod Recognition
- Mod recognition: 100% (recognized mods are not always fully reflected in calculations — calculator still in progress)

### Special Thanks
- WarMachine237 — LEB's very first supporter

---

## [v0.11.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.11.0) (2026/04/10)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.10.0...v0.11.0)

### New Features
- Blessing UI visual overhaul (circular slots, icons, hover popup card)
- Idol crafting system with dedicated affix data, affix count labels, Weaver-specific affixes, and unique idol color
- Idol Altar type label added to Idol Altar UI
- Omen idol affix pool (partial implementation)
- Updated app icon to new LEB design

### Data
- Updated to game version 1.4.2 (balance and item changes)

### Fixed
- Blessing save/load, import, and slot mapping corrections
- Idol crafting class filtering
- Omen idol affix filter

---

## [v0.10.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.10.0) (2026/04/07)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.9.1...v0.10.0)

### New Features
- Skills tab LETools/Maxroll-style UI
  - Damage type icons per skill (physical/lightning/cold/fire/void/necrotic/poison)
  - Skill icons with hex/square masks for spec slots and skill grid
  - Mastered badge for star-unlock mastery skills
  - Spec slot level badge, word-wrap for long skill names
  - Back button relocated to viewport top-left
- Switched to portable distribution — no installer required (extract zip and run)
- Config tab expanded with skill options and effective DPS conditions
- New offense outputs: Electrify, Time Rot, Blind, Slow, Frailty chances
- New defense outputs: Parry, Damage to Mana, Chill/Slow/Shock Attackers
- Endurance system (one-shot protection)
- Full ailment/debuff/buff/Overload implementation
- Tunklab defense formulas (block, dodge, ward)
- Idol Altar UI redesign with Fractured Slot auto-population
- Equipment +skill level mods (global and per-skill)
- Empowered monolith blessing slots
- Skill tree connector line requirement dot indicators

### ModParser Improvements
- Mod recognition rate: 89.7% (12,321/13,743 entries)
- New conditions: transformed, high health, ward, lightning aegis, consecrated ground, per companion/forged weapon, potion recently, enemy ailment stacks

### Fixed
- Removed PoE-specific remnants (Chaos, Energy Shield, cost conversion)
- Removed weapon set swap UI
- Stun threshold formula corrected
- Idol tooltip on all occupied cells including blocked positions
- Config tooltip Unicode issue resolved

---

## [v0.1.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.1.0) (2024/04/02)

First release. Initial feature support: passive tree, character import, item support, basic stat calculation, skill selection.
