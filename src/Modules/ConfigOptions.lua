-- Last Epoch Building
--
-- Module: Config Options
-- List of options for the Configuration tab.
--

local m_min = math.min
local m_max = math.max
local s_format = string.format

local function LowLifeTooltip(modList, build)
	local out = 'You will automatically be considered to be on Low ^xE05030Life ^7if you have at least '..100 - build.calcsTab.mainOutput.LowLifePercentage..'% ^xE05030Life ^7reserved'
	out = out..'\nbut you can use this option to force it if necessary.'
	return out
end

local function FullLifeTooltip(modList, build)
	local out = 'You can be considered to be on Full ^xE05030Life ^7if you have at least '..build.calcsTab.mainOutput.FullLifePercentage..'% ^xE05030Life ^7left.'
	out = out..'\nYou will automatically be considered to be on Full ^xE05030Life ^7if you have Chaos Inoculation,'
	out = out..'\nbut you can use this option to force it if necessary.'
	return out
end


local options = {
	-- Section: General options
	{ section = "General", col = 1 },
	{ var = "campaignBonuses", type = "check", label = "Campaign bonuses?", apply = function(val, modList, enemyModList)
		modList:NewMod("Str", "BASE", 1, "Quest")
		modList:NewMod("Dex", "BASE", 1, "Quest")
		modList:NewMod("Int", "BASE", 1, "Quest")
		modList:NewMod("Att", "BASE", 1, "Quest")
		modList:NewMod("Vit", "BASE", 1, "Quest")
	end },
	{ var = "conditionStationary", type = "count", label = "Time spent stationary", ifCond = "Stationary",
		tooltip = "Applies mods that use `while stationary` and `per / every second while stationary`",
		apply = function(val, modList, enemyModList)
		if type(val) == "boolean" then
			-- Backwards compatibility with older versions that set this condition as a boolean
			val = val and 1 or 0
		end
		local sanitizedValue = m_max(0, val)
		modList:NewMod("Multiplier:StationarySeconds", "BASE", sanitizedValue, "Config")
		if sanitizedValue > 0 then
			modList:NewMod("Condition:Stationary", "FLAG", true, "Config")
		end
	end },
	{ var = "conditionMoving", type = "check", label = "Are you always moving?", ifCond = "Moving", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Moving", "FLAG", true, "Config")
	end },
	{ var = "conditionFullLife", type = "check", label = "Are you always on Full ^xE05030Life?", ifCond = "FullLife", tooltip = FullLifeTooltip, apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:FullLife", "FLAG", true, "Config")
	end },
	{ var = "conditionLowLife", type = "check", label = "Are you always on Low ^xE05030Life?", ifCond = "LowLife", tooltip = LowLifeTooltip, apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:LowLife", "FLAG", true, "Config")
	end },
	{ var = "conditionFullMana", type = "check", label = "Are you always on Full ^x7070FFMana?", ifCond = "FullMana", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:FullMana", "FLAG", true, "Config")
	end },
	{ var = "conditionLowMana", type = "check", label = "Are you always on Low ^x7070FFMana?", ifCond = "LowMana", tooltip = "You will automatically be considered to be on Low ^x7070FFMana ^7if you have at least 50% ^x7070FFmana ^7reserved,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:LowMana", "FLAG", true, "Config")
	end },
	{ var = "minionsConditionFullLife", type = "check", label = "Are your Minions always on Full ^xE05030Life?", ifMinionCond = "FullLife", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Condition:FullLife", "FLAG", true, "Config") }, "Config")
	end },
	{ var = "minionsConditionCreatedRecently", type = "check", label = "Have your Minions been created Recently?", ifCond = "MinionsCreatedRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:MinionsCreatedRecently", "FLAG", true, "Config")
	end },
	{ var = "lifeRegenMode", type = "list", label = "^xE05030Life ^7regen calculation mode:", ifCond = { "LifeRegenBurstAvg", "LifeRegenBurstFull" }, tooltip = "Controls how ^xE05030life ^7regeneration is calculated:\n\tMinimum: does not include burst regen\n\tAverage: includes burst regen, averaged based on uptime\n\tBurst: includes full burst regen", list = {{val="MIN",label="Minimum"},{val="AVERAGE",label="Average"},{val="FULL",label="Burst"}}, apply = function(val, modList, enemyModList)
		if val == "AVERAGE" then
			modList:NewMod("Condition:LifeRegenBurstAvg", "FLAG", true, "Config")
		elseif val == "FULL" then
			modList:NewMod("Condition:LifeRegenBurstFull", "FLAG", true, "Config")
		end
	end },
	{ var = "resourceGainMode", type = "list", label = "Resource gain calculation mode:", ifCond = "AverageResourceGain", defaultIndex = 2, tooltip = "Controls how resource on hit/kill is calculated:\n\tMinimum: does not include chances\n\tAverage: includes chance gains, averaged based on uptime\n\tMaximum: treats all chances as certain", list = {{val="MIN",label="Minimum"},{val="AVERAGE",label="Average"},{val="MAX",label="Maximum"}}, apply = function(val, modList, enemyModList)
		if val == "AVERAGE" then
			modList:NewMod("Condition:AverageResourceGain", "FLAG", true, "Config")
		elseif val == "MAX" then
			modList:NewMod("Condition:MaxResourceGain", "FLAG", true, "Config")
		end
	end },
	{ var = "EHPUnluckyWorstOf", type = "list", label = "EHP calc unlucky:", tooltip = "Sets the EHP calc to pretend its unlucky and reduce the effects of random events", list = {{val=1,label="Average"},{val=2,label="Unlucky"},{val=4,label="Very Unlucky"}} },
	{ var = "DisableEHPGainOnBlock", type = "check", label = "Disable EHP gain on block:", ifMod = {"LifeOnBlock", "ManaOnBlock"}, tooltip = "Sets the EHP calc to not apply gain on block effects"},

	-- Section: Skill-specific options
	{ section = "Skill Options", col = 2 },

	{ label = "Player is cursed by:" },
	{ var = "conditionCursed", type = "check", label = "Are you Cursed?", tooltip = "Check if the player is Cursed (e.g. via Acolyte passives/skills).\nEnables 'while cursed' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Cursed", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionTransformed", type = "check", label = "Are you Transformed?", tooltip = "Check if the player is Transformed (Werebear, Spriggan Form, etc.).\nEnables 'while transformed' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Transformed", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHighHealth", type = "check", label = "Are you at High Health?", tooltip = "Check if you are at High Health (typically 50%+ of max health).\nEnables 'while at high health' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HighHealth", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHaveWard", type = "check", label = "Do you have Ward?", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveWard", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHaveLightningAegis", type = "check", label = "Do you have Lightning Aegis?", tooltip = "Check if you have the Lightning Aegis buff active (Runemaster).\nEnables 'while you have lightning aegis' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveLightningAegis", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionOnConsecratedGround", type = "check", label = "Are you on Consecrated Ground?", tooltip = "Check if you are standing on Consecrated Ground (Paladin).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:OnConsecratedGround", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHaveCompanion", type = "check", label = "Do you have a Companion?", tooltip = "Check if you have at least one Companion (Beastmaster/Falconer).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveCompanion", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierCompanion", type = "count", label = "# of Companions:", implyCond = "HaveCompanion", tooltip = "Number of active Companions. Also implies HaveCompanion condition.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:Companion", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveCompanion", "FLAG", val >= 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionFrenzy", type = "check", label = "Do you have Frenzy?", tooltip = "Check if you have Frenzy stacks (Beastmaster).\n20% increased Attack and Cast Speed.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Frenzy", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Speed", "INC", 20, "Frenzy")
	end },
	{ var = "conditionHaste", type = "check", label = "Do you have Haste?", tooltip = "30% increased Movement Speed for 4 seconds.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Haste", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("MovementSpeed", "INC", 30, "Haste")
	end },
	-- Overloads (Warlock)
	{ var = "conditionBleedOverload", type = "check", label = "Bleed Overload active?", tooltip = "Warlock: 15% more physical DoT vs bosses and moving enemies.\nRequires Cauldron of Blood (5pt).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BleedOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Multiplier:ActiveOverload", "BASE", 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionIgniteOverload", type = "check", label = "Ignite Overload active?", tooltip = "Warlock: 1% more fire damage to ignited enemies per 20% global ignite chance for fire skills.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:IgniteOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Multiplier:ActiveOverload", "BASE", 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionPoisonOverload", type = "check", label = "Poison Overload active?", tooltip = "Warlock: +4% Poison Penetration per stack of poison on the target, up to 100 stacks.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:PoisonOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Multiplier:ActiveOverload", "BASE", 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionDamnedOverload", type = "check", label = "Damned Overload active?", tooltip = "Warlock: 2% more damned damage per 1% missing health on you\nand 1% more damned damage per 2% missing health on target.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:DamnedOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Multiplier:ActiveOverload", "BASE", 1, "Config", { type = "Condition", var = "Combat" })
	end },
	-- Positive buff stacks
	{ var = "multiplierDuskShroudStacks", type = "count", label = "Dusk Shroud Stacks:", tooltip = "5% Glancing Blow chance and +50 Dodge Rating per stack.", apply = function(val, modList, enemyModList)
		modList:NewMod("GlancingBlowChance", "BASE", val * 5, "Dusk Shroud")
		modList:NewMod("Evasion", "BASE", val * 50, "Dusk Shroud")
	end },
	{ var = "multiplierVoidEssenceStacks", type = "count", label = "Void Essence Stacks:", tooltip = "3% more Void Damage, 3% more Melee Damage, 15% reduced stun duration per stack. Max 3.", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		modList:NewMod("VoidDamage", "MORE", val * 3, "Void Essence")
		modList:NewMod("Damage", "MORE", val * 3, "Void Essence", ModFlag.Melee)
	end },
	{ var = "multiplierContemptStacks", type = "count", label = "Contempt Stacks:", tooltip = "+10% All Resistances and 10% more Armor per stack. Max 5.", apply = function(val, modList, enemyModList)
		val = math.min(val, 5)
		for _, res in ipairs({"FireResist", "LightningResist", "ColdResist", "PhysicalResist", "PoisonResist", "NecroticResist", "VoidResist"}) do
			modList:NewMod(res, "BASE", val * 10, "Contempt")
		end
		modList:NewMod("Armour", "MORE", val * 10, "Contempt")
	end },
	{ var = "multiplierVoidBarrierStacks", type = "count", label = "Void Barrier Stacks:", tooltip = "5% less Damage Taken per stack. Max 6.", apply = function(val, modList, enemyModList)
		val = math.min(val, 6)
		modList:NewMod("DamageTaken", "MORE", -val * 5, "Void Barrier")
	end },
	{ var = "multiplierTotemArmorStacks", type = "count", label = "Totem Armor Stacks:", tooltip = "80% increased Armor and 15% more Damage per stack. Max 3.", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		modList:NewMod("Armour", "INC", val * 80, "Totem Armor")
		modList:NewMod("Damage", "MORE", val * 15, "Totem Armor")
	end },
	{ var = "multiplierMoltenInfusionStacks", type = "count", label = "Molten Infusion Stacks:", tooltip = "+15 Fire Melee Damage and +30% Ignite Chance per stack.", apply = function(val, modList, enemyModList)
		modList:NewMod("FireDamage", "BASE", val * 15, "Molten Infusion", ModFlag.Melee)
		modList:NewMod("IgniteChance", "BASE", val * 30, "Molten Infusion")
	end },
	{ var = "multiplierStormInfusionStacks", type = "count", label = "Storm Infusion Stacks:", tooltip = "+21 Lightning Spell/Melee/Bow/Throwing Damage per stack. Max 3.", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		modList:NewMod("LightningDamage", "BASE", val * 21, "Storm Infusion")
	end },
	{ var = "conditionDamageImmunity", type = "check", label = "Damage Immunity active?", tooltip = "100% less Damage Taken for 3 seconds.", apply = function(val, modList, enemyModList)
		modList:NewMod("DamageTaken", "MORE", -100, "Damage Immunity")
	end },
	-- Missing health for Damned Overload
	{ var = "playerMissingHealthPercent", type = "count", label = "Your Missing Health %:", tooltip = "Percentage of your maximum health that is missing.\nUsed for Damned Overload calculation (2% more damned per 1% missing).", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:MissingHealthPercent", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "enemyMissingHealthPercent", type = "count", label = "Enemy Missing Health %:", tooltip = "Percentage of the enemy's maximum health that is missing.\nUsed for Damned Overload calculation (1% more damned per 2% missing).", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:MissingHealthPercent", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierNearbyCorpses", type = "count", label = "# of Nearby Corpses:", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:NearbyCorpse", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionUsedPotionRecently", type = "check", label = "Used a Potion Recently?", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:UsedPotionRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierForgedWeapons", type = "count", label = "# of Forged Weapons:", implyCond = "HaveForgedWeapon", tooltip = "Number of Forged Weapons active (Forge Guard).", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ForgedWeapon", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveForgedWeapon", "FLAG", val >= 1, "Config", { type = "Condition", var = "Combat" })
	end },

	-- Section: Combat options
	{ section = "When In Combat", col = 1 },
	{ var = "repeatMode", type = "list", label = "Repeat Mode:", ifCond = "alwaysFinalRepeat", list = {
		{val="NONE",label="None"},
		{val="AVERAGE",label="Average"},
		{val="FINAL",label="Final only"},
		{val="FINAL_DPS",label="Final (all hits use final)"}
	}, defaultIndex = 2, apply = function(val, modList, enemyModList)
		if val == "AVERAGE" then
			modList:NewMod("Condition:averageRepeat", "FLAG", true, "Config")
		elseif val == "FINAL" or val == "FINAL_DPS" then
			modList:NewMod("Condition:alwaysFinalRepeat", "FLAG", true, "Config")
		end
	end },
	{ var = "conditionLeeching", type = "check", label = "Are you Leeching?", ifCond = "Leeching", tooltip = "You will automatically be considered to be Leeching if you have '^xE05030Life ^7Leech effects are not removed at Full ^xE05030Life^7',\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Leeching", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionLeechingLife", type = "check", label = "Are you Leeching ^xE05030Life?", ifCond = "LeechingLife", implyCond = "Leeching", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Leeching", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHaveTotem", type = "check", label = "Do you have a Totem summoned?", ifCond = "HaveTotem", tooltip = "You will automatically be considered to have a Totem if your main skill is a Totem,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveTotem", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionSummonedTotemRecently", type = "check", label = "Have you Summoned a Totem Recently?", ifCond = "SummonedTotemRecently", tooltip = "You will automatically be considered to have Summoned a Totem Recently if your main skill is a Totem,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:SummonedTotemRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "TotemsSummoned", type = "count", label = "# of Summoned Totems (if not maximum):", ifStat = "TotemsSummoned", ifFlag = "totem", implyCond = "HaveTotem", tooltip = "This also implies that you have a Totem summoned.\nThis will affect all 'per Summoned Totem' modifiers, even for non-Totem skills.", apply = function(val, modList, enemyModList)
		modList:NewMod("TotemsSummoned", "OVERRIDE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveTotem", "FLAG", val >= 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierNearbyAlly", type = "count", label = "# of Nearby Allies:", ifMult = "NearbyAlly", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:NearbyAlly", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierSummonedMinion", type = "count", label = "# of Summoned Minions:", ifMult = "SummonedMinion", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:SummonedMinion", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBlinded", type = "check", label = "Are you Blinded?", ifCond = "Blinded", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Blinded", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionIgnited", type = "check", label = "Are you ^xB97123Ignited?", ifCond = "Ignited", implyCond = "Burning", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Ignited", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionChilled", type = "check", label = "Are you ^x3F6DB3Chilled?", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Chilled", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionChilledEffect", type = "count", label = "Effect of ^x3F6DB3Chill:", ifOption = "conditionChilled", apply = function(val, modList, enemyModList)
		modList:NewMod("ChillVal", "OVERRIDE", val, "Chill", { type = "Condition", var = "Chilled" })
	end },
	{ var = "conditionFrozen", type = "check", label = "Are you ^x3F6DB3Frozen?", ifCond = "Frozen", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Frozen", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionShocked", type = "check", label = "Are you ^xADAA47Shocked?", ifCond = "Shocked", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Shocked", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("DamageTaken", "INC", 15, "Shock", { type = "Condition", var = "Shocked" })
	end },
	{ var = "conditionBleeding", type = "check", label = "Are you Bleeding?", ifCond = "Bleeding", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Bleeding", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionPoisoned", type = "check", label = "Are you Poisoned?", ifCond = "Poisoned", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Poisoned", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierPoisonOnSelf", type = "count", label = "# of Poison on You:", ifMult = "PoisonStack", implyCond = "Poisoned", tooltip = "This also implies that you are Poisoned.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:PoisonStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierNearbyEnemies", type = "count", label = "# of nearby Enemies:", ifMult = "NearbyEnemies", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:NearbyEnemies", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:OnlyOneNearbyEnemy", "FLAG", val == 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHitRecently", type = "check", label = "Have you Hit Recently?", ifCond = "HitRecently", tooltip = "You will automatically be considered to have Hit Recently if your main skill Hits and is self-cast,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HitRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHitSpellRecently", type = "check", label = "Have you Hit with a Spell Recently?", ifCond = "HitSpellRecently", implyCond = "HitRecently", tooltip = "This also implies that you have Hit Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HitSpellRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HitRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionCritRecently", type = "check", label = "Have you Crit Recently?", ifCond = "CritRecently", implyCond = "SkillCritRecently", tooltip = "This also implies that your Skills have Crit Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:CritRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:SkillCritRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionSkillCritRecently", type = "check", label = "Have your Skills Crit Recently?", ifCond = "SkillCritRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:SkillCritRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionNonCritRecently", type = "check", label = "Have you dealt a Non-Crit Recently?", ifCond = "NonCritRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:NonCritRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionChannelling", type = "check", label = "Are you Channelling?", ifCond = "Channelling", tooltip = "You will automatically be considered to be Channeling if your main skill is a channelled skill,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Channelling", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierChannelling", type = "count", label = "Channeling for # seconds:", ifMult = "ChannellingTime", implyCond = "Channelling", tooltip = "This also implies that you are channelling", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ChannellingTime", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:Channelling", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHitRecentlyWithWeapon", type = "check", label = "Have you Hit Recently with Your Weapon?", ifCond = "HitRecentlyWithWeapon", tooltip = "This also implies that you have Hit Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HitRecentlyWithWeapon", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionKilledRecently", type = "check", label = "Have you Killed Recently?", ifCond = "KilledRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:KilledRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierKilledRecently", type = "count", label = "# of Enemies Killed Recently:", ifMult = "EnemyKilledRecently", implyCond = "KilledRecently", tooltip = "This also implies that you have Killed Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:EnemyKilledRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:KilledRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionKilledLast3Seconds", type = "check", label = "Have you Killed in the last 3 Seconds?", ifCond = "KilledLast3Seconds", implyCond = "KilledRecently", tooltip = "This also implies that you have Killed Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:KilledLast3Seconds", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionMinionsKilledRecently", type = "check", label = "Have your Minions Killed Recently?", ifCond = "MinionsKilledRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:MinionsKilledRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionMinionsDiedRecently", type = "check", label = "Has a Minion Died Recently?", ifCond = "MinionsDiedRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:MinionsDiedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierMinionsKilledRecently", type = "count", label = "# of Enemies Killed by Minions Recently:", ifMult = "EnemyKilledByMinionsRecently", implyCond = "MinionsKilledRecently", tooltip = "This also implies that your Minions have Killed Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:EnemyKilledByMinionsRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:MinionsKilledRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierManaSpentRecently", type = "count", label = "# of ^x7070FFMana ^7spent Recently:", ifMult = "ManaSpentRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ManaSpentRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBeenHitRecently", type = "check", label = "Have you been Hit Recently?", ifCond = "BeenHitRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BeenHitRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierBeenHitRecently", type = "count", label = "# of times you have been Hit Recently:", ifMult = "BeenHitRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:BeenHitRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:BeenHitRecently", "FLAG", 1 <= val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBeenCritRecently", type = "check", label = "Have you been Crit Recently?", ifCond = "BeenCritRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BeenCritRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBlockedRecently", type = "check", label = "Have you Blocked Recently?", ifCond = "BlockedRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BlockedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBlockedAttackRecently", type = "check", label = "Have you Blocked an Attack Recently?", ifCond = "BlockedAttackRecently", implyCond = "BlockedRecently", tooltip = "This also implies that you have Blocked Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BlockedAttackRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:BlockedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBlockedSpellRecently", type = "check", label = "Have you Blocked a Spell Recently?", ifCond = "BlockedSpellRecently", implyCond = "BlockedRecently", tooltip = "This also implies that you have Blocked Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BlockedSpellRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:BlockedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionUsedSkillRecently", type = "check", label = "Have you used a Skill Recently?", ifCond = "UsedSkillRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:UsedSkillRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierSkillUsedRecently", type = "count", label = "# of Skills Used Recently:", ifMult = "SkillUsedRecently", implyCond = "UsedSkillRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:SkillUsedRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:UsedSkillRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionAttackedRecently", type = "check", label = "Have you Attacked Recently?", ifCond = "AttackedRecently", implyCond = "UsedSkillRecently", tooltip = "This also implies that you have used a Skill Recently.\nYou will automatically be considered to have Attacked Recently if your main skill is an attack,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:AttackedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:UsedSkillRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionCastSpellRecently", type = "check", label = "Have you Cast a Spell Recently?", ifCond = "CastSpellRecently", implyCond = "UsedSkillRecently", tooltip = "This also implies that you have used a Skill Recently.\nYou will automatically be considered to have Cast a Spell Recently if your main skill is a spell,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:CastSpellRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:UsedSkillRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- Section: Effective DPS options
	{ section = "For Effective DPS", col = 1 },
	{ var = "meleeDistance", type = "count", label = "Melee distance to enemy:", ifTagType = "MeleeProximity", ifFlag = "melee" },
	{ var = "projectileDistance", type = "count", label = "Projectile travel distance:", ifTagType = "DistanceRamp", ifFlag = "projectile" },
	{ var = "conditionAtCloseRange", type = "check", label = "Is the enemy at Close Range?", ifCond = "AtCloseRange", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:AtCloseRange", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyMoving", type = "check", label = "Is the enemy Moving?", ifMod = "BleedChance", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Moving", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyFullLife", type = "check", label = "Is the enemy on Full ^xE05030Life?", ifEnemyCond = "FullLife", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:FullLife", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyLowLife", type = "check", label = "Is the enemy on Low ^xE05030Life?", ifEnemyCond = "LowLife", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:LowLife", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyStunned", type = "check", label = "Is the enemy Stunned?", ifEnemyCond = "Stunned", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Stunned", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyBleeding", type = "check", label = "Is the enemy Bleeding?", ifEnemyCond = "Bleeding", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Bleeding", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyPoisoned", type = "check", label = "Is the enemy Poisoned?", ifEnemyCond = "Poisoned", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Poisoned", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierPoisonOnEnemy", type = "count", label = "# of Poison on enemy:", ifEnemyMult = "PoisonStack", implyCond = "Poisoned", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:PoisonStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyBlinded", type = "check", label = "Is the enemy Blinded?", tooltip = "In addition to allowing 'against Blinded Enemies' modifiers to apply,\n Blind applies the following effects.\n -20% Accuracy \n -20% ^x33FF77Evasion", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Blinded", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyIgnited", type = "check", label = "Is the enemy ^xB97123Ignited?", ifEnemyCond = "Ignited", implyCond = "Burning", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Ignited", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyChilled", type = "check", label = "Is the enemy ^x3F6DB3Chilled?", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Chilled", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:ChilledConfig", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyFrozen", type = "check", label = "Is the enemy ^x3F6DB3Frozen?", ifEnemyCond = "Frozen", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Frozen", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyShocked", type = "check", label = "Is the enemy ^xADAA47Shocked?", tooltip = "In addition to allowing any 'against ^xADAA47Shocked ^7Enemies' modifiers to apply,\nthis will allow you to input the effect of the ^xADAA47Shock ^7applied to the enemy.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Shocked", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:ShockedConfig", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyCursed", type = "check", label = "Is the enemy Cursed?", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Cursed", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemySlowed", type = "check", label = "Is the enemy Slowed?", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Slowed", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyHitRecently", type = "check", label = "Was the enemy Hit Recently?", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:HitRecently", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyStunnedRecently", type = "check", label = "Was the enemy Stunned Recently?", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:StunnedRecently", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyKilledRecently", type = "check", label = "Was an enemy Killed Recently?", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:KilledRecently", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	-- Enemy ailment stack counts (for per-stack modifiers)
	{ var = "multiplierEnemyBleedStacks", type = "count", label = "Enemy Bleed Stacks:", implyCond = "Bleeding", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:BleedStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Bleeding", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyIgniteStacks", type = "count", label = "Enemy Ignite Stacks:", implyCond = "Ignited", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:IgniteStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Ignited", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyShockStacks", type = "count", label = "Enemy Shock Stacks:", implyCond = "Shocked", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		enemyModList:NewMod("Multiplier:ShockStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Shocked", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyChillStacks", type = "count", label = "Enemy Chill Stacks:", implyCond = "Chilled", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		enemyModList:NewMod("Multiplier:ChillStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Chilled", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyTimeRotStacks", type = "count", label = "Enemy Time Rot Stacks:", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:TimeRotStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyDoomStacks", type = "count", label = "Enemy Doom Stacks:", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:DoomStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemySlowStacks", type = "count", label = "Enemy Slow Stacks:", implyCond = "Slowed", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		enemyModList:NewMod("Multiplier:SlowStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Slowed", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyFrailtyStacks", type = "count", label = "Enemy Frailty Stacks:", implyCond = "Frail", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:FrailtyStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Frail", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyCurseStacks", type = "count", label = "Enemy Curse Stacks:", implyCond = "Cursed", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:CurseStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Cursed", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	-- Section: Enemy Stats
	{ section = "Enemy Stats", col = 3 },
	{ var = "leBossCategory", type = "list", label = "Is the enemy a Boss?",
	  tooltip = data.enemyIsBossTooltip,
	  defaultIndex = 2,
	  list = {
		{ val = "none",                    label = "None" },
		{ val = "Empowered Monolith Boss", label = "Empowered Monolith Boss" },
		{ val = "Dungeon Boss",            label = "Dungeon Boss (Tier 4)" },
		{ val = "Pinnacle Boss",           label = "Pinnacle Boss" },
		{ val = "Uber Boss",               label = "Uber Boss (Herald of Oblivion)" },
	  },
	  apply = function(val, modList, enemyModList)
		if val ~= "none" and data.bossStats[val] then
			local s = data.bossStats[val]
			if s.healthMean > 0 then
				enemyModList:NewMod("Life", "BASE", s.healthMean, "BossConfig")
			end
			if s.wardMean > 0 then
				enemyModList:NewMod("Ward", "BASE", s.wardMean, "BossConfig")
			end
			if s.damageModMean > 0 then
				enemyModList:NewMod("Damage", "MORE", s.damageModMean, "BossConfig")
			end
			enemyModList:NewMod("Condition:Boss", "FLAG", true, "BossConfig")
		end
	  end },
	{ var = "enemyLevel", type = "count", label = "Enemy / Area Level:", defaultPlaceholderState = 1, tooltip = "This overrides the default enemy level used to estimate your armor reduction and ^x33FF77dodge ^7chance.\n\nThe default level is set to your character level and cannot exceeds 100", apply = function(val, modList, enemyModList, build)
		build.configTab.varControls['enemyLevel']:SetPlaceholder(build.configTab.enemyLevel, true)
	end },
}

for i,damageType in ipairs(DamageTypes) do
    table.insert(options,  { var = "enemy" .. damageType .. "Resist", type = "integer", label = "Enemy " .. DamageTypesColored[i] .. " Resistance:", apply = function(val, modList, enemyModList)
		enemyModList:NewMod(damageType .. "Resist", "BASE", val, "EnemyConfig")
	end })
end

tableInsertAll(options, {
	{ var = "enemyBlockChance", type = "integer", label = "Enemy Block Chance:", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("BlockChance", "BASE", val, "Config")
	end },
	{ var = "enemyEvasion", type = "count", label = "Enemy Base ^x33FF77Evasion:", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Evasion", "BASE", val, "Config")
	end },
	{ var = "enemyArmour", type = "count", label = "Enemy Base Armour:", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Armour", "BASE", val, "Config")
	end },
	{ var = "enemyDamageRollRange", type = "integer", label = "Enemy Skill Roll Range %:", ifFlag = "BossSkillActive", tooltip = "The percentage of the roll range the enemy hits for \n eg at 100% the enemy deals its maximum damage", defaultPlaceholderState = 70, hideIfInvalid = true },
	{ var = "enemySpeed", type = "integer", label = "Enemy attack / cast time in ms:", defaultPlaceholderState = 700 },
	{ var = "enemyCritChance", type = "integer", label = "Enemy critical strike chance:", defaultPlaceholderState = 5 },
	{ var = "enemyCritDamage", type = "integer", label = "Enemy critical strike multiplier:", defaultPlaceholderState = 30 }
})

for _,damageType in ipairs(DamageTypes) do
    table.insert(options,  { var = "enemy"..damageType.."Damage", type = "integer", label = "Enemy Skill "..damageType.." Damage:", defaultPlaceholderState = 1000})
end

tableInsertAll(options, {
-- Section: Custom mods
	{ section = "Custom Modifiers", col = 1 },
	{ var = "customMods", type = "text", label = "", doNotHighlight = true,
		apply = function(val, modList, enemyModList, build)
			for line in val:gmatch("([^\n]*)\n?") do
				local strippedLine = StripEscapes(line):gsub("^[%s?]+", ""):gsub("[%s?]+$", "")
				local mods, extra = modLib.parseMod(strippedLine)

				if mods and not extra then
					local source = "Custom"
					for i = 1, #mods do
						local mod = mods[i]

						if mod then
							mod = modLib.setSource(mod, source)
							modList:AddMod(mod)
						end
					end
				end
			end
		end,
		inactiveText = function(val)
			local inactiveText = ""
			for line in val:gmatch("([^\n]*)\n?") do
				local strippedLine = StripEscapes(line):gsub("^[%s?]+", ""):gsub("[%s?]+$", "")
				local mods, extra = modLib.parseMod(strippedLine)
				inactiveText = inactiveText .. ((mods and not extra) and colorCodes.MAGIC or colorCodes.UNSUPPORTED).. (IsKeyDown("ALT") and strippedLine or line) .. "\n"
			end
			return inactiveText
		end,
		tooltip = function(modList)
			if not launch.devModeAlt then
				return
			end

			local out
			for _, mod in ipairs(modList) do
				if mod.source == "Custom" then
					out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
				end
			end
			return out
		end},
})

return options
