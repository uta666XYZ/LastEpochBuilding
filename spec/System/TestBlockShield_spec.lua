-- @leb-regression-guard: block-requires-shield
-- Locks the contract that Block Chance / Block Effectiveness / Block Mitigation
-- are zero unless a Shield is equipped (or the BlockChanceConvertedToParryWithoutShield
-- / BlockWithoutShield flag is set). LE behaviour: dump.cs constant
-- `playerPropertyBlockChanceConvertedToParryWithoutShield` (=531) is the only
-- documented bypass; off-hand Catalyst / Quiver MUST NOT contribute block.
--
-- @leb-regression-guard: flame-ward-block-toggle
-- Locks the contract that Flame Ward (treeId fw3d) tree-node mods do NOT apply
-- by default — they must be gated on Config option `conditionHaveFlameWard`
-- (or equivalent Condition:HaveFlameWard flag). Reverting CalcSetup.lua's
-- whileActiveBuffByTreeId table or putting fw3d nodes back on the unconditional
-- node-list path immediately fails the snapshot diff for builds like Bakbr2Ne.
-- IMPORTANT: Flame Ward has SkillType.Buff set (skillTypeTags=131336), so the
-- gating MUST run regardless of the Buff branch — splitting the
-- buffSkillTreePrefixes loop into "if Buff then ... else cond ... end" is wrong
-- because Flame Ward enters the Buff branch and silently bypasses the condition.
-- The fw3d-7 Frostguard node alone leaks +800 Armour in Bakbr2Ne when this gate
-- is wrong. The snapshot-level coverage runs in TestBuilds_spec.lua "test all
-- builds"; this file pins the unit-level Block-Chance contract.
--
-- See REGRESSION_GUARDS.md for the index entries.

describe("BlockRequiresShield", function()
    before_each(function()
        newBuild()
    end)

    it("BlockChance is 0 with no shield even with +50% Block Chance mod", function()
        build.configTab.input.customMods = [[
        +50% Block Chance
        +1000 Block Effectiveness
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(0, build.calcsTab.calcsOutput.BlockChance)
        assert.are.equals(0, build.calcsTab.calcsOutput.BlockEffectiveness)
        assert.are.equals(0, build.calcsTab.calcsOutput.BlockMitigation)
        assert.are.equals(0, build.calcsTab.calcsOutput.AverageBlockChance)
    end)

    it("BlockChance applies with no shield when BlockWithoutShield flag is set", function()
        build.configTab.input.customMods = [[
        +50% Block Chance
        +1000 Block Effectiveness
        ]]
        build.configTab:BuildModList()
        -- Bypass the shield gate via the documented escape-hatch flag.
        build.configTab.modList:NewMod("BlockWithoutShield", "FLAG", true, "Test")
        runCallback("OnFrame")
        assert.is_true(build.calcsTab.calcsOutput.BlockChance > 0)
        assert.is_true(build.calcsTab.calcsOutput.BlockEffectiveness > 0)
    end)
end)
