-- @leb-regression-guard: skill-base-prefab-normalization
-- See REGRESSION_GUARDS.md "skill-base-prefab-normalization".
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("SkillBasePrefabNormalization", function()

    local skillsJson
    setup(function()
        skillsJson = readSource("Data/skills.json")
    end)

    -- Slice one skill entry: from its key to its treeId line (stats always
    -- precede treeId), so negative assertions cannot bleed into the next entry.
    local function entryWindow(key)
        local s = string.find(skillsJson, '"' .. key .. '"%s*:%s*{')
        assert.is_truthy(s, "skills.json must contain entry for " .. key)
        local e = string.find(skillsJson, '"treeId"', s)
        assert.is_truthy(e, key .. " entry must carry a treeId terminator for the window")
        return string.sub(skillsJson, s, e)
    end

    describe("(A) corrected to prefab in the 2026-06-12 batch", function()
        it("Flame Reave is melee fire 2 at eff 4.0 (was 16 / 2.0)", function()
            local w = entryWindow("FlameReave")
            assert.is_truthy(string.find(w, '"melee_base_fire_damage"%s*:%s*2%s*[,}]'),
                "Flame Reave base must be 2 (prefab fr11mv)")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*4%s*[,}]'),
                "Flame Reave eff must be 4 (localization: 400% effectiveness)")
        end)

        it("Firebrand is melee fire 2 at eff 1.25 (was eff 1)", function()
            local w = entryWindow("Firebrand")
            assert.is_truthy(string.find(w, '"melee_base_fire_damage"%s*:%s*2%s*[,}]'),
                "Firebrand base must be 2 (prefab f1b4d)")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*1%.25%s*[,}]'),
                "Firebrand eff must be 1.25 (localization: 125% effectiveness)")
        end)

        it("Meteor is spell fire 240 at eff 12 (was 190 / 9.5)", function()
            local w = entryWindow("Meteor")
            assert.is_truthy(string.find(w, '"spell_base_fire_damage"%s*:%s*240%s*[,}]'),
                "Meteor base must be 240 (child prefab MeteorAoe me27_1)")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*12%s*[,}]'),
                "Meteor eff must be 12 (localization: 1200% effectiveness)")
        end)
    end)

    describe("(C) Shatter Strike value confirmed but NOT landed (gate d fails)", function()
        it("Shatter Strike carries NO melee base damage key (revert: would overshoot in-game +54%)", function()
            local w = entryWindow("ShatterStrike")
            assert.is_falsy(string.find(w, '"melee_base_cold_damage"'),
                "Shatter Strike must NOT carry melee_base_cold_damage: the prefab value (Cold 2) is real, but "
                .. "LEB's melee base-damage pipeline mis-scales it (+54% over the verified +0.04% in-game match). "
                .. "Stays untouched pending a structural melee-base-scaling fix (see project_melee_weapon_basedamage_dropped).")
            assert.is_falsy(string.find(w, '"melee_base_fire_damage"'),
                "Shatter Strike must carry no melee base damage key at all")
        end)

        it("Shatter Strike still has no explicit damageEffectiveness (unchanged from upstream)", function()
            local w = entryWindow("ShatterStrike")
            assert.is_falsy(string.find(w, '"damageEffectiveness"'),
                "Shatter Strike carries no eff key (CalcOffence default 1.0 applies); the base is what was reverted")
        end)
    end)

    describe("(B) verified-correct multi-component models stay pinned", function()
        it("Static Orb keeps the EXPLOSION model: lightning 40 at eff 2.0", function()
            local w = entryWindow("StaticOrb")
            assert.is_truthy(string.find(w, '"spell_base_lightning_damage"%s*:%s*40%s*[,}]'),
                "Static Orb base 40 == child 'Static Orb Explosion' (ln24); do NOT halve to the orb component")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*2%s*[,}]'),
                "Static Orb eff 2.0 == the localization-confirmed explosion effectiveness (200%)")
        end)

        it("Flame Rush keeps the explosion model + the pass-through hit base key", function()
            local w = entryWindow("Runemaster 06 Flame Rush")
            assert.is_truthy(string.find(w, '"spell_base_fire_damage"%s*:%s*40%s*[,}]'),
                "Flame Rush spell base 40 == child 'Runemaster 06.1 Explosion'")
            assert.is_truthy(string.find(w, '"None_base_fire_damage"%s*:%s*20%s*[,}]'),
                "Flame Rush None_base 20 documents the pass-through hit component (engine-inert: sorted last-wins keeps spell=40)")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*2%s*[,}]'),
                "Flame Rush eff 2.0 == explosion effectiveness (localization: 200%)")
        end)

        it("Glyph of Dominion keeps the EXPLOSION model: lightning 40 at eff 2.0", function()
            local w = entryWindow("Runemaster 02 Glyph of Dominion")
            assert.is_truthy(string.find(w, '"spell_base_lightning_damage"%s*:%s*40%s*[,}]'),
                "Glyph base 40 == child 'Glyph of Dominion Explosion' (fm8); the 7.5/0.375 beam is the separate DoT component")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*2%s*[,}]'),
                "Glyph eff 2.0 == explosion effectiveness (localization: 200%)")
        end)

        it("Ice Barrage models one Frostbolt shard: cold 24 at eff 1.2", function()
            local w = entryWindow("IceBarrage")
            assert.is_truthy(string.find(w, '"spell_base_cold_damage"%s*:%s*24%s*[,}]'),
                "Ice Barrage base 24 == child Frostbolt (fblt)")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*1%.2%s*[,}]'),
                "Ice Barrage eff 1.2 == Frostbolt eff (localization: 120%)")
        end)

        it("Glacier models the fused 3-explosion hit (db41ae3a7): cold 125 at eff 6.25", function()
            local w = entryWindow("Glacier")
            assert.is_truthy(string.find(w, '"spell_base_cold_damage"%s*:%s*125%s*[,}]'),
                "Glacier base 125 == Glacier1+2+3 (20+35+70), the fused 3-explosion model; do NOT revert to the single small explosion's 20")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*6%.25%s*[,}]'),
                "Glacier eff 6.25 == 1+1.75+3.5 (localization: 100%/175%/350%)")
        end)

        it("Frost Claw models one burst component: cold 20 at eff 1.0", function()
            local w = entryWindow("Frost Claw")
            assert.is_truthy(string.find(w, '"spell_base_cold_damage"%s*:%s*20%s*[,}]'),
                "Frost Claw base 20 == every child component (L/M/R projectile + explosion are all 20/1.0)")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*1%s*[,}]'),
                "Frost Claw eff 1.0 == localization (100% effectiveness on the burst)")
        end)

        it("Black Hole stays FROZEN at 36 / eff 1.8 / interval 300 pending the structural hit/DoT split", function()
            local w = entryWindow("BlackHole")
            assert.is_truthy(string.find(w, '"spell_base_cold_damage"%s*:%s*36%s*[,}]'),
                "Black Hole base must stay 36: prefab says 48 but the in-game resample (5.4% low, conflation cancels) gates a blind raise")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*1%.8%s*[,}]'),
                "Black Hole eff must stay 1.8 until the hit/DoT profile separation lands (then 2.4 per prefab+localization)")
            assert.is_truthy(string.find(w, '"damage_interval"%s*:%s*300%s*[,}]'),
                "Black Hole tick interval 300ms (prefab 0.3s) must be preserved")
        end)

        it("Elemental Nova keeps its base on the tree nodes, not on the skill", function()
            local w = entryWindow("ElementalNova")
            assert.is_falsy(string.find(w, '"spell_base_fire_damage"'),
                "Elemental Nova base lives on en6-12 (Fire Nova) — re-adding it to the skill regresses TestElementalNovaDamageType")
            assert.is_falsy(string.find(w, '"spell_base_cold_damage"'),
                "Elemental Nova base lives on en6-2 (Ice Nova)")
            assert.is_falsy(string.find(w, '"spell_base_lightning_damage"'),
                "Elemental Nova base lives on en6-8 (Lightning Nova)")
            assert.is_truthy(string.find(w, '"damageEffectiveness"%s*:%s*1%.2%s*[,}]'),
                "Elemental Nova eff 1.2 == prefab/localization (120%)")
        end)
    end)

    describe("functional: the corrected values flow into the loaded data table", function()
        setup(function()
            assert.is_not_nil(data, "global data table must be loaded by the headless wrapper")
            assert.is_not_nil(data.skills, "data.skills must be loaded from skills.json")
        end)

        it("data.skills.FlameReave stats carry 2 / eff 4", function()
            local st = data.skills.FlameReave and data.skills.FlameReave.stats
            assert.is_not_nil(st, "data.skills.FlameReave.stats must exist")
            assert.are.equals(2, st.melee_base_fire_damage)
            assert.are.equals(4, st.damageEffectiveness)
        end)

        it("data.skills.Meteor stats carry 240 / eff 12", function()
            local st = data.skills.Meteor and data.skills.Meteor.stats
            assert.is_not_nil(st, "data.skills.Meteor.stats must exist")
            assert.are.equals(240, st.spell_base_fire_damage)
            assert.are.equals(12, st.damageEffectiveness)
        end)

        it("data.skills.ShatterStrike stats carry NO melee base (reverted) and no eff", function()
            local st = data.skills.ShatterStrike and data.skills.ShatterStrike.stats
            assert.is_not_nil(st, "data.skills.ShatterStrike.stats must exist")
            assert.is_nil(st.melee_base_cold_damage,
                "Shatter Strike must NOT have melee_base_cold_damage (gate d revert)")
            assert.is_nil(st.melee_base_fire_damage)
            assert.is_nil(st.damageEffectiveness)
        end)

        it("data.skills.Firebrand stats carry eff 1.25", function()
            local st = data.skills.Firebrand and data.skills.Firebrand.stats
            assert.is_not_nil(st, "data.skills.Firebrand.stats must exist")
            assert.are.equals(2, st.melee_base_fire_damage)
            assert.are.equals(1.25, st.damageEffectiveness)
        end)
    end)
end)
