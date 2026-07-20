-- @leb-regression-guard:wrongwarp-inline-rebuild-310
-- @leb-regression-guard:chronowarp-buff-conditional
-- Wrongwarp (unique 310, src/Data/Uniques/uniques_1_4.json) was rebuilt to the in-game
-- item. Ground truth = the datamine's tooltipEntries [128,129,130,0,1,131], which decode
-- (>=128 -> tooltipDescriptions[v-128], <128 -> mods[v]) to 6 display lines, confirmed
-- 6/6 against an in-game screenshot. tooltipEntries is the ONLY authority on order --
-- "descriptions come first" is REFUTED (Exsanguinous 11 puts them last).
--
-- LEB carried 6 rows, of which THREE do not exist in the game data at all:
--   "(5-10)% Increased Cooldown Recovery Speed for Teleport"    -- REAL mechanics
--   "(5-10)% Increased Cooldown Recovery Speed for Transplant"  -- REAL mechanics
--   "(-3 to -5) Mana Cost for Spell Skills"                     -- inert ({{},"..."})
-- The game's Wrongwarp has NO cooldown-recovery and NO mana-cost mod; its only cooldown
-- text is desc3, a minimum-cooldown FLOOR ("minimum cooldown of 3 seconds"), which is the
-- opposite of cooldown recovery. These rows are identical across uniques.json / _1_2 /
-- _1_3 / _1_4, so they are NOT a 1.4 patch removal -- they are a LETools transcription
-- artifact (the mana-cost row entered in <see git log> "apply letools 1.1-1.4 balance
-- changes"; the CDR rows in <see git log> / <see git log>). Only the LIVE file (_1_4,
-- GameVersions.lua latestTreeVersion) is rebuilt: 1.2/1.3 are not grounded in-game.
--
-- A fourth row, "+1 Wrongwarp with Teleport or Transplant", is the LETools fallback-
-- formatter artifact for the game's HIDDEN mod[2] (property 58 = "Dark Protection
-- (deprecated)" + specialTag 2, hideInTooltip=true) which folds into desc0. It parsed to
-- {{},""} -- empty modList AND empty text, i.e. carried nothing. It is replaced by desc0's
-- real text. See guard unique-hideintooltip-letools-artifact.
--
-- rollIds: the game's ONLY rollable mod is mods[0] (property 50, canRoll=true, rollID 0)
-- = the Haste line. rollId 1 was used ONLY by the two fabricated CDR rows, so it drops out
-- as a CONSEQUENCE of deleting them -- the export was never used to "fix" rollIds (its
-- mods[].rollID is proven unreliable, e.g. Apiarist's Suit 78). rollIds is a roll-GROUP id
-- and NOT a line index (guard unique-shared-rollids-not-independent, <see git log>); the
-- import reads d[uniqueIDIndex+2+rollId], so a stray id reads an unwritten byte.
--
-- Chronowarp (desc1) is modelled CONDITIONALLY, never always-on: the buff lasts 10s behind
-- a Teleport/Transplant cast, so uptime is a playstyle question. ModParser emits the stats
-- tagged {Condition:Chronowarp} with the 35 CAPTURED from the data line (no hardcoding, no
-- curve-fit); ConfigOptions' conditionChronowarp check sets the FLAG and is itself gated by
-- ifCond="Chronowarp" -> mainEnv.conditionsUsed, so it only appears when Wrongwarp is
-- equipped. See REGRESSION_GUARDS.md.

describe("WrongwarpChronowarp #parser #unique #buff", function()
	local WRONGWARP = 310

	local function wrongwarp()
		local uniques = readJsonFile("Data/Uniques/uniques_1_4.json")
		assert.is_not_nil(uniques, "uniques_1_4.json must load")
		local e = uniques[tostring(WRONGWARP)] or uniques[WRONGWARP]
		assert.is_not_nil(e, "unique 310 must exist in the LIVE file")
		return e
	end

	-- 1. Data truth: the 6 rows, in tooltipEntries order ------------------------------
	it("mods[] is the 6 in-game lines in tooltipEntries order", function()
		local e = wrongwarp()
		assert.are.equal("Wrongwarp", e.name)
		local expected = {
			"When you cast Teleport or Transplant you are teleported to a random nearby location, become immune to all damage for 1 second, and gain Chronowarp for 10 seconds.",
			"Chronowarp grants 35% increased cast speed and movement speed",
			"When you cast teleport or transplant you time lock up to 10 enemies around the destination for 1 second. Bosses are slowed instead of time locked.",
			"(10-35)% Chance to gain Haste for 1 second on Hit",
			"2% increased Spell Damage per 1% increased Movement Speed",
			"Teleport and Transplant have a minimum cooldown of 3 seconds",
		}
		assert.are.equal(#expected, #e.mods, "exactly 6 rows")
		for i, want in ipairs(expected) do
			assert.are.equal(want, e.mods[i], "row " .. i)
		end
	end)

	-- 2. The three fabricated rows are gone -------------------------------------------
	it("carries no cooldown-recovery and no mana-cost row (not in game data)", function()
		local e = wrongwarp()
		for i, m in ipairs(e.mods) do
			assert.is_falsy(m:lower():find("cooldown recovery", 1, true),
				"row " .. i .. " must not be a fabricated CDR row: " .. m)
			assert.is_falsy(m:lower():find("mana cost", 1, true),
				"row " .. i .. " must not be the fabricated mana-cost row: " .. m)
		end
	end)

	-- 3. The LETools fallback artifact is gone -----------------------------------------
	it("carries no '+1 Wrongwarp with ...' fallback-formatter artifact", function()
		local e = wrongwarp()
		for i, m in ipairs(e.mods) do
			assert.is_falsy(m:find("+1 Wrongwarp", 1, true),
				"row " .. i .. " must not be the hideInTooltip artifact: " .. m)
		end
	end)

	-- 4. rollIds: only the Haste row rolls, and it uses the game's rollID 0 ------------
	-- NOTE: do NOT assert on #e.rollIds. JSON null decodes to Lua nil, so rollIds is a
	-- SPARSE table and # is undefined for it (with a null in slot 1 it reports 0). This is
	-- not new or broken -- the old [0,null,null,1,1,null] was equally sparse. Both real
	-- consumers walk ipairs(mods) and index rollIds[i] directly, guarded by a nil check
	-- (Build.lua:1015 `rollIds[i] ~= nil`, ImportTab.lua:2001 `if rollId then`); neither
	-- ever takes a length. Assert the invariant that actually holds instead.
	it("rollIds marks only the Haste row rollable, with the game's rollID 0", function()
		local e = wrongwarp()
		assert.are.equal(0, e.rollIds[4], "the Haste row is game mods[0], rollID 0")
		for i = 1, #e.mods do
			if i ~= 4 then
				assert.is_nil(e.rollIds[i], "row " .. i .. " must not roll")
			end
		end
	end)

	-- The rollId lookup is gated by itemLib.hasRange, so every ranged row needs a rollId
	-- and every rollId needs a ranged row -- otherwise a roll is silently dropped
	-- (range -> defaultItemAffixQuality) or a rollId reads a byte nothing wrote.
	it("exactly one row has a range, and it is the row that carries the rollId", function()
		local e = wrongwarp()
		local ranged = {}
		for i, m in ipairs(e.mods) do
			if itemLib.hasRange(m) then table.insert(ranged, i) end
		end
		assert.are.same({ 4 }, ranged, "only the Haste row is rollable in-game")
		assert.is_not_nil(e.rollIds[4], "the ranged row must have a rollId to import its roll")
	end)

	it("no row claims the stray rollId 1 (only the deleted CDR rows ever used it)", function()
		local e = wrongwarp()
		for i, r in pairs(e.rollIds) do
			assert.are_not.equal(1, r, "row " .. i .. " must not carry the stray rollId 1")
		end
	end)

	-- 5. Chronowarp parse contract -----------------------------------------------------
	-- Number captured from the string: a rebalanced line must follow, not need a code edit.
	local cases = { 35, 20, 50 }
	for _, n in ipairs(cases) do
		it("'Chronowarp grants " .. n .. "% ...' -> Speed(Cast) + MovementSpeed INC " .. n .. ", no residue", function()
			local line = "Chronowarp grants " .. n .. "% increased cast speed and movement speed"
			local list, extra = modLib.parseMod(line)
			assert.is_not_nil(list, "must parse")
			assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
			assert.are.equal(2, #list, "exactly two stats")

			local speed, move = list[1], list[2]
			assert.are.equal("Speed", speed.name)
			assert.are.equal("INC", speed.type)
			assert.are.equal(n, speed.value)
			assert.are.equal(ModFlag.Cast, speed.flags, "cast speed = Speed + ModFlag.Cast")

			assert.are.equal("MovementSpeed", move.name)
			assert.are.equal("INC", move.type)
			assert.are.equal(n, move.value)
			assert.are.equal(0, move.flags, "movement speed carries no ModFlag")

			-- NOT notSupported: these are real, DPS-integrated mods.
			assert.is_falsy(list.notSupported, "Chronowarp is modelled, not a NotSupported label")

			for _, m in ipairs(list) do
				assert.are.equal(1, #m, "exactly one tag")
				assert.are.equal("Condition", m[1].type)
				assert.are.equal("Chronowarp", m[1].var)
			end
		end)
	end

	-- 6. modDB delivery: gated by the condition, never always-on -----------------------
	it("the buff is inert until Condition:Chronowarp is set", function()
		local list = modLib.parseMod("Chronowarp grants 35% increased cast speed and movement speed")
		local db = new("ModDB")
		for _, m in ipairs(list) do db:AddMod(m) end

		-- Condition unset = the buff is down. This is the whole point of the conditional:
		-- an always-on flat mod would fake 35% cast speed for every Wrongwarp build.
		assert.are.equal(0, db:Sum("INC", { flags = ModFlag.Cast }, "Speed"), "cast speed off while Chronowarp is down")
		assert.are.equal(0, db:Sum("INC", nil, "MovementSpeed"), "movement speed off while Chronowarp is down")

		db:NewMod("Condition:Chronowarp", "FLAG", true, "Config")
		assert.are.equal(35, db:Sum("INC", { flags = ModFlag.Cast }, "Speed"), "cast speed on while Chronowarp is up")
		assert.are.equal(35, db:Sum("INC", nil, "MovementSpeed"), "movement speed on while Chronowarp is up")
	end)

	it("the cast-speed mod is scoped to casts (does not leak onto attacks)", function()
		local list = modLib.parseMod("Chronowarp grants 35% increased cast speed and movement speed")
		local db = new("ModDB")
		for _, m in ipairs(list) do db:AddMod(m) end
		db:NewMod("Condition:Chronowarp", "FLAG", true, "Config")
		assert.are.equal(0, db:Sum("INC", { flags = ModFlag.Attack }, "Speed"), "must not grant attack speed")
	end)

	-- 7. The config option exists, is gated, and does NOT re-emit the stats ------------
	it("ConfigOptions carries conditionChronowarp gated by ifCond", function()
		local f = io.open("Modules/ConfigOptions.lua", "r") or io.open("src/Modules/ConfigOptions.lua", "r")
			or io.open("../src/Modules/ConfigOptions.lua", "r")
		assert.is_not_nil(f, "must be able to open ConfigOptions.lua")
		local txt = f:read("*a"); f:close()

		local entry = txt:match('{ var = "conditionChronowarp".-end },')
		assert.is_not_nil(entry, "conditionChronowarp option must exist")
		assert.is_truthy(entry:find('ifCond = "Chronowarp"', 1, true),
			"must be gated by ifCond so it only shows when Wrongwarp is equipped")
		assert.is_truthy(entry:find('Condition:Chronowarp', 1, true), "must set the FLAG")
		-- Unlike Frenzy/Haste, the stats come from the ITEM row. Emitting them here too
		-- would double-count against the ModParser handler.
		assert.is_falsy(entry:find('"Speed", "INC"', 1, true), "must not re-emit cast speed (double-count)")
		assert.is_falsy(entry:find('"MovementSpeed", "INC"', 1, true), "must not re-emit movement speed (double-count)")
	end)

	-- 8. Non-collision: the generic cast-speed chain is untouched -----------------------
	it("does not shadow the generic 'increased Cast Speed' parse", function()
		local list = modLib.parseMod("10% increased Cast Speed")
		assert.are.equal(1, #list)
		assert.are.equal("Speed", list[1].name)
		assert.are.equal(10, list[1].value)
		assert.are.equal(0, #list[1], "generic form carries no Condition tag")
	end)

	-- 9. The other three description rows are display-only, not red UNSUPPORTED --------
	-- @leb-regression-guard:display-only-tooltip-text
	-- These three are tooltipDescriptions in the game data, i.e. not modifiers. Without
	-- the displayOnlyModList entries they parse to {} + a whole-line `extra`, which
	-- formatModLine paints red UNSUPPORTED -- the exact lie that guard exists to stop.
	-- extra must be nil, NOT "": an empty string is truthy in Lua and paints red too.
	describe("display-only description rows", function()
		-- Bypass ModCache so the LIVE parser is exercised, then restore.
		local function reparse(line)
			local saved = modLib.parseModCache[line]
			modLib.parseModCache[line] = nil
			local mods, extra = modLib.parseMod(line)
			modLib.parseModCache[line] = saved
			return mods, extra
		end

		local DISPLAY_ONLY = {
			"When you cast Teleport or Transplant you are teleported to a random nearby location, become immune to all damage for 1 second, and gain Chronowarp for 10 seconds.",
			"When you cast teleport or transplant you time lock up to 10 enemies around the destination for 1 second. Bosses are slowed instead of time locked.",
			"Teleport and Transplant have a minimum cooldown of 3 seconds",
		}

		for _, line in ipairs(DISPLAY_ONLY) do
			it(("%q -> no mod, no residue"):format(line:sub(1, 40)), function()
				local mods, extra = reparse(line)
				assert.is_not_nil(mods, "must return an empty mod list, not nil")
				assert.are.equal(0, #mods, "display-only text must not produce a ghost mod")
				assert.is_nil(extra, "extra must be nil, not \"\" -- a truthy extra paints red UNSUPPORTED")
			end)
		end

		it("are not painted red by formatModLine", function()
			for _, line in ipairs(DISPLAY_ONLY) do
				local mods, extra = reparse(line)
				local out = itemLib.formatModLine({ line = line, modList = mods, extra = extra })
				assert.is_not_nil(out, ("%q must not be hidden entirely"):format(line:sub(1, 40)))
				assert.is_nil(out:find(colorCodes.UNSUPPORTED, 1, true),
					("%q must not render as UNSUPPORTED"):format(line:sub(1, 40)))
			end
		end)

		it("every Wrongwarp row either parses to a mod or is display-only (none red)", function()
			local e = wrongwarp()
			for i, line in ipairs(e.mods) do
				-- Resolve the roll range the way the item pipeline does before parsing,
				-- so the Haste row is tested in its real, concrete form.
				local probe = line:gsub("%((%d+)%-(%d+)%)", "%1")
				local mods, extra = reparse(probe)
				local out = itemLib.formatModLine({ line = probe, modList = mods, extra = extra })
				assert.is_not_nil(out, "row " .. i .. " must render: " .. line)
				assert.is_nil(out:find(colorCodes.UNSUPPORTED, 1, true),
					"row " .. i .. " must not render red UNSUPPORTED: " .. line)
			end
		end)
	end)
end)
