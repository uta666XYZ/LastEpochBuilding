-- Triangulation probe: does "+X% Minion Movespeed" (the literal node text used by
-- Beastmaster "The Chase" Primalist-22 and similar passives) parse into a
-- MinionModifier(MovementSpeed, INC) mod, or does it get dropped?
--
-- LETools tooltip on Qqwvdex2 lv98 Beastmaster:
--   "Movement Speed: 24%
--    Beastmaster Passive Tree (The Chase): 24% increased Minion Movement Speed"
-- LEB output.MinionMovementSpeed = 0 → 100% miss.
describe("MinionMovespeedNodeText", function()
    before_each(function()
        newBuild()
    end)

    it("'+24% Minion Movespeed' (node literal) accumulates into MinionMovementSpeed", function()
        build.configTab.input.customMods = "+24% Minion Movespeed"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equals(24, build.calcsTab.calcsOutput.MinionMovementSpeed or 0)
    end)

    it("'24% increased Minion Movement Speed' (canonical) accumulates", function()
        build.configTab.input.customMods = "24% increased Minion Movement Speed"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equals(24, build.calcsTab.calcsOutput.MinionMovementSpeed or 0)
    end)

    -- eb5656-8 Ardent Touch (Necromancer/Acolyte ascendancy node) phrasing
    it("'+6% Increased Minion Movespeed' (Ardent Touch) accumulates", function()
        build.configTab.input.customMods = "+6% Increased Minion Movespeed"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equals(6, build.calcsTab.calcsOutput.MinionMovementSpeed or 0)
    end)

    -- Acolyte-20 Invigorated Dead phrasing — "Minion" comes BEFORE "Increased"
    it("'2% Minion Increased Movement Speed' (Invigorated Dead) accumulates", function()
        build.configTab.input.customMods = "2% Minion Increased Movement Speed"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equals(2, build.calcsTab.calcsOutput.MinionMovementSpeed or 0)
    end)

    -- Sanity: post-normalization shape should already work
    it("'2% Increased Minion Movement Speed' (post-normalize) accumulates", function()
        build.configTab.input.customMods = "2% Increased Minion Movement Speed"
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
        assert.are.equals(2, build.calcsTab.calcsOutput.MinionMovementSpeed or 0)
    end)
end)
