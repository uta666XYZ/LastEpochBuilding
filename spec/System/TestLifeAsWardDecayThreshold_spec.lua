-- @leb-regression-guard: life-as-ward-decay-threshold-conversion
-- See REGRESSION_GUARDS.md "life-as-ward-decay-threshold-conversion".
-- Validation provenance is retained in maintainer notes.

describe("LifeAsWardDecayThreshold", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    it("ModParser parses the conversion to a BASE LifeAsWardDecayThreshold mod", function()
        local mods = modLib.parseMod("42% of Maximum Health gained as Ward Decay Threshold")
        assert.is_not_nil(mods, "modLib.parseMod must return a mod list")
        assert.are.equals(1, #mods)
        assert.are.equals("LifeAsWardDecayThreshold", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(42, mods[1].value)
    end)

    it("accepts the 'Max Health' / 'of Max[imum] Health' phrasings", function()
        for _, text in ipairs({
            "39% of Maximum Health gained as Ward Decay Threshold",
            "130% of Max Health gained as Ward Decay Threshold",
            "12% Maximum Health gained as Ward Decay Threshold",
        }) do
            local mods = modLib.parseMod(text)
            assert.is_not_nil(mods, "must parse: " .. text)
            assert.are.equals("LifeAsWardDecayThreshold", mods[1].name, "name for: " .. text)
        end
    end)

    it("CalcDefence folds LifeAsWardDecayThreshold against output.Life", function()
        local defenceSrc = readFile("Modules/CalcDefence.lua")
        assert.is_not_nil(defenceSrc, "must read Modules/CalcDefence.lua")
        assert.is_truthy(string.find(defenceSrc,
            'modDB:Sum%("BASE",%s*nil,%s*"LifeAsWardDecayThreshold"%)', 1, false),
            "CalcDefence must read LifeAsWardDecayThreshold via Sum over BASE")
        assert.is_truthy(string.find(defenceSrc,
            'output%.WardDecayThreshold%s*=%s*output%.WardDecayThreshold%s*%+%s*m_floor%(lifeAsWdtPct%s*/%s*100%s*%*%s*%(output%.Life', 1, false),
            "CalcDefence must add lifeAsWdtPct/100 * output.Life into WardDecayThreshold")
    end)

    it("conversion arithmetic: base 55 + 42% of Life 2031 = 908", function()
        local m_floor = math.floor
        local function fold(base, pct, life) return base + m_floor(pct / 100 * life + 0.5) end
        assert.are.equals(908, fold(55, 42, 2031))
    end)
end)
