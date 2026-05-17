-- @leb-regression-guard: letools-import-form-condition-autoset
-- Locks the contract for ImportTabClass:AutoSetConfigFromAbilities:
--   * Druid form skills (Werebear/Swarmblade/Spriggan) auto-set the
--     corresponding `conditionIn*Form=true` Config flag at import time.
--   * Beastmaster companion-summon skills count toward `multiplierCompanion`
--     and set `conditionHaveCompanion=true`.
--
-- Regression history this guard prevents:
--   * Without these auto-sets LE planner "in-combat" stat display and LEB's
--     out-of-combat default diverge by hundreds of points across
--     armor/resist/life/mana/dodge on Druid/Beastmaster builds. Verified on
--     QeY7m5Xq lv97 Druid (single `conditionInWerebearForm=true` closes
--     14+ stat drifts) and QJW0qO5a lv100 Beastmaster (`multiplierCompanion=1`
--     closes the armor -380 drift to -59).
--
-- See REGRESSION_GUARDS.md "letools-import-form-condition-autoset".

describe("LEToolsImportFormAutoset", function()
    local ImportTab
    before_each(function()
        newBuild()
        ImportTab = build.importTab
    end)

    it("sets conditionInWerebearForm when Werebear Form is in abilities", function()
        ImportTab:AutoSetConfigFromAbilities({
            abilities = { "Werebear Form", "Rampage" },
            ascendancy = "Druid",
        })
        assert.is_true(build.configTab.input.conditionInWerebearForm)
    end)

    it("sets conditionInSwarmbladeForm and conditionInSprigganForm", function()
        ImportTab:AutoSetConfigFromAbilities({
            abilities = { "Swarmblade Form", "Spriggan Form" },
            ascendancy = "Druid",
        })
        assert.is_true(build.configTab.input.conditionInSwarmbladeForm)
        assert.is_true(build.configTab.input.conditionInSprigganForm)
    end)

    it("counts Beastmaster companion summons into multiplierCompanion", function()
        ImportTab:AutoSetConfigFromAbilities({
            abilities = { "Summon Wolf", "Summon Sabertooth", "Warcry" },
            ascendancy = "Beastmaster",
        })
        assert.are.equal(2, build.configTab.input.multiplierCompanion)
        assert.is_true(build.configTab.input.conditionHaveCompanion)
    end)

    it("does not set multiplierCompanion for non-Beastmaster classes", function()
        ImportTab:AutoSetConfigFromAbilities({
            abilities = { "Summon Wolf" },
            ascendancy = "Druid",
        })
        assert.is_nil(build.configTab.input.multiplierCompanion)
    end)

    it("does not set Form flags for non-Druid classes (Form skill not always active)", function()
        ImportTab:AutoSetConfigFromAbilities({
            abilities = { "Spriggan Form", "Summon Wolf" },
            ascendancy = "Beastmaster",
        })
        assert.is_nil(build.configTab.input.conditionInSprigganForm)
    end)

    it("is a no-op when no relevant abilities are present", function()
        ImportTab:AutoSetConfigFromAbilities({
            abilities = { "Hammer Throw", "Warpath" },
            ascendancy = "Paladin",
        })
        assert.is_nil(build.configTab.input.conditionInWerebearForm)
        assert.is_nil(build.configTab.input.multiplierCompanion)
    end)

    it("handles missing charData gracefully", function()
        assert.has_no.errors(function()
            ImportTab:AutoSetConfigFromAbilities({})
            ImportTab:AutoSetConfigFromAbilities({ abilities = nil })
        end)
    end)
end)
