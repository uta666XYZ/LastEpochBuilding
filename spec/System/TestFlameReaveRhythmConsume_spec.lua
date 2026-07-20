-- @leb-regression-guard:flame-reave-rhythm-consume
-- See REGRESSION_GUARDS.md "flame-reave-rhythm-consume".
-- Validation provenance is retained in maintainer notes.

describe("FlameReaveRhythmConsume #skills", function()
	local function readSource(p) local f = io.open(p, "r"); if not f then return nil end local s = f:read("*a"); f:close(); return s end
	local function findTag(mod, tt, val)
		for _, t in ipairs(mod) do
			if t.type == tt and (val == nil or t.var == val or t.skillId == val) then return t end
		end
	end

	it("parse: '+130% Damage when consuming Rhythm of Fire' -> Damage MORE 130 + Condition:ConsumingRhythmOfFire, no residue", function()
		local list, extra = modLib.parseMod("+130% Damage when consuming Rhythm of Fire")
		assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		assert.are.equal("Damage", list[1].name)
		assert.are.equal("MORE", list[1].type)
		assert.are.equal(130, list[1].value)
		assert.is_not_nil(findTag(list[1], "Condition", "ConsumingRhythmOfFire"), "must carry the consume Condition")
	end)

	it("raw stat still drops (residue) -- this is what the rewrite fixes", function()
		local _, extra = modLib.parseMod("+130% Damage when consuming 12 stacks")
		assert.is_truthy(extra and extra ~= "", "raw stat must leave residue (PassiveTree then drops it)")
	end)

	it("LE_TREE_NODE_STAT_REWRITE['fr11mv-3'] rewrites the consume Damage line residue-free", function()
		local rules = LE_TREE_NODE_STAT_REWRITE["fr11mv-3"]
		assert.is_table(rules, "fr11mv-3 must have a rewrite entry")
		local raw = "+130% Damage when consuming 12 stacks"
		for _, rule in ipairs(rules) do raw = raw:gsub(rule.pat, rule.repl) end
		assert.are.equal("+130% Damage when consuming Rhythm of Fire", raw)
	end)

	it("tree node fr11mv-3: ProcessStats emits Damage MORE 130 scoped to FlameReave + consume Condition", function()
		newBuild()
		local node = build.spec.nodes["fr11mv-3"]
		assert.is_not_nil(node, "fr11mv-3 must exist in the loaded 1.4 tree")
		node.alloc = 1
		build.spec.tree:ProcessStats(node)
		local found
		for _, m in ipairs(node.modList or {}) do if m.name == "Damage" and m.type == "MORE" then found = m end end
		assert.is_not_nil(found, "consume MORE must survive the residue gate")
		assert.are.equal(130, found.value)
		assert.is_not_nil(findTag(found, "Condition", "ConsumingRhythmOfFire"), "gated by consume Condition")
		assert.is_not_nil(findTag(found, "SkillId", "FlameReave"), "scoped to Flame Reave (node skillId)")
	end)

	it("modDB gating: consume Condition off -> x1.00; on -> x2.30", function()
		local db = new("ModDB")
		db.actor = { output = {}, modDB = db }
		db:NewMod("Damage", "MORE", 130, "test", { type = "Condition", var = "ConsumingRhythmOfFire" })
		assert.are.equal(1, db:More(nil, "Damage"), "consume off -> no bonus (default OFF = corpus-neutral)")
		db.conditions["ConsumingRhythmOfFire"] = true
		assert.is_true(math.abs(db:More(nil, "Damage") - 2.30) < 1e-9, "consume on -> +130% MORE = x2.30")
	end)

	it("config toggle 'conditionConsumingRhythmOfFire' exists (default OFF, ifCond-hidden)", function()
		local src = readSource("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read ConfigOptions.lua")
		local entry = src:match('{ var = "conditionConsumingRhythmOfFire".-end },')
		assert.is_not_nil(entry, "toggle entry must exist")
		assert.is_truthy(entry:find('type = "check"', 1, true))
		assert.is_truthy(entry:find('ifCond = "ConsumingRhythmOfFire"', 1, true), "hidden unless the build carries the node")
		assert.is_truthy(entry:find("Condition:ConsumingRhythmOfFire", 1, true), "apply sets the Condition")
	end)

	it("game-file: fr11mv-3 still carries the consume Damage stat", function()
		local tree = readSource("TreeData/1_4/tree_1.json")
		assert.is_not_nil(tree)
		assert.is_truthy(tree:find("+130% Damage when consuming 12 stacks", 1, true),
			"the consume stat the rewrite keys on must still be present (retune surfaces here)")
	end)
end)
