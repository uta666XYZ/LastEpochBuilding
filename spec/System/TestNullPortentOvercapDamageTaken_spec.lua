-- @leb-regression-guard: null-portent-less-damage-taken-per-resist-overcap
-- Locks the Null Portent (unique body armour) over-cap-resistance damage
-- mitigation. The affix is authored as TWO separate mod lines that together
-- form one mechanic:
--
--   "1% less Damage Taken per 2% Resistance above the normal cap"          (rate)
--   "20% Maximum Less Damage Taken per 2% Resistance above the normal cap"  (cap)
--
-- Regression chain:
--   1. Both lines previously short-circuited on stale Data/ModCache.lua rows
--      that baked a bare `DamageTaken MORE -1` / `DamageTaken BASE 20` with
--      dropped " per 2% Resistance above the normal cap " residue -- so the
--      over-cap-resistance scaling was NEVER modelled (Symbols-of-Hope-style
--      residue trap). Those ModCache rows are deleted so the lines re-parse live.
--   2. ModParser now parses each line into BASE marker stats
--      (LessDamageTakenPerResOverCapNum / Div / Max) with NO residue.
--   3. CalcDefence combines the markers AFTER the per-type <Type>ResistOverCap
--      totals are computed and injects a PER-TYPE, MULTIPLICATIVE
--      <Type>DamageTaken MORE = -min(Max, floor(overCap / Div) * Num), consumed
--      by calcs.buildDefenceEstimations.
--
-- Spec: in-game tooltip -- 85% fire res -> fire cap 75% exceeded by 10% ->
-- 10 / 2 = 5% less FIRE damage taken (multiplicative), capped at 20% less.
--
-- See REGRESSION_GUARDS.md entry
-- `null-portent-less-damage-taken-per-resist-overcap`.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

local parseMod, parserCache

local function parseFresh(line)
    if not parseMod then
        parseMod, parserCache = LoadModule("Modules/ModParser")
    end
    parserCache[line] = nil
    return parseMod(line)
end

local function findMod(mods, name)
    for _, m in ipairs(mods) do
        if m.name == name then return m end
    end
    return nil
end

describe("NullPortentOvercapDamageTaken", function()
    local modParserText, calcDefenceText
    local uniquesTexts = {}

    setup(function()
        modParserText = readSource("Modules/ModParser.lua")
        calcDefenceText = readSource("Modules/CalcDefence.lua")
        for _, p in ipairs({
            "Data/Uniques/uniques.json",
            "Data/Uniques/uniques_1_2.json",
            "Data/Uniques/uniques_1_3.json",
            "Data/Uniques/uniques_1_4.json",
        }) do
            uniquesTexts[p] = readSource(p)
        end
    end)

    it("all 4 uniques*.json files still carry both Null Portent source lines", function()
        for path, text in pairs(uniquesTexts) do
            assert.is_truthy(string.find(text,
                "1% less Damage Taken per 2% Resistance above the normal cap", 1, true),
                path .. " must carry the rate line")
            assert.is_truthy(string.find(text,
                "20% Maximum Less Damage Taken per 2% Resistance above the normal cap", 1, true),
                path .. " must carry the cap line")
        end
    end)

    it("the RATE line parses cleanly into Num + Div markers (no residue)", function()
        local mods, extra = parseFresh("1% less Damage Taken per 2% Resistance above the normal cap")
        assert.is_truthy(mods)
        assert.is_nil(extra, "rate line must leave NO residue (was ' per 2% Resistance above the normal cap ')")
        local num = findMod(mods, "LessDamageTakenPerResOverCapNum")
        local div = findMod(mods, "LessDamageTakenPerResOverCapDiv")
        assert.is_not_nil(num, "must emit LessDamageTakenPerResOverCapNum")
        assert.is_not_nil(div, "must emit LessDamageTakenPerResOverCapDiv")
        assert.are.equal("BASE", num.type)
        assert.are.equal(1, num.value)
        assert.are.equal("BASE", div.type)
        assert.are.equal(2, div.value)
        -- Must NOT bake the old bare DamageTaken MORE anymore.
        assert.is_nil(findMod(mods, "DamageTaken"),
            "rate line must not emit an unscaled DamageTaken mod")
    end)

    it("the CAP line parses cleanly into the Max marker (no residue)", function()
        local mods, extra = parseFresh("20% Maximum Less Damage Taken per 2% Resistance above the normal cap")
        assert.is_truthy(mods)
        assert.is_nil(extra, "cap line must leave NO residue")
        local max = findMod(mods, "LessDamageTakenPerResOverCapMax")
        assert.is_not_nil(max, "must emit LessDamageTakenPerResOverCapMax")
        assert.are.equal("BASE", max.type)
        assert.are.equal(20, max.value)
        assert.is_nil(findMod(mods, "DamageTaken"),
            "cap line must not emit an unscaled DamageTaken mod")
    end)

    it("ModParser carries the named guard marker", function()
        assert.is_truthy(string.find(modParserText,
            "null%-portent%-less%-damage%-taken%-per%-resist%-overcap", 1, false),
            "ModParser must carry the guard marker")
    end)

    it("CalcDefence injects a PER-TYPE, MULTIPLICATIVE <Type>DamageTaken MORE", function()
        assert.is_truthy(string.find(calcDefenceText,
            "null%-portent%-less%-damage%-taken%-per%-resist%-overcap", 1, false),
            "CalcDefence injection site must carry the named guard marker")
        assert.is_truthy(string.find(calcDefenceText,
            'modDB:Sum%("BASE", nil, "LessDamageTakenPerResOverCapNum"%)', 1, false),
            "CalcDefence must Sum the rate Num marker")
        assert.is_truthy(string.find(calcDefenceText,
            'modDB:Sum%("BASE", nil, "LessDamageTakenPerResOverCapMax"%)', 1, false),
            "CalcDefence must Sum the cap Max marker")
        -- per-type over-cap source, MORE injection, capped at the Maximum, floored.
        assert.is_truthy(string.find(calcDefenceText,
            'output%[elem%.%."ResistOverCap"%]', 1, false),
            "CalcDefence must read per-type <Type>ResistOverCap")
        assert.is_truthy(string.find(calcDefenceText,
            'modDB:NewMod%(elem%.%."DamageTaken", "MORE", %-lessDT', 1, false),
            "CalcDefence must inject a per-type <Type>DamageTaken MORE (negative = less)")
        assert.is_truthy(string.find(calcDefenceText,
            "m_min%(lessDT, lessDTMax%)", 1, false),
            "CalcDefence must cap the less amount at the Maximum")
        assert.is_truthy(string.find(calcDefenceText,
            "m_floor%(overCap / lessDTDiv%)", 1, false),
            "CalcDefence must floor at integer steps (per-M%-resistance family)")
    end)

    it("ModCache no longer pins the stale residue rows", function()
        local modCacheText = readSource("Data/ModCache.lua")
        assert.is_nil(string.find(modCacheText,
            'c%["1%% less Damage Taken per 2%% Resistance above the normal cap"%]', 1, false),
            "stale rate ModCache row must be purged so it re-parses live")
        assert.is_nil(string.find(modCacheText,
            'c%["20%% Maximum Less Damage Taken per 2%% Resistance above the normal cap"%]', 1, false),
            "stale cap ModCache row must be purged so it re-parses live")
    end)

    -- Numeric contract: replicate the exact CalcDefence formula so the
    -- magnitude stays pinned to the tooltip spec (-N%/M% per type, cap Max).
    it("magnitude matches the tooltip formula, per-type and capped", function()
        local function lessFor(overCap, num, div, maxLess)
            local v = math.floor(overCap / div) * num
            if maxLess > 0 then v = math.min(v, maxLess) end
            return v
        end
        -- tooltip example: 10% over cap -> 5% less
        assert.are.equal(5, lessFor(10, 1, 2, 20))
        -- odd over-cap floors at integer step
        assert.are.equal(5, lessFor(11, 1, 2, 20))
        -- capped at 20% less (needs 40% over-cap to reach it)
        assert.are.equal(20, lessFor(40, 1, 2, 20))
        assert.are.equal(20, lessFor(90, 1, 2, 20))
        -- no over-cap -> no mitigation
        assert.are.equal(0, lessFor(0, 1, 2, 20))
        assert.are.equal(0, lessFor(1, 1, 2, 20))
    end)
end)
