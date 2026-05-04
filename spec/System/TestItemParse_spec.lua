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

    -- @leb-regression-guard: affix-kind-roundtrip
    -- Locks in the {kind:sealed}/{kind:corrupted}/{kind:primordial} tag emission
    -- in Item:BuildRaw and parsing in Item:ParseRaw so future edits to those
    -- two functions cannot silently drop the tag (commit 92db3d1d6).
    -- If this breaks, sealed/corrupted/primordial affixes lose their bottom-of-list
    -- placement in the modifiers display and Item:Craft cannot route them to the
    -- correct bucket.
    it("Affix kind tag round-trips through BuildRaw/ParseRaw", function()
        -- newBuild() loads data.itemBases for the active targetVersion so
        -- ParseRaw can resolve baseName -> base.type and populate self.affixes
        -- before the round-trip lookup at Item.lua:696.
        newBuild()
        local item = new("Item", "", "RARE")
        item.crafted = true
        -- For RARE items, ParseRaw consumes the first line as `self.name` and
        -- only enters base-detection on subsequent lines. BuildRaw emits a
        -- two-line name+base header iff `item.title` is set, so we need both
        -- title (any string) and a real baseName for the round-trip to find
        -- data.itemBases[base] and populate self.affixes (Item.lua:577).
        -- "Refuge Armor" is a real Body Armor base, also used by the next test.
        item.title = "Test Body"
        item.baseName = "Refuge Armor"
        item.prefixes = {
            { modId = "FOO_0", range = 100, kind = "normal" },
            { modId = "BAR_0", range = 100, kind = "sealed" },
        }
        item.suffixes = {
            { modId = "BAZ_0", range = 100, kind = "corrupted" },
            { modId = "QUX_0", range = 100, kind = "primordial" },
        }
        local raw = item:BuildRaw()
        -- "normal" kind is intentionally NOT emitted (default); only the three
        -- specials carry an explicit tag.
        assert.is_nil(raw:find("Prefix: {kind:normal}", 1, true),
            "kind=normal must not emit a tag (keeps legacy XMLs unchanged)")
        assert.is_not_nil(raw:find("Prefix: {kind:sealed}{range:100}BAR_0", 1, true),
            "sealed kind must round-trip into Prefix: line")
        assert.is_not_nil(raw:find("Suffix: {kind:corrupted}{range:100}BAZ_0", 1, true),
            "corrupted kind must round-trip into Suffix: line")
        assert.is_not_nil(raw:find("Suffix: {kind:primordial}{range:100}QUX_0", 1, true),
            "primordial kind must round-trip into Suffix: line")
        -- Re-parse and verify the kind survives onto entry.kind.
        item:ParseRaw(raw)
        assert.are.equal("sealed",     item.prefixes[2].kind)
        assert.are.equal("corrupted",  item.suffixes[1].kind)
        assert.are.equal("primordial", item.suffixes[2].kind)
    end)

    -- @leb-regression-guard: affix-display-order
    -- Locks in the canonical bucket order assembled by Item:Craft:
    --   prefix -> suffix -> enchant -> savedMods (unique mods) -> sealed -> primordial -> corrupted
    -- Uses Refuge Armor + sat==6 prefix 1002_0 to verify a corrupted-only affix
    -- ends up AT THE END of explicitModLines (matching LE / LETools tooltip).
    it("Craft places sat==6 corrupted affix at the bottom of explicitModLines", function()
        newBuild()
        build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
        Test Order Body
        Refuge Armor
        Unique ID: TestOrder 1
        Crafted: true
        Prefix: {range:128}3_0
        Prefix: {range:0}1002_0
        Suffix: None
        Suffix: None
        LevelReq: 0
        Implicits: 0]])

        local item = build.itemsTab.displayItem
        assert.is_not_nil(item, "displayItem should exist")
        -- The last explicitModLine MUST come from the sat==6 affix (1002_0 =
        -- "Missing Health gained as Ward per second" / "Ward Decay Threshold").
        local last = item.explicitModLines[#item.explicitModLines]
        assert.is_not_nil(last, "explicitModLines must not be empty")
        local lastLine = (last.line or ""):lower()
        assert.is_true(
            lastLine:find("ward", 1, true) ~= nil,
            "Last explicit mod must be from sat==6 corrupted affix; got: " .. tostring(last.line))
    end)

    -- @leb-regression-guard: unique-req-level-override
    -- Uniques can specify a lower req.level than their base type (e.g. Vaion's
    -- Chariot lvl 50 vs Solarum Greaves base lvl 67). Item.lua must override
    -- self.requirements.level from data.uniques entry's req.level for
    -- UNIQUE/LEGENDARY items in BOTH the post-ParseRaw site AND Item:Craft();
    -- otherwise CalcSetup's LevelReq filter (CalcSetup.lua:858-865) drops the
    -- entire item from calc when character.level < base.req.level, even though
    -- in-game the item is equippable at character.level >= unique.req.level.
    -- Establishing commit: 5a88e7161
    it("Unique req.level overrides base req.level (UNIQUE/LEGENDARY)", function()
        newBuild()
        -- Vaion's Chariot: unique req=50, base Solarum Greaves req=67.
        -- XML stores LevelReq: 67 (the base value, also asserted as
        -- importedLevelReq by ParseRaw). After parse, requirements.level
        -- MUST be 50, not 67, so character lv62 keeps the boots equipped.
        build.itemsTab:CreateDisplayItemFromRaw([[Rarity: LEGENDARY
        Vaion's Chariot
        Solarum Greaves
        Unique ID: 8
        Crafted: true
        Prefix: {range:255}28_6
        Prefix: None
        Prefix: None
        Prefix: None
        Prefix: None
        Suffix: None
        Suffix: None
        Suffix: None
        Suffix: None
        Suffix: None
        LevelReq: 67
        Implicits: 3
        +90 Armor
        {range:38}(15-18)% increased Movement Speed
        {range:247}+(30-45)% Fire Resistance
        {range:255}{affixType:Prefix}(26-30)% increased Movement Speed
        {crafted}{range:255}(10-18)% increased Movement Speed
        {crafted}100% Increased Damage per 100% Increased Movement Speed
        {crafted}{range:255}(24-40)% More Damage with your next Movement Skill Every 3 Seconds
        {crafted}{range:255}+(4-10)% to All Resistances
        {crafted}{range:255}{rounding:Integer}+(40-120) Armor]])

        local item = build.itemsTab.displayItem
        assert.is_not_nil(item, "displayItem should exist")
        assert.is_not_nil(item.requirements, "item.requirements should exist")
        assert.are.equals(50, item.requirements.level,
            "Vaion's Chariot must use unique req.level=50, not base req.level=67")

        -- Re-run Craft() to ensure the override survives the recraft path.
        item:Craft()
        assert.are.equals(50, item.requirements.level,
            "After Craft(), unique req.level=50 must still hold (not reset to base 67)")
    end)

    it("Auto-detects corrupted from specialAffixType==6 affix (no 'Corrupted' marker)", function()
        newBuild()
        -- Refuge Armor (Body Armor base) with sat==6 prefix 1002_0 (Missing Health
        -- gained as Ward per Second and Ward Decay Threshold). Raw text intentionally
        -- omits a "Corrupted" line — auto-detection in Item.lua ParseRaw should set
        -- self.corrupted = true purely from the affix's specialAffixType.
        build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
        Test Corrupted Body
        Refuge Armor
        Unique ID: TestCorrupted 1
        Crafted: true
        Prefix: {range:0}1002_0
        Prefix: None
        Suffix: None
        Suffix: None
        LevelReq: 0
        Implicits: 0
        {range:0}+4% Missing Health gained as Ward per second
        {range:0}{rounding:Integer}+(30-32) Ward Decay Threshold]])

        local item = build.itemsTab.displayItem
        assert.is_not_nil(item, "displayItem should exist")
        assert.is_true(item.corrupted, "item.corrupted should auto-derive from sat==6 affix")
    end)
end)
