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

describe("FlameWardTreeGate", function()
    -- @leb-regression-guard: flame-ward-block-toggle
    -- Direct integration check: load Bakbr2Ne (allocates fw3d-7 Frostguard +200
    -- Armor x4 = +800, plus Flame Ward as a socket group with SkillType.Buff)
    -- and assert Armour stays in the LE-aligned range. Reverting the gate to
    -- the old `if Buff then ... else condName ... end` shape immediately bumps
    -- Armour from ~790 to ~1926 because the SkillType.Buff branch bypasses the
    -- Condition:HaveFlameWard gate.

    it("Bakbr2Ne Armour does not include fw3d tree-node leak when Flame Ward is inactive", function()
        local f = io.open("../spec/TestBuilds/1.4/Bakbr2Ne lv86 Sorcerer.xml", "r")
        assert(f, "Bakbr2Ne XML fixture missing")
        local xml = f:read("*a")
        f:close()
        loadBuildFromXML(xml, "Bakbr2Ne lv86 Sorcerer")
        runCallback("OnFrame")
        local armour = build.calcsTab.calcsOutput.Armour or 0
        -- Threshold: 1500 lies safely between the LE-aligned value (~790) and
        -- the broken value (~1926). Flame Ward fw3d-7 alone contributes +800
        -- BASE so even partial regressions of the gate cross this line.
        assert.is_true(armour < 1500,
            ("Armour=%s exceeds 1500; fw3d tree-node leak suspected"):format(tostring(armour)))
    end)
end)
