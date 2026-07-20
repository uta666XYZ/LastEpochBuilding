-- @leb-regression-guard:calcdefence-enemylevel-nil-on-cross-class-import
-- Locks the env.config.enemyLevel fallback chain added in CalcSetup.lua plus
-- the per-function `enemyLevel = enemyLevel or 100` defenses in
-- CalcDefence.armourReductionF / blockMitigationF / dodgeChanceF.
--
-- Crash this protects against (2026-05-28, user-reported):
--   In 'OnFrame': Modules/CalcDefence.lua:39: attempt to perform arithmetic
--   on local 'enemyLevel' (a nil value)
--   stack traceback:
--     Modules/CalcDefence.lua:39:  armourReductionF
--     Modules/CalcDefence.lua:631: defence
--     Modules/CalcPerform.lua:1422: perform
--     Modules/Calcs.lua:375:   buildActiveSkill
--     Modules/CalcSetup.lua:2222: initEnv (MAIN) -> recursive CACHE pass
--     Modules/Calcs.lua:385:   buildOutput
--     Classes/CalcsTab.lua:469: BuildOutput
--     Modules/Build.lua:1455:  CallMode("OnFrame")
--
-- Reproduction (in-app):
--   1. Load ShutFackUp lv85 Spellblade.xml (Mage / Spellblade)
--   2. Touch the Config tab; Save
--   3. Import tab -> DownloadFullImport YsGhostSurfing lv88 Warlock
--      (Acolyte / Warlock -- CROSS-CLASS import)
--   4. Repeat the import once more
--   5. Save As -> "YsGhostSurfing lv88 Warlock.xml"
--   6. Next OnFrame -> CRASH at CalcDefence.lua:39
--
-- Root cause: env.config.enemyLevel was read by CalcDefence without a
-- fallback. The companion field env.enemyLevel set right after the config
-- merge in CalcSetup.lua DID have a fallback (`build.configTab.enemyLevel
-- or m_min(data.misc.MaxEnemyLevel, 100)`). The merge of configTab.input +
-- configTab.placeholder can transiently miss the `enemyLevel` key across the
-- cross-class import + Save As sequence; CACHE-mode initEnv (called inside
-- MAIN initEnv at line 2222 for triggered-skill caching) then rebuilds
-- env.config from that state, leaving env.config.enemyLevel == nil, and
-- the CACHE perform's defence pass crashes before MAIN's defence runs.
--
-- Fix: in CalcSetup.lua, after the input/placeholder merge into env.config,
-- mirror the env.enemyLevel fallback chain so env.config.enemyLevel always
-- gets the authoritative ConfigTab:UpdateLevel value (character level by
-- default). The three F functions in CalcDefence.lua additionally default
-- to 100 if called with nil, so a corrupted upstream cannot crash the calc.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

-- Extract the body of a top-level Lua function by name (until the next top-level
-- `function ` declaration, or end of file). Naive but enough to scope assertions
-- to a single function — the simple `.-end` pattern stops at the FIRST nested
-- `end` (e.g. `if armour == 0 then return 0 end`), which would skip past the
-- enemyLevel default line.
local function extractFunctionBody(source, funcName)
    local startIdx = source:find("function " .. funcName, 1, true)
    if not startIdx then return nil end
    local rest = source:sub(startIdx)
    local nextFuncIdx = rest:find("\nfunction ", 2, true)
    return nextFuncIdx and rest:sub(1, nextFuncIdx) or rest
end

describe("CalcDefenceEnemyLevelDefault", function()
    local calcs
    local calcSetupText
    local calcDefenceText

    setup(function()
        calcs = require("Modules/Calcs")
        calcSetupText = readSource("Modules/CalcSetup.lua")
        calcDefenceText = readSource("Modules/CalcDefence.lua")
    end)

    describe("source invariants", function()
        it("CalcSetup carries the @leb-regression-guard marker on the env.config.enemyLevel fallback", function()
            assert.is_truthy(string.find(calcSetupText,
                "@leb-regression-guard:calcdefence-enemylevel-nil-on-cross-class-import", 1, true),
                "CalcSetup.lua must declare the regression guard above the env.config.enemyLevel fallback")
        end)

        it("CalcSetup defaults env.config.enemyLevel via build.configTab.enemyLevel when nil/0", function()
            -- Lock the exact fallback chain: input/placeholder -> configTab.enemyLevel -> MaxEnemyLevel cap.
            assert.is_truthy(string.find(calcSetupText,
                "if not env.config.enemyLevel or env.config.enemyLevel == 0 then", 1, true),
                "env.config.enemyLevel must be guarded against nil/0 before defence reads it")
            assert.is_truthy(string.find(calcSetupText,
                "env.config.enemyLevel = build.configTab.enemyLevel or m_min(data.misc.MaxEnemyLevel, 100)", 1, true),
                "fallback must mirror the env.enemyLevel chain (configTab.enemyLevel -> MaxEnemyLevel cap)")
        end)

        it("the env.enemyLevel fallback right below is still present (mirror source)", function()
            -- If this line ever loses its fallback, the symmetry argument behind the
            -- env.config.enemyLevel fix collapses — flag it loudly.
            assert.is_truthy(string.find(calcSetupText,
                "env.enemyLevel = build.configTab.enemyLevel or m_min(data.misc.MaxEnemyLevel, 100)", 1, true),
                "env.enemyLevel must retain its existing fallback; env.config.enemyLevel mirrors it")
        end)

        it("CalcDefence carries the @leb-regression-guard marker (one anchored above armourReductionF)", function()
            -- The marker block sits in the doc-comment immediately above the
            -- armourReductionF declaration explaining the defense-in-depth.
            -- Look for the marker on a line that precedes the function name
            -- within a short window (anchored to the call site, not just
            -- "anywhere in the file" — would otherwise also pass if the marker
            -- only lived on blockMitigationF/dodgeChanceF and the primary
            -- function lost it).
            local funcIdx = calcDefenceText:find("function calcs.armourReductionF", 1, true)
            assert.is_truthy(funcIdx, "armourReductionF must exist in CalcDefence.lua")
            local prelude = calcDefenceText:sub(math.max(1, funcIdx - 1200), funcIdx)
            assert.is_truthy(prelude:find("@leb-regression-guard:calcdefence-enemylevel-nil-on-cross-class-import", 1, true),
                "regression guard marker must sit in the doc-comment above armourReductionF")
        end)

        it("CalcDefence.armourReductionF defaults nil enemyLevel to 100", function()
            local body = extractFunctionBody(calcDefenceText, "calcs.armourReductionF")
            assert.is_truthy(body, "armourReductionF body must be findable")
            assert.is_truthy(body:find("enemyLevel = enemyLevel or 100", 1, true),
                "armourReductionF must default nil enemyLevel to 100")
        end)

        it("CalcDefence.blockMitigationF defaults nil enemyLevel to 100", function()
            local body = extractFunctionBody(calcDefenceText, "calcs.blockMitigationF")
            assert.is_truthy(body, "blockMitigationF body must be findable")
            assert.is_truthy(body:find("enemyLevel = enemyLevel or 100", 1, true),
                "blockMitigationF must default nil enemyLevel to 100")
        end)

        it("CalcDefence.dodgeChanceF defaults nil enemyLevel to 100", function()
            local body = extractFunctionBody(calcDefenceText, "calcs.dodgeChanceF")
            assert.is_truthy(body, "dodgeChanceF body must be findable")
            assert.is_truthy(body:find("enemyLevel = enemyLevel or 100", 1, true),
                "dodgeChanceF must default nil enemyLevel to 100")
        end)
    end)

    describe("behavioural", function()
        before_each(function()
            newBuild()
        end)

        it("armourReductionF returns a finite cap-respecting number when called with nil enemyLevel", function()
            -- Pre-fix: nil enemyLevel crashes at `enemyLevel + 5` (CalcDefence:39).
            -- Post-fix: defaults to 100, runs the formula, returns 0..ArmorCap (default 85).
            local r = calcs.armourReductionF(1000, nil)
            assert.is_number(r)
            assert.is_true(r >= 0)
            assert.is_true(r <= data.misc.ArmorCap)
        end)

        it("blockMitigationF returns a finite number when called with nil enemyLevel", function()
            local r = calcs.blockMitigationF(50, nil)
            assert.is_number(r)
            assert.is_true(r >= 0)
        end)

        it("dodgeChanceF returns a finite number when called with nil enemyLevel", function()
            local r = calcs.dodgeChanceF(500, nil)
            assert.is_number(r)
            assert.is_true(r >= 0)
        end)

        it("BuildOutput survives a configTab where both input.enemyLevel and placeholder.enemyLevel are missing", function()
            -- Direct surrogate for the cross-class-import + Save As state: the
            -- merge that drives env.config has no `enemyLevel` key in either
            -- source table at the moment CACHE-mode initEnv rebuilds env.config.
            build.configTab.input.enemyLevel = nil
            build.configTab.placeholder.enemyLevel = nil

            -- Pre-fix: BuildOutput crashes inside the triggered-skill CACHE pass.
            -- Post-fix: env.config.enemyLevel falls back to configTab.enemyLevel
            -- (UpdateLevel default = character level, clamped to [1, 100]) so
            -- defence runs without ever seeing nil.
            assert.has_no.errors(function()
                build.buildFlag = true
                runCallback("OnFrame")
            end)

            local enemyLevel = build.calcsTab.mainEnv.config.enemyLevel
            assert.is_number(enemyLevel)
            assert.is_true(enemyLevel >= 1 and enemyLevel <= 100,
                "fallback enemyLevel must land in the [1, 100] clamp")
        end)

        it("BuildOutput preserves an explicit user-supplied enemyLevel input ahead of the fallback", function()
            -- The fallback only fires when env.config.enemyLevel is nil/0; an
            -- explicit user value (e.g. 85 to model in-game character sheet
            -- vs lv100 monolith) MUST round-trip unchanged.
            build.configTab.input.enemyLevel = 85
            build.configTab:BuildModList()

            assert.has_no.errors(function()
                build.buildFlag = true
                runCallback("OnFrame")
            end)
            assert.are.equals(85, build.calcsTab.mainEnv.config.enemyLevel)
        end)
    end)
end)
