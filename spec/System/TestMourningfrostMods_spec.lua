-- @leb-regression-guard:mourningfrost-per-dex-resist-penalty
-- Locks Mourningfrost (Leather Boots unique, id 19) per-Dexterity Physical
-- and Cold Resistance penalty mods.
--
-- Evidence:
--   1. Datamining (LE_datamining/extracted/unique_mods_generated.json id=19):
--        "+1 cold damage to attacks and spells per point of dexterity",
--        "-1% physical and cold resistance per point of dexterity"
--   2. LETools planner Resistance breakdown for Qdz2XagK lv84 Falconer
--      (Mourningfrost equipped, Dex=91):
--        Cold Resistance: -19%
--          Boots (Unique mod): -91% Cold Resistance
--          Bow (Unique mod):   +52%
--          Blessing (Implicit): +20%
--        Physical Resistance: -5%
--          Gloves (Suffix):    +10%
--          Boots (Unique mod): -91% Physical Resistance
--          Bow (Unique mod):   +56%
--          Blessing (Implicit): +20%
--   3. Before fix, uniques_1_4.json id=19 listed only the freeze rate +
--      movement speed unique rolls; the per-Dex resistance penalty was
--      missing entirely so LEB Cold/Phys totals were ~91 higher than LE
--      across every Mourningfrost build.
--
-- See REGRESSION_GUARDS.md "mourningfrost-per-dex-resist-penalty".

describe("MourningfrostMods", function()
    it("uniques_1_4.json Mourningfrost has per-Dexterity Phys+Cold resist penalty", function()
        local f = io.open("Data/Uniques/uniques_1_4.json", "r")
        assert.is_not_nil(f, "must be able to open uniques_1_4.json")
        local text = f:read("*a")
        f:close()
        local entryStart = string.find(text, '"name": "Mourningfrost"', 1, true)
        assert.is_not_nil(entryStart, "Mourningfrost entry must exist")
        local window = string.sub(text, entryStart, entryStart + 1200)
        assert.is_truthy(
            string.find(window, '"-1% Physical Resistance per Dexterity"', 1, true),
            "Mourningfrost must carry per-Dex Physical Resistance penalty")
        assert.is_truthy(
            string.find(window, '"-1% Cold Resistance per Dexterity"', 1, true),
            "Mourningfrost must carry per-Dex Cold Resistance penalty")
        assert.is_truthy(
            string.find(window, '"+1 Cold Damage to Attacks and Spells per Dexterity"', 1, true),
            "Mourningfrost must carry per-Dex flat Cold damage to Attacks+Spells")
    end)

    it("ModParser parses '-1% Physical Resistance per Dexterity' as PerStat:Dex", function()
        local mods = modLib.parseMod("-1% Physical Resistance per Dexterity")
        assert.is_not_nil(mods)
        assert.is_not_nil(mods[1])
        assert.are.equals("PhysicalResist", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(-1, mods[1].value)
        local hasPerDex = false
        for _, tag in ipairs(mods[1]) do
            if tag.type == "PerStat" and tag.stat == "Dex" then hasPerDex = true end
        end
        assert.is_true(hasPerDex, "must carry PerStat:Dex tag")
    end)

    it("ModParser parses '-1% Cold Resistance per Dexterity' as PerStat:Dex", function()
        local mods = modLib.parseMod("-1% Cold Resistance per Dexterity")
        assert.is_not_nil(mods)
        assert.is_not_nil(mods[1])
        assert.are.equals("ColdResist", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(-1, mods[1].value)
        local hasPerDex = false
        for _, tag in ipairs(mods[1]) do
            if tag.type == "PerStat" and tag.stat == "Dex" then hasPerDex = true end
        end
        assert.is_true(hasPerDex, "must carry PerStat:Dex tag")
    end)

    -- @leb-regression-guard:flat-damage-to-attacks-and-spells
    it("ModParser parses '+1 Cold Damage to Attacks and Spells per Dexterity' with Attack+Spell flags and PerStat:Dex", function()
        local mods = modLib.parseMod("+1 Cold Damage to Attacks and Spells per Dexterity")
        assert.is_not_nil(mods)
        assert.is_not_nil(mods[1])
        assert.are.equals("ColdDamage", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(1, mods[1].value)
        local kf = mods[1].keywordFlags or 0
        assert.is_true(bit.band(kf, KeywordFlag.Attack) ~= 0, "must carry KeywordFlag.Attack")
        assert.is_true(bit.band(kf, KeywordFlag.Spell) ~= 0, "must carry KeywordFlag.Spell")
        local hasPerDex = false
        for _, tag in ipairs(mods[1]) do
            if tag.type == "PerStat" and tag.stat == "Dex" then hasPerDex = true end
        end
        assert.is_true(hasPerDex, "must carry PerStat:Dex tag")
    end)
end)
