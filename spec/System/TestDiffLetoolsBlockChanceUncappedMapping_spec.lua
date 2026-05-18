-- @leb-regression-guard: diff-letools-block-chance-uncapped-mapping
-- Locks the contract that `spec/tools/diff_letools.py` maps LETools'
-- General-tab "Block Chance" to LEB `output.BlockChanceTotal` (raw
-- uncapped), NOT `output.BlockChance` (post-cap at BlockChanceMax=75).
-- LETools planner displays the uncapped value so build planners can
-- see over-cap headroom — same display family as Endurance/EnduranceTotal.
--
-- Establishing case: BgRrP5rr lv98 Paladin Block Chance LEB capped 75
-- vs LETools "93%" = phantom 19.4% drift on every shield Paladin past
-- the cap unless this maps to BlockChanceTotal. Reverting the mapping
-- to bare `BlockChance` (the natural-looking choice) would silently
-- re-introduce the regression.
--
-- See REGRESSION_GUARDS.md §diff-letools-block-chance-uncapped-mapping.

describe("DiffLetoolsBlockChanceUncappedMapping", function()
    local function readPython()
        local f = io.open("spec/tools/diff_letools.py", "r")
            or io.open("../spec/tools/diff_letools.py", "r")
        assert.is_not_nil(f, "diff_letools.py missing")
        local src = f:read("*a")
        f:close()
        return src
    end

    it("'Block Chance' MAPPING entry resolves to 'BlockChanceTotal'", function()
        local src = readPython()
        local mapping = src:match(
            "%('General','Block Chance'%):%s*'([^']+)'")
        assert.is_not_nil(mapping,
            "MAPPING must have an ('General','Block Chance') entry")
        assert.are.equals("BlockChanceTotal", mapping,
            "Must map to BlockChanceTotal (uncapped). Bare 'BlockChance' " ..
            "would re-introduce the 19.4% drift on every shield Paladin " ..
            "past the cap (BlockChanceMax=75). See REGRESSION_GUARDS.md " ..
            "§diff-letools-block-chance-uncapped-mapping.")
    end)

    it("inline guard marker present at the MAPPING entry", function()
        local src = readPython()
        local block = src:match(
            "@leb%-regression%-guard:diff%-letools%-block%-chance%-uncapped%-mapping(.-)'BlockChanceTotal'")
        assert.is_not_nil(block,
            "Inline @leb-regression-guard:diff-letools-block-chance-uncapped-mapping " ..
            "marker must precede the BlockChanceTotal MAPPING entry")
        assert.is_truthy(block:find("BlockChanceMax", 1, false),
            "Marker block must mention BlockChanceMax to anchor the cap " ..
            "rationale for future maintainers")
    end)

    it("Endurance mapping uses the same uncapped-Total pattern", function()
        -- This is a cross-reference assertion: if a future refactor unifies
        -- 'uncapped Total' mappings into a helper and accidentally drops
        -- Block Chance from the set, the Endurance entry stays as the
        -- canonical reference for the pattern.
        local src = readPython()
        local mapping = src:match(
            "%('Defense','Endurance'%):%s*'([^']+)'")
        assert.is_not_nil(mapping,
            "MAPPING must have an ('Defense','Endurance') entry")
        assert.are.equals("EnduranceTotal", mapping,
            "Endurance is the canonical sibling for the uncapped-Total " ..
            "mapping pattern that Block Chance mirrors")
    end)

    it("CalcDefence.lua writes output.BlockChanceTotal as the uncapped value", function()
        local f = io.open("Modules/CalcDefence.lua", "r")
            or io.open("src/Modules/CalcDefence.lua", "r")
        assert.is_not_nil(f, "CalcDefence.lua missing")
        local src = f:read("*a")
        f:close()
        assert.is_truthy(
            src:find("output%.BlockChanceTotal", 1, false),
            "CalcDefence.lua must write output.BlockChanceTotal so the " ..
            "diff_letools.py mapping has a value to read. The Sentinel-70 " ..
            "Dedication ManaRegen handler also depends on this same uncapped " ..
            "field (see @leb-regression-guard:paladin-sentinel70-dedication-mana-regen)")
    end)
end)
