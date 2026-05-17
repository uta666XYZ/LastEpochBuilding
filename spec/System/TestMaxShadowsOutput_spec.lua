-- @leb-regression-guard: max-shadows-output-wiring
-- Locks that CalcDefence emits `output.MaxShadows` summed from BASE
-- MaxShadows mods, and CalcSections has the corresponding display row.
-- Before F1 the parser produced the modName but no consumer used it.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("MaxShadowsOutputWiring", function()
    local defenceText, sectionsText

    setup(function()
        defenceText  = readSource("Modules/CalcDefence.lua")
        sectionsText = readSource("Modules/CalcSections.lua")
    end)

    it("CalcDefence: output.MaxShadows is summed from BASE MaxShadows mods", function()
        local needle = 'output%.MaxShadows%s*=%s*modDB:Sum%("BASE",%s*nil,%s*"MaxShadows"%)'
        assert.is_truthy(string.find(defenceText, needle),
            "CalcDefence.lua must wire output.MaxShadows = modDB:Sum('BASE', nil, 'MaxShadows')")
    end)

    it("CalcDefence: MaxShadows has no character base (must NOT use `N +` constant)", function()
        -- Bladedancer mastery passives are the sole source; non-Bladedancer
        -- classes show 0. A regression introducing `2 + modDB:Sum(...)` style
        -- would silently inflate every build by the constant.
        local bad = 'output%.MaxShadows%s*=%s*%d+%s*%+'
        assert.is_nil(string.find(defenceText, bad),
            "output.MaxShadows must have base 0 (no leading-constant offset)")
    end)

    it("CalcSections: a 'Maximum Shadows' row exists referencing output.MaxShadows", function()
        local needle = 'label%s*=%s*"Maximum Shadows".-haveOutput%s*=%s*"MaxShadows".-output:MaxShadows'
        assert.is_truthy(string.find(sectionsText, needle),
            "CalcSections.lua must include a 'Maximum Shadows' row bound to output.MaxShadows")
    end)
end)
