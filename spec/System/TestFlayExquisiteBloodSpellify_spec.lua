-- @leb-regression-guard:tree-node-spellify-skill
-- structural transform. See REGRESSION_GUARDS.md "tree-node-spellify-skill".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("Flay Exquisite Blood melee->spell transform (fl44-29)", function()
    it("Global.lua registers fl44-29 -> fl44 with the guard marker", function()
        local text = assert(readFile("Data/Global.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:tree%-node%-spellify%-skill"),
            "Global.lua must carry the tree-node-spellify-skill guard marker")
        assert.is_truthy(text:find("LE_TREE_NODE_SKILL_SPELLIFY"),
            "Global.lua must define LE_TREE_NODE_SKILL_SPELLIFY")
        assert.is_truthy(text:find('%["fl44%-29"%]%s*=%s*"fl44"'),
            "registry must map fl44-29 -> fl44 (Flay: Exquisite Blood)")
    end)

    it("the loaded registry maps fl44-29 -> fl44", function()
        -- HeadlessWrapper loads Global.lua, so the global table is available.
        assert.is_table(LE_TREE_NODE_SKILL_SPELLIFY, "LE_TREE_NODE_SKILL_SPELLIFY must be a global table")
        assert.are.equals("fl44", LE_TREE_NODE_SKILL_SPELLIFY["fl44-29"])
    end)

    it("CalcSetup consumer strips melee/weapon flags and adds spell", function()
        local text = assert(readFile("Modules/CalcSetup.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:tree%-node%-spellify%-skill"),
            "CalcSetup must carry the tree-node-spellify-skill consumer marker")
        assert.is_truthy(text:find("LE_TREE_NODE_SKILL_SPELLIFY"),
            "CalcSetup consumer must reference the registry")
        -- the transform: clears melee + sets spell
        assert.is_truthy(text:find("sf%.melee%s*=%s*nil") and text:find("sf%.spell%s*=%s*true"),
            "consumer must clear sf.melee and set sf.spell")
        assert.is_truthy(text:find("SkillType%.Melee%]%s*=%s*nil") and text:find("SkillType%.Spell%]%s*=%s*true"),
            "consumer must swap the SkillType.Melee bit for SkillType.Spell")
    end)

    it("Flay precondition: it is a melee weapon attack with a 2-physical base", function()
        local d = data.skills["Flay 1"]  -- data.skills key is "Flay 1" (name "Flay")
        assert.is_table(d, "data.skills['Flay 1'] must exist")
        assert.are.equals("Flay", d.name)
        assert.is_truthy(d.baseFlags.melee, "Flay base is a melee attack (the thing Exquisite Blood removes)")
        assert.is_truthy(d.baseFlags.attack, "Flay base is an attack")
        assert.are.equals(2, d.stats.melee_base_physical_damage, "Flay base = 2 melee physical")
        assert.are.equals(2, d.stats.damageEffectiveness, "Flay effectiveness = 2")
        assert.are.equals("fl44", d.treeId)
    end)
end)
