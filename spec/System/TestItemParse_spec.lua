describe("TestItemParse #itemParse", function()
    it("Creating unique", function()
        local item = new("Item", "", "UNIQUE")
        item.title = "Calamity"
        item.baseName = "Jewelled Circlet"
        item.explicitModLines = { { line = "+(10-20) Armor" } }
        item:BuildAndParseRaw()
        --print(item:BuildRaw())
        assert.are.equals("Calamity", item.name)
    end)

    it("Test idol with multiline affixes + roundings", function()
        newBuild()
        build.itemsTab:CreateDisplayItemFromRaw([[ Rarity: RARE
        Stout Weaver Idol
        Stout Weaver Idol
        Unique ID: Idol 4
        Crafted: true
        Prefix: {range:205}890_0
        Prefix: None
        Prefix: None
        Suffix: {range:0}880_0
        Suffix: None
        Suffix: None
        LevelReq: 0
        Implicits: 0
        {range:205}{rounding:Integer}+(15-20) Ward per Second
        {range:205}+(8-16)% Ward Retention
        {range:0}{rounding:Integer}(9-20) Health Gain on Kill
        {range:0}{rounding:Integer}(5-6)% increased Health]])

        -- Check parsed mods directly on the display item (before AddDisplayItem clears it)
        -- Idols are not auto-equipped so modDB is not usable here; test the item modList instead
        local item = build.itemsTab.displayItem
        assert.is_not_nil(item, "displayItem should exist")
        local lifeInc = 0
        for _, mod in ipairs(item.modList) do
            if mod.name == "Life" and mod.type == "INC" then
                lifeInc = lifeInc + mod.value
            end
        end
        -- {range:0} = minimum roll: (5-6)% increased Health -> 5%
        assert.are.equals(5, lifeInc)
    end)
end)
