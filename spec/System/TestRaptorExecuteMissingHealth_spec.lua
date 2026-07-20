-- @leb-regression-guard:raptor-execute-missing-health-more
-- Locks the Beastmaster Raptor "Cornered" (srtor-20) missing-health MORE model.
--
-- MECHANIC (datamine-grounded; datamining RaptorFireBreathMutator__getTempStats
-- datamined offset + skill_trees_raw.json srtor-20 "Cornered", maxPoints 3):
-- the Raptor deals MORE damage per 1% of ITS OWN missing health (NOT the
-- target's), capped at 50% missing -> up to +50% more per allocated point at
-- <=50% HP. Fire Breath / Screech / BasicMelee mutators share the scalar.
--
-- BUG: the bare stat "+1% Damage per 1% Missing Health" parses to a FLAT Damage
-- MORE (ModCache row -> MORE 1/pt, no missing-health scaling), so LEB gave the
-- Raptor a permanent +1..3% MORE regardless of health -- wrong at full HP, where
-- the in-game contribution is 0.
--
-- FIX: LE_TREE_NODE_STAT_REWRITE["srtor-20"] rewrites the per-point line to a
-- Raptor-scoped phrasing that ModParser maps to Damage MORE x
-- Multiplier:MissingHealthPercent (limit 50 = the 50%-missing cap). Full HP
-- (minion MissingHealthPercent = 0, the default) => x1.0 inert => corpus-neutral
-- (no corpus build allocates srtor-20). The Raptor's missing-health share is set
-- via the "raptorMissingHealthPercent" config (MinionModifier injection).
--
-- Asserts: (1) rewrite registered for srtor-20 and produces the tagged phrasing;
-- (2) node-gated: the raw (un-rewritten) line still parses to a FLAT MORE, so the
--     scaling only exists for the srtor-20-rewritten form; (3) full-HP inert:
--     MissingHealthPercent 0 -> x1.0; (4) magnitude + 50% cap match the datamine
--     formula; (5) config contract.

local function readSource(relPath)
	local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
	assert.is_not_nil(f, "must be able to open " .. relPath)
	local text = f:read("*a")
	f:close()
	return text
end

local function findTag(mod, tagType, var)
	for _, t in ipairs(mod) do
		if t.type == tagType and (var == nil or t.var == var) then return t end
	end
	return nil
end

describe("RaptorExecuteMissingHealth", function()
	it("registers a LE_TREE_NODE_STAT_REWRITE entry for srtor-20 (Cornered)", function()
		local src = readSource("Data/Global.lua")
		assert.is_truthy(string.find(src, '%["srtor%-20"%]'),
			"Global.lua must register LE_TREE_NODE_STAT_REWRITE['srtor-20']")
	end)

	it("the srtor-20 rewrite converts the missing-health line to the raptor phrasing", function()
		local entry = LE_TREE_NODE_STAT_REWRITE and LE_TREE_NODE_STAT_REWRITE["srtor-20"]
		assert.is_not_nil(entry, "LE_TREE_NODE_STAT_REWRITE['srtor-20'] must exist at runtime")
		local raw = "+1% Damage per 1% Missing Health"
		local rewritten = raw
		for _, rule in ipairs(entry) do rewritten = rewritten:gsub(rule.pat, rule.repl) end
		assert.are_equal("1% raptor damage per 1% missing health", rewritten,
			"the Cornered line must rewrite to the 'raptor damage per 1% missing health' form")
	end)

	it("the rewritten stat parses to a Damage MORE x Multiplier:MissingHealthPercent (limit 50)", function()
		local mods = modLib.parseMod("1% raptor damage per 1% missing health")
		assert.is_not_nil(mods, "rewritten stat must parse to at least one mod")
		assert.is_true(#mods >= 1, "rewritten stat must parse to a mod")
		local m = mods[1]
		assert.are_equal("Damage", m.name, "must be a Damage mod")
		assert.are_equal("MORE", m.type, "must be a MORE multiplier")
		local mult = findTag(m, "Multiplier", "MissingHealthPercent")
		assert.is_not_nil(mult, "must carry Multiplier{var=MissingHealthPercent} so it scales on the Raptor's missing HP")
		assert.are_equal(50, mult.limit, "the missing-health multiplier must be capped at 50 (the node's 50%-missing cap)")
	end)

	it("NODE-GATED: the un-rewritten (non-srtor-20) line parses to a FLAT MORE (no missing-health scaling)", function()
		-- Documents that the missing-health scaling exists ONLY via the srtor-20
		-- rewrite; any other source of the bare phrasing keeps the flat behaviour.
		local mods = modLib.parseMod("+1% Damage per 1% Missing Health")
		assert.is_not_nil(mods)
		assert.are_equal("Damage", mods[1].name)
		assert.are_equal("MORE", mods[1].type)
		assert.is_nil(findTag(mods[1], "Multiplier", "MissingHealthPercent"),
			"sanity: the bare line has NO missing-health multiplier (flat MORE) -- scaling is srtor-20-specific")
	end)

	-- Numeric contract: MORE% = perPointPoints x min(missingHealth%, 50).
	local function moreAt(rewrittenLine, missingPct)
		local mods = modLib.parseMod(rewrittenLine)
		local modDB = new("ModDB")
		modDB:AddMod(mods[1])
		modDB.multipliers.MissingHealthPercent = missingPct
		return modDB:More({}, "Damage")
	end

	it("FULL-HP INERT: MissingHealthPercent 0 -> x1.0 (corpus-neutral default)", function()
		assert.are_equal(1, moreAt("1% raptor damage per 1% missing health", 0),
			"at full HP the Cornered MORE must be a strict no-op")
		assert.are_equal(1, moreAt("3% raptor damage per 1% missing health", 0),
			"at full HP the 3-point Cornered MORE must be a strict no-op")
	end)

	it("MAGNITUDE + 50% CAP match the datamine formula", function()
		-- 1 point: +1% more per 1% missing, capped at 50% missing -> max +50% (x1.50).
		assert.is_true(math.abs(moreAt("1% raptor damage per 1% missing health", 20) - 1.20) < 1e-9,
			"1pt @ 20% missing -> x1.20")
		assert.is_true(math.abs(moreAt("1% raptor damage per 1% missing health", 50) - 1.50) < 1e-9,
			"1pt @ 50% missing -> x1.50 (cap)")
		assert.is_true(math.abs(moreAt("1% raptor damage per 1% missing health", 99) - 1.50) < 1e-9,
			"1pt @ 99% missing must CAP at x1.50 (50%-missing limit)")
		-- 3 points (maxPoints): +3% more per 1% missing, capped at 50% missing -> max +150% (x2.50).
		assert.is_true(math.abs(moreAt("3% raptor damage per 1% missing health", 30) - 1.90) < 1e-9,
			"3pt @ 30% missing -> x1.90")
		assert.is_true(math.abs(moreAt("3% raptor damage per 1% missing health", 50) - 2.50) < 1e-9,
			"3pt @ 50% missing -> x2.50 (cap)")
		assert.is_true(math.abs(moreAt("3% raptor damage per 1% missing health", 100) - 2.50) < 1e-9,
			"3pt @ 100% missing must CAP at x2.50 (50%-missing limit)")
	end)

	it("CONFIG: raptorMissingHealthPercent injects Multiplier:MissingHealthPercent onto minions", function()
		local src = readSource("Modules/ConfigOptions.lua")
		assert.is_truthy(string.find(src, 'var = "raptorMissingHealthPercent"', 1, true),
			"ConfigOptions must expose a raptorMissingHealthPercent config")
		-- It must feed the minion modDB (MinionModifier), NOT the player, and set
		-- the MissingHealthPercent multiplier the Cornered MORE reads.
		local seg = src:match('var = "raptorMissingHealthPercent".-end %}') or ""
		assert.is_truthy(string.find(seg, "MinionModifier", 1, true),
			"the raptor missing-health config must inject via MinionModifier (minion modDB)")
		assert.is_truthy(string.find(seg, "Multiplier:MissingHealthPercent", 1, true),
			"the raptor missing-health config must set Multiplier:MissingHealthPercent")
	end)
end)
