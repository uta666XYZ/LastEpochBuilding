-- @leb-regression-guard:throwing-attack-damage-increased-and-flat
-- rows. See REGRESSION_GUARDS.md.
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

-- Parse with a cache-busted number so ModCache cannot short-circuit; assert clean.
local function parsedSingle(stat)
    local list, extra = modLib.parseMod(stat)
    assert.is_not_nil(list, "must parse: " .. stat)
    assert.is_falsy(extra and extra:match("%S"), "no non-space residue for: " .. stat .. " (got " .. tostring(extra) .. ")")
    assert.are.equals(1, #list, "exactly one mod for: " .. stat)
    return list[1]
end

local function kwHasThrowing(mod)
    return mod.keywordFlags and bit.band(mod.keywordFlags, KeywordFlag.Throwing) ~= 0
end

describe("ThrowingAttackDamageResidue", function()
    local parserText, cacheText
    setup(function()
        newBuild()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("inline guard marker present in ModParser.lua", function()
        assert.is_truthy(string.find(parserText, "throwing-attack-damage-increased-and-flat", 1, true))
    end)

    it("live parse (cache-busted) 'N% Increased Throwing Attack Damage' -> Damage INC Throwing, no residue", function()
        local m = parsedSingle("13% Increased Throwing Attack Damage")
        assert.are.equals("Damage", m.name)
        assert.are.equals("INC", m.type)
        assert.are.equals(13, m.value)
        assert.is_true(kwHasThrowing(m), "must carry Throwing keywordFlag")
    end)

    it("live parse (cache-busted) '+N Throwing Attack Damage' -> Damage BASE Throwing, no residue", function()
        local m = parsedSingle("+9 Throwing Attack Damage")
        assert.are.equals("Damage", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(9, m.value)
        assert.is_true(kwHasThrowing(m), "must carry Throwing keywordFlag")
    end)

    it("bare '+N% Throwing Attack Damage' (sibling guard) still parses clean", function()
        local m = parsedSingle("+12% Throwing Attack Damage")
        assert.are.equals("Damage", m.name)
        assert.are.equals("INC", m.type)
        assert.is_true(kwHasThrowing(m))
    end)

    it("cached exact node strings now carry empty (not 'Attack') residue", function()
        -- these three exact strings are baked in ModCache; they must be re-synced
        for _, stat in ipairs({
            "6% Increased Throwing Attack Damage",  -- Peltast (Sentinel-30)
            "7% Increased Throwing Attack Damage",
            "+3 Throwing Attack Damage",            -- Force of Devotion (Sentinel-75)
        }) do
            local list, extra = modLib.parseMod(stat)
            assert.is_not_nil(list, "must parse: " .. stat)
            assert.are.equals(1, #list, "exactly one mod for: " .. stat)
            assert.is_falsy(extra and extra:match("%S"),
                "cached row must be residue-free for: " .. stat .. " (got " .. tostring(extra) .. ")")
            assert.is_true(kwHasThrowing(list[1]), "Throwing keyword for: " .. stat)
        end
    end)

    it("ModCache rows are patched to empty residue (source check)", function()
        assert.is_truthy(string.find(cacheText,
            'c["6% Increased Throwing Attack Damage"]={{[1]={flags=0,keywordFlags=1024,name="Damage",type="INC",value=6}},""}', 1, true))
        assert.is_truthy(string.find(cacheText,
            'c["+3 Throwing Attack Damage"]={{[1]={flags=0,keywordFlags=1024,name="Damage",type="BASE",value=3}},""}', 1, true))
    end)
end)
