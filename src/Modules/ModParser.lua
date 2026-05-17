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
	-- (e.g. BM6x3nKn lv66 Bladedancer). The form scanner consumes `N% chance`
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
	-- Note: formList "% of" pattern (line ~29) consumes the "of" token from
	-- "25% of damage reflected", so the modNameList key must NOT include "of".
	-- See Obsidian "ShutFackUp lv85 Spellblade in-game stats.md" #8.
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
	-- Symptoms before fix: BgRrP5rr OverkillLeech LE=16 LEB=0; Q9J4wvmD
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
	["potion slots"] = "PotionSlots",
	["minion power from character level"] = "MinionPowerFromCharLevel",
	["health lost on kill"] = "LifeLossOnKillPercent",
	-- Projectile modifiers
	["extra projectiles"] = "ProjectileCount",
	["projectiles"] = "ProjectileCount",
	["projectile speed"] = "ProjectileSpeed",
	-- Totem/trap/mine/brand modifiers
	["totem duration"] = "TotemDuration",
	-- Other skill modifiers
	["radius"] = "AreaOfEffect",
	["area"] = "AreaOfEffect",
	["area of effect"] = "AreaOfEffect",
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
	["to inflict doom"] = "DoomChance",
	["doom chance"] = "DoomChance",
	["to apply damned"] = "DamnedChance",
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

for skillId, skill in pairs(data.skills) do
    -- The player cannot trigger a minion skill and cannot trigger "Stacking" variants of skills
    if not skill.fromMinion and not skillId:find("Stacking") then
    	modNameList["chance to " .. skill.name:lower()] = {"ChanceToTriggerOnHit_"..skillId, flags = ModFlag.Hit}
    	modNameList["to " .. skill.name:lower()] = {"ChanceToTriggerOnHit_"..skillId, flags = ModFlag.Hit}
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
	modNameList[damageType:lower() .. " damage over time"] = { damageType .. "Damage", flags = ModFlag.Dot + ModFlag[damageType] }
	for _, damageSourceType in ipairs(DamageSourceTypes) do
	   modNameList[damageType:lower() .. " " .. damageSourceType:lower() .. " damage"] = {damageType .. "Damage", keywordFlags = KeywordFlag.Spell}
	end
end

modNameList["penetration"] = "Penetration"

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
	-- Slot conditions
	["while dual wielding"] = { tag = { type = "Condition", var = "DualWielding" } },
	["while wielding a two handed melee weapon"] = { tagList = { { type = "Condition", var = "UsingTwoHandedWeapon" }, { type = "Condition", var = "UsingMeleeWeapon" } } },
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
	["with arcane shield"] = { tag = { type = "Condition", var = "HaveArcaneShield" } },
	["with concentration"] = { tag = { type = "Condition", var = "Concentration" } },
	-- @leb-regression-guard: per-set-fractional-precision
	-- roundAfterMultiply lets ModStore:EvalMod floor(value × CompleteSetCount)
	-- so per-set affixes match LE's calc order (round AFTER multiply, not before).
	-- See ItemTools.lua precision=1000 bump for per-set Integer rolls.
	["per complete set"] = { tag = { type = "Multiplier", var = "CompleteSetCount", roundAfterMultiply = true } },
	["per arcane shield"] = { tag = { type = "Multiplier", var = "ArcaneShieldStack" } },
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
	-- Per-active minion/summon multipliers (DPS-integrated via Config tab counts)
	["per active totem"] = { tag = { type = "PerStat", stat = "TotemsSummoned" } },
	["per active dread shade"] = { tag = { type = "Multiplier", var = "ActiveDreadShade" } },
	["per active maelstrom"] = { tag = { type = "Multiplier", var = "ActiveMaelstrom" } },
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
	-- every resistance on B4Xq8aG6 (and any shield-using build).
	-- Spec: spec/System/TestModParse_spec.lua "with a shield condition tag"
	["with a shield"] = { tag = { type = "Condition", var = "UsingShield" } },
	-- @leb-regression-guard:while-with-a-shield-condition
	-- Sentinel-90 "Sanctuary Guardian" notScalingStats also uses the long form
	-- "While With A Shield" (e.g. "+50 Armor While With A Shield"). Without this
	-- entry the trailing " while with a shield" leaves residual extra and the
	-- entire mod is silently dropped from modDB on AVa9YEkg (Paladin, lv95).
	-- Spec: spec/System/TestModParse_spec.lua "while with a shield condition tag"
	["while with a shield"] = { tag = { type = "Condition", var = "UsingShield" } },
	-- @leb-regression-guard:traitors-tongue-offhand-crit-flat
	-- Traitor's Tongue (dual-wield dagger) has cross-slot self-referential mods:
	-- "+(10-13)% Parry Chance with Traitor's Tongue equipped in the mainhand"
	-- "+(10-13)% Critical Strike Chance with Traitor's Tongue equipped in the offhand"
	-- Without these matchers the trailing condition survives as residual extra and
	-- Item.lua's processModLine (isConnectorOnlyExtra) silently drops the entire
	-- mod from modDB — e.g. on QWXjqWJ2 (Bladedancer, lv100) the +12 flat
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
	["per arcane momentum stack"] = { tag = { type = "Multiplier", var = "ArcaneMomentumStack" } },
	-- Blocking
	["on block"] = { tag = { type = "Condition", var = "Blocking" } },
	["while blocking"] = { tag = { type = "Condition", var = "Blocking" } },
}

for i,stat in ipairs(LongAttributes) do
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
	--   Qqwvdex2 lv98 Beastmaster   (LETools 24% / LEB 0 -> after fix: 24)
	--   oy4Jk2Y9 lv100 Beastmaster  (LETools 32% / LEB 0 -> after fix: 32)
	--   oN2zNnaR lv100 Necromancer  (LETools 27% / LEB 0): NOT FIXED here -- its
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
local skillNameByLower = {}
for _, skill in pairs(data.skills) do
	if skill.name then
		skillNameByLower[skill.name:lower()] = skill.name
	end
end

-- Normalize a captured skill phrase and return canonical skill name or nil
local function canonicalSkillName(phrase)
	if not phrase then return nil end
	phrase = phrase:match("^%s*(.-)%s*$")
	return skillNameByLower[phrase:lower()]
end

local specialModList = {
	["no cooldown"] = { flag("NoCooldown") },
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
	-- BxvJP3g1 Altar of Arctus: "+(46-52)% Effect of Weaver Enchantment
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
	-- Ward when hit (item affix: "X% Chance to Gain 30 Ward when Hit")
	["^(%d+)%% chance to gain (%d+) ward when hit$"] = function(num, chance, amount)
		return { mod("ChanceToGainWardWhenHit", "BASE", tonumber(chance)), mod("WardGainedWhenHit", "BASE", tonumber(amount)) }
	end,
	-- Minion damage mods from uniques
	["^your minions deal (%d+)%% increased damage$"] = function(num)
		return { mod("MinionModifier", "LIST", { mod = mod("Damage", "INC", num) }) }
	end,
	["^you and your minions deal (%d+)%% increased melee damage$"] = function(num)
		return { mod("Damage", "INC", num, "", ModFlag.Melee), mod("MinionModifier", "LIST", { mod = mod("Damage", "INC", num, "", ModFlag.Melee) }) }
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
	["^%+?(%d+)%% ward retention per 100%% uncapped cold resistance$"] = function(num)
		return { mod("WardRetention", "BASE", num, "", 0, 0, { type = "PerStat", stat = "ColdResist", div = 100 }) }
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
	-- Ward/Health on melee hit (item affix patterns)
	["^(%d+)%% chance to gain (%d+) ward on melee hit$"] = function(num, chance, amount)
		return { mod("ChanceToGainWardOnMeleeHit", "BASE", tonumber(chance)), mod("WardGainedOnMeleeHit", "BASE", tonumber(amount)) }
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
	-- Sentinel Defiance: "+1 Endurance Threshold Per 2% Uncapped Elemental Resistance"
	["^%+?(%d+) endurance threshold per 2%% uncapped elemental resistance$"] = function(num)
		return { mod("EnduranceThresholdPerUncappedEleRes", "BASE", tonumber(num)) }
	end,
	-- Stone Shield (unique): "+1% Block Chance per 2% Endurance above the Cap"
	["^%+?(%d+)%% block chance per (%d+)%% endurance above the cap$"] = function(_, num, div)
		return { mod("BlockChance", "BASE", tonumber(num), { type = "PerStat", stat = "EnduranceOverCap", div = tonumber(div) }) }
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
	-- Game-file source (dump.cs CharacterMutator):
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

	-- Tabi of Dusk and Dawn (uniqueID=458, body=3/3, boots): two paired
	-- Shadow-Rend-specific descriptive lines that the game treats as pure
	-- tooltip text -- there is no numerically scaling stat and no
	-- CharacterMutator field backing either clause. Before this anchor both
	-- lines were silent-failure no-ops: they parsed to empty modList with
	-- the full residue string echoed back, which polluted ModCache and made
	-- the unique appear partially unrecognized.
	--
	-- Why descriptive-only (not real wiring): "manifests a melee shadow + a
	-- bow shadow" would require per-cast shadow-type composition (1 melee
	-- slot + 1 bow slot for Shadow Rend specifically), and "no longer moves
	-- you" is a behavior toggle on the player skill animation. Neither
	-- maps onto F1 MaxShadows (integer count only) nor F3/F9
	-- MinionType=ShadowClone (uniform shadow pool, no melee/bow split).
	-- Combat-loop attribution is deferred; v1 is parser-anchored only so
	-- the lines stop polluting ModCache and a future calc consumer can
	-- attach by uniqueID without re-touching the parser.
	-- Tabi of Dusk and Dawn (uniqueID=458, boots) carries two paired
	-- Shadow Rend toggles. Game-file evidence (LE 1.4.6 dump.cs):
	--
	--   public bool shadowRendAlsoCastsOtherWeaponVersion; // 0x180B
	--   public bool shadowRendNoPlayerMovement;            // 0x180C
	--
	-- Both are plain bool fields on CharacterMutator, sandwiched
	-- between the lethalMirage* fields at L77720-77735 -- the same
	-- section that backs the cooldown-recovered-on-hit-consumer guard.
	-- Not pure descriptive: real toggles with measurable DPS effect
	-- (dual-cast doubles the player's Shadow Rend swing by casting
	-- both melee and bow ability variants; see ShadowRendMeleeMutator
	-- and ShadowRendBowMutator cross-references in dump.cs L56914,
	-- L57008 -- each holds a reference to the other variant's
	-- mutator). ability_keyed_array.json (extracted/) confirms two
	-- ability prefabs sharing playerAbilityID 'sh4re':
	--   {key=-1115253059, unityObjectName="ShadowRend"}
	--   {key=1439430948,  unityObjectName="ShadowRend Bow"}
	--
	-- v1 wiring:
	--   - Parse both lines to FLAG mods tagged with
	--     SkillName="Shadow Rend" (canonical SkillName per
	--     CalcOffence.lua shadowAttackSkills allowlist).
	--   - CalcOffence consumes ShadowRendAlsoCastsOtherWeaponVersion
	--     as +100% MORE Damage when active skill is Shadow Rend
	--     (surface approximation; the melee and bow variants have
	--     non-identical damage rolls, so a v2 paired-cast computation
	--     would be more accurate).
	--   - ShadowRendNoPlayerMovement has no DPS-layer consumer
	--     (movement behavior only); the FLAG is recorded so future
	--     UI / config layers can surface it.
	--
	-- Flag names mirror the dump.cs field identifiers verbatim for
	-- game-file authoritativeness.
	-- @leb-regression-guard:tabi-of-dusk-and-dawn-flags
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
	-- Kuzon's Fury Reforged (statOrderKey=961, 8 tiers, ModItem.json
	-- L67773-L67890). Source line:
	--   "+(N)% chance to throw a Burning Dagger when you use a melee
	--    fire attack and hit at least one enemy, doubled for Dancing
	--    Strikes (up to 4 times per second)"
	--
	-- Game-file evidence (LE 1.4.6 dump.cs):
	--   L77400  public float burningDaggerChanceOnMeleeFire;
	--             (on AbilityStatsMutatorManager -- per-skill stat
	--              aggregator; THIS affix's exact target field)
	--   L96248  public float chanceToThrowBurningDaggerOnHit;
	--             (on CharacterMutator -- a *different* generic on-hit
	--              version with its own ProcTimeTracker; not this affix)
	--   L33670-L33715  BurningDaggerMutator (ability body)
	--   L35408-L35546  DancingStrikes1..4Mutator family
	--   ability_keyed_array.json  4 player variants share
	--             abilityName="Dancing Strikes" (playerAbilityID
	--             dacn33/34/36/37) -- skill identity, not condition tag.
	--
	-- Stat name `BurningDaggerChanceOnMeleeFire` is dump.cs L77400
	-- verbatim (PascalCase'd). Game-file-authoritative naming per the
	-- F11 MirageCount / cooldown-recovered guard precedent.
	--
	-- The trailing ", doubled for Dancing Strikes" clause is baked
	-- into the mod tag list as Condition{DancingStrikes, mult=2}; the
	-- CalcOffence-side condition gate (dancingStrikesSkills allowlist)
	-- mirrors the F5 ShadowAttack skill-identity pattern.
	--
	-- The "(up to 4 times per second)" rate cap has no LEB infra today
	-- (Limit / ProcTimeTracker family not modelled). v1 absorbs the
	-- clause into the full-line anchor so the residue is consumed; the
	-- chance value is surfaced without a per-second cap. A v2 Limit
	-- infra task is spawned separately.
	--
	-- Tier 7 outlier (`{rounding:Integer}+(1-1.2)` with no `%`) is
	-- deferred: it could be a fraction-representation (1.0=100%) per
	-- the natural tier-6 (60-70%) -> tier-7 (100%) progression, or a
	-- game-data typo. Until verified the tier-7 line emits no mod and
	-- the mangled residue is cleared.
	-- Design fork rationale:
	--   Obsidian "Kuzon's Fury Reforged 設計フォーク.md"
	-- @leb-regression-guard:proc-rate-limit-metadata-v1
	-- The trailing "(up to 4 times per second)" clause is game-file-authoritative
	-- runtime semantics (ProcTimeTracker; dump.cs L239352-L239378 class +
	-- L33671-L33713 BurningDaggerMutator.burningDaggerOnMeleeFirePTT). The
	-- per-PTT (limit, interval) pair is hardcoded in the C# Awake() init, NOT
	-- parameterised in localisation (`Property_Ability_burningDagger_3_Name`
	-- carries the suffix verbatim). The game exposes no planner-visible
	-- effective-rate stat -- the cap is a runtime gate only -- so LEB
	-- preserves the cap as passive metadata and does NOT compute equilibrium
	-- procs/sec. The RateLimit tag is a no-op for value sums (no handler in
	-- ModStore.lua `EvalMod`); CalcSections reads it for display only.
	-- See REGRESSION_GUARDS.md "proc-rate-limit-metadata-v1".
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
	specialModList["^%+?([%d%.]+)%% increased effect of " .. esc .. " on you$"] = function(num)
		return nsList(mod(bVar .. "Effect", "INC", num))
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
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on hit$"] = function(num)
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnHit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " on crit$"] = function(num)
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnCrit" }))
		end
		specialModList["^%+?([%d%.]+)%% chance to cast " .. esc .. " when you use a potion$"] = function(num)
			return nsList(mod("ChanceToCast_" .. canonical:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = canonical }, { type = "Condition", var = "OnPotionUse" }))
		end
	end
end

-- Recognition-only: trigger one skill when you cast/use another
-- e.g. "10% Chance to cast Marrow Shards when you cast Transplant"
-- Single generic pattern with skill-name validation in the handler (avoids N^2 pattern blowup).
specialModList["^%+?([%d%.]+)%% chance to cast (.+) when you cast (.+)$"] = function(num, _, triggerName, castName)
	local trig = canonicalSkillName(triggerName)
	local cast = canonicalSkillName(castName)
	if not trig or not cast then return nil end
	return nsList(mod("ChanceToCast_" .. trig:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = trig }, { type = "Condition", var = "OnCast_" .. cast:gsub("%s+","") }))
end
specialModList["^%+?([%d%.]+)%% chance to cast (.+) when you use (.+)$"] = function(num, _, triggerName, castName)
	local trig = canonicalSkillName(triggerName)
	local cast = canonicalSkillName(castName)
	if not trig or not cast then return nil end
	return nsList(mod("ChanceToCast_" .. trig:gsub("%s+",""), "BASE", num, "", 0, 0, { type = "SkillName", skillName = trig }, { type = "Condition", var = "OnUse_" .. cast:gsub("%s+","") }))
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
-- Game-file backing: dump.cs L22771 `RogueShadow.duskShroudChanceOnConsumption`
-- (field consumed inside `ConsumeShadow()` at L22808); dump.cs L123962
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
specialModList["^%+?([%d%.]+)%% chance to gain (.+) when hit$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) when you are hit$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) on hit$"] = nsAny
specialModList["^%+?([%d%.]+)%% chance to gain (.+) on kill$"] = nsAny
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
-- Handler args: (num, cap1_str, ailmentName). Return nil on known → generic chain fires.
local function ailmentApplyHandler(num, _, ailmentName)
	if ailmentName and knownAilmentChances[ailmentName:lower()] then
		return nil
	end
	return nsAny(num)
end
local function ailmentApplyHandler2(num, _, ailmentName)
	-- For "on <X> hit" and "when you <X>" forms where cap[3] is the trigger qualifier.
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

-- Resource conversion / spend-gained
-- DPS-integrated: "X% of Mana Spent Gained as Ward" emits ManaSpentGainedAsWard,
-- which CalcPerform consumes after offence computes ManaPerSecondCost to add to
-- WardPerSecond. Unknown resource/target combos fall through to nsAny for
-- recognition-only (keeps existing Obsidian notes / tests green).
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
-- (dump.cs L95850, offset 0xDB0) with const cooldown 2s (L95851). Distinct
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

-- @leb-regression-guard: game-faithful-parry-conversion
-- "+N Block Chance converted to Parry Chance while not wielding a shield" — the only
-- known source is the unique sword `Clotho's Needle` (uniques_1_4.json #417, mod text
-- "+1 Block Chance converted to Parry Chance while not wielding a shield"). Game-faithful
-- behavior per GameAssembly.dll decompile (LE_datamining/extracted/block_decompile.txt):
--   * Property #531 `playerPropertyBlockChanceConvertedToParryWithoutShield` is a bool
--     set unconditionally by the mod; when set AND no shield, blockConversion=Parry.
--   * `blockChanceForCharacterSheet` (RVA 0x2344f70) returns 0 when blockConversion!=None.
--   * `parryChanceForCharacterSheet` (RVA 0x2345390) when blockConversion==Parry returns
--     min(blockBase, maxBlock) + parryBonus, capped at ParryCap (75).
-- Implementation: emit BlockChance BASE +N (unconditional, joins regular block pool)
-- AND a FLAG mod `BlockChanceConvertedToParryWithoutShield`. CalcDefence checks the
-- flag + UsingShield condition and routes Block→Parry per the decompile semantics.
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
	["weaver item"] = true, ["weaver items"] = true,
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
-- Triangulation case (g1 BxvJP3g1 lv99 Necromancer, Acolyte-21#8):
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
specialModList["^%+?([%d%.]+)%% (.+) if you have (.+) recently$"] = nsAny
specialModList["^%+?([%d%.]+) (.+) if you have (.+) recently$"] = nsAny
specialModList["^%+?([%d%.]+)%% (.+) if you have (.+) in the last (%d+) seconds?$"] = nsAny

-- 17. Skill base damage conversion ("X% of <skill> Base Damage converted to <damageType>")
-- Only the "base damage" variant is added — the generic "% of X damage converted to Y"
-- is already handled by the generic conversion suffix chain.
specialModList["^%+?([%d%.]+)%% of (.+) base damage converted to (.+)$"] = nsAny

-- 19. Cross-type damage gained-as-added ("Added Melee Damage gained as Added Spell Damage")
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
-- LEB_NotSupported and reintroduce a -30 CritExtraDmgRed diff on B4Xq8aG6.
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

-- Compound "... this effect is doubled if ..." clauses (e.g. doubled-at-300-mana).
-- Intentionally NOT hooked as specialModList — the trailing clause is matched via
-- modTagList ("this effect is doubled if you have N or more maximum mana") which
-- emits a StatThreshold tag with mult=2, letting the generic parser handle the
-- "X% increased <stat>" head. Hooking nsAny here would swallow the whole line.

-- Modifiers that are recognised but unsupported
local unsupportedModList = {
	["chance to shred # resistance on hit"] = true,
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
	-- Handle -> conversion syntax
	if line:find("->", 1, true) then
		local convMods = parseArrowConversion(line)
		if convMods then
			return convMods, ""
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
				or modNameStr == "ManaRegen" or modNameStr == "LifeRegen") then
			-- @leb-regression-guard: regen-pct-shorthand-inc
			-- LE convention: "+N% Health/Mana/Ward/ManaRegen/LifeRegen" (without "increased")
			-- is rendered in-game as an INC modifier. Game's authoritative
			-- localized_master.json affix 1015 affixProperties[1] (Mana Regen)
			-- has modifierType=1 (INC) and extraRolls stored as 0.08-0.09 (= 8-9%
			-- multiplier). ModItem_1_4.json renders the row as "+(8-9)% Mana Regen"
			-- following LE in-game text shorthand. Without ManaRegen/LifeRegen here,
			-- ModParser falls through to BASE and the affix is treated as flat
			-- "+8 Mana Regen" instead of "8% increased Mana Regen", causing
			-- ~+15.5/s drift on Qqwv73q2 (LE 16.72 vs LEB 32.20). See spec
			-- TestModParser_spec.lua "regen-pct-shorthand-inc".
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
	return unpack(copyTable(cache[line]))
end, cache
