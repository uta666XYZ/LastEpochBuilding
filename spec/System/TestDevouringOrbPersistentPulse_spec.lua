-- @leb-regression-guard: devouring-orb-persistent-pulse-hit
-- See REGRESSION_GUARDS.md for the index entry.
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("DevouringOrbPersistentPulse", function()

    it("CalcOffence routes non-dot+hit+duration+damageInterval to the pulse path", function()
        local calc = readSource("Modules/CalcOffence.lua")
        -- the persistentPulseHit predicate must exist with the exact 4-clause gate
        assert.is_truthy(string.find(calc,
            "local persistentPulseHit = not skillFlags.dot and skillFlags.hit", 1, true),
            "persistentPulseHit predicate must gate on not-dot + hit")
        assert.is_truthy(string.find(calc,
            "and skillFlags.duration and skillData.damageInterval", 1, true),
            "persistentPulseHit predicate must also require duration + damageInterval")
        -- the elseif branch must divide TotalDPS by damageInterval (pulses/second)
        assert.is_truthy(string.find(calc,
            "elseif persistentPulseHit then", 1, true),
            "the DPS dispatch must have a persistentPulseHit branch")
        assert.is_truthy(string.find(calc,
            "output.TotalDPS = output.TotalDPS / skillData.damageInterval", 1, true),
            "persistent-pulse branch must divide TotalDPS by damageInterval")
    end)

    it("DevouringOrb skill data still has the persistent-pulse shape (no dot flag)", function()
        local skills = readSource("Data/skills.json")
        local s = string.find(skills, '"DevouringOrb"', 1, true)
        assert.is_not_nil(s, "DevouringOrb must exist in skills.json")
        -- Isolate JUST the DevouringOrb baseFlags object so we don't read a
        -- neighbouring skill's `dot` flag. baseFlags appears right after the key.
        local bfStart = string.find(skills, '"baseFlags"', s, true)
        local bfClose = string.find(skills, "}", bfStart, true)
        local baseFlags = string.sub(skills, bfStart, bfClose)
        assert.is_truthy(string.find(baseFlags, '"hit": true', 1, true),
            "DevouringOrb must keep the hit baseFlag")
        assert.is_truthy(string.find(baseFlags, '"duration": true', 1, true),
            "DevouringOrb must keep the duration baseFlag")
        assert.is_nil(string.find(baseFlags, '"dot"', 1, true),
            "DevouringOrb baseFlags must NOT carry a dot flag (else it uses the dot path)")
        -- stats block (after baseFlags) must keep the 250ms pulse cadence
        local statsBlock = string.sub(skills, bfClose, bfClose + 400)
        assert.is_truthy(string.find(statsBlock, '"damage_interval": 250', 1, true),
            "DevouringOrb damage_interval must be 250ms (0.25s pulse cadence)")
    end)
end)
