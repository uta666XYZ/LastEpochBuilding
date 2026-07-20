-- @leb-regression-guard:spark-charge-detonation-grant
-- See REGRESSION_GUARDS.md "spark-charge-detonation-grant".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("Spark Charge detonation grant wiring (CalcSetup)", function()
    local src = assert(readFile("Modules/CalcSetup.lua"))
    -- isolate the grant block so assertions are scoped to it
    local block = src:match("@leb%-regression%-guard:spark%-charge%-detonation%-grant.-includeInFullDPS = true,")
    it("the grant block exists", function()
        assert.is_truthy(block, "the spark-charge-detonation-grant block must be present in CalcSetup")
    end)
    it("(1) reads SC_chance at the LB skillCfg, never a nil cfg (flag-drop guard)", function()
        assert.is_truthy(block:find('skillModList:Sum("BASE", lbSkill.skillCfg, "ChanceToTriggerOnHit_Ailment_SparkCharge")', 1, true),
            "SC chance must be read at lbSkill.skillCfg (flag-bearing)")
        assert.is_nil(block:find('Sum("BASE", nil, "ChanceToTriggerOnHit_Ailment_SparkCharge")', 1, true),
            "a nil-cfg Sum flag-drops the ModFlag.Hit SC mods and returns 0 -- forbidden")
    end)
    it("(2) rate uses (1 + NovaChance/100) on LB.HitSpeed (Nova is an LB-proc)", function()
        assert.is_truthy(block:find("ChanceToTriggerOnHit_SmallLightningNova", 1, true),
            "Nova's contribution must come from its on-LB-hit proc chance")
        assert.is_truthy(block:find("1 + novaChance / 100", 1, true),
            "detRate must be hitSpeed * scChance/100 * (1 + novaChance/100)")
        assert.is_truthy(block:find("lbCache.HitSpeed or lbCache.Speed", 1, true),
            "must use the chain-aware LB HitSpeed from the CACHE entry")
    end)
    it("(3) grants via Timer source (REGIME A) with includeInFullDPS", function()
        assert.is_truthy(block:find('skillId = "SparkChargeExplosion"', 1, true))
        assert.is_truthy(block:find('source = "Timer:SparkChargeExplosion"', 1, true),
            "REGIME A: a Timer source keeps groupSource != SkillId:LightningBlast so generic LB nodes do not leak")
        assert.is_nil(block:find('source = "SkillId:Ailment_SparkCharge"', 1, true),
            "the SkillId:Ailment_SparkCharge source caused circular source resolution -- forbidden")
        assert.is_truthy(block:find("triggeredByTimer = true", 1, true))
        assert.is_truthy(block:find("includeInFullDPS = true", 1, true))
    end)
    it("is gated on SC chance > 0 (non-Spark-Charge builds byte-identical)", function()
        assert.is_truthy(block:find("scChance > 0", 1, true))
        assert.is_truthy(block:find('group.grantedEffect.id == "LightningBlast"', 1, true),
            "the grant requires a Lightning Blast applier to be socketed")
    end)
end)

describe("Spark Charge detonation grant: data + rescope wiring", function()
    it("SparkChargeExplosion is a Lightning Spell hit in data.skills", function()
        local d = data.skills.SparkChargeExplosion
        assert.is_table(d)
        assert.are.equals("Spark Charge", d.name)
        assert.is_true(d.baseFlags.hit)
        assert.is_true(d.baseFlags.spell)
    end)
    it("lb23il-26 Mortal Capacitor is rescoped to SparkChargeExplosion (REGIME A magnitude)", function()
        local g = assert(readFile("Data/Global.lua"))
        assert.is_truthy(g:find('%["lb23il%-26"%]%s*=%s*{%s*skillId%s*=%s*"SparkChargeExplosion"%s*}'),
            "the Mortal Capacitor rescope must reach the detonation, not Lightning Blast")
    end)
end)

describe("Spark Charge detonation participates in Shock, capped by maxInstances", function()
    -- Validation provenance is retained in maintainer notes.
    it("the detonation's Shock is NOT suppressed (no spark-charge-detonation-no-shock guard)", function()
        local cp = assert(readFile("Modules/CalcPerform.lua"))
        assert.is_nil(cp:find('socketGroup%.source == "SkillId:SparkChargeExplosion"'),
            "the detonation-Shock suppression must be removed (superseded by the maxInstances cap)")
    end)
    it("CalcActiveSkill caps non-damaging ailment debuff stacks at maximum_stacks", function()
        local cas = assert(readFile("Modules/CalcActiveSkill.lua"))
        local i = cas:find("@leb%-regression%-guard:nondamaging%-ailment%-stack%-cap")
        assert.is_truthy(i, "the nondamaging-ailment-stack-cap guard must be present in CalcActiveSkill")
        local block = cas:sub(i, i + 1600)
        assert.is_truthy(block:find("effectStackLimit", 1, true),
            "the ailment debuff GlobalEffect must carry effectStackLimit")
        assert.is_truthy(block:find("maximum_stacks", 1, true),
            "the cap must come from the skill's maximum_stacks stat (game-data maxInstances)")
        assert.is_truthy(block:find("baseFlags%.ailment"),
            "the cap must be scoped to ailment skills so non-ailment buffs are untouched")
        assert.is_truthy(block:find("maximum_stacks > 0", 1, true),
            "must guard maximum_stacks > 0 (0 is truthy in Lua; a 0 stackLimit would zero the debuff)")
    end)
    it("Shock maxInstances data is present and = 10 (game-data Ailment.maxInstances)", function()
        assert.are.equals(10, data.nonDamagingAilment.Shock.maxStacks)
        assert.are.equals(10, data.skills.Ailment_Shock.stats.maximum_stacks)
        assert.are.equals(3, data.nonDamagingAilment.Chill.maxStacks)
        assert.are.equals(3, data.nonDamagingAilment.Slow.maxStacks)
    end)
end)
