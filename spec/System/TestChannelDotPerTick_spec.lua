-- @leb-regression-guard:channel-dot-per-second-base
-- See REGRESSION_GUARDS.md "channel-dot-per-second-base".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("channel DoT per-tick damage_interval (data-grounded)", function()
    local CHANNELS = {
        { key = "DrainLife",              name = "Drain Life",  interval = 183.3 },
        { key = "Disintegrate",           name = "Disintegrate", interval = 250 },
        { key = "Warlock 02 Ghostflame",  name = "Ghostflame",  interval = 250 },
    }

    for _, c in ipairs(CHANNELS) do
        it(c.name .. " carries the datamined damage_interval and the 1e5 channel duration", function()
            local d = data.skills[c.key]
            assert.is_table(d, c.key .. " must exist in data.skills")
            assert.are.equals(c.name, d.name)
            assert.is_truthy(d.baseFlags.dot, c.name .. " is a DoT")
            assert.is_nil(d.baseFlags.hit, c.name .. " is a pure (non-hit) channel DoT")
            assert.are.equals(c.interval, d.stats.damage_interval,
                c.name .. " must carry the datamined per-tick damage_interval (ms)")
            assert.are.equals(100000000, d.stats.base_skill_effect_duration,
                c.name .. " keeps its 1e8ms 'infinite' channel duration")
        end)
    end

    it("CalcOffence carries the channel-dot-per-second-base guard + MaxStacks=1 clamp", function()
        local text = assert(readFile("Modules/CalcOffence.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:channel%-dot%-per%-second%-base"),
            "CalcOffence must carry the channel-dot-per-second-base guard marker")
        -- the clamp: infinite-duration channel DoT -> MaxStacks = 1
        assert.is_truthy(text:find("skillData%.duration >= 1000"),
            "CalcOffence must clamp MaxStacks for duration >= 1000s channel DoTs")
    end)
end)
