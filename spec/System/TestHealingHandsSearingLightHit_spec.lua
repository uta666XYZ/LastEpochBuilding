-- @leb-regression-guard:tree-node-add-hit-skill
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("Healing Hands Searing Light offensive hit (hh7pa3-1)", function()
    it("Global.lua registers hh7pa3-1 -> hh7pa3 with the guard marker", function()
        local text = assert(readFile("Data/Global.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:tree%-node%-add%-hit%-skill"),
            "Global.lua must carry the tree-node-add-hit-skill guard marker")
        assert.is_truthy(text:find("LE_TREE_NODE_SKILL_ADD_HIT"),
            "Global.lua must define LE_TREE_NODE_SKILL_ADD_HIT")
        assert.is_truthy(text:find('%["hh7pa3%-1"%]%s*=%s*"hh7pa3"'),
            "registry must map hh7pa3-1 -> hh7pa3 (Healing Hands: Searing Light)")
    end)

    it("the loaded registry maps hh7pa3-1 -> hh7pa3", function()
        assert.is_table(LE_TREE_NODE_SKILL_ADD_HIT, "LE_TREE_NODE_SKILL_ADD_HIT must be a global table")
        assert.are.equals("hh7pa3", LE_TREE_NODE_SKILL_ADD_HIT["hh7pa3-1"])
    end)

    it("CalcSetup consumer sets skillFlags.hit from the registry", function()
        local text = assert(readFile("Modules/CalcSetup.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:tree%-node%-add%-hit%-skill"),
            "CalcSetup must carry the tree-node-add-hit-skill consumer marker")
        assert.is_truthy(text:find("LE_TREE_NODE_SKILL_ADD_HIT"),
            "CalcSetup consumer must reference the registry")
        assert.is_truthy(text:find("activeSkill%.skillFlags%.hit%s*=%s*true"),
            "consumer must set skillFlags.hit = true")
    end)

    it("Healing Hands carries the calibrated fire base + eff but NO base-kit hit flag", function()
        local d = data.skills["HealingHands"]
        assert.is_table(d, "data.skills['HealingHands'] must exist")
        assert.are.equals("Healing Hands", d.name)
        assert.are.equals(69, d.stats.spell_base_fire_damage, "calibrated Searing Light base = 69 fire")
        assert.are.equals(2, d.stats.damageEffectiveness, "Searing Light added-spell effectiveness = 2 (200%)")
        assert.is_nil(d.baseFlags.hit,
            "base-kit Healing Hands must NOT have the hit flag (the node enables it; the heal kit deals no hit)")
        assert.is_truthy(d.baseFlags.spell, "Healing Hands base is a spell")
        assert.are.equals("hh7pa3", d.treeId)
    end)
end)
