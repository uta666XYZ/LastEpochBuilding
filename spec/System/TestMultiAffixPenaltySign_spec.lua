-- @leb-regression-guard: multi-affix-penalty-sign
-- Locks the contract that "Cannot be X and Reduced Y" / "X and Reduced Y"
-- multi-affixes (specialAffixType == 6, prefix) encode their Line 2 stat
-- as a NEGATIVE literal/range in ModItem_1_4.json — matching the
-- game-side extraRolls[0].minRoll < 0 found in
-- ~/Documents/LE_datamining/extracted/items/multi_affixes_v3.json.
--
-- Historical bug: 951_*, 1001_*, 1006_* were imported with the positive
-- sign, silently flipping a player penalty into a bonus. Ground truth:
-- olVLdj8q lv100 Bladedancer Item 6 "Salt the Wound" carries
-- {kind:corrupted}{range:175}1006_0 — pre-fix LEB granted +7% Fire
-- Resistance instead of the in-game -7% penalty (Δ Fire = +14 vs LETools).
--
-- See REGRESSION_GUARDS.md "multi-affix-penalty-sign".

describe("MultiAffixPenaltySign", function()
    local data
    setup(function()
        local f = io.open("Data/ModItem_1_4.json", "r")
        assert.is_not_nil(f, "must be able to open Data/ModItem_1_4.json")
        local src = f:read("*a")
        f:close()
        -- Lightweight per-entry extraction: locate `"<id>_<tier>":` and
        -- capture the `"2":` line that follows within the next ~500 chars.
        data = src
    end)

    local function lineTwoOf(key)
        -- Find `"<key>": {` and then the first `"2": "<...>",?` after it.
        local startIdx = data:find('"' .. key .. '":%s*{', 1, false)
        assert.is_not_nil(startIdx, "ModItem_1_4.json missing key " .. key)
        local segment = data:sub(startIdx, startIdx + 1500)
        return segment:match('"2":%s*"(.-)"')
    end

    local cases = {
        -- Frenzy effect penalty: game extraRoll -0.18..-0.02
        { key = "951_0", expect = "-18", note = "Frenzy Effect tier 0" },
        { key = "951_7", expect = "-3",  note = "Frenzy Effect tier 7" },
        -- Haste effect penalty: game extraRoll -0.25..-0.03
        { key = "1001_0", expect = "-25", note = "Haste Effect tier 0" },
        { key = "1001_7", expect = "-4",  note = "Haste Effect tier 7" },
        -- Fire Resistance penalty: game extraRoll -0.07..0
        { key = "1006_0", expect = "-7", note = "Fire Resistance tier 0" },
        { key = "1006_6", expect = "-1", note = "Fire Resistance tier 6" },
    }

    for _, c in ipairs(cases) do
        it(c.key .. " Line 2 encodes a negative " .. c.note, function()
            local line = lineTwoOf(c.key)
            assert.is_not_nil(line, "Line 2 missing for " .. c.key)
            -- The first numeric token after `+(` or at the start must be negative,
            -- OR the literal value must start with `-`.
            local leadingSign = line:match('^([%+%-])')
            local firstNumStr
            if leadingSign == '+' then
                -- expect `+(-N--M)% ...` shape
                firstNumStr = line:match('^%+%(([%+%-]?%d+)')
            else
                firstNumStr = line:match('^([%+%-]?%d+)')
            end
            assert.is_not_nil(firstNumStr,
                "could not parse first numeric token from Line 2: " .. line)
            local n = tonumber(firstNumStr)
            assert.is_true(n and n < 0,
                "Line 2 for " .. c.key .. " must encode a negative tier-0 value, got " ..
                tostring(firstNumStr) .. " (expected " .. c.expect .. ") -- full line: " .. line)
        end)
    end

    it("affix 246 (Reduced Volcanic Orb Speed) remains positively-signed", function()
        -- Sanity: affix 246's "Reduced Volcanic Orb Speed" is a descriptive
        -- name, but the game-side extraRoll is POSITIVE (+0.20 t0). The
        -- guard must NOT mis-flip these. If this asserts false, someone
        -- generalised the sign-flip incorrectly.
        local line = lineTwoOf("246_0")
        assert.is_not_nil(line, "246_0 must exist")
        local firstNum = line:match('([%+%-]?%d+)')
        assert.is_not_nil(firstNum, "246_0 line parse failed")
        assert.is_true(tonumber(firstNum) > 0,
            "246_0 Line 2 must remain positive (descriptive-only Reduced wording); got " .. line)
    end)
end)
