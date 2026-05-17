-- @leb-regression-guard: ward-regen-resource-conversion
-- Locks the parser+integration contract for the continuous resource→ward
-- conversion affixes. Source: LE_datamining multi_affixes_v3.json entries
--   58051 / 59414  "Missing Health gained as Ward per Second"
--   59006          "Current Mana Gained as Ward Per Second"
--
-- Before this guard the parser dropped these lines to LEB_NotSupported (form
-- "X% of Y gained as Z") or mis-parsed the +N% form as Life/Mana INC (no
-- WardPerSecond contribution at all). Both are silent failures that don't
-- show up in any numeric Ward output diff.
--
-- See REGRESSION_GUARDS.md "ward-regen-resource-conversion".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardRegenResourceConversion", function()
    local parserText, performText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        performText = readSource("Modules/CalcPerform.lua")
    end)

    describe("ModParser specialModList entries", function()
        it("recognises '% of Missing Health gained as Ward per second'", function()
            assert.is_truthy(string.find(parserText,
                "of missing health gained as ward per second", 1, true),
                "ModParser must carry the '% of missing health gained as ward per second' pattern")
        end)

        it("recognises bare '% Missing Health gained as Ward per second' (no 'of')", function()
            -- Anchored variant for the +N% form that omits "of"
            assert.is_truthy(string.find(parserText,
                '%%%% missing health gained as ward per second%$', 1, false),
                "ModParser must carry the bare '% missing health gained as ward per second' pattern")
        end)

        it("recognises '% of Current Mana gained as Ward per second'", function()
            assert.is_truthy(string.find(parserText,
                "of current mana gained as ward per second", 1, true),
                "ModParser must carry the '% of current mana gained as ward per second' pattern")
        end)

        it("recognises bare '% Current Mana gained as Ward per second'", function()
            assert.is_truthy(string.find(parserText,
                '%%%% current mana gained as ward per second%$', 1, false),
                "ModParser must carry the bare '% current mana gained as ward per second' pattern")
        end)

        it("emits MissingHealthGainedAsWardPerSecond mod kind", function()
            assert.is_truthy(string.find(parserText,
                '"MissingHealthGainedAsWardPerSecond"', 1, true),
                "ModParser must emit MissingHealthGainedAsWardPerSecond")
        end)

        it("emits CurrentManaGainedAsWardPerSecond mod kind", function()
            assert.is_truthy(string.find(parserText,
                '"CurrentManaGainedAsWardPerSecond"', 1, true),
                "ModParser must emit CurrentManaGainedAsWardPerSecond")
        end)
    end)

    describe("CalcPerform post-offence fold-in", function()
        it("consumes MissingHealthGainedAsWardPerSecond + Multiplier:MissingHealthPercent", function()
            assert.is_truthy(string.find(performText,
                'MissingHealthGainedAsWardPerSecond', 1, true),
                "CalcPerform must Sum MissingHealthGainedAsWardPerSecond")
            assert.is_truthy(string.find(performText,
                "Multiplier:MissingHealthPercent", 1, true),
                "CalcPerform must read Multiplier:MissingHealthPercent (drives missing-health share)")
        end)

        it("consumes CurrentManaGainedAsWardPerSecond against final Mana", function()
            assert.is_truthy(string.find(performText,
                'CurrentManaGainedAsWardPerSecond', 1, true),
                "CalcPerform must Sum CurrentManaGainedAsWardPerSecond")
        end)

        it("carries the ward-regen-resource-conversion inline guard markers", function()
            local _, count = string.gsub(performText,
                "@leb%-regression%-guard:ward%-regen%-resource%-conversion", "")
            -- Two sites: (1) post-offence fold-in, (2) breakdown construction.
            assert.are.equals(2, count,
                "CalcPerform must carry 2 ward-regen-resource-conversion markers (fold-in + breakdown sites)")
        end)

        it("constructs breakdown.WardPerSecond when contributions are non-zero", function()
            assert.is_truthy(string.find(performText,
                "env.player.breakdown.WardPerSecond = lines", 1, true),
                "CalcPerform must publish a breakdown.WardPerSecond table from the fold-in block")
        end)

        it("ModParser carries the ward-regen-resource-conversion inline guard marker", function()
            local _, count = string.gsub(parserText,
                "@leb%-regression%-guard:ward%-regen%-resource%-conversion", "")
            assert.are.equals(1, count,
                "ModParser must carry exactly 1 ward-regen-resource-conversion marker")
        end)
    end)

    describe("passive vs event-driven gate", function()
        it("missing-health + current-mana contributions feed passiveWardPerSecond", function()
            -- These are continuous regen (game `wardRegenFromStats`) so they MUST
            -- count toward the floor-gate snapshot. mana-spent is event-driven and
            -- must NOT. The structural assertion is that passiveWardPerSecond is
            -- assembled from the two passive contributions.
            assert.is_truthy(string.find(performText,
                "passiveWardPerSecond = .- %+ currentManaContribution %+ missingHealthContribution",
                1, false),
                "passiveWardPerSecond must include currentManaContribution + missingHealthContribution")
        end)
    end)
end)
