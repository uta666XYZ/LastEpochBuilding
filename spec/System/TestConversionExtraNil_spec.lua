-- @leb-regression-guard:conversion-extra-nil-not-empty
-- Locks the contract that a fully-parsed arrow conversion (e.g. "Fire -> Cold")
-- leaves NO meaningful residue, and that skill-tree / passive-tree nodes apply
-- the conversion into node.modList.
--
-- Two coupled invariants:
--   (1) parser site (ModParser.lua): the arrow-conversion branch must return
--       `extra = nil` (not "") for a clean conversion, matching the clean-parse
--       convention at the parseMod tail (`line:match("%S") and line`).
--   (2) consumer site (PassiveTree.lua ProcessStats): the modifier-applied gate
--       must treat BOTH nil AND "" as "no residue" — because legacy ModCache.lua
--       entries were baked by the old parser and store the pair {modList, ""}
--       (e.g. `c[" Fire -> Cold"]={{...},""}`). `not ""` is false in Lua, so the
--       old gate `if mod.list and not mod.extra` silently dropped EVERY tree-node
--       conversion (Flame Ward "fw3d-6 Frost Ward" " Fire -> Cold", which
--       "globally converts Fire Aura to cold"), so the cross-skill Fire->Cold
--       conversion never reached Fire Aura's skillModList.
--
-- Establishing observation (headless _FireAuraTest, Flame Ward forced active):
--   pre-fix  Fire Aura skillModList FireDamageConvertToCold = 0  (node.modList empty)
--   post-fix Fire Aura skillModList FireDamageConvertToCold = 100 (conversion reaches skill)
--
-- Same failure mode as @leb-regression-guard:dodge-more-multiplier.
-- See REGRESSION_GUARDS.md > "conversion-extra-nil-not-empty".

describe("ConversionExtraNilNotEmpty", function()
    before_each(function()
        newBuild()
    end)

    it("live-parse 'Fire -> Cold' returns FireDamageConvertToCold with nil extra", function()
        -- 'Fire -> Cold' (no leading space) is NOT a ModCache key, so it
        -- exercises the live ModParser arrow-conversion branch.
        local mods, extra = modLib.parseMod("Fire -> Cold")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        assert.are.equals("FireDamageConvertToCold", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(100, mods[1].value)
    end)

    it("tree node ' Fire -> Cold' applies the conversion to node.modList despite extra==''", function()
        -- ' Fire -> Cold' (leading space) is the exact Flame Ward fw3d-6 stat and
        -- is served from ModCache with extra=="". The consumer must apply it.
        local node = { id = "test-conv-extra-guard", stats = { " Fire -> Cold" }, alloc = 1 }
        build.spec.tree:ProcessStats(node)
        local sum = node.modList:Sum("BASE", nil, "FireDamageConvertToCold")
        assert.are.equals(100, sum,
            "tree-node ' Fire -> Cold' must add FireDamageConvertToCold BASE 100 to node.modList")
    end)

    it("a tree node with a genuine non-empty residue is still dropped (no over-matching)", function()
        -- Guard the converse: only an EMPTY residue is treated as clean. A node
        -- whose stat leaves real leftover text must NOT leak a partial mod.
        local node = { id = "test-conv-residue-guard",
            stats = { "40 Retaliation Freeze Rate" }, alloc = 1 }
        build.spec.tree:ProcessStats(node)
        -- "Retaliation" is unconsumed residue → FreezeRate BASE must NOT be added.
        local sum = node.modList:Sum("BASE", nil, "FreezeRate")
        assert.are.equals(0, sum,
            "non-empty residue must still gate the mod out of node.modList")
    end)
end)
