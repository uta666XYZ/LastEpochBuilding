-- @leb-regression-guard:idol-special-affix-type-is-integer
-- `specialAffixType` is LE's AffixList.SpecialAffixType enum
-- (0=Standard, 1=Experimental, 2=Personal, 3=Set, 4=IdolEnchantment, 5=IdolWeaver,
-- 6=Corrupted). ModItem_<ver>.json carries the raw integers. Data.lua builds the idol
-- pool by merging ModIdol_<ver>.json's four sections and tagging each entry by section
-- -- and it used to tag them with STRINGS ("Standard"/"IdolEnchantment"/...).
--
-- Lua does not coerce, so "Corrupted" == 6 is false. Every consumer except CalcSetup
-- compares integers, which meant `mod.specialAffixType == 6` was ALWAYS FALSE for a
-- tier-0 idol affix -- silently disabling corrupted-affix routing, the item-naming skip,
-- and the corruption-gated Line-2 extension on idols.
--
-- It was also tier-dependent: ModIdol stores only `_0` entries and `flat` chains to
-- ModItem via __index (guard idol-affix-tier-fallback), so the SAME affix family was a
-- string at tier 0 and an integer at tier 1+. That bit once for real -- CalcSetup's
-- comment records affix 897_4 skipping the +46% weaver-enchant refracted-slot boost
-- because the tier entry's numeric 4 missed the string test.
--
-- The section->integer mapping is lossless, and this spec proves it rather than trusting
-- it: every ModIdol entry must agree with ModItem's integer for its section.
-- See REGRESSION_GUARDS.md "idol-special-affix-type-is-integer".

describe("Idol specialAffixType is the raw LE enum integer #items", function()
	setup(function() newBuild() end)

	local SECTION_TO_SAT = {
		general   = 0,  -- Standard
		enchanted = 4,  -- IdolEnchantment
		corrupted = 6,  -- Corrupted
		weaver    = 5,  -- IdolWeaver
	}

	it("every idol affix carries a NUMBER, never a string", function()
		local idolFlat = data.itemMods and data.itemMods["Humble Idol"]
		assert.is_not_nil(idolFlat, "idol bases must resolve to the merged idol pool")
		local offenders = {}
		for modId, entry in pairs(idolFlat) do
			if type(entry) == "table" and entry.specialAffixType ~= nil then
				if type(entry.specialAffixType) ~= "number" then
					table.insert(offenders, string.format("%s = %q (%s)",
						tostring(modId), tostring(entry.specialAffixType),
						type(entry.specialAffixType)))
				end
			end
		end
		assert.are.equal(0, #offenders,
			"string-typed specialAffixType silently fails every `== 6` test:\n  "
			.. table.concat(offenders, "\n  "))
	end)

	it("the section tag agrees with ModItem's integer for every entry (lossless)", function()
		-- Data.lua derives an idol affix's specialAffixType from the ModIdol SECTION it
		-- sits in, because ModIdol carries no specialAffixType key of its own. That is
		-- only safe if the section partition reproduces ModItem's integers exactly.
		-- Prove it rather than trust it -- a future data regen that files an affix under
		-- the wrong section would otherwise silently mis-tag it.
		local idolRaw = readJsonFile("Data/ModIdol_1_4.json")
		local itemRaw = readJsonFile("Data/ModItem_1_4.json")
		assert.is_not_nil(idolRaw, "must read ModIdol_1_4.json")
		assert.is_not_nil(itemRaw, "must read ModItem_1_4.json")
		local offenders, checked = {}, 0
		for section, entries in pairs(idolRaw) do
			local want = SECTION_TO_SAT[section]
			if want and type(entries) == "table" then
				for modId, v in pairs(entries) do
					if type(v) == "table" then
						local it = itemRaw[modId]
						local got = it and it.specialAffixType
						checked = checked + 1
						if got ~= want then
							table.insert(offenders, string.format(
								"%s (section %s): ModItem=%s, section implies %d",
								tostring(modId), section, tostring(got), want))
						end
					end
				end
			end
		end
		assert.is_true(checked > 400, "expected the full idol pool, checked only " .. checked)
		assert.are.equal(0, #offenders,
			"the section->integer tagging is NOT lossless -- Data.lua would corrupt these:\n  "
			.. table.concat(offenders, "\n  "))
	end)

	it("a corrupted idol affix resolves to 6, so `== 6` fires", function()
		local idolFlat = data.itemMods and data.itemMods["Humble Idol"]
		-- 1070_0 = the Apiarist corruption affix (All Resistances for you and your
		-- Minions); 1063_0 = Slow chance converted to Armor Shred chance. Both live in
		-- ModIdol's `corrupted` section and are sat==6 in ModItem.
		for _, modId in ipairs({ "1070_0", "1063_0" }) do
			local entry = idolFlat[modId]
			assert.is_not_nil(entry, modId .. " must resolve in the idol pool")
			assert.are.equal(6, entry.specialAffixType,
				modId .. " is corruption-exclusive; `== 6` must fire on an idol base")
		end
	end)

	it("the tier-0 and tier-N entries of one family agree in TYPE", function()
		-- The old bug: ModIdol `892_0` was the string "IdolEnchantment" while the
		-- ModItem fallback `892_3` was the integer 4 -- same family, different type.
		local idolFlat = data.itemMods and data.itemMods["Ornate Idol"]
		local t0 = idolFlat["892_0"]
		local t3 = idolFlat["892_3"]  -- reached via flat's __index -> ModItem
		assert.is_not_nil(t0, "892_0 must resolve")
		assert.is_not_nil(t3, "892_3 must resolve through the tier fallback")
		assert.are.equal(type(t3.specialAffixType), type(t0.specialAffixType),
			"tier 0 and tier 3 of the same affix family must not differ in type")
		assert.are.equal(4, t0.specialAffixType, "892 is an idol enchantment")
		assert.are.equal(4, t3.specialAffixType)
	end)
end)
