-- @leb-regression-guard:scales-eterra-infusion
-- See REGRESSION_GUARDS.md "scales-eterra-infusion".
-- Validation provenance is retained in maintainer notes.

describe("ScalesOfEterraInfusion #config", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	it("config source: three per-element count configs, capped 10, own +10 MORE / cross -6 MORE", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")

		local fire = src:match('{ var = "multiplierFireInfusionStacks".-end },')
		assert.is_not_nil(fire, "multiplierFireInfusionStacks config entry must exist")
		assert.is_truthy(fire:find('type = "count"', 1, true))
		assert.is_truthy(fire:find("max 10", 1, true), "Fire label must carry the '(max 10)' cap hint")
		assert.is_truthy(fire:find("math.min(val, 10)", 1, true), "Fire apply must cap at 10")
		assert.is_truthy(fire:find('NewMod("FireDamage", "MORE", val * 10, "Fire Infusion")', 1, true),
			"Fire apply must emit own-element MORE FireDamage of val*10")
		assert.is_truthy(fire:find('NewMod("ColdDamage", "MORE", -val * 6, "Fire Infusion")', 1, true),
			"Fire apply must emit cross-element MORE ColdDamage of -val*6")
		assert.is_truthy(fire:find('NewMod("LightningDamage", "MORE", -val * 6, "Fire Infusion")', 1, true),
			"Fire apply must emit cross-element MORE LightningDamage of -val*6")

		local light = src:match('{ var = "multiplierLightningInfusionStacks".-end },')
		assert.is_not_nil(light, "multiplierLightningInfusionStacks config entry must exist")
		assert.is_truthy(light:find('NewMod("LightningDamage", "MORE", val * 10, "Lightning Infusion")', 1, true),
			"Lightning apply must emit own-element MORE LightningDamage of val*10")
		assert.is_truthy(light:find('NewMod("FireDamage", "MORE", -val * 6, "Lightning Infusion")', 1, true),
			"Lightning apply must emit cross-element MORE FireDamage of -val*6")
		assert.is_truthy(light:find('NewMod("ColdDamage", "MORE", -val * 6, "Lightning Infusion")', 1, true),
			"Lightning apply must emit cross-element MORE ColdDamage of -val*6")

		local cold = src:match('{ var = "multiplierColdInfusionStacks".-end },')
		assert.is_not_nil(cold, "multiplierColdInfusionStacks config entry must exist")
		assert.is_truthy(cold:find('NewMod("ColdDamage", "MORE", val * 10, "Cold Infusion")', 1, true),
			"Cold apply must emit own-element MORE ColdDamage of val*10")
		assert.is_truthy(cold:find('NewMod("FireDamage", "MORE", -val * 6, "Cold Infusion")', 1, true),
			"Cold apply must emit cross-element MORE FireDamage of -val*6")
		assert.is_truthy(cold:find('NewMod("LightningDamage", "MORE", -val * 6, "Cold Infusion")', 1, true),
			"Cold apply must emit cross-element MORE LightningDamage of -val*6")
	end)

	it("behaviour: Fire Infusion 0 no-op; N stacks -> +N*10% MORE fire, -N*6% each other; capped 10", function()
		newBuild()
		-- Re-read mainEnv.player.modDB on every call: each OnFrame recalc builds a
		-- fresh ModDB (CalcSetup env.modDB = new("ModDB")), so a captured reference
		-- would go stale (mirrors the B5 Dilation spec's meleeMore closure).
		local function fireMore() return build.calcsTab.mainEnv.player.modDB:More(nil, "FireDamage") end
		local function coldMore() return build.calcsTab.mainEnv.player.modDB:More(nil, "ColdDamage") end
		local function lightMore() return build.calcsTab.mainEnv.player.modDB:More(nil, "LightningDamage") end

		-- 0 stacks (default) -> no Infusion contribution
		build.configTab.input["multiplierFireInfusionStacks"] = 0
		build.configTab:BuildModList(); runCallback("OnFrame")
		local fire0, cold0, light0 = fireMore(), coldMore(), lightMore()

		-- 5 stacks -> +50% more fire (x1.5), -30% each other (x0.70)
		build.configTab.input["multiplierFireInfusionStacks"] = 5
		build.configTab:BuildModList(); runCallback("OnFrame")
		assert.are.equal(fire0 * 1.5, fireMore())
		assert.are.equal(cold0 * 0.7, coldMore())
		assert.are.equal(light0 * 0.7, lightMore())

		-- 10 stacks (cap) -> +100% more fire (x2.0), -60% each other (x0.40)
		build.configTab.input["multiplierFireInfusionStacks"] = 10
		build.configTab:BuildModList(); runCallback("OnFrame")
		assert.are.equal(fire0 * 2.0, fireMore())
		assert.are.equal(cold0 * 0.4, coldMore())
		assert.are.equal(light0 * 0.4, lightMore())

		-- 20 stacks -> still capped at 10 (x2.0 / x0.40)
		build.configTab.input["multiplierFireInfusionStacks"] = 20
		build.configTab:BuildModList(); runCallback("OnFrame")
		assert.are.equal(fire0 * 2.0, fireMore())
		assert.are.equal(cold0 * 0.4, coldMore())
		assert.are.equal(light0 * 0.4, lightMore())
	end)

	it("behaviour: Lightning / Cold Infusion are independent and scale their own element", function()
		newBuild()
		-- Compound cross-element cases stack two MORE mods on one element; the engine
		-- rounds each MORE group to 2 decimals (ModList:MoreInternal round(modResult, 2)),
		-- so e.g. 1.5*0.7 -> a clean 1.05 while raw float multiply gives 1.04999...; use
		-- a tolerance for the two-mod products (single-mod cases stay exact).
		local function near(expected, actual)
			assert.is_true(math.abs(expected - actual) < 1e-6,
				("expected ~%s, got %s"):format(tostring(expected), tostring(actual)))
		end
		local function fireMore() return build.calcsTab.mainEnv.player.modDB:More(nil, "FireDamage") end
		local function coldMore() return build.calcsTab.mainEnv.player.modDB:More(nil, "ColdDamage") end
		local function lightMore() return build.calcsTab.mainEnv.player.modDB:More(nil, "LightningDamage") end

		build.configTab.input["multiplierFireInfusionStacks"] = 0
		build.configTab.input["multiplierLightningInfusionStacks"] = 0
		build.configTab.input["multiplierColdInfusionStacks"] = 0
		build.configTab:BuildModList(); runCallback("OnFrame")
		local fire0, cold0, light0 = fireMore(), coldMore(), lightMore()

		-- Lightning Infusion 5 -> +50% lightning, -30% fire, -30% cold
		build.configTab.input["multiplierLightningInfusionStacks"] = 5
		build.configTab:BuildModList(); runCallback("OnFrame")
		assert.are.equal(light0 * 1.5, lightMore())
		assert.are.equal(fire0 * 0.7, fireMore())
		assert.are.equal(cold0 * 0.7, coldMore())

		-- Add Cold Infusion 5 on top -> cold own +50% stacks with lightning's -30% (x1.5*0.7),
		-- fire now hit by both lightning (-30%) and cold (-30%) -> x0.49
		build.configTab.input["multiplierColdInfusionStacks"] = 5
		build.configTab:BuildModList(); runCallback("OnFrame")
		near(cold0 * 1.5 * 0.7, coldMore())
		near(light0 * 1.5 * 0.7, lightMore())
		near(fire0 * 0.7 * 0.7, fireMore())
	end)

	it("grant mods stay no-ops (per-stack effect is config-driven, not from the item mod)", function()
		local mc = readFile("Data/ModCache.lua")
		assert.is_not_nil(mc, "must read Data/ModCache.lua")
		assert.is_truthy(mc:find('Gain Fire Infusion when you cast a fire spell"]={{},', 1, true),
			"the Fire Infusion grant line must stay an empty-modlist no-op")
		assert.is_truthy(mc:find('Gain Lightning Infusion when you cast a lightning spell"]={{},', 1, true),
			"the Lightning Infusion grant line must stay an empty-modlist no-op")
		assert.is_truthy(mc:find('Gain Cold Infusion when you cast a cold spell"]={{},', 1, true),
			"the Cold Infusion grant line must stay an empty-modlist no-op")
	end)
end)
