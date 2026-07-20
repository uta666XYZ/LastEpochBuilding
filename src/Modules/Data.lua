-- Last Epoch Building
--
-- Module: Data
-- Contains static data used by other modules.
--

LoadModule("Data/Global")

local m_min = math.min
local m_max = math.max
local m_floor = math.floor
local t_insert = table.insert
local t_concat = table.concat

local function makeSkillMod(modName, modType, modVal, flags, keywordFlags, ...)
	return {
		name = modName,
		type = modType,
		value = modVal,
		flags = flags or 0,
		keywordFlags = keywordFlags or 0,
		...
	}
end
local function makeFlagMod(modName, ...)
	return makeSkillMod(modName, "FLAG", true, 0, 0, ...)
end
local function makeSkillDataMod(dataKey, dataValue, ...)
	return makeSkillMod("SkillData", "LIST", { key = dataKey, value = dataValue }, 0, 0, ...)
end

-----------------
-- Common Data --
-----------------

-- These are semi-structured
----------------------------------------
-- Everything not in a later category
-- Item mods & jewel data
-- Boss data, skills and minions
-- Remaining Item Data and uniques
----------------------------------------

data = { }

data.powerStatList = {
	{ stat = nil, label = "Offence/Defence", combinedOffDef = true, ignoreForItems = true },
	{ stat = nil, label = "Name", itemField = "Name", ignoreForNodes = true, reverseSort = true, transform = function(value)
		return value:gsub("^The ", "")
	end },
	{ stat = "FullDPS", label = "Full DPS" },
	{ stat = "CombinedDPS", label = "Combined DPS" },
	{ stat = "TotalDPS", label = "Hit DPS" },
	{ stat = "AverageDamage", label = "Average Hit" },
	{ stat = "Speed", label = "Attack/Cast Speed" },
	{ stat = "TotalDot", label = "DoT DPS" },
	{ stat = "Life", label = "Health" },
	{ stat = "LifeRegen", label = "Health regen" },
	{ stat = "LifeLeechRate", label = "Health leech" },
	{ stat = "Armour", label = "Armor" },
	{ stat = "Evasion", label = "Evasion" },
	{ stat = "Mana", label = "Mana" },
	{ stat = "ManaRegen", label = "Mana regen" },
	{ stat = "ManaLeechRate", label = "Mana leech" },
	{ stat = "Ward", label = "Ward" }
}

for i, attribute in ipairs(Attributes) do
	t_insert(data.powerStatList, { stat=attribute, label=AttributesColored[i] })
end

tableInsertAll(data.powerStatList, {
	{ stat = "TotalAttr", label = "Total Attributes" },
	{ stat = "TotalEHP", label = "Effective Hit Pool" },
	{ stat = "SecondMinimalMaximumHitTaken", label = "Eff. Maximum Hit Taken" }
})

for i, damageType in ipairs(DamageTypes) do
	t_insert(data.powerStatList, { stat=damageType .. "TakenHit", label=DamageTypeColors[i] .. "Taken " .. damageType .. " dmg", transform=function(value) return -value end })
end

tableInsertAll(data.powerStatList,{
	{ stat="CritChance", label="Crit Chance" },
	{ stat="CritMultiplier", label="Crit Multiplier" },
	{ stat="EffectiveMovementSpeedMod", label="Move speed" },
	{ stat="BlockChance", label="Block Chance" },
})

data.misc = { -- magic numbers
	AccuracyPerDexBase = 2,
	LowPoolThreshold = 0.5,
	TemporalChainsEffectCap = 75,
	BuffExpirationSlowCap = 0.25,
	-- LE inherent base critical strike chance: every hit starts at 5% (datamined game source Stats.baseCritChance = 0.05,
	-- a global constant). skills.json carries critChance=5 on 137 abilities but OMITS the field on ~206
	-- others (e.g. Shatter Strike, Wandering Spirits); this constant is the fallback so those skills are
	-- not silently dropped to 0 base crit. See @leb-regression-guard: inherent-base-crit-chance.
	BaseCritChance = 5,
	-- LE defense caps
	DamageReductionCap = 85, -- LE armor mitigation cap
	ResistFloor = -200,
	MaxResistCap = 75, -- LE resistance cap (75%)
	EvadeChanceCap = 95,
	DodgeChanceCap = 85, -- LE dodge chance cap (85%)
	AvoidChanceCap = 75,
	WardRechargeDelay = 4,
	Transfiguration = 0.3,
	EnemyMaxResist = 75,
	-- @leb-regression-guard:leech-le-instance-model
	-- Validation provenance is retained in maintainer notes.
	LeechDuration = 3, -- LE LeechTracker.defaultLeechDuration (seconds), datamined game source
	DotDpsCap = 35791394, -- (2 ^ 31 - 1) / 60 (int max / 60 seconds)
	-- LE ailment base values (from support.lastepoch.com)
	BleedBaseDamage = 53, -- Physical DoT per stack
	BleedDurationBase = 3, -- seconds
	IgniteBaseDamage = 40, -- Fire DoT per stack
	IgniteDurationBase = 2.5, -- seconds
	PoisonBaseDamage = 28, -- Poison DoT per stack
	PoisonDurationBase = 3, -- seconds
	FrostbiteBaseDamage = 50, -- Cold DoT per stack
	FrostbiteDurationBase = 3, -- seconds
	ElectrifyBaseDamage = 44, -- Lightning DoT per stack
	ElectrifyDurationBase = 2.5, -- seconds
	DamnedBaseDamage = 35, -- Necrotic DoT per stack
	DamnedDurationBase = 2.5, -- seconds
	TimeRotBaseDamage = 60, -- Void DoT per stack
	TimeRotDurationBase = 3, -- seconds
	-- Legacy PoE ailment values (kept for backward compat until full migration)
	BleedPercentBase = 70,
	PoisonPercentBase = 0.30,
	IgnitePercentBase = 0.9,
	TrapTriggerRadiusBase = 10,
	MineDetonationRadiusBase = 60,
	MineAuraRadiusBase = 35,
	BrandAttachmentRangeBase = 30,
	ProjectileDistanceCap = 150,
	-- LE stun mechanics
	MinStunChanceNeeded = 20,
	StunBaseMult = 200,
	StunBaseDuration = 0.4, -- LE stun base duration (0.4s)
	-- Corruption (Monolith) scaling: C<=100: 0.6*C%, C>100: 0.002*C^1.52 + 1.055*C - 47.69295%
	CorruptionBreakpoint = 100,
	CorruptionLinearRate = 0.6,
	CorruptionPowerCoeff = 0.002,
	CorruptionPower = 1.52,
	CorruptionLinearCoeff = 1.055,
	CorruptionConstant = -47.69295,
	StunMeleeDamageMult = 3, -- LE: player melee damage 3x for stun calc
	StunOtherDamageMult = 2, -- LE: other player damage 2x for stun calc
	StunNotMeleeDamageMult = 0.75,
	StunBossHealthMult = 1.5, -- LE: bosses treat HP as 50% higher for stun/freeze
	-- LE freeze mechanics
	FreezeDurationBase = 1.2, -- seconds
	FreezeBossHealthMult = 1.5, -- bosses treat HP as 50% higher for freeze
	-- LE defense caps
	EnduranceCap = 60, -- LE endurance cap (60% less damage taken)
	ParryCap = 75, -- LE parry chance cap (75%)
	GlancingBlowReduction = 35, -- LE glancing blow reduces hit damage by 35%
	ArmorCap = 85, -- LE armor mitigation cap (85%)
	BlockEffectivenessCap = 85, -- LE block effectiveness cap (85%)
	-- LE leech mechanics
	LeechDuration = 3, -- LE: health from leech granted over 3 seconds
	-- LE mana-before-health
	ManaShieldsHealthRatio = 5, -- LE: 1 mana shields 5 health
	-- LE enemy scaling
	EnemyPenPerLevel = 1, -- All enemies gain 1% pen per area level
	EnemyPenCap = 75, -- max 75% enemy pen
	MaxEnemyLevel = 100,
	maxExperiencePenaltyFreeAreaLevel = 70,
	experiencePenaltyMultiplier = 0.06,
	-- Expected values to calculate EHP
	stdBossDPSMult = 4 / 4.40,
	pinnacleBossDPSMult = 8 / 4.40,
	pinnacleBossPen = 15 / 5,
	uberBossDPSMult = 10 / 4.25,
	uberBossPen = 40 / 5,
	-- ehp helper function magic numbers
	ehpCalcSpeedUp = 8,
	-- max damage can be increased for more accuracy
	ehpCalcMaxDamage = 100000000,
	-- max iterations can be increased for more accuracy this should be perfectly accurate unless it runs out of iterations and so high eHP values will be underestimated.
	ehpCalcMaxIterationsToCalc = 50,
	-- maximum increase for stat weights, only used in trader for now.
	maxStatIncrease = 2, -- 100% increased
}

data.skillColorMap = { colorCodes.STRENGTH, colorCodes.DEXTERITY, colorCodes.INTELLIGENCE, colorCodes.NORMAL }

-- LE damaging ailments (from support.lastepoch.com)
data.ailmentTypeList = { "Ignite", "Bleed", "Poison", "Frostbite", "Electrify", "Damned", "TimeRot", "Doom" }
data.elementalAilmentTypeList = { "Ignite", "Frostbite", "Electrify" }
data.nonDamagingAilmentTypeList = { "Chill", "Shock", "Slow", "Blind", "Frailty" }
data.nonElementalAilmentTypeList = { "Bleed", "Poison", "Damned", "TimeRot", "Doom" }

-- LE damaging ailment definitions
data.damagingAilment = {
	["Bleed"]     = { associatedType = "Physical", baseDamage = 53,  duration = 3,   maxStacks = nil, penType = "Physical" },
	["Ignite"]    = { associatedType = "Fire",     baseDamage = 40,  duration = 2.5, maxStacks = nil, penType = "Fire" },
	["Poison"]    = { associatedType = "Poison",   baseDamage = 28,  duration = 3,   maxStacks = nil, penType = "Poison",
		resistShred = { first30 = true, perStack = 5 }, lessVsPlayers = 60, lessVsBosses = 60 },
	["Frostbite"] = { associatedType = "Cold",     baseDamage = 50,  duration = 3,   maxStacks = nil, penType = "Cold",
		freezeChancePerStack = 20, maxFreezeStacks = 15 },
	["Electrify"] = { associatedType = "Lightning", baseDamage = 44, duration = 2.5, maxStacks = nil, penType = "Lightning" },
	["Damned"]    = { associatedType = "Necrotic", baseDamage = 35,  duration = 2.5, maxStacks = nil, penType = "Necrotic",
		reducedHealthRegen = 20 },
	["TimeRot"]   = { associatedType = "Void",     baseDamage = 60,  duration = 3,   maxStacks = 12,  penType = "Void",
		incStunDuration = 5 },
	["Doom"]      = { associatedType = "Void",     baseDamage = 400, duration = 4,   maxStacks = 4,   penType = "Void",
		incMeleeDamageTaken = 4 },
	["Plague"]    = { associatedType = "Poison",  baseDamage = 150, duration = 4,   maxStacks = 1,   penType = "Poison",
		spreads = { range = 6, delay = 0.6, maxTargets = nil, spreadsOnDeath = true } },
	["Witchfire"] = { associatedType = { "Fire", "Necrotic" }, baseDamage = { Fire = 600, Necrotic = 600 },
		duration = 12, maxStacks = 1, penType = { "Fire", "Necrotic" }, dualType = true },
	["SpreadingFlames"] = { associatedType = "Fire", baseDamage = 200, duration = 4, maxStacks = 1, penType = "Fire",
		spreads = { range = 5, delay = 0.6, maxTargets = nil } },
	["FutureStrike"] = { associatedType = "Void", baseDamage = 60, duration = 3, maxStacks = nil, penType = "Void",
		dealsAllDamageAtEnd = true },
	["AbyssalDecay"] = { associatedType = "Void", baseDamage = 100, duration = 5, maxStacks = 1, penType = "Void",
		appliesRemainingOnHit = true },
	["AbyssalDecayStacking"] = { associatedType = "Void", baseDamage = 30, duration = 3, maxStacks = nil, penType = "Void",
		appliesRemainingOnHit = true },
	["SpiritPlague"] = { associatedType = "Necrotic", baseDamage = 90, duration = 3, maxStacks = 1, penType = "Necrotic",
		isCurse = true, spreads = { range = 9, maxTargets = 1, spreadsOnDeath = true } },
	-- Curses (player-applied)
	["BoneCurse"]  = { associatedType = "Physical", baseDamage = 4, duration = 8, maxStacks = 1, penType = "Physical",
		isCurse = true, takesSpellPhysDmgWhenHit = true },
	["NecroticBoneCurse"] = { associatedType = "Necrotic", baseDamage = 4, duration = 8, maxStacks = 1, penType = "Necrotic",
		isCurse = true, takesSpellPhysDmgWhenHit = true },
	["Torment"]    = { associatedType = "Necrotic", baseDamage = 120, duration = 3, maxStacks = 1, penType = "Necrotic",
		isCurse = true, lessMoveSpeed = 18 },
	["Decrepify"]  = { associatedType = "Physical", baseDamage = 200, duration = 10, maxStacks = 1, penType = "Physical",
		isCurse = true, moreDoTTaken = 15 },
	["Anguish"]    = { associatedType = "Necrotic", baseDamage = 40, duration = 10, maxStacks = 1, penType = "Necrotic",
		isCurse = true, lessDoT = 15 },
	["Penance"]    = { associatedType = "Fire", baseDamage = 20, duration = 15, maxStacks = 1, penType = "Fire",
		isCurse = true, fireOnHitCooldown = 0.35 },
	["AcidSkin"]   = { associatedType = "Poison", baseDamage = 80, duration = 5, maxStacks = 1, penType = "Poison",
		isCurse = true, incCritReceived = 20 },
	-- Skill-specific damaging ailments
	["SerpentVenom"]  = { associatedType = "Poison", baseDamage = 400, duration = 3, maxStacks = 1, penType = "Poison" },
	["Hemorrhage"]    = { associatedType = "Physical", baseDamage = 300, duration = 3, maxStacks = nil, penType = "Physical" },
	["Ravage"]        = { associatedType = "Void", baseDamage = 135, duration = 6, maxStacks = 1, penType = "Void" },
	["Laceration"]    = { associatedType = "Physical", baseDamage = 1, duration = 3, maxStacks = 1, penType = "Physical" },
	["SnakeInfection"]= { associatedType = "Poison", baseDamage = 300, duration = 12, maxStacks = 1, penType = "Poison" },
	["Chained"]       = { associatedType = "Necrotic", baseDamage = 40, duration = 2, maxStacks = 1, penType = "Necrotic" },
	["Pestilence"]    = { associatedType = "Poison", baseDamage = 30, duration = 0.5, maxStacks = 2, penType = "Poison" },
	-- Brand ailments (Falcon skills)
	["BrandOfDeception"]   = { associatedType = "Lightning", baseDamage = 400, duration = 3, maxStacks = 1, penType = "Lightning" },
	["BrandOfSubjugation"] = { associatedType = "Cold", baseDamage = 400, duration = 3, maxStacks = 1, penType = "Cold" },
	["BrandOfTrespass"]    = { associatedType = "Fire", baseDamage = 400, duration = 3, maxStacks = 1, penType = "Fire" },
}

-- LE non-damaging ailment definitions
data.nonDamagingAilment = {
	["Chill"]    = { associatedType = "Cold",      duration = 4, maxStacks = 3,
		effects = { lessAttackSpeed = 12, lessCastSpeed = 12, lessMoveSpeed = 12 }, lessVsPlayers = 50, lessVsBosses = 50 },
	["Shock"]    = { associatedType = "Lightning", duration = 4, maxStacks = 10,
		effects = { incStunChance = 20, negLightningRes = 5 }, lessVsPlayers = 60, lessVsBosses = 60 },
	["Slow"]     = { associatedType = nil,         duration = 4, maxStacks = 3,
		effects = { lessMoveSpeed = 20 }, lessVsPlayers = 50, lessVsBosses = 50 },
	["Blind"]    = { associatedType = nil,         duration = 4, maxStacks = 1,
		effects = { lessCritChance = 100 } },
	["Frailty"]  = { associatedType = nil,         duration = 4, maxStacks = 3,
		effects = { lessDamage = 6 } },
	["Freeze"]   = { associatedType = "Cold",      duration = 1.2, maxStacks = 1 },
	["CriticalVulnerability"] = { associatedType = nil, duration = 4, maxStacks = 10,
		effects = { incCritReceived = 2, negCritAvoidance = 10 } },
	["MarkedForDeath"] = { associatedType = nil, duration = 8, maxStacks = 1,
		effects = { negAllResistances = 25 } },
	["Stagger"]  = { associatedType = nil,         duration = 10, maxStacks = 1,
		effects = { negArmor = 100, incDamageTaken = 10 } },
	["ExposedFlesh"] = { associatedType = "Cold",  duration = 8, maxStacks = 1,
		effects = { negColdRes = 15, incFreezeChance = 30 } },
}

-- LE resistance shred ailments
data.resistShredAilment = {
	["ShredArmor"]          = { duration = 4, maxStacks = nil, perStack = 100, stat = "Armor",            lessVsPlayers = 0,  lessVsBosses = 0 },
	["ShredPhysicalRes"]    = { duration = 4, maxStacks = 10,  perStack = 5,   stat = "PhysicalResist",   lessVsPlayers = 60, lessVsBosses = 60 },
	["ShredFireRes"]        = { duration = 4, maxStacks = 10,  perStack = 5,   stat = "FireResist",       lessVsPlayers = 60, lessVsBosses = 60 },
	["ShredColdRes"]        = { duration = 4, maxStacks = 10,  perStack = 5,   stat = "ColdResist",       lessVsPlayers = 60, lessVsBosses = 60 },
	["ShredLightningRes"]   = { duration = 4, maxStacks = 10,  perStack = 5,   stat = "LightningResist",  lessVsPlayers = 60, lessVsBosses = 60 },
	["ShredNecroticRes"]    = { duration = 4, maxStacks = 10,  perStack = 5,   stat = "NecroticResist",   lessVsPlayers = 60, lessVsBosses = 60 },
	["ShredPoisonRes"]      = { duration = 4, maxStacks = 10,  perStack = 5,   stat = "PoisonResist",     lessVsPlayers = 60, lessVsBosses = 60 },
	["ShredVoidRes"]        = { duration = 4, maxStacks = 10,  perStack = 5,   stat = "VoidResist",       lessVsPlayers = 60, lessVsBosses = 60 },
}

-- Used in ModStoreClass:ScaleAddMod(...) to identify high precision modifiers
data.defaultHighPrecision = 1
data.highPrecisionMods = {
	["CritChance"] = {
		["BASE"] = 2,
	},
	["SelfCritChance"] = {
		["BASE"] = 2,
	},
	["LifeRegenPercent"] = {
		["BASE"] = 2,
	},
	["ManaRegenPercent"] = {
		["BASE"] = 2,
	},
	["LifeRegen"] = {
		["BASE"] = 1,
	},
	["ManaRegen"] = {
		["BASE"] = 1,
	},
	["LifeDegenPercent"] = {
		["BASE"] = 2,
	},
	["ManaDegenPercent"] = {
		["BASE"] = 2,
	},
	["LifeDegen"] = {
		["BASE"] = 1,
	},
	["ManaDegen"] = {
		["BASE"] = 1,
	},
	["DamageLifeLeech"] = {
		["BASE"] = 2,
	},
	["PhysicalDamageLifeLeech"] = {
		["BASE"] = 2,
	},
	["ElementalDamageLifeLeech"] = {
		["BASE"] = 2,
	},
	["FireDamageLifeLeech"] = {
		["BASE"] = 2,
	},
	["ColdDamageLifeLeech"] = {
		["BASE"] = 2,
	},
	["LightningDamageLifeLeech"] = {
		["BASE"] = 2,
	},
	["ChaosDamageLifeLeech"] = {
		["BASE"] = 2,
	},
	["DamageManaLeech"] = {
		["BASE"] = 2,
	},
	["PhysicalDamageManaLeech"] = {
		["BASE"] = 2,
	},
	["ElementalDamageManaLeech"] = {
		["BASE"] = 2,
	},
	["FireDamageManaLeech"] = {
		["BASE"] = 2,
	},
	["ColdDamageManaLeech"] = {
		["BASE"] = 2,
	},
	["LightningDamageManaLeech"] = {
		["BASE"] = 2,
	},
	["ChaosDamageManaLeech"] = {
		["BASE"] = 2,
	},
	["SupportManaMultiplier"] = {
		["MORE"] = 4,
	},
	-- @leb-regression-guard:resist-base-high-precision
	-- ScaleAddMod (ModStore.lua) calls m_modf on the scaled value when no
	-- precision is registered, truncating fractional parts. Buff-tree skill
	-- node mods like Holy Aura ah443-0 ("+15% Cold Resistance") get scaled by
	-- HolyAuraEffect (e.g. Sentinel-119 Covenant of Light: +4%/pt) via
	-- CalcSetup.lua applyBuffPrefix → ScaleAddList. Without precision=1,
	-- 15 * 1.04 = 15.6 truncates to 15, producing per-resist Δ=-0.6 vs LE.
	-- <private build> Cold pre-fix: LEB BASE=96.8 → output 97; LE total 97.6 → 98.
	-- Spec: spec/System/TestResistBaseHighPrecision_spec.lua
	-- Note: stat names are the LEB-internal short forms ("ColdResist", not
	-- "ColdResistance") used by ModParser ("all resistances" → 7 short names)
	-- and modDB:Sum keys. Elemental Resistance fans out to Fire/Cold/Lightning
	-- on parse, so no separate "ElementalResist" key is needed.
	["FireResist"]      = { ["BASE"] = 1 },
	["ColdResist"]      = { ["BASE"] = 1 },
	["LightningResist"] = { ["BASE"] = 1 },
	["NecroticResist"]  = { ["BASE"] = 1 },
	["PoisonResist"]    = { ["BASE"] = 1 },
	["VoidResist"]      = { ["BASE"] = 1 },
	["PhysicalResist"]  = { ["BASE"] = 1 },
}

data.weaponTypeInfo = {
	["None"] = { oneHand = true, melee = true, flag = "Unarmed" },
	["Bow"] = { oneHand = false, melee = false, flag = "Bow" },
	["Dagger"] = { oneHand = true, melee = true, flag = "Dagger" },
	["Two-Handed Staff"] = { oneHand = false, melee = true, flag = "Staff" },
	["Wand"] = { oneHand = true, melee = false, flag = "Wand" },
	["One-Handed Axe"] = { oneHand = true, melee = true, flag = "Axe" },
	["One-Handed Mace"] = { oneHand = true, melee = true, flag = "Mace" },
	["One-Handed Sword"] = { oneHand = true, melee = true, flag = "Sword" },
	-- @leb-regression-guard:sceptre-not-mace
	-- Validation provenance is retained in maintainer notes.
	["Sceptre"] = { oneHand = true, melee = true, flag = "Sceptre", label = "Sceptre" },
	["Two-Handed Axe"] = { oneHand = false, melee = true, flag = "Axe" },
	["Two-Handed Mace"] = { oneHand = false, melee = true, flag = "Mace" },
	["Two-Handed Sword"] = { oneHand = false, melee = true, flag = "Sword" },
	["Two-Handed Spear"] = { oneHand = false, melee = true, flag = "Spear" },
}
data.unarmedWeaponData = {
	[0] = { type = "None", AttackRate = 1.2, CritChance = 0, PhysicalMin = 2, PhysicalMax = 6 }, -- Scion
	[1] = { type = "None", AttackRate = 1.2, CritChance = 0, PhysicalMin = 2, PhysicalMax = 8 }, -- Marauder
	[2] = { type = "None", AttackRate = 1.2, CritChance = 0, PhysicalMin = 2, PhysicalMax = 5 }, -- Ranger
	[3] = { type = "None", AttackRate = 1.2, CritChance = 0, PhysicalMin = 2, PhysicalMax = 5 }, -- Witch
	[4] = { type = "None", AttackRate = 1.2, CritChance = 0, PhysicalMin = 2, PhysicalMax = 6 }, -- Duelist
	[5] = { type = "None", AttackRate = 1.2, CritChance = 0, PhysicalMin = 2, PhysicalMax = 6 }, -- Templar
	[6] = { type = "None", AttackRate = 1.2, CritChance = 0, PhysicalMin = 2, PhysicalMax = 5 }, -- Shadow
}


data.enchantmentSource = {
	{ name = "ENKINDLING", label = "Enkindling Orb" },
	{ name = "INSTILLING", label = "Instilling Orb" },
	{ name = "HEIST", label = "Heist" },
	{ name = "HARVEST", label = "Harvest" },
	{ name = "DEDICATION", label = "Dedication to the Goddess" },
	{ name = "ENDGAME", label = "Eternal Labyrinth" },
	{ name = "MERCILESS", label = "Merciless Labyrinth" },
	{ name = "CRUEL", label = "Cruel Labyrinth" },
	{ name = "NORMAL", label = "Normal Labyrinth" },
}

-- Misc data tables
LoadModule("Data/Misc", data)

-- Stat descriptions
data.describeStats = LoadModule("Modules/StatDescriber")

-- Load item modifiers
data.itemMods = {
	Item = readJsonFile("Data/ModItem.json"),
}

for _,mod in pairs(data.itemMods.Item) do
	if not mod.affix then
		mod.affix = ""
	end
	if not mod.affixName then
		mod.affixName = ""
	end
	if not mod.modName then
		mod.modName = ""
	end
end

data.costs = LoadModule("Data/Costs")
do
	local map = { }
	for i, value in ipairs(data.costs) do
		map[value.Resource] = i
	end
	setmetatable(data.costs, { __index = function(t, k) return t[map[k]] end })
end

-- Manually seeded modifier tag against item slot table for Mastery Item Condition based modifiers
-- Data is informed by getTagBasedModifiers() located in Item.lua
data.itemTagSpecial = {
	["life"] = {
		["body armour"] = {
			-- Keystone
			"Blood Magic",
			"Eternal Youth",
			"Ghost Reaver",
			"Mind Over Matter",
			"The Agnostic",
			"Vaal Pact",
			"Zealot's Oath",
			-- Special Cases
			"^Cannot Leech$",
		},
	},
	["evasion"] = {
		["ring"] = {
			-- Delve
			"chance to Evade",
			-- Unique
			"Cannot Evade",
		},
	},
}
data.itemTagSpecialExclusionPattern = {
	["life"] = {
		["body armour"] = {
			"increased Damage while Leeching Life",
			"Life as Physical Damage",
			"maximum Life as Fire Damage",
			"when on Full Life",
			"Enemy's life",
			"Life From You",
			"^Socketed Gems are Supported by Level"
		},
		["boots"] = {
			"Enemy's Life", -- Legacy of Fury
		},
		["belt"] = {
		},
		["helmet"] = {
			"Recouped as Life", -- Flame Exarch
			"Life when you Suppress", -- Elevore
		},
	},
	["evasion"] = {
		["ring"] = {
		},
	},
}

-- Load bosses (Last Epoch)
-- Categories: "Empowered Monolith Boss", "Dungeon Boss", "Pinnacle Boss", "Uber Boss"
-- Stats are medians within each category (The Mountain Beneath excluded from Dungeon Boss).
-- Ward: wardPct% of health for most bosses; Aberroth/Herald use flat ward values.
do
	data.bosses = { }
	LoadModule("Data/Bosses", data.bosses)

	local cats = {
		"Empowered Monolith Boss",
		"Dungeon Boss",
		"Pinnacle Boss",
		"Uber Boss",
	}
	local totals = { }
	for _, cat in ipairs(cats) do
		totals[cat] = { health = 0, ward = 0, damageMod = 0, count = 0 }
	end

	for _, boss in pairs(data.bosses) do
		local t = totals[boss.category]
		if t and boss.health and boss.health > 0 then
			local w = (boss.wardPct and boss.wardPct > 0)
				and m_floor(boss.health * boss.wardPct / 100)
				or (boss.ward or 0)
			t.health    = t.health    + boss.health
			t.ward      = t.ward      + w
			t.damageMod = t.damageMod + (boss.damageMod or 0)
			t.count     = t.count     + 1
		end
	end

	data.bossStats = { }
	for _, cat in ipairs(cats) do
		local t = totals[cat]
		local n = m_max(t.count, 1)
		data.bossStats[cat] = {
			healthMean    = m_floor(t.health    / n),
			wardMean      = m_floor(t.ward      / n),
			damageModMean = t.damageMod / n,
			count         = t.count,
		}
	end

	local function bossLine(cat)
		local s = data.bossStats[cat]
		if not s or s.count == 0 then return cat .. ": (no data)" end
		local line = cat .. "  HP=" .. s.healthMean
		if s.wardMean > 0 then line = line .. "  Ward=" .. s.wardMean end
		line = line .. "  MoreDmg=" .. m_floor(s.damageModMean) .. "%"
		line = line .. "  (n=" .. s.count .. ")"
		return line
	end
	data.enemyIsBossTooltip =
		"Boss category averages (health / ward / More Damage %)\n" ..
		"Source: lastepoch.tunklab.com v1.3 | Empowered lv100 0-Corruption | Dungeon Tier4 base\n\n" ..
		bossLine("Empowered Monolith Boss") .. "\n" ..
		bossLine("Dungeon Boss")            .. "\n" ..
		bossLine("Pinnacle Boss")           .. "\n" ..
		bossLine("Uber Boss")
end

-- Load skills
data.skills = readJsonFile("Data/skills.json")
data.skillStatMap = LoadModule("Data/SkillStatMap", makeSkillMod, makeFlagMod, makeSkillDataMod)
-- Sub-skill grant registry: parent skill -> sub-skills its base kit grants
-- (consumed by the CalcSetup grantedSubSkills loop; see file header).
data.subSkillGrants = LoadModule("Data/SubSkillGrants")
-- Auto-summon registry: a per-player COUNT stat (granted by an item/affix/
-- passive, not a slotted skill) -> the existing summon skill it auto-casts
-- (consumed by the CalcSetup grantedAutoSummons loop; see file header).
data.autoSummons = LoadModule("Data/AutoSummons")

-- ActorScaler monster level-scaling damage curve, applied to repurposed-monster
-- minions (minionData.monsterScaling present) in place of the companion level MORE.
data.monsterDamageScaling = LoadModule("Data/MonsterDamageScaling")

-- Empirically-measured per-skill firing cadence (hits/s) for multi-skill minions,
-- keyed by minion name -> grantedEffect.id. Consumed by calcs.calcFullDPS ONLY when
-- the default-OFF `minionMultiSkillCadenceFold` config is enabled, to fold secondary
-- minion skills into the FullDPS headline. See the file header for provenance.
data.minionSkillCadence = LoadModule("Data/MinionSkillCadence")

-- Accuracy honesty status: grantedEffect.name -> "approximate"|"unverified".
-- Display-ONLY static reference data (the release-board meta-43 accuracy map,
-- generated by scripts/gen_skill_accuracy_status.py). Consumed solely by the
-- SkillsTab honesty badge (SkillsTab:GetSkillAccuracyBadge); it never enters
-- modList / calcsTab.mainOutput, so corpus snapshots are byte-identical.
-- @leb-regression-guard:ui-accuracy-honesty-badge
data.skillAccuracyStatus = LoadModule("Data/SkillAccuracyStatus")

-- Add a default skill
data.skills["Default"] = {
	name = "Default",
	skillTypeTags = 0,
	baseFlags = {},
	stats = {}
}

-- @leb-regression-guard:ailment-pen-family-fixup (spaced-name map)
-- Spaced ailment DISPLAY name -> data.damagingAilment key (e.g. "Time Rot" ->
-- "TimeRot"). skills.json names its Ailment_* pseudo-skill entries with the spaced
-- display name while data.damagingAilment keys are space-stripped, so SkillName
-- tags / granted-effect names carrying a spaced name never matched the allowlist.
-- A name maps IFF (1) stripping spaces yields a damagingAilment key AND (2) no
-- PLAYER skill owns that display name -- data.skills[id].treeId is set only on
-- player-usable skills (the same data-driven signal as the ModParser
-- skillidbylower-prefer-player guard). The only two real collisions (census
-- 2026-06-11), "Bone Curse" (skill id BoneCurse) and "Spirit Plague" (skill id
-- SpiritPlague), are therefore EXCLUDED: "with Bone Curse" on a pen mod
-- legitimately means the Acolyte SKILL scope, not the BoneCurse ailment.
-- Consumed by the ModParser ailment-pen-family fixup chokepoint and the
-- CalcOffence pseudo-skill site. See REGRESSION_GUARDS.md "ailment-pen-family-fixup".
data.damagingAilmentSpacedName = {}
do
	local playerSkillName = {}
	for _, skill in pairs(data.skills) do
		if skill.name and skill.treeId then
			playerSkillName[skill.name] = true
		end
	end
	for _, skill in pairs(data.skills) do
		local name = skill.name
		if name and name:find(" ", 1, true) then
			local stripped = name:gsub("%s+", "")
			if data.damagingAilment[stripped] and not playerSkillName[name] then
				data.damagingAilmentSpacedName[name] = stripped
			end
		end
	end
end

-- Load minions
data.minions = readJsonFile("Data/minions.json")

data.LETools_itemBases = readJsonFile("Data/LEToolsImport/bases.json") or {}
data.LETools_affixes = readJsonFile("Data/LEToolsImport/affixes.json") or {}

-- Helper: build itemBaseLists and itemBaseTypeList from a bases table
local function buildItemBaseLists(itemBases)
	local lists = { }
	for name, base in pairs(itemBases) do
		if not base.hidden then
			local bType = base.type
			if base.subType then
				bType = bType .. ": " .. base.subType
			end
			lists[bType] = lists[bType] or { }
			table.insert(lists[bType], { label = name:gsub(" %(.+%)",""), name = name, base = base })
		end
	end
	local typeList = { }
	for bType, list in pairs(lists) do
		table.insert(typeList, bType)
		table.sort(list, function(a, b)
			if a.base.req and b.base.req then
				if a.base.req.level == b.base.req.level then
					return a.name < b.name
				else
					return (a.base.req.level or 1) > (b.base.req.level or 1)
				end
			elseif a.base.req and not b.base.req then
				return true
			elseif b.base.req and not a.base.req then
				return false
			else
				return a.name < b.name
			end
		end)
	end
	table.sort(typeList)
	return lists, typeList
end

-- Load data for each supported game version
-- Each version has a dedicated file: Data/ModItem_1_3.json, Data/Bases/bases_1_3.json, etc.
data.versionData = { }
for _, ver in ipairs(treeVersionList) do
	local verMods          = readJsonFile("Data/ModItem_" .. ver .. ".json")
	local verAltarMods     = readJsonFile("Data/ModItem_IdolAltar_" .. ver .. ".json")
	local verBasesRaw = io.open("Data/Bases/bases_" .. ver .. ".json", "r")
	local verBasesContent = verBasesRaw and verBasesRaw:read("*a") or ""
	if verBasesRaw then verBasesRaw:close() end
	local verBases, basesErr = processJson(verBasesContent)
	if basesErr then
		ConPrintf("bases_%s.json parse error: %s", ver, tostring(basesErr))
	end
	local verUniques     = readJsonFile("Data/Uniques/uniques_" .. ver .. ".json")
	local verIdolMods    = readJsonFile("Data/ModIdol_" .. ver .. ".json")
	local verWWMods      = readJsonFile("Data/ModItemWW_" .. ver .. ".json")
	-- Safety fallback: if a version-specific file is missing, use the base files
	if not verMods    then verMods    = readJsonFile("Data/ModItem.json")         end
	if not verBases   then verBases   = readJsonFile("Data/Bases/bases.json")     end
	if not verUniques then verUniques = readJsonFile("Data/Uniques/uniques.json") end
	-- Merge set_<ver>.json entries (set-rarity items) into verUniques by uniqueID,
	-- so import paths that look up data.uniques[uniqueID] still find them after
	-- the unique-side duplicates are removed.
	local verSets = readJsonFile("Data/Set/set_" .. ver .. ".json")
		or readJsonFile("Data/Set/set_1_4.json")
	if verSets and verUniques then
		for _, s in pairs(verSets) do
			if type(s) == "table" and s.uniqueID then
				-- readJsonFile/jsonToLua converts numeric JSON string keys to
				-- Lua integer keys, so verUniques is INT-keyed and parseItem
				-- looks up via the INT form (data.uniques[uniqueID]).
				-- Store under both forms to be safe across call sites that
				-- pass either a number or a string for uniqueID.
				local idInt = tonumber(s.uniqueID)
				local idStr = tostring(s.uniqueID)
				if idInt and not verUniques[idInt] then
					verUniques[idInt] = s
				end
				if not verUniques[idStr] then
					verUniques[idStr] = s
				end
			end
		end
	end
	-- Ensure all affix entries have an affix name
	if verMods then
		for _, mod in pairs(verMods) do
			if not mod.affix then mod.affix = "" end
			if not mod.affixName then mod.affixName = "" end
			if not mod.modName then mod.modName = "" end
		end
	end
	-- Build flat lookup for idol affixes (merged general/enchanted/corrupted/weaver).
	-- Tag each entry with `specialAffixType` based on its source section so the
	-- Idol Altar refracted-slot boost can apply the correct boost type per LE's
	-- `AffixList.SpecialAffixType` enum (Standard=0, IdolEnchantment=4, IdolWeaver=5,
	-- Corrupted=6). See: datamined game source and the
	-- `IsAffectedByAffectOfStandardPrefixesOrSuffixes` extension method which
	-- gates standard P/S effect boosts on Standard-typed affixes only.
	-- @leb-regression-guard:idol-special-affix-type-is-integer
	-- These MUST be the raw LE enum integers, matching ModItem_<ver>.json. They were
	-- historically strings ("Standard"/"IdolEnchantment"/...), which silently broke
	-- every integer comparison against an idol affix — and every consumer except
	-- CalcSetup compares integers. `mod.specialAffixType == 6` was therefore ALWAYS
	-- FALSE for a tier-0 idol affix, since Lua does not coerce "Corrupted" == 6.
	--
	-- Worse, it was tier-dependent: ModIdol_<ver>.json stores only `_0` entries and
	-- `flat` chains to ModItem via __index (see idol-affix-tier-fallback below), so the
	-- SAME affix family was a string at tier 0 and an integer at tier 1+. That bit for
	-- real once — CalcSetup's comment records affix 897_4 skipping the +46%
	-- weaver-enchant refracted-slot boost because the tier entry's numeric 4 missed the
	-- string test.
	--
	-- The mapping is lossless: all 469 ModIdol entries were verified (2026-07-16) to
	-- agree exactly with ModItem's integer for their section (0 mismatches), and no
	-- ModIdol entry carries a specialAffixType key of its own.
	-- Spec: spec/System/TestIdolSpecialAffixTypeInteger_spec.lua
	if verIdolMods then
		local sectionToSpecial = {
			general   = 0,  -- AffixList.SpecialAffixType.Standard
			enchanted = 4,  -- .IdolEnchantment
			corrupted = 6,  -- .Corrupted
			weaver    = 5,  -- .IdolWeaver
		}
		local flat = {}
		for sectionName, entries in pairs(verIdolMods) do
			if type(entries) == "table" then
				local specialTag = sectionToSpecial[sectionName]
				for k, v in pairs(entries) do
					if type(v) == "table" then
						if specialTag and not v.specialAffixType then
							v.specialAffixType = specialTag
						end
						flat[k] = v
					end
				end
			end
		end
		-- @leb-regression-guard:idol-affix-tier-fallback
		-- ModIdol_<ver>.json currently stores only tier 0 (`_0`) for every
		-- affix. Idols can roll higher tiers (enchanted T1..T7, etc.); without
		-- fallback those lookups return nil and the affix contributes zero.
		-- Chain `flat` to ModItem so a missed tier-N idol lookup transparently
		-- resolves to the ModItem entry (which carries the per-tier raw scaling).
		-- Idol-specific corrections (e.g. 1070_0 All Resistances ModIdol +5%
		-- vs ModItem +1%) still take precedence because `flat` is consulted
		-- first. See REGRESSION_GUARDS.md "idol-affix-tier-fallback".
		setmetatable(flat, { __index = verMods })
		verIdolMods.flat = flat
	end
	local verBaseLists, verBaseTypeList = buildItemBaseLists(verBases or {})
	-- @leb-regression-guard:idol-affix-source-and-formula
	-- Idol affix entries live in ModIdol_<ver>.json (not ModItem). Register every
	-- idol base type to point at verIdolMods.flat so Item.lua's affix lookup
	-- (self.base.type → data.itemMods[type]) resolves to idol affix data rather
	-- than falling back to data.itemMods.Item (the body-armor/weapon table) where
	-- shared affix IDs have different raw values. e.g. affix 1070_0 All Resistances:
	-- ModItem raw "+1%" (legacy/wrong); ModIdol raw "+5%" (correct, matches LE).
	-- See REGRESSION_GUARDS.md "idol-affix-source-and-formula".
	local idolFlat = verIdolMods and verIdolMods.flat or nil
	local itemModsTable = { Item = verMods or {}, ["Idol Altar"] = verAltarMods or {} }
	if idolFlat then
		for _, idolType in ipairs({
			"Small Idol", "Minor Idol", "Humble Idol", "Stout Idol",
			"Grand Idol", "Large Idol", "Adorned Idol", "Ornate Idol", "Huge Idol",
		}) do
			itemModsTable[idolType] = idolFlat
		end
	end
	data.versionData[ver] = {
		itemMods         = itemModsTable,
		itemBases        = verBases   or {},
		itemBaseLists    = verBaseLists,
		itemBaseTypeList = verBaseTypeList,
		uniques          = verUniques or {},
		idolMods         = verIdolMods or {},
		wwMods           = verWWMods or {},
	}
end

-- Switch all global data pointers to the specified game version.
-- Called from Build.lua when a build is opened.
function data.setActiveVersion(version)
	local vd = data.versionData[version] or data.versionData[latestTreeVersion]
	data.itemBaseLists   = vd.itemBaseLists
	data.itemBaseTypeList = vd.itemBaseTypeList
	data.uniques         = vd.uniques
	-- @leb-regression-guard: weaver-will-equipped-autocount
	-- Build a name-keyed set of Weaver's Will uniques (legendaryType == 1 in
	-- the game data; exactly 18 uniques carry it). CalcSetup matches equipped
	-- items by title (LEB resolves uniques by name, not by the build-local
	-- "Unique ID" field) to auto-count Multiplier:EquippedWeaverItem. See
	-- REGRESSION_GUARDS.md "weaver-will-equipped-autocount".
	data.weaversWillUniques = {}
	for _, u in pairs(vd.uniques or {}) do
		if type(u) == "table" and u.legendaryType == 1 and u.name then
			data.weaversWillUniques[u.name] = true
		end
	end
	data.modIdol         = vd.idolMods or {}
	data.wwMods          = vd.wwMods or {}
	-- Use the requested version's itemBases/itemMods if non-empty,
	-- otherwise fall back to the newest version that parsed successfully.
	if next(vd.itemBases) then
		data.itemMods  = vd.itemMods
		data.itemBases = vd.itemBases
	else
		for i = #treeVersionList, 1, -1 do
			local fallback = data.versionData[treeVersionList[i]]
			if fallback and next(fallback.itemBases) then
				data.itemMods  = fallback.itemMods
				data.itemBases = fallback.itemBases
				break
			end
		end
	end
end

-- Initialise with the latest version
data.setActiveVersion(latestTreeVersion)

-- Rare templates
data.rares = {}

-- uniqueMods is populated at runtime
data.uniqueMods = { }
