-- @leb-regression-guard: mirages-created-by-lethal-mirage
-- Locks the parser handler for the idol-affix line
-- "+N Mirages created by Lethal Mirage" (ModItem.json statOrder
-- 537, paired with the Mana Efficiency Lethal Mirage line).
-- Without this anchor the line silently parsed to an empty
-- modList with empty residue -- the mirage-count half of the
-- affix produced nothing. The MirageCount BASE stat is the F11
-- calc-consumer target.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("MiragesCreatedByLethalMirage", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser: anchored '+N Mirages created by Lethal Mirage' handler exists", function()
        local literal = '["^%+?(%d+) mirages? created by lethal mirage$"]'
        assert.is_truthy(
            string.find(parserText, literal, 1, true),
            "Parser anchor for '+N Mirages created by Lethal Mirage' must be registered"
        )
    end)

    it("ModParser: handler emits MirageCount BASE tagged with SkillName='Lethal Mirage'", function()
        -- Locate the handler line and the body that follows; we look
        -- for the canonical stat + tag fingerprint immediately after.
        local pattern = 'mod%("MirageCount",%s*"BASE",%s*tonumber%(num%),%s*"",%s*0,%s*0,%s*{%s*type%s*=%s*"SkillName",%s*skillName%s*=%s*"Lethal Mirage"%s*}%)'
        assert.is_truthy(
            string.find(parserText, pattern),
            "Handler must emit MirageCount BASE with SkillName='Lethal Mirage' tag"
        )
    end)

    it("ModParser: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(parserText, '@leb%-regression%-guard:mirages%-created%-by%-lethal%-mirage'),
            "Parser must carry the regression-guard marker"
        )
    end)

    local tiers = { 1, 2, 3 }
    for _, n in ipairs(tiers) do
        it(string.format("ModCache: '+%d Mirages created by Lethal Mirage' resolves to MirageCount BASE=%d", n, n), function()
            local needle = string.format(
                '"%%+%d Mirages created by Lethal Mirage"%%]={{%%[1%%]={%%[1%%]={skillName="Lethal Mirage",type="SkillName"},flags=0,keywordFlags=0,name="MirageCount",type="BASE",value=%d}},nil}',
                n, n
            )
            assert.is_truthy(
                string.find(cacheText, needle),
                string.format("+%d entry must carry MirageCount BASE %d with Lethal Mirage SkillName tag and nil residue", n, n)
            )
        end)
    end

    it("ModCache: no '+N Mirages created by Lethal Mirage' entry retains the empty-modList silent-failure shape", function()
        local pattern = '"%+%d+ Mirages created by Lethal Mirage"%]={{},'
        assert.is_nil(
            string.find(cacheText, pattern),
            "No '+N Mirages created by Lethal Mirage' entry may keep the empty-modList silent-failure shape"
        )
    end)
end)
