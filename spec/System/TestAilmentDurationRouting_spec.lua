-- @leb-regression-guard:ailment-duration-routing
-- See REGRESSION_GUARDS.md > "ailment-duration-routing".
-- Validation provenance is retained in maintainer notes.

local function readSrc(rel)
    local f = io.open(rel, "r") or io.open("src/" .. rel, "r")
    assert.is_not_nil(f, rel .. " must be readable")
    local s = f:read("*a"); f:close()
    return s
end

local function liveParse(line)
    local saved = modLib.parseModCache[line]
    modLib.parseModCache[line] = nil
    local ml = modLib.parseMod(line)
    modLib.parseModCache[line] = saved
    return ml
end

local function firstNamed(ml, name)
    if not ml then return nil end
    for _, m in ipairs(ml) do if m.name == name then return m end end
    return nil
end

describe("AilmentDurationRouting", function()
    before_each(function()
        newBuild()
    end)

    it("'Increased Bleed Duration' routes to EnemyBleedDuration INC (not generic Duration)", function()
        local ml = liveParse("67% Increased Bleed Duration")
        local m = firstNamed(ml, "EnemyBleedDuration")
        assert.is_not_nil(m, "bleed-duration affix must emit EnemyBleedDuration")
        assert.are.equals("INC", m.type)
        assert.are.equals(67, m.value)
        assert.is_nil(firstNamed(ml, "Duration"),
            "must NOT also emit the generic Duration mod (that never reaches the ailment loop)")
    end)

    it("per-ailment keys keep Ignite Duration OUT of the bleed channel", function()
        local ig = liveParse("25% Increased Ignite Duration")
        assert.is_not_nil(firstNamed(ig, "EnemyIgniteDuration"), "ignite routes to its own channel")
        assert.is_nil(firstNamed(ig, "EnemyBleedDuration"),
            "ignite duration must never land on bleed")
    end)

    it("ModParser carries the per-ailment duration keys", function()
        local src = readSrc("Modules/ModParser.lua")
        assert.is_truthy(src:find("@leb-regression-guard:ailment-duration-routing", 1, true))
        assert.is_truthy(src:find('["bleed duration"] = "EnemyBleedDuration"', 1, true))
        assert.is_truthy(src:find('["ignite duration"] = "EnemyIgniteDuration"', 1, true))
    end)

    it("CalcOffence ailment loop scales effDuration by the per-ailment duration channel", function()
        local src = readSrc("Modules/CalcOffence.lua")
        -- enemyDurationMap.Bleed = output.EnemyBleedDuration, consumed as durationMult
        assert.is_truthy(src:find("Bleed = output.EnemyBleedDuration", 1, true),
            "the loop must map Bleed -> EnemyBleedDuration")
        assert.is_truthy(src:find("local effDuration = baseDuration * durationMult", 1, true),
            "effDuration must scale by the per-ailment durationMult")
    end)

    it("Bleed base duration data is stable (3s) so the multiplier is the only lever", function()
        assert.are.equals(3, data.damagingAilment.Bleed.duration)
    end)
end)
