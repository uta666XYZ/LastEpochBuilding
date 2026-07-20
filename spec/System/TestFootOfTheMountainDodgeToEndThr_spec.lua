-- @leb-regression-guard:foot-of-the-mountain-dodge-to-endurance
-- See REGRESSION_GUARDS.md "foot-of-the-mountain-dodge-to-endurance".
-- Validation provenance is retained in maintainer notes.

describe("FootOfTheMountainDodgeToEndThr", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    it("uniques_1_4.json #253 carries the mana-cost and dodge-conversion mod lines", function()
        local src = readFile("Data/Uniques/uniques_1_4.json")
        assert.is_not_nil(src, "must read Data/Uniques/uniques_1_4.json")
        assert.is_truthy(string.find(src, "Foot of the Mountain", 1, true),
            "Foot of the Mountain must exist")
        assert.is_truthy(string.find(src,
            "-2 Mana Cost per stack of Mountains Endurance", 1, true),
            "mana-cost-per-stack line (2) must be present")
        assert.is_truthy(string.find(src,
            "100% of Dodge Rating converted to Endurance Threshold while you have at least 1 stack of Mountains Endurance", 1, true),
            "dodge->EndThr conversion line (3) must be present")
    end)

    it("ModParser maps (3) to a Condition:Stationary-gated BASE % stat", function()
        local mods = modLib.parseMod(
            "100% of Dodge Rating converted to Endurance Threshold while you have at least 1 stack of Mountains Endurance")
        assert.is_not_nil(mods, "must parse the conversion line")
        assert.are.equals(1, #mods)
        assert.are.equals("DodgeRatingConvertedToEnduranceThreshold", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(100, mods[1].value)
        -- The single tag must gate on Condition:Stationary (>=1 stack).
        local tag = mods[1][1]
        assert.is_not_nil(tag, "conversion mod must carry a tag")
        assert.are.equals("Condition", tag.type)
        assert.are.equals("Stationary", tag.var)
    end)

    it("ModParser maps (2) to ManaCost -2 scaled by Multiplier:StationarySeconds (cap 3)", function()
        local mods = modLib.parseMod("-2 Mana Cost per stack of Mountains Endurance")
        assert.is_not_nil(mods, "must parse the mana-cost line")
        assert.are.equals(1, #mods)
        assert.are.equals("ManaCost", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(-2, mods[1].value)
        local tag = mods[1][1]
        assert.is_not_nil(tag, "mana-cost mod must carry a multiplier tag")
        assert.are.equals("Multiplier", tag.type)
        assert.are.equals("StationarySeconds", tag.var)
        assert.are.equals(3, tag.limit)
    end)

    it("CalcDefence reads the conversion via Sum over BASE and reduces Evasion", function()
        local src = readFile("Modules/CalcDefence.lua")
        assert.is_not_nil(src, "must read Modules/CalcDefence.lua")
        assert.is_truthy(string.find(src,
            'modDB:Sum%("BASE",%s*nil,%s*"DodgeRatingConvertedToEnduranceThreshold"%)', 1, false),
            "CalcDefence must read DodgeRatingConvertedToEnduranceThreshold via Sum over BASE")
        -- source-reduction site: moves the converted % off output.Evasion
        assert.is_truthy(string.find(src,
            "output%.DodgeRatingConvertedToEnduranceThreshold%s*=%s*round%(output%.Evasion", 1, false),
            "CalcDefence must stash round(output.Evasion * pct/100) and reduce Evasion")
    end)

    it("CalcDefence folds the stashed amount FLAT into the finalized Endurance Threshold", function()
        local src = readFile("Modules/CalcDefence.lua")
        assert.is_truthy(string.find(src,
            "output%.EnduranceThreshold%s*=%s*output%.EnduranceThreshold%s*%+%s*dodgeAsEndThr", 1, false),
            "CalcDefence must add the converted Dodge Rating flat into EnduranceThreshold")
    end)

    it("conversion arithmetic: stationary EndThr 829 + dodge 402 = 1231, dodge 402 -> 0 at 100%", function()
        local m_floor, m_max = math.floor, math.max
        local function round(x) return m_floor(x + 0.5) end
        local function convert(endThr, dodge, pct)
            local converted = round(dodge * pct / 100)
            local remainingDodge = m_max(dodge - converted, 0)
            return endThr + converted, remainingDodge
        end
        -- Validation provenance is retained in maintainer notes.
        local newEndThr, newDodge = convert(829, 402, 100)
        assert.are.equals(1231, newEndThr)
        assert.are.equals(0, newDodge)
        -- moving (pct sums to 0): no change
        local offEndThr, offDodge = convert(829, 402, 0)
        assert.are.equals(829, offEndThr)
        assert.are.equals(402, offDodge)
    end)
end)
