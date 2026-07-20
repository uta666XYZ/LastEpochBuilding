-- @leb-regression-guard: mirage-count-consumer
-- Locks F11: CalcOffence aggregates MirageCount into
-- output.MirageCount, and CalcSections has a breakdown row. Parser
-- maps "+N Mirages created by Lethal Mirage" (idol affix family,
-- ModItem.json statOrderKey=537, tiers 0..7 emit +1/+2/+3) to this
-- stat with a SkillName='Lethal Mirage' tag (see ModParser.lua,
-- mirages-created-by-lethal-mirage). Before this wiring the value was
-- parsed but never surfaced -- silent failure mirroring F1.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("MirageCountConsumer", function()
    local calcText, sectionsText

    setup(function()
        calcText     = readSource("Modules/CalcOffence.lua")
        sectionsText = readSource("Modules/CalcSections.lua")
    end)

    it("CalcOffence: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(calcText, '@leb%-regression%-guard:mirage%-count%-consumer'),
            "CalcOffence must carry the F11 consumer guard marker"
        )
    end)

    it("CalcOffence: aggregates MirageCount into output", function()
        local pattern = 'output%.MirageCount%s*=%s*skillModList:Sum%("BASE",%s*skillCfg,%s*"MirageCount"%)'
        assert.is_truthy(
            string.find(calcText, pattern),
            "CalcOffence must aggregate MirageCount BASE via skillModList:Sum"
        )
    end)

    it("CalcSections: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(sectionsText, '@leb%-regression%-guard:mirage%-count%-consumer'),
            "CalcSections must carry the F11 consumer guard marker"
        )
    end)

    it("CalcSections: has a Mirage Count breakdown row", function()
        local pattern = 'haveOutput%s*=%s*"MirageCount"'
        assert.is_truthy(
            string.find(sectionsText, pattern),
            "CalcSections must define a row with haveOutput='MirageCount'"
        )
    end)

    it("CalcSections: row formats as integer with skill-cfg modName", function()
        local pattern = 'format%s*=%s*"{0:output:MirageCount}".-modName%s*=%s*"MirageCount",%s*cfg%s*=%s*"skill"'
        assert.is_truthy(
            string.find(sectionsText, pattern),
            "Row must format as integer and reference modName='MirageCount' with cfg='skill'"
        )
    end)
end)
