-- @leb-regression-guard:config-enemy-marked-for-death
-- Marked for Death (AilmentID 17, isCurse, 8s, maxInstances 1) is a Curse that
-- lowers ALL of the enemy's resistances by 25. Datamine authority
-- (ailments_v3: MarkedForDeath buff addedValue -0.25, property 30 = resistances,
-- description "Your resistances are 25% lower"), corroborated by the in-game
-- tree_3 tooltip: "Marked for Death is a Curse that reduces all resistances by
-- 25%. It cannot stack."
--
-- Bug: LEB parsed only the APPLICATION of Marked for Death (MarkedForDeathChance
-- / EnemyMarkedForDeathDuration) but never modelled its resistance-reduction
-- EFFECT on the target -- so a marked enemy took the same damage as an unmarked
-- one (silent UNDER-count for MfD/curse builds; surfaced by an in-game
-- abomination capture whose hits carried an unexplained state multiplier).
--
-- Fix: conditionEnemyMarkedForDeath config toggle (default OFF => corpus-neutral,
-- no snapshot, no regen) applies -25 BASE to every <Type>Resist (all 7
-- DamageTypes incl. Physical, mirroring the enemy-resistance config loop) and
-- flags the enemy as Cursed (MfD isCurse) + MarkedForDeath. Static 100%-uptime
-- toggle: in-game MfD is chance/duration-gated, so it is opt-in.
-- See REGRESSION_GUARDS.md "config-enemy-marked-for-death".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

describe("EnemyMarkedForDeath", function()
    local configText
    setup(function()
        newBuild()
        configText = readSource("Modules/ConfigOptions.lua")
    end)

    it("inline guard marker present in ConfigOptions.lua", function()
        assert.is_truthy(string.find(configText, "config-enemy-marked-for-death", 1, true))
    end)

    it("ConfigOptions adds conditionEnemyMarkedForDeath applying -25 resist + Cursed/MarkedForDeath flags", function()
        assert.is_truthy(string.find(configText, 'var = "conditionEnemyMarkedForDeath"', 1, true))
        assert.is_truthy(string.find(configText, 'NewMod("Condition:MarkedForDeath", "FLAG", true', 1, true))
        assert.is_truthy(string.find(configText, 'NewMod("Condition:Cursed", "FLAG", true', 1, true))
        -- loops over DamageTypes applying -25 BASE to <Type>Resist
        assert.is_truthy(string.find(configText, 'damageType %.%. "Resist", "BASE", %-25'),
            "must apply -25 BASE to each <Type>Resist")
        assert.is_truthy(string.find(configText, 'for _, damageType in ipairs%(DamageTypes%) do'),
            "must iterate all DamageTypes")
    end)

    -- Behavioral (build-independent): toggling the config lowers EVERY enemy
    -- resistance by exactly 25 and sets both condition flags; default OFF leaves
    -- them untouched (corpus-neutral).
    local function enemyDB()
        local env = build.calcsTab.mainEnv
        return env and env.enemyDB
    end
    local function rebuild()
        build.configTab:BuildModList()
        build.buildFlag = true
        build.calcsTab:BuildOutput()
    end

    it("default OFF leaves enemy resistances and flags untouched (corpus-neutral)", function()
        newBuild()
        build.configTab.input.conditionEnemyMarkedForDeath = false
        rebuild()
        local edb = enemyDB()
        assert.is_not_nil(edb, "enemy modDB must exist")
        local marked = edb:Flag(nil, "Condition:MarkedForDeath")
        assert.is_falsy(marked)
    end)

    it("ON lowers all 7 resistances by exactly 25 and flags Cursed + MarkedForDeath", function()
        newBuild()
        -- baseline resists (default config)
        rebuild()
        local edb = enemyDB()
        local base = {}
        for _, dt in ipairs(DamageTypes) do base[dt] = edb:Sum("BASE", nil, dt .. "Resist") end

        build.configTab.input.conditionEnemyMarkedForDeath = true
        rebuild()
        edb = enemyDB()
        for _, dt in ipairs(DamageTypes) do
            local after = edb:Sum("BASE", nil, dt .. "Resist")
            assert.is_near(base[dt] - 25, after, 1e-6,
                dt .. "Resist must drop by exactly 25 (was " .. tostring(base[dt]) .. ")")
        end
        assert.is_true(edb:Flag(nil, "Condition:MarkedForDeath") == true, "MarkedForDeath flag set")
        assert.is_true(edb:Flag(nil, "Condition:Cursed") == true, "Cursed flag set (MfD isCurse)")
    end)
end)
