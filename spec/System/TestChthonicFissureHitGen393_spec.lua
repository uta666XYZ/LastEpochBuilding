-- @leb-regression-guard: chthonic-fissure-gen393-hit
-- @leb-regression-guard: chthonic-fissure-hit-pyrochasm-gated
-- spec. See REGRESSION_GUARDS.md "chthonic-fissure-gen393-hit".
-- Validation provenance is retained in maintainer notes.

describe("ChthonicFissureHitGen393", function()
    it("ModParser maps the CF baseMod sentinel to a Chthonic-Fissure-scoped gen393 trigger", function()
        local mods = modLib.parseMod("Chthonic Fissure also casts Chthonic Fissure Hit")
        assert.is_not_nil(mods, "modLib.parseMod must return a mod list")
        assert.are.equals(1, #mods)
        assert.are.equals("ChanceToTriggerOnHit_Warlock Unique Chthonic Fissure Hit", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(100, mods[1].value)
        -- scoped to the SOURCE skill (Chthonic Fissure) via a SkillName tag —
        -- mirrors the FW handler; here it's belt-and-suspenders because the
        -- sentinel lives in CF's baseMods (already skill-localised) but the
        -- tag keeps both CF trigger sites uniform for diffability.
        assert.is_not_nil(mods[1][1], "trigger mod must carry a tag")
        assert.are.equals("SkillName", mods[1][1].type)
        assert.are.equals("Chthonic Fissure", mods[1][1].skillName)
    end)

    it("skills.json defines Chthonic Fissure Hit with the gen393 base profile", function()
        local cfh = data.skills["Warlock Unique Chthonic Fissure Hit"]
        assert.is_not_nil(cfh, "Chthonic Fissure Hit skill entry must exist")
        assert.are.equals("Chthonic Fissure Hit", cfh.name)
        assert.are.equals("ch0fs", cfh.treeId,
            "must share Chthonic Fissure's treeId so CF tree (fire->phys, per-Int) propagates")
        assert.is_truthy(cfh.baseFlags and cfh.baseFlags.spell and cfh.baseFlags.hit,
            "Chthonic Fissure Hit is a spell hit")
        -- The gen393/gen404 shared baseDamageStats:
        assert.are.equals(60, cfh.stats.spell_base_fire_damage)
        assert.are.equals(3.0, cfh.stats.damageEffectiveness)
        assert.are.equals(5, cfh.stats.critChance)
        assert.are.equals("chthonicFissureHit", cfh.playerAbilityID,
            "playerAbilityID must match the in-game internalName (gen393)")
    end)

    it("Chthonic Fissure's baseMods does NOT carry the gen393 trigger (it is node-gated)", function()
        local cf = data.skills["Warlock 04 Chthonic Fissure"]
        assert.is_not_nil(cf, "Chthonic Fissure skill entry must exist")
        -- The unconditional baseMods sentinel was REMOVED: the gen393 hit is
        -- granted by the Pyrochasm node (ch0fs-21), not by the base skill. A
        -- non-Pyrochasm CF build must NOT receive the phantom hit.
        for _, m in ipairs(cf.baseMods) do
            assert.are_not.equals("ChanceToTriggerOnHit_Warlock Unique Chthonic Fissure Hit", m.name,
                "CF baseMods must NOT carry the gen393 trigger -- re-adding it gives "
                .. "every CF build a phantom ~31%-of-CF hit even without Pyrochasm")
        end
    end)

    it("Pyrochasm (ch0fs-21) rewrites its node stat into the gen393-trigger sentinel", function()
        -- ch0fs-21 grants the initial hit. Its bare display stat
        -- " Fissure Fire Damage on Hit" compiles to nothing on its own, so a
        -- LE_TREE_NODE_STAT_REWRITE entry turns it into the sentinel string that
        -- ModParser maps to the gen393 trigger. Gate = node allocation.
        local rewrites = LE_TREE_NODE_STAT_REWRITE["ch0fs-21"]
        assert.is_not_nil(rewrites, "ch0fs-21 must have a stat rewrite (the gen393 gate)")
        local raw = " Fissure Fire Damage on Hit"
        local rewritten = raw
        for _, rw in ipairs(rewrites) do
            rewritten = (rewritten:gsub(rw.pat, rw.repl))
        end
        assert.are.equals("Chthonic Fissure also casts Chthonic Fissure Hit", rewritten,
            "the Pyrochasm node stat must rewrite to the gen393-trigger sentinel")
        -- and that sentinel must still parse to the trigger mod (closes the loop)
        local mods = modLib.parseMod(rewritten)
        assert.is_not_nil(mods)
        assert.are.equals("ChanceToTriggerOnHit_Warlock Unique Chthonic Fissure Hit", mods[1].name)
        assert.are.equals(100, mods[1].value)
    end)
end)
