-- @leb-regression-guard: ward-on-block-resource-conversion
-- Locks the parser+integration contract for the event-driven resource→ward
-- conversion affix: LE_datamining multi_affixes_v3.json affixId 963
-- "Added Block Chance and Current Mana gained as Ward on Block" (Shield prefix,
-- corrupted-exclusive). Before this guard the bare `+N%` form was mis-parsed
-- as Mana INC + Condition:Blocking and the "% of" form fell through to
-- LEB_NotSupported (both silent failures with no numeric Ward-on-Block diff).
--
-- See REGRESSION_GUARDS.md "ward-on-block-resource-conversion".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardOnBlockResourceConversion", function()
    local parserText, defenceText, sectionsText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        defenceText = readSource("Modules/CalcDefence.lua")
        sectionsText = readSource("Modules/CalcSections.lua")
    end)

    describe("ModParser", function()
        it("recognises '% of Current Mana gained as Ward on Block'", function()
            assert.is_truthy(string.find(parserText,
                "of current mana gained as ward on block", 1, true),
                "ModParser must carry the '% of current mana gained as ward on block' pattern")
        end)

        it("recognises bare '% Current Mana gained as Ward on Block'", function()
            assert.is_truthy(string.find(parserText,
                '%%%% current mana gained as ward on block%$', 1, false),
                "ModParser must carry the bare '% current mana gained as ward on block' pattern")
        end)

        it("emits CurrentManaGainedAsWardOnBlock mod kind", function()
            assert.is_truthy(string.find(parserText,
                '"CurrentManaGainedAsWardOnBlock"', 1, true),
                "ModParser must emit CurrentManaGainedAsWardOnBlock")
        end)

        it("carries the inline regression-guard marker", function()
            assert.is_truthy(string.find(parserText,
                "@leb-regression-guard:ward-on-block-resource-conversion (parser site)", 1, true),
                "inline guard ID (parser site) must remain in ModParser.lua")
        end)
    end)

    describe("CalcDefence integration", function()
        it("Sums WardOnBlock BASE for the flat contribution", function()
            assert.is_truthy(string.find(defenceText,
                'modDB:Sum%("BASE", nil, "WardOnBlock"%)', 1, false),
                "CalcDefence must Sum the existing flat WardOnBlock BASE mod")
        end)

        it("Sums CurrentManaGainedAsWardOnBlock against final Mana", function()
            assert.is_truthy(string.find(defenceText,
                'CurrentManaGainedAsWardOnBlock', 1, true),
                "CalcDefence must consume CurrentManaGainedAsWardOnBlock")
        end)

        it("publishes output.WardOnBlock = flat + mana contribution", function()
            assert.is_truthy(string.find(defenceText,
                "output.WardOnBlock = wardOnBlockFlat + wardOnBlockManaContribution", 1, true),
                "output.WardOnBlock must combine the flat and mana contributions")
        end)

        it("publishes breakdown.WardOnBlock when value > 0", function()
            assert.is_truthy(string.find(defenceText,
                "breakdown.WardOnBlock = lines", 1, true),
                "CalcDefence must publish breakdown.WardOnBlock from the calc site")
        end)

        it("carries the inline regression-guard marker", function()
            assert.is_truthy(string.find(defenceText,
                "@leb-regression-guard:ward-on-block-resource-conversion (calc site)", 1, true),
                "inline guard ID (calc site) must remain in CalcDefence.lua")
        end)
    end)

    describe("CalcSections row", function()
        it("renders a 'Ward on Block' row tied to output.WardOnBlock", function()
            assert.is_truthy(string.find(sectionsText,
                'label = "Ward on Block".-haveOutput = "WardOnBlock"', 1, false),
                "CalcSections must carry a 'Ward on Block' row with haveOutput gate")
        end)

        it("wires breakdown.WardOnBlock and modName auto-breakdown", function()
            assert.is_truthy(string.find(sectionsText,
                '{ breakdown = "WardOnBlock" }', 1, true),
                "row must reference breakdown.WardOnBlock")
            assert.is_truthy(string.find(sectionsText,
                '"WardOnBlock", "CurrentManaGainedAsWardOnBlock"', 1, true),
                "row modName must include both source mod kinds")
        end)
    end)
end)
