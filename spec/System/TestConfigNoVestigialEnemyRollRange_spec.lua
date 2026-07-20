-- @leb-regression-guard:no-vestigial-enemy-damage-roll-range
-- Locks the removal of the PoB-inherited "enemyDamageRollRange" config (boss
-- skill min-max damage roll %).
--
-- Why removed (2026-06-05 config-tab pipeline audit, Class B-3 reclassified):
-- it was doubly inert --
--   (1) gated by `ifFlag = "BossSkillActive"`, a flag NOTHING in LEB ever sets,
--       so the config never rendered in the UI; and
--   (2) its value was read NOWHERE in the calc -- LEB models enemy hit damage as
--       a single configured value per damage type (env.config.enemy<Type>Damage,
--       CalcDefence), with no min/max roll for a "roll range %" to interpolate.
-- The PoB boss-skill min-max-damage model it belongs to was never ported. The
-- only repo references were <Placeholder> values in saved build XMLs (harmless;
-- ignored on load once the config is gone). Removing it -- rather than building
-- that model and porting PoE boss-skill data, which violates no-PoE-in-LEB -- is
-- the consistent action, same class as lifeRegenMode.
--
-- This guard fails if the config OR its dead BossSkillActive gate is
-- re-introduced (e.g. a future PoB merge re-porting it).
-- See REGRESSION_GUARDS.md "no-vestigial-enemy-damage-roll-range".

describe("ConfigNoVestigialEnemyRollRange", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	it("ConfigOptions.lua no longer defines the enemyDamageRollRange config", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		assert.is_falsy(src:find('var = "enemyDamageRollRange"', 1, true),
			"enemyDamageRollRange is vestigial PoB boss-skill-roll and must not be defined")
		assert.is_truthy(src:find("@leb%-regression%-guard:no%-vestigial%-enemy%-damage%-roll%-range", 1, false),
			"the removal guard comment must remain as documentation")
	end)

	it("the dead BossSkillActive gate flag is used nowhere in the calc", function()
		-- BossSkillActive only ever appeared as enemyDamageRollRange's ifFlag and
		-- was never set; if it reappears in the calc, the boss-skill model is being
		-- re-ported. (ConfigOptions.lua is covered by the "config removed" test
		-- above; this guard's own explanatory comment legitimately names the flag,
		-- so we check the calc modules where it must never appear.)
		for _, glob in ipairs({
			"Modules/CalcDefence.lua", "Modules/CalcOffence.lua", "Modules/CalcSetup.lua",
		}) do
			local src = readFile(glob) or ""
			assert.is_falsy(src:find("BossSkillActive", 1, true),
				glob .. " must not reference the dead BossSkillActive gate flag")
		end
	end)

	it("ConfigOptions.lua still loads and neighbouring Enemy Stats configs are intact", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_truthy(src:find('var = "enemyArmour"', 1, true),
			"the preceding config (enemyArmour) must remain")
		assert.is_truthy(src:find('var = "enemySpeed"', 1, true),
			"the following config (enemySpeed) must remain")
		assert.is_truthy(src:find('var = "enemyCritChance"', 1, true),
			"sibling Enemy Stats configs must remain")
	end)
end)
