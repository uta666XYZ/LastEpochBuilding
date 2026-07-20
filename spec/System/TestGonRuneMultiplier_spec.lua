-- @leb-regression-guard: gon-rune-multiplier
-- Locks the per-rune-type Multiplier infrastructure for the Rune Master
-- tree node "Empowered Runes" (tree_1.json L12835):
--     stats: "+4 Ward Gain Per Second per Gon Rune"
-- and the matching `["ward gain per second"]` nameMap alias.
--
-- Before this guard the line fell through to `name="Ward"` (max ward)
-- BASE=4 with residue "  Gain Per Second per Gon Rune ". Allocating the
-- node granted +4 max Ward (independent of Gon Rune count) instead of
-- +4 WPS per active Gon Rune. Silent failure invisible in any numeric
-- Ward output diff.
--
-- Three sites lock together:
-- 1. ModParser modTagList `["per gon rune"] = Multiplier:GonRune`
-- 2. ModParser nameMap `["ward gain per second"] = WardPerSecond`
--    (note: distinct from "ward gained per second" — drops the "-ed")
-- 3. ConfigOptions `multiplierGonRune` count driving `Multiplier:GonRune`
--    so users can dial in their active Gon Rune count via the Config tab.
--
-- Rah/Heo per-rune-type multipliers are intentionally NOT wired here
-- because no ward-regen stat depends on them. When their stats land,
-- mirror this pattern.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("GonRuneMultiplier", function()
    local parserText, cacheText, configText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
        configText = readSource("Modules/ConfigOptions.lua")
    end)

    it("ModParser modTagList carries the 'per gon rune' Multiplier tag", function()
        assert.is_truthy(string.find(parserText,
            '%["per gon rune"%]%s*=%s*{ tag = { type = "Multiplier", var = "GonRune" } }', 1, false),
            "ModParser must map 'per gon rune' to Multiplier:GonRune")
    end)

    it("ModParser nameMap carries the 'ward gain per second' alias (no '-ed')", function()
        assert.is_truthy(string.find(parserText,
            '%["ward gain per second"%]%s*=%s*"WardPerSecond"', 1, false),
            "ModParser nameMap must alias 'ward gain per second' to WardPerSecond")
    end)

    it("ConfigOptions exposes a # of Active Gon Runes count", function()
        assert.is_truthy(string.find(configText,
            'var = "multiplierGonRune"', 1, false),
            "ConfigOptions must expose a multiplierGonRune count entry")
        assert.is_truthy(string.find(configText,
            'Multiplier:GonRune', 1, false),
            "Config entry must publish Multiplier:GonRune to modList")
    end)

    it("ModCache '+4 Ward Gain Per Second per Gon Rune' resolves to WardPerSecond gated on Multiplier:GonRune", function()
        local needle = 'c%["%+4 Ward Gain Per Second per Gon Rune"%]={{%[1%]={%[1%]={type="Multiplier",var="GonRune"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=4}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache entry must produce WardPerSecond BASE=4 with Multiplier:GonRune tag")
    end)

    it("ModCache must NOT carry the stale max-Ward parse for the Gon Rune node", function()
        assert.is_nil(string.find(cacheText,
            'c%["%+4 Ward Gain Per Second per Gon Rune"%]={{%[1%]={flags=0,keywordFlags=0,name="Ward",type="BASE"', 1, false),
            "ModCache must not contain the stale max-Ward parse for +4 Ward Gain Per Second per Gon Rune")
    end)
end)
