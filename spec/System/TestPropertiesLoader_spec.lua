-- Verify the Properties loader resolves PropertyList JSON entries.
--
-- The JSON file ships with the repo (extracted from LE 1.4.6
-- resources.assets via TypeTreeGeneratorAPI). Tests pin a few
-- well-known SPs / propertyNames so any future schema rename is
-- caught immediately.
--
-- @leb-regression-guard: properties-loader-init

describe("Properties Loader (LE PropertyList runtime data)", function()
    local Properties = require("Data.Properties.Loader")

    it("loads property_list_1_4.json (110 entries)", function()
        local ok, err = Properties.load("1.4")
        assert.is_true(ok, tostring(err))
        assert.are.equals(110, #Properties.properties)
    end)

    it("normalizes '1.4' and '1_4' to the same version", function()
        Properties.load("1.4")
        local n1 = Properties.version
        Properties.load("1_4")
        assert.are.equals(n1, Properties.version)
    end)

    it("'Physical Resistance' (SP=64) is Hundredth-ADDED", function()
        Properties.load("1.4")
        local entry = Properties.byName["Physical Resistance"]
        assert.is_truthy(entry)
        assert.are.equals(64, entry.property)
        assert.are.equals(0, entry.roundingForAdded)  -- 0 = Hundredth
        assert.is_true(entry.displayAddedAsPercentage)
    end)

    it("bySP lookup matches byName lookup", function()
        Properties.load("1.4")
        local viaName = Properties.byName["Physical Resistance"]
        local viaSP   = Properties.bySP[64]
        assert.are.equals(viaName, viaSP)
    end)

    it("roundingForName / roundingForSP defaults to 0 for unknown stats", function()
        Properties.load("1.4")
        assert.are.equals(0, Properties.roundingForName("__nonexistent__"))
        assert.are.equals(0, Properties.roundingForSP(99999))
    end)
end)
