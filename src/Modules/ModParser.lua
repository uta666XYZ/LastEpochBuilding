-- Last Epoch Building
-- @leb-canary v1 / id:leb-c3f1a7-modparser-2026 / do-not-remove (see Development/リリース手順.md)
--
-- Module: Mod Parser for 3.0
-- Parser function for modifier names
--
local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local band = bit.band
local bor = bit.bor
local bnot = bit.bnot
local m_huge = math.huge
local function firstToUpper(str)
	return (str:gsub("^%l", string.upper))
end

-- List of modifier forms
local formList = {
	["^([%+%-]?[%d%.]+)%% increased"] = "INC",
	["^([%+%-]?[%d%.]+)%% reduced"] = "RED",
	-- @leb-regression-guard:shadow-suffix-family-c6b-followup-f2
	-- No-% "Increased" promotion. LE's "Increased X" is ALWAYS percent-
	-- scaling; some affix text drops the % sign (e.g. "+1 Increased
	-- Damage for skills used by Shadows"). Without this rule the parser
	-- treats it as BASE and leaves " Increased " in slot[2] as residue
	-- while the BASE mod applies inappropriately. Earliest-start +
	-- longest-match in scan() ensures this beats the bare "+N" BASE rule
	-- for any line containing "Increased". Same applies to "Reduced".
	["^([%+%-]?[%d%.]+) increased"] = "INC",
	["^([%+%-]?[%d%.]+) reduced"] = "RED",
	["^([%+%-]?[%d%.]+)%% more"] = "MORE",
	["^([%+%-]?[%d%.]+)%% less"] = "LESS",
	["^(%d+)%% faster"] = "INC",
	["^(%d+)%% slower"] = "RED",
	-- @leb-regression-guard: bare-form-damage-affix-increased
	-- A bare "+N% <Type> Damage" (no "increased"/"more" word) falls here and
	-- becomes a MULTIPLICATIVE damage MORE. That default is CORRECT for the
	-- many skill/tree nodes whose description genuinely says "more" yet render
	-- bare (e.g. "+200% Vine Melee Damage", "+10% Riposte Fire Damage").
	-- BUT five LE ITEM-AFFIX families had their "increased" keyword dropped in
	-- the LE->LEB extraction, so their bare templates were over-inflated as MORE
	-- (datamine multi_affixes_v3.json modifierType=1=Increased, NOT 2=More):
	--   959 Keplahan's Cryolith (Cold), 960 Keplahan's Pyrolith (Fire),
	--   961 Kuzon's Fury (Fire), 986 "Increased Melee Damage ..." (Melee, the
	--   Rusted Cleaver "Cleaver Solution" sealed affix), 1090 Rogue's/Bladestorm
	--   (Throwing). The fix is DATA-side (Data/ModItem_1_4.json + Data/ModItem.json:
	--   the templates now read "(X)% increased <Type> Damage") -- NOT a broad
	--   parser promotion of bare damage->INC, which would wrongly flip the genuine
	--   bare-MORE skill nodes above. Affix 979 "...More Damage against Poisoned
	--   Enemies" (Global Conditional, modifierType=2=More) is deliberately LEFT bare.
	-- Spec: spec/System/TestBareFormDamageAffixIncreased_spec.lua
	-- See REGRESSION_GUARDS.md "bare-form-damage-affix-increased".
	["^([%+%-]?[%d%.]+)%%"] = "BASE_MORE",
	["^([%+%-]?[%d%.]+)"] = "BASE",
	["^([%+%-][%d%.]+)%%? to"] = "BASE",
	["^([%+%-]?[%d%.]+)%%? of"] = "BASE",
	["^([%+%-][%d%.]+)%%? base"] = "BASE",
	["^([%+%-]?[%d%.]+)%%? additional"] = "BASE",
	["^you gain ([%d%.]+)"] = "GAIN",
	["^gains? ([%d%.]+)%% of"] = "GAIN",
	["^gain ([%d%.]+)"] = "GAIN",
	["^gain %+(%d+)%% to"] = "GAIN",
	["^you lose ([%d%.]+)"] = "LOSE",
	["^loses? ([%d%.]+)%% of"] = "LOSE",
	["^lose ([%d%.]+)"] = "LOSE",
	["^lose %+(%d+)%% to"] = "LOSE",
	["^(%d+)"] = "BASE",
	["^([%+%-]?%d+)%% chance"] = "CHANCE",
	["^([%+%-]?%d+)%% chance to gain "] = "FLAG",
	["^([%+%-]?%d+)%% additional chance"] = "CHANCE",
	["^you have "] = "FLAG",
	["^have "] = "FLAG",
	["^you are "] = "FLAG",
	["^are "] = "FLAG",
	["^gain "] = "FLAG",
	["^you gain "] = "FLAG",
}

-- Map of modifier names
local modNameList = {
	-- Attributes
	["all attributes"] = Attributes,
	-- Life/mana
	-- @leb-regression-guard: regen-alias-coverage
	-- In-game tooltips render regen affixes in BOTH short (`Regen`) and long
	-- (`Regeneration`) forms — registering only one silently drops half the
	-- affix pool. Both Life and Mana must have both keys.
	-- Test: spec/System/TestRegenAlias_spec.lua
	-- See REGRESSION_GUARDS.md "regen-alias-coverage".
	["health leech"] = "DamageLifeLeech",
	["health"] = "Life",
	["health regen"] = "LifeRegen",
	["health regeneration"] = "LifeRegen",
	["maximum health"] = "Life",
	-- @leb-regression-guard:firebrand-tree-max-stacks (name site)
	-- Firebrand tree "+X Maximum Stacks" nodes (f1b4d-9 Wildfire, f1b4d-18 Ardent Branding),
	-- rewritten node-id-keyed to "+X Firebrand Maximum Stacks" by LE_TREE_NODE_STAT_REWRITE so
	-- they map to BASE FirebrandMaxStacks; CalcOffence raises Firebrand's max stacks (base 4) by it.
	["firebrand maximum stacks"] = "FirebrandMaxStacks",
	-- @leb-regression-guard:elemental-arrows-resource (resource-config stat names)
	-- Rogue/Marksman Elemental Arrows resource config: extra-consumed-per-bow-attack (Rogue-32
	-- Elemental Barrage "+1 ... consumed per bow attack"). The max cap + generation rate are
	-- bare-number ("3 Maximum Elemental Arrows") so they are matched in specialModList (the
	-- "Maximum X" name path here needs a leading "+"). CalcPerform reads Max + ExtraConsume to
	-- derive the steady-state consumed count -> Multiplier:ElementalArrowConsumed.
	["elemental arrow consumed per bow attack"] = "ElementalArrowExtraConsume",
	["elemental arrows consumed per bow attack"] = "ElementalArrowExtraConsume",
	["mana"] = "Mana",
	["maximum mana"] = "Mana",
	["mana regen"] = "ManaRegen",
	["mana regeneration"] = "ManaRegen",
	["mana cost"] = "ManaCost",
	["mana efficiency"] = "ManaEfficiency",
	["channel cost"] = "ChannelCost",
	-- Primary defences
	["armour"] = "Armour",
	["armor"] = "Armour",
	["dodge rating"] = "Evasion",
	["ward"] = "Ward",
	["endurance"] = "Endurance",
	["endurance threshold"] = "EnduranceThreshold",
	["ward decay threshold"] = "WardDecayThreshold",
	["maximum omen idols equipped"] = "MaximumOmenIdols",
	["maximum omen idols"] = "MaximumOmenIdols",
	["corrupted idol limit"] = "CorruptedIdolLimit",
	["heretical idol limit"] = "HereticalIdolLimit",
	["ward per second"] = "WardPerSecond",
	["ward retention"] = "WardRetention",
	["ward regen"] = "WardPerSecond",
	-- Idol affix (idol_900_0 Suffix): "(N) Ward gained per second while wielding a Staff".
	-- Without this alias the parser stripped "Ward" + numeric, treated the "gained per
	-- second" tail as unmatched residue, and the BASE mod fell through to `Ward` (max
	-- ward) instead of `WardPerSecond`. See spec/System/TestWardGainedPerSecond_spec.lua.
	["ward gained per second"] = "WardPerSecond",
	-- Unique mods (uniques_1_4.json L4631 "Symbol of Hope" & L7464 unique helmet):
	-- "(N) Ward gained each second per Active Wandering Spirit". Same silent-failure
	-- shape as the staff idol — without this alias the BASE fell through to `Ward`
	-- with residue "  gained each second  " and the `per Active Wandering Spirit`
	-- multiplier was glued to the wrong stat.
	["ward gained each second"] = "WardPerSecond",
	-- Rune Master tree node (tree_1.json L12835 "Empowered Runes" rn7iv-13):
	-- "+4 Ward Gain Per Second per Gon Rune". Drops the "-ed" suffix relative
	-- to the staff idol wording. Without this alias the BASE fell through to
	-- the bare `Ward` stat (max ward) with residue "  Gain Per Second per
	-- Gon Rune " and the `per Gon Rune` Multiplier (added separately above)
	-- was glued to max Ward rather than to WardPerSecond.
	["ward gain per second"] = "WardPerSecond",
	["glancing blow chance"] = "GlancingBlowChance",
	["chance to take 0 damage when hit"] = "GlancingBlowChance",
	-- @leb-regression-guard:chance-to-receive-glancing-blow-when-hit
	-- Item affix wording: `(10-24)% Chance to receive a Glancing Blow when hit`
	-- (e.g. <private build> lv66 Bladedancer). The form scanner consumes `N% chance`
	-- as the CHANCE form, leaving the tail starting with `to receive ...`,
	-- so the modNameList key must match the tail (no leading "chance").
	-- See REGRESSION_GUARDS.md "chance-to-receive-glancing-blow-when-hit".
	["to receive a glancing blow when hit"] = "GlancingBlowChance",
	["block effectiveness"] = "BlockEffectiveness",
	["stun avoidance"] = "StunAvoidance",
	["crit avoidance"] = "CritAvoidance",
	["critical strike avoidance"] = "CritAvoidance",
	-- Damage Reflected (LE thorns)
	["damage reflected to attackers"] = "DamageReflectedToAttackers",
	-- @leb-regression-guard: thornshell-flat-reflect-per-attunement
	-- Thornshell carries "(3-6)% Increased Flat Damage Reflected to Attackers per
	-- Attunement" — the "flat" prefix on the INCREASED form must resolve to the same
	-- stat as the BASE "+N Damage Reflected to Attackers". Without this key the whole
	-- per-Attunement INC is residue-dropped, so LEB read the flat reflect (in-game
	-- "Thorns") ~13x under (HitMeBabyOneMoreTime: LEB 2682 vs in-game 34609, Att 189).
	["flat damage reflected to attackers"] = "DamageReflectedToAttackers",
	-- Validation provenance is retained in maintainer notes.
	["damage reflected"] = "DamageReflectedPercent",
	["minion damage reflected"] = "MinionDamageReflectedPercent",
	-- Resistances
	["elemental resistance"] = { "FireResist", "LightningResist", "ColdResist" },
	["elemental resistances"] = { "FireResist", "LightningResist", "ColdResist" },
	["all resistances"] = { "FireResist", "LightningResist", "ColdResist", "PhysicalResist", "PoisonResist", "NecroticResist", "VoidResist" },
	-- Damage taken
	["damage taken"] = "DamageTaken",
	["damage over time taken"] = "DamageTakenOverTime",
	["elemental damage taken"] = "ElementalDamageTaken",
	["elemental damage taken over time"] = "ElementalDamageTakenOverTime",
	-- Other defences
	["block chance"] = "BlockChance",
	["health gained on block"] = "LifeOnBlock",
	["health gain on block"] = "LifeOnBlock",
	["mana gained on block"] = "ManaOnBlock",
	["mana gain on block"] = "ManaOnBlock",
	["ward gained on block"] = "WardOnBlock",
	["ward gain on block"] = "WardOnBlock",
	["ward gained on potion use"] = "WardOnPotionUse",
	["ward gain on potion use"] = "WardOnPotionUse",
	["mana gained on potion use"] = "ManaOnPotionUse",
	["mana gain on potion use"] = "ManaOnPotionUse",
	["health gained on potion use"] = "LifeOnPotionUse",
	["health gain on potion use"] = "LifeOnPotionUse",
	["ward gained when you use .+"] = "WardOnSkillUse",
	["ward gain on kill"] = "WardOnKill",
	["ward on hit"] = "WardOnHit",
	["ward gain on hit"] = "WardOnHit",
	["ward gained on hit"] = "WardOnHit",
	["ward gained on critical strike"] = "WardOnCrit",
	["ward gain on critical strike"] = "WardOnCrit",
	["ward on critical strike"] = "WardOnCrit",
	["of potion health converted to ward"] = "PotionHealthConvertedToWard",
	["potion health converted to ward"] = "PotionHealthConvertedToWard",
	-- Stun/knockback modifiers
	["stun duration on you"] = "StunDuration",
	["armor while channelling"] = "ArmourWhileChannelling",
	["leech rate"] = "LeechRate",
	["stun duration"] = "EnemyStunDuration",
	["knockback distance"] = "EnemyKnockbackDistance",
	-- Auras/curses/buffs
	["buff effect"] = "BuffEffect",
	["haste effect"] = "HasteEffect",
	["frenzy effect"] = "FrenzyEffect",
	["holy aura effect"] = "HolyAuraEffect",
	["symbols of hope effect"] = "SymbolsOfHopeEffect",
	["holy aura and symbols of hope effect"] = { "HolyAuraEffect", "SymbolsOfHopeEffect" },
	-- On hit/kill/leech effects
	["health gain on kill"] = "LifeOnKill",
	["health gain on hit"] = { "LifeOnHit", flags = ModFlag.Hit },
	["health gain on melee hit"] = { "LifeOnMeleeHit", flags = bor(ModFlag.Melee, ModFlag.Hit) },
	["health gained on melee hit"] = { "LifeOnMeleeHit", flags = bor(ModFlag.Melee, ModFlag.Hit) },
	["health on melee hit"] = { "LifeOnMeleeHit", flags = bor(ModFlag.Melee, ModFlag.Hit) },
	["health gain on stun"] = "LifeOnStun",
	["health gained on stun"] = "LifeOnStun",
	["health gain on freeze"] = "LifeOnFreeze",
	["health gained on freeze"] = "LifeOnFreeze",
	["health gain on crit"] = "LifeOnCrit",
	["health gained on crit"] = "LifeOnCrit",
	["health gain on critical strike"] = "LifeOnCrit",
	-- Mana / Companion / Potion / Overkill summary stats (LETools parity)
	["overkill health leech"] = "OverkillLeech",
	["overkill leech"] = "OverkillLeech",
	-- @leb-regression-guard:overkill-damage-leech-parser
	-- Affix wording "(N)% of Overkill Damage Leeched as Health" must emit
	-- OverkillLeech (display-only summary), NOT generic DamageLifeLeech.
	-- LE applies overkill leech only to damage exceeding remaining HP, so
	-- routing through DamageLifeLeech (the prior behavior, where the
	-- generic "damage" modName + "leeched as health" suffix combined to
	-- produce DamageLifeLeech and left "Overkill" unconsumed) would
	-- over-leech every hit while leaving output.OverkillLeech = 0.
	-- Symptoms before fix: <private build> OverkillLeech LE=16 LEB=0; <private build>
	-- LE=9 LEB=0. Match must precede the generic "damage" entry; scan()
	-- picks earliest+longest, so this 4-word phrase wins. See spec
	-- TestModParser_spec.lua "overkill-damage-leech-parser".
	["overkill damage leeched as health"] = "OverkillLeech",
	["maximum companions"] = "MaxCompanions",
	["maximum number of companions"] = "MaxCompanions",
	-- @leb-regression-guard:shadow-suffix-family-c6a
	-- "+N Maximum Shadows" / "+N max Shadows" stat (count cap on the
	-- Bladedancer Shadow pool). 3 ModCache entries fell through with empty
	-- mods + residue " Maximum Shadows ".
	["maximum shadows"] = "MaxShadows",
	["max shadows"] = "MaxShadows",
	-- @leb-regression-guard:auto-summon-registry
	-- Apiarist bee auto-summon COUNT stats (fallback alias for variants the
	-- $-anchored specialModList handlers can't catch, e.g. the conditional
	-- "+8 Bees per 10 seconds while in Spriggan Form" whose trailing clause is
	-- consumed by the "while in spriggan form" Condition modTag). The plain
	-- and "+N%" forms are handled explicitly in specialModList (scanned first)
	-- to force BASE/INC; here they only serve the tail/conditional variants
	-- (always "+N", so BASE is correct). The longer "elemental bees..." key
	-- wins for the elemental variant via scan()'s earliest+longest rule.
	["elemental bees per 10 seconds"] = "ElementalBeesPerTenSeconds",
	["bees per 10 seconds"] = "BeesPerTenSeconds",
	["potion slots"] = "PotionSlots",
	-- @leb-regression-guard: weaver-will-equipped-autocount
	-- Singular "Potion Slot" alias. Communion of the Erased's per-item mod is
	-- baked into saved build XML as "+1 Potion Slot per equipped Weaver Item"
	-- (singular name). Without this alias modNameList only matched the plural
	-- "potion slots", so the modName scan failed and the whole mod dropped,
	-- leaving PotionSlots stuck at the implicit 3 instead of 3 + per-item count.
	-- scan() is earliest+longest: for plural text the 12-char "potion slots"
	-- still wins over this 11-char alias, so plural parsing is unaffected.
	-- See REGRESSION_GUARDS.md "weaver-will-equipped-autocount".
	["potion slot"] = "PotionSlots",
	["minion power from character level"] = "MinionPowerFromCharLevel",
	["health lost on kill"] = "LifeLossOnKillPercent",
	-- Projectile modifiers
	["extra projectiles"] = "ProjectileCount",
	["projectiles"] = "ProjectileCount",
	["daggers thrown"] = "ProjectileCount", -- Shadow Cascade Dagger Dance (dagg3-21/24); count of DaggerThrow projectiles thrown per cast
	["projectile speed"] = "ProjectileSpeed",
	-- Totem/trap/mine/brand modifiers
	["totem duration"] = "TotemDuration",
	-- Other skill modifiers
	["radius"] = "AreaOfEffect",
	["area"] = "AreaOfEffect",
	["area of effect"] = "AreaOfEffect",
	-- @leb-regression-guard:ailment-duration-routing
	-- Validation provenance is retained in maintainer notes.
	["bleed duration"] = "EnemyBleedDuration",
	["ignite duration"] = "EnemyIgniteDuration",
	["poison duration"] = "EnemyPoisonDuration",
	["frostbite duration"] = "EnemyFrostbiteDuration",
	["electrify duration"] = "EnemyElectrifyDuration",
	-- @leb-regression-guard:aura-of-decay-ailment-frequency (parser site)
	-- Aura of Decay's tree scales how OFTEN the aura applies its ailment (base 4/s,
	-- datamined RepeatedlyApplyAilmentsInRadius applicationInterval 0.25s). The nodes
	-- carry the verbatim display text "Ailment Frequency": ad0ry-2 Rot Weaver +8%/pt
	-- (max 3), ad0ry-5 Mana Blight +12%/pt (max 3), ad0ry-6 Poisoned Soul +50% (max 1).
	-- Keyed on the TEXT, deliberately NOT on the datamined property id 5056: 5056 is a
	-- GENERIC "frequency" property the game reuses across unrelated trees with different
	-- display texts (to50-6 "Lightning Frequency", bl5st-7 "Shurikens Frequency", arcas-17
	-- "Superconductor Frequency", vo54-13 "Explosive Ground Frequency", ...). Only ad0ry-2/5/6
	-- use the exact string "Ailment Frequency", so this key cannot leak to those skills --
	-- they stay unmapped/inert exactly as before. Rank scaling happens upstream
	-- (PassiveTree:ProcessNode multiplies the leading value by node.alloc BEFORE parseMod),
	-- so this rule only reads the already-scaled number. fl44-8 "Aura of Decay More Ailment
	-- Frequency" (a conditional, stacking, 4s-uptime MORE granted by a Flay melee hit) is a
	-- DIFFERENT text and stays inert -- modeling it needs an uptime config, out of scope here.
	-- Consumed by CalcOffence's AoD block as output.HitSpeed = 4 * (1 + AilmentFrequency/100).
	-- See REGRESSION_GUARDS.md "aura-of-decay-ailment-frequency".
	["ailment frequency"] = "AilmentFrequency",
	["duration"] = "Duration",
	["cooldown duration"] = "CooldownRecovery",
	["cooldown recovery"] = "CooldownRecovery",
	["cooldown recovery speed"] = "CooldownRecovery",
	["melee range"] = "MeleeWeaponRange",
	["to deal double damage"] = "DoubleDamageChance",
	["freeze rate multiplier"] = "FreezeRateMultiplier",
	["freeze rate"] = "FreezeRate",
	["stun chance"] = "StunChance",
	["kill threshold"] = "KillThreshold",
	["chance to find potions"] = "ChanceToFindPotions",
	-- Ailment application chances (from item affixes)
	["to slow"] = "SlowChance",
	["to apply slow"] = "SlowChance",
	["to apply frailty"] = "FrailtyChance",
	["to blind"] = "BlindChance",
	["to apply blind"] = "BlindChance",
	["to electrify"] = "ElectrifyChance",
	["to apply electrify"] = "ElectrifyChance",
	-- "to apply/inflict <basic ailment>" alt forms (complement the "<ailment> chance" set)
	["to apply bleed"] = "BleedChance",
	["to apply a bleed"] = "BleedChance",
	["to inflict bleed"] = "BleedChance",
	["to inflict a bleed"] = "BleedChance",
	["to apply ignite"] = "IgniteChance",
	["to inflict ignite"] = "IgniteChance",
	["to apply poison"] = "PoisonChance",
	["to inflict poison"] = "PoisonChance",
	["to apply shock"] = "ShockChance",
	["to inflict shock"] = "ShockChance",
	["to apply chill"] = "ChillChance",
	["to inflict chill"] = "ChillChance",
	["to apply frostbite"] = "FrostbiteChance",
	["to inflict frostbite"] = "FrostbiteChance",
	["to inflict time rot"] = "TimeRotChance",
	-- @leb-regression-guard:ailment-apply-parser-gap
	-- Time Rot and Doom each only registered their "to inflict X" / "doom chance"
	-- forms, but several uniques carry the "to apply X on Hit" phrasing instead
	-- (Doom's OFFICIAL descriptor is literally "Chance to apply Doom on Hit"
	-- [descriptors "1,0,90,0"]; Black Blade of Chaos stores "apply Time Rot on
	-- Hit"). With no "to apply" key the generic chain found no modName and the
	-- whole line silently returned {} (empty modList) -> the DoomChance /
	-- TimeRotChance addend never reached modDB (silent UNDER-count; the consumers
	-- are already fully modeled at CalcOffence.lua:2527/2531). These aliases map
	-- to the SAME primitive as the sanctioned "to inflict X" forms.
	-- Items landed: Siphon of Anguish (blast 64), Stymied Fate, Apathy's Maw
	-- (Doom); Black Blade of Chaos (Time Rot). The DEFENSIVE reflect variant
	-- "Chance to apply Time Rot to Attackers when Hit" (Property_Player_39,
	-- descriptors "98,39,0,0" -- Defiance of the Forgotten Knight) is a distinct
	-- stat and must NOT resolve to offensive TimeRotChance; its "to attackers
	-- when hit" tail keeps the generic chain from mistaking it (verified by spec).
	-- Spec: spec/System/TestAilmentApplyParserGap_spec.lua
	["to apply time rot"] = "TimeRotChance",
	["to inflict doom"] = "DoomChance",
	["to apply doom"] = "DoomChance",
	["doom chance"] = "DoomChance",
	["to apply damned"] = "DamnedChance",
	-- @leb-regression-guard:chronicle-damned-inflict-with-skill-per-spirit
	-- Damned only had the "to apply damned" / "damned chance" forms, unlike every
	-- other ailment above which registers BOTH "to apply X" and "to inflict X".
	-- Chronicle of the Damned (unique, id 247) rolls the "inflict" phrasing:
	-- "(11-16)% Chance to inflict Damned on Hit with Hungering Souls per Active
	-- Wandering Spirit". Without this key the generic chain finds no modName, so
	-- the whole line silently returned {} (empty modList) -> the DamnedChance
	-- addend never reached modDB (silent UNDER-count on the consumer side, which
	-- is already fully modeled: DamnedChance / DamnedBaseDamage=35 Necrotic DoT /
	-- Multiplier:ActiveWanderingSpirit). The "with Hungering Souls" SkillName tag
	-- and the "per Active Wandering Spirit" Multiplier tag are attached by the
	-- existing skillNameList/modTagList scans exactly as they already are for the
	-- working "to apply damned ... with Hungering Souls per Active Wandering
	-- Spirit" phrasing; the connector-only "with" residue is accepted by
	-- Item.lua isConnectorOnlyExtra. Stale empty ModCache row deleted so the fix
	-- parses live. Spec: spec/System/TestChronicleDamnedInflictWithSkill_spec.lua
	["to inflict damned"] = "DamnedChance",
	["damned chance"] = "DamnedChance",
	-- Basic ailment application chances (stat form without "to")
	["bleed chance"] = "BleedChance",
	["ignite chance"] = "IgniteChance",
	["poison chance"] = "PoisonChance",
	["shock chance"] = "ShockChance",
	["chill chance"] = "ChillChance",
	["frostbite chance"] = "FrostbiteChance",
	-- Alt "X chance" forms for ailments that only had "to X" or "to apply X" forms
	["frailty chance"] = "FrailtyChance",
	["electrify chance"] = "ElectrifyChance",
	["time rot chance"] = "TimeRotChance",
	["slow chance"] = "SlowChance",
	["blind chance"] = "BlindChance",
	-- Shred chance stat forms (complement existing "to shred X resistance" forms)
	["armor shred chance"] = "ArmorShredChance",
	["armour shred chance"] = "ArmorShredChance",
	["armor shred effect"] = "ArmorShredEffect",
	["armour shred effect"] = "ArmorShredEffect",
	["to shred physical resistance"] = "PhysicalResShredChance",
	["to shred fire resistance"] = "FireResShredChance",
	["to shred cold resistance"] = "ColdResShredChance",
	["to shred lightning resistance"] = "LightningResShredChance",
	["to shred necrotic resistance"] = "NecroticResShredChance",
	["to shred poison resistance"] = "PoisonResShredChance",
	["to shred void resistance"] = "VoidResShredChance",
	["physical res shred chance"] = "PhysicalResShredChance",
	["fire res shred chance"] = "FireResShredChance",
	["cold res shred chance"] = "ColdResShredChance",
	["lightning res shred chance"] = "LightningResShredChance",
	["necrotic res shred chance"] = "NecroticResShredChance",
	["poison res shred chance"] = "PoisonResShredChance",
	["void res shred chance"] = "VoidResShredChance",
	["plague chance"] = "PlagueChance",
	["to inflict plague"] = "PlagueChance",
	["witchfire chance"] = "WitchfireChance",
	["to inflict witchfire"] = "WitchfireChance",
	["spreading flames chance"] = "SpreadingFlamesChance",
	["to inflict spreading flames"] = "SpreadingFlamesChance",
	["to apply future strike"] = "FutureStrikeChance",
	["future strike chance"] = "FutureStrikeChance",
	["abyssal decay chance"] = "AbyssalDecayChance",
	["to inflict abyssal decay"] = "AbyssalDecayChance",
	["spirit plague chance"] = "SpiritPlagueChance",
	["to inflict spirit plague"] = "SpiritPlagueChance",
	-- Curse chances
	["bone curse chance"] = "BoneCurseChance",
	["to apply bone curse"] = "BoneCurseChance",
	["torment chance"] = "TormentChance",
	["to apply torment"] = "TormentChance",
	["decrepify chance"] = "DecrepifyChance",
	["to apply decrepify"] = "DecrepifyChance",
	["anguish chance"] = "AnguishChance",
	["to apply anguish"] = "AnguishChance",
	["penance chance"] = "PenanceChance",
	["to apply penance"] = "PenanceChance",
	["acid skin chance"] = "AcidSkinChance",
	["to apply acid skin"] = "AcidSkinChance",
	["exposed flesh chance"] = "ExposedFleshChance",
	["to apply exposed flesh"] = "ExposedFleshChance",
	-- Skill-specific ailment chances
	["serpent venom chance"] = "SerpentVenomChance",
	["to inflict serpent venom"] = "SerpentVenomChance",
	["hemorrhage chance"] = "HemorrhageChance",
	["to inflict hemorrhage"] = "HemorrhageChance",
	["ravage chance"] = "RavageChance",
	["to inflict ravage"] = "RavageChance",
	-- Debuff chances
	["critical vulnerability chance"] = "CriticalVulnerabilityChance",
	["to apply critical vulnerability"] = "CriticalVulnerabilityChance",
	["marked for death chance"] = "MarkedForDeathChance",
	["to apply marked for death"] = "MarkedForDeathChance",
	["stagger chance"] = "StaggerChance",
	["to apply stagger"] = "StaggerChance",
	-- Attacker debuff chances
	["to slow attackers"] = "ChanceToSlowAttackers",
	["to chill attackers"] = "ChanceToChillAttackers",
	["to shock attackers"] = "ChanceToShockAttackers",
	-- Defense stats
	["of damage dealt to mana before health"] = "DamageToManaBeforeHealth",
	["damage dealt to mana before health"] = "DamageToManaBeforeHealth",
	["of damage dealt to mana before ward"] = "DamageToManaBeforeWard",
	["damage dealt to mana before ward"] = "DamageToManaBeforeWard",
	["parry chance"] = "ParryChance",
	["healing effectiveness"] = "HealingEffectiveness",
	-- On-hit resource gains
	["health gained when you receive a glancing blow"] = "LifeOnGlancingBlow",
	-- Basic damage types
	["damage"] = "Damage",
	-- @leb-regression-guard:warpath-warslash-spin-duration-more (name site)
	-- Warpath "Giant Splitter" (va53st-21, Warpath tree, tree_2.json) grants
	-- "+15% Slash Damage Per Second Spinning". "Slash" is a melee-delivery
	-- descriptor for Warpath's spin hits, NOT a modeled damage TYPE, so the line
	-- must resolve to the generic Damage name (matching the existing baked parse
	-- `Damage MORE 15`). Without this entry the bare "damage" name match leaves
	-- "Slash" as residue (" Slash  Per Second Spinning "), and PassiveTree.lua's
	-- non-empty-extra gate (L566) then DROPS the node mod entirely -- the node
	-- contributes nothing, exactly the AerialProwess pre-fix failure mode. The
	-- string "+15% Slash Damage Per Second Spinning" is UNIQUE to va53st-21 across
	-- every tree version (1_2/1_3/1_4) and appears nowhere else in src/Data or
	-- src/TreeData, so this two-word mapping has zero collision. The per-second
	-- scaling is attached separately by the "per second spinning" modTagList entry
	-- below. Spec: spec/System/TestWarpathSpinDurationMore_spec.lua
	["slash damage"] = "Damage",
	["elemental damage"] = {"FireDamage", "ColdDamage", "LightningDamage"},
	["damage over time"] = { "Damage", flags = ModFlag.Dot },
	["ailment damage"] = "AilmentDamage",
	["bleed damage"] = "BleedDamage",
	["ignite damage"] = "IgniteDamage",
	["poison damage"] = "PoisonDamage",
	["frostbite damage"] = "FrostbiteDamage",
	["electrify damage"] = "ElectrifyDamage",
	["damned damage"] = "DamnedDamage",
	["doom damage"] = "DoomDamage",
	["time rot damage"] = "TimeRotDamage",
	["plague damage"] = "PlagueDamage",
	["witchfire damage"] = "WitchfireDamage",
	["spreading flames damage"] = "SpreadingFlamesDamage",
	["future strike damage"] = "FutureStrikeDamage",
	["abyssal decay damage"] = "AbyssalDecayDamage",
	["spirit plague damage"] = "SpiritPlagueDamage",
	["bone curse damage"] = "BoneCurseDamage",
	-- @leb-regression-guard:shadow-damage-minion-scope
	-- C6/F9 follow-up to shadow-suffix-family-c6d. "Shadow Damage" in LE
	-- means damage dealt by Bladedancer Rogue Shadows (the ShadowClone
	-- prefab in src/Data/minions.json, sourced from datamined
	-- actors_player_specific_gameplay_assets_all.bundle). Previously gated
	-- by a no-op Condition:ShadowDamageScope placeholder which left the
	-- mod parsed-but-unconsumed. Now routes via MinionModifier LIST with
	-- minionTypes={"ShadowClone"} (parser infra:
	-- guard `minion-modifier-type-narrowing`), so the Damage INC reaches
	-- env.minion.modDB only when env.minion.type=="ShadowClone".
	-- Dispatch site: CalcPerform.lua (`minion-modifier-multi-type-gate`).
	["shadow damage"] = { "Damage", addToMinion = true, addToMinionTypes = { "ShadowClone" } },
	-- @leb-regression-guard:shadow-suffix-family-c6f
	-- P14 Lethal Mirage Shadow Dagger composite. "50% Chance to apply a
	-- Shadow Dagger on Hit with Lethal Mirage" is parsed via this modName
	-- entry; the "with Lethal Mirage" suffix is consumed by the modTagList
	-- hook below, producing a SkillName-scoped trigger chance. Gate-only:
	-- no calc consumer yet wires Shadow Dagger application from Lethal
	-- Mirage hits to Shadow Dagger DoT damage. Follow-up: implement
	-- Shadow Dagger application trigger and on-hit chance evaluation.
	["chance to apply a shadow dagger on hit"] = "ChanceToApplyShadowDaggerOnHit",
	-- @leb-regression-guard:shadow-suffix-family-c6c-followup-f7
	-- "Chance to consume Shadow" Bladedancer consume-trigger probability.
	-- 1 ModCache entry (10% Chance To Consume Shadow) was silent-failing
	-- with empty mod array. Gate-only: no calc consumer yet wires the
	-- chance-gate into Shadow consume events.
	["chance to consume shadow"] = "ChanceToConsumeShadow",
	-- @leb-regression-guard: curse-spell-damage-stat
	-- "+N Curse Spell Damage" applies as flat spell damage to skills with the
	-- Curse skill type (Bone Curse, Torment, Decrepify, Anguish, Penance).
	-- Implemented as a tagged modName entry rather than a dedicated stat:
	-- name="Damage" + keywordFlags=Spell + SkillType.Curse tag routes through
	-- the existing skillModList:Sum("BASE", cfg, "Damage") path in CalcOffence,
	-- so curse spell skills auto-pick up the BASE without new wiring.
	-- Without this entry the parser leaves "Curse" as residual extra → red
	-- "UNSUPPORTED" tooltip text on items like Hexed Grand Bone Idol.
	-- Test: spec/System/TestCurseSpellDamage_spec.lua
	-- See REGRESSION_GUARDS.md "curse-spell-damage-stat".
	["curse spell damage"] = { "Damage", keywordFlags = KeywordFlag.Spell, tag = { type = "SkillType", skillType = SkillType.Curse } },
	["torment damage"] = "TormentDamage",
	["decrepify damage"] = "DecrepifyDamage",
	["anguish damage"] = "AnguishDamage",
	["penance damage"] = "PenanceDamage",
	["acid skin damage"] = "AcidSkinDamage",
	["serpent venom damage"] = "SerpentVenomDamage",
	["hemorrhage damage"] = "HemorrhageDamage",
	["ravage damage"] = "RavageDamage",
	-- Crit/speed modifiers
	["crit chance"] = "CritChance",
	["critical chance"] = "CritChance",
	["critical strike chance"] = "CritChance",
	["critical strike multiplier"] = "CritMultiplier",
	["critical multiplier"] = "CritMultiplier",
	["shared critical multiplier"] = "CritMultiplier",
	-- @leb-regression-guard:deaths-door-lowlife-critmult
	-- See REGRESSION_GUARDS.md "deaths-door-lowlife-critmult".
	-- Validation provenance is retained in maintainer notes.
	["crit multiplier"] = "CritMultiplier",
	["crit multi"] = "CritMultiplier",
	-- @leb-regression-guard:pierce-chance-to-crit-multiplier
	-- "Pierce Chance" is a real LE stat (game data `pierce_%`, SkillStatMap
	-- maps it to PierceChance). It has no DPS effect of its own in LEB, but
	-- the Shurikens tree node "Ricochet" (srk21-19) converts the summed
	-- pierce chance into critical strike multiplier, so the ledger must
	-- exist. See parseArrowConversion and REGRESSION_GUARDS.md
	-- "pierce-chance-to-crit-multiplier".
	["pierce chance"] = "PierceChance",
	["attack speed"] = { "Speed", flags = ModFlag.Attack },
	["cast speed"] = { "Speed", flags = ModFlag.Cast },
	["attack and cast speed"] = "Speed",
	["freeze duration"] = "EnemyFreezeDuration",
	["abyssal decay duration"] = "EnemyAbyssalDecayDuration",
	["spreading flames duration"] = "EnemySpreadingFlamesDuration",
	["spirit plague duration"] = "EnemySpiritPlagueDuration",
	-- Misc modifiers
	["movespeed"] = "MovementSpeed",
	["movement speed"] = "MovementSpeed",
	["(%w+) and (%w+) resistance"] = function(d1, d2) return { d1:capitalize() .. "Resist", d2:capitalize() .. "Resist" } end,
	-- Skill level
	["skills"] = "SkillLevel",
	["level of"] = "SkillLevel",
	["to level of all skills"] = "SkillLevel",
	-- Attribute conversion (Season 4 / 1.4)
	["strength converted to brutality"] = "StrengthConvertedToBrutality",
	["intelligence converted to madness"] = "IntelligenceConvertedToMadness",
	["dexterity converted to guile"] = "DexterityConvertedToGuile",
	["attunement converted to apathy"] = "AttunementConvertedToApathy",
	["vitality converted to rampancy"] = "VitalityConvertedToRampancy",
}

for i,stat in ipairs(LongAttributes) do
	modNameList[stat:lower()] = Attributes[i]
end

-- @leb-regression-guard:modnamelist-deterministic-trigger-resolution
-- DETERMINISTIC iteration (pairsSortByKey, not pairs): this loop maps every
-- skill's display name (and altName) to "<name> chance"/"chance to <name>"/
-- "to <name>" -> ChanceToTriggerOnHit_<skillId>. When two skills resolve the same
-- name/altName key the LAST assignment wins -- so the winner depended on Lua's
-- `pairs` hash order, which SHIFTS whenever any skill is added/removed from
-- data.skills (adding SparkChargeExplosion silently flipped Bone Curse + Arcane
-- Ascendance from the base skill to the Ailment_ variant). Sorting by skillId makes
-- the winner the alphabetically-greatest skillId, STABLE against future additions.
-- Five order-sensitive collision groups exist; for each the greatest key wins:
--   * Bone Curse: BoneCurse > Ailment_BoneCurse, Ailment_NecroticBoneCurse
--   * Arcane Ascendance: ArcaneAscendance > Ailment_ArcaneAscendance
--   * Spirit Plague: SpiritPlague > Ailment_SpiritPlague
--   * Runebolt: 05c3 Cold > 05c1 Fire, 05c2 Lightning (3 element variants -- no
--     element-neutral base; the suffix tiebreak is arbitrary but DETERMINISTIC)
--   * "Mark For Death" (name-vs-altName): MarkForDeath > Ailment_MarkedForDeath
--     (whose altName is "Mark For Death"). NOTE the winner flips vs `pairs` here.
-- ZERO corpus impact, verified by regen of 12 builds across every affected class
-- (Acolyte/Necro/Warlock, Mage/Sorcerer/Runemaster, Rogue) -- NOT because the
-- names are unused (affixes DO name these skills: "+N to Bone Curse/Runebolt",
-- "Chance to Marked For Death on Hit"), but because every USED form is unaffected:
-- "+N to <skill>" is consumed by the "+N to skill" handler in specialModList
-- BEFORE this rule; the used trigger form "Marked For Death" (with the -ed) has NO
-- collision (only Ailment_MarkedForDeath carries that exact name); and the one form
-- whose winner this flips, "Mark For Death" (no -ed), has zero corpus users. The
-- fix exists to keep that true against future skill additions. SparkCharge stays
-- on the ailment via excludeFromTriggerNameList below (only Ailment_SparkCharge
-- registers); a future ailment-application collision wanting the Ailment_ variant
-- (not the greatest key) would use the same flag.
for skillId, skill in pairsSortByKey(data.skills) do
    -- The player cannot trigger a minion skill and cannot trigger "Stacking" variants of skills
    -- @leb-regression-guard:spark-charge-detonation
    -- excludeFromTriggerNameList: a damaging HIT skill that shares its display
    -- name with an ailment/debuff skill (SparkChargeExplosion is name "Spark
    -- Charge", the same as the Ailment_SparkCharge stack) must NOT register the
    -- greedy "<name> chance" -> ChanceToTriggerOnHit rule, or "X% Spark Charge
    -- Chance On Hit" (which APPLIES a stack = the ailment, 0 damage) would
    -- mis-resolve to the explosion HIT (20 Lightning) and fabricate damage.
    -- The detonation is granted via the source-independent timer-trigger block in
    -- CalcSetup (guard spark-charge-detonation-grant), NOT data.subSkillGrants; it keeps
    -- the "Spark Charge" name only so Spark-Charge-scoped DAMAGE mods still reach it.
    if not skill.fromMinion and not skillId:find("Stacking") and not skill.excludeFromTriggerNameList then
    	modNameList["chance to " .. skill.name:lower()] = {"ChanceToTriggerOnHit_"..skillId, flags = ModFlag.Hit}
    	modNameList["to " .. skill.name:lower()] = {"ChanceToTriggerOnHit_"..skillId, flags = ModFlag.Hit}
    	-- @leb-regression-guard:additional-skill-chance-not-trigger
    	-- NOTE: this "<skill> chance" -> ChanceToTriggerOnHit rule is greedy. A
    	-- "+projectiles QUANTITY" affix phrased "<N>% Additional <skill> Chance" (e.g. the
    	-- Shurikens tree node "Flip of a Coin": "50% Additional Shurikens Chance" = chance
    	-- to throw +N extra projectiles) would otherwise be misread as a 50%-chance full-
    	-- skill SELF-recast trigger. That misparse is blocked up-front in specialModList
    	-- ("^%+?([%d%.]+)%%? additional (.+) chance$"), which is scanned before this rule
    	-- AND before the "N% additional" form that consumes the discriminating "additional".
    	-- See REGRESSION_GUARDS.md "additional-skill-chance-not-trigger".
    	modNameList[skill.name:lower() .. " chance"] = {"ChanceToTriggerOnHit_"..skillId, flags = ModFlag.Hit}
    	if skill.altName then
    		modNameList[skill.altName:lower() .. " chance"] = {"ChanceToTriggerOnHit_"..skillId, flags = ModFlag.Hit}
    	end
    end
end

for _, damageType in ipairs(DamageTypes) do
	modNameList[damageType:lower() .. " penetration"] = damageType .. "Penetration"
	modNameList[damageType:lower() .. " damage"] = damageType .. "Damage"
	modNameList[damageType:lower() .. " resistance"] = damageType .. "Resist"
	modNameList[damageType:lower() .. " damage taken"] = damageType .. "DamageTaken"
	modNameList[damageType:lower() .. " damage over time taken"] = damageType .. "DamageTakenOverTime"
	-- @leb-regression-guard:type-damage-over-time-dot-only
	-- "X Damage over Time" (e.g. Sunwreath / Invoker's Scorching Grasp "increased
	-- Fire Damage over Time") is scoped to its type by the "<Type>Damage" NAME and
	-- to DoTs by ModFlag.Dot -- exactly like the generic "damage over time"
	-- ({ "Damage", flags = ModFlag.Dot }) above. The old "+ ModFlag[damageType]"
	-- ALSO required the damage cfg to carry the type's ModFlag (e.g. ModFlag.Fire=8),
	-- but no skill cfg ever sets a damage-type ModFlag (CalcActiveSkill only sets
	-- Hit/Attack/Cast/Spell/Melee/Projectile/Area/Dot), so these mods matched NOTHING
	-- for any skill and silently dropped (Consecrated Ground / fire-DoT builds lost
	-- every "Fire Damage over Time" affix). Dot-only keeps hits excluded (no Dot) and
	-- other-type DoTs excluded (the FireDamage name is only summed for fire-dealing).
	-- See REGRESSION_GUARDS.md "type-damage-over-time-dot-only".
	modNameList[damageType:lower() .. " damage over time"] = { damageType .. "Damage", flags = ModFlag.Dot }
	for _, damageSourceType in ipairs(DamageSourceTypes) do
	   modNameList[damageType:lower() .. " " .. damageSourceType:lower() .. " damage"] = {damageType .. "Damage", keywordFlags = KeywordFlag.Spell}
	end
end

-- @leb-regression-guard:elemental-dot-flag-parse
-- LE affix "X% increased Elemental Damage Over Time" (e.g. Nameless_King's
-- "(140-170)% increased Elemental Damage Over Time") is the ELEMENTAL AGGREGATE
-- of the per-type "<Type> Damage over Time" entries generated at L636. Without
-- this entry the parser matched only the shorter ["elemental damage"] (L429,
-- non-DoT split) and left residue "over time" -> the INC parsed with flags=0 and
-- did NOT scale fire/cold/lightning DoT (Fire Aura fire/cold ticks read ~33% low;
-- light/void flat portions matched exact). Splitting to the three elemental
-- FireDamage/ColdDamage/LightningDamage names + ModFlag.Dot mirrors the per-type
-- form exactly: Dot-only keeps hits excluded, and each <Type>Damage name is only
-- summed for that type. Longest-match already prefers this over "elemental damage"
-- (same as "fire damage over time" beating "fire damage"). Spec:
-- spec/System/TestElementalDamageOverTimeParse_spec.lua.
modNameList["elemental damage over time"] = { "FireDamage", "ColdDamage", "LightningDamage", flags = ModFlag.Dot }

modNameList["penetration"] = "Penetration"

-- @leb-regression-guard:damage-over-time-penetration-parse
-- Generic DoT penetration "Damage Over Time Penetration" (uniques_1_4 #116 Atrophy
-- "+(20-25)%", #408 Weaver's Gift "+(22-33)%"). Without this entry the parser had
-- no key for the full 4-word phrase, so longest-match fell to the shorter
-- ["damage over time"] ({ "Damage", flags = ModFlag.Dot }, L430) and consumed "damage
-- over time", then the leftover "Penetration" was further mangled -- the substring
-- "net" matched an ability named "Net" and was eaten as a {SkillName="Net"} tag,
-- leaving residue "Peration" -> the whole line parsed to a bogus "Damage MORE (Dot)
-- {SkillName=Net}" with NON-EMPTY residue -> Item.lua:1901 / PassiveSpec dropped it
-- entirely (silent UNDER-count: the unique's DoT penetration contributed NOTHING).
-- The fix maps the full phrase to the generic Penetration name + ModFlag.Dot -- the
-- penetration sibling of ["damage over time"]'s Dot-flagged Damage, and of the
-- per-type ["<type> penetration"] (L619). Penetration-family names bake as BASE (LE
-- penetration is additive %-shred, like resistance). ModFlag.Dot scopes it to DoT:
-- CalcOffence sums generic "Penetration" in BOTH the hit loop (L443) and the
-- ailment/DoT loop (L3733/3735); the Dot flag makes the mod apply to DoT/ailment
-- damage (cfg carries Dot) and be excluded from hits (cfg lacks Dot) -- exactly LE's
-- "Damage over Time Penetration" semantics. Two stale cache-first ModCache rows (the
-- mangled MORE-Dot-{SkillName=Net} + "Peration" residue shape) were deleted so the
-- lines re-parse live. NOT corpus-neutral (real DoT-pen): the 8 corpus builds
-- equipping Atrophy / Weaver's Gift are snapshot-regenerated. Longest-match already
-- prefers this 4-word key over "damage over time" / "penetration".
-- See REGRESSION_GUARDS.md "damage-over-time-penetration-parse".
modNameList["damage over time penetration"] = { "Penetration", flags = ModFlag.Dot }

-- List of modifier flags
local modFlagList = {
	-- Skill types
	["elemental"] = { keywordFlags = bor(KeywordFlag.Fire, KeywordFlag.Cold, KeywordFlag.Lightning) },
	["on melee hit"] = { flags = bor(ModFlag.Melee, ModFlag.Hit) },
	["on hit"] = { flags = ModFlag.Hit },
	["hit"] = { flags = ModFlag.Hit },
	["minion skills"] = { tag = { type = "SkillType", skillType = SkillType.Minion } },
	["with elemental spells"] = { keywordFlags = bor(KeywordFlag.Lightning, KeywordFlag.Cold, KeywordFlag.Fire) },
	-- @leb-regression-guard:flat-damage-to-attacks-and-spells
	-- LE uses "<N> <Type> Damage to/with Attacks and Spells" phrasing on flat-added
	-- damage mods that should apply to BOTH attack-source skills (Melee|Throwing|Bow)
	-- AND spell-source skills (e.g. Mourningfrost: "+1 cold damage to attacks and
	-- spells per point of dexterity"). Without these modFlagList entries, the
	-- parser would either drop the keyword or only catch the second word ("spells")
	-- and miss the attack side. Spec: TestModParserAttacksAndSpells_spec.lua.
	["to attacks and spells"] = { keywordFlags = bor(KeywordFlag.Attack, KeywordFlag.Spell) },
	["to spells and attacks"] = { keywordFlags = bor(KeywordFlag.Attack, KeywordFlag.Spell) },
	["with attacks and spells"] = { keywordFlags = bor(KeywordFlag.Attack, KeywordFlag.Spell) },
	["with spells and attacks"] = { keywordFlags = bor(KeywordFlag.Attack, KeywordFlag.Spell) },
	["minion"] = { addToMinion = true },
	-- Leech suffixes
	["leeched as health"] = { modSuffix = "LifeLeech" },
	-- Other
	["global"] = { tag = { type = "Global" } },
}

for _, damageType in ipairs(DamageTypes) do
	modFlagList["on " .. damageType:lower() .. " hit"] = { keywordFlags = KeywordFlag[damageType], flags = ModFlag.Hit }
	modFlagList["with " .. damageType:lower() .. " skills"] = { keywordFlags = KeywordFlag[damageType] }
end

for _, damageSourceType in ipairs(DamageSourceTypes) do
	modFlagList[damageSourceType:lower()] = { keywordFlags = ModFlag[damageSourceType] }
end

for _, damageType in ipairs(DamageTypes) do
	modFlagList[damageType:lower()] = { keywordFlags = ModFlag[damageType] }
end

for _, weapon in ipairs(DamageSourceWeapons) do
	if not modFlagList[weapon:lower()] then
		modFlagList[weapon:lower()] = { tag = { type = "Condition", var = "Using" .. weapon } }
	end
end

-- List of modifier flags/tags that appear at the start of a line
local preFlagList = {
}

-- List of modifier tags
local modTagList = {
	[". this effect is doubled if you have (%d+) or more maximum mana."] = function(num) return { tag = { type = "StatThreshold", stat = "Mana", threshold = num, mult = 2 } } end,
	["if you have at least (%d+) ward"] = function(num) return { tag = { type = "StatThreshold", stat = "Ward", threshold = num } } end,
	["if you have at least (%d+) total attributes"] = function(num) return { tag = { type = "StatThreshold", stat = "TotalAttr", threshold = num } } end,
	-- "with at least N Corrupted (non-Idol|Idol|) Items equipped"
	-- (proposal C): proper StatThreshold against equipped corrupted-item
	-- counts populated in CalcSetup.lua. The empty middle group covers
	-- the unqualified "with at least N Corrupted Items equipped" wording.
	["with at least (%d+) corrupted items equipped"] = function(num) return { tag = { type = "StatThreshold", stat = "CorruptedItemsEquipped", threshold = num } } end,
	["with at least (%d+) corrupted non%-idol items equipped"] = function(num) return { tag = { type = "StatThreshold", stat = "CorruptedNonIdolItemsEquipped", threshold = num } } end,
	["with at least (%d+) corrupted idol items equipped"] = function(num) return { tag = { type = "StatThreshold", stat = "CorruptedIdolItemsEquipped", threshold = num } } end,
	["for (%d+) seconds"] = { },
	-- @leb-regression-guard:ward-per-second-and-retention-family
	-- Descriptive "for you or your allies" noise-eater. LEB models a single
	-- player so "or your allies" has no effect; this entry exists purely to
	-- consume the text so the residue is empty and the proper Condition tag
	-- attached by the following suffix ("while standing on your Glyph of
	-- Dominion" etc.) is the only gate. 10 Runemaster Glyph of Dominion
	-- ward-regen cache entries depend on this strip.
	["for you or your allies"] = { },
	-- @leb-regression-guard:ward-per-second-and-retention-family (W4)
	-- Acolyte / Lich Profane Veil is a 4-second-duration buff. The Lich
	-- ward-regen line "+N Ward per Second during Profane Veil" must be
	-- gated on the buff being active. ConfigOptions exposes the
	-- conditionDuringProfaneVeil check.
	["during profane veil"] = { tag = { type = "Condition", var = "DuringProfaneVeil" } },
	-- @leb-regression-guard:bulwark-of-the-last-abyss-apocalypse
	-- Bulwark of the Last Abyss (Ironglass Shield) self-applies the Apocalypse buff
	-- (3s, every 3s while on high health); per the item's altText its ONLY effects are
	-- the two damage mods on the shield ("70% increased Void Damage during Apocalypse",
	-- "+70% Melee Critical Strike Multiplier during Apocalypse"). Gated on the
	-- conditionDuringApocalypse check (ConfigOptions, default OFF).
	["during apocalypse"] = { tag = { type = "Condition", var = "DuringApocalypse" } },
	-- @leb-regression-guard:flow-conditional-damage
	-- Bladedancer "Flow" resource conditionals. The mastery "Rhythm" node and
	-- Flow uniques grant more damage / crit for skills that generate or consume
	-- Flow. These parsed to a valid numeric mod PLUS a non-empty residue ("when
	-- generating or consuming Flow"), so PassiveTree:ProcessStats dropped the whole
	-- family -> 0 Flow mods in modDB (verified on AfiyaLapizDSTake2). Strip the
	-- phrase here so the numeric mod survives with a Condition tag, gated by the
	-- ConfigOptions Flow toggles (default OFF => corpus-neutral). NOTE: "when
	-- consuming flow" cannot match "...or consuming flow", so the two keys are
	-- mutually exclusive on real lines regardless of table iteration order.
	-- Spec: spec/System/TestFlowConditional_spec.lua
	["when generating or consuming flow"] = { tag = { type = "Condition", var = "GeneratingOrConsumingFlow" } },
	["when consuming flow"] = { tag = { type = "Condition", var = "ConsumingFlow" } },
	-- @leb-regression-guard:flame-reave-rhythm-consume (parse tag)
	-- Flame Reave "Rhythm of Fire" (fr11mv-3): using Flame Reave grants 4 stacks
	-- (cap 12); at 12 the next use CONSUMES all stacks for +130% Damage (MORE,
	-- multiplicative, Flame-Reave-scoped). LE_TREE_NODE_STAT_REWRITE rewrites the
	-- raw "+130% Damage when consuming 12 stacks" (residue "when consuming 12
	-- stacks" -> PassiveTree:648 whole-mod-drop) to "...when consuming Rhythm of
	-- Fire" so the numeric Damage MORE survives with this Condition tag, gated by
	-- the ConfigOptions toggle (default OFF => corpus-neutral). This is Flame
	-- Reave's OWN Rhythm, distinct from the Bladedancer Dancing-Strikes "Rhythm"
	-- (dacn33 RhythmStacks) and the Rogue Flow "Rhythm" node. Capture
	-- (4guanghuan 20260707_140512_03) confirms the consume band = x2.50 vs normal.
	-- Spec: spec/System/TestFlameReaveRhythmConsume_spec.lua
	["when consuming rhythm of fire"] = { tag = { type = "Condition", var = "ConsumingRhythmOfFire" } },
	-- @leb-regression-guard:ward-per-second-and-retention-family (W5)
	-- "for each Curse affecting you" multiplier (Acolyte self-curse stacking).
	-- ConfigOptions exposes multiplierCurseOnSelf count input.
	["for each curse affecting you"] = { tag = { type = "Multiplier", var = "CurseOnSelf" } },
	[" on critical strike"] = { tag = { type = "Condition", var = "CriticalStrike" } },
	["from critical strikes"] = { tag = { type = "Condition", var = "CriticalStrike" } },
	-- Multipliers
	["per level"] = { tag = { type = "Multiplier", var = "Level" } },
	-- Per stat
	["per (%d+) total attributes"] = function(num) return { tag = { type = "PerStat", statList = Attributes, div = num } } end,
	["per (%d+) maximum mana"] = function(num) return { tag = { type = "PerStat", stat = "Mana", div = num } } end,
	["per (%d+) max mana"] = function(num) return { tag = { type = "PerStat", stat = "Mana", div = num } } end,
	-- @leb-regression-guard:current-mana-damage-scaling
	-- "per N current mana" scales a (usually MORE) damage mod by the player's
	-- current mana. LE has no static "current mana" — it fluctuates per cast — so
	-- the static planner models it as FULL mana (current == max), matching the
	-- in-game dominant case where mana sits at the cap (YsMaiden Storm Bolt: 74%
	-- of hits land at full 711 mana, modest-raman 2026-05-29). The PerStat reads
	-- output.CurrentMana, which CalcPerform.doActorLifeMana sets to output.Mana.
	-- Without this entry the phrase fell to `extra` residue and PassiveTree.lua
	-- ("if mod.list and (not mod.extra or mod.extra == '')") silently DROPPED the
	-- whole mod, so Excited Bolts (Gathering Storm), Flame Rush, and the Stygian
	-- Beam unique each contributed 0 (ModCache 6069/1875/13555). Mirrors "per N
	-- max mana" above. Per-node caps (e.g. Excited Bolts +300%) are metadata
	-- absent from the mod string and are NOT modelled here; would bind only above
	-- ~1000 mana. Spec: spec/System/TestCurrentManaDamageScaling_spec.lua
	["per (%d+) current mana"] = function(num) return { tag = { type = "PerStat", stat = "CurrentMana", div = num } } end,
	-- @leb-regression-guard:mana-missing-not-full-mechanics
	-- LE "Missing Mana" scaling (e.g. Smite/Paladin "+1 Spell Damage per 5
	-- Missing Mana", "1% Increased Cast Speed per 2% Missing Mana"). Absolute
	-- vs percent are distinct LE phrasings -> distinct tags. Multiplier values
	-- are config-driven (Config "Your Missing Mana %" -> Multiplier:MissingManaPercent;
	-- CalcPerform derives Multiplier:MissingMana = Mana x %/100). The static
	-- planner models full mana by default, so both are 0 until the config is set.
	-- Spec: spec/System/TestConfigManaMechanics_spec.lua
	-- Absolute uses PerStat (reads output.MissingMana, set idempotently in
	-- CalcPerform) -- NOT a Multiplier mod, because doActorLifeMana runs more
	-- than once per BuildOutput and an additive NewMod would double-count.
	-- PerStat is also continuous (not floored), matching LE "per N stat".
	["per (%d+) missing mana"] = function(num) return { tag = { type = "PerStat", stat = "MissingMana", div = num } } end,
	-- Percent is config-driven (Multiplier:MissingManaPercent set once by the
	-- config), so a Multiplier tag is safe and mirrors per-missing-health-percent.
	["per (%d+)%% missing mana"] = function(num) return { tag = { type = "Multiplier", var = "MissingManaPercent", div = num } } end,
	["per (%d+) maximum health"] = function(num) return { tag = { type = "PerStat", stat = "Life", div = num } } end,
	["per (%d+) max health"] = function(num) return { tag = { type = "PerStat", stat = "Life", div = num } } end,
	["per (%d+)%% block chance"] = function(num) return { tag = { type = "PerStat", stat = "BlockChance", div = num } } end,
	["per (%d+) block effectiveness"] = function(num) return { tag = { type = "PerStat", stat = "BlockEffect", div = num } } end,
	["per totem"] = { tag = { type = "PerStat", stat = "TotemsSummoned" } },
	["for each of your totems"] = { tag = { type = "PerStat", stat = "TotemsSummoned" } },
	["for your totems"] = { tag = { type = "Scope", scope = "totem" } },
	["for minions"] = { tag = { type = "Scope", scope = "minion" } },
	["for your minions"] = { tag = { type = "Scope", scope = "minion" } },
	-- @leb-regression-guard:shadow-suffix-family-c6b
	-- @leb-regression-guard:shadow-skills-minion-scope
	-- C6/F3 follow-up. "for skills used by shadows" was previously gated
	-- with a no-op Scope:minion placeholder (Scope tags have no calc
	-- consumer in LEB, so the mod applied unconditionally to the player).
	-- Now routes via MinionModifier LIST with minionTypes={"ShadowClone"}
	-- (parser infra: guard `minion-modifier-type-narrowing`), so the
	-- prefix mod reaches env.minion.modDB only when
	-- env.minion.type=="ShadowClone" (the Bladedancer Rogue Shadow prefab
	-- in src/Data/minions.json). "for shadow attack" remains a runtime
	-- Condition toggled when the active hit is a Shadow Attack
	-- (Shadow Cascade etc.). Dispatch site: CalcPerform.lua
	-- (`minion-modifier-multi-type-gate`).
	["for skills used by shadows"] = { addToMinion = true, addToMinionTypes = { "ShadowClone" } },
	["for shadow attack"] = { tag = { type = "Condition", var = "ShadowAttack" } },
	-- @leb-regression-guard:doubled-for-shadow-attack
	-- @leb-regression-guard:doubled-with-bow
	-- F4 follow-up to shadow-suffix-family-c6b. Trailing-clause patterns
	-- ", doubled for shadow attack" and ", doubled with bow" emit a
	-- Condition tag with mult=2. The consumer side (ModStore.lua
	-- `condition-tag-mult`) multiplies value by mult on match and falls
	-- through (keeps base value) when the condition is not met -- the
	-- exact StatThreshold mult contract. scan() longest-match makes
	-- these win over the bare "for shadow attack" / "with bow" entries.
	[", doubled for shadow attack"] = { tag = { type = "Condition", var = "ShadowAttack", mult = 2 } },
	[", doubled with bow"] = { tag = { type = "Condition", var = "UsingBow", mult = 2 } },
	-- @leb-regression-guard: dodge-rating-doubled-if-hit-recently
	-- Rogue passive "Once" (Rogue-52) grants "10 Dodge Rating, Doubled if Hit
	-- Recently" per point. Without this trailing-clause tag the modTag scan
	-- consumed only the bare "hit recently" fragment and left residue
	-- " , Doubled if  Recently ", so the Evasion BASE mod was dropped at tree
	-- application -- losing 10 x allocated points of Dodge Rating (60 at 6/6 on
	-- ImPalmBeachPete: Dodge Rating 111 -> 184, Dodge Chance 10.65% -> 15%).
	-- Same Condition+mult contract as ", doubled for shadow attack" above:
	-- BeenHitRecently defaults off so the base (un-doubled) value applies,
	-- matching the in-game character-sheet display. scan() longest-match makes
	-- this comma-anchored phrase win over the inner "hit recently" tag.
	-- See REGRESSION_GUARDS.md "dodge-rating-doubled-if-hit-recently".
	[", doubled if hit recently"] = { tag = { type = "Condition", var = "BeenHitRecently", mult = 2 } },
	-- @leb-regression-guard:shadow-suffix-family-c6c
	-- Shadow trigger gates. OnShadowCreate fires each time a Shadow is
	-- summoned (Bladedancer); OnShadowConsume fires each time a Shadow is
	-- consumed (Lethal Mirage etc.). No calc consumer exists yet for either
	-- condition - parser correctness only. "gain per shadow" (3 words) wins
	-- over "per shadow" (2 words) via scan() longest-match preference.
	["gained on shadow creation"] = { tag = { type = "Condition", var = "OnShadowCreate" } },
	["gain on shadow creation"] = { tag = { type = "Condition", var = "OnShadowCreate" } },
	["gain per shadow"] = { tag = { type = "Condition", var = "OnShadowCreate" } },
	["from subsequent shadows consumed"] = { tag = { type = "Condition", var = "OnShadowConsume" } },
	["when you consume a shadow"] = { tag = { type = "Condition", var = "OnShadowConsume" } },
	-- @leb-regression-guard:shadow-suffix-family-c6d
	-- "with Shadow Daggers" residue cleanup. SkillName="Shadow Daggers" is
	-- already attached by the skillNameList post-scan (L2562/2577) but the
	-- leading "with" word fell out into slot[2] as orphaned residue. Explicit
	-- modTagList hook consumes the whole phrase atomically so fresh parses
	-- leave no residue. 10 ModCache entries patched (Physical Penetration
	-- with Shadow Daggers).
	["with shadow daggers"] = { tag = { type = "SkillName", skillName = "Shadow Daggers" } },
	-- @leb-regression-guard:shadow-suffix-family-c6f
	-- Lethal Mirage suffix family. "with lethal mirage" mirrors the C6d
	-- Shadow Daggers fix (SkillName already attached post-scan, just need
	-- to consume the "with" prefix atomically). "of mirage attacks with
	-- lethal mirage" is a 5-word composite where the "of mirage attacks"
	-- qualifier is informational - in LE all Lethal Mirage hits ARE mirage
	-- attacks, so the SkillName:Lethal Mirage tag alone is correct.
	-- Longest-match wins so the 5-word form takes precedence over the
	-- bare "with lethal mirage".
	["with lethal mirage"] = { tag = { type = "SkillName", skillName = "Lethal Mirage" } },
	["of mirage attacks with lethal mirage"] = { tag = { type = "SkillName", skillName = "Lethal Mirage" } },
	-- @leb-regression-guard:shadow-suffix-family-c6c-followup-f8
	-- "From Shadow Falcons" Falconer-specific scope. Shadow Falcon is a
	-- Companion-type minion not in data.skills, so skillNameList post-scan
	-- doesn't match it - explicit modTagList hook required. 1 ModCache
	-- entry (Dusk Shroud Chance From Shadow Falcons) carries the SkillName
	-- tag with empty residue.
	["from shadow falcons"] = { tag = { type = "SkillName", skillName = "Shadow Falcon" } },
	-- @leb-regression-guard:paladin-sentinel95-healthregen-partition
	-- "From Symbols of Hope" passive-suffix on Sentinel-95 Covenant of
	-- Protection's 5-point bonus ("+5 Health Regen From Symbols Of Hope",
	-- notScaling, noScalingPointThreshold=5). The "from <skill>" wording in
	-- this context scales per active Symbol (LE convention - matches the
	-- existing Symbols of Hope INC LifeRegen 41.6% per ActiveSymbol pattern),
	-- so the tag is Multiplier:ActiveSymbol, not SkillName. With 5 symbols
	-- active the +5 BASE becomes +25, restoring the LifeRegen drift target.
	["from symbols of hope"] = { tag = { type = "Multiplier", var = "ActiveSymbol" } },
	-- Slot conditions
	["while dual wielding"] = { tag = { type = "Condition", var = "DualWielding" } },
	["while wielding a two handed melee weapon"] = { tagList = { { type = "Condition", var = "UsingTwoHandedWeapon" }, { type = "Condition", var = "UsingMeleeWeapon" } } },
	-- @leb-regression-guard:erasing-strike-obliteration-2h-double
	-- Negated two-handed condition. Used by LE_TREE_NODE_STAT_REWRITE["es6ai-16"]
	-- (Erasing Strike Obliteration) to gate the node's BASE "+X% MORE Damage" on the
	-- non-2h case so it still applies to 1h AND weaponless/unclassified builds (the 2h
	-- case is the doubled value via "with 2h weapon"). Without this the base was gated
	-- on "with 1h weapon", which left builds where neither 1h nor 2h fires with ZERO
	-- Obliteration bonus (regression: YsBonkVK_S2 x0.91).
	["while not wielding a two handed weapon"] = { tag = { type = "Condition", var = "UsingTwoHandedWeapon", neg = true } },
	["while unarmed"] = { tag = { type = "Condition", var = "Unarmed" } },
	["while moving"] = { tag = { type = "Condition", var = "Moving" } },
	["while charging"] = { tag = { type = "Condition", var = "Charging" } },
	["while channelling"] = { tag = { type = "Condition", var = "Channelling" } },
	["while channeling"] = { tag = { type = "Condition", var = "Channelling" } },
	["while leeching"] = { tag = { type = "Condition", var = "Leeching" } },
	["while frozen"] = { tag = { type = "Condition", var = "Frozen" } },
	["while cursed"] = { tag = { type = "Condition", var = "Cursed" } },
	["while transformed"] = { tag = { type = "Condition", var = "Transformed" } },
	-- @leb-regression-guard:ward-per-second-and-retention-family
	["on transform"] = { tag = { type = "Condition", var = "Transformed" } },
	["when you transform"] = { tag = { type = "Condition", var = "Transformed" } },
	["while at high health"] = { tag = { type = "Condition", var = "HighHealth" } },
	["while you have ward"] = { tag = { type = "Condition", var = "HaveWard" } },
	["while you have lightning aegis"] = { tag = { type = "Condition", var = "HaveLightningAegis" } },
	["while you have haste"] = { tag = { type = "Condition", var = "Haste" } },
	["while you have frenzy"] = { tag = { type = "Condition", var = "Frenzy" } },
	["while you have an ailment overload"] = { tag = { type = "Condition", var = "HaveAilmentOverload" } },
	["while on consecrated ground"] = { tag = { type = "Condition", var = "OnConsecratedGround" } },
	["while you have a companion"] = { tag = { type = "Condition", var = "HaveCompanion" } },
	-- @leb-regression-guard:grounding-totem-condition
	-- Avalanche specialization node av75ch-12 "Grounding" stat
	-- "+15% Hit Damage While Totem Active" (maxPoints 3 -> +45% at 3/3).
	-- In-game node description: "Avalanche hits deal more damage (multiplicative
	-- with other modifiers) while you have at least one active totem" -> MORE,
	-- NOT increased (datamine field AvalancheSnowballMutator.increasedDamageWithATotem
	-- is just the engine var name; the measured per-hit totem factor is a clean
	-- x1.4521 ~= 3pt x 15% MORE -- an `increased` would be diluted by the build's
	-- increased pool and could never net x1.45). The "+15% Hit Damage" half
	-- already parses to {name="Damage", type="MORE", value=15, flags=ModFlag.Hit};
	-- before this entry the trailing " While Totem Active" survived as residue and
	-- PassiveTree.lua:ProcessStats dropped the whole mod (non-empty `extra` gate),
	-- so SuXes (lv92 Shaman, Avalanche + totem) lost the entire Grounding x1.45.
	-- Routes through the pre-existing Condition:HaveTotem (ConfigOptions
	-- conditionHaveTotem / CalcPerform.lua auto-sets it for totem mains) so the
	-- bonus only applies while a totem is active: gated OFF -> no contribution.
	-- Only the Grounding node uses this string (tree_0.json 1_2/1_3/1_4; no
	-- affix/unique), so the general suffix entry has a Grounding-only blast radius.
	-- Spec: spec/System/TestGroundingTotemCondition_spec.lua
	["while totem active"] = { tag = { type = "Condition", var = "HaveTotem" } },
	["with arcane shield"] = { tag = { type = "Condition", var = "HaveArcaneShield" } },
	["with concentration"] = { tag = { type = "Condition", var = "Concentration" } },
	-- @leb-regression-guard: per-set-integer-source-not-halfstep
	-- roundAfterMultiply lets ModStore:EvalMod floor(value × CompleteSetCount),
	-- mirroring the engine order: CharacterMutator applies
	-- `count × perSourceValue` as a float, the All-Attributes total is floored
	-- only at final display (CharacterMutator.c L10497-10501). For the Integer
	-- per-set affix the per-source value is already an INTEGER (ItemTools uses
	-- the normal precision=1 roll — NOT a half-step), so floor(int × int) is a
	-- harmless no-op; the floor remains for any future fractional per-set roll.
	["per complete set"] = { tag = { type = "Multiplier", var = "CompleteSetCount", roundAfterMultiply = true } },
	["per arcane shield"] = { tag = { type = "Multiplier", var = "ArcaneShieldStack" } },
	-- @leb-regression-guard:elemental-arrows-resource
	-- Rogue/Marksman "Elemental Arrows" resource: bow attacks consume Elemental Arrows and
	-- each consumed arrow adds fire+lightning + increased-elemental (game Property_Player_113/115).
	-- The tree stats phrase it "... with Elemental Arrow" / "... per Elemental Arrow used"; both
	-- scale by Multiplier:ElementalArrowConsumed (the steady-state consumed count computed in
	-- CalcPerform from ElementalArrowMax + ElementalArrowExtraConsume). Without this entry the
	-- lines failed to parse (no skill named "Elemental Arrow") and were silently dropped.
	-- "with Elemental Arrow" on an INCREASED line (Rogue-35 "125% increased Elemental Damage
	-- with Elemental Arrow") is a CONDITIONAL bonus while consuming (applied once), NOT per-arrow
	-- -- matching LEB's "with arcane shield" = Condition convention. In-game AmHoA lightning
	-- non-crit floor/median (9681/10384) matches added-per-arrow x3 + this increased applied x1
	-- (~10338); applying it x consumed (x3, +375%) over-shot ~1.6x. The per-arrow ADDED lines
	-- ("+N Fire/Lightning Damage with Elemental Arrow", Property_113) are handled in specialModList
	-- with the Multiplier so ONLY they scale by the consumed count.
	["with elemental arrow"] = { tag = { type = "Condition", var = "HaveElementalArrows" } },
	-- "per Elemental Arrow [used]" (Property_115-style) genuinely scales per consumed arrow.
	["per elemental arrow used"] = { tag = { type = "Multiplier", var = "ElementalArrowConsumed" } },
	["per elemental arrow"] = { tag = { type = "Multiplier", var = "ElementalArrowConsumed" } },
	["per companion"] = { tag = { type = "Multiplier", var = "Companion" } },
	["per idol in a refracted slot"] = { tag = { type = "Multiplier", var = "IdolInRefractedSlot" } },
	["per equipped heretical idol"] = { tag = { type = "Multiplier", var = "EquippedHereticalIdol" } },
	["per equipped huge idol"] = { tag = { type = "Multiplier", var = "EquippedHugeIdol" } },
	["per equipped ornate idol"] = { tag = { type = "Multiplier", var = "EquippedOrnateIdol" } },
	["per equipped grand idol"] = { tag = { type = "Multiplier", var = "EquippedGrandIdol" } },
	["per equipped large idol"] = { tag = { type = "Multiplier", var = "EquippedLargeIdol" } },
	["per equipped adorned idol"] = { tag = { type = "Multiplier", var = "EquippedAdornedIdol" } },
	["per equipped stout idol"] = { tag = { type = "Multiplier", var = "EquippedStoutIdol" } },
	["per equipped humble idol"] = { tag = { type = "Multiplier", var = "EquippedHumbleIdol" } },
	["per equipped small idol"] = { tag = { type = "Multiplier", var = "EquippedSmallIdol" } },
	["per equipped minor idol"] = { tag = { type = "Multiplier", var = "EquippedMinorIdol" } },
	["per equipped corrupted idol"] = { tag = { type = "Multiplier", var = "EquippedCorruptedIdol" } },
	["if there are no larger idols above smaller ones in the grid"] = { tag = { type = "Condition", var = "NoLargerIdolsAboveSmaller" } },
	["per symbol"] = { tag = { type = "Multiplier", var = "ActiveSymbol" } },
	["per active symbol"] = { tag = { type = "Multiplier", var = "ActiveSymbol" } },
	["per symbol consumed"] = { tag = { type = "Multiplier", var = "ActiveSymbol" } },
	-- @leb-regression-guard:abomination-minions-consumed-more
	-- Assemble Abomination (Necromancer, skills.json AssembleAbomination): on summon the
	-- abomination snapshots the minions it absorbed and gains "5% more damage per minion
	-- consumed, up to 20 minions" (in-game tooltip + datamining AssembleAbominationAdapter.c
	-- :1777-1795 -> Stat value = min(absorbed,20) * 0.05, baked once at summon = a snapshot).
	-- limit = 20 mirrors the code cap (0x14). Driven by the "# of Minions Absorbed by
	-- Abomination" Config count (Multiplier:AbominationMinionsConsumed, set on the minion via
	-- a MinionModifier); default 0 -> MORE 1.0 -> corpus-neutral. The skill baseMod scopes the
	-- MORE to the abomination minion only. (Per-absorbed-minion-TYPE tree MOREs -- Engorgement,
	-- Death in the Family, Sharpened Bones, Spoils of War -- are a separate follow-up.)
	-- See REGRESSION_GUARDS.md "abomination-minions-consumed-more".
	["per minion consumed"] = { tag = { type = "Multiplier", var = "AbominationMinionsConsumed", limit = 20 } },
	-- @leb-regression-guard:abomination-pertype-more
	-- Assemble Abomination per-absorbed-TYPE specialization-tree MOREs (Necromancer,
	-- TreeData/1_4/tree_3.json, treeId "aa710"). Each of these "per <type>" / "with all
	-- types" suffixes is the SCALING tail of a node MORE line; the node MORE itself
	-- ("+N% Damage" / "+N% Melee Damage") parses generically and these tags attach the
	-- per-type Multiplier (or all-types Condition) that the matching ConfigOptions counts
	-- populate on the abomination minion (same guard). Vars / limits:
	--   * "per skeleton warrior" -> AbominationSkeletonWarriorsAbsorbed (Sharpened Bones
	--     aa710-2, cap 20 skeletons total). "per skeleton rogue"/"per skeleton archer"
	--     are the secondary AS/area lines (counts only; tags still consume the suffix so
	--     the node line parses with no residue instead of being dropped by PassiveTree).
	--   * "per minion type absorbed" -> AbominationMinionTypesAbsorbed (Engorgement
	--     aa710-26, max 4 types). MUST out-rank the generic "per minion" entry below: scan
	--     prefers the same-start, longer-end match, so the full phrase wins.
	--   * "with all types absorbed" -> Condition:AbominationAllTypesAbsorbed (Death in the
	--     Family aa710-28, binary +20% Damage gate).
	--   * "per warrior or rogue absorbed" -> AbominationWarriorsOrRoguesAbsorbed (Spoils
	--     of War aa710-6, cap 20). NOTE: this MORE belongs to a granted Double Strike
	--     sub-skill that LEB does NOT model, so the tag has no skill to attach to yet; the
	--     entry exists so the count config + string parse cleanly (documented gap).
	-- The Damage-and-Health half of aa710-2 is split to a Damage-only line via
	-- LE_TREE_NODE_STAT_REWRITE (Data/Global.lua, same guard) so the parse leaves no
	-- residue (PassiveTree drops mods with non-empty `extra`). The necrotic base-damage
	-- split of the abomination melee is NOT datamineable from cache -> not modeled (only
	-- multiplicative MOREs here). Default counts 0 / condition OFF -> corpus-neutral.
	-- Pairs with ConfigOptions.lua + spec/System/TestAbominationPerTypeMore_spec.lua.
	-- See REGRESSION_GUARDS.md "abomination-pertype-more".
	["per skeleton warrior"] = { tag = { type = "Multiplier", var = "AbominationSkeletonWarriorsAbsorbed", limit = 20 } },
	["per skeleton rogue"] = { tag = { type = "Multiplier", var = "AbominationSkeletonRoguesAbsorbed", limit = 20 } },
	["per skeleton archer"] = { tag = { type = "Multiplier", var = "AbominationSkeletonArchersAbsorbed", limit = 20 } },
	["per minion type absorbed"] = { tag = { type = "Multiplier", var = "AbominationMinionTypesAbsorbed", limit = 4 } },
	["with all types absorbed"] = { tag = { type = "Condition", var = "AbominationAllTypesAbsorbed" } },
	["per warrior or rogue absorbed"] = { tag = { type = "Multiplier", var = "AbominationWarriorsOrRoguesAbsorbed", limit = 20 } },
	-- Per-active minion/summon multipliers (DPS-integrated via Config tab counts)
	["per active totem"] = { tag = { type = "PerStat", stat = "TotemsSummoned" } },
	["per active dread shade"] = { tag = { type = "Multiplier", var = "ActiveDreadShade" } },
	["per active maelstrom"] = { tag = { type = "Multiplier", var = "ActiveMaelstrom" } },
	-- Throne of Ambition: "2% more <Fire/Cold/Armor> per stack of Ambition", max 20 stacks
	-- (stacks are additive, not multiplicative with each other -> one MORE of value*stacks).
	-- Driven by the "# of Active Ambition Stacks" config (ifMult AmbitionStacks); limit caps at 20.
	["per stack of ambition"] = { tag = { type = "Multiplier", var = "AmbitionStacks", limit = 20 } },
	-- @leb-regression-guard:firebrand-per-stack-tree-damage (tag site)
	-- Firebrand specialization-tree per-stack damage nodes (treeId f1b4d, Spellblade).
	-- Game source (TreeData/1_4/tree_1.json): f1b4d-2 Charring "+4% Melee Damage Per Stack"
	-- (maxPoints 3), f1b4d-18 Ardent Branding "+3% Damage Per Stack" (maxPoints 1). These are
	-- CONTINUOUS per-live-Firebrand-stack MORE (description: "deals more ... per stack of
	-- Firebrand, multiplicative with other modifiers"). LE_TREE_NODE_STAT_REWRITE rewrites those
	-- node-id-keyed lines to append "per stack of Firebrand" so this tag attaches
	-- Multiplier:FirebrandStack (set to the max stack count in CalcOffence; default 4, the
	-- "# of Firebrand Stacks" config overrides). NODE-ID-KEYED on purpose: f1b4d-7 Incineration
	-- "+12% Damage Per Stack" is the IDENTICAL text but a CONSUMED-stack proc (NOT continuous) and
	-- must NOT be wired here. limit 12 = realistic Firebrand max (base 4 + Wildfire + Ardent Branding).
	-- Spec: spec/System/TestFirebrandTreePerStackDamage_spec.lua
	["per stack of firebrand"] = { tag = { type = "Multiplier", var = "FirebrandStack", limit = 12 } },
	-- @leb-regression-guard:rhythm-stack-crit-multi (tag site)
	-- Dancing Strikes "Rhythm" stacks (Bladedancer): gained on use-and-hit,
	-- max = 2 x points in the "Rhythm" node (10 at 5/5). The stat strings are
	-- rewritten to this phrasing by LE_TREE_NODE_STAT_REWRITE (Data/Global.lua)
	-- because in-game the per-stack semantics live only in the node
	-- description. Stacks are additive within a mod (in-game CSV: exact
	-- 20-crit-mult-pt steps per stack at Art of Blades 2/2, plateau +200 at 10).
	-- Driven by the "# of Rhythm Stacks" config (ifMult RhythmStacks); limit caps at 10.
	["per stack of rhythm"] = { tag = { type = "Multiplier", var = "RhythmStacks", limit = 10 } },
	-- @leb-regression-guard:berserk-stack-melee-damage (tag site)
	-- Warcry "Berserk" buff: "+4 Melee Damage Per Stack" (wc57-22) is rewritten
	-- to "...per stack of Berserk" by LE_TREE_NODE_STAT_REWRITE so this tag
	-- attaches Multiplier:BerserkStacks. Stacks are additive (one BASE mod of
	-- value x stacks), the Throne/Rhythm precedent. limit = 15 = 10 base max
	-- (Berserker) + 5 from Brutality 5/5; driven by the "# of Berserk Stacks"
	-- config (default 0). Spec: spec/System/TestBerserkStackMeleeDamage_spec.lua
	["per stack of berserk"] = { tag = { type = "Multiplier", var = "BerserkStacks", limit = 15 } },
	-- @leb-regression-guard:germination-per-companion-scaling (tag site)
	-- Validation provenance is retained in maintainer notes.
	["per stack of germination"] = { tag = { type = "Multiplier", var = "GerminationStacks", limit = 4 } },
	-- @leb-regression-guard:aerial-prowess-per-stack (tag site)
	-- Falconer "Aerial Prowess" (Aerial Assault tree node aa989-19). The node
	-- grants "+2% Damage Per stack" (notScalingStats) backed by "12 Max Aerial
	-- Prowess stacks"; its description: "When you next use Aerial Assault, it
	-- consumes all stacks to ... deal more damage (multiplicative with other
	-- modifiers) per stack." The per-stack semantics live in the node, and the
	-- bare "Per stack" phrasing is shared by ~18 unrelated stacking stats, so the
	-- raw line cannot be tagged generically. LE_TREE_NODE_STAT_REWRITE["aa989-19"]
	-- (Data/Global.lua) appends "per stack of Aerial Prowess" to the Damage line so
	-- this tag attaches Multiplier:AerialProwessStacks. The MORE is consumed by
	-- (and scoped to) Aerial Assault -- the default tree-node SkillId tag keeps it
	-- on the owning skill (NOT lifted to global scope, unlike Berserk). Datamine
	-- (datamining AerialAssaultMutator.GetMoreDamageFromAerialProwess,
	-- datamined offset): MORE = stackCount(0x138) x perStackFloat(0x15c = 2%), capped
	-- at maxStacks(0x150 = 12) and consumed on the next cast. limit = 12 = the
	-- node's "12 Max Aerial Prowess stacks". Driven by the "# of Aerial Prowess
	-- Stacks" config (default 0 -> strict no-op). Per-stack stacking is ADDITIVE
	-- within the mod (one MORE of value x stacks), the Throne/Rhythm/Berserk/
	-- Germination precedent. The Falcon-minion-side per-stack MORE buff applied at
	-- cast (AerialAssaultMutator ~L1684-1702) is a documented follow-up, NOT here.
	-- Spec: spec/System/TestAerialProwessPerStack_spec.lua
	["per stack of aerial prowess"] = { tag = { type = "Multiplier", var = "AerialProwessStacks", limit = 12 } },
	-- @leb-regression-guard:chaos-bolts-exult-in-misery-enemy-ailment (tag site)
	-- Warlock "Exult in Misery" (Chaos Bolts tree node ch4bo-11). The node's four
	-- display stats ("+4% Hit Damage to {Damned,Ignited,Bleeding,Frostbitten}")
	-- encode ONE engine perAilment value scaled by the live count of DISTINCT
	-- negative ailments on the target (DamageEffectMoreDamagePerNegativeAilment.c:
	-- 43-66: factor = 1 + perAilment × GetUniqueNegativeAilmentCount; ctor at
	-- datamined game source). LE_TREE_NODE_STAT_REWRITE["ch4bo-11"]
	-- (Data/Global.lua) collapses the four lines into ONE "+X% Hit Damage per
	-- Negative Ailment on Enemy" so this tag attaches
	-- Multiplier:EnemyNegativeAilmentCount. actor="enemy" mirrors the "+1% Hit
	-- Damage Per Bleed" precedent (var="BleedStack", actor="enemy"): the count
	-- lives on the enemy modDB, fed by the "# Distinct Negative Ailments on Enemy"
	-- config (enemyModList) and propagated to enemyDB.multipliers by CalcPerform
	-- (the BleedStack/IgniteStack/ShockStack propagation loop). NO limit -- the
	-- engine's maxAilments arg = 0 (uncapped); the realistic cap of 4 distinct
	-- ailments is enforced by the config (val = math.min(val, 4)). Default config 0
	-- -> multiplier 0 -> MORE factor 1.0 -> strict no-op. Scope is the owning skill
	-- (Chaos Bolts) via the tree node's default SkillId tag, NOT global.
	-- Spec: spec/System/TestChaosBoltsExultInMisery_spec.lua
	["per negative ailment on enemy"] = { tag = { type = "Multiplier", var = "EnemyNegativeAilmentCount", actor = "enemy" } },
	-- @leb-regression-guard:ladle-negative-ailment-on-target (tag site)
	-- Mad Alchemist's Ladle (unique) "6% more Spell Damage per Negative Ailment on the
	-- Target (up to 8)". SAME engine mechanic as "per negative ailment on enemy" above
	-- (Multiplier:EnemyNegativeAilmentCount, DamageEffectMoreDamagePerNegativeAilment.c)
	-- but the item text says "on the Target", which was UNALIASED. Pre-fix the tail
	-- "per Negative Ailment on the Target" was left as NON-EMPTY residue (modLine.extra),
	-- so Item.lua's mod-line gate (`not modLine.extra`, ~L1864/1879) DROPPED the mod --
	-- the Ladle contributed NOTHING to spell damage (the "node contributed nothing" class,
	-- same as chaos-bolts-exult-in-misery / aerial-prowess, NOT an active over-count). A
	-- stale Data/ModCache.lua row cached that dropped shape (flat MORE 6 + residue) and,
	-- being cache-first, shadowed any live rule. "per stack of bleed on the target"
	-- (below) already establishes the "on the target" suffix -> actor="enemy". ModParser
	-- strips the "(up to 8)" parenthetical BEFORE this lookup, so the key carries no
	-- parens and the cap rides limit=8 (the shared "on enemy" entry above stays limit-less
	-- on purpose: its Chaos Bolts consumer is config-capped at 4). With the alias the mod
	-- now parses residue-free -> the item loader KEEPS it as a proper per-ailment MORE.
	-- Default config EnemyNegativeAilmentCount=0 -> multiplier 0 -> MORE 1.0, so the fix
	-- is CORPUS-NEUTRAL (0/28 Ladle builds change, snapshots byte-identical, NO regen) and
	-- its value is newly ENABLING the scaling when the count is set (verified: Rip Blood
	-- Warlock om6xj3n8 FullDPS x1.26 at count=8). It is 6% PER distinct enemy negative
	-- ailment up to 8 = max +48%, and 0 with none. Affects 5 Maxroll S-tier curse/ailment
	-- builds (Profane Veil / Rip Blood Lich+Warlock / Lightning Blast RM / Shatter Totem).
	-- Spec: spec/System/TestLadleNegativeAilmentTarget_spec.lua
	["per negative ailment on the target"] = { tag = { type = "Multiplier", var = "EnemyNegativeAilmentCount", actor = "enemy", limit = 8 } },
	-- @leb-regression-guard:warpath-warslash-spin-duration-more (tag site)
	-- Warpath "Giant Splitter" (va53st-21, Warpath tree node, tree_2.json,
	-- maxPoints 5). Stats: " Warslash After Warpath", "+15% Slash Damage Per Second
	-- Spinning", "+15% Area Per Second Spinning"; notScalingStats "5 Maximum
	-- Duration Benefit (seconds)". Description: "After spinning for at least 2
	-- seconds you do a Warslash when you stop spinning. This deals more damage
	-- (multiplicative with other modifiers) in a larger area for each second you
	-- spent spinning, up to a maximum duration." datamining formula
	-- (datamined game source .../c_spawn_specs datamined game source):
	-- MoreStat(min(spinSeconds, 5) x (15% x pointsAllocated)) -- i.e. the per-point
	-- 15% MORE is multiplied by the number of seconds spent spinning, capped at 5s.
	-- The "Slash" decorator is consumed by the `["slash damage"] = "Damage"`
	-- modNameList entry above so the line resolves to a generic Damage MORE; this
	-- tag then attaches Multiplier:WarpathSpinSeconds. limit = 5 = the node's "5
	-- Maximum Duration Benefit (seconds)" duration cap (ModCache.lua "5 Maximum
	-- Duration Benefit (seconds)" Duration BASE 5). Scope is the DEFAULT owning-skill
	-- SkillId tag (node.skillId == "Warpath") -- va53st-21 is deliberately NOT in
	-- LE_TREE_NODE_GLOBAL_SCOPE, so the stored MORE stays on Warpath, modeling the
	-- in-game behavior that the spin-charge MORE is carried onto the Warslash fired
	-- when Warpath ends. Driven by the "Seconds spent Spinning (Warpath, max 5)"
	-- config (ifMult WarpathSpinSeconds, default 0 -> strict no-op; the planner
	-- cannot know runtime spin time, and no corpus build allocates va53st-21).
	-- Per-second stacking is ADDITIVE within the mod (one MORE of value x seconds),
	-- the AerialProwess/Throne/Germination precedent. NOTE: the sibling "+15% Area
	-- Per Second Spinning" line lives on the SAME node and scales identically
	-- in-game, but its baked ModCache row is intentionally LEFT in place (inert) so
	-- this fix stays scoped to the per-second Damage MORE only -- the larger-area
	-- benefit lands on the unmodeled Warslash sub-ability (its base hit damage is
	-- absent from prefab_damage/subprefab_damage/ability_attribute_scaling, so the
	-- Warslash is NOT registered as a damage-dealing sub-skill here).
	-- Spec: spec/System/TestWarpathSpinDurationMore_spec.lua
	["per second spinning"] = { tag = { type = "Multiplier", var = "WarpathSpinSeconds", limit = 5 } },
	-- @leb-regression-guard:dragonfang-stack-fire-damage (tag site)
	-- Marksman "Dragonfang" (Heartseeker tree node htsk5-15). The node grants
	-- "+1 Bow/Spell/Throwing Fire Damage Per Stack" (stats) with the description
	-- "Consecutive Recurves each grant a stack of Dragonfang for 10 seconds ...
	-- up to a maximum of 20." The per-stack semantics live in the node, and the
	-- bare "Per Stack" phrasing is shared by ~18 unrelated stacking stats, so the
	-- raw lines cannot be tagged generically. LE_TREE_NODE_STAT_REWRITE["htsk5-15"]
	-- (Data/Global.lua) rewrites only the trailing "Per Stack" -> "per stack of
	-- Dragonfang" (the leading Bow/Spell/Throwing keyword survives, so each line
	-- keeps its keywordFlags -> FireDamage BASE 1) so this tag attaches
	-- Multiplier:DragonfangStacks. The flat Fire is granted to and consumed by
	-- Heartseeker -- the default tree-node SkillId tag keeps it on the owning skill
	-- (NOT lifted to global scope, unlike Berserk). Datamine (datamining
	-- datamined game source): Stats__AddedStat(0, <tag>, field+0x144) =
	-- +1 Fire per stack, capped at 0x14 = 20 (L603/608). limit = 20 = the node's
	-- "up to a maximum of 20". Driven by the "# of Dragonfang Stacks" config
	-- (default 0 -> strict no-op). Per-stack stacking is ADDITIVE within the mod
	-- (one BASE mod of value x stacks), the Throne/Rhythm/Berserk/Germination/
	-- Aerial-Prowess precedent. Spec: spec/System/TestDragonfangStackFireDamage_spec.lua
	["per stack of dragonfang"] = { tag = { type = "Multiplier", var = "DragonfangStacks", limit = 20 } },
	-- @leb-regression-guard:umbral-blades-edge-of-obscurity-per-shroud (tag site)
	-- Rogue "Edge of Obscurity" (Umbral Blades tree node ub5d9-7). The node grants
	-- "+2% Damage per Dusk Shroud, up to 20" (stats); Umbral Blades gains MORE
	-- damage (multiplicative) per active Dusk Shroud, capped at 20 shrouds. The bare
	-- "per Dusk Shroud" phrasing collides with unrelated Dusk-Shroud stats, so the
	-- raw line cannot be tagged generically; LE_TREE_NODE_STAT_REWRITE["ub5d9-7"]
	-- (Data/Global.lua) rewrites it to end in "per stack of dusk shroud" (dropping
	-- the literal "20", folded here as limit) so this tag attaches
	-- Multiplier:DuskShroudStacks. The MORE is scoped to Umbral Blades (the tree's
	-- own skill) -- the default tree-node SkillId tag keeps it on the owning skill
	-- (NOT lifted to global scope). Datamine (datamining BaseUmbralBladesMutator.c
	-- :245): MORE = (InsideSmokeBomb?2:1) x nodeFloat(0x108 = 2%) x getStacks(0x52),
	-- capped at DAT_183d71c44 = 20. limit = 20 = the node's "up to 20" / "20 Max
	-- Dusk Shrouds Considered". Driven by the existing "Dusk Shroud Stacks" config
	-- (multiplierDuskShroudStacks, default 0 -> strict no-op). Per-stack stacking is
	-- ADDITIVE within the mod (one MORE of value x stacks), the Aerial Prowess /
	-- Berserk / Germination precedent. The Smoke-Bomb x2 doubling
	-- (" Doubled Inside Smoke Bomb") is a documented follow-up, NOT here.
	-- Spec: spec/System/TestUmbralBladesEdgeOfObscurity_spec.lua
	["per stack of dusk shroud"] = { tag = { type = "Multiplier", var = "DuskShroudStacks", limit = 20 } },
	["per active rune"] = { tag = { type = "Multiplier", var = "ActiveRune" } },
	-- @leb-regression-guard:gon-rune-multiplier
	-- Rune Master tree-node uses per-rune-type multipliers (Gon/Rah/Heo).
	-- Gon Rune was wired first because of Ward regen (tree_1.json L12835
	-- "+4 Ward Gain Per Second per Gon Rune"). Without this tag (and the
	-- matching "ward gain per second" nameMap alias) the mod parsed as bare
	-- `name="Ward"` BASE=4 with residue "  Gain Per Second per Gon Rune " —
	-- silent failure with no numeric Ward output diff.
	["per gon rune"] = { tag = { type = "Multiplier", var = "GonRune" } },
	-- @leb-regression-guard:heo-rah-rune-multiplier
	-- Heo/Rah sibling per-rune-type multipliers. Heo Rune affixes grant Dodge
	-- Rating per active Heo Rune (silently parsed as `name="Evasion"` BASE=N
	-- with residue "  per Heo Rune ") and the tree node "+8% Freeze Rate
	-- Multiplier per Heo Rune" (tree_1.json) was likewise stripped of its
	-- multiplier. Rah Rune affixes grant Armour per active Rah Rune, and the
	-- "2% Increased Mana Regen per Rah Rune" node lost its multiplier the
	-- same way. Mirrors the Gon Rune recipe: parser modTag + ConfigOptions
	-- count + ModCache patches + busted guard.
	["per heo rune"] = { tag = { type = "Multiplier", var = "HeoRune" } },
	["per rah rune"] = { tag = { type = "Multiplier", var = "RahRune" } },
	["per active wandering spirit"] = { tag = { type = "Multiplier", var = "ActiveWanderingSpirit" } },
	["per active crimson shroud"] = { tag = { type = "Multiplier", var = "ActiveCrimsonShroud" } },
	["per active shadow"] = { tag = { type = "Multiplier", var = "ActiveShadow" } },
	-- @leb-regression-guard:shadow-suffix-family-c6a
	-- Bare "Per Shadow" colloquial suffix + "With At Least N Shadows" threshold.
	-- ModCache had 4 silent-failure entries with these residues; the parser
	-- consumed the leading damage/area name and dropped the suffix into slot[2].
	["per shadow"] = { tag = { type = "Multiplier", var = "ActiveShadow" } },
	["with at least 3 shadows"] = { tag = { type = "MultiplierThreshold", var = "ActiveShadow", threshold = 3 } },
	["per equipped omen idol"] = { tag = { type = "Multiplier", var = "EquippedOmenIdol" } },
	["per equipped weaver item"] = { tag = { type = "Multiplier", var = "EquippedWeaverItem" } },
	-- @leb-regression-guard: weaver-will-equipped-autocount
	-- Game-accurate phrasing is "per equipped Weaver's Will Item" (datamining
	-- localization Unique_Tooltip_1_327). LEB uniques 327/8145/8191 use this
	-- form; without this mapping the Multiplier:EquippedWeaverItem tag silently
	-- dropped (e.g. Communion of the Erased "+1 Potion Slot(s) per equipped
	-- Weaver's Will Item"). The legacy "per equipped weaver item" key above is
	-- kept for back-compat. See REGRESSION_GUARDS.md "weaver-will-equipped-autocount".
	["per equipped weaver's will item"] = { tag = { type = "Multiplier", var = "EquippedWeaverItem" } },
	-- Per-summoned-minion multiplier. Multiplier:SummonedMinion is auto-supplied
	-- by CalcPerform from the sum of activeSkill.minion.minionData.limit across
	-- all minion-summoning skills, with the Config tab "# of Summoned Minions"
	-- as a manual override. Required for passives like Empty The Graves
	-- ("Increased Health Regen Per Minion").
	["per minion"]            = { tag = { type = "Multiplier", var = "SummonedMinion" } },
	["per active minion"]     = { tag = { type = "Multiplier", var = "SummonedMinion" } },
	["per summoned minion"]   = { tag = { type = "Multiplier", var = "SummonedMinion" } },
	-- Per-projectile / per-additional-totem global multipliers (fed by Config tab)
	["per projectile"] = { tag = { type = "Multiplier", var = "ProjectileCountConfig" } },
	["per additional totem summoned"] = { tag = { type = "Multiplier", var = "AdditionalTotem" } },
	["if you[' ]h?a?ve dealt a critical strike recently"] = { tag = { type = "Condition", var = "CritRecently" } },
	["on kill"] = { tag = { type = "Condition", var = "KilledRecently" } },
	["on melee kill"] = { flags = ModFlag.WeaponMelee, tag = { type = "Condition", var = "KilledRecently" } },
	["when you kill an enemy"] = { tag = { type = "Condition", var = "KilledRecently" } },
	["if you[' ]h?a?ve stunned an enemy recently"] = { tag = { type = "Condition", var = "StunnedEnemyRecently" } },
	["if you[' ]h?a?ve been hit recently"] = { tag = { type = "Condition", var = "BeenHitRecently" } },
	["if you have ?n[o']t been hit recently"] = { tag = { type = "Condition", var = "BeenHitRecently", neg = true } },
	["when you summon a totem"] = { tag = { type = "Condition", var = "SummonedTotemRecently" } },
	-- Enemy status conditions
	["against poisoned enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Poisoned" } },
	["to poisoned enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Poisoned" } },
	["against blinded enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Blinded" } },
	["against ignited enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Ignited" } },
	["to ignited enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Ignited" } },
	["against shocked enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Shocked" } },
	["to shocked enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Shocked" } },
	["against frozen enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Frozen" } },
	["to frozen enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Frozen" } },
	["against chilled enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Chilled" } },
	["to chilled enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Chilled" } },
	["against chilled or frozen enemies"] = { tag = { type = "ActorCondition", actor = "enemy", varList = { "Chilled","Frozen" } } },
	-- @leb-regression-guard:against-high-health-enemies
	-- Validation provenance is retained in maintainer notes.
	["against high health enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "HighHealth" } },
	["to high health enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "HighHealth" } },
	["against high health"] = { tag = { type = "ActorCondition", actor = "enemy", var = "HighHealth" } },
	["to high health"] = { tag = { type = "ActorCondition", actor = "enemy", var = "HighHealth" } },
	-- Additional enemy status conditions
	["against stunned enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Stunned" } },
	["to stunned enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Stunned" } },
	["against bleeding enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Bleeding" } },
	["to bleeding enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Bleeding" } },
	["against cursed enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Cursed" } },
	["to cursed enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Cursed" } },
	["to cursed"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Cursed" } },
	["against cursed"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Cursed" } },
	["against slowed enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Slowed" } },
	["to slowed enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Slowed" } },
	-- @leb-regression-guard:erasing-strike-merciful-damaged
	-- "damaged" enemy = NOT at full life. Modelled as the negation of the FullLife
	-- enemy ActorCondition (Global.lua:258). Used by the Erasing Strike Merciful
	-- node (es6ai-9) via LE_TREE_NODE_STAT_REWRITE -> "N% more melee damage against
	-- damaged enemies". Because conditionEnemyFullLife defaults OFF (ConfigOptions
	-- ~L963), the enemy is not full life by default, so neg-FullLife evaluates TRUE
	-- and the bonus applies by default (LEB "most combat occurs below full life"
	-- realistic-sustained-DPS convention). See REGRESSION_GUARDS.md.
	["against damaged enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "FullLife", neg = true } },
	-- @leb-regression-guard:enemy-full-health-alt-order
	-- "full health" enemy = at full life. Modelled as the (NON-negated) FullLife enemy
	-- ActorCondition (Global.lua:258) -- the exact opposite of "against damaged enemies"
	-- above. Base order; the word-order aliases below map to the SAME condition. The
	-- Erasing Strike Ruthless node (es6ai-10, "+25% Melee Damage Vs Full Health Enemies")
	-- parses residue-free via the "vs full health enemies" alias below -- it no longer needs
	-- a LE_TREE_NODE_STAT_REWRITE entry (that rewrite was retired as a NO-OP; the invariant
	-- lives in TestEnemyFullHealthAltOrder_spec.lua). Because conditionEnemyFullLife defaults
	-- OFF (ConfigOptions ~L897), the enemy is NOT flagged full life by default, so the
	-- (non-neg) FullLife condition evaluates FALSE and the MORE does NOT apply by default ->
	-- CORPUS-NEUTRAL (no snapshot regen). The phrase matches conditionEnemyFullLife's own
	-- suggestPattern "against full health enemies". See REGRESSION_GUARDS.md.
	["against full health enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "FullLife" } },
	-- @leb-regression-guard:enemy-full-health-alt-order
	-- Word-order aliases of the enemy FullLife conditional above. Real affix/tree lines
	-- phrase the same "enemy is at full life" condition in orders the single "against full
	-- health enemies" key did not cover: "<stat> To Full Health Enemies", "<stat> Vs Full
	-- Health Enemies", "<stat> Against Enemies At Full Health" (and the "full life" spelling
	-- of each). Without these keys the stat parsed but left "To/Vs Full Health Enemies" /
	-- "Against Enemies At Full Health" as non-empty `extra` residue -> Item.lua:1901
	-- (isConnectorOnlyExtra) DROPPED the whole mod (silent UNDER-count; the "node
	-- contributed nothing" class, same as against-full-health-enemies / to-low-health-
	-- enemies / to-moving-enemies). All map to the SAME enemy ActorCondition FullLife that
	-- conditionEnemyFullLife raises (ConfigOptions ~L984; its suggestPattern already lists
	-- "to full life enemies"/"to full health enemies"). NOTE: "against enemies at full
	-- health" contains the player-self "at full health" substring (~L1691); scan() is
	-- earliest-then-longest so this longer enemy key wins and the line stays enemy-scoped.
	-- CORPUS-NEUTRAL (no snapshot regen): conditionEnemyFullLife defaults OFF and is absent
	-- from every snapshot -> the enemy is never flagged full life -> the (non-neg) FullLife
	-- condition evaluates FALSE -> the kept MORE is inert, byte-identical to the pre-fix
	-- dropped state. Stale ModCache rows caching the dropped shapes were deleted so the
	-- lines re-parse live. Also covers the es6ai-10 (Erasing Strike Ruthless) raw line
	-- "+25% Melee Damage Vs Full Health Enemies": the "vs full health enemies" key made it
	-- parse residue-free, retiring its former LE_TREE_NODE_STAT_REWRITE entry as a NO-OP
	-- (spec asserts raw -> MORE + Melee + non-neg enemy FullLife). See REGRESSION_GUARDS.md
	-- "enemy-full-health-alt-order".
	["to full health enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "FullLife" } },
	["to full life enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "FullLife" } },
	["vs full health enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "FullLife" } },
	["vs full life enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "FullLife" } },
	["against enemies at full health"] = { tag = { type = "ActorCondition", actor = "enemy", var = "FullLife" } },
	["against enemies at full life"] = { tag = { type = "ActorCondition", actor = "enemy", var = "FullLife" } },
	-- @leb-regression-guard:to-low-health-enemies
	-- "low health" enemy = at low life (below ~35% health, execute range). Modelled as
	-- the (NON-negated) LowLife enemy ActorCondition (Global.lua:256), the mirror of the
	-- FullLife entry above. Used by uniques like Swaddling of the Erased (uniques_1_4 #293
	-- "(12-17)% more Spell Damage to Low Health Enemies"). The parser had the PLAYER-self
	-- "at low health"/"while at low health" -> Condition:LowLife forms (~L1575) but NO
	-- enemy-scoped "to low health enemies" phrase, so the stat parsed but left "to Low
	-- Health Enemies" as `extra` residue -> Item.lua:1901 (`isConnectorOnlyExtra`) DROPPED
	-- the whole mod (silent UNDER-count; the "node contributed nothing" class, same as
	-- ladle-negative-ailment-on-target / against-rares-and-bosses). conditionEnemyLowLife
	-- ALREADY anticipates this exact vocabulary in its suggestPattern ("to low health
	-- enemies", "more spell damage to low health"; ConfigOptions.lua ~L980) -- it just had
	-- no modTagList entry to make the phrase resolve. Because conditionEnemyLowLife defaults
	-- OFF, the enemy is NOT flagged low life by default -> the (non-neg) LowLife condition
	-- evaluates FALSE and the MORE does NOT apply by default -> CORPUS-NEUTRAL (no snapshot
	-- regen; enable the config for execute-range/burst evaluation to make it live). A stale
	-- ModCache row (the dropped flat-MORE + residue shape) was deleted so it re-parses live.
	-- See REGRESSION_GUARDS.md "to-low-health-enemies".
	["to low health enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "LowLife" } },
	-- @leb-regression-guard:to-moving-enemies
	-- Enemy-motion conditional "<stat> to Moving Enemies". Modelled as the enemy
	-- ActorCondition Moving -- the exact condition conditionEnemyMoving raises
	-- (ConfigOptions.lua ~L960: enemyModList "Condition:Moving"; its tooltip already
	-- names "'against moving enemies' modifiers"). The parser only had the PLAYER-self
	-- "while moving" -> Condition:Moving form (~L918), NO enemy-scoped "to moving
	-- enemies" phrase, so uniques like Blood of the Exile (uniques_1_4 #306 "(30-40)%
	-- more Physical Ailment Damage to Moving Enemies") parsed the leading stat but left
	-- "to Moving Enemies" as `extra` residue -> Item.lua:1901 (`isConnectorOnlyExtra`)
	-- DROPPED the whole mod (silent UNDER-count; the "node contributed nothing" class,
	-- same as ladle-negative-ailment-on-target / to-low-health-enemies). Because
	-- conditionEnemyMoving defaults OFF, the enemy is NOT flagged moving by default ->
	-- the Moving condition evaluates FALSE and the MORE does NOT apply by default ->
	-- CORPUS-NEUTRAL (no snapshot regen; enable the config to make it live). Two stale
	-- ModCache rows (the dropped MORE + residue shape, for both this line and the
	-- affix/tree "+15% Hit Damage To Moving Enemies") were deleted so they re-parse live.
	-- See REGRESSION_GUARDS.md "to-moving-enemies".
	["to moving enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Moving" } },
	-- @leb-regression-guard:against-ailment-no-enemies-suffix
	-- Article/noun-less "Against <ailment>" suffix (no trailing "enemies"/"targets"),
	-- the form LEB passive/skill-tree stats actually use (e.g. Marksman/Falconer
	-- "+20% Hit Damage Against Bleeding", "10% More Damage Against Chilled",
	-- "20% More Crit Chance Against Frozen Targets"). The parser only had the
	-- "against <ailment> enemies" forms, so the bare form parsed the leading stat
	-- but left "Against <ailment>" as `extra` residue (often mangled to "Against
	-- ed/ing" because a damage-type fragment was consumed) -> PassiveSpec.lua:1024
	-- dropped the whole mod (silent UNDER-count; same class as with-1h-suffix-family).
	-- Mirrors the pre-existing no-"enemies" precedent "against cursed"/"to cursed".
	-- Each ailment's enemy ActorCondition var already exists (used by the "enemies"
	-- forms above). Immobilized is intentionally NOT added here -- no enemy
	-- Immobilized condition var exists yet (needs separate grounding).
	["against bleeding"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Bleeding" } },
	["against poisoned"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Poisoned" } },
	["against chilled"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Chilled" } },
	["against frozen"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Frozen" } },
	["against frozen targets"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Frozen" } },
	["against ignited"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Ignited" } },
	["against shocked"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Shocked" } },
	["against slowed"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Slowed" } },
	["against chilled or frozen"] = { tag = { type = "ActorCondition", actor = "enemy", varList = { "Chilled","Frozen" } } },
	-- @leb-regression-guard:against-rares-and-bosses
	-- Validation provenance is retained in maintainer notes.
	["against rares and bosses"] = { tag = { type = "ActorCondition", actor = "enemy", varList = { "Rare","Boss" } } },
	["to rares and bosses"] = { tag = { type = "ActorCondition", actor = "enemy", varList = { "Rare","Boss" } } },
	["vs rares and bosses"] = { tag = { type = "ActorCondition", actor = "enemy", varList = { "Rare","Boss" } } },
	-- @leb-regression-guard:to-bosses-and-rare-enemies
	-- See REGRESSION_GUARDS.md "to-bosses-and-rare-enemies".
	-- Validation provenance is retained in maintainer notes.
	["to bosses and rare enemies"] = { tag = { type = "ActorCondition", actor = "enemy", varList = { "Rare","Boss" } } },
	-- @leb-regression-guard:against-distant-enemies
	-- Validation provenance is retained in maintainer notes.
	["against distant enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Distant" } },
	["to distant enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Distant" } },
	-- "from X enemies" — damage taken conditional tags
	["from chilled enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Chilled" } },
	["from ignited enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Ignited" } },
	["from shocked enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Shocked" } },
	["from slowed enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Slowed" } },
	["from frozen enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Frozen" } },
	["from bleeding enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Bleeding" } },
	["from poisoned enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Poisoned" } },
	["from time rotting enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "TimeRotted" } },
	["to time rotting enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "TimeRotted" } },
	["against time rotting enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "TimeRotted" } },
	["against frail enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Frail" } },
	["to frail enemies"] = { tag = { type = "ActorCondition", actor = "enemy", var = "Frail" } },
	["against enemies hit recently"] = { tag = { type = "ActorCondition", actor = "enemy", var = "HitRecently" } },
	["against enemies stunned recently"] = { tag = { type = "ActorCondition", actor = "enemy", var = "StunnedRecently" } },
	-- @leb-regression-guard:near-enemy-proximity-suffix-eat
	-- Bastion of Honour Old Kite Shield intrinsic
	-- "+1% Block Chance per Strength against enemies within 4 metres" parses
	-- modName="BlockChance", per-Stat tag from "per Strength", and leaves
	-- "against enemies within 4 metres" as `extra` residue. PassiveTree.lua
	-- (`if mod.list and not mod.extra`) silently drops any mod with non-empty
	-- extra — for an Str=125 build that means -125% BlockChance vanishes.
	-- LETools always counts this bonus (it does not gate on proximity), so the
	-- correct fix is to noise-eat the suffix: register an empty modTagList
	-- entry so the scan consumes the residue without attaching a Condition.
	-- This matches LETools display behaviour AND keeps the parser's extra
	-- empty so consumers retain the mod. Pattern uses (%d+) instead of "4"
	-- so the same handler covers any future "within N metres" reroll.
	-- Spec: spec/System/TestNearEnemyProximitySuffixEat_spec.lua
	["against enemies within (%d+) metres"] = { },
	["if the enemy was hit recently"] = { tag = { type = "ActorCondition", actor = "enemy", var = "HitRecently" } },
	["if the enemy was stunned recently"] = { tag = { type = "ActorCondition", actor = "enemy", var = "StunnedRecently" } },
	["if the enemy was killed recently"] = { tag = { type = "ActorCondition", actor = "enemy", var = "KilledRecently" } },
	-- Per-stack enemy ailment multipliers
	["per bleed stack"] = { tag = { type = "Multiplier", var = "BleedStack", actor = "enemy" } },
	["per ignite stack"] = { tag = { type = "Multiplier", var = "IgniteStack", actor = "enemy" } },
	["per shock stack"] = { tag = { type = "Multiplier", var = "ShockStack", actor = "enemy" } },
	["per chill stack"] = { tag = { type = "Multiplier", var = "ChillStack", actor = "enemy" } },
	["per poison stack"] = { tag = { type = "Multiplier", var = "PoisonStack", actor = "enemy" } },
	["per time rot stack"] = { tag = { type = "Multiplier", var = "TimeRotStack", actor = "enemy" } },
	["per doom stack"] = { tag = { type = "Multiplier", var = "DoomStack", actor = "enemy" } },
	["per slow stack"] = { tag = { type = "Multiplier", var = "SlowStack", actor = "enemy" } },
	["per frailty stack"] = { tag = { type = "Multiplier", var = "FrailtyStack", actor = "enemy" } },
	["per curse stack"] = { tag = { type = "Multiplier", var = "CurseStack", actor = "enemy" } },
	-- @leb-regression-guard:per-bleed-stack-suffix-family
	-- Colloquial "per Bleed" / "Per Bleed" used by passive-tree stats — must
	-- be a modTagList match so the SkillName eater doesn't consume "Bleed"
	-- first. Mirrors the existing "per bleed stack" pattern. Without these
	-- 7 entries the parser fell through and the inner mod applied
	-- unconditionally to any "of Bleed skill" computation.
	["per bleed"] = { tag = { type = "Multiplier", var = "BleedStack", actor = "enemy" } },
	["per 10 bleeds on the target, up to 200 bleeds"] = { tag = { type = "Multiplier", var = "BleedStack", actor = "enemy", div = 10, limit = 20 } },
	["per 10 bleeds on enemy, up to 20%"] = { tag = { type = "Multiplier", var = "BleedStack", actor = "enemy", div = 10, limit = 20 } },
	["per stack of bleed on you"] = { tag = { type = "Multiplier", var = "BleedStack", actor = "self" } },
	["per stack of bleed on the enemy releasing it"] = { tag = { type = "Multiplier", var = "BleedStack", actor = "enemy", limit = 20 } },
	["per stack of bleed on the target"] = { tag = { type = "Multiplier", var = "BleedStack", actor = "enemy" } },
	["per 10% bleed chance"] = { tag = { type = "PerStat", stat = "BleedChance", div = 10 } },
	-- @leb-regression-guard:foot-of-the-mountain-dodge-to-endurance (mana-cost site)
	-- Foot of the Mountain: "-2 Mana Cost per stack of Mountain's Endurance"
	-- (uniques_1_4 #253). Stacks are gained per second while not moving (cap 3),
	-- proxied by Multiplier:StationarySeconds; limit 3 enforces the in-game
	-- 3-stack maximum. UNLIKE the paired dodge->EndThr conversion (binary 100%),
	-- the mana cost DOES scale with stack count. No Condition tag needed: at 0
	-- stacks the multiplier is 0, so the reduction self-gates.
	["per stack of mountains endurance"] = { tag = { type = "Multiplier", var = "StationarySeconds", limit = 3 } },
	-- Transformation form conditions
	["while in werebear form"] = { tag = { type = "Condition", var = "InWerebearForm" } },
	["in werebear form"] = { tag = { type = "Condition", var = "InWerebearForm" } },
	["while in spriggan form"] = { tag = { type = "Condition", var = "InSprigganForm" } },
	["in spriggan form"] = { tag = { type = "Condition", var = "InSprigganForm" } },
	["while in swarmblade form"] = { tag = { type = "Condition", var = "InSwarmbladeForm" } },
	["in swarmblade form"] = { tag = { type = "Condition", var = "InSwarmbladeForm" } },
	["while in reaper form"] = { tag = { type = "Condition", var = "InReaperForm" } },
	["in reaper form"] = { tag = { type = "Condition", var = "InReaperForm" } },
	-- Druid passive node OR-conditionals. Translated to NAND on the other forms:
	-- "In Human Or Spriggan" fires when NOT in {Werebear, Swarmblade, Reaper}.
	-- "In Bear Or Swarmblade" fires when in {Werebear, Swarmblade}.
	-- Used by Aspects of Might (1% Armor Per Str In Human/Spriggan + 1% Melee
	-- Damage Per Str In Bear/Swarmblade) and similar Druid mastery nodes.
	["in human or spriggan"] = { tag = { type = "Condition", varList = { "InWerebearForm", "InSwarmbladeForm", "InReaperForm" }, neg = true } },
	["in bear or swarmblade"] = { tag = { type = "Condition", varList = { "InWerebearForm", "InSwarmbladeForm" } } },
	-- "recently" conditions not yet handled
	["if echoed recently"] = { tag = { type = "Condition", var = "EchoedRecently" } },
	["if you have directly cast a cold spell recently"] = { tag = { type = "Condition", var = "DirectlyCastColdSpellRecently" } },
	["if you have directly cast a physical spell recently"] = { tag = { type = "Condition", var = "DirectlyCastPhysSpellRecently" } },
	["if cast physical spell recently"] = { tag = { type = "Condition", var = "DirectlyCastPhysSpellRecently" } },
	["if cast cold spell recently"] = { tag = { type = "Condition", var = "DirectlyCastColdSpellRecently" } },
	["if you have cast devouring orb recently"] = { tag = { type = "Condition", var = "CastDevouringOrbRecently" } },
	["for each meteor you have cast recently"] = { tag = { type = "Multiplier", var = "MeteorCastRecently" } },
	-- Player: Potion / Forged Weapon
	["while you have used a potion recently"] = { tag = { type = "Condition", var = "UsedPotionRecently" } },
	["after using a potion"] = { tag = { type = "Condition", var = "UsedPotionRecently" } },
	["when you use a potion"] = { tag = { type = "Condition", var = "UsedPotionRecently" } },
	-- Player: Offhand type conditions
	["while using evade"] = { tag = { type = "Condition", var = "UsingEvade" } },
	["while using a catalyst"] = { tag = { type = "Condition", var = "UsingCatalyst" } },
	["while using a shield"] = { tag = { type = "Condition", var = "UsingShield" } },
	-- @leb-regression-guard:with-a-shield-condition
	-- LE class trees use the short form "With A Shield" (e.g. Sentinel-90
	-- "Sanctuary Guardian": +15% All Resistances With A Shield in notScalingStats).
	-- Without this entry the trailing " with a shield" survives as residual extra
	-- in modLib.parseMod, which sets node.extra=true in PassiveTree.lua and
	-- prevents the entire mod from reaching modDB — silently dropping ~15 from
	-- every resistance on <private build> (and any shield-using build).
	-- Spec: spec/System/TestModParse_spec.lua "with a shield condition tag"
	["with a shield"] = { tag = { type = "Condition", var = "UsingShield" } },
	-- @leb-regression-guard:while-with-a-shield-condition
	-- Sentinel-90 "Sanctuary Guardian" notScalingStats also uses the long form
	-- "While With A Shield" (e.g. "+50 Armor While With A Shield"). Without this
	-- entry the trailing " while with a shield" leaves residual extra and the
	-- entire mod is silently dropped from modDB on <private build> (Paladin, lv95).
	-- Spec: spec/System/TestModParse_spec.lua "while with a shield condition tag"
	["while with a shield"] = { tag = { type = "Condition", var = "UsingShield" } },
	-- @leb-regression-guard:traitors-tongue-offhand-crit-flat
	-- Traitor's Tongue (dual-wield dagger) has cross-slot self-referential mods:
	-- "+(10-13)% Parry Chance with Traitor's Tongue equipped in the mainhand"
	-- "+(10-13)% Critical Strike Chance with Traitor's Tongue equipped in the offhand"
	-- Without these matchers the trailing condition survives as residual extra and
	-- Item.lua's processModLine (isConnectorOnlyExtra) silently drops the entire
	-- mod from modDB — e.g. on <private build> (Bladedancer, lv100) the +12 flat
	-- CritChance was missing from every skill's CritChance output.
	-- Spec: spec/System/TestModParse_spec.lua "equipped in the offhand/mainhand condition tag"
	-- Game data check (2026-05-12): only Traitor's Tongue uses this pattern in
	-- unique_mods_generated.json; no affix/set bonus matches. Generic name capture
	-- via "(.-)" supports future cross-slot uniques without per-item patches.
	["with (.-) equipped in the offhand"] = function(name) return { tag = { type = "Condition", var = "OffhandHas:" .. name } } end,
	["with (.-) equipped in the mainhand"] = function(name) return { tag = { type = "Condition", var = "MainHandHas:" .. name } } end,
	-- @leb-regression-guard:per-1pct-increased-movement-speed
	-- Unbroken Charge unique grants "+(11-30) Block Effectiveness per 1% Increased
	-- Movement Speed". Without this matcher the trailing " per 1% increased
	-- movement speed" leaves residual extra and the mod is silently dropped from
	-- modDB. Multiplier:MovementSpeedInc is auto-populated in CalcSetup.lua.
	-- Spec: spec/System/TestModParse_spec.lua "per 1% increased movement speed multiplier"
	["per 1%% increased movement speed"] = { tag = { type = "Multiplier", var = "MovementSpeedInc" } },
	-- @leb-regression-guard:cradle-of-the-erased-block-eff-per-uncapped-resist
	-- Cradle of the Erased unique grants "+1 Block Effectiveness per 1% Total
	-- Uncapped Resistance". Without this matcher the trailing " per 1% total
	-- uncapped resistance" leaves residual extra and the BlockEffectiveness mod is
	-- silently dropped (<private build> Beastmaster lv98: LEB BlockEffectiveness=90 vs
	-- LET=945; derived Block Mitigation 12 vs 35). Mirrors the sibling
	-- "per 1%% increased movement speed" matcher above.
	-- Game-data basis (LE localization Property_Player_272_AltText, verbatim):
	--   "Your total uncapped resistance is the sum of your uncapped physical,
	--    fire, lightning, cold, necrotic, void, and poison resistances."
	-- That 7-resist set is exactly Multiplier:UncappedResistTotal, auto-populated
	-- in CalcSetup.lua (Sum BASE on Fire/Cold/Lightning/Physical/Necrotic/Void/
	-- Poison resist) and already used by the Ward Per Second uncapped-resist family.
	-- Spec: spec/System/TestModParse_spec.lua "per 1% total uncapped resistance multiplier"
	["per 1%% total uncapped resistance"] = { tag = { type = "Multiplier", var = "UncappedResistTotal" } },
	-- @leb-regression-guard:thicket-reflect-per-uncapped-phys-res
	-- Thicket of Blinding Light (uniques_1_4 #426) carries the craft affix
	-- "(11-17) Damage Reflected to Attackers per 10% uncapped Physical Resistance".
	-- The BASE stat "damage reflected to attackers" -> DamageReflectedToAttackers
	-- (modNameList l.163) already parses, but WITHOUT this tag phrase the trailing
	-- " per 10% uncapped physical resistance" leaves residual extra and the whole
	-- per-uncapped-phys-res flat-reflect term is silently dropped -> in-game "Thorns"
	-- reads UNDER (HitMeBabyOneMoreTime: LEB 33096 vs in-game 34609, -4.4%).
	-- Per-TYPE uncapped physical resistance, NOT total: mirrors the per-type
	-- Multiplier:UncappedFireResist pattern (Incinerating Aura), auto-populated in
	-- CalcSetup.lua as Sum BASE on PhysicalResist (raw/overcap-inclusive, matching the
	-- in-game "uncapped" wording). div=10 for the "per 10%" step.
	-- Spec: spec/System/TestModParse_spec.lua "reflect per 10% uncapped physical resistance"
	["per 10%% uncapped physical resistance"] = { tag = { type = "Multiplier", var = "UncappedPhysicalResist", div = 10 } },
	["per forged weapon"] = { tag = { type = "Multiplier", var = "ForgedWeapon" } },
	["while you have a forged weapon"] = { tag = { type = "Condition", var = "HaveForgedWeapon" } },
	-- Runemaster: Glyph of Dominion / Arcane Momentum
	["while standing on your glyph of dominion"] = { tag = { type = "Condition", var = "StandingOnGlyphOfDominion" } },
	["while near an enemy"] = { tag = { type = "Condition", var = "NearEnemy" } },
	["from nearby enemies"] = { tag = { type = "Condition", var = "NearEnemy" } },
	-- Player health threshold conditions
	["at low health"] = { tag = { type = "Condition", var = "LowLife" } },
	["while at low health"] = { tag = { type = "Condition", var = "LowLife" } },
	["at low life"] = { tag = { type = "Condition", var = "LowLife" } },
	["while at low life"] = { tag = { type = "Condition", var = "LowLife" } },
	-- @leb-regression-guard:while-at-full-health
	-- Player-self "at Full Health/Life" damage/crit conditional, the FullLife mirror of
	-- the LowLife player forms just above. Used by Xithara's Conundrum (uniques_1_4 #133
	-- "(25-30)% more Physical Damage while at Full Health") and Full-Health crit/damage
	-- affixes ("+40% <Melee/Throwing> Critical Strike Multiplier while at Full Health",
	-- "10% Increased Damage at Full Health"). The parser had the ENEMY form ("against
	-- full health enemies" -> ActorCondition FullLife) but NO player-self "while at full
	-- health" phrase, so these parsed the leading stat but left "while at Full Health"
	-- as `extra` residue -> Item.lua:1901 / PassiveSpec DROPPED the whole mod (silent
	-- UNDER-count, "node contributed nothing" class). conditionFullLife (ConfigOptions
	-- L92) ALREADY anticipates this exact vocabulary in its suggestPattern ("while at
	-- full health", "while at full life", "while on full health", "on full health") --
	-- it just had no modTagList entry to make the phrase resolve. Maps to the player
	-- Condition:FullLife (the config's own flag, ConfigOptions L93). CORPUS-NEUTRAL
	-- (deductively proven, no snapshot regen): the ONLY setter of the player
	-- Condition:FullLife flag is conditionFullLife's apply, which is absent from EVERY
	-- corpus snapshot -> default OFF -> the player is NOT flagged full life -> the
	-- Condition evaluates FALSE and the mod is inert by default. Enable the config
	-- (opener/burst evaluation) to make it live. Stale ModCache rows (the dropped
	-- shapes for Xithara's MORE + the two crit-mult BASE + the INC-damage row) were
	-- deleted so the lines re-parse live. See REGRESSION_GUARDS.md "while-at-full-health".
	["at full health"] = { tag = { type = "Condition", var = "FullLife" } },
	["while at full health"] = { tag = { type = "Condition", var = "FullLife" } },
	["at full life"] = { tag = { type = "Condition", var = "FullLife" } },
	["while at full life"] = { tag = { type = "Condition", var = "FullLife" } },
	["on full health"] = { tag = { type = "Condition", var = "FullLife" } },
	["while on full health"] = { tag = { type = "Condition", var = "FullLife" } },
	-- @leb-regression-guard:mana-missing-not-full-mechanics
	-- LE "While Not Full Mana" (e.g. "+10% Damage While Not Full Mana",
	-- "+1% Leech While Not Full Mana"). Driven by Config "Your Missing Mana %"
	-- (> 0 sets Condition:NotFullMana). The planner models full mana by default,
	-- so this is OFF until the user indicates missing mana.
	["while not full mana"] = { tag = { type = "Condition", var = "NotFullMana" } },
	["not full mana"] = { tag = { type = "Condition", var = "NotFullMana" } },
	["per arcane momentum stack"] = { tag = { type = "Multiplier", var = "ArcaneMomentumStack" } },
	-- Blocking
	["on block"] = { tag = { type = "Condition", var = "Blocking" } },
	["while blocking"] = { tag = { type = "Condition", var = "Blocking" } },
}

for i,stat in ipairs(LongAttributes) do
	-- @leb-regression-guard:notscaling-health-regen-per-vitality
	-- This generic "per <LongAttribute>" -> PerStat loop is (together with the
	-- "health regen"->LifeRegen modName entry) what makes Acolyte-39 "Bed of Souls"
	-- notScaling string "2% Increased Health Regen per Vitality" parse into an INC
	-- LifeRegen mod carrying PerStat:Vit. It is NOT a dedicated node fix -- a refactor
	-- that drops this per-attribute tag would silently zero the node's contribution.
	-- Spec: spec/System/TestNotScalingHealthRegenPerVitality_spec.lua
	modTagList["per " .. stat:lower()] = { tag = { type = "PerStat", stat = Attributes[i] } }
	modTagList["per point of " .. stat:lower()] = { tag = { type = "PerStat", stat = Attributes[i] } }
	modTagList["per player " .. stat:lower()] = { tag = { type = "PerStat", stat = Attributes[i], actor = "parent" } }
	modTagList["per (%d+) " .. stat:lower()] = function(num) return { tag = { type = "PerStat", stat = Attributes[i], div = num } } end
	modTagList["w?h?i[lf]e? you have at least (%d+) " .. stat:lower()] = function(num) return { tag = { type = "StatThreshold", stat = Attributes[i], threshold = num } } end
	-- @leb-regression-guard:with-attribute-threshold
	-- LE phrasing "with N <Attribute>" gates the leading effect behind a StatThreshold
	-- (the effect applies in full once you reach N points of the attribute — it is
	-- NOT a per-N divisor). Example: Mage-91 "Transcendence" rank 6 grants
	-- "+24 Additional Ward per Second with 60 Intelligence" — players above 60 Int
	-- get the full +24, otherwise 0. Without this entry the tail parses as `extra`
	-- and PassiveTree.lua:458 silently drops the entire mod list.
	-- Spec: spec/System/TestWithAttributeThreshold_spec.lua
	modTagList["with (%d+) " .. stat:lower()] = function(num) return { tag = { type = "StatThreshold", stat = Attributes[i], threshold = num } } end
end
-- Also handle abbreviated attribute names (e.g. "Per Int" in addition to "Per Intelligence")
for i,stat in ipairs(Attributes) do
	local abbr = stat:lower()
	modTagList["per " .. abbr] = { tag = { type = "PerStat", stat = Attributes[i] } }
	modTagList["per point of " .. abbr] = { tag = { type = "PerStat", stat = Attributes[i] } }
	modTagList["per player " .. abbr] = { tag = { type = "PerStat", stat = Attributes[i], actor = "parent" } }
	modTagList["per (%d+) " .. abbr] = function(num) return { tag = { type = "PerStat", stat = Attributes[i], div = num } } end
	modTagList["with (%d+) " .. abbr] = function(num) return { tag = { type = "StatThreshold", stat = Attributes[i], threshold = num } } end
end
-- Season 4 (1.4) converted attributes
local S4Attributes = {
	{ long = "guile",     stat = "Guile" },
	{ long = "brutality", stat = "Brutality" },
	{ long = "madness",   stat = "Madness" },
	{ long = "apathy",    stat = "Apathy" },
	{ long = "rampancy",  stat = "Rampancy" },
}
for _, s4 in ipairs(S4Attributes) do
	local s = s4.stat
	modTagList["per " .. s4.long] = { tag = { type = "PerStat", stat = s } }
	modTagList["per (%d+) " .. s4.long] = function(num) return { tag = { type = "PerStat", stat = s, div = num } } end
	modTagList["w?h?i[lf]e? you have at least (%d+) " .. s4.long] = function(num) return { tag = { type = "StatThreshold", stat = s, threshold = num } } end
end
-- @leb-regression-guard:with-weapon-type-condition-modcache-sync
-- Validation provenance is retained in maintainer notes.
for _, weapon in ipairs(DamageSourceWeapons) do
	modTagList["with an? " .. weapon:lower()] = { tag = { type = "Condition", var = "Using" .. weapon } }
	modTagList["with " .. weapon:lower()] = { tag = { type = "Condition", var = "Using" .. weapon } }
	modTagList["while wielding a " .. weapon:lower()] = { tag = { type = "Condition", var = "Using" .. weapon } }
	-- @leb-regression-guard:wielding-weapon-conditions
	-- 2-Handed variant: "+N Spell Damage while wielding a 2 Handed Axe" etc.
	-- Without this entry the "2 Handed " phrase was stripped to residue and
	-- the mod applied to any Axe (1H or 2H) — silently wrong. tagList
	-- combines the weapon condition with UsingTwoHandedWeapon (CalcSetup
	-- publishes the latter when `not w1info.oneHand`).
	modTagList["while wielding a 2 handed " .. weapon:lower()] = { tagList = { { type = "Condition", var = "Using" .. weapon }, { type = "Condition", var = "UsingTwoHandedWeapon" } } }
	-- @leb-regression-guard:with-2h-suffix-family
	-- LEB passive-tree node text uses the colloquial "With 2h <Weapon>" form
	-- (e.g. Rogue-83 Expert Duelist "Melee Attack Speed With 2h Sword").
	-- Without this entry the parser stripped only "With 2h " and applied the
	-- mod to any wielded weapon of that subtype, dropping the 2-handed gate.
	modTagList["with 2h " .. weapon:lower()] = { tagList = { { type = "Condition", var = "Using" .. weapon }, { type = "Condition", var = "UsingTwoHandedWeapon" } } }
	modTagList["per equipped " .. weapon:lower()] = { tag = { type = "Multiplier", var = weapon .. "Item" } }
	modTagList["per " .. weapon:lower()] = { tag = { type = "Multiplier", var = weapon .. "Item" } }
end
-- @leb-regression-guard:with-2h-suffix-family
-- Generic "With 2h" / "With 2h Weapon" suffix (no specific subtype).
-- Sources: Sentinel-111 Champion of the Forge ("+1% Crit Multi Per 2 Str
-- With 2h", "10% Increased Crit Chance With 2h"), Sentinel-68 Master of
-- Arms ("+2 Strength With 2h Weapon"), Warpath va53st-7 Battlemaster's
-- Blade ("+20% Area With 2h"), Tempest Strike ts85i-16 Heorot's Arsenal
-- ("+8 Spell Damage With 2h Weapon"), Rogue-83 Expert Duelist
-- ("7% Increased Melee Damage With 2h Weapon").
modTagList["with 2h"] = { tag = { type = "Condition", var = "UsingTwoHandedWeapon" } }
modTagList["with 2h weapon"] = { tag = { type = "Condition", var = "UsingTwoHandedWeapon" } }
-- @leb-regression-guard:with-1h-suffix-family
-- Symmetric "With 1h" / "With 1h Weapon" suffix (no specific subtype), the 1H
-- counterpart of the "with 2h" family above. Source: Rogue-88 "Fencing Grace"
-- ("6% Increased Damage With 1h Weapon", "+5% Block Chance With 1h Weapon").
-- Without this entry parseMod recognises the leading "X% increased damage" but
-- leaves "with 1h weapon" as `extra`, so PassiveSpec.lua:1024 (`if mod.list and
-- not mod.extra`) DROPS the whole mod -> the conditional damage silently
-- vanishes for 1H-wielding rogues (UNDER-count). The condition var
-- UsingOneHandedWeapon is published by CalcPerform.lua:177-178/196 (info.oneHand),
-- so the gate correctly applies for 1H and evaluates false (0) for 2H/bow.
-- NOTE: the prior "1h"->"7h" rank-scale mangling on this node is a SEPARATE,
-- already-fixed issue (tree-rank-scale-skip-weapon-hand-token).
modTagList["with 1h"] = { tag = { type = "Condition", var = "UsingOneHandedWeapon" } }
modTagList["with 1h weapon"] = { tag = { type = "Condition", var = "UsingOneHandedWeapon" } }
-- @leb-regression-guard:with-spelled-equipment-condition
-- Spelled-out equipment-condition suffixes that LEB tree/affix data uses but the
-- parser lacked, so the stat parsed with the condition left as `extra` residue and
-- PassiveSpec.lua:1024 dropped it (same silent-drop class as with-1h/2h-suffix-family).
--  - "With Two Handed Weapon" (spelled out) is the verbose form of "With 2h Weapon"
--    -> UsingTwoHandedWeapon (e.g. "+10% Area With Two Handed Weapon").
--  - "With Shield" (no article) is the article-less form of the existing "with a
--    shield" -> UsingShield (e.g. "15% Increased Physical Damage With Shield",
--    "+15% Bleed Chance With Shield"). UsingShield is published by
--    CalcPerform.lua:161 / CalcSetup.lua:2017.
-- Both condition vars are already computed; the matching ModCache entries are
-- patched to carry the condition with empty residue (ModCache short-circuits the
-- parser otherwise — see with-1h-suffix-family).
modTagList["with two handed weapon"] = { tag = { type = "Condition", var = "UsingTwoHandedWeapon" } }
modTagList["with shield"] = { tag = { type = "Condition", var = "UsingShield" } }
modTagList["with spear"] = { tag = { type = "Condition", var = "UsingSpear" } }
modTagList["with a spear"] = { tag = { type = "Condition", var = "UsingSpear" } }
-- @leb-regression-guard:dual-wield-pair-suffix-family
-- Rogue-65 "Weapons of Choice" (and similar dual-wield nodes) describe
-- bonuses as "with a <Weapon> and (a) <Weapon>" or "with 2 <Weapons>".
-- Before this loop the parser stripped only the trailing weapon (matched
-- by the single-weapon "with a <weapon>" handler), leaving the first
-- weapon and the connector in slot[2] residue — the dual-wield gate and
-- the first weapon condition were both lost. Each pair handler emits a
-- tagList with both weapon conditions PLUS DualWielding. Same-weapon
-- "with 2 <weapons>" forms emit Using<Weapon> + DualWielding.
for _, w1 in ipairs(DamageSourceWeapons) do
	for _, w2 in ipairs(DamageSourceWeapons) do
		if w1 ~= w2 then
			local a1 = (w1 == "Axe") and "an" or "a"
			local tagList = {
				{ type = "Condition", var = "Using" .. w1 },
				{ type = "Condition", var = "Using" .. w2 },
				{ type = "Condition", var = "DualWielding" },
			}
			modTagList["with " .. a1 .. " " .. w1:lower() .. " and " .. w2:lower()] = { tagList = tagList }
			modTagList["with " .. a1 .. " " .. w1:lower() .. " and a " .. w2:lower()] = { tagList = tagList }
			modTagList["with " .. a1 .. " " .. w1:lower() .. " and an " .. w2:lower()] = { tagList = tagList }
		end
	end
	-- "with 2 <weapons>" pluralisation: Axe->Axes, Sword->Swords, etc.
	-- All DamageSourceWeapons take a simple "s" suffix.
	modTagList["with 2 " .. w1:lower() .. "s"] = { tagList = { { type = "Condition", var = "Using" .. w1 }, { type = "Condition", var = "DualWielding" } } }
end

local mod = modLib.createMod
local function flag(name, ...)
	return mod(name, "FLAG", true, ...)
end

local dmgTypeNames = {}
for _, dt in ipairs(DamageTypes) do
	dmgTypeNames[dt:lower()] = dt
	dmgTypeNames[dt:lower() .. " damage"] = dt
	dmgTypeNames[dt:lower() .. " conversion"] = dt
end
dmgTypeNames["base damage"] = "Physical"
dmgTypeNames["base physical damage"] = "Physical"
dmgTypeNames["base melee damage"] = "Physical"
dmgTypeNames["melee base damage"] = "Physical"
dmgTypeNames["base necrotic damage"] = "Necrotic"
dmgTypeNames["base lightning damage"] = "Lightning"
dmgTypeNames["base cold damage"] = "Cold"
dmgTypeNames["base fire damage"] = "Fire"
dmgTypeNames["base void damage"] = "Void"
dmgTypeNames["base poison damage"] = "Poison"

local function parseArrowConversion(line)
	local ll = line:lower()
	local pctStr, srcText, dstText
	pctStr, srcText, dstText = ll:match("^%s*%+?(%d+%.?%d*)%%%s+(.-)%s*%->%s*(.-)%s*$")
	if not pctStr then
		srcText, dstText = ll:match("^%s*(.-)%s*%->%s*(.-)%s*$")
		pctStr = "100"
	end
	if not srcText or not dstText then return nil end
	local srcType = dmgTypeNames[srcText]
	local dstType = dmgTypeNames[dstText]
	if srcType and dstType and srcType ~= dstType then
		return { mod(srcType .. "DamageConvertTo" .. dstType, "BASE", tonumber(pctStr)) }
	end
	-- @leb-regression-guard:apocrypha-incregen-to-armour (parse site)
	-- Cross-stat increased-conversion: "N% Increased <StatA> -> Increased <StatB>"
	-- (PoB's "X% of increased Y also applies to Z"). Warlock passive
	-- Apocrypha (Acolyte-58) carries "50% Increased Mana Regen -> Increased Armor"
	-- as a notScalingStat. Before this branch parseArrowConversion only handled
	-- damage-type conversions and returned nil, so parseMod dropped the whole
	-- line as `extra` residue (0 mods emitted).
	-- BOTH sides MUST carry the "increased" qualifier so we only match the
	-- INC-aggregate form — a flat/base "->" or a damage-type conversion (handled
	-- above) never falls in here. We reuse modNameList (the canonical display
	-- name -> modName table) rather than a bespoke denylist, and accept only
	-- single-stat (string) mappings so multi-stat keys like "all resistances"
	-- can't silently produce a malformed conversion.
	-- Consumed in CalcDefence.lua (Armour INC) via modDB:List("IncreasedStatConversion").
	-- Spec: spec/System/TestApocryphaIncRegenToArmour_spec.lua
	-- See REGRESSION_GUARDS.md "apocrypha-incregen-to-armour".
	local srcStatText = srcText:match("^increased%s+(.+)$")
	local dstStatText = dstText:match("^increased%s+(.+)$")
	if srcStatText and dstStatText then
		local srcName = modNameList[srcStatText]
		local dstName = modNameList[dstStatText]
		if type(srcName) == "string" and type(dstName) == "string" then
			return { mod("IncreasedStatConversion", "LIST", { src = srcName, dst = dstName, fraction = tonumber(pctStr) }) }
		end
	end
	-- @leb-regression-guard:pierce-chance-to-crit-multiplier
	-- Shurikens tree node "Ricochet" (srk21-19) notScalingStat
	-- " Pierce Chance -> Critical Multiplier"; game description: "Pierce
	-- chance is converted to additional critical strike multiplier." The
	-- node mod is skill-scoped by the tree loader (SkillId=Shurikens), so
	-- the flag only fires for Shurikens. Consumption: CalcOffence adds
	-- Sum(BASE, cfg, "PierceChance") into the crit-multiplier extra when
	-- the flag is set. Kept as an EXACT pair on purpose -- no generic
	-- flat-stat "X -> Y" conversion exists in LE game data, and a greedy
	-- rule here is how the #3-B "Additional <skill> Chance" misparse
	-- happened. Spec: spec/System/TestPierceChanceToCritMultiplier_spec.lua
	if srcText == "pierce chance" and dstText == "critical multiplier" then
		return { flag("PierceChanceConvertsToCritMultiplier") }
	end
	-- @leb-regression-guard:falcon-avian-arsenal-buff
	-- Validation provenance is retained in maintainer notes.
	if srcText == "character damage" and dstText == "falcon damage" then
		return { mod("FalconAvianArsenalPercent", "BASE", tonumber(pctStr), "", 0, 0, { type = "Multiplier", var = "FalconAvianArsenalStacks" }) }
	end
	return nil
end

local explodeFunc = function(chance, amount, type, ...)
	local amountNumber = tonumber(amount) or (amount == "tenth" and 10) or (amount == "quarter" and 25)
	if not amountNumber then
		return
	end
	local amounts = {}
	amounts[type] = amountNumber
	return {
		mod("ExplodeMod", "LIST", { type = firstToUpper(type), chance = chance / 100, amount = amountNumber, keyOfScaledMod = "chance" }, ...),
		flag("CanExplode")
	}
end

-- List of special modifiers
local specialQuickFixModList = {
	-- "Added" after a number is LE terminology for flat/base; strip it so parsers don't choke on it
	["^([%+%-]?[%d%.]+%%?) Added "] = "%1 ",
	-- "X% Global Increased/More/Reduced/Less Y" — reorder so the form-detection regex (which
	-- requires "increased"/"more"/etc. directly after "%") still classifies the form correctly.
	-- The "global" word is preserved later via modFlagList scanning, which adds the Global tag.
	["^([%+%-]?[%d%.]+%%) Global Increased"] = "%1 increased Global",
	["^([%+%-]?[%d%.]+%%) Global More"] = "%1 more Global",
	["^([%+%-]?[%d%.]+%%) Global Reduced"] = "%1 reduced Global",
	["^([%+%-]?[%d%.]+%%) Global Less"] = "%1 less Global",
	-- "Physical Leech" is LE shorthand for "Physical Damage Leeched as Health".
	-- Lua patterns don't support optional groups, so we list both shapes.
	["^([%+%-]?[%d%.]+%%) Global Physical Leech"] = "%1 Global Physical Damage Leeched as Health",
	["^([%+%-]?[%d%.]+%%) Physical Leech"] = "%1 Physical Damage Leeched as Health",
	["^([%+%-]?[%d%.]+%%) Cast Speed"] = "%1 increased Cast Speed",
	["^([%+%-]?[%d%.]+%%) Cooldown Recovery Speed"] = "%1 increased Cooldown Recovery Speed",
	["^([%+%-]?[%d%.]+%%) Duration"] = "%1 increased Duration",
	["^([%+%-]?[%d%.]+%%) Movespeed"] = "%1 increased Movespeed",
	-- @leb-regression-guard:minion-movespeed-passive-node-phrasings
	-- LE 1.4 passive-tree nodes use multiple inconsistent phrasings for
	-- "% Minion Movement Speed":
	--   * Primalist-22 "The Chase"        (tree_0): "+4% Minion Movespeed"
	--     -- no "Increased", 1-word Movespeed
	--   * Acolyte-20 "Invigorated Dead"   (tree_3): "2% Minion Increased Movement Speed"
	--     -- word-swap: "Minion" before "Increased"
	-- The pre-existing "^...%%) Movespeed" rule does not match when "Minion" sits
	-- between the percentage and "Movespeed", so these node texts parsed as either
	-- BASE (instead of INC) or dropped entirely. Triangulated on:
	--   <private build> lv98 Beastmaster   (LETools 24% / LEB 0 -> after fix: 24)
	--   <private build> lv100 Beastmaster  (LETools 32% / LEB 0 -> after fix: 32)
	--   <private build> lv100 Necromancer  (LETools 27% / LEB 0): NOT FIXED here -- its
	--     Necromancer minion-movespeed feed is a separate skill-tree
	--     SkillStatMap("minion_movement_speed_+%") routing bug, not text parsing.
	-- Spec: spec/System/TestMinionMovespeedNodeText_spec.lua.
	-- See REGRESSION_GUARDS.md "minion-movespeed-passive-node-phrasings".
	["^([%+%-]?[%d%.]+%%) Minion Movespeed"] = "%1 increased Minion Movespeed",
	-- Word-swap variant: "X% Minion Increased Movement Speed" (Acolyte-20 Invigorated Dead).
	-- Narrowly targeted to Movement Speed only — other "X% Minion Increased Y" phrasings
	-- (cast speed, healing effectiveness, etc.) also exist and have the same cache-residue
	-- bug, but fixing those changes more snapshots than this PR's scope warrants. See the
	-- regression-guard note for the follow-up TODO.
	["^([%+%-]?[%d%.]+%%) Minion Increased Movement Speed"] = "%1 Increased Minion Movement Speed",
	["^([%+%-]?[%d%.]+%%) Mana Cost"] = "%1 increased Mana Cost",
	["^([%+%-]?[%d%.]+%%) Mana Efficiency"] = "%1 increased Mana Efficiency",
	["%(up to %d+%)%s*$"] = "",
	-- @leb-regression-guard:additional-flavor-strip
	-- LE phrases certain conditional regen as "+N Additional <Stat> with M <Attr>"
	-- (e.g. Mage-91 "Transcendence" rank 6: "+24 Additional Ward per Second with
	-- 60 Intelligence"). "Additional" is flavor text only — strip it so the regular
	-- mod-name parser matches "Ward per Second" cleanly. Combined with the
	-- "with N <Attr>" StatThreshold tag this yields BASE 24 WardPerSecond gated
	-- by StatThreshold Int >= 60.
	["^([%+%-]?[%d%.]+) Additional "] = "%1 ",
	-- Normalize "X% [Type] Damage Taken" (without increased/reduced keyword) to INC type
	["^([%+%-]?[%d%.]+%%) Damage Over Time Taken"] = "%1 increased Damage Over Time Taken",
	["^([%+%-]?[%d%.]+%%) Damage Taken"] = "%1 increased Damage Taken",
	["^([%+%-]?[%d%.]+%%) Elemental Damage Taken"] = "%1 increased Elemental Damage Taken",
	["^([%+%-]?[%d%.]+%%) Cold Damage Taken"] = "%1 increased Cold Damage Taken",
	["^([%+%-]?[%d%.]+%%) Fire Damage Taken"] = "%1 increased Fire Damage Taken",
	["^([%+%-]?[%d%.]+%%) Lightning Damage Taken"] = "%1 increased Lightning Damage Taken",
	["^([%+%-]?[%d%.]+%%) Physical Damage Taken"] = "%1 increased Physical Damage Taken",
	["^([%+%-]?[%d%.]+%%) Void Damage Taken"] = "%1 increased Void Damage Taken",
	["^([%+%-]?[%d%.]+%%) Necrotic Damage Taken"] = "%1 increased Necrotic Damage Taken",
	["^([%+%-]?[%d%.]+%%) Poison Damage Taken"] = "%1 increased Poison Damage Taken",
}

for _, damageType in ipairs(DamageTypes) do
	specialQuickFixModList[damageType .. " Shred Chance"] = "Shred " .. damageType .. " Resistance Chance"
end

-- Build a mod list tagged as "recognised but not yet implemented in LEB".
-- Item.lua propagates this flag to modLine.notSupported; formatModLine appends a
-- "(NOT SUPPORTED IN LEB YET)" annotation so the line is neither red nor silently
-- producing a ghost mod.
local function nsList(...)
	local list = { ... }
	list.notSupported = true
	return list
end

-- Lowercased skill name -> canonical name (used by idol-affix specialModList patterns)
-- skillIdByLower: lowercased skill name -> data.skills KEY (skillId). Used by the
-- trigger bridge to emit the functional ChanceToTriggerOnHit_<skillId> mod that
-- the CalcSetup grantedTriggeredSkills loop + CalcTriggers framework consume.
-- @leb-regression-guard:trigger-chance-to-cast-bridge (name->id map site)
-- @leb-regression-guard:skillidbylower-prefer-player
-- data.skills contains duplicate skill NAMES: the same display name is shared by
-- a player skill and one or more minion/enemy/ailment homonyms (e.g. "Lightning
-- Blast" = player LightningBlast AND minion StormCrowLightningBlast; "Surge" =
-- player Surge AND RogueFalcon Diving Attack; Bone Curse / Spirit Plague / Arcane
-- Ascendance each vs an Ailment_* variant). A naive pairs() build collapses each
-- name to ONE id whose identity depends on pairs() iteration order — i.e. it is
-- NON-DETERMINISTIC across processes. Every trigger bridge resolving a skill by
-- name (on-hit/on-melee/on-spell-cast, the cooldown globalCapped bridge, and the
-- qualified on-crit rate-cap bridge) then risks injecting the MINION's skill into
-- Full DPS instead of the player's — a real in-game-accuracy bug.
--
-- Fix: iterate keys in a STABLE (sorted) order and, on a name collision, prefer
-- the id that owns a player skill tree. data.skills[id].treeId is set ONLY for
-- player-usable skills; every minion/enemy/ailment homonym verified in
-- src/Data/skills.json has treeId == nil, so it is a data-driven signal (not a
-- name-prefix denylist). Within a collision the higher-ranked (treeId present) id
-- wins; on equal rank the sorted-first id wins, which is identical across
-- processes. The only multi-treeId collision ("Runebolt" = three same-treeId
-- color variants) has no distinct player winner, so sorted tie-break is correct.
local skillNameByLower = {}
local skillIdByLower = {}
do
	local sortedIds = {}
	for skillId in pairs(data.skills) do
		sortedIds[#sortedIds + 1] = skillId
	end
	table.sort(sortedIds)
	-- Higher rank == more player-like. treeId (player skill tree) is the signal.
	local function playerRank(skill)
		return skill.treeId and 1 or 0
	end
	local rankByLower = {}
	for _, skillId in ipairs(sortedIds) do
		local skill = data.skills[skillId]
		if skill.name then
			local lower = skill.name:lower()
			local rank = playerRank(skill)
			if rankByLower[lower] == nil or rank > rankByLower[lower] then
				skillNameByLower[lower] = skill.name
				skillIdByLower[lower] = skillId
				rankByLower[lower] = rank
			end
		end
	end
end

-- @leb-regression-guard:conscrated-ground-typo-alias
-- LE game data misspells "Consecrated Ground" as "Conscrated Ground" (missing the
-- 2nd 'e') in two Judgement tree stats ("+30% Conscrated Ground Damage Against
-- Ignited Enemies", "+20% Conscrated Ground Damage Against High Health"). The
-- per-skill scoping loops below key off the real skill name, so the misspelled
-- phrase fails to scope and the MORE is dropped from the granted Consecrated Ground
-- sub-skill. Alias the typo to the canonical skill so both stats scope to CG.
if skillNameByLower["consecrated ground"] then
	skillNameByLower["conscrated ground"] = skillNameByLower["consecrated ground"]
	skillIdByLower["conscrated ground"] = skillIdByLower["consecrated ground"]
end

-- Normalize a captured skill phrase and return canonical skill name or nil
local function canonicalSkillName(phrase)
	if not phrase then return nil end
	phrase = phrase:match("^%s*(.-)%s*$")
	return skillNameByLower[phrase:lower()]
end

-- @leb-regression-guard:skill-name-arrow-conversion (parse site)
-- (@leb-regression-guard:conversion-extra-nil-not-empty) but skill-scoped.
-- Validation provenance is retained in maintainer notes.
local function parseSkillNameArrowConversion(line)
	local ll = line:lower()
	local pctStr, srcText, dstText = ll:match("^%s*%+?(%d+%.?%d*)%%%s+(.-)%s*%->%s*(.-)%s*$")
	if not pctStr then
		srcText, dstText = ll:match("^%s*(.-)%s*%->%s*(.-)%s*$")
		pctStr = "100"
	end
	if not srcText or not dstText then return nil end
	local canonical = canonicalSkillName(srcText)
	local dstType = dmgTypeNames[dstText]
	-- Both halves must resolve: a known skill name on the left, a damage type on
	-- the right. Non-skill arrows ("Ward -> Health") and skill->skill arrows
	-- ("Volcanic Orb -> Frozen Orb", dst is not a damage type) correctly fall
	-- through to nil so the existing drop path is unchanged.
	if not canonical or not dstType then return nil end
	local convMods = { }
	for _, srcType in ipairs(DamageTypes) do
		if srcType ~= dstType then
			t_insert(convMods, mod(srcType .. "DamageConvertTo" .. dstType, "BASE", tonumber(pctStr), "", 0, 0,
				{ type = "SkillName", skillName = canonical }))
		end
	end
	return convMods
end

-- @leb-regression-guard:recast-parse
-- LE skill-tree recast nodes expose their recast as plain English `stats`
-- strings (Shatter Strike Whiteout "1 Recasts", Iceblink "+6% Chance for Two
-- Recasts with Two Handed Weapon", Chaos Bolts "10% Chance to recast", ...).
-- ModParser had NO recast rule, so every form fell through the generic chain to
-- an empty mod list and got baked into ModCache.lua as `{{}, "...residue..."}` —
-- the recast never reached the existing RepeatCount/output.Repeats mechanism
-- (CalcOffence.lua:783 `output.Repeats = 1 + Sum("BASE", skillCfg, "RepeatCount")`).
-- These handlers route the clean "repeat the whole cast" forms to a RepeatCount
-- BASE mod. Tree-node mods are SkillId-scoped by PassiveTree.lua (it appends a
-- {SkillId} tag), so the repeat applies only to the owning skill; the
-- probabilistic / weapon-conditional variants fold the average extra-cast count
-- into the BASE value and gate on the weapon Condition. Recast is a
-- cast-rate / hit-rate effect (output.Repeats), NOT a per-hit magnitude
-- multiplier — per-hit damage is unchanged.
-- Out of scope (divergent semantics, deliberately left as empty no-op parses):
-- on-kill auto-recast (Rip Blood " Automatically Recasts On Kill"),
-- spread-on-recast combo (Spirit Plague " Spread On Recast"), per-resource
-- recast chance (Divine Flare "Recast Chance per Symbol Consumed") and the
-- skill-named "<Skill> Recast Chance" expire/cast re-triggers (Black Hole,
-- Thorn Shield). Spec: spec/System/TestRecastParseGap_spec.lua.
-- See REGRESSION_GUARDS.md "recast-parse".
local recastCountWords = { ["one"] = 1, ["two"] = 2, ["three"] = 3, ["four"] = 4 }
local specialModList = {
	["no cooldown"] = { flag("NoCooldown") },
	["no melee attack"] = { flag("NoMeleeAttack") }, -- Shadow Cascade Porcupine's Wrath (dagg3-24): suppresses the melee hit (consumed in CalcOffence)
	-- @leb-regression-guard:hammer-throw-spiral-multihit (parser site)
	-- Hammer Throw skill-tree bare-flag stats (tree_2.json ht16aw-20 Iron Spiral):
	-- " Hammers Spiral" makes the thrown hammers travel in a spiral that CAN re-hit
	-- the same target, and " Half Extra Projectiles" halves the additional-hammer
	-- count. Both were previously UNPARSED (node.extra) so LEB never modelled the
	-- spiral same-target multi-hit. Capture into flags consumed in CalcOffence.
	-- See REGRESSION_GUARDS.md "hammer-throw-spiral-multihit".
	["hammers spiral"] = { flag("HammersSpiral") },
	["half extra projectiles"] = { flag("HalveExtraProjectiles") },
	-- @leb-regression-guard:void-knight-echo-more (parser site)
	-- Void Knight mastery ("Void Knight" isAscendancyStart node, tree_2.json) 2nd bonus:
	-- "Your melee attacks, throwing attacks and void spells have a 10% chance to be
	-- repeated by an echo 0.5s later (excludes movement abilities and Anomaly)." The echo
	-- is a full re-cast dealing full damage with no chaining (datamining:
	-- CreateVoidKnightEchoAfterDelay / Property_Player_81 no-chain / Property_Player_57
	-- "increased Echo Damage" default 0), so a P% repeat chance = +P% average damage.
	-- Capture P into a VoidKnightEchoChance BASE player mod; CalcActiveSkill turns it into
	-- a Damage MORE on eligible skills (melee/throwing attacks + void spells, MINUS movement
	-- skills and Anomaly -- the any-of/exclusion set can't live on one keyword-tagged mod).
	-- Whole-line ^...$ so parseMod leaves no `extra` residue (else PassiveTree:ProcessStats
	-- drops the mod -- the <see git log> trailing-period trap). The bare-flag echo line was
	-- previously UNPARSED (node.extra) -> the bonus was entirely unmodelled.
	-- Spec: spec/System/TestVoidKnightEcho_spec.lua. See REGRESSION_GUARDS.md.
	["^your melee attacks, throwing attacks and void spells have a ([%d%.]+)%% chance to be repeated by an echo.-$"] = function(num) return { mod("VoidKnightEchoChance", "BASE", num) } end,
	-- @leb-regression-guard:aspect-effect-buff-scalar
	-- Beastmaster "(N)% Increased Aspect of the {Lynx,Shark,Viper,Boar} Effect" affixes
	-- (ModItem_1_4.json verbatim: "(10-25)% Increased Aspect of the Lynx Effect",
	-- "(6-20)% Increased Aspect of the Shark Effect",
	-- "(10-25)% Increased Aspect of the Viper Effect",
	-- "(5-12)% Increased Aspect of the Boar Effect"). These were SILENT FAILURES:
	-- ModCache baked {{}," Effect "} with an empty modList because the skillNameList
	-- post-scan strips "Aspect of the Lynx/Shark/Viper" as a skill name, leaving a
	-- bare "Effect" residue that never reaches a modName. The buff-effect scalar is
	-- a per-buff INCREASE stat named buff.name:gsub(" ","").."Effect", read by
	-- CalcPerform buff scaling (CalcPerform.lua ~L733 / ~L751:
	--   skillModList:Sum("INC", skillCfg, buff.name:gsub(" ","").."Effect")), exactly
	-- like the working "frenzy effect"->"FrenzyEffect" modName alias. The four buffs
	-- are named "Aspect of the {Lynx,Shark,Viper,Boar}" (TreeData/1_4/tree_0.json), so
	-- the engine stats are "AspectoftheLynxEffect" / "AspectoftheSharkEffect" /
	-- "AspectoftheViperEffect" / "AspectoftheBoarEffect" -- grounded in the engine's own
	-- gsub, not fabricated. Whole-line handlers (residue-free) so PassiveTree:ProcessStats
	-- never drops them. Spec: TestAspectEffect_spec.lua.
	["^%+?([%d%.]+)%%? increased aspect of the lynx effect$"] = function(num)
		return { mod("AspectoftheLynxEffect", "INC", tonumber(num)) }
	end,
	["^%+?([%d%.]+)%%? increased aspect of the shark effect$"] = function(num)
		return { mod("AspectoftheSharkEffect", "INC", tonumber(num)) }
	end,
	["^%+?([%d%.]+)%%? increased aspect of the viper effect$"] = function(num)
		return { mod("AspectoftheViperEffect", "INC", tonumber(num)) }
	end,
	["^%+?([%d%.]+)%%? increased aspect of the boar effect$"] = function(num)
		return { mod("AspectoftheBoarEffect", "INC", tonumber(num)) }
	end,
	-- @leb-regression-guard:aspect-effect-bare-alias
	-- ALIAS (bare, no "increased" word): LE also renders these Beastmaster aspect-effect
	-- rolls WITHOUT the "increased" word and WITH a signed prefix, e.g.
	-- "+80% Aspect Of The Shark Effect" / "+10% Aspect Of The Shark Effect". Those were
	-- SILENT FAILURES (ModCache baked {{},"  Effect "}: the "Aspect of the <Beast>" skill
	-- name is stripped by the skillNameList post-scan, leaving a bare " Effect " residue
	-- that never reaches a modName). Same stat, same INC semantics, same consumer as the
	-- "increased" handlers above (buff.name:gsub(" ","").."Effect"). Sign is captured
	-- ([%+%-]?...) so a reduced roll models as a negative INC rather than being dropped or
	-- sign-flipped. "%% aspect" cannot match the "%% increased aspect" or "%% less aspect"
	-- strings (a word intervenes before " aspect"), so no collision. Whole-line ^...$ so
	-- parseMod leaves no `extra` residue. Spec: TestAspectEffect_spec.lua.
	["^([%+%-]?[%d%.]+)%%? aspect of the lynx effect$"] = function(num)
		return { mod("AspectoftheLynxEffect", "INC", tonumber(num)) }
	end,
	["^([%+%-]?[%d%.]+)%%? aspect of the shark effect$"] = function(num)
		return { mod("AspectoftheSharkEffect", "INC", tonumber(num)) }
	end,
	["^([%+%-]?[%d%.]+)%%? aspect of the viper effect$"] = function(num)
		return { mod("AspectoftheViperEffect", "INC", tonumber(num)) }
	end,
	["^([%+%-]?[%d%.]+)%%? aspect of the boar effect$"] = function(num)
		return { mod("AspectoftheBoarEffect", "INC", tonumber(num)) }
	end,
	-- @leb-regression-guard:increased-healing-effectiveness-alias
	-- Skill-tree nodes whose display stat is the bare "(N)% Increased Healing"
	-- (NO "Effectiveness" word) were SILENT FAILURES: ModCache baked {{},"  "}
	-- with an empty modList. The generic "increased X" path strips "increased"
	-- and looks up the remainder "healing" in the modName map, which has an entry
	-- only for "healing effectiveness" (-> "HealingEffectiveness", L409), so the
	-- shortened node text resolves to no modName and drops. These are REAL nodes,
	-- and each node's OWN description proves the semantics are identical to
	-- Healing Effectiveness (src/TreeData/1_4/tree_0.json + tree_2.json, verbatim):
	--   Blossoming Garden  "10% Increased Healing"  -> "Increases healing effectiveness for you and your minions."
	--   Blessed Springs    "7% Increased Healing"   -> "Increases cold damage and healing effectiveness ..."
	--   Improved Blessing  "+20% Increased Healing" -> "Eterra's Blessing has increased healing effectiveness."
	--   Violent Squall     "+200% Increased Healing"-> "Maelstrom ... has significantly increased healing effectiveness ..."
	--   Redemption         "+10% Increased Healing"  (tree_2, Paladin)
	--   Virtue of Patience "24% Increased Healing"   (tree_2, Paladin)
	-- so the shortened node text is the SAME modeled stat as the working
	-- "(N)% Increased Healing Effectiveness" affix (ModCache proves that form parses
	-- to HealingEffectiveness INC; consumed at CalcDefence.lua L1845
	-- output.HealingEffectiveness = modDB:Sum("INC", nil, "HealingEffectiveness")).
	-- Whole-line ^...$ so parseMod leaves no `extra` residue (PassiveTree:ProcessStats
	-- never drops it). Scoped to end with "healing$": it will NOT match the
	-- "increased healing effectiveness" affix (trailing word) NOR the minion variant
	-- "increased minion healing" (different text) -- so no collision with minion code.
	-- Spec: spec/System/TestIncreasedHealingAlias_spec.lua. See REGRESSION_GUARDS.md.
	["^%+?([%d%.]+)%%? increased healing$"] = function(num)
		return { mod("HealingEffectiveness", "INC", tonumber(num)) }
	end,
	-- @leb-regression-guard:lightning-blast-chain-rehit
	-- Lightning Blast specialization chain/cast nodes. These were ModCache
	-- silent-failure NO-OPs ({{},"..."}); LEB models LB as a spell (no
	-- projectile, so skillFlags.chaining is never set and the generic
	-- ChainCountMax machinery is bypassed), so the consumer is a node-gated
	-- custom hit multiplier in CalcOffence (output.HitSpeed), NOT the generic
	-- chain path. Mechanism is from a clean datamined game source of
	-- LightningBlastMutator (datamined game source on the game binary):
	--   numberOfChains = chains(0x148) + min(maxChainsForRecent(0x11C)+2,
	--     recentDirectCasts(0x120)) + (staticOrb ? 2 : 0); if halfChains: Ceil(*0.5).
	--   "Convergence" (lb23il-18) sets chainsBackOnItself+halfChains so chains
	--   re-hit the SAME target. Re-hits fire 0.25s apart
	--   (mutateDelayedCastDuration = previousDelayedCasts * 0.25f).
	-- The "Maximum Additional Chains" text covers BOTH the recent-cast cap
	-- (Arcing Power, no "+") and the flat chains (Chain Lightning, "+"); at
	-- steady-state recent-cast ramp they sum, so a single accumulator is faithful.
	-- See wiki concepts/lightning-blast-chain-rehit-convergence + memory
	-- project_runemaster_subskills_structurally_unmodeled.
	["lightning blast chains only to first target hit"] = { flag("LightningBlastChainsBackOnItself") },
	["half maximum chains"] = { flag("LightningBlastHalfChains") },
	["^%+?([%d%.]+) maximum additional chains$"] = function(num) return { mod("MaxAdditionalChains", "BASE", num) } end,
	-- @leb-regression-guard:elemental-arrows-resource (bare-number resource caps)
	-- Rogue-24 notScalingStats "3 Maximum Elemental Arrows" / "1 Elemental Arrows Per Second"
	-- carry NO leading "+", so the modNameList "Maximum X" path does not fire (it needs "+N").
	-- Match the bare form here (%+? = optional +) -> BASE resource-config mods consumed by
	-- CalcPerform's Elemental Arrows consumed-count computation.
	["^%+?([%d%.]+) maximum elemental arrows$"] = function(num) return { mod("ElementalArrowMax", "BASE", num) } end,
	["^%+?([%d%.]+) elemental arrows? per second$"] = function(num) return { mod("ElementalArrowGenRate", "BASE", num) } end,
	-- Rogue-24 "+N Fire/Lightning Damage with Elemental Arrow" = ADDED PER consumed arrow
	-- (game Property_113). Matched here (before the modTagList "with elemental arrow" Condition)
	-- so ONLY the added scales by Multiplier:ElementalArrowConsumed; the increased "with
	-- elemental arrow" (Rogue-35) stays a x1 Condition. Property_113 is fire+lightning only.
	["^%+?([%d%.]+) fire damage with elemental arrow$"] = function(num) return { mod("FireDamage", "BASE", num, { type = "Multiplier", var = "ElementalArrowConsumed" }) } end,
	["^%+?([%d%.]+) lightning damage with elemental arrow$"] = function(num) return { mod("LightningDamage", "BASE", num, { type = "Multiplier", var = "ElementalArrowConsumed" }) } end,
	["^%+?([%d%.]+)%% doublecast chance$"] = function(num) return { mod("DoublecastChance", "BASE", num) } end,
	["^%+?([%d%.]+)%% quadruple cast chance$"] = function(num) return { mod("QuadrupleCastChance", "BASE", num) } end,
	-- @leb-regression-guard:additional-skill-chance-not-trigger
	-- "<N>% Additional <skill> Chance" is a PROJECTILE-QUANTITY affix -- a chance to throw
	-- +N extra projectiles -- NOT a "chance to cast <skill>" trigger. The only intercepted
	-- (skill-named) entry in current game data is the Shurikens tree node "Flip of a Coin":
	-- "50% Additional Shurikens Chance" ("25% Additional Storm Stack Chance", tree_0
	-- ga2st-20 "Island Cleaver", also matches the pattern but declines below -- Storm Stack
	-- is a buff, not a skill). Without this guard the "N% additional" BASE form in formList
	-- consumes "additional", then the generic "<skill> chance" -> ChanceToTriggerOnHit rule
	-- misreads the remainder as a 50%-chance full-skill SELF-recast: StarSeaVnV over-modeled
	-- a "Shurikens (from Shurikens)" copy worth ~39k that does NOT exist in-game. The
	-- in-game gap (142,136 hit vs LEB 121,470) is unmodeled additional-projectile damage --
	-- a -7% per-hit gap plus a -8% single-target spread-landing gap (base projectile count
	-- is datamine-blocked) -- not a trigger. specialModList is scanned first (the
	-- scan(line, specialModList) call at the top of parseMod), so this intercepts before
	-- both the form and the trigger rule. Return {} (no mod, the same unmodeled outcome as
	-- the typo'd "+N Additonal <skill>" entries) ONLY when the middle capture names a real
	-- non-minion, non-ailment skill; otherwise return nil to decline so generic
	-- "additional X chance" affixes still parse and real "<skill> Chance" triggers (which
	-- have no "additional") are untouched. Ailment_* skills (and their altNames -- all 21
	-- altNames in data.skills belong to ailments, e.g. "Bleeding"/"Armor Shred") are
	-- deliberately NOT intercepted: a hypothetical "additional <ailment> chance" string is
	-- plausibly a legitimate additive ailment-chance stat whose correct representation IS
	-- ChanceToTriggerOnHit_Ailment_* via the generic chain -- decide deliberately if such a
	-- string ever ships. See REGRESSION_GUARDS.md.
	["^%+?([%d%.]+)%%? additional (.+) chance$"] = function(num, _, skillNameLower)
		if skillNameLower then
			for skillId, skill in pairs(data.skills) do
				if not skill.fromMinion and not skillId:find("Stacking") and not skillId:find("Ailment_", 1, true)
						and skill.name and skill.name:lower() == skillNameLower then
					return { }
				end
			end
		end
		return nil
	end,
	-- "<N> Recasts": the skill recasts after it finishes (e.g. Shatter Strike
	-- Whiteout). PassiveTree per-point scaling multiplies the leading number, so
	-- "1 Recasts" -> "2 Recasts" at 2 points; match any N.
	["^(%d+) recasts?$"] = function(num)
		return { mod("RepeatCount", "BASE", num) }
	end,
	-- @leb-regression-guard:avalanche-large-boulder-double-damage
	-- Avalanche specialization node av75ch-15 "Intensity" stat "5% Large Boulder
	-- Chance" (maxPoints 4 -> 20% at 4/4). In-game a fraction of Avalanche boulders
	-- spawn as "large boulders" that deal AvalancheSnowballMutator.BIG_BOULDER_MORE_DAMAGE
	-- = 1 (datamined game source) -> +1.0 MORE = exactly x2.0 = DOUBLE damage. The SuXes per-hit
	-- ladder isolated the large cluster at x2.0000 exact, observed at ~18% (the 20% node
	-- within finite-sample error). A p-chance to deal double damage is precisely LEB's
	-- existing DoubleDamageChance mechanic: CalcOffence ScaledDamageEffect *= (1 + p), the
	-- expected-value MORE (1 + p*(2-1)) the small:large boulder mix produces (20% -> x1.20).
	-- Before this entry the stat was a ModCache no-op ({{}," Large Boulder Chance "}), so
	-- the whole large-boulder contribution was dropped.
	--
	-- ModFlag.Hit: BIG_BOULDER_MORE_DAMAGE multiplies the boulder HIT only. LE ailments
	-- are stack-based with fixed per-stack damage -- they do NOT scale with the applying
	-- hit's size -- so a large boulder must NOT double the Frostbite/Chill/Shock it
	-- inflicts. A flagless DoubleDamageChance would (it propagates to Avalanche's triggered
	-- ailments via the SkillId groupSource channel and CalcOffence applies ScaledDamageEffect
	-- to the ailment DoT), which is a PoE-ism (PoE ailments scale with the hit; LE's do not).
	-- The Hit flag confines the x1.20 to the boulder hit: verified on BOwJRDdE lv74 Shaman
	-- (av75ch-15 #4) -- only slot5_Avalanche hit metrics move x1.20, the Frostbite-from-
	-- Avalanche DoT DPS is byte-unchanged.
	--
	-- The "5% Large Boulder Chance" form parses per-point (BASE 5); PassiveTree multiplies
	-- by allocated points (x4 -> 20). Anchored ^...$ so the sibling Avalanche tree stats
	-- "50% Large Boulder Chance To Leave Frozen Ground" (chill ground, not damage) and
	-- "50% Upheaval Chance From Large Boulder" do NOT match (trailing text fails $).
	-- "Large Boulder Chance" exists only on the Avalanche tree (tree_0.json 1_2/1_3/1_4;
	-- no affix/unique/idol/set), and skill-tree node mods are SkillId-scoped by
	-- PassiveTree.lua (ModStore SkillId gate), so the DoubleDamageChance reaches Avalanche
	-- only -- no leak to other skills. Avalanche bug B only; A (Grounding, landed dev
	-- <see git log>), C (adaptive flat typing), D (boulder no-crit) are tracked separately.
	-- Spec: spec/System/TestAvalancheLargeBoulder_spec.lua
	["^([%d%.]+)%% large boulder chance$"] = function(num)
		return { mod("DoubleDamageChance", "BASE", num, "", ModFlag.Hit) }
	end,
	-- @leb-regression-guard:ice-spiral-double-chance-ev
	-- Frost Claw specialization node frc87w-21 "Chaos Whirl" (maxPoints 4) carries the
	-- scaling stat "25% Chance for Double Ice Spirals" (stats[]) plus the non-scaling
	-- descriptor "+100% Ice Spiral Damage when Doubled" (notScalingStats[]). Node text:
	-- "When you cast Ice Spirals there is a chance that the number of projectiles will be
	-- doubled and they'll all deal double damage" (game-source, tree_1.json 1_2/1_3/1_4).
	-- The doubled magnitude is +100% = exactly x2.0 = DOUBLE damage; the game's own
	-- IceSpiralMutator.getTempStatsForTooltipDPS folds extra = chance, i.e. EV MORE =
	-- (1 + chance*(2-1)). This is precisely LEB's DoubleDamageChance mechanic: CalcOffence
	-- ScaledDamageEffect *= (1 + DoubleDamageChance/100).
	--
	-- Before this entry the node pair OVER-counted: "+100% Ice Spiral Damage when Doubled"
	-- was a ModCache Damage MORE 100 applied UNCONDITIONALLY (always x2.0, never gated on the
	-- roll) while "25% Chance for Double Ice Spirals" was a ModCache no-op (dropped). The fix
	-- removes the unconditional MORE (ModCache row -> empty no-op) and re-expresses the
	-- magnitude as a chance: 25% per point -> BASE DoubleDamageChance; PassiveTree multiplies
	-- by allocated points (4/4 -> 100 = guaranteed double = x2.0, matching the old number ONLY
	-- at full points -- partial allocations were the over-count).
	--
	-- ModFlag.Hit: the roll doubles the Ice Spiral / Frost Claw HIT only. LE ailments are
	-- stack-based with fixed per-stack damage -- they do NOT scale with the applying hit's
	-- size -- so a doubled hit must NOT double the Frostbite/Chill it inflicts (mirrors the
	-- avalanche-large-boulder rationale; a flagless mod would leak into the ailment DoT).
	--
	-- Anchored ^...$ + value-tolerant ([%d%.]+): "Chance for Double Ice Spirals" exists ONLY
	-- on the Frost Claw tree (tree_1.json frc87w-21, all of 1_2/1_3/1_4; no affix/unique/idol/
	-- set), and skill-tree node mods are SkillId-scoped by PassiveTree.lua (ModStore SkillId
	-- gate), so the DoubleDamageChance reaches Frost Claw only -- no leak to other skills.
	-- The successful roll ALSO doubles the projectile COUNT (Mutate iVar7=iVar2*2); the game
	-- tooltip ignores count-doubling (getTempStatsForTooltipDPS reads field 0x104 directly),
	-- so this per-hit EV MORE matches the tooltip and is the faithful minimal fix -- modeling
	-- the EV count increase is a separate game-source follow-up.
	-- Spec: spec/System/TestIceSpiralDoubleChance_spec.lua
	["^([%d%.]+)%% chance for double ice spirals$"] = function(num)
		return { mod("DoubleDamageChance", "BASE", num, "", ModFlag.Hit) }
	end,
	-- "+X% Chance for <count> Recasts with <One/Two> Handed Weapon": probabilistic
	-- recast gated on the equipped weapon type (Shatter Strike Iceblink). Average
	-- extra casts = X/100 * count, gated on UsingOneHandedWeapon/UsingTwoHandedWeapon.
	["^%+?(%d+)%% chance for (%a+) recasts? with (%a+) handed weapon$"] = function(num, _, countWord, handWord)
		local count = recastCountWords[countWord]
		if not count then return nil end
		local condVar = (handWord == "two") and "UsingTwoHandedWeapon" or "UsingOneHandedWeapon"
		return { mod("RepeatCount", "BASE", num * count / 100, { type = "Condition", var = condVar }) }
	end,
	-- "+X% Chance for <count> Recasts" (no weapon condition): probabilistic recast.
	["^%+?(%d+)%% chance for (%a+) recasts?$"] = function(num, _, countWord)
		local count = recastCountWords[countWord]
		if not count then return nil end
		return { mod("RepeatCount", "BASE", num * count / 100) }
	end,
	-- "X% Chance to recast": single probabilistic recast (Chaos Bolts). The
	-- in-game vs-cursed / toward-another-enemy qualifiers live in the node
	-- description, not this stat string, so the nominal average is modelled.
	["^%+?(%d+)%% chance to recast$"] = function(num)
		return { mod("RepeatCount", "BASE", num / 100) }
	end,
	-- @leb-regression-guard:hydra-arc-bow-repeat
	-- Hydra Arc (uniques_1_4.json uniqueID 441, verbatim mod string): "100% chance
	-- to Repeat your most recent Bow Attack after Evading". Pre-this-rule the line
	-- fell through the generic chain to an empty ModCache row
	-- ({{}," to Repeat your most recent  after Evading "}) -- a silent no-op, so the
	-- repeat reached no computed entity. Route the clean "repeat the bow attack"
	-- form to the existing RepeatCount/output.Repeats mechanism (CalcOffence.lua
	-- output.Repeats = 1 + Sum("BASE", skillCfg, "RepeatCount")), mirroring the
	-- recast-parse handlers above. Two deliberate scoping choices:
	--   * KeywordFlag.Bow: the affix repeats a *Bow Attack* only, so the RepeatCount
	--     sums only for a bow-keyword skill cfg (a spell/melee main skill is
	--     unaffected even when the condition is on).
	--   * Condition var "UsingEvade": the repeat happens "after Evading", an
	--     evade-uptime-dependent window. Gate on the EXISTING evade condition
	--     (ConfigOptions "Are you Using Evade?", default OFF; the same condition the
	--     "while using evade" tag uses) rather than inventing a new toggle. Default
	--     OFF => Condition:UsingEvade unset => the RepeatCount mod is inert =>
	--     output.Repeats stays 1 => corpus byte-identical (blast 0, no regen).
	--
	-- HONESTY / DPS-reach note (VERIFIED, do not "fix" as an under-count): even with
	-- the condition ON, this does NOT increase sustained Full DPS for the bow
	-- attacks Hydra Arc applies to. TotalDPS = AverageDamage * dpsMultiplier * Speed;
	-- output.Repeats enters TotalDPS ONLY via the cooldown Speed-cap
	-- (CalcOffence "if output.Cooldown then output.Speed = min(Speed, 1/Cooldown *
	-- Repeats)") and via the FINAL repeatMode dpsMultiplier /= Repeats (a DECREASE).
	-- EVERY Last Epoch bow attack has cooldown=None (skills.json: Cinder Strike,
	-- Detonating Arrow, Multishot, Puncture, Hail of Arrows, Explosive Trap, ...),
	-- so the cap never fires and output.Repeats only moves the burst-DISPLAY fields
	-- (AverageBurstHits / AverageBurstDamage) which do NOT feed TotalDPS/FullDPS
	-- (see the flame-reave-return-wave-hits guard). Probe (TmpHydraProbe, worktree):
	-- RepeatCount BASE 1 -> Repeats 1->2 but TotalDPS 1000->1000 unchanged for all
	-- three bow attacks. So the DPS-reach blast is 0 by construction; this rule
	-- removes the silent residue, fixes the burst display, and installs the native
	-- mechanism (it will start moving sustained DPS iff a future engine change
	-- propagates output.Repeats into attack hit-rate, or for any future
	-- cooldown-bearing bow attack). Full DPS is NOT a free-extra-attack-on-evade
	-- proc model -- that deeper mechanism is out of scope, exactly the Razorfall /
	-- SequentialProjectiles deeper-gap situation.
	-- Spec: spec/System/TestHydraArcBowRepeat_spec.lua
	["^(%d+)%% chance to repeat your most recent bow attack after evading$"] = function(num)
		return { mod("RepeatCount", "BASE", num / 100, "Hydra Arc", 0, KeywordFlag.Bow, { type = "Condition", var = "UsingEvade" }) }
	end,
	-- @leb-regression-guard:double-glancing-blow-if-not-hit
	-- Rogue-104 "Poise" notScalingStat (after PassiveTree.lua trim) is the bare
	-- sentence "Double Glancing Blow Chance If Not Hit". LE applies +100 INC
	-- GlancingBlowChance while the player has NOT been hit recently. Gate on
	-- the shared BeenHitRecently condition (neg) — the ConfigOptions "Have
	-- you been Hit Recently?" toggle defaults off, so by default the bonus
	-- applies and matches LE/LETools sidebar.
	-- See REGRESSION_GUARDS.md "double-glancing-blow-if-not-hit".
	["^double glancing blow chance if not hit$"] = function()
		return { mod("GlancingBlowChance", "INC", 100, { type = "Condition", var = "BeenHitRecently", neg = true }) }
	end,
	-- Idol Altar: Refracted Slot affix-effect modifiers.
	-- Produce named INC mods so the values accumulate on modDB and are visible (not red);
	-- actual per-affix scaling of refracted-slot idols is handled elsewhere.
	["^(%d+)%% increased effect of prefixes and suffixes for idols in refracted slots$"] = function(num)
		return { mod("IdolRefractedAffixEffect", "INC", num) }
	end,
	["^(%d+)%% increased effect of prefixes for idols in refracted slots$"] = function(num)
		return { mod("IdolRefractedPrefixEffect", "INC", num) }
	end,
	["^(%d+)%% increased effect of suffixes for idols in refracted slots$"] = function(num)
		return { mod("IdolRefractedSuffixEffect", "INC", num) }
	end,
	-- @leb-regression-guard: idol-refracted-weaver-enchant-boost
	-- The in-game tooltip text for the Weaver Enchantment variant of this
	-- Idol Altar affix omits "increased" and starts with "+" — verified on
	-- <private build> Altar of Arctus: "+(46-52)% Effect of Weaver Enchantment
	-- Affixes for Idols in Refracted Slots" (XML lines 828-833 around the
	-- standard prefix/suffix variants which DO use "increased Effect").
	-- Accept both forms so the same `IdolRefractedWeaverEffect` mod fires.
	-- Spec: spec/System/TestIdolRefractedWeaverEnchantBoost_spec.lua
	-- See REGRESSION_GUARDS.md "idol-refracted-weaver-enchant-boost".
	["^%+?(%d+)%% increased effect of weaver enchantment affixes for idols in refracted slots$"] = function(num)
		return { mod("IdolRefractedWeaverEffect", "INC", num) }
	end,
	["^%+?(%d+)%% effect of weaver enchantment affixes for idols in refracted slots$"] = function(num)
		return { mod("IdolRefractedWeaverEffect", "INC", num) }
	end,
	-- @leb-regression-guard: non-unique-idol-stat-multiplier
	-- Reliquary Nest (unique relic, id=433) carries property 98
	-- (`nonUniqueIdolStatModifier`) which scales every mod on every
	-- non-unique idol item by (1 + N/100). Game tooltip reads
	-- "Stats on your Non-Unique Idols have N% increased Effect"; the
	-- LEB-internal text is "+N% Non-Unique Idol Stat Multiplier".
	-- Both forms must parse to a flat BASE Multiplier:NonUniqueIdolStatEffect
	-- so CalcSetup can pre-scan and scale non-unique idol mods at item
	-- merge time. See REGRESSION_GUARDS.md "non-unique-idol-stat-multiplier".
	["^%+?([%d%.]+)%% non%-unique idol stat multiplier$"] = function(num)
		return { mod("Multiplier:NonUniqueIdolStatEffect", "BASE", tonumber(num)) }
	end,
	["^stats on your non%-unique idols have ([%d%.]+)%% increased effect$"] = function(num)
		return { mod("Multiplier:NonUniqueIdolStatEffect", "BASE", tonumber(num)) }
	end,
	-- @leb-regression-guard:different-shape-idol-stat-effect
	-- Wings of Discord legendary mod: "100% increased effect of stats on
	-- your Non-Unique Idols that are a different shape to all other
	-- equipped Non-Unique Idols". Unlike Reliquary Nest (flat merge-time
	-- multiplier on ALL non-unique idols), this is per-idol conditional
	-- (shape unique among equipped non-unique idols) and composes
	-- ADDITIVELY with the Idol Altar refracted-slot boosts at the affix
	-- value layer -- sheet-verified on StarSeaVnV: Impaling Huge Shadow
	-- idol pen prefix 8 -> in-game 8 x (1 + altar 0.457 + altar 0.0998 +
	-- Wings 1.0) = 20.45-20.48 (in-game carried 20.48; the unrounded affix
	-- roll is ~8.01, so the closure is structural, +-0.15%).
	-- CalcSetup pre-scans this multiplier and routes it through the same
	-- postRoundScalar path as the altar boosts. Unlike the altar boosts it
	-- applies to ALL affix subtypes (the Heretical weaver crit lines on the
	-- same idol are altar-exempt but ARE doubled in-game: carried cc/multi
	-- closures). Spec: spec/System/TestDifferentShapeIdolStatEffect_spec.lua
	["^([%d%.]+)%% increased effect of stats on your non%-unique idols that are a different shape to all other equipped non%-unique idols$"] = function(num)
		return { mod("Multiplier:DifferentShapeIdolStatEffect", "BASE", tonumber(num)) }
	end,
	-- @leb-regression-guard:offhand-exalted-weapon-stat-multiplier
	-- (The old "~21% under" was ~half buff confound.) See REGRESSION_GUARDS.md
	-- Validation provenance is retained in maintainer notes.
	["^([%d%.]+)%% increased effectiveness of stats on an offhand exalted weapon$"] = function(num)
		return { mod("Multiplier:OffhandExaltedWeaponStatEffect", "BASE", tonumber(num)) }
	end,
	-- @leb-regression-guard: weaver-set-2pc-ww-weapon-legendary-affix-effect
	-- Weaver Set 2-piece bonus (set_<ver>.json setId 15 bonus "2"):
	-- "Legendary affixes on equipped Weaver's Will weapons have 50% increased
	-- effect". applySetBonuses parses this line through modLib.parseMod; without
	-- this rule it resolved to nothing (silent no-op, the same class of bug the
	-- Whetstone/Truesight guards fixed) so the 2-set was functionally UNMODELED.
	-- We map it to Multiplier:WeaverWillWeaponLegendaryAffixEffect BASE 50 so the
	-- magnitude is data-sourced (not hardcoded); CalcSetup.applySetBonuses reads
	-- that Multiplier back and scales the legendaryAffix (woven) mods on equipped
	-- Weaver's Will WEAPONS by (1 + N/100). See REGRESSION_GUARDS.md
	-- "weaver-set-2pc-ww-weapon-legendary-affix-effect" and
	-- spec/System/TestWeaverSet2pcWWWeaponLegendaryAffix_spec.lua.
	["^legendary affixes on equipped weaver's will weapons have ([%d%.]+)%% increased effect$"] = function(num)
		return { mod("Multiplier:WeaverWillWeaponLegendaryAffixEffect", "BASE", tonumber(num)) }
	end,
	-- ("X% Chance to Gain Y Ward when Hit" is handled by the ward-aware
	-- chance-gain catch-alls near nsAny — see @leb-regression-guard:resource-gain-mode-chance-averaging.)
	-- Minion damage mods from uniques
	["^your minions deal (%d+)%% increased damage$"] = function(num)
		return { mod("MinionModifier", "LIST", { mod = mod("Damage", "INC", num) }) }
	end,
	["^you and your minions deal (%d+)%% increased melee damage$"] = function(num)
		return { mod("Damage", "INC", num, "", ModFlag.Melee), mod("MinionModifier", "LIST", { mod = mod("Damage", "INC", num, "", ModFlag.Melee) }) }
	end,
	-- @leb-regression-guard:companion-more-damage-health
	-- Validation provenance is retained in maintainer notes.
	["^([%d%.]+)%% more companion damage$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Damage", "MORE", tonumber(num)),
			minionTypes = {
				"PrimalBear",
				"PrimalWolf",
				"Summon_Raptor",
				"PrimalSabertooth",
				"PrimalScorpion",
				"StormCrow",
				"Spriggan",
				"RogueFalcon",
				"AncientOasis01 Primordial Minion",
			},
		}) }
	end,
	["^%+?([%d%.]+)%% more companion health$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Life", "MORE", tonumber(num)),
			minionTypes = {
				"PrimalBear",
				"PrimalWolf",
				"Summon_Raptor",
				"PrimalSabertooth",
				"PrimalScorpion",
				"StormCrow",
				"Spriggan",
				"RogueFalcon",
				"AncientOasis01 Primordial Minion",
			},
		}) }
	end,
	-- @leb-regression-guard:bear-tree-grants-minion-skills
	-- Validation provenance is retained in maintainer notes.
	["^bear can use earthquake$"] = function()
		-- inheritsMinionAttackBase: like Swipe, the bear's Earthquake is a PLAYER weapon skill
		-- reused by the bear -> it hits off the bear's BASIC-ATTACK base (~50), not the player
		-- EarthquakeSlam declared intrinsic (base 2). minionAttackEffectiveness=6: datamine eff 6
		-- (pid 261582/263683) vs LEB skills.json 2, applied ONLY to the bear's clone (the shared
		-- player Shaman EarthquakeSlam is untouched). F4 minion-breakdown oracle (DoNotReleaseThem,
		-- 2026-07-01): EQ ref-slam == Melee-clone x 6; element-MORE 9.98 == Melee's (the "-60%
		-- Earthquake" node be36ar-15 does NOT apply). See createMinionSkills.
		-- minionSlamNodeMod/minionSlamSum: eq5s-21 "Seismic Tide" fires the initial slam 3x at
		-- 0.70/0.95/1.30 (sum 2.95). When the player has that node (EarthquakeSeismicTide flag),
		-- the bear's Earthquake per-cast = ref x 2.95 (collapsed, Glacier-idiom). Bear-only.
		return { mod("ExtraMinionSkill", "LIST", { skillId = "EarthquakeSlam", minionList = { "PrimalBear" }, inheritsMinionAttackBase = true, minionAttackEffectiveness = 6, minionSlamNodeMod = "EarthquakeSeismicTide", minionSlamSum = 2.95 }) }
	end,
	["^bears use swipe$"] = function()
		-- inheritsMinionAttackBase: Swipe is a PLAYER weapon skill reused by the bear. In-game it
		-- deals the bear's BASIC-ATTACK damage (weapon base ~50), NOT the player-Swipe declared
		-- intrinsic (base 2) + the player Swipe skill-tree. F4 minion-breakdown oracle (DoNotReleaseThem,
		-- 2026-07-01): Swipe final 5139 ≈ Melee final 5415 (the bear's basic attack), whereas base-2 would
		-- be ~1/25 of Melee. So model it as a clone of the minion's primary attack. See createMinionSkills.
		return { mod("ExtraMinionSkill", "LIST", { skillId = "Swipe", minionList = { "PrimalBear" }, inheritsMinionAttackBase = true }) }
	end,
	-- @leb-regression-guard:minion-granted-weapon-attack-base-inheritance
	-- eq5s-21 "Seismic Tide" makes Earthquake's initial slam occur THREE times, at 0.70x / 0.95x
	-- / 1.30x damage (tree_0.json: "First with 30% reduced ... damage, then with 5% reduced ...,
	-- then with 30% increased ... damage"; sum 2.95). ModCache baked it as a {{},""} no-op, so the
	-- triple-slam was unmodeled. We emit a detectable FLAG (inert on its own — no damage stat); the
	-- bear's granted Earthquake reads it in createMinionSkills and applies the collapsed per-cast
	-- slam-sum (Glacier-idiom: one fused hit = ref x 2.95). Gated on the EQ grant's minionSlamNodeMod
	-- so it ONLY scales the bear's Earthquake clone; the shared player Shaman Earthquake is untouched
	-- (the flag exists on its modDB but nothing player-side reads it -> byte-identical). F4 oracle
	-- (DoNotReleaseThem 2026-07-01): 3 clusters 20974/28464/38951 = ref 29963 x {0.70,0.95,1.30} EXACT.
	["^initial slam occurs three times$"] = function()
		return { mod("EarthquakeSeismicTide", "FLAG", true) }
	end,
	-- @leb-regression-guard:manifest-armor-grant-skills
	-- Validation provenance is retained in maintainer notes.
	["^forgebreath$"] = function()
		return { mod("ExtraMinionSkill", "LIST", { skillId = "ManifestArmorForgeBreath", minionList = { "ManifestedArmor" } }) }
	end,
	["^whirlwind strike$"] = function()
		return { mod("ExtraMinionSkill", "LIST", { skillId = "ManifestArmorWhirlwind", minionList = { "ManifestedArmor" } }) }
	end,
	["^charge attack$"] = function()
		return { mod("ExtraMinionSkill", "LIST", { skillId = "ManifestArmorCharge", minionList = { "ManifestedArmor" } }) }
	end,
	-- @leb-regression-guard:falcon-feather-knives-grant
	-- Validation provenance is retained in maintainer notes.
	["^(%d+) feather knives cooldown %(seconds%)$"] = function()
		return { mod("ExtraMinionSkill", "LIST", { skillId = "FeatherKnives", minionList = { "RogueFalcon" } }) }
	end,
	-- @leb-regression-guard:dragonflame-nova-grant
	-- Dragonflame Edict (unique staff, uniques_1_4.json) mod "60% Chance for the
	-- nearest minion to the target location to cast Dragonflame Nova when you use
	-- a minion skill (1 second cooldown)". ModCache baked it as LEB_NotSupported,
	-- so the proc was a silent no-op (the last open root on the ACG-3 board row).
	-- "Nearest minion" = whichever minion is out, so the grant carries NO
	-- minionList (createMinionSkills applies it to any minion type). The skill
	-- data already exists: data.skills.DragonfireNova ("Dragonflame Nova",
	-- datamined Fire 80 / eff 4.0 / crit 5% x2.0, spell hit) -- the granted
	-- sub-skill scales with the wielder's minion mods (including this staff's own
	-- "increased Minion Fire Damage"). Granted skills append AFTER the minion's
	-- base kit, so the minion's main/FullDPS skill is unchanged.
	-- @leb-regression-guard:dragonflame-nova-proc-rate
	-- The proc RATE is GROUNDED (2026-07-10 datamine, reference_leb_trigger_framework):
	-- chance = affix property 98 value 0.6 (uniques_v3.json, the matched 60 here) and
	-- the 1s cooldown is the game's real text constant (descriptor 98,83,0,0) -- so
	-- rate = min(chance x minion_skill_use_rate, 1/s) is datamine-grounded, NOT
	-- curve-fit (the ONE nova-family proc where both factors are grounded). Emit the
	-- chance under ChanceToTriggerOnMinionSkillUse_DragonfireNova and the cap under
	-- TriggerRateCapPerSecond_DragonfireNova (the PTT rate-cap family, mirroring the
	-- on-spell-cast bridge naming). Neither stat name is scanned by the CalcSetup
	-- player-trigger loops (no ChanceToTriggerOnHit_/Capped_ alias), so NO player-side
	-- triggered group is created -- the per-hit stays SOLELY on the minion sub-skill
	-- and the rate fold happens where that per-hit lives (Calcs.lua calcFullDPS,
	-- guard dragonflame-nova-proc-rate). minion_skill_use_rate = the summoning
	-- skill's own cast rate (config-overridable), resolved at the fold site.
	-- Spec: spec/System/TestDragonflameNovaGrant_spec.lua (grant),
	--       spec/System/TestDragonflameNovaProcRate_spec.lua (rate).
	["^(%d+)%% chance for the nearest minion to the target location to cast dragonflame nova when you use a minion skill %(1 second cooldown%)$"] = function(num)
		return { mod("ExtraMinionSkill", "LIST", { skillId = "DragonfireNova" }),
		         mod("ChanceToTriggerOnMinionSkillUse_DragonfireNova", "BASE", tonumber(num)),
		         mod("TriggerRateCapPerSecond_DragonfireNova", "BASE", 1) }
	end,
	-- @leb-regression-guard:falcon-per-dex-added
	-- Falconry per-Dexterity added-damage nodes route added damage onto the Falcon
	-- (RogueFalcon), scaling off the PLAYER's Dexterity. datamining
	-- (FalconryMutator): falconMeleeDamagePer4Dex  -> Stats.AddedStat(tag 0x200=Melee,
	-- Dex * value * 0.25); falconThrowingDamagePer4Dex -> tag 0x400=Throwing. Two
	-- SEPARATE tag-specific stats, NOT a global add.
	--   tree_4.json L31   "+1 Falcon Melee Damage per 4 Dexterity" (Falconer
	--                      ascendancy-start node, innate to every Falconer)
	--   tree_4.json L2296 "+1 Falcon Throwing Damage Per 4 Dex"
	-- ModCache baked both as a player-side Damage BASE PerStat + " Falcon " residue
	-- (dropped at the tree gate, and mis-scoped to the player), so the Falcon got
	-- neither. Route via MinionModifier{minionTypes={"RogueFalcon"}} with the inner
	-- PerStat reading actor="parent" Dex (GetStatsFromPlayer) and div=4 (the x0.25).
	-- keywordFlags Melee(512)/Throwing(1024) keep each add tag-specific: the Falcon's
	-- throwing abilities (Aerial Assault / Feather Knives) get the throwing add, its
	-- placeholder Melee gets the melee add. Rem-MK3 runtime dump: Dex 263 -> 65.75
	-- added on both t512 and t1024 (263/4). Grants the dominant Falcon added-damage
	-- component; the residual (Falconer's Mark consume) is DEFER, no curve-fit.
	-- Spec: spec/System/TestFalconPerDexAdded_spec.lua
	["^%+([%d%.]+) falcon melee damage per 4 dexterity$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Damage", "BASE", tonumber(num), "", 0, KeywordFlag.Melee, { type = "PerStat", stat = "Dex", div = 4, actor = "parent" }),
			minionTypes = { "RogueFalcon" },
		}) }
	end,
	["^%+([%d%.]+) falcon throwing damage per 4 dex$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Damage", "BASE", tonumber(num), "", 0, KeywordFlag.Throwing, { type = "PerStat", stat = "Dex", div = 4, actor = "parent" }),
			minionTypes = { "RogueFalcon" },
		}) }
	end,
	-- @leb-regression-guard:falcon-tactician-flat-added
	-- Validation provenance is retained in maintainer notes.
	["^%+([%d%.]+) melee damage for falcon$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Damage", "BASE", tonumber(num), "", 0, KeywordFlag.Melee),
			minionTypes = { "RogueFalcon" },
		}) }
	end,
	["^%+([%d%.]+) throwing damage for falcon$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Damage", "BASE", tonumber(num), "", 0, KeywordFlag.Throwing),
			minionTypes = { "RogueFalcon" },
		}) }
	end,
	-- @leb-regression-guard:falcon-avian-hurl-conversion
	-- Avian Hurl (Rogue-90, Falconer mastery, 6pts). Node stat "N% Added Throwing
	-- Damage Conversion To Falcon" is EHG's loose wording for a GRANT, not an LE
	-- damage-TYPE conversion: datamining field
	-- `falconAddedThrowingAndMeleeDamagePercentageFromPlayerThrowingDamage`
	-- (AbilityStatsMutatorManager bucket 0x2d7) -> the Falcon gains added Throwing
	-- AND Melee damage equal to N% of the PLAYER's added throwing flat. Fixed N
	-- (noScaling), so a plain BASE percent. This rule only records the percent on
	-- the PLAYER modDB; the per-type routing onto env.minion.modDB happens in
	-- CalcPerform (mirror of the weapon-attack-minion-inheritance block), because
	-- "50% of my added-throwing pool" has no PerStat primitive (it is a per-type
	-- sum, not a single scalar). Independent of the per-Dex adds above (Dex source
	-- vs added-throwing source are disjoint pools -> no double count). The prior
	-- ModCache row for this line was a wrong `Damage MORE 50` player misparse with
	-- non-empty residue (inert only by the tree gate's residue-drop); regenerate
	-- ModCache after this rule lands so the row becomes this clean player mod.
	-- Spec: spec/System/TestFalconAvianHurl_spec.lua
	["^([%d%.]+)%% added throwing damage conversion to falcon$"] = function(num)
		return { mod("FalconAddedThrowingConversion", "BASE", tonumber(num)) }
	end,
	-- @leb-regression-guard:abomination-double-strike-grant
	-- Validation provenance is retained in maintainer notes.
	["^double strike gained on warrior or rogue absorbed$"] = function()
		return { mod("ExtraMinionSkill", "LIST", { skillId = "Abomination Double Strike", minionList = { "SummonedAbomination" } }) }
	end,
	-- @leb-regression-guard:per-mana-cost-melee-affix
	-- "X% [Damage / Crit / Area] for Melee ... per 1 Mana Cost" affixes scale by the
	-- ACTIVE skill's Mana cost, NOT flat. Basis = output.ManaCost -- for the channeled
	-- Warpath this is the ability's nominal manaCost field = 1 (datamine
	-- ability_attribute_scaling.json va53st manaCost 1.0, NOT channelCost 18, NOT 0),
	-- so a PerStat:ManaCost tag resolves it per skill (verified sum-time: Warpath x1,
	-- Forge Strike x20; ProbePerManaTag.lua). Scope = the Melee KEYWORD (all melee
	-- skills), fixing the old ModCache bake that wrongly scoped to SkillName
	-- "Melee Attack" (basic attack only) and DROPPED the mana scaling + cap, so these
	-- contributed ~0 on Warpath / Forge Strike. The Damage prefix is multiplicative and
	-- capped (Property_Player_636 "up to 20", AltText "more, Multiplicative with other
	-- modifiers"); the Crit / Area variants carry no "(up to 20)" text so no limit.
	-- On the current corpus every melee output.ManaCost <= 20 so the cap is non-binding.
	-- Spec: spec/System/TestPerManaCostMeleeAffix_spec.lua. Shares the basis with the
	-- Brutality attribute instance (CalcOffence brutality-per-manacost-melee-more).
	["^%+?([%d%.]+)%% damage for melee attacks per 1 mana cost %(up to 20%)$"] = function(num)
		return { mod("Damage", "MORE", tonumber(num), "", ModFlag.Melee, 0, { type = "PerStat", stat = "ManaCost", div = 1, limit = 20 }) }
	end,
	["^%+?([%d%.]+)%% critical strike chance for melee attacks per 1 mana cost$"] = function(num)
		return { mod("CritChance", "BASE", tonumber(num), "", ModFlag.Melee, 0, { type = "PerStat", stat = "ManaCost", div = 1 }) }
	end,
	["^%+?([%d%.]+)%% increased area for melee area skills per 1 mana cost$"] = function(num)
		return { mod("AreaOfEffect", "INC", tonumber(num), "", 0, KeywordFlag.Melee, { type = "PerStat", stat = "ManaCost", div = 1 }) }
	end,
	-- @leb-regression-guard:skeletal-mage-pyromancer-conversion
	-- Manifest Armor grants) -> no requiresNode. See REGRESSION_GUARDS.md.
	-- Validation provenance is retained in maintainer notes.
	["^adds pyromancers$"] = function()
		return { mod("ExtraMinionSkill", "LIST", { skillId = "Skeletal Mages Fire Projectile", minionList = { "SummonedSkeletonMage" }, replaces = "Skeletal Mages Necrotic Projectile" }) }
	end,
	-- "-60% Bear Earthquake Damage" (be36ar-15 downside): a MORE multiplier on
	-- the BEAR's Earthquake only. ModCache baked a bare SkillName=Earthquake
	-- Damage MORE with residue " Bear   " (dropped by the tree layer; and if
	-- it had applied, it would have hit the PLAYER's Earthquake). Route it
	-- through MinionModifier so it lands on the bear's modDB, keeping the
	-- SkillName tag so it scopes to the granted Earthquake and not the bear's
	-- melee or Swipe.
	["^%-(%d+)%% bear earthquake damage$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Damage", "MORE", -tonumber(num), "", 0, 0, { type = "SkillName", skillName = "Earthquake" }),
			minionTypes = { "PrimalBear" },
		}) }
	end,
	-- @leb-regression-guard:crit-chance-for-skeletons-skeletal-mages
	-- Acolyte minion-summoner affixes (idol prefix 313, item prefixes around
	-- ModItem_1_4.json index 42387..) of the form
	--   "+N% Critical Strike Chance for Skeletons"     (rolls separately, line "1")
	--   "+N% Critical Strike Chance for Skeletal Mages"(rolls separately, line "2")
	-- Before this guard the bare `name="CritChance" BASE` mod leaked the +N% onto
	-- the PLAYER's main-skill crit chance instead of any minion. Each line emits
	-- a MinionModifier LIST whose dispatch in CalcPerform.lua (see guard
	-- `minion-modifier-multi-type-gate`) routes to the matching minion-family
	-- type(s). Skeletons family covers SummonedSkeleton + Archer/Harvester/
	-- Vanguard/Rogue per src/Data/minions.json. Skeletal Mages is a single type.
	["^%+?([%d%.]+)%% critical strike chance for skeletons$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("CritChance", "BASE", num),
			minionTypes = {
				"SummonedSkeleton",
				"SummonedSkeletonArcher",
				"SummonedSkeletonHarvester",
				"SummonedSkeletonVanguard",
				"SummonedSkeletonRogue",
			},
		}) }
	end,
	["^%+?([%d%.]+)%% critical strike chance for skeletal mages$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("CritChance", "BASE", num),
			type = "SummonedSkeletonMage",
		}) }
	end,
	-- @leb-regression-guard:auto-summon-registry
	-- Apiarist "Bees" auto-summon COUNT stats. LE grants bees by GEAR/affix,
	-- not a slotted skill: "+N Bees Per 10 Seconds" (and the "Elemental Bees"
	-- variant). These were ModCache no-ops ({{}," Bees Per 10 Seconds "}), so
	-- LEB recognized the text but summoned nothing. Parse to a PLAYER-side
	-- count stat (BeesPerTenSeconds / ElementalBeesPerTenSeconds); the
	-- CalcSetup grantedAutoSummons loop (data.autoSummons) detects it
	-- (env.modDB:Sum("BASE",...) > 0) and injects SummonBee as an
	-- includeInFullDPS granted skill, and calcFullDPS scales the bee minion
	-- DPS by the resolved count (pack DPS). The "+N%" form has no "increased"
	-- keyword, so the generic BASE_MORE form scanner would bake it as BASE;
	-- these explicit handlers fix it to INC per the affix's in-game meaning.
	-- A conditional tail variant ("+8 Bees per 10 seconds while in Spriggan
	-- Form") falls through to the modNameList "bees per 10 seconds" alias so
	-- the "while in spriggan form" Condition modTag attaches automatically.
	-- Spec: spec/System/TestAutoSummonFramework_spec.lua
	["^%+?([%d%.]+) bees per 10 seconds$"] = function(num)
		return { mod("BeesPerTenSeconds", "BASE", tonumber(num)) }
	end,
	["^%+?([%d%.]+)%% bees per 10 seconds$"] = function(num)
		return { mod("BeesPerTenSeconds", "INC", tonumber(num)) }
	end,
	["^%+?([%d%.]+) elemental bees per 10 seconds$"] = function(num)
		return { mod("ElementalBeesPerTenSeconds", "BASE", tonumber(num)) }
	end,
	["^%+?([%d%.]+)%% elemental bees per 10 seconds$"] = function(num)
		return { mod("ElementalBeesPerTenSeconds", "INC", tonumber(num)) }
	end,
	-- @leb-regression-guard:auto-summon-registry
	-- "+N Melee Damage for your Summoned Bees": flat added MELEE damage scoped
	-- to the Bee minion. Mirrors the bear-earthquake idiom (MinionModifier LIST
	-- with minionTypes). Before this rule ModCache baked a bare player-side
	-- Damage BASE (keywordFlags=Melee) with the unconsumed residue " for your
	-- Summoned Bees ", leaking the add onto the player's main skill. The
	-- minion type "Bee" is the src/Data/minions.json key (== env.minion.type
	-- after the SummonBee.minionList -> ["Bee"] linkage fix), so the
	-- minion-modifier-multi-type-gate dispatch in CalcPerform routes it to the
	-- bee's modDB. keywordFlags=Melee (512) matches LE's "Melee Damage" idiom.
	["^%+?([%d%.]+) melee damage for your summoned bees$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Damage", "BASE", tonumber(num), "", 0, KeywordFlag.Melee),
			minionTypes = { "Bee" },
		}) }
	end,
	-- @leb-regression-guard:auto-summon-registry
	-- Phase B auto-summon COUNT stats (same framework as the bees above): unique
	-- items that auto-summon a non-skill-bound minion. Each was a ModCache no-op
	-- ({{},"..."} residue), so LEB recognized the text but summoned nothing.
	-- Parse to a PLAYER-side count stat that data.autoSummons maps to the existing
	-- summon skill; CalcSetup grantedAutoSummons injects it (includeInFullDPS) and
	-- calcFullDPS scales the minion DPS by the count (pack DPS). The summoned
	-- minion's primary attack skill is encoded in skills.json (datamine v1).
	--   * Tyrant's Skull (unique 424): "+100% Summons Tyrannosaur Minion". The
	--     "100%" is the property magnitude, NOT a count -- it summons exactly ONE
	--     permanent T-Rex while equipped, so parse to BASE 1 (ignore the number).
	--   * Tolmat's Incorrect History of Eterra (unique 369): "+N Tolmat's Historic
	--     Minions". A flat steady-state COUNT (maxTolmatMinions, per-area resummon);
	--     count = N directly (stacks across sources).
	--   * Chorus of the Anurok (unique 430): "1 Summon Anuroks up to your Companion
	--     Limit". v1 parses a presence flag (BASE 1) -> exactly 1 Anurok shown
	--     (CONSERVATIVE undercount: the in-game pack fills the companion limit, so
	--     true count = MaxCompanions, typically 2-5). Refining to a separate
	--     pack-count stat is a documented follow-up; BASE 1 keeps correct gating
	--     (only fires when Chorus is equipped, unlike MaxCompanions which any
	--     companion class carries).
	-- Spec: spec/System/TestAutoSummonFramework_spec.lua
	["^%+?([%d%.]+)%% summons tyrannosaur minion$"] = function()
		return { mod("TyrannosaursSummoned", "BASE", 1) }
	end,
	["^%+?([%d%.]+) tolmat's historic minions$"] = function(num)
		return { mod("TolmatHistoricMinions", "BASE", tonumber(num)) }
	end,
	["^%+?([%d%.]+) summon anuroks up to your companion limit$"] = function()
		return { mod("AnuroksSummoned", "BASE", 1) }
	end,
		-- @leb-regression-guard:storm-sprite-tempest-maw
		-- Tempest Maw intrinsic (ability tooltip, not a rollable mod): "When you summon
		-- a totem you also summon N Storm Sprites around the totem (up to 2 times per 6
		-- seconds)". Parse per-proc count N (game-source 4) -> StormSpritesSummoned;
		-- data.autoSummons maps it to SummonStormSprite (StormSprite casts stormSpriteDash
		-- = Lightning 20, added 2026-06-17 from live 1.4.7 bundles). 2x/6s proc rate +
		-- totem-summon trigger flattened to steady-state count (in-game WARRIOR95 ~4).
		["^when you summon a totem you also summon ([%d%.]+) storm sprites.*$"] = function(num)
			return { mod("StormSpritesSummoned", "BASE", tonumber(num)) }
		end,
	-- @leb-regression-guard:auto-summon-registry
	-- Queen Bee auto-summon (Apiarist's Set 3-piece bonus "Summon the Queen Bee").
	-- This is a SET BONUS string, not an item affix: CalcSetup.applySetBonuses
	-- parses each bonus tier via modLib.parseMod when the piece count is met, so
	-- this handler fires and puts QueenBeeSummoned on env.itemModDB -> env.modDB.
	-- The bonus summons exactly ONE persistent Queen (a bool flag in-game), so
	-- parse to BASE 1. data.autoSummons maps it to SummonQueenBee -> QueenBee
	-- minion (Scratch 60 phys, eff 3). Quadruple Scratch + on-death Bee Explosion
	-- are deferred (v1 single primary, like the other auto-summons).
	["^summon the queen bee$"] = function()
		return { mod("QueenBeeSummoned", "BASE", 1) }
	end,
	-- @leb-regression-guard:throwing-attack-damage-inc
	-- "X% Throwing Attack Damage" (passive Rogue-49 "Pursuit" per-rank stat;
	-- one more tree node carries "+12%"). ModCache baked the family as
	-- `Damage MORE keywordFlags=Throwing` with parse residue "  Attack  " --
	-- and the tree layer drops residue-carrying mods entirely (see
	-- conversion-extra-nil-not-empty consumer in PassiveTree.lua), so the stat
	-- NEVER applied. In-game it is an additive INCREASE: Prepfor1o1 Acid Flask
	-- first-hit capture decomposes to +30 generic-INC-equivalent missing with
	-- Pursuit x5 allocated, and the phys/fire pair (300.20 / 349.31) fits
	-- Damage INC 30 on BOTH types simultaneously (MORE x1.30 is excluded:
	-- it would give 346 phys). Emit a clean (residue-free) Throwing-scoped INC.
	["^%+?([%d%.]+)%% throwing attack damage$"] = function(num)
		return { mod("Damage", "INC", num, "", 0, KeywordFlag.Throwing) }
	end,
	-- @leb-regression-guard:throwing-attack-damage-increased-and-flat
	-- Validation provenance is retained in maintainer notes.
	["^%+?([%d%.]+)%% increased throwing attack damage$"] = function(num)
		return { mod("Damage", "INC", num, "", 0, KeywordFlag.Throwing) }
	end,
	["^%+?([%d%.]+) throwing attack damage$"] = function(num)
		return { mod("Damage", "BASE", num, "", 0, KeywordFlag.Throwing) }
	end,
	-- @leb-regression-guard:storm-totem-unmatched-storms-cadence
	-- Validation provenance is retained in maintainer notes.
	["^storm bolts instead of lightning strikes$"] = function()
		return { mod("MinionFixedCastTime", "LIST", {
			time = 1 / 8.307,
			minionList = { "StormTotem" },
		}) }
	end,
	-- @leb-regression-guard:crit-for-totems-per-int-and-multi
	-- Totem-family crit affixes:
	--   "+N% Critical Strike Chance for Totems per Intelligence"
	--     - inherent on unique Ferebor's Chisel (uniques.json "+1% ...")
	--     - ModItem prefix 786 "Ferebor's Chisel Reforged" 1.4.5 text (8 values).
	--       Note: v3 game-data dump 2026-05-01 shows affix 786 second line was
	--       reworked post-1.4.5 to a Frenzy-on-Storm-Totem-hit line; the parser
	--       fix is still correct for the LEB-current text and the unique mod.
	--   "+N% Critical Strike Multiplier for Totems"
	--     - ModItem prefix 786 first line (still active per v3 dump: property 5
	--       Critical Strike Multiplier + tag 16384 Totem)
	-- Before this guard, the bare `CritChance` / `CritMultiplier` BASE mod leaked
	-- the +N% onto the PLAYER's main-skill crit instead of any totem. Each line
	-- emits a MinionModifier LIST whose dispatch in CalcPerform.lua (see guard
	-- `minion-modifier-multi-type-gate`) routes to the totem-family minion types.
	-- per-Int AltText "Scales with your Intelligence" (Property_Player_175) =>
	-- inner mod carries PerStat:Int with actor="parent" so it scales on player Int.
	-- Totem family per src/Data/minions.json: 8 keys (Frenzy Totem, Thorn Totem,
	-- StormTotem, HealingTotem, ClawTotem, TempestTotem, WarcryTotem, UpheavalTotem).
	["^%+?([%d%.]+)%% critical strike chance for totems per intelligence$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("CritChance", "BASE", num, "", 0, 0, { type = "PerStat", stat = "Int", actor = "parent" }),
			minionTypes = {
				"Frenzy Totem",
				"Thorn Totem",
				"StormTotem",
				"HealingTotem",
				"ClawTotem",
				"TempestTotem",
				"WarcryTotem",
				"UpheavalTotem",
			},
		}) }
	end,
	["^%+?([%d%.]+)%% critical strike multiplier for totems$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("CritMultiplier", "BASE", num),
			minionTypes = {
				"Frenzy Totem",
				"Thorn Totem",
				"StormTotem",
				"HealingTotem",
				"ClawTotem",
				"TempestTotem",
				"WarcryTotem",
				"UpheavalTotem",
			},
		}) }
	end,
	-- @leb-regression-guard:tyrant-skull-per-attribute-minion-scope
	-- Validation provenance is retained in maintainer notes.
	["^%+?([%d%.]+) tyrannosaur melee damage per strength$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Damage", "BASE", tonumber(num), "", ModFlag.Melee, 0, { type = "PerStat", stat = "Str", actor = "parent" }, { type = "ActorCondition", actor = "parent", var = "TyrantSkullPerAttribute" }),
			minionTypes = { "PrimalTyrannosaur" },
		}) }
	end,
	["^([%d%.]+)%% more tyrannosaur health and damage per 1%% uncapped endurance$"] = function(num)
		return {
			mod("MinionModifier", "LIST", {
				mod = mod("Life", "MORE", tonumber(num), "", 0, 0, { type = "PerStat", stat = "EnduranceTotal", actor = "parent" }, { type = "ActorCondition", actor = "parent", var = "TyrantSkullPerAttribute" }),
				minionTypes = { "PrimalTyrannosaur" },
			}),
			mod("MinionModifier", "LIST", {
				mod = mod("Damage", "MORE", tonumber(num), "", 0, 0, { type = "PerStat", stat = "EnduranceTotal", actor = "parent" }, { type = "ActorCondition", actor = "parent", var = "TyrantSkullPerAttribute" }),
				minionTypes = { "PrimalTyrannosaur" },
			}),
		}
	end,
	["^%+?([%d%.]+)%% tyrannosaur physical penetration per intelligence$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("PhysicalPenetration", "BASE", tonumber(num), "", 0, 0, { type = "PerStat", stat = "Int", actor = "parent" }, { type = "ActorCondition", actor = "parent", var = "TyrantSkullPerAttribute" }),
			minionTypes = { "PrimalTyrannosaur" },
		}) }
	end,
	["^%+?([%d%.]+)%% tyrannosaur critical strike multiplier per attunement$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("CritMultiplier", "BASE", tonumber(num), "", 0, 0, { type = "PerStat", stat = "Att", actor = "parent" }, { type = "ActorCondition", actor = "parent", var = "TyrantSkullPerAttribute" }),
			minionTypes = { "PrimalTyrannosaur" },
		}) }
	end,
	["^([%d%.]+)%% increased tyrannosaur attack and cast speed per dexterity$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Speed", "INC", tonumber(num), "", 0, 0, { type = "PerStat", stat = "Dex", actor = "parent" }, { type = "ActorCondition", actor = "parent", var = "TyrantSkullPerAttribute" }),
			minionTypes = { "PrimalTyrannosaur" },
		}) }
	end,
	-- @leb-regression-guard:ballista-attack-speed-minion-scope
	-- "Increased Ballista Attack Speed" (affix 536/640, datamine property 58 / summon-
	-- Ballista tag 379) scales the RogueBallista minion's BallistaBolt FIRING rate, not
	-- a player skill. The default parse routed it to a player-side INC Speed carrying
	-- tag=SkillName:"Ballista" -- which names the SUMMON skill ("Ballista"), not the
	-- minion's firing skill ("Ballista Bolt") -- and is never wrapped as a
	-- MinionModifier, so it never reaches env.minion.modDB. Result: the ballista's
	-- firing rate was under-modeled (Rem-MK3: INC 29 from a rolled "Rogue's" affix
	-- silently dropped, minion Speed 1.45 vs measured higher). Mirror the tyrannosaur
	-- precedent above: emit a MinionModifier LIST scoped to RogueBallista; dispatch in
	-- CalcPerform.lua (guard minion-modifier-multi-type-gate) lands the inner INC Speed
	-- on env.minion.modDB, where CalcOffence.lua Sum("INC",cfg,"Speed") picks it up.
	-- Inner mod: flags=0, NO SkillName tag (the minion Speed query is scoped to
	-- "Ballista Bolt"; an unscoped INC Speed matches). Datamine: RogueBallista runs
	-- BallistaBolt (minions.json), LE_WEAPON_ATTACK_MINIONS.RogueBallista (Global.lua).
	-- Spec: spec/System/TestBallistaAttackSpeedMinionScope_spec.lua
	["^([%d%.]+)%% increased ballista attack speed$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Speed", "INC", tonumber(num)),
			minionTypes = { "RogueBallista" },
		}) }
	end,
	-- @leb-regression-guard:stygian-coal-per-int-castfreq
	-- Stygian Coal (unique, id 328) rolls verbatim "1% increased Stygian Beam frequency
	-- per Intelligence". Stygian Beam is the player-cast spell Drain Life fires when this
	-- unique is equipped ("+1 Drain Life casts Stygian Beams instead"); it is a real
	-- modeled skill (Data/skills.json "Drain Life Stygian Beam" -> name "Stygian Beam",
	-- castTime 0.6818182, spell/hit, playerAbilityID lb23il). "frequency" = casts per
	-- second = that skill's cast rate, i.e. an INC Speed scoped to the one skill. There
	-- is no "frequency" modName alias, so the generic parse chain left "frequency" as
	-- residue and emitted {} (empty modList) -> the affix silently dropped (ModCache row
	-- baked {{},"  frequency  "}). Emit a player-side INC Speed with a PerStat:Int tag
	-- and a SkillName:"Stygian Beam" tag: CalcOffence.lua ~L2174 Sum("INC", cfg, "Speed")
	-- feeds output.Speed/output.CastRate, and the SkillName tag is matched against
	-- cfg.skillName in ModStore.lua:762 so it only scales Stygian Beam. flags=0 (like the
	-- ballista handler above) so it is not restricted to a cast/attack-flagged query.
	-- Same per-stat cast/attack-speed shape as the tyrannosaur/ballista handlers above;
	-- the consumer already exists (no new primitive). Whole-line ^...$ so parseMod leaves
	-- no residue (extra=nil, <see git log> trailing-residue drop avoided). Stale empty
	-- ModCache row deleted so the affix parses live. Spec:
	-- spec/System/TestStygianCoalPerIntCastFreq_spec.lua. See REGRESSION_GUARDS.md.
	["^([%d%.]+)%% increased stygian beam frequency per intelligence$"] = function(num)
		return { mod("Speed", "INC", tonumber(num), "", 0, 0, { type = "PerStat", stat = "Int" }, { type = "SkillName", skillName = "Stygian Beam" }) }
	end,
	-- @leb-regression-guard:totem-damage-minion-scope
	-- Totem-family damage tree nodes:
	--   "+1 Totem Spell Damage"       - Primalist-115 "Elder Branch" (tree_0.json;
	--     stats "+1 Spell Damage" / "+1 Totem Spell Damage" / " Tripled while
	--     using an Axe"; description "You and your totems deal additional spell
	--     damage. This bonus is tripled while using an axe." - the first stat is
	--     the player half, this one is the totem half)
	--   "+10% Increased Totem Damage" - Primalist-35 "Fate Carver" (tree_0.json)
	-- Before this guard, ModCache baked both as PLAYER-scoped Damage mods with
	-- the "Totem" scope eaten into parse residue ("tem   " / " Totem  "), so the
	-- bonus leaked onto the player's main skill instead of the totem minions.
	-- Each line emits a MinionModifier LIST whose dispatch in CalcPerform.lua
	-- (see guard `minion-modifier-multi-type-gate`) routes to the totem-family
	-- minion types (same 8-key family as `crit-for-totems-per-int-and-multi`
	-- above, per src/Data/minions.json). The flat spell line carries
	-- KeywordFlag.Spell on the inner mod, matching the old baked
	-- keywordFlags=256. The two stale ModCache rows are REMOVED (not patched) so
	-- the lines live-parse through these handlers; that also covers the
	-- point-scaled variants ("+2".."+5" / "+20%".."+80%") that were never baked.
	-- The Elder Branch companion stat " Tripled while using an Axe" stays
	-- recognition-only (ModCache no-op row, zero mods) - the tripling is NOT
	-- modeled. The sibling "on Hit" rows ("+1 Totem Spell Damage on Hit", "+1
	-- Totem Melee Damage on Hit") are a different stat family, still baked
	-- player-scoped, and the `$` anchors here cannot match them.
	-- No corpus build allocates either node (grep Primalist-115 / Primalist-35
	-- over spec/TestBuilds 2026-06-11: zero hits), so zero snapshot impact; this
	-- is a parser-correctness fix justified by the node text + parse residue.
	-- Spec: spec/System/TestTotemDamageMinionScope_spec.lua
	["^%+?([%d%.]+) totem spell damage$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Damage", "BASE", num, "", 0, KeywordFlag.Spell),
			minionTypes = {
				"Frenzy Totem",
				"Thorn Totem",
				"StormTotem",
				"HealingTotem",
				"ClawTotem",
				"TempestTotem",
				"WarcryTotem",
				"UpheavalTotem",
			},
		}) }
	end,
	["^%+?([%d%.]+)%% increased totem damage$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("Damage", "INC", num),
			minionTypes = {
				"Frenzy Totem",
				"Thorn Totem",
				"StormTotem",
				"HealingTotem",
				"ClawTotem",
				"TempestTotem",
				"WarcryTotem",
				"UpheavalTotem",
			},
		}) }
	end,
	-- @leb-regression-guard:stormcarved-for-totems-scope
	-- Validation provenance is retained in maintainer notes.
	["^%+?([%d%.]+)%% lightning penetration for totems$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("LightningPenetration", "BASE", num),
			minionTypes = {
				"Frenzy Totem",
				"Thorn Totem",
				"StormTotem",
				"HealingTotem",
				"ClawTotem",
				"TempestTotem",
				"WarcryTotem",
				"UpheavalTotem",
			},
		}) }
	end,
	["^%+?([%d%.]+) spell lightning damage for totems$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("LightningDamage", "BASE", num, "", 0, KeywordFlag.Spell),
			minionTypes = {
				"Frenzy Totem",
				"Thorn Totem",
				"StormTotem",
				"HealingTotem",
				"ClawTotem",
				"TempestTotem",
				"WarcryTotem",
				"UpheavalTotem",
			},
		}) }
	end,
	["^%+?([%d%.]+)%% chance to shock on hit for totems$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("ChanceToTriggerOnHit_Ailment_Shock", "BASE", num, "", ModFlag.Hit),
			minionTypes = {
				"Frenzy Totem",
				"Thorn Totem",
				"StormTotem",
				"HealingTotem",
				"ClawTotem",
				"TempestTotem",
				"WarcryTotem",
				"UpheavalTotem",
			},
		}) }
	end,
	["^%+?([%d%.]+)%% lightning resistance for totems$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("LightningResist", "BASE", num),
			minionTypes = {
				"Frenzy Totem",
				"Thorn Totem",
				"StormTotem",
				"HealingTotem",
				"ClawTotem",
				"TempestTotem",
				"WarcryTotem",
				"UpheavalTotem",
			},
		}) }
	end,
	-- @leb-regression-guard:ward-per-second-and-retention-family
	-- Ward Per Second / Ward Retention / Ward Decay Threshold affix family.
	-- 13 silent-failure entries: parser was emitting the bare stat with the
	-- conditional residue left in slot[2], so the ward bonus leaked onto the
	-- player's base ward stat unconditionally instead of being gated by the
	-- referenced condition/multiplier. Each handler below maps to one
	-- LEB-source tree node or unique mod text. Companion sites:
	--   * ConfigOptions.lua  multiplierFirebrandStack + multiplierActiveSymbols
	--     (Condition:HaveActiveSymbol)
	--   * CalcSetup.lua      auto-populate Multiplier:AreaInc / ArmourInc /
	--     UncappedResistTotal from sum INC / BASE on the relevant stats.
	-- Spec: spec/System/TestWardRegenFamily_spec.lua
	["^%+?(%d+) ward decay threshold per 2%% necro res$"] = function(num)
		return { mod("WardDecayThreshold", "BASE", num, "", 0, 0, { type = "PerStat", stat = "NecroticResist", div = 2 }) }
	end,
	["^%+?(%d+) ward per second per 5%% uncapped resistances$"] = function(num)
		return { mod("WardPerSecond", "BASE", num, "", 0, 0, { type = "Multiplier", var = "UncappedResistTotal", div = 5 }) }
	end,
	["^%+?(%d+)%% ward retention per 1%% increased area$"] = function(num)
		return { mod("WardRetention", "BASE", num, "", 0, 0, { type = "Multiplier", var = "AreaInc" }) }
	end,
	-- @leb-regression-guard:frostbite-shackles-wr-per-uncapped-cold-res
	-- Frostbite Shackles unique text is "+1% Ward Retention per 2% uncapped
	-- Cold Resistance" (verified via datamined game source
	-- L27913). Emits a custom BASE mod name so CalcDefence can inject AFTER
	-- output.ColdResistTotal is computed — a PerStat tag here would (a) read
	-- the capped output.ColdResist and (b) be summed by CalcPerform L1388
	-- before calcs.defence even runs, both yielding 0 contribution.
	--
	-- Two patterns: the correct "+N% per 2%" text (new uniques*.json
	-- post-fix) and the LEGACY wrong "+N% per 100%" text (frozen in
	-- existing imported build XMLs — LETools/Maxroll importers captured
	-- the pre-fix uniques.json text verbatim). The legacy pattern also
	-- emits the same custom BASE mod with coefficient num (treating the
	-- legacy text as a typo of the canonical +1%/2% rate, not as a
	-- 50× literal interpretation), matching what LE actually computes.
	-- Spec: spec/System/TestFrostbiteShacklesWRPerUncappedColdRes_spec.lua
	["^%+?(%d+)%% ward retention per 2%% uncapped cold resistance$"] = function(num)
		return { mod("WardRetentionPerUncappedColdRes_Per2", "BASE", num) }
	end,
	["^%+?(%d+)%% ward retention per 100%% uncapped cold resistance$"] = function(num)
		-- LEGACY text from pre-fix uniques*.json, frozen in existing build XMLs.
		-- num is always 100 in this branch; collapse to the canonical 1 so the
		-- CalcDefence injection computes the same round(crTotal/2)*1 bonus.
		return { mod("WardRetentionPerUncappedColdRes_Per2", "BASE", 1) }
	end,
	-- @leb-regression-guard:fire-aura-damage-per-uncapped-fire-res
	-- "+X% Fire Aura Damage Per 1% Uncapped Fire Resistance" (Mage-42 Incinerating
	-- Aura notScalingStat). The generic "+X% <skill> damage" path parses the prefix
	-- to a Fire-Aura-scoped MORE Damage but drops "per 1% uncapped fire resistance"
	-- as residue (the modifier table only has the type-agnostic "per 1% total uncapped
	-- resistance"; the "fire" type word is consumed before it reaches the table).
	-- Anchored here (specialModList is scanned first) so the per-resistance scaling
	-- survives as Multiplier:UncappedFireResist (auto-populated in CalcSetup.lua):
	-- value * UncappedFireResist => +num% more per 1% uncapped fire resistance.
	-- MORE (multiplicative), matching the sibling "+15% Fire Aura Damage" node whose
	-- tooltip says "deals more damage (multiplicative)". Affects no current corpus
	-- build (the node is allocatable but unused in the test corpus); verified at the
	-- parse + multiplier level. Spec:
	-- spec/System/TestFireAuraDamagePerUncappedFireRes_spec.lua.
	["^%+?(%d+)%% fire aura damage per 1%% uncapped fire resistance$"] = function(num)
		return { mod("Damage", "MORE", num, "", 0, 0, { type = "SkillName", skillName = "Fire Aura" }, { type = "Multiplier", var = "UncappedFireResist" }) }
	end,
	["^%+?(%d+) ward per second with a catalyst$"] = function(num)
		return { mod("WardPerSecond", "BASE", num, "", 0, 0, { type = "Condition", var = "UsingCatalyst" }) }
	end,
	["^%+?(%d+)%% ward retention on transform$"] = function(num)
		return { mod("WardRetention", "BASE", num, "", 0, 0, { type = "Condition", var = "Transformed" }) }
	end,
	["^%+?(%d+) ward per second per 10 mana$"] = function(num)
		return { mod("WardPerSecond", "BASE", num, "", 0, 0, { type = "PerStat", stat = "Mana", div = 10 }) }
	end,
	["^(%d+)%% ward retention from increased armor$"] = function(num)
		return { mod("WardRetention", "BASE", num, "", 0, 0, { type = "Multiplier", var = "ArmourInc", div = 100 }) }
	end,
	["^(%d+) forged weapon ward per second$"] = function(num)
		return { mod("MinionModifier", "LIST", {
			mod = mod("WardPerSecond", "BASE", num),
			type = "ForgedWeapon",
		}) }
	end,
	["^(%d+) ward per second per stack$"] = function(num)
		return { mod("WardPerSecond", "BASE", num, "", 0, 0, { type = "Multiplier", var = "FirebrandStack" }) }
	end,
	["^(%d+) ward regen per second$"] = function(num)
		return { mod("WardPerSecond", "BASE", num) }
	end,
	["^(%d+) arcane shield ward per second$"] = function(num)
		return { mod("WardPerSecond", "BASE", num, "", 0, 0, { type = "Condition", var = "HaveArcaneShield" }) }
	end,
	["^(%d+) holy symbol ward per second$"] = function(num)
		return { mod("WardPerSecond", "BASE", num, "", 0, 0, { type = "Condition", var = "HaveActiveSymbol" }) }
	end,
	-- Julra's Obsession: stats on gloves also apply to minions.
	-- Recognition only: marker mod consumed by CalcSetup to replicate
	-- non-attribute glove mods onto the minion modDB.
	["^%+?(%d+)%% stats on your gloves also apply to your minions$"] = function(num)
		return { mod("StatsApplyToMinions_Gloves", "BASE", num) }
	end,
	-- Bow Mastery unique item mod
	["^bow mastery: (%d+)%% increased damage while using a bow$"] = function(num)
		return { mod("Damage", "INC", num, "", 0, 0, { type = "Condition", var = "UsingBow" }) }
	end,
	-- Ward on melee hit (item affix). resourceGainMode pattern, same as the
	-- ward-aware chance-gain catch-alls near nsAny
	-- (@leb-regression-guard:resource-gain-mode-chance-averaging): emit WardOnHit
	-- gated by Average/Max conditions; Min => 0. Kept as its own pattern because
	-- the generic "on hit$" catch-all does not match "on melee hit".
	["^(%d+)%% chance to gain (%d+) ward on melee hit$"] = function(num, chance, amount)
		chance, amount = tonumber(chance), tonumber(amount)
		return {
			mod("WardOnHit", "BASE", amount * chance / 100, "", 0, 0, { type = "Condition", var = "AverageResourceGain" }),
			mod("WardOnHit", "BASE", amount * math.ceil(chance / 100), "", 0, 0, { type = "Condition", var = "MaxResourceGain" }),
		}
	end,
	-- Chance to Gain [BuffName] for [Duration] seconds
	-- e.g. "20% chance to gain Unholy Might for 4 seconds"
	["^(%d+)%% chance to gain (.+) for (%d+) seconds$"] = function(line, chance, buffName, duration)
		local buffVar = buffName:gsub("%s+", ""):gsub("[^%a%d_]", "")
		return {
			mod("ChanceToGain" .. buffVar, "BASE", tonumber(chance)),
			mod(buffVar .. "Duration", "BASE", tonumber(duration)),
		}
	end,
	-- Capped PerStat: e.g. "+2 Dodge Rating per 1 Intelligence, up to +100" (Spellblade: Illusory Combatant)
	["^%+(%d+) dodge rating per 1 intelligence, up to %+(%d+)$"] = function(num, rate, cap)
		return { mod("EvasionPerInt", "BASE", tonumber(rate)), mod("EvasionPerIntCap", "BASE", tonumber(cap)) }
	end,
	-- Runemaster: Cerulean Runestones 6-point bonus
	["^(%d+)%% mana gained as endurance threshold$"] = function(num)
		return { mod("ManaAsEnduranceThreshold", "BASE", tonumber(num)) }
	end,
	-- Primalist/Rogue/Sentinel tree: "X% Max[imum] Health Gained as Endurance Threshold"
	["^%+?(%d+)%% max health gained as endurance threshold$"] = function(num)
		return { mod("LifeAsEnduranceThreshold", "BASE", tonumber(num)) }
	end,
	["^%+?(%d+)%% maximum health gained as endurance threshold$"] = function(num)
		return { mod("LifeAsEnduranceThreshold", "BASE", tonumber(num)) }
	end,
	["^%+?(%d+)%% of max health gained as endurance threshold$"] = function(num)
		return { mod("LifeAsEnduranceThreshold", "BASE", tonumber(num)) }
	end,
	["^%+?(%d+)%% of maximum health gained as endurance threshold$"] = function(num)
		return { mod("LifeAsEnduranceThreshold", "BASE", tonumber(num)) }
	end,
	-- @leb-regression-guard: life-as-ward-decay-threshold-conversion
	-- Validation provenance is retained in maintainer notes.
	["^%+?(%d+)%% max health gained as ward decay threshold$"] = function(num)
		return { mod("LifeAsWardDecayThreshold", "BASE", tonumber(num)) }
	end,
	["^%+?(%d+)%% maximum health gained as ward decay threshold$"] = function(num)
		return { mod("LifeAsWardDecayThreshold", "BASE", tonumber(num)) }
	end,
	["^%+?(%d+)%% of max health gained as ward decay threshold$"] = function(num)
		return { mod("LifeAsWardDecayThreshold", "BASE", tonumber(num)) }
	end,
	["^%+?(%d+)%% of maximum health gained as ward decay threshold$"] = function(num)
		return { mod("LifeAsWardDecayThreshold", "BASE", tonumber(num)) }
	end,
	-- Strong Mind (unique): "200% of maximum mana added as stun avoidance".
	-- @leb-regression-guard: strong-mind-mana-as-stun-avoidance
	-- This is a tooltipDescription-only property in item data (no numeric mod
	-- entry), so the datamining extraction dropped it and LEB applied 0. We emit
	-- a BASE ManaAsStunAvoidance stat that CalcDefence converts against max Mana,
	-- mirroring the Mana/Life-AsEnduranceThreshold contract above.
	["^%+?(%d+)%% of maximum mana added as stun avoidance$"] = function(num)
		return { mod("ManaAsStunAvoidance", "BASE", tonumber(num)) }
	end,
	["^%+?(%d+)%% of max mana added as stun avoidance$"] = function(num)
		return { mod("ManaAsStunAvoidance", "BASE", tonumber(num)) }
	end,
	["^%+?(%d+)%% maximum mana added as stun avoidance$"] = function(num)
		return { mod("ManaAsStunAvoidance", "BASE", tonumber(num)) }
	end,
	["^%+?(%d+)%% mana added as stun avoidance$"] = function(num)
		return { mod("ManaAsStunAvoidance", "BASE", tonumber(num)) }
	end,
	-- Sentinel Defiance: "+1 Endurance Threshold Per 2% Uncapped Elemental Resistance"
	["^%+?(%d+) endurance threshold per 2%% uncapped elemental resistance$"] = function(num)
		return { mod("EnduranceThresholdPerUncappedEleRes", "BASE", tonumber(num)) }
	end,
	-- Stone Shield (unique): "+1% Block Chance per 2% Endurance above the Cap"
	["^%+?(%d+)%% block chance per (%d+)%% endurance above the cap$"] = function(_, num, div)
		return { mod("BlockChance", "BASE", tonumber(num), { type = "PerStat", stat = "EnduranceOverCap", div = tonumber(div) }) }
	end,
	-- Null Portent (unique body armour): the over-cap-resistance damage mitigation is
	-- authored as TWO separate mod lines that together form one mechanic:
	--   "1% less Damage Taken per 2% Resistance above the normal cap"     (rate: N% per M%)
	--   "20% Maximum Less Damage Taken per 2% Resistance above the normal cap"  (cap: 20%)
	-- @leb-regression-guard: null-portent-less-damage-taken-per-resist-overcap
	-- We cannot use a PerStat tag (it can't express the Maximum cap alongside the
	-- per-type <Type>ResistOverCap, and the two lines carry the rate/cap separately),
	-- so each line emits a BASE marker stat. CalcDefence combines them AFTER the
	-- per-type resist over-cap totals are known and injects a per-type
	-- <Type>DamageTaken MORE (multiplicative, per spec). Mirrors the Urzil's Pride /
	-- Boneclamor "per M% resistance" injection family (all floor at integer steps).
	-- These anchored rules replace the pre-fix ModCache rows (deleted in the same
	-- commit) that baked a bare `DamageTaken MORE -1` with dropped " per 2% Resistance
	-- above the normal cap " residue and no over-cap scaling.
	-- Spec: spec/System/TestNullPortentOvercapDamageTaken_spec.lua
	["^(%d+)%% less damage taken per (%d+)%% resistance above the normal cap$"] = function(_, num, div)
		return {
			mod("LessDamageTakenPerResOverCapNum", "BASE", tonumber(num)),
			mod("LessDamageTakenPerResOverCapDiv", "BASE", tonumber(div)),
		}
	end,
	["^(%d+)%% maximum less damage taken per (%d+)%% resistance above the normal cap$"] = function(_, num)
		return { mod("LessDamageTakenPerResOverCapMax", "BASE", tonumber(num)) }
	end,
	-- Urzil's Pride (unique): "1% Increased Mana Regeneration per 2% Uncapped Lightning Resistance"
	-- @leb-regression-guard: urzils-pride-mana-regen-per-uncapped-lightning-res
	-- Game behaviour is floored at integer steps (LETools matches this); we cannot use a
	-- PerStat tag because ModStore.GetStat uses continuous scaling (intentional; see comment
	-- at ModStore.lua:414). Instead we emit a BASE stat that CalcDefence reads after the
	-- resist totals are computed, floors div, and injects the ManaRegen INC mod.
	["^(%d+)%% increased mana regeneration per 2%% uncapped lightning resistance$"] = function(num)
		return { mod("ManaRegenIncPerUncappedLightningRes_Per2", "BASE", tonumber(num)) }
	end,
	-- Paladin: "+N Maximum Symbols" (Polygram, Tetragram etc.)
	["^%+?(%d+) maximum symbols?$"] = function(num)
		return { mod("MaximumSymbols", "BASE", tonumber(num)) }
	end,
	-- Boneclamor Barbute (unique helmet): "1 Ward per Second per 3% uncapped Necrotic Resistance"
	-- @leb-regression-guard: boneclamor-barbute-ward-per-uncapped-necrotic-res
	-- Game behaviour is floored at integer steps (matches LETools display). Like
	-- Urzil's Pride, we cannot use a PerStat tag because ModStore.GetStat is
	-- continuous (intentional; ModStore.lua:414). Emit a BASE stat that
	-- CalcDefence reads after NecroticResistTotal is computed, floors div, and
	-- adds the result directly to output.WardPerSecond (before the primary Ward
	-- formula at CalcDefence.lua:432 consumes WardPerSecond).
	["^(%d+) ward per second per 3%% uncapped necrotic resistance$"] = function(num)
		return { mod("WardPerSecondPerUncappedNecroticRes_Per3", "BASE", tonumber(num)) }
	end,

	-- Chthonic Fissure tree node 22 "Fissure of Wrath" (ch0fs-22):
	-- "+N Fissure Spell Damage per 2% Ignite Chance". Game text
	-- (sharedassets1.assets tree 476002 node 22): "...per 2% ignite chance.
	-- This effect scales with bleed or poison if the Fissure is converted to
	-- physical or poison respectively." altText: "Ailment chance is counted
	-- before being converted." The chance is UNCAPPED (output.<X>Chance caps at
	-- 100, CalcOffence:1954) and skill-scoped, so we cannot use a PerStat tag
	-- (GetStat reads the capped output). Emit a marker BASE mod that CalcOffence
	-- reads before the base-damage assembly; CalcOffence selects which uncapped
	-- ailment chance to scale on based on the Fissure's actual conversion
	-- (fire->physical from Blood Gulch ch0fs-28 -> bleed; otherwise ignite),
	-- then injects the added spell damage (x damage effectiveness).
	-- @leb-regression-guard:fissure-of-wrath-ailment-scaled-added-spell-damage
	["^%+?(%d+) fissure spell damage per 2%% ignite chance$"] = function(num)
		return { mod("FissureSpellDamagePerUncappedAilment_Per2", "BASE", tonumber(num)) }
	end,
	-- Runemaster: Sanguine Runestones 6-point bonus, and the
	-- "Health Regen also applies to Ward" affix family on items
	-- and idols. The `%+?` is critical: without it, the affix
	-- form ("+2% Health Regen also applies to Ward", ...) fell
	-- through to the generic "+N% health regen" handler and
	-- silently emitted LifeRegen INC while the
	-- LifeRegenAppliesToWard BASE that CalcDefence.lua:641, :796
	-- consumes never fired.
	-- @leb-regression-guard:health-regen-applies-to-ward-plus-prefix
	["^%+?(%d+)%% of health regen also applies to ward$"] = function(num)
		return { mod("LifeRegenAppliesToWard", "BASE", tonumber(num)) }
	end,
	["^%+?(%d+)%% health regen also applies to ward$"] = function(num)
		return { mod("LifeRegenAppliesToWard", "BASE", tonumber(num)) }
	end,
	-- Rusted Cleaver unique: Intelligence gains a value equal to Strength
	["^%+1 intelligence equals strength$"] = { flag("IntEqualsStr") },

	-- The Butcher's Crown (unique helmet, uniqueID=449): zero player mana regen.
	-- @leb-regression-guard: butchers-crown-no-mana-regen
	-- Game tooltip text is "You do not Regenerate Mana" (uniques.json
	-- tooltipDescriptions[0]). LEB unique JSON historically uses the variant
	-- "100% Disabled Mana Regen"; both forms are recognised so future text
	-- regenerations don't silently re-introduce the bug. Without this the
	-- BASE_MORE form ("100%") matches and the trailing "Disabled Mana Regen"
	-- collapses into a +100 BASE ManaRegen mod (boost), the opposite of intent.
	-- The NoManaRegen flag is consumed at CalcDefence.lua:602 ("if modDB:Flag(
	-- nil, 'No'..resource..'Regen') then output.ManaRegen = 0").
	-- Test: spec/System/TestModParse_spec.lua "butchers-crown-no-mana-regen".
	-- See REGRESSION_GUARDS.md "butchers-crown-no-mana-regen".
	["^you do not regenerate mana$"] = { flag("NoManaRegen") },
	["^100%% disabled mana regen$"] = { flag("NoManaRegen") },

	-- Category A: "X% increased Damage for Totems" (distinct from "per totem")
	["^%+?([%d%.]+)%% increased damage for totems$"] = function(num)
		return { mod("Damage", "INC", num, "", 0, 0, { type = "Scope", scope = "totem" }) }
	end,

	-- Lethal Mirage prefix family (idol affix, ModItem.json statOrder 537):
	-- "+N Mirages created by Lethal Mirage" pairs with a Mana Efficiency
	-- line on the same affix. Without this anchor the line parses to an
	-- empty modList with empty residue -- the mirage-count half of the
	-- affix silently produces nothing. The MirageCount BASE stat is the
	-- F11 calc-consumer target (calcs.mirages in src/Modules/CalcMirages.lua
	-- currently hardcodes a single mirage; F11 will read this stat).
	-- @leb-regression-guard:mirages-created-by-lethal-mirage
	["^%+?(%d+) mirages? created by lethal mirage$"] = function(num)
		return { mod("MirageCount", "BASE", tonumber(num), "", 0, 0, { type = "SkillName", skillName = "Lethal Mirage" }) }
	end,

	-- Cooldown-recovered-on-hit family (2 known sources, both unique):
	--   Black Blade of Chaos (uniqueID=339, Mod[4]): Lethal Mirage variant
	--   Razorfall          (uniqueID=337, Mod[4]): Aerial Assault variant
	-- Game-file source (datamined game source CharacterMutator):
	--   L96718 lethalMirageRemainingCooldownRecoveredOnMeleeHitUpTo12TimesPerUse
	--   L96712 chanceToRecover8pOfRemainingAerialAssaultCooldownOnThrowingHit
	-- Both fields are plain floats on CharacterMutator with a private
	-- "SinceLast<Skill>Use" int counter that resets on each cast of the
	-- gating skill. The cap (12 / 3) is a const int per skill. Both
	-- ModCache entries were silent-failure no-ops before this anchor.
	--
	-- v1 surface-only consumer: emit a paired
	--   CooldownRecoveryOnHit          BASE pct (effective, chance-folded)
	--   CooldownRecoveryOnHitMaxPerCast BASE cap (12 or 3)
	-- both tagged with SkillName='<X>' so the breakdown row only shows
	-- when the corresponding skill is the active calc target. Real
	-- cooldown-projection math is deferred to v2 (would need per-cast
	-- hit-window simulation; see open question in REGRESSION_GUARDS.md
	-- entry cooldown-recovered-on-hit-consumer).
	--
	-- Razorfall's "(N)% chance to recover 8%" is folded into a single
	-- effective value (chance * 8 / 100); the literal 8% is not stored
	-- separately since the game's `chanceToRecover8p...` field is also
	-- a single float (no per-source chance/value split).
	-- @leb-regression-guard:cooldown-recovered-on-hit-consumer
	-- Dispatch convention: specialMod(tonumber(cap[1]), unpack(cap)) so handlers
	-- with N captures take (numericFirst, rawFirst, rawSecond, ...). For two
	-- captures the cap-string is the THIRD arg, not the second.
	["^%+?([%d%.]+)%% of lethal mirage's remaining cooldown recovered on melee hit %(up to (%d+) times%)$"] = function(_, pctStr, capStr)
		return {
			mod("CooldownRecoveryOnHit", "BASE", tonumber(pctStr), "", 0, 0, { type = "SkillName", skillName = "Lethal Mirage" }),
			mod("CooldownRecoveryOnHitMaxPerCast", "BASE", tonumber(capStr), "", 0, 0, { type = "SkillName", skillName = "Lethal Mirage" }),
		}
	end,
	-- @leb-regression-guard:cooldown-recovered-on-hit-consumer
	["^%+?([%d%.]+)%% chance to recover 8%% of aerial assault's remaining cooldown on throwing hit %(up to (%d+) times%)$"] = function(_, chanceStr, capStr)
		local effective = tonumber(chanceStr) * 8 / 100
		return {
			mod("CooldownRecoveryOnHit", "BASE", effective, "", 0, 0, { type = "SkillName", skillName = "Aerial Assault" }),
			mod("CooldownRecoveryOnHitMaxPerCast", "BASE", tonumber(capStr), "", 0, 0, { type = "SkillName", skillName = "Aerial Assault" }),
		}
	end,

	-- @leb-regression-guard:tabi-of-dusk-and-dawn-flags
	-- Validation provenance is retained in maintainer notes.
	["^shadow rend no longer moves you$"] = function()
		return { flag("ShadowRendNoPlayerMovement", { type = "SkillName", skillName = "Shadow Rend" }) }
	end,
	["^shadow rend always manifests a melee shadow in front of you and a bow shadow behind you$"] = function()
		return { flag("ShadowRendAlsoCastsOtherWeaponVersion", { type = "SkillName", skillName = "Shadow Rend" }) }
	end,

	-- Orb Weaver's Fang (uniqueID=405, sword): single-source conditional
	-- self-mult mod -- "+100% Stats on this item are doubled for 3 seconds
	-- after hitting a boss or rare enemy that is low life". The semantics
	-- require a per-item-scope multiplier that conditionally doubles every
	-- OTHER mod emitted by THIS unique piece (the other 4 mod lines on
	-- Orb Weaver's Fang: +Melee Damage, Crit, Movement Speed, Dodge
	-- Rating). LEB has no per-item-scope multiplier infra today; the
	-- closest precedent is the F4 ", doubled for shadow attack" trailing
	-- clause (modTagList Condition+mult=2) which scopes by Condition tag
	-- on the SAME mod line, not across sibling lines on the same item.
	--
	-- Even with the infra wired, the gate ("after hitting a boss or rare
	-- enemy that is low life") is a transient 3s buff with a niche
	-- trigger -- average DPS contribution would require a Config-tab
	-- uptime input. v1 parser-only anchor matches the Tabi of Dusk and
	-- Dawn / W6 Ward-per-Second-Duration precedent: recognise-but-emit-
	-- nothing, clear the mangled residue, defer combat-loop attribution.
	--
	-- Pattern uses %d+ for the duration so future version bumps (3->5s
	-- etc.) don't silently re-introduce the mangled residue. The leading
	-- "+100%" is matched literally because the source line is hand-
	-- authored on a single unique with no tier roll.
	-- @leb-regression-guard:orb-weavers-fang-descriptive
	["^%+?100%% stats on this item are doubled for %d+ seconds? after hitting a boss or rare enemy that is low life$"] = function() return {} end,

	-- @leb-regression-guard:kuzons-fury-reforged-burning-dagger-chance
	-- @leb-regression-guard:proc-rate-limit-metadata-v1
	-- See REGRESSION_GUARDS.md "proc-rate-limit-metadata-v1".
	-- Validation provenance is retained in maintainer notes.
	["^%+?([%d%.]+)%% chance to throw a burning dagger when you use a melee fire attack and hit at least one enemy, doubled for dancing strikes %(up to 4 times per second%)$"] = function(num)
		return { mod("BurningDaggerChanceOnMeleeFire", "BASE", num, "", 0, 0,
			{ type = "Condition", var = "DancingStrikes", mult = 2 },
			{ type = "RateLimit", limit = 4, interval = 1, var = "BurningDaggerOnMeleeFire" }) }
	end,
	-- Tier 7 outlier: `{rounding:Integer}+(1-1.2)` renders as "+1" after
	-- integer rounding, no `%` suffix. Deferred until game-file semantics
	-- are confirmed (fraction vs literal +1). Returning {} clears the
	-- residue without emitting a mod; revisit in a follow-up task.
	["^%+?1 chance to throw a burning dagger when you use a melee fire attack and hit at least one enemy, doubled for dancing strikes %(up to 4 times per second%)$"] = function() return {} end,
}

-- Escape Lua pattern specials (non-word chars)
local function escPat(s) return (s:gsub("(%W)", "%%%1")) end

-- Per-skill idol affix patterns (recognised with proper SkillName tags).
-- Only A (damage) and H (cooldown) are registered per-skill since they integrate
-- with DPS calcs via SkillName. Trigger-chance / resource-gain mods are intentionally
-- left unrecognised for now to avoid bloating specialModList with thousands of patterns.
-- Skill names that collide with damage types / keywords — skip to avoid hijacking
-- generic parsing of e.g. "increased poison damage".
--
-- @leb-regression-guard:skill-scoped-damage-idol-tag
-- "(N)% increased <Skill> Damage" idol affixes (e.g. ShutFackUp's
-- "(30-100)% Increased Fire Aura Damage" prefix) MUST parse to a single
-- `Damage INC` mod carrying a `SkillName="<Skill>"` tag, so the increase
-- lands ONLY on that skill's cfg and never leaks globally or onto other
-- skills. This is the ② sub-point of the Fire Aura DPS gap: the idol mod was
-- (incorrectly) believed dropped, but it is parsed + tagged here and reaches
-- env.modDB scoped — it produces no DPS today only because Fire Aura is a
-- triggered skill absent from activeSkillList (handled separately by ④
-- trigger injection). Verified on ShutFackUp lv85 Spellblade: the idol
-- "Increased Fire Aura Damage" sums to 71 under a Fire Aura cfg vs 19
-- (global only) under Shatter Strike / nil cfg. The patterns below ("increased
-- <skill> damage$" / "increased damage with <skill>$") are the registration
-- site; skillNameByLower (built from data.skills) supplies the canonical name.
-- See REGRESSION_GUARDS.md "skill-scoped-damage-idol-tag".
local skillNameBlacklist = { bleed = true, poison = true }
for lower, canonical in pairs(skillNameByLower) do
	if not skillNameBlacklist[lower] then
		local esc = escPat(lower)
		specialModList["^%+?([%d%.]+)%% increased damage with " .. esc .. "$"] = function(num)
			return { mod("Damage", "INC", num, "", 0, 0, { type = "SkillName", skillName = canonical }) }
		end
		specialModList["^%+?([%d%.]+)%% increased " .. esc .. " damage$"] = function(num)
			return { mod("Damage", "INC", num, "", 0, 0, { type = "SkillName", skillName = canonical }) }
		end
		specialModList["^%+?([%d%.]+)%% increased damage with " .. esc .. " per active shadow$"] = function(num)
			return { mod("Damage", "INC", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Multiplier", var = "ActiveShadow" }) }
		end
		specialModList["^%+?([%d%.]+)%% increased cooldown recovery speed for " .. esc .. "$"] = function(num)
			return { mod("CooldownRecovery", "INC", num, "", 0, 0, { type = "SkillName", skillName = canonical }) }
		end
		specialModList["^%+?([%d%.]+)%% increased cooldown recovery speed of " .. esc .. "$"] = function(num)
			return { mod("CooldownRecovery", "INC", num, "", 0, 0, { type = "SkillName", skillName = canonical }) }
		end
	end
end

-- Buff-effect recognition (named stats only; no DPS integration yet)
local knownBuffsOnYou = { "Haste", "Frenzy", "Haven", "Rebuke", "Unholy Might", "Smoke Bomb" }
for _, buff in ipairs(knownBuffsOnYou) do
	local esc = escPat(buff:lower())
	local bVar = buff:gsub("%s+", ""):gsub("[^%a%d_]", "")
	-- @leb-regression-guard:effect-of-buff-signed-value
	-- Capture the optional sign ([%+%-]?) INSIDE the number group (not a bare "%+?"
	-- anchor): a reduced roll renders "-7% Effect of Frenzy on You", and a "%+?"-only
	-- anchor both failed to match the "-" (SILENT FAILURE) and, if the sign sat outside
	-- the capture, would have flipped a reduction into an increase. tonumber("-7") = -7
	-- so the reduction models correctly.
	specialModList["^([%+%-]?[%d%.]+)%% increased effect of " .. esc .. " on you$"] = function(num)
		return nsList(mod(bVar .. "Effect", "INC", tonumber(num)))
	end
	-- @leb-regression-guard:effect-of-buff-on-you-bare-alias
	-- ALIAS: bare "+N% Effect of <Buff> on You" (NO "increased" word) is the SAME
	-- stat as the "increased" form above. The datamine affix text is
	-- "(N)% increased Effect of Haste on You" / "... of Frenzy on You"
	-- (src/Data/ModItem_1_4.json L75499+, L75643+), and the "increased" rendering
	-- already parses to <bVar>Effect INC (ModCache proves e.g.
	-- "14% increased Effect of Haste on You" -> HasteEffect INC 14). LE also renders
	-- these rolls WITHOUT the "increased" word and WITH a "+" prefix
	-- ("+14% Effect of Haste on You"); those rows were SILENT FAILURES -- ModCache
	-- baked {{}," Effect of  on You "} (the buff name stripped by the skill-name
	-- post-scan) with an empty modList. Same modName, same INC semantics, same
	-- consumer: CalcPerform.lua:1216 / :1234
	--   skillModList:Sum("INC", skillCfg, buff.name:gsub(" ", "").."Effect")
	-- scales the active Haste/Frenzy buff's modList by (1 + inc/100). Scoped to the
	-- knownBuffsOnYou list (only real buff names), and "%% effect" cannot match the
	-- "%% increased effect" string above -- so no collision. Whole-line ^...$ so
	-- parseMod leaves no `extra` residue (PassiveTree:ProcessStats never drops it).
	-- Spec: spec/System/TestEffectOfBuffAlias_spec.lua. See REGRESSION_GUARDS.md.
	specialModList["^([%+%-]?[%d%.]+)%% effect of " .. esc .. " on you$"] = function(num)
		return nsList(mod(bVar .. "Effect", "INC", tonumber(num)))
	end
	-- @leb-regression-guard:fangs-berserker-frenzy-effect
	-- E: "N% increased Effect of <Buff> while Dual Wielding" and "... per Strength".
	-- Fangs of the Berserker (unique 446, src/Data/Uniques/uniques_1_4.json) carries
	-- "(12-20)% increased Effect of Frenzy while Dual Wielding" and
	-- "0.5% increased Effect of Frenzy per Strength" (datamine: unique 446 mod idx 6
	-- val 0.12/max 0.20, mod idx 7 val 0.005/max 0.01 -- the per-Str coefficient is a
	-- 0.5%->1% rollable, so the number is CAPTURED from the string, never hardcoded).
	-- The "on you" handlers above only anchor the " on you" suffix; the "while dual
	-- wielding" / "per strength" tails fell through -- "Frenzy" is stripped by the
	-- skill-name post-scan, leaving a bare " Effect of " residue, so ModCache baked
	-- {{}," Effect of   "} (empty modList, SILENT FAILURE). Same stat, same INC
	-- semantics, same consumer: CalcPerform.lua:1305 / :1323
	--   skillModList:Sum("INC", skillCfg, buff.name:gsub(" ", "").."Effect")
	-- scales the active Frenzy buff's modList by (1 + inc/100). The DualWielding
	-- Condition tag (modTagList "while dual wielding", ModParser.lua:952) and the
	-- PerStat:Str tag (Attributes[2]="Str", Global.lua:97; precedent ModCache.lua:10280
	-- "... per player Attunement" -> FrenzyEffect INC + PerStat) are the standard tags,
	-- carried inline on the mod (createMod treats a leading table arg as a tag, leaving
	-- source=nil -- NOT "" -- so a strict `not extra` consumer keeps the flag). Whole-
	-- line ^...$ so parseMod leaves no residue. The stale ModCache rows (:10026 / :11708)
	-- are DELETED so both re-parse live. Spec: TestFangsBerserkerFrenzyEffect_spec.lua.
	specialModList["^([%+%-]?[%d%.]+)%% increased effect of " .. esc .. " while dual wielding$"] = function(num)
		return nsList(mod(bVar .. "Effect", "INC", tonumber(num), { type = "Condition", var = "DualWielding" }))
	end
	specialModList["^([%+%-]?[%d%.]+)%% increased effect of " .. esc .. " per strength$"] = function(num)
		return nsList(mod(bVar .. "Effect", "INC", tonumber(num), { type = "PerStat", stat = "Str" }))
	end
	-- @leb-regression-guard:exulis-haste-effect-per-rampancy
	-- Exulis (Oracle Amulet, unique) carries "5% Increased effect of Haste per 10
	-- Rampancy" (src/Data/Uniques/uniques_1_4.json L9476, uniques.json L10662). The
	-- "on you" / "per strength" / "while dual wielding" handlers above only anchor
	-- their own tails; the " per N rampancy" tail fell through, so "Haste" was
	-- stripped by the skill-name post-scan and ModCache baked
	-- {{}," effect of   "} (empty modList, SILENT FAILURE: ModCache.lua:14683).
	-- Same stat, same INC semantics as the on-you form: <bVar>Effect INC scaled by
	-- PerStat{Rampancy, div=N}. BOTH the coefficient (5) and the divisor (10) are
	-- CAPTURED from the string -- nothing hardcoded, no curve-fit. Rampancy is the
	-- Vit-converted Season-4 attribute (ModParser.lua:1816 registers the stat;
	-- CalcPerform.lua:344 converts Vit->Rampancy); PerStat{stat="Rampancy"} reads
	-- its runtime value exactly the way the Guile/Brutality/Madness PerStat mods do
	-- (CalcSetup.lua:870, all Season-4 converted attrs). NON-DPS: Haste is
	-- movement-only in-game (datamine ailment id 33 "Increases movement speed",
	-- single buff property 9 = MovementSpeed, increasedValue 0.30, dealsDamage=false)
	-- and LEB models it as MovementSpeed INC 30 (ConfigOptions.lua:511) -- so
	-- HasteEffect scales movement speed only, zero per-hit / DPS impact. This handler
	-- is parse-completion (kills the silent fail), NOT a DPS change. Consumer:
	-- CalcPerform.lua Sum("INC", skillCfg, buff.name:gsub(" ","").."Effect") scales
	-- the active Haste buff's modList by (1 + inc/100). Whole-line ^...$ so parseMod
	-- leaves no residue. The stale ModCache row is DELETED so it re-parses live.
	-- Spec: spec/System/TestExulisHasteEffectRampancy_spec.lua. See REGRESSION_GUARDS.md.
	-- Calling convention (parseMod L6298): specialMod(tonumber(cap[1]), unpack(cap))
	-- -> args are (coefficientAsNumber, cap[1], cap[2], ...). The captured DIVISOR is
	-- cap[2], so it arrives as the THIRD parameter; the second (_) is the raw cap[1]
	-- re-passed. Mirrors the "chance to gain <Buff> for N seconds when you Echo"
	-- handler's function(num, chance, duration) signature.
	specialModList["^([%+%-]?[%d%.]+)%% increased effect of " .. esc .. " per (%d+) rampancy$"] = function(num, _, per)
		return nsList(mod(bVar .. "Effect", "INC", tonumber(num), { type = "PerStat", stat = "Rampancy", div = tonumber(per) }))
	end
	-- D: Chance to gain <Buff> for N seconds when you Echo an ability
	specialModList["^%+?(%d+)%% chance to gain " .. esc .. " for (%d+) seconds? when you echo an ability$"] = function(num, chance, duration)
		return nsList(
			mod("ChanceToGain" .. bVar .. "OnEcho", "BASE", tonumber(chance)),
			mod(bVar .. "Duration", "BASE", tonumber(duration))
		)
	end
	-- D: Chance to gain <Buff> for N seconds when you Summon a Totem
	specialModList["^%+?(%d+)%% chance to gain " .. esc .. " for (%d+) seconds? when you summon a totem$"] = function(num, chance, duration)
		return nsList(
			mod("ChanceToGain" .. bVar .. "OnTotemSummon", "BASE", tonumber(chance)),
			mod(bVar .. "Duration", "BASE", tonumber(duration))
		)
	end
end

-- @leb-regression-guard:chronowarp-buff-conditional
-- Chronowarp is Wrongwarp's (unique 310) buff, granted for 10s on Teleport/Transplant
-- cast. It is NOT in knownBuffsOnYou: that list drives "<N>% increased Effect of <Buff>
-- on You" handlers, and no LE stat scales Chronowarp's effect -- Chronowarp's numbers
-- live only in this one item line, so it needs its own whole-line handler.
-- The line is game text: unique 310 tooltipDescriptions[1] "Chronowarp grants 35%
-- increased cast speed and movement speed" (tooltipEntries [128,129,130,0,1,131] ->
-- this is display line 2 of 6; in-game screenshot verified 6/6).
-- The 35 is CAPTURED from the string, never hardcoded -- if LE rebalances the buff the
-- data line changes and this handler follows it. No curve-fit.
-- CONDITIONAL, not always-on: Chronowarp has a 10s duration gated behind a Teleport/
-- Transplant cast (which desc3 floors at a 3s minimum cooldown), so uptime is a build/
-- playstyle question, not a constant. Both mods carry {Condition:Chronowarp}; the
-- ConfigOptions "Do you have Chronowarp?" check (var conditionChronowarp) sets the FLAG.
-- That option is gated by ifCond="Chronowarp", which reads mainEnv.conditionsUsed
-- (ConfigTab.lua:791-797) -- i.e. it only appears once a mod TAGGED with the condition
-- exists, which is exactly this handler firing. So the option is invisible (and the buff
-- inert) unless Wrongwarp is equipped. Mirrors the Haste idiom (ConfigOptions.lua:524).
-- Stat names match the generic parse chain: cast speed = "Speed" INC with ModFlag.Cast
-- (modNameList ModParser.lua:606; ModCache proves "10% increased Cast Speed" ->
-- Speed/INC/flags=256), movement speed = "MovementSpeed" INC flags=0 (ModCache
-- "30% increased Movement Speed"). NOT nsList: these are real, DPS-integrated mods
-- (cast speed feeds per-hit rate), so marking them notSupported would be a lie.
-- Whole-line ^...$ so parseMod leaves no `extra` residue.
-- Spec: spec/System/TestWrongwarpChronowarp_spec.lua. See REGRESSION_GUARDS.md.
specialModList["^chronowarp grants ([%d%.]+)%% increased cast speed and movement speed$"] = function(num)
	return {
		mod("Speed", "INC", tonumber(num), "", ModFlag.Cast, 0, { type = "Condition", var = "Chronowarp" }),
		mod("MovementSpeed", "INC", tonumber(num), "", 0, 0, { type = "Condition", var = "Chronowarp" }),
	}
end

-- Recognition-only: trigger-based resource gains (E)
-- e.g. "3 Mana Gained when you use Vengeance and hit an enemy"
--      "+4 Mana Gained When you directly cast Smite"
for lower, canonical in pairs(skillNameByLower) do
	if not skillNameBlacklist[lower] then
		local esc = escPat(lower)
		specialModList["^%+?(%d+) mana gained when you use " .. esc .. " and hit an enemy$"] = function(num)
			return nsList(mod("ManaGainOnUse_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }))
		end
		specialModList["^%+?(%d+) mana gained when you directly cast " .. esc .. "$"] = function(num)
			return nsList(mod("ManaGainOnCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }))
		end
		specialModList["^%+?(%d+) ward gained when you use " .. esc .. "$"] = function(num)
			return nsList(mod("WardGainOnUse_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }))
		end
		specialModList["^%+?(%d+) health gained when you use " .. esc .. "$"] = function(num)
			return nsList(mod("HealthGainOnUse_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }))
		end
		-- G: Chance to cast <skill> on trigger
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on kill$"] = function(num)
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnKill" }))
		end
		-- @leb-regression-guard:trigger-chance-to-cast-on-hit-bridge
		-- "X% chance to cast <skill> on hit": bridge into the existing trigger
		-- pipeline. When the triggered skill exists in data.skills we emit the
		-- FUNCTIONAL, global ChanceToTriggerOnHit_<skillId> BASE mod (no SkillName
		-- scope) which the CalcSetup grantedTriggeredSkills loop sums per source
		-- skill; CalcTriggers then derives the trigger rate from the source skill's
		-- hit rate x this chance (uptime build-derived, not fabricated). Absent from
		-- data (e.g. data-blocked sub-skills) -> recognition-only ChanceToCast_ fallback.
		-- Scope note: only the bare "on hit$" form is bridged. Rate-capped variants
		-- ("... up to N times per M seconds", cooldowns) and tag-stripped forms
		-- ("on melee hit") are intentionally NOT matched here - their rate cannot be
		-- derived without fabrication and is handled separately. See the trigger
		-- design note (LEB-0.13.2) for the per-condition rollout plan.
		local triggerSkillId = skillIdByLower[lower]
		-- @leb-regression-guard:trigger-aura-exclude-discrete-bridges
		-- baseFlags of the triggered skill, hoisted here so the on-hit / on-melee-hit /
		-- on-spell-cast bridges can exclude pure auras (see below). triggerSkillIsHit:
		-- a discrete-hit skill (baseFlags.hit). triggerSkillIsAura: a pure aura/DoT
		-- (baseFlags {dot,duration}, NO hit — e.g. Fire Aura {spell,dot,duration}).
		-- A pure aura "Is not a Hit", so modelling it through the discrete
		-- ChanceToTriggerOn*_ path would compute discrete hit-DPS for a skill that has
		-- none — it needs the aura-uptime / stack model instead. The cooldown path
		-- (globalCappedTrigger) routes auras to AuraTriggerRatePerSecond_ (it has a
		-- parse-time rate 1/K); the on-hit/melee/spell-cast bridges have NO parse-time
		-- rate (rate = source hit/cast rate x chance, derived in CalcSetup), so the
		-- honest defensive fallback is recognition-only (ChanceToCast_), NOT discrete.
		-- There is currently no in-data aura-on-hit affix; this is a defensive guard so
		-- one cannot silently be discrete-modelled. If such data appears, the correct
		-- extension is a hit-rate-driven aura-stack injection in CalcSetup.
		local triggerSkillBaseFlags = triggerSkillId and data.skills[triggerSkillId] and data.skills[triggerSkillId].baseFlags
		local triggerSkillIsHit = triggerSkillBaseFlags and triggerSkillBaseFlags.hit
		local triggerSkillIsAura = triggerSkillBaseFlags and triggerSkillBaseFlags.dot
			and triggerSkillBaseFlags.duration and not triggerSkillBaseFlags.hit
		local function onHitTriggerBridge(num)
			if triggerSkillId and not triggerSkillIsAura then
				return { mod("ChanceToTriggerOnHit_" .. triggerSkillId, "BASE", num) }
			end
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnHit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on hit$"] = onHitTriggerBridge
		-- @leb-regression-guard:trigger-chance-to-cast-on-melee-hit
		-- "X% chance to cast <skill> on melee hit": like the on-hit bridge but only a
		-- MELEE source skill's hits count. Emit the functional, global
		-- ChanceToTriggerOnMeleeHit_<skillId>; CalcSetup gates source selection to
		-- skills with SkillType.Melee, then routes through the SAME on-hit trigger
		-- path (the handler applies the melee source's hit chance). Rate is
		-- build-derived (melee attack rate x hit chance x chance). Absent from data
		-- -> recognition-only ChanceToCast_ fallback (e.g. Summon Forged Weapon, a
		-- minion not in data.skills, is unchanged). Only the bare "on melee hit$"
		-- form; rate-capped ("... up to N per second", cooldowns) stay deferred.
		local function onMeleeHitTriggerBridge(num)
			if triggerSkillId and not triggerSkillIsAura then
				return { mod("ChanceToTriggerOnMeleeHit_" .. triggerSkillId, "BASE", num) }
			end
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnMeleeHit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on melee hit$"] = onMeleeHitTriggerBridge
		-- @leb-regression-guard:trigger-chance-to-cast-on-spell-cast
		-- "X% chance to cast <skill> on (spell) cast": the source is "you cast a
		-- spell". Emit the functional, global ChanceToTriggerOnSpellCast_<skillId>;
		-- CalcSetup gates source selection to skills with SkillType.Spell, then routes
		-- through the on-hit trigger path. For a spell source the handler's hit-chance
		-- branch (Melee/Attack only) is NOT taken, so the rate is the spell's CAST
		-- rate x this chance, build-derived. Absent from data -> recognition-only.
		-- @leb-regression-guard:trigger-spell-cast-cooldown-cap
		-- Some on-spell-cast triggers carry a per-cast trigger cooldown in the affix/node
		-- REMINDER TEXT, not an inline "(K second cooldown)" the capped patterns below can
		-- read from the line -- so the bare bridge would over-read the trigger at very high
		-- cast rates. Datamined reminder-text cooldowns are tabled here as procs/sec caps
		-- (1 / cooldown seconds) and emitted alongside the chance; CalcSetup attaches
		-- TriggerRateCapPerSecond_<skillId> to the injected group and CalcTriggers min-
		-- applies it (trigger-rate-cap-ptt): SkillTriggerRate = min(cap, castRate x chance).
		-- Lagon's Answer (Primalist-69) casts Storm Bolt (PrimalLightning) with a 1s trigger
		-- cooldown -> 1/s. Non-binding at the observed ground-truth cast rate (SuXes_StormBolt2,
		-- proc gaps >= 4.7s) and corpus-neutral (no fast Lagon's Answer build), but caps the
		-- over-read for any future fast-casting build. Spec: TestTriggerOnSpellCastDPS_spec.lua
		local onSpellCastReminderTextCooldownCap = { PrimalLightning = 1 }  -- skillId -> 1 / reminderText cooldown seconds
		local function onSpellCastTriggerBridge(num)
			if triggerSkillId and not triggerSkillIsAura then
				local cap = onSpellCastReminderTextCooldownCap[triggerSkillId]
				if cap then
					return { mod("ChanceToTriggerOnSpellCast_" .. triggerSkillId, "BASE", num),
					         mod("TriggerRateCapPerSecond_" .. triggerSkillId, "BASE", cap) }
				end
				return { mod("ChanceToTriggerOnSpellCast_" .. triggerSkillId, "BASE", num) }
			end
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnSpellCast" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on spell cast$"] = onSpellCastTriggerBridge
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on cast$"] = onSpellCastTriggerBridge
		-- @leb-regression-guard:trigger-rate-cap-ptt
		-- Capped variants of the bridged conditions. LE limits triggered casts with a
		-- ProcTimeTracker (datamined game source: limit procs per interval) -> effective cap =
		-- limit/interval. Emit the base condition's functional mod PLUS a global
		-- TriggerRateCapPerSecond_<skillId> (= limit/interval); CalcSetup attaches it to
		-- the triggered skill and the handler does TriggerRateCap = min(cap, ...).
		-- "(up to N times per second)" = N/1 ; "(up to N times per M seconds)" = N/M ;
		-- "(K second cooldown)" = PTT(1,K) = 1/K.
		-- on melee hit (rate-capped)
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on melee hit %(up to (%d+) times? per second%)$"] = function(num, _, n)
			if triggerSkillId and not triggerSkillIsAura then return { mod("ChanceToTriggerOnMeleeHit_"..triggerSkillId, "BASE", num), mod("TriggerRateCapPerSecond_"..triggerSkillId, "BASE", tonumber(n)) } end
			return nsList(mod("ChanceToCast_"..canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnMeleeHit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on melee hit %(up to (%d+) times? per ([%d%.]+) seconds?%)$"] = function(num, _, n, m)
			if triggerSkillId and not triggerSkillIsAura then return { mod("ChanceToTriggerOnMeleeHit_"..triggerSkillId, "BASE", num), mod("TriggerRateCapPerSecond_"..triggerSkillId, "BASE", tonumber(n)/tonumber(m)) } end
			return nsList(mod("ChanceToCast_"..canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnMeleeHit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on melee hit %(([%d%.]+) second cooldown%)$"] = function(num, _, k)
			if triggerSkillId and not triggerSkillIsAura then return { mod("ChanceToTriggerOnMeleeHit_"..triggerSkillId, "BASE", num), mod("TriggerRateCapPerSecond_"..triggerSkillId, "BASE", 1/tonumber(k)) } end
			return nsList(mod("ChanceToCast_"..canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnMeleeHit" }))
		end
		-- on hit (rate-capped)
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on hit %(up to (%d+) times? per ([%d%.]+) seconds?%)$"] = function(num, _, n, m)
			if triggerSkillId and not triggerSkillIsAura then return { mod("ChanceToTriggerOnHit_"..triggerSkillId, "BASE", num), mod("TriggerRateCapPerSecond_"..triggerSkillId, "BASE", tonumber(n)/tonumber(m)) } end
			return nsList(mod("ChanceToCast_"..canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnHit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on hit %(([%d%.]+) second cooldown%)$"] = function(num, _, k)
			if triggerSkillId and not triggerSkillIsAura then return { mod("ChanceToTriggerOnHit_"..triggerSkillId, "BASE", num), mod("TriggerRateCapPerSecond_"..triggerSkillId, "BASE", 1/tonumber(k)) } end
			return nsList(mod("ChanceToCast_"..canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnHit" }))
		end
		-- @leb-regression-guard:trigger-chance-to-cast-on-throwing-hit
		-- Validation provenance is retained in maintainer notes.
		local function onThrowingHitTriggerBridge(num)
			if triggerSkillId and not triggerSkillIsAura then
				return { mod("ChanceToTriggerOnThrowingHit_" .. triggerSkillId, "BASE", num) }
			end
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnThrowingHit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on hit with throwing attacks$"] = onThrowingHitTriggerBridge
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on hit with throwing attacks %(up to (%d+) times? per second%)$"] = function(num, _, n)
			if triggerSkillId and not triggerSkillIsAura then return { mod("ChanceToTriggerOnThrowingHit_"..triggerSkillId, "BASE", num), mod("TriggerRateCapPerSecond_"..triggerSkillId, "BASE", tonumber(n)) } end
			return onThrowingHitTriggerBridge(num)
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on hit with throwing attacks %(up to (%d+) times? per ([%d%.]+) seconds?%)$"] = function(num, _, n, m)
			if triggerSkillId and not triggerSkillIsAura then return { mod("ChanceToTriggerOnThrowingHit_"..triggerSkillId, "BASE", num), mod("TriggerRateCapPerSecond_"..triggerSkillId, "BASE", tonumber(n)/tonumber(m)) } end
			return onThrowingHitTriggerBridge(num)
		end
		-- @leb-regression-guard:trigger-chance-to-cast-on-bow-hit
		-- "X% chance to cast <skill> on bow hit": like the on-hit / on-throwing-hit
		-- bridges but only a BOW source skill's hits count. Emit the functional, global
		-- ChanceToTriggerOnBowHit_<skillId> BASE mod (new scoped family, no default
		-- consumer); the CalcSetup grantedTriggeredSkills loop sums it per source ONLY
		-- when the source skill has SkillType.Bow AND the config toggle is on (see the
		-- sourceIsBow gate there), then routes through the SAME on-hit trigger path
		-- (rate = bow attack rate x hit chance x this chance, build-derived).
		-- Ground truth: the unique bow "Reign of Winter" (uniques_1_4.json #159)
		-- affix "(23-28)% Chance to cast Icicle on Bow Hit"; the triggered skill Icicle
		-- is data.skills.HeorotUniqueBowIcicle (spell, hit, cold base 100). This "on bow
		-- hit" phrasing matched NO specialModList rule before, so the line baked to an
		-- EMPTY ModCache entry (`{{}," to cast  on   "}`) and never reached FullDPS.
		-- WHY the CalcSetup read is config-gated (NOT auto-folded like on-hit/throwing):
		-- the proc's RATE CAP / internal cooldown is NOT datamined, so folding at full
		-- bow-hit rate x chance would be a fabricated magnitude. Default OFF keeps the
		-- corpus byte-identical; a user who wants to model the proc opts in. Absent from
		-- data / pure aura -> recognition-only ChanceToCast_ fallback.
		-- Spec: spec/System/TestReignOfWinterIcicleProc_spec.lua
		local function onBowHitTriggerBridge(num)
			if triggerSkillId and not triggerSkillIsAura then
				return { mod("ChanceToTriggerOnBowHit_" .. triggerSkillId, "BASE", num) }
			end
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnBowHit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on bow hit$"] = onBowHitTriggerBridge
		-- @leb-regression-guard:trigger-chance-after-skill
		-- "X% chance to cast <T> after you use <SOURCE> and hit a boss or rare enemy"
		-- (Aurelis, uniques_1_4 id 225: "100% Chance to cast Smite after you use
		-- Multistrike and hit a Boss or Rare enemy"). Unlike the on-hit/melee/throwing
		-- bridges above (which emit a GLOBAL chance summed across EVERY eligible source
		-- of the matching skill type), this is SOURCE-SCOPED: only the ONE named source
		-- skill's uses trigger it. Emit ChanceToTriggerAfterSkill_<triggeredId> BASE
		-- tagged {SkillName=<SOURCE>} so CalcSetup's per-source Sum(activeSkill.skillCfg)
		-- is non-zero ONLY when the active source IS <SOURCE> (Multistrike). Without the
		-- SkillName scope, a bare ChanceToTriggerOnMeleeHit_ sum would fire for Rive /
		-- every other melee source too -> massive over-count. The boss/rare enemy
		-- condition is NOT applied here -- it is gated at DPS time in CalcTriggers
		-- (env.enemyDB, unambiguous), so the group is CREATED regardless of enemy config
		-- and a non-boss zeroes it downstream. Absent from data / pure aura / unknown
		-- source -> recognition-only ChanceToCast_ fallback. NOTE: this line's stale
		-- pre-fix ModCache row (Data/ModCache.lua: {{}, residue}) was DELETED in the same
		-- commit -- otherwise the cache short-circuits parseMod and this bridge never runs.
		local function afterSkillBossRareBridge(num, _, sourceName)
			local sourceCanonical = sourceName and skillNameByLower[sourceName]
			if triggerSkillId and not triggerSkillIsAura and sourceCanonical then
				return { mod("ChanceToTriggerAfterSkill_" .. triggerSkillId, "BASE", num, "", 0, 0, { type = "SkillName", skillName = sourceCanonical }) }
			end
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnHit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " after you use (.+) and hit a boss or rare enemy$"] = afterSkillBossRareBridge
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on crit$"] = function(num)
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnCrit" }))
		end
		-- @leb-regression-guard:trigger-global-capped-on-crit-when-hit
		-- "on crit (K second cooldown)" / "when hit (K second cooldown)": the trigger
		-- fires on a crit / on being hit, bounded by a PTT cap (datamined game source ProcTimeTracker,
		-- L239352). All in-data on-crit forms carry the cooldown, so we model the rate as
		-- the cap (= 1/K), i.e. "fires often enough to saturate the cooldown" - the PoB
		-- CWDT model, which avoids generalising the shared crit handler to spell sources.
		-- Emit a source-INDEPENDENT ChanceToTriggerCapped_<skillId> (CalcSetup injects a
		-- triggeredGlobalCapped group) + the PTT cap. The crit/hit chance itself is an
		-- upper-bound approximation (saturation); exact rate needs a firing-build CSV.
		-- Bare "on crit"/"when hit" (no cooldown) stay recognition-only (no cap = unbounded).
		-- Only bridge DISCRETE-HIT triggered skills here (baseFlags.hit). A pure aura/DoT
		-- (e.g. Fire Aura: baseFlags {spell,dot}, no hit) must NOT be modelled as discrete
		-- casts at the cap — it needs the aura-uptime model (the TreeNodeGrant precedent),
		-- so it falls through to recognition-only here.
		-- triggerSkillBaseFlags / triggerSkillIsHit / triggerSkillIsAura are computed once
		-- near the top of this skill-loop iteration (hoisted so the on-hit / on-melee-hit /
		-- on-spell-cast bridges can exclude pure auras). Reused below.
		-- A pure aura/DoT (Fire Aura: baseFlags {spell,dot}, no hit) is a STACKING aura
		-- (LETools "Each stack lasts 4 seconds"; datamined game source FireAuraStacks buff). It is NOT a
		-- discrete cast: a cooldown-bound trigger gains a stack at the cap rate, each stack
		-- lasts the skill duration -> steady-state stacks = (1/K) x duration (the ailment
		-- stack-uptime model). @leb-regression-guard:trigger-aura-stack-on-crit-when-hit
		local function globalCappedTrigger(num, k)
			if triggerSkillId and triggerSkillIsHit then
				-- discrete-hit skill: rate = cap (globalTrigger + PTT cap)
				return { mod("ChanceToTriggerCapped_"..triggerSkillId, "BASE", num), mod("TriggerRateCapPerSecond_"..triggerSkillId, "BASE", 1/tonumber(k)) }
			elseif triggerSkillId and triggerSkillIsAura then
				-- stacking aura: gain a stack at the cap rate (1/K); MaxStacks = rate x duration
				return { mod("AuraTriggerRatePerSecond_"..triggerSkillId, "BASE", 1/tonumber(k)) }
			end
			return nil
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on crit %(([%d%.]+) second cooldown%)$"] = function(num, _, k)
			return globalCappedTrigger(num, k) or nsList(mod("ChanceToCast_"..canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnCrit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " when hit %(([%d%.]+) second cooldown%)$"] = function(num, _, k)
			return globalCappedTrigger(num, k) or nsList(mod("ChanceToCast_"..canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "WhenHit" }))
		end
		-- @leb-regression-guard:trigger-qualified-oncrit-ratecap
		-- "X% chance to cast <skill> on crit with <source> (up to N casts per second)":
		-- a rate-capped, source-qualified on-crit trigger (e.g. "Lightning Blast on Crit
		-- with Frost Claw (up to 3 casts per second)"). The "up to N casts per second" is
		-- the explicit PTT cap (= N/s), so for a discrete-hit triggered skill we model the
		-- rate as that cap (saturation upper bound; the "with <source>" qualifier is
		-- assumed to drive the crits that saturate it). Reuses the globalTrigger+cap path
		-- (ChanceToTriggerCapped_ + TriggerRateCapPerSecond_ = N). Auras -> recognition-only
		-- (handled by the aura-stack path elsewhere; none in data for this form).
		local function qualifiedOnCritRateCap(num, capN)
			if triggerSkillId and triggerSkillIsHit then
				return { mod("ChanceToTriggerCapped_"..triggerSkillId, "BASE", num), mod("TriggerRateCapPerSecond_"..triggerSkillId, "BASE", tonumber(capN)) }
			end
			return nil
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on crit with .+ %(up to (%d+) casts? per second%)$"] = function(num, _, capN)
			return qualifiedOnCritRateCap(num, capN) or nsList(mod("ChanceToCast_"..canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnCrit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on crit with .+ %(up to (%d+) casts? per ([%d%.]+) seconds?%)$"] = function(num, _, capN, capM)
			if triggerSkillId and triggerSkillIsHit then
				return { mod("ChanceToTriggerCapped_"..triggerSkillId, "BASE", num), mod("TriggerRateCapPerSecond_"..triggerSkillId, "BASE", tonumber(capN)/tonumber(capM)) }
			end
			return nsList(mod("ChanceToCast_"..canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnCrit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " when you use a potion$"] = function(num)
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnPotionUse" }))
		end
		-- @leb-regression-guard:trigger-chance-to-cast-every-n-seconds
		-- "X% chance to cast <skill> every N seconds": a SOURCE-INDEPENDENT timer
		-- trigger (no source skill — fires on a fixed N-second clock). The expected
		-- steady-state rate is chance/100 attempts per N seconds = num/(100*N) casts
		-- per second; we bake that exact (text-derived, not fabricated) value into a
		-- functional TriggerRatePerSecond_<skillId> BASE mod. CalcSetup injects a
		-- timer-triggered group (triggeredByTimer, no triggeredOnHit) into Full DPS;
		-- CalcTriggers uses the fixed rate via a gated dispatch branch. Absent from
		-- data -> recognition-only ChanceToCast_ fallback.
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " every ([%d%.]+) seconds?$"] = function(num, _, nStr)
			local n = tonumber(nStr)
			if triggerSkillId and n and n > 0 then
				return { mod("TriggerRatePerSecond_" .. triggerSkillId, "BASE", num / 100 / n) }
			end
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnTimer" }))
		end
	end
end

-- @leb-regression-guard:trigger-chance-to-cast-when-you-cast-bridge
-- "X% chance to cast A when you cast B": bridge into the existing trigger
-- pipeline with EXPLICIT, build-derived source selection.
-- e.g. "10% Chance to cast Marrow Shards when you cast Transplant"
--
-- Unlike the bare "on hit" form (which emits a GLOBAL ChanceToTriggerOnHit_ so
-- any active skill can be the source), this two-skill form names the source B
-- explicitly. We therefore emit the functional ChanceToTriggerOnHit_<Aid> mod
-- SCOPED to the SOURCE skill B (SkillName = B). The CalcSetup
-- grantedTriggeredSkills loop sums ChanceToTriggerOnHit_<Aid> with each candidate
-- source's own skillCfg, so the SkillName=B tag matches ONLY when the source is B
-- (ModStore.lua SkillName tag eval). The trigger rate is then B's CAST rate
-- (B is a spell -> Speed = cast rate, no hit-chance/crit branch) x this chance -
-- fully build-derived, not fabricated. This is the correct source selection the
-- global on-hit bridge cannot express. Crucially the scope is the SOURCE (B), NOT
-- the triggered skill (A): scoping to A (as the old ChanceToCast_ form did) made
-- the per-source Sum never match, which is why nothing consumed it.
-- A absent from data.skills (e.g. data-blocked sub-skills) -> recognition-only
-- ChanceToCast_ fallback (unchanged behaviour). Single generic pattern with
-- skill-name validation in the handler (avoids N^2 pattern blowup).
specialModList["^%+?([%d%.]+)%% chance to cast (.+) when you cast (.+)$"] = function(num, _, triggerName, castName)
	local trig = canonicalSkillName(triggerName)
	local cast = canonicalSkillName(castName)
	if not trig or not cast then return nil end
	local trigId = skillIdByLower[trig:lower()]
	if trigId then
		-- functional (consumed by the trigger framework), source-scoped to B
		return { mod("ChanceToTriggerOnHit_" .. trigId, "BASE", num, "", 0, 0, { type = "SkillName", skillName = cast }) }
	end
	return nsList(mod("ChanceToCast_" .. trig:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = trig }, { type = "Condition", var = "OnCast_" .. cast:gsub("%s+","") }))
end
specialModList["^%+?([%d%.]+)%% chance to cast (.+) when you use (.+)$"] = function(num, _, triggerName, castName)
	local trig = canonicalSkillName(triggerName)
	local cast = canonicalSkillName(castName)
	if not trig or not cast then return nil end
	-- @leb-regression-guard:trigger-chance-to-cast-when-you-cast-bridge
	-- "when you use B" is bridged like "when you cast B" ONLY when the source B is a
	-- SPELL (data.skills[B].baseFlags.spell). For a spell, "use" == "cast", so the
	-- source rate is B's cast rate and the shared handler's hit-chance/crit branch
	-- (Melee/Attack only) is not taken -> correct, build-derived. For a non-spell
	-- source B (attack/throw) "use" != "hit", so routing through the hit-chance
	-- branch would undercount; that case stays recognition-only (deferred).
	local trigId = skillIdByLower[trig:lower()]
	local castId = skillIdByLower[cast:lower()]
	local castIsSpell = castId and data.skills[castId] and data.skills[castId].baseFlags and data.skills[castId].baseFlags.spell
	if trigId and castIsSpell then
		return { mod("ChanceToTriggerOnHit_" .. trigId, "BASE", num, "", 0, 0, { type = "SkillName", skillName = cast }) }
	end
	return nsList(mod("ChanceToCast_" .. trig:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = trig }, { type = "Condition", var = "OnUse_" .. cast:gsub("%s+","") }))
end

-- @leb-regression-guard:riverbend-grasp-throw-axe
-- Riverbend Grasp (uniques_1_4 id 23, weapon baseType 4/subType 2): the affix
-- "(18-30)% Chance to Throw an Axe at a nearby enemy on hit (1 second cooldown)".
-- The line names the ACTION ("throw an axe"), NOT a "cast <skill>" form, so none
-- of the generic on-hit "chance to cast X on hit" bridges above match it -- its
-- ModCache row was a {{}, residue} no-op, i.e. silently unmodelled (genuine-
-- unmodelled ★HIGH in the unmodeled-affix-C proc triage; corpus: <private build>
-- Marksman, <private build> / QJWMRVWx Falconer).
--
-- Grounding: the unique's abilityTooltipKey 1895528163 resolves (ability_keyed_
-- array.json) to unityObjectName "AxeThrow" (playerAbilityID "ht16aw", tags
-- Physical/Throwing, Str/Dex scaling; ability_attribute_scaling pid 261129).
-- Datamined base (extract_axethrow.py, resources.assets base "axeThrow" prefab
-- pid 23089 DamageEnemyOnHit): 25 Physical, addedDamageScaling (damageEffective-
-- ness) 1.0, critChance 0.05, critMultiplier 2.0. This is ALREADY normalised in
-- data.skills["AxeThrow"] (skills.json: throwing_base_physical_damage 25,
-- damageEffectiveness 1, critChance 5, base_critical_strike_multiplier_+ 100),
-- so NO new skill is added here -- only the trigger bridge.
--
-- Bridge exactly like the generic bare "on hit$" form (onHitTriggerBridge): emit
-- the FUNCTIONAL, GLOBAL ChanceToTriggerOnHit_AxeThrow (CalcSetup's granted-
-- TriggeredSkills loop sums it against EVERY source skill's hit rate, so the
-- trigger rate is build-derived) PLUS the "(1 second cooldown)" PTT cap
-- TriggerRateCapPerSecond_AxeThrow = 1/s (CalcSetup attaches it, CalcTriggers
-- min-applies it: SkillTriggerRate = min(1, sourceHitRate x chance)). No flags,
-- matching onHitTriggerBridge (~line 4002). Guarded on data.skills["AxeThrow"]
-- so a data change can't emit a dangling skillId (declines -> nil, falls through
-- to the generic no-op, unchanged). Proc-rate magnitude is a display-only /
-- capture concern (deferred). Spec: spec/System/TestRiverbendGraspThrowAxe_spec.lua
specialModList["^%+?([%d%.]+)%% chance to throw an axe at a nearby enemy on hit %(1 second cooldown%)$"] = function(num)
	if data.skills["AxeThrow"] then
		return { mod("ChanceToTriggerOnHit_AxeThrow", "BASE", num), mod("TriggerRateCapPerSecond_AxeThrow", "BASE", 1) }
	end
	return nil
end

-- @leb-regression-guard:razorfall-umbral-blades-per-dex
-- Validation provenance is retained in maintainer notes.
specialModList["^%+(%d+) umbral blades per (%d+) dexterity thrown with aerial assault's burst of feathers$"] = function(num, _, divStr)
	return {
		mod("Multiplier:RazorfallEquipped", "BASE", 1, "Razorfall"),
		mod("ProjectileCount", "BASE", num, "Razorfall", 0, 0,
			{ type = "SkillName", skillName = "Umbral Blades" },
			{ type = "PerStat", stat = "Dexterity", div = tonumber(divStr) },
			{ type = "Condition", var = "RazorfallBurstOfFeathers" }),
	}
end

-- @leb-regression-guard: chthonic-fissure-gen393-hit
-- @leb-regression-guard: chthonic-fissure-hit-pyrochasm-gated
-- Validation provenance is retained in maintainer notes.
specialModList["^chthonic fissure also casts chthonic fissure hit$"] = function()
	local cfhId = skillIdByLower["chthonic fissure hit"]
	if cfhId then
		return { mod("ChanceToTriggerOnHit_" .. cfhId, "BASE", 100, "", 0, 0, { type = "SkillName", skillName = "Chthonic Fissure" }) }
	end
end

-- @leb-regression-guard: flame-whip-from-chthonic-fissure-node
-- Validation provenance is retained in maintainer notes.
specialModList["^100%% chance for chthonic fissures to cast flame whip instead of releasing spirits$"] = function()
	local fwId = skillIdByLower["flame whip"]
	if fwId then
		-- @leb-regression-guard:chthonic-fissure-soul-blast
		-- The Spirits are REPLACED by Flame Whip, so the Spirit's Necrotic hit
		-- ("Soul Blast", Warlock 04.2 Arcing Soul Explosion) -- with its on-hit
		-- ailments + Torment -- does NOT exist on a Spine of Malatros build. The
		-- base-kit Soul Blast SubSkillGrant is therefore gated on the ABSENCE of this
		-- very trigger (SubSkillGrants requiresAbsentParentTrigger = "Warlock Unique
		-- Flame Whip"); Flame Whip (the swapped hit) carries the on-hit ailments for
		-- Spine builds instead. See SubSkillGrants.lua + CalcSetup grantedSubSkills.
		return { mod("ChanceToTriggerOnHit_" .. fwId, "BASE", 100, "", 0, 0, { type = "SkillName", skillName = "Chthonic Fissure" }) }
	end
end

-- @leb-regression-guard: flame-whip-crit-mult-per-uncapped-necrotic-res
-- See REGRESSION_GUARDS.md "flame-whip-crit-mult-per-uncapped-necrotic-res".
-- Validation provenance is retained in maintainer notes.
specialModList["^%+?(%d+)%% critical strike multiplier with flame whip per 10%% uncapped necrotic resistance$"] = function(num)
	return { mod("CritMultiplier", "BASE", num, "", 0, 0,
		{ type = "SkillName", skillName = "Flame Whip" },
		{ type = "PerStat", stat = "NecroticResistTotal", div = 10 }) }
end

-- Reap-prefixed tree mods (Reap is granted by Reaper Form; scope to Reaper Form active skill).
-- Roadmap: Tier 3 — strict Reap subskill split (treeId share check required).
local reaperFormTag = { type = "SkillName", skillName = "Reaper Form" }
specialModList["^%+?([%d%.]+)%% reap area$"] = function(num)
	return { mod("AreaOfEffect", "INC", num, "", 0, 0, reaperFormTag) }
end
specialModList["^%+?([%d%.]+)%% reap health leech$"] = function(num)
	return { mod("DamageLifeLeech", "BASE", num, "", 0, 0, reaperFormTag) }
end
specialModList["^%+?([%d%.]+)%% reap damage per missing health percent$"] = function(num)
	return { mod("Damage", "MORE", num, "", 0, 0, reaperFormTag, { type = "Multiplier", var = "MissingHealthPercent" }) }
end
specialModList["^%+?([%d%.]+)%% reap cooldown duration$"] = function(num)
	return { mod("CooldownRecovery", "INC", -num, "", 0, 0, reaperFormTag) }
end
-- @leb-regression-guard:raptor-execute-missing-health-more (parser site)
-- Beastmaster Raptor "Cornered" (srtor-20), rewritten from "+X% Damage per 1%
-- Missing Health" by LE_TREE_NODE_STAT_REWRITE (Data/Global.lua). The Raptor
-- deals MORE damage per 1% of ITS OWN missing health, capped at 50% missing
-- (Multiplier limit=50). Mirrors the Reaper-Form missing-health MORE above but
-- with the datamine 50%-missing cap; scoped to the Raptor by the minion-tree
-- node context (PassiveTree ProcessStats), same placement as the former flat
-- parse -- applies to all Raptor attacks (Fire Breath / Screech / Melee). The
-- MissingHealthPercent multiplier is a MINION state (default 0 => full HP =>
-- x1.0 inert). See REGRESSION_GUARDS.md.
specialModList["^%+?([%d%.]+)%% raptor damage per 1%% missing health$"] = function(num)
	return { mod("Damage", "MORE", num, "", 0, 0, { type = "Multiplier", var = "MissingHealthPercent", limit = 50 }) }
end
specialModList["^%+?([%d%.]+)%% reap cooldown recovery speed$"] = function(num)
	return { mod("CooldownRecovery", "INC", num, "", 0, 0, reaperFormTag) }
end
specialModList["^%+?([%d%.]+) reap health gained$"] = function(num)
	return { mod("LifeOnHit", "BASE", num, "", 0, 0, reaperFormTag) }
end
specialModList["^%+?([%d%.]+)%% increased cooldown recovery speed of reap$"] = function(num)
	return { mod("CooldownRecovery", "INC", num, "", 0, 0, reaperFormTag) }
end
specialModList["^%+?([%d%.]+)%% increased cooldown recovery speed for reap$"] = function(num)
	return { mod("CooldownRecovery", "INC", num, "", 0, 0, reaperFormTag) }
end
specialModList["^%+?([%d%.]+)%% reap range$"] = function(num)
	return { mod("MeleeWeaponRange", "BASE", num, "", 0, 0, reaperFormTag) }
end
specialModList["^%+?([%d%.]+) reap freeze rate per intelligence$"] = function(num)
	return { mod("FreezeRate", "BASE", num, "", 0, 0, reaperFormTag, { type = "PerStat", stat = "Int" }) }
end
specialModList["^%+?([%d%.]+)%% reap kill threshold$"] = function(num)
	return { mod("KillThreshold", "BASE", num, "", 0, 0, reaperFormTag) }
end
specialModList["^%+?([%d%.]+)%% reap poison chance$"] = function(num)
	return { mod("ChanceToTriggerOnHit_Ailment_Poison", "BASE", num, "", 0, 0, reaperFormTag) }
end

-- @leb-regression-guard:dusk-shroud-trigger-effect
-- Doppelganger's Facade unique (uniques.json L10257 / set_1_4.json L301) carries the
-- guaranteed-form mod line:
--     "Consuming a Shadow grants a stack of Dusk Shroud"
-- This is the 100%-chance counterpart to the chance-form Bladedancer affix family
--     "+N% Chance to gain a stack of Dusk Shroud when you consume a Shadow"
-- already locked by shadow-suffix-family C6c P8 (7 ModCache entries parse to
-- ChanceToTriggerOnHit_Ailment_DuskShroud BASE with Condition:OnShadowConsume).
-- Game-file backing: datamined game source `RogueShadow.duskShroudChanceOnConsumption`
-- (field consumed inside `ConsumeShadow()` at L22808); datamined game source
-- `AilmentID DuskShroud = 82`. We emit the same stat as the chance form with
-- BASE=100 + the OnShadowConsume condition tag, so the existing
-- conditionOnShadowConsume Config toggle (ConfigOptions.lua L292) is the consumer
-- surface — no new stat or accumulator needed. v2 deferred: per-cast stack limit
-- (1 stack per consume) is not modelled here because the chance-form entries
-- don't model it either; surface accuracy parity is intentional.
specialModList["^consuming a shadow grants a stack of dusk shroud$"] = function()
	return { mod("ChanceToTriggerOnHit_Ailment_DuskShroud", "BASE", 100, "", ModFlag.Hit, 0, { type = "Condition", var = "OnShadowConsume" }) }
end

-- Recognition-only catch-alls for remaining red-text idol patterns.
-- These use broad (.+) captures and deliberately run AFTER the specific patterns above;
-- scan() picks the longest match, so specific patterns still win when they apply.
local function nsAny(num)
	return nsList(mod("LEB_NotSupported", "BASE", num))
end

-- @leb-regression-guard:resource-gain-mode-chance-averaging
-- Chance-based resource gain ("X% Chance to Gain N Ward when/on Hit / on Kill").
-- Adopts PoB's emit-two-gated-mods pattern (PoB clone ModParser ~4489): emit the
-- gain into the consumed/displayed output (`out`) TWICE, gated by resourceGainMode's
-- conditions -- Average = amount*chance/100, Max = amount*ceil(chance/100) (ceil
-- makes a >100% chance = multiple certain procs), Min = neither condition => 0.
-- ConfigOptions `resourceGainMode` sets Condition:AverageResourceGain /
-- MaxResourceGain; this ALSO auto-fixes that config's `ifCond="AverageResourceGain"`
-- visibility gate (the tag is now emitted). output.WardOnHit / WardOnKill are
-- DISPLAY values (Calcs panel "Ward on Hit"/"Ward on Kill"), NOT consumed by
-- EHP/DPS -> display-correctness fix only, ZERO DPS/EHP impact. Non-ward gains
-- (and the no-amount "gain Ward" form) fall through to nsAny (recognition-only).
-- Spec: spec/System/TestResourceGainModeChance_spec.lua.
local function chanceGainResource(out)
	return function(num, _, gainText)
		local amount = gainText and gainText:match("^(%d+) ward$")
		if amount then
			amount = tonumber(amount)
			return {
				mod(out, "BASE", amount * num / 100, "", 0, 0, { type = "Condition", var = "AverageResourceGain" }),
				mod(out, "BASE", amount * math.ceil(num / 100), "", 0, 0, { type = "Condition", var = "MaxResourceGain" }),
			}
		end
		return nsAny(num)
	end
end

-- Buff-conditional stat scaling (e.g. "+19% Increased Cast Speed while you have Lightning Aegis")
-- Known buff names round-trip through modTagList's "while you have <X>" keys below, so
-- for those we return nil to let the generic parser apply the proper Condition tag.
-- Unknown buff names still get nsAny for recognition-only fallback.
local knownWhileYouHaveBuffs = {
	["ward"] = true,
	["lightning aegis"] = true,
	["haste"] = true,
	["frenzy"] = true,
	["an ailment overload"] = true,
	["a companion"] = true,
	["a forged weapon"] = true,
}
-- Handler args: (num_as_number, cap1_as_string, stat, buff). We only care about the buff.
local function whileYouHaveHandler(num, _, _, buff)
	if buff and knownWhileYouHaveBuffs[buff:lower()] then
		return nil  -- fall through to generic parser (modTagList carries the Condition tag)
	end
	return nsAny(num)
end
specialModList["^%+?([%d%.]+)%% increased (.+) while you have (.+)$"] = whileYouHaveHandler
specialModList["^%+?([%d%.]+)%% reduced (.+) while you have (.+)$"] = whileYouHaveHandler
specialModList["^%+?([%d%.]+)%% more (.+) while you have (.+)$"] = whileYouHaveHandler
specialModList["^%+?([%d%.]+)%% less (.+) while you have (.+)$"] = whileYouHaveHandler

-- Chance-to-gain <buff> on generic triggers (hit, crit, kill, dodge, block, potion use)
-- Existing per-buff patterns for Echo/Totem still win via longest-match.
specialModList["^%+?([%d%.]+)%% chance to gain (.+) when hit$"] = chanceGainResource("WardOnHit")
specialModList["^%+?([%d%.]+)%% chance to gain (.+) when you are hit$"] = chanceGainResource("WardOnHit")
specialModList["^%+?([%d%.]+)%% chance to gain (.+) on hit$"] = chanceGainResource("WardOnHit")
specialModList["^%+?([%d%.]+)%% chance to gain (.+) on kill$"] = chanceGainResource("WardOnKill")
specialModList["^%+?([%d%.]+)%% chance to gain (.+) on crit$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) when you crit$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) when you dodge$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) when you block$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) when you use a potion$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) for (%d+) seconds? when hit$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) for (%d+) seconds? on kill$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) for (%d+) seconds? on crit$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) for (%d+) seconds? when you dodge$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) for (%d+) seconds? when you block$"] = nsAny

-- Ailment / charge application (e.g. "+3% Chance to apply Frailty on Minion Hit",
--                                     "+1% Chance to apply a Spark Charge on Lightning Melee Hit")
-- DPS-integrated via the generic parse chain: modNameList has per-ailment
-- "<ailment> chance" / "to apply <ailment>" → <Ailment>Chance stats, and
-- modTagList handles "on hit" (ModFlag.Hit), "on melee hit", "on kill", etc.
-- A smart handler falls through for recognized ailments so the mod actually
-- applies; unknown names still get caught by nsAny for recognition-only.
local knownAilmentChances = {
	["bleed"] = true, ["a bleed"] = true,
	["ignite"] = true, ["poison"] = true, ["shock"] = true, ["chill"] = true,
	["frostbite"] = true, ["frailty"] = true, ["electrify"] = true,
	["time rot"] = true, ["slow"] = true, ["blind"] = true,
	["plague"] = true, ["witchfire"] = true, ["spreading flames"] = true,
	["future strike"] = true, ["abyssal decay"] = true, ["spirit plague"] = true,
	["bone curse"] = true, ["torment"] = true, ["decrepify"] = true,
	["anguish"] = true, ["penance"] = true, ["acid skin"] = true,
	["exposed flesh"] = true, ["serpent venom"] = true, ["hemorrhage"] = true,
	["ravage"] = true, ["critical vulnerability"] = true,
	["marked for death"] = true, ["mark for death"] = true,
	["damned"] = true, ["doom"] = true,
	["armor shred"] = true, ["armour shred"] = true,
}
-- @leb-regression-guard:spark-charge-gear-apply
-- Gear/idol affix "+N% Chance to apply a Spark Charge on [Melee/Lightning Melee] Hit"
-- (URA XML L301 "+(10-12)% Chance to apply a Spark Charge on Hit") routes to
-- ChanceToTriggerOnHit_Ailment_SparkCharge -- the SAME stat the Cloud Answer tree
-- node "X% Spark Charge Chance On Hit" already emits -- instead of LEB_NotSupported.
-- "Spark Charge" is NOT in knownAilmentChances and the SparkChargeExplosion HIT skill
-- carries excludeFromTriggerNameList, so the generic chain has no route for it; emit
-- the stat directly here. The on-hit qualifier maps to flags exactly like the
-- modFlagList "on melee hit" entry: bare "on hit" = Hit; "on melee hit" = Melee|Hit;
-- "on lightning melee hit" = Melee|Hit + KeywordFlag.Lightning. This is the SC
-- APPLICATION chance (feeds the separately-granted detonation), never a HIT trigger,
-- so it can never fabricate SparkChargeExplosion damage. See REGRESSION_GUARDS.md
-- "spark-charge-gear-apply" and "spark-charge-detonation".
local function isSparkChargeName(name)
	local lname = name and name:lower()
	return lname == "a spark charge" or lname == "spark charge"
end
local function sparkChargeApplyMod(num, qualifier)
	local flags = ModFlag.Hit
	local keywordFlags = 0
	if qualifier then
		local q = qualifier:lower()
		if q:find("melee", 1, true) then flags = bor(ModFlag.Melee, ModFlag.Hit) end
		if q:find("lightning", 1, true) then keywordFlags = KeywordFlag.Lightning end
	end
	return { mod("ChanceToTriggerOnHit_Ailment_SparkCharge", "BASE", num, "", flags, keywordFlags) }
end
-- Handler args: (num, cap1_str, ailmentName). Return nil on known → generic chain fires.
local function ailmentApplyHandler(num, _, ailmentName)
	if isSparkChargeName(ailmentName) then
		return sparkChargeApplyMod(num, nil)
	end
	if ailmentName and knownAilmentChances[ailmentName:lower()] then
		return nil
	end
	return nsAny(num)
end
local function ailmentApplyHandler2(num, _, ailmentName, qualifier)
	-- For "on <X> hit" and "when you <X>" forms where cap[4] is the trigger qualifier.
	if isSparkChargeName(ailmentName) then
		return sparkChargeApplyMod(num, qualifier)
	end
	if ailmentName and knownAilmentChances[ailmentName:lower()] then
		return nil
	end
	return nsAny(num)
end
specialModList["^%+?([%d%.]+)%% chance to apply (.+) on hit$"] = ailmentApplyHandler
specialModList["^%+?([%d%.]+)%% chance to apply (.+) on kill$"] = ailmentApplyHandler
specialModList["^%+?([%d%.]+)%% chance to apply (.+) on crit$"] = ailmentApplyHandler
specialModList["^%+?([%d%.]+)%% chance to apply (.+) on (.+) hit$"] = ailmentApplyHandler2
specialModList["^%+?([%d%.]+)%% chance to apply (.+) when you (.+)$"] = ailmentApplyHandler2
-- Also cover "chance to inflict" phrasing symmetrically.
specialModList["^%+?([%d%.]+)%% chance to inflict (.+) on hit$"] = ailmentApplyHandler
specialModList["^%+?([%d%.]+)%% chance to inflict (.+) on kill$"] = ailmentApplyHandler
specialModList["^%+?([%d%.]+)%% chance to inflict (.+) on crit$"] = ailmentApplyHandler
specialModList["^%+?([%d%.]+)%% chance to inflict (.+) on (.+) hit$"] = ailmentApplyHandler2

-- Validation provenance is retained in maintainer notes.
local function spendGainedHandler(num, _, resource, target)
	if resource and target then
		local r, t = resource:lower(), target:lower()
		if r == "mana" and t == "ward" then
			return { mod("ManaSpentGainedAsWard", "BASE", num) }
		end
	end
	return nsAny(num)
end
specialModList["^%+?([%d%.]+)%% of (.+) spent gained as (.+)$"] = spendGainedHandler
-- @leb-regression-guard:ward-per-n-seconds-tick
-- Mage tree node "Decree of the Eternal Tundra" (Mage-94, tree_1.json L1900):
--   stats = "+10 Ward Per 2 Seconds", description "You gain ward every 2 seconds."
-- Modelled as a continuous WardPerSecond contribution with value = N / seconds
-- (10 / 2 = 5 WPS) — the in-game tick granularity is invisible to the build
-- planner's steady-state Ward calculation. Without this handler the BASE fell
-- through to the bare `Ward` stat (max ward) with residue "  Per 2 Seconds ".
-- (The notScalingStats "Doubled Effect with Heo Rune" rune-glyph mechanic is a
-- separate concern and is NOT handled here.)
specialModList["^%+?([%d%.]+) ward per (%d+) seconds?$"] = function(num, _, secondsStr)
	local seconds = tonumber(secondsStr) or 1
	if seconds <= 0 then seconds = 1 end
	return { mod("WardPerSecond", "BASE", num / seconds) }
end
-- @leb-regression-guard:ward-regen-resource-conversion (parser site)
-- Continuous resource→ward conversion affixes (multi_affix 58051/59006/59414):
--     "X% of Missing Health gained as Ward per second"  → MissingHealthGainedAsWardPerSecond
--     "X% of Current Mana gained as Ward per second"    → CurrentManaGainedAsWardPerSecond
-- Also accept the bare "+X% Y gained as Z per second" form (no "of") used by
-- some uniques/idols. CalcPerform post-offence folds these into WardPerSecond
-- using output.LifeUnreserved/ManaUnreserved (with Multiplier:MissingHealthPercent
-- driving the missing-health share). See REGRESSION_GUARDS.md
-- "ward-regen-resource-conversion".
specialModList["^%+?([%d%.]+)%% of missing health gained as ward per second$"] = function(num)
	return { mod("MissingHealthGainedAsWardPerSecond", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% missing health gained as ward per second$"] = function(num)
	return { mod("MissingHealthGainedAsWardPerSecond", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% of current mana gained as ward per second$"] = function(num)
	return { mod("CurrentManaGainedAsWardPerSecond", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% current mana gained as ward per second$"] = function(num)
	return { mod("CurrentManaGainedAsWardPerSecond", "BASE", num) }
end
-- @leb-regression-guard:ward-on-block-resource-conversion (parser site)
-- Event-driven resource→ward conversion on block (multi_affix 963 "Added Block
-- Chance and Current Mana gained as Ward on Block", Shield prefix). Both the
-- "X% of Current Mana gained as Ward on Block" and the bare "+X% Current Mana
-- gained as Ward on Block" forms appear; without these patterns the latter is
-- mis-parsed as Mana INC + Condition:Blocking (see ModCache stale entries) and
-- the former falls through to LEB_NotSupported. CalcDefence consumes the mod
-- after Mana is finalised. See REGRESSION_GUARDS.md "ward-on-block-resource-conversion".
specialModList["^%+?([%d%.]+)%% of current mana gained as ward on block$"] = function(num)
	return { mod("CurrentManaGainedAsWardOnBlock", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% current mana gained as ward on block$"] = function(num)
	return { mod("CurrentManaGainedAsWardOnBlock", "BASE", num) }
end
-- @leb-regression-guard:ward-stop-moving-config-amortize (parser site)
-- Event-driven resource→ward conversion on stop moving (Transient Rest unique,
-- "(40-60)% of Current Mana gained as Ward when you stop moving (2 second
-- cooldown)"). Game-side field `Character.currentManaGainedAsWardOnStopMoving`
-- (datamined game source, offset 0xDB0) with const cooldown 2s (L95851). Distinct
-- from `currentManaGainedAsWardPerSecond` (L95820, offset 0xD38, continuous).
-- Before this pattern the line fell through to LEB_NotSupported (silent
-- failure: see ModCache L15263). The contribution is gated by Config tab
-- `conditionStoppedMoving` and amortized as `currentMana * pct / 100 / 2` in
-- CalcPerform's post-offence ward fold-in (only when the Condition is on).
-- See REGRESSION_GUARDS.md "ward-stop-moving-config-amortize".
specialModList["^%+?([%d%.]+)%% of current mana gained as ward when you stop moving %(2 second cooldown%)$"] = function(num)
	return { mod("CurrentManaGainedAsWardOnStopMoving", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% current mana gained as ward when you stop moving %(2 second cooldown%)$"] = function(num)
	return { mod("CurrentManaGainedAsWardOnStopMoving", "BASE", num) }
end
-- Defensive: cooldown-suffix-stripped variants (in case future data drops the
-- parenthetical; game text currently always includes it).
specialModList["^%+?([%d%.]+)%% of current mana gained as ward when you stop moving$"] = function(num)
	return { mod("CurrentManaGainedAsWardOnStopMoving", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% current mana gained as ward when you stop moving$"] = function(num)
	return { mod("CurrentManaGainedAsWardOnStopMoving", "BASE", num) }
end
-- @leb-regression-guard:ward-on-cast-health-config-amortize (parser site)
-- Event-driven Current Health -> Ward conversion when you DIRECTLY cast a spell
-- of a given school. Two game sources (property-98 family):
--   * Twisted Heart of Uhkeiros (uniques_1_4 #216): both a Necrotic and an
--     Elemental variant, "(5-8)% of Current Health converted to Ward when you
--     directly cast a {Necrotic|Elemental} Spell".
--   * crafted/sealed affix 766 (ModItem_1_4.json, Necrotic variant, 1-7%).
-- Distinct school -> distinct BASE mod so each can be gated on its own Config
-- toggle (`Condition:DirectlyCast{Necrotic|Elemental}SpellRecently`). Before
-- these patterns the generic `% of X converted to Y` handler
-- (attrConvertedHandler) intercepted and fell through to LEB_NotSupported (see
-- ModCache stale entries). These literal patterns out-score the generic one in
-- scan() (same start/end span -> longer pattern string wins). The per-cast
-- amount is amortized into a steady-state Ward per Second in CalcPerform's
-- post-offence fold-in (per-cast Life% x cast rate), gated on the Config toggle
-- and EXCLUDED from the passive-WPS floor snapshot (event-driven, like the
-- on-block / on-stop-moving / mana-spent ward sources). Default off so corpus
-- baseline parity is preserved. See REGRESSION_GUARDS.md
-- "ward-on-cast-health-config-amortize".
specialModList["^%+?([%d%.]+)%% of current health converted to ward when you directly cast a necrotic spell$"] = function(num)
	return { mod("CurrentHealthGainedAsWardOnCastNecrotic", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% current health converted to ward when you directly cast a necrotic spell$"] = function(num)
	return { mod("CurrentHealthGainedAsWardOnCastNecrotic", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% of current health converted to ward when you directly cast an elemental spell$"] = function(num)
	return { mod("CurrentHealthGainedAsWardOnCastElemental", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% current health converted to ward when you directly cast an elemental spell$"] = function(num)
	return { mod("CurrentHealthGainedAsWardOnCastElemental", "BASE", num) }
end
-- @leb-regression-guard:ward-on-potion-use-resource-conversion (parser site)
-- Event-driven resource→ward conversion on potion use.
--   * "X% [of] Missing Health gained as Ward on Potion Use" — Shield/idol affix
--     (multi_affix 57778 "Maximum Potion Slots and Missing Health gained as Ward
--     on Potion Use" and similar). Before this pattern the bare `+N%` form was
--     mis-parsed as Life INC (silent failure; see ModCache stale entries).
--   * "X% [of] Potion Health Converted to Ward" — idol affix (multi_affix 43665).
--     The "of potion health converted to ward" keyword exists in modNameList
--     but the generic `% of X converted to Y` handler (attrConvertedHandler)
--     intercepts first and falls through to LEB_NotSupported. Explicit pattern
--     here wins by being listed before the generic converted-to handler.
-- CalcDefence consumes these after Life is finalised. See REGRESSION_GUARDS.md
-- "ward-on-potion-use-resource-conversion".
specialModList["^%+?([%d%.]+)%% of missing health gained as ward on potion use$"] = function(num)
	return { mod("MissingHealthGainedAsWardOnPotionUse", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% missing health gained as ward on potion use$"] = function(num)
	return { mod("MissingHealthGainedAsWardOnPotionUse", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% of potion health converted to ward$"] = function(num)
	return { mod("PotionHealthConvertedToWard", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% potion health converted to ward$"] = function(num)
	return { mod("PotionHealthConvertedToWard", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% of (.+) gained as (.+)$"] = nsAny
-- "X% Endurance Threshold added as Ward Decay Threshold" — gear/idol affix that
-- adds a percentage of the player's *final* Endurance Threshold to Ward Decay
-- Threshold. Emits EnduranceThresholdAddedAsWardDecayThreshold (BASE %); CalcPerform
-- consumes it after EnduranceThreshold is computed and before WardDecayThreshold.
-- Examples: ModItem_1_4.json L117953-118028 (8/9/10/11/12/14/15%), uniques 1_4 L7162.
specialModList["^%+?([%-%d%.]+)%% endurance threshold added as ward decay threshold$"] = function(num)
	return { mod("EnduranceThresholdAddedAsWardDecayThreshold", "BASE", num) }
end
specialModList["^%+?([%-%d%.]+)%% of endurance threshold added as ward decay threshold$"] = function(num)
	return { mod("EnduranceThresholdAddedAsWardDecayThreshold", "BASE", num) }
end
-- @leb-regression-guard:foot-of-the-mountain-dodge-to-endurance (parser site)
-- Validation provenance is retained in maintainer notes.
specialModList["^([%d%.]+)%% of dodge rating converted to endurance threshold while you have at least 1 stack of mountains endurance$"] = function(num)
	return { mod("DodgeRatingConvertedToEnduranceThreshold", "BASE", num, "", 0, 0, { type = "Condition", var = "Stationary" }) }
end
-- Season 4 (1.4) attribute → mastery conversion. e.g. "100% of Strength Converted
-- to Brutality" on corrupted-affix unique amulets (1083_*..1087_*). Emits the
-- *ConvertedTo* mod that CalcPerform reads to move points from base attribute
-- to its S4 variant. Falls back to nsAny for non-attribute "X converted to Y".
local s4AttrConversion = {
	["strength"]     = { dst = "Brutality", mod = "StrengthConvertedToBrutality" },
	["intelligence"] = { dst = "Madness",   mod = "IntelligenceConvertedToMadness" },
	["dexterity"]    = { dst = "Guile",     mod = "DexterityConvertedToGuile" },
	["attunement"]   = { dst = "Apathy",    mod = "AttunementConvertedToApathy" },
	["vitality"]     = { dst = "Rampancy",  mod = "VitalityConvertedToRampancy" },
}
-- Per-skill delivery-type conversion ("100% of Heartseeker converted to
-- Throwing" on Ravager's Dart helmet). Emits a SkillTagSwap_<Canonical>
-- LIST mod that CalcSetup's cap-summing path reads to remap the skill's
-- delivery tag bit (Bow/Melee/Throwing/Spell) before evaluating
-- "+to <Cat> Skills" affixes. SkillsTab consumes the same list for the
-- Scaling Tags tooltip row so display matches in-game.
local deliverySwapTypes = {
	melee = SkillType.Melee, throwing = SkillType.Throwing,
	bow = SkillType.Bow, spell = SkillType.Spell,
}
local function attrConvertedHandler(num, _, src, dst)
	local entry = s4AttrConversion[(src or ""):lower()]
	if entry and (dst or ""):lower() == entry.dst:lower() then
		return { mod(entry.mod, "BASE", num) }
	end
	-- Skill-scoped delivery conversion: 100% of <Skill> converted to <Type>
	if num and tonumber(num) and tonumber(num) >= 100 then
		local canonical = canonicalSkillName(src)
		local dstBit = deliverySwapTypes[(dst or ""):lower()]
		if canonical and dstBit then
			return { mod("SkillTagSwap_" .. canonical:gsub("%s+", ""), "LIST",
				{ skillName = canonical, deliveryBit = dstBit }) }
		end
	end
	return nsAny(num)
end
specialModList["^%+?([%d%.]+)%% of (.+) converted to (.+)$"] = attrConvertedHandler

-- Vial of Volatile Ice (uniques_1_4 #331) skill-scoped ailment-CHANCE conversion:
-- "Poison Chance from all sources is converted to Frostbite Chance for Acid Flask".
-- (Historical note: this was recognition-only until the chance->chance conversion
-- engine landed; the source chance must be removed from ALL downstream consumers, so
-- the older raw reads of modDB:Sum("BASE", skillCfg, "PoisonChance") were redirected to
-- read the post-conversion output.PoisonChance. Shared with Apex of Thought's
-- glyph-gated ailment->resist-shred-chance conversion below.)
-- @leb-regression-guard:chance-chance-conversion (parse site, Vial of Volatile Ice)
-- FAITHFUL implementation: emit a structured AilmentChanceConversion LIST mod tagged
-- with SkillName=Acid Flask. CalcOffence's conversion stage (after the ailment-chance
-- BASE sums, before the ailment-DPS loop) moves the active skill's PoisonChance into
-- FrostbiteChance and zeroes the source -- but ONLY when the active skill is Acid Flask
-- (the SkillName tag is resolved by modDB:List(skillCfg, ...)). For any other skill the
-- mod is filtered out, so PoisonChance is untouched (skill-scope is exact, no global
-- leak). The conversion is unconditional (no "while" clause) for Acid Flask.
-- Spec: spec/System/TestChanceChanceConversion_spec.lua
-- See REGRESSION_GUARDS.md "chance-chance-conversion".
specialModList["^poison chance from all sources is converted to frostbite chance for acid flask$"] = function()
	local acidFlask = canonicalSkillName("Acid Flask")
	if not acidFlask then return nsAny(100) end
	return { mod("AilmentChanceConversion", "LIST", { source = "PoisonChance", dest = "FrostbiteChance" }, "", 0, 0,
		{ type = "SkillName", skillName = acidFlask }) }
end

-- @leb-regression-guard:chance-chance-conversion (parse site, Apex of Thought)
-- Apex of Thought (uniques_1_4 #316) glyph-gated ailment-CHANCE -> resist-shred-CHANCE
-- conversion. The datamine packs the three in-game conversions into ONE combined string:
--   "100% of Ignite Shock and Chill Chance converted to Fire Lightning and Cold
--    Resistance Shred Chance while standing on your Glyph of Dominion"
-- which in-game reads as: 100% of Ignite Chance -> Fire Res Shred Chance, 100% of Shock
-- Chance -> Lightning Res Shred Chance, 100% of Chill Chance -> Cold Res Shred Chance,
-- all gated on "while standing on your Glyph of Dominion". Emit three AilmentChanceConversion
-- LIST mods, each tagged with Condition:StandingOnGlyphOfDominion (reusing the existing
-- config var conditionStandingOnGlyphOfDominion -- no new config). When the config is OFF
-- the mods are filtered out by modDB:List, so the ailment chances are untouched (no-op).
-- When ON, CalcOffence's conversion stage moves each source chance into its dest chance
-- and zeroes the source, so the three ailments stop applying and the three res-shred
-- chances gain the moved value. The conversion is player-global (no SkillName tag) per the
-- tooltip wording ("100% of your Ignite Chance ...").
-- ModCache.lua baked this combined string as LEB_NotSupported notSupported=true; that row
-- is removed in the same commit so the build live-parses through this handler.
-- Spec: spec/System/TestChanceChanceConversion_spec.lua
-- See REGRESSION_GUARDS.md "chance-chance-conversion".
specialModList["^100%% of ignite shock and chill chance converted to fire lightning and cold resistance shred chance while standing on your glyph of dominion$"] = function()
	local glyphTag = { type = "Condition", var = "StandingOnGlyphOfDominion" }
	return {
		mod("AilmentChanceConversion", "LIST", { source = "IgniteChance", dest = "FireResShredChance" }, "", 0, 0, glyphTag),
		mod("AilmentChanceConversion", "LIST", { source = "ShockChance", dest = "LightningResShredChance" }, "", 0, 0, glyphTag),
		mod("AilmentChanceConversion", "LIST", { source = "ChillChance", dest = "ColdResShredChance" }, "", 0, 0, glyphTag),
	}
end

-- @leb-regression-guard:chance-chance-conversion (parse site, Liath's Machinations)
-- Liath's Machinations (Amulet, uniques_1_4.json #276) skill-scoped ailment-CHANCE
-- conversion. Verbatim datamine mod string (uniques_1_4.json #276):
--   "100% of Ignite Chance Converted to Shock Chance for Fireball"
-- The same amulet also converts 50% of Fireball's base damage to Lightning, so a
-- Fireball that shocks instead of ignites is the in-game intent. Mirrors the Vial of
-- Volatile Ice handler above: emit a structured AilmentChanceConversion LIST mod tagged
-- with SkillName=Fireball. CalcOffence's conversion stage (after the ailment-chance BASE
-- sums, before the ailment-DPS loop) moves the active skill's IgniteChance into
-- ShockChance and zeroes the source -- but ONLY when the active skill is Fireball (the
-- SkillName tag is resolved by modDB:List(skillCfg, ...)). For any other skill the mod is
-- filtered out, so IgniteChance is untouched (skill-scope is exact, no global leak). The
-- conversion is unconditional (no "while" clause) for Fireball. NOTE: ShockChance is a
-- debuff chance, NOT a damaging-ailment DoT -- the engine simply moves the 0-100 chance
-- value into output.ShockChance (CalcOffence ~L1957), so no DoT pipeline is involved.
-- This was recognition-only (LEB_NotSupported) in ModCache.lua until now; that row is
-- removed so the build live-parses through this handler.
-- Spec: spec/System/TestChanceChanceConversion_spec.lua
-- See REGRESSION_GUARDS.md "chance-chance-conversion".
specialModList["^100%% of ignite chance converted to shock chance for fireball$"] = function()
	local fireball = canonicalSkillName("Fireball")
	if not fireball then return nsAny(100) end
	return { mod("AilmentChanceConversion", "LIST", { source = "IgniteChance", dest = "ShockChance" }, "", 0, 0,
		{ type = "SkillName", skillName = fireball }) }
end

-- @leb-regression-guard:ailment-scoped-penetration (parse site, Salt the Wound)
-- "(N)% of added Critical Strike Multiplier Converted to <Type> Penetration with <Ailment>"
-- (Salt the Wound #187, un-baked from ModCache). Emit a CritMultToAilmentPen LIST mod
-- { ailment, pct }; CalcOffence's consumer turns pct% of the added crit multiplier into an
-- Ailment<Name>Penetration BASE mod (ailment-scoped, never hits). General over single-word
-- ailments; the pen damage type is intrinsic to the ailment so the "<Type>" word is matched
-- but not captured. Unconditional (no skill/condition tag).
-- Dispatch convention (see L4016): specialMod(tonumber(cap[1]), unpack(cap)) -> a 2-capture
-- pattern reaches the handler as (num, rawNumStr, ailmentStr), so the ailment is the THIRD arg.
-- Spec: spec/System/TestAilmentScopedPenetration_spec.lua
-- See REGRESSION_GUARDS.md "ailment-scoped-penetration".
specialModList["^([%d%.]+)%% of added critical strike multiplier converted to %a+ penetration with (%a+)$"] = function(num, _, ailment)
	local canon = ailment:sub(1,1):upper() .. ailment:sub(2)
	return { mod("CritMultToAilmentPen", "LIST", { ailment = canon, pct = num }, "", 0, 0) }
end

-- @leb-regression-guard:chance-chance-conversion (parse site, Carrion of Creation)
-- Carrion of Creation (uniques_1_4.json #431, primordial) GLOBAL ailment-CHANCE
-- conversion. The unique carries six separate verbatim datamine mod strings, one per
-- ailment, which read in-game as the combined tooltip
--   "100% of Ignite, Frostbite, Shock, Time Rot, Damned, and Poison Chance Converted
--    to Bleed Chance."
-- i.e. 100% of SIX ailment chances -> Bleed Chance, applied to ALL skills, with no
-- "while" clause and no "for <skill>" scope. This is the first chance->chance unique
-- that is neither glyph-gated (Apex) nor skill-scoped (Vial/Liath): it is player-GLOBAL.
--
-- We emit ONE untagged AilmentChanceConversion LIST mod per ailment. The absence of a
-- tag is load-bearing: in ModStoreClass:ListInternal a LIST mod with no tag element
-- (mod[1] == nil) takes the `elseif mod.value then` branch and is inserted UNCONDITIONALLY
-- for every cfg (no EvalMod/tag check), so modDB:List(skillCfg, "AilmentChanceConversion")
-- returns these for ANY skill -- the faithful global scope. (Tagged mods -- Apex Condition,
-- Vial/Liath SkillName -- go through EvalMod and are filtered when inactive.) CalcOffence's
-- conversion stage (~L2017) then moves each source <X>Chance into BleedChance (re-capped at
-- 100) and zeroes the source, for every skill. All six source stats and BleedChance are
-- summed as output.<X>Chance just above that loop (CalcOffence ~L1954-1968), so the
-- `output[src] ~= nil and output[dst] ~= nil` guard passes for all six.
--
-- Pattern: literal-anchored on "100% of <ailment> chance converted to bleed chance" so it
-- out-scores the generic `% of (.+) converted to (.+)` (attrConvertedHandler) in scan()
-- (same start/end span -> longer pattern wins), same as the Apex/Vial/Liath handlers. The
-- captured ailment name is mapped to its source-chance stat; an unknown ailment name (or
-- "bleed" itself, which would be a no-op self-conversion) returns nsAny (recognition-only),
-- so the handler never fabricates a conversion for an ailment LEB doesn't track.
-- These six strings were recognition-only (LEB_NotSupported) in ModCache.lua until now;
-- those rows are removed so the build live-parses through this handler.
-- Spec: spec/System/TestChanceChanceConversion_spec.lua
-- See REGRESSION_GUARDS.md "chance-chance-conversion".
local ailmentChanceToBleedSources = {
	["ignite"]    = "IgniteChance",
	["frostbite"] = "FrostbiteChance",
	["shock"]     = "ShockChance",
	["time rot"]  = "TimeRotChance",
	["damned"]    = "DamnedChance",
	["poison"]    = "PoisonChance",
}
specialModList["^100%% of (.+) chance converted to bleed chance$"] = function(_, ailment)
	local source = ailmentChanceToBleedSources[(ailment or ""):lower()]
	if not source then return nsAny(100) end
	-- Untagged => global (applies to every skill cfg). See ListInternal note above.
	return { mod("AilmentChanceConversion", "LIST", { source = source, dest = "BleedChance" }, "", 0, 0) }
end

-- @leb-regression-guard:chance-chance-conversion (parse site, Maehlin's Hubris)
-- Maehlin's Hubris (Mage Helmet, uniques_1_4.json #83) GLOBAL ailment-CHANCE conversion.
-- Verbatim datamine mod string (uniques_1_4.json #83):
--   "100% of Bleed Chance Converted to Ignite Chance"
-- Datamine encode (datamined game source uniqueID 83, first
-- mod): value 1.0 (= 100%), canRoll false (fixed -> rollId null in LEB JSON), property
-- 100 (Bleed->Ignite chance-conversion property), specialTag 2, no "for/with <skill>"
-- clause -> player-GLOBAL (Carrion of Creation #431 is the same untagged-global class;
-- Liath/Vial/Troaka carry a skill restriction, Maehlin does not). 100% of the source
-- converts, applied to ALL skills, with no "while" clause and no skill scope.
--
-- Like Carrion, we emit ONE untagged AilmentChanceConversion LIST mod. The absence of a
-- tag is load-bearing: in ModStoreClass:ListInternal a LIST mod with no tag element
-- (mod[1] == nil) takes the `elseif mod.value then` branch and is inserted UNCONDITIONALLY
-- for every cfg (no EvalMod/tag check), so modDB:List(skillCfg, "AilmentChanceConversion")
-- returns it for ANY skill -- the faithful global scope. CalcOffence's conversion stage
-- (~L2017) then moves output.BleedChance into output.IgniteChance (re-capped at 100) and
-- zeroes BleedChance, for every skill. Both stats are summed as output.<X>Chance just
-- above that loop (CalcOffence ~L1954-1959), so the `output[src] ~= nil and output[dst]
-- ~= nil` guard passes.
--
-- Pattern: literal-anchored on the full string so it out-scores the generic
-- `% of (.+) converted to (.+)` (attrConvertedHandler) in scan() -- same start/end span,
-- the longer literal pattern wins the `#pattern > #bestPattern` tiebreak (L3797), same as
-- the Apex/Vial/Liath/Carrion handlers. This string was recognition-only (LEB_NotSupported,
-- via the generic handler -> nsAny) until now. ModCache.lua never baked it (no row to
-- remove). Spec: spec/System/TestChanceChanceConversion_spec.lua
-- See REGRESSION_GUARDS.md "chance-chance-conversion".
specialModList["^100%% of bleed chance converted to ignite chance$"] = function()
	-- Untagged => global (applies to every skill cfg). See ListInternal note above.
	return { mod("AilmentChanceConversion", "LIST", { source = "BleedChance", dest = "IgniteChance" }, "", 0, 0) }
end

-- @leb-regression-guard:chance-chance-conversion (parse site, Troaka's Teeth)
-- Troaka's Teeth (Bow, uniques_1_4.json #146) skill-scoped TWO-SOURCE ailment-CHANCE
-- conversion. Verbatim datamine mod string (uniques_1_4.json #146):
--   "100% of Bleed and Poison Chance converted to Frostbite Chance with Puncture"
-- Datamine encode (datamined game source uniqueID 146, fifth
-- mod): value 1.0 (= 100%), canRoll false (fixed -> rollId null in LEB JSON), property 58
-- (the ailment-chance->ailment-chance conversion property shared with Liath's #276 Ignite->
-- Shock), specialTag 2. The "with Puncture" clause scopes it to a single skill (Puncture is
-- a registered skill, skills.json "Puncture", canonicalSkillName resolves it). Mirrors the
-- Vial/Liath SkillName path, but TWO sources collapse into ONE dest: both Bleed Chance AND
-- Poison Chance become Frostbite Chance for Puncture only.
--
-- Emit TWO SkillName=Puncture-tagged AilmentChanceConversion LIST mods:
-- {Bleed->Frostbite} and {Poison->Frostbite}. modDB:List(skillCfg, ...) resolves the
-- SkillName tag, so both are returned ONLY for a Puncture cfg; any other skill gets neither
-- (Bleed/Poison chance untouched, skill-scope is exact, no global leak). CalcOffence's
-- conversion stage (~L2017) runs both: it moves output.BleedChance into output.FrostbiteChance
-- (re-capped at 100, source zeroed), then moves output.PoisonChance into output.FrostbiteChance
-- (accumulating, re-capped at 100, source zeroed) -- so a Puncture that bleeds+poisons instead
-- frostbites, with the two chances summed into Frostbite. All three stats are summed as
-- output.<X>Chance just above that loop (CalcOffence ~L1954-1959), so the
-- `output[src] ~= nil and output[dst] ~= nil` guard passes for both.
--
-- Pattern: literal-anchored on the full string so it out-scores the generic
-- `% of (.+) converted to (.+)` in scan() (same span, longer literal wins). If Puncture
-- ever fails to resolve (skill data missing) we fall back to nsAny (recognition-only) rather
-- than fabricate an unscoped conversion. This string was recognition-only (LEB_NotSupported,
-- via the generic handler -> nsAny) until now. ModCache.lua never baked it (no row to remove).
-- Spec: spec/System/TestChanceChanceConversion_spec.lua
-- See REGRESSION_GUARDS.md "chance-chance-conversion".
specialModList["^100%% of bleed and poison chance converted to frostbite chance with puncture$"] = function()
	local puncture = canonicalSkillName("Puncture")
	if not puncture then return nsAny(100) end
	local skillTag = { type = "SkillName", skillName = puncture }
	return {
		mod("AilmentChanceConversion", "LIST", { source = "BleedChance", dest = "FrostbiteChance" }, "", 0, 0, skillTag),
		mod("AilmentChanceConversion", "LIST", { source = "PoisonChance", dest = "FrostbiteChance" }, "", 0, 0, skillTag),
	}
end

-- @leb-regression-guard: game-faithful-parry-conversion
-- "+N Block Chance converted to Parry Chance while not wielding a shield" — the only
-- known source is the unique sword `Clotho's Needle` (uniques_1_4.json #417, mod text
-- "+1 Block Chance converted to Parry Chance while not wielding a shield"). Game-faithful
-- behavior per datamined game source (datamined game source):
--   * Property #531 `playerPropertyBlockChanceConvertedToParryWithoutShield` is a bool
--     set unconditionally by the mod; when set AND no shield, blockConversion=Parry.
--   * `blockChanceForCharacterSheet` (datamined offset) returns 0 when blockConversion!=None.
--   * `parryChanceForCharacterSheet` (datamined offset) when blockConversion==Parry returns
--     min(blockBase, maxBlock) + parryBonus, capped at ParryCap (75).
-- Implementation: emit BlockChance BASE +N (unconditional, joins regular block pool)
-- AND a FLAG mod `BlockChanceConvertedToParryWithoutShield`. CalcDefence checks the
-- flag + UsingShield condition and routes Block→Parry per the datamining semantics.
-- Note: ModCache.lua L1325 previously parsed this as a stray "+1 BlockChance BASE"
-- mod with residual extra "converted to Parry Chance while not wielding a shield" —
-- the residual was non-connector so Item.lua processModLine silently dropped the
-- entire mod (no current build was affected). This explicit handler consumes the
-- whole string and produces the correct conversion semantics.
-- Spec: spec/System/TestParryConversion_spec.lua
specialModList["^%+?(%-?[%d%.]+) block chance converted to parry chance while not wielding a shield$"] = function(num)
	return {
		mod("BlockChance", "BASE", num),
		flag("BlockChanceConvertedToParryWithoutShield"),
	}
end

-- "N <resource> gained when you use <skill>" variants (already covered per-skill above,
-- but catch unknown-skill phrasing as recognition-only)
specialModList["^%+?(%d+) (%a+) gained when you use (.+)$"] = nsAny
specialModList["^%+?(%d+) (%a+) gained when hit$"] = nsAny
specialModList["^%+?(%d+) (%a+) gained when you are hit$"] = nsAny
specialModList["^%+?(%d+) (%a+) gained on kill$"] = nsAny
specialModList["^%+?(%d+) (%a+) gained on crit$"] = nsAny
specialModList["^%+?(%d+) (%a+) gained on hit$"] = nsAny

-- Flat "while wielding" / "while dual wielding" intentionally NOT added here.
-- modTagList already has "while wielding a <weapon>" and "while dual wielding" as
-- proper Condition tags that the generic parse chain combines with any stat name.
-- Catching them in specialModList would shadow real DPS-integrated mods.

-- Buff-duration grants after action (e.g. "1 second of Haste after you Transform",
--                                         "4 seconds of Haste after you use Evade")
specialModList["^%+?(%d+) seconds? of (.+) after you (.+)$"] = nsAny
specialModList["^%+?(%d+) seconds? of (.+) on (.+)$"] = nsAny
specialModList["^%+?(%d+) seconds? of (.+) when (.+)$"] = nsAny

-- Per-active / per-equipped / per-stack multipliers
-- DPS-integrated when the tail noun matches a known multiplier (handled via modTagList
-- entries above — e.g. "per active Rune" → Multiplier:ActiveRune with a Config count).
-- Unknown tail nouns fall through to nsAny for recognition only.
local knownPerActive = {
	["totem"] = true, ["totems"] = true,
	["symbol"] = true, ["symbols"] = true,
	["shadow"] = true, ["shadows"] = true,
	["rune"] = true, ["runes"] = true,
	["dread shade"] = true, ["dread shades"] = true,
	["maelstrom"] = true, ["maelstroms"] = true,
	["wandering spirit"] = true, ["wandering spirits"] = true,
	["crimson shroud"] = true, ["crimson shrouds"] = true,
}
local knownPerEquipped = {
	["sword"] = true, ["swords"] = true,
	["dagger"] = true, ["daggers"] = true,
	["omen idol"] = true, ["omen idols"] = true,
	-- @leb-regression-guard: weaver-will-equipped-autocount
	-- "weaver item(s)" is the legacy/saved-build noun; "weaver's will item(s)"
	-- is the game-accurate datamining phrasing (Unique_Tooltip_1_327). Both must
	-- route through perEquippedHandler -> nil (fall through to the generic
	-- parser) so modTagList "per equipped weaver('s will) item" attaches
	-- Multiplier:EquippedWeaverItem. Without the "weaver's will item" keys the
	-- handler returned nsAny -> LEB_NotSupported and the per-item scaling dropped.
	["weaver item"] = true, ["weaver items"] = true,
	["weaver's will item"] = true, ["weaver's will items"] = true,
	["heretical idol"] = true, ["huge idol"] = true, ["ornate idol"] = true,
	["grand idol"] = true, ["large idol"] = true, ["adorned idol"] = true,
	["stout idol"] = true, ["humble idol"] = true, ["small idol"] = true,
	["minor idol"] = true, ["corrupted idol"] = true,
}
-- Handler args: (num, cap1_str, stat, tailNoun). Only tailNoun matters for routing.
local function perActiveHandler(num, _, _, tailNoun)
	if tailNoun and knownPerActive[tailNoun:lower()] then
		return nil  -- fall through to generic parser (modTagList carries the Multiplier)
	end
	return nsAny(num)
end
local function perEquippedHandler(num, _, _, tailNoun)
	if tailNoun and knownPerEquipped[tailNoun:lower()] then
		return nil
	end
	return nsAny(num)
end
specialModList["^%+?([%d%.]+)%% increased (.+) per active (.+)$"] = perActiveHandler
specialModList["^%+?([%d%.]+)%% reduced (.+) per active (.+)$"] = perActiveHandler
specialModList["^%+?([%d%.]+)%% more (.+) per active (.+)$"] = perActiveHandler
specialModList["^%+?([%d%.]+)%% less (.+) per active (.+)$"] = perActiveHandler
specialModList["^%+?([%d%.]+)%% increased (.+) per equipped (.+)$"] = perEquippedHandler
specialModList["^%+?([%d%.]+)%% reduced (.+) per equipped (.+)$"] = perEquippedHandler
specialModList["^%+?([%d%.]+)%% chance to (.+) per active (.+)$"] = perActiveHandler
specialModList["^%+?([%d%.]+)%% chance to (.+) per equipped (.+)$"] = perEquippedHandler
specialModList["^%+?([%d%.]+) (.+) per active (.+)$"] = perActiveHandler
specialModList["^%+?([%d%.]+) (.+) per equipped (.+)$"] = perEquippedHandler

-- Exotic chance-to-cast triggers with qualifier / trailing parenthetical
-- (e.g. "+5% Chance to cast Fire Aura on Kill with Fire Skills (1 second cooldown)",
--       "+5% Chance to cast Smite on Hit with Throwing Attacks (up to 10 times per 2 seconds)")
specialModList["^%+?([%d%.]+)%% chance to cast (.+) on (.+) with (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to cast (.+) on (.+) with (.+) %(.+%)$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to cast (.+) on (.+) %(.+%)$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to cast (.+) when you (.+) %(.+%)$"] = nsAny

-- Non-idol item affix recognition catch-alls (found via data scan)

-- 1. "Chance for <outcome> when you <action>" / 2. "Chance for <static outcome>"
specialModList["^%+?([%d%.]+)%% chance for (.+) when you (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance for (.+) on (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance for (.+) to (.+)$"] = nsAny

-- 3. Ailment chance per second (e.g. "X% Frostbite Chance per Second with Frost Wall")
specialModList["^%+?([%d%.]+)%% (.+) chance per second with (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% (.+) chance per second$"] = nsAny

-- 4. While-channelling modifier (e.g. "X% Endurance while channelling Warpath")
-- DPS-integrated for the subset of stat+skill combos actually present in affix data
-- (Endurance while channelling Warpath; Ward per Second while channelling Ghostflame).
-- Other variants fall through to nsAny recognition.
-- Mechanic: Condition:Channelling<Skill> is set by CalcPerform when the player is
-- channelling AND their main skill matches. This double-gates by skill identity.
for _lowerCh, _canonicalCh in pairs(skillNameByLower) do
	if not skillNameBlacklist[_lowerCh] then
		local _escCh = escPat(_lowerCh)
		local _condVar = "Channelling" .. _canonicalCh:gsub("%s+", "")
		-- Endurance while channelling <skill>
		specialModList["^%+?([%d%.]+)%% endurance while channell?ing " .. _escCh .. "$"] = function(num)
			return { mod("Endurance", "BASE", num, "", 0, 0, { type = "Condition", var = _condVar }) }
		end
		-- Ward per Second while channelling <skill>
		specialModList["^%+?([%d%.]+) ward per second while channell?ing " .. _escCh .. "$"] = function(num)
			return { mod("WardPerSecond", "BASE", num, "", 0, 0, { type = "Condition", var = _condVar }) }
		end
		-- @leb-regression-guard:skill-grants-ward-per-second
		-- "<Skill> Grants Ward Gain Per Second" — Rune Master Disintegrate node
		-- (tree_1.json L10164 "Runes of Disintegration", stat "+40 Disintegrate
		-- Grants Ward Gain Per Second"). Description gates the effect on
		-- "channelling Disintegrate while standing on your Glyph"; the build
		-- planner models the steady state by gating on Channelling<Skill> only —
		-- the on-Glyph sub-condition is the player's intended play pattern and is
		-- consistent with how other channelling-WPS handlers ignore positional
		-- sub-conditions. Without this handler the line fell through to
		-- name="Ward" (max ward) with residue "  Grants  Gain Per Second ".
		specialModList["^%+?([%d%.]+) " .. _escCh .. " grants ward gain per second$"] = function(num)
			return { mod("WardPerSecond", "BASE", num, "", 0, 0, { type = "Condition", var = _condVar }) }
		end
	end
end
-- Fallback: unknown stat/skill combos still get recognised (but flagged unsupported).
specialModList["^%+?([%d%.]+)%% (.+) while channelling (.+)$"] = nsAny
specialModList["^%+?([%d%.]+) (.+) while channelling (.+)$"] = nsAny

-- @leb-regression-guard:health-per-second-channelling
-- Acolyte/Sentinel-style "Focus" channelled-skill tree node "Inner Growth"
-- (Mage tree_1.json L17197 "vm53dx-14"):
--     stats: "6 Health Per Second"
--     description: "Focus heals the target each second while channeled."
--     reminderText: "This effect is affected by increased healing effectiveness."
-- Before this guard the line fell through to `name="Life"` BASE=6 with
-- residue "  Per Second " — silently granting +6 *max* Health, completely
-- unrelated to the actual mechanic. The fix routes the bare "+N Health Per
-- Second" form to LifeRegen BASE=N gated on Condition:Channelling so the
-- regen only contributes while the player is channelling (CalcPerform sets
-- the condition from mainSkill type, and the Config tab "Are you
-- Channelling?" toggle lets the user dial in the steady state).
specialModList["^%+?([%d%.]+) health per second$"] = function(num)
	return { mod("LifeRegen", "BASE", num, "", 0, 0, { type = "Condition", var = "Channelling" }) }
end

-- @leb-regression-guard:minion-health-regen-per-second
-- Acolyte tree node "Blood Armor" (tree_3.json Acolyte-21) scaling stat is
--     "+6 Minion Health Regen Per Second"
-- (analogous +2 entry exists in 1_2 tree_3.json). The "Minion" prefix routes
-- to MinionModifier and "Health Regen" maps to LifeRegen via nameMap, but the
-- trailing "Per Second" survives as residue. modLib.parseMod sets
-- node.extra=true on residue and PassiveTree.lua silently drops the entire
-- mod from modDB — losing 6×ranks of minion regen on every Necromancer/
-- Lich/Warlock build that takes Blood Armor.
--
-- Triangulation case (g1 <private build> lv99 Necromancer, Acolyte-21#8):
--   expected: +48 Minion Health Regen → output.MinionLifeRegen = 186 + 48 = 234
--   observed (pre-fix): MinionLifeRegen = 186 (Pebbles' Collar only)
--   LETools Minion tab: Health Regen = 234. Δ matches the missing node grant.
--
-- Routes the bare "+N Minion Health Regen Per Second" form directly to a
-- MinionModifier LIST wrapping LifeRegen BASE=N, consuming the full line so
-- no residue remains. Mirrors the existing +N Minion Health Regen path
-- (which works because no "per second" suffix is present).
-- Spec: spec/System/TestMinionHealthRegenPerSecond_spec.lua
specialModList["^%+?(%d+) minion health regen per second$"] = function(num)
	return { mod("MinionModifier", "LIST", { mod = mod("LifeRegen", "BASE", num) }) }
end
specialModList["^%+?(%d+) minion life regen per second$"] = function(num)
	return { mod("MinionModifier", "LIST", { mod = mod("LifeRegen", "BASE", num) }) }
end

-- @leb-regression-guard:channelling-per-second-stacking-buff
-- Channelling-stacking-buff "Per Second" Damage nodes such as
--   Smelter's Wrath "+5% Damage Per Second" (tree_2.json L14336)
--   Flurry "Accelerating Impact" "+3% Damage Per Second" (flur3-14)
--   Volcanic Orb "+20% Damage Per Second" (tree_2.json va53st-19)
-- gain a stack each second while the player is channelling, granting
-- +N% MORE Damage per stack. Before this guard the bare form fell
-- through to a flat `Damage MORE` with residue "  Per Second " —
-- silently granting the full N% MORE Damage unconditionally,
-- independent of channelling state or stack count.
--
-- The fix routes the bare "+N% damage per second" form to
-- `Damage MORE` gated on Condition:Channelling AND multiplied by
-- Multiplier:ChannellingSeconds (Config tab "# of Channelling
-- Seconds"). The result is N% MORE Damage × seconds while channelling
-- and 0 otherwise.
specialModList["^%+?([%d%.]+)%% damage per second$"] = function(num)
	return { mod("Damage", "MORE", num, "", 0, 0, { type = "Condition", var = "Channelling" }, { type = "Multiplier", var = "ChannellingSeconds" }) }
end

-- @leb-regression-guard:smelters-wrath-charge-scaling-nodes
-- Test: spec/System/TestSmeltersWrathChargeNodes_spec.lua
-- Validation provenance is retained in maintainer notes.
specialModList["^%+?([%d%.]+)%% more damage per second$"] = function(num)
	return { mod("Damage", "MORE", num, "", 0, 0, { type = "Condition", var = "Channelling" }, { type = "Multiplier", var = "ChannellingSeconds" }) }
end
specialModList["^%+?([%d%.]+)%% melee damage per second$"] = function(num)
	return { mod("Damage", "MORE", num, "", 0, KeywordFlag.Melee, { type = "Condition", var = "Channelling" }, { type = "Multiplier", var = "ChannellingSeconds" }) }
end
specialModList["^%+?([%d%.]+)%% fire damage per second$"] = function(num)
	return { mod("FireDamage", "MORE", num, "", 0, 0, { type = "Condition", var = "Channelling" }, { type = "Multiplier", var = "ChannellingSeconds" }) }
end
specialModList["^%+?([%d%.]+)%% damage at full charge$"] = function(num)
	return { mod("Damage", "MORE", num, "", 0, 0, { type = "Condition", var = "FullyCharged" }) }
end
specialModList["^%+?([%d%.]+)%% more crit chance at full charge$"] = function(num)
	return { mod("CritChance", "MORE", num, "", 0, 0, { type = "Condition", var = "FullyCharged" }) }
end

-- 5. Mitigation-also-applies-to-DoT (armor/resist mitigation crossover)
specialModList["^%+?([%d%.]+)%% (.+) mitigation also applies to damage over time per (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% (.+) mitigation also applies to damage over time$"] = nsAny

-- 8. Area / stat for <skill> per active <minion> (e.g. "% Increased Area for Infernal Shade per Active Dread Shade")
specialModList["^%+?([%d%.]+)%% increased (.+) for (.+) per active (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% more (.+) for (.+) per active (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% less (.+) for (.+) per active (.+)$"] = nsAny

-- 9. Per numeric stat threshold — intentionally NOT added; modTagList already handles
-- "per N total attributes", "per N maximum mana", "per N <attribute>" etc. as PerStat
-- tags which feed proper DPS. A generic catch-all here would shadow those.

-- 10. "if wielding a <weapon>" intentionally NOT added — modTagList's weapon-condition
-- handlers ("while wielding a <weapon>") already cover the DPS-integrated case. The
-- "if wielding" phrasing in data generally normalises to the same condition.

-- 11. Per-projectile scaling ("per arrow with Multishot") — DPS-integrated for the
-- Multishot subset found in affix data (every cached instance is Multishot-only).
-- Mechanic: Multiplier:ArrowsWithMultishot is fed by the Config tab ("# of Arrows
-- with Multishot"), and the mod is also skill-gated so it only scales Multishot
-- damage. Unknown skill/stat combos still fall through to nsAny for recognition.
for _lowerAr, _canonicalAr in pairs(skillNameByLower) do
	if not skillNameBlacklist[_lowerAr] then
		local _escAr = escPat(_lowerAr)
		local _multVar = "ArrowsWith" .. _canonicalAr:gsub("%s+", "")
		specialModList["^%+?([%d%.]+)%% increased damage per arrow with " .. _escAr .. "$"] = function(num)
			return { mod("Damage", "INC", num, "", 0, 0, { type = "SkillName", skillName = _canonicalAr }, { type = "Multiplier", var = _multVar }) }
		end
		specialModList["^%+?([%d%.]+)%% increased damage per projectile with " .. _escAr .. "$"] = function(num)
			return { mod("Damage", "INC", num, "", 0, 0, { type = "SkillName", skillName = _canonicalAr }, { type = "Multiplier", var = _multVar }) }
		end
	end
end
-- Fallback: unknown stat/skill combos still get recognised.
specialModList["^%+?([%d%.]+)%% increased (.+) per arrow with (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% increased (.+) per projectile with (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% reduced (.+) per arrow with (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% reduced (.+) per projectile with (.+)$"] = nsAny

-- 11b. "Per Arrow Before Limit" — recognition only (capped multiplier, depends on
-- skill-specific arrow-limit mechanics not yet modelled).
specialModList["^%+?([%d%.]+)%% (.+) per arrow before limit$"] = nsAny

-- 12. Per forged weapon (Forge Weapon summon count)
specialModList["^%+?([%d%.]+)%% (.+) per forged weapon$"] = nsAny
specialModList["^%+?([%d%.]+) (.+) per forged weapon$"] = nsAny

-- 14. Depending on area level
-- Formula: effective = min(rolled * min(areaLevel, 75) / 75, cap)
-- implemented via existing Multiplier tag:
--   mod value = rolled / 75
--   tag: { type = "Multiplier", var = "AreaLevel", limit = 75, limitTotal = cap }
-- For single-value form ("X% Y depending on area level") cap = rolled (self-capping).
-- For ranged form ("X% to Z% Y depending on area level") cap = Z (explicit).
-- Reference: dev blog "Overhauling Defenses" — 1% per area level, scaling up to 75%.
local function areaLevelTag(cap)
    -- limit=75 clamps the area-level multiplier at 75 (dev-blog cap).
    -- valueCap clamps the final value at `cap` (either the rolled % for single-value
    -- form, or the explicit "to Z%" cap for the ranged form).
    return { type = "Multiplier", var = "AreaLevel", limit = 75, valueCap = cap }
end
-- Cursed prefix (boots): "less Damage" and "more Damage Taken", possibly with "to Z%".
specialModList["^%+?([%d%.]+)%% to ([%d%.]+)%% less damage depending on area level.*$"] = function(num, _, capStr)
    local cap = tonumber(capStr) or num
    return { mod("Damage", "MORE", -num / 75, "", 0, 0, areaLevelTag(cap)) }
end
specialModList["^%+?([%d%.]+)%% to ([%d%.]+)%% more damage taken depending on area level.*$"] = function(num, _, capStr)
    local cap = tonumber(capStr) or num
    return { mod("DamageTaken", "MORE", num / 75, "", 0, 0, areaLevelTag(cap)) }
end
specialModList["^%+?([%d%.]+)%% less damage depending on area level.*$"] = function(num)
    return { mod("Damage", "MORE", -num / 75, "", 0, 0, areaLevelTag(num)) }
end
specialModList["^%+?([%d%.]+)%% more damage taken depending on area level.*$"] = function(num)
    return { mod("DamageTaken", "MORE", num / 75, "", 0, 0, areaLevelTag(num)) }
end
-- Fallback: any other "depending on area level" phrasing stays recognition-only.
specialModList["^%+?([%d%.]+)%% (.+) depending on area level(.*)$"] = nsAny
specialModList["^%+?([%d%.]+) (.+) depending on area level(.*)$"] = nsAny

-- 15. Conditional on recent action ("if you have <action> recently")
-- @leb-regression-guard: conditional-recent-action-stat-recognition
-- These catch-all nsAny patterns previously swallowed lines whose stat name
-- AND condition phrase are BOTH known to the generic parser, demoting them
-- to LEB_NotSupported. Example: the corrupted-sealed Julra's Obsession
-- prefix "+305 Endurance Threshold if you have not been Hit Recently" was
-- intercepted here before modNameList/modTagList ever ran, producing a
-- LEB_NotSupported BASE 305 mod that CalcDefence ignored — explaining the
-- <private build> EnduranceThreshold -316 LEB-vs-LET diff. The fix: decline (return
-- nil) when the stat half resolves through modNameList AND the condition
-- half re-scans to a modTagList match, so parseMod falls through to the
-- generic chain that builds an EnduranceThreshold BASE 305 mod tagged with
-- Condition:BeenHitRecently(neg). For truly unknown stat or condition
-- phrases the handler still emits nsAny(num), preserving recognition-only
-- coverage for the long tail.
-- Spec: spec/System/TestConditionalRecentActionStatRecognition_spec.lua
local function conditionalRecentDecline(num, _, statName, condName)
    local statLower = (statName or ""):lower():match("^%s*(.-)%s*$") or ""
    local condPhrase = ("if you have " .. (condName or "") .. " recently"):lower()
    if modNameList[statLower] then
        for pattern in pairs(modTagList) do
            if condPhrase:find(pattern, 1, false) then
                return nil
            end
        end
    end
    return nsAny(num)
end
specialModList["^%+?([%d%.]+)%% (.+) if you have (.+) recently$"] = conditionalRecentDecline
specialModList["^%+?([%d%.]+) (.+) if you have (.+) recently$"] = conditionalRecentDecline
specialModList["^%+?([%d%.]+)%% (.+) if you have (.+) in the last (%d+) seconds?$"] = nsAny

-- 17. Skill-scoped base-damage type conversion
-- "X% of <Skill> Base Damage converted to <DamageType>" (e.g. Vial of Volatile Ice
-- "100% of Acid Flask Base Damage converted to Cold"). When the source resolves to a
-- canonical skill and the destination to a damage type, emit a SKILL-SCOPED
-- <srcType>DamageConvertTo<dst> BASE % for every non-dst type — mirroring
-- parseSkillNameArrowConversion (the "<Skill> -> <Type>" arrow form) so ONLY that
-- skill's base damage converts. CalcOffence's conversionTable consumes the BASE %
-- and removes the converted fraction from the source (mult = 1 - converted), so there
-- is no double-counting. A non-skill source (the generic global "base damage" with no
-- skill name) falls through to nsAny (recognition-only) — unchanged for every other
-- build. Many uniques/affixes use this form (Fury Leap/Meteor/Shurikens/etc.); their
-- ModCache rows stay baked as notSupported until removed/regenerated, so only the rows
-- explicitly removed live-parse to the new result for now: Acid Flask (Vial of Volatile
-- Ice, 100% -> Cold) and Fireball (Liath's Machinations #276, "50% of Fireball Base
-- Damage Converted to Lightning" -- a PARTIAL conversion: the 50 sets conversionTable
-- mult = 1 - 0.5, so half the Fire base stays Fire and half becomes Lightning).
-- @leb-regression-guard:skill-base-damage-conversion (parse site)
-- Spec: spec/System/TestSkillBaseDamageConversion_spec.lua
-- See REGRESSION_GUARDS.md "skill-base-damage-conversion".
local function skillBaseDamageConversionHandler(num, _, src, dst)
	local canonical = canonicalSkillName(src)
	local dstType = dmgTypeNames[dst]
	if canonical and dstType and tonumber(num) then
		local convMods = { }
		for _, srcType in ipairs(DamageTypes) do
			if srcType ~= dstType then
				t_insert(convMods, mod(srcType .. "DamageConvertTo" .. dstType, "BASE", tonumber(num), "", 0, 0,
					{ type = "SkillName", skillName = canonical }))
			end
		end
		return convMods
	end
	-- Not a skill-scoped conversion (or unresolved type): recognition-only, as before.
	return nsAny(num)
end
specialModList["^%+?([%d%.]+)%% of (.+) base damage converted to (.+)$"] = skillBaseDamageConversionHandler

-- @leb-regression-guard:stormhide-empowered-swipe (parse site)
-- Stormhide Paws (uniques_1_4.json #202) carries an INTERMITTENT empowered-Swipe
-- effect: in-game tooltip (datamine tooltipDescriptions, single combined stat,
-- 2026-06-01) "Every 3 seconds your next Swipe has 100% of its base damage
-- converted to Lightning and deals +(30-45) Melee Lightning Damage". The effect
-- only fires on the empowered (every-3s) Swipe cast, so it MUST be gated behind
-- the conditionEmpoweredSwipe config (Condition:EmpoweredSwipe, default OFF) —
-- otherwise the conversion + bonus would over-count on every Swipe and inflate
-- the baseline. LEB transcribes the single stat as two strings (one conversion,
-- one added-damage), both ending in the "(Empowered Swipe)" marker that routes
-- here. The generic skillBaseDamageConversionHandler above stays UNTOUCHED so
-- the always-on conversions (Acid Flask / Shuriken) keep their ungated behaviour.
-- We reuse the SAME CalcOffence consumer (conversionTable / globalConv,
-- mult = 1 - converted, no double-count) plus a Condition:EmpoweredSwipe tag.
-- Spec: spec/System/TestStormhideEmpoweredSwipe_spec.lua
-- See REGRESSION_GUARDS.md > "stormhide-empowered-swipe".
local function empoweredSwipeConversionHandler(num, _, src, dst)
	local canonical = canonicalSkillName(src)
	local dstType = dmgTypeNames[dst]
	if canonical and dstType and tonumber(num) then
		local convMods = { }
		for _, srcType in ipairs(DamageTypes) do
			if srcType ~= dstType then
				t_insert(convMods, mod(srcType .. "DamageConvertTo" .. dstType, "BASE", tonumber(num), "", 0, 0,
					{ type = "SkillName", skillName = canonical },
					{ type = "Condition", var = "EmpoweredSwipe" }))
			end
		end
		return convMods
	end
	-- Skill / type did not resolve: recognition-only (unchanged fallback).
	return nsAny(num)
end
specialModList["^%+?([%d%.]+)%% of (.+) base damage converted to (.+) %(empowered swipe%)$"] = empoweredSwipeConversionHandler

-- Added Melee Lightning Damage, Swipe-scoped AND gated on Condition:EmpoweredSwipe
-- (the "+X Melee Lightning Damage" half of the same Stormhide stat). Emitted as a
-- clean (nil-extra) LightningDamage BASE with KeywordFlag.Melee (512) + SkillName
-- tag + Condition tag, so it lands ONLY on the empowered Swipe. (The bare
-- "+X Melee Lightning Damage with Swipe" form parses Swipe-scoped today but
-- UNGATED and with dirty residue; this dedicated form fixes both.)
specialModList["^%+?(%d+) melee lightning damage with swipe %(empowered swipe%)$"] = function(num)
	local canonical = canonicalSkillName("Swipe")
	if not canonical or not tonumber(num) then return nsAny(num) end
	return { mod("LightningDamage", "BASE", tonumber(num), "", 0, KeywordFlag.Melee,
		{ type = "SkillName", skillName = canonical },
		{ type = "Condition", var = "EmpoweredSwipe" }) }
end

-- 19. Cross-type damage gained-as-added ("Added Melee Damage gained as Added Spell Damage")
-- @leb-regression-guard:spellblade-weapon-melee-added-gained-as-spell
-- LE Spellblade MASTERY innate: "X% of added melee damage on weapons is also gained
-- as added spell damage". Emit a real WeaponMeleeAddedGainedAsSpell BASE mod that
-- CalcOffence consumes (X% of each weapon item's melee-tagged added flat, per type,
-- re-granted as Spell-flagged added). This SPECIFIC rule must precede the generic
-- gained-as-added nsAny below (which would otherwise catch it as a no-op). The
-- static ModCache entry for this exact text was deleted so live parse reaches here.
-- Validated: Tru_Flamer E.Nova spell-added 110->177.6 (weapon typeless 169*0.40) +
-- SpellFire +46.8 (weapon melee-fire 117*0.40). Spec: TestSpellbladeMeleeGainedAsSpell.
specialModList["^([%d%.]+)%% of added melee damage on weapons is also gained as added spell damage$"] = function(num)
	return { mod("WeaponMeleeAddedGainedAsSpell", "BASE", tonumber(num)) }
end
-- Item-affix 988 variant: "+X% Added Melee Damage gained as Added Spell Damage" (corrupted
-- 1H-sword sealed/exalted affix, 1.4-new). SAME mechanic + SAME mod as the mastery innate
-- above; STACKS ADDITIVELY with it (engine-confirmed via the SpellPhysical capture 164358:
-- weapon phys-melee 45 -> physical spell-added 22.5 = mastery 40% + affix 10% = 50%). Emit
-- the same WeaponMeleeAddedGainedAsSpell BASE so CalcOffence sums both. Must precede the
-- generic gained-as-added nsAny below (which would otherwise catch it as a no-op); the
-- static ModCache entries for "+11%..+33% Added Melee Damage gained as Added Spell Damage"
-- were deleted so live parse reaches here.
specialModList["^%+?([%d%.]+)%% added melee damage gained as added spell damage$"] = function(num)
	return { mod("WeaponMeleeAddedGainedAsSpell", "BASE", tonumber(num)) }
end
specialModList["^%+?([%d%.]+)%% added (.+) gained as added (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% of added (.+) gained as added (.+)$"] = nsAny

-- 21. "+N to <skill>" — DPS-integrated: emits a SkillName-tagged SkillLevel BASE
-- that CalcSetup consumes via env.modDB:Sum("BASE", skillCfg, "SkillLevel") to
-- raise the specialized skill's effective level. If the captured name isn't a
-- canonical skill (e.g. "+1 to Strength", "+1 to All Attributes"), return nil so
-- parseMod falls through to the generic chain and the stat mod still applies.
specialModList["^%+?(%d+) to (.+)$"] = function(num, _, name)
	-- "+N to Level of <Skill>" — equivalent to "+N to <Skill>".
	name = name:gsub("^[Ll]evel [Oo]f ", "")
	local canonical = canonicalSkillName(name)
	if not canonical then
		-- Plural fallback: "+N to Melee Attacks" / "Bow Attacks" describe the
		-- basic auto-attack skill ("Melee Attack" / "Bow Attack"), so try the
		-- singular form when the plural doesn't resolve.
		local singular = name:gsub("s$", "")
		if singular ~= name then
			canonical = canonicalSkillName(singular)
		end
	end
	if not canonical then return nil end
	return { mod("SkillLevel", "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }) }
end

-- 21b. "+N to <Cat> Minion Skills" — emits a SkillType=Minion-tagged SkillLevel BASE
-- on the PLAYER side (not wrapped as MinionModifier) so the per-skill-point cap in
-- CalcSetup.lua (Sum("BASE", skillCfg, "SkillLevel")) recognises the bonus for
-- minion skills like Summon Skeleton/Skeletal Mage/Volatile Zombie. <Cat> can be
-- "all", a damage type, a delivery type (spell/melee/throwing/bow), or an
-- attribute (strength/dexterity/intelligence/attunement/vitality). Unknown
-- prefixes return nil to fall through.
local minionSkillCatFlags = {
	["all"] = 0,
	["spell"] = KeywordFlag.Spell,
	["melee"] = KeywordFlag.Melee,
	["throwing"] = KeywordFlag.Throwing,
	["bow"] = KeywordFlag.Bow,
	["fire"] = KeywordFlag.Fire,
	["cold"] = KeywordFlag.Cold,
	["lightning"] = KeywordFlag.Lightning,
	["physical"] = KeywordFlag.Physical,
	["necrotic"] = KeywordFlag.Necrotic,
	["poison"] = KeywordFlag.Poison,
	["void"] = KeywordFlag.Void,
	["elemental"] = bor(KeywordFlag.Fire, KeywordFlag.Cold, KeywordFlag.Lightning),
	["damage over time"] = KeywordFlag.Dot,
	["dot"] = KeywordFlag.Dot,
}
local minionSkillCatAttrs = {
	["strength"] = "Str", ["dexterity"] = "Dex", ["intelligence"] = "Int",
	["attunement"] = "Attunement", ["vitality"] = "Vitality",
}
specialModList["^%+?(%d+) to (.+) minion skills$"] = function(num, _, cat)
	cat = cat:lower()
	cat = cat:gsub("^level of ", "")
	-- "+N to Level of Minion Skills" reduces to empty cat (treat as "all").
	if cat == "" then cat = "all" end
	local mods = {}
	local kf = minionSkillCatFlags[cat]
	if kf ~= nil then
		-- Match against the host's minionTagsDisplay (via MinionTagFlag), not
		-- the host's own keywordFlags. The host is rarely tagged with the
		-- minion's delivery/damage type itself (e.g. Summon Bear is Physical
		-- but its bear is Melee+Physical). cat="all" emits no extra filter.
		if kf == 0 then
			t_insert(mods, mod("SkillLevel", "BASE", num, "", 0, 0, { type = "SkillType", skillType = SkillType.Minion }))
		else
			t_insert(mods, mod("SkillLevel", "BASE", num, "", 0, 0,
				{ type = "SkillType", skillType = SkillType.Minion },
				{ type = "MinionTagFlag", keywordFlags = kf }))
		end
	elseif minionSkillCatAttrs[cat] then
		-- "+N to <Attribute> Minion Skills" — gate on both Minion type AND the
		-- skill carrying the attribute (via SkillAttribute predicate). Without
		-- the attribute gate, e.g. Mantle of the Pale Ox's "+1-2 to Strength
		-- Minion Skills" would lift Warcry's cap once it picks up Minion via
		-- Totemic Heart, even though Warcry only scales with Attunement.
		local attr = ({
			["strength"] = "Strength", ["dexterity"] = "Dexterity",
			["intelligence"] = "Intelligence", ["attunement"] = "Attunement",
			["vitality"] = "Vitality",
		})[cat]
		t_insert(mods, mod("SkillLevel", "BASE", num, "", 0, 0,
			{ type = "SkillType", skillType = SkillType.Minion },
			{ type = "SkillAttribute", attribute = attr }))
	else
		return nil
	end
	return mods
end

-- 21c. "+N to Skills" / "+N to All Skills" — global SkillLevel BASE that lifts
-- every skill's cap. Consumed via env.modDB:Sum("BASE", skillCfg, "SkillLevel").
specialModList["^%+?(%d+) to skills$"] = function(num)
	return { mod("SkillLevel", "BASE", num) }
end
specialModList["^%+?(%d+) skills$"] = function(num)
	return { mod("SkillLevel", "BASE", num) }
end

-- 21d. "+N to <Category> Skills" — generic dispatcher for damage-type / skill-type /
-- attribute / DOT prefixes. Routes via a category table:
--   * KeywordFlag set → emits SkillLevel BASE with keywordFlags filter
--   * SkillType tag   → emits SkillLevel BASE with SkillType filter tag
--   * attribute       → treated as global (LE scopes attribute-skills by
--                       per-skill attribute tag, not via a player-side flag, so
--                       cap-wise we apply it globally)
--   * "all"           → global, no filter
-- Unknown categories return nil so the generic chain still produces a stat mod.
local skillCatFlags = {
	["spell"] = KeywordFlag.Spell,
	["melee"] = KeywordFlag.Melee,
	["throwing"] = KeywordFlag.Throwing,
	["bow"] = KeywordFlag.Bow,
	["minion"] = KeywordFlag.Minion,
	["fire"] = KeywordFlag.Fire,
	["cold"] = KeywordFlag.Cold,
	["lightning"] = KeywordFlag.Lightning,
	["physical"] = KeywordFlag.Physical,
	["necrotic"] = KeywordFlag.Necrotic,
	["poison"] = KeywordFlag.Poison,
	["void"] = KeywordFlag.Void,
	["elemental"] = bor(KeywordFlag.Fire, KeywordFlag.Cold, KeywordFlag.Lightning),
	["damage over time"] = KeywordFlag.Dot,
	["dot"] = KeywordFlag.Dot,
}
local skillCatTypes = {
	["totem"] = SkillType.Totem,
	["all totem"] = SkillType.Totem,
	["buff"] = SkillType.Buff,
	["curse"] = SkillType.Curse,
	["channelling"] = SkillType.Channelling,
	["transform"] = SkillType.Transform,
	["ailment"] = SkillType.Ailment,
}
-- Lowercase affix word → canonical attribute name stored in
-- grantedEffect.skillAttributes. "vitality" has no LE skill-scaling counterpart
-- (no specialTag for "Vitality Skills"), but LEB has historically accepted the
-- string; route it through the same tag mechanism for consistency — it will
-- simply never match because no skill carries Vitality in its scalings.
local skillCatAttrs = {
	["strength"] = "Strength", ["dexterity"] = "Dexterity",
	["intelligence"] = "Intelligence", ["attunement"] = "Attunement",
	["vitality"] = "Vitality",
}
-- Class names: a single character is one class, so a class-skills bonus is
-- effectively a global SkillLevel BASE for the player.
local skillCatClasses = {
	["mage"] = true, ["sentinel"] = true, ["acolyte"] = true,
	["primalist"] = true, ["rogue"] = true,
}
local function dispatchCatSkills(num, cat)
	cat = cat:lower()
	-- "+N to Level of <Cat> Skills" — equivalent to "+N to <Cat> Skills".
	cat = cat:gsub("^level of ", "")
	if cat == "all" then
		return { mod("SkillLevel", "BASE", num) }
	end
	local kf = skillCatFlags[cat]
	if kf then
		return { mod("SkillLevel", "BASE", num, "", 0, kf) }
	end
	local st = skillCatTypes[cat]
	if st then
		return { mod("SkillLevel", "BASE", num, "", 0, 0, { type = "SkillType", skillType = st }) }
	end
	local attrName = skillCatAttrs[cat]
	if attrName then
		-- "+N to <Attribute> Skills" — filter via SkillAttribute tag
		-- (matches LE's ScalesWithAttribute via DataProcess.skillAttributes).
		return { mod("SkillLevel", "BASE", num, "", 0, 0, { type = "SkillAttribute", attribute = attrName }) }
	end
	if skillCatClasses[cat] then
		return { mod("SkillLevel", "BASE", num) }
	end
	-- Multi-keyword combos like "cold melee" / "lightning melee" — try ORing
	-- each whitespace-separated term that resolves to a flag.
	local combinedKf = 0
	local matchedAll = true
	for term in cat:gmatch("%S+") do
		local termKf = skillCatFlags[term]
		if termKf then
			combinedKf = bor(combinedKf, termKf)
		else
			matchedAll = false
			break
		end
	end
	if matchedAll and combinedKf ~= 0 then
		return { mod("SkillLevel", "BASE", num, "", 0, combinedKf) }
	end
	return nil
end
specialModList["^%+?(%d+) to (.+) skills$"] = function(num, _, cat)
	return dispatchCatSkills(num, cat)
end
-- Alias: in-game text uses "+N to <Cat> Attacks" / "Abilities" interchangeably
-- with "<Cat> Skills" for non-spell skill categories (e.g. "Throwing Attacks",
-- "Fire Melee Attacks"). Without this, the generic "+N to <name>" handler
-- (pattern 21) strips the trailing "s" and resolves "Melee Attack" / "Bow
-- Attack" to the canonical basic auto-attack skill, binding the bonus to that
-- single skill instead of the whole category. scan() picks the longest match,
-- so this dispatcher wins over the generic canonical-skill fallback.
specialModList["^%+?(%d+) to (.+) attacks$"] = function(num, _, cat)
	return dispatchCatSkills(num, cat)
end
specialModList["^%+?(%d+) to (.+) abilities$"] = function(num, _, cat)
	return dispatchCatSkills(num, cat)
end
-- Alias: "+N to <Cat> Minions" — game writes some +Skills affixes without the
-- trailing "Skills" word. Re-route to dispatchCatSkills with " minion"
-- appended. The Spells variant has its own dedicated handler below (21f) that
-- combines Spell with damage-type filters; defining it here would be shadowed
-- by Lua's last-write-wins on duplicate table keys.
specialModList["^%+?(%d+) to (.+) minions$"] = function(num, _, cat)
	return dispatchCatSkills(num, cat .. " minion")
end
-- 21d-attr. "+N to (Level of) <Cat> Skills per <D> Total Attributes" —
-- conditional scaling: emits SkillLevel BASE with a PerStat tag over
-- (Str+Dex+Int+Att+Vit) divided by D. Pre-empts the generic
-- "per N total attributes" tag pipeline because longer patterns win in scan().
specialModList["^%+?(%d+) to (.+) skills per (%d+) total attributes$"] = function(num, _, cat, div)
	cat = cat:lower()
	cat = cat:gsub("^level of ", "")
	div = tonumber(div)
	local perStatTag = { type = "PerStat", statList = { "Str", "Dex", "Int", "Att", "Vit" }, div = div }
	if cat == "all" then
		return { mod("SkillLevel", "BASE", num, "", 0, 0, perStatTag) }
	end
	local kf = skillCatFlags[cat]
	if kf then
		return { mod("SkillLevel", "BASE", num, "", 0, kf, perStatTag) }
	end
	local st = skillCatTypes[cat]
	if st then
		return { mod("SkillLevel", "BASE", num, "", 0, 0, perStatTag, { type = "SkillType", skillType = st }) }
	end
	local attrName = skillCatAttrs[cat]
	if attrName then
		return { mod("SkillLevel", "BASE", num, "", 0, 0, perStatTag, { type = "SkillAttribute", attribute = attrName }) }
	end
	if skillCatClasses[cat] then
		return { mod("SkillLevel", "BASE", num, "", 0, 0, perStatTag) }
	end
	return nil
end

-- 21e. "+N to <Cat> Skills per Complete Set" — same dispatch as 21d but the
-- emitted SkillLevel BASE mod carries a Multiplier tag on CompleteSetCount so
-- the cap only scales when matching set rings/items are equipped (the same
-- counter env.itemModDB.multipliers["CompleteSetCount"] populated in CalcSetup).
specialModList["^%+?(%d+) to (.+) skills per complete set$"] = function(num, _, cat)
	cat = cat:lower()
	cat = cat:gsub("^level of ", "")
	local setTag = { type = "Multiplier", var = "CompleteSetCount" }
	if cat == "all" then
		return { mod("SkillLevel", "BASE", num, "", 0, 0, setTag) }
	end
	local kf = skillCatFlags[cat]
	if kf then
		return { mod("SkillLevel", "BASE", num, "", 0, kf, setTag) }
	end
	local st = skillCatTypes[cat]
	if st then
		return { mod("SkillLevel", "BASE", num, "", 0, 0, setTag, { type = "SkillType", skillType = st }) }
	end
	local attrName = skillCatAttrs[cat]
	if attrName then
		return { mod("SkillLevel", "BASE", num, "", 0, 0, setTag, { type = "SkillAttribute", attribute = attrName }) }
	end
	if skillCatClasses[cat] then
		return { mod("SkillLevel", "BASE", num, "", 0, 0, setTag) }
	end
	return nil
end

-- 21f. "+N to <Cat> Spells" — emits a Spell-keyword-tagged SkillLevel BASE,
-- ORed with a damage-type flag when <Cat> is a damage type (e.g. "Necrotic
-- Spells" → Spell+Necrotic). Without a damage type ("All Spells" / bare
-- "Spells") it's just the Spell flag.
specialModList["^%+?(%d+) to (.+) spells$"] = function(num, _, cat)
	cat = cat:lower()
	cat = cat:gsub("^level of ", "")
	local kf = KeywordFlag.Spell
	if cat == "all" or cat == "" then
		return { mod("SkillLevel", "BASE", num, "", 0, kf) }
	end
	local dmgKf = skillCatFlags[cat]
	if dmgKf then
		-- Spell AND (damage types). For single-type categories (e.g. "Fire") we
		-- want both bits present, so MatchAll is correct. For multi-type
		-- categories like "Elemental" (Fire|Cold|Lightning) we want Spell AND
		-- *any* of the elemental bits — MatchAll would force the skill to carry
		-- all three damage types simultaneously, which never happens (Judgement
		-- is Fire+Spell, so "+1 to Elemental Spells" would never apply).
		-- Detect multi-bit dmgKf by counting set bits and switch matching mode:
		--   single-bit → keywordFlags = Spell|Damage with MatchAll (both required)
		--   multi-bit  → SkillType=Spell tag (Spell required) + damage keywordFlags (any-of)
		local bits, tmp = 0, dmgKf
		while tmp ~= 0 do
			bits = bits + (band(tmp, 1) ~= 0 and 1 or 0)
			tmp = bit.rshift(tmp, 1)
		end
		if bits <= 1 then
			return { mod("SkillLevel", "BASE", num, "", 0, bor(kf, dmgKf, KeywordFlag.MatchAll)) }
		end
		return { mod("SkillLevel", "BASE", num, "", 0, dmgKf, { type = "SkillType", skillType = SkillType.Spell }) }
	end
	local attrName = skillCatAttrs[cat]
	if attrName then
		-- "+N to <Attribute> Spells" — combine Spell keyword with attribute filter.
		return { mod("SkillLevel", "BASE", num, "", 0, kf, { type = "SkillAttribute", attribute = attrName }) }
	end
	if skillCatClasses[cat] then
		return { mod("SkillLevel", "BASE", num, "", 0, kf) }
	end
	return nil
end


-- 21g. "% increased Effect of Skill Level modifiers on Legendary Affixes"
-- (Permanence of Primal Knowledge): emits a global INC stat that CalcSetup
-- uses to multiply the BASE SkillLevel mods tagged mod.legendaryAffix=true
-- (set by Item.lua for sealed Prefix/Suffix on Reforged Legendary items).
specialModList["^%+?([%d%.]+)%% increased effect of skill level modifiers on legendary affixes$"] = function(num)
	return { mod("LegendaryAffixSkillLevelEffect", "INC", num) }
end


-- 22. Flat charge count for a skill ("+1 Charge for Flame Ward")
specialModList["^%+?(%d+) charges? for (.+)$"] = nsAny
specialModList["^%+?(%d+) additional charges? for (.+)$"] = nsAny

-- @leb-regression-guard:truesight-glass-super-crit (parser site)
-- Validation provenance is retained in maintainer notes.
specialModList["^%+?%d+%% you can deal super critical strikes$"] = { flag("CanSuperCrit") }
specialModList["^you can deal super critical strikes$"] = { flag("CanSuperCrit") }

-- Damage-taken reductions with qualifier / source
-- DPS-integrated where possible via:
--   * "bonus damage taken from critical strikes" → ReduceCritExtraDamage stat
--     (consumed in CalcDefence.lua as a flat reduction to enemy crit extra damage)
--   * "from <ailment> enemies" → ActorCondition tag in modTagList combined with
--     "DamageTaken" from modNameList via the generic parse chain
--   * "<type> damage taken" → auto-generated "<Type>DamageTaken" modNameList entry
-- Known qualifiers fall through to the generic chain; unknown still get nsAny
-- recognition so the mod is at least flagged rather than silently broken.
specialModList["^%+?([%d%.]+)%% reduced bonus damage taken from critical strikes$"] = function(num)
	return { mod("ReduceCritExtraDamage", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% less bonus damage taken from critical strikes$"] = function(num)
	return { mod("ReduceCritExtraDamage", "BASE", num) }
end
-- Per Equipped Heretical Idol variant: scale by Multiplier:EquippedHereticalIdol
-- (populated by CalcSetup at idol-altar processing time). The vanilla generic
-- chain doesn't know which target stat "bonus damage taken from critical strikes"
-- maps to, so handle this composite explicitly.
specialModList["^%+?([%d%.]+)%% reduced bonus damage taken from critical strikes per equipped heretical idol$"] = function(num)
	return { mod("ReduceCritExtraDamage", "BASE", num, { type = "Multiplier", var = "EquippedHereticalIdol" }) }
end
-- @leb-regression-guard:crits-abbreviation
-- LE class trees abbreviate "Critical Strikes" as "Crits" on several Sentinel
-- passives (Sentinel-14 Patient Doom, Sentinel-42 Iron Reflexes, Sentinel-114
-- Heaven's Bulwark). Map them to the same ReduceCritExtraDamage stat.
-- The "from crits$" tail must remain LONGER than the catch-all "from (.+)$"
-- below, so scan()'s longest-pattern tie-breaking picks this specific form
-- first. Shortening it or reordering will silently route Sentinel-114 to
-- LEB_NotSupported and reintroduce a -30 CritExtraDmgRed diff on <private build>.
-- Spec: spec/System/TestModParse_spec.lua "crits abbreviation reduces crit damage"
specialModList["^%+?([%d%.]+)%% reduced bonus damage taken from crits$"] = function(num)
	return { mod("ReduceCritExtraDamage", "BASE", num) }
end
specialModList["^%+?([%d%.]+)%% less bonus damage taken from crits$"] = function(num)
	return { mod("ReduceCritExtraDamage", "BASE", num) }
end
-- "bonus damage taken from X" for other X values is not yet modeled.
specialModList["^%+?([%d%.]+)%% reduced bonus damage taken from (.+)$"] = nsAny
specialModList["^%+?([%d%.]+)%% less bonus damage taken from (.+)$"] = nsAny

-- Enemy-condition sources (chilled/ignited/shocked/slowed/bleeding/poisoned/
-- frozen/time rotting/frail enemies, critical strikes) already have modTagList
-- entries, so we fall through for known sources and only nsAny unknown ones.
local knownDamageTakenSources = {
	["critical strikes"] = true, ["crits"] = true,
	["chilled enemies"] = true, ["ignited enemies"] = true, ["shocked enemies"] = true,
	["slowed enemies"] = true, ["frozen enemies"] = true, ["bleeding enemies"] = true,
	["poisoned enemies"] = true, ["time rotting enemies"] = true, ["frail enemies"] = true,
}
local function damageTakenFromHandler(num, _, source)
	if source and knownDamageTakenSources[source:lower()] then
		return nil
	end
	return nsAny(num)
end
specialModList["^%+?([%d%.]+)%% reduced damage taken from (.+)$"] = damageTakenFromHandler
specialModList["^%+?([%d%.]+)%% less damage taken from (.+)$"] = damageTakenFromHandler

-- "<type> damage taken" — auto-generated modNameList entries cover standard damage
-- types (Physical/Fire/Cold/Lightning/Poison/Necrotic/Void) plus "Elemental" and
-- bare "Damage Taken". Fall through to let the generic chain produce the flat mod.
-- Unknown prefixes still hit nsAny to stay recognised.
local knownDamageTakenTypes = {
	["physical"] = true, ["fire"] = true, ["cold"] = true, ["lightning"] = true,
	["poison"] = true, ["necrotic"] = true, ["void"] = true, ["elemental"] = true,
	["hit"] = true, ["melee"] = true, ["spell"] = true, ["minion"] = true,
	["damage over time"] = true, ["dot"] = true,
}
local function damageTakenTypeHandler(num, _, dtype)
	if dtype and knownDamageTakenTypes[dtype:lower()] then
		return nil
	end
	return nsAny(num)
end
specialModList["^%+?([%d%.]+)%% reduced (.+) damage taken$"] = damageTakenTypeHandler
specialModList["^%+?([%d%.]+)%% less (.+) damage taken$"] = damageTakenTypeHandler
specialModList["^%+?([%d%.]+)%% increased (.+) damage taken$"] = damageTakenTypeHandler
specialModList["^%+?([%d%.]+)%% more (.+) damage taken$"] = damageTakenTypeHandler

-- @leb-regression-guard:dual-attribute-and-pair
-- "+N <Attr1> and <Attr2>" (e.g. Jormun's Hunger "+(6-10) Strength and Dexterity")
-- is a single mod that grants BOTH attributes. The generic parse chain matches the
-- first attribute via modNameList but leaves "and <Attr2>" as non-empty extra
-- residue, which PassiveTree.lua / item-mod consumers DROP entirely (`if mod.list
-- and not mod.extra`). Result: LEB silently lost +N to both attributes whereas
-- LETools applies both. Verified on BOwJRDdE lv74 Shaman Jormun's Hunger byte=127.5:
--   LET Str=42 Dex=17 ; LEB Str=33 Dex=8 (-9/-9 = the dual mod value)
-- Hook here as a specialModList entry that emits two BASE mods, validating both
-- captures against LongAttributes so unrelated "<num> <X> and <Y>" lines decline.
local dualAttrLookup = {}
for i, longName in ipairs(LongAttributes) do
    dualAttrLookup[longName:lower()] = Attributes[i]
end
-- Dispatch convention (see L1529): specialMod(tonumber(cap[1]), unpack(cap)) →
-- 3 captures unpack to (numericFirst, cap1str, cap2str, cap3str). attr1/attr2
-- live at args 3/4, not 2/3 — the numeric cap-string occupies arg 2.
specialModList["^%+?([%d%.]+) (%a+) and (%a+)$"] = function(num, _, attr1, attr2)
    local m1 = dualAttrLookup[attr1:lower()]
    local m2 = dualAttrLookup[attr2:lower()]
    if m1 and m2 and m1 ~= m2 then
        return { mod(m1, "BASE", num), mod(m2, "BASE", num) }
    end
    return nil
end

-- Compound "... this effect is doubled if ..." clauses (e.g. doubled-at-300-mana).
-- Intentionally NOT hooked as specialModList — the trailing clause is matched via
-- modTagList ("this effect is doubled if you have N or more maximum mana") which
-- emits a StatThreshold tag with mult=2, letting the generic parser handle the
-- "X% increased <stat>" head. Hooking nsAny here would swallow the whole line.

-- Modifiers that are recognised but unsupported
local unsupportedModList = {
	["chance to shred # resistance on hit"] = true,
}

-- @leb-regression-guard:display-only-tooltip-text
-- Lines that carry no modifier at all. In LE's game data these live in a unique's
-- `tooltipDescriptions` block (tooltipEntries modDisplay >= 128) rather than its
-- `mods` array: they describe engine-side behaviour the item data does not encode.
-- The mechanic itself is modelled elsewhere (e.g. the Ambition stack cap is
-- `limit = 20` on the "per stack of ambition" modTagList entry, and the stack count
-- is user-driven via ConfigOptions "# of Active Ambition Stacks"), so these lines
-- must contribute nothing.
--
-- `extra` MUST be nil, not "" — an empty string is truthy in Lua and would make the
-- line render as red UNSUPPORTED (ItemTools.formatModLine tests `modLine.extra`),
-- which is exactly what we're distinguishing them from. They are not "unsupported";
-- there is nothing to support.
-- Spec: spec/System/TestDisplayOnlyTooltipText_spec.lua
local displayOnlyModList = {
	["you gain a stack of ambition when you hit a boss or rare enemy (1 second cooldown)"] = true,
	["20 maximum stacks of ambition"] = true,
	["you lose all stacks of ambition if you go 4 seconds without gaining a stack"] = true,
	-- @leb-regression-guard:wrongwarp-inline-rebuild-310
	-- Validation provenance is retained in maintainer notes.
	["when you cast teleport or transplant you are teleported to a random nearby location, become immune to all damage for 1 second, and gain chronowarp for 10 seconds."] = true,
	["when you cast teleport or transplant you time lock up to 10 enemies around the destination for 1 second. bosses are slowed instead of time locked."] = true,
	["teleport and transplant have a minimum cooldown of 3 seconds"] = true,
}

-- Special lookups used for various modifier forms
local suffixTypes = {
	["as fire"] = "AsFire",
}
for _, damageType in ipairs(DamageTypes) do
	suffixTypes["converted to " .. damageType:lower()] = "ConvertTo" .. damageType
end
local function appendMod(inputTable, string)
	local table = { }
	for subLine, mods in pairs(inputTable) do
		if type(mods) == "string" then
			table[subLine] = mods..string
		else
			table[subLine] = { }
			for _, mod in ipairs(mods) do
				t_insert(table[subLine], mod..string)
			end
		end
	end
	return table
end
local flagTypes = {
	["frenzy"] = "Condition:Frenzy",
}

-- Build active skill name lookup
local skillNameList = {
}

for _, skill in pairs(data.skills) do
	skillNameList[skill.name:lower()] = { tag = { type = "SkillName", skillName = skill.name } }
end

-- @leb-regression-guard:subskill-grant-registry (thorn-burst alias)
-- Validation provenance is retained in maintainer notes.
skillNameList["thorn burst"] = { tag = { type = "SkillName", skillName = "Thorn Shield" } }

-- @leb-regression-guard:conscrated-ground-typo-alias (skill-name eater)
-- LE game data misspells "Consecrated Ground" as "Conscrated Ground" (missing the
-- 2nd 'e') in two Judgement tree stats ("+30% Conscrated Ground Damage Against
-- Ignited Enemies", "+20% Conscrated Ground Damage Against High Health"). This
-- eater scopes a leading/trailing skill phrase to a SkillName tag, so the
-- misspelled phrase fails to match and the MORE never reaches the granted
-- Consecrated Ground sub-skill. Alias the typo to the real skill so both stats
-- scope to CG. Mirrors the "thorn burst" alias precedent above.
if skillNameList["consecrated ground"] then
	skillNameList["conscrated ground"] = skillNameList["consecrated ground"]
end


local preSkillNameList = { }

-- Scan a line for the earliest and longest match from the pattern list
-- If a match is found, returns the corresponding value from the pattern list, plus the remainder of the line and a table of captures
local function scan(line, patternList, plain, matchAll, excludeStart, excludeEnd)
	local bestIndex, bestEndIndex
	local bestPattern = ""
	local bestVal, bestStart, bestEnd, bestCaps
	local lineLower = line:lower()
	for pattern, patternVal in pairs(patternList) do
		local index, endIndex, cap1, cap2, cap3, cap4, cap5 = lineLower:find(pattern, 1, plain)
		-- Skip matches fully contained within an excluded range (used to protect
		-- multi-word modName matches like "health gain on block" from being
		-- broken up by shorter modTag patterns like "on block"). Patterns that
		-- merely overlap the name region (e.g. a long ". this effect is doubled
		-- if you have N or more maximum mana." tag whose tail covers "maximum
		-- mana") must still be allowed.
		if index and excludeStart and index >= excludeStart and endIndex <= excludeEnd then
			index = nil
		end
		if index and (not bestIndex or index < bestIndex or (index == bestIndex and (endIndex > bestEndIndex or (endIndex == bestEndIndex and #pattern > #bestPattern)))) then
			bestIndex = index
			bestEndIndex = endIndex
			bestPattern = pattern
			bestVal = patternVal
			bestStart = index
			bestEnd = endIndex
			bestCaps = { cap1, cap2, cap3, cap4, cap5 }
		end
	end
	if bestVal then
		local lineRemainder = line:sub(1, bestStart - 1) .. line:sub(bestEnd + 1, -1)
		if matchAll then
			local results, lineRemainderFinal = scan(lineRemainder, patternList, plain, true)
			t_insert(results, bestVal)
			return results, lineRemainderFinal
		else
			return bestVal, lineRemainder, bestCaps
		end
	else
		if matchAll then
			return {nil}, line
		else
			return nil, line
		end
	end
end

local function parseMod(line, order)
	-- Strip leading/trailing whitespace
	line = line:match("^%s*(.-)%s*$") or line
	-- @leb-regression-guard:dodge-more-multiplier (parser site)
	-- Strip purely decorative "(multiplicative with other modifiers)" suffix/inline
	-- so the parser's "extra" residue stays empty. PassiveTree.lua skips mods with
	-- non-empty extra (`if mod.list and not mod.extra`), which dropped the
	-- Bladedancer ascendancy "15% more dodge rating (multiplicative...)" entirely
	-- from modDB. Without this strip the parser returns extra=" (multiplicative
	-- with other modifiers) " and the MORE Evasion mod never reaches the calc.
	-- Spec: spec/System/TestDodgeMoreMultiplier_spec.lua
	line = line:gsub("%s*%(multiplicative with other modifiers%)%s*", " ")
	line = line:match("^%s*(.-)%s*$") or line
	-- Check if this is a special modifier
	local lineLower = line:lower()
	if unsupportedModList[lineLower] then
		return { }, line
	end
	if displayOnlyModList[lineLower] then
		return { }, nil
	end
	-- Handle -> conversion syntax
	if line:find("->", 1, true) then
		local convMods = parseArrowConversion(line)
		if convMods then
			-- @leb-regression-guard:conversion-extra-nil-not-empty
			-- A fully-parsed arrow conversion has NO leftover residue, so the
			-- second return (`extra`) must be nil — matching the clean-parse
			-- convention at the function tail (`line:match("%S") and line`).
			-- Returning "" instead is truthy in Lua, and PassiveTree.lua
			-- ProcessStats skips any mod whose `extra` is truthy
			-- (`if mod.list and not mod.extra`). That dropped EVERY skill-tree /
			-- passive-tree conversion node (e.g. Flame Ward "fw3d-6 Frost Ward"
			-- " Fire -> Cold", which globally converts Fire Aura to cold) from
			-- node.modList, so cross-skill conversions never reached the calc.
			-- Same failure mode as @leb-regression-guard:dodge-more-multiplier.
			-- Spec: spec/System/TestConversionExtraNil_spec.lua
			return convMods
		end
		-- @leb-regression-guard:skill-name-arrow-conversion (consumer site)
		-- parseArrowConversion handles <type>-><type>; a skill-name source
		-- ("Volcanic Orb -> Cold") falls through here. Emit a skill-scoped
		-- conversion (nil extra, same clean-parse contract as above) so the
		-- node is no longer dropped. See parseSkillNameArrowConversion.
		local skillConvMods = parseSkillNameArrowConversion(line)
		if skillConvMods then
			return skillConvMods
		end
		return { }, line
	end
	local specialMod, specialLine, cap = scan(line, specialModList)
	if specialMod and #specialLine == 0 then
		if type(specialMod) == "function" then
			local result = specialMod(tonumber(cap[1]), unpack(cap))
			if result ~= nil then
				return result
			end
			-- Handler returned nil to decline (e.g. skill-name validation failed);
			-- fall through to the generic parse chain so common forms still work.
		else
			return copyTable(specialMod)
		end
	end

	for pattern, replacement in pairs(specialQuickFixModList) do
		line = line:gsub(pattern, replacement)
	end

	line = line .. " "

	-- Check for a flag/tag specification at the start of the line
	local preFlag, preFlagCap
	preFlag, line, preFlagCap = scan(line, preFlagList)
	if type(preFlag) == "function" then
		preFlag = preFlag(unpack(preFlagCap))
	end

	-- Check for skill name at the start of the line
	local skillTag
	skillTag, line = scan(line, preSkillNameList)

	-- Scan for modifier form
	local modForm, formCap
	modForm, line, formCap = scan(line, formList)
	if not modForm then
		return { }, line
	end

	-- Peek modNameList for the longest match span on the current line so we can
	-- protect it from shorter modTag patterns (e.g. "on block") that would
	-- otherwise consume part of a longer name like "health gain on block".
	local nameStart, nameEnd
	do
		local lineLower = line:lower()
		local bestLen = 0
		for pattern in pairs(modNameList) do
			local i, j = lineLower:find(pattern, 1, false)
			if i and (j - i + 1) > bestLen then
				bestLen = j - i + 1
				nameStart, nameEnd = i, j
			end
		end
	end

	-- Check for tags (per-charge, conditionals)
	local modTag, modTag2, tagCap
	modTag, line, tagCap = scan(line, modTagList, false, false, nameStart, nameEnd)
	if type(modTag) == "function" then
		if tagCap[1]:match("%d+") then
			modTag = modTag(tonumber(tagCap[1]), unpack(tagCap))
		else
			modTag = modTag(tagCap[1], unpack(tagCap))
		end
	end
	if modTag then
		modTag2, line, tagCap = scan(line, modTagList, false, false, nameStart, nameEnd)
		if type(modTag2) == "function" then
			if tagCap[1]:match("%d+") then
				modTag2 = modTag2(tonumber(tagCap[1]), unpack(tagCap))
			else
				modTag2 = modTag2(tagCap[1], unpack(tagCap))
			end
		end
	end

	-- Scan for modifier name and skill name
	local modName, nameCap
	if order == 2 and not skillTag then
		skillTag, line = scan(line, skillNameList)
	end
	if modForm == "FLAG" then
		formCap[1], line = scan(line, flagTypes, false)
		if not formCap[1] then
			return { }, line
		end
		modName, line = scan(line, modNameList, true)
	else
		modName, line, nameCap = scan(line, modNameList)
		if type(modName) == "function" then
			modName = modName(unpack(nameCap))
		end
	end
	if order == 1 and not skillTag then
		skillTag, line = scan(line, skillNameList)
	end

	-- Fallback: if no modName found but a skill name was matched, treat as skill level
	-- This handles "+X to [SkillName]" patterns (e.g. "+4 to Erasing Strike")
	-- skillTag already provides the SkillName tag, so just set the mod name
	-- @leb-regression-guard:shadow-suffix-family-c6f-followup-f12
	-- Strict residue gate: only fire when the remaining line is whitespace-
	-- only (clean "+N to <Skill>" or "+N <Skill>" form). If there's
	-- non-whitespace residue the skill name appeared in a descriptive
	-- context (e.g. "+1 Additional <Skill> Casts", "+1 <Skill> Stacks",
	-- "+1 <Skill> is a quick attack...") and the mod is NOT a skill-level
	-- grant. Documented follow-up: ~287 existing ModCache entries still
	-- carry the wrong SkillLevel mod from before this gate landed; they
	-- need a separate sweep to reclassify (Stacks / Charges / Conversion
	-- / flag mods).
	if not modName and modForm == "BASE" and skillTag and skillTag.tag and skillTag.tag.type == "SkillName" and line:match("^%s*$") then
		modName = "SkillLevel"
	end

	-- Scan for flags
	local modFlags
	modFlags, line = scan(line, modFlagList, true, true)
	if #modFlags > 1 then
		line = line:gsub(" And ", "")
	end

	-- Find modifier value and type according to form
	local keywordFlags
	local modValue = tonumber(formCap[1]) or formCap[1]
	local modType = "BASE"
	local modSuffix
	local modExtraTags
	if modForm == "INC" then
		modType = "INC"
	elseif modForm == "RED" then
		modValue = -modValue
		modType = "INC"
	elseif modForm == "MORE" then
		modType = "MORE"
	elseif modForm == "LESS" then
		modValue = -modValue
		modType = "MORE"
	elseif modForm == "BASE" then
		modSuffix, line = scan(line, suffixTypes, true)
	elseif modForm == "GAIN" then
		modType = "BASE"
		modSuffix, line = scan(line, suffixTypes, true)
	elseif modForm == "LOSE" then
		modValue = -modValue
		modType = "BASE"
		modSuffix, line = scan(line, suffixTypes, true)
	elseif modForm == "GRANTS" then -- local
		modType = "BASE"
		modExtraTags = { tag = { type = "Condition", var = "{Hand}Attack" } }
		modSuffix, line = scan(line, suffixTypes, true)
	elseif modForm == "REMOVES" then -- local
		modValue = -modValue
		modType = "BASE"
		modExtraTags = { tag = { type = "Condition", var = "{Hand}Attack" } }
		modSuffix, line = scan(line, suffixTypes, true)
	elseif modForm == "FLAG" then
		modName = type(modValue) == "table" and modValue.name or modValue
		modType = type(modValue) == "table" and modValue.type or "FLAG"
		modValue = type(modValue) == "table" and modValue.value or true
	elseif modForm == "OVERRIDE" then
		modType = "OVERRIDE"
	end
	if not modName then
		return { }, line
	end

	if modForm == "BASE_MORE" and modName ~= nil then
		local modNameStr = type(modName) == "table" and modName[1] or modName
		local hasModSuffix = false
		for _, flagEntry in ipairs(modFlags) do
			if type(flagEntry) == "table" and flagEntry.modSuffix then
				hasModSuffix = true
				break
			end
		end
		if not hasModSuffix and (modNameStr:match("Damage$") or modName == "Duration") then
			modType = "MORE"
		elseif not hasModSuffix and (modNameStr == "Life" or modNameStr == "Mana" or modNameStr == "Ward"
				or modNameStr == "ManaRegen" or modNameStr == "LifeRegen" or modNameStr == "Armour") then
			-- @leb-regression-guard: regen-pct-shorthand-inc
			-- LE convention: "+N% Health/Mana/Ward/ManaRegen/LifeRegen" (without "increased")
			-- is rendered in-game as an INC modifier. Game's authoritative
			-- localized_master.json affix 1015 affixProperties[1] (Mana Regen)
			-- has modifierType=1 (INC) and extraRolls stored as 0.08-0.09 (= 8-9%
			-- multiplier). ModItem_1_4.json renders the row as "+(8-9)% Mana Regen"
			-- following LE in-game text shorthand. Without ManaRegen/LifeRegen here,
			-- ModParser falls through to BASE and the affix is treated as flat
			-- "+8 Mana Regen" instead of "8% increased Mana Regen", causing
			-- ~+15.5/s drift on <private build> (LE 16.72 vs LEB 32.20). See spec
			-- TestModParser_spec.lua "regen-pct-shorthand-inc".
			--
			-- @leb-regression-guard: armour-pct-shorthand-inc
			-- Same convention extends to Armour. datamined game source
			-- multi_affixes_v3.json affix 1007 (rendered by ModItem_1_4.json as
			-- "+(85-90)% Armor" on body_armor slotOverrides, "+(24-30)% Armor"
			-- default) carries affixProperties[0] property=10 (Armor)
			-- modifierType=1 (INC). Without "Armour" here, the prefix falls
			-- through to BASE and is applied as flat +N Armor instead of
			-- +N% increased Armor, causing 4 builds to under-count by Sum~1596:
			-- <private build> Necromancer D=-667, BGzxJrgn Bladedancer D=-436,
			-- <private build> Bladedancer D=-285, <private build> Necromancer D=-208.
			-- See spec TestArmourPctShorthandInc_spec.lua.
			modType = "INC"
		else
			modType = "BASE"
		end
	end

	-- Combine flags and tags
	local flags = 0
	local baseKeywordFlags = 0
	local tagList = { }
	local misc = { }
	local dataList = { modName, preFlag, modTag, modTag2, skillTag, modExtraTags }
	tableInsertAll(dataList, modFlags)
	for _, data in pairs(dataList) do
		if type(data) == "table" then
			flags = bor(flags, data.flags or 0)
			baseKeywordFlags = bor(baseKeywordFlags, data.keywordFlags or 0)
			if data.tag then
				t_insert(tagList, copyTable(data.tag))
			elseif data.tagList then
				for _, tag in ipairs(data.tagList) do
					t_insert(tagList, copyTable(tag))
				end
			end
			for k, v in pairs(data) do
				misc[k] = v
			end
		end
	end

	-- Generate modifier list
	local nameList = modName
	local modList = { }
	for i, name in ipairs(type(nameList) == "table" and nameList or { nameList }) do
		modList[i] = {
			name = name .. (modSuffix or misc.modSuffix or ""),
			type = modType,
			value = type(modValue) == "table" and modValue[i] or modValue,
			flags = flags,
			keywordFlags = bor(type(keywordFlags) == "table" and keywordFlags[i] or 0, baseKeywordFlags),
			unpack(tagList)
		}
	end
	if modList[1] then
		-- Special handling for various modifier types
		if misc.addToAura then
			-- Modifiers that add effects to your auras
			for i, effectMod in ipairs(modList) do
				modList[i] = mod("ExtraAuraEffect", "LIST", { mod = effectMod })
			end
		elseif misc.newAura then
			-- Modifiers that add extra auras
			for i, effectMod in ipairs(modList) do
				local tagList = { }
				for i, tag in ipairs(effectMod) do
					tagList[i] = tag
					effectMod[i] = nil
				end
				modList[i] = mod("ExtraAura", "LIST", { mod = effectMod, onlyAllies = misc.newAuraOnlyAllies }, unpack(tagList))
			end
		elseif misc.addToMinion then
			-- @leb-regression-guard:minion-modifier-type-narrowing
			-- Minion modifiers. Optional `misc.addToMinionType` (single string) or
			-- `misc.addToMinionTypes` (array of strings) narrows dispatch to the
			-- named env.minion.type(s); without them the mod fires for any minion.
			-- This is the assembly-side counterpart of the `value.type` /
			-- `value.minionTypes` gate in CalcPerform.lua (guard
			-- `minion-modifier-multi-type-gate`). F3+F9 use this to route
			-- Shadow-specific suffix mods ("for skills used by Shadows",
			-- "Shadow Damage") into ShadowClone only, instead of leaking onto
			-- the player or every minion.
			-- Spec: spec/System/TestMinionModifierTypeNarrowing_spec.lua
			for i, effectMod in ipairs(modList) do
				local tagList = { }
				if misc.playerTag then t_insert(tagList, misc.playerTag) end
				if misc.addToMinionTag then t_insert(tagList, misc.addToMinionTag) end
				if misc.playerTagList then
					for _, tag in ipairs(misc.playerTagList) do
						t_insert(tagList, tag)
					end
				end
				local minionValue = { mod = effectMod }
				if misc.addToMinionType then minionValue.type = misc.addToMinionType end
				if misc.addToMinionTypes then minionValue.minionTypes = misc.addToMinionTypes end
				modList[i] = mod("MinionModifier", "LIST", minionValue, unpack(tagList))
			end
		elseif misc.addToSkill then
			-- Skill enchants or socketed gem modifiers that add additional effects
			for i, effectMod in ipairs(modList) do
				modList[i] = mod("ExtraSkillMod", "LIST", { mod = effectMod }, misc.addToSkill)
			end
		elseif misc.applyToEnemy then
			for i, effectMod in ipairs(modList) do
				local tagList = { }
				if misc.playerTag then t_insert(tagList, misc.playerTag) end
				if misc.playerTagList then
					for _, tag in ipairs(misc.playerTagList) do
						t_insert(tagList, tag)
					end
				end
				local newMod = effectMod
				if effectMod[1] and type(effectMod) == "table" and misc.actorEnemy then
					newMod = copyTable(effectMod)
					newMod[1]["actor"] = "enemy"
				end
				modList[i] = mod("EnemyModifier", "LIST", { mod = newMod }, unpack(tagList))
			end
		end
	end
	return modList, line:match("%S") and line
end

local cache = { }
local unsupported = { }
local count = 0
--local foo = io.open("../unsupported.txt", "w")
--foo:close()
-- "Shared X" mods in Last Epoch apply to BOTH the player and their minions.
-- We expand these into two parses: one for the player (with "Shared" stripped)
-- and one for minions (with the "minion" modFlag appended so addToMinion fires).
local function parseSharedExpanded(line)
	local lower = line:lower()
	local sharedStart, sharedEnd = lower:find(" shared ", 1, true)
	if not sharedStart then
		sharedStart, sharedEnd = lower:find("^shared ")
	end
	if not sharedStart then
		return parseMod(line, 1)
	end
	-- Player line: drop the "shared" word, keep the rest as-is
	local strippedLine = line:sub(1, sharedStart - 1) .. " " .. line:sub(sharedEnd + 1)
	strippedLine = strippedLine:gsub("^%s+", ""):gsub("%s+", " ")
	local pList, pExtra = parseMod(strippedLine, 1)
	-- Minion line: same stripped text but with " minion" appended so the
	-- modFlag scan sets addToMinion=true on every produced mod.
	local mList = parseMod(strippedLine .. " minion", 1)
	local combined = {}
	if pList then
		for i = 1, #pList do t_insert(combined, pList[i]) end
	end
	if mList then
		for i = 1, #mList do t_insert(combined, mList[i]) end
	end
	if #combined == 0 then return nil, pExtra end
	return combined, pExtra
end

-- @leb-regression-guard:ailment-pen-family-fixup
-- "+X% <Type> Penetration with <Ailment>" (gear affixes, passives, idols, tree nodes)
-- parses/bakes as a <Type>Penetration BASE mod tagged {SkillName=<Ailment>}.
-- Pre-fix delivery, precisely (the earlier "whole family was inert" diagnosis was
-- WRONG -- LEB imports each damaging ailment as a separate ACTIVE skill whose
-- granted-effect name == the ailment name, so that pseudo-skill's skillCfg.skillName
-- DOES match the tag; CalcActiveSkill.lua skillCfg.skillName = grantedEffect.name,
-- ModStore.lua case-insensitive SkillName matching):
--  (a) Physical rows ("+15% Physical Penetration with Bleed"): inert on the hit loop
--      everywhere (the hit loop's Physical branch uses the armour-reduction path and
--      never sums pen); live ONLY via the imported pseudo-skill's NESTED-ailment path
--      (calcAilmentMitigation sums <Type>Penetration with cfg.skillName=="Bleed"
--      during the Bleed pseudo-skill's run) -- item sources only, see (c).
--  (b) non-Physical rows ("+10% Fire Penetration with Ignite"): LIVE on the imported
--      pseudo-skill channel for ITEM sources (Item.lua isConnectorOnlyExtra lets the
--      "  with  " residue through): cfg.skillName=="Ignite" matched the tag at the
--      hit loop's pen sum (the pseudo-skill's own DoT damage) AND inside
--      calcAilmentMitigation (its nested ailments).
--  (c) tree/passive sources of ALL types: dropped wholesale at the tree extra gates
--      (PassiveTree.lua:556 / PassiveSpec.lua:1024 drop mods whose extra is
--      non-empty), so they never reached modDB at all.
-- Fix, at the single parse-result chokepoint every line (ModCache-baked or
-- live-parsed) flows through:
--  1. rewrite any such mod into the ailment-scoped penetration channel:
--     name = "Ailment"..<Ailment>..<Type>.."Penetration", SkillName tag removed.
--     calcAilmentMitigation sums the type-qualified key for EVERY skill's nested
--     ailments (newly live for normal skills; for the pseudo-skill's nested path it
--     is the same value the old SkillName match produced), and the hit loop's pen
--     sum is extended with the channel keys for damaging-ailment pseudo-skills only
--     (CalcOffence "pseudo-skill site") so channel (b) keeps its pen -- routing
--     unification, not a behaviour change.
--  2. if the rewrite consumed >=1 mod and the entry's leftover residue is EXACTLY
--     the connector "with", clear it (see the chokepoint below) -- this intentionally
--     ACTIVATES tree/passive family sources (c) for the first time (the purpose of
--     the fix); every other residue is untouched so the tree gates keep dropping
--     genuinely unparsed lines.
-- The type-qualified key keeps dual-type ailments exact (each damage type only receives
-- its own pen). Gated on data.damagingAilment membership so real skill scopes
-- ("with Puncture", "with Shadow Daggers", "with Staff") are untouched. SPACED display
-- names ("with Time Rot": tag carries "Time Rot", the key is "TimeRot") normalize
-- through data.damagingAilmentSpacedName (Modules/Data.lua), which maps a spaced name
-- to its space-stripped key ONLY when no player skill (data.skills treeId) owns that
-- name -- so the two genuine collisions "Bone Curse" (real Acolyte skill BoneCurse)
-- and "Spirit Plague" (real Acolyte skill SpiritPlague) stay SkillName-tagged: there
-- the scope legitimately means the SKILL. The rewrite emits the STRIPPED key
-- ("AilmentTimeRotVoidPenetration") so calcAilmentMitigation's keys match. Idempotent:
-- once rewritten there is no SkillName tag left to match (flag per cache entry).
-- NOTE: the <private build> in-game 134.88-pt bleed-pen residual is NOT this family (that
-- build carries zero family lines; the residual tracks a dynamic in-game added crit
-- multiplier, quantized at 9.6 pts = 48% x 20 crit-mult -- a separate axis).
-- Spec: spec/System/TestAilmentPenFamilyFixup_spec.lua
local function fixupAilmentScopedPen(modList)
	-- Modules/Data may not be loaded yet when ModParser itself loads; resolve the
	-- damaging-ailment allowlist lazily at call time. Returning false leaves the
	-- cache entry unflagged so a later call retries once data is available.
	if not (data and data.damagingAilment and data.damagingAilmentSpacedName) then
		return false
	end
	local rewrote = false
	for _, parsedMod in ipairs(modList) do
		local typePrefix = type(parsedMod) == "table" and type(parsedMod.name) == "string"
			and parsedMod.name:match("^(%a+)Penetration$")
		-- Bare "Penetration" cannot match (the pattern requires a non-empty prefix);
		-- skip names already rewritten into the Ailment channel.
		if typePrefix and not parsedMod.name:match("^Ailment") then
			for i = 1, #parsedMod do
				local tag = parsedMod[i]
				if type(tag) == "table" and tag.type == "SkillName" and tag.skillName then
					-- Direct key ("Bleed") or spaced display name ("Time Rot" -> "TimeRot"
					-- via data.damagingAilmentSpacedName; real-skill collisions "Bone
					-- Curse"/"Spirit Plague" are excluded from that map, so those scopes
					-- keep their SkillName tag -- see the guard comment above).
					local ailmentKey = data.damagingAilment[tag.skillName] and tag.skillName
						or data.damagingAilmentSpacedName[tag.skillName]
					if ailmentKey then
						parsedMod.name = "Ailment" .. ailmentKey .. typePrefix .. "Penetration"
						table.remove(parsedMod, i)
						rewrote = true
						break
					end
				end
			end
		end
	end
	return true, rewrote
end

return function(line, isComb)
	if not cache[line] then
		local modList, extra = parseSharedExpanded(line)
		if modList and extra then
			-- TODO: No need currently, to be removed?
			-- modList, extra = parseMod(line, 2)
		end
		cache[line] = { modList, extra }
		if foo and not isComb and not cache[line][1] then
			local form = line:gsub("[%+%-]?%d+%.?%d*","{num}")
			if not unsupported[form] then
				unsupported[form] = true
				count = count + 1
				foo = io.open("../unsupported.txt", "a+")
				foo:write(count, ': ', form, (cache[line][2] and #cache[line][2] < #line and ('    {' .. cache[line][2]).. '}') or "", '\n')
				foo:close()
			end
		end
	end
	local entry = cache[line]
	-- Apply the ailment-pen family fixup once per cache entry (see guard comment above).
	-- The dedupe flag lives on the entry WRAPPER, not the modList: Main.lua SaveModCache
	-- serializes only entry[1] (writeLuaTable) and entry[2], so the flag can never leak
	-- into a regenerated Data/ModCache.lua. Saving REWRITTEN mods is stable: a rewritten
	-- mod carries no ailment SkillName tag, so the fixup is a structural no-op on reload.
	if entry[1] and not entry.ailmentPenFixed then
		local applied, rewrote = fixupAilmentScopedPen(entry[1])
		if applied then
			entry.ailmentPenFixed = true
			-- Tree/passive delivery (guard point 2): a family line's only leftover is the
			-- scope connector ("  with  " in entry[2]). PassiveTree.lua:556 and
			-- PassiveSpec.lua:1024 drop any mod whose extra is non-empty, so without this
			-- the rewritten family mods would still never reach modDB from tree/passive
			-- sources (e.g. tree_0.json node stat "+15% Physical Penetration with Bleed").
			-- Clear the residue ONLY when this entry actually had >=1 mod rewritten AND
			-- the residue is exactly the bare connector "with" (case/whitespace-
			-- insensitive) -- intentionally activating tree/passive family sources for
			-- the first time. Every other residue (real skill scopes, unparsed text) is
			-- untouched, so the tree gates keep their behaviour for all other lines.
			-- Item/idol sources already passed via Item.lua isConnectorOnlyExtra.
			if rewrote and type(entry[2]) == "string" and entry[2]:lower():gsub("%s+", "") == "with" then
				entry[2] = nil
			end
		end
	end
	return unpack(copyTable(entry))
end, cache
