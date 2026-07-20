-- @leb-regression-guard:consecrated-ground
-- @leb-regression-guard:pure-dot-skill-modflag-dot
-- @leb-regression-guard:type-damage-over-time-dot-only
-- See REGRESSION_GUARDS.md "consecrated-ground", "pure-dot-skill-modflag-dot",
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("ConsecratedGround grant + base data (no fabrication)", function()
    it("Judgement grants ConsecratedGround as a base-kit sub-skill (no requiresNode)", function()
        local grants = data.subSkillGrants.Judgement
        assert.is_table(grants, "Judgement must be in the grant registry")
        assert.are.equals(1, #grants)
        assert.are.equals("ConsecratedGround", grants[1].skillId)
        assert.is_nil(grants[1].requiresNode,
            "CG is a base-kit grant (Judgement always creates it), not node-conditional")
    end)

    it("ConsecratedGround carries the datamined Fire Spell DoT base", function()
        local d = data.skills.ConsecratedGround
        assert.is_table(d, "ConsecratedGround must exist in data.skills")
        assert.are.equals("Consecrated Ground", d.name)
        assert.are.equals(4352, d.skillTypeTags, "damageTags 4352 = 4096 DoT + 256 Spell")
        assert.are.equals(24, d.stats.spell_base_fire_damage, "datamined base 24 Fire")
        assert.are.equals(1.2, d.stats.damageEffectiveness, "addedDamageScaling 1.2")
        -- pure DoT: dot + spell, but NOT a hit and NOT an ailment (so it takes the
        -- skill-DoT path in CalcOffence, gets ModFlag.Dot, and is NOT routed through
        -- the data.damagingAilment ailment machinery).
        assert.is_true(d.baseFlags.dot)
        assert.is_true(d.baseFlags.spell)
        assert.is_nil(d.baseFlags.hit)
        assert.is_nil(d.baseFlags.ailment)
        -- per-application base divided by the in-game-measured tick interval
        -- (prefab _damageInterval is 0.0 / runtime; CSV 3.12 tick/s -> 320 ms).
        assert.are.equals(320, d.stats.damage_interval)
    end)
end)

describe("pure-DoT skills receive ModFlag.Dot (engine fix #1)", function()
    it("CalcActiveSkill adds ModFlag.Dot for dot && !hit && !ailment", function()
        local text = assert(readFile("Modules/CalcActiveSkill.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:pure%-dot%-skill%-modflag%-dot"),
            "CalcActiveSkill must carry the guard marker")
        assert.is_truthy(text:find("skillFlags%.dot and not skillFlags%.hit and not skillFlags%.ailment"),
            "the ModFlag.Dot gate must be dot && !hit && !ailment")
    end)
end)

describe("type 'X Damage over Time' is Dot-scoped, not type-ModFlag-scoped (engine fix #2)", function()
    it("'increased fire damage over time' parses to FireDamage with ModFlag.Dot and NOT ModFlag.Fire", function()
        local mods = modLib.parseMod("30% increased Fire Damage Over Time")
        assert.is_table(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("FireDamage", m.name)
        assert.are.equals("INC", m.type)
        -- Dot flag present (so it reaches DoT skills), type ModFlag (Fire=8) absent
        -- (the FireDamage NAME already scopes it to fire; requiring ModFlag.Fire in
        -- the cfg made it match nothing, since no skill cfg sets a damage-type flag).
        assert.are.equals(ModFlag.Dot, bit.band(m.flags or 0, ModFlag.Dot),
            "must carry ModFlag.Dot")
        assert.are.equals(0, bit.band(m.flags or 0, ModFlag.Fire),
            "must NOT carry ModFlag.Fire (over-constraint that dropped the mod for all skills)")
    end)

    it("generic 'increased damage over time' stays Dot-only (unchanged)", function()
        local mods = modLib.parseMod("50% increased Damage Over Time")
        assert.are.equals(1, #mods)
        assert.are.equals("Damage", mods[1].name)
        assert.are.equals(ModFlag.Dot, bit.band(mods[1].flags or 0, ModFlag.Dot))
    end)

    it("ModParser carries the type-DoT guard marker", function()
        local text = assert(readFile("Modules/ModParser.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:type%-damage%-over%-time%-dot%-only"))
    end)
end)
