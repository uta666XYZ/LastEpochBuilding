-- @leb-regression-guard:config-sets-ui
-- Config sets UI (2026-05-29). LEB inherited the config-set BACKEND from PoB
-- (configSets / configSetOrderList / NewConfigSet / SetActiveConfigSet +
-- multi-set Save/Load) but had no UI to drive it, so it was effectively a
-- single locked config set. This ports PoB's ConfigSetListControl (a generic
-- planner UI — no LE/PoE game content) plus the ConfigTab set selector
-- (dropdown + "Manage..." button → popup) on top of the existing backend.
--
-- LE-relevance discipline (memory: feedback_no_poe_specific_in_leb): only
-- generic planner infrastructure crossed over. PoB-isms adapted, not
-- blind-copied:
--   * LEB ListControl / control constructors take FLAT (anchor, x, y, w, h,
--     ...) args, not PoB's (anchor, rect) form.
--   * Dirty flag is `configTab.build.modFlag` (LEB convention, cf. TreeTab),
--     not PoB's `configTab.modFlag` (absent in LEB).
--
-- This spec mixes behavioral checks (real build via newBuild()) with
-- source-structural checks (wiring shape), and smoke-tests that the control
-- actually instantiates headlessly.
--
-- See REGRESSION_GUARDS.md "config-sets-ui".

describe("ConfigSetsUI", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    -- ===== Behavioral: config-set backend the UI drives =====
    describe("backend behavior (real build)", function()
        before_each(function()
            newBuild()
        end)

        it("starts with a single Default config set", function()
            local ct = build.configTab
            assert.is_not_nil(ct, "build.configTab must exist")
            assert.are.equal(1, #ct.configSetOrderList, "fresh build has exactly one config set")
            assert.is_not_nil(ct.configSets[ct.activeConfigSetId], "active config set must exist")
        end)

        it("NewConfigSet adds a set with a fresh id and seeds default tables", function()
            local ct = build.configTab
            local set = ct:NewConfigSet()
            assert.is_not_nil(set, "NewConfigSet returns the new set")
            assert.is_not_nil(set.id, "new set has an id")
            assert.is_table(set.input, "new set has an input table")
            assert.is_table(set.placeholder, "new set has a placeholder table")
            assert.is_not_nil(ct.configSets[set.id], "new set is registered in configSets")
        end)

        it("SetActiveConfigSet switches the active set and re-points the input alias", function()
            local ct = build.configTab
            local set2 = ct:NewConfigSet()
            -- order list must include the new set for the dropdown to list it
            table.insert(ct.configSetOrderList, set2.id)

            ct:SetActiveConfigSet(set2.id)
            assert.are.equal(set2.id, ct.activeConfigSetId, "active set id switched")
            assert.are.equal(ct.configSets[set2.id].input, ct.input,
                "self.input alias must point at the active set's input table")
        end)

        it("config values are isolated between sets", function()
            local ct = build.configTab
            local set1 = ct.activeConfigSetId
            ct.input.__test_marker = "set1value"

            local set2 = ct:NewConfigSet()
            table.insert(ct.configSetOrderList, set2.id)
            ct:SetActiveConfigSet(set2.id)
            assert.is_nil(ct.input.__test_marker,
                "a fresh set must not see the previous set's input value")

            ct.input.__test_marker = "set2value"
            ct:SetActiveConfigSet(set1)
            assert.are.equal("set1value", ct.input.__test_marker,
                "switching back restores set 1's value (sets are isolated)")
        end)

        it("OpenConfigSetManagePopup instantiates ConfigSetListControl headlessly", function()
            local ct = build.configTab
            local ok, err = pcall(function() ct:OpenConfigSetManagePopup() end)
            assert.is_true(ok, "OpenConfigSetManagePopup must not error: " .. tostring(err))
            -- A popup should have been pushed; clean it up so state doesn't leak.
            if main and main.popups and #main.popups > 0 then
                main:ClosePopup()
            end
        end)
    end)

    -- ===== Structural: wiring shape =====
    describe("source wiring", function()
        local ctrlSrc, tabSrc
        setup(function()
            ctrlSrc = readFile("Classes/ConfigSetListControl.lua")
            tabSrc = readFile("Classes/ConfigTab.lua")
        end)

        it("ConfigSetListControl.lua exists and carries the guard marker", function()
            assert.is_not_nil(ctrlSrc, "Classes/ConfigSetListControl.lua must exist")
            assert.is_truthy(ctrlSrc:find("@leb%-regression%-guard:config%-sets%-ui", 1, false),
                "control file must carry the config-sets-ui guard marker")
        end)

        it("control is a ListControl subclass constructed with LEB flat args", function()
            assert.is_truthy(ctrlSrc:find('newClass("ConfigSetListControl", "ListControl"', 1, true),
                "must subclass ListControl")
            -- LEB flat ctor: self.ListControl(anchor, x, y, width, height, rowHeight, ...)
            assert.is_truthy(ctrlSrc:find("self.ListControl(anchor, x, y, width, height, 16,", 1, true),
                "must call ListControl with LEB flat args (anchor, x, y, width, height, rowHeight, ...)")
        end)

        it("control uses LEB dirty-flag convention (build.modFlag), not PoB configTab.modFlag", function()
            assert.is_truthy(ctrlSrc:find("self.configTab.build.modFlag = true", 1, true),
                "must set self.configTab.build.modFlag (LEB convention)")
            -- The PoB-ism `configTab.modFlag = true` (without `.build`) must NOT appear.
            assert.falsy(ctrlSrc:find("self.configTab.modFlag = true", 1, true),
                "must NOT use PoB's self.configTab.modFlag (absent in LEB)")
        end)

        it("control implements the ListControl override methods", function()
            for _, m in ipairs({ "RenameSet", "GetRowValue", "OnOrderChange", "OnSelClick", "OnSelDelete", "OnSelKeyDown" }) do
                assert.is_truthy(ctrlSrc:find("ConfigSetListClass:" .. m, 1, true),
                    "control must implement " .. m)
            end
        end)

        it("ConfigTab wires the set selector + Manage button + popup", function()
            assert.is_not_nil(tabSrc, "Classes/ConfigTab.lua must exist")
            assert.is_truthy(tabSrc:find("self.controls.setSelect", 1, true),
                "ConfigTab must create the setSelect dropdown")
            assert.is_truthy(tabSrc:find("self.controls.setManage", 1, true),
                "ConfigTab must create the Manage... button")
            assert.is_truthy(tabSrc:find("function ConfigTabClass:OpenConfigSetManagePopup", 1, true),
                "ConfigTab must define OpenConfigSetManagePopup")
            assert.is_truthy(tabSrc:find('new("ConfigSetListControl"', 1, true),
                "OpenConfigSetManagePopup must instantiate ConfigSetListControl")
        end)

        it("ConfigTab Draw populates the setSelect dropdown from configSetOrderList", function()
            assert.is_truthy(tabSrc:find("self.controls.setSelect:SetList(newSetList)", 1, true),
                "Draw must populate setSelect via SetList(newSetList)")
        end)

        it("setSelect switch handler calls SetActiveConfigSet", function()
            assert.is_truthy(tabSrc:find("self:SetActiveConfigSet(self.configSetOrderList[index])", 1, true),
                "setSelect onChange must switch the active set via SetActiveConfigSet")
        end)
    end)
end)
