-- @leb-regression-guard: ward-stop-moving-config-amortize
-- Locks the parser + Config + CalcPerform fold-in contract for the
-- Transient Rest unique affix:
--   "(40-60)% of Current Mana gained as Ward when you stop moving
--    (2 second cooldown)"
--
-- Game-side authority (dump.cs, il2cpp re-extraction):
--   * L95850 `public float currentManaGainedAsWardOnStopMoving; // 0xDB0`
--   * L95851 `private const float currentManaGainedAsWardOnStopMovingCooldown = 2;`
--   * Distinct from the continuous-per-second variant
--     `currentManaGainedAsWardPerSecond` (L95820 offset 0xD38).
--   * Event-driven sources feed `ProtectionClass.GainWard(amount)` separately
--     from passive `wardRegen + wardRegenFromStats`; they are NOT part of the
--     0.5/s decay floor gate (see LE_datamining/extracted/ward_formulas.md §2).
--
-- LEB strategy: surface the affix as a steady-state continuous Ward per
-- Second contribution, amortizing over the 2-second hard cooldown, but ONLY
-- when the user opts in via Config tab "Stopped Moving?" (default off, to
-- preserve baseline parity with LETools UI which omits event-driven sources).
--
-- amortized wps = currentMana * pct / 100 / 2
--
-- Before this guard the line fell through to LEB_NotSupported (see ModCache
-- L15263 stale entry: 50% form → notSupported=true). The o3Zlpkxd lv98
-- Necromancer test build wears Transient Rest and contributed 0 wps from
-- this affix prior to the fix.
--
-- See REGRESSION_GUARDS.md "ward-stop-moving-config-amortize".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardStopMovingConfigAmortize", function()
    local parserText, configText, performText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        configText = readSource("Modules/ConfigOptions.lua")
        performText = readSource("Modules/CalcPerform.lua")
    end)

    describe("ModParser", function()
        it("recognises '% of Current Mana gained as Ward when you stop moving (2 second cooldown)'", function()
            -- Pattern stored verbatim as `^%+?([%d%.]+)%% of current mana gained as ward when you stop moving %(2 second cooldown%)$`;
            -- search with plain=true so the literal `%(` and `%)` in the file match.
            assert.is_truthy(string.find(parserText,
                "of current mana gained as ward when you stop moving %(2 second cooldown%)", 1, true),
                "ModParser must carry the '% of ... stop moving (2 second cooldown)' pattern")
        end)

        it("recognises bare '% Current Mana gained as Ward when you stop moving (2 second cooldown)'", function()
            -- Pattern stored as `^%+?([%d%.]+)%% current mana gained as ward when you stop moving %(2 second cooldown%)$`;
            -- to disambiguate from the "of"-prefixed variant, anchor the leading space before "current".
            assert.is_truthy(string.find(parserText,
                "%% current mana gained as ward when you stop moving %(2 second cooldown%)", 1, true),
                "ModParser must carry the bare '% ... stop moving (2 second cooldown)' pattern")
        end)

        it("emits CurrentManaGainedAsWardOnStopMoving mod kind", function()
            assert.is_truthy(string.find(parserText,
                '"CurrentManaGainedAsWardOnStopMoving"', 1, true),
                "ModParser must emit CurrentManaGainedAsWardOnStopMoving")
        end)

        it("carries the inline regression-guard marker (parser site)", function()
            assert.is_truthy(string.find(parserText,
                "@leb-regression-guard:ward-stop-moving-config-amortize (parser site)", 1, true),
                "inline guard ID (parser site) must remain in ModParser.lua")
        end)
    end)

    describe("ConfigOptions", function()
        it("defines the conditionStoppedMoving toggle bound to Condition:StoppedMoving", function()
            assert.is_truthy(string.find(configText,
                'var = "conditionStoppedMoving"', 1, true),
                "ConfigOptions must define conditionStoppedMoving")
            assert.is_truthy(string.find(configText,
                '"Condition:StoppedMoving"', 1, true),
                "conditionStoppedMoving must emit Condition:StoppedMoving FLAG")
        end)

        it("scopes the toggle to Combat", function()
            assert.is_truthy(string.find(configText,
                'Condition:StoppedMoving".-Combat', 1, false),
                "conditionStoppedMoving must be Combat-scoped so it does not leak outside the combat snapshot")
        end)

        it("carries the inline regression-guard marker (config site)", function()
            assert.is_truthy(string.find(configText,
                "@leb-regression-guard:ward-stop-moving-config-amortize (config site)", 1, true),
                "inline guard ID (config site) must remain in ConfigOptions.lua")
        end)
    end)

    describe("CalcPerform fold-in", function()
        it("Sums CurrentManaGainedAsWardOnStopMoving BASE", function()
            assert.is_truthy(string.find(performText,
                'CurrentManaGainedAsWardOnStopMoving', 1, true),
                "CalcPerform must read CurrentManaGainedAsWardOnStopMoving from modDB")
        end)

        it("gates on Condition:StoppedMoving flag", function()
            assert.is_truthy(string.find(performText,
                'Condition:StoppedMoving', 1, true),
                "CalcPerform must gate the contribution on Condition:StoppedMoving")
        end)

        it("amortizes by /2 to match the 2-second game-side cooldown", function()
            -- Match the computation expression `* currentManaGainedAsWardOnStopMoving / 100 / 2`
            assert.is_truthy(string.find(performText,
                "currentManaGainedAsWardOnStopMoving / 100 / 2", 1, true),
                "CalcPerform must divide by 2 (the dump.cs hardcoded 2s cooldown)")
        end)

        it("adds stopMovingContribution into totalContribution", function()
            assert.is_truthy(string.find(performText,
                "totalContribution = manaSpentContribution %+ currentManaContribution %+ missingHealthContribution %+ stopMovingContribution", 1, false),
                "CalcPerform must include stopMovingContribution in the fold-in total")
        end)

        it("excludes stopMovingContribution from the passive snapshot (floor-gate parity)", function()
            -- passiveWardPerSecond = baseWardPerSecond + currentManaContribution + missingHealthContribution
            -- (NO stopMovingContribution -- event-driven, like manaSpentContribution)
            local idx = string.find(performText,
                "passiveWardPerSecond = baseWardPerSecond %+ currentManaContribution %+ missingHealthContribution", 1, false)
            assert.is_truthy(idx,
                "passiveWardPerSecond must aggregate only continuous (passive) ward sources")
            -- Verify the next ~80 chars do NOT mention stopMovingContribution on the same line.
            local snippet = performText:sub(idx, idx + 120)
            assert.is_nil(string.find(snippet, "stopMovingContribution", 1, true),
                "passiveWardPerSecond must NOT include stopMovingContribution (event-driven, outside floor gate)")
        end)

        it("carries the inline regression-guard marker (fold-in site)", function()
            assert.is_truthy(string.find(performText,
                "@leb-regression-guard:ward-stop-moving-config-amortize (fold-in site)", 1, true),
                "inline guard ID (fold-in site) must remain in CalcPerform.lua")
        end)
    end)
end)
