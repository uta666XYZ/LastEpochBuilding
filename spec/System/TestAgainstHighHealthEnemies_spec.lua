-- @leb-regression-guard: against-high-health-enemies
-- Locks the fix for the "To/Against High Health [Enemies]" enemy-conditional
-- damage-mod family. These mods (Elemental Nova en6-14 "+5% Hit Damage To High
-- Health Enemies", plus "+20/25/30% ... To/Against High Health" that were baked
-- into ModCache) previously left their condition suffix as residue -> dropped at
-- PassiveSpec.lua (`if mod.list and not mod.extra`). The fix maps the suffix to
-- an enemy ActorCondition "HighHealth" (ModParser, mirroring "against distant
-- enemies") gated by a ConfigOptions toggle `conditionEnemyHighHealth` that
-- DEFAULTS OFF -> corpus-neutral (the mods contributed nothing before, and are
-- gated-off now, so unchanged unless the user opts in). The stale ModCache
-- entries were deleted so live re-parse regenerates them conditionally.
-- Grounded 2026-07-02: with the toggle ON, Tru_Flamer Elemental Nova fire pre-mit
-- rose 526.1 -> 629.6 (+~20%, = 5x the +5% MORE node); with it OFF, unchanged.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("AgainstHighHealthEnemies", function()
    local parserText, configText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        configText = readSource("Modules/ConfigOptions.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(parserText, '@leb%-regression%-guard:against%-high%-health%-enemies'),
            "ModParser must carry the against-high-health-enemies guard marker"
        )
    end)

    it("ModParser: maps 'to/against high health [enemies]' to enemy ActorCondition HighHealth", function()
        for _, key in ipairs({ "to high health enemies", "against high health enemies", "against high health", "to high health" }) do
            assert.is_truthy(
                string.find(parserText, '%["' .. key .. '"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"ActorCondition"'),
                "ModParser must map \"" .. key .. "\" to an ActorCondition tag"
            )
        end
        assert.is_truthy(
            string.find(parserText, 'actor%s*=%s*"enemy"%s*,%s*var%s*=%s*"HighHealth"'),
            "the high-health condition must target the enemy actor with var HighHealth"
        )
    end)

    it("ConfigOptions: exposes the conditionEnemyHighHealth toggle (enemy HighHealth)", function()
        assert.is_truthy(
            string.find(configText, 'var%s*=%s*"conditionEnemyHighHealth"'),
            "ConfigOptions must expose conditionEnemyHighHealth"
        )
        assert.is_truthy(
            string.find(configText, 'ifEnemyCond%s*=%s*"HighHealth"'),
            "the toggle must gate on the enemy HighHealth condition"
        )
        assert.is_truthy(
            string.find(configText, 'Condition:HighHealth'),
            "the toggle must publish Condition:HighHealth"
        )
    end)

    it("ModCache: the stale dropped-residue high-health damage entries are removed (live re-parse)", function()
        assert.is_falsy(
            string.find(cacheText, '+5% Hit Damage To High Health Enemies', 1, true),
            "the stale '+5% Hit Damage To High Health Enemies' ModCache entry must be deleted"
        )
        assert.is_falsy(
            string.find(cacheText, '+25% Melee Damage To High Health', 1, true),
            "the stale '+25% Melee Damage To High Health' ModCache entry must be deleted"
        )
    end)
end)
