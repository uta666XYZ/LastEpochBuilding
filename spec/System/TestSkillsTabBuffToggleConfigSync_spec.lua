-- @leb-regression-guard: skills-tab-buff-toggle-config-sync
-- Locks the two-way sync between the SkillsTab buff/form toggle and the
-- ConfigTab "condition<X>" checkbox for every skill mapped in
-- LE_WHILE_ACTIVE_BUFF_BY_TREE_ID.
--
-- Sync mechanism: SkillsTab's toggle reads from / writes to
-- build.configTab.input["condition" .. condName] for registry-mapped skills.
-- For this to round-trip cleanly:
--   1. Every condName in LE_WHILE_ACTIVE_BUFF_BY_TREE_ID must have a
--      matching `var = "condition" .. condName` entry of type "check" in
--      ConfigOptions.lua. Without it, ConfigTab.BuildModList silently
--      drops the input (it only iterates known varList entries) and the
--      Condition:<X> FLAG is never emitted -> CalcSetup gating fails.
--   2. SkillsTab.lua must reference both LE_WHILE_ACTIVE_BUFF_BY_TREE_ID
--      and build.configTab.input at the buff-toggle click site.
--
-- Why source-level grep instead of in-process exercise: simulating a UI
-- click on the SkillsTab toggle requires a full Build instance + cursor
-- events, which is heavier than the surface the guard protects. The pairing
-- between the registry and ConfigOptions is the only place this fix can
-- silently regress.

describe("SkillsTabBuffToggleConfigSync", function()
    -- (1) Registry <-> ConfigOptions pairing
    it("every LE_WHILE_ACTIVE_BUFF_BY_TREE_ID entry has a matching condition<X> ConfigOptions check", function()
        local registry = LE_WHILE_ACTIVE_BUFF_BY_TREE_ID
        assert.is_table(registry, "LE_WHILE_ACTIVE_BUFF_BY_TREE_ID must be defined in Global.lua")
        local f = io.open("Modules/ConfigOptions.lua", "r")
        assert.is_not_nil(f, "must be able to open ConfigOptions.lua")
        local text = f:read("*a")
        f:close()
        for treeId, condName in pairs(registry) do
            local var = "condition" .. condName
            -- Match `{ var = "conditionInWerebearForm", type = "check", ...`
            local pattern = 'var%s*=%s*"' .. var .. '"%s*,%s*type%s*=%s*"check"'
            assert.is_truthy(
                string.find(text, pattern),
                ("ConfigOptions.lua must define a check entry { var = %q, type = \"check\", ... } " ..
                 "for treeId %q (registry value %q) so the SkillsTab toggle can sync to it"):format(var, treeId, condName)
            )
        end
    end)

    -- (2) SkillsTab references both sides of the sync at the toggle site
    it("SkillsTab.lua buff toggle reads LE_WHILE_ACTIVE_BUFF_BY_TREE_ID and writes configTab.input", function()
        local f = io.open("Classes/SkillsTab.lua", "r")
        assert.is_not_nil(f, "must be able to open SkillsTab.lua")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(
            string.find(text, "LE_WHILE_ACTIVE_BUFF_BY_TREE_ID", 1, true),
            "SkillsTab.lua must read LE_WHILE_ACTIVE_BUFF_BY_TREE_ID at the buff toggle render site"
        )
        assert.is_truthy(
            string.find(text, "configTab.input", 1, true) or string.find(text, "configInput", 1, true),
            "SkillsTab.lua must write to build.configTab.input at the buff toggle click site"
        )
        assert.is_truthy(
            string.find(text, "configTab:BuildModList", 1, true),
            "SkillsTab.lua must rebuild ConfigTab mod list after flipping the synced input"
        )
    end)
end)
