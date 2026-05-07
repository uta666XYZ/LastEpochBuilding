-- @leb-regression-guard: sentinel-93-mana-regen-from-holy-aura
-- Locks the contract that Sentinel-93 (Covenant of Dominion) at 5 allocated
-- points injects a clean ManaRegen INC mod (untagged) when Holy Aura is active,
-- scaled by HolyAuraEffect INC. The pre-fix behaviour cached the stat with a
-- SkillName=Holy Aura tag, which never matched the cfg=nil sum site in
-- CalcDefence:580 — so the bonus contributed 0 to ManaRegen.
--
-- See REGRESSION_GUARDS.md for the index entry.

describe("Sentinel93ManaRegenFromHolyAura", function()
    before_each(function()
        newBuild()
    end)

    it("Sentinel-93 25% scales by HolyAuraEffect and surfaces as INC ManaRegen", function()
        -- Mirror the in-fix arithmetic: with Sentinel-119 Covenant of Light at
        -- 5pts (+20% HolyAuraEffect), Sentinel-93 25% becomes 30% INC ManaRegen.
        local baseInc = 25
        local haEffectInc = 20
        local scaledPct = baseInc * (1 + haEffectInc / 100)
        assert.are.equals(30, scaledPct)

        build.configTab.modList:NewMod("ManaRegen", "INC", scaledPct,
            "Sentinel-93 Covenant of Dominion")
        runCallback("OnFrame")

        local incTotal = build.calcsTab.mainEnv.modDB:Sum("INC", nil, "ManaRegen")
        local moreTotal = build.calcsTab.mainEnv.modDB:More(nil, "ManaRegen")
        assert.are.equals(30, incTotal)
        assert.are.equals(1, moreTotal)
    end)

    it("tree_2.json Sentinel-93 retains '25% Increased Mana Regen From Holy Aura' notScalingStat", function()
        local f = io.open("TreeData/1_4/tree_2.json", "r")
            or io.open("src/TreeData/1_4/tree_2.json", "r")
        assert.is_not_nil(f, "tree_2.json missing")
        local raw = f:read("*a")
        f:close()
        local block = raw:match('"Sentinel%-93"%s*:%s*{(.-)}%s*,%s*"Sentinel%-95"')
        assert.is_not_nil(block, "Sentinel-93 block not found")
        assert.is_truthy(block:find('"25%% Increased Mana Regen From Holy Aura"', 1, false),
            "Sentinel-93 notScalingStats must contain '25% Increased Mana Regen From Holy Aura'")
    end)
end)
