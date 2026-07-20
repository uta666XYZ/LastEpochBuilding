-- @leb-regression-guard:dot-resist-pen-mitigation
-- See REGRESSION_GUARDS.md "dot-resist-pen-mitigation".
-- Validation provenance is retained in maintainer notes.

local function setMods(s)
	build.configTab.input.customMods = s
	build.configTab:BuildModList()
	runCallback("OnFrame")
end

local function resetEnemy()
	for _, k in ipairs({
		"enemyPhysicalResist", "enemyFireResist", "enemyColdResist",
		"enemyLightningResist", "enemyPoisonResist", "enemyNecroticResist",
		"enemyVoidResist", "enemyArmour",
	}) do
		build.configTab.input[k] = nil
	end
end

describe("DotResistPenMitigation", function()
	before_each(function()
		newBuild()
		resetEnemy()
		-- A directly-cast spell with a non-zero cast speed so the ailment loop has a
		-- positive hit rate; Fireball is unrelated to the ailments we inject by config.
		build.skillsTab:SelSkill(1, "Fireball")
	end)

	-- Inject a generous ailment chance + ailment damage so the steady-state DoT is
	-- non-zero, then read output.<Ailment>DPS / output.<Ailment>Mitigation.
	local function igniteMods()
		return table.concat({
			"+100% chance to inflict Ignite",
			"+500 Ignite Damage",
		}, "\n")
	end
	local function bleedMods()
		return table.concat({
			"+100% chance to inflict Bleed",
			"+500 Bleed Damage",
		}, "\n")
	end

	---------------------------------------------------------------------------
	-- Source-text guard: the inline marker + helper must remain
	---------------------------------------------------------------------------
	it("CalcOffence carries the inline regression-guard marker and the mitigation helper", function()
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f)
		local text = f:read("*a"); f:close()
		assert.is_truthy(string.find(text, "@leb-regression-guard:dot-resist-pen-mitigation", 1, true),
			"inline guard ID must remain in CalcOffence.lua")
		assert.is_truthy(string.find(text, "local function calcAilmentMitigation", 1, true),
			"the DoT mitigation helper must remain")
	end)

	---------------------------------------------------------------------------
	-- Baseline: 0-resist enemy, no penetration -> mitigation == 1 (no change)
	---------------------------------------------------------------------------
	it("0-resist enemy, no penetration -> Ignite mitigation is exactly 1", function()
		setMods(igniteMods())
		local o = build.calcsTab.mainOutput
		assert.is_truthy((o.IgniteDPS or 0) > 0, "Ignite DPS must be non-zero with chance+damage")
		assert.are.equals(1, o.IgniteMitigation, "0 resist, 0 pen -> factor 1")
	end)

	---------------------------------------------------------------------------
	-- Resistance reduces the DoT: factor = 1 - R/100
	---------------------------------------------------------------------------
	it("enemy Fire resistance reduces Ignite DoT by (1 - R/100)", function()
		-- baseline (0 resist)
		setMods(igniteMods())
		local base = build.calcsTab.mainOutput.IgniteDPS
		assert.is_truthy(base > 0)

		-- 50% fire resistance -> factor 0.5
		build.configTab.input.enemyFireResist = 50
		setMods(igniteMods())
		local o = build.calcsTab.mainOutput
		assert.is_near(0.5, o.IgniteMitigation, 1e-6, "50% resist -> 0.50 factor")
		assert.is_near(base * 0.5, o.IgniteDPS, base * 0.5 * 1e-4,
			"Ignite DoT must halve at 50% enemy Fire resistance")
	end)

	---------------------------------------------------------------------------
	-- Penetration amplifies the DoT (and past 100% when resist is 0)
	---------------------------------------------------------------------------
	it("Fire penetration amplifies Ignite DoT by (1 + pen/100) against a 0-resist enemy", function()
		setMods(igniteMods())
		local base = build.calcsTab.mainOutput.IgniteDPS

		-- +30 Fire Penetration, 0 resist -> (1 - (0 - 30)/100) = 1.30 (amplified > 1)
		setMods(igniteMods() .. "\n+30% Fire Penetration")
		local o = build.calcsTab.mainOutput
		assert.is_near(1.30, o.IgniteMitigation, 1e-6, "0 resist, 30 pen -> 1.30 factor (>1)")
		assert.is_near(base * 1.30, o.IgniteDPS, base * 1.30 * 1e-4,
			"penetration must amplify the DoT past 1x against a 0-resist enemy")
	end)

	it("penetration cancels resistance: 50 resist - 20 pen -> 0.70 factor", function()
		setMods(igniteMods())
		local base = build.calcsTab.mainOutput.IgniteDPS

		build.configTab.input.enemyFireResist = 50
		setMods(igniteMods() .. "\n+20% Fire Penetration")
		local o = build.calcsTab.mainOutput
		assert.is_near(0.70, o.IgniteMitigation, 1e-6, "(1 - (50-20)/100) = 0.70")
		assert.is_near(base * 0.70, o.IgniteDPS, base * 0.70 * 1e-4,
			"resist minus pen must net 30% mitigation")
	end)

	---------------------------------------------------------------------------
	-- Resistance term is capped at EnemyMaxResist (75); pen is uncapped
	---------------------------------------------------------------------------
	it("resistance term is capped at data.misc.EnemyMaxResist (75)", function()
		setMods(igniteMods())
		local base = build.calcsTab.mainOutput.IgniteDPS

		-- request 90% resist -> capped to 75 -> factor 0.25 (NOT 0.10)
		build.configTab.input.enemyFireResist = 90
		setMods(igniteMods())
		local o = build.calcsTab.mainOutput
		assert.is_near(0.25, o.IgniteMitigation, 1e-6, "90% requested -> capped at 75 -> 0.25 factor")
		assert.is_near(base * 0.25, o.IgniteDPS, base * 0.25 * 1e-4)
	end)

	---------------------------------------------------------------------------
	-- ARMOUR must NOT affect DoT (opt-in stat, not modelled) -- the key test
	---------------------------------------------------------------------------
	it("enemy ARMOUR does not change a Physical ailment (Bleed) -- armour is deferred", function()
		setMods(bleedMods())
		local noArmour = build.calcsTab.mainOutput.BleedDPS
		assert.is_truthy(noArmour > 0, "Bleed DPS must be non-zero")
		assert.are.equals(1, build.calcsTab.mainOutput.BleedMitigation,
			"no resist/pen/armour -> Bleed factor 1")

		-- huge armour -- a HIT would be heavily reduced, a DoT must be untouched
		build.configTab.input.enemyArmour = 100000
		setMods(bleedMods())
		local withArmour = build.calcsTab.mainOutput
		assert.are.equals(1, withArmour.BleedMitigation,
			"armour must not enter the DoT mitigation factor")
		assert.is_near(noArmour, withArmour.BleedDPS, noArmour * 1e-4,
			"Bleed DoT must be identical with and without enemy armour")
	end)

	it("Physical ailment (Bleed) IS reduced by Physical RESISTANCE (not armour)", function()
		setMods(bleedMods())
		local base = build.calcsTab.mainOutput.BleedDPS

		build.configTab.input.enemyPhysicalResist = 40
		setMods(bleedMods())
		local o = build.calcsTab.mainOutput
		assert.is_near(0.60, o.BleedMitigation, 1e-6, "40% physical resist -> 0.60 factor")
		assert.is_near(base * 0.60, o.BleedDPS, base * 0.60 * 1e-4,
			"Bleed must scale with Physical RESISTANCE")
	end)

	---------------------------------------------------------------------------
	-- Per-type: each ailment uses its OWN damage type's resistance
	---------------------------------------------------------------------------
	it("Cold resistance does not affect an Ignite (Fire) DoT -- per-type isolation", function()
		setMods(igniteMods())
		local base = build.calcsTab.mainOutput.IgniteDPS

		build.configTab.input.enemyColdResist = 75
		setMods(igniteMods())
		local o = build.calcsTab.mainOutput
		assert.are.equals(1, o.IgniteMitigation, "Cold resist must not touch a Fire ailment")
		assert.is_near(base, o.IgniteDPS, base * 1e-4)
	end)
end)
