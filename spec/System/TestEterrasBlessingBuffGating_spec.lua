-- @leb-regression-guard:eterras-blessing-buff-gating
-- Locks Eterra's Blessing (treeId eb5656) into CalcSetup's
-- whileActiveBuffByTreeId table so its specialization tree node mods
-- (notably eb5656-2 "Safeguard": +15% Elemental Resistance + +15% Poison
-- Resistance per point) require an explicit Condition:HaveEterrasBlessing
-- flag to apply globally.
--
-- Without the entry the SkillType.Buff bit alone is enough for CalcSetup's
-- buff-tree bucket, but the gate degrades to `enabled = group.enabled` —
-- i.e. "skill is on the bar" instead of "buff is currently active". LE's
-- Buffs panel shows EB OFF by default (matching the 4s cast-time duration
-- semantics), so for parity LEB must default it OFF too.
--
-- Symptoms before fix (BOwJnY3Y Beastmaster, eb5656-2 #3):
--   * FireResist  LE=56  LEB=101 Δ=+45
--   * ColdResist  LE=80  LEB=125 Δ=+45
--   * LightResist LE=179 LEB=224 Δ=+45
--   * PoisonResist LE=1  LEB=46  Δ=+45
-- See REGRESSION_GUARDS.md "eterras-blessing-buff-gating".

describe("EterrasBlessingBuffGating", function()
    it("LE_WHILE_ACTIVE_BUFF_BY_TREE_ID maps eb5656 to HaveEterrasBlessing", function()
        -- The registry moved from a CalcSetup-local table to the shared global
        -- LE_WHILE_ACTIVE_BUFF_BY_TREE_ID in src/Data/Global.lua so the SkillsTab
        -- UI can read the same map without forking. Assert on the global directly
        -- now; the file-grep variant below is a separate safety net.
        assert.is_table(LE_WHILE_ACTIVE_BUFF_BY_TREE_ID,
            "LE_WHILE_ACTIVE_BUFF_BY_TREE_ID must be defined in Global.lua")
        assert.are.equal("HaveEterrasBlessing", LE_WHILE_ACTIVE_BUFF_BY_TREE_ID["eb5656"])
        local f = io.open("Data/Global.lua", "r")
        assert.is_not_nil(f, "must be able to open Global.lua")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(
            string.find(text, '%["eb5656"%]%s*=%s*"HaveEterrasBlessing"'),
            "Global.lua LE_WHILE_ACTIVE_BUFF_BY_TREE_ID must include eb5656 -> HaveEterrasBlessing")
    end)
end)
