-- @leb-regression-guard:chance-chance-conversion
-- Locks the game-faithful chance->chance conversion engine for two uniques:
--
--   * Apex of Thought (Mage Helmet, uniques_1_4.json #316). In-game tooltip:
--       "While standing on your Glyph of Dominion, 100% of your Ignite Chance is
--        converted to Fire Resistance Shred Chance, 100% of your Chill Chance is
--        converted to Cold Resistance Shred Chance, and 100% of your Shock Chance
--        is converted to Lightning Resistance Shred Chance."
--     The datamine packs all three into ONE combined mod string
--       "100% of Ignite Shock and Chill Chance converted to Fire Lightning and Cold
--        Resistance Shred Chance while standing on your Glyph of Dominion".
--     Conversions: Ignite->FireResShred, Shock->LightningResShred, Chill->ColdResShred,
--     each 100%, gated on the glyph (existing config conditionStandingOnGlyphOfDominion).
--
--   * Vial of Volatile Ice (Off-Hand Catalyst, uniques_1_4.json #331). In-game:
--       "Poison Chance from all sources is converted to Frostbite Chance for Acid Flask"
--     One conversion: Poison->Frostbite, 100%, skill-scoped to Acid Flask, unconditional.
--
--   * Carrion of Creation (primordial, uniques_1_4.json #431). In-game combined tooltip:
--       "100% of Ignite, Frostbite, Shock, Time Rot, Damned, and Poison Chance Converted
--        to Bleed Chance."
--     SIX conversions: {Ignite,Frostbite,Shock,TimeRot,Damned,Poison}Chance -> BleedChance,
--     each 100%, applied GLOBALLY (no glyph gate, no skill scope -- every skill). The six
--     ailment chances were baked in ModCache.lua as LEB_NotSupported; those rows are removed
--     so they live-parse. The GLOBAL scope is expressed by emitting the AilmentChanceConversion
--     mods with NO tag: ModStoreClass:ListInternal inserts a tagless LIST mod unconditionally
--     for every cfg (mod[1] == nil -> the `elseif mod.value` branch, no EvalMod), so
--     modDB:List(skillCfg, ...) returns them for ANY skill -- the faithful all-skill scope.
--
--   * Maehlin's Hubris (Mage Helmet, uniques_1_4.json #83). Verbatim datamine mod string:
--       "100% of Bleed Chance Converted to Ignite Chance"
--     ONE conversion: BleedChance -> IgniteChance, 100%, applied GLOBALLY (no glyph gate,
--     no skill scope). Same untagged-global class as Carrion. Datamine (uniques_v3.json
--     uniqueID 83): value 1.0, canRoll false, property 100, specialTag 2, no "for/with"
--     clause. Never baked in ModCache.lua (no row to remove) -- it previously fell through
--     the generic `% of X converted to Y` handler to nsAny (LEB_NotSupported).
--
--   * Troaka's Teeth (Bow, uniques_1_4.json #146). Verbatim datamine mod string:
--       "100% of Bleed and Poison Chance converted to Frostbite Chance with Puncture"
--     TWO conversions collapsing into ONE dest: BleedChance -> FrostbiteChance and
--     PoisonChance -> FrostbiteChance, each 100%, skill-scoped to Puncture only,
--     unconditional. Datamine (uniques_v3.json uniqueID 146, fifth mod): value 1.0, canRoll
--     false, property 58 (shared with Liath's #276), specialTag 2, "with Puncture" scope.
--     Never baked in ModCache.lua (no row to remove) -- previously nsAny (LEB_NotSupported).
--
-- Engine design:
--   1. ModParser emits AilmentChanceConversion LIST mods carrying { source, dest } and
--      the appropriate tag -- Condition:StandingOnGlyphOfDominion for Apex (player-global),
--      SkillName=Acid Flask for Vial (skill-scoped). The Apex combined string was baked in
--      ModCache.lua as LEB_NotSupported; that row is removed so it live-parses.
--   2. CalcOffence (after the ailment-chance BASE sums, before the ailment-DPS loop) reads
--      modDB:List(skillCfg, "AilmentChanceConversion") -- tag resolution returns ONLY the
--      active conversions (glyph OFF -> empty; non-matching skill -> empty). FAITHFUL: 100%
--      of the source converts -> move the full (0-100 capped) source value into the dest
--      (re-capped at 100) and zero the source so its ailment stops applying.
--   3. The two raw readers that previously read modDB:Sum("BASE", skillCfg, "<X>Chance")
--      -- Ignite Overload and Fissure of Wrath -- are redirected to the post-conversion
--      value. With no conversion equipped the conversion list is empty (the loop is a
--      no-op), so output.<X>Chance == the prior raw Sum and the redirects are byte-identical
--      for every other build (proven below).
--
-- See REGRESSION_GUARDS.md > "chance-chance-conversion".

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

describe("ChanceChanceConversion", function()
	before_each(function()
		newBuild()
	end)

	---------------------------------------------------------------------------
	-- Parse-level: ModParser emits the structured conversion mods + tags
	---------------------------------------------------------------------------
	it("Vial: parses to a SkillName-gated Poison->Frostbite AilmentChanceConversion", function()
		local mods, extra = modLib.parseMod("Poison Chance from all sources is converted to Frostbite Chance for Acid Flask")
		assert.is_nil(extra, "a fully-parsed Vial conversion must leave no residue")
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		local m = mods[1]
		assert.are.equals("AilmentChanceConversion", m.name)
		assert.are.equals("LIST", m.type)
		assert.are.equals("PoisonChance", m.value.source)
		assert.are.equals("FrostbiteChance", m.value.dest)
		local skillTag = findTag(m, "SkillName")
		assert.is_not_nil(skillTag, "Vial conversion must be skill-scoped")
		assert.are.equals("Acid Flask", skillTag.skillName)
		assert.is_nil(findTag(m, "Condition"), "Vial conversion is unconditional (no glyph gate)")
	end)

	it("Apex: combined string parses to THREE glyph-gated conversions", function()
		local mods, extra = modLib.parseMod("100% of Ignite Shock and Chill Chance converted to Fire Lightning and Cold Resistance Shred Chance while standing on your Glyph of Dominion")
		assert.is_nil(extra, "the Apex combined conversion must leave no residue")
		assert.is_not_nil(mods)
		assert.are.equals(3, #mods, "Apex packs three ailment->res-shred conversions")
		-- collect source->dest pairs, asserting each carries the glyph condition
		local pairs_ = {}
		for _, m in ipairs(mods) do
			assert.are.equals("AilmentChanceConversion", m.name)
			assert.are.equals("LIST", m.type)
			local cond = findTag(m, "Condition")
			assert.is_not_nil(cond, "each Apex conversion must be glyph-gated")
			assert.are.equals("StandingOnGlyphOfDominion", cond.var)
			assert.is_nil(findTag(m, "SkillName"), "Apex conversion is player-global, not skill-scoped")
			pairs_[m.value.source] = m.value.dest
		end
		-- Faithful mapping per the in-game tooltip (NOT positional 1:1 in the packed string):
		--   Ignite -> Fire Res Shred, Shock -> Lightning Res Shred, Chill -> Cold Res Shred
		assert.are.equals("FireResShredChance", pairs_["IgniteChance"])
		assert.are.equals("LightningResShredChance", pairs_["ShockChance"])
		assert.are.equals("ColdResShredChance", pairs_["ChillChance"])
	end)

	it("Apex combined string is NOT baked as LEB_NotSupported in ModCache (live-parses)", function()
		local mods = modLib.parseMod("100% of Ignite Shock and Chill Chance converted to Fire Lightning and Cold Resistance Shred Chance while standing on your Glyph of Dominion")
		for _, m in ipairs(mods) do
			assert.are_not.equals("LEB_NotSupported", m.name,
				"the ModCache notSupported row must be removed so the handler live-parses")
		end
	end)

	it("Liath's: parses to a SkillName-gated Ignite->Shock AilmentChanceConversion", function()
		-- Liath's Machinations (uniques_1_4.json #276), verbatim datamine string. Shock is
		-- a debuff (not a DoT), but the conversion just moves the chance VALUE; dest is the
		-- ShockChance stat CalcOffence reads.
		local mods, extra = modLib.parseMod("100% of Ignite Chance Converted to Shock Chance for Fireball")
		assert.is_nil(extra, "a fully-parsed Liath's conversion must leave no residue")
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		local m = mods[1]
		assert.are.equals("AilmentChanceConversion", m.name)
		assert.are.equals("LIST", m.type)
		assert.are.equals("IgniteChance", m.value.source)
		assert.are.equals("ShockChance", m.value.dest)
		local skillTag = findTag(m, "SkillName")
		assert.is_not_nil(skillTag, "Liath's conversion must be skill-scoped")
		assert.are.equals("Fireball", skillTag.skillName)
		assert.is_nil(findTag(m, "Condition"), "Liath's conversion is unconditional (no glyph gate)")
	end)

	it("Liath's: NOT baked as LEB_NotSupported in ModCache (live-parses)", function()
		local mods = modLib.parseMod("100% of Ignite Chance Converted to Shock Chance for Fireball")
		assert.is_not_nil(mods)
		for _, m in ipairs(mods) do
			assert.are_not.equals("LEB_NotSupported", m.name,
				"the ModCache notSupported row must be removed so the handler live-parses")
		end
	end)

	---------------------------------------------------------------------------
	-- Consumer (modDB tag resolution): only ACTIVE conversions are returned
	---------------------------------------------------------------------------
	it("Apex: glyph condition gates the conversion list (OFF -> none, ON -> 3)", function()
		local combined = "100% of Ignite Shock and Chill Chance converted to Fire Lightning and Cold Resistance Shred Chance while standing on your Glyph of Dominion"
		-- glyph OFF
		build.configTab.input.conditionStandingOnGlyphOfDominion = nil
		setMods(combined)
		local off = build.calcsTab.mainEnv.modDB:List(nil, "AilmentChanceConversion")
		assert.are.equals(0, #off, "glyph OFF -> conversion is filtered out (no-op)")
		-- glyph ON
		build.configTab.input.conditionStandingOnGlyphOfDominion = true
		setMods(combined)
		local on = build.calcsTab.mainEnv.modDB:List(nil, "AilmentChanceConversion")
		assert.are.equals(3, #on, "glyph ON -> all three conversions are active")
	end)

	it("Vial: SkillName tag returns the conversion ONLY for an Acid Flask cfg", function()
		local db = new("ModDB")
		db.actor = { modDB = db }
		db:AddList(modLib.parseMod("Poison Chance from all sources is converted to Frostbite Chance for Acid Flask"))
		assert.are.equals(1, #db:List({ skillName = "Acid Flask" }, "AilmentChanceConversion"),
			"Acid Flask is the scoped skill -> conversion applies")
		assert.are.equals(0, #db:List({ skillName = "Fireball" }, "AilmentChanceConversion"),
			"another skill -> conversion is filtered out (poison chance untouched)")
		assert.are.equals(0, #db:List(nil, "AilmentChanceConversion"),
			"no skill cfg -> the skill-scoped conversion does not leak globally")
	end)

	it("Liath's: SkillName tag returns the conversion ONLY for a Fireball cfg", function()
		local db = new("ModDB")
		db.actor = { modDB = db }
		db:AddList(modLib.parseMod("100% of Ignite Chance Converted to Shock Chance for Fireball"))
		assert.are.equals(1, #db:List({ skillName = "Fireball" }, "AilmentChanceConversion"),
			"Fireball is the scoped skill -> conversion applies")
		assert.are.equals(0, #db:List({ skillName = "Acid Flask" }, "AilmentChanceConversion"),
			"another skill -> conversion is filtered out (ignite chance untouched)")
		assert.are.equals(0, #db:List(nil, "AilmentChanceConversion"),
			"no skill cfg -> the skill-scoped conversion does not leak globally")
	end)

	---------------------------------------------------------------------------
	-- End-to-end: output ailment/res-shred chances flip under the conversion
	---------------------------------------------------------------------------
	it("Apex end-to-end: glyph ON moves each ailment chance into its res-shred chance", function()
		-- "Chance to apply X" is the real affix form that emits <X>Chance BASE
		-- (the bare "ignite chance" phrasing is shadowed by the Ignite ailment-skill
		-- trigger mapping, so it is NOT used by real ailment-chance affixes).
		local base = table.concat({
			"+100% Chance to apply Ignite",
			"+60% Chance to apply Shock",
			"+40% Chance to apply Chill",
			"100% of Ignite Shock and Chill Chance converted to Fire Lightning and Cold Resistance Shred Chance while standing on your Glyph of Dominion",
		}, "\n")

		-- glyph OFF: ailments keep their chance, res-shred untouched
		build.configTab.input.conditionStandingOnGlyphOfDominion = nil
		setMods(base)
		local off = build.calcsTab.calcsOutput
		assert.are.equals(100, off.IgniteChance)
		assert.are.equals(60, off.ShockChance)
		assert.are.equals(40, off.ChillChance)
		assert.are.equals(0, off.FireResShredChance)
		assert.are.equals(0, off.LightningResShredChance)
		assert.are.equals(0, off.ColdResShredChance)

		-- glyph ON: each source chance is zeroed, the dest res-shred gains the moved value
		build.configTab.input.conditionStandingOnGlyphOfDominion = true
		setMods(base)
		local on = build.calcsTab.calcsOutput
		assert.are.equals(0, on.IgniteChance, "Ignite chance fully converted away")
		assert.are.equals(0, on.ShockChance, "Shock chance fully converted away")
		assert.are.equals(0, on.ChillChance, "Chill chance fully converted away")
		assert.are.equals(100, on.FireResShredChance, "Ignite chance -> Fire Res Shred chance")
		assert.are.equals(60, on.LightningResShredChance, "Shock chance -> Lightning Res Shred chance")
		assert.are.equals(40, on.ColdResShredChance, "Chill chance -> Cold Res Shred chance")
	end)

	it("Apex end-to-end: a pre-existing res-shred chance is ADDED to (re-capped at 100)", function()
		-- 70 ignite chance + 50 existing fire-res-shred chance -> 120 -> capped 100, ignite -> 0.
		-- "Fire Res Shred Chance" is the affix form that emits FireResShredChance BASE
		-- (the "shred fire resistance" forms route to the on-hit trigger stat instead).
		local base = table.concat({
			"+70% Chance to apply Ignite",
			"+50 Fire Res Shred Chance",
			"100% of Ignite Shock and Chill Chance converted to Fire Lightning and Cold Resistance Shred Chance while standing on your Glyph of Dominion",
		}, "\n")
		build.configTab.input.conditionStandingOnGlyphOfDominion = true
		setMods(base)
		local o = build.calcsTab.calcsOutput
		assert.are.equals(0, o.IgniteChance)
		assert.are.equals(100, o.FireResShredChance,
			"50 existing + 70 moved = 120, re-capped at the 100 chance cap")
	end)

	---------------------------------------------------------------------------
	-- Regression safety: the redirects are a strict no-op without a conversion
	---------------------------------------------------------------------------
	it("Ignite Overload reads post-conversion ignite chance, byte-identical without conversion", function()
		-- No conversion unique: output.IgniteChance == raw modDB:Sum, so the redirected
		-- Ignite Overload (1% more fire per 20% ignite chance) is unchanged.
		build.configTab.input.conditionIgniteOverload = true
		setMods("+80% Chance to apply Ignite")
		local o = build.calcsTab.calcsOutput
		assert.are.equals(80, o.IgniteChance)
		assert.are.equals(4, o.IgniteOverloadMore, "floor(80/20) = 4 -- identical to the pre-redirect raw read")
	end)

	it("Ignite Overload sees ZERO when Apex converts the ignite chance away", function()
		build.configTab.input.conditionIgniteOverload = true
		build.configTab.input.conditionStandingOnGlyphOfDominion = true
		setMods(table.concat({
			"+80% Chance to apply Ignite",
			"100% of Ignite Shock and Chill Chance converted to Fire Lightning and Cold Resistance Shred Chance while standing on your Glyph of Dominion",
		}, "\n"))
		local o = build.calcsTab.calcsOutput
		assert.are.equals(0, o.IgniteChance, "ignite chance converted away")
		assert.are.equals(80, o.FireResShredChance, "the 80 ignite chance moved into Fire Res Shred chance")
		-- IgniteOverloadMore is only written when > 0; converted-away ignite -> no overload.
		assert.is_truthy((o.IgniteOverloadMore or 0) == 0,
			"no ignite chance remains, so Ignite Overload contributes nothing")
	end)

	---------------------------------------------------------------------------
	-- Carrion of Creation (#431): SIX GLOBAL (untagged) ailment->Bleed conversions
	---------------------------------------------------------------------------
	-- The six verbatim datamine strings, source ailment -> expected source-chance stat.
	local carrionStrings = {
		{ "100% of Ignite Chance Converted to Bleed Chance",    "IgniteChance" },
		{ "100% of Frostbite Chance Converted to Bleed Chance", "FrostbiteChance" },
		{ "100% of Shock Chance Converted to Bleed Chance",     "ShockChance" },
		{ "100% of Time Rot Chance Converted to Bleed Chance",  "TimeRotChance" },
		{ "100% of Damned Chance Converted to Bleed Chance",    "DamnedChance" },
		{ "100% of Poison Chance Converted to Bleed Chance",    "PoisonChance" },
	}

	it("Carrion: all six strings parse to an UNTAGGED <X>Chance->BleedChance conversion", function()
		for _, case in ipairs(carrionStrings) do
			local str, expectSrc = case[1], case[2]
			local mods, extra = modLib.parseMod(str)
			assert.is_nil(extra, "Carrion conversion must leave no residue: " .. str)
			assert.is_not_nil(mods)
			assert.are.equals(1, #mods, "one conversion per string: " .. str)
			local m = mods[1]
			assert.are.equals("AilmentChanceConversion", m.name)
			assert.are.equals("LIST", m.type)
			assert.are.equals(expectSrc, m.value.source, "source stat for: " .. str)
			assert.are.equals("BleedChance", m.value.dest)
			-- The crux: the conversion is GLOBAL, so it must carry NO tag (no SkillName, no
			-- Condition). A tag would make ListInternal route through EvalMod and gate it.
			assert.is_nil(m[1], "Carrion conversion must be untagged (global): " .. str)
			assert.is_nil(findTag(m, "SkillName"), "no skill scope: " .. str)
			assert.is_nil(findTag(m, "Condition"), "no condition gate: " .. str)
		end
	end)

	it("Carrion: NOT baked as LEB_NotSupported in ModCache (all six live-parse)", function()
		for _, case in ipairs(carrionStrings) do
			local mods = modLib.parseMod(case[1])
			for _, m in ipairs(mods) do
				assert.are_not.equals("LEB_NotSupported", m.name,
					"the ModCache notSupported row must be removed so it live-parses: " .. case[1])
			end
		end
	end)

	it("Carrion: the untagged conversion applies to EVERY skill cfg (global scope)", function()
		-- This is the load-bearing global-scope assertion. A tagless LIST mod must be
		-- returned by modDB:List for ANY cfg -- including unrelated skills and nil.
		local db = new("ModDB")
		db.actor = { modDB = db }
		db:AddList(modLib.parseMod("100% of Ignite Chance Converted to Bleed Chance"))
		assert.are.equals(1, #db:List({ skillName = "Fireball" }, "AilmentChanceConversion"),
			"global conversion applies to Fireball")
		assert.are.equals(1, #db:List({ skillName = "Acid Flask" }, "AilmentChanceConversion"),
			"global conversion applies to an unrelated skill (Acid Flask)")
		assert.are.equals(1, #db:List(nil, "AilmentChanceConversion"),
			"global conversion applies even with no skill cfg")
	end)

	it("Carrion end-to-end: ALL SIX ailment chances move into Bleed chance on any skill", function()
		-- Inject each source via its real chance-to-apply affix form, on Fireball (a skill
		-- entirely unrelated to bleed). The bare "<X> Chance" affix maps to the on-hit
		-- trigger stat, so the BASE <X>Chance form is "chance to inflict/apply <X>".
		build.skillsTab:SelSkill(1, "Fireball")
		local sources = table.concat({
			"+80% chance to inflict Ignite",
			"+70% chance to inflict Frostbite",
			"+60% chance to inflict Shock",
			"+50% chance to inflict Time Rot",
			"+40% chance to apply Damned",
			"+30% chance to inflict Poison",
		}, "\n")
		local conv = table.concat({
			"100% of Ignite Chance Converted to Bleed Chance",
			"100% of Frostbite Chance Converted to Bleed Chance",
			"100% of Shock Chance Converted to Bleed Chance",
			"100% of Time Rot Chance Converted to Bleed Chance",
			"100% of Damned Chance Converted to Bleed Chance",
			"100% of Poison Chance Converted to Bleed Chance",
		}, "\n")

		-- Without the conversion: every source chance is present, Bleed is 0.
		setMods(sources)
		local off = build.calcsTab.mainOutput
		assert.are.equals(80, off.IgniteChance)
		assert.are.equals(70, off.FrostbiteChance)
		assert.are.equals(60, off.ShockChance)
		assert.are.equals(50, off.TimeRotChance)
		assert.are.equals(40, off.DamnedChance)
		assert.are.equals(30, off.PoisonChance)
		assert.are.equals(0, off.BleedChance)

		-- With the conversion: every source is zeroed, Bleed gains the sum (capped at 100).
		setMods(sources .. "\n" .. conv)
		local on = build.calcsTab.mainOutput
		assert.are.equals(0, on.IgniteChance, "Ignite chance converted away")
		assert.are.equals(0, on.FrostbiteChance, "Frostbite chance converted away")
		assert.are.equals(0, on.ShockChance, "Shock chance converted away")
		assert.are.equals(0, on.TimeRotChance, "Time Rot chance converted away")
		assert.are.equals(0, on.DamnedChance, "Damned chance converted away")
		assert.are.equals(0, on.PoisonChance, "Poison chance converted away")
		-- 80+70+60+50+40+30 = 330, re-capped at the 100 chance cap.
		assert.are.equals(100, on.BleedChance, "all six ailment chances summed into Bleed, capped at 100")
	end)

	it("Carrion: a single source converts in isolation, leaving the other ailments untouched", function()
		-- Only Poison->Bleed equipped: Poison chance moves, the other ailments stay.
		build.skillsTab:SelSkill(1, "Fireball")
		setMods(table.concat({
			"+30% chance to inflict Poison",
			"+45% chance to inflict Ignite",
			"100% of Poison Chance Converted to Bleed Chance",
		}, "\n"))
		local o = build.calcsTab.mainOutput
		assert.are.equals(0, o.PoisonChance, "the equipped Poison->Bleed conversion zeroes Poison")
		assert.are.equals(30, o.BleedChance, "Poison chance moved into Bleed")
		assert.are.equals(45, o.IgniteChance, "Ignite has no equipped conversion -> untouched")
	end)

	---------------------------------------------------------------------------
	-- Maehlin's Hubris (#83): GLOBAL (untagged) Bleed->Ignite conversion
	---------------------------------------------------------------------------
	it("Maehlin's: parses to an UNTAGGED Bleed->Ignite AilmentChanceConversion (global)", function()
		local mods, extra = modLib.parseMod("100% of Bleed Chance Converted to Ignite Chance")
		assert.is_nil(extra, "a fully-parsed Maehlin's conversion must leave no residue")
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		local m = mods[1]
		assert.are.equals("AilmentChanceConversion", m.name)
		assert.are.equals("LIST", m.type)
		assert.are.equals("BleedChance", m.value.source)
		assert.are.equals("IgniteChance", m.value.dest)
		-- GLOBAL => NO tag (mirrors Carrion). A tag would route through EvalMod and gate it.
		assert.is_nil(m[1], "Maehlin's conversion must be untagged (global)")
		assert.is_nil(findTag(m, "SkillName"), "no skill scope")
		assert.is_nil(findTag(m, "Condition"), "no condition gate")
	end)

	it("Maehlin's: NOT baked as LEB_NotSupported in ModCache (live-parses)", function()
		local mods = modLib.parseMod("100% of Bleed Chance Converted to Ignite Chance")
		assert.is_not_nil(mods)
		for _, m in ipairs(mods) do
			assert.are_not.equals("LEB_NotSupported", m.name,
				"the generic-handler nsAny fallback must be superseded so it live-parses")
		end
	end)

	it("Maehlin's: the untagged conversion applies to EVERY skill cfg (global scope)", function()
		local db = new("ModDB")
		db.actor = { modDB = db }
		db:AddList(modLib.parseMod("100% of Bleed Chance Converted to Ignite Chance"))
		assert.are.equals(1, #db:List({ skillName = "Fireball" }, "AilmentChanceConversion"),
			"global conversion applies to Fireball")
		assert.are.equals(1, #db:List({ skillName = "Puncture" }, "AilmentChanceConversion"),
			"global conversion applies to an unrelated skill (Puncture)")
		assert.are.equals(1, #db:List(nil, "AilmentChanceConversion"),
			"global conversion applies even with no skill cfg")
	end)

	it("Maehlin's end-to-end: Bleed chance moves into Ignite chance on any skill", function()
		-- Fireball is unrelated to bleed; the global conversion still applies.
		build.skillsTab:SelSkill(1, "Fireball")
		setMods("+80% chance to inflict Bleed")
		local off = build.calcsTab.mainOutput
		assert.are.equals(80, off.BleedChance)
		assert.are.equals(0, off.IgniteChance)

		setMods(table.concat({
			"+80% chance to inflict Bleed",
			"100% of Bleed Chance Converted to Ignite Chance",
		}, "\n"))
		local on = build.calcsTab.mainOutput
		assert.are.equals(0, on.BleedChance, "Bleed chance fully converted away")
		assert.are.equals(80, on.IgniteChance, "Bleed chance moved into Ignite")
	end)

	it("Maehlin's end-to-end: a pre-existing Ignite chance is ADDED to (re-capped at 100)", function()
		build.skillsTab:SelSkill(1, "Fireball")
		setMods(table.concat({
			"+70% chance to inflict Bleed",
			"+50% chance to inflict Ignite",
			"100% of Bleed Chance Converted to Ignite Chance",
		}, "\n"))
		local o = build.calcsTab.mainOutput
		assert.are.equals(0, o.BleedChance, "Bleed converted away")
		assert.are.equals(100, o.IgniteChance, "50 existing + 70 moved = 120, re-capped at 100")
	end)

	---------------------------------------------------------------------------
	-- Troaka's Teeth (#146): Puncture-scoped TWO-SOURCE Bleed+Poison->Frostbite
	---------------------------------------------------------------------------
	it("Troaka's: parses to TWO SkillName=Puncture Bleed/Poison->Frostbite conversions", function()
		local mods, extra = modLib.parseMod("100% of Bleed and Poison Chance converted to Frostbite Chance with Puncture")
		assert.is_nil(extra, "a fully-parsed Troaka's conversion must leave no residue")
		assert.is_not_nil(mods)
		assert.are.equals(2, #mods, "two sources collapsing into one dest -> two conversion mods")
		local dests = {}
		for _, m in ipairs(mods) do
			assert.are.equals("AilmentChanceConversion", m.name)
			assert.are.equals("LIST", m.type)
			assert.are.equals("FrostbiteChance", m.value.dest, "both sources convert into Frostbite")
			local skillTag = findTag(m, "SkillName")
			assert.is_not_nil(skillTag, "Troaka's conversion must be skill-scoped")
			assert.are.equals("Puncture", skillTag.skillName)
			assert.is_nil(findTag(m, "Condition"), "Troaka's conversion is unconditional (no glyph gate)")
			dests[m.value.source] = m.value.dest
		end
		assert.are.equals("FrostbiteChance", dests["BleedChance"], "Bleed -> Frostbite")
		assert.are.equals("FrostbiteChance", dests["PoisonChance"], "Poison -> Frostbite")
	end)

	it("Troaka's: NOT baked as LEB_NotSupported in ModCache (live-parses)", function()
		local mods = modLib.parseMod("100% of Bleed and Poison Chance converted to Frostbite Chance with Puncture")
		assert.is_not_nil(mods)
		for _, m in ipairs(mods) do
			assert.are_not.equals("LEB_NotSupported", m.name,
				"the generic-handler nsAny fallback must be superseded so it live-parses")
		end
	end)

	it("Troaka's: SkillName tag returns BOTH conversions ONLY for a Puncture cfg", function()
		local db = new("ModDB")
		db.actor = { modDB = db }
		db:AddList(modLib.parseMod("100% of Bleed and Poison Chance converted to Frostbite Chance with Puncture"))
		assert.are.equals(2, #db:List({ skillName = "Puncture" }, "AilmentChanceConversion"),
			"Puncture is the scoped skill -> both conversions apply")
		assert.are.equals(0, #db:List({ skillName = "Fireball" }, "AilmentChanceConversion"),
			"another skill -> conversions filtered out (Bleed/Poison chance untouched)")
		assert.are.equals(0, #db:List(nil, "AilmentChanceConversion"),
			"no skill cfg -> the skill-scoped conversions do not leak globally")
	end)

	it("Troaka's end-to-end: both Bleed and Poison chance accumulate into Frostbite for Puncture", function()
		build.skillsTab:SelSkill(1, "Puncture")
		setMods(table.concat({
			"+60% chance to inflict Bleed",
			"+40% chance to inflict Poison",
		}, "\n"))
		local off = build.calcsTab.mainOutput
		assert.are.equals(60, off.BleedChance)
		assert.are.equals(40, off.PoisonChance)
		assert.are.equals(0, off.FrostbiteChance)

		setMods(table.concat({
			"+60% chance to inflict Bleed",
			"+40% chance to inflict Poison",
			"100% of Bleed and Poison Chance converted to Frostbite Chance with Puncture",
		}, "\n"))
		local on = build.calcsTab.mainOutput
		assert.are.equals(0, on.BleedChance, "Bleed chance converted away")
		assert.are.equals(0, on.PoisonChance, "Poison chance converted away")
		-- 60 (Bleed) + 40 (Poison) = 100, accumulated into Frostbite, capped at 100.
		assert.are.equals(100, on.FrostbiteChance, "Bleed+Poison chance summed into Frostbite")
	end)

	it("Troaka's end-to-end: a DIFFERENT skill is untouched (skill-scope is exact)", function()
		-- Same mods, but the active skill is Fireball, not Puncture -> no conversion.
		build.skillsTab:SelSkill(1, "Fireball")
		setMods(table.concat({
			"+60% chance to inflict Bleed",
			"+40% chance to inflict Poison",
			"100% of Bleed and Poison Chance converted to Frostbite Chance with Puncture",
		}, "\n"))
		local o = build.calcsTab.mainOutput
		assert.are.equals(60, o.BleedChance, "Bleed untouched on a non-Puncture skill")
		assert.are.equals(40, o.PoisonChance, "Poison untouched on a non-Puncture skill")
		assert.are.equals(0, o.FrostbiteChance, "no Frostbite gained on a non-Puncture skill")
	end)
end)
