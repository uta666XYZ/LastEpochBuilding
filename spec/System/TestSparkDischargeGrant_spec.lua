-- @leb-regression-guard:spark-discharge-base
-- See REGRESSION_GUARDS.md "spark-discharge-base".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("SparkDischarge Explosive-Trap base-kit grant registry (no fabrication)", function()
    it("Explosive Trap grants SparkDischarge, base-kit (no requiresNode)", function()
        local grants = data.subSkillGrants["Falconer 04 Explosive Trap"]
        assert.is_table(grants, "Falconer 04 Explosive Trap must be in the grant registry")
        local spark
        for _, g in ipairs(grants) do
            if g.skillId == "SparkDischarge" then spark = g end
        end
        assert.is_table(spark, "Explosive Trap must grant SparkDischarge")
        assert.is_nil(spark.requiresNode,
            "Spark Discharge is the base-kit hit of every Explosive Trap (not node-gated)")
        assert.is_nil(spark.summon, "Spark Discharge is a direct hit, not a summon")
        assert.is_nil(spark.noParentTreeBaseConversion,
            "Spark Discharge must INHERIT the Explosive Trap tree base conversion (it IS the ET hit)")
    end)

    it("SparkDischarge carries the datamined Fire throwing base + eff 1.5", function()
        local d = data.skills.SparkDischarge
        assert.is_table(d, "SparkDischarge must exist in data.skills")
        assert.are.equals("Spark Discharge", d.name)
        assert.are.equals(30, d.stats.throwing_base_fire_damage)
        assert.are.equals(1.5, d.stats.damageEffectiveness)
        assert.are.equals(5, d.stats.critChance)
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"])
        assert.is_true(d.baseFlags.attack, "Spark Discharge is a throwing Attack")
        assert.is_true(d.baseFlags.hit, "Spark Discharge deals a Hit (isHit=1 in datamine)")
        assert.are.equals(1032, d.skillTypeTags, "tags = Fire(8) + Throwing(1024)")
        assert.is_nil(d.stats.throwing_base_cold_damage,
            "base must be innate Fire (gear/tree may convert), not native Cold")
        assert.is_nil(d.stats.spell_base_fire_damage,
            "Spark Discharge is a Throwing hit, not a Spell")
        assert.is_true(d.excludeFromTriggerNameList,
            "'Spark Discharge' is a display name shared by many enemy abilities")
    end)

    it("the Explosive Trap CAST parent still carries NO damage (base 0)", function()
        local p = data.skills["Falconer 04 Explosive Trap"]
        assert.is_table(p)
        assert.is_nil(p.stats.throwing_base_fire_damage,
            "the ET cast is trap-deployment; its damage lives on SparkDischarge")
        assert.is_nil(p.baseFlags.hit, "the ET cast is not itself a hit")
    end)
end)

describe("spark-discharge-base guard markers", function()
    it("SubSkillGrants carries the grant guard marker at the Explosive Trap entry", function()
        local text = assert(readFile("Data/SubSkillGrants.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:spark%-discharge%-base"),
            "SubSkillGrants must carry the guard marker")
        assert.is_truthy(text:find('%["Falconer 04 Explosive Trap"%] = {'),
            "SubSkillGrants must register the Explosive Trap grant entry")
        assert.is_truthy(text:find('{ skillId = "SparkDischarge" }'),
            "SubSkillGrants must register the base-kit SparkDischarge grant")
    end)
end)
