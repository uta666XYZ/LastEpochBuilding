-- @leb-regression-guard:profane-orb-grant
-- See REGRESSION_GUARDS.md "profane-orb-grant".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("Profane Veil -> Profane Orb node-gated grant registry (no fabrication)", function()
    it("Profane Veil grants Profane Orb, node-gated on pr5fm-28", function()
        local grants = data.subSkillGrants["Warlock 05 Profane Veil"]
        assert.is_table(grants, "Warlock 05 Profane Veil must be in the grant registry")
        local orb
        for _, g in ipairs(grants) do
            if g.skillId == "Warlock 05.2 Profane Orb" then orb = g end
        end
        assert.is_table(orb, "Profane Veil must grant Warlock 05.2 Profane Orb")
        assert.are.equals("pr5fm-28", orb.requiresNode,
            "the orb only exists when the pr5fm-28 'Profane Orbs' node is allocated")
        assert.is_nil(orb.summon, "Profane Orb is a direct hit, not a summon")
        assert.is_nil(orb.noParentTreeBaseConversion,
            "Profane Orb must INHERIT the Profane Veil tree base conversion (Lake of Blood)")
    end)

    it("Warlock 05.2 Profane Orb carries the datamined Necrotic Spell base + eff 2.0", function()
        local d = data.skills["Warlock 05.2 Profane Orb"]
        assert.is_table(d, "Warlock 05.2 Profane Orb must exist in data.skills")
        assert.are.equals("Profane Orb", d.name)
        assert.are.equals(40, d.stats.spell_base_necrotic_damage)
        assert.are.equals(2, d.stats.damageEffectiveness)
        assert.are.equals(5, d.stats.critChance)
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"])
        assert.is_true(d.baseFlags.spell, "Profane Orb explosion is a Spell")
        assert.is_true(d.baseFlags.hit, "Profane Orb deals a Hit (isHit=1 in datamine)")
        assert.is_nil(d.stats.spell_base_physical_damage,
            "base must be innate Necrotic (Lake of Blood tree converts it), not native Physical")
        assert.is_nil(d.stats.penetration, "the datamined prefab has no intrinsic penetration")
        assert.is_true(d.excludeFromTriggerNameList,
            "the granted orb is not itself a trigger source")
        -- per-Int scaling is legit for the Int-class Warlock (not a phantom).
        -- "4% increased Damage per player Intelligence" parses to an INC Damage mod
        -- of value 4 with a PerStat:Int tag.
        local hasInt = false
        for _, m in ipairs(d.baseMods or {}) do
            if m.name == "Damage" and m.type == "INC" and m.value == 4 then
                for _, t in ipairs(m) do
                    if t.type == "PerStat" and t.stat == "Int" then hasInt = true end
                end
            end
        end
        assert.is_true(hasInt, "Profane Orb scales 4% increased Damage per Intelligence")
    end)

    it("the Profane Veil parent stays an aura (isHit 0, Necrotic 10 / eff 0.5)", function()
        local p = data.skills["Warlock 05 Profane Veil"]
        assert.is_table(p)
        assert.is_nil(p.baseFlags.hit, "the veil aura is a pure DoT; the orb is the isHit component")
        assert.are.equals(10, p.stats.spell_base_necrotic_damage)
        assert.are.equals(0.5, p.stats.damageEffectiveness)
    end)
end)

describe("profane-orb-grant guard markers", function()
    it("SubSkillGrants carries the grant guard marker at the Profane Veil entry", function()
        local text = assert(readFile("Data/SubSkillGrants.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:profane%-orb%-grant"),
            "SubSkillGrants must carry the guard marker")
        assert.is_truthy(text:find('%["Warlock 05 Profane Veil"%] = {'),
            "SubSkillGrants must register the Profane Veil grant entry")
        assert.is_truthy(text:find('{ skillId = "Warlock 05%.2 Profane Orb", requiresNode = "pr5fm%-28" }'),
            "SubSkillGrants must register the node-gated Profane Orb grant")
    end)
end)
