-- @leb-regression-guard:void-knight-mastery-melee-void-more
-- Validation provenance is retained in maintainer notes.

local ORIG_VK = "You gain 1% more melee void damage (multiplicative with other modifiers) per 3 Vitality."
local ORIG_PAL = "You deal 1.5% more damage (multiplicative with other modifiers) per 10% remaining health, up to 15% more damage at full heath."

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

-- Mirror PassiveTree.lua's per-node rewrite loop.
local function applyRewrite(nodeId, stat)
    local rw = LE_TREE_NODE_STAT_REWRITE[nodeId]
    if rw then
        for _, r in ipairs(rw) do
            stat = (stat:gsub(r.pat, r.repl))
        end
    end
    return stat
end

local function liveParse(line)
    if modLib.parseModCache then modLib.parseModCache[line] = nil end
    return modLib.parseMod(line)
end

-- Full build path: allocate the mastery-start node and run ProcessStats, exactly as a
-- real build load does. Returns node.modList (the mods that actually reach the player).
-- NOTE node.extra is legitimately set here by the SIBLING echo line ("...repeated by an
-- echo...", which LEB doesn't model) -- that flag is per-node, not per-line, so it is NOT
-- a reliable signal that the damage-more line was dropped. Whether the damage-more mod
-- survives is decided by ITS OWN parse residue; the "residue-free line" test below pins
-- that at the parseMod level, and this helper checks the mod actually lands in modList.
local function masteryModList(nodeId)
    local node = build.spec.tree.nodes[nodeId]
    assert.is_not_nil(node, nodeId .. " mastery-start node must exist in the loaded tree")
    node.alloc = 1
    build.spec.tree:ProcessStats(node)
    return node.modList or {}
end

local function findMore(modList, name)
    for _, m in ipairs(modList) do
        if m.type == "MORE" and (name == nil or m.name == name) then return m end
    end
    return nil
end

describe("VoidKnightMasteryMoreVoid", function()
    before_each(function()
        newBuild()
    end)

    it("tree_2.json still carries the mastery node AND the multiplicative clause", function()
        local tree = readSource("TreeData/1_4/tree_2.json")
        assert.is_truthy(tree:find('"Void Knight"', 1, true), "mastery-start node present")
        assert.is_truthy(tree:find('1% more melee void damage', 1, true), "per-Vit more display string")
        assert.is_truthy(tree:find('multiplicative with other modifiers', 1, true),
            "the multiplicative gloss must still exist -- if LE re-tunes this bonus " ..
            "(e.g. back to 'increased'), RE-MEASURE before trusting this model")
    end)

    it("rewrite yields a residue-free MORE-anchored line (no trailing period)", function()
        assert.is_not_nil(LE_TREE_NODE_STAT_REWRITE["Void Knight"], "rewrite registered")
        local rewritten = applyRewrite("Void Knight", ORIG_VK)
        assert.are.equals("1% more melee void damage per 3 Vitality", rewritten,
            "must be period-free: a trailing '.' becomes parseMod `extra` -> ProcessStats drops it")
        local mods, extra = liveParse(rewritten)
        assert.is_falsy(extra, "the rewritten line must parse with NO extra residue")
        assert.is_not_nil(mods and mods[1])
        local m = mods[1]
        assert.are.equals("VoidDamage", m.name)
        assert.are.equals("MORE", m.type, "the '1% more ... (multiplicative)' bonus is a MORE, never BASE")
        assert.are.equals(1, m.value)
        assert.are.equals(512, m.keywordFlags, "Melee-tagged (melee void)")
        assert.is_not_nil(m[1], "a PerStat tag must be attached")
        assert.are.equals("PerStat", m[1].type)
        assert.are.equals("Vit", m[1].stat)
        assert.are.equals(3, m[1].div, "1% per 3 Vitality")
    end)

    it("FULL BUILD: the Void Knight mastery node emits a VoidDamage MORE into modList", function()
        -- This is the test the prefix-only rewrite FAILED: parseMod worked but the mod
        -- never reached node.modList because of the trailing-period `extra`.
        local m = findMore(masteryModList("Void Knight"), "VoidDamage")
        assert.is_not_nil(m, "Void Knight mastery must contribute a VoidDamage MORE to the build")
        assert.are.equals(512, m.keywordFlags, "Melee-tagged")
        assert.are.equals(1, m.value)
    end)

    it("regression witness: the RAW 'You gain ...' line still mis-parses to BASE (why the rewrite exists)", function()
        local mods = liveParse(ORIG_VK)
        assert.is_not_nil(mods and mods[1])
        assert.are.equals("VoidDamage", mods[1].name)
        assert.are.equals("BASE", mods[1].type,
            "ModParser's ^N% more anchor is defeated by the 'You gain ' prefix -- retire the " ..
            "rewrite only if this ever flips to MORE")
    end)

    it("Paladin mastery: FULL BUILD emits a Damage MORE 15 (was dropped to an empty list)", function()
        assert.are.equals(0, #liveParse(ORIG_PAL), "raw 'You deal ...' line yields NO mod (why the rewrite exists)")
        assert.are.equals("15% more Damage", applyRewrite("Paladin", ORIG_PAL))
        local m = findMore(masteryModList("Paladin"), "Damage")
        assert.is_not_nil(m, "Paladin mastery must contribute a Damage MORE to the build")
        assert.are.equals(15, m.value, "+15% more damage at the full-health config default")
    end)

    it("preventive: EVERY mastery-start 'more (multiplicative)' damage bonus reaches modList as a MORE (all classes)", function()
        -- Scans all 5 ascendancy trees. Any isAscendancyStart node whose bonus text is a
        -- multiplicative MORE must (a) rewrite to a residue-free line and (b) actually emit
        -- a MORE mod through the FULL ProcessStats path. This is the tripwire for the
        -- recurring "mastery bonus silently misparsed/dropped" class -- it would have failed
        -- on Void Knight (BASE) before the fix, and on the prefix-only rewrite (dropped).
        local scanned = 0
        for i = 0, 4 do
            local ok, treeData = pcall(readJsonFile, "TreeData/1_4/tree_" .. i .. ".json")
            if ok and type(treeData) == "table" and treeData.nodes then
                for id, node in pairs(treeData.nodes) do
                    if type(node) == "table" and node.isAscendancyStart and type(node.stats) == "table" then
                        for _, stat in ipairs(node.stats) do
                            if type(stat) == "string"
                               and stat:find("more", 1, true)
                               and stat:find("multiplicative", 1, true)
                               and stat:lower():find("damage", 1, true) then
                                scanned = scanned + 1
                                local rewritten = applyRewrite(id, stat)
                                local mods, extra = liveParse(rewritten)
                                assert.is_falsy(extra, ("mastery node %q line %q leaves parse residue %q -> "
                                    .. "ProcessStats will DROP it; the rewrite must emit a residue-free line")
                                    :format(id, stat, tostring(extra)))
                                local hasMore = false
                                for _, m in ipairs(mods or {}) do
                                    if m.type == "MORE" then hasMore = true break end
                                end
                                assert.is_true(hasMore, ("mastery node %q line %q must yield a MORE mod -- "
                                    .. "add a LE_TREE_NODE_STAT_REWRITE that strips whatever prefix defeats "
                                    .. "ModParser's start-anchored '^N%% more' detector"):format(id, stat))
                            end
                        end
                    end
                end
            end
        end
        assert.is_true(scanned >= 1, "expected at least the Void Knight mastery void-more line to be scanned")
    end)
end)
