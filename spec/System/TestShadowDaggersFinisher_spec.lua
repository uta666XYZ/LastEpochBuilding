-- @leb-regression-guard:shadow-daggers-finisher (+ sceptre-not-mace,
-- See REGRESSION_GUARDS.md "shadow-daggers-finisher" / "sceptre-not-mace".
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ShadowDaggersFinisher", function()
    describe("data shape (runtime data.skills)", function()
        local sd
        setup(function()
            sd = data.skills["Ailment_ShadowDaggers"]
        end)

        it("entry exists with the LETools ailment_9 finisher stats", function()
            assert.is_table(sd, "Ailment_ShadowDaggers must exist in data.skills")
            assert.are.equal(68, sd.stats.melee_base_physical_damage)
            assert.are.equal(3.4, sd.stats.damageEffectiveness)
            assert.are.equal(100, sd.stats.critChance)
            assert.are.equal(100, sd.stats["base_critical_strike_multiplier_+"])
        end)

        it("is MELEE-only for modifier matching (skillTypeTags 512, no Throwing bit)", function()
            assert.are.equal(512, sd.skillTypeTags,
                "in-game: Rogue-52 throwing +12 / Rogue-49 throwing INC do not apply to the finisher")
        end)

        it("does not carry the ailment baseFlag (it zeroes damageEffectiveness)", function()
            assert.is_table(sd.baseFlags)
            assert.is_nil(sd.baseFlags.ailment)
            assert.is_true(sd.baseFlags.melee)
            assert.is_true(sd.baseFlags.hit)
        end)

        it("is marked ailmentFinisher (strict kw / no weapon flats / no parent tree)", function()
            assert.is_true(sd.ailmentFinisher,
                "the three finisher scaling rules hang off this single data flag")
        end)
    end)

    describe("sceptre-not-mace (runtime data)", function()
        it("Sceptre has its own weaponTypeInfo flag", function()
            local info = data.weaponTypeInfo["Sceptre"]
            assert.is_table(info)
            assert.are.equal("Sceptre", info.flag,
                "LE sceptres are not maces; flag='Mace' was a PoE-ism from upstream PoB")
            assert.are.equal("Sceptre", info.label)
        end)

        it("ModFlag.Sceptre exists with the shared Unsupported bit (flag-level no-op)", function()
            assert.are.equal(ModFlag.Mace, ModFlag.Sceptre,
                "SkillType.Sceptre must carry the same Unsupported bit so weapon-flag matching is unchanged")
        end)

        it("real maces still publish UsingMace (wielding-weapon-conditions intact)", function()
            assert.are.equal("Mace", data.weaponTypeInfo["One-Handed Mace"].flag)
            assert.are.equal("Mace", data.weaponTypeInfo["Two-Handed Mace"].flag)
        end)
    end)

    describe("source contracts", function()
        local activeSkillText, offenceText

        setup(function()
            activeSkillText = readSource("Modules/CalcActiveSkill.lua")
            offenceText = readSource("Modules/CalcOffence.lua")
        end)

        it("CalcActiveSkill gates cfg.groupSource on ailmentFinisher", function()
            assert.is_truthy(activeSkillText:find(
                'if not activeGrantedEffect.ailmentFinisher then', 1, true),
                "the parent-tree SkillId channel must be skippable per granted skill")
        end)

        it("CalcActiveSkill gives ailmentFinisher melee skills the strict Melee keyword", function()
            assert.is_truthy(activeSkillText:find(
                'if activeGrantedEffect.ailmentFinisher then', 1, true))
            assert.is_truthy(activeSkillText:find(
                'skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Melee)', 1, true),
                "finisher must take KeywordFlag.Melee, not the Attack bundle")
        end)

        it("CalcOffence excludes weapon-sourced flats for ailmentFinisher skills", function()
            assert.is_truthy(offenceText:find(
                'local noWeaponAdded = activeSkill.activeEffect.grantedEffect.ailmentFinisher', 1, true))
            assert.is_truthy(offenceText:find(
                'addedDmg = addedDmg - weaponAdded', 1, true),
                "weapon flats must leave the pool entirely (neither convert nor remain)")
            assert.is_truthy(offenceText:find(
                '@leb-regression-guard:ailment-finisher-scaling', 1, true))
        end)

        it("weaponModSources is built for the ailment-finisher path ONLY (all other skills keep weapon flats type-preserved)", function()
            -- Since the 2026-06-13 weapon-added-preserved-through-conversion fix, NO skill folds
            -- weapon flats into the convertible base except an ailment-finisher (which DROPS
            -- them). The convertAllAddedDamage carve-out (forms etc.) was removed 2026-06-14
            -- after in-game disproved it (Swarmblade keeps its weapon physical), so the gate is
            -- now bare `noWeaponAdded` -- see weapon-added-base-only-universal.
            assert.is_truthy(offenceText:find(
                'if noWeaponAdded and actor.itemList then', 1, true))
            assert.is_falsy(offenceText:find('skillHasConversion and convertAllAdded', 1, true),
                'the convertAllAddedDamage carve-out gate must be gone')
        end)
    end)
end)
