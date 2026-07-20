-- @leb-regression-guard: chance-to-apply-shadow-dagger-on-hit-consumer
-- Locks F10: CalcOffence aggregates ChanceToApplyShadowDaggerOnHit
-- into output.ChanceToApplyShadowDaggerOnHit, and CalcSections has
-- a breakdown row. Parser maps "chance to apply a shadow dagger on
-- hit" to this stat (ModParser.lua L399). Before this wiring the
-- value was parsed (e.g. 50% from the Lethal Mirage unique suffix)
-- but never surfaced -- silent failure mirroring F1.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ChanceToApplyShadowDaggerOnHitConsumer", function()
    local calcText, sectionsText

    setup(function()
        calcText     = readSource("Modules/CalcOffence.lua")
        sectionsText = readSource("Modules/CalcSections.lua")
    end)

    it("CalcOffence: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(calcText, '@leb%-regression%-guard:chance%-to%-apply%-shadow%-dagger%-on%-hit%-consumer'),
            "CalcOffence must carry the F10 consumer guard marker"
        )
    end)

    it("CalcOffence: aggregates ChanceToApplyShadowDaggerOnHit into output", function()
        local pattern = 'output%.ChanceToApplyShadowDaggerOnHit%s*=%s*skillModList:Sum%("BASE",%s*skillCfg,%s*"ChanceToApplyShadowDaggerOnHit"%)'
        assert.is_truthy(
            string.find(calcText, pattern),
            "CalcOffence must aggregate ChanceToApplyShadowDaggerOnHit BASE via skillModList:Sum"
        )
    end)

    it("CalcSections: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(sectionsText, '@leb%-regression%-guard:chance%-to%-apply%-shadow%-dagger%-on%-hit%-consumer'),
            "CalcSections must carry the F10 consumer guard marker"
        )
    end)

    it("CalcSections: has a Shadow Dagger Apply Chance breakdown row", function()
        local pattern = 'haveOutput%s*=%s*"ChanceToApplyShadowDaggerOnHit"'
        assert.is_truthy(
            string.find(sectionsText, pattern),
            "CalcSections must define a row with haveOutput='ChanceToApplyShadowDaggerOnHit'"
        )
    end)

    it("CalcSections: row formats as percent with skill-cfg modName", function()
        local pattern = 'format%s*=%s*"{0:output:ChanceToApplyShadowDaggerOnHit}%%".-modName%s*=%s*"ChanceToApplyShadowDaggerOnHit",%s*cfg%s*=%s*"skill"'
        assert.is_truthy(
            string.find(sectionsText, pattern),
            "Row must format as percent and reference modName='ChanceToApplyShadowDaggerOnHit' with cfg='skill'"
        )
    end)
end)
