-- @leb-regression-guard: ward-gained-per-second-alias
-- Locks the ModParser nameMap alias for the idol affix
--   idol_900_0  Suffix: "(N) Ward gained per second while wielding a Staff"
--   (ModIdol_1_4.json line ~6597; affix scales 1..18 across tiers)
--
-- Before this guard the parser only mapped the canonical "ward per second" name
-- to WardPerSecond. The actual affix text uses "Ward gained per second", which
-- caused the numeric BASE mod to fall through to the bare "Ward" stat (max ward)
-- with the residue "  gained per second  " left unparsed. Equipping the idol
-- would grant +N max Ward instead of +N Ward per Second — a silent failure that
-- doesn't show up in any numeric Ward output diff.
--
-- See REGRESSION_GUARDS.md "ward-gained-per-second-alias" and
-- LE_datamining/extracted/ward_formulas.md for the WPS pipeline that consumes
-- the corrected output.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardGainedPerSecondAlias", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser nameMap carries the 'ward gained per second' alias", function()
        assert.is_truthy(string.find(parserText,
            '%["ward gained per second"%]%s*=%s*"WardPerSecond"', 1, false),
            "ModParser nameMap must alias 'ward gained per second' to WardPerSecond")
    end)

    it("ModCache 'Ward gained per second' entries resolve to WardPerSecond (not Ward)", function()
        -- Spot-check all 7 tier entries (values 2/4/6/8/10/14/18).
        for _, val in ipairs({2, 4, 6, 8, 10, 14, 18}) do
            local key = val .. " Ward gained per second while wielding a Staff"
            local needle = 'c%["' .. key .. '"%]={{%[1%]={%[1%]={type="Condition",var="UsingStaff"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=' .. val .. '}}'
            assert.is_truthy(string.find(cacheText, needle, 1, false),
                "ModCache entry for '" .. key .. "' must produce a WardPerSecond BASE mod")
        end
    end)

    it("ModCache must NOT carry the stale 'name=\"Ward\"...gained per second' parse", function()
        -- The old broken parse emitted name="Ward" + extra="  gained per second  ".
        -- If this ever reappears, the alias was bypassed or cache was regenerated
        -- against an old ModParser.
        assert.is_nil(string.find(cacheText,
            'name="Ward",type="BASE",value=%d+}},"  gained per second  "', 1, false),
            "ModCache must not contain stale 'Ward + gained per second residue' parses")
    end)
end)
