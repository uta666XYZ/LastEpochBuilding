-- @leb-regression-guard:firebrand-flame-wave-grant
-- @leb-regression-guard:flamewave-caster-hit-context-inc
-- See REGRESSION_GUARDS.md "firebrand-flame-wave-grant" +
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("FlameWave base data is recorded (datamined, no fabrication)", function()
    it("FlameWave carries the datamined Fire Spell HIT base", function()
        local d = data.skills.FlameWave
        assert.is_table(d, "FlameWave must exist in data.skills")
        assert.are.equals("Flame Wave", d.name)
        -- damageTags 256 = Spell bit only (the Fire type is the damage breakdown, not a tag).
        assert.are.equals(256, d.skillTypeTags, "datamined damageTags 256 = Spell")
        assert.are.equals(60, d.stats.spell_base_fire_damage, "datamined base 60 Fire")
        assert.are.equals(3, d.stats.damageEffectiveness, "addedDamageScaling 3.0 (300% effectiveness)")
        assert.are.equals(5, d.stats.critChance, "datamined critChance 0.05 -> 5%")
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"],
            "datamined critMultiplier 2.0 -> base_critical_strike_multiplier_+ 100 (+100% = x2.0)")
        -- isHit=1: a HIT spell (not a DoT, not an ailment).
        assert.is_true(d.baseFlags.spell)
        assert.is_true(d.baseFlags.hit)
        assert.is_nil(d.baseFlags.dot)
        assert.is_nil(d.baseFlags.ailment)
        assert.is_nil(d.stats.damage_interval)
    end)

    it("socketing Flame Wave directly computes a positive fire spell hit (base 60 x attr INC x crit blend)", function()
        newBuild()
        for _, k in ipairs({ "enemyFireResist", "enemyArmour" }) do
            build.configTab.input[k] = nil
        end
        build.skillsTab:SelSkill(1, "FlameWave")
        runCallback("OnFrame")

        local o = build.calcsTab.mainOutput
        -- per-hit (speed-independent): base 60 with the inherent 5% crit at x2.0 and
        -- no added damage. The entry's baseMods (guard flamewave-caster-hit-context-inc)
        -- give +4% INC per player Int + Dex, so the empty-build expectation is
        -- 60 * (1 + 0.04*(Int+Dex)) * (0.95 + 2.0*0.05).
        assert.is_truthy(o.AverageHit and o.AverageHit > 0,
            "Flame Wave base must emit a positive hit (was structurally 0 / absent)")
        local attrInc = 1 + 0.04 * ((o.Int or 0) + (o.Dex or 0))
        local expected = 60 * attrInc * 1.05
        assert.is_true(math.abs(o.AverageHit - expected) < expected * 0.05,
            ("empty-build per-hit must be ~%.1f (base 60 x attr INC %.2f x 1.05 crit blend), got %s")
                :format(expected, attrInc, tostring(o.AverageHit)))

        local ms = build.calcsTab.mainEnv.player.mainSkill
        assert.is_true(ms.skillFlags.spell, "Flame Wave must be a spell")
        assert.is_true(ms.skillFlags.hit, "Flame Wave must hit")
        assert.is_nil(ms.skillFlags.dot, "Flame Wave is a hit, not a DoT")
    end)
end)

describe("FlameWave grant is NODE-GATED on f1b4d-22 (Pyre)", function()
    it("Firebrand grants exactly FlameWave, gated on f1b4d-22", function()
        local grants = data.subSkillGrants.Firebrand
        assert.is_table(grants, "Firebrand must be in the grant registry")
        assert.are.equals(1, #grants)
        assert.are.equals("FlameWave", grants[1].skillId)
        assert.are.equals("f1b4d-22", grants[1].requiresNode,
            "the Flame Wave grant must be node-conditional on the f1b4d-22 'Pyre' node")
        -- scope: FlameWave is granted ONLY by Firebrand, nothing else.
        local owners = {}
        for parentId, gs in pairs(data.subSkillGrants) do
            for _, g in ipairs(gs) do
                if g.skillId == "FlameWave" then owners[#owners + 1] = parentId end
            end
        end
        assert.are.same({ "Firebrand" }, owners, "FlameWave must be granted only by Firebrand")
    end)

    it("socketing Firebrand WITHOUT f1b4d-22 does NOT inject Flame Wave", function()
        newBuild()
        build.skillsTab:SelSkill(1, "Firebrand")
        runCallback("OnFrame")

        -- no granted sub-skill group pointing at Firebrand (node not allocated)...
        for _, group in pairs(build.skillsTab.socketGroupList) do
            assert.is_not.equal("Firebrand", group.subSkillOf,
                "Flame Wave must not be granted when f1b4d-22 is not allocated")
        end
        -- ...and Flame Wave is not in the active skill list (Firebrand itself still
        -- deals its own damage; only the Flame Wave grant is gated off).
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local ge = s.activeEffect and s.activeEffect.grantedEffect
            assert.is_not.equal("Flame Wave", ge and ge.name,
                "Flame Wave must not appear without the f1b4d-22 node (grant is node-gated)")
        end
    end)

    it("the f1b4d-22 'Pyre' node exists in the loaded tree and carries the Flame Wave-On-Hit gate", function()
        newBuild()
        local node = build.spec.nodes["f1b4d-22"]
        assert.is_truthy(node, "f1b4d-22 must exist in the loaded 1.4 tree")
        assert.are.equals("Firebrand", node.skillId,
            "f1b4d-22 must scope to the Firebrand specialization tree (skillId Firebrand)")
        local stats = node.stats or {}
        local hasFlameWave = false
        for _, s in ipairs(stats) do
            if tostring(s):find("Flame Wave On Hit", 1, true) then hasFlameWave = true end
        end
        assert.is_true(hasFlameWave,
            "f1b4d-22 must carry ' Flame Wave On Hit' (the node the grant keys on)")
    end)
end)

describe("FlameWave calc wiring (source invariant)", function()
    it("CalcSetup gates the grant on env.allocNodes[requiresNode]", function()
        local text = assert(readFile("Modules/CalcSetup.lua"))
        assert.is_truthy(text:find("grant.requiresNode", 1, true),
            "CalcSetup grant loop must honor the optional requiresNode gate")
    end)
end)

-- @leb-regression-guard:flamewave-caster-hit-context-inc
describe("FlameWave scaling = caster hit context for INC only", function()
    it("the grant carries inheritCasterHitContextInc and the wave carries Firebrand's attribute baseMods", function()
        local grant = data.subSkillGrants.Firebrand[1]
        assert.is_true(grant.inheritCasterHitContextInc,
            "the Flame Wave grant must compute its hit INC in the caster's context (2026-07-04 paired captures)")
        -- context inheritance includes the caster's per-attribute INC: the wave's
        -- baseMods must be exactly Firebrand's two attribute lines (the fi9 ability's
        -- own datamined attributeScalings is EMPTY -- these are inherited, not native).
        -- (baseMods are parsed at load; compare structure, not the per-skill source.)
        local function attrIncSet(mods)
            local set = { }
            for _, m in ipairs(mods or { }) do
                if m.name == "Damage" and m.type == "INC" and m[1] and m[1].type == "PerStat" then
                    set[m[1].stat] = m.value
                end
            end
            return set
        end
        assert.are.same({ Int = 4, Dex = 4 }, attrIncSet(data.skills.FlameWave.baseMods),
            "FlameWave baseMods must carry 4% INC Damage per Int and per Dex (caster context)")
        assert.are.same(attrIncSet(data.skills.Firebrand.baseMods), attrIncSet(data.skills.FlameWave.baseMods),
            "FlameWave's attribute INC must mirror Firebrand's (inherited, not invented)")
        -- the wave itself stays a SPELL (crit/added/MORE reads are spell-side): the
        -- engine truth (FlameWave damageTags Spell; CSV critMult 3.135 vs FB 4.085).
        assert.are.equals(256, data.skills.FlameWave.skillTypeTags)
        assert.is_true(data.skills.FlameWave.baseFlags.spell)
        assert.is_nil(data.skills.FlameWave.baseFlags.melee,
            "the wave must NOT be melee-flagged: melee MOREs / melee typed flat / melee crit do not reach it")
    end)

    it("allocating f1b4d-22 injects Flame Wave with the context flag on its socket group", function()
        newBuild()
        build.skillsTab:SelSkill(1, "Firebrand")
        local node = build.spec.nodes["f1b4d-22"]
        assert.is_truthy(node, "f1b4d-22 must exist")
        node.alloc = 1
        build.spec.allocNodes[node.id or "f1b4d-22"] = node
        build.buildFlag = true
        runCallback("OnFrame")

        local wave
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local ge = s.activeEffect and s.activeEffect.grantedEffect
            if ge and ge.name == "Flame Wave" then wave = s end
        end
        assert.is_truthy(wave, "Flame Wave must be granted when f1b4d-22 is allocated")
        assert.is_truthy(wave.socketGroup, "the granted wave must have a socket group")
        assert.is_true(wave.socketGroup.inheritCasterHitContextInc == true,
            "the socket group must carry inheritCasterHitContextInc for calcDamage")
        assert.are.equals("Firebrand", wave.socketGroup.subSkillOf)
        -- the wave stays a spell (NOT melee) even with the context flag
        assert.is_true(wave.skillFlags.spell)
        assert.is_nil(wave.skillFlags.melee)
    end)

    it("ModStore semantics: melee-keyword INC applies under the caster context cfg but not the wave's own cfg; MORE stays own-cfg", function()
        newBuild()
        build.skillsTab:SelSkill(1, "Firebrand")
        local node = build.spec.nodes["f1b4d-22"]
        node.alloc = 1
        build.spec.allocNodes["f1b4d-22"] = node
        build.buildFlag = true
        runCallback("OnFrame")

        local wave
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local ge = s.activeEffect and s.activeEffect.grantedEffect
            if ge and ge.name == "Flame Wave" then wave = s end
        end
        assert.is_truthy(wave, "Flame Wave must be granted")
        local sml, cfg = wave.skillModList, wave.skillCfg

        -- inject a melee-keyword INC + a Firebrand-SkillName INC + a melee-keyword flat
        -- (the ModCache encoding for "+X% increased Melee Damage" is flags=0,
        -- keywordFlags=KeywordFlag.Melee; tree/skill mods scope via SkillName)
        sml:NewMod("Damage", "INC", 37, "spec:melee-INC", 0, KeywordFlag.Melee)
        sml:NewMod("Damage", "INC", 11, "spec:fb-scoped-INC", 0, 0, { type = "SkillName", skillName = "Firebrand" })
        sml:NewMod("FireDamage", "BASE", 23, "spec:melee-flat", 0, KeywordFlag.Melee)

        -- replicate calcDamage's context construction (CalcOffence,
        -- guard flamewave-caster-hit-context-inc)
        local parent = data.skills[wave.socketGroup.subSkillOf]
        local incCfg = copyTable(cfg, true)
        local ctxFlags = 0
        for flagName in pairs(parent.baseFlags or { }) do
            local flagBit = ModFlag[flagName:gsub("^%l", string.upper)]
            if flagBit then ctxFlags = bit.bor(ctxFlags, flagBit) end
        end
        incCfg.flags = bit.bor(incCfg.flags or 0, ctxFlags)
        incCfg.keywordFlags = bit.bor(incCfg.keywordFlags or 0, ctxFlags)
        incCfg.skillName = parent.name

        local ownInc = sml:Sum("INC", cfg, "Damage")
        local ctxInc = sml:Sum("INC", incCfg, "Damage")
        assert.are.equals(48, ctxInc - ownInc,
            "caster context must pick up the melee-keyword INC (37) + the Firebrand-SkillName INC (11) that the wave's own spell cfg filters out")

        -- melee-keyword FLAT must stay excluded under the wave's OWN cfg (added pools
        -- are never read with the context cfg -- wave cold = 0 in-game)
        local flatOwn = sml:Sum("BASE", cfg, "FireDamage")
        sml:NewMod("FireDamage", "BASE", 100, "spec:spell-flat", 0, KeywordFlag.Spell)
        assert.are.equals(flatOwn + 100, sml:Sum("BASE", cfg, "FireDamage"),
            "spell-keyword flat must reach the wave's own added pool")
        -- (the melee-keyword flat 23 injected above must NOT be in the own-cfg pool)
        local list = sml:Tabulate("BASE", cfg, "FireDamage")
        for _, e in ipairs(list) do
            assert.is_not.equal("spec:melee-flat", e.mod and e.mod.source,
                "melee-keyword flat must not reach the wave's own (spell) added pool")
        end
    end)
end)
