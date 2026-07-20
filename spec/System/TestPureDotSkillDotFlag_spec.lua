-- @leb-regression-guard: pure-dot-skill-dot-flag
-- Locks the contract that PURE-DoT skills (DoT bit in skillTypeTags but no hit)
-- get skillFlags.dot derived, carry ModFlag.Dot into their skill mod-flag set,
-- and therefore have ModFlag.Dot-gated mods ("increased Damage Over Time")
-- applied to their damage.
--
-- Root cause (fixed 2026-06-24):
--   src/Modules/CalcActiveSkill.lua initialises skillFlags as a literal
--   copyTable(activeGrantedEffect.baseFlags). Pure-DoT skills such as
--   "Warlock 05 Profane Veil" (skillTypeTags 4384 = DoT 4096 + Spell 256 +
--   Necrotic 32) carry the DoT bit in skillTypeTags but their baseFlags omit
--   'dot', so skillFlags.dot stayed nil. Two consequences:
--     1. The skill mod-flag set (skillModFlags -> cfg.flags) never gained
--        ModFlag.Dot, so "increased Damage Over Time" (parsed as Damage +
--        ModFlag.Dot) never matched -> increased-DoT silently dropped.
--     2. Profane Veil (YsGhostSurfing) computed AverageHit 178.5 vs in-game
--        400.775 (x2.245 under) because +521% increased-DoT was filtered out.
--
-- Fix (one commit, three src touches):
--   - CalcActiveSkill.lua: derive
--       skillFlags.dot = skillFlags.dot
--           or (activeSkill.skillTypes[SkillType.Dot] and not skillFlags.hit)
--           or nil
--     immediately after the skillFlags.hit derivation. The `and not
--     skillFlags.hit` gate restricts this to PURE-DoT skills and EXCLUDES
--     hit+dot skills (DevouringOrb, EntanglingRoots, HungeringSouls, Chthonic
--     Fissure, Judgement, Skeletal Mages Necrotic Projectile) whose hit path
--     must not change.
--   - CalcActiveSkill.lua: bor ModFlag.Dot into skillModFlags when
--     skillFlags.dot, so DoT-gated mods reach the damage Sum via cfg.flags.
--   - CalcOffence.lua: guard `baseDmg / skillData.duration` so permanent-aura
--     pure-DoT skills with no duration (AuraOfDecay) do not divide by nil.
--
-- The fix newly flags exactly six pure-DoT skills (verified by enumerating
-- skills.json: DoT bit set, baseFlags.dot absent, no hit/projectile):
--   Warlock 05 Profane Veil, AbyssalEchoes, AuraOfDecay, FireTrail,
--   SpiritPlague, Runemaster 01 Frost Wall.
--
-- See REGRESSION_GUARDS.md > "pure-dot-skill-dot-flag" for the index entry.

describe("PureDotSkillDotFlag", function()
    before_each(function()
        newBuild()
    end)

    local function selectSkill(skillKey)
        build.skillsTab:SelSkill(1, skillKey)
        runCallback("OnFrame")
        return build.calcsTab.mainEnv.player.mainSkill
    end

    it("(a) Profane Veil gets skillFlags.dot and increased-DoT now raises its damage", function()
        -- Baseline: Profane Veil with a plain Necrotic base, no increased-DoT.
        build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
        Brass Sceptre
        Brass Sceptre
        +30 Spell Necrotic Damage]])
        build.itemsTab:AddDisplayItem()
        local ms = selectSkill("Warlock 05 Profane Veil")
        assert.is_true(ms.skillFlags.dot == true,
            "Profane Veil (DoT bit, baseFlags omits dot) must get skillFlags.dot")
        assert.is_nil(ms.skillFlags.hit,
            "Profane Veil is a pure-DoT skill and must not be flagged as a hit")
        assert.is_true((bit.band(ms.skillCfg.flags or 0, ModFlag.Dot) ~= 0),
            "skillFlags.dot must propagate ModFlag.Dot into the skill cfg flags")
        -- mainSkill.output is nil in the headless calc path; read the resolved
        -- output from build.calcsTab.mainOutput (same accessor TestSkills uses).
        local baselineAvg = build.calcsTab.mainOutput.AverageHit
        assert.is_true(baselineAvg and baselineAvg > 0,
            "Profane Veil should produce a positive AverageHit baseline")

        -- Add "increased Damage Over Time" (parses to Damage + ModFlag.Dot).
        -- It must now raise the skill's damage instead of being filtered out.
        newBuild()
        build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
        Brass Sceptre
        Brass Sceptre
        +30 Spell Necrotic Damage
        100% increased Damage Over Time]])
        build.itemsTab:AddDisplayItem()
        selectSkill("Warlock 05 Profane Veil")
        local boostedAvg = build.calcsTab.mainOutput.AverageHit
        assert.is_true(boostedAvg > baselineAvg + 1e-6,
            string.format("increased Damage Over Time must raise Profane Veil damage (%.3f -> %.3f)",
                baselineAvg, boostedAvg))
    end)

    it("(b) DevouringOrb (hit+dot) is not force-flagged dot and its hit path is unchanged", function()
        local ms = selectSkill("DevouringOrb")
        -- baseFlags for DevouringOrb already carry hit (and not dot); the
        -- `and not skillFlags.hit` gate must leave dot un-forced.
        assert.is_true(ms.skillFlags.hit == true,
            "DevouringOrb must remain a hit skill")
        assert.is_not_true(ms.skillFlags.dot,
            "DevouringOrb (hit+dot) must NOT get dot forced by the pure-DoT derivation")
        assert.is_true((bit.band(ms.skillCfg.flags or 0, ModFlag.Hit) ~= 0),
            "DevouringOrb cfg must still carry ModFlag.Hit")
    end)

    it("(c) all six pure-DoT skills get skillFlags.dot and load without error", function()
        local pureDot = {
            "Warlock 05 Profane Veil",
            "AbyssalEchoes",
            "AuraOfDecay",
            "FireTrail",
            "SpiritPlague",
            "Runemaster 01 Frost Wall",
        }
        for _, key in ipairs(pureDot) do
            local ms = selectSkill(key)
            assert.is_truthy(ms, "mainSkill missing for "..key)
            assert.is_true(ms.skillFlags.dot == true,
                key.." must get skillFlags.dot")
            assert.is_nil(ms.skillFlags.hit,
                key.." is a pure-DoT skill and must not be a hit")
        end
    end)

    it("(d) hit+dot skills are excluded (dot not forced, hit preserved)", function()
        -- NOTE: "Warlock 04 Chthonic Fissure" was REMOVED from this list by the
        -- ailment-source refactor (@leb-regression-guard:chthonic-fissure-soul-blast).
        -- The CF cast is isHit=0 in-game, so it lost its `hit` flag; it is therefore
        -- no longer a hit+dot skill (it is a pure spawner -- the periodic Spirits
        -- "Soul Blast" do the hitting). With the hit flag gone the pure-dot guard
        -- DOES now derive dot for the cast, which is harmless: CF is
        -- includeInFullDPS=false everywhere (the cast's base is inert) so it adds
        -- nothing to Full DPS. See TestChthonicFissureSoulBlast_spec.lua.
        local hitDot = {
            "DevouringOrb",
            "EntanglingRoots",
            "HungeringSouls",
            "Judgement",
            "Skeletal Mages Necrotic Projectile",
        }
        for _, key in ipairs(hitDot) do
            local ms = selectSkill(key)
            assert.is_truthy(ms, "mainSkill missing for "..key)
            assert.is_true(ms.skillFlags.hit == true,
                key.." must remain a hit skill")
            assert.is_not_true(ms.skillFlags.dot,
                key.." (hit+dot) must NOT get dot forced")
        end
    end)
end)
