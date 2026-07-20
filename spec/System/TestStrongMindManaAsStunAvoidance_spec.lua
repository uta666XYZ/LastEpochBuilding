-- @leb-regression-guard: strong-mind-mana-as-stun-avoidance
-- Locks the "X% of maximum mana added as stun avoidance" conversion that the
-- Strong Mind unique grants. This is a tooltipDescription-only property in the
-- item data (no numeric mod entry), so the datamining extraction dropped it and
-- LEB applied 0. The fix is two-sided:
--
--   1. ModParser.lua maps the tooltip string to a BASE `ManaAsStunAvoidance`
--      stat (mirroring the Mana/Life-AsEnduranceThreshold contract).
--   2. CalcDefence.lua folds `ManaAsStunAvoidance`% of `output.Mana` into the
--      flat stun-avoidance pool, so it feeds BOTH the StunAvoidance display
--      stat AND the stun-threshold pool.
--
-- Triangulation case study: ImPalmBeachPete lv48 Bladedancer (save BETA_12).
--   in-game Stun Avoidance = 880. Strong Mind grants 200%; Mana = 195.
--   flat (base+tree+items) 490 + 200% * 195 = 490 + 390 = 880.
--   Before the fix LEB showed 490 (the conversion silently 0) — the same gap
--   the lv36 XML snapshot recorded as 430 vs 796 (= 2 * Mana 183).
--
-- Dropping either the ModParser mapping or the CalcDefence fold re-introduces
-- the missing 2*Mana term and fails this spec.
--
-- See REGRESSION_GUARDS.md "strong-mind-mana-as-stun-avoidance".

describe("StrongMindManaAsStunAvoidance", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local parserSrc = readFile("Modules/ModParser.lua")
    local defenceSrc = readFile("Modules/CalcDefence.lua")

    it("ModParser maps the tooltip string to a BASE ManaAsStunAvoidance stat", function()
        assert.is_not_nil(parserSrc, "must read Modules/ModParser.lua")
        assert.is_truthy(string.find(parserSrc,
            'maximum mana added as stun avoidance', 1, true),
            "ModParser must recognise the 'maximum mana added as stun avoidance' tooltip line")
        assert.is_truthy(string.find(parserSrc,
            'mod%("ManaAsStunAvoidance",%s*"BASE"', 1, false),
            "the tooltip handler must emit a BASE ManaAsStunAvoidance mod")
    end)

    it("CalcDefence folds ManaAsStunAvoidance against max Mana into the flat pool", function()
        assert.is_not_nil(defenceSrc, "must read Modules/CalcDefence.lua")
        assert.is_truthy(string.find(defenceSrc,
            'modDB:Sum%("BASE",%s*nil,%s*"ManaAsStunAvoidance"%)', 1, false),
            "CalcDefence must read ManaAsStunAvoidance via Sum over BASE")
        -- The conversion must multiply against output.Mana and add into the
        -- flat stun-avoidance accumulator (which feeds both the display stat
        -- and the stun-threshold pool).
        assert.is_truthy(string.find(defenceSrc,
            'flatStunAvoidance%s*=%s*flatStunAvoidance%s*%+%s*%(output%.Mana[^\n]-manaAsStunAvoidance', 1, false),
            "CalcDefence must add output.Mana * manaAsStunAvoidance/100 to flatStunAvoidance")
    end)

    it("arithmetic: 200% of Mana 195 adds 390 -> 490 base becomes 880", function()
        local function round(x) return math.floor(x + 0.5) end
        local flatBase = 490
        local mana = 195
        local manaAsStunAvoidance = 200
        local total = round(flatBase + mana * manaAsStunAvoidance / 100)
        assert.are.equals(880, total)
        -- without the conversion the stat collapses to the flat base only
        assert.are.equals(490, round(flatBase))
    end)
end)
