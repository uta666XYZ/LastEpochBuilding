-- @leb-regression-guard: idol-affix-tier-fallback
-- Locks the metatable fallback that chains the flat idol affix lookup table
-- (`verIdolMods.flat`) to `verMods` (ModItem). ModIdol_<ver>.json currently
-- carries only tier 0 (`_0`) entries for every affix; idols can roll up to
-- T7 (e.g. enchanted 905_4 Mana Regen). Without the fallback, tier-N lookups
-- return nil and the affix contributes zero, silently regressing every
-- non-T0 idol affix introduced by the paired guard
-- `idol-affix-source-and-formula`.
--
-- Idol-specific T0 corrections (e.g. 1070_0 All Resistances ModIdol raw +5%
-- vs ModItem raw +1%) still take precedence because `flat` is consulted
-- first; the metatable only fires on miss.
--
-- See REGRESSION_GUARDS.md "idol-affix-tier-fallback".

describe("IdolAffixTierFallback", function()

    local dataSrc
    setup(function()
        local f = io.open("Modules/Data.lua", "r")
        assert.is_not_nil(f, "must open Modules/Data.lua")
        dataSrc = f:read("*a"); f:close()
    end)

    it("Data.lua guard comment is present", function()
        assert.is_truthy(string.find(dataSrc,
            "idol-affix-tier-fallback", 1, true),
            "Data.lua must keep the @leb-regression-guard comment")
    end)

    it("Data.lua chains verIdolMods.flat to verMods via __index", function()
        -- The metatable fallback line is the entire correctness invariant:
        -- removing it re-introduces the silent tier-N=0 regression.
        assert.is_truthy(string.find(dataSrc,
            "setmetatable(flat, { __index = verMods })", 1, true),
            "Data.lua must keep `setmetatable(flat, { __index = verMods })` " ..
            "so tier-N idol affix lookups fall back to ModItem")
    end)

    it("Data.lua sets verIdolMods.flat AFTER the metatable is attached", function()
        local mtIdx = string.find(dataSrc,
            "setmetatable(flat, { __index = verMods })", 1, true)
        local assignIdx = string.find(dataSrc, "verIdolMods.flat = flat", 1, true)
        assert.is_not_nil(mtIdx, "metatable line must exist")
        assert.is_not_nil(assignIdx, "verIdolMods.flat assignment must exist")
        assert.is_true(mtIdx < assignIdx,
            "metatable must be attached before publishing verIdolMods.flat")
    end)
end)
