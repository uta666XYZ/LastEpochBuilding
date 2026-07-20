-- @leb-regression-guard:static-orb-body-impact
--   117973 (+~40%). See REGRESSION_GUARDS.md "static-orb-body-impact".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("StaticOrbBody grant registry (base-kit, no fabrication)", function()
    it("Static Orb grants StaticOrbBody with NO node gate (base kit)", function()
        local grants = data.subSkillGrants.StaticOrb
        assert.is_table(grants, "StaticOrb must be in the grant registry")
        local body
        for _, g in ipairs(grants) do
            if g.skillId == "StaticOrbBody" then body = g end
        end
        assert.is_table(body, "StaticOrb must grant StaticOrbBody")
        -- The ABSENCE of a node gate is the load-bearing invariant: the contact hit
        -- is part of the base Static Orb kit (every orb contacts on the way to
        -- exploding), so it must NOT be conditional on any node.
        assert.is_nil(body.requiresNode,
            "the body-contact hit is base kit -- it must NOT be node-gated")
    end)

    it("StaticOrbBody carries the datamined Lightning hit base + the 0.40 calibration", function()
        local d = data.skills.StaticOrbBody
        assert.is_table(d, "StaticOrbBody must exist in data.skills")
        assert.are.equals("Static Orb Impact", d.name)
        assert.are.equals(20, d.stats.spell_base_lightning_damage,
            "datamined contact intrinsic base = 20 (half the explosion's 40)")
        assert.are.equals(1, d.stats.damageEffectiveness,
            "contact eff = 1 (half the explosion's eff 2)")
        -- it IS a hit (not a DoT), unlike Charged Ground / Fissure
        assert.is_true(d.baseFlags.hit, "the contact is a hit (isHit=1)")
        assert.is_nil(d.baseFlags.dot, "the contact is not a DoT")
        -- baseMods are PARSED into mod tables at data-load (NOT raw strings), so
        -- assert on the parsed form. The x0.80 calibration parses to a MORE Damage
        -- mod of -20 (the explosion getTempStats lead the body lacks); the shared Int
        -- scaling parses to a per-Intelligence multiplier mod.
        local hasLess, hasInt = false, false
        for _, m in ipairs(d.baseMods or {}) do
            if type(m) == "table" then
                if m.name == "Damage" and m.type == "MORE" and m.value == -20 then hasLess = true end
                for _, t in ipairs(m) do
                    if type(t) == "table" and t.type == "PerStat" and t.stat == "Int" then
                        hasInt = true
                    end
                end
            elseif type(m) == "string" then
                if m:find("less Damage", 1, true) then hasLess = true end
                if m:find("Intelligence", 1, true) then hasInt = true end
            end
        end
        assert.is_true(hasLess, "body must carry the '20% less Damage' (MORE -20) x0.80 calibration baseMod")
        assert.is_true(hasInt, "body must share Static Orb's per-Intelligence scaling baseMod")
        assert.is_true(d.excludeFromTriggerNameList,
            "granted sub-skill must not pollute the trigger-name resolution list")
    end)

    it("SubSkillGrants carries the guard marker", function()
        local text = assert(readFile("Data/SubSkillGrants.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:static%-orb%-body%-impact"),
            "SubSkillGrants must carry the body guard marker")
    end)
end)

describe("StaticOrbBody end-to-end (Ys451 corpus build)", function()
    it("body = 0.40 x explosion at the same cadence, routed via SkillId:StaticOrb", function()
        local rel = "spec/TestBuilds/1.4/bin/Ys451 lv100 Sorcerer.xml"
        local fh, path
        for _, p in ipairs({ "../../../../", "../../../", "../../../../../", "../../", "" }) do
            path = p .. rel; fh = io.open(path, "r"); if fh then break end
        end
        if not fh then pending("Ys451 XML not present (spec/TestBuilds is gitignored)"); return end
        local xml = fh:read("*a"); fh:close()
        loadBuildFromXML(xml)
        build.buildFlag = true
        build:OnFrame({})
        local env = build.calcsTab.mainEnv
        local body
        for _, s in ipairs(env.player.activeSkillList) do
            local ge = s.activeEffect and s.activeEffect.grantedEffect
            if ge and ge.name == "Static Orb Impact" then body = s end
        end
        assert.is_not_nil(body, "Static Orb Impact (body) must be injected into activeSkillList")
        assert.are.equals("SkillId:StaticOrb", body.socketGroup and body.socketGroup.source,
            "body must route the Static Orb tree mods via SkillId:StaticOrb")
        local out = build.calcsTab.mainOutput
        local orbDPS, bodyDPS = 0, 0
        for _, e in ipairs(out.SkillDPS or {}) do
            if e.name == "Static Orb" then orbDPS = orbDPS + e.dps * (e.count or 1) end
            if e.name == "Static Orb Impact" then bodyDPS = bodyDPS + e.dps * (e.count or 1) end
        end
        assert.is_true(orbDPS > 0, "Static Orb explosion must contribute DPS")
        assert.is_true(bodyDPS > 0, "Static Orb body must contribute DPS")
        -- The decisive, build-independent invariant: body realized = 0.40 x explosion.
        assert.is_true(math.abs(bodyDPS / orbDPS - 0.40) < 0.001,
            "body/explosion DPS must be 0.40 (got " .. tostring(bodyDPS / orbDPS) .. ")")
    end)
end)
