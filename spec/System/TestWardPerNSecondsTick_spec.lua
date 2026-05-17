-- @leb-regression-guard: ward-per-n-seconds-tick
-- Locks the ModParser specialModList handler for the Mage tree node
--   tree_1.json L1900 Mage-94 "Decree of the Eternal Tundra":
--     stats: "+10 Ward Per 2 Seconds"
--     description: "You gain ward every 2 seconds."
--
-- Before this guard the line fell through to `name="Ward"` (max ward) with
-- residue "  Per 2 Seconds ". Equipping/allocating the node granted +10 max
-- Ward instead of +5 Ward per Second. Silent failure invisible in any
-- numeric Ward output diff.
--
-- The handler models the tick as a continuous WardPerSecond contribution
-- with value = N / seconds (10 / 2 = 5). In-game tick granularity is below
-- the planner's steady-state resolution.
--
-- See REGRESSION_GUARDS.md "ward-per-n-seconds-tick".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardPerNSecondsTick", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser specialModList carries the 'ward per N seconds' handler", function()
        assert.is_truthy(string.find(parserText,
            'specialModList%["%^%%%+%?%(%[%%d%%%.%]%+%) ward per %(%%d%+%) seconds%?%$"%]', 1, false),
            "ModParser must register a 'ward per N seconds' specialModList handler")
        assert.is_truthy(string.find(parserText,
            'mod%("WardPerSecond", "BASE", num / seconds%)', 1, false),
            "Handler must emit WardPerSecond BASE with value = num/seconds")
    end)

    it("ModCache '+10 Ward Per 2 Seconds' resolves to WardPerSecond BASE=5", function()
        local needle = 'c%["%+10 Ward Per 2 Seconds"%]={{%[1%]={flags=0,keywordFlags=0,name="WardPerSecond",type="BASE",value=5}},nil}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "ModCache entry must produce a WardPerSecond BASE=5 mod (10/2)")
    end)

    it("ModCache must NOT carry the stale 'name=\"Ward\"...Per 2 Seconds' parse", function()
        assert.is_nil(string.find(cacheText,
            'c%["%+10 Ward Per 2 Seconds"%]={{%[1%]={flags=0,keywordFlags=0,name="Ward",type="BASE"', 1, false),
            "ModCache must not contain the stale max-Ward parse for +10 Ward Per 2 Seconds")
    end)
end)
