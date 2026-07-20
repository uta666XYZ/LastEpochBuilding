-- @leb-regression-guard:minion-granted-weapon-attack-base-inheritance
-- See REGRESSION_GUARDS.md "minion-granted-weapon-attack-base-inheritance".
-- Validation provenance is retained in maintainer notes.

describe("MinionGrantedWeaponAttackBase #minionweaponbase parser + cache contract", function()

    it("' Bears use Swipe' emits a PrimalBear ExtraMinionSkill grant flagged inheritsMinionAttackBase", function()
        local m = modLib.parseMod(" Bears use Swipe")
        assert.is_table(m, "' Bears use Swipe' must parse to a mod list")
        assert.are.equals("ExtraMinionSkill", m[1].name)
        assert.are.equals("Swipe", m[1].value.skillId)
        assert.are.equals("PrimalBear", m[1].value.minionList[1])
        -- the flag is what routes createMinionSkills onto the clone-primary path; a ModCache
        -- regen that drops it silently reverts Swipe to the base-2 under-model (x2.23 gap).
        assert.is_true(m[1].value.inheritsMinionAttackBase,
            "Swipe grant must carry inheritsMinionAttackBase=true (ModCache c[' Bears use Swipe'] flag)")
    end)

    it("the minion's primary attack still carries the base that Swipe inherits (base 50)", function()
        -- The clone source: the bear's basic attack. If this base changes, Swipe follows (by design).
        local s = data.skills["PrimalBear 01 melee attack"]
        assert.is_table(s, "PrimalBear 01 melee attack must exist in data.skills")
        assert.are.equal(50, s.stats.melee_base_physical_damage)
        assert.is_true(s.baseFlags.attack)
        assert.is_true(s.baseFlags.melee)
    end)

    it("the player Swipe skill keeps its tiny declared intrinsic (base 2) — the fix does NOT edit skill data", function()
        -- The fix lives in createMinionSkills (clone at build time), NOT by editing Swipe's data,
        -- so the player-facing Swipe skill is unchanged; only the bear's granted copy is re-based.
        local s = data.skills.Swipe
        assert.is_table(s)
        assert.are.equal(2, s.stats.melee_base_physical_damage)
    end)

    -- Earthquake shares the SAME weapon-base-inheritance mechanism as Swipe (both are player
    -- weapon skills granted to the bear) but additionally carries an effectiveness ratio: the
    -- bear's Earthquake hits at added-damage-effectiveness 6 vs the Melee/Swipe eff 1 (datamine
    -- pid 261582/263683). F4 oracle (same capture): EQ ref-slam == Melee-clone x 6 (probe:
    -- 29298.5 = 4883.1 x 6, MORE 59.4 = 9.9 x 6, NO -60% Earthquake-node leak). The eff ratio is
    -- carried ON THE GRANT (minionAttackEffectiveness) and applied ONLY to the bear's clone in
    -- createMinionSkills, so the SHARED player Shaman EarthquakeSlam is untouched.
    it("' Bear Can Use Earthquake' emits a flagged grant carrying eff 6 (inheritsMinionAttackBase + minionAttackEffectiveness=6)", function()
        local m = modLib.parseMod(" Bear Can Use Earthquake")
        assert.is_table(m, "' Bear Can Use Earthquake' must parse to a mod list")
        assert.are.equals("ExtraMinionSkill", m[1].name)
        assert.are.equals("EarthquakeSlam", m[1].value.skillId)
        assert.are.equals("PrimalBear", m[1].value.minionList[1])
        assert.is_true(m[1].value.inheritsMinionAttackBase,
            "EQ grant must carry inheritsMinionAttackBase=true (ModCache c[' Bear Can Use Earthquake'] flag)")
        assert.are.equal(6, m[1].value.minionAttackEffectiveness,
            "EQ grant must carry minionAttackEffectiveness=6 (datamine eff; a ModCache regen dropping it reverts EQ to eff 1)")
    end)

    it("' Initial Slam Occurs Three Times' (eq5s-21 Seismic Tide) emits the EarthquakeSeismicTide flag", function()
        -- Datamine (tree_0.json eq5s-21): Earthquake's initial slam occurs 3x at 0.70/0.95/1.30x
        -- (30% reduced / 5% reduced / 30% increased damage), sum 2.95. ModCache baked it {{},""}
        -- (no-op) so the triple-slam was unmodeled. The flag is INERT on its own (no damage stat);
        -- createMinionSkills reads it to fuse the bear EQ's per-cast slam-sum. A regen dropping this
        -- back to a no-op silently reverts the bear EQ to a single slam (x2.95 per-cast under).
        local m = modLib.parseMod(" Initial Slam Occurs Three Times")
        assert.is_table(m, "' Initial Slam Occurs Three Times' must parse to a mod list")
        assert.are.equals("EarthquakeSeismicTide", m[1].name)
        assert.are.equals("FLAG", m[1].type)
        assert.is_true(m[1].value)
    end)

    it("the EQ grant declares the Seismic Tide slam-sum (minionSlamNodeMod + minionSlamSum=2.95)", function()
        -- The triple-slam is applied ONLY when the player has eq5s-21 (the flag exists) AND the
        -- grant declares the association, so the shared player Earthquake is never triple-slammed
        -- by this minion-only path. 2.95 = 0.70+0.95+1.30 (datamine).
        local m = modLib.parseMod(" Bear Can Use Earthquake")
        assert.are.equals("EarthquakeSeismicTide", m[1].value.minionSlamNodeMod)
        assert.are.equal(2.95, m[1].value.minionSlamSum)
    end)

    it("the player EarthquakeSlam skill is not edited by the eff-6 fix (bear-specific, shared skill untouched)", function()
        -- eff-6 is applied as a per-clone MORE gated on the grant flag, NOT by editing the shared
        -- EarthquakeSlam skill data. A player Shaman Earthquake must keep the source effectiveness.
        local s = data.skills.EarthquakeSlam
        assert.is_table(s, "EarthquakeSlam must exist in data.skills")
        -- the source declares eff 2 (LEB skills.json); the bear's 6 is a grant-scoped ratio, not
        -- a data edit, so this must stay whatever the shared source is (assert it is NOT 6).
        assert.are_not.equal(6, s.stats and s.stats.damageEffectiveness,
            "EarthquakeSlam data eff must NOT be globally set to 6 (that would 3x every player Earthquake)")
    end)
end)
