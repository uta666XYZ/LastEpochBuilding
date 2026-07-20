-- @leb-regression-guard: notscaling-health-regen-per-vitality
-- Locks that the Acolyte-39 "Bed of Souls" notScalingStats string
--   "2% Increased Health Regen per Vitality"
-- parses end-to-end into a single INC LifeRegen mod, value 2, carrying a
-- PerStat tag scoped to Vitality (stat = "Vit").
--
-- Evidence (datamined game source extracted/passives_raw.json, Acolyte node id 39
-- "Bed of Souls", prefab "Lich Vitality"):
--   stats[2] = { text = "Increased Health Regen per Vitality", value = "2%",
--                noScaling = 1, property = 54 }
--   noScalingPointThreshold = 5
-- i.e. once >= 5 points are allocated the node grants a one-time
-- "+2% Increased Health Regen per Vitality" bonus (not per-point scaling).
--
-- This is NOT a dedicated-fix node: the value is produced by two generic
-- ModParser mechanisms acting together --
--   * modNameList "health regen" -> "LifeRegen" (INC via the "increased" form)
--   * the generic per-Attribute loop emitting "per vitality" -> PerStat:Vit
-- and applied once at threshold by PassiveTree.lua (notScalingStats /
-- noScalingPointThreshold handling). The spec exists to PIN that the
-- combined parse keeps producing the PerStat:Vit-tagged INC LifeRegen mod,
-- so a future ModParser refactor cannot silently drop the per-attribute tag
-- (which would zero out the node's contribution).
--
-- See REGRESSION_GUARDS.md "notscaling-health-regen-per-vitality".

describe("NotScalingHealthRegenPerVitality", function()
    before_each(function()
        newBuild()
    end)

    it("Bed of Souls notScaling string -> INC 2 LifeRegen PerStat:Vit", function()
        build.configTab.input.customMods = "2% Increased Health Regen per Vitality"
        build.configTab:BuildModList()
        runCallback("OnFrame")
        local ml = build.configTab.modList

        local found
        for _, m in ipairs(ml) do
            if m.name == "LifeRegen" and m.type == "INC" then
                found = m
                break
            end
        end
        assert.is_not_nil(found, "must produce an INC LifeRegen mod")
        assert.are.equals(2, found.value, "INC value must be 2 (per Vitality)")

        local hasPerVit = false
        for ti = 1, #found do
            local t = found[ti]
            if t.type == "PerStat" and t.stat == "Vit" then
                hasPerVit = true
            end
        end
        assert.is_true(hasPerVit, "INC LifeRegen mod must carry a PerStat tag scoped to Vitality (stat = Vit)")
    end)
end)
