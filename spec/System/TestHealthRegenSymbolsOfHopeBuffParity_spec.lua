-- @leb-regression-guard: health-regen-symbols-of-hope-buff-parity
-- Locks the classification that LEB's Health Regen > LETools' Health Regen
-- for builds with Symbols of Hope active is a *known semantic gap*, not a
-- LEB bug. LEB auto-tops Multiplier:ActiveSymbol to gameplay-max at
-- CalcSetup.lua L1968-1975 ('Auto:Symbols of Hope'); LETools' static
-- 'Health Regen' is the no-buff baseline.
--
-- Establishing build (G3 aggregate, +71%):
--   BGzxnRdY lv92 Void Knight  LET 37.63  LEB 64.5  Δ +26.87
--     Sum BASE = 26.88; Sum INC = 40% (Sentinel-49) + 5 × 20% (Symbols of
--     Hope per-stack) = 140%.  26.88 × 2.4 = 64.51 ✓ vs LET's 26.88 × 1.4
--     = 37.63 ✓ (no symbols).
--
-- The LET no-buff value is reproducible in LEB via ConfigOptions slider
-- 'multiplierActiveSymbols' = 0.  See REGRESSION_GUARDS.md
-- §health-regen-symbols-of-hope-buff-parity.

local function readFile(relPath)
    local f = io.open(relPath, "r") or io.open("../" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("HealthRegenSymbolsOfHopeBuffParity", function()
    local diffPy
    local calcSetupText

    setup(function()
        diffPy = readFile("spec/tools/diff_letools.py")
        calcSetupText = readFile("src/Modules/CalcSetup.lua")
    end)

    local function findGapsEntry()
        local dictStart = string.find(diffPy, "KNOWN_SEMANTIC_GAPS%s*=%s*{")
        assert.is_not_nil(dictStart, "KNOWN_SEMANTIC_GAPS dict declaration must exist")
        local entryAt = string.find(diffPy, "%('General','Health Regen'%)", dictStart, false)
        return dictStart, entryAt
    end

    it("diff_letools.py has a KNOWN_SEMANTIC_GAPS entry for ('General','Health Regen')", function()
        local _, entryAt = findGapsEntry()
        assert.is_not_nil(entryAt,
            "KNOWN_SEMANTIC_GAPS must include ('General','Health Regen')")
    end)

    it("the entry carries the named guard marker", function()
        local _, entryAt = findGapsEntry()
        local before = diffPy:sub(math.max(1, entryAt - 400), entryAt)
        assert.is_truthy(
            string.find(before,
                "@leb%-regression%-guard:%s*health%-regen%-symbols%-of%-hope%-buff%-parity"),
            "Inline @leb-regression-guard:health-regen-symbols-of-hope-buff-parity "
            .. "comment must precede the ('General','Health Regen') KNOWN_SEMANTIC_GAPS entry"
        )
    end)

    it("gap text references 'Auto:Symbols of Hope' and the multiplierActiveSymbols knob", function()
        local _, entryAt = findGapsEntry()
        local block = diffPy:sub(entryAt, entryAt + 1200)
        assert.is_truthy(
            string.find(block, "Auto:Symbols of Hope", 1, true),
            "Gap text must name the CalcSetup auto-application source 'Auto:Symbols of Hope'"
        )
        assert.is_truthy(
            string.find(block, "multiplierActiveSymbols", 1, true),
            "Gap text must reference the multiplierActiveSymbols Config knob "
            .. "so maintainers know the per-build override path"
        )
    end)

    it("CalcSetup retains the Symbols of Hope auto-top-up block this gap rationalizes", function()
        assert.is_truthy(
            string.find(calcSetupText, "Auto:Symbols of Hope", 1, true),
            "CalcSetup must still emit the 'Auto:Symbols of Hope' mod source — "
            .. "removing it would silently drop every Paladin/Void Knight's "
            .. "Health Regen by 50-100% INC. This guard exists to *justify* that block."
        )
        assert.is_truthy(
            string.find(calcSetupText, 'Multiplier:ActiveSymbol", "BASE"', 1, true),
            "Auto-top-up must register a Multiplier:ActiveSymbol BASE mod"
        )
    end)
end)
