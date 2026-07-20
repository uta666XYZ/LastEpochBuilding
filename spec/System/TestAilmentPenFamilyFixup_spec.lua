-- @leb-regression-guard:ailment-pen-family-fixup
-- Locks the ailment-scoped penetration FAMILY fixup at the ModParser chokepoint.
--
-- Diagnosis (pre-fix delivery, per channel -- the earlier "whole family was inert"
-- claim was FALSE): "+X% <Type> Penetration with <Ailment>" (gear affixes, passives,
-- idols, tree nodes) parses/bakes as a <Type>Penetration BASE mod tagged
-- {SkillName=<Ailment>} (e.g. ModCache row '+10% Physical Penetration With Bleed').
-- LEB imports each damaging ailment as a separate ACTIVE skill whose granted-effect
-- name == the ailment name (skills.json Ailment_*; CalcActiveSkill.lua
-- skillCfg.skillName = grantedEffect.name; ModStore.lua case-insensitive SkillName
-- matching), so that pseudo-skill's cfg DOES match the tag. Precisely:
--  (a) Physical rows: inert on the hit loop everywhere (the Physical branch uses the
--      armour path and never sums pen); live ONLY via the imported pseudo-skill's
--      nested-ailment path (calcAilmentMitigation's <Type>Penetration sum) -- item
--      sources only, per (c).
--  (b) non-Physical rows: LIVE on the imported pseudo-skill channel for ITEM sources
--      (Item.lua isConnectorOnlyExtra passes the "  with  " residue): matched at the
--      hit loop's pen sum (the pseudo-skill's own DoT) AND in calcAilmentMitigation.
--  (c) tree/passive sources of ALL types: dropped at the tree extra gates
--      (PassiveTree.lua:556 / PassiveSpec.lua:1024, non-empty extra) -- first
--      activated by the chokepoint's connector-residue clearing.
--  (d) the <private build> in-game 134.88-pt bleed-pen residual is NOT this family (zero
--      family lines on that build; it tracks a dynamic in-game added crit
--      multiplier, quantized at 9.6 pts = 48% x 20 crit-mult -- a separate axis).
--
-- Fix: at the single parse-result chokepoint in ModParser.lua (the returned closure
-- every line -- ModCache-baked or live-parsed -- flows through), rewrite any
-- <Type>Penetration BASE mod whose SkillName tag names a data.damagingAilment member
-- into the ailment-scoped channel: name = "Ailment"..<Ailment>..<Type>.."Penetration",
-- SkillName tag removed (all other tags preserved); when >=1 mod was rewritten and the
-- entry residue is exactly the bare connector "with", clear it so tree/passive sources
-- pass the extra gates. calcAilmentMitigation sums the type-qualified key alongside
-- the typeless one, so dual-type ailments receive only their own type's pen; the hit
-- loop's pen sum is extended with the channel keys for damaging-ailment pseudo-skills
-- only (CalcOffence "pseudo-skill site"), preserving channel (b). Real skill scopes
-- ("with Puncture", "with Shadow Daggers") are NOT in data.damagingAilment and stay
-- untouched (their "  with  " residue also stays, so the tree gates still drop them).
--
-- SPACED display names ("with Time Rot": tag carries "Time Rot", the key is "TimeRot")
-- normalize through data.damagingAilmentSpacedName (Modules/Data.lua): a spaced name
-- maps to its space-stripped key ONLY when no player skill (data.skills treeId) owns
-- that display name. The rewrite emits the STRIPPED key (AilmentTimeRotVoidPenetration)
-- so calcAilmentMitigation's keys match, and the CalcOffence pseudo-skill site resolves
-- spaced granted-effect names through the same map. The two genuine collisions --
-- "Bone Curse" (real Acolyte skill BoneCurse) and "Spirit Plague" (real Acolyte skill
-- SpiritPlague) -- are excluded from the map and stay SkillName-tagged: there the pen
-- scope legitimately means the SKILL (the documented exception).
--
-- See REGRESSION_GUARDS.md "ailment-pen-family-fixup".

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

-- Inject a synthetic BASE mod that the parser cannot produce from config text (the
-- internal "Ailment<Name><Type>Penetration" stat). Push it through configTab.modList so
-- the runCallback modDB rebuild propagates it; do NOT call BuildModList afterwards (that
-- would re-derive modList from customMods and wipe the injection). Mirrors the
-- TestAilmentScopedPenetration_spec injection pattern.
local function injectMod(name, modType, value)
	build.configTab.modList:NewMod(name, modType, value, "Test")
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

describe("AilmentPenFamilyFixup", function()
	before_each(function()
		newBuild()
		resetEnemy()
		-- A directly-cast spell with a non-zero cast speed so the ailment loop has a
		-- positive hit rate; Fireball is unrelated to the ailments we inject by config.
		build.skillsTab:SelSkill(1, "Fireball")
	end)

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
	-- Source-text guard: the inline marker must remain at the chokepoint
	---------------------------------------------------------------------------
	it("ModParser carries the family-fixup inline guard marker", function()
		local f = io.open("Modules/ModParser.lua", "r") or io.open("src/Modules/ModParser.lua", "r")
		assert.is_not_nil(f)
		local text = f:read("*a"); f:close()
		assert.is_truthy(string.find(text, "@leb-regression-guard:ailment-pen-family-fixup", 1, true),
			"inline guard ID must remain in ModParser.lua")
		assert.is_truthy(string.find(text, "fixupAilmentScopedPen", 1, true),
			"the chokepoint fixup function must remain in ModParser.lua")
	end)

	---------------------------------------------------------------------------
	-- (a) live parse rewrites the family into the type-qualified ailment channel
	---------------------------------------------------------------------------
	it("'+10% Physical Penetration with Bleed' parses to ONE AilmentBleedPhysicalPenetration BASE mod, SkillName tag removed", function()
		local mods = modLib.parseMod("+10% Physical Penetration with Bleed")
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		local m = mods[1]
		assert.are.equals("AilmentBleedPhysicalPenetration", m.name)
		assert.are.equals("BASE", m.type)
		assert.are.equals(10, m.value)
		assert.is_nil(findTag(m, "SkillName"),
			"the ailment SkillName tag must be removed (it would gate the mod off forever)")
	end)

	---------------------------------------------------------------------------
	-- (b) ModCache-BAKED rows are covered: exact cached strings (both casings),
	--     one Ignite and one Frostbite line. The pre-check on modLib.parseModCache
	--     proves the row was loaded from the baked cache, not live-parsed.
	---------------------------------------------------------------------------
	for _, case in ipairs({
		{ line = "+10% Physical Penetration With Bleed", name = "AilmentBleedPhysicalPenetration", value = 10 },
		{ line = "+10% Physical Penetration with Bleed", name = "AilmentBleedPhysicalPenetration", value = 10 },
		{ line = "+10% Fire Penetration with Ignite", name = "AilmentIgniteFirePenetration", value = 10 },
		{ line = "+15% Cold Penetration with Frostbite", name = "AilmentFrostbiteColdPenetration", value = 15 },
	}) do
		it("baked row '" .. case.line .. "' is rewritten to " .. case.name, function()
			assert.is_not_nil(modLib.parseModCache[case.line],
				"the exact string must exist as a baked ModCache row (update the spec if the cache changed)")
			local mods = modLib.parseMod(case.line)
			assert.is_not_nil(mods)
			assert.are.equals(1, #mods)
			local m = mods[1]
			assert.are.equals(case.name, m.name)
			assert.are.equals("BASE", m.type)
			assert.are.equals(case.value, m.value)
			assert.is_nil(findTag(m, "SkillName"))
		end)
	end

	it("a multi-tag family row keeps its other tags (PerStat survives the rewrite)", function()
		-- Baked row: {[1]={div=2,stat="Att",type="PerStat"},[2]={skillName="Frostbite",type="SkillName"},...}
		local line = "+1% Frostbite Cold Penetration Per 2 Attunement"
		assert.is_not_nil(modLib.parseModCache[line])
		local mods = modLib.parseMod(line)
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		local m = mods[1]
		assert.are.equals("AilmentFrostbiteColdPenetration", m.name)
		assert.is_nil(findTag(m, "SkillName"))
		local perStat = findTag(m, "PerStat")
		assert.is_not_nil(perStat, "the PerStat tag must survive the rewrite")
		assert.are.equals("Att", perStat.stat)
		assert.are.equals(2, perStat.div)
	end)

	---------------------------------------------------------------------------
	-- (c) real SKILL scopes stay SkillName-tagged (not in data.damagingAilment)
	---------------------------------------------------------------------------
	for _, case in ipairs({
		{ line = "+10% Physical Penetration with Puncture", skill = "Puncture" },
		{ line = "+13% Physical Penetration with Shadow Daggers", skill = "Shadow Daggers" },
	}) do
		it("skill scope '" .. case.line .. "' stays a SkillName-tagged PhysicalPenetration", function()
			assert.is_not_nil(modLib.parseModCache[case.line],
				"the exact string must exist as a baked ModCache row")
			local mods = modLib.parseMod(case.line)
			assert.is_not_nil(mods)
			assert.are.equals(1, #mods)
			local m = mods[1]
			assert.are.equals("PhysicalPenetration", m.name)
			local tag = findTag(m, "SkillName")
			assert.is_not_nil(tag, "real skill scopes must keep their SkillName tag")
			assert.are.equals(case.skill, tag.skillName)
		end)
	end

	it("'+30% Cold Penetration With Staff' (Condition-tagged, no SkillName) is untouched", function()
		local line = "+30% Cold Penetration With Staff"
		assert.is_not_nil(modLib.parseModCache[line])
		local mods = modLib.parseMod(line)
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		assert.are.equals("ColdPenetration", mods[1].name)
		assert.is_not_nil(findTag(mods[1], "Condition"))
	end)

	---------------------------------------------------------------------------
	-- (c2) SPACED display names: normalized to the stripped key via
	--      data.damagingAilmentSpacedName, EXCEPT genuine real-skill collisions
	--      ("Bone Curse"/"Spirit Plague"), which stay SkillName-tagged.
	---------------------------------------------------------------------------
	it("spaced-name map: ailment-only display names map to their stripped key; real-skill collisions do not", function()
		-- Census 2026-06-11 (skills.json x data.damagingAilment): 9 spaced display
		-- names strip to an ailment key; 7 are ailment-only (no treeId homonym), 2
		-- collide with REAL Acolyte player skills and must be excluded.
		for name, key in pairs({
			["Time Rot"] = "TimeRot",
			["Spreading Flames"] = "SpreadingFlames",
			["Abyssal Decay"] = "AbyssalDecay",
			["Acid Skin"] = "AcidSkin",
			["Future Strike"] = "FutureStrike",
			["Serpent Venom"] = "SerpentVenom",
			["Snake Infection"] = "SnakeInfection",
		}) do
			assert.are.equals(key, data.damagingAilmentSpacedName[name],
				name .. " must map to its space-stripped damagingAilment key")
		end
		assert.is_nil(data.damagingAilmentSpacedName["Bone Curse"],
			"Bone Curse is a REAL Acolyte skill (skills.json id BoneCurse, treeId set) -- must be excluded")
		assert.is_nil(data.damagingAilmentSpacedName["Spirit Plague"],
			"Spirit Plague is a REAL Acolyte skill (skills.json id SpiritPlague, treeId set) -- must be excluded")
	end)

	it("baked row '+10% Void Penetration with Time Rot' (spaced display name) is rewritten to AilmentTimeRotVoidPenetration with residue cleared", function()
		-- data.damagingAilment keys the ailment as "TimeRot" (no space); the parsed tag
		-- carries the display name "Time Rot". The spaced-name map normalizes it, the
		-- rewrite emits the STRIPPED key so calcAilmentMitigation's keys match, and the
		-- connector residue is cleared so tree/passive sources pass the extra gates.
		local line = "+10% Void Penetration with Time Rot"
		assert.is_not_nil(modLib.parseModCache[line],
			"the exact string must exist as a baked ModCache row (update the spec if the cache changed)")
		local mods, extra = modLib.parseMod(line)
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		local m = mods[1]
		assert.are.equals("AilmentTimeRotVoidPenetration", m.name)
		assert.are.equals("BASE", m.type)
		assert.are.equals(10, m.value)
		assert.is_nil(findTag(m, "SkillName"),
			"the spaced ailment SkillName tag must be removed (it would gate the mod off forever)")
		assert.is_nil(extra, "the connector-only residue must be cleared (tree-gate delivery)")
	end)

	for _, case in ipairs({
		{ skill = "Bone Curse" },
		{ skill = "Spirit Plague" },
	}) do
		it("collision exception: 'with " .. case.skill .. "' stays a SkillName-tagged PhysicalPenetration (real Acolyte skill)", function()
			-- "Bone Curse"/"Spirit Plague" strip to damagingAilment keys, but each is ALSO
			-- a real Acolyte player skill (treeId set), so the scope legitimately means the
			-- SKILL. No baked family row exists for either (ModCache census 2026-06-11), so
			-- the line is synthesized; the live parse must keep the SkillName tag and its
			-- residue (no rewrite -> no residue clearing).
			local mods, extra = modLib.parseMod("+10% Physical Penetration with " .. case.skill)
			assert.is_not_nil(mods)
			assert.are.equals(1, #mods)
			local m = mods[1]
			assert.are.equals("PhysicalPenetration", m.name)
			local tag = findTag(m, "SkillName")
			assert.is_not_nil(tag, "real-skill collisions must keep their SkillName tag")
			assert.are.equals(case.skill, tag.skillName)
			assert.is_not_nil(extra, "no rewrite happened, so the connector residue must survive")
		end)
	end

	---------------------------------------------------------------------------
	-- (d) end-to-end: the type-qualified key raises the Bleed DoT ONLY
	---------------------------------------------------------------------------
	it("AilmentBleedPhysicalPenetration amplifies the Bleed DoT against a 0-resist enemy", function()
		setMods(bleedMods())
		local base = build.calcsTab.mainOutput.BleedDPS
		assert.is_truthy(base > 0, "Bleed DPS must be non-zero")
		assert.are.equals(1, build.calcsTab.mainOutput.BleedMitigation, "0 resist, 0 pen -> factor 1")

		-- +30 type-qualified Bleed pen, 0 resist -> (1 - (0 - 30)/100) = 1.30
		injectMod("AilmentBleedPhysicalPenetration", "BASE", 30)
		local o = build.calcsTab.mainOutput
		assert.is_near(1.30, o.BleedMitigation, 1e-6, "0 resist, 30 Bleed-Physical pen -> 1.30 factor")
		assert.is_near(base * 1.30, o.BleedDPS, base * 1.30 * 1e-4,
			"the type-qualified ailment pen must amplify the Bleed DoT")
	end)

	it("AilmentBleedPhysicalPenetration does NOT reach the HIT loop's penetration sum", function()
		-- The hit loop reads skillModList:Sum("BASE", cfg, "<Type>Penetration", "Penetration").
		-- The rewritten stat is distinctly named, so it must NOT appear in that sum.
		setMods(bleedMods())
		injectMod("AilmentBleedPhysicalPenetration", "BASE", 50)
		local modDB = build.calcsTab.mainEnv.modDB
		assert.are.equals(0, modDB:Sum("BASE", nil, "PhysicalPenetration", "Penetration"),
			"type-qualified Bleed pen must not enter the Physical hit-pen sum")
		assert.are.equals(0, modDB:Sum("BASE", nil, "FirePenetration", "Penetration"),
			"type-qualified Bleed pen must not enter the Fire hit-pen sum")
		-- And it IS readable under its own scoped stat name (sanity: the mod did land).
		assert.are.equals(50, modDB:Sum("BASE", nil, "AilmentBleedPhysicalPenetration"))
	end)

	it("AilmentBleedPhysicalPenetration does NOT change a Poison ailment", function()
		setMods(poisonMods())
		local basePoison = build.calcsTab.mainOutput.PoisonDPS
		assert.is_truthy((basePoison or 0) > 0, "Poison DPS must be non-zero")

		setMods(poisonMods())
		injectMod("AilmentBleedPhysicalPenetration", "BASE", 50)
		local o = build.calcsTab.mainOutput
		assert.is_near(basePoison, o.PoisonDPS, basePoison * 1e-6,
			"Bleed-scoped pen must not leak into the Poison ailment")
		assert.are.equals(1, o.PoisonMitigation, "Poison mitigation untouched by a Bleed-scoped pen")
	end)

	---------------------------------------------------------------------------
	-- (e) idempotency: repeated parses return the same single rewritten mod
	---------------------------------------------------------------------------
	it("parsing the same family line repeatedly returns one stable rewritten mod (no double rewrite)", function()
		local line = "+10% Physical Penetration With Bleed"
		for pass = 1, 3 do
			local mods = modLib.parseMod(line)
			assert.is_not_nil(mods, "pass " .. pass)
			assert.are.equals(1, #mods, "pass " .. pass .. ": exactly one mod")
			local m = mods[1]
			assert.are.equals("AilmentBleedPhysicalPenetration", m.name,
				"pass " .. pass .. ": no second 'Ailment' prefix may accumulate")
			assert.are.equals(10, m.value, "pass " .. pass .. ": value must not accumulate")
			assert.is_nil(findTag(m, "SkillName"), "pass " .. pass)
		end
		-- The cache entry itself holds the single rewritten mod (mutated in place, once).
		local entry = modLib.parseModCache[line]
		assert.is_not_nil(entry)
		assert.are.equals(1, #entry[1])
		assert.are.equals("AilmentBleedPhysicalPenetration", entry[1][1].name)
	end)

	---------------------------------------------------------------------------
	-- (f) the type-qualified key does NOT leak across damage types
	---------------------------------------------------------------------------
	it("AilmentBleedPoisonPenetration (wrong type for Bleed) does not move Bleed's Physical mitigation", function()
		setMods(bleedMods())
		local base = build.calcsTab.mainOutput.BleedDPS
		assert.is_truthy(base > 0)

		-- Bleed's mitigation sums "AilmentBleedPenetration" + "AilmentBleedPhysicalPenetration"
		-- (its associated type is Physical); a Poison-qualified key must be ignored.
		injectMod("AilmentBleedPoisonPenetration", "BASE", 50)
		local o = build.calcsTab.mainOutput
		assert.are.equals(1, o.BleedMitigation,
			"a Poison-qualified Bleed pen key must not enter Bleed's Physical mitigation")
		assert.is_near(base, o.BleedDPS, base * 1e-6, "Bleed DoT unchanged by the wrong-type key")
	end)

	---------------------------------------------------------------------------
	-- (g) tree-gate delivery: family residue is cleared so PassiveTree.lua:556 /
	--     PassiveSpec.lua:1024 (which drop mods with non-empty extra) accept the
	--     rewritten mods; non-family residues stay untouched.
	---------------------------------------------------------------------------
	it("tree-gate delivery: '+15% Physical Penetration with Bleed' (tree_0.json node stat) parses with cleared residue", function()
		-- This exact string exists verbatim as a node stat in src/TreeData/1_4/tree_0.json.
		local mods, extra = modLib.parseMod("+15% Physical Penetration with Bleed")
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		assert.are.equals("AilmentBleedPhysicalPenetration", mods[1].name)
		assert.are.equals(15, mods[1].value)
		assert.is_truthy(extra == nil or extra == "",
			"the connector-only residue must be cleared (was '  with  ') so the tree extra gates pass")
		-- PassiveSpec.lua:1024 gates on `not mod.extra` (empty string is truthy in Lua),
		-- so the residue must be cleared to NIL specifically.
		assert.is_nil(extra, "residue must be nil, not the (truthy) empty string")
	end)

	it("a non-family line keeps its connector residue (tree gate behaviour preserved for others)", function()
		-- Real-skill scope: not rewritten, so its "  with  " residue must survive and
		-- the tree gates keep dropping it exactly as before the fixup.
		local line = "+10% Physical Penetration with Puncture"
		assert.is_not_nil(modLib.parseModCache[line])
		local mods, extra = modLib.parseMod(line)
		assert.is_not_nil(mods)
		assert.are.equals("PhysicalPenetration", mods[1].name)
		assert.are.equals("  with  ", extra,
			"un-rewritten lines must keep their residue byte-identical (no clearing without a rewrite)")
	end)

	---------------------------------------------------------------------------
	-- (h) imported ailment pseudo-skill channel (CalcOffence pseudo-skill site):
	--     LEB imports each damaging ailment as its own ACTIVE skill (skills.json
	--     "Ailment_Ignite", granted-effect name "Ignite"). On dev the SkillName-
	--     tagged family rows were summed at the hit loop's pen site during that
	--     skill's run; the rewritten channel keys must keep that pen flowing.
	---------------------------------------------------------------------------
	it("pseudo-skill channel: AilmentIgniteFirePenetration amplifies the Ignite pseudo-skill's own DoT", function()
		build.skillsTab:SelSkill(1, "Ailment_Ignite")
		runCallback("OnFrame")
		local base = build.calcsTab.mainOutput.TotalDPS
		assert.is_truthy(base and base > 0, "the Ignite pseudo-skill must have non-zero DoT DPS")

		-- 0 enemy resist, +10 type-qualified Ignite pen -> effMult 1.10 on its fire DoT.
		-- Exactly x1.10 also proves the key is applied ONCE (no double-count with the
		-- nested-ailment path: no ailment chance on this build, and calcAilmentMitigation
		-- only serves nested ailments, not the pseudo-skill's own damage).
		injectMod("AilmentIgniteFirePenetration", "BASE", 10)
		local o = build.calcsTab.mainOutput
		assert.is_near(base * 1.10, o.TotalDPS, base * 1.10 * 1e-4,
			"the type-qualified channel key must reach the pseudo-skill's own damage (dev parity)")
	end)

	it("pseudo-skill channel: the typeless AilmentIgnitePenetration (Salt the Wound channel) also reaches it", function()
		build.skillsTab:SelSkill(1, "Ailment_Ignite")
		runCallback("OnFrame")
		local base = build.calcsTab.mainOutput.TotalDPS
		assert.is_truthy(base and base > 0)

		injectMod("AilmentIgnitePenetration", "BASE", 10)
		local o = build.calcsTab.mainOutput
		assert.is_near(base * 1.10, o.TotalDPS, base * 1.10 * 1e-4,
			"the typeless channel key must reach the pseudo-skill's own damage")
	end)

	it("pseudo-skill channel: a different ailment's key does not move the Ignite pseudo-skill", function()
		build.skillsTab:SelSkill(1, "Ailment_Ignite")
		runCallback("OnFrame")
		local base = build.calcsTab.mainOutput.TotalDPS
		assert.is_truthy(base and base > 0)

		injectMod("AilmentBleedPhysicalPenetration", "BASE", 50)
		local o = build.calcsTab.mainOutput
		assert.is_near(base, o.TotalDPS, base * 1e-6,
			"Bleed-scoped pen must not leak into the Ignite pseudo-skill's own damage")
	end)

	---------------------------------------------------------------------------
	-- (i) spaced-name end-to-end: the TimeRot DoT (associated type Void) responds
	--     to the stripped channel key on BOTH channels.
	---------------------------------------------------------------------------
	it("end-to-end: the spaced family line amplifies a TimeRot DoT on a normal skill (x1.10 at 0 resist)", function()
		local timeRotMods = table.concat({
			"+100% chance to inflict Time Rot",
			"+500 Time Rot Damage",
		}, "\n")
		setMods(timeRotMods)
		local o = build.calcsTab.mainOutput
		local base = o.TimeRotDPS
		assert.is_truthy((base or 0) > 0, "TimeRot DPS must be non-zero")
		assert.are.equals(1, o.TimeRotMitigation, "0 resist, 0 pen -> factor 1")

		-- The full pipeline: the spaced family line text parses through the chokepoint
		-- (rewritten to AilmentTimeRotVoidPenetration, residue cleared) and reaches the
		-- TimeRot ailment's mitigation via calcAilmentMitigation's stripped key.
		setMods(timeRotMods .. "\n+10% Void Penetration with Time Rot")
		o = build.calcsTab.mainOutput
		assert.is_near(1.10, o.TimeRotMitigation, 1e-6, "0 resist, 10 TimeRot-Void pen -> 1.10 factor")
		assert.is_near(base * 1.10, o.TimeRotDPS, base * 1.10 * 1e-4,
			"the spaced family line must amplify the TimeRot DoT end-to-end")
	end)

	it("pseudo-skill channel: AilmentTimeRotVoidPenetration amplifies the Time Rot pseudo-skill's own DoT (spaced granted-effect name)", function()
		-- The Ailment_TimeRot pseudo-skill's granted-effect name is the SPACED "Time Rot";
		-- the CalcOffence pseudo-skill site must resolve it through the spaced-name map to
		-- sum the STRIPPED channel keys (dev parity for the previously SkillName-delivered
		-- item-channel pen).
		build.skillsTab:SelSkill(1, "Ailment_TimeRot")
		runCallback("OnFrame")
		local base = build.calcsTab.mainOutput.TotalDPS
		assert.is_truthy(base and base > 0, "the Time Rot pseudo-skill must have non-zero DoT DPS")

		injectMod("AilmentTimeRotVoidPenetration", "BASE", 10)
		local o = build.calcsTab.mainOutput
		assert.is_near(base * 1.10, o.TotalDPS, base * 1.10 * 1e-4,
			"the stripped channel key must reach the spaced-name pseudo-skill's own damage")
	end)
end)
