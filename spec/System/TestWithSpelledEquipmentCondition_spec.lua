-- @leb-regression-guard:with-spelled-equipment-condition
-- Spelled-out equipment-condition suffixes the parser previously lacked, so the
-- stat parsed with the condition left as `extra` residue and PassiveSpec.lua:1024
-- (`if mod.list and not mod.extra`) dropped it (same silent-drop class as
-- with-1h-suffix-family / with-2h-suffix-family).
--   - "With Two Handed Weapon" (verbose form of "With 2h Weapon") -> UsingTwoHandedWeapon
--     ("+10% Area With Two Handed Weapon").
--   - "With Shield" (article-less form of "with a shield") -> UsingShield
--     ("15% Increased Physical Damage With Shield", "+15% Bleed Chance With Shield",
--      "+20 Armour With Shield", "+6% Frailty Chance With Shield",
--      "3% Increased Armor With Shield"). UsingShield: CalcPerform.lua:161 / CalcSetup.lua:2017.
-- ModParser registration + the 6 cache-keyed ModCache entries are locked together
-- (ModCache short-circuits parseMod, so the parser fix alone is inert — see
-- with-1h-suffix-family).

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

describe("WithSpelledEquipmentCondition", function()
    local parserText, cacheText

    setup(function()
        newBuild()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser registers 'with two handed weapon' -> UsingTwoHandedWeapon", function()
        assert.is_truthy(string.find(parserText,
            'modTagList%["with two handed weapon"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"UsingTwoHandedWeapon"'),
            "ModParser must register 'with two handed weapon'")
    end)

    it("ModParser registers 'with shield' -> UsingShield", function()
        assert.is_truthy(string.find(parserText,
            'modTagList%["with shield"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"UsingShield"'),
            "ModParser must register 'with shield'")
    end)

    it("inline guard marker present in ModParser.lua", function()
        assert.is_truthy(string.find(parserText, "with-spelled-equipment-condition", 1, true))
    end)

    it("ModCache: '+10% Area With Two Handed Weapon' carries UsingTwoHandedWeapon, empty residue", function()
        local needle = 'c%["%+10%% Area With Two Handed Weapon"%]={{%[1%]={%[1%]={type="Condition",var="UsingTwoHandedWeapon"},flags=0,keywordFlags=0,name="AreaOfEffect",type="BASE",value=10}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: '15% Increased Physical Damage With Shield' carries UsingShield, empty residue", function()
        local needle = 'c%["15%% Increased Physical Damage With Shield"%]={{%[1%]={%[1%]={type="Condition",var="UsingShield"},flags=0,keywordFlags=0,name="PhysicalDamage",type="INC",value=15}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false))
    end)

    it("ModCache: no spelled equipment entry retains the stale residue form", function()
        assert.is_nil(string.find(cacheText, '"  With Two Handed Weapon "', 1, true),
            "no entry may keep stale 'With Two Handed Weapon' residue")
        assert.is_nil(string.find(cacheText, '"  With Shield "', 1, true),
            "no entry may keep stale 'With Shield' residue")
    end)

    it("live parse (cache-busted) '+11% Area With Two Handed Weapon' -> AreaOfEffect + UsingTwoHandedWeapon, no residue", function()
        local list, extra = modLib.parseMod("+11% Area With Two Handed Weapon")
        assert.is_not_nil(list)
        assert.is_falsy(extra and extra:match("%S"))
        local m
        for _, x in ipairs(list) do if x.name == "AreaOfEffect" then m = x end end
        assert.is_not_nil(m)
        assert.is_true(condVar(m, "UsingTwoHandedWeapon"))
    end)

    it("live parse (cache-busted) '16% Increased Physical Damage With Shield' -> PhysicalDamage + UsingShield, no residue", function()
        local list, extra = modLib.parseMod("16% Increased Physical Damage With Shield")
        assert.is_not_nil(list)
        assert.is_falsy(extra and extra:match("%S"))
        local m
        for _, x in ipairs(list) do if x.name == "PhysicalDamage" then m = x end end
        assert.is_not_nil(m)
        assert.is_true(condVar(m, "UsingShield"))
    end)
end)
