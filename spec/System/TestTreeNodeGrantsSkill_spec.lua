-- @leb-regression-guard:tree-node-grants-skill
-- Locks ④ of the Fire Aura DPS gap: a skill-tree node that GRANTS a continuous
-- DoT/aura skill absent from the loadout must have that skill injected into
-- env.player.activeSkillList with includeInFullDPS so calcFullDPS sums its
-- damage. LEB has no native pipeline for node-granted active skills, so without
-- this the granted aura's damage was missing from Full DPS entirely.
--
-- fw3d-12 "Fire Aura" (Flame Ward tree) grants the Fire Aura DoT. It only
-- exists while Flame Ward is active, so injection is gated on the node being
-- allocated AND Condition:HaveFlameWard (LE_WHILE_ACTIVE_BUFF_BY_TREE_ID).
-- The injected skill's skillModList receives the ①' Fire->Cold conversion and
-- the ② SkillName="Fire Aura"-tagged idol/passive INC mods.
--
-- Establishing observation (ShutFackUp lv85 Spellblade, conditionHaveFlameWard
-- forced on): Fire Aura appears in activeSkillList with includeInFullDPS=true
-- (source "TreeNodeGrant:fw3d-12"); its skillModList sums FireDamageConvertToCold
-- BASE = 100 (cfg) and contributes to FullDPS (was absent / 0 before). With
-- Flame Ward inactive (default) the build has NO Fire Aura skill.
--
-- Three coupled invariants:
--   (1) registry (Global.lua): LE_TREE_NODE_GRANTS_SKILL["fw3d-12"] == "FireAura".
--   (2) wiring (CalcSetup.lua): the injection loop consults the registry,
--       checks env.allocNodes + the buff condition, and flags the synthetic
--       socket group includeInFullDPS.
--   (3) behaviour: Flame Ward active => Fire Aura present & includeInFullDPS;
--       inactive => absent (no double count, no leak to other builds).
-- See REGRESSION_GUARDS.md > "tree-node-grants-skill".

describe("TreeNodeGrantsSkill", function()
    it("LE_TREE_NODE_GRANTS_SKILL maps fw3d-12 to FireAura", function()
        assert.is_table(LE_TREE_NODE_GRANTS_SKILL,
            "LE_TREE_NODE_GRANTS_SKILL must be defined in Global.lua")
        assert.are.equal("FireAura", LE_TREE_NODE_GRANTS_SKILL["fw3d-12"])
        local f = io.open("Data/Global.lua", "r")
        assert.is_not_nil(f, "must be able to open Global.lua")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(string.find(text, '%["fw3d%-12"%]%s*=%s*"FireAura"'),
            "Global.lua LE_TREE_NODE_GRANTS_SKILL must include fw3d-12 -> FireAura")
    end)

    it("CalcSetup injects node-granted skills with includeInFullDPS gated by the buff", function()
        local f = io.open("Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f, "must be able to open CalcSetup.lua")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(string.find(text, "LE_TREE_NODE_GRANTS_SKILL", 1, true),
            "CalcSetup must consult LE_TREE_NODE_GRANTS_SKILL")
        assert.is_truthy(string.find(text, "env.allocNodes", 1, true),
            "CalcSetup must check the node is allocated")
        assert.is_truthy(string.find(text, "LE_WHILE_ACTIVE_BUFF_BY_TREE_ID", 1, true),
            "CalcSetup must gate injection by the while-active buff condition")
        assert.is_truthy(string.find(text, "TreeNodeGrant:", 1, true),
            "CalcSetup must tag the synthetic group source TreeNodeGrant:<nodeId>")
    end)

    it("ShutFackUp injects Fire Aura into FullDPS only when Flame Ward is active", function()
        local xmlPath = "../spec/TestBuilds/1.4/ShutFackUp lv85 Spellblade.xml"
        local fh = io.open(xmlPath, "r")
        if not fh then
            pending("ShutFackUp build XML not present (spec/TestBuilds is gitignored)")
            return
        end
        local xml = fh:read("*a"); fh:close()

        local function fireAuraInFullDPS(build)
            local env = build.calcsTab.mainEnv
            for _, s in ipairs(env.player.activeSkillList) do
                local ge = s.activeEffect and s.activeEffect.grantedEffect
                if ge and ge.name == "Fire Aura" then
                    return s.socketGroup and s.socketGroup.includeInFullDPS or false, true
                end
            end
            return false, false
        end

        -- Default config: Flame Ward inactive -> no Fire Aura skill.
        loadBuildFromXML(xml)
        local _, presentOff = fireAuraInFullDPS(build)
        assert.is_false(presentOff,
            "Fire Aura must NOT be injected while Flame Ward is inactive (default)")

        -- Flame Ward active -> Fire Aura injected with includeInFullDPS.
        loadBuildFromXML(xml)
        build.configTab.input["conditionHaveFlameWard"] = true
        build.configTab:BuildModList()
        build.buildFlag = true
        build:OnFrame({})
        local incFDPS, presentOn = fireAuraInFullDPS(build)
        assert.is_true(presentOn,
            "Fire Aura must be injected while Flame Ward is active")
        assert.is_true(incFDPS,
            "the injected Fire Aura's socket group must be includeInFullDPS")
    end)

    -- @leb-regression-guard:tree-node-grant-aura-single-stack
    it("the injected Fire Aura aura is computed as a single stack (MaxStacks=1)", function()
        local xmlPath = "../spec/TestBuilds/1.4/ShutFackUp lv85 Spellblade.xml"
        local fh = io.open(xmlPath, "r")
        if not fh then
            pending("ShutFackUp build XML not present (spec/TestBuilds is gitignored)")
            return
        end
        local xml = fh:read("*a"); fh:close()
        local calcs = require("Modules/Calcs")

        loadBuildFromXML(xml)
        build.configTab.input["conditionHaveFlameWard"] = true
        build.configTab:BuildModList()
        build.buildFlag = true
        build:OnFrame({})
        local env = build.calcsTab.mainEnv
        local fa
        for _, s in ipairs(env.player.activeSkillList) do
            local ge = s.activeEffect and s.activeEffect.grantedEffect
            if ge and ge.name == "Fire Aura" then fa = s end
        end
        assert.is_not_nil(fa, "Fire Aura must be injected")
        assert.are.equal("TreeNodeGrant:fw3d-12", fa.socketGroup.source)
        env.player.mainSkill = fa
        calcs.perform(env)
        -- granted aura is a single refreshed instance, NOT cast at cast-speed:
        -- MaxStacks must be clamped to 1 (would be ~17 under Speed*Duration).
        assert.are.equal(1, env.player.output.MaxStacks,
            "tree-node-granted aura MaxStacks must be clamped to 1")
    end)
end)
