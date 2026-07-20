-- @leb-regression-guard:offhand-exalted-weapon-stat-multiplier
-- <private build>) -- all affected. See REGRESSION_GUARDS.md
-- Validation provenance is retained in maintainer notes.

describe("WhetstoneGavelOffhandExalted", function()

    describe("ModParser parses the affix to Multiplier:OffhandExaltedWeaponStatEffect BASE", function()
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
            assert.are.equals("Multiplier:OffhandExaltedWeaponStatEffect", m.name)
            assert.are.equals("BASE", m.type)
            assert.are.equals(expectedValue, m.value)
        end

        it("'90% increased effectiveness of Stats on an offhand Exalted Weapon' → BASE 90", function()
            checkEntry("90% increased effectiveness of Stats on an offhand Exalted Weapon", 90)
        end)

        it("'95% increased effectiveness of Stats on an offhand Exalted Weapon' → BASE 95 (cached roll)", function()
            checkEntry("95% increased effectiveness of Stats on an offhand Exalted Weapon", 95)
        end)

        it("'100% increased effectiveness of Stats on an offhand Exalted Weapon' → BASE 100", function()
            checkEntry("100% increased effectiveness of Stats on an offhand Exalted Weapon", 100)
        end)
    end)

    describe("ModCache row for the cached 95% roll is baked (not the empty no-op)", function()
        it("carries the parsed mod with nil extra", function()
            local line = "95% increased effectiveness of Stats on an offhand Exalted Weapon"
            local entry = modLib.parseModCache[line]
            assert.is_not_nil(entry, "the 95% roll must remain a cached ModCache entry")
            local mods, extra = entry[1], entry[2]
            assert.is_nil(extra, "ModCache extra must be nil, not the leftover placeholder string")
            assert.are.equals(1, #mods, "ModCache row must hold exactly one parsed mod")
            assert.are.equals("Multiplier:OffhandExaltedWeaponStatEffect", mods[1].name)
            assert.are.equals("BASE", mods[1].type)
            assert.are.equals(95, mods[1].value)
        end)
    end)

    describe("CalcSetup pre-scan and offhand-only exalted scale", function()
        local source
        setup(function()
            local f = io.open("Modules/CalcSetup.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
            source = f:read("*a")
            f:close()
        end)

        it("regression-guard comment block is present", function()
            assert.is_truthy(string.find(source, "offhand-exalted-weapon-stat-multiplier", 1, true),
                "CalcSetup.lua must keep the @leb-regression-guard comment so future edits trip review")
        end)

        it("declares `local offhandExaltedEffectPercent = 0` and scans for the multiplier", function()
            assert.is_truthy(string.find(source, "local%s+offhandExaltedEffectPercent%s*=%s*0"),
                "CalcSetup.lua must declare the pre-scan accumulator")
            assert.is_truthy(string.find(source, 'm%.name%s*==%s*"Multiplier:OffhandExaltedWeaponStatEffect"'),
                "CalcSetup.lua must scan item modLists for Multiplier:OffhandExaltedWeaponStatEffect")
        end)

        it("computes offhandExaltedScale = 1 + N/100", function()
            assert.is_truthy(string.find(source,
                "local%s+offhandExaltedScale%s*=%s*1%s*%+%s*offhandExaltedEffectPercent%s*/%s*100"),
                "CalcSetup.lua must convert the percent into a (1 + N/100) scale")
        end)

        it("applies the scale only to Weapon 2, weapon base, EXALTED rarity", function()
            local i = string.find(source, "scale%s*=%s*scale%s*%*%s*offhandExaltedScale")
            assert.is_not_nil(i, "scale assignment using offhandExaltedScale must exist")
            local window = string.sub(source, math.max(1, i - 400), i + 100)
            assert.is_truthy(string.find(window, '"Weapon 2"', 1, true),
                "scale block must gate on the offhand slot (Weapon 2)")
            assert.is_truthy(string.find(window, "item%.base%.weapon"),
                "scale block must require a weapon base (excludes shields/catalysts)")
            assert.is_truthy(string.find(window, '"EXALTED"', 1, true),
                "scale block must require EXALTED rarity")
        end)

        it("is inert on shields (no base.weapon), non-exalted offhands, and main-hand", function()
            -- The gate is a CONJUNCTION: dropping any one condition would leak the
            -- scale onto a shield/catalyst (no base.weapon), a non-exalted offhand,
            -- or a main-hand weapon (Weapon 1). Assert all three conditions are
            -- present AND joined with `and` so none can be silently removed.
            local i = string.find(source, "scale%s*=%s*scale%s*%*%s*offhandExaltedScale")
            assert.is_not_nil(i, "scale assignment using offhandExaltedScale must exist")
            local window = string.sub(source, math.max(1, i - 400), i + 100)
            -- shield/catalyst-inert: requires a weapon base
            assert.is_truthy(string.find(window, "and%s+item%.base%s+and%s+item%.base%.weapon"),
                "shield-inert: the weapon-base condition must be conjoined into the gate")
            -- non-exalted-inert: requires EXALTED rarity, conjoined
            assert.is_truthy(string.find(window, 'and%s+item%.rarity%s*==%s*"EXALTED"'),
                "non-exalted-inert: the EXALTED condition must be conjoined into the gate")
            -- main-hand-inert: the offhand slot is the only scaled slot
            assert.is_truthy(string.find(window, 'slotName%s*==%s*"Weapon 2"'),
                "main-hand-inert: only the Weapon 2 (offhand) slot may be scaled")
        end)
    end)

    describe("Whetstone Gavel unique carries the offhand-exalted affix line", function()
        it("uniques_1_4.json has the (90-100)% effectiveness mod", function()
            local f = io.open("Data/Uniques/uniques_1_4.json", "r")
            assert.is_not_nil(f, "must be able to open Data/Uniques/uniques_1_4.json")
            local source = f:read("*a")
            f:close()
            assert.is_truthy(string.find(source,
                "%(90%-100%)%% increased effectiveness of Stats on an offhand Exalted Weapon", 1, false),
                "Whetstone Gavel must keep the offhand-exalted effectiveness mod line")
        end)
    end)
end)
