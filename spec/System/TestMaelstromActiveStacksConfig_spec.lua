-- @leb-regression-guard:maelstrom-active-stacks-config
-- Validation provenance is retained in maintainer notes.

describe("MaelstromActiveStacksConfig", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	it("CalcOffence carries the maelstrom-active-stacks-config guard marker", function()
		local src = readFile("Modules/CalcOffence.lua")
		assert.is_not_nil(src, "must read Modules/CalcOffence.lua")
		assert.is_truthy(src:find("@leb%-regression%-guard:maelstrom%-active%-stacks%-config"),
			"CalcOffence.lua must carry the maelstrom-active-stacks-config guard marker")
	end)

	it("overrides MaxStacks with the active-Maelstrom-stacks config for the Maelstrom skill only", function()
		local src = readFile("Modules/CalcOffence.lua")
		-- gated on the Maelstrom skill name + a positive config value
		assert.is_truthy(src:find('grantedEffect.name == "Maelstrom"', 1, true),
			"the override must be gated on the Maelstrom skill")
		assert.is_truthy(src:find('Multiplier:ActiveMaelstrom', 1, true),
			"the override must read the Multiplier:ActiveMaelstrom config value")
		assert.is_truthy(src:find("output.MaxStacks = cfgStacks", 1, true),
			"a positive config value must become output.MaxStacks for Maelstrom")
	end)

	it("the '# of Active Maelstrom Stacks' config option exists", function()
		local cfg = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(cfg, "must read Modules/ConfigOptions.lua")
		assert.is_truthy(cfg:find("multiplierActiveMaelstrom", 1, true),
			"the multiplierActiveMaelstrom config option must exist")
	end)
end)
