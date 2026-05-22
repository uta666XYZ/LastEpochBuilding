-- @leb-regression-guard: armour-pct-shorthand-inc
-- Locks the BASE_MORE->INC promotion for "+N% Armor" shorthand text.
--
-- Evidence (LE_datamining extracted/items/multi_affixes_v3.json affix 1007):
--   affixName: "Increased Armor and Damage Reflected to Attackers per Armor Mitigation"
--   affixProperties[0]: property=10 (Armor), modifierType=1 (INC)
-- ModItem_1_4.json renders the row as "+(24-30)% Armor" default and
-- "+(85-90)% Armor" body_armor slotOverride at tier 5 (no "increased" word
-- in shorthand). Without the Armour entry in the ModParser INC-promotion
-- list, the prefix falls through to BASE and is applied as flat +N Armor.
--
-- Affected at v0.14.6 (4 builds with negative Armor delta):
--   oN2zNnaR Necromancer  D=-667
--   BGzxJrgn Bladedancer  D=-436
--   Qqwv6zbR Bladedancer  D=-285
--   QeY79rn2 Necromancer  D=-208
--
-- Three sites lock together:
-- a. `Modules/ModParser.lua` BASE_MORE branch includes "Armour" in the
--    INC promotion list alongside Life/Mana/Ward/ManaRegen/LifeRegen.
-- b. `Data/ModCache.lua` plain "+N% Armor" entries carry name="Armour"
--    type="INC" (not type="BASE").
-- c. The promotion is scoped to bare modName == "Armour" — entries with
--    modSuffix in modFlags (explicit MORE/BASE marker) still bypass.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ArmourPctShorthandInc", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser BASE_MORE branch includes 'Armour' in INC promotion list", function()
        assert.is_truthy(string.find(parserText,
            'modNameStr == "Life" or modNameStr == "Mana" or modNameStr == "Ward"', 1, true),
            "INC-promotion list anchor (Life/Mana/Ward) must remain present")
        assert.is_truthy(string.find(parserText,
            'or modNameStr == "ManaRegen" or modNameStr == "LifeRegen" or modNameStr == "Armour"', 1, true),
            "INC-promotion list must include 'Armour' after ManaRegen/LifeRegen")
    end)

    it("ModParser carries @leb-regression-guard: armour-pct-shorthand-inc marker", function()
        assert.is_truthy(string.find(parserText,
            "@leb-regression-guard: armour-pct-shorthand-inc", 1, true),
            "Promotion site must carry the named guard marker")
    end)

    for _, num in ipairs({"15", "25", "27", "34", "35", "41", "44", "48", "53", "55", "62", "68", "71", "80", "88"}) do
        it("ModCache '+" .. num .. "% Armor' carries name=Armour type=INC", function()
            local needle = 'c["+' .. num .. '% Armor"]={{[1]={flags=0,keywordFlags=0,name="Armour",type="INC",value=' .. num .. '}},nil}'
            assert.is_truthy(string.find(cacheText, needle, 1, true),
                "+" .. num .. "%% Armor entry must carry type=INC (got something else)")
        end)

        it("ModCache '+" .. num .. "% Armor' must NOT carry the stale BASE form", function()
            local stale = 'c["+' .. num .. '% Armor"]={{[1]={flags=0,keywordFlags=0,name="Armour",type="BASE",value=' .. num .. '}},nil}'
            assert.is_nil(string.find(cacheText, stale, 1, true),
                "+" .. num .. "%% Armor entry must not carry the stale unconditional BASE form")
        end)
    end
end)
