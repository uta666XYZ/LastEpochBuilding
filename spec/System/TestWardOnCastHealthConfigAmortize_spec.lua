-- @leb-regression-guard: ward-on-cast-health-config-amortize
-- Locks the parser + Config + CalcPerform fold-in contract for the
-- Current-Health -> Ward on directly-cast-spell affixes (property-98 family):
--   * Twisted Heart of Uhkeiros (uniques_1_4 #216): a Necrotic AND an Elemental
--     variant, "(5-8)% of Current Health converted to Ward when you directly
--     cast a {Necrotic|Elemental} Spell".
--   * crafted/sealed affix 766 (ModItem_1_4.json): Necrotic variant, 1-7%.
--
-- Game-side behaviour (property #98, tags 167=Necrotic / 168=Elemental):
-- on each direct cast of a spell of the matching school the game converts a
-- percentage of CURRENT Health into Ward via the event-driven
-- `ProtectionClass.GainWard(amount)` path (the same path that carries
-- ManaSpentGainedAsWard / on-block / on-stop-moving ward). It is NOT part of
-- the passive `wardRegen + wardRegenFromStats` floor gate.
--
-- LEB strategy: surface each school as a steady-state continuous Ward per
-- Second contribution by amortizing the per-cast amount over the cast rate
-- (casts/second), but ONLY when the user opts in via the matching Config tab
-- toggle (default off, to preserve corpus baseline parity — event-driven ward
-- sources are not in the default snapshot).
--
--   amortized wps = Current Life * pct / 100 * castRate     (castRate = pOut.Speed)
--
-- Before this guard the lines fell through to LEB_NotSupported (the generic
-- `% of X converted to Y` handler / attrConvertedHandler intercepted them).
-- The new literal patterns out-score the generic one in scan() because, for
-- the same matched span, the longer pattern string wins (ModParser.scan,
-- `#pattern > #bestPattern` tiebreak).
--
-- See REGRESSION_GUARDS.md "ward-on-cast-health-config-amortize".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardOnCastHealthConfigAmortize", function()
    local parserText, configText, performText, modCacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        configText = readSource("Modules/ConfigOptions.lua")
        performText = readSource("Modules/CalcPerform.lua")
        modCacheText = readSource("Data/ModCache.lua")
    end)

    describe("ModParser", function()
        it("recognises '% of Current Health converted to Ward when you directly cast a Necrotic Spell'", function()
            assert.is_truthy(string.find(parserText,
                "of current health converted to ward when you directly cast a necrotic spell", 1, true),
                "ModParser must carry the '% of ... Necrotic Spell' pattern")
        end)

        it("recognises bare '% Current Health converted to Ward when you directly cast a Necrotic Spell'", function()
            assert.is_truthy(string.find(parserText,
                "%% current health converted to ward when you directly cast a necrotic spell", 1, true),
                "ModParser must carry the bare '% ... Necrotic Spell' pattern")
        end)

        it("recognises '% of Current Health converted to Ward when you directly cast an Elemental Spell'", function()
            assert.is_truthy(string.find(parserText,
                "of current health converted to ward when you directly cast an elemental spell", 1, true),
                "ModParser must carry the '% of ... Elemental Spell' pattern")
        end)

        it("recognises bare '% Current Health converted to Ward when you directly cast an Elemental Spell'", function()
            assert.is_truthy(string.find(parserText,
                "%% current health converted to ward when you directly cast an elemental spell", 1, true),
                "ModParser must carry the bare '% ... Elemental Spell' pattern")
        end)

        it("emits per-school CurrentHealthGainedAsWardOnCast mod kinds", function()
            assert.is_truthy(string.find(parserText,
                '"CurrentHealthGainedAsWardOnCastNecrotic"', 1, true),
                "ModParser must emit CurrentHealthGainedAsWardOnCastNecrotic")
            assert.is_truthy(string.find(parserText,
                '"CurrentHealthGainedAsWardOnCastElemental"', 1, true),
                "ModParser must emit CurrentHealthGainedAsWardOnCastElemental")
        end)

        it("carries the inline regression-guard marker (parser site)", function()
            assert.is_truthy(string.find(parserText,
                "@leb-regression-guard:ward-on-cast-health-config-amortize (parser site)", 1, true),
                "inline guard ID (parser site) must remain in ModParser.lua")
        end)
    end)

    describe("ConfigOptions", function()
        it("defines the per-school directly-cast toggles bound to their Conditions", function()
            assert.is_truthy(string.find(configText,
                'var = "conditionDirectlyCastNecroticSpellRecently"', 1, true),
                "ConfigOptions must define conditionDirectlyCastNecroticSpellRecently")
            assert.is_truthy(string.find(configText,
                '"Condition:DirectlyCastNecroticSpellRecently"', 1, true),
                "necrotic toggle must emit Condition:DirectlyCastNecroticSpellRecently FLAG")
            assert.is_truthy(string.find(configText,
                'var = "conditionDirectlyCastElementalSpellRecently"', 1, true),
                "ConfigOptions must define conditionDirectlyCastElementalSpellRecently")
            assert.is_truthy(string.find(configText,
                '"Condition:DirectlyCastElementalSpellRecently"', 1, true),
                "elemental toggle must emit Condition:DirectlyCastElementalSpellRecently FLAG")
        end)

        it("scopes both toggles to Combat", function()
            assert.is_truthy(string.find(configText,
                'Condition:DirectlyCastNecroticSpellRecently".-Combat', 1, false),
                "necrotic toggle must be Combat-scoped")
            assert.is_truthy(string.find(configText,
                'Condition:DirectlyCastElementalSpellRecently".-Combat', 1, false),
                "elemental toggle must be Combat-scoped")
        end)

        it("carries the inline regression-guard marker (config site)", function()
            assert.is_truthy(string.find(configText,
                "@leb-regression-guard:ward-on-cast-health-config-amortize (config site)", 1, true),
                "inline guard ID (config site) must remain in ConfigOptions.lua")
        end)
    end)

    describe("CalcPerform fold-in", function()
        it("Sums both CurrentHealthGainedAsWardOnCast BASE mods", function()
            assert.is_truthy(string.find(performText,
                'CurrentHealthGainedAsWardOnCastNecrotic', 1, true),
                "CalcPerform must read CurrentHealthGainedAsWardOnCastNecrotic from modDB")
            assert.is_truthy(string.find(performText,
                'CurrentHealthGainedAsWardOnCastElemental', 1, true),
                "CalcPerform must read CurrentHealthGainedAsWardOnCastElemental from modDB")
        end)

        it("gates each school on its DirectlyCast<School>SpellRecently Condition", function()
            assert.is_truthy(string.find(performText,
                'Condition:DirectlyCastNecroticSpellRecently', 1, true),
                "CalcPerform must gate the necrotic contribution on its Condition")
            assert.is_truthy(string.find(performText,
                'Condition:DirectlyCastElementalSpellRecently', 1, true),
                "CalcPerform must gate the elemental contribution on its Condition")
        end)

        it("amortizes per-cast Life% by the cast rate (pOut.Speed)", function()
            -- castRate = pOut.Speed
            assert.is_truthy(string.find(performText,
                "castRate = pOut.Speed", 1, true),
                "CalcPerform must source the cast rate from pOut.Speed")
            -- Life * pct / 100 * castRate (per-cast value amortized by casts/sec)
            assert.is_truthy(string.find(performText,
                "healthWardOnCastNecrotic / 100 %* castRate", 1, false),
                "necrotic contribution must be Life * pct / 100 * castRate")
            assert.is_truthy(string.find(performText,
                "healthWardOnCastElemental / 100 %* castRate", 1, false),
                "elemental contribution must be Life * pct / 100 * castRate")
        end)

        it("adds castWardContribution into totalContribution", function()
            assert.is_truthy(string.find(performText,
                "totalContribution = manaSpentContribution %+ currentManaContribution %+ missingHealthContribution %+ stopMovingContribution %+ castWardContribution", 1, false),
                "CalcPerform must include castWardContribution in the fold-in total")
        end)

        it("feeds castWardContribution into the event-driven wps (Ward inversion)", function()
            assert.is_truthy(string.find(performText,
                "wps = passiveWardPerSecond %+ manaSpentContribution %+ castWardContribution", 1, false),
                "castWardContribution must feed the wps used for the Ward / WardDecay inversion")
        end)

        it("excludes castWardContribution from the passive snapshot (floor-gate parity)", function()
            -- passiveWardPerSecond = baseWardPerSecond + currentManaContribution + missingHealthContribution
            -- (NO castWardContribution -- event-driven, like manaSpentContribution)
            local idx = string.find(performText,
                "passiveWardPerSecond = baseWardPerSecond %+ currentManaContribution %+ missingHealthContribution", 1, false)
            assert.is_truthy(idx,
                "passiveWardPerSecond must aggregate only continuous (passive) ward sources")
            local snippet = performText:sub(idx, idx + 140)
            assert.is_nil(string.find(snippet, "castWardContribution", 1, true),
                "passiveWardPerSecond must NOT include castWardContribution (event-driven, outside floor gate)")
        end)

        it("carries the inline regression-guard marker (fold-in site)", function()
            assert.is_truthy(string.find(performText,
                "@leb-regression-guard:ward-on-cast-health-config-amortize (fold-in site)", 1, true),
                "inline guard ID (fold-in site) must remain in CalcPerform.lua")
        end)
    end)

    describe("ModCache live-parse migration", function()
        it("no longer carries the converted-to-ward-on-cast lines as LEB_NotSupported", function()
            assert.is_nil(string.find(modCacheText,
                "converted to Ward when you directly cast", 1, true),
                "the on-cast health->ward lines must be live-parsed, not cached as LEB_NotSupported")
        end)
    end)
end)
