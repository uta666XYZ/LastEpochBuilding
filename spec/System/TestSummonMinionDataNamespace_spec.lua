-- @leb-regression-guard:summon-minion-data-namespace
-- SummonIllusoryTree (Summon Illusory Tree) and SummonMercenary (Recruit Mercenary) each
-- summon a minion. Their skills.json minionList MUST reference the minions.json KEY, NOT the
-- raw in-game display/prefab name:
--   * SummonIllusoryTree: key 'IllusoryTree'  (NOT display name 'Illusory Tree' with a space)
--   * SummonMercenary:    key 'Mercenary'     (NOT prefab name  'Summoned Mercenary')
-- Each pair is the SAME minion (datamined game source):
--   * minion_stats.json 'Illusory Tree' = maxHealth 100 / skillList [] -> minions.json
--     'IllusoryTree' (life '100', empty skillList) EXACTLY.
--   * leb_minion_mapping_v4.json leb_key='Mercenary' <-> matched_prefab='Summoned Mercenary'
--     (name-match, bundle=player, actorType=Heavy, confidence=high); minion_stats.json
--     'Summoned Mercenary' maxHealth 400 -> minions.json 'Mercenary' (life '400',
--     skillList ['Crossbow Bolt']) EXACTLY.
--
-- BUG (pre-fix): minionList held the display/prefab name, which is absent from minions.json,
-- so createMinionSkills (CalcActiveSkill.lua ~1346
-- `minion.minionData = env.data.minions[minionType]`) resolved nil and CRASHED at ~1476
-- (`attempt to index local 'minionData' (a nil value)`) for ANY build with either skill
-- enabled as an active skill -- createMinionSkills runs per-active-skill from
-- CalcPerform.lua:548, so it is NOT limited to the isolated single-skill probe.
--
-- This is the SAME namespace-gap bug fixed for PontifexCremate (BurningSkeleton).
-- See REGRESSION_GUARDS.md "summon-minion-data-namespace".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

-- (skillId, minionKey, badName) tuples driving the parameterised assertions.
local CASES = {
    { skill = "SummonIllusoryTree", key = "IllusoryTree", bad = "Illusory Tree" },
    { skill = "SummonMercenary",    key = "Mercenary",    bad = "Summoned Mercenary" },
}

describe("SummonMinionDataNamespace #minion", function()
    before_each(function() newBuild() end)

    for _, c in ipairs(CASES) do
        -- The core regression: a build running the skill must compute output WITHOUT error.
        it(c.skill .. " builds output without crashing (minion resolves to a minions.json entry)", function()
            build.skillsTab:SelSkill(1, c.skill)
            runCallback("OnFrame")
            build.buildFlag = true
            local ok, err = pcall(function()
                build.calcsTab:BuildOutput()
            end)
            assert.is_true(ok, c.skill .. " build must not error: " .. tostring(err))
            local env = build.calcsTab.mainEnv
            local minion = env and (env.minion or (env.player.mainSkill and env.player.mainSkill.minion))
            assert.is_not_nil(minion, c.skill .. " must produce a minion")
            assert.are.equals(c.key, minion.type, "minion type must be the minions.json key")
            assert.is_table(minion.minionData, "minion.minionData must resolve (non-nil) from minions.json")
        end)

        -- Data-layer guard: the loaded data must reference the correct key, not the display/prefab name.
        it(c.skill .. " minionList references the minions.json key, not the display/prefab name", function()
            local skill = data.skills[c.skill]
            assert.is_table(skill, c.skill .. " skill must exist")
            assert.is_table(skill.minionList)
            local joined = table.concat(skill.minionList, ",")
            assert.is_truthy(string.find(joined, c.key, 1, true),
                "minionList must contain '" .. c.key .. "'")
            assert.is_falsy(string.find(joined, c.bad, 1, true),
                "minionList must NOT contain the raw display/prefab name '" .. c.bad .. "'")
            -- every listed minion type must resolve to a minions.json entry
            for _, mt in ipairs(skill.minionList) do
                assert.is_table(data.minions[mt], "minionList entry '" .. mt .. "' must exist in minions.json")
            end
        end)
    end

    it("minions.json carries the target entries", function()
        assert.is_table(data.minions.IllusoryTree, "IllusoryTree must exist in minions.json")
        assert.is_table(data.minions.Mercenary, "Mercenary must exist in minions.json")
    end)

    it("skills.json carries the guard marker", function()
        local txt = readSource("Data/skills.json")
        assert.is_truthy(string.find(txt, "@leb-regression-guard:summon-minion-data-namespace", 1, true),
            "Summon* docNotes must carry the guard marker")
    end)
end)
