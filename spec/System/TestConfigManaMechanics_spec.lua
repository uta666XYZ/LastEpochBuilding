-- @leb-regression-guard:mana-missing-not-full-mechanics
-- Locks LE's mana-scaling mechanics, which LEB previously did not recognise at
-- all (ModParser had no "missing mana" / "not full mana" handling, and the
-- conditionFullMana/conditionLowMana configs set Condition:FullMana/LowMana that
-- NOTHING consumed).
--
-- LE reality (verified in src/Data, 2026-06-02): mana scaling is
--   * "Per N Missing Mana"  (absolute, e.g. "+1 Spell Damage per 5 Missing Mana")
--   * "Per N% Missing Mana" (percent,  e.g. "1% Increased Cast Speed per 2% Missing Mana")
--   * "While Not Full Mana"  (binary,  e.g. "+10% Damage While Not Full Mana")
-- There is NO "full mana" / "low mana" threshold-bonus affix in LE, so the old
-- full/low-mana checks were the wrong abstraction and were replaced by a single
-- "Your Missing Mana %" count (playerMissingManaPercent), mirroring
-- playerMissingHealthPercent. The static planner models full mana by default
-- (ModParser "per N current mana" guard), so all three are inert until the user
-- sets the config.
--
-- Wiring:
--   Config playerMissingManaPercent -> Multiplier:MissingManaPercent (+ Condition:NotFullMana when >0)
--   CalcPerform -> Multiplier:MissingMana = Mana x MissingManaPercent/100
--   ModParser modTagList -> per N missing mana / per N% missing mana / while not full mana
-- See REGRESSION_GUARDS.md "mana-missing-not-full-mechanics".

describe("ConfigManaMechanics", function()
	local function readFile(path)
		local f = io.open(path, "r"); if not f then return nil end
		local s = f:read("*a"); f:close(); return s
	end
	local function tagsOf(mod)
		local t = {}
		for _, tag in ipairs(mod) do t[#t+1] = tag end
		return t
	end
	local function findTag(mod, ttype)
		for _, tag in ipairs(mod) do if tag.type == ttype then return tag end end
		return nil
	end

	it("ModParser: 'while not full mana' -> Condition:NotFullMana tag", function()
		local list = modLib.parseMod("10% increased damage while not full mana")
		assert.is_not_nil(list); assert.is_true(#list >= 1)
		local tag = findTag(list[1], "Condition")
		assert.is_not_nil(tag, "must carry a Condition tag")
		assert.are.equal("NotFullMana", tag.var)
	end)

	it("ModParser: 'per N% missing mana' -> Multiplier:MissingManaPercent tag with div=N", function()
		local list = modLib.parseMod("10% increased damage per 2% missing mana")
		assert.is_not_nil(list); assert.is_true(#list >= 1)
		local tag = findTag(list[1], "Multiplier")
		assert.is_not_nil(tag, "must carry a Multiplier tag")
		assert.are.equal("MissingManaPercent", tag.var)
		assert.are.equal(2, tag.div)
	end)

	it("ModParser: 'per N missing mana' (absolute) -> PerStat MissingMana tag with div=N", function()
		-- Absolute is PerStat (reads output.MissingMana set idempotently in
		-- CalcPerform), NOT a Multiplier mod -- doActorLifeMana runs >1x per
		-- BuildOutput so an additive mod would double-count.
		local list = modLib.parseMod("10% increased damage per 5 missing mana")
		assert.is_not_nil(list); assert.is_true(#list >= 1)
		local tag = findTag(list[1], "PerStat")
		assert.is_not_nil(tag, "must carry a PerStat tag")
		assert.are.equal("MissingMana", tag.stat)
		assert.are.equal(5, tag.div)
	end)

	it("behaviour: 'while not full mana' gates on Condition:NotFullMana", function()
		local modDB = new("ModDB"); modDB.actor = { modDB = modDB }
		for _, m in ipairs(modLib.parseMod("10% increased damage while not full mana")) do modDB:AddMod(m) end
		assert.are.equal(0, modDB:Sum("INC", nil, "Damage"),
			"inactive when NotFullMana is unset (planner default = full mana)")
		modDB:NewMod("Condition:NotFullMana", "FLAG", true, "Test")
		assert.are.equal(10, modDB:Sum("INC", nil, "Damage"),
			"active when NotFullMana is set")
	end)

	it("behaviour: 'per N% missing mana' scales by Multiplier:MissingManaPercent/N", function()
		local modDB = new("ModDB"); modDB.actor = { modDB = modDB }
		for _, m in ipairs(modLib.parseMod("10% increased damage per 2% missing mana")) do modDB:AddMod(m) end
		assert.are.equal(0, modDB:Sum("INC", nil, "Damage"), "0 missing mana -> no effect")
		modDB:NewMod("Multiplier:MissingManaPercent", "BASE", 50, "Config")
		-- floor(50/2) = 25 stacks x 10 = 250
		assert.are.equal(250, modDB:Sum("INC", nil, "Damage"))
	end)

	it("behaviour: 'per N missing mana' scales by output.MissingMana/N (PerStat, continuous)", function()
		local modDB = new("ModDB"); modDB.actor = { modDB = modDB, output = { MissingMana = 100 } }
		for _, m in ipairs(modLib.parseMod("10% increased damage per 5 missing mana")) do modDB:AddMod(m) end
		-- 100/5 = 20 x 10 = 200 (PerStat is continuous, not floored)
		assert.are.equal(200, modDB:Sum("INC", nil, "Damage"))
	end)

	it("config: playerMissingManaPercent exists and sets the multiplier + NotFullMana; old full/low checks gone", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src)
		assert.is_truthy(src:find('var = "playerMissingManaPercent"', 1, true),
			"playerMissingManaPercent config must exist")
		assert.is_truthy(src:find("Multiplier:MissingManaPercent", 1, true),
			"config must set Multiplier:MissingManaPercent")
		assert.is_truthy(src:find("Condition:NotFullMana", 1, true),
			"config must set Condition:NotFullMana when missing mana > 0")
		assert.is_falsy(src:find('var = "conditionFullMana"', 1, true),
			"wrong-abstraction conditionFullMana must be removed")
		assert.is_falsy(src:find('var = "conditionLowMana"', 1, true),
			"wrong-abstraction conditionLowMana must be removed")
	end)

	it("calc: CalcPerform derives Multiplier:MissingMana from the config %", function()
		local src = readFile("Modules/CalcPerform.lua")
		assert.is_not_nil(src)
		assert.is_truthy(src:find("@leb%-regression%-guard:mana%-missing%-not%-full%-mechanics", 1, false),
			"CalcPerform must carry the guard marker")
		assert.is_truthy(src:find("output.MissingMana", 1, true),
			"CalcPerform must derive absolute output.MissingMana (idempotent assignment, not additive mod)")
	end)
end)
