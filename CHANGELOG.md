# Changelog

## [beta](https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2/tree/beta) (2026/07/20)

[Full Changelog](https://github.com/uta666XYZ/LastEpochBuilding/compare/v0.12.1...beta)


## What's Changed
### Other changes
- release: v0.14.0 main snapshot [\#5](https://github.com/uta666XYZ/LastEpochBuilding/pull/5) ([uta666XYZ](https://github.com/uta666XYZ))



## [v0.14.0](https://github.com/uta666XYZ/LastEpochBuilding/tree/v0.14.0) (2026/07/21)

> A large **DPS / calculation-accuracy** release: a trigger-skill engine, an auto-summon framework, a game-faithful damage-conversion engine, more accurate ailment / damage-over-time handling, an across-the-board minion damage fix, a Config-tab overhaul, and a Notes tab with Markdown — plus modeling for a large number of skills, uniques, and minions across every class.
>
> **Validation:** LEB's stat calculations were cross-checked against **over 500 community-shared builds per mastery** to surface systematic discrepancies.
>
> **Tags used below:** _(off by default)_ = a Config toggle or per-stack count that does nothing until you enable it · _(display only)_ = a new readout; the headline DPS number is unchanged · _(per-hit only)_ = shown per hit, not yet summed into Full DPS · _(corrects an over-count)_ = this number now goes **down**, it was previously too high · _(data only)_ = recorded internally, not active yet.

### Notable Changes

- **Trigger-skill DPS engine (new)** — a large family of "X% chance to cast / trigger `<skill>`" affixes, idols, and tree nodes used to contribute nothing (the triggered skill was recognized but never entered the calculation). They now feed Full DPS at a build-derived rate (source's hit/cast rate × the chance), with the affix's own rate caps and cooldowns applied. Bridged forms: on hit, on melee hit, on spell cast / on cast, "when you cast B", "when you use B", on crit / when hit, source-qualified on-crit, "every N seconds", and "cast after you use `<source>` and hit a Boss/Rare".
- **Minions deal a lot more damage (systematic fix)** — every minion now gets Last Epoch's inherent "more damage per character level" scaling (about −37% low at level 100 before this). This raises Full DPS for **all** minion builds.
- **Auto-summon framework (new)** — minions summoned by gear, affixes, set bonuses, or passives (with no summon skill to slot) are now modeled and counted in Full DPS; previously they were recognized as text but not modeled at all.
  - _Affects:_ Apiarist Bees ("+N Bees Per 10 Seconds"), Queen Bee (Apiarist 3-set bonus), Tyrannosaur (Tyrant's Skull), Tolmat's historic minions (Tolmat's Incorrect History of Eterra), Anurok (Chorus of the Anurok).
- **Multi-skill minions fold their abilities into Full DPS** at a measured cadence, instead of counting only their default attack.
  - _Affects:_ Summon Bear (Melee / Swipe / Earthquake), Abomination (Melee / Double Strike), Manifest Armor.
- **Notes tab — Markdown** — live Edit/Preview with headings, lists, tables, code blocks, blockquotes; image embeds (`![alt](url)`, cached + auto-resized); a `[[TOC]]` table of contents; `[[Loadout: X]]` build-variant references; Edit↔Preview scroll sync; and Ctrl-wheel font scaling.
- **Config tab overhaul** — options your build actually cares about are auto-highlighted (based on your tree, skill trees, skill loadout, and equipped affixes), each tooltip naming the exact node / skill / item that made it relevant. Added a **Config Sets** UI (named presets — New / Copy / Rename / Delete / reorder). Highlighting is read-only and never auto-toggles a config or changes DPS on its own.
- **Damage-over-Time reporting** — new **Total DoT DPS** row (Last Epoch's ailments stack, so the correct aggregate is a sum), ignite rows, and ailments folded into their parent skill in the Full DPS display. _(display only)_

### Calculations — damage conversion

- **Skill-scoped "X% of base damage converted to `<Type>`" now actually converts** (was recognized but silently dropped, so the base kept its original element); the converted fraction is removed from the source, so nothing is double-counted.
  - _Affects:_ Heartseeker (Molten Arrowstorm Physical→Fire, Controlled Icicle Physical→Cold), Rive (Temporal Warrior Physical→Void), Vengeance (Flaming Sword Physical→Fire), Volcanic Orb (Liath's Machinations 50%→Lightning; Lament of the Lost Refuge →Void), Swarmblade (Frost Bites full base→Cold).
- **Opposing / cyclic / multi-hop conversions no longer delete damage** — a closed loop (e.g. Avalanche with both Cold→Physical and Physical→Cold) used to zero out the convertible base; the total is now preserved and lands on the correct final type, following the game's own conversion order (for that Avalanche pair, the net result is all Cold — matching the in-game note that Rockfall has no effect if you also have Frost).
- **Conversion uses the right damage pool** — it converts the skill's own base plus weapon flats, while non-weapon added damage keeps its own type and is applied after conversion (restores realistic off-type splits instead of forcing everything to one element).
- **Player-wide (aura) conversions also convert typed added damage**, removing leftover off-type damage. _Affects:_ Symbols of Hope Fire→Void (Smite, Warpath).
- **Form-tree conversions are scoped to that form's own attacks** instead of leaking onto every skill of that element. _Affects:_ Werebear, Swarmblade, Spriggan, Reaper forms.
- **Typeless / adaptive "+X Damage" is distributed the game's way** — spread proportionally across the post-conversion types instead of added in full to every type or dumped onto a converted-away lane.
- **New chance → chance conversion engine.** _Affects:_ Apex of Thought, Vial of Volatile Ice, Liath's Machinations (Ignite→Shock), Carrion of Creation (ailment chances→Bleed), Puncture (Bleed+Poison→Frostbite). _(These uniques aren't on any existing build, so they're inert until you use them.)_

### Calculations — ailments & damage over time

_These are several distinct accuracy fixes — not a single finished "damaging-ailment engine"._

- **Ailment chance above 100% now overstacks** — extra stacks apply per hit instead of being clipped at 100%. _Affects:_ high-chance Bleed / Ignite / Poison stacking builds.
- **Multi-hit-per-cast is still a deliberate conservative under-estimate.** Application uses your cast/attack rate, so skills that hit many times per cast (orbiting projectiles, bounces, re-sweeps) read low on purpose. Hammer Throw's spiral now models its deterministic 3-hammer same-target multiplicity, but further orbit re-hits are not modeled — so **Bleed Hammerdin still reads below its true ceiling**.
- **Non-damaging ailment stacks are hard-capped at the game's limits** (Shock 10, Chill 3, Slow 3, Blind 1). _(corrects an over-count)_ on Shock resistance-shred and Shock-scaled lightning; also lets Spark Charge detonations contribute Shock.
- **Player tree/passive "+% chance to inflict `<ailment>`" now counts** toward damaging ailments (was gear-only), and per-ailment **Duration** affixes extend the correct ailment.
- **Damaging-ailment magnitude now includes damage-over-time mods** ("increased Damage over Time", phys-DoT nodes) that previously did nothing to ailment damage.
- **Ailment (DoT) ticks are now mitigated by enemy resistance minus your penetration**, like hits — a correctness fix that can **lower** displayed DoT versus the old raw treatment. Added a general ailment-scoped penetration channel. _Affects:_ Salt the Wound (crit-multi → ailment penetration).
- **Minion Bleed / Ignite now deal damage** — was always 0 because minions never consumed ailment chance. _Affects:_ e.g. Skeleton Rogue Bleed.
- **Channelled infinite-duration DoT beams now compute per-second DPS** (were 0). _Affects:_ Drain Life, Disintegrate, Ghostflame.
- **Finite-duration stacking DoT auras use the correct per-second base** (were collapsed ~7× low). _Affects:_ Maelstrom; pure-DoT skills also now receive "increased Damage over Time" (e.g. Profane Veil, Aura of Decay).

### Calculations — minions

- Inherent minion "more damage per player level" now modeled (see Notable Changes) — a large increase for every minion build.
- **Weapon-attack minions inherit the equipped weapon's per-type added damage** (closes a ~10× under-read), restricted to the validated Rogue Ballista so Skeleton Archers don't wrongly inherit it yet.
- **`+Minion Bow / Throwing Damage` no longer leaks onto minion melee.** _(corrects an over-count)_
- **Julra's Obsession** "+100% Stats on your gloves also apply to your minions" implemented (attributes correctly excluded).
- Minion-applied ailments now produce realistic DPS with a full stacking model, shown in new breakdown rows.
- Base-data corrections and duplicate-scaling removals (Bone Golem Rampage, Spriggan Thorn Volley, Storm Crow Lightning Blast phantom per-Int _(corrects an over-count)_, plus a fixed crash when Cremate / Recruit Mercenary / Summon Illusory Tree resolved their minions).

### Calculations — crit

- **Every hit now gets the inherent 5% base crit** even on skills whose data omitted the field (they showed 0% crit and a dead crit calc before). _Affects:_ Shatter Strike, Wandering Spirits, and ~200 others.
- **Weapon-delivery skills now register as "hits"** so their crit calc runs at all (melee / bow / throwing).
- **Super Critical Strikes modeled** — only once your uncapped crit exceeds 100% (as in-game); affects Full DPS. _Affects:_ Truesight Glass. Builds under 100% crit are unchanged.
- **Boss crit-damage reduction** — new non-crit / crit / crit-weighted breakdown reflecting that bosses take reduced bonus crit damage. _(display only)_

### Calculations — core

- **Leech reworked to Last Epoch's instance-based model** (replacing an inert port whose caps had zeroed all leech). Affects leech/recovery values only, not offensive DPS.
- **Missing-mana / not-full-mana scaling implemented** ("per X Missing Mana", "while Not Full Mana"), previously dropped. _(off by default)_ — the planner assumes full mana until you set the missing-mana config.
- **"per 1 Mana Cost" melee affix family** now scales off the active skill's mana cost (was mis-scoped to the basic attack and contributing ~0); Damage variant capped at 20, Crit/Area uncapped. Related: **Brutality** grants its intrinsic per-mana-cost melee more damage. _Affects:_ Forge Strike, Warpath, Rive (a root cause of Forge Guard melee under-count).
- **Cross-element attribute scaling fixed** — "per `<attribute>`" mods sum the converted attribute total; intrinsic bonuses use the raw attribute. _Affects:_ fully-converted builds (e.g. converted-Strength Druids).
- **Chance-based "Gain Ward on Hit/Kill"** now resolves via a Min/Average/Max selector (Config tab → "Resource gain calculation mode"). _(display only)_
- **Skill level cap shows the correct base (20)** instead of allocated tree points.
- **Determinism fixes** — tree tag-swaps and skill-stat merges resolve identically every load, so a build's DPS no longer varies between runs.

### Triggers (skill/affix details)

- Added the missing trigger sub-skills so triggered skills can actually deal damage: Fire Burst, Zap, Ice Spike, Mana Arc, Divine Bolt, Wind Tempest, plus Runemaster Spark Nova / Lightning Explosion.
- **Fire Aura affixes** are modeled as a stacking aura DoT rather than discrete casts.
- **Fixed Full DPS double-counting from self-triggering / cycle skills** — a self-triggering skill (e.g. "Shurikens from Shurikens") was being _halved_; triggered copies are now added on top, and duplicate self/timer-triggered copies are hidden from the Main Skill selector.
- **Fixed "50% Additional Shurikens Chance"** being read as a full recast (it's an extra-projectile chance) — removed a phantom Shurikens DPS entry. _(corrects an over-count)_
- **Fixed a trigger resolving onto the wrong same-named skill** (player vs minion) — player skills are now preferred, deterministically.

### Defence, Ward & mitigation

- **Ward decay uses the game's exact formula**, retention clamped at −90%; Net Ward Regen uses unrounded decay; passive vs event-driven ward regen separated so the displayed "Added Ward Per Second" matches the game.
- **"% of Max Health as Ward Decay Threshold" now applies** (was dropped). _Affects:_ Architects of Astral Blood and similar.
- **"% of Current Health → Ward on directly-cast Necrotic/Elemental spell" implemented.** _(off by default)_ _Affects:_ Twisted Heart of Uhkeiros + the crafted affix.
- **Resistance display rounds half-up** (was truncating — a uniform −1% on many resistances); fractional resist base preserved through buff scaling; corrupted sealed "All Resistances" roll corrected.
- **Health / Mana totals now floor** to match the in-game character sheet.
- **Damage-over-Time-Taken defence stats added**, including a "Less Damage over Time Taken" row folding in the inherent 15% DoT reduction; fixed off-hand dual-wield conditions never activating.
- **Flame Ward's "Barrier" node treated as defensive**, not a DPS penalty (activating Flame Ward previously cut damage up to 40% by mistake). _(corrects an over-count)_
- **Form skill-tree nodes gated behind being in that form** _(off by default)_, so imported builds don't over-count armour/HP/damage out of form.
- **Fixes:** cross-class import + Save no longer crashes the defence calc; block / life-on-block / mana-on-block zero out with no shield; the **Apophis & Majasa** and **Temple of Eterra** quest rewards each correctly grant **+1 to all attributes** (two separate +1 bonuses, verified in-game).

### Skills by class

_Most items below are corrections where a skill was reading under, over, or 0 — see tags._

**Sentinel — Void Knight**

- **Void Knight echo** (mastery): +10% more damage to eligible melee/throwing/void skills was unmodeled; now applies (movement skills & Anomaly excluded).
- **Per-Vitality void** now a multiplicative _more_ (was flat additive).
- **Singular Purpose** now doubles below 30% block chance (clause was unmodeled).
- **Devouring Orb** modeled as a persistent 0.25s re-pulse (was one hit per cast — ~13× under).
- **Rive** Temporal Warrior Physical→Void conversion now works (allocation-gated).
- **Erasing Strike** conditional nodes (Final Hour/Chamber, Merciful, Ruthless as _more_; Obliteration 2H doubling) — were dropped or mis-typed; most apply only with the enemy-state config on _(off by default)_, except Merciful.

**Sentinel — Paladin**

- **Healing Hands** — Searing Light offensive fire hit (Healing Hands dealt no hit damage before); Seraph Blade spell→melee conversion.
- **Consecrated Ground (Judgement)** modeled as a fire DoT (was structurally absent — up to ~95% of some builds' damage); pure-DoT skills now receive DoT scaling.
- **Holy Aura** intrinsic +30% damage aura _(off by default)_; **Symbols of Hope** innate +3 fire per active symbol + Empowering Symbols per-symbol damage (both were missing).
- **Call To Arms** grants _increased_, not _more_, physical. _(corrects an over-count)_
- **Divine Flare** node-gated sub-skill. _(per-hit only)_

**Sentinel — Forge Guard**

- **Vengeance** — Flaming Sword Physical→Fire conversion now works; **Iron Blade** (Blade Assault) granted (was zero), and a leak of "Iron Blade Damage" onto Vengeance itself fixed.
- **Manifest Armor** minion abilities (Forge Breath / Whirlwind / Charge) modeled; Charge base halved and spurious attribute scaling dropped. _(corrects an over-count on Charge; per-hit only)_
- **Smelter's Wrath** max-charge ramp (up to +100% more) modeled (~2× under; defaults to max charge, config-overridable), plus its charge-scaling tree nodes.

**Mage — Sorcerer / Spellblade / Runemaster**

- **Elemental Nova** — added-spell pool now reaches the tree-gated types (~24× under before); each type gated on its "Enables X Nova" node.
- **Glacier** three-explosion combined hit (~8% of real output before). Validated +2%.
- **Static Orb** body-contact hit added (~40% per-cast under before).
- **Spellblade** — Enchant Weapon buff (passive +15% auto; active +50% _(off by default)_); mastery "weapon melee added also gained as added spell" (was a no-op, −40% of weapon added).
- **Firebrand** — per-stack added melee fire, continuous per-stack nodes, and "+X Maximum Stacks" (was hardcoded to 4); **Flame Wave** (Pyre grant) now inherits caster melee-hit context (~4.4× under before).
- **Runemaster** — Lightning Blast Convergence chain re-hit + doublecast/quadcast rate (~3× under; validated −3.5%); Spark Charge detonation now granted into Full DPS; Static Orb → Charged Ground grant active.
- **Volcanic Orb → Cold** skill-name conversion now applies (Meteor stays fire).

**Acolyte — Warlock / Necromancer / Lich**

- **Chthonic Fissure — major remodel** as a multi-stack DoT: ailment source moved to the released Spirits; **Torment** necrotic curse (dominant ~74–78%) now caps at 6 stacks (was 1 — ~6× under); persistent fissure fire DoT granted; Fissure of Wrath node modeled; Chaos Bolts tree conversions scoped to Chaos Bolts only.
- **Flame Whip** (cast by the Chthonic Fissure unique node) now modeled (was dropped as unsupported despite ~84% of some builds' damage); Spine of Malatros crit-multi scoped to it.
- **Chaos Bolts — Exult in Misery** more-damage per distinct negative ailment. _(off by default — count defaults to 0)_
- **Profane Veil — Profane Orbs** explosion (the real ~91% of damage) modeled (~10× under before). _(per-hit only)_
- **Drain Life / Disintegrate / Ghostflame** channel DoTs now non-zero (see ailments section).
- **Assemble Abomination** absorb scaling (+5%/minion, cap 20) and per-absorbed-type tree mores. _(off by default — count defaults to 0)_ Spoils of War +30% is _(data only)_.
- **Flay — Exquisite Blood** now transforms to a spell (was a weapon melee attack — ~23× too high). _(corrects a large over-count)_

**Rogue — Bladedancer / Marksman / Falconer**

- **Elemental Arrows** resource modeled (per-consumed fire/lightning added + increased elemental); "with Elemental Arrow" increased is one condition, not per-arrow. _(the per-arrow reading was an over-count)_
- **Heartseeker** — Molten Arrowstorm / Controlled Icicle conversions now work (allocation-gated); Dragonfang per-stack fire _(off by default)_.
- **Hail of Arrows** physical→fire/cold now a whole-attack conversion (physical was over-read).
- **Shadow Daggers finisher** calibrated (melee-delivery only; sceptres no longer treated as maces); **Bladestorm** storm-tick base modeled.
- **Shadow Cascade — Dagger Dance** conversion mechanism modeled — **magnitude still being calibrated** (reads low; no fabricated number).
- **Shadow Rend** manifest shadows — _(data only — not active yet)_.
- **Dancing Strikes — Rhythm** per-stack global crit-multi / more now correctly per-stack _(off by default — was applying full value at 0 stacks)_; **Flow-conditional** family modeled (Consuming Flow _(off by default)_).
- **Falcon** — scores its real Aerial Assault (was an unused placeholder); duplicate per-Dex + phantom per-Int removed _(corrects a ~33% over-count)_; now receives Falconry per-Dex and Tactician flat added; **Feather Knives** granted _(per-hit)_; Aerial Prowess _(off by default)_; Avian Hurl / Avian Arsenal wired (Avian Arsenal _(off by default)_, magnitudes not yet capture-validated).
- **Ballista** firing rate fixed — restored the intrinsic per-Dexterity attack speed (had been mistakenly removed, under-reading Dex builds), recalibrated base rate, fires weapon-independently, and routes "Increased Ballista Attack Speed" affixes to the turret.
- **Explosive Trap** now deals its real damage via the Spark Discharge child (read ~0 before). _(per-hit)_

**Primalist — Druid / Shaman / Beastmaster**

- **Bear — Swipe / Earthquake** now hit off the bear's own weapon base (Swipe was ~2.2× under); Earthquake gets 6× effectiveness + Seismic Tide triple-slam (validated −2.2%); Bear folds Melee+Swipe+Earthquake into Full DPS.
- **Raptor — Cornered** now scales with the Raptor's own missing health (was a permanent flat bonus at full HP). _(off by default; corrects an always-on over-count)_
- **Avalanche** — Fissures From Large Boulders grant; Intensity "Large Boulder Chance" modeled as expected-value double-damage (was dropping the whole ×2.0 contribution); Grounding gated on having a totem.
- **Grounding Conduit** now conditional _increased_ lightning, not unconditional _more_. _(corrects an over-count)_
- **Gathering Storm** Storm-Bolt nodes re-scoped to all Storm Bolt instances (one had leaked onto the triggered bolt / melee).
- **Frost Claw — Chaos Whirl** double ice spirals modeled as expected-value (was always ×2.0). _(corrects an over-count)_
- **Totems** — Spiked Totems scales Healing Totems as Thorn Totems; totem attacks correctly ignore cast speed; **Upheaval's Shatter Totem** child modeled _(per-hit)_; new pipeline for tree-node pack summons (Spriggan Form Healing Totems).

**Cross-class**

- **Marked for Death** now reduces the enemy's resistances by 25 (marked enemies took normal damage before). _(off by default)_
- **Fire Aura (Flame Ward grant)** remodeled as a single-stack aura DoT (was treated as ~17 spammed stacks); scales with uncapped fire resistance.
- **Maelstrom** active-stack config override _(off by default — unset = unchanged)_.

### Uniques & Sets

- **Truesight Glass** — Super Critical Strikes (see crit section); affects Full DPS above 100% crit.
- **Whetstone Gavel** — "effectiveness of stats on an offhand Exalted Weapon" now scales those stats (was a no-op); large effect, flagged for in-game verification.
- **Thornshell** — flat-reflect-per-Attunement now applies (~13× under before; validated −4.4%).
- **Riverbend Grasp** — on-hit Axe Throw proc now functional (+16–26% Full DPS on affected builds; proc-rate magnitude deferred).
- **Stygian Coal** — Stygian Beam cast frequency per Intelligence now scales (was an empty parse). _Affects:_ Lich Drain Life / Stygian Beam.
- **Hammer of Lorent**, **Frozen Ire**, **Foot of the Mountain** — per-character-level and stacking mods that had been silently dropped in data transcription are restored (Foot of the Mountain's stationary conversion is _(off by default)_).
- **Wings of Discord** (different-shape idol doubling), **Ricochet** (pierce chance → crit multi), refracted-slot rank gating — modeled.
- _(off by default — per-stack effects that default to 0):_ **Event Horizon** Dilation, **Eye of Reen** (Reen's Ire), **Throne of Ambition**, **Roots of Vithrasil** (Germination), **Bulwark of the Last Abyss** (Apocalypse), **Death's Door** low-life crit multi, **Stormhide Paws** empowered Swipe; **Fangs of the Berserker** Frenzy scalars and **Chronicle of the Damned** inflict-Damned are modeled (magnitude/condition deferred).
- **Chance-conversion uniques now functional:** Carrion of Creation, Liath's Machinations, Apex of Thought, Vial of Volatile Ice. _(inert until equipped)_
- **Julra's Obsession** minion stat-propagation (see minions).
- **Sets** — per-Complete-Set scaling, Apiarist auto-summon, Legends Entwined wildcard membership; equipped set bonuses shown in the Calcs tab.

### Items, Affixes & Idols

- **Affix rounding now matches the in-game per-affix tooltip** — `%` affixes floor to the game's shown value (e.g. 21% → 20%); resistance and other rolls reworked to the game's exact rounding, fixing frequent off-by-1 drift. Resistance display rounds half-up.
- **Per-Complete-Set integer attribute affixes** roll a whole number per set piece (was under-counting, e.g. 9 → 10 All Attributes). _Affects:_ Legends Entwined.
- **Omen Idol** — capacity is now altar-layout-based (label matches the in-game header), slots auto-populate on build load from idols overlapping Refracted cells, and the "Refracted N" label was restored (was "Fractured"); refracted slots respect their in-game unlock rank _(new config, default = previous behavior)_.
- Corrupted-idol affix scaling made consistent; multi-slot idol icons no longer have a border cutting across them.
- Item req-level reflects affix tiers and respects a unique's own level-requirement override.
- 1.4 unique data corrections: Ruby Fang Aegis (Ruby Venom 8→10s), Blade of the Forgotten Knight (attack/cast speed 15→20%), Fragments of the Shattered Lance, Exulis, Cursed Coin Amulet implicit sign, and more.

### Import

- **Offline-save reader now reads all affix slots** (previously stopped early and silently dropped affixes, e.g. a 6th affix on Slammed + Sealed items) — up to 7 slots for gear, and it now **surfaces a "dropped affix" count** so lost data is visible instead of silent.
- **Phantom vs dropped reclassification** — trailing bytes on Omen/Woven idols and Prophesied Altars were mis-read as bogus affixes and counted as "dropped"; now correctly identified as phantom (logged, not counted), and such bytes can no longer be imported as a real affix onto a grid idol.
- **Legendary (Legendary Potential) items import correctly** — the save rarity byte is decoded properly, so exalted-fused legendaries load their unique mods (were mis-imported as plain Exalted); fused-affix parse hardened against crashes.
- **Unspecialized bar skills are now imported** (were skipped), so low-level builds don't lose a barred skill's base damage.
- Import can resolve **Last Epoch Tools profile / character URLs** (not just planner links); the quest-reward toggles (Apophis & Majasa, Temple of Eterra) are now set automatically from your completed quests on import.
- Fixed a renderer crash (invalid image handles) after importing certain builds (notably Reforged-set builds); duplicate offline-character entries no longer shown.

### Config tab

- **Config Sets UI** (see Notable Changes) — named presets with New / Copy / Rename / Delete / reorder.
- **Build-relevance auto-highlight** — highlighted configs auto-show without "Show All"; tooltips name the specific node / skill / item (and affix line); clutter reduced (buff/stack and enemy-ailment state configs show only when a build modifier references them).
- Long Config tooltip lines now wrap on-screen instead of running off the edge; two inert leftover options were removed; and re-importing a different build no longer keeps the previous build's highlights.

### Notes tab

- **Markdown support** with Edit/Preview toggle and help tooltip — see Notable Changes for the full capability list; bundled example note templates.
- **Preview / Edit refinements** — the Preview scroll extent now covers the full rendered height (no cut-off past the cached measure), and Edit↔Preview layout / scroll sync were tightened.

### UI & Misc

- Per-skill total renamed **"Combined DPS"**; added **Stable Ward** and **Potion Slots** rows; regrouped Ward / Armor / Endurance; renamed "Attack Dodge Chance" → "Dodge Chance"; long stat labels auto-wrap.
- Redundant rows hidden when they add nothing (Average Damage / Effective Crit Chance at 100% hit chance; Net Ward Recovery at +0.0).
- **Read-only tree preview** — clicking a locked/unassignable skill opens its tree read-only instead of doing nothing.
- Item / idol tooltips wrap long mod lines inside the box; tab buttons show their keyboard shortcut on hover, and tabs can now be switched directly with those keyboard shortcuts.
- **Calcs and Config tabs** — text that previously ran past its section box now wraps / clips inside the panel.
- **Tooltip text hierarchy** — set-item, item sub-type, and blessing lines render at a smaller size than the item name; attribute values use per-attribute text colours for quicker reading.
- Added a **donation / support link**.
- Items tab: weapon slots labelled "Weapon" / "Off-hand", tighter header; tree header badges centered; dedicated Off-Hand Catalyst icon; refreshed item-type icons.
- Fixed an Items-tab renderer crash from asynchronous icon loading.

### Craft & Tooltips

- Craft affix dropdown shows the **affix name** with a per-tier (T1–T8) hover tooltip; duplicate names disambiguated with (added)/(increased)/(more)/(reduced)/(less).
- **Experimental affixes** (belt / boots / gloves) available under an "Experimental" subcategory.
- Stripped narrative "flavor" sentences from craft tooltips so they show scaling info without boilerplate; idol-altar label / typo fixes.

### Parser / mod recognition

- Recognized many previously-unhandled phrasings so more affixes and tree lines actually apply — e.g. Damage over Time Penetration (was mis-read as a damage boost), "to Moving Enemies", "Against Distant Enemies", "Against/vs Rares and Bosses", "at Full Health" (self and enemy), "to Low/High Health Enemies", "per N current mana", weapon-hand conditionals, healing / healing-effectiveness, and various ailment-penetration and crit-multi aliases.
- Fixed affixes parsed as the wrong kind (bare-form item damage was "more" instead of "increased"; "+N% Mana/Health Regen" is increased, not flat).

### Data & Compatibility

- **Verified compatible with LE 1.4.7** (bug-fix-only patch; no build-data changes required).
- Added missing data: previously-missing minions and their skills, Doom / Necrotic Bone Curse ailments, and minion skill lists corrected to the game's values.
- Corrected numerous 1.4 affix display ranges and slot-override values against the game; cleaned up duplicate unique entries.
- **Retired 1.2 / 1.3 tree data** from the version selector — older tree versions are hidden to reduce clutter; existing builds are unaffected.
- Synced 4 passive-tree node tooltips to the game's canonical text:
  - Elixir of Knowledge (Mage): "5% increased Mana Regen" → "5% Mana Regen"
  - Gemini (Mage): "+8% More Damage Taken While Dual Wielding" → "+8% Damage Taken While Dual Wielding"
  - Infinite Bulwark (Sentinel): dropped a stray leading space on "100% Armor -> Minion Healing"
  - Covenant of Protection (Sentinel): removed a stale duplicate "+6 Health Regen" line (the live "+5" line was already correct)
- README: added a Linux / Wine usage section.

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

Your build _KoraWasteTime lv91 Spellblade_ almost broke my heart.
It was pure PAIN to implement — but hey, you cooked such a complex build. Congrats.

_One person, five builds — single-handedly broke the Blessing system, broke the Crit calc, and made me question every Resist value._

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
