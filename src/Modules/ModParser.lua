-- Last Epoch Building
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
	["health leech"] = "DamageLifeLeech",
	["health"] = "Life",
	["health regen"] = "LifeRegen",
	["health regeneration"] = "LifeRegen",
	["maximum health"] = "Life",
	["mana"] = "Mana",
	["maximum mana"] = "Mana",
	["mana regen"] = "ManaRegen",
	["mana cost"] = "ManaCost",
	["channel cost"] = "ChannelCost",
	-- Primary defences
	["armour"] = "Armour",
	["armor"] = "Armour",
	["dodge rating"] = "Evasion",
	["ward"] = "Ward",
	["endurance"] = "Endurance",
	["endurance threshold"] = "EnduranceThreshold",
	["ward decay threshold"] = "WardDecayThreshold",
	["ward per second"] = "WardPerSecond",
	["ward retention"] = "WardRetention",
	["ward regen"] = "WardPerSecond",
	["glancing blow chance"] = "GlancingBlowChance",
	["chance to take 0 damage when hit"] = "GlancingBlowChance",
	["block effectiveness"] = "BlockEffectiveness",
	["stun avoidance"] = "StunAvoidance",
	["crit avoidance"] = "CritAvoidance",
	["critical strike avoidance"] = "CritAvoidance",
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
	-- Stun/knockback modifiers
	["stun duration on you"] = "StunDuration",
	["armor while channelling"] = "ArmourWhileChannelling",
	["leech rate"] = "LeechRate",
	["stun duration"] = "EnemyStunDuration",
	["knockback distance"] = "EnemyKnockbackDistance",
	-- Auras/curses/buffs
	["buff effect"] = "BuffEffect",
	-- On hit/kill/leech effects
	["health gain on kill"] = "LifeOnKill",
	["health gain on hit"] = { "LifeOnHit", flags = ModFlag.Hit },
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
	["to apply frailty"] = "FrailtyChance",
	["to blind"] = "BlindChance",
	["to electrify"] = "ElectrifyChance",
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
	["for (%d+) seconds"] = { },
	[" on critical strike"] = { tag = { type = "Condition", var = "CriticalStrike" } },
	["from critical strikes"] = { tag = { type = "Condition", var = "CriticalStrike" } },
	-- Multipliers
	["per level"] = { tag = { type = "Multiplier", var = "Level" } },
	-- Per stat
	["per (%d+) total attributes"] = function(num) return { tag = { type = "PerStat", statList = Attributes, div = num } } end,
	["per (%d+) maximum mana"] = function(num) return { tag = { type = "PerStat", stat = "Mana", div = num } } end,
	["per (%d+) max mana"] = function(num) return { tag = { type = "PerStat", stat = "Mana", div = num } } end,
	["per (%d+)%% block chance"] = function(num) return { tag = { type = "PerStat", stat = "BlockChance", div = num } } end,
	["per (%d+) block effectiveness"] = function(num) return { tag = { type = "PerStat", stat = "BlockEffect", div = num } } end,
	["per totem"] = { tag = { type = "PerStat", stat = "TotemsSummoned" } },
	["for each of your totems"] = { tag = { type = "PerStat", stat = "TotemsSummoned" } },
	["for your totems"] = { tag = { type = "Scope", scope = "totem" } },
	["for minions"] = { tag = { type = "Scope", scope = "minion" } },
	["for your minions"] = { tag = { type = "Scope", scope = "minion" } },
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
	["while at high health"] = { tag = { type = "Condition", var = "HighHealth" } },
	["while you have ward"] = { tag = { type = "Condition", var = "HaveWard" } },
	["while you have lightning aegis"] = { tag = { type = "Condition", var = "HaveLightningAegis" } },
	["while you have haste"] = { tag = { type = "Condition", var = "Haste" } },
	["while you have frenzy"] = { tag = { type = "Condition", var = "Frenzy" } },
	["while you have an ailment overload"] = { tag = { type = "Condition", var = "HaveAilmentOverload" } },
	["while on consecrated ground"] = { tag = { type = "Condition", var = "OnConsecratedGround" } },
	["while you have a companion"] = { tag = { type = "Condition", var = "HaveCompanion" } },
	["with arcane shield"] = { tag = { type = "Condition", var = "HaveArcaneShield" } },
	["per arcane shield"] = { tag = { type = "Multiplier", var = "ArcaneShieldStack" } },
	["per companion"] = { tag = { type = "Multiplier", var = "Companion" } },
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
	-- Transformation form conditions
	["while in werebear form"] = { tag = { type = "Condition", var = "InWerebearForm" } },
	["in werebear form"] = { tag = { type = "Condition", var = "InWerebearForm" } },
	["while in spriggan form"] = { tag = { type = "Condition", var = "InSprigganForm" } },
	["in spriggan form"] = { tag = { type = "Condition", var = "InSprigganForm" } },
	["while in swarmblade form"] = { tag = { type = "Condition", var = "InSwarmbladeForm" } },
	["in swarmblade form"] = { tag = { type = "Condition", var = "InSwarmbladeForm" } },
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
	modTagList["per player " .. stat:lower()] = { tag = { type = "PerStat", stat = Attributes[i], actor = "parent" } }
	modTagList["per (%d+) " .. stat:lower()] = function(num) return { tag = { type = "PerStat", stat = Attributes[i], div = num } } end
	modTagList["w?h?i[lf]e? you have at least (%d+) " .. stat:lower()] = function(num) return { tag = { type = "StatThreshold", stat = Attributes[i], threshold = num } } end
end
-- Also handle abbreviated attribute names (e.g. "Per Int" in addition to "Per Intelligence")
for i,stat in ipairs(Attributes) do
	local abbr = stat:lower()
	modTagList["per " .. abbr] = { tag = { type = "PerStat", stat = Attributes[i] } }
	modTagList["per player " .. abbr] = { tag = { type = "PerStat", stat = Attributes[i], actor = "parent" } }
	modTagList["per (%d+) " .. abbr] = function(num) return { tag = { type = "PerStat", stat = Attributes[i], div = num } } end
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
	modTagList["per equipped " .. weapon:lower()] = { tag = { type = "Multiplier", var = weapon .. "Item" } }
	modTagList["per " .. weapon:lower()] = { tag = { type = "Multiplier", var = weapon .. "Item" } }
end
modTagList["with spear"] = { tag = { type = "Condition", var = "UsingSpear" } }
modTagList["with a spear"] = { tag = { type = "Condition", var = "UsingSpear" } }

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
	["^([%+%-]?[%d%.]+%%) Cast Speed"] = "%1 increased Cast Speed",
	["^([%+%-]?[%d%.]+%%) Cooldown Recovery Speed"] = "%1 increased Cooldown Recovery Speed",
	["^([%+%-]?[%d%.]+%%) Duration"] = "%1 increased Duration",
	["^([%+%-]?[%d%.]+%%) Movespeed"] = "%1 increased Movespeed",
	["%(up to %d+%)%s*$"] = "",
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

local specialModList = {
	["no cooldown"] = { flag("NoCooldown") },
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
	-- Runemaster: Sanguine Runestones 6-point bonus
	["^(%d+)%% health regen also applies to ward$"] = function(num)
		return { mod("LifeRegenAppliesToWard", "BASE", tonumber(num)) }
	end,
}

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
local function scan(line, patternList, plain, matchAll)
	local bestIndex, bestEndIndex
	local bestPattern = ""
	local bestVal, bestStart, bestEnd, bestCaps
	local lineLower = line:lower()
	for pattern, patternVal in pairs(patternList) do
		local index, endIndex, cap1, cap2, cap3, cap4, cap5 = lineLower:find(pattern, 1, plain)
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
			return specialMod(tonumber(cap[1]), unpack(cap))
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

	-- Check for tags (per-charge, conditionals)
	local modTag, modTag2, tagCap
	modTag, line, tagCap = scan(line, modTagList)
	if type(modTag) == "function" then
		if tagCap[1]:match("%d+") then
			modTag = modTag(tonumber(tagCap[1]), unpack(tagCap))
		else
			modTag = modTag(tagCap[1], unpack(tagCap))
		end
	end
	if modTag then
		modTag2, line, tagCap = scan(line, modTagList)
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
	if not modName and modForm == "BASE" and skillTag and skillTag.tag and skillTag.tag.type == "SkillName" then
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
			-- Minion modifiers
			for i, effectMod in ipairs(modList) do
				local tagList = { }
				if misc.playerTag then t_insert(tagList, misc.playerTag) end
				if misc.addToMinionTag then t_insert(tagList, misc.addToMinionTag) end
				if misc.playerTagList then
					for _, tag in ipairs(misc.playerTagList) do
						t_insert(tagList, tag)
					end
				end
				modList[i] = mod("MinionModifier", "LIST", { mod = effectMod }, unpack(tagList))
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
return function(line, isComb)
	if not cache[line] then
		local modList, extra = parseMod(line, 1)
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
