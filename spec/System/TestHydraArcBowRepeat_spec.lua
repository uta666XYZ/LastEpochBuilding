-- @leb-regression-guard:hydra-arc-bow-repeat
-- Locks ModParser's handling of Hydra Arc's (uniques_1_4.json uniqueID 441)
-- verbatim mod string "100% chance to Repeat your most recent Bow Attack after
-- Evading". Before the fix the line fell through the generic parse chain to an
-- empty ModCache row ({{}," to Repeat your most recent  after Evading "}) -- a
-- silent no-op, so the repeat reached no computed entity. The handler routes it
-- to the existing RepeatCount/output.Repeats mechanism
-- (CalcOffence output.Repeats = 1 + Sum("BASE", skillCfg, "RepeatCount")),
-- scoped to KeywordFlag.Bow (the affix repeats a *Bow Attack*) and gated on the
-- EXISTING Condition:UsingEvade (ConfigOptions "Are you Using Evade?", default
-- OFF) because the repeat only happens "after Evading".
--
-- Coverage:
--   * parseMod: verbatim affix -> RepeatCount BASE 1, NO extra residue,
--     keywordFlags == KeywordFlag.Bow, carries a Condition:UsingEvade tag.
--   * gating (via Sum with a crafted cfg): contributes 1 only for a Bow-keyword
--     cfg AND UsingEvade; 0 without the evade condition; 0 for a non-bow cfg.
--   * corpus-neutrality: with the default (UsingEvade OFF) a build's
--     output.Repeats stays 1 (the parsed mod is inert => byte-identical snapshots,
--     blast 0, no regen).
--   * DPS-inert HONESTY LOCK: output.Repeats does NOT raise sustained TotalDPS
--     for a cooldown-less bow attack (every LE bow attack has cooldown=None), so
--     a RepeatCount is a burst-display-only quantity here. This asserts the
--     REFUTED verdict so a future reader does not mistake the 0 Full-DPS reach
--     for an under-count and "fix" it by fabricating a multiplier.
-- See REGRESSION_GUARDS.md "hydra-arc-bow-repeat".

local AFFIX = "100% chance to Repeat your most recent Bow Attack after Evading"

local function findRepeatCount(mods)
	if not mods then return nil end
	for _, m in ipairs(mods) do
		if m.name == "RepeatCount" then return m end
	end
	return nil
end

describe("hydra-arc-bow-repeat: parseMod -> bow-scoped, UsingEvade-gated RepeatCount", function()
	it("verbatim affix parses to RepeatCount BASE 1 with no residue", function()
		local mods, extra = modLib.parseMod(AFFIX)
		assert.is_nil(extra, "whole-line anchored rule must leave no `extra` residue")
		local m = findRepeatCount(mods)
		assert.is_not_nil(m, "expected a RepeatCount mod")
		assert.are.equals("BASE", m.type)
		assert.are.equals(1, m.value) -- 100% -> 1 repeat
	end)

	it("the RepeatCount is scoped to the Bow keyword", function()
		local m = findRepeatCount(modLib.parseMod(AFFIX))
		assert.are.equals(KeywordFlag.Bow, m.keywordFlags,
			"repeat must apply only to bow attacks")
	end)

	it("the RepeatCount carries a Condition:UsingEvade tag", function()
		local m = findRepeatCount(modLib.parseMod(AFFIX))
		assert.is_not_nil(m[1], "must carry a condition tag (after Evading)")
		assert.are.equals("Condition", m[1].type)
		assert.are.equals("UsingEvade", m[1].var)
	end)
end)

describe("hydra-arc-bow-repeat: gating (bow AND evade)", function()
	before_each(function()
		newBuild()
		build.configTab.input.customMods = AFFIX
		build.configTab:BuildModList()
	end)

	it("contributes RepeatCount 1 only for a Bow cfg WITH UsingEvade", function()
		local ml = build.configTab.modList
		assert.are.equals(1, ml:Sum("BASE", { keywordFlags = KeywordFlag.Bow, skillCond = { UsingEvade = true } }, "RepeatCount"),
			"bow attack while using Evade must get the repeat")
	end)

	it("contributes 0 for a Bow cfg WITHOUT UsingEvade (default -> inert)", function()
		local ml = build.configTab.modList
		assert.are.equals(0, ml:Sum("BASE", { keywordFlags = KeywordFlag.Bow, skillCond = { UsingEvade = false } }, "RepeatCount"),
			"without the evade condition the repeat must be inert")
	end)

	it("contributes 0 for a non-bow cfg even WITH UsingEvade", function()
		local ml = build.configTab.modList
		assert.are.equals(0, ml:Sum("BASE", { skillCond = { UsingEvade = true } }, "RepeatCount"),
			"a spell/melee main skill must not be repeated")
	end)
end)

describe("hydra-arc-bow-repeat: corpus-neutral by default + DPS-inert honesty lock", function()
	before_each(function()
		newBuild()
	end)

	it("with UsingEvade OFF (default) a bow attack keeps output.Repeats = 1", function()
		build.configTab.input.customMods = AFFIX
		build.configTab:BuildModList()
		build.skillsTab:SelSkill(1, "Detonating Arrow")
		build.buildFlag = true
		runCallback("OnFrame")
		assert.are.equals(1, build.calcsTab.mainOutput.Repeats,
			"default (no evade) must leave output.Repeats at 1 -> corpus byte-identical")
	end)

	it("HONESTY LOCK: a RepeatCount does NOT raise TotalDPS on a cooldown-less bow attack", function()
		-- Every LE bow attack has cooldown=None, so the cooldown Speed-cap
		-- (the only path by which output.Repeats feeds TotalDPS) never fires.
		-- output.Repeats therefore only moves burst-DISPLAY fields, NOT FullDPS.
		local function totalDps(withRepeat)
			newBuild()
			local mods = "+1000 Physical Damage"
			if withRepeat then mods = mods .. "\n1 Recasts" end -- RepeatCount BASE 1
			build.configTab.input.customMods = mods
			build.configTab:BuildModList()
			build.skillsTab:SelSkill(1, "Detonating Arrow")
			build.buildFlag = true
			runCallback("OnFrame")
			return build.calcsTab.mainOutput.TotalDPS, build.calcsTab.mainOutput.Repeats
		end
		local base, baseR = totalDps(false)
		local rep, repR = totalDps(true)
		assert.are.equals(1, baseR)
		assert.are.equals(2, repR, "RepeatCount BASE 1 must bump output.Repeats to 2")
		assert.are.equals(base, rep,
			"TotalDPS must be UNCHANGED by the repeat (burst-display-only for cooldown-less attacks)")
	end)
end)
