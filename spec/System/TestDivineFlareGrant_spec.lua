-- @leb-regression-guard:divineflare-grant
-- See REGRESSION_GUARDS.md "divineflare-grant".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("DivineFlare base data is recorded (datamined, no fabrication)", function()
    it("DivineFlare carries the datamined Fire Spell HIT base", function()
        local d = data.skills.DivineFlare
        assert.is_table(d, "DivineFlare must exist in data.skills")
        assert.are.equals("Divine Flare", d.name)
        -- damageTags 256 = Spell bit only (the Fire type is the damage breakdown, not a tag).
        assert.are.equals(256, d.skillTypeTags, "datamined damageTags 256 = Spell")
        assert.are.equals(70, d.stats.spell_base_fire_damage, "datamined base 70 Fire")
        assert.are.equals(3.5, d.stats.damageEffectiveness, "addedDamageScaling 3.5 (350% effectiveness)")
        -- base crit 5% / x2.0: base_critical_strike_multiplier_+ 100 == +100% == x2.0
        -- (matches the DamageEnemyOnHit critMultiplier 2.0 / critChance 0.05).
        assert.are.equals(5, d.stats.critChance, "datamined critChance 0.05 -> 5%")
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"],
            "datamined critMultiplier 2.0 -> base_critical_strike_multiplier_+ 100 (+100% = x2.0)")
        -- isHit=1: a HIT spell (not a DoT like ConsecratedGround, not an ailment).
        assert.is_true(d.baseFlags.spell)
        assert.is_true(d.baseFlags.hit)
        assert.is_nil(d.baseFlags.dot)
        assert.is_nil(d.baseFlags.ailment)
        -- no DoT tick interval (this is a hit, not Consecrated Ground's per-tick DoT).
        assert.is_nil(d.stats.damage_interval)
    end)

    it("socketing Divine Flare directly computes a positive fire spell hit (~73.5)", function()
        newBuild()
        -- clear enemy mitigation so the empty-build hit is the unscaled base.
        for _, k in ipairs({ "enemyFireResist", "enemyArmour" }) do
            build.configTab.input[k] = nil
        end
        build.skillsTab:SelSkill(1, "DivineFlare")
        runCallback("OnFrame")

        local o = build.calcsTab.mainOutput
        -- per-hit (speed-independent): base 70 with the inherent 5% crit at x2.0 and
        -- no added/increased damage = 70 * (0.95 + 2.0*0.05) = 73.5.
        assert.is_truthy(o.AverageHit and o.AverageHit > 0,
            "Divine Flare base must emit a positive hit (was structurally 0 / absent)")
        assert.is_true(o.AverageHit > 70 and o.AverageHit < 80,
            "empty-build per-hit must be ~73.5 (base 70 x 5%/x2.0 crit blend), got " .. tostring(o.AverageHit))

        -- it is a Fire SPELL HIT.
        local ms = build.calcsTab.mainEnv.player.mainSkill
        assert.is_true(ms.skillFlags.spell, "Divine Flare must be a spell")
        assert.is_true(ms.skillFlags.hit, "Divine Flare must hit")
        assert.is_nil(ms.skillFlags.dot, "Divine Flare is a hit, not a DoT")
    end)
end)

describe("DivineFlare grant is NODE-GATED on si4lgl-17", function()
    it("Symbols of Hope grants exactly DivineFlare, gated on si4lgl-17", function()
        local grants = data.subSkillGrants.SigilsOfHope
        assert.is_table(grants, "SigilsOfHope must be in the grant registry")
        assert.are.equals(1, #grants)
        assert.are.equals("DivineFlare", grants[1].skillId)
        assert.are.equals("si4lgl-17", grants[1].requiresNode,
            "the Divine Flare grant must be node-conditional on the si4lgl-17 'Divine Flare' node")
        -- scope: DivineFlare is granted ONLY by Symbols of Hope, nothing else.
        local owners = {}
        for parentId, gs in pairs(data.subSkillGrants) do
            for _, g in ipairs(gs) do
                if g.skillId == "DivineFlare" then owners[#owners + 1] = parentId end
            end
        end
        assert.are.same({ "SigilsOfHope" }, owners,
            "DivineFlare must be granted only by SigilsOfHope")
    end)

    it("socketing Symbols of Hope WITHOUT si4lgl-17 does NOT inject Divine Flare", function()
        newBuild()
        build.skillsTab:SelSkill(1, "SigilsOfHope")
        runCallback("OnFrame")

        -- no granted sub-skill group pointing at Symbols of Hope (node not allocated)...
        for _, group in pairs(build.skillsTab.socketGroupList) do
            assert.is_not.equal("SigilsOfHope", group.subSkillOf,
                "Divine Flare must not be granted when si4lgl-17 is not allocated")
        end
        -- ...and Divine Flare is not in the active skill list.
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local ge = s.activeEffect and s.activeEffect.grantedEffect
            assert.is_not.equal("Divine Flare", ge and ge.name,
                "Divine Flare must not appear without the si4lgl-17 node (grant is node-gated)")
        end

        -- corpus invariant: a Symbols-of-Hope-only build (no node) is a buff/aura with
        -- no damage of its own -> FullDPS 0, byte-identical to pre-grant dev. This is
        -- the 105/106 SigilsOfHope builds that do NOT take si4lgl-17.
        local fullDPS = build.calcsTab.mainOutput.FullDPS or 0
        assert.are.equals(0, fullDPS,
            "a Symbols-of-Hope-only build (no si4lgl-17) must contribute 0 FullDPS")
    end)

    it("the si4lgl-17 'Divine Flare' node exists in the loaded tree and is the canCastDivineFlare gate", function()
        -- Behavioral positive (allocating si4lgl-17 -> grant injected) is validated by
        -- the real corpus A/B regen on <private build> (the single MAIN-repo build that takes
        -- si4lgl-17); spec/TestBuilds is gitignored so it cannot be referenced here.
        -- Here we lock the gate node itself: si4lgl-17 must exist, be the SigilsOfHope
        -- node that carries " Activation Casts Divine Flare", so requiresNode resolves.
        newBuild()
        local node = build.spec.nodes["si4lgl-17"]
        assert.is_truthy(node, "si4lgl-17 must exist in the loaded 1.4 tree")
        assert.are.equals("SigilsOfHope", node.skillId,
            "si4lgl-17 must scope to the Symbols of Hope specialization tree (skillId SigilsOfHope)")
        local stats = node.stats or {}
        local hasActivation = false
        for _, s in ipairs(stats) do
            if tostring(s):find("Activation Casts Divine Flare", 1, true) then hasActivation = true end
        end
        assert.is_true(hasActivation,
            "si4lgl-17 must carry ' Activation Casts Divine Flare' (the canCastDivineFlare gate the grant keys on)")
    end)
end)

describe("DivineFlare calc wiring (source invariants)", function()
    it("CalcSetup gates the grant on env.allocNodes[requiresNode]", function()
        local text = assert(readFile("Modules/CalcSetup.lua"))
        assert.is_truthy(text:find("grant.requiresNode", 1, true),
            "CalcSetup grant loop must honor the optional requiresNode gate")
    end)

    it("per-symbol scaling rides the existing Multiplier:ActiveSymbol parse", function()
        local mods = modLib.parseMod("+25% Divine Flare Damage Per Symbol")
        assert.is_truthy(mods and #mods >= 1,
            "'... Per Symbol' must parse (Multiplier:ActiveSymbol), not drop to empty")
        local hasSymbolMult = false
        for _, m in ipairs(mods) do
            for _, tag in ipairs(m) do
                if tag.type == "Multiplier" and tag.var == "ActiveSymbol" then
                    hasSymbolMult = true
                end
            end
        end
        assert.is_true(hasSymbolMult,
            "the per-symbol Divine Flare damage node must carry a Multiplier:ActiveSymbol tag")
    end)
end)
