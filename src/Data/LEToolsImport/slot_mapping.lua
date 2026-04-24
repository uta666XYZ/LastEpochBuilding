-- LETools canRollOn slot code -> LEB base type name mapping
-- Source: src/Data/LEToolsImport/slot_mapping.json (38 confirmed codes; 11, 24 reserved)
-- Used by ItemsTabCraft.lua to filter sat=2 (Champion/Personal) affixes by equipped slot.

return {
	codeToType = {
		[0]  = "Helmet",
		[1]  = "Body Armor",
		[2]  = "Belt",
		[3]  = "Boots",
		[4]  = "Gloves",
		[5]  = "One-Handed Axe",
		[6]  = "Dagger",
		[7]  = "One-Handed Mace",
		[8]  = "Sceptre",
		[9]  = "One-Handed Sword",
		[10] = "Wand",
		[12] = "Two-Handed Axe",
		[13] = "Two-Handed Mace",
		[14] = "Two-Handed Spear",
		[15] = "Two-Handed Staff",
		[16] = "Two-Handed Sword",
		[17] = "Quiver",
		[18] = "Shield",
		[19] = "Off-Hand Catalyst",
		[20] = "Amulet",
		[21] = "Ring",
		[22] = "Relic",
		[23] = "Bow",
		[25] = "Small Idol",
		[26] = "Minor Idol",
		[27] = "Humble Idol",
		[28] = "Stout Idol",
		[29] = "Grand Idol",
		[30] = "Large Idol",
		[31] = "Ornate Idol",
		[32] = "Huge Idol",
		[33] = "Adorned Idol",
		[34] = "Blessing",
		[35] = "Greater Lens",
		[36] = "Arctus Lens",
		[37] = "Mesembria Lens",
		[38] = "Eos Lens",
		[39] = "Dysis Lens",
		[41] = "Idol Altar",
	},
	-- Some LEB bases use "Body Armour" (British spelling) in the type field;
	-- normalize by matching either.
	typeAliases = {
		["Body Armor"]  = "Body Armour",
		["Body Armour"] = "Body Armor",
	},
	-- Given a LEB base type string, return true if the given slot code list (from
	-- canRollOn) includes the slot matching this base type. Unknown codes do NOT
	-- match (strict mode).
	matchesSlot = function(self, baseTypeStr, canRollOn)
		if not baseTypeStr or not canRollOn then return false end
		local alias = self.typeAliases[baseTypeStr]
		for _, code in ipairs(canRollOn) do
			local name = self.codeToType[code]
			if name and (name == baseTypeStr or name == alias) then
				return true
			end
		end
		return false
	end,
}
