-- @leb-regression-guard:main-skill-dropdown-hide-ailments
-- User-reported (2026-05-30): the "Main Skill" selector dropdown listed
-- auto-granted ailment / debuff sub-skills like "Bleed (from Puncture)",
-- "Shred Armour (from Puncture)", "Critical Vulnerability (from X)",
-- "Blind / Chill / Slow / Frailty (from X)" — clutter that isn't a
-- castable main skill.
--
-- These are trigger-granted socket groups created in CalcSetup (label
-- "<skill> (from <source>)", with group.triggeredOnHit set). They are
-- distinguished from real damage triggers by data.skills[id].baseFlags
-- .ailment. RefreshSkillSelectControls now skips a socket group when it is
-- BOTH trigger-granted (triggeredOnHit) AND an ailment — so manually-
-- equipped skills (no triggeredOnHit) and triggered *damage* skills (no
-- ailment flag) are never hidden. Hidden groups still contribute to Full
-- DPS; only the selector row is suppressed.
--
-- Because filtering shrinks the dropdown list, CalcsTab's "Active Skill"
-- onChange was switched from positional tableKeys(...)[index] to the
-- selected list item's value.val (the socketGroupList key set by
-- RefreshSkillSelectControls), so the index->skill_number mapping stays
-- correct regardless of filtering.
--
-- See REGRESSION_GUARDS.md "main-skill-dropdown-hide-ailments".

describe("MainSkillDropdownHideAilments", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local buildSrc, calcsTabSrc
    setup(function()
        buildSrc = readFile("Modules/Build.lua")
        calcsTabSrc = readFile("Classes/CalcsTab.lua")
        assert.is_not_nil(buildSrc, "must read Modules/Build.lua")
        assert.is_not_nil(calcsTabSrc, "must read Classes/CalcsTab.lua")
    end)

    -- ===== game-data anchor (anti-fabrication) =====
    it("ailment/debuff skills carry baseFlags.ailment in skills.json (the discriminator is real)", function()
        local skills = readFile("Data/skills.json")
        assert.is_not_nil(skills, "must read Data/skills.json")
        -- The user's reported clutter entries must all be ailment-flagged,
        -- else the filter would miss them. Spot-check the headline ones.
        for _, name in ipairs({ "Shred Armor", "Bleed", "Critical Vulnerability", "Blind", "Chill", "Slow", "Frailty" }) do
            local block = skills:match('"name": "' .. name .. '".-baseFlags".-}')
            assert.is_not_nil(block, "skills.json must define '" .. name .. "' with a baseFlags block")
            assert.is_truthy(block:find('"ailment": true', 1, true),
                "'" .. name .. "' must have baseFlags.ailment = true for the dropdown filter to catch it")
        end
    end)

    -- ===== filter logic =====
    it("RefreshSkillSelectControls carries the guard marker and skips granted ailments", function()
        local startIdx = buildSrc:find("function buildMode:RefreshSkillSelectControls", 1, true)
        assert.is_not_nil(startIdx, "RefreshSkillSelectControls must exist")
        local nextFn = buildSrc:find("\nfunction buildMode:", startIdx + 1)
        local body = buildSrc:sub(startIdx, nextFn or #buildSrc)

        assert.is_truthy(body:find("@leb%-regression%-guard:main%-skill%-dropdown%-hide%-ailments", 1, false),
            "RefreshSkillSelectControls must carry the guard marker")
        -- Filter must gate on BOTH triggeredOnHit AND baseFlags.ailment.
        assert.is_truthy(body:find("triggeredOnHit", 1, true),
            "filter must require the group be trigger-granted (triggeredOnHit)")
        assert.is_truthy(body:find("baseFlags", 1, true) and body:find("ailment", 1, true),
            "filter must check data.skills[id].baseFlags.ailment")
        -- The insert must be guarded by the not-ailment condition. (As of the
        -- fulldps-fold-same-skill-cycle change the gate also ORs in hideSelfTrigger,
        -- and hide-timer-trigger-duplicate added hideTimerDuplicate, so accept the
        -- original form or ANY combined `not (hideAilment or <other hide gates>)`
        -- -- pattern, not literal, so future gate additions don't re-stale this.)
        assert.is_truthy(
            body:find("if not hideAilment then", 1, true) or body:find("not %(hideAilment or [%w_ ]+%)"),
            "the list insert must be gated on hideAilment (optionally combined with other hide gates)")
    end)

    it("CalcsTab Active Skill onChange maps via value.val (filter-safe), not positional tableKeys", function()
        assert.is_truthy(calcsTabSrc:find("self.input.skill_number = value.val", 1, true),
            "Calcs Active Skill onChange must map via value.val")
        assert.falsy(calcsTabSrc:find("skill_number = tableKeys(self.build.skillsTab.socketGroupList)[index]", 1, true),
            "the fragile positional tableKeys(...)[index] mapping must be gone")
    end)

    -- ===== behavioral: real build, filter excludes a granted ailment =====
    it("a trigger-granted ailment group is excluded from the Main Skill dropdown list", function()
        newBuild()
        -- Find an ailment skill id from the loaded skill data.
        local ailmentId
        for id, sk in pairs(data.skills) do
            if sk.baseFlags and sk.baseFlags.ailment and not sk.baseFlags.minion then
                ailmentId = id
                break
            end
        end
        assert.is_not_nil(ailmentId, "data.skills must contain at least one ailment skill")

        -- Inject ONLY a fake trigger-granted ailment group. After the filter
        -- excludes it the list is empty, so RefreshSkillSelectControls takes
        -- its safe "<No skills added yet>" branch (no displaySkillList access)
        -- — keeping the test independent of the selected group's internals.
        local sgl = build.skillsTab.socketGroupList
        wipeTable(sgl)
        local ailmentKey = 999
        sgl[ailmentKey] = { displayLabel = "FakeAilment (from X)", triggeredOnHit = 12345, skillId = ailmentId }

        -- Minimal controls stub matching what RefreshSkillSelectControls touches.
        local controls = {
            mainSocketGroup = { list = {}, CheckDroppedWidth = function() end },
            mainSkillPart = {}, mainSkillMineCount = {}, mainSkillStageCount = {},
            mainSkillMinion = {}, mainSkillMinionSkill = {},
        }
        build:RefreshSkillSelectControls(controls, ailmentKey, "")

        local labels = {}
        for _, item in ipairs(controls.mainSocketGroup.list) do labels[item.label or ""] = true end
        assert.is_nil(labels["FakeAilment (from X)"],
            "the trigger-granted ailment group must NOT appear in the Main Skill dropdown list")
        -- The only group was an ailment, so the filtered list collapses to
        -- the placeholder — proof the ailment was actually filtered out.
        assert.is_truthy(labels["<No skills added yet>"],
            "with only an ailment group present, the filtered dropdown should show the empty placeholder")
    end)
end)
