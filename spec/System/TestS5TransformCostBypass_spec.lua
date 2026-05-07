-- @leb-regression-guard: transform-cost-bypass
-- Locks the contract that LE Form/Transform abilities (Werebear, Spriggan,
-- Swarmblade, Reaper) skip CalcOffence's Mana/Rage/Soul cost calculation
-- entirely. In LE these are Mutators: the Form ability itself has no Mana
-- cost — entering Form swaps the player resource (mana→rage for Werebear /
-- Swarmblade, mana→nothing for Spriggan, mana→soul stacks for Reaper) and
-- the in-Form bar skills are auto-given child abilities not modeled in
-- LEB's skills.json. The bypass relies on TWO sites cooperating:
--
--   (1) DataProcess.lua mirrors baseFlags.transform → SkillType.Transform
--       (skills.json L8390 etc.: Form abilities have skillTypeTags=0 plus
--        baseFlags.transform=true, so without the mirror the Transform bit
--        never reaches activeSkill.skillTypes).
--   (2) CalcOffence.lua tests `not activeSkill.skillTypes[SkillType.Transform]`
--       to short-circuit the cost loop.
--
-- Removing either side reintroduces a phantom Mana cost on Form skills and
-- inflates the ManaCost diff vs LETools snapshots (which generate from a
-- Form-OFF / pre-transform state). Different mechanism from
-- form-tree-nodes-gated-by-condition (which gates skill-tree node MODS, not
-- the cost-calc bypass).
--
-- See REGRESSION_GUARDS.md "transform-cost-bypass".

describe("S5TransformCostBypass", function()

    describe("DataProcess maps baseFlags.transform -> SkillType.Transform", function()
        local source
        setup(function()
            local f = io.open("Modules/DataProcess.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/DataProcess.lua")
            source = f:read("*a")
            f:close()
        end)

        it("flagToType table contains transform = SkillType.Transform", function()
            -- Match `transform%s*=%s*SkillType.Transform` allowing whitespace
            local pat = "transform%s*=%s*SkillType%.Transform"
            assert.is_truthy(string.find(source, pat),
                "DataProcess.lua flagToType must map baseFlags.transform -> SkillType.Transform")
        end)

        it("regression-guard comment block is present", function()
            assert.is_truthy(string.find(source, "transform-cost-bypass", 1, true),
                "DataProcess.lua must keep the @leb-regression-guard comment so future edits trip review")
        end)
    end)

    describe("CalcOffence cost block is gated on `not SkillType.Transform`", function()
        local source
        setup(function()
            local f = io.open("Modules/CalcOffence.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/CalcOffence.lua")
            source = f:read("*a")
            f:close()
        end)

        it("cost-block guard tests activeSkill.skillTypes[SkillType.Transform]", function()
            -- The exact line is:
            --   if not skillModList:Flag(skillCfg, "HasNoCost") and not activeSkill.skillTypes[SkillType.Transform] then
            -- Match a relaxed pattern to survive whitespace/quote churn but lock
            -- the AND-clause structure.
            local pat = 'not%s+activeSkill%.skillTypes%[SkillType%.Transform%]'
            assert.is_truthy(string.find(source, pat),
                "CalcOffence.lua must gate the cost loop on `not activeSkill.skillTypes[SkillType.Transform]`")
        end)

        it("HasNoCost guard still co-exists (no regression of the other bypass)", function()
            local pat = '"HasNoCost"'
            assert.is_truthy(string.find(source, pat, 1, true),
                "CalcOffence.lua must keep the HasNoCost flag check alongside the Transform check")
        end)

        it("regression-guard comment block is present", function()
            assert.is_truthy(string.find(source, "transform-cost-bypass", 1, true),
                "CalcOffence.lua must keep the @leb-regression-guard comment so future edits trip review")
        end)
    end)

    describe("skills.json Form entries carry baseFlags.transform=true", function()
        local source
        setup(function()
            local f = io.open("Data/skills.json", "r")
            assert.is_not_nil(f, "must be able to open Data/skills.json")
            source = f:read("*a")
            f:close()
        end)

        local forms = { "WerebearForm", "SprigganForm", "ReaperForm" }
        for _, key in ipairs(forms) do
            it(("%s entry contains \"transform\": true in baseFlags"):format(key), function()
                -- Find the entry block and ensure "transform": true appears
                -- within it (use a coarse window after the key).
                local s = string.find(source, '"' .. key .. '"%s*:%s*{')
                assert.is_truthy(s, "skills.json must contain entry for " .. key)
                local window = string.sub(source, s, s + 4000)
                assert.is_truthy(string.find(window, '"transform"%s*:%s*true'),
                    key .. " entry must keep baseFlags.transform = true")
            end)
        end
    end)
end)
