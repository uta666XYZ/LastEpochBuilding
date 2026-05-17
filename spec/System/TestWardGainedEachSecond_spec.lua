-- @leb-regression-guard: ward-gained-each-second-alias
-- Locks the ModParser nameMap alias for the Wandering Spirit unique mods
--   uniques_1_4.json L4631 "Symbol of Hope":
--     "{rounding:Integer}+(6-11) Ward gained each second per Active Wandering Spirit"
--   uniques_1_4.json L7464 (unique helmet):
--     "{rounding:Integer}+(4-7) Ward gained each second per Active Wandering Spirit"
--
-- Same silent-failure shape as the staff idol guard (ward-gained-per-second-alias):
-- without the "ward gained each second" alias the BASE mod fell through to `Ward`
-- (max ward) with residue "  gained each second  ", and the `per Active Wandering
-- Spirit` multiplier was glued to the wrong stat. Equipping the unique would grant
-- +N max Ward per spirit instead of +N WPS per spirit — a silent failure invisible
-- in numeric Ward output diffs.
--
-- See REGRESSION_GUARDS.md "ward-gained-each-second-alias".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardGainedEachSecondAlias", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser nameMap carries the 'ward gained each second' alias", function()
        assert.is_truthy(string.find(parserText,
            '%["ward gained each second"%]%s*=%s*"WardPerSecond"', 1, false),
            "ModParser nameMap must alias 'ward gained each second' to WardPerSecond")
    end)

    it("ModCache Wandering Spirit entries resolve to WardPerSecond (not Ward)", function()
        for _, val in ipairs({6, 9}) do
            local key = "+" .. val .. " Ward gained each second per Active Wandering Spirit"
            local needle = 'c%["%+' .. val .. ' Ward gained each second per Active Wandering Spirit"%]={{%[1%]={%[1%]={type="Multiplier",var="ActiveWanderingSpirit"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=' .. val .. '}}'
            assert.is_truthy(string.find(cacheText, needle, 1, false),
                "ModCache entry for '" .. key .. "' must produce a WardPerSecond BASE mod")
        end
    end)

    it("ModCache '+1 Ward Gained Per 3 Int Per Second' resolves to WardPerSecond", function()
        -- Mage tree node dig5-28 (tree_1.json L3442). With the new
        -- 'ward gained per second' alias in place, the PerStat tag is preserved
        -- and the name resolves to WardPerSecond instead of the bare `Ward`
        -- stat with residue "  Gained  Per Second ".
        local needle = 'c%["%+1 Ward Gained Per 3 Int Per Second"%]={{%[1%]={%[1%]={div=3,stat="Int",type="PerStat"},flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=1}}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache entry for '+1 Ward Gained Per 3 Int Per Second' must produce a WardPerSecond BASE mod with PerStat tag intact")
    end)

    it("ModCache must NOT carry the stale 'name=\"Ward\"...gained each second' parse", function()
        assert.is_nil(string.find(cacheText,
            'name="Ward",type="BASE",value=%d+}},"  gained each second  "', 1, false),
            "ModCache must not contain stale 'Ward + gained each second residue' parses")
    end)
end)
