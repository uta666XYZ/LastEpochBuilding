-- @leb-regression-guard: you-and-minions-dual-mods
-- Locks the player+minion mod pair on uniques whose in-game tooltip uses the
-- collapsed "for You and your Minions" / "You and your minions have ..."
-- wording. In LE's underlying data these tooltips are backed by TWO separate
-- mods (tags=0 player + tags=8192 minion), and LEB's ModParser does NOT have
-- a generic handler for the "for You and your Minions" suffix — leaving that
-- text in a single mod line silently parses as MinionModifier-only and drops
-- the player side entirely.
--
-- Affected uniques (datamining: extracted/items/uniques_v3.json):
--   id=66  Hollow Finger        Cold Resist + Phys Resist (both pairs hideInTooltip)
--   id=461 Ash Wake             Chance to Ignite on Hit (player + minion)
--   id=463 Rahyeh's Embrace     increased Health (player + minion)
--
-- Affected sets (Data/Set/set_1_4.json):
--   id=0   Apiarist's Suit      +Health + +Armor (player + minion)
--
-- See REGRESSION_GUARDS.md "you-and-minions-dual-mods".

local function readJson()
    local f = io.open("Data/Uniques/uniques_1_4.json", "r")
    assert.is_not_nil(f, "must be able to open uniques_1_4.json")
    local text = f:read("*a")
    f:close()
    return text
end

local function entryWindow(text, name)
    local i = string.find(text, '"name": "' .. name .. '"', 1, true)
    assert.is_not_nil(i, name .. " entry must exist")
    return string.sub(text, i, i + 2000)
end

describe("YouAndMinionsDualMods", function()
    it("Hollow Finger (id 66) carries BOTH player and minion Cold/Phys resist", function()
        local w = entryWindow(readJson(), "Hollow Finger")
        assert.is_truthy(string.find(w, '"+(7-13)% Cold Resistance"',          1, true), "player Cold Resistance")
        assert.is_truthy(string.find(w, '"+(7-13)% Minion Cold Resistance"',   1, true), "minion Cold Resistance")
        assert.is_truthy(string.find(w, '"+(7-13)% Physical Resistance"',      1, true), "player Physical Resistance")
        assert.is_truthy(string.find(w, '"+(7-13)% Minion Physical Resistance"',1,true), "minion Physical Resistance")
    end)

    it("Ash Wake (id 461) splits Ignite-on-hit into player and minion mods", function()
        local w = entryWindow(readJson(), "Ash Wake")
        assert.is_truthy(string.find(w, '"+(50-90)% Chance to Ignite on Hit"',         1, true), "player Ignite-on-hit")
        assert.is_truthy(string.find(w, '"+(50-90)% Chance to Ignite on Minion Hit"',  1, true), "minion Ignite-on-hit")
        -- The collapsed "for You and your Minions" wording must NOT remain.
        assert.is_falsy (string.find(w, 'Ignite on Hit for You and your Minions',      1, true), "collapsed wording must be removed")
    end)

    it("Rahyeh's Embrace (id 463) splits increased Health into player and minion mods", function()
        local w = entryWindow(readJson(), "Rahyeh's Embrace")
        assert.is_truthy(string.find(w, '"(30-44)% increased Health"',         1, true), "player increased Health")
        assert.is_truthy(string.find(w, '"(30-44)% increased Minion Health"',  1, true), "minion increased Health")
        assert.is_falsy (string.find(w, 'increased Health for you and your Minions', 1, true), "collapsed wording must be removed")
    end)

    it("Apiarist's Suit (set id 0) splits +Health and +Armor into player and minion mods", function()
        local f = io.open("Data/Set/set_1_4.json", "r")
        assert.is_not_nil(f, "must be able to open set_1_4.json")
        local text = f:read("*a")
        f:close()
        local i = string.find(text, '"name": "Apiarist\'s Suit"', 1, true)
        assert.is_not_nil(i, "Apiarist's Suit entry must exist")
        local w = string.sub(text, i, i + 1500)
        assert.is_truthy(string.find(w, '"+(80-150) Health"',         1, true), "player +Health")
        assert.is_truthy(string.find(w, '"+(80-150) Minion Health"',  1, true), "minion +Health")
        assert.is_truthy(string.find(w, '"+(200-400) Armor"',         1, true), "player +Armor")
        assert.is_truthy(string.find(w, '"+(200-400) Minion Armor"',  1, true), "minion +Armor")
        assert.is_falsy (string.find(w, 'for you and your Minions',   1, true), "collapsed wording must be removed")
    end)
end)
