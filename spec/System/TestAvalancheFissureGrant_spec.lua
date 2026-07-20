-- @leb-regression-guard:avalanche-fissure-grant
-- @leb-regression-guard:grant-base-conversion-scope
-- Locks the Avalanche -> Fissure grant. Avalanche's "Pummeling" node (av75ch-17,
-- stat " Fissures From Large Boulders") makes its LARGE boulders open a Fissure
-- dealing a physical Spell DoT. The Fissure is a granted sub-skill (not a tree
-- node), NODE-gated on av75ch-17 so non-Pummeling Avalanche builds are unchanged.
--
-- Two Fissure-specific facts + one engine invariant are locked here:
--   (1) data.skills.AvalancheFissure base = Physical 20 / eff 1 / damageInterval 500
--       (datamine prefab fs47re, RepeatedlyDamageEnemiesWithinRadius pure DoT).
--   (2) baseMods "100% more Damage" = the LARGE-boulder MORE (x2.0). The Fissure
--       only spawns from large boulders (Pummeling), so it ALWAYS gets the full
--       BIG_BOULDER_MORE_DAMAGE x2.0 (AvalancheFissureMutator.Mutate scales the
--       spawned damage by field_0xf8+1 = 2.0). A *base* multiplier would only
--       double the intrinsic 20 (player-added pool stays single = far too small),
--       so it must be a MORE — A/B verified it cleanly x2.0s the per-tick.
--   (3) noParentTreeBaseConversion = the conversion-scope fix: the parent Avalanche
--       tree's base-conversion node (av75ch-20 Frost " Physical -> Cold Damage",
--       scoped in-game to "Avalanche's base", NOT the Fissure) must NOT convert the
--       granted Fissure's own base. It reaches the grant only via the
--       cfg.groupSource == "SkillId:Avalanche" channel (ModStore), so CalcOffence
--       builds the conversion table for a flagged grant with groupSource stripped:
--       the parent-tree (SkillId-tagged) base-conversion drops out while GLOBAL
--       (untagged) gear/passive phys->cold still applies (in-game the Fissure keeps
--       ~70% cold + an invariant ~26% physical). GATED on the flag so every other
--       skill's conversion table is byte-identical.
--
-- Game ground truth + magnitude diagnosis: memory project_avalanche_ingame_fissure_grant.
-- See REGRESSION_GUARDS.md "avalanche-fissure-grant" / "grant-base-conversion-scope".

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("AvalancheFissure grant registry (node-gated, no fabrication)", function()
    it("Avalanche grants AvalancheFissure gated on av75ch-17 (Pummeling)", function()
        local grants = data.subSkillGrants.Avalanche
        assert.is_table(grants, "Avalanche must be in the grant registry")
        assert.are.equals(1, #grants)
        assert.are.equals("AvalancheFissure", grants[1].skillId)
        -- The node gate keeps the corpus byte-identical: 0 spec/TestBuilds builds
        -- allocate av75ch-17, so the grant fires for none of them.
        assert.are.equals("av75ch-17", grants[1].requiresNode,
            "the Fissure grant must be node-conditional on Pummeling (av75ch-17)")
    end)

    it("AvalancheFissure carries the datamined Physical Spell DoT base + large-boulder MORE", function()
        local d = data.skills.AvalancheFissure
        assert.is_table(d, "AvalancheFissure must exist in data.skills")
        assert.are.equals("Fissure", d.name)
        assert.are.equals(20, d.stats.spell_base_physical_damage)
        assert.are.equals(1, d.stats.damageEffectiveness)
        assert.are.equals(500, d.stats.damage_interval)
        assert.is_true(d.baseFlags.dot, "Fissure is a pure DoT (dot flag)")
        assert.is_nil(d.baseFlags.hit, "Fissure deals no hit (isHit=0 in datamine)")
        assert.is_true(d.excludeFromTriggerNameList)
        -- large-boulder x2.0 MORE (always-large; a base multiplier would be too small).
        -- baseMods are parsed at load, so baseMods[1] is the mod object, not the string.
        assert.is_table(d.baseMods)
        local m = d.baseMods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type)
        assert.are.equals(100, m.value,
            "the always-large boulder MORE must be +100% (x2.0) Damage MORE, not a base multiplier")
        -- conversion-scope opt-out flag (the load-bearing correctness invariant)
        assert.is_true(d.noParentTreeBaseConversion,
            "the Fissure must opt OUT of parent-tree base-conversion (Frost) reaching its base")
    end)
end)

describe("grant-base-conversion-scope engine wiring (default byte-identical)", function()
    it("CalcOffence strips groupSource from the conversion cfg only for flagged grants", function()
        local text = assert(readFile("Modules/CalcOffence.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:grant%-base%-conversion%-scope"),
            "CalcOffence must carry the conversion-scope guard marker")
        assert.is_truthy(text:find("noParentTreeBaseConversion", 1, true),
            "the conversion table must gate the groupSource strip on the skill flag")
        assert.is_truthy(text:find("convCfg.groupSource = nil", 1, true),
            "the flagged path must strip groupSource so parent-tree base-conversions drop out")
        -- The default path must stay convCfg == skillCfg (byte-identical for every
        -- other skill); the strip is inside an `if ... noParentTreeBaseConversion` gate.
        assert.is_truthy(text:find("local convCfg = skillCfg", 1, true),
            "convCfg must default to skillCfg so non-flagged skills are unaffected")
    end)

    it("SubSkillGrants carries the grant guard marker", function()
        local text = assert(readFile("Data/SubSkillGrants.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:avalanche%-fissure%-grant"),
            "SubSkillGrants must carry the guard marker at the Avalanche entry")
    end)
end)
