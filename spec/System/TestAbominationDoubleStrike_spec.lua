-- @leb-regression-guard:abomination-double-strike-grant
-- Invariant: Spoils of War grants the abomination's Double Strike sub-skill, and
-- its per-warrior-or-rogue MORE modifier applies only to that granted skill.
-- Test data also locks the required base damage and effectiveness fields.
-- See REGRESSION_GUARDS.md.

describe("AbominationDoubleStrike #abomination parser contracts", function()

    it("' Double Strike Gained on Warrior or Rogue Absorbed' emits the SummonedAbomination ExtraMinionSkill grant", function()
        local g = modLib.parseMod(" Double Strike Gained on Warrior or Rogue Absorbed")
        assert.is_table(g, "grant line must parse to a mod (ModCache row must not be a no-op)")
        assert.are.equals("ExtraMinionSkill", g[1].name)
        assert.are.equals("Abomination Double Strike", g[1].value.skillId)
        assert.are.equals("SummonedAbomination", g[1].value.minionList[1])
    end)

    it("the +30% Spoils line parses to a Double-Strike-scoped MORE with the per-warrior-or-rogue multiplier (no rewrite, no residue)", function()
        -- Once the granted skill exists (name "Double Strike"), the raw node line needs
        -- no LE_TREE_NODE_STAT_REWRITE: the skillNameList post-scan strips the "Double
        -- Strike" token (previously an unmodeled residue) and the "per warrior or rogue
        -- absorbed" tag makes it MORE, matching the sibling Engorgement per-type line.
        local mods, extra = modLib.parseMod("+30% Double Strike Damage per Warrior or Rogue Absorbed")
        assert.is_table(mods)
        assert.is_true(not extra or extra == "", "gap CLOSED: no 'Double Strike' residue, got: " .. tostring(extra))
        local m = mods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type, "must be MORE (multiplicative per the node description), not INCREASED")
        assert.are.equals(30, m.value)
        local sawSkillName, sawMult = false, false
        for _, tag in ipairs(m) do
            if tag.type == "SkillName" and tag.skillName == "Double Strike" then sawSkillName = true end
            if tag.type == "Multiplier" and tag.var == "AbominationWarriorsOrRoguesAbsorbed" and tag.limit == 20 then sawMult = true end
        end
        assert.is_true(sawSkillName, "MORE must be SkillName-scoped to 'Double Strike' (so base Melee is untouched)")
        assert.is_true(sawMult, "MORE must carry the AbominationWarriorsOrRoguesAbsorbed multiplier (cap 20)")
    end)
end)

describe("AbominationDoubleStrike #abomination data contracts", function()

    it("data.skills['Abomination Double Strike'] carries the datamined Physical 40 / eff 2.0 melee base", function()
        local s = data.skills["Abomination Double Strike"]
        assert.is_table(s, "Abomination Double Strike must exist in data.skills")
        assert.are.equal(40, s.stats.melee_base_physical_damage)
        assert.are.equal(2.0, s.stats.damageEffectiveness)
        assert.are.equal(5, s.stats.critChance)
        assert.are.equal(100, s.stats["base_critical_strike_multiplier_+"])
        assert.is_true(s.baseFlags.melee)
        assert.is_true(s.baseFlags.attack)
        assert.is_true(s.baseFlags.hit)
    end)

    it("Abomination Double Strike is named 'Double Strike' so the Spoils MORE scopes to it", function()
        -- The +30% MORE is SkillName-scoped to "Double Strike"; the granted skill's
        -- `name` field is what the skillNameList post-scan matches. Keep them in sync.
        local s = data.skills["Abomination Double Strike"]
        assert.are.equal("Double Strike", s.name)
        assert.is_true(s.fromMinion, "must be a minion-only skill (no player treeId, rank 0)")
        assert.is_nil(s.treeId)
    end)
end)
