-- @leb-regression-guard: frostbite-shackles-wr-per-uncapped-cold-res
-- Locks the Frostbite Shackles (unique boots) intrinsic
-- "+1% Ward Retention per 2% uncapped Cold Resistance" against three
-- regressions discovered together on QWXjqDq9 lv95 Spellblade:
--
--   1. The uniques*.json files (uniques.json, uniques_1_2/3/4.json) had
--      the WRONG mod text "+100% Ward Retention per 100% uncapped Cold
--      Resistance". The actual in-game text per the LE datamining dump
--      (LE_datamining/extracted/items/uniques_v3.json L27913) is
--      "+1% Ward Retention per 2% uncapped Cold Resistance". The wrong
--      text drove a parser pattern that produced a PerStat-tagged BASE
--      WardRetention=100 mod.
--
--   2. ModParser emitted a PerStat tag referencing the CAPPED stat
--      `ColdResist` (max 75%). The intrinsic explicitly says
--      "uncapped Cold Resistance" → must use the uncapped sum.
--
--   3. WardRetention is finalized by CalcPerform L1388 BEFORE
--      calcs.defence runs at L1396 — so a PerStat tag on WardRetention
--      that depends on output.ColdResist[Total] reads 0 (the resist
--      outputs aren't set yet). The fix bypasses ModStore PerStat
--      entirely: ModParser emits a custom BASE mod name
--      `WardRetentionPerUncappedColdRes_Per2`, and CalcDefence injects
--      the bonus AFTER the resist loop but BEFORE WardRetention is
--      consumed by the stable-ward / decay formulas.
--
-- Evidence (QWXjqDq9 lv95 Spellblade):
--   - Cold Resistance (uncapped): 363%
--   - Bonus from Frostbite Shackles: round(363 / 2) * 1 = 182
--   - LETools display:  WardRetention = 344%
--   - LEB base (no Frostbite contribution): WardRetention = 162%
--   - 162 + 182 = 344  → Δ closes to 0
--
-- See REGRESSION_GUARDS.md entry
-- `frostbite-shackles-wr-per-uncapped-cold-res` for the full chain.

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

describe("FrostbiteShacklesWRPerUncappedColdRes", function()
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

    it("all 4 uniques*.json files carry the CORRECT in-game text (+1% / 2%)", function()
        for path, text in pairs(uniquesTexts) do
            assert.is_truthy(string.find(text,
                "+1% Ward Retention per 2% uncapped Cold Resistance", 1, true),
                path .. " must contain the correct in-game mod text")
        end
    end)

    it("no uniques*.json file still carries the WRONG legacy text (+100% / 100%)", function()
        for path, text in pairs(uniquesTexts) do
            assert.is_nil(string.find(text,
                "+100% Ward Retention per 100% uncapped Cold Resistance", 1, true),
                path .. " must not contain the legacy wrong text")
        end
    end)

    it("ModParser emits custom BASE mod 'WardRetentionPerUncappedColdRes_Per2' (not a PerStat tag)", function()
        assert.is_truthy(string.find(modParserText,
            'mod%("WardRetentionPerUncappedColdRes_Per2", "BASE", num%)', 1, false),
            "Parser must emit a custom BASE mod name so CalcDefence can inject after resist totals")
    end)

    it("ModParser pattern matches the new '+N% ward retention per 2% uncapped cold resistance' text", function()
        assert.is_truthy(string.find(modParserText,
            "ward retention per 2%% uncapped cold resistance", 1, true),
            "Parser pattern must target divisor 2 (not legacy 100)")
    end)

    it("ModParser does NOT carry the legacy PerStat ColdResist tag for this line", function()
        assert.is_nil(string.find(modParserText,
            'mod%("WardRetention", "BASE", num, "", 0, 0, %{ type = "PerStat", stat = "ColdResist", div = 100 %}%)', 1, false),
            "Legacy PerStat:ColdResist emission must be removed (read capped resist + wrong ordering)")
    end)

    it("ModParser ALSO handles the LEGACY '+N% per 100%' text (frozen in existing build XMLs)", function()
        -- Existing TestBuilds XMLs (e.g. QWXjqDq9 lv95 Spellblade.xml) carry the
        -- pre-fix wrong text frozen into them by the importer. The parser must
        -- recognise that text and emit the SAME custom BASE mod (coefficient
        -- collapsed to 1) so already-imported builds get the bonus too.
        assert.is_truthy(string.find(modParserText,
            "ward retention per 100%% uncapped cold resistance", 1, true),
            "Parser must keep a fallback pattern for the legacy '+N% per 100%' text")
        local legacyMods = parseFresh("+100% Ward Retention per 100% uncapped Cold Resistance")
        assert.is_truthy(legacyMods)
        assert.are.equal("WardRetentionPerUncappedColdRes_Per2", legacyMods[1].name)
        assert.are.equal("BASE", legacyMods[1].type)
        assert.are.equal(1, legacyMods[1].value,
            "Legacy text must collapse to coefficient 1 (canonical +1%/2% rate)")
    end)

    it("ModParser correctly handles the NEW '+1% per 2%' text", function()
        local newMods = parseFresh("+1% Ward Retention per 2% uncapped Cold Resistance")
        assert.is_truthy(newMods)
        assert.are.equal("WardRetentionPerUncappedColdRes_Per2", newMods[1].name)
        assert.are.equal("BASE", newMods[1].type)
        assert.are.equal(1, newMods[1].value)
    end)

    it("CalcDefence carries the @leb-regression-guard:frostbite-shackles-wr-per-uncapped-cold-res marker", function()
        assert.is_truthy(string.find(calcDefenceText,
            "@leb-regression-guard:frostbite-shackles-wr-per-uncapped-cold-res", 1, true),
            "CalcDefence injection site must carry the named guard marker")
    end)

    it("CalcDefence injects WardRetentionPerUncappedColdRes_Per2 against ColdResistTotal (uncapped)", function()
        assert.is_truthy(string.find(calcDefenceText,
            'modDB:Sum%("BASE", nil, "WardRetentionPerUncappedColdRes_Per2"%)', 1, false),
            "CalcDefence must Sum the custom BASE mod")
        assert.is_truthy(string.find(calcDefenceText,
            "output.ColdResistTotal", 1, true),
            "CalcDefence must reference UNCAPPED ColdResistTotal")
        assert.is_truthy(string.find(calcDefenceText,
            "output.WardRetention = %(output.WardRetention or 0%) %+ bonusWR", 1, false),
            "CalcDefence must add the bonus directly to output.WardRetention")
    end)

    it("ModCache no longer pins the stale +100%/100% entry", function()
        local modCacheText = readSource("Data/ModCache.lua")
        assert.is_nil(string.find(modCacheText,
            "+100% Ward Retention per 100% uncapped Cold Resistance", 1, true),
            "Stale ModCache entry must be purged so re-parse picks up the new mod name")
    end)
end)
