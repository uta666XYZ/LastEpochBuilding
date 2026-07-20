-- @leb-regression-guard:recast-parse
-- Locks ModParser's handling of LE skill-tree recast `stats` strings and the
-- routing into the existing RepeatCount/output.Repeats mechanism
-- (CalcOffence.lua:783). Before the fix, every recast form fell through the
-- generic parse chain to an empty mod list and was baked into ModCache.lua as
-- `{{}, "...residue..."}`, so Shatter Strike "Whiteout" (1 Recasts), Iceblink
-- ("+6% Chance for Two Recasts with Two Handed Weapon") and Chaos Bolts
-- ("10% Chance to recast") never produced a RepeatCount mod — output.Repeats
-- stayed 1 (corpus-wide parse gap, found from the melee-weapon-base-damage
-- SS-tree-node investigation, 2026-06-01).
--
-- Coverage:
--   * parseMod direct: the three cached forms (these also validate the patched
--     ModCache.lua rows, since parseMod returns the cached value) PLUS two
--     uncached forms ("2 Recasts", "+12% ... One Handed Weapon") that force a
--     LIVE parse through the new specialModList handlers.
--   * end-to-end: customMods route a RepeatCount into the skill mod list and
--     bump output.Repeats; the weapon-conditional variant is gated on the
--     UsingTwoHandedWeapon condition.
--   * scope boundary: divergent-semantics recast strings (on-kill auto-recast,
--     spread-on-recast, skill-named "Recast Chance") deliberately produce NO
--     RepeatCount.
-- See REGRESSION_GUARDS.md "recast-parse".

local function findRepeatCount(mods)
	if not mods then return nil end
	for _, m in ipairs(mods) do
		if m.name == "RepeatCount" then return m end
	end
	return nil
end

describe("recast parse-gap: parseMod -> RepeatCount", function()
	it("'1 Recasts' parses to RepeatCount BASE 1 (cached form / ModCache row)", function()
		local mods, extra = modLib.parseMod("1 Recasts")
		assert.is_nil(extra)
		local m = findRepeatCount(mods)
		assert.is_not_nil(m, "expected a RepeatCount mod")
		assert.are.equals("BASE", m.type)
		assert.are.equals(1, m.value)
		assert.is_nil(m[1], "plain 'N Recasts' must carry no condition tag")
	end)

	it("'2 Recasts' parses to RepeatCount BASE 2 (uncached -> live parser, point-scaled form)", function()
		local mods, extra = modLib.parseMod("2 Recasts")
		assert.is_nil(extra)
		local m = findRepeatCount(mods)
		assert.is_not_nil(m)
		assert.are.equals("BASE", m.type)
		assert.are.equals(2, m.value)
	end)

	it("'+6% Chance for Two Recasts with Two Handed Weapon' -> RepeatCount 0.12 gated UsingTwoHandedWeapon (cached form)", function()
		local mods, extra = modLib.parseMod("+6% Chance for Two Recasts with Two Handed Weapon")
		assert.is_nil(extra)
		local m = findRepeatCount(mods)
		assert.is_not_nil(m)
		assert.are.equals("BASE", m.type)
		assert.are.equals(0.12, m.value) -- 6% * 2 recasts
		assert.is_not_nil(m[1], "weapon-conditional recast must carry a Condition tag")
		assert.are.equals("Condition", m[1].type)
		assert.are.equals("UsingTwoHandedWeapon", m[1].var)
	end)

	it("'+12% Chance for Two Recasts with One Handed Weapon' -> RepeatCount 0.24 gated UsingOneHandedWeapon (uncached -> live parser)", function()
		local mods, extra = modLib.parseMod("+12% Chance for Two Recasts with One Handed Weapon")
		assert.is_nil(extra)
		local m = findRepeatCount(mods)
		assert.is_not_nil(m)
		assert.are.equals("BASE", m.type)
		assert.are.equals(0.24, m.value) -- 12% * 2 recasts
		assert.is_not_nil(m[1])
		assert.are.equals("Condition", m[1].type)
		assert.are.equals("UsingOneHandedWeapon", m[1].var)
	end)

	it("'10% Chance to recast' parses to RepeatCount BASE 0.1 (cached form / Chaos Bolts)", function()
		local mods, extra = modLib.parseMod("10% Chance to recast")
		assert.is_nil(extra)
		local m = findRepeatCount(mods)
		assert.is_not_nil(m)
		assert.are.equals("BASE", m.type)
		assert.are.equals(0.1, m.value)
		assert.is_nil(m[1], "unconditional chance-to-recast must carry no condition tag")
	end)
end)

describe("recast parse-gap: scope boundary (no RepeatCount for divergent forms)", function()
	-- These have different in-game semantics (kill-chain / combo-spread /
	-- per-resource / expire re-trigger) and are intentionally NOT routed to
	-- RepeatCount. Guard against a future over-broad pattern catching them.
	local outOfScope = {
		"Automatically Recasts On Kill",
		"Spread On Recast",
		"10% Black Hole Recast Chance",
		"+10% Recast Chance per Symbol Consumed",
	}
	for _, line in ipairs(outOfScope) do
		it("'" .. line .. "' produces no RepeatCount mod", function()
			local mods = modLib.parseMod(line)
			assert.is_nil(findRepeatCount(mods),
				"'" .. line .. "' must not be routed to RepeatCount")
		end)
	end
end)

describe("recast parse-gap: RepeatCount -> output.Repeats mechanism", function()
	before_each(function()
		newBuild()
	end)

	it("a global '1 Recasts' RepeatCount lands in the skill mod list and bumps output.Repeats to 2", function()
		build.configTab.input.customMods = "1 Recasts"
		build.configTab:BuildModList()
		assert.are.equals(1, build.configTab.modList:Sum("BASE", nil, "RepeatCount"),
			"customMods '1 Recasts' must contribute RepeatCount BASE 1")
		build.skillsTab:SelSkill(1, "Fireball")
		build.buildFlag = true
		runCallback("OnFrame")
		assert.are.equals(1, build.calcsTab.mainEnv.player.mainSkill.skillModList:Sum("BASE", nil, "RepeatCount"),
			"RepeatCount must reach the active skill's skillModList")
		-- CalcOffence.lua:783  output.Repeats = 1 + Sum(RepeatCount)
		assert.are.equals(2, build.calcsTab.mainOutput.Repeats,
			"output.Repeats must become 1 + RepeatCount = 2")
	end)

	it("weapon-conditional recast is gated by the UsingTwoHandedWeapon condition", function()
		build.configTab.input.customMods = "+6% Chance for Two Recasts with Two Handed Weapon"
		build.configTab:BuildModList()
		assert.are.equals(0, build.configTab.modList:Sum("BASE", nil, "RepeatCount"),
			"with no weapon condition set the gated recast must contribute 0")
		assert.are.equals(0.12, build.configTab.modList:Sum("BASE", { skillCond = { UsingTwoHandedWeapon = true } }, "RepeatCount"),
			"with a two-handed weapon the recast must contribute 0.12")
	end)
end)
