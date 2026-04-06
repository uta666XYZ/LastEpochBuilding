# Changelog

## [Unreleased]

### New Features
- Skills tab LETools/Maxroll-style UI
  - Damage type icons per skill (physical/lightning/cold/fire/void/necrotic/poison)
  - Skill icons with hex/square masks for spec slots and skill grid
  - Mastered badge for star-unlock mastery skills
  - Spec slot level badge, word-wrap for long skill names
  - Back button relocated to viewport top-left
- Switched to portable distribution — no installer required (extract zip and run)

---

## [v0.10.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.10.0) (2026/04/03)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.9.1...v0.10.0)

### New Features
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

## [v0.9.1](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.9.1) (2025/10/01)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.9.0...v0.9.1)

### Fixed
- Fix crash when selecting skills with triggered ailments

---

## [v0.9.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.9.0) (2025/09/24)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.8.0...v0.9.0)

### New Features
- Support for tree icons
- Full import button and improved main skill detection
- Armor reduction and ward calculation

### Fixed
- Crash on offline import with wrong nbAffixes value
- Throwing skills not taking throwing mods into account

---

## [v0.8.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.8.0) (2025/08/22)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.7.1...v0.8.0)

### New Features
- Season 3 update

### Fixed Calculations
- Fix bonus to damage with first damage type and then source type
- Fix mods like "+10% (one_word) Chance"

### Fixed Bugs
- Fix mod cache picking wrong skills
- Remove "Add Crucible mod..." button (crash)
- Fix import of unique with duplicate names from letools
- Fix unable to select some skills in CalcsTab when less than 5 skills are selected

---

## [v0.7.1](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.7.1) (2025/08/08)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.7.0...v0.7.1)

### Fixed
- Fix missing summon_raptor minion data
- Fix crash due to wrong life/accuracy calculations for minions
- Fix passive point allocations no longer displayed with new runtime
- Fix crash with dot skills without duration

---

## [v0.7.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.7.0) (2025/07/23)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.6.0...v0.7.0)

### New Features
- Blessings support
- Renamed to Last Epoch Building, updated runtimes

### Fixed Calculations
- Fix base stats
- Fix/Improve stats for: Movespeed, All resistances, Mana Regen
- Fix nihilis mods

### Fixed Bugs
- Support offline import on Linux
- Correctly import mods and items on offline import

---

## [v0.6.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.6.0) (2025/07/02)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.5.1...v0.6.0)

### New Features
- Support for modifying nodes (Alt + Left click)
- Weekly beta release channel

### Fixed
- UI review to remove all PoE-specific elements
- Mod parsing simplification and cleanup

---

## [v0.5.1](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.5.1) (2025/06/11)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.5.0...v0.5.1)

### New Features
- Improved online import feedback
- Partial crafting support with affix roll changes
- Default affix roll set to 127.5 (configurable)

### Fixed
- Import of unique items with mods that don't have a roll value
- Fix roll roundings and wrong affix effect modifiers
- Fix life per level gain
- Fix idol positions on online import
- Fix offline import of legacy characters

---

## [v0.5.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.5.0) (2025/06/04)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.4.0...v0.5.0)

### New Features
- Season 2 game data update
- Minion skill support
- Online character import via lastepochtools.com
- Additional abilities and mods

---

## [v0.4.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.4.0) (2024/04/26)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.3.0...v0.4.0)

### New Features
- Channeled skill support
- Ailment support (displayed as triggered skills)
- Debuff support (shred resistance, chill, etc.)
- DoT support

---

## [v0.3.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.3.0) (2024/04/16)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.2.0...v0.3.0)

### New Features
- Skill nodes affect only the related skill
- Skill added damage effectiveness, damage scaling per attribute, cooldown, cast time, critical chance
- Mastery class passive bonuses
- Weapon attack rate for attack skills
- Multi-point skill node allocation

---

## [v0.2.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.2.0) (2024/04/09)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.1.0...v0.2.0)

### New Features
- Basic DPS calculation for several skills

---

## [v0.1.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.1.0) (2024/04/02)

First release, forked from [Path of Building](https://github.com/PathOfBuildingCommunity/PathOfBuilding) and adapted for Last Epoch.

Initial feature support: passive tree, character import, item support, basic stat calculation, skill selection.
