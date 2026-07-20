-- @leb-regression-guard: flame-whip-crit-mult-per-uncapped-necrotic-res
-- See REGRESSION_GUARDS.md "flame-whip-crit-mult-per-uncapped-necrotic-res".
-- Validation provenance is retained in maintainer notes.

describe("FlameWhipCritMultPerNecroticRes", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    it("parses the node to a Flame-Whip-scoped CritMultiplier per uncapped Necrotic Resistance", function()
        local mods = modLib.parseMod("+8% Critical Strike Multiplier with Flame Whip per 10% Uncapped Necrotic Resistance")
        assert.is_not_nil(mods, "modLib.parseMod must return a mod list")
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("CritMultiplier", m.name)
        assert.are.equals("BASE", m.type)
        assert.are.equals(8, m.value)

        -- collect the two tags regardless of order
        local skillNameTag, perStatTag
        for _, tag in ipairs(m) do
            if tag.type == "SkillName" then skillNameTag = tag end
            if tag.type == "PerStat" then perStatTag = tag end
        end
        assert.is_not_nil(skillNameTag, "must carry a SkillName tag")
        assert.are.equals("Flame Whip", skillNameTag.skillName)

        assert.is_not_nil(perStatTag, "must carry a PerStat tag")
        assert.are.equals("NecroticResistTotal", perStatTag.stat,
            "must scale on the UNCAPPED necrotic resistance total, not the capped NecroticResist")
        assert.are.equals(10, perStatTag.div)
    end)

    it("handles every roll in the (6-9)% range via the live parser", function()
        for _, v in ipairs({6, 7, 9}) do
            local mods = modLib.parseMod(v .. "% Critical Strike Multiplier with Flame Whip per 10% Uncapped Necrotic Resistance")
            assert.is_not_nil(mods, "roll " .. v .. " must parse")
            assert.are.equals(1, #mods)
            assert.are.equals("CritMultiplier", mods[1].name)
            assert.are.equals(v, mods[1].value)
        end
    end)

    it("ModCache no longer leaves the node as a bare global crit mult with residue", function()
        local cacheSrc = readFile("Data/ModCache.lua")
        assert.is_not_nil(cacheSrc, "must read Data/ModCache.lua")
        local line = cacheSrc:match('(c%["%+8%% Critical Strike Multiplier with Flame Whip per 10%% Uncapped Necrotic Resistance"%]=[^\n]*)')
        assert.is_not_nil(line, "ModCache must still carry the node entry")
        assert.is_truthy(line:find("NecroticResistTotal", 1, true),
            "ModCache must scope by the uncapped Necrotic Resistance total")
        assert.is_truthy(line:find("Flame Whip", 1, true),
            "ModCache must keep the Flame Whip skill scope")
        assert.is_falsy(line:find("keywordFlags=32", 1, true),
            "stray keywordFlag must be gone")
    end)
end)
