-- @leb-regression-guard:with-weapon-type-condition-modcache-sync
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

local function condVar(mod, var)
    for _, tag in ipairs(mod) do
        if tag.type == "Condition" and tag.var == var then return true end
    end
    return false
end

-- parse with a cache-busted number so ModCache cannot short-circuit; assert clean.
local function parsedSingle(stat)
    local list, extra = modLib.parseMod(stat)
    assert.is_not_nil(list, "must parse: " .. stat)
    assert.is_falsy(extra and extra:match("%S"), "no non-space residue for: " .. stat .. " (got " .. tostring(extra) .. ")")
    assert.are.equals(1, #list, "exactly one mod for: " .. stat)
    return list[1]
end

describe("WithWeaponTypeConditionModcacheSync", function()
    local parserText, cacheText
    setup(function()
        newBuild()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("inline guard marker present in ModParser.lua", function()
        assert.is_truthy(string.find(parserText, "with-weapon-type-condition-modcache-sync", 1, true))
    end)

    it("live parse (cache-busted) 'More Melee Damage With Mace' -> Damage MORE + UsingMace, no residue", function()
        local m = parsedSingle("6% More Melee Damage With Mace")
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type)
        assert.is_true(condVar(m, "UsingMace"), "must carry Condition UsingMace")
    end)

    it("live parse (cache-busted) 'Physical Penetration With Mace' -> UsingMace, no residue", function()
        local m = parsedSingle("+11% Physical Penetration With Mace")
        assert.are.equals("PhysicalPenetration", m.name)
        assert.is_true(condVar(m, "UsingMace"))
    end)

    it("live parse (cache-busted) 'Area With Mace' -> UsingMace, no residue", function()
        local m = parsedSingle("+41% Area With Mace")
        assert.are.equals("AreaOfEffect", m.name)
        assert.is_true(condVar(m, "UsingMace"))
    end)

    it("ModCache: the 3 baked 'With Mace' entries carry Condition:UsingMace, empty residue", function()
        for _, needle in ipairs({
            'c%["5%% More Melee Damage With Mace"%]={{%[1%]={%[1%]={type="Condition",var="UsingMace"},flags=0,keywordFlags=512,name="Damage",type="MORE",value=5}},""}',
            'c%["%+10%% Physical Penetration With Mace"%]={{%[1%]={%[1%]={type="Condition",var="UsingMace"},flags=0,keywordFlags=0,name="PhysicalPenetration",type="BASE",value=10}},""}',
            'c%["%+40%% Area With Mace"%]={{%[1%]={%[1%]={type="Condition",var="UsingMace"},flags=0,keywordFlags=0,name="AreaOfEffect",type="BASE",value=40}},""}',
        }) do
            assert.is_truthy(string.find(cacheText, needle, 1, false), "patched ModCache entry must exist: " .. needle)
        end
    end)

    it("ModCache: no entry retains a 'With <weapon-type>' residue", function()
        -- residue form was {..}, "   With Mace " — assert no such trailing-residue survives
        assert.is_nil(string.find(cacheText, '},"%s*With Mace%s*"}'),
            "no ModCache entry may keep a 'With Mace' residue")
        assert.is_nil(string.find(cacheText, '},"%s*With Sword%s*"}'))
        assert.is_nil(string.find(cacheText, '},"%s*With Axe%s*"}'))
        assert.is_nil(string.find(cacheText, '},"%s*With Spear%s*"}'))
    end)
end)
