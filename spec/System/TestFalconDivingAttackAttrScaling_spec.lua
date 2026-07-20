-- @leb-regression-guard:falcon-diving-attack-redundant-attr-scaling
-- See REGRESSION_GUARDS.md "falcon-diving-attack-redundant-attr-scaling".
-- Validation provenance is retained in maintainer notes.

describe("FalconDivingAttackAttrScaling", function()
	local SUMMON = "Falconer 00 Falconry"
	local SUBSKILL = "RogueFalcon Diving Attack"

	before_each(function()
		newBuild()
		-- Keep the player level under 26 so the minion level-MORE = 1 (deterministic INC).
		build.characterLevel = 1
	end)

	-- Select the summon, build the env, then inject known player attributes and rebuild so the
	-- "per player <Attr>" PerStat contributions are non-zero and measurable.
	local function buildFalcon(dex, int)
		build.skillsTab:SelSkill(1, SUMMON)
		runCallback("OnFrame")
		local pdb = build.calcsTab.mainEnv.player.modDB
		pdb:NewMod("Dex", "BASE", dex, "Test")
		pdb:NewMod("Int", "BASE", int, "Test")
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

	-- Count per-<attr> Damage INC/MORE mods held on a store's OWN mods, excluding its parent.
	-- The two stores differ: a ModList keeps its mods in a plain sequential array on itself,
	-- while a ModDB keys them by mod name in `.mods` (iterating a ModDB with ipairs silently
	-- yields nothing -- the trap this helper exists to avoid).
	local function countPerAttr(store, attr)
		local n = 0
		local own = store.mods and (store.mods["Damage"] or { }) or store
		for _, mod in ipairs(own) do
			if isPerAttrDamage(mod, attr) then n = n + 1 end
		end
		return n
	end

	-- Count every per-<attr> Damage source the falcon's hit sees: the sub-skill's own ModList
	-- plus the minion's modDB (its parent). The player's own modDB is deliberately NOT walked
	-- -- the summon's grant is re-homed onto minion.modDB, and player-side per-attr damage mods
	-- are a different concern.
	local function countFalconPerAttr(minion, as, attr)
		return countPerAttr(as.skillModList, attr) + countPerAttr(minion.modDB, attr)
	end

	it("registry registers the falcon's Diving Attack with BOTH Dex and Int", function()
		assert.is_table(LE_MINION_SKILL_REDUNDANT_ATTR_SCALING,
			"LE_MINION_SKILL_REDUNDANT_ATTR_SCALING must be defined in Global.lua")
		local entry = LE_MINION_SKILL_REDUNDANT_ATTR_SCALING[SUBSKILL]
		assert.is_table(entry, SUBSKILL .. " must be registered")
		assert.is_true(entry.Dex == true, "Dex (duplicate of Falconry's per-Dex) must be dropped")
		assert.is_true(entry.Int == true, "Int (phantom -- no Int scaling in-game) must be dropped")
	end)

	it("the strip removes REAL mods: Diving Attack's baseMods do carry per-Dex AND per-Int", function()
		-- Guard against the registry silently no-op'ing: the source data must actually carry both
		-- per-attr Damage baseMods, so the strip removes present mods (not matching nothing).
		buildFalcon(263, 41) -- ensure a build has loaded env.data.skills
		local ge = build.calcsTab.mainEnv.data.skills[SUBSKILL]
		assert.is_table(ge and ge.baseMods, SUBSKILL .. " must have baseMods in data")
		local found = { Dex = false, Int = false }
		for _, m in ipairs(ge.baseMods) do
			if type(m) == "table" and m.name == "Damage" and (m.type == "INC" or m.type == "MORE") then
				for _, tag in ipairs(m) do
					if tag.type == "PerStat" then
						local stat = tag.stat or (tag.statList and tag.statList[1])
						if found[stat] ~= nil then found[stat] = true end
					end
				end
			end
		end
		assert.is_true(found.Dex, "Diving Attack baseMods must carry a per-Dex Damage mod")
		assert.is_true(found.Int, "Diving Attack baseMods must carry a per-Int Damage mod")
	end)

	it("Diving Attack's OWN per-Dex and per-Int Damage mods are stripped from its skillModList", function()
		local _, as = buildFalcon(263, 41)
		assert.are.equals(SUBSKILL, as.activeEffect.grantedEffect.id,
			"the falcon's default sub-skill must be " .. SUBSKILL)
		assert.are.equals(0, countPerAttr(as.skillModList, "Dex"),
			"the duplicated per-Dex Damage mod must be stripped from the sub-skill")
		assert.are.equals(0, countPerAttr(as.skillModList, "Int"),
			"the phantom per-Int Damage mod must be stripped from the sub-skill")
	end)

	it("the summon's canonical per-Dex minion scaling SURVIVES on minion.modDB (no zero-count)", function()
		-- The strip is local to the sub-skill's skillModList. Falconry's "increased Minion Damage
		-- per player Dexterity" lives on minion.modDB and is the one true source -- it must remain,
		-- otherwise the fix would trade a double-count for a zero-count.
		local minion = buildFalcon(263, 41)
		assert.is_true(countPerAttr(minion.modDB, "Dex") >= 1,
			"Falconry's per-Dex minion-damage scaling must remain on minion.modDB")
	end)

	it("net effect: the falcon sees player Dex exactly ONCE and player Int NEVER", function()
		-- The invariant the +32.6% over-count violated. Counting sources across the sub-skill's
		-- ModList + minion.modDB is what "scales off the attribute exactly once" means: before the
		-- fix the falcon saw Dex twice (summon + sub-skill copy) and Int once (the phantom).
		local minion, as = buildFalcon(263, 41)
		assert.are.equals(1, countFalconPerAttr(minion, as, "Dex"),
			"player Dex must reach the falcon's hit through exactly one mod (the summon's)")
		assert.are.equals(0, countFalconPerAttr(minion, as, "Int"),
			"player Int must not reach the falcon's hit at all")
	end)

	it("SCOPED: Feather Knives is untouched (it carries no per-attr baseMods)", function()
		buildFalcon(263, 41)
		local ge = build.calcsTab.mainEnv.data.skills["FeatherKnives"]
		assert.is_table(ge, "FeatherKnives must exist in data")
		local n = 0
		for _, m in ipairs(ge.baseMods or {}) do
			if type(m) == "table" and m.name == "Damage" then
				for _, tag in ipairs(m) do
					if tag.type == "PerStat" then n = n + 1 end
				end
			end
		end
		assert.are.equals(0, n,
			"FeatherKnives must carry no per-attr Damage baseMods (so it was never inflated)")
		assert.is_nil(LE_MINION_SKILL_REDUNDANT_ATTR_SCALING["FeatherKnives"],
			"FeatherKnives must not be registered (nothing to strip)")
	end)
end)
