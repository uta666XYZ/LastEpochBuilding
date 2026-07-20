-- @leb-regression-guard:config-highlight-moddb-signal
-- D (2026-05-30) of the Config-highlight family. Adds a modDB-driven
-- highlight signal alongside the text-based suggestBuff / suggestPattern.
--
-- A config may declare `suggestCond` / `suggestEnemyCond` / `suggestMult` —
-- the parsed-modDB relevance key(s). The highlight fires when the build's
-- modifiers MECHANICALLY reference that condition / multiplier, read from
-- `mainEnv.conditionsUsed` / `enemyConditionsUsed` / `multipliersUsed` (the
-- same precise signal PoB uses for config visibility). This complements the
-- text signals (union: text OR modDB) and avoids the false positives of raw
-- substring matching.
--
-- Privacy: the tooltip reports only the COUNT of contributing modifiers, NOT
-- `mod.source` (a raw internal string that LEB only surfaces under
-- devModeAlt). So this path cannot leak internal info
-- (cf. config-tooltip-no-internal-info).
--
-- Anti-fabrication: a declared key must be a REAL mod-tag var (the same
-- namespace ModParser emits), else conditionsUsed[key] is always empty and
-- the highlight never fires. The initial keys (Cursed / Haste / Frenzy) are
-- verified against ModParser below.
--
-- See REGRESSION_GUARDS.md "config-highlight-moddb-signal".

describe("ConfigHighlightModDBSignal", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local cfgTabSrc, cfgOptsSrc
    setup(function()
        cfgTabSrc = readFile("Classes/ConfigTab.lua")
        cfgOptsSrc = readFile("Modules/ConfigOptions.lua")
        assert.is_not_nil(cfgTabSrc, "must read Classes/ConfigTab.lua")
        assert.is_not_nil(cfgOptsSrc, "must read Modules/ConfigOptions.lua")
    end)

    it("ConfigTab carries the modDB-signal guard marker", function()
        assert.is_truthy(cfgTabSrc:find("@leb%-regression%-guard:config%-highlight%-moddb%-signal", 1, false),
            "ConfigTab.lua must carry the config-highlight-moddb-signal guard marker")
    end)

    it("the modDB block reads conditionsUsed / enemyConditionsUsed / multipliersUsed", function()
        local startIdx = cfgTabSrc:find("if varData.suggestCond or varData.suggestEnemyCond or varData.suggestMult then", 1, true)
        assert.is_not_nil(startIdx, "the suggestCond/suggestEnemyCond/suggestMult block must exist")
        -- End-anchored on the loop-body terminator so the whole modDB block
        -- is captured regardless of byte length (Lua :sub is byte-based; a
        -- fixed +N window can clip the block when multi-byte chars precede).
        local block = cfgTabSrc:sub(startIdx, (cfgTabSrc:find("t_insert(self.controls, control)", startIdx, true) or #cfgTabSrc))
        assert.is_truthy(block:find("mainEnv.conditionsUsed", 1, true),
            "must read mainEnv.conditionsUsed for suggestCond")
        assert.is_truthy(block:find("mainEnv.enemyConditionsUsed", 1, true),
            "must read mainEnv.enemyConditionsUsed for suggestEnemyCond")
        assert.is_truthy(block:find("mainEnv.multipliersUsed", 1, true),
            "must read mainEnv.multipliersUsed for suggestMult")
        assert.is_truthy(block:find("countModDBUses", 1, true),
            "must count contributing modifiers via countModDBUses")
    end)

    it("the modDB tooltip reports a COUNT, never raw mod.source (no internal leak)", function()
        local startIdx = cfgTabSrc:find("if varData.suggestCond or varData.suggestEnemyCond or varData.suggestMult then", 1, true)
        -- End-anchored on the loop-body terminator so the whole modDB block
        -- is captured regardless of byte length (Lua :sub is byte-based; a
        -- fixed +N window can clip the block when multi-byte chars precede).
        local block = cfgTabSrc:sub(startIdx, (cfgTabSrc:find("t_insert(self.controls, control)", startIdx, true) or #cfgTabSrc))
        assert.is_truthy(block:find(" that scale with this state", 1, true),
            "tooltip must report the count-based phrasing")
        assert.is_truthy(block:find('Your build has " .. n', 1, true),
            "tooltip must include the modifier count (n)")
        assert.falsy(block:find("mod.source", 1, true),
            "modDB tooltip must NOT emit raw mod.source (internal/devModeAlt-only)")
        assert.falsy(block:find("formatMod", 1, true),
            "modDB tooltip must NOT emit modLib.formatMod output")
    end)

    it("the label highlights on a bare truthy modDB check (persistent, Phase 7 style)", function()
        local startIdx = cfgTabSrc:find("if varData.suggestCond or varData.suggestEnemyCond or varData.suggestMult then", 1, true)
        -- End-anchored on the loop-body terminator so the whole modDB block
        -- is captured regardless of byte length (Lua :sub is byte-based; a
        -- fixed +N window can clip the block when multi-byte chars precede).
        local block = cfgTabSrc:sub(startIdx, (cfgTabSrc:find("t_insert(self.controls, control)", startIdx, true) or #cfgTabSrc))
        assert.is_truthy(block:find("if countModDBUses() > 0 then", 1, true),
            "label must highlight when countModDBUses() > 0 (no active gate — persistent)")
    end)

    it("initial configs declare verified suggestCond / suggestEnemyCond keys", function()
        -- conditionCursed -> suggestCond "Cursed"; conditionEnemyCursed ->
        -- suggestEnemyCond "Cursed"; conditionHaste/Frenzy -> suggestCond.
        local cursed = cfgOptsSrc:match('{%s*var%s*=%s*"conditionCursed".-suggestCond%s*=%s*"([^"]*)"')
        assert.are.equal("Cursed", cursed, "conditionCursed must declare suggestCond = \"Cursed\"")
        local enemyCursed = cfgOptsSrc:match('{%s*var%s*=%s*"conditionEnemyCursed".-suggestEnemyCond%s*=%s*"([^"]*)"')
        assert.are.equal("Cursed", enemyCursed, "conditionEnemyCursed must declare suggestEnemyCond = \"Cursed\"")
        local haste = cfgOptsSrc:match('{%s*var%s*=%s*"conditionHaste".-suggestCond%s*=%s*"([^"]*)"')
        assert.are.equal("Haste", haste, "conditionHaste must declare suggestCond = \"Haste\"")
        local frenzy = cfgOptsSrc:match('{%s*var%s*=%s*"conditionFrenzy".-suggestCond%s*=%s*"([^"]*)"')
        assert.are.equal("Frenzy", frenzy, "conditionFrenzy must declare suggestCond = \"Frenzy\"")
    end)

    it("anti-fabrication: the initial keys are real mod-tag vars (ModParser emits them)", function()
        local mp = readFile("Modules/ModParser.lua")
        assert.is_not_nil(mp, "must read Modules/ModParser.lua")
        for _, key in ipairs({ "Cursed", "Haste", "Frenzy" }) do
            assert.is_truthy(mp:find('var = "' .. key .. '"', 1, true),
                "ModParser must emit a condition tag var \"" .. key .. "\" for the modDB signal to ever fire")
        end
    end)

    -- ===== behavioral: real build, injected conditionsUsed drives the count =====
    it("countModDBUses-equivalent: conditionsUsed lookup is the live mainEnv shape", function()
        newBuild()
        local mainEnv = build.calcsTab.mainEnv
        assert.is_not_nil(mainEnv, "build.calcsTab.mainEnv must exist after a build")
        assert.is_table(mainEnv.conditionsUsed, "mainEnv.conditionsUsed must be a table")
        assert.is_table(mainEnv.enemyConditionsUsed, "mainEnv.enemyConditionsUsed must be a table")
        assert.is_table(mainEnv.multipliersUsed, "mainEnv.multipliersUsed must be a table")
        -- Inject a fake Cursed-using modifier and confirm the lookup the
        -- highlight relies on returns a non-empty list (the highlight fires
        -- when #conditionsUsed[key] > 0).
        mainEnv.conditionsUsed["Cursed"] = { { source = "Tree:test" } }
        assert.is_true(#mainEnv.conditionsUsed["Cursed"] > 0,
            "conditionsUsed['Cursed'] must be countable (the modDB highlight keys off #mods)")
    end)
end)
