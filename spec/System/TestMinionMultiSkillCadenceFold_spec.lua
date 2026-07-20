-- @leb-regression-guard:minion-multiskill-cadence-fold
-- See REGRESSION_GUARDS.md for the default-behavior invariant.
-- Validation provenance is retained in maintainer notes.

describe("MinionMultiSkillCadenceFold #minioncadence data contract", function()

	it("data.minionSkillCadence carries the measured ManifestedArmor cadences", function()
		assert.is_table(data.minionSkillCadence, "data.minionSkillCadence must exist")
		local m = data.minionSkillCadence["ManifestedArmor"]
		assert.is_table(m, "ManifestedArmor cadence row must exist")
		-- keyed by grantedEffect.id (NOT the logged projectile name "Warpath")
		assert.are.equal(0.338, m["Manifest Armor 01 Melee"])
		assert.are.equal(0.467, m["ManifestArmorForgeBreath"])
		assert.are.equal(1.067, m["ManifestArmorWhirlwind"])
		assert.are.equal(0.419, m["ManifestArmorCharge"])
	end)

	it("the ManifestedArmor cadence table has exactly the 4 measured skills (no stray rows)", function()
		local m = data.minionSkillCadence["ManifestedArmor"]
		local n = 0
		for _ in pairs(m) do n = n + 1 end
		assert.are.equal(4, n)
	end)

	it("data.minionSkillCadence carries the two-capture-measured PrimalBear cadences", function()
		-- Validation provenance is retained in maintainer notes.
		local b = data.minionSkillCadence["PrimalBear"]
		assert.is_table(b, "PrimalBear cadence row must exist")
		assert.are.equal(0.548, b["PrimalBear 01 melee attack"])
		assert.are.equal(0.638, b["Swipe"])
		assert.are.equal(0.159, b["EarthquakeSlam"])
	end)

	it("the PrimalBear cadence table has exactly the 3 measured skills (no stray rows)", function()
		local b = data.minionSkillCadence["PrimalBear"]
		local n = 0
		for _ in pairs(b) do n = n + 1 end
		assert.are.equal(3, n)
	end)

	it("data.minionSkillCadence carries the measured SummonedAbomination cadences (Melee + gated Double Strike)", function()
		local a = data.minionSkillCadence["SummonedAbomination"]
		assert.is_table(a, "SummonedAbomination cadence row must exist")
		-- Melee = plain rate; keyed by grantedEffect.id
		assert.are.equal(0.635, a["Abomination Melee"])
		-- Double Strike = conditional form: only folds while a Warrior/Rogue is absorbed
		local ds = a["Abomination Double Strike"]
		assert.is_table(ds, "Double Strike must be the conditional { rate, requires } form")
		assert.are.equal(0.336, ds.rate)
		assert.are.equal("Multiplier:AbominationWarriorsOrRoguesAbsorbed", ds.requires)
	end)

	it("the SummonedAbomination cadence table has exactly the 2 boss-damaging skills (Devour excluded)", function()
		-- Validation provenance is retained in maintainer notes.
		local a = data.minionSkillCadence["SummonedAbomination"]
		local n = 0
		for _ in pairs(a) do n = n + 1 end
		assert.are.equal(2, n)
	end)

	it("every cadence is a positive rate -- a number, or a { rate, requires } conditional entry", function()
		for minion, tbl in pairs(data.minionSkillCadence) do
			for skillId, entry in pairs(tbl) do
				local ctx = minion .. "/" .. tostring(skillId)
				if type(entry) == "table" then
					-- conditional form: a granted sub-skill that only fires while a state
					-- multiplier is non-zero (e.g. abomination Double Strike per absorb)
					assert.is_true(type(entry.rate) == "number" and entry.rate > 0,
						ctx .. " conditional cadence must have a positive numeric rate")
					assert.is_true(type(entry.requires) == "string" and entry.requires ~= "",
						ctx .. " conditional cadence must name a `requires` multiplier")
				else
					assert.is_true(type(entry) == "number" and entry > 0,
						ctx .. " cadence must be a positive number")
				end
			end
		end
	end)
end)

describe("MinionMultiSkillCadenceFold #minioncadence config contract", function()

	it("exposes a default-ON `minionMultiSkillCadenceFold` check that flags the fold condition", function()
		local ConfigOptions = LoadModule("Modules/ConfigOptions")
		local opt
		for _, o in ipairs(ConfigOptions) do
			if type(o) == "table" and o.var == "minionMultiSkillCadenceFold" then opt = o end
		end
		assert.is_table(opt, "minionMultiSkillCadenceFold config option must exist")
		assert.are.equal("check", opt.type)
		-- DEFAULT ON: the fold is corpus-neutral even enabled (no corpus build includes a
		-- multi-skill Manifest Armor in Full DPS -> 0 fold), and the folded number beats the
		-- single-skill ~21% estimate. configTab reads `defaultState or false` for a check.
		assert.is_true(opt.defaultState == true,
			"the fold must default ON (defaultState == true)")

		-- checked -> sets the player-side Condition the fold reads (fullEnv.modDB:Flag)
		local set = {}
		local fakeModList = { NewMod = function(_, name, mtype, value) set[name] = { mtype, value } end }
		opt.apply(true, fakeModList, fakeModList)
		assert.is_table(set["Condition:MinionMultiSkillCadenceFold"],
			"checking the option must set Condition:MinionMultiSkillCadenceFold")

		-- unchecked -> sets nothing, so the fold block is skipped (conservative fallback)
		local set2 = {}
		local fakeModList2 = { NewMod = function(_, name) set2[name] = true end }
		opt.apply(false, fakeModList2, fakeModList2)
		assert.is_nil(set2["Condition:MinionMultiSkillCadenceFold"],
			"unchecking the option must set no condition (conservative single-skill fallback)")
	end)
end)
