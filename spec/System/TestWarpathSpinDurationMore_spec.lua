-- @leb-regression-guard:warpath-warslash-spin-duration-more
-- Warpath "Giant Splitter" (va53st-21, Warpath tree, TreeData/1_4/tree_2.json,
-- maxPoints 5) charge-time MORE-all-damage. The node grants:
--   stats           [" Warslash After Warpath",
--                    "+15% Slash Damage Per Second Spinning",
--                    "+15% Area Per Second Spinning"]
--   notScalingStats ["5 Maximum Duration Benefit (seconds)"]
--   description "After spinning for at least 2 seconds you do a {Warslash} when
--   you stop spinning. This deals more damage (multiplicative with other
--   modifiers) in a larger area for each second you spent spinning, up to a
--   maximum duration."
-- GAME-SOURCE values:
--   * per-second MORE = 15% per second per allocated point (tree_2.json
--     "+15% Slash Damage Per Second Spinning"; baked ModCache parsed it to
--     Damage MORE 15).
--   * duration cap = 5s (notScalingStats "5 Maximum Duration Benefit (seconds)"
--     -> Duration BASE 5).
-- datamining formula (datamined game source .../c_spawn_specs datamined game source):
--   MoreStat(min(spinSeconds, 5) x (15% x pointsAllocated)).
--
-- Implementation (mirrors aerial-prowess-per-stack, but the "per second spinning"
-- phrase is UNIQUE to this node so NO LE_TREE_NODE_STAT_REWRITE is needed -- the
-- tag is routed directly in ModParser):
--   * ModParser modNameList ["slash damage"] = "Damage": consumes the "Slash"
--     melee-delivery descriptor (NOT a modeled damage type) so the line resolves
--     to a generic Damage MORE with NO residue. Without it "Slash" stays as
--     residue and PassiveTree.lua's non-empty-extra gate (L566) DROPS the node
--     mod -- the AerialProwess pre-fix failure mode.
--   * ModParser modTagList ["per second spinning"] = Multiplier:WarpathSpinSeconds
--     (limit 5 = the node's "5 Maximum Duration Benefit (seconds)" cap).
--   * va53st-21 is deliberately NOT in LE_TREE_NODE_GLOBAL_SCOPE, so the DEFAULT
--     owning-skill SkillId tag (node.skillId == "Warpath") scopes the MORE to
--     Warpath -- modeling the in-game stored-MORE carried onto the Warslash fired
--     when Warpath ends.
--   * ConfigOptions "Seconds spent Spinning (Warpath, max 5)" (ifMult
--     WarpathSpinSeconds, default 0 -> strict no-op; corpus-neutral, no build
--     allocates va53st-21). apply clamps with math.min(val, 5).
--   * Data/ModCache.lua: the stale FLAT-baked "+15% Slash Damage Per Second
--     Spinning" row was REMOVED so the live parser regenerates it WITH the
--     multiplier (the Ambition/Germination/AerialProwess REMOVE-not-patch
--     precedent). The sibling "+15% Area Per Second Spinning" baked row is LEFT
--     in place (inert) -- this fix is scoped to the per-second Damage MORE only;
--     the Warslash sub-ability (and its larger-area benefit) is NOT modeled here
--     (its base hit damage is absent from prefab/subprefab/attribute datamine).
-- Per-second stacking is ADDITIVE within the mod (one MORE of value x seconds).
-- See REGRESSION_GUARDS.md "warpath-warslash-spin-duration-more".

describe("WarpathSpinDurationMore #skills", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	local function findTag(mod, tagType, var)
		for _, tag in ipairs(mod) do
			if tag.type == tagType and (var == nil or tag.var == var) then
				return tag
			end
		end
		return nil
	end

	it("parse contract: 'Slash Damage Per Second Spinning' -> Damage MORE 15 x Multiplier:WarpathSpinSeconds (limit 5), no residue, no SkillId", function()
		local list, extra = modLib.parseMod("+15% Slash Damage Per Second Spinning")
		assert.is_not_nil(list, "must parse")
		-- "Slash" must be consumed (modNameList ["slash damage"]); a non-empty extra
		-- would be dropped by the PassiveTree non-empty-extra gate.
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(15, mod.value)
		local mult = findTag(mod, "Multiplier", "WarpathSpinSeconds")
		assert.is_not_nil(mult, "must carry Multiplier:WarpathSpinSeconds")
		assert.are.equal(5, mult.limit, "limit must cap at 5 (the node's '5 Maximum Duration Benefit (seconds)')")
		assert.is_nil(findTag(mod, "SkillId"), "parse must not produce a SkillId tag (scope comes from the tree node)")
	end)

	it("scope: va53st-21 stays owning-skill scoped (NOT lifted to global scope)", function()
		assert.is_table(LE_TREE_NODE_GLOBAL_SCOPE, "LE_TREE_NODE_GLOBAL_SCOPE must be defined")
		assert.is_nil(LE_TREE_NODE_GLOBAL_SCOPE["va53st-21"],
			"the spin-charge MORE is consumed by / scoped to Warpath, so the default SkillId scope must stay -- do NOT global-lift")
		-- no node-keyed stat rewrite is used for this fix (the phrase is unique)
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["va53st-21"],
			"the 'per second spinning' phrase is unique, so no LE_TREE_NODE_STAT_REWRITE is needed")
	end)

	it("tree node end-to-end: va53st-21 emits a MORE Damage mod scoped to Warpath (SkillId kept)", function()
		newBuild()
		local node = build.spec.nodes["va53st-21"]
		assert.is_not_nil(node, "va53st-21 must exist in the loaded 1.4 tree")
		assert.are.equal("Warpath", node.skillId, "va53st-21 must be a Warpath skill-subtree node")
		node.alloc = 1
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then found = mod end
		end
		assert.is_not_nil(found, "Giant Splitter must emit a MORE Damage mod (not dropped by the residue gate)")
		assert.are.equal(15, found.value, "1 point -> +15% per second")
		assert.is_not_nil(findTag(found, "Multiplier", "WarpathSpinSeconds"),
			"the node mod must be per-second-spinning")
		local skillTag = findTag(found, "SkillId")
		assert.is_not_nil(skillTag, "the SkillId scoping must be KEPT -- the spin-charge MORE only buffs Warpath")
		assert.are.equal("Warpath", skillTag.skillId)
	end)

	it("rank scaling: 5 points -> per-second value 75 (15 x 5), the leading value only", function()
		newBuild()
		local node = build.spec.nodes["va53st-21"]
		node.alloc = 5
		build.spec.tree:ProcessStats(node)
		local found
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then found = mod end
		end
		assert.is_not_nil(found, "must emit the MORE Damage mod at 5 points")
		assert.are.equal(75, found.value, "5 points must rank-scale +15% -> +75% per second")
		assert.are.equal(5, (findTag(found, "Multiplier", "WarpathSpinSeconds") or {}).limit,
			"the seconds cap (limit 5) must survive rank scaling")
	end)

	it("behaviour: scoped MORE = 15% x seconds x points (cap 5s); 0 = no-op; other skills unaffected", function()
		newBuild()
		local node = build.spec.nodes["va53st-21"]
		node.alloc = 5
		build.spec.tree:ProcessStats(node)
		local spinMod
		for _, mod in ipairs(node.modList) do
			if mod.name == "Damage" and mod.type == "MORE" then spinMod = mod end
		end
		assert.is_not_nil(spinMod, "must have the per-second MORE Damage mod (5 points)")

		local warpathCfg = { skillGrantedEffect = { id = "Warpath" } }
		local otherCfg = { skillGrantedEffect = { id = "Some Other Skill" } }
		local function moreAt(seconds, cfg)
			local modDB = new("ModDB")
			modDB:AddMod(spinMod)
			modDB.multipliers.WarpathSpinSeconds = seconds
			return modDB:More(cfg, "Damage")
		end

		-- 0 seconds (default) -> strict no-op
		assert.are.equal(1, moreAt(0, warpathCfg))
		-- 5 seconds at 5 points -> +75% x 5 = +375% MORE (4.75x)  [task assertion (b)]
		assert.is_true(math.abs(moreAt(5, warpathCfg) - 4.75) < 1e-9,
			"5s x 5 points must give 4.75 MORE, got " .. tostring(moreAt(5, warpathCfg)))
		-- cap: 10 seconds must still be +375% (parser limit 5)
		assert.is_true(math.abs(moreAt(10, warpathCfg) - 4.75) < 1e-9,
			"10s must cap at 4.75 MORE, got " .. tostring(moreAt(10, warpathCfg)))
		-- scope: a non-Warpath skill gets nothing even at 5 seconds  [task assertion (c)]
		assert.are.equal(1, moreAt(5, otherCfg))
	end)

	it("config: 'Seconds spent Spinning (Warpath, max 5)' is ifMult-gated and clamps at 5", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierWarpathSpinSeconds".-end },')
		assert.is_not_nil(entry, "multiplierWarpathSpinSeconds config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		assert.is_truthy(entry:find('ifMult = "WarpathSpinSeconds"', 1, true),
			"must be visibility-gated on the WarpathSpinSeconds multiplier being referenced (Throne/AerialProwess pattern)")
		assert.is_truthy(entry:find("max 5", 1, true), "label must carry the cap hint '(max 5)'")
		assert.is_truthy(entry:find('NewMod("Multiplier:WarpathSpinSeconds", "BASE", math.min(val, 5), "Config"', 1, true),
			"apply must set Multiplier:WarpathSpinSeconds clamped with math.min(val, 5)")
	end)

	it("ModCache: the stale FLAT Slash-Damage row was removed; the Area sibling row was left inert", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		assert.is_nil(src:find('c["+15% Slash Damage Per Second Spinning"]', 1, true),
			"the stale residue-bearing Damage row must be removed so the live parser regenerates it with Multiplier:WarpathSpinSeconds")
		-- the Area sibling is intentionally NOT swept into this fix: its baked row stays,
		-- keeping it inert (Damage-only scope).
		assert.is_not_nil(src:find('c["+15% Area Per Second Spinning"]', 1, true),
			"the '+15% Area Per Second Spinning' baked row must be LEFT in place (Damage-only scope)")
	end)

	it("Area sibling stays inert: '+15% Area Per Second Spinning' still parses with residue (not multiplier-tagged)", function()
		local list, extra = modLib.parseMod("+15% Area Per Second Spinning")
		assert.is_not_nil(list)
		-- baked row short-circuits the live parser, so it keeps the old AreaOfEffect
		-- BASE 15 with residue (dropped by the tree gate) -- this fix does not touch it.
		assert.is_truthy(extra and extra ~= "", "Area row must remain inert (residue present), got: " .. tostring(extra))
		assert.is_nil(findTag(list[1] or {}, "Multiplier", "WarpathSpinSeconds"),
			"the Area mod must NOT carry the spin multiplier (Damage-only scope)")
	end)

	it("name mapping: 'slash damage' resolves to generic Damage with zero corpus collision", function()
		-- "Slash" is a melee-delivery descriptor, not a modeled damage type; the
		-- mapping must produce the same generic Damage name as bare "damage".
		local list = modLib.parseMod("+10 Slash Damage")
		assert.is_not_nil(list)
		assert.are.equal("Damage", (list[1] or {}).name, "'Slash Damage' must resolve to the generic Damage name")
	end)

	it("game-file: va53st-21 still carries the stat strings and the per-second/maximum-duration description", function()
		local tree = readFile("TreeData/1_4/tree_2.json")
		assert.is_not_nil(tree, "must read TreeData/1_4/tree_2.json")
		assert.is_truthy(tree:find('"va53st%-21"', 1, false))
		assert.is_truthy(tree:find("Giant Splitter", 1, true))
		assert.is_truthy(tree:find("+15% Slash Damage Per Second Spinning", 1, true),
			"the Slash-Damage-per-second stat string the tag keys on must still be present")
		assert.is_truthy(tree:find("5 Maximum Duration Benefit (seconds)", 1, true),
			"the maximum-duration stat backing the 5s cap must still be present")
		assert.is_truthy(tree:find("for each second you spent spinning", 1, true),
			"the per-second more-damage description that justifies the multiplier must still be present")
	end)
end)
