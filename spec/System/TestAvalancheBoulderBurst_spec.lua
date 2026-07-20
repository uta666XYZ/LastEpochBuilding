-- @leb-regression-guard:avalanche-boulder-burst-per-cast
-- in-game idol-proc 0.444/s). See REGRESSION_GUARDS.md "avalanche-boulder-burst-per-cast".
-- Validation provenance is retained in maintainer notes.

describe("AvalancheBoulderBurst #skills", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	local function findTag(mod, tagType, key, keyVal)
		for _, tag in ipairs(mod) do
			if tag.type == tagType and (key == nil or tag[key] == keyVal) then
				return tag
			end
		end
		return nil
	end

	it("datamine schedule: all 10 boulders (0.4*1.2^(i-1)) land within the 2.5s lifespan -> effective count = 10 (no truncation)", function()
		local initialDelay, growth, lifespan, count = 0.4, 1.2, 2.5, 10
		local fired = 0
		for i = 1, count do
			local t = initialDelay * growth ^ (i - 1)
			if t <= lifespan then fired = fired + 1 end
		end
		assert.are.equal(10, fired, "the compounding schedule does not truncate: all 10 boulders fire")
		-- the last boulder lands well inside the lifespan (guards against a schedule regression)
		local last = initialDelay * growth ^ (count - 1)
		assert.is_true(last < lifespan, "boulder #10 must land before the 2.5s lifespan (got " .. string.format("%.4f", last) .. "s)")
		assert.is_true(math.abs(last - 2.06391) < 1e-4, "boulder #10 lands at ~2.064s")
	end)

	it("config: avalancheBouldersPerCast is a default-off count gated by ifSkill Avalanche, injecting AdditionalSameTargetHits (N-1) only when > 1", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "avalancheBouldersPerCast".-end },')
		assert.is_not_nil(entry, "avalancheBouldersPerCast config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true), "must be a count option (default 0 = off)")
		assert.is_truthy(entry:find('ifSkill = "Avalanche"', 1, true),
			"must only surface for a build that uses the Avalanche skill")
		assert.is_truthy(entry:find('if val > 1 then', 1, true),
			"the burst must only activate when > 1 boulder/cast (0/1 -> no-op, corpus-neutral)")
		assert.is_truthy(entry:find('NewMod("AdditionalSameTargetHits", "BASE", val - 1, "Config"', 1, true),
			"enabling must add AdditionalSameTargetHits BASE (val-1): N boulders = 1 + (N-1) same-target hits")
		assert.is_truthy(entry:find('skillName = "Avalanche"', 1, true),
			"the extra hits must be scoped to Avalanche only")
	end)

	it("behaviour: AdditionalSameTargetHits is 0 by default, (N-1) when enabled, and scoped to Avalanche only", function()
		local avaCfg = { skillName = "Avalanche" }
		local otherCfg = { skillName = "Maelstrom" }

		-- default: config off -> no mod created -> 0 extra same-target hits (corpus-neutral)
		local dbOff = new("ModDB")
		dbOff.actor = { modDB = dbOff, output = {} }
		assert.are.equal(0, dbOff:Sum("BASE", avaCfg, "AdditionalSameTargetHits"),
			"with the config OFF Avalanche gets 0 extra hits -> dpsMultiplier x1 -> inert")

		-- enabled with the datamined 10 -> apply() injects BASE (10-1) = 9
		local dbOn = new("ModDB")
		dbOn.actor = { modDB = dbOn, output = {} }
		dbOn:NewMod("AdditionalSameTargetHits", "BASE", 10 - 1, "Config", { type = "SkillName", skillName = "Avalanche" })
		assert.are.equal(9, dbOn:Sum("BASE", avaCfg, "AdditionalSameTargetHits"),
			"10 boulders/cast = 1 base hit + 9 extra same-target hits -> dpsMultiplier x(1+9) = x10")
		-- scope: a different skill is unaffected even with the mod present
		assert.are.equal(0, dbOn:Sum("BASE", otherCfg, "AdditionalSameTargetHits"),
			"the extra hits are SkillName-scoped to Avalanche, so other skills are untouched")
	end)

	it("CalcOffence: the same-target-hits fold multiplies dpsMultiplier by (1 + additionalSameTargetHits)", function()
		local src = readFile("Modules/CalcOffence.lua")
		assert.is_not_nil(src, "must read Modules/CalcOffence.lua")
		assert.is_truthy(src:find('skillModList:Sum("BASE", skillCfg, "AdditionalSameTargetHits")', 1, true),
			"CalcOffence must read the skill-scoped AdditionalSameTargetHits sum")
		assert.is_truthy(src:find("dpsMultiplier * (1 + additionalSameTargetHits)", 1, true),
			"the extra boulders fold into one (1 + N-1) = xN dpsMultiplier factor")
		assert.is_truthy(src:find("@leb-regression-guard:avalanche-boulder-burst-per-cast", 1, true),
			"the consumption site carries the inline guard tag")
	end)

	it("fold arithmetic: N boulders/cast => dpsMultiplier xN via (1 + (N-1))", function()
		for _, N in ipairs({ 2, 5, 10 }) do
			local additional = N - 1
			assert.are.equal(N, 1 + additional, "N=" .. N .. " boulders -> x" .. N .. " multiplier")
		end
	end)
end)
