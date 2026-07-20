-- @leb-regression-guard:charged-ground-grant
-- See REGRESSION_GUARDS.md "charged-ground-grant".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("ChargedGround grant registry (node-gated, no fabrication)", function()
    it("Static Orb grants ChargedGround gated on so35a-4 (Static Ground)", function()
        local grants = data.subSkillGrants.StaticOrb
        assert.is_table(grants, "StaticOrb must be in the grant registry")
        -- Static Orb now grants TWO sub-skills: the base-kit body-contact hit
        -- (StaticOrbBody, no gate) and the node-gated Charged Ground DoT.
        local cg
        for _, g in ipairs(grants) do
            if g.skillId == "ChargedGround" then cg = g end
        end
        assert.is_table(cg, "StaticOrb must still grant ChargedGround")
        -- The node gate is the load-bearing invariant: dropping requiresNode would
        -- inject an always-on Charged Ground DoT into EVERY Static Orb build's Full
        -- DPS (inflating the corpus). It MUST stay conditional on Static Ground.
        assert.are.equals("so35a-4", cg.requiresNode,
            "the Charged Ground grant must be node-conditional on Static Ground (so35a-4)")
    end)

    it("ChargedGround carries the datamined Lightning Spell DoT base", function()
        local d = data.skills.ChargedGround
        assert.is_table(d, "ChargedGround must exist in data.skills")
        assert.are.equals("Charged Ground", d.name)
        assert.are.equals(9, d.stats.spell_base_lightning_damage)
        assert.are.equals(0.45, d.stats.damageEffectiveness)
        assert.are.equals(300, d.stats.damage_interval,
            "300ms interval = 3.33 tick/s; per-tick base x interval is folded at the TotalDPS stage")
        -- pure DoT (isHit=0): dot flag set, hit flag NOT set, so it folds as a
        -- per-application interval DoT (like ConsecratedGround), not a hit.
        assert.is_true(d.baseFlags.dot, "Charged Ground is a pure DoT (dot flag)")
        assert.is_nil(d.baseFlags.hit, "Charged Ground deals no hit (isHit=0 in datamine)")
        assert.is_true(d.excludeFromTriggerNameList,
            "granted sub-skill must not pollute the trigger-name resolution list")
    end)
end)

describe("ChargedGround grant calc wiring (source invariants)", function()
    it("CalcSetup gates the grant on env.allocNodes[requiresNode]", function()
        local text = assert(readFile("Modules/CalcSetup.lua"))
        assert.is_truthy(text:find("grant.requiresNode", 1, true),
            "CalcSetup grant loop must honor the optional requiresNode gate")
    end)

    it("SubSkillGrants carries the guard marker", function()
        local text = assert(readFile("Data/SubSkillGrants.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:charged%-ground%-grant"),
            "SubSkillGrants must carry the guard marker at the StaticOrb entry")
    end)
end)
