-- @leb-regression-guard:with-1h-suffix-family
-- Locks the colloquial "With 1h" / "With 1h Weapon" suffix family, the 1H
-- counterpart of the "with 2h" family (TestWith2hSuffix_spec). Source: passive
-- node Rogue-88 "Fencing Grace" ("6% Increased Damage With 1h Weapon",
-- "+5% Block Chance With 1h Weapon").
--
-- Bug: ModParser had "with 2h"/"with 2h weapon" but NOT the 1h equivalents, so
-- parseMod recognised the leading "X% increased damage" (list non-nil) but left
-- "with 1h weapon" as `extra`. PassiveSpec.lua:1024 (`if mod.list and not
-- mod.extra`) then DROPS the whole mod -> the conditional damage silently
-- vanished for 1H-wielding rogues who allocate Rogue-88 (UNDER-count). The
-- condition var UsingOneHandedWeapon is published by CalcPerform.lua:177-178/196
-- (info.oneHand), so the gate applies for 1H and evaluates false (0) for 2H/bow.
--
-- Two things are locked:
--  1. ModParser registers "with 1h"/"with 1h weapon" -> UsingOneHandedWeapon.
--  2. parseMod on the real node stat returns the Damage INC mod WITH the
--     UsingOneHandedWeapon condition and NO leftover `extra` (so it is no longer
--     dropped by the PassiveSpec extra-gate).

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

describe("With1hSuffixFamily", function()
    local parserText, cacheText

    setup(function()
        newBuild()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser registers 'with 1h' and 'with 1h weapon' -> UsingOneHandedWeapon", function()
        assert.is_truthy(string.find(parserText,
            'modTagList%["with 1h"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"UsingOneHandedWeapon"'),
            "ModParser must register generic 'with 1h' suffix")
        assert.is_truthy(string.find(parserText,
            'modTagList%["with 1h weapon"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"UsingOneHandedWeapon"'),
            "ModParser must register 'with 1h weapon' suffix")
    end)

    it("inline guard marker present in ModParser.lua", function()
        assert.is_truthy(string.find(parserText, "with-1h-suffix-family", 1, true),
            "ModParser.lua must carry the inline guard marker")
    end)

    it("'6% Increased Damage With 1h Weapon' parses to Damage INC + UsingOneHandedWeapon, no residue", function()
        local list, extra = modLib.parseMod("6% Increased Damage With 1h Weapon")
        assert.is_not_nil(list, "the stat must parse (list non-nil)")
        assert.is_falsy(extra and extra:match("%S"), "no non-space residue left in `extra` (else PassiveSpec drops the mod)")
        local found
        for _, m in ipairs(list) do
            if m.name == "Damage" and m.type == "INC" then found = m end
        end
        assert.is_not_nil(found, "must emit a Damage INC mod")
        assert.are.equals(6, found.value)
        assert.is_true(condVar(found, "UsingOneHandedWeapon"), "Damage INC must carry UsingOneHandedWeapon condition")
    end)

    it("ModCache: '6% Increased Damage With 1h Weapon ' carries UsingOneHandedWeapon, empty residue", function()
        local needle = 'c%["6%% Increased Damage With 1h Weapon "%]={{%[1%]={%[1%]={type="Condition",var="UsingOneHandedWeapon"},flags=0,keywordFlags=0,name="Damage",type="INC",value=6}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache Damage entry must carry the condition with empty residue (else PassiveSpec drops it)")
    end)

    it("ModCache: '+5% Block Chance With 1h Weapon ' carries UsingOneHandedWeapon, empty residue", function()
        local needle = 'c%["%+5%% Block Chance With 1h Weapon "%]={{%[1%]={%[1%]={type="Condition",var="UsingOneHandedWeapon"},flags=0,keywordFlags=0,name="BlockChance",type="BASE",value=5}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache BlockChance entry must carry the condition with empty residue")
    end)

    it("ModCache: no 1h entry retains the stale residue form", function()
        assert.is_nil(string.find(cacheText, '"  With 1h Weapon "', 1, true),
            "no ModCache 1h entry may keep the stale '  With 1h Weapon ' residue")
    end)

    it("trailing-space variant '...With 1h Weapon ' also parses cleanly (raw tree form, via patched cache)", function()
        local list, extra = modLib.parseMod("6% Increased Damage With 1h Weapon ")
        assert.is_not_nil(list)
        assert.is_falsy(extra and extra:match("%S"))
        local found
        for _, m in ipairs(list) do
            if m.name == "Damage" and m.type == "INC" then found = m end
        end
        assert.is_not_nil(found)
        assert.is_true(condVar(found, "UsingOneHandedWeapon"))
    end)
end)
