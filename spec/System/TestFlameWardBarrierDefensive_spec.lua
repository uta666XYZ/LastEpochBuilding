-- @leb-regression-guard:tree-node-defensive-hit-damage
-- Locks the node-scoped rewrite that fixes Flame Ward's "Barrier" node
-- (fw3d-18) being misparsed as an OFFENSIVE DPS penalty.
--
-- Root cause (confirmed on saved build "ShutFackUp lv85 Spellblade", a Shatter
-- Strike Spellblade that allocates fw3d-18 at rank 5):
--   * fw3d-18 "Barrier" per-point stat string = "8% Less Hit Damage".
--   * In-game it is DEFENSIVE — TreeData/1_4/tree_1.json description:
--       "You take less damage from hits while Flame Ward is active
--        (multiplicative with other modifiers)."
--   * But the bare string "X% Less Hit Damage" is byte-identical in FORM to the
--     ~90 OFFENSIVE "hit damage" tree nodes ("<skill> hits deal less/more
--     damage"). ModParser parses it as % less + ModFlag.Hit + name "Damage" =
--     an offensive -X% hit damage DEALT.
--   * The node is gated behind the Flame Ward while-active buff
--     (LE_WHILE_ACTIVE_BUFF_BY_TREE_ID "fw3d" -> "HaveFlameWard"), so ticking
--     the "Do you have Flame Ward active?" config applied -40% (8% x 5) to the
--     player's OUTGOING DPS. Measured FullDPS 16853 -> 10534 (x0.604) before
--     the fix; after the fix 16853 -> 17351 (Barrier mitigation now lands on
--     EHP, the fw3d-12 Fire Aura grant adds a little DoT). Deterministic &
--     reversible (idempotent recompute, not a calc-order artifact).
--
-- Fix: src/Data/Global.lua LE_TREE_NODE_STAT_REWRITE maps fw3d-18's
-- "...Less Hit Damage" -> "...less hit damage taken"; PassiveTree:ProcessStats
-- applies it on the raw per-point string BEFORE rank scaling (so the leading
-- value still multiplies). "less hit damage taken" -> ModParser name
-- "DamageTaken" + ModFlag.Hit = a mitigation mod, not a DPS penalty.
--
-- The rewrite MUST stay node-scoped: mush9-6 "Point Blank" also carries the
-- words "less hit damage" but is OFFENSIVE ("Multishot deals less hit damage as
-- it travels"). A blanket string rule would wrongly flip it, so this spec also
-- asserts mush9-6 is NOT registered.
--
-- See REGRESSION_GUARDS.md "tree-node-defensive-hit-damage".

describe("FlameWardBarrierDefensive", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	local function firstMod(s)
		local list = modLib.parseMod(s)
		assert.is_not_nil(list, "parseMod returned nil for: " .. s)
		assert.is_true(#list >= 1, "parseMod returned no mods for: " .. s)
		return list[1]
	end

	it("registry: LE_TREE_NODE_STAT_REWRITE rewrites fw3d-18 'Less Hit Damage' -> '...taken'", function()
		assert.is_not_nil(LE_TREE_NODE_STAT_REWRITE, "global registry must exist")
		local entry = LE_TREE_NODE_STAT_REWRITE["fw3d-18"]
		assert.is_not_nil(entry, "fw3d-18 (Barrier) must be registered")
		-- Applying every registered rewrite to the raw per-point stat must yield
		-- the defensive "taken" phrasing (number untouched; scaling happens later).
		local stat = "8% Less Hit Damage"
		for _, rw in ipairs(entry) do
			stat = (stat:gsub(rw.pat, rw.repl))
		end
		assert.are.equal("8% less hit damage taken", stat)
		-- Number-tolerant: a re-tuned per-point value still rewrites correctly.
		local hi = ("13% Less Hit Damage"):gsub(entry[1].pat, entry[1].repl)
		assert.are.equal("13% less hit damage taken", (hi))
	end)

	it("parse contract: the rewrite flips Damage(Hit) [offensive] -> DamageTaken(Hit) [defensive]", function()
		-- Bare string (what every non-registered 'hit damage' node still produces).
		local off = firstMod("40% Less Hit Damage")
		assert.are.equal("Damage", off.name)        -- player's OUTGOING damage pool
		assert.are.equal("MORE", off.type)
		assert.are.equal(-40, off.value)
		assert.are.equal(ModFlag.Hit, bit.band(off.flags, ModFlag.Hit),
			"bare 'Less Hit Damage' must carry the Hit flag (offensive)")

		-- Rewritten string -> mitigation pool. Same type/value/flag; ONLY the
		-- mod name changes, which is what moves it off the DPS path.
		local def = firstMod("40% less hit damage taken")
		assert.are.equal("DamageTaken", def.name)   -- incoming-damage (mitigation) pool
		assert.are.equal("MORE", def.type)
		assert.are.equal(-40, def.value)
		assert.are.equal(ModFlag.Hit, bit.band(def.flags, ModFlag.Hit),
			"'less hit damage taken' must carry the Hit flag (defensive)")

		assert.are_not.equal(off.name, def.name,
			"the rewrite must change the mod name so it leaves the outgoing-damage pool")
	end)

	it("game-file: fw3d-18 'Barrier' is the defensive node the registry targets", function()
		local tree = readFile("TreeData/1_4/tree_1.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_1.json")
		assert.is_truthy(tree:find('"fw3d%-18"', 1, false), "fw3d-18 must exist in tree_1.json")
		assert.is_truthy(tree:find('"Barrier"', 1, true), "Barrier node name must exist")
		assert.is_truthy(tree:find("Less Hit Damage", 1, true),
			"the Barrier stat string the rewrite keys on must still be present")
		assert.is_truthy(tree:find("[Yy]ou take less damage from hits", 1, false),
			"the DEFENSIVE description that justifies the rewrite must still be present")
	end)

	it("scope guard: mush9-6 'Point Blank' (OFFENSIVE 'less hit damage') must NOT be registered", function()
		-- Point Blank: "Multishot deals less hit damage as it travels" — genuinely
		-- offensive. If a future change tries to generalise the rewrite to a
		-- string rule, this fails loudly.
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["mush9-6"],
			"only nodes confirmed defensive may be registered; mush9-6 is offensive")
	end)

	it("source: PassiveTree applies the rewrite before rank scaling; Global holds the registry", function()
		local pt = readFile("Classes/PassiveTree.lua")
		assert.is_not_nil(pt, "must read Classes/PassiveTree.lua")
		assert.is_truthy(pt:find("@leb%-regression%-guard:tree%-node%-defensive%-hit%-damage", 1, false),
			"PassiveTree.lua must carry the inline guard marker")
		assert.is_truthy(pt:find("LE_TREE_NODE_STAT_REWRITE%[node%.id%]", 1, false),
			"PassiveTree.lua must look the rewrite up by node.id")
		-- The rewrite block must precede the rank-scaling block so the value scales.
		local rewriteAt = pt:find("LE_TREE_NODE_STAT_REWRITE%[node%.id%]", 1, false)
		local scaleAt = pt:find("node%.alloc > 1 and stat:match", 1, false)
		assert.is_not_nil(scaleAt, "rank-scaling guard line must exist")
		assert.is_true(rewriteAt < scaleAt,
			"rewrite must run BEFORE the rank-scaling block (so the leading value still multiplies)")

		local g = readFile("Data/Global.lua")
		assert.is_not_nil(g, "must read Data/Global.lua")
		assert.is_truthy(g:find("LE_TREE_NODE_STAT_REWRITE", 1, true),
			"Global.lua must define the registry")
		assert.is_truthy(g:find('%["fw3d%-18"%]', 1, false),
			"Global.lua registry must contain fw3d-18")
	end)
end)
