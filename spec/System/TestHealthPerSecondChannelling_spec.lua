-- @leb-regression-guard: health-per-second-channelling
-- Locks the "+N Health Per Second" silent-failure parse.
--
-- Focus tree node "Inner Growth" (Mage tree_1.json L17197 "vm53dx-14")
-- carries stat "6 Health Per Second" with description
-- "Focus heals the target each second while channeled." Before this guard
-- the line fell through to `name="Life"` BASE=6 with residue
-- "  Per Second " — silently granting +6 *max* Health, completely
-- unrelated to the actual mechanic.
--
-- Three sites lock together:
-- a. `Modules/ModParser.lua` specialModList entry maps the bare
--    "+N health per second" form to LifeRegen BASE=N gated on
--    Condition:Channelling.
-- b. `Data/ModCache.lua` "6 Health Per Second" entry carries the
--    Condition:Channelling tag with name="LifeRegen" and empty residue.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("HealthPerSecondChannelling", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser specialModList maps '+N health per second' to LifeRegen+Channelling", function()
        assert.is_truthy(string.find(parserText,
            'specialModList%["%^%%%+%?%(%[%%d%%.%]%+%) health per second%$"%]', 1, false),
            "ModParser must register the '+N health per second' specialModList pattern")
        assert.is_truthy(string.find(parserText,
            'mod%("LifeRegen", "BASE", num, "", 0, 0, { type = "Condition", var = "Channelling" }%)', 1, false),
            "Pattern handler must emit LifeRegen BASE gated on Condition:Channelling")
    end)

    it("ModCache '6 Health Per Second' carries Condition:Channelling + LifeRegen", function()
        local needle = 'c%["6 Health Per Second"%]={{%[1%]={%[1%]={type="Condition",var="Channelling"},flags=0,keywordFlags=0,name="LifeRegen",type="BASE",value=6}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache entry must carry Condition:Channelling tag with name=LifeRegen and empty residue")
    end)

    it("ModCache must NOT carry the stale name=\"Life\" parse for Health Per Second", function()
        assert.is_nil(string.find(cacheText,
            '"6 Health Per Second"%]={{%[1%]={flags=0,keywordFlags=0,name="Life",type="BASE",value=6}},"  Per Second "}', 1, false),
            "ModCache must not contain the stale name=Life BASE parse")
    end)

    it("ModCache must NOT carry the stale '  Per Second ' residue for Health Per Second", function()
        -- Allow the residue string globally (other lines may legitimately have it),
        -- but ensure the Health Per Second entry specifically has empty residue.
        assert.is_nil(string.find(cacheText,
            'c%["6 Health Per Second"%]=[^\n]-"  Per Second "', 1, false),
            "Health Per Second entry must have empty residue")
    end)
end)
