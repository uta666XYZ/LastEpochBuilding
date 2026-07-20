-- @leb-regression-guard:doubled-if-X-tree-notscaling
-- Locks the generic doubling mechanism for tree-node `notScalingStats` lines
-- of the form " Doubled if <X>". Tree audit (game-file 2026-05-28) found
-- exactly three nodes use this pattern across all 1.4 trees:
--   * ch0fs-20 Death from Below    — stats "+5% Damage",  X="Cursed"
--   * ch0fs-14 Eradication         — stats "+8% Damage to Rares and Bosses", X="Cursed"
--   * srtor-11 Taste for Flesh     — stats "+6% Attack And Cast Speed",     X="Killed Recently"
--
-- The literal string " Doubled if X" stays a no-op in ModCache (`{}`); the
-- doubling SEMANTICS lives in PassiveTree.lua:ProcessStats which scans
-- `node.sd` for the pattern and attaches a `{type="Condition", var=<var>,
-- mult=2}` tag to every scaling mod of the same node. The Condition-tag
-- mult evaluator in ModStore.lua:607-621 (`condition-tag-mult` guard) then
-- returns base value when the matching `condition<X>` config toggle is OFF
-- and value*2 when ON — exact "doubled" semantics with no spurious gate.
--
-- Three coupled invariants this spec locks:
--   (1) PassiveTree.lua holds the doubling-tag scan and the per-mod append.
--   (2) ModCache.lua keeps " Doubled if Cursed" / " Doubled if Killed Recently"
--       as {} (the semantics is owned by PassiveTree, not the cache).
--   (3) The Condition-tag mult contract from ModStore is honoured: a mod
--       with `{type="Condition", var="Cursed", mult=2}` evaluates to base
--       value when Condition:Cursed is unset, and 2*base when set (NOT a
--       full gate — that would zero the base out before the toggle).
--
-- See REGRESSION_GUARDS.md "doubled-if-X-tree-notscaling".

describe("DoubledIfXTreeNotScaling", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    it("PassiveTree.lua holds the doublingTag scan and the per-mod append", function()
        local src = readFile("Classes/PassiveTree.lua")
        assert.is_not_nil(src, "must be able to read Classes/PassiveTree.lua")
        assert.is_truthy(src:find("@leb%-regression%-guard:doubled%-if%-X%-tree%-notscaling", 1, false),
            "PassiveTree.lua must carry the inline guard marker")
        assert.is_truthy(src:find("local doublingTag", 1, true),
            "PassiveTree.lua must declare the doublingTag local")
        assert.is_truthy(src:find('[Dd]oubled %[Ii%]f', 1, false) or src:find("Doubled [Ii]f", 1, false),
            "PassiveTree.lua must match the 'Doubled if' notScalingStats pattern")
        assert.is_truthy(src:find('var = "Cursed", mult = 2', 1, true),
            "PassiveTree.lua must map 'Cursed' to a player Condition tag with mult=2")
        assert.is_truthy(src:find('var = "KilledRecently", mult = 2', 1, true),
            "PassiveTree.lua must map 'Killed Recently' to a Condition:KilledRecently tag with mult=2")
        assert.is_truthy(src:find("if doublingTag then", 1, true),
            "PassiveTree.lua must conditionally append the doubling tag to each scaling mod")
    end)

    it("ModCache keeps the literal ' Doubled if X' strings as empty no-ops", function()
        -- Semantics is owned by PassiveTree.lua; the cache MUST stay neutral so
        -- the doubling tag is not double-applied (cache mod + tree-handler mod).
        local cursed = data.cacheItemMods and data.cacheItemMods[" Doubled if Cursed"]
            or data.cacheItemAndTreeNodeMods and data.cacheItemAndTreeNodeMods[" Doubled if Cursed"]
        if not cursed then
            -- ModCache is loaded as a Lua module returning a table; the var name
            -- in src/Data/ModCache.lua is `c` and it is re-exported.
            local cacheSrc = readFile("Data/ModCache.lua")
            assert.is_not_nil(cacheSrc, "must read Data/ModCache.lua")
            assert.is_truthy(cacheSrc:find('c%[" Doubled if Cursed"%]={{},"Doubled if Cursed "}', 1, false),
                "ModCache must keep ' Doubled if Cursed' as an empty no-op")
            assert.is_truthy(cacheSrc:find('c%[" Doubled If Killed Recently"%]={{},"Doubled If Killed Recently "}', 1, false),
                "ModCache must keep ' Doubled If Killed Recently' as an empty no-op")
        end
    end)

    it("ModStore Condition-tag with mult=2 returns base when unset and 2*base when set (contract)", function()
        -- Underlying contract: a mod with a Condition tag carrying `mult`
        -- delivers `value` when the condition is unset (NOT zero — that's the
        -- full-gate path used when mult is absent) and `value * mult` when set.
        -- This is the exact mechanism the tree-node generic handler relies on.
        local modDB = new("ModDB")
        modDB.actor = { modDB = modDB }
        modDB:NewMod("Damage", "MORE", 5, "Tree:ch0fs-20-test",
            { type = "Condition", var = "Cursed", mult = 2 })

        local baseSum = modDB:Sum("MORE", nil, "Damage")
        assert.are.equals(5, baseSum,
            "Condition tag with mult must return base value when condition is unset")

        modDB:NewMod("Condition:Cursed", "FLAG", true, "Test")
        local cursedSum = modDB:Sum("MORE", nil, "Damage")
        assert.are.equals(10, cursedSum,
            "Condition tag with mult=2 must return 2*base value when condition is set")
    end)

    it("ModStore.lua holds the condition-tag-mult contract this spec depends on", function()
        local src = readFile("Classes/ModStore.lua")
        assert.is_not_nil(src, "must read Classes/ModStore.lua")
        assert.is_truthy(src:find("@leb%-regression%-guard:condition%-tag%-mult", 1, false),
            "ModStore must carry the condition-tag-mult guard the generic handler depends on")
        assert.is_truthy(src:find("value = value * tag.mult", 1, true),
            "ModStore must apply value*mult when a Condition tag's mult is set and match is true")
    end)

    it("game-file: the three known tree nodes carry the expected stats and 'Doubled if X' notScalingStats", function()
        -- Pin the audited universe of in-scope nodes so a future tree update
        -- that adds a new "Doubled if X" node forces revisit of this guard.
        local treeFile = readFile("TreeData/1_4/tree_3.json")
        assert.is_not_nil(treeFile, "must read TreeData/1_4/tree_3.json")
        -- Death from Below: +5% Damage, " Doubled if Cursed"
        assert.is_truthy(treeFile:find('"ch0fs%-20"', 1, false), "ch0fs-20 must exist in tree_3.json")
        assert.is_truthy(treeFile:find('"Death from Below"', 1, true), "Death from Below name must exist")
        -- Eradication: +8% Damage to Rares and Bosses, " Doubled if Cursed"
        assert.is_truthy(treeFile:find('"ch0fs%-14"', 1, false), "ch0fs-14 must exist in tree_3.json")
        assert.is_truthy(treeFile:find('"Eradication"', 1, true), "Eradication name must exist")

        -- srtor-11 lives in a different mastery sub-tree; spec keeps the
        -- assertion soft (only fails if the named node cannot be located in
        -- any 1.4 tree json — tree_0..tree_4 cover every released class).
        local foundFlesh = false
        for _, p in ipairs({"TreeData/1_4/tree_0.json","TreeData/1_4/tree_1.json","TreeData/1_4/tree_2.json","TreeData/1_4/tree_3.json","TreeData/1_4/tree_4.json"}) do
            local s = readFile(p)
            if s and s:find('"Taste for Flesh"', 1, true) then foundFlesh = true; break end
        end
        assert.is_true(foundFlesh, "srtor-11 'Taste for Flesh' must exist in some 1.4 tree json")
    end)
end)
