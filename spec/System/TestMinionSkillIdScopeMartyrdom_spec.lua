-- @leb-regression-guard:minion-skillid-scope-martyrdom
-- See REGRESSION_GUARDS.md "minion-skillid-scope-martyrdom" and
-- Validation provenance is retained in maintainer notes.

describe("MinionSkillIdScopeMartyrdom", function()
    it("CalcSetup.buildModListForNodeList exempts MinionModifier from SkillId strip", function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
        local text = f:read("*a")
        f:close()
        -- The exemption is a literal AND-clause on the strip-detection
        -- branch. Asserting on the textual form catches accidental
        -- removal during future refactors (e.g. when someone replaces
        -- the inline loop with a helper).
        assert.is_truthy(
            string.find(text, 'stripSkillId and mod%.name ~= "MinionModifier"'),
            'CalcSetup.lua buildModListForNodeList must guard the SkillId ' ..
            'strip with `stripSkillId and mod.name ~= "MinionModifier"` ' ..
            'so Dread Shade Martyrdom et al. stay scoped per skill.')
        -- Inline guard comment must also stay so any reader hitting
        -- the line understands why the AND-clause exists.
        assert.is_truthy(
            string.find(text, "@leb%-regression%-guard:minion%-skillid%-scope%-martyrdom"),
            'CalcSetup.lua must retain the @leb-regression-guard comment ' ..
            'next to the MinionModifier strip exemption.')
    end)
end)
