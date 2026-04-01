# Changelog

## (2026-04-02)
## What's Changed
### Analysis
- **Mod recognition rate verification** — Full audit of ModCache (13,743 entries): 89.7% recognition rate (12,321 parsed, 1,422 unparsed). Unparsed mods categorized: skill mechanics (1,091), timing/delay/cast (100), summon/companion (90), stacks/charges (54), additional/extra effects (41), damage conversion (31), abyssal/void (15). Conclusion: 89.7% is sufficient for practical use; most unparsed entries are skill-specific behavior descriptions not suited for item affix parser.

## (2026-03-29)
## What's Changed
### New Features
- **Config tab expanded** — All new options show without pressing "Show All Configurations"
  - Skill Options: Cursed, Transformed, High Health, Ward, Lightning Aegis, Consecrated Ground, Companion count, Frenzy, Nearby Corpses, Used Potion Recently, Forged Weapons count
  - For Effective DPS: Enemy Cursed, Slowed, Hit/Stunned/Killed Recently, enemy ailment stack counts (Bleed, Ignite, Shock, Chill, Time Rot, Doom, Slow, Frailty, Curse)
- **New Offense outputs** — ElectrifyChance, TimeRotChance, BlindChance, SlowChance, FrailtyChance now shown in Calcs tab
- **New Defense outputs** — ParryChance, DamageToManaBeforeHealth, ChanceToChillAttackers, ChanceToSlowAttackers, ChanceToShockAttackers
- **ModParser improvements** — Item affixes now recognized: Slow/Frailty/Blind/Electrify/Time Rot application chances, Parry Chance, Damage to Mana Before Health, Chance to Chill/Slow/Shock Attackers, Healing Effectiveness, per-stack enemy ailment multipliers, UsedPotionRecently, ForgedWeapon
- **Endurance system** — One-shot protection mechanic correctly calculated (threshold-based damage reduction)
- **New player/enemy conditions** in ModParser: `while transformed`, `while at high health`, `while you have ward/lightning aegis`, `on consecrated ground`, `per companion`, `per forged weapon`, `after using a potion`, enemy hit/stunned/killed recently, per-stack ailment tags

### Fixed
- Config tooltip text was rendering as Unicode escape sequences when written in Japanese — all tooltips are now English only

## (2026/08/19)
## What's Changed
### Launch.lua
- Changed APP_NAME = "Last Epoch Building" to APP_NAME = "Last Epoch Building"



## [v0.9.1](https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2/tree/v0.9.1) (2025/10/01)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.9.0...v0.9.1)


## What's Changed
### Fixed Crashes
- Fix crash when selecting skills with triggered ailments in the web version [\#77](https://github.com/uta666XYZ/LastEpochBuilding/pull/77)



## [v0.9.0](https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2/tree/v0.9.0) (2025/09/24)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.8.0...v0.9.0)


## What's Changed
### New to Last Epoch Building
- Support for tree icons [\#66](https://github.com/uta666XYZ/LastEpochBuilding/pull/66)
- Add a full import button and improve main skill guess [\#71](https://github.com/uta666XYZ/LastEpochBuilding/pull/71)
- Support for armor reduction and ward calculation [\#72](https://github.com/uta666XYZ/LastEpochBuilding/pull/72)
### Fixed Crashes
- Fix crash on offline import when importing items with wrong nbAffixes value [\#65](https://github.com/uta666XYZ/LastEpochBuilding/pull/65)
### Fixed Calculations
- Fix throwing skills not taking throwing mods into account [\#67](https://github.com/uta666XYZ/LastEpochBuilding/pull/67)



## [v0.8.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.8.0) (2025/08/22)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.7.1...v0.8.0)

## What's Changed
### New
- Season 3 update [\#61](https://github.com/uta666XYZ/LastEpochBuilding/pull/61)

### Fixed calculations
- Fix bonus to damage with first damage type and then source type (e.g. void spell damage) [\#51](https://github.com/uta666XYZ/LastEpochBuilding/pull/51)
- Fix mods like "+10% (one_word) Chance" [\#57](https://github.com/uta666XYZ/LastEpochBuilding/pull/57)

### User interface
- Fix the listing of skills in SkillsTab: increase limit + fix color [\#58](https://github.com/uta666XYZ/LastEpochBuilding/pull/58)

### Fixed bugs
- Fix mod cache picking wrong skills [\#52](https://github.com/uta666XYZ/LastEpochBuilding/pull/52)
- Remove the "Add Crucible mod..." button that causes a crash [\#55](https://github.com/uta666XYZ/LastEpochBuilding/pull/55)
- Fix import of unique with duplicate names from letools [\#60](https://github.com/uta666XYZ/LastEpochBuilding/pull/60)
- Fix unable to select some skills in CalcsTab when less than 5 skills are selected [\#62](https://github.com/uta666XYZ/LastEpochBuilding/pull/62)

### Other changes
- Modcache fix for notScalingStats [\#50](https://github.com/uta666XYZ/LastEpochBuilding/pull/50)
- Minor automated testing improvement [\#46](https://github.com/uta666XYZ/LastEpochBuilding/pull/46)

## Mod parsing progression TODO
* **Out of 14,246 mods, 5,020 (35%) mods are recognized by the parser**. Even if a mod is recognized, it's not guaranteed that it will work as expected.
* The total amount of mods is made of
    * the implicits (one for each implicit of each item)
    * the prefixes and suffixes (one for each tier of each)
    * the unique modifiers (one for each mod of each unique)
    * the passive and skill trees (one for each mod of each node)

## [v0.7.1](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.7.1) (2025/08/08)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.7.0...v0.7.1)

## What's Changed
### Fixed bugs
- Fix missing summon_raptor minion data [\#35](https://github.com/uta666XYZ/LastEpochBuilding/pull/35)
- Fix crash due to wrong life/accuracy calculations for minions [\#36](https://github.com/uta666XYZ/LastEpochBuilding/pull/36)
- Fix passive point allocations no longer displayed with new runtime [\#37](https://github.com/uta666XYZ/LastEpochBuilding/pull/37)
- Fix crash with dot skills without duration [\#42](https://github.com/uta666XYZ/LastEpochBuilding/pull/42)
- Clean a lot of obsolete code related to jewels or sockets from PoE [\#43](https://github.com/uta666XYZ/LastEpochBuilding/pull/43)



## [v0.7.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.7.0) (2025/07/23)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.6.0...v0.7.0)

## What's Changed
### New
- Add blessings support [\#24](https://github.com/uta666XYZ/LastEpochBuilding/pull/24)
- Rename the tool to Last Epoch Building + update runtimes [\#31](https://github.com/uta666XYZ/LastEpochBuilding/pull/31)

### User interface
- Use attribute colors [\#32](https://github.com/uta666XYZ/LastEpochBuilding/pull/32)

### Fixed calculations
- Fix base stats [\#25](https://github.com/uta666XYZ/LastEpochBuilding/pull/25)
- Fix/Improve stats for: Movespeed, All resistances, Mana Regen [\#26](https://github.com/uta666XYZ/LastEpochBuilding/pull/26)
- Fix nihilis mods due to a mix of positive and negative values in range [\#23](https://github.com/uta666XYZ/LastEpochBuilding/pull/23)

### Fixed bugs
- Support offline import on linux [\#21](https://github.com/uta666XYZ/LastEpochBuilding/pull/21)
- Correctly import mods and items on offline import [\#22](https://github.com/uta666XYZ/LastEpochBuilding/pull/22)

## Mod parsing progression
* **Out of 13,091 mods, 4,519 (36%) mods are recognized by the parser**. Even if a mod is recognized, it's not guaranteed that it will work as expected.
* The total amount of mods is made of
    * the implicits (one for each implicit of each item)
    * the prefixes and suffixes (one for each tier of each)
    * the unique modifiers (one for each mod of each unique)
    * the passive and skill trees (one for each mod of each node)

## [v0.6.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.6.0) (2025/07/02)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.5.1...v0.6.0)

## What's Changed
### New
- Support for modifying nodes in order to do some quick fix of some not yet supported mods (Alt + Left click on node) [\#19](https://github.com/uta666XYZ/LastEpochBuilding/pull/19)
- Support for weekly beta release (same as PoB) that you can opt in from the options

### User interface
- UI review to remove all specific parts related to Path of Exile [\#18](https://github.com/uta666XYZ/LastEpochBuilding/pull/18)

### Fixed calculations
- Review mod parsing (simplification + removing irrelevant mods) [\#17](https://github.com/uta666XYZ/LastEpochBuilding/pull/17)
  - Add the support of a bit more mods
  - Add a slider to set the range of all mods of all items (making it easier to compare builds from LETools)

## Mod parsing progression
* **Out of 13,274 mods, 4,082 (31%) mods are recognized by the parser**. Even if a mod is recognized, it's not guaranteed that it will work as expected.
* The total amount of mods is made of
    * the implicits (one for each implicit of each item)
    * the prefixes and suffixes (one for each tier of each)
    * the unique modifiers (one for each mod of each unique)
    * the passive and skill trees (one for each mod of each node)


## [v0.5.1](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.5.1) (2025/06/11)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.5.0...v0.5.1)

## What's Changed
### User interface
- Improve online import (giving feedback on last cache) [\#12](https://github.com/uta666XYZ/LastEpochBuilding/pull/12)
- Partial support for crafting items and changing rolls of affixes
- Set the default roll for affixes to 127.5 (the average) (this is configurable in the options) (/!\ You may end up with the old value of 0.5)

### Fixed bugs / calculations
- On online import, fix import of unique items with mods that don't have roll [\#10](https://github.com/uta666XYZ/LastEpochBuilding/pull/10)
- Fix roll roundings and wrong affix effect modifiers for some affixes [\#13](https://github.com/uta666XYZ/LastEpochBuilding/pull/13)
- Fix life per level gain
- Fix idol positions on online import (one idol could not be imported)
- Fix offline import of legacy characters


## [v0.5.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.5.0) (2025/06/04)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.4.0...v0.5.0)

## What's Changed

Finally updated with game data from season 2 along with several changes:

* Support for minion skills
* Online character import through https://www.lastepochtools.com/profile/
* Some fixes on DOT calculation
* Support of additional abilities and mods

## [v0.4.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.4.0) (2024/04/26)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.3.0...v0.4.0)

## What's Changed
Major improvement to DPS calculations with the support of ailments, debuffs, channeled skills, and DOT skills. I decided to consider the ailments as triggered skills since it seemed more flexible this way.

* Support for channeled skills
* Support for ailments, they are displayed as triggered skills
* Support for debuffs (shred resistance, chill, ...)
* Support for DOT

## [v0.3.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.3.0) (2024/04/16)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.2.0...v0.3.0)

## What's Changed
Major improvement to skill Hit DPS calculations and improvement to the passives and skills tree looks (multiple points can now be allocated to a single node).

There are still a lot of unrecognized mods but DPS indication can already provide useful feedback for several skills.

There is no support yet for ailments and DoT.

* Skill nodes only affect the related skill
* Support for skill added damage effectiveness, increased damage scaling per attribute, cooldown, cast time, critical chance
* Support for several mods: more damage in skill nodes, cooldown, cast speed, elemental damage, per attribute suffixes ...
* Support for mastery class passive bonuses (if the mods are recognized only)
* Guess main skill at import time (based on DPS calculation somehow)
* Support for weapon attack rate for attack skills

## [v0.2.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.2.0) (2024/04/09)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.1.0...v0.2.0)

## What's Changed
This release introduces DPS calculation. It takes into account a large variety of skills, but it does not support yet a lot of mods.

So do not expect passives in the skill tree to have the intended effect for example. What is probably working is mods like "+x melee physical damage" or "x% increased fire damage"

* Basic DPS calculation support for several skills
* Fixed several mods from imported data (display value)
* A bit of cleaning (removing some irrelevant files)
* A few minor fixes (save/load fix, display of damage types in breakdown,...)

## [v0.1.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.1.0) (2024/04/02)
First release, it started as a fork of [Path of Building](https://github.com/PathOfBuildingCommunity/PathOfBuilding) which is slowly adapted to Last Epoch so most content is not yet relevant to the game.

The following features are supported (or partially):
* Passive tree
* Character import: for offline character and from LE tools build planner
* Most stats and mods/affixes are not working correctly (either not recognized or not applied correctly)
* Items: Imported from character import and can be crafted / modified
* Unique items (no support for legendary yet)
* Basic support for following stat calculation: health, mana, armor, attributes
* Skills: Can select up to 5 skills which allows to spend points in the associated skill trees

Note that online character import is not directly available, but you can import from Last Epoch Tools build planner (which can do online character import). 
