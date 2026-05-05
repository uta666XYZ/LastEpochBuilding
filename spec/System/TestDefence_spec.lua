describe("TestDefence", function()
    before_each(function()
        newBuild()
    end)

    it("no armour max hits", function()
        -- Default enemy is Empowered Monolith Boss (leBossCategory defaultIndex=2, ~60% more damage)
        -- MaximumHitTaken = Life(110) / enemyDamageMult(1.6) = 68.75 -> 69
        for _, damageType in ipairs(DamageTypes) do
            assert.are.equals(69, round(build.calcsTab.calcsOutput[damageType .. "MaximumHitTaken"]))
        end
    end)

    it("armoured max hits", function()
        build.configTab.input.enemyLevel = 100
        build.configTab.input.customMods = [[
        +890 health
        +3100 to armour
        -2 Strength
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(1000, build.calcsTab.calcsOutput.Life)
        -- Default enemy is Empowered Monolith Boss (~60% more damage)
        -- Physical: 1000 / drMulti(armour ~49.5%) / enemyDamageMult(1.6) = 1236
        -- Non-physical: armour 70% effective -> drMulti lower -> 956
        assert.are.equals(1236, round(build.calcsTab.calcsOutput.PhysicalMaximumHitTaken))
        for _, damageType in ipairs(DamageTypes) do
            if damageType ~= "Physical" then
                assert.are.equals(956, round(build.calcsTab.calcsOutput[damageType .. "MaximumHitTaken"]))
            end
        end
    end)


    it("ward regen", function()
        build.configTab.input.customMods = [[
        +10 Ward per Second
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(10, build.calcsTab.calcsOutput.WardPerSecond)
        assert.are.equals(0, build.calcsTab.calcsOutput.WardDecayThreshold)
        assert.are.equals(0, build.calcsTab.calcsOutput.WardRetention)
        assert.are.equals(49, build.calcsTab.calcsOutput.Ward)
    end)

    it("ward regen and ward decay threshold", function()
        build.configTab.input.customMods = [[
        +10 Ward per Second
        +100 Ward Decay Threshold
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(10, build.calcsTab.calcsOutput.WardPerSecond)
        assert.are.equals(100, build.calcsTab.calcsOutput.WardDecayThreshold)
        assert.are.equals(0, build.calcsTab.calcsOutput.WardRetention)
        assert.are.equals(149, build.calcsTab.calcsOutput.Ward)
    end)

    it("ward regen and retention", function()
        build.configTab.input.customMods = [[
        +10 Ward per Second
        +100% Ward Retention
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(10, build.calcsTab.calcsOutput.WardPerSecond)
        assert.are.equals(0, build.calcsTab.calcsOutput.WardDecayThreshold)
        assert.are.equals(100, build.calcsTab.calcsOutput.WardRetention)
        assert.are.equals(74, build.calcsTab.calcsOutput.Ward)
    end)

    -- @leb-regression-guard:ward-retention-negative-clamp
    -- Game (ProtectionClass.Update RVA 0x234B8C0) clamps WardRetention at -90% before
    -- the (1 + 0.5*R) decay divisor. Without the clamp, R <= -200% drives the divisor
    -- to <= 0 and stable ward becomes non-finite. This spec pins the clamped result so
    -- a regression that drops the clamp is caught.
    it("ward retention clamped at -90% (negative retention)", function()
        build.configTab.input.customMods = [[
        +10 Ward per Second
        -200% Ward Retention
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(10, build.calcsTab.calcsOutput.WardPerSecond)
        assert.are.equals(-200, build.calcsTab.calcsOutput.WardRetention)
        -- With R clamped to -90%, divisor = 1 + 0.5*(-0.9) = 0.55
        -- W = (-0.2 + sqrt(0.04 + 0.0002*10*0.55)) / 0.0001 = ~27
        assert.are.equals(27, build.calcsTab.calcsOutput.Ward)
    end)
end)
