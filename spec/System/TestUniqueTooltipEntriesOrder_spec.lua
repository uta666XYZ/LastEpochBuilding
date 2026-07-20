-- @leb-regression-guard: unique-tooltip-entries-display-order
-- Locks the rule that a unique's tooltip is rendered from the GAME's `tooltipEntries`
-- (entry <128 -> mods[entry], entry >=128 -> tooltipDescriptions[entry-128]), NOT from
-- LEB's `mods[]` order, and that doing so never touches the mechanics.
--
-- WHY THIS IS NOT COSMETIC
-- `mods[]` is the ModParser input, i.e. the mechanics carrier. 464 of the 699 rows LEB
-- marks "NOT SUPPORTED IN LEB YET" still emit real modDB mods, so rewriting a mod string
-- into in-game prose would silently delete mechanics. This layer is ADDITIVE: it only
-- chooses which modLine is drawn and in what order.
--
-- IN-GAME GROUNDING (the gate; datamine alone is not sufficient)
--   11  Exsanguinous     tooltipEntries [3,4,128,129] -> 4 lines, descriptions LAST
--   413 Shattered Worlds tooltipEntries [128,129,...] -> 6 lines, descriptions FIRST
-- Both verified against screenshots of the real item. The pair is deliberate: it refutes
-- "descriptions always come first" -- order is decided by tooltipEntries and nothing else.
-- Exsanguinous also proves the row count is not the line count: 6 rows -> 4 lines, because
-- its 3 hidden speed mods fold into one description.
--
-- STAGED ROLLOUT -- AND WHAT "RESOLVED" DOES NOT MEAN
-- Only items whose LEB-row <-> game-mod correspondence RESOLVED carry tooltipEntries (430 of
-- 471). RESOLVED = matched structurally against the game data (property/type/tags/value
-- signature). It does NOT mean confirmed in-game: only the two items above were read off
-- screenshots. Structural agreement with the export is not in-game truth -- the same line
-- this project draws everywhere else (reference_corpus_selfconsistency_not_ingame). Neither
-- the code nor the tooltip may imply the other 428 were verified against the game.
-- An item without tooltipEntries MUST fall back to mods[] order. The plan also bails out if
-- the inherent-line count stops matching #mods, rather than drawing a confident lie.
--
-- See REGRESSION_GUARDS.md "unique-tooltip-entries-display-order".

local dkjson = require("dkjson")

describe("Unique tooltip entries display order #parser", function()
	local function readFile(relPath)
		for _, p in ipairs({ relPath, "src/" .. relPath, "../src/" .. relPath }) do
			local f = io.open(p, "r")
			if f then
				local text = f:read("*a")
				f:close()
				return text
			end
		end
		error("must be able to open " .. relPath)
	end

	local function liveEntries()
		local out = {}
		local uniques = dkjson.decode(readFile("Data/Uniques/uniques_1_4.json"))
		for key, entry in pairs(uniques) do
			if type(entry) == "table" then out[tonumber(key)] = entry end
		end
		local sets = dkjson.decode(readFile("Data/Set/set_1_4.json"))
		for _, entry in pairs(sets) do
			if type(entry) == "table" and entry.uniqueID and not out[entry.uniqueID] then
				out[entry.uniqueID] = entry
			end
		end
		return out
	end

	-- Synthetic inherent modLines standing in for a parsed item, in mods[] order.
	local function inherentLinesFor(entry)
		local lines = {}
		for i, text in ipairs(entry.mods) do
			lines[i] = { line = text, uniqueInherent = true }
		end
		return lines
	end

	local function renderedLines(entry)
		local plan = itemLib.buildUniqueTooltipPlan(inherentLinesFor(entry), entry)
		assert.is_table(plan)
		local out = {}
		for i, planEntry in ipairs(plan) do
			out[i] = planEntry.text or planEntry.modLine.line
		end
		return out, plan
	end

	it("renders Exsanguinous as the 4 lines the game shows, descriptions LAST", function()
		local entry = liveEntries()[11]
		assert.same({ 3, 4, 128, 129 }, entry.tooltipEntries)
		local lines = renderedLines(entry)
		assert.are.equal(4, #lines)
		assert.are.equal("20% of Current Health Lost per second", lines[1])
		assert.are.equal("20% of Missing Health gained as Ward per second", lines[2])
		assert.is_truthy(lines[3]:find("increased attack speed, cast speed, and movement speed", 1, true))
		assert.is_truthy(lines[4]:find("Immunity to Bleed", 1, true))
		-- the 3 hidden speed mods folded into line 3 are NOT drawn on their own
		for _, line in ipairs(lines) do
			assert.is_nil(line:find("increased Attack Speed for 4 seconds", 1, true))
		end
	end)

	it("renders Shattered Worlds with descriptions FIRST (order is tooltipEntries, nothing else)", function()
		local entry = liveEntries()[413]
		local lines = renderedLines(entry)
		assert.are.equal(6, #lines)
		assert.is_truthy(lines[1]:find("immune to Slow", 1, true))
		assert.is_truthy(lines[2]:find("Haste", 1, true))
		assert.is_truthy(lines[3]:find("Critical Strike Chance", 1, true))
	end)

	it("does not reorder or rewrite mods[] (mechanics are untouched)", function()
		local entry = liveEntries()[11]
		local before = {}
		for i, text in ipairs(entry.mods) do before[i] = text end
		local lines = inherentLinesFor(entry)
		itemLib.buildUniqueTooltipPlan(lines, entry)
		assert.same(before, entry.mods)
		for i, text in ipairs(before) do
			assert.are.equal(text, lines[i].line) -- input list order preserved
		end
	end)

	it("falls back (nil plan) when the item's correspondence was never resolved", function()
		local entry = { mods = { "+10 Health" }, rollIds = { 0 } }
		assert.is_nil(itemLib.buildUniqueTooltipPlan(inherentLinesFor(entry), entry))
	end)

	it("bails out rather than mis-index when the inherent-line count drifts from #mods", function()
		local entry = liveEntries()[11]
		local lines = inherentLinesFor(entry)
		table.remove(lines) -- e.g. a future producer drops or splits a line
		assert.is_nil(itemLib.buildUniqueTooltipPlan(lines, entry))
	end)

	it("counts folded unsupported mods for the item-level note instead of marking a description", function()
		local entry = liveEntries()[11]
		local lines = inherentLinesFor(entry)
		lines[1].notSupported = true -- a hidden mod folded into description 0
		local plan = itemLib.buildUniqueTooltipPlan(lines, entry)
		assert.are.equal(1, plan.foldedNotSupported)
		for _, planEntry in ipairs(plan) do
			assert.is_nil(planEntry.text and planEntry.text:find("NOT SUPPORTED", 1, true))
		end
	end)

	it("no baked description carries control characters or stray edge whitespace", function()
		-- The game export leaks CRLF and hard line breaks into description text (6 rows
		-- ended in a bare \r, one embedded \n, one had a trailing space). A tooltip renders
		-- one string per line, so baking those verbatim emits control characters into the
		-- UI. The generator collapses them to a single space; a regen must keep doing so.
		local offenders = {}
		for uid, entry in pairs(liveEntries()) do
			for i, desc in ipairs(entry.tooltipDescriptions or {}) do
				if desc:find("[%z\1-\31\127]") or desc:match("^%s") or desc:match("%s$") then
					offenders[#offenders + 1] = ("uid %d desc %d: %q"):format(uid, i - 1, desc)
				end
			end
		end
		assert.same({}, offenders)
	end)

	it("every baked tooltipEntry resolves inside its own item", function()
		local checked = 0
		for uid, entry in pairs(liveEntries()) do
			if entry.tooltipEntries then
				checked = checked + 1
				for _, e in ipairs(entry.tooltipEntries) do
					if e < 128 then
						assert.is_truthy(entry.mods[e + 1],
							("uid %d: tooltipEntries mod index %d out of range"):format(uid, e))
					else
						assert.is_truthy(entry.tooltipDescriptions and entry.tooltipDescriptions[e - 128 + 1],
							("uid %d: tooltipEntries desc index %d out of range"):format(uid, e - 128))
					end
				end
			end
		end
		assert.is_true(checked >= 400, "expected the verified majority to be baked, got " .. checked)
	end)
end)
