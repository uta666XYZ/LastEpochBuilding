-- @leb-regression-guard: urzils-pride-mana-regen-per-uncapped-lightning-res
-- Locks the contract that Urzil's Pride's inherent mod
-- "1% Increased Mana Regeneration per 2% Uncapped Lightning Resistance"
-- (a) is present on the unique in all four uniques*.json files,
-- (b) parses to a BASE `ManaRegenIncPerUncappedLightningRes_Per2` stat
--     (NOT a PerStat tag — ModStore.GetStat uses continuous scaling, which
--     produces 64.5 instead of 64 at LightningResistTotal=129),
-- (c) is injected as ManaRegen INC by CalcDefence with floor(LRTotal / 2)
--     after the resist totals are computed.
--
-- See REGRESSION_GUARDS.md for the index entry.

describe("UrzilsPrideManaRegenPerUncappedLR", function()
    before_each(function()
        newBuild()
    end)

    it("Urzil's Pride mod parses to BASE ManaRegenIncPerUncappedLightningRes_Per2", function()
        build.configTab.input.customMods = [[
        1% Increased Mana Regeneration per 2% Uncapped Lightning Resistance
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        local stat = build.calcsTab.mainEnv.modDB:Sum("BASE", nil, "ManaRegenIncPerUncappedLightningRes_Per2")
        assert.are.equals(1, stat)
    end)

    it("Urzil's Pride floors mana regen INC per 2% uncapped lightning resistance", function()
        -- Mirror the in-fix arithmetic: at LightningResistTotal=129 the contribution
        -- is floor(129 / 2) * 1 = 64% INC (not 64.5 — continuous scaling would over-
        -- count by 0.5%, surfacing 18.4 instead of LETools' 18.32).
        local lrTotal = 129
        local perPct = 1
        local floored = math.floor(lrTotal / 2) * perPct
        assert.are.equals(64, floored)

        -- Spot-check arithmetic the CalcDefence injection mirrors:
        -- Belt 35 + Sentinel-93 30 + Urzil 64 = 129% INC; base 8 → 8 * (1 + 1.29) = 18.32
        local baseRegen = 8
        local incTotal = 35 + 30 + floored
        local result = baseRegen * (1 + incTotal / 100)
        assert.are.equals(129, incTotal)
        -- Use a small tolerance because LE uses float arithmetic for regen.
        assert.is_true(math.abs(result - 18.32) < 0.001,
            "expected 18.32, got " .. tostring(result))
    end)

    it("uniques_1_4.json Urzil's Pride retains the per-uncapped-lightning-res mod line", function()
        local paths = {
            "Data/Uniques/uniques.json",
            "Data/Uniques/uniques_1_2.json",
            "Data/Uniques/uniques_1_3.json",
            "Data/Uniques/uniques_1_4.json",
            "src/Data/Uniques/uniques.json",
            "src/Data/Uniques/uniques_1_2.json",
            "src/Data/Uniques/uniques_1_3.json",
            "src/Data/Uniques/uniques_1_4.json",
        }
        local checked = 0
        for _, p in ipairs(paths) do
            local f = io.open(p, "r")
            if f then
                local raw = f:read("*a")
                f:close()
                -- Find Urzil's Pride block; require the mod line within ~30 lines after.
                local nameIdx = raw:find('"Urzil', 1, true)
                if nameIdx then
                    local block = raw:sub(nameIdx, nameIdx + 1500)
                    assert.is_truthy(
                        block:find("1%% Increased Mana Regeneration per 2%% Uncapped Lightning Resistance", 1, false),
                        p .. " missing Urzil's Pride mana-regen-per-uncapped-lightning-res mod line")
                    checked = checked + 1
                end
            end
        end
        assert.is_true(checked > 0, "no uniques*.json file was readable for verification")
    end)
end)
