-- @leb-regression-guard:hammer-throw-spiral-multihit
-- See REGRESSION_GUARDS.md > "hammer-throw-spiral-multihit".
-- Validation provenance is retained in maintainer notes.

local function readSrc(rel)
    local f = io.open(rel, "r") or io.open("src/" .. rel, "r")
    assert.is_not_nil(f, rel .. " must be readable")
    local s = f:read("*a"); f:close()
    return s
end

local function firstNamed(ml, name)
    if not ml then return nil end
    for _, m in ipairs(ml) do if m.name == name then return m end end
    return nil
end

local function liveParse(line)
    local saved = modLib.parseModCache[line]
    modLib.parseModCache[line] = nil
    local ml = modLib.parseMod(line)
    modLib.parseModCache[line] = saved
    return ml
end

describe("HammerThrowSpiralMultihit", function()
    before_each(function()
        newBuild()
    end)

    it("' Hammers Spiral' node stat parses to the HammersSpiral flag", function()
        -- exact node-stat form (leading space, as stored in tree_2.json ht16aw-20)
        local m = firstNamed(liveParse(" Hammers Spiral"), "HammersSpiral")
        assert.is_not_nil(m, "spiral node stat must emit HammersSpiral")
        assert.are.equals("FLAG", m.type)
        assert.is_true(m.value)
    end)

    it("' Half Extra Projectiles' node stat parses to the HalveExtraProjectiles flag", function()
        local m = firstNamed(liveParse(" Half Extra Projectiles"), "HalveExtraProjectiles")
        assert.is_not_nil(m, "half-extra node stat must emit HalveExtraProjectiles")
        assert.are.equals("FLAG", m.type)
        assert.is_true(m.value)
    end)

    it("ModCache does NOT shadow the spiral flags with empty mod lists", function()
        -- The exact bug: cache-first parseMod returned {{},""} for these keys, so the
        -- live specialModList entries never ran. The cached rows must now carry the flag.
        local hs = modLib.parseModCache[" Hammers Spiral"]
        assert.is_not_nil(hs, "ModCache must keep a row for ' Hammers Spiral'")
        assert.is_not_nil(firstNamed(hs[1], "HammersSpiral"),
            "cached ' Hammers Spiral' must contain the HammersSpiral flag, not an empty list")
        local he = modLib.parseModCache[" Half Extra Projectiles"]
        assert.is_not_nil(he, "ModCache must keep a row for ' Half Extra Projectiles'")
        assert.is_not_nil(firstNamed(he[1], "HalveExtraProjectiles"),
            "cached ' Half Extra Projectiles' must contain the HalveExtraProjectiles flag")
    end)

    it("ModParser registers the spiral node-stat flags", function()
        local src = readSrc("Modules/ModParser.lua")
        assert.is_truthy(src:find("@leb-regression-guard:hammer-throw-spiral-multihit", 1, true))
        assert.is_truthy(src:find('["hammers spiral"] = { flag("HammersSpiral") }', 1, true))
        assert.is_truthy(src:find('["half extra projectiles"] = { flag("HalveExtraProjectiles") }', 1, true))
    end)

    it("CalcOffence gates the same-target multiplier on the spiral flag and applies it to both paths", function()
        local src = readSrc("Modules/CalcOffence.lua")
        -- gated count: base 1 + halved additional projectiles
        assert.is_truthy(src:find('skillModList:Flag(skillCfg, "HammersSpiral")', 1, true),
            "multiplier must be gated on the (skill-scoped) HammersSpiral flag")
        assert.is_truthy(src:find("output.SpiralHammerHits = 1 + additionalProj", 1, true),
            "count = base 1 + additional projectiles")
        assert.is_truthy(src:find('skillModList:Flag(skillCfg, "HalveExtraProjectiles")', 1, true),
            "Iron Spiral halves the additional projectiles")
        -- direct hit: folded into dpsMultiplier
        assert.is_truthy(src:find("skillData.dpsMultiplier = (skillData.dpsMultiplier or 1) * output.SpiralHammerHits", 1, true),
            "direct hit DPS must be multiplied by the hammer count")
        -- damaging ailment: the dpsMultiplier does NOT reach the ailment rate, so the
        -- ailment loop must multiply its own hitRate by the same count.
        assert.is_truthy(src:find("hitRate = hitRate * output.SpiralHammerHits", 1, true),
            "ailment application rate must be multiplied by the hammer count")
    end)
end)
