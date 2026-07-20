-- @leb-regression-guard:trigger-chance-to-cast-when-you-cast-bridge
-- Locks the two-skill, EXPLICIT-source trigger bridge:
--   "X% chance to cast A when you cast B"
-- must be CONSUMED (A enters Full DPS, triggered off B's cast rate), not merely
-- recognized.
--
-- Before: ModParser emitted ChanceToCast_<A> (SkillName=A + Condition=OnCast_B,
-- notSupported=true) which nothing read, so A never entered Full DPS.
--
-- Fix: when A exists in data.skills, emit the FUNCTIONAL ChanceToTriggerOnHit_<Aid>
-- BASE mod SCOPED to the SOURCE skill B (SkillName = B). The CalcSetup
-- grantedTriggeredSkills loop sums ChanceToTriggerOnHit_<Aid> against each candidate
-- source's own skillCfg; the SkillName=B tag (ModStore.lua L747 SkillName eval)
-- matches ONLY when the source skill is B, so the source is selected EXACTLY (no
-- ambiguous global-source guessing). CalcTriggers then derives the rate from B's
-- cast rate x this chance (build-derived, not fabricated).
--
-- The crux vs the old broken form: scope the functional mod to the SOURCE (B),
-- NOT the triggered skill (A). Scoping to A made the per-source Sum never match,
-- which is why nothing consumed ChanceToCast_<A>. See REGRESSION_GUARDS.md
-- "trigger-chance-to-cast-when-you-cast-bridge".

describe("TriggerChanceToCastWhenYouCast bridge (parser)", function()
    it("'10% Chance to cast Marrow Shards when you cast Transplant' emits functional ChanceToTriggerOnHit_MarrowShards", function()
        local mods, extra = modLib.parseMod("10% Chance to cast Marrow Shards when you cast Transplant")
        assert.is_nil(extra)
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("ChanceToTriggerOnHit_MarrowShards", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(10, m.value)
        -- functional (consumed), NOT recognition-only
        assert.is_falsy(mods.notSupported)
    end)

    it("the triggered-skill id is the data.skills KEY (MarrowShards), not the spaced name", function()
        assert.is_table(data.skills.MarrowShards, "data.skills.MarrowShards must exist")
        assert.are.equals("Marrow Shards", data.skills.MarrowShards.name)
        local mods = modLib.parseMod("36% Chance to cast Marrow Shards when you cast Transplant")
        assert.are.equals("ChanceToTriggerOnHit_MarrowShards", mods[1].name)
        assert.are.equals(36, mods[1].value)
    end)

    it("the functional mod is scoped to the SOURCE skill B (Transplant), NOT the triggered A", function()
        local mods = modLib.parseMod("12% Chance to cast Marrow Shards when you cast Transplant")
        local m = mods[1]
        local skillNameTag
        for _, tag in ipairs(m) do
            if tag.type == "SkillName" then skillNameTag = tag end
        end
        assert.is_not_nil(skillNameTag, "functional trigger mod must carry a SkillName (source) tag")
        assert.are.equals("Transplant", skillNameTag.skillName,
            "scope must be the SOURCE skill B, not the triggered skill A")
        assert.are_not.equals("Marrow Shards", skillNameTag.skillName,
            "scoping to the triggered skill A is the original bug (per-source Sum never matches)")
        -- no Condition tag on the functional form (the rate comes from the source)
        for _, tag in ipairs(m) do
            assert.are_not.equals("Condition", tag.type,
                "functional trigger mod must not carry the recognition-only Condition tag")
        end
    end)

    it("source-scoping: the mod sums only for source B's cfg (ModStore SkillName eval)", function()
        local mods = modLib.parseMod("20% Chance to cast Marrow Shards when you cast Transplant")
        local store = new("ModDB")
        store:AddMod(mods[1])
        local asB = store:Sum("BASE", { skillName = "Transplant" }, "ChanceToTriggerOnHit_MarrowShards")
        local asA = store:Sum("BASE", { skillName = "Marrow Shards" }, "ChanceToTriggerOnHit_MarrowShards")
        local asOther = store:Sum("BASE", { skillName = "Fireball" }, "ChanceToTriggerOnHit_MarrowShards")
        assert.are.equals(20, asB, "must sum for the source skill B (Transplant)")
        assert.are.equals(0, asA, "must NOT sum for the triggered skill A (Marrow Shards)")
        assert.are.equals(0, asOther, "must NOT sum for an unrelated skill")
    end)
end)

describe("TriggerChanceToCastWhenYouUse bridge (spell source only)", function()
    it("'when you use B' bridges to functional when B is a spell (use == cast)", function()
        -- Transplant has baseFlags.spell = true, so "use" == "cast".
        assert.is_true(data.skills.Transplant.baseFlags.spell, "Transplant must be a spell")
        local mods = modLib.parseMod("10% Chance to cast Marrow Shards when you use Transplant")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("ChanceToTriggerOnHit_MarrowShards", m.name)
        assert.are.equals(10, m.value)
        assert.is_falsy(mods.notSupported)
        local skillNameTag
        for _, tag in ipairs(m) do if tag.type == "SkillName" then skillNameTag = tag end end
        assert.are.equals("Transplant", skillNameTag and skillNameTag.skillName,
            "must scope to the SOURCE spell B")
    end)

    it("'when you use B' stays recognition-only when B is NOT a spell (use != hit)", function()
        -- Shield Throw / Hammer Throw etc. are non-spell. Use a known non-spell skill.
        local nonSpell
        for k, s in pairs(data.skills) do
            if s.baseFlags and not s.baseFlags.spell and s.name and not s.name:find("%s") then
                nonSpell = s.name; break
            end
        end
        assert.is_not_nil(nonSpell, "need a single-word non-spell skill for the negative case")
        local mods = modLib.parseMod("10% Chance to cast Marrow Shards when you use " .. nonSpell)
        if mods then
            -- if recognised at all, it must be the recognition-only ChanceToCast_ form,
            -- NOT the functional ChanceToTriggerOnHit_ (we cannot derive a use-rate for
            -- a non-spell source without the hit-chance caveat).
            assert.are_not.equals("ChanceToTriggerOnHit_MarrowShards", mods[1].name,
                "non-spell source must NOT be bridged to the functional trigger mod")
        end
    end)
end)

describe("TriggerChanceToCastWhenYouCast ModCache", function()
    it("no stale 'Chance to cast Marrow Shards when you cast Transplant' row short-circuits the parser", function()
        local f = assert(io.open("Data/ModCache.lua", "r"))
        local body = f:read("*a")
        f:close()
        assert.is_nil(body:find("Chance to cast Marrow Shards when you cast Transplant", 1, true),
            "stale ModCache row would re-mask the recognition-only behaviour")
    end)
end)

describe("TriggerChanceToCastWhenYouCast source invariants", function()
    it("ModParser bridges when-you-cast to source-scoped ChanceToTriggerOnHit_", function()
        local f = assert(io.open("Modules/ModParser.lua", "r"))
        local text = f:read("*a")
        f:close()
        assert.is_truthy(text:find('ChanceToTriggerOnHit_" .. trigId', 1, true),
            "ModParser when-you-cast handler must emit the functional ChanceToTriggerOnHit_ mod")
        assert.is_truthy(text:find("skillName = cast", 1, true),
            "the functional mod must be scoped to the SOURCE skill B (cast)")
        assert.is_truthy(text:find("@leb%-regression%-guard:trigger%-chance%-to%-cast%-when%-you%-cast%-bridge"),
            "inline regression-guard marker must be present")
    end)
end)
