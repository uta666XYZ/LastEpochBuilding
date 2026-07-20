-- @leb-regression-guard:spriggan-thornvolley-redundant-attr-scaling
-- See REGRESSION_GUARDS.md "spriggan-thornvolley-redundant-attr-scaling".
-- Validation provenance is retained in maintainer notes.

describe("SprigganThornVolleyAttrScaling", function()
	local SUMMON = "SummonSpriggan"
	local SUBSKILL = "ThornVolley"

	before_each(function()
		newBuild()
		-- Keep the player level under 26 so the minion level-MORE = 1 (deterministic INC).
		build.characterLevel = 1
	end)

	local function buildSpriggan(att)
		build.skillsTab:SelSkill(1, SUMMON)
		runCallback("OnFrame")
		build.calcsTab.mainEnv.player.modDB:NewMod("Att", "BASE", att, "Test")
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

	it("registry registers ThornVolley's Att as redundant", function()
		assert.is_table(LE_MINION_SKILL_REDUNDANT_ATTR_SCALING,
			"LE_MINION_SKILL_REDUNDANT_ATTR_SCALING must be defined in Global.lua")
		local entry = LE_MINION_SKILL_REDUNDANT_ATTR_SCALING[SUBSKILL]
		assert.is_table(entry, SUBSKILL .. " must be registered")
		assert.is_true(entry.Att == true, "Att (duplicate of SummonSpriggan's per-Att) must be dropped")
	end)

	it("the strip removes a REAL mod: ThornVolley's baseMods do carry per-Att Damage", function()
		-- Guard against the registry silently no-op'ing: the source data must actually carry
		-- the per-Att Damage baseMod, so the strip removes a present duplicate.
		buildSpriggan(68) -- ensure a build has loaded env.data.skills
		local ge = build.calcsTab.mainEnv.data.skills[SUBSKILL]
		assert.is_table(ge and ge.baseMods, SUBSKILL .. " must have baseMods in data")
		local hasPerAtt = false
		for _, m in ipairs(ge.baseMods) do
			if type(m) == "table" and isPerAttrDamage(m, "Att") then hasPerAtt = true end
		end
		assert.is_true(hasPerAtt, "ThornVolley baseMods must carry a per-Att Damage mod")
	end)

	it("ThornVolley's OWN per-Att Damage mod is stripped from its skillModList", function()
		local _, as = buildSpriggan(68)
		assert.are.equals(SUBSKILL, as.activeEffect.grantedEffect.id,
			"the Spriggan's default sub-skill must be " .. SUBSKILL)
		assert.are.equals(0, countPerAttr(as.skillModList, "Att"),
			"the duplicated per-Att Damage mod must be stripped from the sub-skill")
	end)

	it("the summon's canonical per-Att minion scaling SURVIVES on minion.modDB (no zero-count)", function()
		local minion = buildSpriggan(68)
		assert.is_true(countPerAttr(minion.modDB, "Att") >= 1,
			"SummonSpriggan's per-Att minion-damage scaling must remain on minion.modDB")
	end)

	it("net effect: the Spriggan sees player Att through exactly ONE mod", function()
		local minion, as = buildSpriggan(68)
		local total = countPerAttr(as.skillModList, "Att") + countPerAttr(minion.modDB, "Att")
		assert.are.equals(1, total,
			"player Att must reach the Spriggan's hit through exactly one mod (the summon's)")
	end)

	it("SCOPED: ValeSpirit SpiritThorns (same mechanism, NO capture yet) stays unregistered", function()
		-- SpiritThorns is the same structural duplicate, but the registry is capture-gated:
		-- only in-game-validated entries belong here. Registering it without its own oracle
		-- would violate the whitelist contract -- this case pins that decision until a
		-- ValeSpirit capture exists (then flip this assertion together with the new entry).
		assert.is_nil(LE_MINION_SKILL_REDUNDANT_ATTR_SCALING["SpiritThorns"],
			"SpiritThorns must not be registered until a ValeSpirit blank-capture validates it")
	end)
end)
