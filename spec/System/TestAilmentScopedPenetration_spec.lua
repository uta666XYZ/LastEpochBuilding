-- @leb-regression-guard:ailment-scoped-penetration
-- Locks the GENERAL ailment-scoped penetration channel and its Salt the Wound
-- (uniques_1_4.json #187) consumer.
--
-- Channel: a BASE mod named "Ailment<Name>Penetration" (e.g. AilmentBleedPenetration,
-- AilmentPoisonPenetration) adds penetration that applies ONLY to that ailment's DoT tick,
-- on TOP of the generic <type>/global penetration. It is summed solely inside
-- calcAilmentMitigation, gated on the ailmentName param that the ailment DPS loop passes --
-- so it can never reach the HIT loop (hits never call calcAilmentMitigation) nor another
-- ailment (the param differs).
--
-- Consumer: Salt the Wound carries two ailment-scoped conversions
--   "(40-50)% of added Critical Strike Multiplier Converted to Physical Penetration with Bleed"
--   "(40-50)% of added Critical Strike Multiplier Converted to Poison Penetration with Poison"
-- ModParser (un-baked from ModCache) emits a CritMultToAilmentPen LIST mod { ailment, pct };
-- CalcOffence reads the ADDED crit multiplier (playerExtra = BASE CritMultiplier, the
-- gear/passive bonus above the 100 skill base) and injects pct% of it as an
-- Ailment<Name>Penetration BASE mod.
--
-- Structural invariants locked here:
--   1. AilmentBleedPenetration raises the Bleed DoT (lowers enemy effective Physical resist
--      for Bleed only), does NOT touch a Physical HIT, does NOT touch a Poison ailment.
--   2. AilmentPoisonPenetration affects only the Poison DoT.
--   3. Salt the Wound text live-parses (un-baked) into a CritMultToAilmentPen LIST mod, and
--      with a known added CritMultiplier (BASE 40 -> playerExtra 40) and pct=45 it injects
--      penValue 18 (= 45/100 * 40) on the matching Ailment<Name>Penetration.
--   4. With NO conversion mod the ailment DoT is byte-identical to baseline (strict no-op).
--
-- See REGRESSION_GUARDS.md "ailment-scoped-penetration".

local function findTag(mod, ttype)
	for _, tag in ipairs(mod) do
		if tag.type == ttype then return tag end
	end
end

local function setMods(s)
	build.configTab.input.customMods = s
	build.configTab:BuildModList()
	runCallback("OnFrame")
end

-- Inject a synthetic BASE mod that the parser cannot produce from text (e.g. the
-- internal "Ailment<Name>Penetration" stat). Push it through configTab.modList so the
-- runCallback modDB rebuild propagates it; do NOT call BuildModList afterwards (that would
-- re-derive modList from customMods and wipe the injection). Mirrors the
-- TestPaladinSentinel95LifeRegen / TestLifeOnHit injection pattern.
local function injectMod(name, modType, value)
	build.configTab.modList:NewMod(name, modType, value, "Test")
	-- BuildModList already ran (via the preceding setMods) and populated configTab.modList
	-- from customMods; appending here keeps that text. Force a calc rebuild so BuildOutput
	-- re-reads the modList WITH the injected mod (OnFrame only rebuilds when buildFlag set,
	-- and it does NOT re-run BuildModList, so the appended mod survives).
	build.buildFlag = true
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

describe("AilmentScopedPenetration", function()
	before_each(function()
		newBuild()
		resetEnemy()
		-- A directly-cast spell with a non-zero cast speed so the ailment loop has a
		-- positive hit rate; Fireball is unrelated to the ailments we inject by config.
		build.skillsTab:SelSkill(1, "Fireball")
	end)

	-- Inject a generous ailment chance + ailment damage so the steady-state DoT is non-zero.
	local function bleedMods()
		return table.concat({
			"+100% chance to inflict Bleed",
			"+500 Bleed Damage",
		}, "\n")
	end
	local function poisonMods()
		return table.concat({
			"+100% chance to inflict Poison",
			"+500 Poison Damage",
		}, "\n")
	end

	---------------------------------------------------------------------------
	-- Source-text guard: the inline markers must remain (channel + consumer)
	---------------------------------------------------------------------------
	it("CalcOffence carries the channel + consumer inline guard markers", function()
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f)
		local text = f:read("*a"); f:close()
		assert.is_truthy(string.find(text, "@leb-regression-guard:ailment-scoped-penetration", 1, true),
			"inline guard ID must remain in CalcOffence.lua")
		assert.is_truthy(string.find(text, "CritMultToAilmentPen", 1, true),
			"the Salt the Wound consumer (CritMultToAilmentPen) must remain")
	end)

	it("ModParser carries the Salt the Wound parse-site guard marker", function()
		local f = io.open("Modules/ModParser.lua", "r") or io.open("src/Modules/ModParser.lua", "r")
		assert.is_not_nil(f)
		local text = f:read("*a"); f:close()
		assert.is_truthy(string.find(text, "@leb-regression-guard:ailment-scoped-penetration", 1, true),
			"inline parse-site guard ID must remain in ModParser.lua")
	end)

	---------------------------------------------------------------------------
	-- (a) AilmentBleedPenetration raises the Bleed DoT but not a Phys HIT nor Poison
	---------------------------------------------------------------------------
	it("AilmentBleedPenetration amplifies the Bleed DoT against a 0-resist enemy", function()
		setMods(bleedMods())
		local base = build.calcsTab.mainOutput.BleedDPS
		assert.is_truthy(base > 0, "Bleed DPS must be non-zero")
		assert.are.equals(1, build.calcsTab.mainOutput.BleedMitigation, "0 resist, 0 pen -> factor 1")

		-- +30 ailment-scoped Bleed penetration, 0 resist -> (1 - (0 - 30)/100) = 1.30
		injectMod("AilmentBleedPenetration", "BASE", 30)
		local o = build.calcsTab.mainOutput
		assert.is_near(1.30, o.BleedMitigation, 1e-6, "0 resist, 30 ailment-Bleed pen -> 1.30 factor (>1)")
		assert.is_near(base * 1.30, o.BleedDPS, base * 1.30 * 1e-4,
			"ailment-scoped Bleed penetration must amplify the Bleed DoT")
	end)

	it("AilmentBleedPenetration nets against Physical resistance like normal pen", function()
		setMods(bleedMods())
		local base = build.calcsTab.mainOutput.BleedDPS

		build.configTab.input.enemyPhysicalResist = 50
		setMods(bleedMods())
		injectMod("AilmentBleedPenetration", "BASE", 20)
		local o = build.calcsTab.mainOutput
		assert.is_near(0.70, o.BleedMitigation, 1e-6, "(1 - (50-20)/100) = 0.70")
		assert.is_near(base * 0.70, o.BleedDPS, base * 0.70 * 1e-4)
	end)

	it("AilmentBleedPenetration does NOT reach the HIT loop's penetration sum", function()
		-- The hit loop reads skillModList:Sum("BASE", cfg, "<Type>Penetration", "Penetration").
		-- An Ailment<Name>Penetration BASE mod is a distinctly-named stat, so it must NOT appear
		-- in that sum for ANY damage type -- it is summed solely inside calcAilmentMitigation.
		setMods(bleedMods())
		injectMod("AilmentBleedPenetration", "BASE", 50)
		local modDB = build.calcsTab.mainEnv.modDB
		assert.are.equals(0, modDB:Sum("BASE", nil, "PhysicalPenetration", "Penetration"),
			"ailment-scoped Bleed pen must not enter the Physical hit-pen sum")
		assert.are.equals(0, modDB:Sum("BASE", nil, "FirePenetration", "Penetration"),
			"ailment-scoped Bleed pen must not enter the Fire hit-pen sum")
		-- And it IS readable under its own scoped stat name (sanity: the mod did land).
		assert.are.equals(50, modDB:Sum("BASE", nil, "AilmentBleedPenetration"),
			"the ailment-scoped pen mod lands on its own distinctly-named stat")
	end)

	it("AilmentBleedPenetration does NOT change a Poison ailment", function()
		setMods(poisonMods())
		local basePoison = build.calcsTab.mainOutput.PoisonDPS
		assert.is_truthy((basePoison or 0) > 0, "Poison DPS must be non-zero")

		setMods(poisonMods())
		injectMod("AilmentBleedPenetration", "BASE", 50)
		local o = build.calcsTab.mainOutput
		assert.is_near(basePoison, o.PoisonDPS, basePoison * 1e-6,
			"Bleed-scoped pen must not leak into the Poison ailment")
		assert.are.equals(1, o.PoisonMitigation, "Poison mitigation untouched by a Bleed-scoped pen")
	end)

	---------------------------------------------------------------------------
	-- (b) AilmentPoisonPenetration affects only the Poison DoT
	---------------------------------------------------------------------------
	it("AilmentPoisonPenetration amplifies only the Poison DoT", function()
		setMods(poisonMods())
		local basePoison = build.calcsTab.mainOutput.PoisonDPS
		assert.is_truthy((basePoison or 0) > 0)

		setMods(poisonMods())
		injectMod("AilmentPoisonPenetration", "BASE", 30)
		local o = build.calcsTab.mainOutput
		assert.is_near(1.30, o.PoisonMitigation, 1e-6, "0 resist, 30 ailment-Poison pen -> 1.30 factor")
		assert.is_near(basePoison * 1.30, o.PoisonDPS, basePoison * 1.30 * 1e-4,
			"ailment-scoped Poison penetration must amplify the Poison DoT")
	end)

	it("AilmentPoisonPenetration does NOT change a Bleed ailment", function()
		setMods(bleedMods())
		local baseBleed = build.calcsTab.mainOutput.BleedDPS

		setMods(bleedMods())
		injectMod("AilmentPoisonPenetration", "BASE", 50)
		local o = build.calcsTab.mainOutput
		assert.is_near(baseBleed, o.BleedDPS, baseBleed * 1e-6,
			"Poison-scoped pen must not leak into the Bleed ailment")
		assert.are.equals(1, o.BleedMitigation, "Bleed mitigation untouched by a Poison-scoped pen")
	end)

	---------------------------------------------------------------------------
	-- (c) Salt the Wound text live-parses (un-baked) into CritMultToAilmentPen
	---------------------------------------------------------------------------
	it("Salt the Wound (Bleed) parses to a CritMultToAilmentPen LIST mod { Bleed, pct }", function()
		local mods, extra = modLib.parseMod("45% of added Critical Strike Multiplier Converted to Physical Penetration with Bleed")
		assert.is_nil(extra, "a fully-parsed Salt the Wound conversion must leave no residue")
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		local m = mods[1]
		assert.are.equals("CritMultToAilmentPen", m.name)
		assert.are.equals("LIST", m.type)
		assert.are.equals("Bleed", m.value.ailment)
		assert.are.equals(45, m.value.pct)
		assert.is_nil(findTag(m, "SkillName"), "Salt the Wound conversion is unconditional (no skill scope)")
		assert.is_nil(findTag(m, "Condition"), "Salt the Wound conversion is unconditional (no gate)")
	end)

	it("Salt the Wound (Poison) parses to a CritMultToAilmentPen LIST mod { Poison, pct }", function()
		local mods, extra = modLib.parseMod("45% of added Critical Strike Multiplier Converted to Poison Penetration with Poison")
		assert.is_nil(extra)
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		local m = mods[1]
		assert.are.equals("CritMultToAilmentPen", m.name)
		assert.are.equals("LIST", m.type)
		assert.are.equals("Poison", m.value.ailment)
		assert.are.equals(45, m.value.pct)
	end)

	it("Salt the Wound: NOT baked as LEB_NotSupported in ModCache (live-parses)", function()
		for _, str in ipairs({
			"45% of added Critical Strike Multiplier Converted to Physical Penetration with Bleed",
			"45% of added Critical Strike Multiplier Converted to Poison Penetration with Poison",
		}) do
			local mods = modLib.parseMod(str)
			assert.is_not_nil(mods)
			for _, m in ipairs(mods) do
				assert.are_not.equals("LEB_NotSupported", m.name,
					"the ModCache notSupported row must be removed so it live-parses: " .. str)
			end
		end
	end)

	---------------------------------------------------------------------------
	-- (c cont.) End-to-end: pct% of the ADDED crit multiplier -> Ailment pen value
	-- BASE CritMultiplier 40 (playerExtra 40), pct 45 -> penValue 18.
	---------------------------------------------------------------------------
	it("Salt the Wound (Bleed): 45% of added crit mult 40 -> +18 AilmentBleedPenetration on the Bleed DoT", function()
		-- Baseline Bleed DoT with the added crit mult but NO conversion.
		setMods(table.concat({
			bleedMods(),
			"+40% Critical Strike Multiplier",
		}, "\n"))
		local base = build.calcsTab.mainOutput.BleedDPS
		assert.is_truthy(base > 0)
		assert.are.equals(1, build.calcsTab.mainOutput.BleedMitigation,
			"no conversion yet -> Bleed mitigation is 1 (0 resist, 0 pen)")

		-- Add the Salt the Wound conversion: 45% of added crit mult (40) = 18 pen on Bleed.
		setMods(table.concat({
			bleedMods(),
			"+40% Critical Strike Multiplier",
			"45% of added Critical Strike Multiplier Converted to Physical Penetration with Bleed",
		}, "\n"))
		local o = build.calcsTab.mainOutput
		-- (1 - (0 - 18)/100) = 1.18 against a 0-resist enemy.
		assert.is_near(1.18, o.BleedMitigation, 1e-6, "45% of 40 = 18 pen -> 1.18 factor")
		assert.is_near(base * 1.18, o.BleedDPS, base * 1.18 * 1e-4,
			"the Salt the Wound Bleed conversion injects +18 Bleed-scoped penetration")
	end)

	it("Salt the Wound (Poison): 45% of added crit mult 40 -> +18 AilmentPoisonPenetration only on Poison", function()
		setMods(table.concat({
			poisonMods(),
			"+40% Critical Strike Multiplier",
			"45% of added Critical Strike Multiplier Converted to Poison Penetration with Poison",
		}, "\n"))
		local o = build.calcsTab.mainOutput
		assert.is_near(1.18, o.PoisonMitigation, 1e-6, "45% of 40 = 18 Poison pen -> 1.18 factor")
	end)

	it("Salt the Wound (Bleed) does NOT inject Poison penetration (ailment-scoped)", function()
		-- Equip ONLY the Bleed conversion, then check a Poison ailment is untouched.
		setMods(table.concat({
			poisonMods(),
			"+40% Critical Strike Multiplier",
			"45% of added Critical Strike Multiplier Converted to Physical Penetration with Bleed",
		}, "\n"))
		local o = build.calcsTab.mainOutput
		assert.are.equals(1, o.PoisonMitigation,
			"the Bleed-scoped Salt the Wound conversion must not touch the Poison DoT")
	end)

	---------------------------------------------------------------------------
	-- (d) No conversion mod -> ailment DoT identical to baseline (strict no-op)
	---------------------------------------------------------------------------
	it("no conversion / no ailment-pen mod -> Bleed DoT is identical to baseline", function()
		setMods(bleedMods())
		local a = build.calcsTab.mainOutput.BleedDPS
		assert.are.equals(1, build.calcsTab.mainOutput.BleedMitigation)

		-- Re-evaluate the same mods: byte-identical (the new consumer loop runs zero times).
		setMods(bleedMods())
		local b = build.calcsTab.mainOutput.BleedDPS
		assert.are.equals(a, b, "the ailment-scoped pen consumer is a strict no-op with no conversion")
		assert.are.equals(1, build.calcsTab.mainOutput.BleedMitigation)
	end)

	it("an added crit multiplier WITHOUT the conversion does not move any ailment pen", function()
		-- +40% Critical Strike Multiplier alone must NOT change the Bleed DoT: the
		-- conversion mod is what injects the pen, the crit mult by itself does nothing here.
		setMods(bleedMods())
		local base = build.calcsTab.mainOutput.BleedDPS

		setMods(bleedMods() .. "\n+40% Critical Strike Multiplier")
		local o = build.calcsTab.mainOutput
		assert.is_near(base, o.BleedDPS, base * 1e-6,
			"added crit multiplier alone must not change the Bleed DoT (no conversion equipped)")
		assert.are.equals(1, o.BleedMitigation)
	end)
end)
