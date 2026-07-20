-- @leb-regression-guard:shadow-rend-manifest-base
-- not a base/eff anomaly. See REGRESSION_GUARDS.md "shadow-rend-manifest-base".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("ShadowRend manifest base damage (data-only, no fabrication)", function()
    it("ShadowRendSmallDamage = Shadow Blade, melee base 2 phys / eff 1 / crit 5%/x2", function()
        local d = data.skills.ShadowRendSmallDamage
        assert.is_table(d, "ShadowRendSmallDamage must exist in data.skills")
        assert.are.equals("Shadow Blade", d.name)
        assert.are.equals(2, d.stats.melee_base_physical_damage,
            "datamined contact base = 2 physical (baseDamageStats.damage[0])")
        assert.are.equals(1, d.stats.damageEffectiveness,
            "ShadowRend Small Damage addedDamageScaling = 1")
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"],
            "critMultiplier 2 encodes as base_critical_strike_multiplier_+ 100")
        assert.are.equals(5, d.stats.critChance, "critChance 0.05 -> 5")
        assert.is_true(d.baseFlags.hit, "the shadow attack is a hit")
        assert.is_true(d.baseFlags.attack, "Melee-tagged attack")
        assert.is_nil(d.baseFlags.dot)
        assert.is_true(d.excludeFromTriggerNameList,
            "manifest sub-skill must not pollute the trigger-name list")
    end)

    it("ShadowRendDamage = the larger Shadow Blade hit (same melee base, eff 5)", function()
        local d = data.skills.ShadowRendDamage
        assert.is_table(d, "ShadowRendDamage must exist in data.skills")
        assert.are.equals("Shadow Blade", d.name)
        assert.are.equals(2, d.stats.melee_base_physical_damage)
        assert.are.equals(5, d.stats.damageEffectiveness,
            "ShadowRend Damage addedDamageScaling = 5 (the larger hit)")
    end)

    it("ShadowRendSmallDamageBow = Energy Ball, bow base 2 phys / eff 1", function()
        local d = data.skills.ShadowRendSmallDamageBow
        assert.is_table(d, "ShadowRendSmallDamageBow must exist in data.skills")
        assert.are.equals("Energy Ball", d.name)
        assert.are.equals(2, d.stats.bow_base_physical_damage,
            "Energy Ball is Bow-tagged -> bow_base_physical_damage = 2")
        assert.are.equals(1, d.stats.damageEffectiveness)
        assert.is_true(d.excludeFromTriggerNameList)
    end)

    it("ShadowRend stays corpus-inert: NOT activated as a grant", function()
        -- The load-bearing deferral: until the per-cast shadow COUNT + hit mix are
        -- REd and validated in-game, ShadowRend must NOT appear in the grant table
        -- (activating it would change Lariani's FullDPS at an unvalidated rate).
        assert.is_nil(data.subSkillGrants.ShadowRend,
            "ShadowRend must NOT be in the grant table (corpus-inert until validated)")
    end)

    it("SubSkillGrants carries the guard marker", function()
        local text = assert(readFile("Data/SubSkillGrants.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:shadow%-rend%-manifest%-base"),
            "SubSkillGrants must carry the shadow-rend-manifest-base guard marker")
    end)
end)
