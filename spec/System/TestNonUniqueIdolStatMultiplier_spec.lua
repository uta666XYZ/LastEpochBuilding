-- @leb-regression-guard: non-unique-idol-stat-multiplier
-- the residual within range-rounding tolerance. See REGRESSION_GUARDS.md
-- Validation provenance is retained in maintainer notes.

describe("NonUniqueIdolStatMultiplier", function()

    describe("ModParser parses both forms to Multiplier:NonUniqueIdolStatEffect BASE", function()
        local cache
        setup(function()
            cache = modLib.parseModCache
            assert.is_not_nil(cache, "modLib.parseModCache must be populated by HeadlessWrapper")
        end)

        local function checkEntry(line, expectedValue)
            local entry = cache[line]
            if not entry then
                local mods, extra = modLib.parseMod(line)
                entry = { mods, extra }
            end
            local mods, extra = entry[1], entry[2]
            assert.is_nil(extra, "line `" .. line .. "` must parse with no unparsed leftover")
            assert.is_not_nil(mods, "line `" .. line .. "` must produce a parsed mod list")
            assert.are.equals(1, #mods, "line `" .. line .. "` must produce exactly one mod")
            local m = mods[1]
            assert.are.equals("Multiplier:NonUniqueIdolStatEffect", m.name)
            assert.are.equals("BASE", m.type)
            assert.are.equals(expectedValue, m.value)
        end

        it("'+50% Non-Unique Idol Stat Multiplier' (LEB-internal text) → BASE 50", function()
            checkEntry("+50% Non-Unique Idol Stat Multiplier", 50)
        end)

        it("'Stats on your Non-Unique Idols have 50% increased Effect' (game text) → BASE 50", function()
            checkEntry("Stats on your Non-Unique Idols have 50% increased Effect", 50)
        end)
    end)

    describe("CalcSetup pre-scan and scale", function()
        local source
        setup(function()
            local f = io.open("Modules/CalcSetup.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
            source = f:read("*a")
            f:close()
        end)

        it("regression-guard comment block is present", function()
            assert.is_truthy(string.find(source, "non-unique-idol-stat-multiplier", 1, true),
                "CalcSetup.lua must keep the @leb-regression-guard comment so future edits trip review")
        end)

        it("declares `local nonUniqueIdolEffectPercent = 0` and a pre-scan loop", function()
            assert.is_truthy(string.find(source, "local%s+nonUniqueIdolEffectPercent%s*=%s*0"),
                "CalcSetup.lua must declare the pre-scan accumulator")
            assert.is_truthy(string.find(source, 'm%.name%s*==%s*"Multiplier:NonUniqueIdolStatEffect"'),
                "CalcSetup.lua must scan item modLists for Multiplier:NonUniqueIdolStatEffect")
        end)

        it("computes nonUniqueIdolScale = 1 + N/100", function()
            assert.is_truthy(string.find(source,
                "local%s+nonUniqueIdolScale%s*=%s*1%s*%+%s*nonUniqueIdolEffectPercent%s*/%s*100"),
                "CalcSetup.lua must convert the percent into a (1 + N/100) scale")
        end)

        it("excludes Idol Altar and unique/set rarity from the scale", function()
            -- All four conditions must appear within the same neighbourhood as
            -- the scale assignment so we don't accidentally scale the wrong
            -- items in the future.
            local i = string.find(source, "scale%s*=%s*scale%s*%*%s*nonUniqueIdolScale")
            assert.is_not_nil(i, "scale assignment using nonUniqueIdolScale must exist")
            local window = string.sub(source, math.max(1, i - 600), i + 200)
            assert.is_truthy(string.find(window, '"Idol Altar"', 1, true),
                "scale block must exclude `Idol Altar`")
            assert.is_truthy(string.find(window, '"%s+Idol"', 1, false)
                          or string.find(window, '" Idol"', 1, true),
                "scale block must check for ` Idol` base-type suffix")
            assert.is_truthy(string.find(window, '"UNIQUE"', 1, true),
                "scale block must exclude UNIQUE rarity")
            assert.is_truthy(string.find(window, '"SET"', 1, true),
                "scale block must exclude SET rarity")
        end)
    end)

    describe("Reliquary Nest text adopts the game tooltip wording", function()
        it("uniques_1_4.json carries the game text, not the LEB-internal placeholder", function()
            local f = io.open("Data/Uniques/uniques_1_4.json", "r")
            assert.is_not_nil(f, "must be able to open Data/Uniques/uniques_1_4.json")
            local source = f:read("*a")
            f:close()
            assert.is_truthy(string.find(source,
                "Stats on your Non%-Unique Idols have %(40%-60%)%% increased Effect", 1, false),
                "Reliquary Nest must use the game-faithful tooltip text")
            assert.is_falsy(string.find(source,
                "%(40%-60%)%% Non%-Unique Idol Stat Multiplier", 1, false),
                "the legacy LEB-internal text must not appear anywhere")
        end)
    end)
end)
