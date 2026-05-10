-- @leb-regression-guard:resist-base-high-precision
-- ScaleAddMod (src/Classes/ModStore.lua) calls m_modf on the scaled value
-- when no precision is registered in data.highPrecisionMods, truncating
-- fractional parts. Buff-tree skill node mods like Holy Aura ah443-0
-- ("+15% Cold/Fire/Lightning Resistance") are scaled by HolyAuraEffect
-- INC mods (e.g. Sentinel-119 Covenant of Light: +4%/pt) via
-- CalcSetup.lua applyBuffPrefix → ScaleAddList. Without precision=1,
-- 15 * 1.04 = 15.6 truncates to 15, producing per-resist Δ=-0.6 vs LE.
--
-- Establishing build: BgRrP5rr lv98 Paladin (Cold Resistance LE total 97.6
-- → 98; LEB stored 96.8 → 97 pre-fix).
--
-- This spec pins the precision registration in src/Modules/Data.lua so
-- a future refactor of the highPrecisionMods table cannot silently drop
-- the resist BASE entries.

-- @leb-regression-guard:corrupted-sealed-allres-round-half-up
-- Idol of Hope (and similar small idols) carries a corrupted sealed
-- "All Resistances" affix (affixId 1070, multi_affixes_v3.json) whose
-- canonical minRoll/maxRoll is 0.008 (raw) = 0.8%. LE displays per-affix
-- with round-half-up to 1% AND uses the rounded value in the per-source
-- sum for the resist tooltip. LEB ModItem.json/ModItem_1_4.json
-- previously stored "+0.8%" matching the raw float, producing
-- ΔBASE=-0.2/resist vs LE's stored sum.
--
-- Establishing build: BgRrP5rr lv98 Paladin (Idol of Hope contributes
-- "+1% Cold Resistance" per LETools; LEB stored 0.8 pre-fix).

describe("ResistBaseHighPrecision", function()
    local function readFile(path)
        local f = assert(io.open(path, "r"), "missing: " .. path)
        local s = f:read("*a")
        f:close()
        return s
    end

    -- ----- Fix C: data.highPrecisionMods must register BASE=1 for resists -----
    -- LEB-internal short stat names (no "-ance" suffix), matching the keys
    -- used by ModParser ("all resistances") and modDB:Sum.
    local resistStats = {
        "FireResist", "ColdResist", "LightningResist",
        "NecroticResist", "PoisonResist", "VoidResist",
        "PhysicalResist",
    }

    describe("Data.lua highPrecisionMods", function()
        local src = readFile("../src/Modules/Data.lua")

        for _, stat in ipairs(resistStats) do
            it("registers BASE=1 precision for " .. stat, function()
                -- Match: ["<stat>"] = { ["BASE"] = 1 }
                local pat = '%["' .. stat .. '"%]%s*=%s*{%s*%["BASE"%]%s*=%s*1%s*}'
                assert.is_truthy(src:find(pat),
                    stat .. " missing BASE=1 in data.highPrecisionMods")
            end)
        end

        it("carries the @leb-regression-guard marker", function()
            assert.is_truthy(
                src:find("@leb%-regression%-guard:resist%-base%-high%-precision"),
                "guard marker missing above the resist precision block")
        end)
    end)

    -- ----- Fix D: corrupted sealed All Resistances stored as +1% ------------
    local function findAffix1070(json)
        -- Locate the "1070_0" entry and return ~1500 chars
        local idx = json:find('"1070_0"%s*:')
        assert.is_not_nil(idx, "missing affixId 1070_0 in ModItem JSON")
        return json:sub(idx, idx + 1500)
    end

    describe("ModItem.json affixId 1070_0 (corrupted sealed All Resistances)", function()
        for _, path in ipairs({
            "../src/Data/ModItem.json",
            "../src/Data/ModItem_1_4.json",
        }) do
            it(path .. " stores +1% (not +0.8%) on player and minion lines", function()
                local json = readFile(path)
                local entry = findAffix1070(json)
                assert.is_truthy(entry:find('+1%% All Resistances'),
                    "expected '+1% All Resistances' in " .. path)
                assert.is_truthy(entry:find('+1%% Minion All Resistances'),
                    "expected '+1% Minion All Resistances' in " .. path)
                assert.is_falsy(entry:find('+0%.8%% All Resistances'),
                    "raw 0.8 must not be restored in " .. path)
            end)
        end
    end)
end)
