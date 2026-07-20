-- @leb-regression-guard:pontifex-cremate-minion-data
-- PontifexCremate (Cremate) summons Burning Skeletons. Its skills.json minionList MUST
-- reference the minions.json KEY 'BurningSkeleton', NOT the raw in-game prefab name
-- 'SummonedBurningSkeleton'. They are the SAME minion (datamined game source leb_minion_mapping_v4
-- leb_key='BurningSkeleton' <-> matched_prefab='SummonedBurningSkeleton'; minion_stats.json
-- 'SummonedBurningSkeleton' = skillList ['Fireball'] / maxHealth 200 / actorName
-- 'Burning Skeleton', matching minions.json 'BurningSkeleton' EXACTLY).
--
-- BUG (pre-fix): minionList held 'SummonedBurningSkeleton', which is absent from
-- minions.json, so createMinionSkills (CalcActiveSkill.lua ~1346
-- `minion.minionData = env.data.minions[minionType]`) resolved nil and CRASHED at ~1476
-- (`attempt to index local 'minionData' (a nil value)`) for ANY build with PontifexCremate
-- enabled as an active skill -- createMinionSkills runs per-active-skill from
-- CalcPerform.lua:548, so it is NOT limited to the isolated single-skill probe.
--
-- See REGRESSION_GUARDS.md "pontifex-cremate-minion-data".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

describe("PontifexCremateMinionData #minion", function()
    before_each(function() newBuild() end)

    -- The core regression: a build running PontifexCremate must compute output WITHOUT error.
    it("builds output without crashing (minion type resolves to a minions.json entry)", function()
        build.skillsTab:SelSkill(1, "PontifexCremate")
        runCallback("OnFrame")
        build.buildFlag = true
        local ok, err = pcall(function()
            build.calcsTab:BuildOutput()
        end)
        assert.is_true(ok, "PontifexCremate build must not error: " .. tostring(err))
        -- and the summoned minion must have resolved to real minion data
        local env = build.calcsTab.mainEnv
        local minion = env and (env.minion or (env.player.mainSkill and env.player.mainSkill.minion))
        assert.is_not_nil(minion, "PontifexCremate must produce a minion")
        assert.are.equals("BurningSkeleton", minion.type, "minion type must be the minions.json key")
        assert.is_table(minion.minionData, "minion.minionData must resolve (non-nil) from minions.json")
    end)

    -- Data-layer guards: the loaded data must reference the correct key and the key must exist.
    it("skills.json minionList references the minions.json key, not the prefab", function()
        local skill = data.skills.PontifexCremate
        assert.is_table(skill, "PontifexCremate skill must exist")
        assert.is_table(skill.minionList)
        local joined = table.concat(skill.minionList, ",")
        assert.is_truthy(string.find(joined, "BurningSkeleton", 1, true),
            "minionList must contain 'BurningSkeleton'")
        assert.is_falsy(string.find(joined, "SummonedBurningSkeleton", 1, true),
            "minionList must NOT contain the raw prefab 'SummonedBurningSkeleton'")
        -- every listed minion type must resolve to a minions.json entry
        for _, mt in ipairs(skill.minionList) do
            assert.is_table(data.minions[mt], "minionList entry '" .. mt .. "' must exist in minions.json")
        end
    end)

    it("minions.json carries the BurningSkeleton entry (Fireball, life 200)", function()
        local m = data.minions.BurningSkeleton
        assert.is_table(m, "BurningSkeleton must exist in minions.json")
        assert.is_table(m.skillList)
        assert.is_truthy(string.find(table.concat(m.skillList, ","), "Fireball", 1, true),
            "BurningSkeleton must cast Fireball")
    end)

    it("skills.json carries the guard marker", function()
        local txt = readSource("Data/skills.json")
        assert.is_truthy(string.find(txt, "@leb-regression-guard:pontifex-cremate-minion-data", 1, true),
            "PontifexCremate docNote must carry the guard marker")
    end)
end)
