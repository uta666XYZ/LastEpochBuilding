-- @leb-regression-guard: tree-tag-swap-determinism
-- Locks the contract that tree-driven damage-tag swaps are DETERMINISTIC:
--
-- (1) calcs.getTreeTagSwaps resolves a same-source collision (two allocated
--     nodes on one tree both producing a swap FROM the same damage type) in
--     favour of the LEXICALLY-LAST node id, independent of pairs() hash order.
--     Real case (YsSmiteVK): Smite with sm87r4-21 " Fire -> Lightning Damage"
--     and sm87r4-32 " Void Conversion" (source-less, source inferred from the
--     skill's intrinsic Fire tag) both write swaps[Fire]. The old
--     pairs(env.allocNodes) iteration made the winner flap per process (string
--     hash order is randomised per process): when Fire->Lightning won, Smite
--     lost its Void tag, the Void Knight Echo 10% MORE gate failed, and ~32
--     hit/DPS output keys shifted uniformly by x1.10 run-to-run.
--
-- (2) calcs.applyTreeTagSwaps applies every swap against the PRE-swap tag set
--     (two-phase), so chained swaps {A->B, B->C} never double-hop and the
--     result does not depend on swaps-table iteration order.
--
-- See REGRESSION_GUARDS.md > "tree-tag-swap-determinism".

describe("TreeTagSwapDeterminism", function()
    local calcs
    before_each(function()
        newBuild()
        calcs = build.calcsTab.calcs
    end)

    local FIRE = SkillType.Fire
    local LIGHTNING = SkillType.Lightning
    local VOID = SkillType.Void
    local COLD = SkillType.Cold

    -- Mirror of the Smite collision: node -21 explicit Fire->Lightning,
    -- node -32 source-less Void Conversion inferring Fire from the skill.
    local function makeEnv(nodes)
        return { allocNodes = nodes }
    end
    local fireSkill = { skillTypeTags = FIRE, fakeTags = 0 }

    it("same-source collision resolves to the lexically-last node id", function()
        local env = makeEnv({
            ["t1-21"] = { stats = { " Fire -> Lightning Damage" } },
            ["t1-32"] = { stats = { " Void Conversion" } },
        })
        local swaps = calcs.getTreeTagSwaps(env, "t1", fireSkill)
        -- t1-32 sorts after t1-21, so the Void Conversion must win the
        -- swaps[Fire] slot -- matching the snapshot corpus (VK Void Smite).
        assert.are.equal(VOID, swaps[FIRE])
    end)

    it("collision winner follows node id order, not stat shape", function()
        -- Same two stats with the node ids exchanged: now the explicit
        -- Fire->Lightning node sorts last and must win.
        local env = makeEnv({
            ["t1-21"] = { stats = { " Void Conversion" } },
            ["t1-32"] = { stats = { " Fire -> Lightning Damage" } },
        })
        local swaps = calcs.getTreeTagSwaps(env, "t1", fireSkill)
        assert.are.equal(LIGHTNING, swaps[FIRE])
    end)

    it("applyTreeTagSwaps decides chained swaps against the pre-swap set", function()
        -- Chain {Fire->Lightning, Lightning->Cold} on a skill that has BOTH
        -- source tags. Two-phase contract: each swap sees the ORIGINAL set, so
        -- Fire is removed, Lightning stays (removed as a source but re-added as
        -- Fire's destination), Cold is added. The old incremental loop produced
        -- {Cold} or {Lightning, Cold} depending on pairs() order.
        local swaps = { [FIRE] = LIGHTNING, [LIGHTNING] = COLD }
        local types = { [FIRE] = true, [LIGHTNING] = true }
        local out, kw = calcs.applyTreeTagSwaps(swaps, types, bit.bor(FIRE, LIGHTNING), false)
        assert.is_nil(out[FIRE])
        assert.is_true(out[LIGHTNING])
        assert.is_true(out[COLD])
        assert.are.equal(bit.bor(LIGHTNING, COLD), bit.band(kw, bit.bor(FIRE, LIGHTNING, COLD)))
    end)

    it("swap with absent source is a no-op", function()
        local swaps = { [COLD] = VOID }
        local types = { [FIRE] = true }
        local out, kw = calcs.applyTreeTagSwaps(swaps, types, FIRE, false)
        assert.is_true(out[FIRE])
        assert.is_nil(out[VOID])
        assert.are.equal(FIRE, kw)
    end)
end)
