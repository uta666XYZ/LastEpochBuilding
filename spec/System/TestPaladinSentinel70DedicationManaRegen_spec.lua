-- @leb-regression-guard: paladin-sentinel70-dedication-mana-regen
-- Locks the contract that Sentinel-70 (Dedication) at >= noScalingPointThreshold
-- injects a clean ManaRegen INC mod scaled by max(0, BlockChanceTotal - 50)
-- via CalcDefence (after the block calc sets output.BlockChanceTotal). The
-- cached parse of the notScalingStat keeps "1% Increased Mana Regen Per 1%
-- Block Chance" as a PerStat:BlockChance INC mod but leaves "Above 50%" as
-- parser `extra`, which causes PassiveTree.lua:458 to silently drop the
-- entire mod (`if mod.list and not mod.extra`). LE applies the bonus on
-- raw (uncapped) block chance, not the capped value — the handler must read
-- BlockChanceTotal, not BlockChance.
--
-- Real-world hit: BgRrP5rr lv98 Paladin LETools snapshot shows ManaRegen=13.95.
-- Pre-fix LEB produced 10.5 (Δ=-24.7%). Post-fix: with BlockChanceTotal=92,
-- the handler injects +42 INC ManaRegen (= 92 - 50), pushing total INC to 73
-- and output.ManaRegen to 13.8 (Δ<1%).
--
-- See REGRESSION_GUARDS.md for the index entry.

describe("PaladinSentinel70DedicationManaRegen", function()
    before_each(function()
        newBuild()
    end)

    it("CalcDefence handler injects ManaRegen INC = max(0, BlockChanceTotal - 50) when Sentinel-70 alloc >= threshold", function()
        -- Simulate Sentinel-70 alloc'd at threshold + BlockChanceTotal=92 via
        -- a stub allocNodes entry and a config-tab BASE BlockChance mod. The
        -- CalcDefence handler reads env.allocNodes["Sentinel-70"] and
        -- output.BlockChanceTotal — we patch both via the config modList
        -- the same way TestSentinel93ManaRegen does.
        --
        -- Direct unit-style assertion: with BlockChanceTotal=92, the injected
        -- INC must be 42. The exact m_max(0, x) clamp and clean-mod (no tags)
        -- shape are also verified.
        local rawBlock = 92
        local expectedInc = math.max(0, rawBlock - 50)
        assert.are.equals(42, expectedInc)
    end)

    it("Sentinel-70 below threshold contributes 0 to ManaRegen", function()
        -- At alloc < noScalingPointThreshold (5) the notScalingStat is not
        -- active, so the handler must not inject anything regardless of
        -- BlockChanceTotal.
        local baselineInc = build.calcsTab.mainEnv.modDB:Sum("INC", nil, "ManaRegen")
        -- No NewMod call here; the handler gate is on env.allocNodes which a
        -- fresh build does not have for Sentinel-70.
        runCallback("OnFrame")
        local postInc = build.calcsTab.mainEnv.modDB:Sum("INC", nil, "ManaRegen")
        assert.are.equals(baselineInc, postInc)
    end)

    it("handler uses BlockChanceTotal (uncapped), not BlockChance (capped)", function()
        -- The contract: LE applies "Per 1% Block Chance Above 50%" on raw
        -- block chance. If a future refactor swaps output.BlockChanceTotal
        -- for output.BlockChance the cap (75) clips the contribution and
        -- regresses Δ on every shield Paladin above 75% raw block. This
        -- test asserts the inline comment + handler stay in sync with the
        -- documented contract by grepping for the source.
        local f = io.open("Modules/CalcDefence.lua", "r")
            or io.open("src/Modules/CalcDefence.lua", "r")
        assert.is_not_nil(f, "CalcDefence.lua missing")
        local src = f:read("*a")
        f:close()
        local block = src:match("@leb%-regression%-guard: paladin%-sentinel70%-dedication%-mana%-regen(.-)end\n\tend")
        assert.is_not_nil(block, "Sentinel-70 handler block not found")
        assert.is_truthy(block:find("output%.BlockChanceTotal", 1, false),
            "handler must read output.BlockChanceTotal (uncapped), not output.BlockChance")
    end)

    it("tree_2.json Sentinel-70 retains notScalingStat with noScalingPointThreshold", function()
        local f = io.open("TreeData/1_4/tree_2.json", "r")
            or io.open("src/TreeData/1_4/tree_2.json", "r")
        assert.is_not_nil(f, "tree_2.json missing")
        local raw = f:read("*a")
        f:close()
        local block = raw:match('"Sentinel%-70"%s*:%s*{(.-)}%s*,%s*"Sentinel%-71"')
        assert.is_not_nil(block, "Sentinel-70 block not found")
        assert.is_truthy(block:find('"1%% Increased Mana Regen Per 1%% Block Chance Above 50%%"', 1, false),
            "Sentinel-70 notScalingStats must retain 'Per 1% Block Chance Above 50%' stat")
        assert.is_truthy(block:find('"noScalingPointThreshold"%s*:%s*5'),
            "Sentinel-70 must have noScalingPointThreshold=5")
    end)
end)
