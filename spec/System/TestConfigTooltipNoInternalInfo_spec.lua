-- @leb-regression-guard:config-tooltip-no-internal-info
-- Config `tooltip` strings are USER-FACING. They must not leak internal
-- developer info. User-reported (2026-05-30): the Eterra's Blessing config
-- tooltip showed "e.g. eb5656-2 'Safeguard'" (an internal tree-node id) and
-- "See REGRESSION_GUARDS.md 'eterras-blessing-buff-gating'" (a dev-doc
-- reference). The Dread Shade tooltip leaked "DreadShadeMutator
-- .DelayedCastOnMinion" (an internal code symbol) + another REGRESSION_GUARDS
-- reference, and the curse-count tooltip leaked "Condition:Cursed" (raw
-- mod-tag syntax). All were scrubbed to plain in-game language while keeping
-- real in-game node/skill names (Safeguard, Martyrdom, etc.).
--
-- This spec scans every `tooltip = "..."` string in ConfigOptions.lua and
-- fails if any leaks internal info, so the same class of leak can't return.
--
-- See REGRESSION_GUARDS.md "config-tooltip-no-internal-info".

describe("ConfigTooltipNoInternalInfo", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local src
    setup(function()
        src = readFile("Modules/ConfigOptions.lua")
        assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
    end)

    it("carries the no-internal-info guard marker", function()
        assert.is_truthy(src:find("@leb%-regression%-guard:config%-tooltip%-no%-internal%-info", 1, false),
            "ConfigOptions.lua must carry the config-tooltip-no-internal-info guard marker")
    end)

    it("no config tooltip leaks internal developer info", function()
        local count = 0
        for tip in src:gmatch('tooltip = "([^"]*)"') do
            count = count + 1
            -- (a) Dev-doc reference.
            assert.falsy(tip:find("REGRESSION_GUARDS", 1, true),
                "tooltip references REGRESSION_GUARDS.md (internal dev doc): " .. tip)
            -- (b) Internal code symbol (CamelCase + "Mutator", ".DelayedCast", etc.).
            assert.falsy(tip:find("Mutator", 1, true),
                "tooltip leaks an internal code symbol ('Mutator'): " .. tip)
            assert.falsy(tip:find("DelayedCast", 1, true),
                "tooltip leaks an internal code symbol ('DelayedCast'): " .. tip)
            -- (c) Raw mod-tag syntax (the internal modDB key form).
            assert.falsy(tip:find("Condition:%u", 1, false),
                "tooltip leaks raw mod-tag syntax ('Condition:X'): " .. tip)
            assert.falsy(tip:find("Multiplier:%u", 1, false),
                "tooltip leaks raw mod-tag syntax ('Multiplier:X'): " .. tip)
            -- (d) Internal tree/node id: 2+ letters then alnum then "-<digit>"
            -- (e.g. eb5656-2, ch0fs-20, Mage-61). Roll ranges like "(15-40)"
            -- start with a digit so they don't match; hyphenated English
            -- words like "Off-hand" / "4-second" end in a letter so the
            -- trailing "-%d" guard excludes them.
            assert.falsy(tip:find("%a%a[%l%d]*%-%d", 1, false),
                "tooltip leaks an internal tree/node id (e.g. eb5656-2): " .. tip)
        end
        assert.is_true(count > 10, "sanity: should have scanned many tooltips; got " .. tostring(count))
    end)

    it("the cleaned tooltips keep their real in-game example names", function()
        -- Regression floor that the scrub didn't gut the useful content:
        -- the Eterra's Blessing tooltip should still cite the 'Safeguard'
        -- node, and Dread Shade should still cite Martyrdom's example mod.
        assert.is_truthy(src:find("'Safeguard'", 1, true),
            "Eterra's Blessing tooltip should still name the 'Safeguard' node example")
        assert.is_truthy(src:find("Martyrdom", 1, true),
            "Dread Shade tooltip should still name the Martyrdom example")
    end)
end)
