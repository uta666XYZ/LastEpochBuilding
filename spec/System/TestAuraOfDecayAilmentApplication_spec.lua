-- @leb-regression-guard:aura-of-decay-ailment-application
-- @leb-regression-guard:aura-of-decay-ailment-frequency
-- See REGRESSION_GUARDS.md "aura-of-decay-ailment-application" / "aura-of-decay-ailment-frequency".
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
	local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
	assert.is_not_nil(f, "must be able to open " .. relPath)
	local text = f:read("*a"); f:close()
	return text
end

describe("aura-of-decay-ailment-application: behaviour (functional)", function()
	-- NOTE on the harness: SelSkill builds a bare granted effect WITHOUT the skill's
	-- intrinsic stats (no leveled gem), so the innate ChanceToTriggerOnHit_Ailment_
	-- Poison=100 is NOT present here -- it is locked instead by the skills.json
	-- game-file assertion + the documented Dicey_LEB / Dicey_blank real-save
	-- validations. These tests inject bleed/poison chance via customMods to exercise
	-- the reroute, 75%-effectiveness and attack-scope logic directly.
	before_each(function()
		newBuild()
	end)

	local function buildAoD(extraMods)
		newBuild()
		build.configTab.input.customMods = extraMods or ""
		build.configTab:BuildModList()
		build.skillsTab:SelSkill(1, "Aura Of Decay")
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainEnv.player.output
	end

	local BLOOD_FONT = " Poison -> Physical" -- Blood Font marker => PoisonDamageConvertToPhysical=100

	it("UNCONDITIONAL: the datamined 4/s aura rate applies with NO config toggle set (replaces the old default-off gate)", function()
		-- Was: "config OFF (default) => no HitSpeed override, 0 ailment DPS".
		-- Now the model is always on, so a fresh build with no config input gets the rate.
		local o = buildAoD("")
		assert.are.equal(4, o.HitSpeed, "aura application rate must be 4/s with no config set")
	end)

	it("UNCONDITIONAL: Blood Font + bleed chance produces ailment DPS with no config toggle set", function()
		-- Was: "config OFF + Blood Font => still 0 DPS (corpus-neutral)". Inverted on purpose.
		local o = buildAoD(BLOOD_FONT .. "\n+40% chance to inflict Bleed")
		assert.is_true((o.BleedDPS or 0) > 0, "AoD must produce bleed DPS without any config opt-in")
	end)

	it("Blood Font: player NON-attack bleed chance applies at 75% effectiveness, poison zeroed", function()
		-- innate is 0 in this bare-skill harness, so BleedChance = 0 + 40*0.75 = 30.
		-- (With the real intrinsic 100% innate it is 100 + 40*0.75, capped 100.)
		local o = buildAoD(BLOOD_FONT .. "\n+40% chance to inflict Bleed")
		assert.is_true(math.abs((o.BleedChance or 0) - 30) < 1e-9,
			"40% non-attack bleed chance must apply at 75% effectiveness = 30 (no double-count with the L2535 base)")
		assert.are.equal(0, o.PoisonChance, "poison is rerouted to bleed under Blood Font")
		assert.is_true((o.BleedDPS or 0) > 0, "converted AoD must produce bleed DPS")
		assert.is_true((o.PoisonDPS or 0) == 0, "no poison DPS once converted")
	end)

	it("Blood Font: attack-scoped gear bleed chance is INERT on the aura (matches capture: chance!=132)", function()
		-- AoD's cfg carries no Attack flag, so "chance to bleed on hit with attacks"
		-- never reaches the aura even under Blood Font.
		local o = buildAoD(BLOOD_FONT .. "\n43% chance to Bleed on Hit with Attacks")
		assert.are.equal(0, o.BleedChance,
			"attack-scoped gear bleed chance must contribute 0 to AoD (the capture needs the innate alone, not +43x0.75)")
	end)

	it("NO Blood Font: applies POISON (unconverted case) at 4/s", function()
		local o = buildAoD("+50% chance to inflict Poison")
		assert.are.equal(4, o.HitSpeed, "aura application rate must be 4/s")
		assert.is_true((o.PoisonChance or 0) > 0, "unconverted AoD applies poison")
		assert.is_true((o.BleedChance or 0) == 0, "no bleed reroute without Blood Font")
		assert.is_true((o.PoisonDPS or 0) > 0, "unconverted AoD must produce poison DPS")
	end)

	it("HONESTY LOCK: HitSpeed must NOT create phantom hit DPS (AoD has no base hit)", function()
		local o = buildAoD(BLOOD_FONT .. "\n+40% chance to inflict Bleed")
		assert.are.equal(0, o.AverageHit or 0, "AoD has no base hit -> AverageHit stays 0")
		assert.are.equal(0, o.AverageDamage or 0, "AoD has no base hit -> AverageDamage stays 0")
		assert.are.equal(0, o.TotalDPS or 0, "no hit -> TotalDPS (hit path) stays 0; all damage is the ailment")
	end)
end)

describe("aura-of-decay-ailment-frequency: behaviour (functional)", function()
	before_each(function()
		newBuild()
	end)

	local function buildAoD(extraMods)
		newBuild()
		build.configTab.input.customMods = extraMods or ""
		build.configTab:BuildModList()
		build.skillsTab:SelSkill(1, "Aura Of Decay")
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainEnv.player.output
	end

	it("★ NO frequency nodes => rate is EXACTLY the base 4/s (pins both capture-validated builds)", function()
		-- Dicey_LEB (bleed, -3.8%) and Dicey_blank (poison, -3.2%) have ZERO frequency
		-- nodes. If the frequency term ever leaks a non-zero default, both validations
		-- move and this fails. This is the regression check that frequency does not
		-- silently rescale builds that should not get it.
		local o = buildAoD("")
		assert.are.equal(4, o.HitSpeed, "with no Ailment Frequency the rate must be exactly 4/s, not 4*(1+x)")
	end)

	it("scales the aura rate: HitSpeed = 4 * (1 + freq/100)", function()
		-- +24% = Rot Weaver (ad0ry-2, +8%/pt) at its 3-point max.
		local o = buildAoD("+24% Ailment Frequency")
		assert.is_true(math.abs((o.HitSpeed or 0) - 4.96) < 1e-9, "4 * 1.24 = 4.96")
	end)

	it("frequency sources are ADDITIVE with each other (not a product of per-node multipliers)", function()
		-- Rot Weaver 3pt (+24%) + Mana Blight 3pt (+36%) + Poisoned Soul (+50%) = +110%.
		-- Additive => 4 * 2.10 = 8.4/s.  (A product would give 4*1.24*1.36*1.5 = 10.18.)
		local o = buildAoD("+24% Ailment Frequency\n+36% Ailment Frequency\n+50% Ailment Frequency")
		assert.is_true(math.abs((o.HitSpeed or 0) - 8.4) < 1e-9,
			"additive stacking: 4 * (1 + (24+36+50)/100) = 8.4")
	end)

	it("more frequency => proportionally more ailment DPS (rate drives ailment stacks)", function()
		local base = buildAoD("+50% chance to inflict Poison")
		local fast = buildAoD("+50% chance to inflict Poison\n+50% Ailment Frequency")
		assert.is_true((base.PoisonDPS or 0) > 0, "baseline must produce poison DPS")
		assert.is_true(math.abs((fast.PoisonDPS or 0) / (base.PoisonDPS or 1) - 1.5) < 1e-6,
			"+50% Ailment Frequency must scale the ailment DPS by exactly 1.5 via the stack count")
	end)
end)

describe("aura-of-decay-ailment-frequency: parser + cache locks", function()
	it("parses the verbatim node texts to AilmentFrequency BASE (percent)", function()
		-- These are the exact per-point strings on the three ad0ry nodes.
		local cases = { ["+8% Ailment Frequency"] = 8, ["+12% Ailment Frequency"] = 12, ["+50% Ailment Frequency"] = 50 }
		for line, expected in pairs(cases) do
			local list, extra = modLib.parseMod(line)
			assert.is_not_nil(list, "must parse: " .. line)
			assert.is_true(#list == 1, "exactly one mod from: " .. line)
			assert.are.equal("AilmentFrequency", list[1].name, "mod name for: " .. line)
			assert.are.equal("BASE", list[1].type, "mod type for: " .. line)
			assert.are.equal(expected, list[1].value, "mod value for: " .. line)
			assert.is_true(not extra or extra == "", "no unparsed residue for: " .. line ..
				" (a NON-EMPTY residue makes PassiveTree drop the mod -- the exact stale-ModCache " ..
				"failure this locks: Data/ModCache.lua rows short-circuit modLib.parseMod, so an " ..
				"empty baked row shadows the parser rule at 1 allocated point while the uncached " ..
				"rank-scaled line parses live)")
		end
	end)

	it("parses rank-scaled lines identically (PassiveTree multiplies the value by node.alloc BEFORE parseMod)", function()
		-- Rot Weaver at 3 points is rewritten to "+24% Ailment Frequency" before parsing.
		local list, extra = modLib.parseMod("+24% Ailment Frequency")
		assert.is_not_nil(list)
		assert.are.equal("AilmentFrequency", list[1].name)
		assert.are.equal(24, list[1].value)
		assert.is_true(not extra or extra == "", "no residue on the rank-scaled line")
	end)

	it("NO-LEAK: property 5056's other display texts stay unmapped/inert", function()
		-- The datamined property id 5056 is a GENERIC "frequency" property reused across
		-- unrelated trees. The parse is keyed on the TEXT "Ailment Frequency" precisely so
		-- these never gain an AilmentFrequency mod (they have no rate model at all).
		local others = {
			"+35% Lightning Frequency",              -- to50-6 Frequent Lightning
			"+12% Shurikens Frequency",              -- bl5st-7 Surge of Steel
			"+20% Superconductor Frequency",         -- arcas-17 Closed Circuit
			"+30% Explosive Ground Frequency",       -- vo54-13 Tectonic Orb
			"2% Aura of Decay More Ailment Frequency", -- fl44-8 Open Wounds (conditional MORE, out of scope)
		}
		for _, line in ipairs(others) do
			local list = modLib.parseMod(line)
			local found = false
			for _, m in ipairs(list or {}) do
				if m.name == "AilmentFrequency" then found = true end
			end
			assert.is_false(found, "must NOT emit AilmentFrequency: " .. line)
		end
	end)
end)

describe("aura-of-decay-ailment-application: source + game-file locks", function()
	it("skills.json: AuraOfDecay keeps its innate poison-application stat (a retune should fail loudly)", function()
		local src = readSource("Data/skills.json")
		local aod = src:match('"AuraOfDecay"%s*:%s*(%b{})')
		assert.is_not_nil(aod, "AuraOfDecay entry must exist in skills.json")
		assert.is_truthy(aod:find('"chance_to_cast_Ailment_Poison_on_hit_%%"', 1, false),
			"the innate ailment-application stat the fix keys on must remain")
	end)

	it("tree: Blood Font (ad0ry-8) still carries the Poison->Physical conversion + 75% bleed effectiveness", function()
		local src = readSource("TreeData/1_4/tree_3.json")
		assert.is_truthy(src:find("Blood Font", 1, true), "Blood Font node name must remain")
		assert.is_truthy(src:find("Poison %-> Physical", 1, false), "Blood Font's Poison->Physical conversion must remain")
		assert.is_truthy(src:find("75%% Bleed Chance Effectiveness", 1, false),
			"Blood Font's 75% bleed-chance-effectiveness stat must remain")
	end)

	it("tree: the three AoD Ailment Frequency nodes keep their datamined verbatim texts", function()
		-- Datamine: skill_trees_raw.json trees.ad0ry -- ad0ry-2 Rot Weaver +8% (maxPoints 3),
		-- ad0ry-5 Mana Blight +12% (maxPoints 3), ad0ry-6 Poisoned Soul +50% (maxPoints 1).
		-- The parse is text-keyed, so a text change silently zeroes the rate scaling.
		local src = readSource("TreeData/1_4/tree_3.json")
		for _, line in ipairs({ "+8% Ailment Frequency", "+12% Ailment Frequency", "+50% Ailment Frequency" }) do
			assert.is_truthy(src:find(line, 1, true), "tree must still carry the verbatim stat: " .. line)
		end
	end)

	it("ConfigOptions: the auraOfDecayAilmentApplication gate is GONE (removal is intentional, not a regression)", function()
		local src = readSource("Modules/ConfigOptions.lua")
		assert.is_nil(src:match('{ var = "auraOfDecayAilmentApplication"'),
			"the AoD config gate must NOT be re-added: AoD's application is the skill's only damage " ..
			"source, so gating it off makes LEB report 0 DPS (a 100% error). See the guard comment.")
		assert.is_truthy(src:find("@leb-regression-guard:aura-of-decay-ailment-application", 1, true),
			"the explanatory guard comment marking the intentional absence must remain")
	end)

	it("CalcOffence: the AoD block is scoped by grantedEffect name, is UNGATED, and reroutes on the Blood Font marker", function()
		local src = readSource("Modules/CalcOffence.lua")
		assert.is_truthy(src:find("@leb-regression-guard:aura-of-decay-ailment-application", 1, true),
			"inline guard ID must remain for cross-reference auditing")
		local block = src:match('activeSkill%.activeEffect%.grantedEffect%.name == "Aura Of Decay".-output%.PoisonChance = m_min%(%(output%.PoisonChance or 0%) %+ innate, 100%)')
		assert.is_not_nil(block, "the AoD-scoped ailment block must exist")
		assert.is_falsy(block:find('Condition:AuraOfDecayAura', 1, true),
			"the block must NOT be gated on the removed config condition")
		assert.is_truthy(block:find('Sum("BASE", skillCfg, "PoisonDamageConvertToPhysical") > 0', 1, true),
			"Blood Font reroute must be gated on the PoisonDamageConvertToPhysical marker")
		assert.is_truthy(block:find("playerBleed * 0.75", 1, true),
			"Blood Font applies the player's bleed chance at 75% effectiveness")
	end)

	it("CalcOffence: the aura rate is the datamined 4/s scaled by Ailment Frequency", function()
		local src = readSource("Modules/CalcOffence.lua")
		assert.is_truthy(src:find("@leb-regression-guard:aura-of-decay-ailment-frequency", 1, true),
			"inline frequency guard ID must remain")
		local block = src:match('activeSkill%.activeEffect%.grantedEffect%.name == "Aura Of Decay".-output%.PoisonChance = m_min%(%(output%.PoisonChance or 0%) %+ innate, 100%)')
		assert.is_not_nil(block)
		assert.is_truthy(block:find('Sum("BASE", skillCfg, "AilmentFrequency")', 1, true),
			"frequency must be summed from the skill modlist (where the AoD tree's nodes land)")
		assert.is_truthy(block:find("output.HitSpeed = 4 * (1 + freq / 100)", 1, true),
			"the datamined 4/s base rate must be scaled by (1 + freq/100)")
	end)

	it("ModParser: 'ailment frequency' maps to AilmentFrequency (text-keyed, NOT property-id keyed)", function()
		local src = readSource("Modules/ModParser.lua")
		assert.is_truthy(src:find('%["ailment frequency"%] = "AilmentFrequency"'),
			"the modNameList entry must remain")
		assert.is_truthy(src:find("@leb%-regression%-guard:aura%-of%-decay%-ailment%-frequency"),
			"parser-site guard comment must remain")
	end)

	it("ModCache: the baked rows match the live parse EXACTLY, including a nil (not \"\") residue", function()
		-- Data/ModCache.lua is loaded into modLib.parseModCache and short-circuits parseMod,
		-- so these rows MUST agree with the parser or a 1-point node contributes nothing
		-- while a 3-point (uncached, rank-scaled) node works -- a silent, rank-dependent bug.
		--
		-- The residue must be nil, NOT "": ConfigOptions' customMods gate is
		-- `if mods and not extra then` and "" is TRUTHY in Lua, so an ""-residue row makes
		-- the mod silently vanish on that path (observed: "+50% Ailment Frequency" dropped
		-- => HitSpeed 6.4 instead of 8.4, while the uncached +24%/+36% lines worked).
		-- nil is also what a Main.lua:SaveModCache regen writes for a clean parse, so this
		-- keeps the file regen-stable.
		local src = readSource("Data/ModCache.lua")
		for _, v in ipairs({ 8, 12, 50 }) do
			local row = src:match('c%["%+' .. v .. '%% Ailment Frequency"%]=(.-)\n')
			assert.is_not_nil(row, "ModCache row must exist for +" .. v .. "% Ailment Frequency")
			assert.is_truthy(row:find('name="AilmentFrequency"', 1, true),
				"row must carry the AilmentFrequency mod, not an empty list: +" .. v .. "%")
			assert.is_truthy(row:find("value=" .. v, 1, true), "row value must be " .. v)
			assert.is_falsy(row:find('" Ailment Frequency "', 1, true),
				"row must not keep the stale unparsed residue: +" .. v .. "%")
			assert.is_truthy(row:find(",nil}", 1, true),
				'row residue must be nil, not "" (which is truthy and drops the mod): +' .. v .. "%")
		end
	end)
end)
