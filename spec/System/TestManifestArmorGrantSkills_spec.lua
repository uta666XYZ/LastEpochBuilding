-- @leb-regression-guard:manifest-armor-grant-skills
-- See REGRESSION_GUARDS.md "manifest-armor-grant-skills".
-- Validation provenance is retained in maintainer notes.

describe("ManifestArmorGrantSkills #manifestarmor parser contracts", function()

    it("'" .. " Forgebreath' / ' Whirlwind Strike' / ' Charge Attack' emit ManifestedArmor ExtraMinionSkill grants", function()
        local fb = modLib.parseMod(" Forgebreath")
        assert.are.equals("ExtraMinionSkill", fb[1].name)
        assert.are.equals("ManifestArmorForgeBreath", fb[1].value.skillId)
        assert.are.equals("ManifestedArmor", fb[1].value.minionList[1])

        local ww = modLib.parseMod(" Whirlwind Strike")
        assert.are.equals("ExtraMinionSkill", ww[1].name)
        assert.are.equals("ManifestArmorWhirlwind", ww[1].value.skillId)
        assert.are.equals("ManifestedArmor", ww[1].value.minionList[1])

        local ch = modLib.parseMod(" Charge Attack")
        assert.are.equals("ExtraMinionSkill", ch[1].name)
        assert.are.equals("ManifestArmorCharge", ch[1].value.skillId)
        assert.are.equals("ManifestedArmor", ch[1].value.minionList[1])
    end)
end)

describe("ManifestArmorGrantSkills #manifestarmor data contracts", function()

    it("ManifestArmorForgeBreath carries the datamined Fire 70 / eff 3.5 spell base", function()
        local s = data.skills.ManifestArmorForgeBreath
        assert.is_table(s, "ManifestArmorForgeBreath must exist in data.skills")
        assert.are.equal(70, s.stats.spell_base_fire_damage)
        assert.are.equal(3.5, s.stats.damageEffectiveness)
        assert.is_true(s.baseFlags.spell)
        assert.is_true(s.baseFlags.hit)
    end)

    it("ManifestArmorWhirlwind carries the datamined Physical 2 / eff 3.0 melee base", function()
        local s = data.skills.ManifestArmorWhirlwind
        assert.is_table(s)
        assert.are.equal(2, s.stats.melee_base_physical_damage)
        assert.are.equal(3.0, s.stats.damageEffectiveness)
        assert.is_true(s.baseFlags.melee)
        assert.is_true(s.baseFlags.attack)
    end)

    it("ManifestArmorCharge carries the in-game-grounded Physical 6 / eff 1.2 melee base", function()
        -- @leb-regression-guard:manifest-armor-charge-half-damage
        -- Validation provenance is retained in maintainer notes.
        local s = data.skills.ManifestArmorCharge
        assert.is_table(s)
        assert.are.equal(6, s.stats.melee_base_physical_damage)
        assert.are.equal(1.2, s.stats.damageEffectiveness)
        assert.is_true(s.baseFlags.melee)
    end)

    it("ManifestArmorCharge has NO spurious Strength/Attunement attribute baseMods", function()
        -- @leb-regression-guard:manifest-armor-charge-half-damage
        -- Validation provenance is retained in maintainer notes.
        local s = data.skills.ManifestArmorCharge
        local bm = s.baseMods or {}
        for _, m in ipairs(bm) do
            assert.is_nil(tostring(m):lower():find("per player strength"),
                "Charge must not carry per-Strength attribute scaling")
            assert.is_nil(tostring(m):lower():find("per player attunement"),
                "Charge must not carry per-Attunement attribute scaling")
        end
    end)
end)
