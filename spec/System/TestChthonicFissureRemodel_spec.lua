-- @leb-regression-guard:chthonic-fissure-torment-multistack
-- @leb-regression-guard:chthonic-fissure-fire-dot
-- (@leb-regression-guard:chthonic-fissure-soul-blast): the Chthonic Fissure CAST
-- See REGRESSION_GUARDS.md "chthonic-fissure-torment-multistack",
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

describe("ChthonicFissureRemodel #chthonic", function()
    before_each(function()
        newBuild()
    end)

    -- ===== Torment ailment (the DOMINANT native component) =====

    it("Torment is a NECROTIC multi-stack-capable curse DoT with base 40/s (120 over 3s)", function()
        local t = data.damagingAilment.Torment
        assert.is_table(t, "Torment ailment must exist")
        assert.are.equals("Necrotic", t.associatedType, "Torment is Necrotic (NOT converted by Blood Gulch)")
        assert.are.equals("Necrotic", t.penType)
        assert.are.equals(120, t.baseDamage, "Torment base = 120 over 3s (game tooltip)")
        assert.are.equals(3, t.duration)
        -- per-second base = 120 / 3 = 40/s, matching the captured tooltip
        -- "120 damage over 3s, added @ 200% effectiveness per second" => base 40/s.
        assert.are.equals(40, t.baseDamage / t.duration, "Torment per-second base = 40/s")
        assert.is_truthy(t.isCurse, "Torment is a curse ailment")
        -- default maxStacks = 1 keeps corpus single-stack (the config overrides it)
        assert.are.equals(1, t.maxStacks, "default Torment maxStacks stays 1 (corpus-neutral)")
    end)

    -- @leb-regression-guard:chthonic-fissure-soul-blast
    it("the SPIRIT (Soul Blast), not the cast, applies Torment on hit", function()
        -- In-game the CF cast is isHit=0 (it leaves the fire DoT line); the
        -- periodic Spirits ("Soul Blast") are the only isHit=1 component and are
        -- the real on-hit ailment source (Soul Blast n == Torment n in the
        -- dicey_blank capture). The Torment trigger therefore lives on Soul Blast,
        -- NOT on the cast (moving it cast->spirit is what lets Soul Blast be
        -- granted without double-counting the build's on-hit ailments).
        local sb = data.skills["Warlock 04.2 Arcing Soul Explosion"]
        assert.is_table(sb, "Soul Blast must exist")
        assert.are.equals(100, sb.stats["chance_to_cast_Ailment_Torment_on_hit_%"],
            "Soul Blast (the Spirit hit) applies Torment (the Necrotic curse DoT)")
        local cf = data.skills["Warlock 04 Chthonic Fissure"]
        assert.is_table(cf, "Chthonic Fissure must exist")
        assert.is_nil(cf.stats["chance_to_cast_Ailment_Torment_on_hit_%"],
            "the CF cast must NOT carry the Torment trigger -- it is isHit=0 in-game")
    end)

    it("the Torment-stack config + CalcOffence override wiring carry the guard marker (default 0 -> corpus-neutral)", function()
        local co = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(string.find(co, "@leb-regression-guard:chthonic-fissure-torment-multistack", 1, true),
            "ConfigOptions must carry the guard marker")
        assert.is_truthy(string.find(co, "multiplierChthonicTormentStacks", 1, true),
            "ConfigOptions must define the Torment-stack count config")
        assert.is_truthy(string.find(co, "Multiplier:ChthonicTormentStacks", 1, true))
        local cox = readSource("Modules/CalcOffence.lua")
        assert.is_truthy(string.find(cox, "@leb-regression-guard:chthonic-fissure-torment-multistack", 1, true),
            "CalcOffence must carry the guard marker at the override site")
        -- the override only applies to Torment and only when set (>0)
        assert.is_truthy(string.find(cox, 'ailmentName == "Torment"', 1, true),
            "override must be scoped to Torment only")
        assert.is_truthy(string.find(cox, "Multiplier:ChthonicTormentStacks", 1, true))
    end)

    it("Ailment_Torment trigger-skill is the REAL CF Torment path: maxStacks=6 (Spirit-limited), base 120/eff 6", function()
        -- @leb-regression-guard:chthonic-fissure-torment-multistack
        -- CF routes Torment through the TRIGGER-SKILL "Ailment_Torment" (via
        -- chance_to_cast_Ailment_Torment_on_hit_%), NOT the data.damagingAilment path
        -- (TormentChance=0 for CF -> that override is inert). The dominant CF damage
        -- (74-78%) lives here; pre-fix maximum_stacks=1 under-counted it ~6x.
        local at = data.skills["Ailment_Torment"]
        assert.is_table(at, "Ailment_Torment trigger-skill must exist")
        assert.are.equals(120, at.stats.spell_base_necrotic_damage, "base 120 Necrotic")
        assert.are.equals(3000, at.stats.base_skill_effect_duration, "3s duration")
        -- Validation provenance is retained in maintainer notes.
        assert.are.equals(6, at.stats.damageEffectiveness, "eff 6 = 200%/s x 3s")
        assert.is_truthy(at.baseFlags.spell and at.baseFlags.dot, "spell+dot DoT-ailment")
        -- THE FIX: coexisting Torment stacks = Spirit emit ~2/s x 3s duration = 6
        -- (dicey_blank 2026-06-25 capture). Caps LEB's cast-rate-based application
        -- (which over-counts vs the fixed 2/s Spirit emit) to the Spirit-limited count.
        assert.are.equals(6, at.stats.maximum_stacks,
            "Ailment_Torment maxStacks = 6 (Spirit emit 2/s x 3s); was 1 (~6x undercount)")
    end)

    -- ===== Fissure FIRE DoT (the over-time component, NOT a Bleed) =====

    it("Fissure FIRE DoT entry is a pure FIRE skill-DoT (spell+dot, eff 0.25 = datamined addedDamageScaling), NOT a Bleed ailment", function()
        local dot = data.skills["Warlock Unique Chthonic Fissure DoT"]
        assert.is_table(dot, "Chthonic Fissure DoT entry must exist")
        assert.is_truthy(dot.baseFlags and dot.baseFlags.spell, "is a spell")
        assert.is_truthy(dot.baseFlags and dot.baseFlags.dot, "is a DoT (skill-DoT, per-second base path)")
        assert.is_falsy(dot.baseFlags and dot.baseFlags.hit, "pure DoT -> no hit flag")
        -- @leb-regression-guard:chthonic-fissure-fire-dot
        -- effectiveness = the datamined addedDamageScaling 0.25 (per-TICK effectiveness
        -- for flat added damage), NOT 1.2. A prior commit used 1.2 by conflating the
        -- per-second tooltip with the per-tick added scaling, which made flat '+Spell
        -- Damage' (e.g. Spine of Malatros +65) inflate the line DoT ~4.8x (YsGhostSurfing
        -- 835.8/tick = +378% over the 175/tick capture; eff 0.25 -> 213.98/tick = +22%).
        assert.are.equals(0.25, dot.stats.damageEffectiveness, "added-damage effectiveness = datamined addedDamageScaling 0.25 (per tick)")
        assert.is_truthy((dot.stats.spell_base_fire_damage or 0) > 0,
            "DoT base is FIRE (Blood Gulch fire->phys, Valley of Defilement fire->poison)")
        -- It must NOT carry a non-fire base (Torment, the necrotic component, is a
        -- separate ailment -- this entry models ONLY the fire over-time).
        assert.is_nil(dot.stats.spell_base_necrotic_damage, "fire DoT must not carry necrotic base")
        -- treeId removed (ConsecratedGround pattern): a granted sub-skill gets the CF
        -- tree (Blood Gulch fire->phys, Valley fire->poison) via groupSource
        -- ("SkillId:Warlock 04 Chthonic Fissure"), NOT treeId. Carrying treeId=ch0fs
        -- wrongly enrolled it in the FullDPS cast-cycle (x1/N), diluting the build's
        -- real CF skills; removing it keeps the conversion (verified: BgRrekvv Blood
        -- Gulch build -> line DoT PhysicalDamageBase, FireBase 0) with count=1 (no cycle).
        assert.is_nil(dot.treeId, "no treeId -> CF tree via groupSource, not cycle-weighted (CG pattern)")
    end)

    it("Fissure FIRE DoT is GRANTED via SubSkillGrants (ConsecratedGround pattern), not a baseMod trigger", function()
        -- @leb-regression-guard:chthonic-fissure-fire-dot
        -- WIRED 2026-06-25: the line fire DoT is granted as a base-kit sub-skill of
        -- Chthonic Fissure (source="SkillId:Warlock 04 Chthonic Fissure"), so it
        -- contributes to Full DPS for every CF build. Validated in-game (dicey_blank
        -- native: 172.5/tick @ 259ms; LEB om6xj3n8 line DoT 127.66, ~5% of CF).
        local grants = data.subSkillGrants["Warlock 04 Chthonic Fissure"]
        assert.is_table(grants, "Chthonic Fissure must have a SubSkillGrants entry")
        local hasDot = false
        for _, g in ipairs(grants) do
            if g.skillId == "Warlock Unique Chthonic Fissure DoT" then hasDot = true end
        end
        assert.is_truthy(hasDot, "CF grants the Fissure FIRE DoT sub-skill")
        -- It is granted via the registry (data), NOT a baseMod trigger sentinel.
        local cf = data.skills["Warlock 04 Chthonic Fissure"]
        for _, m in ipairs(cf.baseMods or {}) do
            local nm = type(m) == "table" and m.name or tostring(m)
            assert.is_falsy(nm:find("Chthonic Fissure DoT", 1, true),
                "DoT is granted via SubSkillGrants, NOT a baseMod trigger")
        end
        local cox = readSource("Modules/CalcOffence.lua")
        assert.is_falsy(cox:find("chthonicFissureDoT", 1, true), "CalcOffence must not hard-reference the DoT entry")
    end)

    -- ===== Preservation of the validated hit / Spine paths =====

    it("PRESERVED: gen393 Chthonic Fissure Hit base is UNCHANGED (60 Fire / eff 3.0)", function()
        local cfh = data.skills["Warlock Unique Chthonic Fissure Hit"]
        assert.is_table(cfh)
        assert.are.equals(60, cfh.stats.spell_base_fire_damage)
        assert.are.equals(3.0, cfh.stats.damageEffectiveness)
        assert.are.equals(5, cfh.stats.critChance)
        assert.are.equals("chthonicFissureHit", cfh.playerAbilityID)
        assert.are.equals("ch0fs", cfh.treeId)
    end)

    it("PRESERVED: Flame Whip (Spine swap) base is UNCHANGED (60 Fire / eff 3.0)", function()
        local fw = data.skills["Warlock Unique Flame Whip"]
        assert.is_table(fw)
        assert.are.equals(60, fw.stats.spell_base_fire_damage)
        assert.are.equals(3.0, fw.stats.damageEffectiveness)
        assert.are.equals(5, fw.stats.critChance)
        assert.are.equals("flameWhip", fw.playerAbilityID)
        assert.are.equals("ch0fs", fw.treeId)
    end)

    -- @leb-regression-guard:chthonic-fissure-soul-blast
    it("the Chthonic Fissure CAST is INERT (no hit, zero base damage)", function()
        local cf = data.skills["Warlock 04 Chthonic Fissure"]
        -- The cast is isHit=0 in-game and deals no direct damage (its old
        -- 6F/6N/eff0.3 base was phantom -- absent in the dicey_blank capture). The
        -- ailment-source refactor removed the `hit` flag AND zeroed the base, so the
        -- cast computes ZERO damage (the engine counts hit damage in TotalDPS even
        -- without the hit flag, so zeroing the base is required -- this prevents a
        -- ~43% FullDPS over-count on CF-main builds like <private build>). The real damage
        -- is the granted line DoT + Soul Blast + Torment + gen393 hit.
        assert.is_falsy(cf.baseFlags and cf.baseFlags.hit,
            "the CF cast must NOT have the hit flag (isHit=0 in-game)")
        assert.is_truthy(cf.baseFlags and cf.baseFlags.spell, "still a spell (spawner)")
        assert.are.equals(0, cf.stats.spell_base_fire_damage or 0, "cast base fire zeroed (inert)")
        assert.are.equals(0, cf.stats.spell_base_necrotic_damage or 0, "cast base necrotic zeroed (inert)")
        assert.are.equals(0, cf.stats.damageEffectiveness or 0, "cast damageEffectiveness zeroed (inert)")
        -- The gen393 "Chthonic Fissure Hit" trigger is NOT in CF baseMods: it is
        -- Pyrochasm-node-gated (ch0fs-21), per TestChthonicFissureHitGen393. The
        -- Hit / Flame Whip paths remain intact via that node + the Spine swap mod.
        for _, m in ipairs(cf.baseMods) do
            assert.are_not.equals("ChanceToTriggerOnHit_Warlock Unique Chthonic Fissure Hit", m.name,
                "gen393 trigger must NOT be in baseMods (it is Pyrochasm-gated)")
        end
    end)
end)
