-- @leb-regression-guard:void-knight-echo-more
-- Locks the Void Knight ascendancy-START ("mastery bonus") ECHO model -- the SECOND
-- stat on the tree_2.json "Void Knight" isAscendancyStart node:
--   "Your melee attacks, throwing attacks and void spells have a 10% chance to be
--    repeated by an echo 0.5s later (excludes movement abilities and Anomaly)."
--
-- MECHANIC (datamining): the echo is a FULL re-cast of the ability 0.5s later
-- (CreateVoidKnightEchoAfterDelay), it does NOT chain (Property_Player_81), and
-- "increased Echo Damage" defaults to 0 (Property_Player_57) -- so the echo deals the
-- ability's full damage. A P% chance to repeat the whole ability therefore multiplies
-- average output by (1 + P/100), i.e. it is a +P% MORE Damage on every eligible skill.
--
-- THE BUG THIS GUARDS: the echo line is bare prose with no "N% more/increased/added"
-- form, so ModParser produced NOTHING and PassiveTree:ProcessStats flagged it node.extra
-- -> the bonus was entirely UNMODELLED (a flat ~+10% DPS miss on every Void Knight that
-- swings a melee/throwing/void skill). The fix is a whole-line specialModList handler
-- that captures the chance into a VoidKnightEchoChance BASE player mod (residue-free --
-- a trailing-period `extra` would re-drop it, the <see git log> trap), which CalcActiveSkill
-- turns into a per-skill Damage MORE over the any-of eligibility set minus movement/Anomaly.
--
-- Ground truth: in-game Void Knight PASSIVE BONUSES tooltip (user screenshot 2026-07-06)
-- + datamining See memory project_erasing_strike_perhit_under / project_mastery_bonus_unmodeled
-- and REGRESSION_GUARDS.md.

local ECHO = "Your melee attacks, throwing attacks and void spells have a 10% chance to be repeated by an echo 0.5s later (excludes movement abilities and Anomaly)."

local function readSource(relPath)
	local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
	assert.is_not_nil(f, "must be able to open " .. relPath)
	local text = f:read("*a")
	f:close()
	return text
end

local function liveParse(line)
	if modLib.parseModCache then modLib.parseModCache[line] = nil end
	return modLib.parseMod(line)  -- returns list, extra (extra MUST be nil/empty or the
	                              -- mod is DROPPED from the tree node's modList in-build)
end

describe("VoidKnightEcho", function()
	before_each(function()
		newBuild()
	end)

	it("tree_2.json still carries the verbatim echo bonus on the mastery-start node", function()
		local tree = readSource("TreeData/1_4/tree_2.json")
		assert.is_truthy(tree:find('"Void Knight"', 1, true), "mastery-start node present")
		assert.is_truthy(tree:find("10% chance to be repeated by an echo", 1, true),
			"the echo bonus text must still exist -- if LE re-tunes the chance or wording, " ..
			"RE-MEASURE and update the specialModList pattern + this expectation")
		assert.is_truthy(tree:find("excludes movement abilities and Anomaly", 1, true),
			"the exclusion clause (movement + Anomaly) must still be present")
	end)

	it("the echo line parses to VoidKnightEchoChance BASE 10 with NO residue", function()
		local list, extra = liveParse(ECHO)
		assert.is_not_nil(list and list[1], "the echo line must now produce a mod (was UNPARSED)")
		local m = list[1]
		assert.are.equals("VoidKnightEchoChance", m.name)
		assert.are.equals("BASE", m.type)
		assert.are.equals(10, m.value, "10% repeat chance captured verbatim")
		-- The load-bearing check: a trailing-period / leftover `extra` here means the mod
		-- is silently dropped from the tree node (the <see git log> residue trap).
		assert.is_true(extra == nil or not tostring(extra):match("%S"),
			"echo line must parse with NO extra residue (got: " .. tostring(extra) .. ")")
	end)

	it("captures the chance value (future-proof if LE re-tunes the percentage)", function()
		local list = liveParse("Your melee attacks, throwing attacks and void spells have a 15% chance to be repeated by an echo 0.5s later (excludes movement abilities and Anomaly).")
		assert.is_not_nil(list and list[1])
		assert.are.equals("VoidKnightEchoChance", list[1].name)
		assert.are.equals(15, list[1].value, "the MORE% tracks the tooltip chance, not a hardcoded 10")
	end)

	it("does NOT match unrelated echo/repeat lines (pattern is anchored to the VK bonus)", function()
		-- A different 'repeated by an echo' phrasing must not accidentally grant the VK chance.
		local list = liveParse("Your spells have a 20% chance to be repeated by an echo.")
		local granted = false
		for _, m in ipairs(list or {}) do
			if m.name == "VoidKnightEchoChance" then granted = true break end
		end
		assert.is_false(granted, "only the full Void Knight mastery line grants VoidKnightEchoChance")
	end)

	it("src/Data/ModCache.lua has NO stale empty entry for the echo line (else parseMod short-circuits it)", function()
		-- THE LOAD-BEARING CORPUS GUARD. parseMod short-circuits on an exact parseModCache
		-- key (Main.lua loads Data/ModCache into modLib.parseModCache). A STALE
		-- c["<echo line>"]={{},"<residue>"} row (baked when the line was UNPARSED, before the
		-- specialModList handler existed) makes parseMod return the cached EMPTY mod and NEVER
		-- run the handler -- so in a real build the bonus is silently dropped even though the
		-- cache-clearing parser tests above pass. Observed on corpus VoidCleaver lv84 VK:
		-- VoidKnightEchoChance stayed 0 / DPS unchanged until this row was removed (then
		-- 37,793 -> 41,573 = x1.100). A ModCache regen re-adds a CORRECT (VoidKnightEchoChance)
		-- row, which is fine; only the empty {{},...} form is the bug.
		local mc = readSource("Data/ModCache.lua")
		local stale = mc:match('c%["Your melee attacks, throwing attacks and void spells have a 10%% chance to be repeated by an echo[^\n]-%]=%{%{%},')
		assert.is_nil(stale,
			"ModCache has a STALE empty-mod entry for the echo line -- parseMod short-circuits on it and " ..
			"bypasses the VoidKnightEchoChance handler in real builds. Delete that row (or regen ModCache " ..
			"so it holds the VoidKnightEchoChance parse).")
	end)
end)
