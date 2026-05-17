-- @leb-regression-guard: heo-rah-rune-multiplier
-- Sibling of TestGonRuneMultiplier_spec.lua. Locks the per-rune-type
-- Multiplier infrastructure for Heo Rune and Rah Rune (Rune Master class
-- specialization). The Gon Rune flavor went in first because ward-regen
-- depended on it; the Heo/Rah affixes and tree nodes were silently
-- mis-parsed at the same time:
--
--   Heo Rune:
--     Dodge Rating affixes "+N Dodge Rating per Heo Rune" parsed as
--     `name="Evasion"` BASE=N with residue "  per Heo Rune " — the per-rune
--     multiplier was dropped. Likewise the tree node "+8% Freeze Rate
--     Multiplier per Heo Rune" lost its multiplier.
--
--   Rah Rune:
--     Armor affixes "+N Armor per Rah Rune" parsed as `name="Armour"`
--     BASE=N with residue "  per Rah Rune ". The tree node "2% Increased
--     Mana Regen per Rah Rune" lost its multiplier the same way.
--
-- Three sites lock together (mirroring the Gon Rune recipe):
-- 1. ModParser modTagList `["per heo rune"] = Multiplier:HeoRune`
--    and `["per rah rune"] = Multiplier:RahRune`
-- 2. ConfigOptions `multiplierHeoRune` / `multiplierRahRune` counts
--    publishing `Multiplier:HeoRune` / `Multiplier:RahRune` to modList
--    so users can dial in their active rune count via the Config tab.
-- 3. ModCache affix entries carry the matching Multiplier tag and an
--    empty residue.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("HeoRahRuneMultipliers", function()
    local parserText, cacheText, configText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
        configText = readSource("Modules/ConfigOptions.lua")
    end)

    it("ModParser modTagList carries the 'per heo rune' Multiplier tag", function()
        assert.is_truthy(string.find(parserText,
            '%["per heo rune"%]%s*=%s*{ tag = { type = "Multiplier", var = "HeoRune" } }', 1, false),
            "ModParser must map 'per heo rune' to Multiplier:HeoRune")
    end)

    it("ModParser modTagList carries the 'per rah rune' Multiplier tag", function()
        assert.is_truthy(string.find(parserText,
            '%["per rah rune"%]%s*=%s*{ tag = { type = "Multiplier", var = "RahRune" } }', 1, false),
            "ModParser must map 'per rah rune' to Multiplier:RahRune")
    end)

    it("ConfigOptions exposes a # of Active Heo Runes count", function()
        assert.is_truthy(string.find(configText,
            'var = "multiplierHeoRune"', 1, false),
            "ConfigOptions must expose a multiplierHeoRune count entry")
        assert.is_truthy(string.find(configText,
            'Multiplier:HeoRune', 1, false),
            "Config entry must publish Multiplier:HeoRune to modList")
    end)

    it("ConfigOptions exposes a # of Active Rah Runes count", function()
        assert.is_truthy(string.find(configText,
            'var = "multiplierRahRune"', 1, false),
            "ConfigOptions must expose a multiplierRahRune count entry")
        assert.is_truthy(string.find(configText,
            'Multiplier:RahRune', 1, false),
            "Config entry must publish Multiplier:RahRune to modList")
    end)

    it("ModCache '+8% Freeze Rate Multiplier per Heo Rune' resolves to FreezeRateMultiplier gated on Multiplier:HeoRune", function()
        local needle = 'c%["%+8%% Freeze Rate Multiplier per Heo Rune"%]={{%[1%]={%[1%]={type="Multiplier",var="HeoRune"},flags=0,keywordFlags=0,name="FreezeRateMultiplier",type="BASE",value=8}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache entry for Freeze Rate Multiplier per Heo Rune must carry Multiplier:HeoRune tag")
    end)

    it("ModCache '2% Increased Mana Regen per Rah Rune' resolves to ManaRegen gated on Multiplier:RahRune", function()
        local needle = 'c%["2%% Increased Mana Regen per Rah Rune"%]={{%[1%]={%[1%]={type="Multiplier",var="RahRune"},flags=0,keywordFlags=0,name="ManaRegen",type="INC",value=2}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache entry for Mana Regen per Rah Rune must carry Multiplier:RahRune tag")
    end)

    it("ModCache Dodge Rating per Heo Rune affixes carry Multiplier:HeoRune", function()
        -- Spot-check a representative tier (value=102).
        local needle = 'c%["%+102 Dodge Rating per Heo Rune"%]={{%[1%]={%[1%]={type="Multiplier",var="HeoRune"},flags=0,keywordFlags=0,name="Evasion",type="BASE",value=102}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache Dodge Rating per Heo Rune affix must carry Multiplier:HeoRune tag")
    end)

    it("ModCache Armor per Rah Rune affixes carry Multiplier:RahRune", function()
        -- Spot-check a representative tier (value=108).
        local needle = 'c%["%+108 Armor per Rah Rune"%]={{%[1%]={%[1%]={type="Multiplier",var="RahRune"},flags=0,keywordFlags=0,name="Armour",type="BASE",value=108}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache Armor per Rah Rune affix must carry Multiplier:RahRune tag")
    end)

    it("ModCache must NOT carry the stale residue for Heo Rune entries", function()
        assert.is_nil(string.find(cacheText, '},"  per Heo Rune "}', 1, true),
            "ModCache must not contain any '  per Heo Rune ' residue strings")
    end)

    it("ModCache must NOT carry the stale residue for Rah Rune entries", function()
        assert.is_nil(string.find(cacheText, '},"  per Rah Rune "}', 1, true),
            "ModCache must not contain any '  per Rah Rune ' residue strings")
    end)
end)
