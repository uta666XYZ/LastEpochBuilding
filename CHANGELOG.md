# Changelog

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
