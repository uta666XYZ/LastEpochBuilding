-- @leb-regression-guard: idol-altar-no-reforged-set
-- See REGRESSION_GUARDS.md "idol-altar-no-reforged-set".
-- Validation provenance is retained in maintainer notes.

describe("IdolAltarNoReforgedSet", function()

    local importSrc
    setup(function()
        local f = assert(io.open("Classes/ImportTab.lua", "r"), "must open Classes/ImportTab.lua")
        importSrc = f:read("*a"); f:close()
    end)

    it("ImportTab.lua keeps the @leb-regression-guard comment", function()
        assert.is_truthy(string.find(importSrc, "idol-altar-no-reforged-set", 1, true),
            "ImportTab.lua must keep the @leb-regression-guard comment")
    end)

    it("both reforged-set scans are gated on non-idol/non-altar bases", function()
        -- The inline scan gate (affix loop) must require NOT idol/altar.
        assert.is_truthy(string.find(importSrc,
            'if not isIdolOrAltar and modData.affix and modData.affix:sub(-9) == " Reforged" then', 1, true),
            "the inline reforged scan must be gated on `not isIdolOrAltar`")
        -- The offline-save scanForReforged block must be gated by an idol/altar check.
        assert.is_truthy(string.find(importSrc,
            'if not (itemBaseName:find("Idol") or itemBaseName:find("Altar")) then', 1, true),
            "the scanForReforged block must be gated on non-idol/non-altar base name")
    end)
end)
