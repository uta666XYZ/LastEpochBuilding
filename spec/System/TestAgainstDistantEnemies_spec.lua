-- @leb-regression-guard:against-distant-enemies
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

local function parsedTags(stat)
    local list, extra = modLib.parseMod(stat)
    assert.is_not_nil(list, "must parse: " .. stat)
    assert.is_falsy(extra and extra:match("%S"), "no non-space residue for: " .. stat .. " (got " .. tostring(extra) .. ")")
    assert.are.equals(1, #list, "exactly one mod for: " .. stat)
    return list[1]
end
local function hasEnemyDistant(mod)
    for _, tag in ipairs(mod) do
        if tag.type == "ActorCondition" and tag.actor == "enemy" and tag.var == "Distant" then return true end
    end
    return false
end
local function hasSkillName(mod)
    for _, tag in ipairs(mod) do if tag.type == "SkillName" then return true end end
    return false
end

describe("AgainstDistantEnemies", function()
    local parserText, cacheText, configText
    setup(function()
        newBuild()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
        configText = readSource("Modules/ConfigOptions.lua")
    end)

    it("inline guard marker present in ModParser.lua", function()
        assert.is_truthy(string.find(parserText, "against-distant-enemies", 1, true))
    end)

    it("ModParser registers 'against/to distant enemies' -> enemy Distant", function()
        for _, key in ipairs({ "against distant enemies", "to distant enemies" }) do
            assert.is_truthy(string.find(parserText,
                '%["' .. key .. '"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"ActorCondition",%s*actor%s*=%s*"enemy",%s*var%s*=%s*"Distant"'),
                "ModParser must register '" .. key .. "' -> enemy Distant")
        end
    end)

    it("ConfigOptions adds conditionEnemyDistant publishing Condition:Distant", function()
        assert.is_truthy(string.find(configText, 'var = "conditionEnemyDistant"', 1, true))
        assert.is_truthy(string.find(configText, 'NewMod("Condition:Distant", "FLAG", true', 1, true))
    end)

    it("'+25% Chill Chance Against Distant Enemies' -> Chill chance + enemy Distant, no residue", function()
        local m = parsedTags("+25% Chill Chance Against Distant Enemies")
        assert.are.equals("ChanceToTriggerOnHit_Ailment_Chill", m.name)
        assert.is_true(hasEnemyDistant(m))
        assert.is_false(hasSkillName(m))
    end)

    it("'+40% Shock Chance Against Distant Enemies' -> Shock chance + enemy Distant", function()
        local m = parsedTags("+40% Shock Chance Against Distant Enemies")
        assert.are.equals("ChanceToTriggerOnHit_Ailment_Shock", m.name)
        assert.is_true(hasEnemyDistant(m))
    end)

    it("ModCache no longer carries the stale 'Against Distant Enemies' residue for the 3 fixed entries", function()
        for _, key in ipairs({
            '+25% Chill Chance Against Distant Enemies',
            '+25% Slow Chance Against Distant Enemies',
            '+40% Shock Chance Against Distant Enemies',
        }) do
            assert.is_nil(string.find(cacheText, 'c["' .. key .. '"]', 1, true),
                "stale ModCache entry must be deleted so it re-parses live: " .. key)
        end
    end)
end)
