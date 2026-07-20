-- @leb-regression-guard:against-rares-and-bosses
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

-- Return the single mod's tags, asserting exactly one mod and clean residue.
local function parsedTags(stat)
    local list, extra = modLib.parseMod(stat)
    assert.is_not_nil(list, "must parse: " .. stat)
    assert.is_falsy(extra and extra:match("%S"), "no non-space residue for: " .. stat .. " (got " .. tostring(extra) .. ")")
    assert.are.equals(1, #list, "exactly one mod for: " .. stat)
    return list[1]
end
local function raresAndBossesTag(mod)
    for _, tag in ipairs(mod) do
        if tag.type == "ActorCondition" and tag.actor == "enemy" and tag.varList then
            return tag
        end
    end
    return nil
end
local function hasSkillName(mod)
    for _, tag in ipairs(mod) do if tag.type == "SkillName" then return true end end
    return false
end

describe("AgainstRaresAndBosses", function()
    local parserText, cacheText, configText
    setup(function()
        newBuild()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
        configText = readSource("Modules/ConfigOptions.lua")
    end)

    it("inline guard marker present in ModParser.lua", function()
        assert.is_truthy(string.find(parserText, "against-rares-and-bosses", 1, true))
    end)

    it("ModParser registers the three rare/boss conditional suffix forms", function()
        for _, key in ipairs({ "against rares and bosses", "to rares and bosses", "vs rares and bosses" }) do
            assert.is_truthy(string.find(parserText,
                '%["' .. key .. '"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"ActorCondition",%s*actor%s*=%s*"enemy",%s*varList%s*=%s*{%s*"Rare","Boss"%s*}'),
                "ModParser must register '" .. key .. "' -> enemy varList {Rare,Boss}")
        end
    end)

    it("ConfigOptions adds the conditionEnemyRare toggle publishing Condition:Rare", function()
        assert.is_truthy(string.find(configText, 'var = "conditionEnemyRare"', 1, true),
            "ConfigOptions must define conditionEnemyRare")
        assert.is_truthy(string.find(configText, 'NewMod("Condition:Rare", "FLAG", true', 1, true),
            "conditionEnemyRare must publish Condition:Rare on the enemy")
    end)

    it("'+20% Hit Damage Against Rares And Bosses' -> Damage MORE + enemy varList{Rare,Boss}, no residue", function()
        local m = parsedTags("+20% Hit Damage Against Rares And Bosses")
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type)
        local tag = raresAndBossesTag(m)
        assert.is_not_nil(tag, "must carry an enemy varList ActorCondition")
        assert.are.equals("Rare", tag.varList[1])
        assert.are.equals("Boss", tag.varList[2])
        assert.is_false(hasSkillName(m), "must NOT carry a spurious SkillName tag")
    end)

    it("'25% More Hit Damage Against Rares And Bosses' -> Damage MORE + varList", function()
        local m = parsedTags("25% More Hit Damage Against Rares And Bosses")
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type)
        assert.is_not_nil(raresAndBossesTag(m))
    end)

    it("'+8% Damage to Rares and Bosses' (ch0fs-14 Eradication) -> Damage + varList, no residue", function()
        local m = parsedTags("+8% Damage to Rares and Bosses")
        assert.are.equals("Damage", m.name)
        assert.is_not_nil(raresAndBossesTag(m))
        assert.is_false(hasSkillName(m))
    end)

    it("skill-scoped '50% Shadow Daggers Damage to Rares and Bosses' keeps SkillName AND adds varList", function()
        local list, extra = modLib.parseMod("50% Shadow Daggers Damage to Rares and Bosses")
        assert.is_not_nil(list)
        assert.is_falsy(extra and extra:match("%S"), "no residue (got " .. tostring(extra) .. ")")
        assert.are.equals(1, #list)
        local m = list[1]
        assert.is_true(hasSkillName(m), "must keep the Shadow Daggers SkillName scope")
        assert.is_not_nil(raresAndBossesTag(m), "must also gain the rare/boss ActorCondition")
    end)

    it("ModCache no longer carries the stale 'Rares and Bosses' residue for the 8 fixed entries", function()
        for _, key in ipairs({
            '+20% Damage to Rares and Bosses',
            '+20% Hit Damage Against Rares And Bosses',
            '+25% Damage To Rares And Bosses',
            '+25% Hit Damage Against Rares And Bosses',
            '+8% Damage to Rares and Bosses',
            '20% More Hit Damage Against Rares And Bosses',
            '25% More Hit Damage Against Rares And Bosses',
            '50% Shadow Daggers Damage to Rares and Bosses',
        }) do
            assert.is_nil(string.find(cacheText, 'c["' .. key .. '"]', 1, true),
                "stale ModCache entry must be deleted so it re-parses live: " .. key)
        end
    end)
end)
