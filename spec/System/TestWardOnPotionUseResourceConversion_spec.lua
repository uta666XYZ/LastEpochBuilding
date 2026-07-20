-- @leb-regression-guard: ward-on-potion-use-resource-conversion
-- Locks the parser+integration contract for the event-driven resource→ward
-- conversion affixes that fire on potion use:
--   * `Missing Health gained as Ward on Potion Use` (multi_affix 57778 etc.)
--   * `Potion Health Converted to Ward` (multi_affix 43665 etc.)
--
-- Before this guard the bare `+N%` Missing-Health form was mis-parsed as
-- Life INC (silent failure) and the `% of Potion Health Converted to Ward`
-- form was intercepted by the generic `% of X converted to Y` handler and
-- fell through to LEB_NotSupported despite the keyword existing in
-- modNameList. Both were silent — no numeric Ward-on-Potion-Use diff.
--
-- See REGRESSION_GUARDS.md "ward-on-potion-use-resource-conversion".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardOnPotionUseResourceConversion", function()
    local parserText, defenceText, sectionsText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        defenceText = readSource("Modules/CalcDefence.lua")
        sectionsText = readSource("Modules/CalcSections.lua")
    end)

    describe("ModParser", function()
        it("recognises '% of Missing Health gained as Ward on Potion Use'", function()
            assert.is_truthy(string.find(parserText,
                "of missing health gained as ward on potion use", 1, true),
                "ModParser must carry the '% of missing health gained as ward on potion use' pattern")
        end)

        it("recognises bare '% Missing Health gained as Ward on Potion Use'", function()
            assert.is_truthy(string.find(parserText,
                '%%%% missing health gained as ward on potion use%$', 1, false),
                "ModParser must carry the bare '% missing health gained as ward on potion use' pattern")
        end)

        it("recognises '% of Potion Health Converted to Ward'", function()
            assert.is_truthy(string.find(parserText,
                "of potion health converted to ward%$", 1, false),
                "ModParser must carry the '% of potion health converted to ward' pattern (specialModList, not just keyword)")
        end)

        it("emits MissingHealthGainedAsWardOnPotionUse mod kind", function()
            assert.is_truthy(string.find(parserText,
                '"MissingHealthGainedAsWardOnPotionUse"', 1, true),
                "ModParser must emit MissingHealthGainedAsWardOnPotionUse")
        end)

        it("emits PotionHealthConvertedToWard mod kind from specialModList", function()
            -- The keyword in modNameList exists; the specialModList must also
            -- emit it so the generic converted-to handler doesn't win first.
            local _, count = string.gsub(parserText,
                '"PotionHealthConvertedToWard"', "")
            assert.is_true(count >= 2,
                "PotionHealthConvertedToWard must appear in both modNameList AND specialModList (got " .. count .. ")")
        end)

        it("carries the inline regression-guard marker", function()
            assert.is_truthy(string.find(parserText,
                "@leb-regression-guard:ward-on-potion-use-resource-conversion (parser site)", 1, true),
                "inline guard ID (parser site) must remain in ModParser.lua")
        end)
    end)

    describe("CalcDefence integration", function()
        it("Sums MissingHealthGainedAsWardOnPotionUse + Multiplier:MissingHealthPercent", function()
            assert.is_truthy(string.find(defenceText,
                'MissingHealthGainedAsWardOnPotionUse', 1, true),
                "CalcDefence must consume MissingHealthGainedAsWardOnPotionUse")
            assert.is_truthy(string.find(defenceText,
                "Multiplier:MissingHealthPercent", 1, true),
                "CalcDefence must read Multiplier:MissingHealthPercent")
        end)

        it("publishes output.WardOnPotionUse = flat + missing-health contribution", function()
            assert.is_truthy(string.find(defenceText,
                "output.WardOnPotionUse = flat + mhContribution", 1, true),
                "output.WardOnPotionUse must combine flat + missing-health contributions")
        end)

        it("publishes breakdown.WardOnPotionUse when value > 0", function()
            assert.is_truthy(string.find(defenceText,
                "breakdown.WardOnPotionUse = lines", 1, true),
                "CalcDefence must publish breakdown.WardOnPotionUse")
        end)

        it("carries the inline regression-guard marker", function()
            assert.is_truthy(string.find(defenceText,
                "@leb-regression-guard:ward-on-potion-use-resource-conversion (calc site)", 1, true),
                "inline guard ID (calc site) must remain in CalcDefence.lua")
        end)
    end)

    describe("CalcSections row", function()
        it("wires breakdown.WardOnPotionUse and modName auto-breakdown", function()
            assert.is_truthy(string.find(sectionsText,
                '{ breakdown = "WardOnPotionUse" }', 1, true),
                "row must reference breakdown.WardOnPotionUse")
            assert.is_truthy(string.find(sectionsText,
                '"WardOnPotionUse", "MissingHealthGainedAsWardOnPotionUse"', 1, true),
                "row modName must include both source mod kinds")
        end)
    end)
end)
