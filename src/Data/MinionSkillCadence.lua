-- Validation provenance is retained in maintainer notes.

local cadence = {
	-- minion grantedEffect.id  ->  measured hits/second
	["ManifestedArmor"] = {
		["Manifest Armor 01 Melee"] = 0.338,
		["ManifestArmorForgeBreath"] = 0.467,
		["ManifestArmorWhirlwind"]   = 1.067,
		["ManifestArmorCharge"]      = 0.419,
	},
	["PrimalBear"] = {
		["PrimalBear 01 melee attack"] = 0.548,  -- Melee Attack (intrinsic)
		["Swipe"]          = 0.638,              -- Swipe (granted, _MinionWeaponBase)
		["EarthquakeSlam"] = 0.159,              -- Earthquake CAST rate (3-slam sum per hit)
	},
	["SummonedAbomination"] = {
		["Abomination Melee"]         = 0.635,  -- Melee Attack (intrinsic default skill)
		-- Double Strike is always in activeSkillList (its Spoils node is allocated), but only
		-- FIRES once a Warrior/Rogue is absorbed -> gate the fold on that multiplier so a
		-- 0-absorb build folds nothing (nMatched < nTbl) and stays byte-identical.
		["Abomination Double Strike"] = { rate = 0.336, requires = "Multiplier:AbominationWarriorsOrRoguesAbsorbed" },
	},
}

return cadence
