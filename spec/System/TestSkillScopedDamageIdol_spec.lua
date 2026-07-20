-- @leb-regression-guard:skill-scoped-damage-idol-tag
-- Locks the ② sub-point of the Fire Aura DPS gap: a "(N)% increased <Skill>
-- Damage" idol affix must parse to a single `Damage INC` mod tagged
-- SkillName="<Skill>", so the increase applies ONLY to that skill's cfg and
-- never leaks globally or onto other skills.
--
-- Establishing observation (ShutFackUp lv85 Spellblade, idol prefix
-- "(30-100)% Increased Fire Aura Damage" at scalar 0.67):
--   * env.modDB carries `Damage INC 52  SkillName="Fire Aura"`
--   * Sum INC Damage under {skillName="Fire Aura"} = 71 (19 global + 52 scoped)
--   * Sum INC Damage under {skillName="Shatter Strike"} = 19 (no leak)
--   * Sum INC Damage under nil cfg (global) = 19 (no leak)
-- The mod produces no Fire Aura DPS today only because Fire Aura is a triggered
-- skill absent from activeSkillList (the separate ④ trigger-injection gap), NOT
-- because the tag is missing. Earlier notes mis-diagnosed this as "dropped".
--
-- Three coupled invariants:
--   (1) parse: "X% increased Fire Aura Damage" -> Damage INC X + SkillName tag.
--   (2) scoping: the tagged INC sums only under a matching skillName cfg.
--   (3) wiring (ModParser.lua): the skillNameByLower loop registers the
--       "increased <skill> damage$" pattern with a SkillName tag.
-- See REGRESSION_GUARDS.md > "skill-scoped-damage-idol-tag".

describe("SkillScopedDamageIdol", function()
    it("parses '(N)% increased Fire Aura Damage' to a SkillName-tagged Damage INC", function()
        local mods = modLib.parseMod("67% Increased Fire Aura Damage")
        assert.is_table(mods, "must parse to a mod list")
        assert.are.equal(1, #mods)
        local m = mods[1]
        assert.are.equal("Damage", m.name)
        assert.are.equal("INC", m.type)
        assert.are.equal(67, m.value)
        local skillTag
        for _, tag in ipairs(m) do
            if tag.type == "SkillName" then skillTag = tag end
        end
        assert.is_not_nil(skillTag, "Damage INC must carry a SkillName tag")
        assert.are.equal("Fire Aura", skillTag.skillName)
    end)

    it("the tagged INC applies only under a Fire Aura cfg (no leak)", function()
        local db = new("ModDB")
        -- global INC shared by all skills (e.g. generic "increased damage")
        db:NewMod("Damage", "INC", 19, "Global")
        -- the skill-scoped idol INC
        db:NewMod("Damage", "INC", 52, "Idol", 0, 0,
            { type = "SkillName", skillName = "Fire Aura" })

        assert.are.equal(71, db:Sum("INC", { skillName = "Fire Aura" }, "Damage"),
            "Fire Aura cfg must see global 19 + scoped 52 = 71")
        assert.are.equal(19, db:Sum("INC", { skillName = "Shatter Strike" }, "Damage"),
            "another skill must see only the global 19 (no leak)")
        assert.are.equal(19, db:Sum("INC", nil, "Damage"),
            "global/nil cfg must see only the global 19 (no leak)")
    end)

    it("ModParser registers the skill-scoped damage idol pattern", function()
        local f = io.open("Modules/ModParser.lua", "r")
        assert.is_not_nil(f, "must be able to open ModParser.lua")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(string.find(text, 'esc .. " damage$"', 1, true),
            "ModParser must register the 'increased <skill> damage$' pattern")
        assert.is_truthy(string.find(text, "skill-scoped-damage-idol-tag", 1, true),
            "ModParser must carry the inline regression-guard anchor")
        assert.is_truthy(string.find(text, 'type = "SkillName", skillName = canonical', 1, true),
            "the per-skill damage pattern must tag SkillName = canonical")
    end)
end)
