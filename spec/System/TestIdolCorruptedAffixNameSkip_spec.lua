-- @leb-regression-guard: idol-corrupted-affix-name-skip
-- Locks that Idol / Idol Altar / Refracted display names are built from the
-- base plus NORMAL prefix/suffix name words only. Corruption-exclusive affixes
-- (specialAffixType == 6) and Class-Specific Idol enchants (specialAffixType
-- == 4) carry a stat LABEL in their `affix` field (e.g. "Maximum Idols
-- Equipped", "Bees per 10 Seconds", "Increased Mana Regeneration and Reduced
-- Health Regeneration", "Slow chance converted to Armor Shred chance", or the
-- enchant placeholder "UNKNOWN") rather than a proper name word, and corruption
-- / enchant never renames the item in-game.
--
-- Regression (reported 2026-07-14): idol / idol-altar / refracted item names were
-- prefixed with the corruption stat label, e.g. a Spire Altar with the corrupted
-- prefix 1106 "Maximum Idols Equipped" rendered as "Maximum Idols Equipped Spire
-- Altar of Eos" instead of the correct "Spire Altar of Eos". The normal suffix
-- name word ("of Eos") is preserved; only the corruption/enchant label is dropped.
--
-- Root cause: the generated name is baked into the stored name line (self.title)
-- at import time from the GENERIC data.itemMods.Item pool, where these affixes
-- carry the stat label. Three coordinated sites:
--   * ImportTab.lua  — import side (skip specialAffixType 6/4 when generating)
--   * Item.lua ParseRaw — load side (rebuild name so already-saved builds heal)
--   * Item.lua Craft() — fresh UI craft (namePrefix/nameSuffix gate)
-- The load-side rebuild classifies corruption/enchant via data.itemMods.Item
-- (authoritative) because the idol pool (ModIdol) can carry a sat==6 affix such
-- as 1063 in a non-corrupted section with no specialAffixType marker.
--
-- See REGRESSION_GUARDS.md "idol-corrupted-affix-name-skip".

describe("IdolCorruptedAffixNameSkip", function()

    local itemSrc, importSrc
    setup(function()
        local f = assert(io.open("Classes/Item.lua", "r"), "must open Classes/Item.lua")
        itemSrc = f:read("*a"); f:close()
        f = assert(io.open("Classes/ImportTab.lua", "r"), "must open Classes/ImportTab.lua")
        importSrc = f:read("*a"); f:close()
    end)

    it("Item.lua and ImportTab.lua keep the @leb-regression-guard comment", function()
        assert.is_truthy(string.find(itemSrc, "idol-corrupted-affix-name-skip", 1, true),
            "Item.lua must keep the @leb-regression-guard comment")
        assert.is_truthy(string.find(importSrc, "idol-corrupted-affix-name-skip", 1, true),
            "ImportTab.lua must keep the @leb-regression-guard comment")
    end)

    it("the name gates exclude specialAffixType 6 and 4", function()
        assert.is_truthy(string.find(itemSrc, "specialAffixType ~= 6", 1, true),
            "Item.lua name gate must exclude specialAffixType 6")
        assert.is_truthy(string.find(itemSrc, "specialAffixType ~= 4", 1, true),
            "Item.lua name gate must exclude specialAffixType 4")
        assert.is_truthy(string.find(importSrc, "specialAffixType == 6", 1, true),
            "ImportTab.lua name gate must exclude specialAffixType 6")
        assert.is_truthy(string.find(importSrc, "specialAffixType == 4", 1, true),
            "ImportTab.lua name gate must exclude specialAffixType 4")
    end)

    -- Behavioral (altar): corrupted prefix 1106 ("Maximum Idols Equipped",
    -- kind:corrupted) + normal suffix 1102 ("of Eos"). Display name must be
    -- "Spire Altar of Eos".
    it("Idol Altar corrupted prefix is dropped, normal suffix kept", function()
        newBuild()
        build.itemsTab:CreateDisplayItemFromRaw([[Rarity: EXALTED
		Maximum Idols Equipped Spire Altar of Eos
		Spire Altar
		Unique ID: 900
		Crafted: true
		Prefix: {kind:corrupted}{range:186}1106_5
		Prefix: None
		Prefix: None
		Suffix: {range:124}1102_0
		Suffix: None
		Suffix: None
		LevelReq: 1
		Implicits: 0]])
        local item = build.itemsTab.displayItem
        assert.is_not_nil(item, "displayItem should exist")
        assert.are.equals("Idol Altar", item.base and item.base.type,
            "fixture must resolve to the Idol Altar base type")
        assert.are.equals("Spire Altar of Eos", item.name,
            "corrupted stat label must be dropped and the normal suffix kept")
    end)

    -- Behavioral (idol, NO kind tag): corruption-exclusive prefix 1063
    -- ("Slow chance converted to Armor Shred chance") stored WITHOUT a
    -- {kind:corrupted} tag (as offline-save import produces) must still be
    -- excluded, classified via data.itemMods.Item (specialAffixType==6). The
    -- normal prefix 843 names the item and the normal suffix 322 ("of Fire")
    -- is kept.
    it("idol sat==6 prefix without a kind tag is still excluded", function()
        newBuild()
        build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Slow chance converted to Armor Shred chance Minor Weaver Idol of Fire
		Minor Weaver Idol
		Unique ID: Idol 7
		Crafted: true
		Prefix: {range:244}1063_0
		Prefix: {range:142}843_0
		Prefix: None
		Suffix: {range:201}322_0
		Suffix: None
		Suffix: None
		LevelReq: 0
		Implicits: 0]])
        local item = build.itemsTab.displayItem
        assert.is_not_nil(item, "displayItem should exist")
        assert.are.equals("Minor Idol", item.base and item.base.type,
            "fixture must resolve to the Minor Idol base type")
        assert.is_nil(string.find(item.name, "Slow chance", 1, true),
            "the sat==6 stat label must NOT appear in the name; got: " .. tostring(item.name))
        assert.is_truthy(string.find(item.name, "Minor Weaver Idol", 1, true),
            "the base name must be preserved; got: " .. tostring(item.name))
        assert.is_truthy(string.find(item.name, "of Fire", 1, true),
            "the normal suffix must be preserved; got: " .. tostring(item.name))
    end)
end)
