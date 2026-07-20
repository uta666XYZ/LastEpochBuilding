-- @leb-regression-guard: chthonic-fissure-soul-blast
-- The Spirits released by Chthonic Fissure each deal a Necrotic HIT in-game
-- labelled "Soul Blast" (internal ability "Warlock 04.2 Arcing Soul Explosion").
-- Its base is datamined (subprefab_damage.json parent "Chthonic Fissure Spirit"):
-- Necrotic 6.0, addedDamageScaling 0.30 (= damageEffectiveness, matches the
-- tooltip "Spirits added at 30% effectiveness"), critChance 0.05, critMultiplier
-- 2.0, isHit, Spell tag.
--
-- AILMENT-SOURCE REFACTOR (2026-06-26): in-game the CF cast is isHit=0 (it leaves
-- the FIRE DoT line); the periodic Spirits ("Soul Blast") are the ONLY isHit=1
-- component, so they -- not the cast -- are the real on-hit ailment + Torment
-- source (dicey_blank capture: Soul Blast n == Torment n == 144). LEB previously
-- modelled the CAST as the hit, so it spawned the build's on-hit ailments
-- ("<ailment> (from Chthonic Fissure)") AND triggered Torment; Soul Blast was an
-- inert scaffold (granting it then would DOUBLE-count those ailments). This spec
-- locks the completed refactor:
--   * the CF cast lost its `hit` flag and its Torment trigger (it is isHit=0);
--   * Soul Blast carries the Torment trigger and IS granted via SubSkillGrants,
--     so the on-hit ailments + Torment source from "(from Soul Blast)" only --
--     NO "(from Chthonic Fissure)" cast duplicates;
--   * the grant is SUPPRESSED on a Spine of Malatros build (Spirits replaced by
--     Flame Whip -> no Soul Blast in-game), via requiresAbsentParentTrigger.
-- VALIDATED in-game (dicey_blank, build_Dicey import 0-spec): Soul Blast
-- NecroticHitAverage (non-crit) 137.26 vs in-game 155.9 (-12%, enemy-cursed state
-- LEB does not flag); Torment preserved EXACTLY at 2541.6 DPS / 423.6 per-app /
-- 6 stacks (identical before/after the cast->spirit move). CF is
-- includeInFullDPS=false in every corpus build (zero build-DPS impact); this is a
-- display-correctness fix. See REGRESSION_GUARDS.md "chthonic-fissure-soul-blast".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

describe("ChthonicFissureSoulBlast", function()
    it("defines Soul Blast with the datamined spirit-hit base profile + Torment trigger", function()
        local sb = data.skills["Warlock 04.2 Arcing Soul Explosion"]
        assert.is_not_nil(sb, "Soul Blast skill entry must exist")
        assert.are.equals("Soul Blast", sb.name)
        assert.is_truthy(sb.baseFlags and sb.baseFlags.spell and sb.baseFlags.hit,
            "Soul Blast is a spell hit")
        assert.is_falsy(sb.baseFlags and sb.baseFlags.dot, "Soul Blast is a HIT, not a DoT")
        assert.are.equals(6, sb.stats.spell_base_necrotic_damage, "datamined base Necrotic 6.0")
        assert.are.equals(0.3, sb.stats.damageEffectiveness, "datamined addedDamageScaling 0.30")
        assert.are.equals(5, sb.stats.critChance)
        assert.are.equals(100, sb.stats["base_critical_strike_multiplier_+"],
            "crit multiplier +100 (= x2.0 datamined)")
        assert.is_nil(sb.treeId, "no treeId (line-DoT/CG pattern)")
        -- The Spirit (Soul Blast) is the real Torment applier: the trigger moved
        -- here from the CF cast (Soul Blast n == Torment n in-game).
        assert.are.equals(100, sb.stats["chance_to_cast_Ailment_Torment_on_hit_%"],
            "Soul Blast carries the Torment trigger (the Spirit applies Torment)")
    end)

    it("is GRANTED by Chthonic Fissure (alongside the line DoT), Spine-gated", function()
        local cfGrants = data.subSkillGrants["Warlock 04 Chthonic Fissure"]
        assert.is_not_nil(cfGrants, "Chthonic Fissure must still grant the line DoT")
        local soulBlastGrant, lineDoTGrant
        for _, g in ipairs(cfGrants) do
            if g.skillId == "Warlock 04.2 Arcing Soul Explosion" then soulBlastGrant = g end
            if g.skillId == "Warlock Unique Chthonic Fissure DoT" then lineDoTGrant = g end
        end
        assert.is_not_nil(lineDoTGrant, "the line FIRE DoT grant must remain")
        assert.is_not_nil(soulBlastGrant, "Soul Blast must now be GRANTED (the spirit hit)")
        -- Spine of Malatros replaces the Spirits with Flame Whip -> no Soul Blast.
        -- The grant is suppressed when the parent triggers Flame Whip on hit.
        assert.are.equals("Warlock Unique Flame Whip", soulBlastGrant.requiresAbsentParentTrigger,
            "Soul Blast grant must be gated off Spine builds (Flame Whip swap)")
    end)

    it("the CF cast is NO LONGER the on-hit ailment source (isHit=0, no Torment trigger)", function()
        local cf = data.skills["Warlock 04 Chthonic Fissure"]
        assert.is_not_nil(cf)
        assert.is_falsy(cf.baseFlags and cf.baseFlags.hit,
            "the CF cast must have lost its hit flag (so it spawns NO '(from Chthonic Fissure)' ailments)")
        assert.is_nil(cf.stats["chance_to_cast_Ailment_Torment_on_hit_%"],
            "the Torment trigger must have moved off the cast onto Soul Blast")
    end)

    it("the Spine swap mod + grant gate are wired (carry the guard marker)", function()
        -- ModParser: the Spine swap emits the Flame Whip trigger this gate reads.
        local mp = readSource("Modules/ModParser.lua")
        assert.is_truthy(mp:find("@leb-regression-guard:chthonic-fissure-soul-blast", 1, true),
            "ModParser must carry the guard marker on the Spine swap handler")
        -- CalcSetup: the grant loop honours requiresAbsentParentTrigger.
        local cs = readSource("Modules/CalcSetup.lua")
        assert.is_truthy(cs:find("requiresAbsentParentTrigger", 1, true),
            "CalcSetup grant loop must implement the requiresAbsentParentTrigger gate")
        assert.is_truthy(cs:find("@leb-regression-guard:chthonic-fissure-soul-blast", 1, true),
            "CalcSetup must carry the guard marker on the gate")
    end)
end)
