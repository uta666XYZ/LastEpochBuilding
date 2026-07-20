-- @leb-regression-guard:against-ailment-no-enemies-suffix
-- The article/noun-less "Against <ailment>" suffix (no trailing "enemies"/"targets")
-- that LEB passive/skill-tree stats use, e.g. "+20% Hit Damage Against Bleeding",
-- "10% More Damage Against Chilled", "20% More Crit Chance Against Frozen Targets".
--
-- Bug: ModParser only had the "against <ailment> enemies" forms. The bare form
-- parsed the leading stat but matched the ailment word as a SkillName (the
-- ailment-pseudo-skill mechanism) and left "Against <ailment>" as `extra` residue
-- (mangled to "Against ed/ing" because the damage-type/ailment fragment was
-- consumed) -> PassiveSpec.lua:1024 (`if mod.list and not mod.extra`) dropped the
-- whole mod (silent UNDER-count; same class as with-1h-suffix-family). The fix adds
-- the no-"enemies" modTag variants mapping to the enemy ActorCondition vars (which
-- already exist, used by the "enemies" forms). Immobilized is intentionally excluded
-- (no enemy Immobilized condition var yet). The 14 cache-keyed stale entries were
-- deleted from ModCache so they re-parse live with the correct ActorCondition.

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
local function hasActorCond(mod, var)
    for _, tag in ipairs(mod) do
        if tag.type == "ActorCondition" and tag.actor == "enemy" and tag.var == var then return true end
    end
    return false
end
local function hasSkillName(mod)
    for _, tag in ipairs(mod) do if tag.type == "SkillName" then return true end end
    return false
end

describe("AgainstAilmentNoEnemiesSuffix", function()
    local parserText, cacheText
    setup(function()
        newBuild()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser registers the no-enemies 'against <ailment>' variants", function()
        for _, a in ipairs({ {"against bleeding","Bleeding"}, {"against poisoned","Poisoned"},
                             {"against chilled","Chilled"}, {"against frozen","Frozen"},
                             {"against ignited","Ignited"}, {"against shocked","Shocked"},
                             {"against slowed","Slowed"} }) do
            local pat = 'modTagList?%["' .. a[1] .. '"%]'  -- inside the conditional modTagList table literal
            assert.is_truthy(string.find(parserText, '%["' .. a[1] .. '"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"ActorCondition",%s*actor%s*=%s*"enemy",%s*var%s*=%s*"' .. a[2] .. '"'),
                "ModParser must register '" .. a[1] .. "' -> enemy " .. a[2])
        end
    end)

    it("inline guard marker present in ModParser.lua", function()
        assert.is_truthy(string.find(parserText, "against-ailment-no-enemies-suffix", 1, true))
    end)

    it("'+20% Hit Damage Against Bleeding' -> Damage MORE + enemy Bleeding, no SkillName, no residue", function()
        local m = parsedTags("+20% Hit Damage Against Bleeding")
        assert.are.equals("Damage", m.name)
        assert.is_true(hasActorCond(m, "Bleeding"))
        assert.is_false(hasSkillName(m), "must NOT carry a spurious SkillName=Bleed tag")
    end)

    it("'10% More Damage Against Chilled' -> Damage MORE + enemy Chilled", function()
        local m = parsedTags("10% More Damage Against Chilled")
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type)
        assert.is_true(hasActorCond(m, "Chilled"))
        assert.is_false(hasSkillName(m))
    end)

    it("'20% More Crit Chance Against Frozen Targets' -> CritChance + enemy Frozen ('targets' variant)", function()
        local m = parsedTags("20% More Crit Chance Against Frozen Targets")
        assert.are.equals("CritChance", m.name)
        assert.is_true(hasActorCond(m, "Frozen"))
    end)

    it("'+6% Damage Against Chilled Or Frozen' -> varList Chilled+Frozen", function()
        local list, extra = modLib.parseMod("+6% Damage Against Chilled Or Frozen")
        assert.is_falsy(extra and extra:match("%S"))
        local m = list[1]
        local vl
        for _, tag in ipairs(m) do if tag.type == "ActorCondition" and tag.varList then vl = tag.varList end end
        assert.is_not_nil(vl, "must carry a varList ActorCondition")
        assert.are.equals("Chilled", vl[1]); assert.are.equals("Frozen", vl[2])
    end)

    it("ModCache no longer carries the stale 'Against ed/ing' residue for these", function()
        assert.is_nil(string.find(cacheText, "Hit Damage Against Bleeding\"]={{[1]={[1]={skillName", 1, true),
            "stale SkillName-scoped 'Hit Damage Against Bleeding' cache entry must be gone")
        assert.is_nil(string.find(cacheText, '"  Against ed "', 1, true),
            "no entry may keep the mangled '  Against ed ' residue")
    end)
end)
