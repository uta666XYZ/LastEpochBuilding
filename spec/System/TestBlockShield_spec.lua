-- @leb-regression-guard: game-faithful-block-no-shield-gate
-- Locks the game-faithful contract: LE has NO automatic shield gate on Block
-- Chance / Block Effectiveness / Block Mitigation. Verified via PyGhidra
-- decompile of GameAssembly.dll (Last Epoch 1.4) at
-- LE_datamining/extracted/block_decompile.txt:
--   * PrecalculatedStatsHolder.blockChanceForCharacterSheet (RVA 0x2344F70)
--     returns min(blockChance, maximumBlockChance) gated only on
--     blockConversion == None — no shield/off-hand reference.
--   * PrecalculatedStatsHolder.GetBlockChance (RVA 0x2344F00) returns
--     min(blockChance + extra, maximumBlockChance) unconditionally.
--   * playerPropertyBlockChanceConvertedToParryWithoutShield (=531) is a
--     mod-driven flag on CharacterMutator that sets blockConversion = Parry,
--     NOT an automatic gate.
-- Therefore LEB must accumulate Block stats from item / passive mods
-- unconditionally. Reverting to a "no-shield → zero block" branch is rejected
-- by these specs.
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

describe("BlockGameFaithful", function()
    before_each(function()
        newBuild()
    end)

    it("BlockChance accumulates from mods with no shield (game-faithful)", function()
        build.configTab.input.customMods = [[
        +50% Block Chance
        +1000 Block Effectiveness
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        -- LE's PrecalculatedStatsHolder.GetBlockChance returns min(blockChance + extra,
        -- maximumBlockChance) regardless of off-hand slot — LEB must surface the mods.
        assert.is_true(build.calcsTab.calcsOutput.BlockChance > 0,
            "BlockChance should be > 0 with +50% Block Chance even without a shield")
        assert.is_true(build.calcsTab.calcsOutput.BlockEffectiveness > 0,
            "BlockEffectiveness should be > 0 with +1000 Block Effectiveness even without a shield")
    end)

    it("BlockChanceTotal is 0 (not nil) when no block mods are present", function()
        -- letools-diff cross-build coverage requires BlockChanceTotal to always be set;
        -- with no mods the unconditional block calc writes 0, never nil.
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(0, build.calcsTab.calcsOutput.BlockChanceTotal)
    end)

    it("Bakbr2Ne-style no-mod build still produces BlockChance = 0 naturally", function()
        -- Sanity: with no block mods anywhere, the natural sum is zero — no special
        -- shield gate needed (LE does the same).
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.are.equals(0, build.calcsTab.calcsOutput.BlockChance)
        assert.are.equals(0, build.calcsTab.calcsOutput.BlockEffectiveness)
    end)

    it("LifeOnBlock / ManaOnBlock accumulate from mods unconditionally", function()
        -- LE applies Life/Mana Gained on Block on the block trigger; the trigger
        -- has no shield prerequisite (see PrecalculatedStatsHolder above).
        build.configTab.input.customMods = [[
        50 Health Gained on Block
        25 Mana Gained on Block
        ]]
        build.configTab:BuildModList()
        runCallback("OnFrame")
        assert.is_true(build.calcsTab.calcsOutput.LifeOnBlock > 0,
            "LifeOnBlock should be > 0 with 50 Health Gained on Block mod")
        assert.is_true(build.calcsTab.calcsOutput.ManaOnBlock > 0,
            "ManaOnBlock should be > 0 with 25 Mana Gained on Block mod")
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
        if not f then
            pending("Bakbr2Ne XML fixture missing in this worktree; covered in determined-hawking worktree")
            return
        end
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
