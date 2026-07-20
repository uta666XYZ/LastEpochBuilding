-- @leb-regression-guard: spellblade-weapon-melee-added-gained-as-spell
-- Locks the LE Spellblade MASTERY innate "40% of added melee damage on weapons is
-- also gained as added spell damage" (property 646). Two halves:
--
-- (1) PARSE: ModParser must turn the mastery text into a real
--     WeaponMeleeAddedGainedAsSpell BASE mod carrying the percentage -- NOT the
--     recognition-only LEB_NotSupported no-op it used to become (a static ModCache
--     entry mapped it to LEB_NotSupported; that entry was deleted + a specific
--     specialModList rule added so live parse yields the real mod). Bug this locks:
--     the transfer was dropped, so a Spellblade's spell-added pool was under-read by
--     40% of its weapon melee added.
--
-- (2) CALC: CalcOffence must take X% of each equipped WEAPON item's melee-tagged
--     ADDED flat (typeless "Damage" and typed "<T>Damage", keywordFlags Melee) and
--     re-grant it as Spell-keyword added of the same name/type -- additive, type-
--     preserving, WEAPON-scoped (rings/tree melee excluded). For the tree-gated
--     Elemental Nova a typed transfer is gated on a node base for that type so it
--     cannot surface a spurious element.
--
-- Grounding: Tru_Flamer (Spellblade, 40%), weapon Jasper's Searing Pride: typeless
-- melee 169 (94+75) x0.40 = 67.6 -> E.Nova spell-added pool 110 -> 177.6 (engine
-- Spell add 177.6, exact); weapon melee-fire 117 x0.40 = 46.8 -> engine SpellFire
-- delta 46.8. On the lightning-only isolation (save-08) this takes the gated
-- lightning per-hit pre-mit 56.6 (pre-Bug1) / ~825 (Bug1 only) -> ~1304 vs in-game
-- 1379.6 (~5.5%, residual = en6-tree MORE/buff). See REGRESSION_GUARDS.md >
-- "spellblade-weapon-melee-added-gained-as-spell".

-- A corpus Spellblade build whose DEFAULT main skill is a SPELL (Lightning Blast) that
-- receives the transfer, so the granted mods are visible on the selected skill. It
-- allocates the mastery + carries weapon melee added (full-corpus scan: FullDPS
-- +22.58%, the mastery was previously unmodeled). The transfer mods are per-calc on
-- the SELECTED skill's modList, so the fixture must have a spell as its main skill (on
-- a melee-main build the transfer still fires -- into triggered spells -- but is not
-- visible on the melee main). Only the calc test needs it; the parse tests are
-- fixture-free.
local FIXTURE = "QnagvWp8 lv98 Spellblade"

describe("SpellbladeWeaponMeleeAddedGainedAsSpell", function()
    before_each(function()
        newBuild()
    end)

    -- 1. PARSE contract (fixture-free) --------------------------------------------
    it("mastery text parses to WeaponMeleeAddedGainedAsSpell BASE 40 (not LEB_NotSupported)", function()
        local list, extra = modLib.parseMod("40% of added melee damage on weapons is also gained as added spell damage")
        assert.is_not_nil(list, "must parse")
        assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
        assert.are.equal(1, #list)
        local mod = list[1]
        assert.are.equal("WeaponMeleeAddedGainedAsSpell", mod.name)
        assert.are.equal("BASE", mod.type)
        assert.are.equal(40, mod.value)
        assert.are_not.equal("LEB_NotSupported", mod.name)
    end)

    it("percentage is captured from the text (not hardcoded 40)", function()
        local list = modLib.parseMod("25% of added melee damage on weapons is also gained as added spell damage")
        assert.is_not_nil(list)
        assert.are.equal(1, #list)
        assert.are.equal("WeaponMeleeAddedGainedAsSpell", list[1].name)
        assert.are.equal(25, list[1].value)
    end)

    -- The ITEM-AFFIX 988 variant ("+X% Added Melee Damage gained as Added Spell Damage",
    -- corrupted 1H-sword sealed affix) emits the SAME mod and STACKS with the mastery
    -- (engine-confirmed via SpellPhysical capture 164358: weapon phys-melee 45 -> physical
    -- spell-added 22.5 = mastery 40% + affix 10% = 50%). It must NOT fall through to the
    -- generic gained-as-added nsAny no-op (its ModCache entries were deleted).
    it("item-affix 988 text parses to the same WeaponMeleeAddedGainedAsSpell mod (stacks w/ mastery)", function()
        local list = modLib.parseMod("+10% Added Melee Damage gained as Added Spell Damage")
        assert.is_not_nil(list, "affix must parse")
        assert.are.equal(1, #list)
        assert.are.equal("WeaponMeleeAddedGainedAsSpell", list[1].name)
        assert.are.equal("BASE", list[1].type)
        assert.are.equal(10, list[1].value)
        assert.are_not.equal("LEB_NotSupported", list[1].name)
    end)

    -- 2. CALC contract (corpus fixture; heavy build -> opt-in) --------------------
    -- The only corpus Spellblade builds whose DEFAULT main skill is a SPELL that
    -- receives the transfer (so it is visible on the selected skill) are lv95-98 --
    -- heavy enough that loadBuildFromXML OOM-crashes LuaJIT under busted COVERAGE
    -- (reference_snapshot_regen_pitfalls_windows trap 5). So this test is opt-in:
    -- it pends in the default (coverage) suite and runs on demand with
    -- LEB_RUN_HEAVY_SPEC=1 (coverage off) -- verified 3/3. The calc contract is
    -- otherwise locked by the 5 regen'd corpus snapshots + the inline
    -- @leb-regression-guard in CalcOffence (any regression flips their FullDPS).
    it("Spellblade build: weapon melee added is re-granted as Spell-keyword added at X%", function()
        if not os.getenv("LEB_RUN_HEAVY_SPEC") then
            pending("heavy lv98 corpus load OOM-crashes LuaJIT under busted coverage; run with LEB_RUN_HEAVY_SPEC=1 + coverage off (verified). Calc locked by the regen'd snapshots + inline guard.")
            return
        end
        local path = "../spec/TestBuilds/1.4/" .. FIXTURE .. ".xml"
        local f = io.open(path, "r")
        if not f then
            pending("Spellblade fixture '" .. FIXTURE .. "' missing in this worktree; covered where spec/TestBuilds is populated")
            return
        end
        local xml = f:read("*a"); f:close()
        loadBuildFromXML(xml, FIXTURE)
        runCallback("OnFrame")

        local p = (build.calcsTab.calcsEnv or build.calcsTab.mainEnv).player
        local ms = p.mainSkill
        -- the mastery mod is present (this build allocates Spellblade mastery)
        local pct = ms.skillModList:Sum("BASE", ms.skillCfg, "WeaponMeleeAddedGainedAsSpell")
        assert.is_true((pct or 0) > 0, "Spellblade mastery WeaponMeleeAddedGainedAsSpell must be present")

        -- at least one added-damage contribution sourced from "Spellblade Mastery"
        -- (the weapon-melee->spell transfer) is present on the selected spell skill.
        -- Use Tabulate (the transfer mods surface through the resolved mod list, not
        -- the raw base .mods table).
        local found = false
        for _, nm in ipairs({ "Damage", "FireDamage", "ColdDamage", "LightningDamage", "VoidDamage" }) do
            for _, e in ipairs(ms.skillModList:Tabulate("BASE", ms.skillCfg, nm)) do
                if e.mod and e.mod.source == "Spellblade Mastery" then found = true end
            end
        end
        assert.is_true(found, "a 'Spellblade Mastery' Spell-added contribution must be granted from weapon melee added")
    end)

    -- 3. CALC contract for @leb-regression-guard:elemental-nova-nonelement-added-not-gated -----
    -- The nova weapon-melee->spell transfer gate must let a NON-element type (Physical)
    -- through, so Elemental Nova emits a physical component from a physical-melee weapon
    -- transferred to spell (mastery/affix). Only the three nova ELEMENTS (Fire/Cold/Lightning)
    -- are gated on their node. No corpus build has E.Nova + the mastery/affix + a physical-
    -- melee weapon (corpus E.Nova builds are Sorcerers with no mastery), and the only real
    -- one -- Tru_Flamer + a Marauder's Longsword (affix 988) -- is a lv100 save that OOMs
    -- LuaJIT under busted coverage. So (like the calc test above) this is opt-in: it pends
    -- in the default suite and runs on demand with LEB_RUN_HEAVY_SPEC=1 (coverage off) +
    -- LEB_NOVA_PHYS_SAVE=<the .epoch> (an env var, so no absolute path is baked into this
    -- tracked file). Default-suite protection = the inline guard + the 0-change corpus blast.
    -- Verified on demand: E.Nova PhysicalHitAverage 0 (pre-fix) -> 281 (in-game phys 183/hit).
    it("Elemental Nova emits a physical hit from a non-element weapon-melee->spell transfer", function()
        if not os.getenv("LEB_RUN_HEAVY_SPEC") then
            pending("heavy lv100 nova+physical-weapon save; run with LEB_RUN_HEAVY_SPEC=1 + LEB_NOVA_PHYS_SAVE=<epoch> (coverage off). Locked by the inline guard + 0-change corpus blast.")
            return
        end
        local savePath = os.getenv("LEB_NOVA_PHYS_SAVE")
        local sf = savePath and io.open(savePath, "rb")
        if not sf then
            pending("set LEB_NOVA_PHYS_SAVE to the Tru_Flamer + Marauder's Longsword (affix 988) .epoch capture")
            return
        end
        local raw = sf:read("*a"); sf:close()
        newBuild()
        loadBuildFromJSON((raw:gsub("^EPOCH", "")))
        build.buildFlag = true
        runCallback("OnFrame")
        for i, g in ipairs(build.skillsTab.socketGroupList) do
            if g.displaySkillList then
                for k, sk in ipairs(g.displaySkillList) do
                    local ge = sk.activeEffect and sk.activeEffect.grantedEffect
                    if ge and tostring(ge.name) == "Elemental Nova" then
                        build.mainSocketGroup = i
                        build.calcsTab.input.skill_number = i
                        g.mainActiveSkill = k
                        g.mainActiveSkillCalcs = k
                    end
                end
            end
        end
        build.calcsTab:BuildOutput()
        local o = (build.calcsTab.calcsEnv or build.calcsTab.mainEnv).player.output
        assert.is_true((o.PhysicalHitAverage or 0) > 0,
            "nova must emit a physical hit from the transferred non-element (physical) added (got "..tostring(o.PhysicalHitAverage)..")")
    end)
end)
