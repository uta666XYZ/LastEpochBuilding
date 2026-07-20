-- @leb-regression-guard:minion-bucket-evalmod-perstat
-- Locks the contract that the CalcDefence MinionModifier bucket evaluates
-- inner mods through ModStore:EvalMod, so PerStat / Multiplier tags resolve
-- against the player modDB instead of contributing their raw per-unit
-- coefficient.
--
-- Symptom before fix (G1 fresh diff, 2026-05-11):
--   BxvJKdPR lv97 Necromancer MinionLifeInc LE=384 LEB=128 Δ=-256
-- The Acolyte-59 "Grave Thorns" notScalingStat
-- "4% Increased Minion Health Per Vitality" was wrapped as
-- MinionModifier{ mod=Life INC value=4, tag=PerStat:Vit } but the bucket
-- summed raw m.value (4) instead of evaluating 4 * Vit(65) = 260.
--
-- See REGRESSION_GUARDS.md "minion-bucket-evalmod-perstat".

describe("Minion bucket PerStat evaluation", function()
    it("'4% Increased Minion Health Per Vitality' wraps Life INC with PerStat:Vit", function()
        local mods = modLib.parseMod("4% Increased Minion Health Per Vitality")
        assert.is_not_nil(mods)
        assert.are.equals("MinionModifier", mods[1].name)
        assert.are.equals("LIST", mods[1].type)
        local inner = mods[1].value and mods[1].value.mod
        assert.is_not_nil(inner, "MinionModifier LIST must carry a wrapped mod")
        assert.are.equals("Life", inner.name)
        assert.are.equals("INC", inner.type)
        assert.are.equals(4, inner.value)
        local hasPerStatVit = false
        for _, tag in ipairs(inner) do
            if tag.type == "PerStat" and tag.stat == "Vit" then hasPerStatVit = true end
        end
        assert.is_true(hasPerStatVit, "wrapped mod must carry PerStat:Vit tag")
    end)

    it("CalcDefence MinionModifier bucket evaluates via EvalMod, not raw m.value", function()
        local f = assert(io.open("Modules/CalcDefence.lua", "r"))
        local body = f:read("*a")
        f:close()
        assert.is_truthy(body:find("@leb-regression-guard: minion-bucket-evalmod-perstat", 1, true),
            "CalcDefence bucket must keep the regression-guard marker")
        assert.is_truthy(body:find("modDB:EvalMod(m)", 1, true),
            "bucket must call modDB:EvalMod(m) so PerStat/Multiplier tags resolve")
        -- The raw-sum form `(m.value or 0)` would silently re-mask the bug.
        local startPos = body:find("@leb-regression-guard: phase4-minion-modifier-bucket-aggregation", 1, true)
        assert.is_not_nil(startPos, "phase4 marker must still anchor the bucket region")
        local region = body:sub(startPos, startPos + 2000)
        assert.is_nil(region:find("(m.value or 0)", 1, true),
            "the raw m.value sum must not return inside the bucket region")
    end)

    it("Acolyte-59 tree_3.json carries the Per-Vitality notScalingStat", function()
        -- Acolyte-59 "Grave Thorns" notScalingStats only exist in 1.3+ trees.
        local versions = { "1_3", "1_4" }
        for _, ver in ipairs(versions) do
            local path = "TreeData/" .. ver .. "/tree_3.json"
            local f = io.open(path, "r")
            assert.is_not_nil(f, "must be able to open " .. path)
            local text = f:read("*a")
            f:close()
            assert.is_truthy(text:find("Increased Minion Health Per Vitality", 1, true),
                "tree_3.json " .. ver .. " must keep the Acolyte-59 notScalingStat wording")
        end
    end)
end)
