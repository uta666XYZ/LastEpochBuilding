-- @leb-regression-guard:unique-inherent-not-crafted
-- @leb-regression-guard:item-tooltip-source-colour
-- LEB's unique importers used to tag a unique's OWN mods "{crafted}" (two
-- `TODO: avoid using crafted` comments marked the debt). That was wrong twice over:
--   * Visibly: LEB painted unique-inherent mods CRAFTED pale blue, while in-game they
--     render WHITE. Confirmed in-game 2026-07-16 on Suloron's Step, an LP-crafted
--     Legendary: its unique mods ("+95% Melee Critical Strike Multiplier", "22%
--     increased Movement Speed", "-75% Physical Resistance") are white and carry no
--     "Tier:" row, while its two rolled T7 affixes render crimson.
--   * Structurally: `crafted` was load-bearing for THREE non-colour readers, so it
--     could not simply be dropped. The dangerous one is isLegendaryAffix
--     (Item.lua BuildAndParseRaw), which gates Permanence's "increased Effect of Skill
--     Level modifiers on Legendary Affixes". If a unique's own mods stopped being
--     excluded there, they would be scaled as legendary affixes and DPS would MOVE.
--
-- This spec locks: (1) the new flag survives a raw round-trip, (2) unique mods are
-- excluded from the legendary-affix set on a LEGENDARY item, (3) the tooltip renders
-- them white, and (4) the legacy {crafted} migration is calc-inert.
--
-- See REGRESSION_GUARDS.md "unique-inherent-not-crafted".

describe("Unique-inherent mods are not crafted #items", function()
	before_each(function() newBuild() end)

	it("{uniqueInherent} round-trips through raw text", function()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: UNIQUE
Throne of Ambition
Adorned Silver Idol
{uniqueInherent}2% more Fire Damage per stack of Ambition]])
		local item = build.itemsTab.displayItem
		local modLine = item.explicitModLines[1]
		assert.is_true(modLine.uniqueInherent, "the {uniqueInherent} flag must parse")
		assert.is_nil(modLine.crafted, "uniqueInherent must not imply crafted")
		assert.is_truthy(item:BuildRaw():find("{uniqueInherent}", 1, true),
			"BuildRaw must re-emit the flag or it is lost on save")
	end)

	it("a unique-inherent mod renders WHITE, not CRAFTED pale blue", function()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: UNIQUE
Throne of Ambition
Adorned Silver Idol
{uniqueInherent}2% more Fire Damage per stack of Ambition]])
		local item = build.itemsTab.displayItem
		local out = itemLib.formatModLine(item.explicitModLines[1], false, nil, item)
		assert.is_not_nil(out)
		assert.is_truthy(out:find(colorCodes.NORMAL, 1, true),
			"in-game unique mods take the default (white) colour")
		assert.is_nil(out:find(colorCodes.CRAFTED, 1, true),
			"a unique's own mods are not crafted")
	end)

	-- The load-bearing one. isLegendaryAffix requires modLine.affixType, which a
	-- unique-inherent line never has, AND `not crafted and not uniqueInherent`. Assert
	-- the flag itself is the thing keeping the mod out of the legendary-affix set, so
	-- that dropping `not modLine.uniqueInherent` from that gate trips here.
	it("unique-inherent mods are excluded from Permanence's legendary-affix scaling", function()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: LEGENDARY
Suloron's Step
Brigandine Boots
{uniqueInherent}22% increased Movement Speed]])
		local item = build.itemsTab.displayItem
		local modLine = item.explicitModLines[1]
		assert.is_true(modLine.uniqueInherent)
		for _, mod in ipairs(modLine.modList or {}) do
			assert.is_nil(mod.legendaryAffix,
				"a unique's own mod must never be tagged legendaryAffix -- Permanence would scale it")
		end
	end)

	-- Legacy migration: builds saved before the split carry {crafted} on unique mods
	-- (633 corpus files at the time of writing). They must be reclassified so the
	-- colour is fixed without a re-import -- and must stay calc-inert while doing it.
	it("legacy {crafted} on a unique is migrated to uniqueInherent", function()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: UNIQUE
Throne of Ambition
Adorned Silver Idol
{crafted}2% more Fire Damage per stack of Ambition]])
		local modLine = build.itemsTab.displayItem.explicitModLines[1]
		assert.is_true(modLine.uniqueInherent, "legacy {crafted} on a unique must migrate")
		assert.is_nil(modLine.crafted, "and must not remain crafted, or it stays pale blue")
	end)

	it("the migration does not touch {crafted} on a non-unique item", function()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
Brass Sceptre
Brass Sceptre
{crafted}2% more Fire Damage per stack of Ambition]])
		local modLine = build.itemsTab.displayItem.explicitModLines[1]
		assert.is_true(modLine.crafted, "a RARE item's crafted mod is genuinely crafted")
		assert.is_nil(modLine.uniqueInherent)
	end)

	it("the migration is calc-inert: {crafted} and {uniqueInherent} give identical DPS", function()
		local function dpsWith(flag)
			newBuild()
			build.itemsTab:CreateDisplayItemFromRaw([[Rarity: UNIQUE
Throne of Ambition
Adorned Silver Idol
]] .. flag .. [[2% more Cold Damage per stack of Ambition]])
			build.itemsTab:AddDisplayItem()
			build.skillsTab:SelSkill(1, "Runemaster 05c3 Runebolt Cold")
			build.configTab.input["multiplierActiveAmbition"] = 20
			build.configTab:BuildModList()
			runCallback("OnFrame")
			return build.calcsTab.mainOutput.TotalDPS
		end
		local dpsCrafted = dpsWith("{crafted}")
		local dpsInherent = dpsWith("{uniqueInherent}")
		assert.is_true(dpsCrafted > 0)
		assert.are.equals(round(dpsCrafted, 4), round(dpsInherent, 4),
			"the flag split must move colour only, never a number")
	end)
end)
