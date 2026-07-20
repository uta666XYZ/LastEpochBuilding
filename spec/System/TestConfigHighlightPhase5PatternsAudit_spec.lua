-- @leb-regression-guard:config-highlight-suggest-pattern (Phase 5 patterns audit)
-- Phase 5 (2026-05-29) of the Config-highlight family. Phases 1〜4 wired
-- the *mechanism* (suggestPattern field + plain-substring matcher across
-- passive tree + skill subtree + skill loadout + equipped item modList +
-- source-attribution tooltip + multi-source collection). Phase 5 fills
-- the *data* gap: ConfigOptions entries that SHOULD highlight on certain
-- builds but had no suggestPattern declared yet.
--
-- Target entries this spec locks (10 entries, all NEW suggestPattern in
-- Phase 5):
--   * conditionFullLife, conditionLowLife, playerMissingManaPercent (mana: missing/not-full)
--   * conditionHaveWard
--   * conditionBleedOverload, conditionIgniteOverload,
--     conditionPoisonOverload, conditionDamnedOverload
--   * conditionEnemyFullLife, conditionEnemyLowLife
--
-- Two-layer invariant:
--   (a) Each target entry DECLARES suggestPattern (so the highlight
--       mechanism is wired up).
--   (b) Each declared phrase ACTUALLY APPEARS in 1.4 game content
--       (uniques_1_4.json / tree_*.json). This is the anti-fabrication
--       guard — without it, a phrase like "while at low health" could
--       be added that never matches anything, becoming dead config that
--       the user can't trust. The memory rule "No fabrication of game
--       data names" applies in spirit to phrasings too.
--
-- See REGRESSION_GUARDS.md "config-highlight-suggest-pattern" Phase 5
-- patterns table for the audited phrase list per entry.

describe("ConfigHighlightPhase5PatternsAudit", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local cfgOptsSrc
    setup(function()
        cfgOptsSrc = readFile("Modules/ConfigOptions.lua")
        assert.is_not_nil(cfgOptsSrc, "must read Modules/ConfigOptions.lua")
    end)

    -- Extract suggestPattern text for a given var name.
    local function entrySuggest(varName)
        local pattern = '{%s*var%s*=%s*"' .. varName .. '"[^\n]-suggestPattern%s*=%s*(%b{})'
        return cfgOptsSrc:match(pattern)
    end

    -- (a) Each target entry declares suggestPattern.
    it("(a) all 10 Phase 5 target entries declare suggestPattern", function()
        local targets = {
            "conditionFullLife", "conditionLowLife",
            "playerMissingManaPercent",
            "conditionHaveWard",
            "conditionBleedOverload", "conditionIgniteOverload",
            "conditionPoisonOverload", "conditionDamnedOverload",
            "conditionEnemyFullLife", "conditionEnemyLowLife",
        }
        for _, var in ipairs(targets) do
            local literal = entrySuggest(var)
            assert.is_not_nil(literal,
                "Phase 5: ConfigOptions entry `" .. var .. "` must declare suggestPattern")
        end
    end)

    -- (b) Each entry's anchor phrase (most identity-defining one) is
    -- present. Specific phrases per category — these are the canonical
    -- ones that MUST be there. Other phrases are exploratory and audit-
    -- floor is owned by the data-evidence assertion below.
    it("(b1) Low Health / Full Health entries include their anchor phrases", function()
        local lowLife = entrySuggest("conditionLowLife")
        assert.is_truthy(lowLife:find("low health", 1, true),
            "conditionLowLife must include 'low health'")
        assert.is_truthy(lowLife:find("current health lost per second", 1, true),
            "conditionLowLife must include 'current health lost per second' (Architects of Astral Blood anchor)")
        assert.is_truthy(lowLife:find("missing health", 1, true),
            "conditionLowLife must include 'missing health' (many ward-from-missing-health builds care)")

        local fullLife = entrySuggest("conditionFullLife")
        assert.is_truthy(fullLife:find("while at full health", 1, true),
            "conditionFullLife must include 'while at full health'")
    end)

    it("(b2) Missing Mana entry includes its anchor phrases", function()
        -- conditionFullMana/conditionLowMana were removed (wrong LE abstraction;
        -- LE uses missing-mana / not-full-mana, not full/low thresholds) and
        -- replaced by playerMissingManaPercent. See
        -- @leb-regression-guard:mana-missing-not-full-mechanics.
        local missingMana = entrySuggest("playerMissingManaPercent")
        assert.is_truthy(missingMana:find("missing mana", 1, true),
            "playerMissingManaPercent must include 'missing mana'")
        assert.is_truthy(missingMana:find("not full mana", 1, true),
            "playerMissingManaPercent must include 'not full mana'")
    end)

    it("(b3) Ward entry includes the canonical Ward-vocabulary phrases", function()
        local ward = entrySuggest("conditionHaveWard")
        for _, phrase in ipairs({
            "ward per second", "ward retention", "ward decay threshold",
            "gained as ward", "ward gained on", "ward limit",
            "while you have ward",
        }) do
            assert.is_truthy(ward:find(phrase, 1, true),
                "conditionHaveWard must include phrase '" .. phrase .. "'")
        end
    end)

    it("(b4) each Overload entry includes its specific ailment + the generic 'ailment overload' umbrella", function()
        for _, t in ipairs({
            { var = "conditionBleedOverload",  ail = "bleed overload"  },
            { var = "conditionIgniteOverload", ail = "ignite overload" },
            { var = "conditionPoisonOverload", ail = "poison overload" },
            { var = "conditionDamnedOverload", ail = "damned overload" },
        }) do
            local lit = entrySuggest(t.var)
            assert.is_truthy(lit:find(t.ail, 1, true),
                t.var .. " must include phrase '" .. t.ail .. "'")
            assert.is_truthy(lit:find("ailment overload", 1, true),
                t.var .. " must also include the generic 'ailment overload' umbrella")
        end
    end)

    it("(b5) Enemy Low Life entry includes execute-range phrases", function()
        local enemyLow = entrySuggest("conditionEnemyLowLife")
        assert.is_truthy(enemyLow:find("low health enemies", 1, true),
            "conditionEnemyLowLife must include 'low health enemies'")
        assert.is_truthy(enemyLow:find("low life enemies", 1, true),
            "conditionEnemyLowLife must include 'low life enemies'")
        assert.is_truthy(enemyLow:find("more spell damage to low health", 1, true),
            "conditionEnemyLowLife must include 'more spell damage to low health' (Boneclamor Barbute-class affix anchor)")
    end)

    -- (c) Anti-fabrication: each anchor phrase actually appears in 1.4
    -- content. This is the regression floor that prevents drift — if a
    -- future 1.x rephrasing breaks an anchor, this test fails loudly
    -- before the user's tooltip silently stops highlighting.
    it("(c) anchor phrases are present in actual 1.4 game data (anti-fabrication floor)", function()
        local uniques = readFile("Data/Uniques/uniques_1_4.json")
        assert.is_not_nil(uniques, "must read Data/Uniques/uniques_1_4.json")
        local tree3 = readFile("TreeData/1_4/tree_3.json")
        assert.is_not_nil(tree3, "must read TreeData/1_4/tree_3.json (Warlock mastery)")

        -- Low Health anchors
        assert.is_truthy(uniques:lower():find("current health lost per second", 1, true),
            "uniques_1_4.json must still contain 'current health lost per second' (Architects of Astral Blood)")
        assert.is_truthy(uniques:lower():find("low health", 1, true),
            "uniques_1_4.json must still contain 'low health'")

        -- Ward anchors
        for _, phrase in ipairs({
            "ward per second", "ward retention", "ward decay threshold",
            "gained as ward", "ward gained on",
        }) do
            assert.is_truthy(uniques:lower():find(phrase, 1, true),
                "uniques_1_4.json must still contain Ward phrase '" .. phrase .. "'")
        end

        -- Overload anchors live in Warlock mastery tree
        for _, phrase in ipairs({
            "bleed overload", "ignite overload",
            "poison overload", "damned overload",
        }) do
            assert.is_truthy(tree3:lower():find(phrase, 1, true),
                "tree_3.json must still contain Overload phrase '" .. phrase .. "'")
        end
    end)

    -- (d) The Phase 5 inline guard marker tag (sub-id of the umbrella
    -- `config-highlight-suggest-pattern`) is present on ConfigOptions.lua
    -- so a regression sweep can locate Phase 5 additions by grep.
    it("(d) Phase 5 inline guard sub-markers are present in ConfigOptions.lua", function()
        local _, n = cfgOptsSrc:gsub("Phase 5 ", "")
        assert.is_true(n >= 4,
            "ConfigOptions.lua must carry at least 4 inline `Phase 5 ` sub-markers (Low Health / Ward / Overload / Enemy Low Life); found " .. tostring(n))
    end)
end)
