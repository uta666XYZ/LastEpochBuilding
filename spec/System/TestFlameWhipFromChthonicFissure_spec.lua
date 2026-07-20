-- @leb-regression-guard: flame-whip-from-chthonic-fissure-node
-- this spec. See REGRESSION_GUARDS.md "flame-whip-from-chthonic-fissure-node".
-- Validation provenance is retained in maintainer notes.

describe("FlameWhipFromChthonicFissure", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    it("ModParser maps the node to a Chthonic-Fissure-scoped Flame Whip trigger", function()
        local mods = modLib.parseMod("100% Chance for Chthonic Fissures to cast Flame Whip instead of releasing Spirits")
        assert.is_not_nil(mods, "modLib.parseMod must return a mod list")
        assert.are.equals(1, #mods)
        assert.are.equals("ChanceToTriggerOnHit_Warlock Unique Flame Whip", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(100, mods[1].value)
        -- scoped to the SOURCE skill (Chthonic Fissure) via a SkillName tag
        assert.is_not_nil(mods[1][1], "trigger mod must carry a tag")
        assert.are.equals("SkillName", mods[1][1].type)
        assert.are.equals("Chthonic Fissure", mods[1][1].skillName)
    end)

    it("skills.json defines Flame Whip with the LETools base profile", function()
        assert.is_not_nil(data.skills["Warlock Unique Flame Whip"], "Flame Whip skill entry must exist")
        local fw = data.skills["Warlock Unique Flame Whip"]
        assert.are.equals("Flame Whip", fw.name)
        assert.are.equals("ch0fs", fw.treeId, "must share Chthonic Fissure's treeId for tree/conversion passthrough")
        assert.is_truthy(fw.baseFlags and fw.baseFlags.spell and fw.baseFlags.hit, "Flame Whip is a spell hit")
        assert.are.equals(60, fw.stats.spell_base_fire_damage)
        assert.are.equals(3.0, fw.stats.damageEffectiveness)
    end)

    it("ModCache no longer stubs the node as LEB_NotSupported", function()
        local cacheSrc = readFile("Data/ModCache.lua")
        assert.is_not_nil(cacheSrc, "must read Data/ModCache.lua")
        local line = cacheSrc:match('(c%["100%% Chance for Chthonic Fissures to cast Flame Whip instead of releasing Spirits"%]=[^\n]*)')
        assert.is_not_nil(line, "ModCache must still carry the node entry")
        assert.is_falsy(line:find("LEB_NotSupported", 1, true), "node must not be stubbed NotSupported")
        assert.is_truthy(line:find("ChanceToTriggerOnHit_Warlock Unique Flame Whip", 1, true),
            "ModCache must re-point the node to the Flame Whip trigger mod")
    end)
end)
