-- @leb-regression-guard:vengeance-bolster-player-buff
-- Hence the node-level lift. See REGRESSION_GUARDS.md > "vengeance-bolster-player-buff".
-- Validation provenance is retained in maintainer notes.

local function findTag(mod, tagType)
    for _, tag in ipairs(mod) do
        if tag.type == tagType then return tag end
    end
end

-- Process a REAL tree node at a given rank and return its modList. Snapshots and
-- restores node.alloc so the shared tree object stays pristine for other specs.
local function processRealNode(nodeId, rank)
    local node = build.spec.tree.nodes[nodeId]
    assert.is_not_nil(node, "tree node " .. nodeId .. " must exist in 1_4 tree data")
    local origAlloc = node.alloc
    node.alloc = rank
    build.spec.tree:ProcessStats(node)
    local mods = node.modList
    node.alloc = origAlloc
    if type(origAlloc) == "number" then
        build.spec.tree:ProcessStats(node)
    end
    return mods
end

local function findMod(mods, name, modType)
    for _, m in ipairs(mods) do
        if m.name == name and m.type == modType then return m end
    end
end

describe("VengeanceBolsterPlayerBuff", function()
    before_each(function()
        newBuild()
    end)

    -- ---- registry / game-data pin ----

    it("gs15de-19 is 'Bolster' carrying the Less-Damage-Taken / Increased-Armor stats (live tree data)", function()
        local node = build.spec.tree.nodes["gs15de-19"]
        assert.is_not_nil(node, "gs15de-19 must exist in 1_4 tree data")
        assert.are.equals("Bolster", node.name)
        local hasDR, hasArmour = false, false
        for _, s in ipairs(node.stats or {}) do
            if s == "13% Less Damage Taken" then hasDR = true end
            if s == "25% Increased Armor" then hasArmour = true end
        end
        assert.is_true(hasDR, "gs15de-19 must carry the '13% Less Damage Taken' stat")
        assert.is_true(hasArmour, "gs15de-19 must carry the '25% Increased Armor' stat")
    end)

    it("registry maps gs15de-19 -> HaveBolster", function()
        assert.are.equals("HaveBolster", LE_TREE_NODE_PLAYER_CONDITIONAL_BUFF["gs15de-19"])
    end)

    -- ---- tagging layer ----

    it("gs15de-19 is lifted to the player (no SkillId) and gated by the Bolster Condition", function()
        local mods = processRealNode("gs15de-19", 2)
        local dr = findMod(mods, "DamageTaken", "MORE")
        local armour = findMod(mods, "Armour", "INC")
        assert.is_not_nil(dr, "Bolster must emit a DamageTaken MORE mod ('Less Damage Taken')")
        assert.is_not_nil(armour, "Bolster must emit an Armour INC mod ('Increased Armor')")
        -- 2/2 points: -13% MORE x2 = -26 ; +25% INC x2 = +50 (matches the captured deltas)
        assert.are.equals(-26, dr.value, "2/2 Bolster -> -26% MORE damage taken (captured moreValue=-0.26)")
        assert.are.equals(50, armour.value, "2/2 Bolster -> +50% increased armour (captured increasedValue=0.5)")
        for _, m in ipairs({ dr, armour }) do
            assert.is_nil(findTag(m, "SkillId"),
                "Bolster mods reach the PLAYER sheet -> no SkillId:Vengeance scope")
            local cond = findTag(m, "Condition")
            assert.is_not_nil(cond, "Bolster mods must be gated by the Bolster Condition")
            assert.are.equals("HaveBolster", cond.var)
        end
    end)

    it("Bolster scales with allocated points (rank 1 -> -13 MORE / +25 INC)", function()
        local mods = processRealNode("gs15de-19", 1)
        assert.are.equals(-13, findMod(mods, "DamageTaken", "MORE").value)
        assert.are.equals(25, findMod(mods, "Armour", "INC").value)
    end)

    -- ---- control: a NON-lifted gs15de node keeps the Vengeance scope ----

    it("a non-lifted gs15de node still scopes to the owning skill (SkillId kept)", function()
        -- gs15de-6 "Vengeful Fighter" ("+6% Damage") is an ordinary Vengeance-scoped
        -- damage node, NOT a player-wide buff: its mod must keep the SkillId scope so
        -- the player-buff lift does not accidentally strip every node's scope.
        local node = build.spec.tree.nodes["gs15de-6"]
        assert.is_not_nil(node, "gs15de-6 must exist (control)")
        assert.is_nil(LE_TREE_NODE_PLAYER_CONDITIONAL_BUFF["gs15de-6"],
            "gs15de-6 is NOT a registered player-buff node")
        local mods = processRealNode("gs15de-6", 1)
        local damageMod = findMod(mods, "Damage", "MORE")  -- LE "+X% Damage" is MORE, not INC
        assert.is_not_nil(damageMod, "Vengeful Fighter must emit a Damage MORE mod (+6% Damage)")
        local skillTag = findTag(damageMod, "SkillId")
        assert.is_not_nil(skillTag, "non-lifted gs15de nodes keep their owning-skill SkillId scope")
        assert.are.equals("Vengeance", skillTag.skillId, "scoped to the owning Vengeance skill")
        assert.is_nil(findTag(damageMod, "Condition"),
            "non-lifted gs15de nodes do NOT receive the player-buff Condition")
    end)

    -- ---- end-to-end through ModDB: Condition gates the player buff ----

    it("Bolster applies to the player defensive panel ONLY while the Condition is set", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        for _, m in ipairs(processRealNode("gs15de-19", 2)) do db:AddMod(m) end
        -- Player defensive panel queries with cfg=nil (no active skill).
        assert.are.equals(0, db:Sum("MORE", nil, "DamageTaken"), "Bolster OFF -> no DamageTaken contribution")
        assert.are.equals(0, db:Sum("INC", nil, "Armour"), "Bolster OFF -> no Armour contribution")
        db.conditions["HaveBolster"] = true
        assert.are.equals(-26, db:Sum("MORE", nil, "DamageTaken"), "Bolster ON -> -26% MORE damage taken")
        assert.are.equals(50, db:Sum("INC", nil, "Armour"), "Bolster ON -> +50% increased armour")
    end)

    -- ---- config toggle source pin ----

    it("ConfigOptions exposes the Bolster toggle that sets the Condition", function()
        local f = assert(io.open("Modules/ConfigOptions.lua", "r"))
        local src = f:read("*a"); f:close()
        assert.is_truthy(src:find('var = "conditionHaveBolster"', 1, true),
            "ConfigOptions must declare the conditionHaveBolster toggle")
        assert.is_truthy(src:find("Condition:HaveBolster", 1, true),
            "the toggle's apply must set Condition:HaveBolster")
    end)
end)
