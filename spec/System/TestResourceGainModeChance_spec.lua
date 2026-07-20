-- @leb-regression-guard:resource-gain-mode-chance-averaging
-- Locks the resourceGainMode (Min/Average/Max) wiring for chance-based ward
-- gain, adopting PoB's emit-two-gated-mods pattern.
--
-- Before (config-tab audit, Class B-2): the chance-based ward affixes
--   "X% Chance to Gain Y Ward when Hit"  /  "...on Melee Hit"
-- parsed to ChanceToGainWardWhenHit + WardGainedWhenHit, which NOTHING consumed
-- (silent drop). The resourceGainMode config (Min/Average/Max) set
-- Condition:AverageResourceGain / MaxResourceGain that ALSO nothing read, and
-- its ifCond="AverageResourceGain" visibility gate never passed (config hidden).
--
-- Fix (PoB pattern, ModParser): emit the gain into the consumed/displayed output
-- WardOnHit TWICE, each gated by a mode condition:
--   Average -> amount * chance/100        (Condition:AverageResourceGain)
--   Max     -> amount * ceil(chance/100)  (Condition:MaxResourceGain)  [>100% => multiple certain procs]
--   Min     -> neither condition set => 0
-- output.WardOnHit (CalcDefence) sums these; resourceGainMode picks the mode via
-- the conditions. This also auto-fixes the visibility gate (AverageResourceGain
-- is now an emitted tag). output.WardOnHit is DISPLAY-only (Calcs panel), not
-- used by EHP/DPS -> display-correctness fix, zero DPS/EHP impact.
-- See REGRESSION_GUARDS.md "resource-gain-mode-chance-averaging".

describe("ResourceGainModeChance", function()
	local function readFile(path)
		local f = io.open(path, "r"); if not f then return nil end
		local s = f:read("*a"); f:close(); return s
	end
	-- Parse the affix, add to a fresh ModDB, optionally set the mode condition,
	-- return summed WardOnHit (what output.WardOnHit reads).
	local function wardOnHit(modText, condVar)
		local modDB = new("ModDB"); modDB.actor = { modDB = modDB }
		local list = modLib.parseMod(modText)
		assert.is_not_nil(list, "parseMod returned nil for: " .. modText)
		for _, m in ipairs(list) do modDB:AddMod(m) end
		if condVar then modDB:NewMod("Condition:" .. condVar, "FLAG", true, "Test") end
		return modDB:Sum("BASE", nil, "WardOnHit"), list
	end

	it("'ward when hit': Min=0 / Average=amount*chance/100 / Max=amount", function()
		-- "20% chance to gain 30 ward when hit"
		assert.are.equal(0,  (wardOnHit("20% chance to gain 30 ward when hit", nil)),                  "Min (no mode) = 0")
		assert.are.equal(6,  (wardOnHit("20% chance to gain 30 ward when hit", "AverageResourceGain")),"Average = 30*20/100 = 6")
		assert.are.equal(30, (wardOnHit("20% chance to gain 30 ward when hit", "MaxResourceGain")),    "Max = 30 (one certain proc)")
	end)

	it("'ward on melee hit': same mode gating into WardOnHit", function()
		-- "25% chance to gain 40 ward on melee hit"
		assert.are.equal(0,  (wardOnHit("25% chance to gain 40 ward on melee hit", nil)))
		assert.are.equal(10, (wardOnHit("25% chance to gain 40 ward on melee hit", "AverageResourceGain")), "40*25/100 = 10")
		assert.are.equal(40, (wardOnHit("25% chance to gain 40 ward on melee hit", "MaxResourceGain")))
	end)

	it(">100% chance: Average scales past amount, Max = amount*ceil(chance/100)", function()
		-- "150% chance to gain 20 ward when hit" (LE allows >100% chance)
		assert.are.equal(30, (wardOnHit("150% chance to gain 20 ward when hit", "AverageResourceGain")), "20*150/100 = 30")
		assert.are.equal(40, (wardOnHit("150% chance to gain 20 ward when hit", "MaxResourceGain")),     "20*ceil(1.5) = 20*2 = 40")
	end)

	it("'ward on kill' routes to WardOnKill (not WardOnHit), mode-gated", function()
		local function killWard(condVar, sumName)
			local modDB = new("ModDB"); modDB.actor = { modDB = modDB }
			for _, m in ipairs(modLib.parseMod("100% chance to gain 20 ward on kill")) do modDB:AddMod(m) end
			if condVar then modDB:NewMod("Condition:" .. condVar, "FLAG", true, "Test") end
			return modDB:Sum("BASE", nil, sumName)
		end
		assert.are.equal(20, killWard("AverageResourceGain", "WardOnKill"), "100%*20 -> WardOnKill 20")
		assert.are.equal(0,  killWard("AverageResourceGain", "WardOnHit"),  "must NOT leak into WardOnHit")
		assert.are.equal(0,  killWard(nil, "WardOnKill"),                   "Min (no mode) -> 0")
	end)

	it("emits gated WardOnHit mods, NOT the old silently-dropped ChanceToGainWardWhenHit", function()
		local _, list = wardOnHit("20% chance to gain 30 ward when hit", nil)
		local names = {}
		for _, m in ipairs(list) do names[m.name] = true end
		assert.is_truthy(names["WardOnHit"], "must emit WardOnHit (consumed/displayed output)")
		assert.is_falsy(names["ChanceToGainWardWhenHit"], "must NOT emit the old unconsumed ChanceToGainWardWhenHit")
		assert.is_falsy(names["WardGainedWhenHit"], "must NOT emit the old unconsumed WardGainedWhenHit")
		-- both emitted mods carry a Condition tag (Average / Max)
		local condVars = {}
		for _, m in ipairs(list) do
			for _, tag in ipairs(m) do if tag.type == "Condition" then condVars[tag.var] = true end end
		end
		assert.is_truthy(condVars["AverageResourceGain"], "one mod gated by AverageResourceGain")
		assert.is_truthy(condVars["MaxResourceGain"], "one mod gated by MaxResourceGain")
	end)

	it("config + ModParser source wiring present", function()
		local cfg = readFile("Modules/ConfigOptions.lua")
		assert.is_truthy(cfg:find('var = "resourceGainMode"', 1, true), "resourceGainMode config must exist")
		assert.is_truthy(cfg:find("Condition:AverageResourceGain", 1, true), "config must set AverageResourceGain")
		assert.is_truthy(cfg:find("Condition:MaxResourceGain", 1, true), "config must set MaxResourceGain")
		local mp = readFile("Modules/ModParser.lua")
		assert.is_truthy(mp:find("@leb%-regression%-guard:resource%-gain%-mode%-chance%-averaging", 1, false),
			"ModParser must carry the guard marker")
	end)
end)
