-- @leb-regression-guard:stormcrow-lightningblast-redundant-attr-scaling
-- See REGRESSION_GUARDS.md "stormcrow-lightningblast-redundant-attr-scaling".
-- Validation provenance is retained in maintainer notes.

describe("StormCrowLightningBlastAttrScaling", function()
	local SUMMON = "SummonStormCrow"
	local SUBSKILL = "StormCrowLightningBlast"

	before_each(function()
		newBuild()
		-- Keep the player level under 26 so the minion level-MORE = 1 (deterministic INC).
		build.characterLevel = 1
	end)

	local function buildStormCrow(int)
		build.skillsTab:SelSkill(1, SUMMON)
		runCallback("OnFrame")
		build.calcsTab.mainEnv.player.modDB:NewMod("Int", "BASE", int, "Test")
		build.buildFlag = false
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion for " .. SUMMON)
		return minion, minion.mainSkill
	end

	local function isPerAttrDamage(mod, attr)
		if mod.name ~= "Damage" or (mod.type ~= "INC" and mod.type ~= "MORE") then return false end
		for _, tag in ipairs(mod) do
			if tag.type == "PerStat" and (tag.stat == attr or (tag.statList and tag.statList[1] == attr)) then
				return true
			end
		end
		return false
	end

	-- ModList keeps its own mods in a sequential array on itself; ModDB keys them by mod
	-- name in `.mods` (ipairs over a ModDB silently yields nothing -- the trap this avoids).
	local function countPerAttr(store, attr)
		local n = 0
		local own = store.mods and (store.mods["Damage"] or { }) or store
		for _, mod in ipairs(own) do
			if isPerAttrDamage(mod, attr) then n = n + 1 end
		end
		return n
	end

	it("registry registers StormCrowLightningBlast's Int as redundant", function()
		assert.is_table(LE_MINION_SKILL_REDUNDANT_ATTR_SCALING,
			"LE_MINION_SKILL_REDUNDANT_ATTR_SCALING must be defined in Global.lua")
		local entry = LE_MINION_SKILL_REDUNDANT_ATTR_SCALING[SUBSKILL]
		assert.is_table(entry, SUBSKILL .. " must be registered")
		assert.is_true(entry.Int == true, "Int (the phantom per-Int) must be dropped")
	end)

	it("the strip removes a REAL mod: StormCrowLightningBlast's baseMods carry per-Int Damage", function()
		-- Guard against the registry silently no-op'ing: the source data must actually carry
		-- the per-Int Damage baseMod, so the strip removes a present mod.
		buildStormCrow(38) -- ensure a build has loaded env.data.skills
		local ge = build.calcsTab.mainEnv.data.skills[SUBSKILL]
		assert.is_table(ge and ge.baseMods, SUBSKILL .. " must have baseMods in data")
		local hasPerInt = false
		for _, m in ipairs(ge.baseMods) do
			if type(m) == "table" and isPerAttrDamage(m, "Int") then hasPerInt = true end
		end
		assert.is_true(hasPerInt, "StormCrowLightningBlast baseMods must carry a per-Int Damage mod")
	end)

	it("StormCrowLightningBlast's OWN per-Int Damage mod is stripped from its skillModList", function()
		local _, as = buildStormCrow(38)
		assert.are.equals(SUBSKILL, as.activeEffect.grantedEffect.id,
			"the Storm Crow's default sub-skill must be " .. SUBSKILL)
		assert.are.equals(0, countPerAttr(as.skillModList, "Int"),
			"the phantom per-Int Damage mod must be stripped from the sub-skill")
	end)

	it("PHANTOM shape: SummonStormCrow grants NO per-Int, so the strip leaves ZERO per-Int total", function()
		-- Validation provenance is retained in maintainer notes.
		local minion, as = buildStormCrow(38)
		assert.are.equals(0, countPerAttr(minion.modDB, "Int"),
			"SummonStormCrow must NOT grant per-Int minion damage (this is a phantom, not a dup)")
		local total = countPerAttr(as.skillModList, "Int") + countPerAttr(minion.modDB, "Int")
		assert.are.equals(0, total,
			"after the strip the Storm Crow's Lightning Blast must see the player Int through ZERO mods")
	end)

	it("the summon's REAL per-Att/per-Str minion scaling is untouched (only Int is stripped)", function()
		local minion = buildStormCrow(38)
		assert.is_true(countPerAttr(minion.modDB, "Att") >= 1,
			"SummonStormCrow's per-Attunement minion-damage scaling must remain")
		assert.is_true(countPerAttr(minion.modDB, "Str") >= 1,
			"SummonStormCrow's per-Strength minion-damage scaling must remain")
	end)
end)
