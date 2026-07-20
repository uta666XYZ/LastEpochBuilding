-- @leb-regression-guard:item-tooltip-source-colour
-- LEB colours each item mod line by its SOURCE, mirroring LE's own per-line priority
-- (TooltipContentBuilder.GetItemModifierIconForAffix, applied in-game as the row's icon
-- tint). Hex values come from the game's MasterColorList / MasterItemTooltipAssetList.
--
-- The ORDER is the whole point of this spec. Every case below is an in-game screenshot
-- (2026-07-16), not a preference:
--   * Suloron's Step (LP Legendary): T7 affixes CRIMSON, unique-inherent mods WHITE.
--   * The Last Bear's Fury Reforged (Set): the SAME T7 "+16 Strength" is PURPLE.
--     -> item rarity is tested BEFORE tier.
--   * Weaver's Touch idol: "+13 Ward Decay Threshold" ("Tier: 4 (enchantment only)")
--     is CYAN -> the idol-enchant pool is tested BEFORE tier, or a T6/T7 enchant would
--     be painted EXALTED purple.
--   * Corrupted idol: the sealed affix sits in a PURPLE box (#A872DE) -> that is
--     SealedAffixType.FromCorruption, NOT the corruption-exclusive affix pool.
--
-- TWO INDEPENDENT AXES, and conflating them is the mistake this spec exists to prevent:
--   modLine.kind             == LE SealedAffixType     (how it was sealed)
--   modLine.specialAffixType == LE SpecialAffixType    (which pool it came from)
-- `kind == "corrupted"` (#A872DE) and `specialAffixType == 6` (#E6ADFF) are different
-- facts with different colours. See REGRESSION_GUARDS.md "item-tooltip-source-colour".

describe("Item tooltip source colour #items", function()
	before_each(function() newBuild() end)

	local function colourOf(modLine, item)
		local out = itemLib.formatModLine(modLine, true, nil, item)
		assert.is_not_nil(out, "line must not be hidden")
		return out:sub(1, 8)  -- "^xRRGGBB" is 8 chars
	end

	it("a plain T1-T5 affix is WHITE (the game never colours normal affix text)", function()
		assert.are.equal(colorCodes.NORMAL,
			colourOf({ line = "15% increased Melee Attack Speed", affixType = "Prefix", tier = 4 }))
	end)

	it("a T6/T7 affix is EXALTED purple; T5 is not", function()
		assert.are.equal(colorCodes.EXALTED,
			colourOf({ line = "+16 Strength", affixType = "Prefix", tier = 6 }), "tier index 6 = T7")
		assert.are.equal(colorCodes.EXALTED,
			colourOf({ line = "+16 Strength", affixType = "Prefix", tier = 5 }), "tier index 5 = T6")
		assert.are.equal(colorCodes.NORMAL,
			colourOf({ line = "+16 Strength", affixType = "Prefix", tier = 4 }),
			"tier index 4 = T5 = max craftable, NOT exalted (get_IsExalted is affixTier+1 > 5)")
	end)

	-- The load-bearing ordering case. Same affix, same tier, different item rarity.
	it("on a LEGENDARY item a T7 affix is CRIMSON, not EXALTED purple", function()
		local legendary = { rarity = "LEGENDARY" }
		local setItem = { rarity = "SET" }
		local modLine = { line = "+16 Strength", affixType = "Prefix", tier = 6 }
		assert.are.equal(colorCodes.LEGENDARY, colourOf(modLine, legendary),
			"item.isLegendary() precedes the exalted test in LE's own branch order")
		assert.are.equal(colorCodes.EXALTED, colourOf(modLine, setItem),
			"the same T7 affix on a Set item stays purple -- this contrast is the evidence")
	end)

	it("a LEGENDARY item's unique-inherent mods stay WHITE", function()
		-- No affixType => not a rolled affix => the legendary branch must not fire.
		assert.are.equal(colorCodes.NORMAL,
			colourOf({ line = "22% increased Movement Speed", uniqueInherent = true },
				{ rarity = "LEGENDARY" }))
	end)

	-- The idol-enchant ordering case: sat 4/5 must beat the tier test.
	it("an idol enchantment is CYAN even at T7 (never EXALTED purple)", function()
		for _, sat in ipairs({ 4, 5 }) do
			assert.are.equal(colorCodes.IDOL,
				colourOf({ line = "+18 Ward gained when you use Evade",
					affixType = "Suffix", tier = 6, specialAffixType = sat }),
				("specialAffixType %d tiers up to T7; the pool test must precede `tier >= 5`"):format(sat))
		end
		assert.are.equal(colorCodes.IDOL,
			colourOf({ line = "+13 Ward Decay Threshold",
				affixType = "Suffix", tier = 3, specialAffixType = 4 }))
	end)

	it("the sealed axis and the affix-pool axis are different colours", function()
		-- kind == "corrupted" is SealedAffixType.FromCorruption -> the purple box.
		assert.are.equal(colorCodes.SEALEDCORRUPTED,
			colourOf({ line = "+10% Chance to Chill on Hit", affixType = "Suffix",
				tier = 0, kind = "corrupted" }))
		-- specialAffixType == 6 is the corruption-EXCLUSIVE pool -> a different colour.
		assert.are.equal(colorCodes.CORRUPTEDAFFIX,
			colourOf({ line = "+5% All Resistances", affixType = "Suffix",
				tier = 0, specialAffixType = 6 }))
		assert.are.equal(colorCodes.SEALED,
			colourOf({ line = "+19% Void Resistance", affixType = "Suffix",
				tier = 0, kind = "sealed" }), "a plain sealed affix is grey, not purple")
		assert.are.equal(colorCodes.PRIMORDIAL,
			colourOf({ line = "+19% Void Resistance", affixType = "Suffix",
				tier = 0, kind = "primordial" }))
	end)

	it("a Reforged Set affix is green", function()
		assert.are.equal(colorCodes.SET,
			colourOf({ line = "11% increased Melee Physical Damage",
				affixType = "Suffix", tier = 0, specialAffixType = 3 }))
	end)

	-- Red is no longer a colour; it is a suffix. This keeps the "LEB can't use this line"
	-- signal from colliding with LEGENDARY crimson (^xE80B58 vs the old ^xF05050).
	it("an unparsed line keeps its source colour and gains the unsupported suffix", function()
		local out = itemLib.formatModLine(
			{ line = "+16 Strength", affixType = "Prefix", tier = 6, extra = "some residue" },
			true, nil, nil)
		assert.is_not_nil(out)
		assert.are.equal(colorCodes.EXALTED, out:sub(1, 8),
			"the line's SOURCE colour must survive; red text would destroy that signal")
		assert.is_truthy(out:find("(NOT SUPPORTED IN LEB YET)", 1, true),
			"the unsupported state must still be visible -- as a suffix")
	end)

	it("a notSupported line is marked the same way as an unparsed one", function()
		local out = itemLib.formatModLine(
			{ line = "some recognised but unmodelled mod", affixType = "Prefix", tier = 0,
			  notSupported = true }, true, nil, nil)
		assert.is_truthy(out:find("(NOT SUPPORTED IN LEB YET)", 1, true))
	end)

	-- @leb-regression-guard:unsupported-note-own-line
	-- The note must sit on its OWN line (\n-prefixed) so Tooltip:AddLine renders it below the
	-- mod text instead of letting a long mod line width-wrap THROUGH the note.
	it("puts the unsupported note on its own line (\\n), not appended inline with spaces", function()
		local longLine = "16 Minions teleported around you after you use a Traversal Skill"
		local out = itemLib.formatModLine(
			{ line = longLine, affixType = "Prefix", tier = 0, notSupported = true }, true, nil, nil)
		assert.is_not_nil(out)
		assert.is_truthy(out:find("\n" .. colorCodes.UNSUPPORTED .. "(NOT SUPPORTED IN LEB YET)", 1, true),
			"the note must be on a new line (\\n) so a long mod does not wrap through it")
		assert.is_nil(out:find("Skill  " .. colorCodes.UNSUPPORTED, 1, true),
			"the note must NOT be appended inline with spaces after the mod text")
	end)
end)
