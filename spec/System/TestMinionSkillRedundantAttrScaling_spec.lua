-- @leb-regression-guard:minion-skill-redundant-attr-scaling
-- See REGRESSION_GUARDS.md "minion-skill-redundant-attr-scaling".
-- Validation provenance is retained in maintainer notes.

describe("MinionSkillRedundantAttrScaling", function()
	before_each(function()
		newBuild()
		-- Keep the player level under 26 so the minion level-MORE = 1 (deterministic INC).
		build.characterLevel = 1
	end)

	-- Select a summon, build the env, then inject a known player attribute and rebuild so
	-- the "per player <Attr>" PerStat contributions are non-zero and measurable.
	local function buildSummonWithAttr(summonId, attr, n)
		build.skillsTab:SelSkill(1, summonId)
		runCallback("OnFrame")
		build.calcsTab.mainEnv.player.modDB:NewMod(attr, "BASE", n, "Test")
		build.buildFlag = false
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion for " .. summonId)
		return minion, minion.mainSkill
	end

	local function dreadBoltDamageINC()
		local minion, as = buildSummonWithAttr("SummonMage", "Int", 100)
		return as.skillModList:Sum("INC", as.skillCfg, "Damage"), minion, as
	end

	it("registry exists and registers Dread Bolt's Int as a redundant attribute", function()
		assert.is_table(LE_MINION_SKILL_REDUNDANT_ATTR_SCALING,
			"LE_MINION_SKILL_REDUNDANT_ATTR_SCALING must be defined in Global.lua")
		assert.is_table(LE_MINION_SKILL_REDUNDANT_ATTR_SCALING["Skeletal Mages Necrotic Projectile"],
			"Dread Bolt (Skeletal Mages Necrotic Projectile) must be registered")
		assert.is_true(LE_MINION_SKILL_REDUNDANT_ATTR_SCALING["Skeletal Mages Necrotic Projectile"].Int == true,
			"Dread Bolt's redundant attribute must be Int")
	end)

	-- Count per-Int Damage INC/MORE mods on a store, split by whether they come from the
	-- minion ATTACK skill (Skill:Skeletal Mages Necrotic Projectile -- the duplicate the
	-- strip removes) vs the SUMMON (Skill:SummonMage -- the canonical single source).
	local function countPerIntBySource(store)
		local fromSummon, fromBolt = 0, 0
		for _, mod in ipairs(store) do
			if mod.name == "Damage" and (mod.type == "INC" or mod.type == "MORE") then
				for _, tag in ipairs(mod) do
					if tag.type == "PerStat" and (tag.stat == "Int" or (tag.statList and tag.statList[1] == "Int")) then
						local src = tostring(mod.source)
						if src == "Skill:SummonMage" then fromSummon = fromSummon + 1
						elseif src == "Skill:Skeletal Mages Necrotic Projectile" then fromBolt = fromBolt + 1 end
					end
				end
			end
		end
		return fromSummon, fromBolt
	end

	it("Dread Bolt's OWN per-Int Damage mod is stripped from the minion skill's modList", function()
		local _, _, as = dreadBoltDamageINC()
		-- The strip is local to the minion attack skill's skillModList: the bolt's own
		-- baseMods copy (Skill:Skeletal Mages Necrotic Projectile) must be gone, leaving the
		-- summon's MinionModifier (which lives on minion.modDB, not here) as the single source.
		local _, fromBolt = countPerIntBySource(as.skillModList)
		assert.are.equals(0, fromBolt,
			"the Dread Bolt skill's OWN per-Int Damage mod must be stripped (no doubling)")
	end)

	it("the strip removes a REAL mod: Dread Bolt's baseMods do carry per-Int Damage in data", function()
		-- Guard against the registry silently no-op'ing: the source data (skills.json,
		-- env.data.skills) must actually carry the per-Int Damage baseMod on Dread Bolt, so
		-- the strip is removing a present duplicate (not matching nothing). The summon
		-- (SummonMage) carries the canonical "increased Minion Damage per player Intelligence"
		-- which is NOT stripped -- it remains the single source.
		dreadBoltDamageINC() -- ensure a build has loaded env.data.skills
		local boltGe = build.calcsTab.mainEnv.data.skills["Skeletal Mages Necrotic Projectile"]
		assert.is_table(boltGe and boltGe.baseMods, "Dread Bolt must have baseMods in data")
		-- baseMods are parsed into mod objects by DataProcess: look for the per-Int Damage mod.
		local hasPerInt = false
		for _, m in ipairs(boltGe.baseMods) do
			if type(m) == "table" and m.name == "Damage" and (m.type == "INC" or m.type == "MORE") then
				for _, tag in ipairs(m) do
					if tag.type == "PerStat" and (tag.stat == "Int" or (tag.statList and tag.statList[1] == "Int")) then
						hasPerInt = true
					end
				end
			end
		end
		assert.is_true(hasPerInt,
			"Dread Bolt baseMods must carry a per-Int Damage mod (the duplicate the strip targets)")
	end)

	it("SCOPED: an UNregistered minion skill keeps its per-attribute scaling (Bone Golem Maul/Str)", function()
		-- The Bone Golem's Maul scales per Strength + Attunement; SummonBoneGolem scales per Int.
		-- Different attributes -> NOT a duplicate -> Maul's per-Str must NOT be stripped.
		local _, as = buildSummonWithAttr("SummonBoneGolem", "Str", 100) -- as = Maul
		-- Maul carries "4% increased Damage per player Strength" (Skill:Bone Golem 02 Big Slam);
		-- it is NOT registered as redundant (SummonBoneGolem scales per Int, a different attr),
		-- so the per-Str mod must survive.
		local perStrPresent = false
		for _, v in ipairs(as.skillModList:Tabulate("INC", as.skillCfg, "Damage")) do
			for _, tag in ipairs(v.mod) do
				if tag.type == "PerStat" and (tag.stat == "Str" or (tag.statList and tag.statList[1] == "Str")) then
					perStrPresent = true
				end
			end
		end
		assert.is_true(perStrPresent,
			"Bone Golem Maul's per-Strength scaling (unregistered) must be preserved")
	end)

	it("source contract: createMinionSkills gates the strip on the registry", function()
		local f = io.open("Modules/CalcActiveSkill.lua", "r") or io.open("src/Modules/CalcActiveSkill.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcActiveSkill.lua")
		local src = f:read("*a"); f:close()
		assert.is_truthy(src:find("@leb-regression-guard:minion-skill-redundant-attr-scaling", 1, true),
			"guard marker must be present in CalcActiveSkill.lua")
		assert.is_truthy(src:find("LE_MINION_SKILL_REDUNDANT_ATTR_SCALING[skillId]", 1, true),
			"the strip must be gated by the LE_MINION_SKILL_REDUNDANT_ATTR_SCALING registry (whitelist)")
	end)
end)
