-- @leb-regression-guard:no-vestigial-liferegen-burst-config
-- Locks the removal of the PoB-inherited "lifeRegenMode" config (burst life
-- regen: LifeRegenBurstAvg / LifeRegenBurstFull).
--
-- Why removed (2026-06-02 config-tab pipeline audit): LE life regeneration is
-- continuous — there is no "burst regen" mechanic. The config set
-- Condition:LifeRegenBurstAvg / LifeRegenBurstFull, but those conditions were
-- read NOWHERE in the calc (the PoB burst-regen pipeline was never ported to
-- LEB). Confirmed 0 references repo-wide outside ConfigOptions.lua. It was an
-- inert dropdown that changed nothing. Removing it (rather than wiring a
-- fabricated LE behaviour) is the no-PoE-in-LEB-correct action.
--
-- This guard fails if the vestigial config is re-introduced OR if the dead
-- burst-regen conditions reappear (e.g. a future PoB merge re-porting it).
-- See REGRESSION_GUARDS.md "no-vestigial-liferegen-burst-config".

describe("ConfigNoVestigialBurstRegen", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	it("ConfigOptions.lua no longer defines the lifeRegenMode config", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		assert.is_falsy(src:find('var = "lifeRegenMode"', 1, true),
			"lifeRegenMode is vestigial PoB burst-regen and must not be defined")
		assert.is_truthy(src:find("@leb%-regression%-guard:no%-vestigial%-liferegen%-burst%-config", 1, false),
			"the removal guard comment must remain as documentation")
	end)

	it("the dead burst-regen conditions are produced/consumed nowhere in src", function()
		-- These conditions had no consumer; if the "Condition:LifeRegenBurst*"
		-- mod string reappears (producer in ConfigOptions, or a :Flag/read in a
		-- calc module), the burst-regen pipeline is being re-ported (do not — LE
		-- regen is continuous). We match the "Condition:" form so this guard's
		-- own explanatory comment (which names the bare conditions) does not
		-- trip it.
		for _, glob in ipairs({
			"Modules/ConfigOptions.lua", "Modules/CalcDefence.lua",
			"Modules/CalcPerform.lua", "Modules/CalcOffence.lua",
		}) do
			local src = readFile(glob) or ""
			assert.is_falsy(src:find("Condition:LifeRegenBurstAvg", 1, true),
				glob .. " must not produce/consume Condition:LifeRegenBurstAvg")
			assert.is_falsy(src:find("Condition:LifeRegenBurstFull", 1, true),
				glob .. " must not produce/consume Condition:LifeRegenBurstFull")
		end
	end)

	it("ConfigOptions.lua still loads and the rest of the General section is intact", function()
		-- Sanity: removing the entry must not break the table (neighbouring
		-- configs survive). resourceGainMode follows lifeRegenMode's old slot.
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_truthy(src:find('var = "resourceGainMode"', 1, true),
			"the following config (resourceGainMode) must remain")
		assert.is_truthy(src:find('var = "conditionStationary"', 1, true),
			"earlier General configs must remain")
	end)
end)
