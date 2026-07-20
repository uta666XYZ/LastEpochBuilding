-- @leb-regression-guard:tree-node-meleeify-skill
-- refinement deferred for lack of grounding. See REGRESSION_GUARDS.md "tree-node-meleeify-skill".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("Healing Hands Seraph Blade spell->melee transform (hh7pa3-8)", function()
    it("Global.lua registers hh7pa3-8 -> hh7pa3 with the guard marker", function()
        local text = assert(readFile("Data/Global.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:tree%-node%-meleeify%-skill"),
            "Global.lua must carry the tree-node-meleeify-skill guard marker")
        assert.is_truthy(text:find("LE_TREE_NODE_SKILL_MELEEIFY"),
            "Global.lua must define LE_TREE_NODE_SKILL_MELEEIFY")
        assert.is_truthy(text:find('%["hh7pa3%-8"%]%s*=%s*"hh7pa3"'),
            "registry must map hh7pa3-8 -> hh7pa3 (Healing Hands: Seraph Blade)")
    end)

    it("the loaded registry maps hh7pa3-8 -> hh7pa3", function()
        assert.is_table(LE_TREE_NODE_SKILL_MELEEIFY, "LE_TREE_NODE_SKILL_MELEEIFY must be a global table")
        assert.are.equals("hh7pa3", LE_TREE_NODE_SKILL_MELEEIFY["hh7pa3-8"])
    end)

    it("CalcSetup consumer clears spell and sets melee (without weapon-attack flags)", function()
        local text = assert(readFile("Modules/CalcSetup.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:tree%-node%-meleeify%-skill"),
            "CalcSetup must carry the tree-node-meleeify-skill consumer marker")
        assert.is_truthy(text:find("LE_TREE_NODE_SKILL_MELEEIFY"),
            "CalcSetup consumer must reference the registry")
        -- the transform: clears spell + sets melee
        assert.is_truthy(text:find("sf%.spell%s*=%s*nil") and text:find("sf%.melee%s*=%s*true"),
            "consumer must clear sf.spell and set sf.melee")
        assert.is_truthy(text:find("SkillType%.Spell%]%s*=%s*nil") and text:find("SkillType%.Melee%]%s*=%s*true"),
            "consumer must swap the SkillType.Spell bit for SkillType.Melee")
    end)

    it("is the INVERSE of spellify (does NOT add weapon-attack flags in the meleeify block)", function()
        -- guard against accidentally pulling weapon base damage: the meleeify consumer must
        -- NOT set weapon1Attack/weapon2Attack (HH is a self-based melee hit, not a weapon strike).
        local text = assert(readFile("Modules/CalcSetup.lua"))
        local s = text:find("@leb%-regression%-guard:tree%-node%-meleeify%-skill", 1)
        assert.is_truthy(s, "meleeify consumer block must exist")
        -- slice from the meleeify marker to the next guard marker (add-hit) and check no weaponNAttack=true
        local e = text:find("@leb%-regression%-guard:tree%-node%-add%-hit%-skill", s + 10) or (s + 1200)
        local block = text:sub(s, e)
        assert.is_nil(block:find("weapon1Attack%s*=%s*true"),
            "meleeify must NOT set weapon1Attack=true (no weapon base damage)")
        assert.is_nil(block:find("weapon2Attack%s*=%s*true"),
            "meleeify must NOT set weapon2Attack=true (no weapon base damage)")
    end)

    it("Healing Hands precondition: a SPELL (the thing Seraph Blade converts to melee)", function()
        local d = data.skills["HealingHands"]
        assert.is_table(d, "data.skills['HealingHands'] must exist")
        assert.are.equals("hh7pa3", d.treeId, "HealingHands treeId must be hh7pa3 (Seraph Blade's tree)")
        assert.is_truthy(d.baseFlags.spell, "Healing Hands base is a spell (Seraph Blade flips this to melee)")
        assert.is_nil(d.baseFlags.melee, "Healing Hands base is NOT melee until Seraph Blade is allocated")
    end)
end)
