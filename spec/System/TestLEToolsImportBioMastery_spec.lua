-- @leb-regression-guard: letools-import-bio-level-mastery
-- Locks ImportTabClass:BuildCharFromLETools bio→classId/mastery/level
-- resolution. The LETools planner API returns identity fields nested
-- under `data.bio = {level, characterClass, chosenMastery}`; these must
-- take precedence over top-level `jsonData.level / jsonData["class"] /
-- jsonData.mastery` (stale duplicates from older API revisions).
--
-- Regression case this guard prevents:
--   Build QJWMRv53 with bio={level:98, characterClass:4, chosenMastery:1}
--   must produce `QJWMRv53 lv98 Bladedancer.xml`, NOT `lv73 Falconer.xml`.
--   The XML filename derives from `build.characterLevel or char.level`
--   + `build.spec.curAscendClassName`, so a silent fallback to wrong
--   top-level values corrupts the output name without an error.
--
-- See REGRESSION_GUARDS.md "letools-import-bio-level-mastery".

describe("LEToolsImportBioMastery", function()
    local ImportTab
    before_each(function()
        newBuild()
        ImportTab = build.importTab
    end)

    it("source keeps the @leb-regression-guard anchor", function()
        local f = io.open("Classes/ImportTab.lua", "r")
        assert.is_not_nil(f, "must be able to open Classes/ImportTab.lua")
        local src = f:read("*a")
        f:close()
        assert.is_truthy(
            string.find(src, "letools-import-bio-level-mastery", 1, true),
            "ImportTab.lua must keep the @leb-regression-guard:letools-import-bio-level-mastery comment"
        )
    end)

    it("resolves classId/mastery/level from data.bio", function()
        local char = ImportTab:BuildCharFromLETools({}, {
            bio = { level = 98, characterClass = 4, chosenMastery = 1 },
        }, "QJWMRv53")
        assert.is_not_nil(char)
        assert.are.equal(98, char.level)
        assert.are.equal(4, char.classId)
        assert.are.equal("Rogue", char.class)
        assert.are.equal(1, char.ascendancy)
        assert.are.equal("Bladedancer", char.ascendancyName)
    end)

    it("bio.* takes precedence over top-level jsonData fields", function()
        local char = ImportTab:BuildCharFromLETools({
            ["class"] = 0, mastery = 0, level = 1,
        }, {
            bio = { level = 98, characterClass = 4, chosenMastery = 1 },
        }, "QJWMRv53")
        assert.are.equal(98, char.level)
        assert.are.equal(4, char.classId)
        assert.are.equal(1, char.ascendancy)
        assert.are.equal("Bladedancer", char.ascendancyName)
    end)

    it("falls back to top-level jsonData when bio is missing", function()
        local char = ImportTab:BuildCharFromLETools({
            ["class"] = 4, mastery = 2, level = 75,
        }, {}, "FallbackId")
        assert.is_not_nil(char)
        assert.are.equal(75, char.level)
        assert.are.equal(4, char.classId)
        assert.are.equal(2, char.ascendancy)
        assert.are.equal("Marksman", char.ascendancyName)
    end)

    it("resolves Rogue Falconer (mastery=3) correctly", function()
        local char = ImportTab:BuildCharFromLETools({}, {
            bio = { level = 73, characterClass = 4, chosenMastery = 3 },
        }, "RogueFalconer")
        assert.are.equal(73, char.level)
        assert.are.equal("Rogue", char.class)
        assert.are.equal("Falconer", char.ascendancyName)
    end)

    it("returns nil on unknown class", function()
        local char = ImportTab:BuildCharFromLETools({}, {
            bio = { level = 1, characterClass = 999, chosenMastery = 1 },
        }, "BadClass")
        assert.is_nil(char)
    end)

    it("returns nil on unknown mastery", function()
        local char = ImportTab:BuildCharFromLETools({}, {
            bio = { level = 1, characterClass = 4, chosenMastery = 99 },
        }, "BadMastery")
        assert.is_nil(char)
    end)
end)
