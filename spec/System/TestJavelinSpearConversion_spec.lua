-- @leb-regression-guard:javelin-spear-melee-to-throwing-conversion
-- CalcOffence.lua skillPart term). See REGRESSION_GUARDS.md.
-- Validation provenance is retained in maintainer notes.

describe("JavelinSpearConversion", function()
	-- A level-100 Sentinel can BOTH wield a Two-Handed Spear and use Javelin. Auto-equip
	-- rejects a fresh 2H spear (empty build), so force-equip to Weapon 1. Returns the
	-- Javelin physical hit AND the skill-scoped BASE PhysicalDamage added (which the
	-- conversion injects) so the coefficient can be asserted without any scaling noise.
	local function javelin(weaponRaw)
		newBuild()
		build.spec:SelectClass(2) -- Sentinel
		build.characterLevelAutoMode = false
		build.characterLevel = 100
		build.itemsTab:CreateDisplayItemFromRaw(weaponRaw)
		local item = build.itemsTab.displayItem
		build.itemsTab:AddDisplayItem()
		build.itemsTab.slots["Weapon 1"]:SetSelItemId(item.id)
		build.buildFlag = true
		build.skillsTab:SelSkill(1, "Javelin")
		runCallback("OnFrame")
		local ms = build.calcsTab.mainEnv.player.mainSkill
		local physAdd = ms.skillModList:Sum("BASE", ms.skillCfg, "PhysicalDamage")
		return build.calcsTab.mainOutput.PhysicalHitAverage or 0, physAdd
	end

	local SPEAR = "Rarity: RARE\nTrident\nTrident\n"
	local SCEPTRE = "Rarity: RARE\nBrass Sceptre\nBrass Sceptre\n"

	it("spear added melee converts to throwing-added physical at exactly 50%", function()
		local _, baseAdd = javelin(SPEAR)
		local _, meleeAdd = javelin(SPEAR .. "+100 Melee Physical Damage")
		-- +100 Melee Physical on the spear -> +50 skill-scoped added throwing physical
		-- (datamined 0.5 conversion). The base spear has no physical melee affix -> 0.
		assert.are.equals(0, round(baseAdd, 4))
		assert.are.equals(50, round(meleeAdd, 4))
	end)

	it("the converted added rides the same 250% effectiveness as ordinary added damage", function()
		local base, baseAdd = javelin(SPEAR)
		local melee, meleeAdd = javelin(SPEAR .. "+100 Melee Physical Damage")
		local generic, genericAdd = javelin(SPEAR .. "+100 Physical Damage")
		-- Per unit of added-physical, the spear-converted flat must raise the hit by the
		-- same amount as an ordinary added-physical flat (both ride x damageEffectiveness x
		-- increases x more). Equal per-unit rates prove the converted flat is NOT shorted
		-- the 250% effectiveness.
		local meleeRate = (melee - base) / (meleeAdd - baseAdd)
		local genericRate = (generic - base) / (genericAdd - baseAdd)
		assert.is_true(meleeAdd > baseAdd and genericAdd > baseAdd)
		assert.are.equals(round(genericRate, 4), round(meleeRate, 4))
	end)

	it("added melee from a NON-spear weapon does NOT convert (other-source melee has no effect)", function()
		local _, baseAdd = javelin(SCEPTRE)
		local _, meleeAdd = javelin(SCEPTRE .. "+100 Melee Physical Damage")
		assert.are.equals(round(baseAdd, 4), round(meleeAdd, 4))
	end)

	it("scope: conversion gates on the Javelin skill id + an equipped Spear (source guard)", function()
		local f = io.open("Modules/CalcActiveSkill.lua", "r") or io.open("src/Modules/CalcActiveSkill.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcActiveSkill.lua")
		local src = f:read("*a"); f:close()
		assert.is_truthy(src:find("@leb-regression-guard:javelin-spear-melee-to-throwing-conversion", 1, true),
			"the guard marker must be present")
		assert.is_truthy(src:find('activeGrantedEffect.id == "Javelin"', 1, true),
			"the conversion must gate on the Javelin skill id (scope)")
		assert.is_truthy(src:find('weapon1Type.flag == "Spear"', 1, true),
			"the conversion must require an equipped Spear")
		assert.is_truthy(src:find("spearMeleeAdded * 0.5", 1, true),
			"the conversion coefficient must be 0.5 (added melee -> added throwing)")
	end)
end)
