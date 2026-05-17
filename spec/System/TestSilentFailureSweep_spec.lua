-- @leb-regression-guard: silent-failure-affix-sweep
-- Phase 1 lock for the Category B silent-failure affix sweep.
--
-- The tool `spec/tools/enumerate_silent_failures.py` walks
-- src/Data/ModCache.lua and emits spec/Data/silent-failure-affixes.json
-- listing every row of the form `c["..."]={{},"<residue>"}` -- an affix
-- string LEB attempted to parse, where ModParser returned an empty modList
-- yet emitted non-empty residue (i.e. the affix was silently swallowed
-- without surfacing into calculations and without raising an error).
--
-- This spec locks the Phase 1 baseline so any regression -- either:
--   (a) a new silent-failure regression growing the count back, or
--   (b) a successful Phase 3 wiring shrinking the count -- forces a
-- deliberate update of the JSON snapshot and this spec's baselines.
--
-- Phase 1 deliverables:
--   * tool   : spec/tools/enumerate_silent_failures.py
--   * data   : spec/Data/silent-failure-affixes.json
--   * spec   : this file
--   * index  : REGRESSION_GUARDS.md "silent-failure-affix-sweep"
--
-- Phase 2 (classification refinement via datamining cross-reference) and
-- Phase 3 (type-specific PRs neutralising / wiring / spawning / purging)
-- live behind their own tickets -- see TODO.md "Category B silent-failure
-- affix sweep".

local function readFile(relPath)
    local f = io.open(relPath, "r") or io.open("../" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("SilentFailureAffixSweep", function()
    local cjson_ok, cjson = pcall(require, "lua.dkjson")
    if not cjson_ok then cjson_ok, cjson = pcall(require, "dkjson") end

    local raw, data
    setup(function()
        raw = readFile("spec/Data/silent-failure-affixes.json")
        if cjson_ok and cjson.decode then
            data = cjson.decode(raw)
        end
    end)

    describe("JSON artefact freshness", function()
        it("exists and has the expected top-level shape", function()
            assert.is_string(raw)
            assert.is_truthy(string.find(raw, '"metadata"', 1, true))
            assert.is_truthy(string.find(raw, '"silent_failures"', 1, true))
            assert.is_truthy(string.find(raw, '"dm_gap"', 1, true))
        end)

        it("identifies itself as the enumerate_silent_failures tool", function()
            assert.is_truthy(string.find(raw, '"enumerate_silent_failures"', 1, true))
        end)

        it("declares Phase 2", function()
            assert.is_truthy(string.find(raw, '"phase": 2', 1, true))
        end)
    end)

    describe("baseline counts (Phase 3a lock)", function()
        -- These baselines are intentionally hard-coded. When you change
        -- ModCache.lua in a way that moves these numbers, RE-RUN the tool
        --   python spec/tools/enumerate_silent_failures.py
        -- and update both spec/Data/silent-failure-affixes.json AND the
        -- numbers below in the SAME commit. A drift here is your cue that
        -- a wiring/neutralisation actually landed and the baseline moved.
        --
        -- Phase 3a (a1-pure-flavor bulk neutralization) moved:
        --   neutralized  367 -> 1082  (+715)
        --   silent      2791 -> 2076  (-715)
        --   recognition 83.34% -> 87.61%
        local EXPECTED_TOTAL          = 16749
        local EXPECTED_PARSED         = 13591
        local EXPECTED_NEUTRALIZED    = 1082
        local EXPECTED_SILENT         = 2076

        local function field(name)
            -- Cheap regex extraction so the spec runs even without dkjson.
            local v = raw:match('"' .. name .. '"%s*:%s*(%-?%d+)')
            assert.is_not_nil(v, "missing metadata field: " .. name)
            return tonumber(v)
        end

        it("total_rows matches baseline", function()
            assert.are.equal(EXPECTED_TOTAL, field("total_rows"))
        end)

        it("parsed_rows matches baseline", function()
            assert.are.equal(EXPECTED_PARSED, field("parsed_rows"))
        end)

        it("neutralized_rows matches baseline", function()
            assert.are.equal(EXPECTED_NEUTRALIZED, field("neutralized_rows"))
        end)

        it("silent_failure_rows matches baseline", function()
            assert.are.equal(EXPECTED_SILENT, field("silent_failure_rows"))
        end)

        it("malformed_rows is zero (parser stays sound)", function()
            assert.are.equal(0, field("malformed_rows"))
        end)

        it("parsed + neutralized + silent == total", function()
            assert.are.equal(field("total_rows"),
                field("parsed_rows") + field("neutralized_rows") + field("silent_failure_rows"))
        end)
    end)

    describe("category breakdown (Phase 3a post-neutralization)", function()
        -- Phase 2 classifier uses key + residue + datamining_match.
        -- Buckets and baselines (post Phase 3a a1-pure-flavor neutralization):
        --   a1-pure-flavor : 0    (all 715 promoted to neutralized rows)
        --   a2-numeric-real: 634
        --   b-dm-numeric   : 135  (dm-confirmed real numeric, parser gap)
        --   b-parser-gap   : 466
        --   c-dm-infra     : 239  (dm-confirmed real trigger/event)
        --   c-infra-gap    : 602
        local function catCount(cat)
            local n = raw:match('"' .. cat .. '"%s*:%s*(%-?%d+)')
            return tonumber(n)
        end

        it("emits the five remaining Phase 3a buckets", function()
            -- a1-pure-flavor is intentionally absent after Phase 3a.
            assert.is_nil(catCount("a1%-pure%-flavor"))
            assert.is_not_nil(catCount("a2%-numeric%-real"))
            assert.is_not_nil(catCount("b%-dm%-numeric"))
            assert.is_not_nil(catCount("b%-parser%-gap"))
            assert.is_not_nil(catCount("c%-dm%-infra"))
            assert.is_not_nil(catCount("c%-infra%-gap"))
        end)

        it("category counts sum to silent_failure_rows", function()
            local sum = (catCount("a2%-numeric%-real") or 0)
                + (catCount("b%-dm%-numeric") or 0)
                + (catCount("b%-parser%-gap") or 0)
                + (catCount("c%-dm%-infra") or 0)
                + (catCount("c%-infra%-gap") or 0)
            local silent = raw:match('"silent_failure_rows"%s*:%s*(%-?%d+)')
            assert.are.equal(tonumber(silent), sum)
        end)
    end)

    describe("Phase 2 datamining cross-reference", function()
        local function dmField(name)
            local v = raw:match('"' .. name .. '"%s*:%s*(%-?%d+)')
            return tonumber(v)
        end

        it("declares Phase 2", function()
            assert.is_truthy(string.find(raw, '"phase": 2', 1, true))
        end)

        -- These baselines move when ModItem_1_4.json or ModCache.lua
        -- change. Re-run the tool and update in the same commit.
        local EXPECTED_DM_LINES      = 9525
        local EXPECTED_DM_UNIQUE     = 986
        local EXPECTED_SF_MATCHED    = 374  -- unchanged: a1 had no dm matches
        local EXPECTED_DM_GAP        = 283

        it("moditem_lines_scanned matches baseline", function()
            assert.are.equal(EXPECTED_DM_LINES, dmField("moditem_lines_scanned"))
        end)
        it("moditem_unique_norms matches baseline", function()
            assert.are.equal(EXPECTED_DM_UNIQUE, dmField("moditem_unique_norms"))
        end)
        it("silent_failure_matched matches baseline", function()
            assert.are.equal(EXPECTED_SF_MATCHED, dmField("silent_failure_matched"))
        end)
        it("dm_gap_count matches baseline", function()
            assert.are.equal(EXPECTED_DM_GAP, dmField("dm_gap_count"))
        end)
    end)

    describe("tool source carries the inline regression-guard marker", function()
        it("enumerate_silent_failures.py keeps the guard ID", function()
            local toolText = readFile("spec/tools/enumerate_silent_failures.py")
            assert.is_truthy(string.find(toolText,
                "@leb-regression-guard: silent-failure-affix-sweep", 1, true),
                "tool must carry the inline guard ID")
        end)
    end)
end)
