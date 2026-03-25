-- Last Epoch Building
--
-- Module: Items Tab
-- Items tab for the current build.
--
local pairs = pairs
local ipairs = ipairs
local next = next
local t_insert = table.insert
local t_remove = table.remove
local s_format = string.format
local m_max = math.max
local m_min = math.min
local m_ceil = math.ceil
local m_floor = math.floor
local m_modf = math.modf

local rarityDropList = {
	{ label = colorCodes.NORMAL.."Normal", rarity = "NORMAL" },
	{ label = colorCodes.MAGIC.."Magic", rarity = "MAGIC" },
	{ label = colorCodes.RARE.."Rare", rarity = "RARE" },
	{ label = colorCodes.UNIQUE.."Unique", rarity = "UNIQUE" },
	{ label = colorCodes.RELIC.."Relic", rarity = "RELIC" }
}

local baseSlots = { "Weapon 1", "Weapon 2", "Helmet", "Body Armor", "Gloves", "Boots", "Amulet", "Ring 1", "Ring 2", "Belt", "Relic" }

-- Idol inventory grid layout.
-- Each row is a list of slot names (or false for invalid/blocked cells).
-- 5×5 grid with 4 corners + center blocked = 20 valid slots.
-- Import formula (posX=col-1, posY=row-1, 0-indexed from game export):
--   idolPosition = posX + posY*5
--   if posY > 0:                          -= 1   (col=4,row=0 blocked)
--   if posY>2 or (posY==2 and posX>2):   -= 1   (col=2,row=2 blocked)
--   if posY == 4:                         -= 1   (col=0,row=4 blocked)
--   Row 0 (top):    inv | 1  | 2  | 3  | inv
--   Row 1:          4   | 5  | 6  | 7  | 8
--   Row 2:          9   | 10 | inv| 11 | 12
--   Row 3:          13  | 14 | 15 | 16 | 17
--   Row 4 (bottom): inv | 18 | 19 | 20 | inv
-- All 25 cells have names. "Idol 21-25" are the 5 positions blocked in Default mode
-- but may be enabled by altar layouts (row1/5 corners + row3 center).
local IDOL_GRID_LAYOUT = {
	{ "Idol 21",  "Idol 1",  "Idol 2",  "Idol 3",  "Idol 22" }, -- row 1: corners = altar-only slots
	{ "Idol 4",   "Idol 5",  "Idol 6",  "Idol 7",  "Idol 8"  }, -- row 2: all open
	{ "Idol 9",   "Idol 10", "Idol 23", "Idol 11", "Idol 12" }, -- row 3: center = altar-only slot
	{ "Idol 13",  "Idol 14", "Idol 15", "Idol 16", "Idol 17" }, -- row 4: all open
	{ "Idol 24",  "Idol 18", "Idol 19", "Idol 20", "Idol 25" }, -- row 5: corners = altar-only slots
}

-- Reverse map: slotName -> {row, col} (1-indexed, matching IDOL_GRID_LAYOUT)
local idolSlotPos = {}
for r, rowData in ipairs(IDOL_GRID_LAYOUT) do
	for c, slotName in ipairs(rowData) do
		if slotName then idolSlotPos[slotName] = { r, c } end
	end
end

-- Idol size in grid cells: {width (cols), height (rows)}
local idolSize = {
	["Minor Idol"]  = {1, 1},
	["Small Idol"]  = {1, 1},
	["Humble Idol"] = {2, 1},
	["Stout Idol"]  = {1, 2},
	["Grand Idol"]  = {3, 1},
	["Large Idol"]  = {1, 3},
	["Ornate Idol"] = {4, 1},
	["Huge Idol"]   = {1, 4},
	["Adorned Idol"]= {2, 2},
}

table.insert(baseSlots, "Fall of the Outcasts")
table.insert(baseSlots, "The Stolen Lance")
table.insert(baseSlots, "The Black Sun")
table.insert(baseSlots, "Blood, Frost, and Death")
table.insert(baseSlots, "Ending the Storm")
table.insert(baseSlots, "Fall of the Empire")
table.insert(baseSlots, "Reign of Dragons")
table.insert(baseSlots, "The Age of Winter")
table.insert(baseSlots, "Spirits of Fire")
table.insert(baseSlots, "The Last Ruin")

-- Maximum Omen Idol slots provided by an altar
local MAX_OMEN_IDOL_SLOTS = 6

-- Horizontally flips a grid (mirrors left-right)
local function mirrorGrid(grid)
	local result = {}
	for y = 1, #grid do
		local row = {}
		local len = #grid[y]
		for x = 1, len do row[x] = grid[y][len - x + 1] end
		result[y] = row
	end
	return result
end

-- Load altar layouts from dedicated data file
local IDOL_ALTAR_LAYOUTS = LoadModule("Data/IdolAltarLayouts")
-- Resolve mirrorOf references
for _, layout in pairs(IDOL_ALTAR_LAYOUTS) do
	if layout.mirrorOf and not layout.grid then
		local src = IDOL_ALTAR_LAYOUTS[layout.mirrorOf]
		if src and src.grid then layout.grid = mirrorGrid(src.grid) end
	end
end

local influenceInfo = itemLib.influenceInfo

local ItemsTabClass = newClass("ItemsTab", "UndoHandler", "ControlHost", "Control", function(self, build)
	self.UndoHandler()
	self.ControlHost()
	self.Control()

	self.build = build

	self.socketViewer = new("PassiveTreeView")

	self.items = { }
	self.itemOrderList = { }


	-- Set selector
	self.controls.setSelect = new("DropDownControl", {"TOPLEFT",self,"TOPLEFT"}, 96, 8, 216, 20, nil, function(index, value)
		self:SetActiveItemSet(self.itemSetOrderList[index])
		self:AddUndoState()
	end)
	self.controls.setSelect.enableDroppedWidth = true
	self.controls.setSelect.enabled = function()
		return #self.itemSetOrderList > 1
	end
	self.controls.setSelect.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode == "HOVER" then
			self:AddItemSetTooltip(tooltip, self.itemSets[self.itemSetOrderList[index]])
		end
	end
	self.controls.setLabel = new("LabelControl", {"RIGHT",self.controls.setSelect,"LEFT"}, -2, 0, 0, 16, "^7Item set:")
	self.controls.setManage = new("ButtonControl", {"LEFT",self.controls.setSelect,"RIGHT"}, 4, 0, 90, 20, "Manage...", function()
		self:OpenItemSetManagePopup()
	end)

	-- Item slots
	self.slots = { }
	self.orderedSlots = { }
	self.slotOrder = { }
	self.slotAnchor = new("Control", {"TOPLEFT",self,"TOPLEFT"}, 96, 76, 310, 0)
	local prevSlot = self.slotAnchor
	local function addSlot(slot)
		prevSlot = slot
		self.slots[slot.slotName] = slot
		t_insert(self.orderedSlots, slot)
		self.slotOrder[slot.slotName] = #self.orderedSlots
		t_insert(self.controls, slot)
	end
	local blessingSlotNames = {
		["Fall of the Outcasts"]=true, ["The Stolen Lance"]=true, ["The Black Sun"]=true, ["Blood, Frost, and Death"]=true, ["Ending the Storm"]=true, ["Fall of the Empire"]=true, ["Reign of Dragons"]=true, ["The Age of Winter"]=true, ["Spirits of Fire"]=true, ["The Last Ruin"]=true
	}
	local lastVisibleSlot = self.slotAnchor
	for index, slotName in ipairs(baseSlots) do
		local slot = new("ItemSlotControl", {"TOPLEFT",prevSlot,"BOTTOMLEFT"}, 0, 2, self, slotName)
		addSlot(slot)
		if blessingSlotNames[slotName] then
			slot.shown = function() return false end
		else
			lastVisibleSlot = slot
		end
		if slotName:match("Weapon") then
			-- Add alternate weapon slot
			slot.weaponSet = 1
			slot.shown = function()
				return not self.activeItemSet.useSecondWeaponSet
			end
			local swapSlot = new("ItemSlotControl", {"TOPLEFT",prevSlot,"BOTTOMLEFT"}, 0, 2, self, slotName.." Swap", slotName)
			addSlot(swapSlot)
			swapSlot.weaponSet = 2
			swapSlot.shown = function()
				return self.activeItemSet.useSecondWeaponSet
			end
			for i = 1, 6 do
				local abyssal = new("ItemSlotControl", {"TOPLEFT",prevSlot,"BOTTOMLEFT"}, 0, 2, self, slotName.." Swap Abyssal Socket "..i, "Abyssal #"..i)
				addSlot(abyssal)
				abyssal.parentSlot = swapSlot
				abyssal.weaponSet = 2
				abyssal.shown = function()
					return not abyssal.inactive and self.activeItemSet.useSecondWeaponSet
				end
				swapSlot.abyssalSocketList[i] = abyssal
			end
		end
	end

	-- Expose the layout so IdolsTab can reference it without duplicating the table
	self.idolGridLayout = IDOL_GRID_LAYOUT
	self.altarLayouts = IDOL_ALTAR_LAYOUTS

	-- Passive tree dropdown controls
	self.controls.specSelect = new("DropDownControl", {"TOPLEFT",lastVisibleSlot,"BOTTOMLEFT"}, 0, 8, 216, 20, nil, function(index, value)
		if self.build.treeTab.specList[index] then
			self.build.modFlag = true
			self.build.treeTab:SetActiveSpec(index)
		end
	end)
	self.controls.specSelect.enabled = function()
		return #self.controls.specSelect.list > 1
	end
	prevSlot = self.controls.specSelect
	self.controls.specButton = new("ButtonControl", {"LEFT",prevSlot,"RIGHT"}, 4, 0, 90, 20, "Manage...", function()
		self.build.treeTab:OpenSpecManagePopup()
	end)
	self.controls.specLabel = new("LabelControl", {"RIGHT",prevSlot,"LEFT"}, -2, 0, 0, 16, "^7Passive tree:")
	self.controls.idolPositionsLabel = new("LabelControl", {"TOPLEFT",self.controls.specLabel,"BOTTOMLEFT"}, 0, 16, 0, 16, "Idol positions start from bottom left then left to right")

	-- ===== IDOL ALTAR (S4) =====
	self.activeAltarLayout = "Default"
	local altarDropList = { { label = "Default", key = "Default" } }
	do
		local altarNames = {}
		for name in pairs(IDOL_ALTAR_LAYOUTS) do t_insert(altarNames, name) end
		table.sort(altarNames)
		for _, name in ipairs(altarNames) do
			local layout = IDOL_ALTAR_LAYOUTS[name]
			t_insert(altarDropList, {
				label = (layout.mirrorOf or name) .. (layout.isMirrored and " [Mirrored]" or ""),
				key   = name,
			})
		end
	end
	self.controls.idolAltarSelect = new("DropDownControl",
		{"TOPLEFT",self.controls.idolPositionsLabel,"BOTTOMLEFT"}, 0, 8, 216, 20,
		altarDropList, function(index, value)
			self.activeAltarLayout = altarDropList[index].key
			self.build.buildFlag = true
		end)
	self.controls.idolAltarLabel = new("LabelControl",
		{"RIGHT",self.controls.idolAltarSelect,"LEFT"}, -2, 0, 0, 16, "^7Idol Altar:")
	local prevOmenSlot = self.controls.idolAltarSelect
	for i = 1, MAX_OMEN_IDOL_SLOTS do
		local omenSlot = new("ItemSlotControl", {"TOPLEFT",prevOmenSlot,"BOTTOMLEFT"}, 0, 2, self, "Omen Idol " .. i)
		local slotNum = i
		omenSlot.shown = function()
			if self.activeAltarLayout == "Default" then return false end
			local layout = IDOL_ALTAR_LAYOUTS[self.activeAltarLayout]
			return layout ~= nil and slotNum <= layout.baseCapacity
		end
		self.slots[omenSlot.slotName] = omenSlot
		t_insert(self.orderedSlots, omenSlot)
		self.slotOrder[omenSlot.slotName] = #self.orderedSlots
		t_insert(self.controls, omenSlot)
		prevOmenSlot = omenSlot
	end
	self.controls.idolAltarEnd = new("Control", {"TOPLEFT",prevOmenSlot,"BOTTOMLEFT",true}, 0, 4, 0, 0)

	-- ===== BLESSING PANEL =====
	local blessingData = {
		["Fall of the Outcasts"] = {
			normal = {
				{name="Curse of Flesh", minVal=30.0, maxVal=50.0, implCount=1, impl1="(30-50)% Increased Huge Idol Drop Rate", label="(30-50)% Inc. Huge Idol Drop%"},
				{name="Favor of Souls", minVal=30.0, maxVal=50.0, implCount=1, impl1="(30-50)% Increased Ornate Idol Drop Rate", label="(30-50)% Inc. Ornate Idol Drop%"},
				{name="Mark of Agony", minVal=30.0, maxVal=50.0, implCount=1, impl1="(30-50)% Increased Adorned Idol Drop Rate", label="(30-50)% Inc. Adorned Idol Drop%"},
				{name="Memory of the Living", minVal=10.0, maxVal=15.0, implCount=1, impl1="(10-15)% Increased Glyph Drop Rate", label="(10-15)% Inc. Glyph Drop%"},
				{name="Pride of Rebellion", minVal=30.0, maxVal=50.0, implCount=1, impl1="(30-50)% Increased Grand Idol Drop Rate", label="(30-50)% Inc. Grand Idol Drop%"},
				{name="Scales of Greed", minVal=25.0, maxVal=40.0, implCount=1, impl1="(25-40)% Increased Gold Drop Rate", label="(25-40)% Inc. Gold Drop%"},
				{name="Sight of the Outcasts", minVal=30.0, maxVal=50.0, implCount=1, impl1="(30-50)% Increased Large Idol Drop Rate", label="(30-50)% Inc. Large Idol Drop%"},
				{name="Sign of Torment", minVal=10.0, maxVal=15.0, implCount=1, impl1="(10-15)% Increased Rune Drop Rate", label="(10-15)% Inc. Rune Drop%"},
				{name="Strength of Mind", minVal=4.0, maxVal=6.0, implCount=1, impl1="(4-6)% Increased Experience", label="(4-6)% Inc. Experience"},
				{name="Winds of Fortune", minVal=10.0, maxVal=15.0, implCount=1, impl1="(10-15)% Increased Unique Drop Rate", label="(10-15)% Inc. Unique Drop%"},
			},
			grand = {
				{name="Grand Curse of Flesh", minVal=51.0, maxVal=100.0, implCount=1, impl1="(51-100)% Increased Huge Idol Drop Rate", label="(51-100)% Inc. Huge Idol Drop%"},
				{name="Grand Favor of Souls", minVal=51.0, maxVal=100.0, implCount=1, impl1="(51-100)% Increased Ornate Idol Drop Rate", label="(51-100)% Inc. Ornate Idol Drop%"},
				{name="Grand Mark of Agony", minVal=51.0, maxVal=100.0, implCount=1, impl1="(51-100)% Increased Adorned Idol Drop Rate", label="(51-100)% Inc. Adorned Idol Drop%"},
				{name="Grand Memory of the Living", minVal=16.0, maxVal=25.0, implCount=1, impl1="(16-25)% Increased Glyph Drop Rate", label="(16-25)% Inc. Glyph Drop%"},
				{name="Grand Pride of Rebellion", minVal=51.0, maxVal=100.0, implCount=1, impl1="(51-100)% Increased Grand Idol Drop Rate", label="(51-100)% Inc. Grand Idol Drop%"},
				{name="Grand Scales of Greed", minVal=45.0, maxVal=70.0, implCount=1, impl1="(45-70)% Increased Gold Drop Rate", label="(45-70)% Inc. Gold Drop%"},
				{name="Grand Sight of the Outcasts", minVal=51.0, maxVal=100.0, implCount=1, impl1="(51-100)% Increased Large Idol Drop Rate", label="(51-100)% Inc. Large Idol Drop%"},
				{name="Grand Sign of Torment", minVal=16.0, maxVal=25.0, implCount=1, impl1="(16-25)% Increased Rune Drop Rate", label="(16-25)% Inc. Rune Drop%"},
				{name="Grand Strength of Mind", minVal=7.0, maxVal=10.0, implCount=1, impl1="(7-10)% Increased Experience", label="(7-10)% Inc. Experience"},
				{name="Grand Winds of Fortune", minVal=16.0, maxVal=22.0, implCount=1, impl1="(16-22)% Increased Unique Drop Rate", label="(16-22)% Inc. Unique Drop%"},
			},
		},
		["The Stolen Lance"] = {
			normal = {
				{name="Ambition of the Empire", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Two-Handed Sword Drop Rate", label="(30-45)% Inc. 2H Sword Drop%"},
				{name="Chill of Death", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Two-Handed Staff Drop Rate", label="(30-45)% Inc. 2H Staff Drop%"},
				{name="Cruelty of Formosus", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Wand Drop Rate", label="(30-45)% Inc. Wand Drop%"},
				{name="Enmity of the Clans", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased One-Handed Sword Drop Rate", label="(30-45)% Inc. One-Handed Sword Drop%"},
				{name="Favor of the Wengari", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Two-Handed Axe Drop Rate", label="(30-45)% Inc. 2H Axe Drop%"},
				{name="Remorse of Heorot", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Two-Handed Spear Drop Rate", label="(30-45)% Inc. 2H Spear Drop%"},
				{name="Resolve of Frost", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased One-Handed Mace Drop Rate", label="(30-45)% Inc. One-Handed Mace Drop%"},
				{name="Savior of the North", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Sceptre Drop Rate", label="(30-45)% Inc. Sceptre Drop%"},
				{name="Scars of Blood", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased One-Handed Axe Drop Rate", label="(30-45)% Inc. One-Handed Axe Drop%"},
				{name="Shards of Unity", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Two-Handed Mace Drop Rate", label="(30-45)% Inc. 2H Mace Drop%"},
			},
			grand = {
				{name="Grand Ambition of the Empire", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased Two-Handed Sword Drop Rate", label="(50-90)% Inc. 2H Sword Drop%"},
				{name="Grand Chill of Death", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased Two-Handed Staff Drop Rate", label="(50-90)% Inc. 2H Staff Drop%"},
				{name="Grand Cruelty of Formosus", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased Wand Drop Rate", label="(50-90)% Inc. Wand Drop%"},
				{name="Grand Enmity of the Clans", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased One-Handed Sword Drop Rate", label="(50-90)% Inc. One-Handed Sword Drop%"},
				{name="Grand Favor of the Wengari", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased Two-Handed Axe Drop Rate", label="(50-90)% Inc. 2H Axe Drop%"},
				{name="Grand Remorse of Heorot", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased Two-Handed Spear Drop Rate", label="(50-90)% Inc. 2H Spear Drop%"},
				{name="Grand Resolve of Frost", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased One-Handed Mace Drop Rate", label="(50-90)% Inc. One-Handed Mace Drop%"},
				{name="Grand Savior of the North", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased Sceptre Drop Rate", label="(50-90)% Inc. Sceptre Drop%"},
				{name="Grand Scars of Blood", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased One-Handed Axe Drop Rate", label="(50-90)% Inc. One-Handed Axe Drop%"},
				{name="Grand Shards of Unity", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased Two-Handed Mace Drop Rate", label="(50-90)% Inc. 2H Mace Drop%"},
			},
		},
		["The Black Sun"] = {
			normal = {
				{name="Depths of Infinity", minVal=10.0, maxVal=20.0, implCount=1, impl1="+(10-20)% Chance to Shred Void Resistance on Hit", label="+(10-20)% Shred Void Res on Hit"},
				{name="Echo of Solarum", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Void Resistance", label="+(25-40)% Void Res"},
				{name="Flames of the Black Sun", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to Ignite on Hit", label="+(40-60)% Chance to Ignite on Hit"},
				{name="Hunger of the Void", minVal=1.2, maxVal=2.0, implCount=1, impl1="(1.2-2)% of Spell Damage Leeched as Health", label="(1.2-2)% of Spell Dmg Leeched as Health"},
				{name="Memory of Light", minVal=30.0, maxVal=42.0, implCount=1, impl1="+(30-42) Health", label="+(30-42) Health"},
				{name="Shadow of the Eclipse", minVal=60.0, maxVal=100.0, implCount=1, impl1="+(60-100) Dodge Rating", label="+(60-100) Dodge Rating"},
				{name="Strength of the Mountain", minVal=10.0, maxVal=14.0, implCount=1, impl1="(10-14) Health Gain on Block", label="(10-14) Health Gain on Block"},
				{name="Whisper of Orobyss", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Void Damage", label="(40-60)% inc. Void Dmg"},
				{name="Winds of Oblivion", minVal=30.0, maxVal=50.0, implCount=1, impl1="(30-50)% increased Critical Strike Chance", label="(30-50)% inc. Critical Strike Chance"},
				{name="Wrath of Rahyeh", minVal=1.2, maxVal=2.0, implCount=1, impl1="(1.2-2)% of Throwing Damage Leeched as Health", label="(1.2-2)% of Throwing Dmg Leeched as Health"},
			},
			grand = {
				{name="Grand Depths of Infinity", minVal=25.0, maxVal=50.0, implCount=1, impl1="+(25-50)% Chance to Shred Void Resistance on Hit", label="+(25-50)% Shred Void Res on Hit"},
				{name="Grand Echo of Solarum", minVal=55.0, maxVal=75.0, implCount=1, impl1="+(55-75)% Void Resistance", label="+(55-75)% Void Res"},
				{name="Grand Flames of the Black Sun", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to Ignite on Hit", label="+(65-100)% Chance to Ignite on Hit"},
				{name="Grand Hunger of the Void", minVal=2.2, maxVal=3.5, implCount=1, impl1="(2.2-3.5)% of Spell Damage Leeched as Health", label="(2.2-3.5)% of Spell Dmg Leeched as Health"},
				{name="Grand Memory of Light", minVal=45.0, maxVal=70.0, implCount=1, impl1="+(45-70) Health", label="+(45-70) Health"},
				{name="Grand Shadow of the Eclipse", minVal=101.0, maxVal=200.0, implCount=1, impl1="+(101-200) Dodge Rating", label="+(101-200) Dodge Rating"},
				{name="Grand Strength of the Mountain", minVal=15.0, maxVal=22.0, implCount=1, impl1="(15-22) Health Gain on Block", label="(15-22) Health Gain on Block"},
				{name="Grand Whisper of Orobyss", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Void Damage", label="(65-100)% inc. Void Dmg"},
				{name="Grand Winds of Oblivion", minVal=51.0, maxVal=80.0, implCount=1, impl1="(51-80)% increased Critical Strike Chance", label="(51-80)% inc. Critical Strike Chance"},
				{name="Grand Wrath of Rahyeh", minVal=2.2, maxVal=3.5, implCount=1, impl1="(2.2-3.5)% of Throwing Damage Leeched as Health", label="(2.2-3.5)% of Throwing Dmg Leeched as Health"},
			},
		},
		["Blood, Frost, and Death"] = {
			normal = {
				{name="Boon of the Scarab", minVal=25.0, maxVal=35.0, implCount=1, impl1="(25-35)% Increased Bow Shard Drop Rate", label="(25-35)% Inc. Bow Shard Drop%"},
				{name="Emptiness of Ash", minVal=20.0, maxVal=26.0, implCount=1, impl1="+(20-26)% Critical Strike Multiplier", label="+(20-26)% Critical Strike Multiplier"},
				{name="Greed of Darkness", minVal=6.0, maxVal=10.0, implCount=2, impl1="(6-10) Ward Gain on Kill", label="(6-10) Ward Gain on Kill", impl2="+(60-100) Ward Decay Threshold"},
				{name="Hope of the Beginning", minVal=7.0, maxVal=14.0, implCount=1, impl1="(7-14)% Increased Prefix Shard Drop Rate", label="(7-14)% Inc. Prefix Shard Drop%"},
				{name="Inevitability of the Void", minVal=16.0, maxVal=26.0, implCount=1, impl1="(16-26)% Increased Two-Handed Staff Shard Drop Rate", label="(16-26)% Inc. 2H Staff Shard Drop%"},
				{name="Remnants of the Living", minVal=20.0, maxVal=30.0, implCount=1, impl1="(20-30)% Increased Ring Shard Drop Rate", label="(20-30)% Inc. Ring Shard Drop%"},
				{name="Rot of the World", minVal=25.0, maxVal=35.0, implCount=1, impl1="(25-35)% Increased Wand Shard Drop Rate", label="(25-35)% Inc. Wand Shard Drop%"},
				{name="Safety of the Labyrinth", minVal=10.0, maxVal=20.0, implCount=1, impl1="(10-20)% Increased Amulet Shard Drop Rate", label="(10-20)% Inc. Amulet Shard Drop%"},
				{name="Thirst of the Sun", minVal=20.0, maxVal=30.0, implCount=1, impl1="(20-30)% Increased Leech Rate", label="(20-30)% Inc. Leech Rate"},
				{name="Visions of Death", minVal=25.0, maxVal=35.0, implCount=1, impl1="(25-35)% Increased Two-Handed Spear Shard Drop Rate", label="(25-35)% Inc. 2H Spear Shard Drop%"},
			},
			grand = {
				{name="Grand Boon of the Scarab", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% Increased Bow Shard Drop Rate", label="(40-60)% Inc. Bow Shard Drop%"},
				{name="Grand Emptiness of Ash", minVal=27.0, maxVal=40.0, implCount=1, impl1="+(27-40)% Critical Strike Multiplier", label="+(27-40)% Critical Strike Multiplier"},
				{name="Grand Greed of Darkness", minVal=12.0, maxVal=18.0, implCount=2, impl1="(12-18) Ward Gain on Kill", label="(12-18) Ward Gain on Kill", impl2="+(120-200) Ward Decay Threshold"},
				{name="Grand Hope of the Beginning", minVal=15.0, maxVal=25.0, implCount=1, impl1="(15-25)% Increased Prefix Shard Drop Rate", label="(15-25)% Inc. Prefix Shard Drop%"},
				{name="Grand Inevitability of the Void", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Two-Handed Staff Shard Drop Rate", label="(30-45)% Inc. 2H Staff Shard Drop%"},
				{name="Grand Remnants of the Living", minVal=33.0, maxVal=50.0, implCount=1, impl1="(33-50)% Increased Ring Shard Drop Rate", label="(33-50)% Inc. Ring Shard Drop%"},
				{name="Grand Rot of the World", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% Increased Wand Shard Drop Rate", label="(40-60)% Inc. Wand Shard Drop%"},
				{name="Grand Safety of the Labyrinth", minVal=22.0, maxVal=35.0, implCount=1, impl1="(22-35)% Increased Amulet Shard Drop Rate", label="(22-35)% Inc. Amulet Shard Drop%"},
				{name="Grand Thirst of the Sun", minVal=35.0, maxVal=50.0, implCount=1, impl1="(35-50)% Increased Leech Rate", label="(35-50)% Inc. Leech Rate"},
				{name="Grand Visions of Death", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% Increased Two-Handed Spear Shard Drop Rate", label="(40-60)% Inc. 2H Spear Shard Drop%"},
			},
		},
		["Ending the Storm"] = {
			normal = {
				{name="Apex of Fortune", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Quiver Drop Rate", label="(15-30)% Inc. Quiver Drop%"},
				{name="Arrogance of Argentus", minVal=10.0, maxVal=20.0, implCount=1, impl1="(10-20)% Increased Helmet Drop Rate", label="(10-20)% Inc. Helmet Drop%"},
				{name="Despair of the Empire", minVal=25.0, maxVal=40.0, implCount=1, impl1="(25-40)% Increased Ailment Shard Drop Rate", label="(25-40)% Inc. Ailment Shard Drop%"},
				{name="Embrace of Ice", minVal=10.0, maxVal=20.0, implCount=1, impl1="(10-20)% Increased Body Armor Drop Rate", label="(10-20)% Inc. Body Armor Drop%"},
				{name="Grip of the Lance", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Gloves Drop Rate", label="(15-30)% Inc. Gloves Drop%"},
				{name="Reach of Flame", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Off-Hand Catalyst Drop Rate", label="(15-30)% Inc. Off-Hand Catalyst Drop%"},
				{name="Right of Conquest", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Boots Drop Rate", label="(15-30)% Inc. Boots Drop%"},
				{name="Shadows of Infinity", minVal=10.0, maxVal=20.0, implCount=1, impl1="(10-20)% Increased Relic Shard Drop Rate", label="(10-20)% Inc. Relic Shard Drop%"},
				{name="Subtlety of Slaughter", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Dagger Drop Rate", label="(30-45)% Inc. Dagger Drop%"},
				{name="Vigilance of the Damned", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Bow Drop Rate", label="(30-45)% Inc. Bow Drop%"},
			},
			grand = {
				{name="Grand Apex of Fortune", minVal=41.0, maxVal=60.0, implCount=1, impl1="(41-60)% Increased Quiver Drop Rate", label="(41-60)% Inc. Quiver Drop%"},
				{name="Grand Arrogance of Argentus", minVal=22.0, maxVal=50.0, implCount=1, impl1="(22-50)% Increased Helmet Drop Rate", label="(22-50)% Inc. Helmet Drop%"},
				{name="Grand Despair of the Empire", minVal=45.0, maxVal=70.0, implCount=1, impl1="(45-70)% Increased Ailment Shard Drop Rate", label="(45-70)% Inc. Ailment Shard Drop%"},
				{name="Grand Embrace of Ice", minVal=22.0, maxVal=50.0, implCount=1, impl1="(22-50)% Increased Body Armor Drop Rate", label="(22-50)% Inc. Body Armor Drop%"},
				{name="Grand Grip of the Lance", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Gloves Drop Rate", label="(35-75)% Inc. Gloves Drop%"},
				{name="Grand Reach of Flame", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Off-Hand Catalyst Drop Rate", label="(35-75)% Inc. Off-Hand Catalyst Drop%"},
				{name="Grand Right of Conquest", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Boots Drop Rate", label="(35-75)% Inc. Boots Drop%"},
				{name="Grand Shadows of Infinity", minVal=22.0, maxVal=35.0, implCount=1, impl1="(22-35)% Increased Relic Shard Drop Rate", label="(22-35)% Inc. Relic Shard Drop%"},
				{name="Grand Subtlety of Slaughter", minVal=50.0, maxVal=75.0, implCount=1, impl1="(50-75)% Increased Dagger Drop Rate", label="(50-75)% Inc. Dagger Drop%"},
				{name="Grand Vigilance of the Damned", minVal=50.0, maxVal=75.0, implCount=1, impl1="(50-75)% Increased Bow Drop Rate", label="(50-75)% Inc. Bow Drop%"},
			},
		},
		["Fall of the Empire"] = {
			normal = {
				{name="Bastion of Divinity", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Lightning Resistance", label="+(25-40)% Lightning Res"},
				{name="Binds of Sanctuary", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Shield Drop Rate", label="(15-30)% Inc. Shield Drop%"},
				{name="Chaos of Lagon", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Lightning Damage", label="(40-60)% inc. Lightning Dmg"},
				{name="Intellect of Liath", minVal=15.0, maxVal=25.0, implCount=1, impl1="(15-25)% Chance to Gain 30 Ward when Hit", label="(15-25)% Chance to Gain 30 Ward when Hit"},
				{name="Light of the Moon", minVal=30.0, maxVal=50.0, implCount=1, impl1="+(30-50) Mana", label="+(30-50) Mana"},
				{name="Might of the Siege", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Belt Drop Rate", label="(15-30)% Inc. Belt Drop%"},
				{name="Rhythm of the Tide", minVal=60.0, maxVal=100.0, implCount=2, impl1="(60-100)% increased Health Regen", label="(60-100)% inc. Health Regen", impl2="+(6-10) Health Regen"},
				{name="Slumber of Morditas", minVal=12.0, maxVal=25.0, implCount=1, impl1="(12-25)% Increased Relic Drop Rate", label="(12-25)% Inc. Relic Drop%"},
				{name="Talon of Grandeur", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Ring Drop Rate", label="(15-30)% Inc. Ring Drop%"},
				{name="Vision of the Aurora", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Amulet Drop Rate", label="(15-30)% Inc. Amulet Drop%"},
			},
			grand = {
				{name="Grand Bastion of Divinity", minVal=55.0, maxVal=75.0, implCount=1, impl1="+(55-75)% Lightning Resistance", label="+(55-75)% Lightning Res"},
				{name="Grand Binds of Sanctuary", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Shield Drop Rate", label="(35-75)% Inc. Shield Drop%"},
				{name="Grand Chaos of Lagon", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Lightning Damage", label="(65-100)% inc. Lightning Dmg"},
				{name="Grand Intellect of Liath", minVal=30.0, maxVal=50.0, implCount=1, impl1="(30-50)% Chance to Gain 30 Ward when Hit", label="(30-50)% Chance to Gain 30 Ward when Hit"},
				{name="Grand Light of the Moon", minVal=60.0, maxVal=90.0, implCount=1, impl1="+(60-90) Mana", label="+(60-90) Mana"},
				{name="Grand Might of the Siege", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Belt Drop Rate", label="(35-75)% Inc. Belt Drop%"},
				{name="Grand Rhythm of the Tide", minVal=120.0, maxVal=200.0, implCount=2, impl1="(120-200)% increased Health Regen", label="(120-200)% inc. Health Regen", impl2="+(12-20) Health Regen"},
				{name="Grand Slumber of Morditas", minVal=30.0, maxVal=60.0, implCount=1, impl1="(30-60)% Increased Relic Drop Rate", label="(30-60)% Inc. Relic Drop%"},
				{name="Grand Talon of Grandeur", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Ring Drop Rate", label="(35-75)% Inc. Ring Drop%"},
				{name="Grand Vision of the Aurora", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Amulet Drop Rate", label="(35-75)% Inc. Amulet Drop%"},
			},
		},
		["Reign of Dragons"] = {
			normal = {
				{name="Crash of the Waves", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased Stun Chance", label="(50-90)% Inc. Stun Chance"},
				{name="Cruelty of the Meruna", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to Shock on Hit", label="+(40-60)% Chance to Shock on Hit"},
				{name="Grace of Water", minVal=40.0, maxVal=70.0, implCount=2, impl1="(40-70) Ward Gained on Potion Use", label="(40-70) Ward Gained on Potion Use", impl2="+(80-140) Ward Decay Threshold"},
				{name="Might of the Sea Titan", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Cold Damage", label="(40-60)% inc. Cold Dmg"},
				{name="Mysteries of the Deep", minVal=10.0, maxVal=20.0, implCount=1, impl1="+(10-20)% Chance to Shred Lightning Resistance on Hit", label="+(10-20)% Shred Lightning Res on Hit"},
				{name="Resolve of Humanity", minVal=7.0, maxVal=12.0, implCount=1, impl1="+(7-12)% to All Resistances", label="+(7-12)% to All Ress"},
				{name="Resonance of the Sea", minVal=17.0, maxVal=25.0, implCount=1, impl1="+(17-25) Ward per Second", label="+(17-25) Ward per Second"},
				{name="Survival of Might", minVal=30.0, maxVal=45.0, implCount=2, impl1="+(30-45)% Critical Strike Avoidance", label="+(30-45)% Critical Strike Avoidance", impl2="+(30-50) Dodge Rating"},
				{name="Trance of the Sirens", minVal=10.0, maxVal=14.0, implCount=1, impl1="(10-14)% Increased Shock Duration", label="(10-14)% Inc. Shock Duration"},
				{name="Weight of the Abyss", minVal=100.0, maxVal=180.0, implCount=1, impl1="+(100-180)% Freeze Rate Multiplier", label="+(100-180)% Freeze Rate Multiplier"},
			},
			grand = {
				{name="Grand Crash of the Waves", minVal=100.0, maxVal=160.0, implCount=1, impl1="(100-160)% Increased Stun Chance", label="(100-160)% Inc. Stun Chance"},
				{name="Grand Cruelty of the Meruna", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to Shock on Hit", label="+(65-100)% Chance to Shock on Hit"},
				{name="Grand Grace of Water", minVal=80.0, maxVal=130.0, implCount=2, impl1="(80-130) Ward Gained on Potion Use", label="(80-130) Ward Gained on Potion Use", impl2="+(160-260) Ward Decay Threshold"},
				{name="Grand Might of the Sea Titan", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Cold Damage", label="(65-100)% inc. Cold Dmg"},
				{name="Grand Mysteries of the Deep", minVal=25.0, maxVal=50.0, implCount=1, impl1="+(25-50)% Chance to Shred Lightning Resistance on Hit", label="+(25-50)% Shred Lightning Res on Hit"},
				{name="Grand Resolve of Humanity", minVal=13.0, maxVal=20.0, implCount=1, impl1="+(13-20)% to All Resistances", label="+(13-20)% to All Ress"},
				{name="Grand Resonance of the Sea", minVal=30.0, maxVal=42.0, implCount=1, impl1="+(30-42) Ward per Second", label="+(30-42) Ward per Second"},
				{name="Grand Survival of Might", minVal=50.0, maxVal=70.0, implCount=2, impl1="+(50-70)% Critical Strike Avoidance", label="+(50-70)% Critical Strike Avoidance", impl2="+(51-90) Dodge Rating"},
				{name="Grand Trance of the Sirens", minVal=15.0, maxVal=22.0, implCount=1, impl1="(15-22)% Increased Shock Duration", label="(15-22)% Inc. Shock Duration"},
				{name="Grand Weight of the Abyss", minVal=200.0, maxVal=300.0, implCount=1, impl1="+(200-300)% Freeze Rate Multiplier", label="+(200-300)% Freeze Rate Multiplier"},
			},
		},
		["The Age of Winter"] = {
			normal = {
				{name="Binds of Nature", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Poison Damage", label="(40-60)% inc. Poison Dmg"},
				{name="Cruelty of Strength", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Physical Damage", label="(40-60)% inc. Physical Dmg"},
				{name="Despair of Flesh", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Necrotic Damage", label="(40-60)% inc. Necrotic Dmg"},
				{name="Dream of Eterra", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Necrotic Resistance", label="+(25-40)% Necrotic Res"},
				{name="Guile of Wyrms", minVal=60.0, maxVal=90.0, implCount=1, impl1="+(60-90)% Chance to Shred Poison Resistance on Hit", label="+(60-90)% Shred Poison Res on Hit"},
				{name="Hemmorage of Marrow", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to inflict Bleed on Hit", label="+(40-60)% Chance to inflict Bleed on Hit"},
				{name="Hunger of Dragons", minVal=2.0, maxVal=4.0, implCount=1, impl1="(2-4)% of Melee Damage Leeched as Health", label="(2-4)% of Melee Dmg Leeched as Health"},
				{name="Persistance of Will", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Poison Resistance", label="+(25-40)% Poison Res"},
				{name="Taste of Venom", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to Poison on Hit", label="+(40-60)% Chance to Poison on Hit"},
				{name="Virtue of Command", minVal=8.0, maxVal=15.0, implCount=1, impl1="+(8-15)% to Minion All Resistances", label="+(8-15)% to Minion All Ress"},
			},
			grand = {
				{name="Grand Binds of Nature", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Poison Damage", label="(65-100)% inc. Poison Dmg"},
				{name="Grand Cruelty of Strength", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Physical Damage", label="(65-100)% inc. Physical Dmg"},
				{name="Grand Despair of Flesh", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Necrotic Damage", label="(65-100)% inc. Necrotic Dmg"},
				{name="Grand Dream of Eterra", minVal=45.0, maxVal=75.0, implCount=1, impl1="+(45-75)% Necrotic Resistance", label="+(45-75)% Necrotic Res"},
				{name="Grand Guile of Wyrms", minVal=100.0, maxVal=150.0, implCount=1, impl1="+(100-150)% Chance to Shred Poison Resistance on Hit", label="+(100-150)% Shred Poison Res on Hit"},
				{name="Grand Hemmorage of Marrow", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to inflict Bleed on Hit", label="+(65-100)% Chance to inflict Bleed on Hit"},
				{name="Grand Hunger of Dragons", minVal=4.5, maxVal=7.0, implCount=1, impl1="(4.5-7)% of Melee Damage Leeched as Health", label="(4.5-7)% of Melee Dmg Leeched as Health"},
				{name="Grand Persistance of Will", minVal=55.0, maxVal=75.0, implCount=1, impl1="+(55-75)% Poison Resistance", label="+(55-75)% Poison Res"},
				{name="Grand Taste of Venom", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to Poison on Hit", label="+(65-100)% Chance to Poison on Hit"},
				{name="Grand Virtue of Command", minVal=16.0, maxVal=25.0, implCount=1, impl1="+(16-25)% to Minion All Resistances", label="+(16-25)% to Minion All Ress"},
			},
		},
		["Spirits of Fire"] = {
			normal = {
				{name="Allure of Apathy", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to Slow on Hit", label="+(40-60)% Chance to Slow on Hit"},
				{name="Bones of Eternity", minVal=3.0, maxVal=4.0, implCount=2, impl1="+(3-4)% Block Chance", label="+(3-4)% Block Chance", impl2="+(100-140) Block Effectiveness"},
				{name="Fury of the North", minVal=10.0, maxVal=20.0, implCount=1, impl1="+(10-20)% Chance to Shred Physical Resistance on Hit", label="+(10-20)% Shred Physical Res on Hit"},
				{name="Heart of Ice", minVal=20.0, maxVal=35.0, implCount=1, impl1="+(20-35)% Chance to Chill on Hit", label="+(20-35)% Chance to Chill on Hit"},
				{name="Maw of Artor", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to apply Frostbite on Hit", label="+(40-60)% Chance to apply Frostbite on Hit"},
				{name="Protection of Heorot", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Cold Resistance", label="+(25-40)% Cold Res"},
				{name="Rage of Winter", minVal=10.0, maxVal=20.0, implCount=1, impl1="+(10-20)% Chance to Shred Cold Resistance on Hit", label="+(10-20)% Shred Cold Res on Hit"},
				{name="Resolve of Grael", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Physical Resistance", label="+(25-40)% Physical Res"},
				{name="Vigor of Jormun", minVal=40.0, maxVal=70.0, implCount=1, impl1="+(40-70) Endurance Threshold", label="+(40-70) Endurance Threshold"},
				{name="Winds of Frost", minVal=30.0, maxVal=50.0, implCount=1, impl1="+(30-50)% Freeze Rate per stack of Chill", label="+(30-50)% Freeze Rate per stack of Chill"},
			},
			grand = {
				{name="Grand Allure of Apathy", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to Slow on Hit", label="+(65-100)% Chance to Slow on Hit"},
				{name="Grand Bones of Eternity", minVal=5.0, maxVal=8.0, implCount=2, impl1="+(5-8)% Block Chance", label="+(5-8)% Block Chance", impl2="+(180-240) Block Effectiveness"},
				{name="Grand Fury of the North", minVal=25.0, maxVal=50.0, implCount=1, impl1="+(25-50)% Chance to Shred Physical Resistance on Hit", label="+(25-50)% Shred Physical Res on Hit"},
				{name="Grand Heart of Ice", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to Chill on Hit", label="+(40-60)% Chance to Chill on Hit"},
				{name="Grand Maw of Artor", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to apply Frostbite on Hit", label="+(65-100)% Chance to apply Frostbite on Hit"},
				{name="Grand Protection of Heorot", minVal=55.0, maxVal=75.0, implCount=1, impl1="+(55-75)% Cold Resistance", label="+(55-75)% Cold Res"},
				{name="Grand Rage of Winter", minVal=25.0, maxVal=50.0, implCount=1, impl1="+(25-50)% Chance to Shred Cold Resistance on Hit", label="+(25-50)% Shred Cold Res on Hit"},
				{name="Grand Resolve of Grael", minVal=55.0, maxVal=75.0, implCount=1, impl1="+(55-75)% Physical Resistance", label="+(55-75)% Physical Res"},
				{name="Grand Vigor of Jormun", minVal=80.0, maxVal=150.0, implCount=1, impl1="+(80-150) Endurance Threshold", label="+(80-150) Endurance Threshold"},
				{name="Grand Winds of Frost", minVal=55.0, maxVal=80.0, implCount=1, impl1="+(55-80)% Freeze Rate per stack of Chill", label="+(55-80)% Freeze Rate per stack of Chill"},
			},
		},
		["The Last Ruin"] = {
			normal = {
				{name="Body of Obsidian", minVal=120.0, maxVal=180.0, implCount=1, impl1="+(120-180) Armor", label="+(120-180) Armor"},
				{name="Breath of Cinders", minVal=10.0, maxVal=20.0, implCount=1, impl1="+(10-20)% Chance to Shred Fire Resistance on Hit", label="+(10-20)% Shred Fire Res on Hit"},
				{name="Bulwark of the Tundra", minVal=12.0, maxVal=24.0, implCount=1, impl1="(12-24)% increased Armor", label="(12-24)% inc. Armor"},
				{name="Curse of Sulphur", minVal=20.0, maxVal=35.0, implCount=1, impl1="+(20-35)% Chance to apply Frailty on Hit", label="+(20-35)% Chance to apply Frailty on Hit"},
				{name="Defiance of Yulia", minVal=5.0, maxVal=10.0, implCount=1, impl1="+(5-10) Spell Cold Damage While Channelling", label="+(5-10) Spell Cold Dmg While Channelling"},
				{name="Embers of Immortality", minVal=10.0, maxVal=14.0, implCount=1, impl1="+(10-14)% Endurance", label="+(10-14)% Endurance"},
				{name="Heart of the Caldera", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Fire Resistance", label="+(25-40)% Fire Res"},
				{name="Promise of Death", minVal=10.0, maxVal=20.0, implCount=1, impl1="+(10-20)% Chance to Shred Necrotic Resistance on Hit", label="+(10-20)% Shred Necrotic Res on Hit"},
				{name="Spirit of Command", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Minion Damage", label="(40-60)% inc. Minion Dmg"},
				{name="Swiftness of Logi", minVal=15.0, maxVal=35.0, implCount=1, impl1="(15-35)% increased Dodge Rating", label="(15-35)% inc. Dodge Rating"},
			},
			grand = {
				{name="Grand Body of Obsidian", minVal=200.0, maxVal=320.0, implCount=1, impl1="+(200-320) Armor", label="+(200-320) Armor"},
				{name="Grand Breath of Cinders", minVal=25.0, maxVal=50.0, implCount=1, impl1="+(25-50)% Chance to Shred Fire Resistance on Hit", label="+(25-50)% Shred Fire Res on Hit"},
				{name="Grand Bulwark of the Tundra", minVal=25.0, maxVal=55.0, implCount=1, impl1="(25-55)% increased Armor", label="(25-55)% inc. Armor"},
				{name="Grand Curse of Sulphur", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to apply Frailty on Hit", label="+(40-60)% Chance to apply Frailty on Hit"},
				{name="Grand Defiance of Yulia", minVal=11.0, maxVal=20.0, implCount=1, impl1="+(11-20) Spell Cold Damage While Channelling", label="+(11-20) Spell Cold Dmg While Channelling"},
				{name="Grand Embers of Immortality", minVal=18.0, maxVal=30.0, implCount=1, impl1="+(18-30)% Endurance", label="+(18-30)% Endurance"},
				{name="Grand Heart of the Caldera", minVal=55.0, maxVal=75.0, implCount=1, impl1="+(55-75)% Fire Resistance", label="+(55-75)% Fire Res"},
				{name="Grand Promise of Death", minVal=25.0, maxVal=50.0, implCount=1, impl1="+(25-50)% Chance to Shred Necrotic Resistance on Hit", label="+(25-50)% Shred Necrotic Res on Hit"},
				{name="Grand Spirit of Command", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Minion Damage", label="(65-100)% inc. Minion Dmg"},
				{name="Grand Swiftness of Logi", minVal=40.0, maxVal=70.0, implCount=1, impl1="(40-70)% increased Dodge Rating", label="(40-70)% inc. Dodge Rating"},
			},
		},
	}

	local blessingTimelines = {"Fall of the Outcasts", "The Stolen Lance", "The Black Sun", "Blood, Frost, and Death", "Ending the Storm", "Fall of the Empire", "Reign of Dragons", "The Age of Winter", "Spirits of Fire", "The Last Ruin"}
	self.blessingControls = {}

	local function updateBlessingSlot(tl, blessEntry, rollFrac)
		local slot = self.slots[tl]
		if not slot then return end
		local oldId = slot.selItemId
		if oldId and oldId < 0 then self.items[oldId] = nil end
		if not blessEntry or not blessEntry.name then
			slot.selItemId = 0
			if self.activeItemSet[tl] then self.activeItemSet[tl].selItemId = 0 end
			self.build.buildFlag = true
			return
		end
		local frac = rollFrac or 1.0
		local val = blessEntry.minVal + frac * (blessEntry.maxVal - blessEntry.minVal)
		local function resolveImpl(impl)
			return impl:gsub("%([0-9.]+%-[0-9.]+%)", function()
				return string.format("%d", math.floor(val + 0.5))
			end)
		end
		local implCount = blessEntry.implCount or 1
		local raw = "Rarity: NORMAL\n"..blessEntry.name.."\n"..blessEntry.name
			.."\nImplicits: "..implCount.."\n"..resolveImpl(blessEntry.impl1 or "")
		if blessEntry.impl2 then raw = raw.."\n"..resolveImpl(blessEntry.impl2) end
		local item = new("Item", raw)
		if not item or not item.base then return end
		item:BuildModList()
		item.id = -1
		while self.items[item.id] do item.id = item.id - 1 end
		self.items[item.id] = item
		slot.selItemId = item.id
		if self.activeItemSet[tl] then self.activeItemSet[tl].selItemId = item.id end
		self.build.buildFlag = true
	end

	local prevBless = self.controls.idolAltarEnd
	self.controls.blessingHeader = new("LabelControl", {"TOPLEFT",prevBless,"BOTTOMLEFT"}, 0, 12, 310, 16, "^7Blessings (Monolith):")
	prevBless = self.controls.blessingHeader

	for _, tl in ipairs(blessingTimelines) do
		local tlData = blessingData[tl]
		if tlData then
			local isGrand = false
			local slider, drop, gradeBtn

			local function buildList(grand)
				local list = { {label="None"} }
				for _, b in ipairs(grand and tlData.grand or tlData.normal) do
					t_insert(list, {label=b.label or b.impl1 or b.name, data=b})
				end
				return list
			end

			-- Row1: timeline label + dropdown (same y)
			local tlLabel = new("LabelControl", {"TOPLEFT",prevBless,"BOTTOMLEFT"}, 0, 5, 144, 16, function()
				return "^x888888"..tl..":"
			end)
			drop = new("DropDownControl", {"TOPLEFT",prevBless,"BOTTOMLEFT"}, 148, 5, 250, 40, buildList(false), function(index, value)
				local frac = slider and slider.val or 1.0
				updateBlessingSlot(tl, value and value.data, frac)
			end)
			drop.enableDroppedWidth = true

			-- Row2: grade button + slider + value (anchored to tlLabel bottom, fixed offset for 40px drop)
			local row2 = new("Control", {"TOPLEFT",tlLabel,"BOTTOMLEFT"}, 0, 28, 0, 20)
			gradeBtn = new("ButtonControl", {"LEFT",row2,"RIGHT"}, 0, 2, 52, 16, "Normal", function()
				isGrand = not isGrand
				gradeBtn.label = isGrand and "Grand" or "Normal"
				drop:SetList(buildList(isGrand))
				local sel = drop.list[drop.selIndex]
				updateBlessingSlot(tl, sel and sel.data, slider and slider.val or 1.0)
			end)
			slider = new("SliderControl", {"LEFT",gradeBtn,"RIGHT"}, 4, 2, 150, 16, function(val)
				local sel = drop.list[drop.selIndex]
				updateBlessingSlot(tl, sel and sel.data, val)
			end)
			slider.val = 1.0
			local valLabel = new("LabelControl", {"LEFT",slider,"RIGHT"}, 4, 0, 44, 16, function()
				local sel = drop.list[drop.selIndex]
				if not sel or not sel.data then return "^x555555--" end
				local b = sel.data
				local v = b.minVal + slider.val * (b.maxVal - b.minVal)
				return string.format("^7%d", math.floor(v + 0.5))
			end)

			t_insert(self.controls, tlLabel)
			t_insert(self.controls, drop)
			t_insert(self.controls, row2)
			t_insert(self.controls, gradeBtn)
			t_insert(self.controls, slider)
			t_insert(self.controls, valLabel)
			self.blessingControls[tl] = {drop=drop, slider=slider, gradeBtn=gradeBtn}
			prevBless = row2
		end
	end

	self.controls.blessingPanelEnd = new("Control", {"TOPLEFT",prevBless,"BOTTOMLEFT"}, 0, 4, 0, 0)
	t_insert(self.controls, self.controls.blessingPanelEnd)
	-- ===== END BLESSING PANEL =====

	self.controls.slotHeader = new("LabelControl", {"BOTTOMLEFT",self.slotAnchor,"TOPLEFT"}, 0, -4, 0, 16, "^7Equipped items:")
	self.controls.weaponSwap1 = new("ButtonControl", {"BOTTOMRIGHT",self.slotAnchor,"TOPRIGHT"}, -20, -2, 18, 18, "I", function()
		if self.activeItemSet.useSecondWeaponSet then
			self.activeItemSet.useSecondWeaponSet = false
			self:AddUndoState()
			self.build.buildFlag = true
			local mainSocketGroup = self.build.skillsTab.socketGroupList[self.build.mainSocketGroup]
			if mainSocketGroup and mainSocketGroup.slot and self.slots[mainSocketGroup.slot].weaponSet == 2 then
				for index, socketGroup in pairs(self.build.skillsTab.socketGroupList) do
					if socketGroup.slot and self.slots[socketGroup.slot].weaponSet == 1 then
						self.build.mainSocketGroup = index
						break
					end
				end
			end
		end
	end)
	self.controls.weaponSwap1.overSizeText = 3
	self.controls.weaponSwap1.locked = function()
		return not self.activeItemSet.useSecondWeaponSet
	end
	self.controls.weaponSwap2 = new("ButtonControl", {"BOTTOMRIGHT",self.slotAnchor,"TOPRIGHT"}, 0, -2, 18, 18, "II", function()
		if not self.activeItemSet.useSecondWeaponSet then
			self.activeItemSet.useSecondWeaponSet = true
			self:AddUndoState()
			self.build.buildFlag = true
			local mainSocketGroup = self.build.skillsTab.socketGroupList[self.build.mainSocketGroup]
			-- TODO: support second item slot
			if mainSocketGroup and mainSocketGroup.slot and self.slots[mainSocketGroup.slot].weaponSet == 1 then
				for index, socketGroup in pairs(self.build.skillsTab.socketGroupList) do
					if socketGroup.slot and self.slots[socketGroup.slot].weaponSet == 2 then
						self.build.mainSocketGroup = index
						break
					end
				end
			end
		end
	end)
	self.controls.weaponSwap2.overSizeText = 3
	self.controls.weaponSwap2.locked = function()
		return self.activeItemSet.useSecondWeaponSet
	end
	self.controls.weaponSwapLabel = new("LabelControl", {"RIGHT",self.controls.weaponSwap1,"LEFT"}, -4, 0, 0, 14, "^7Weapon Set:")

	-- All items list
	if main.portraitMode then
		self.controls.itemList = new("ItemListControl", {"TOPRIGHT",self.lastSlot,"BOTTOMRIGHT"}, 0, 0, 360, 308, self, true)
	else
		self.controls.itemList = new("ItemListControl", {"TOPLEFT",self.controls.setManage,"TOPRIGHT"}, 20, 20, 360, 308, self, true)
	end

	-- Database selector
	self.controls.selectDBLabel = new("LabelControl", {"TOPLEFT",self.controls.itemList,"BOTTOMLEFT"}, 0, 14, 0, 16, "^7Import from:")
	self.controls.selectDBLabel.shown = function()
		return self.height < 980
	end
	self.controls.selectDB = new("DropDownControl", {"LEFT",self.controls.selectDBLabel,"RIGHT"}, 4, 0, 150, 18, { "Uniques", "Rare Templates" })

	-- Unique database
	self.controls.uniqueDB = new("ItemDBControl", {"TOPLEFT",self.controls.itemList,"BOTTOMLEFT"}, 0, 76, 360, function(c) return m_min(244, self.maxY - select(2, c:GetPos())) end, self, main.uniqueDB, "UNIQUE")
	self.controls.uniqueDB.y = function()
		return self.controls.selectDBLabel:IsShown() and 118 or 96
	end
	self.controls.uniqueDB.shown = function()
		return not self.controls.selectDBLabel:IsShown() or self.controls.selectDB.selIndex == 1
	end

	-- Rare template database
	self.controls.rareDB = new("ItemDBControl", {"TOPLEFT",self.controls.itemList,"BOTTOMLEFT"}, 0, 76, 360, function(c) return m_min(260, self.maxY - select(2, c:GetPos())) end, self, main.rareDB, "RARE")
	self.controls.rareDB.y = function()
		return self.controls.selectDBLabel:IsShown() and 78 or 396
	end
	self.controls.rareDB.shown = function()
		return not self.controls.selectDBLabel:IsShown() or self.controls.selectDB.selIndex == 2
	end
	-- Set all item ranges
	self.controls.allItemRangeSlider = new("SliderControl", {"TOPLEFT",main.portraitMode and self.controls.setManage or self.controls.itemList,"TOPRIGHT"}, 20, main.portraitMode and 0 or -20, 100, 18, function ()
		self:UpdateAllItemRangeLabel()
	end)


	self.controls.allItemRangeButton = new("ButtonControl", {"TOPLEFT",self.controls.allItemRangeSlider,"TOPRIGHT"}, 8, 0, 250, 20, "Set all mods range of all items", function()
		local range = self.controls.allItemRangeSlider.val * 256
		-- Fix for allowing half range values
		if range > 127.2 and range < 127.8 then
			range = 127.5
		else
			range = round(range)
		end
		self:SetAllItemRanges(range)
		self:AddUndoState()
	end)

	self.controls.allItemRangeSlider.val = main.defaultItemAffixQuality / 256;
	self:UpdateAllItemRangeLabel()

	-- Create/import item
	self.controls.craftDisplayItem = new("ButtonControl", {"TOPLEFT",self.controls.allItemRangeSlider,"BOTTOMLEFT"}, 0, 8, 120, 20, "Craft item...", function()
		self:CraftItem()
	end)
	self.controls.craftDisplayItem.shown = function()
		return self.displayItem == nil
	end
	self.controls.newDisplayItem = new("ButtonControl", {"TOPLEFT",self.controls.craftDisplayItem,"TOPRIGHT"}, 8, 0, 120, 20, "Create custom...", function()
		self:EditDisplayItemText()
	end)
	self.controls.displayItemTip = new("LabelControl", {"TOPLEFT",self.controls.craftDisplayItem,"BOTTOMLEFT"}, 0, 8, 100, 16,
[[^7Double-click an item from one of the lists to view or edit
the item and add it to your build. You can
also clone an item within Last Epoch Building by
copying and pasting it with Ctrl+C and Ctrl+V.

You can Control + Click an item to equip it, or
drag it onto the slot.  This will also add it to
your build if it's from the unique/template list.
If there's 2 slots an item can go in,
holding Shift will put it in the second.]])
	self.controls.sharedItemList = new("SharedItemListControl", {"TOPLEFT",self.controls.craftDisplayItem, "BOTTOMLEFT"}, 0, 232, 340, 308, self, true)

	-- Display item
	self.displayItemTooltip = new("Tooltip")
	self.displayItemTooltip.maxWidth = 458
	self.anchorDisplayItem = new("Control", {"TOPLEFT",self.controls.allItemRangeSlider,"BOTTOMLEFT"}, 0, 8, 0, 0)
	self.anchorDisplayItem.shown = function()
		return self.displayItem ~= nil
	end
	self.controls.addDisplayItem = new("ButtonControl", {"TOPLEFT",self.anchorDisplayItem,"TOPLEFT"}, 0, 0, 100, 20, "", function()
		self:AddDisplayItem()
	end)
	self.controls.addDisplayItem.label = function()
		return self.items[self.displayItem.id] and "Save" or "Add to build"
	end
	self.controls.editDisplayItem = new("ButtonControl", {"LEFT",self.controls.addDisplayItem,"RIGHT"}, 8, 0, 60, 20, "Edit...", function()
		self:EditDisplayItemText()
	end)
	self.controls.removeDisplayItem = new("ButtonControl", {"LEFT",self.controls.editDisplayItem,"RIGHT"}, 8, 0, 60, 20, "Cancel", function()
		self:SetDisplayItem()
	end)

	self.controls.displayItemAddImplicit = new("ButtonControl", {"TOPLEFT",self.controls.addDisplayItem,"BOTTOMLEFT"}, 0, 8, 120, 20, "Add Implicit...", function()
		self:AddImplicitToDisplayItem()
	end)
	self.controls.displayItemAddImplicit.shown = function()
		return self.displayItem
	end

	-- Section: Affix Selection
	self.controls.displayItemSectionAffix = new("Control", {"TOPLEFT",self.controls.displayItemAddImplicit,"BOTTOMLEFT"}, 0, 0, 0, function()
		if not self.displayItem or not self.displayItem.crafted then
			return 0
		end
		local h = 6
		for i = 1, 6 do
			if self.controls["displayItemAffix"..i]:IsShown() then
				h = h + 24
				if self.controls["displayItemAffixRange"..i]:IsShown() then
					h = h + 18
				end
			end
		end
		return h
	end)
	for i = 1, 6 do
		local prev = self.controls["displayItemAffix"..(i-1)] or self.controls.displayItemSectionAffix
		local drop, slider
		local function verifyRange(range, index, drop) -- flips range if it will form discontinuous values
			local priorMod = index - 1 > 0 and self.displayItem.affixes[drop.list[drop.selIndex].modList[index - 1]] or nil
			local nextMod = index + 1 < #drop.list[drop.selIndex].modList and self.displayItem.affixes[drop.list[drop.selIndex].modList[index + 1]] or nil
			local function flipRange(modA, modB) -- assumes all pairs are ordered the same
				local function getMinMax(mod) -- gets first valid range from a mod
					for _, line in ipairs(mod) do
						local min, max = line:match("%((%d[%d%.]*)%-(%d[%d%.]*)%)")
						if min and max then return tonumber(min), tonumber(max)	end
					end
				end

				local minA, maxA = getMinMax(modA)
				local minB, maxB = getMinMax(modB)

				if not minA or not minB or not maxA or not maxB then
					return false
				end

				local allInts = minA == m_floor(minA) and maxA == m_floor(maxA) and minB == m_floor(minB) and maxB == m_floor(maxB) -- if the mod goes in steps that aren't 1, then the code below this doesn't work
				if (minA and minB and maxA and maxB and allInts) then
					if (minA < minB) then -- ascending
						return minA + 1 == maxB
					else -- descending
						return minA - 1 == maxB
					end
				end
				return false
			end

			if priorMod then
				if flipRange(priorMod, self.displayItem.affixes[drop.list[drop.selIndex].modList[index]]) then
					range = 256 - range
				end
			elseif nextMod then
				if flipRange(self.displayItem.affixes[drop.list[drop.selIndex].modList[index]], nextMod) then
					range = 256 - range
				end
			end
			return range
		end
		drop = new("DropDownControl", {"TOPLEFT",prev,"TOPLEFT"}, i==1 and 40 or 0, 0, 418, 20, nil, function(index, value)
			local affix = { modId = "None" }
			if value.modId then
				affix.modId = value.modId
				affix.range = slider.val
			elseif value.modList then
				slider.divCount = #value.modList
				local index, range = slider:GetDivVal()
				affix.modId = value.modList[index]
				affix.range = verifyRange(range, index, drop)
			end
			self.displayItem[drop.outputTable][drop.outputIndex] = affix
			self.displayItem:Craft()
			self:UpdateDisplayItemTooltip()
			self:UpdateAffixControls()
		end)
		drop.y = function()
			return i == 1 and 0 or 24 + (prev.slider:IsShown() and 18 or 0)
		end
		drop.tooltipFunc = function(tooltip, mode, index, value)
			local modList = value.modList
			if not modList or main.popups[1] or mode == "OUT" or (self.selControl and self.selControl ~= drop) then
				tooltip:Clear()
			elseif tooltip:CheckForUpdate(modList) then
				if value.modId or #modList == 1 then
					local mod = self.displayItem.affixes[value.modId or modList[1]]
					tooltip:AddLine(16, "^7Affix: "..mod.affix)
					for _, line in ipairs(mod) do
						tooltip:AddLine(14, "^7"..line)
					end
					if mod.level > 1 then
						tooltip:AddLine(16, "Level: "..mod.level)
					end
					if mod.modTags and #mod.modTags > 0 then
						tooltip:AddLine(16, "Tags: "..table.concat(mod.modTags, ', '))
					end
				else
					tooltip:AddLine(16, "^7"..#modList.." Tiers")
					local minMod = self.displayItem.affixes[modList[1]]
					local maxMod = self.displayItem.affixes[modList[#modList]]
					for l, line in ipairs(minMod) do
						local minLine = line:gsub("%((%d[%d%.]*)%-(%d[%d%.]*)%)", "%1")
						local maxLine = maxMod[l]:gsub("%((%d[%d%.]*)%-(%d[%d%.]*)%)", "%2")
						if maxLine == maxMod[l] then
							tooltip:AddLine(14, maxLine)
						else
							local start = 1
							tooltip:AddLine(14, minLine:gsub("%d[%d%.]*", function(min)
								local s, e, max = maxLine:find("(%d[%d%.]*)", start)
								start = e + 1
								if min == max then
									return min
								else
									return "("..min.."-"..max..")"
								end
							end))
						end
					end
					tooltip:AddLine(16, "Level: "..minMod.level.." to "..maxMod.level)
					-- Assuming that all mods have the same tags
					if maxMod.modTags and #maxMod.modTags > 0 then
						tooltip:AddLine(16, "Tags: "..table.concat(maxMod.modTags, ', '))
					end
				end
				local mod = { }
				if value.modId or #modList == 1 then
					mod = self.displayItem.affixes[value.modId or modList[1]]
				else
					mod = self.displayItem.affixes[modList[1 + round((#modList - 1) * main.defaultItemAffixQuality / 256)]]
				end

				-- Adding Mod
				self:AddModComparisonTooltip(tooltip, mod)
			end
		end
		drop.shown = function()
			return self.displayItem and self.displayItem.crafted and i <= self.displayItem.affixLimit
		end
		slider = new("SliderControl", {"TOPLEFT",drop,"BOTTOMLEFT"}, 0, 2, 300, 16, function(val)
			local affix = self.displayItem[drop.outputTable][drop.outputIndex]
			local index, range = slider:GetDivVal()
			affix.modId = drop.list[drop.selIndex].modList[index]

			affix.range = verifyRange(range, index, drop)
			self.displayItem:Craft()
			self:UpdateDisplayItemTooltip()
		end)
		slider.width = function()
			return slider.divCount and 300 or 100
		end
		slider.tooltipFunc = function(tooltip, val)
			local modList = drop.list[drop.selIndex].modList
			if not modList or main.popups[1] or (self.selControl and self.selControl ~= slider) then
				tooltip:Clear()
			elseif tooltip:CheckForUpdate(val, modList) then
				local index, range = slider:GetDivVal(val)
				local modId = modList[index]
				local mod = self.displayItem.affixes[modId]
				for _, line in ipairs(mod) do
					tooltip:AddLine(16, itemLib.applyRange(line, range, 1.0, mod.rounding))
				end
				tooltip:AddSeparator(10)
				if #modList > 1 then
					tooltip:AddLine(16, "^7Affix: Tier "..isValueInArray(modList, modId).." ("..mod.affix..")")
				else
					tooltip:AddLine(16, "^7Affix: "..mod.affix)
				end
				for _, line in ipairs(mod) do
					tooltip:AddLine(14, line)
				end
				if mod.level > 1 then
					tooltip:AddLine(16, "Level: "..mod.level)
				end
			end
		end
		drop.slider = slider
		self.controls["displayItemAffix"..i] = drop
		self.controls["displayItemAffixLabel"..i] = new("LabelControl", {"RIGHT",drop,"LEFT"}, -4, 0, 0, 14, function()
			return drop.outputTable == "prefixes" and "^7Prefix:" or "^7Suffix:"
		end)
		self.controls["displayItemAffixRange"..i] = slider
		self.controls["displayItemAffixRangeLabel"..i] = new("LabelControl", {"RIGHT",slider,"LEFT"}, -4, 0, 0, 14, function()
			return drop.selIndex > 1 and "^7Roll:" or "^x7F7F7FRoll:"
		end)
	end

	-- Section: Custom modifiers
	-- if Custom mod button is shown, create the control for the list of mods
	self.controls.displayItemSectionCustom = new("Control", {"TOPLEFT",self.controls.displayItemSectionAffix,"BOTTOMLEFT"}, 0, 0, 0, function()
		return self.controls.displayItemAddCustom:IsShown() and 28 + self.displayItem.customCount * 22 or 0
	end)
	self.controls.displayItemAddCustom = new("ButtonControl", {"TOPLEFT",self.controls.displayItemSectionCustom,"TOPLEFT"}, 0, 0, 120, 20, "Add modifier...", function()
		self:AddCustomModifierToDisplayItem()
	end)
	self.controls.displayItemAddCustom.shown = function()
		return self.displayItem and (self.displayItem.rarity == "MAGIC" or self.displayItem.rarity == "RARE")
	end

	-- Section: Modifier Range
	self.controls.displayItemSectionRange = new("Control", {"TOPLEFT",self.controls.displayItemSectionCustom,"BOTTOMLEFT"}, 0, 0, 0, function()
		return self.displayItem.rangeLineList[1] and 28 or 0
	end)
	self.controls.displayItemRangeLine = new("DropDownControl", {"TOPLEFT",self.controls.displayItemSectionRange,"TOPLEFT"}, 0, 0, 350, 18, nil, function(index, value)
		self.controls.displayItemRangeSlider.val = self.displayItem.rangeLineList[index].range / 256
	end)
	self.controls.displayItemRangeLine.shown = function()
		return self.displayItem and self.displayItem.rangeLineList[1] ~= nil
	end
	self.controls.displayItemRangeSlider = new("SliderControl", {"LEFT",self.controls.displayItemRangeLine,"RIGHT"}, 8, 0, 100, 18, function(val)
		self.displayItem.rangeLineList[self.controls.displayItemRangeLine.selIndex].range = val * 256
		self.displayItem:BuildAndParseRaw()
		self:UpdateDisplayItemTooltip()
		self:UpdateCustomControls()
	end)

	-- Tooltip anchor
	self.controls.displayItemTooltipAnchor = new("Control", {"TOPLEFT",self.controls.displayItemSectionRange,"BOTTOMLEFT"})

	-- Scroll bars
	self.controls.scrollBarH = new("ScrollBarControl", nil, 0, 0, 0, 18, 100, "HORIZONTAL", true)
	self.controls.scrollBarV = new("ScrollBarControl", nil, 0, 0, 18, 0, 100, "VERTICAL", true)

	-- Initialise drag target lists
	t_insert(self.controls.itemList.dragTargetList, self.controls.sharedItemList)
	t_insert(self.controls.itemList.dragTargetList, build.controls.mainSkillMinion)
	t_insert(self.controls.uniqueDB.dragTargetList, self.controls.itemList)
	t_insert(self.controls.uniqueDB.dragTargetList, self.controls.sharedItemList)
	t_insert(self.controls.uniqueDB.dragTargetList, build.controls.mainSkillMinion)
	t_insert(self.controls.rareDB.dragTargetList, self.controls.itemList)
	t_insert(self.controls.rareDB.dragTargetList, self.controls.sharedItemList)
	t_insert(self.controls.rareDB.dragTargetList, build.controls.mainSkillMinion)
	t_insert(self.controls.sharedItemList.dragTargetList, self.controls.itemList)
	t_insert(self.controls.sharedItemList.dragTargetList, build.controls.mainSkillMinion)
	for _, slot in pairs(self.slots) do
		t_insert(self.controls.itemList.dragTargetList, slot)
		t_insert(self.controls.uniqueDB.dragTargetList, slot)
		t_insert(self.controls.rareDB.dragTargetList, slot)
		t_insert(self.controls.sharedItemList.dragTargetList, slot)
	end

	-- Initialise item sets
	self.itemSets = { }
	self.itemSetOrderList = { 1 }
	self:NewItemSet(1)
	self:SetActiveItemSet(1)

	self:PopulateSlots()
	self.lastSlot = lastVisibleSlot
end)

function ItemsTabClass:Load(xml, dbFileName)
	self.activeItemSetId = 0
	self.activeItemSet = nil   -- prevent SetActiveItemSet from saving back the constructor-time item set (which pre-dates idol slot registration)
	self.itemSets = { }
	self.itemSetOrderList = { }
	for _, node in ipairs(xml) do
		if node.elem == "Item" then
			local item = new("Item", "")
			item.id = tonumber(node.attrib.id)
			item.variant = tonumber(node.attrib.variant)
			if node.attrib.variantAlt then
				item.hasAltVariant = true
				item.variantAlt = tonumber(node.attrib.variantAlt)
			end
			if node.attrib.variantAlt2 then
				item.hasAltVariant2 = true
				item.variantAlt2 = tonumber(node.attrib.variantAlt2)
			end
			if node.attrib.variantAlt3 then
				item.hasAltVariant3 = true
				item.variantAlt3 = tonumber(node.attrib.variantAlt3)
			end
			if node.attrib.variantAlt4 then
				item.hasAltVariant4 = true
				item.variantAlt4 = tonumber(node.attrib.variantAlt4)
			end
			if node.attrib.variantAlt5 then
				item.hasAltVariant5 = true
				item.variantAlt5 = tonumber(node.attrib.variantAlt5)
			end
			for _, child in ipairs(node) do
				if type(child) == "string" then
					item:ParseRaw(child)
				elseif child.elem == "ModRange" then
					local id = tonumber(child.attrib.id) or 0
					local range = tonumber(child.attrib.range) or 1
					-- This is garbage, but needed due to change to separate mod line lists
					-- 'ModRange' elements are legacy though, so is this actually needed? :<
					-- Maybe it is? Maybe it isn't? Maybe up is down? Maybe good is bad? AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
					-- Sorry, cluster jewels are making me crazy(-ier)
					for _, list in ipairs{item.buffModLines, item.enchantModLines, item.implicitModLines, item.explicitModLines} do
						if id <= #list then
							list[id].range = range
							break
						end
						id = id - #list
					end
				end
			end
			if item.base then
				item:BuildModList()
				self.items[item.id] = item
				t_insert(self.itemOrderList, item.id)
			end
		-- Below is OBE and left for legacy compatibility (all Slots are part of ItemSets now)
		elseif node.elem == "Slot" then
			local slot = self.slots[node.attrib.name or ""]
			if slot then
				slot.selItemId = tonumber(node.attrib.itemId)
				if slot.controls.activate then
					slot.active = node.attrib.active == "true"
					slot.controls.activate.state = slot.active
				end
			end
		elseif node.elem == "ItemSet" then
			local itemSet = self:NewItemSet(tonumber(node.attrib.id))
			itemSet.title = node.attrib.title
			itemSet.useSecondWeaponSet = node.attrib.useSecondWeaponSet == "true"
			for _, child in ipairs(node) do
				if child.elem == "Slot" then
					local slotName = child.attrib.name or ""
					if itemSet[slotName] then
						itemSet[slotName].selItemId = tonumber(child.attrib.itemId)
						itemSet[slotName].active = child.attrib.active == "true"
						itemSet[slotName].pbURL = child.attrib.itemPbURL or ""
					end
				elseif child.elem == "SocketIdURL" then
					local id = tonumber(child.attrib.nodeId)
					itemSet[id] = { pbURL = child.attrib.itemPbURL or "" }
				end
			end
			t_insert(self.itemSetOrderList, itemSet.id)
		end
	end
	if not self.itemSetOrderList[1] then
		self.activeItemSet = self:NewItemSet(1)
		self.activeItemSet.useSecondWeaponSet = xml.attrib.useSecondWeaponSet == "true"
		self.itemSetOrderList[1] = 1
	end
	self:SetActiveItemSet(tonumber(xml.attrib.activeItemSet) or 1)
	self:ResetUndo()
end

function ItemsTabClass:Save(xml)
	xml.attrib = {
		activeItemSet = tostring(self.activeItemSetId),
		useSecondWeaponSet = tostring(self.activeItemSet.useSecondWeaponSet),
	}
	for _, id in ipairs(self.itemOrderList) do
		local item = self.items[id]
		local child = {
			elem = "Item",
			attrib = {
				id = tostring(id),
				variant = item.variant and tostring(item.variant),
				variantAlt = item.variantAlt and tostring(item.variantAlt),
				variantAlt2 = item.variantAlt2 and tostring(item.variantAlt2),
				variantAlt3 = item.variantAlt3 and tostring(item.variantAlt3),
				variantAlt4 = item.variantAlt4 and tostring(item.variantAlt4),
				variantAlt5 = item.variantAlt5 and tostring(item.variantAlt5)
			}
		}
		item:BuildAndParseRaw()
		t_insert(child, item.raw)
		local id = #item.buffModLines + 1
		for _, modLine in ipairs(item.implicitModLines) do
			if modLine.range ~= nil then
				t_insert(child, { elem = "ModRange", attrib = { id = tostring(id), range = tostring(modLine.range) } })
			end
			id = id + 1
		end
		for _, modLine in ipairs(item.explicitModLines) do
			if modLine.range ~= nil then
				t_insert(child, { elem = "ModRange", attrib = { id = tostring(id), range = tostring(modLine.range) } })
			end
			id = id + 1
		end
		t_insert(xml, child)
	end
	for _, itemSetId in ipairs(self.itemSetOrderList) do
		local itemSet = self.itemSets[itemSetId]
		local child = { elem = "ItemSet", attrib = { id = tostring(itemSetId), title = itemSet.title, useSecondWeaponSet = tostring(itemSet.useSecondWeaponSet) } }
		for slotName, slot in pairsSortByKey(self.slots) do
			if not slot.nodeId then
				t_insert(child, { elem = "Slot", attrib = { name = slotName, itemId = tostring(itemSet[slotName].selItemId), itemPbURL = itemSet[slotName].pbURL or "", active = itemSet[slotName].active and "true" }})
			else
				if self.build.spec.allocNodes[slot.nodeId] then
					t_insert(child, { elem = "SocketIdURL", attrib = { name = slotName, nodeId = tostring(slot.nodeId), itemPbURL = itemSet[slot.nodeId] and itemSet[slot.nodeId].pbURL or ""}})
				end
			end
		end
		t_insert(xml, child)
	end
end

function ItemsTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height
	self.controls.scrollBarH.width = viewPort.width
	self.controls.scrollBarH.x = viewPort.x
	self.controls.scrollBarH.y = viewPort.y + viewPort.height - 18
	self.controls.scrollBarV.height = viewPort.height - 18
	self.controls.scrollBarV.x = viewPort.x + viewPort.width - 18
	self.controls.scrollBarV.y = viewPort.y
	do
		local maxY = select(2, self.controls.blessingPanelEnd:GetPos()) + 24
		local maxX = self.anchorDisplayItem:GetPos() + 462
		if self.displayItem then
			local x, y = self.controls.displayItemTooltipAnchor:GetPos()
			local ttW, ttH = self.displayItemTooltip:GetDynamicSize(viewPort)
			maxY = m_max(maxY, y + ttH + 4)
			maxX = m_max(maxX, x + ttW + 80)
		end
		local contentHeight = maxY - self.y
		local contentWidth = maxX - self.x
		local v = contentHeight > viewPort.height
		local h = contentWidth > viewPort.width - (v and 20 or 0)
		if h then
			v = contentHeight > viewPort.height - 20
		end
		self.controls.scrollBarV:SetContentDimension(contentHeight, viewPort.height - (h and 20 or 0))
		self.controls.scrollBarH:SetContentDimension(contentWidth, viewPort.width - (v and 20 or 0))
		if self.snapHScroll == "RIGHT" then
			self.controls.scrollBarH:SetOffset(self.controls.scrollBarH.offsetMax)
		elseif self.snapHScroll == "LEFT" then
			self.controls.scrollBarH:SetOffset(0)
		end
		self.snapHScroll = nil
		self.maxY = h and self.controls.scrollBarH.y or viewPort.y + viewPort.height
	end
	self.x = self.x - self.controls.scrollBarH.offset
	self.y = self.y - self.controls.scrollBarV.offset

	for _, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "v" and IsKeyDown("CTRL") then
				local newItem = Paste()
				if newItem then
					self:CreateDisplayItemFromRaw(newItem, true)
				end
			elseif event.key == "e" then
				local mOverControl = self:GetMouseOverControl()
				if mOverControl and mOverControl._className == "ItemSlotControl" and mOverControl.selItemId ~= 0 then
					-- Trigger itemList's double click procedure
					self.controls.itemList:OnSelClick(0, mOverControl.selItemId, true)
				end
			elseif event.key == "z" and IsKeyDown("CTRL") then
				self:Undo()
				self.build.buildFlag = true
			elseif event.key == "y" and IsKeyDown("CTRL") then
				self:Redo()
				self.build.buildFlag = true
			elseif event.key == "f" and IsKeyDown("CTRL") then
				local selUnique = self.selControl == self.controls.uniqueDB.controls.search
				local selRare = self.selControl == self.controls.rareDB.controls.search
				if selUnique or (self.controls.selectDB:IsShown() and not selRare and self.controls.selectDB.selIndex == 2) then
					self:SelectControl(self.controls.rareDB.controls.search)
					self.controls.selectDB.selIndex = 2
				else
					self:SelectControl(self.controls.uniqueDB.controls.search)
					self.controls.selectDB.selIndex = 1
				end
			end
		end
	end
	self:ProcessControlsInput(inputEvents, viewPort)
	for _, event in ipairs(inputEvents) do
		if event.type == "KeyUp" then
			if self.controls.scrollBarV:IsScrollDownKey(event.key) then
				if self.controls.scrollBarV:IsMouseOver() or not self.controls.scrollBarH:IsShown() then
					self.controls.scrollBarV:Scroll(1)
				else
					self.controls.scrollBarH:Scroll(1)
				end
			elseif self.controls.scrollBarV:IsScrollUpKey(event.key) then
				if self.controls.scrollBarV:IsMouseOver() or not self.controls.scrollBarH:IsShown() then
					self.controls.scrollBarV:Scroll(-1)
				else
					self.controls.scrollBarH:Scroll(-1)
				end
			end
		end
	end

	main:DrawBackground(viewPort)

	local newItemList = { }
	for index, itemSetId in ipairs(self.itemSetOrderList) do
		local itemSet = self.itemSets[itemSetId]
		t_insert(newItemList, itemSet.title or "Default")
		if itemSetId == self.activeItemSetId then
			self.controls.setSelect.selIndex = index
		end
	end
	self.controls.setSelect:SetList(newItemList)

	if self.displayItem then
		local x, y = self.controls.displayItemTooltipAnchor:GetPos()
		self.displayItemTooltip:Draw(x, y, nil, nil, viewPort)
	end

	self:DrawControls(viewPort)
	if self.controls.scrollBarH:IsShown() then
		self.controls.scrollBarH:Draw(viewPort)
	end
	if self.controls.scrollBarV:IsShown() then
		self.controls.scrollBarV:Draw(viewPort)
	end

	self.controls.specSelect:SetList(self.build.treeTab:GetSpecList())
end

-- Registers a slot that was created after the ItemsTab constructor finished
-- (e.g. idol slots created by IdolGridControl).  Performs the same bookkeeping
-- that the constructor loop does for the original slots:
--   1. Add to drag-target lists so items can be dragged onto it.
--   2. Add an entry to every existing item set so SetSelItemId / SetActiveItemSet
--      never index a nil key.
function ItemsTabClass:RegisterLateSlot(slot)
	-- Drag targets
	t_insert(self.controls.itemList.dragTargetList, slot)
	t_insert(self.controls.uniqueDB.dragTargetList, slot)
	t_insert(self.controls.rareDB.dragTargetList, slot)
	t_insert(self.controls.sharedItemList.dragTargetList, slot)
	-- Item sets
	if not slot.nodeId then
		for _, itemSet in pairs(self.itemSets) do
			if not itemSet[slot.slotName] then
				itemSet[slot.slotName] = { selItemId = 0 }
			end
		end
	end
end

-- Creates a new item set
function ItemsTabClass:NewItemSet(itemSetId)
	local itemSet = { id = itemSetId }
	if not itemSetId then
		itemSet.id = 1
		while self.itemSets[itemSet.id] do
			itemSet.id = itemSet.id + 1
		end
	end
	for slotName, slot in pairs(self.slots) do
		if not slot.nodeId then
			itemSet[slotName] = { selItemId = 0 }
		end
	end
	self.itemSets[itemSet.id] = itemSet
	return itemSet
end

-- Changes the active item set
function ItemsTabClass:SetActiveItemSet(itemSetId)
	local prevSet = self.activeItemSet
	if not self.itemSets[itemSetId] then
		itemSetId = self.itemSetOrderList[1]
	end
	self.activeItemSetId = itemSetId
	self.activeItemSet = self.itemSets[itemSetId]
	local curSet = self.activeItemSet
	for slotName, slot in pairs(self.slots) do
		if not slot.nodeId then
			if prevSet then
				-- Update the previous set
				prevSet[slotName].selItemId = slot.selItemId
				prevSet[slotName].active = slot.active
			end
			-- Equip the incoming set's item
			slot.selItemId = curSet[slotName].selItemId
			slot.active = curSet[slotName].active
			if slot.controls.activate then
				slot.controls.activate.state = slot.active
			end
		end
	end
	self.build.buildFlag = true
	self:PopulateSlots()
end

-- Equips the given item in the given item set
function ItemsTabClass:EquipItemInSet(item, itemSetId)
	local itemSet = self.itemSets[itemSetId]
	local slotName = item:GetPrimarySlot()
	if self.slots[slotName].weaponSet == 1 and itemSet.useSecondWeaponSet then
		-- Redirect to second weapon set
		slotName = slotName .. " Swap"
	end
	if not item.id or not self.items[item.id] then
		item = new("Item", item.raw)
		self:AddItem(item, true)
	end
	local altSlot = slotName:gsub("1","2")
	if IsKeyDown("SHIFT") then
		-- Redirect to second slot if possible
		if self:IsItemValidForSlot(item, altSlot, itemSet) then
			slotName = altSlot
		end
	end
	if itemSet == self.activeItemSet then
		self.slots[slotName]:SetSelItemId(item.id)
	else
		itemSet[slotName].selItemId = item.id
		if itemSet[altSlot].selItemId ~= 0 and not self:IsItemValidForSlot(self.items[itemSet[altSlot].selItemId], altSlot, itemSet) then
			itemSet[altSlot].selItemId = 0
		end
	end
	self:PopulateSlots()
	self:AddUndoState()
	self.build.buildFlag = true
end

function ItemsTabClass:UpdateAllItemRangeLabel()
	local range = self.controls.allItemRangeSlider.val * 256
	if range > 127.2 and range < 127.8 then
		range = 127.5
	else
		range = round(range)
	end
	self.controls.allItemRangeButton.label = "Set all mods range of all items (" .. round(range / 255 * 100,1) .. "%)"
end

-- Update the item lists for all the slot controls
function ItemsTabClass:PopulateSlots()
	for _, slot in pairs(self.slots) do
		slot:Populate()
	end
end

-- Adds the given item to the build's item list
function ItemsTabClass:AddItem(item, noAutoEquip, index)
	if not item.id then
		-- Find an unused item ID
		item.id = 1
		while self.items[item.id] do
			item.id = item.id + 1
		end

		if index then
			t_insert(self.itemOrderList, index, item.id)
		else
			-- Add it to the end of the display order list
			t_insert(self.itemOrderList, item.id)
		end

		if not noAutoEquip then
			-- Autoequip it
			for _, slot in ipairs(self.orderedSlots) do
				if not slot.nodeId and slot.selItemId == 0 and slot:IsShown() and self:IsItemValidForSlot(item, slot.slotName) then
					slot:SetSelItemId(item.id)
					break
				end
			end
		end
	end

	-- Add it to the list
	local replacing = self.items[item.id]
	self.items[item.id] = item
	item:BuildModList()
end

-- Adds the current display item to the build's item list
function ItemsTabClass:AddDisplayItem(noAutoEquip)
	-- Add it to the list and clear the current display item
	self:AddItem(self.displayItem, noAutoEquip)
	self:SetDisplayItem()

	self:PopulateSlots()
	self:AddUndoState()
	self.build.buildFlag = true
end

-- Sorts the build's item list
function ItemsTabClass:SortItemList()
	table.sort(self.itemOrderList, function(a, b)
		local itemA = self.items[a]
		local itemB = self.items[b]
		local primSlotA = itemA:GetPrimarySlot()
		local primSlotB = itemB:GetPrimarySlot()
		if primSlotA ~= primSlotB then
			if not self.slotOrder[primSlotA] then
				return false
			elseif not self.slotOrder[primSlotB] then
				return true
			end
			return self.slotOrder[primSlotA] < self.slotOrder[primSlotB]
		end
		local equipSlotA, equipSetA = self:GetEquippedSlotForItem(itemA)
		local equipSlotB, equipSetB = self:GetEquippedSlotForItem(itemB)
		if equipSlotA and equipSlotB then
			if equipSlotA ~= equipSlotB then
				return self.slotOrder[equipSlotA.slotName] < self.slotOrder[equipSlotB.slotName]
			elseif equipSetA and not equipSetB then
				return false
			elseif not equipSetA and equipSetB then
				return true
			elseif equipSetA and equipSetB then
				return isValueInArray(self.itemSetOrderList, equipSetA.id) < isValueInArray(self.itemSetOrderList, equipSetB.id)
			end
		elseif equipSlotA then
			return true
		elseif equipSlotB then
			return false
		end
		return itemA.name < itemB.name
	end)
	self:AddUndoState()
end

-- Delete all unused items
function ItemsTabClass:DeleteUnused()
	local delList = {}
	for itemId, item in pairs(self.items) do
		if not self:GetEquippedSlotForItem(item) then
			t_insert(delList, itemId)
		end
	end
	-- Delete in reverse order so as to not delete the wrong item whilst deleting
	for i = #delList, 1, -1 do
		self:DeleteItem(self.items[delList[i]], true)
	end
	self:PopulateSlots()
	self:AddUndoState()
	self.build.buildFlag = true
end

-- Deletes an item
function ItemsTabClass:DeleteItem(item, deferUndoState)
	for slotName, slot in pairs(self.slots) do
		if slot.selItemId == item.id then
			slot:SetSelItemId(0)
			self.build.buildFlag = true
		end
		if not slot.nodeId then
			for _, itemSet in pairs(self.itemSets) do
				if itemSet[slotName].selItemId == item.id then
					itemSet[slotName].selItemId = 0
					self.build.buildFlag = true
				end
			end
		end
	end
	for index, id in pairs(self.itemOrderList) do
		if id == item.id then
			t_remove(self.itemOrderList, index)
			break
		end
	end
	self.items[item.id] = nil
	if not deferUndoState then
		self:PopulateSlots()
		self:AddUndoState()
	end
end

-- Attempt to create a new item from the given item raw text and sets it as the new display item
function ItemsTabClass:CreateDisplayItemFromRaw(itemRaw, normalise)
	local newItem = new("Item", itemRaw)
	if newItem.base then
		if normalise then
			newItem:NormaliseQuality()
			newItem:BuildModList()
		end
		self:SetDisplayItem(newItem)
	end
end

-- Sets the display item to the given item
function ItemsTabClass:SetDisplayItem(item)
	self.displayItem = item
	if item then
		-- Update the display item controls
		self:UpdateDisplayItemTooltip()
		self.snapHScroll = "RIGHT"

		if item.crafted then
			self:UpdateAffixControls()
		end

		self:UpdateCustomControls()
		self:UpdateDisplayItemRangeLines()
	else
		self.snapHScroll = "LEFT"
	end
end

function ItemsTabClass:UpdateDisplayItemTooltip()
	self.displayItemTooltip:Clear()
	self:AddItemTooltip(self.displayItemTooltip, self.displayItem)
	self.displayItemTooltip.center = false
end

-- Update affix selection controls
function ItemsTabClass:UpdateAffixControls()
	local item = self.displayItem
	for i = 1, item.affixLimit/2 do
		self:UpdateAffixControl(self.controls["displayItemAffix"..i], item, "Prefix", "prefixes", i)
		self:UpdateAffixControl(self.controls["displayItemAffix"..(i+item.affixLimit/2)], item, "Suffix", "suffixes", i)
	end
	-- The custom affixes may have had their indexes changed, so the custom control UI is also rebuilt so that it will
	-- reference the correct affix index.
	self:UpdateCustomControls()
end

function ItemsTabClass:UpdateAffixControl(control, item, type, outputTable, outputIndex)
	local extraTags = { }
	local excludeGroups = { }
	for _, table in ipairs({"prefixes","suffixes"}) do
		for index = 1, item.affixLimit/2 do
			if index ~= outputIndex or table ~= outputTable then
				local mod = item.affixes[item[table][index] and item[table][index].modId]
				if mod then
					if mod.group then
						excludeGroups[mod.group] = true
					end
					if mod.tags then
						for _, tag in ipairs(mod.tags) do
							extraTags[tag] = true
						end
					end
				end
			end
		end
	end
	local affixList = { }
	for modId, mod in pairs(item.affixes) do
		if mod.type == type and not excludeGroups[mod.group] then
			t_insert(affixList, modId)
		end
	end
	table.sort(affixList, function(a, b)
		local modA = item.affixes[a]
		local modB = item.affixes[b]
		for i = 1, m_max(#modA, #modB) do
			if not modA[i] then
				return true
			elseif not modB[i] then
				return false
			elseif modA.statOrder[i] ~= modB.statOrder[i] then
				return modA.statOrder[i] < modB.statOrder[i]
			end
		end
		return modA.tier > modB.tier
	end)
	control.selIndex = 1
	control.list = { "None" }
	control.outputTable = outputTable
	control.outputIndex = outputIndex
	control.slider.shown = false
	control.slider.val = main.defaultItemAffixQuality / 256 or 0
	local selAffix = item[outputTable][outputIndex].modId
	local lastSeries
	for _, modId in ipairs(affixList) do
		local mod = item.affixes[modId]
		if not lastSeries or lastSeries.statOrderKey ~= mod.statOrderKey then
			local modString = table.concat(mod, "/")
			lastSeries = {
				label = modString,
				modList = { },
				haveRange = modString:match("%(%-?[%d%.]+%-%-?[%d%.]+%)"),
				statOrderKey = mod.statOrderKey,
			}
			t_insert(control.list, lastSeries)
		end
		if selAffix == modId then
			control.selIndex = #control.list
		end
		t_insert(lastSeries.modList, 1, modId)
		if #lastSeries.modList == 2 then
			lastSeries.label = lastSeries.label:gsub("%(%-?[%d%.]+%-%-?[%d%.]+%)","#"):gsub("%-?%d+%.?%d*","#")
			lastSeries.haveRange = true
		end
	end
	if control.list[control.selIndex].haveRange then
		control.slider.divCount = #control.list[control.selIndex].modList
		control.slider.val = (isValueInArray(control.list[control.selIndex].modList, selAffix) - 1 + (item[outputTable][outputIndex].range / 256 or 0)) / control.slider.divCount
		if control.slider.divCount == 1 then
			control.slider.divCount = nil
		end
		control.slider.shown = true
	end
end

-- Create/update custom modifier controls
function ItemsTabClass:UpdateCustomControls()
	local item = self.displayItem
	local i = 1
	local modLines = copyTable(item.explicitModLines)
	if item.rarity == "MAGIC" or item.rarity == "RARE" then
		for index, modLine in ipairs(modLines) do
			if modLine.custom or modLine.crafted then
				local line = itemLib.formatModLine(modLine)
				if line then
					if not self.controls["displayItemCustomModifierRemove"..i] then
						self.controls["displayItemCustomModifierRemove"..i] = new("ButtonControl", {"TOPLEFT",self.controls.displayItemSectionCustom,"TOPLEFT"}, 0, i * 22 + 4, 70, 20, "^7Remove")
						self.controls["displayItemCustomModifier"..i] = new("LabelControl", {"LEFT",self.controls["displayItemCustomModifierRemove"..i],"RIGHT"}, 65, 0, 0, 16)
						self.controls["displayItemCustomModifierLabel"..i] = new("LabelControl", {"LEFT",self.controls["displayItemCustomModifierRemove"..i],"RIGHT"}, 5, 0, 0, 16)
					end
					self.controls["displayItemCustomModifierRemove"..i].shown = true
					local label = itemLib.formatModLine(modLine)
					if DrawStringCursorIndex(16, "VAR", label, 330, 10) < #label then
						label = label:sub(1, DrawStringCursorIndex(16, "VAR", label, 310, 10)) .. "..."
					end
					self.controls["displayItemCustomModifier"..i].label = label
					self.controls["displayItemCustomModifierLabel"..i].label = modLine.crafted and " ^7Crafted:" or " ^7Custom:"
					self.controls["displayItemCustomModifierRemove"..i].onClick = function()
						t_remove(item.explicitModLines, index)
						item:BuildAndParseRaw()
						local id = item.id
						self:CreateDisplayItemFromRaw(item:BuildRaw())
						self.displayItem.id = id
					end
					i = i + 1
				end
			end
		end
	end
	item.customCount = i - 1
	while self.controls["displayItemCustomModifierRemove"..i] do
		self.controls["displayItemCustomModifierRemove"..i].shown = false
		i = i + 1
	end
end

-- Updates the range line dropdown and range slider for the current display item
function ItemsTabClass:UpdateDisplayItemRangeLines()
	if self.displayItem and self.displayItem.rangeLineList[1] then
		wipeTable(self.controls.displayItemRangeLine.list)
		for _, modLine in ipairs(self.displayItem.rangeLineList) do
			t_insert(self.controls.displayItemRangeLine.list, modLine.line)
		end
		self.controls.displayItemRangeLine.selIndex = 1
		self.controls.displayItemRangeSlider.val = self.displayItem.rangeLineList[1].range / 256
	end
end

local function checkLineForAllocates(line, nodes)
	if nodes and string.match(line, "Allocates") then
		local nodeId = tonumber(string.match(line, "%d+"))
		if nodes[nodeId] then
			return "Allocates "..nodes[nodeId].name
		end
	end
	return line
end

function ItemsTabClass:AddModComparisonTooltip(tooltip, mod)
	local slotName = self.displayItem:GetPrimarySlot()
	local newItem = new("Item", self.displayItem:BuildRaw())

	for _, subMod in ipairs(mod) do
		t_insert(newItem.explicitModLines, { line = checkLineForAllocates(subMod, self.build.spec.nodes), modTags = mod.modTags, [mod.type] = true })
	end

	newItem:BuildAndParseRaw()

	local calcFunc = self.build.calcsTab:GetMiscCalculator()
	local storedGlobalCacheDPSView = GlobalCache.useFullDPS
	GlobalCache.useFullDPS = GlobalCache.numActiveSkillInFullDPS > 0
	local outputBase = calcFunc({ repSlotName = slotName, repItem = self.displayItem }, {})
	local outputNew = calcFunc({ repSlotName = slotName, repItem = newItem }, {})
	GlobalCache.useFullDPS = storedGlobalCacheDPSView
	self.build:AddStatComparesToTooltip(tooltip, outputBase, outputNew, "\nAdding this mod will give: ")
end

-- Returns the first slot in which the given item is equipped
function ItemsTabClass:GetEquippedSlotForItem(item)
	for _, slot in ipairs(self.orderedSlots) do
		if not slot.inactive then
			if slot.selItemId == item.id then
				return slot
			end
			for _, itemSetId in ipairs(self.itemSetOrderList) do
				local itemSet = self.itemSets[itemSetId]
				if itemSetId ~= self.activeItemSetId and itemSet[slot.slotName] and itemSet[slot.slotName].selItemId == item.id then
					return slot, itemSet
				end
			end
		end
	end
end

-- Check if the given item could be equipped in the given slot, taking into account possible conflicts with currently equipped items
-- For example, a shield is not valid for Weapon 2 if Weapon 1 is a staff, and a wand is not valid for Weapon 2 if Weapon 1 is a dagger
function ItemsTabClass:IsItemValidForSlot(item, slotName, itemSet)
	itemSet = itemSet or self.activeItemSet
	local slotType, slotId = slotName:match("^([%a ]+) (%d+)$")
	if not slotType then
		slotType = slotName
	end
	if item.type == slotType then
		return true
	elseif item.type == "Blessing" and item.base and item.base.timeline then
		return slotName == item.base.timeline
	elseif slotType == "Idol" then
		if not item.type:match("Idol$") then return false end
		-- Size overflow check: verify the idol's cell footprint stays within valid grid cells
		local size = idolSize[item.type]
		local pos  = idolSlotPos[slotName]
		if size and pos then
			for dr = 0, size[2] - 1 do
				for dc = 0, size[1] - 1 do
					local row = IDOL_GRID_LAYOUT[pos[1] + dr]
					if not row or not row[pos[2] + dc] then return false end
				end
			end
		end
		return true
	elseif slotType == "Omen Idol" then
		return item.type ~= nil and item.type:match("Idol$") ~= nil
	elseif slotName == "Weapon 1" or slotName == "Weapon 1 Swap" or slotName == "Weapon" then
		return item.base.weapon ~= nil
	elseif slotName == "Weapon 2" or slotName == "Weapon 2 Swap" then
		local weapon1Sel = itemSet[slotName == "Weapon 2" and "Weapon 1" or "Weapon 1 Swap"].selItemId or 0
		local weapon1Type = self.items[weapon1Sel] and self.items[weapon1Sel].base.type or "None"
		if weapon1Type == "None" then
			return item.type == "Shield" or item.type == "Off-Hand Catalyst" or (self.build.data.weaponTypeInfo[item.type] and self.build.data.weaponTypeInfo[item.type].oneHand)
		elseif weapon1Type == "Bow" then
			return item.type == "Quiver"
		elseif self.build.data.weaponTypeInfo[weapon1Type].oneHand then
			return item.type == "Shield" or item.type == "Off-Hand Catalyst" or (self.build.data.weaponTypeInfo[item.type] and self.build.data.weaponTypeInfo[item.type].oneHand)
		end
	end
end

-- Opens the item set manager
function ItemsTabClass:OpenItemSetManagePopup()
	local controls = { }
	controls.setList = new("ItemSetListControl", nil, -155, 50, 300, 200, self)
	controls.sharedList = new("SharedItemSetListControl", nil, 155, 50, 300, 200, self)
	controls.setList.dragTargetList = { controls.sharedList }
	controls.sharedList.dragTargetList = { controls.setList }
	controls.close = new("ButtonControl", nil, 0, 260, 90, 20, "Done", function()
		main:ClosePopup()
	end)
	main:OpenPopup(630, 290, "Manage Item Sets", controls)
end

function ItemsTabClass:SetAllItemRanges(range)
	for _, item in pairs(self.items) do
		for _, rangeLine in pairs(item.rangeLineList) do
			rangeLine.range = range
		end
		for _, rangeLine in pairs(item.prefixes) do
			rangeLine.range = range
		end
		for _, rangeLine in pairs(item.suffixes) do
			rangeLine.range = range
		end
		item:BuildAndParseRaw()
	end
	if self.displayItem then
		self:UpdateDisplayItemTooltip()
		self:UpdateCustomControls()
	end
	self.build.buildFlag = true
end

-- Opens the item crafting popup
function ItemsTabClass:CraftItem()
	local controls = { }
	local function makeItem(base)
		local item = new("Item")
		item.name = base.name
		item.base = base.base
		item.baseName = base.name
		item.buffModLines = { }
		item.enchantModLines = { }
		item.classRequirementModLines = { }
		item.implicitModLines = { }
		item.explicitModLines = { }
		item.quality = 0
		local raritySel = controls.rarity.selIndex
		if raritySel == 2 or raritySel == 3 then
			item.crafted = true
		end
		item.rarity = controls.rarity.list[raritySel].rarity
		if raritySel >= 3 then
			item.title = controls.title.buf:match("%S") and controls.title.buf or "New Item"
		end
		if base.base.implicits then
			local implicitIndex = 1
			for _,line in ipairs(base.base.implicits) do
				t_insert(item.implicitModLines, { line = line})
				implicitIndex = implicitIndex + 1
			end
		end
		item:NormaliseQuality()
		item:BuildAndParseRaw()
		return item
	end
	controls.rarityLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 50, 20, 0, 16, "Rarity:")
	controls.rarity = new("DropDownControl", nil, -80, 20, 100, 18, rarityDropList)
	controls.rarity.selIndex = self.lastCraftRaritySel or 3
	controls.title = new("EditControl", nil, 70, 20, 190, 18, "", "Name")
	controls.title.shown = function()
		return controls.rarity.selIndex >= 3
	end
	controls.typeLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 50, 45, 0, 16, "Type:")
	controls.type = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, 55, 45, 295, 18, self.build.data.itemBaseTypeList, function(index, value)
		controls.base.list = self.build.data.itemBaseLists[self.build.data.itemBaseTypeList[index]]
		controls.base.selIndex = 1
	end)
	controls.type.selIndex = self.lastCraftTypeSel or 1
	controls.baseLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 50, 70, 0, 16, "Base:")
	controls.base = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, 55, 70, 200, 18, self.build.data.itemBaseLists[self.build.data.itemBaseTypeList[controls.type.selIndex]])
	controls.base.selIndex = self.lastCraftBaseSel or 1
	controls.base.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode ~= "OUT" then
			self:AddItemTooltip(tooltip, makeItem(value), nil, true)
		end
	end
	controls.save = new("ButtonControl", nil, -45, 100, 80, 20, "Create", function()
		main:ClosePopup()
		local item = makeItem(controls.base.list[controls.base.selIndex])
		self:SetDisplayItem(item)
		if not item.crafted and item.rarity ~= "NORMAL" then
			self:EditDisplayItemText()
		end
		self.lastCraftRaritySel = controls.rarity.selIndex
		self.lastCraftTypeSel = controls.type.selIndex
		self.lastCraftBaseSel = controls.base.selIndex
	end)
	controls.cancel = new("ButtonControl", nil, 45, 100, 80, 20, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(370, 130, "Craft Item", controls)
end

-- Opens the item text editor popup
function ItemsTabClass:EditDisplayItemText(alsoAddItem)
	local controls = { }
	local function buildRaw()
		local editBuf = controls.edit.buf
		if editBuf:match("^Item Class: .*\nRarity: ") or editBuf:match("^Rarity: ") then
			return editBuf
		else
			return "Rarity: "..controls.rarity.list[controls.rarity.selIndex].rarity.."\n"..controls.edit.buf
		end
	end
	controls.rarity = new("DropDownControl", nil, -190, 10, 100, 18, rarityDropList)
	controls.edit = new("EditControl", nil, 0, 40, 480, 420, "", nil, "^%C\t\n", nil, nil, 14)
	if self.displayItem then
		controls.edit:SetText(self.displayItem:BuildRaw():gsub("Rarity: %w+\n",""))
		controls.rarity:SelByValue(self.displayItem.rarity, "rarity")
	else
		controls.rarity.selIndex = 3
	end
	controls.edit.font = "FIXED"
	controls.edit.pasteFilter = sanitiseText
	controls.save = new("ButtonControl", nil, -45, 470, 80, 20, self.displayItem and "Save" or "Create", function()
		local id = self.displayItem and self.displayItem.id
		self:CreateDisplayItemFromRaw(buildRaw(), not self.displayItem)
		self.displayItem.id = id
		if alsoAddItem then
			self:AddDisplayItem()
		end
		main:ClosePopup()
	end, nil, true)
	controls.save.enabled = function()
		local item = new("Item", buildRaw())
		return item.base ~= nil
	end
	controls.save.tooltipFunc = function(tooltip)
		tooltip:Clear()
		local item = new("Item", buildRaw())
		if item.base then
			self:AddItemTooltip(tooltip, item, nil, true)
		else
			tooltip:AddLine(14, "The item is invalid.")
			tooltip:AddLine(14, "Check that the item's title and base name are in the correct format.")
			tooltip:AddLine(14, "For Rare and Unique items, the first 2 lines must be the title and base name. E.g.:")
			tooltip:AddLine(14, "Abberath's Horn")
			tooltip:AddLine(14, "Goat's Horn")
			tooltip:AddLine(14, "For Normal and Magic items, the base name must be somewhere in the first line. E.g.:")
			tooltip:AddLine(14, "Scholar's Platinum Kris of Joy")
		end
	end
	controls.cancel = new("ButtonControl", nil, 45, 470, 80, 20, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(500, 500, self.displayItem and "Edit Item Text" or "Create Custom Item from Text", controls, nil, "edit")
end

-- Opens the item enchanting popup
function ItemsTabClass:EnchantDisplayItem(enchantSlot)
	self.enchantSlot = enchantSlot or 1

	local controls = { }
	local enchantments = self.displayItem.enchantments
	local haveSkills = true
	for _, source in ipairs(self.build.data.enchantmentSource) do
		if self.displayItem.enchantments[source.name] then
			haveSkills = false
			break
		end
	end
	local skillList = { }
	local skillsUsed = { }
	if haveSkills then
		for _, socketGroup in pairs(self.build.skillsTab.socketGroupList) do
			for _, gemInstance in ipairs(socketGroup.gemList) do
				if gemInstance.gemData then
					for _, grantedEffect in ipairs(gemInstance.gemData.grantedEffectList) do
						if not grantedEffect.support and enchantments[grantedEffect.name] then
							skillsUsed[grantedEffect.name] = true
						end
					end
				end
			end
		end
	end
	local function buildSkillList(onlyUsedSkills)
		wipeTable(skillList)
		for skillName in pairs(enchantments) do
			if not onlyUsedSkills or not next(skillsUsed) or skillsUsed[skillName] then
				t_insert(skillList, skillName)
			end
		end
		table.sort(skillList)
	end
	local enchantmentSourceList = { }
	local function buildEnchantmentSourceList()
		wipeTable(enchantmentSourceList)
		local list = haveSkills and enchantments[skillList[controls.skill and controls.skill.selIndex or 1]] or enchantments
		for _, source in ipairs(self.build.data.enchantmentSource) do
			if list[source.name] then
				t_insert(enchantmentSourceList, source)
			end
		end
	end
	local enchantmentList = { }
	local function buildEnchantmentList()
		wipeTable(enchantmentList)
		local list = haveSkills and enchantments[skillList[controls.skill and controls.skill.selIndex or 1]] or enchantments
		for _, enchantment in ipairs(list[enchantmentSourceList[controls.enchantmentSource and controls.enchantmentSource.selIndex or 1].name]) do
			t_insert(enchantmentList, enchantment)
		end
	end
	if haveSkills then
		buildSkillList(true)
	end
	buildEnchantmentSourceList()
	buildEnchantmentList()
	local function enchantItem(idx, remove)
		local item = new("Item", self.displayItem:BuildRaw())
		local index = idx or controls.enchantment.selIndex
		item.id = self.displayItem.id
		local list = haveSkills and enchantments[controls.skill.list[controls.skill.selIndex]] or enchantments
		local line = list[controls.enchantmentSource.list[controls.enchantmentSource.selIndex].name][index]
		local first, second = line:match("([^/]+)/([^/]+)")
		if remove then
			t_remove(item.enchantModLines, self.enchantSlot)
		elseif first then
			item.enchantModLines = { { crafted = true, line = first }, { crafted = true, line = second } }
		else
			if not item.canHaveTwoEnchants and #item.enchantModLines > 1 then
				item.enchantModLines = { item.enchantModLines[1] }
			end
			if #item.enchantModLines >= self.enchantSlot then
				t_remove(item.enchantModLines, self.enchantSlot)
			end
			t_insert(item.enchantModLines, self.enchantSlot, { crafted = true, line = line})
		end
		item:BuildAndParseRaw()
		return item
	end
	if haveSkills then
		controls.skillLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 95, 20, 0, 16, "^7Skill:")
		controls.skill = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, 100, 20, 180, 18, skillList, function(index, value)
			buildEnchantmentSourceList()
			buildEnchantmentList()
			controls.enchantment:SetSel(1)
		end)
		controls.allSkills = new("CheckBoxControl", {"TOPLEFT",nil,"TOPLEFT"}, 350, 20, 18, "All skills:", function(state)
			buildSkillList(not state)
			controls.skill:SetSel(1)
			buildEnchantmentList()
			controls.enchantment:SetSel(1)
		end)
		controls.allSkills.tooltipText = "Show all skills, not just those used by this build."
		if not next(skillsUsed) then
			controls.allSkills.state = true
			controls.allSkills.enabled = false
		end
	end
	controls.enchantmentSourceLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 95, 45, 0, 16, "^7Source:")
	controls.enchantmentSource = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, 100, 45, 180, 18, enchantmentSourceList, function(index, value)
		buildEnchantmentList()
		controls.enchantment:SetSel(m_min(controls.enchantment.selIndex, #enchantmentList))
	end)
	controls.enchantmentLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 95, 70, 0, 16, "^7Enchantment:")
	controls.enchantment = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, 100, 70, 440, 18, enchantmentList)
	controls.enchantment.tooltipFunc = function(tooltip, mode, index)
		tooltip:Clear()
		self:AddItemTooltip(tooltip, enchantItem(index), nil, true)
	end
	controls.save = new("ButtonControl", nil, -88, 100, 80, 20, "Enchant", function()
		self:SetDisplayItem(enchantItem())
		main:ClosePopup()
	end)
	controls.remove = new("ButtonControl", nil, 0, 100, 80, 20, "Remove", function()
		self:SetDisplayItem(enchantItem(nil, true))
		main:ClosePopup()
	end)
	controls.close = new("ButtonControl", nil, 88, 100, 80, 20, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(550, 130, "Enchant Item", controls)
end

---Appends tooltip with information about added notable passive node if it would be allocated.
---@param tooltip table @The tooltip to append into
---@param node table @The passive tree node that will be added
function ItemsTabClass:AppendAddedNotableTooltip(tooltip, node)
	local storedGlobalCacheDPSView = GlobalCache.useFullDPS
	GlobalCache.useFullDPS = GlobalCache.numActiveSkillInFullDPS > 0
	local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator()
	local outputNew = calcFunc({ addNodes = { [node] = true } }, { requirementsItems = true, requirementsGems = true, skills = true })
	GlobalCache.useFullDPS = storedGlobalCacheDPSView
	local numChanges = self.build:AddStatComparesToTooltip(tooltip, calcBase, outputNew, "^7Allocating "..node.dn.." will give you: ")
	if numChanges == 0 then
		tooltip:AddLine(14, "^7Allocating "..node.dn.." changes nothing.")
	end
end

-- Opens the custom modifier popup
function ItemsTabClass:AddCustomModifierToDisplayItem()
	local controls = { }
	local sourceList = { }
	local modList = { }
	---Mutates modList to contain mods from the specified source
	---@param sourceId string @The crafting source id to build the list of mods for
	local function buildMods(sourceId)
		wipeTable(modList)
		if sourceId == "MASTER" then
			local excludeGroups = { }
			for _, modLine in ipairs({ self.displayItem.prefixes, self.displayItem.suffixes }) do
				for i = 1, self.displayItem.affixLimit / 2 do
					if modLine[i].modId ~= "None" then
						excludeGroups[self.displayItem.affixes[modLine[i].modId].group] = true
					end
				end
			end
			for i, craft in ipairs(self.build.data.masterMods) do
				if craft.types[self.displayItem.type] and not excludeGroups[craft.group] then
					t_insert(modList, {
						label = table.concat(craft, "/") .. " ^8(" .. craft.type .. ")",
						mod = craft,
						type = "crafted",
						affixType = craft.type,
						defaultOrder = i,
					})
				end
			end
			table.sort(modList, function(a, b)
				if a.affixType ~= b.affixType then
					return a.affixType == "Prefix" and b.affixType == "Suffix"
				else
					return a.defaultOrder < b.defaultOrder
				end
			end)
		elseif sourceId == "PREFIX" or sourceId == "SUFFIX" then
			for _, mod in pairs(self.displayItem.affixes) do
				if sourceId:lower() == mod.type:lower() and self.displayItem:GetModSpawnWeight(mod) > 0 then
					t_insert(modList, {
						label = mod.affix .. "   ^8[" .. table.concat(mod, "/") .. "]",
						mod = mod,
						type = "custom",
					})
				end
			end
			table.sort(modList, function(a, b)
				local modA = a.mod
				local modB = b.mod
				for i = 1, m_max(#modA, #modB) do
					if not modA[i] then
						return true
					elseif not modB[i] then
						return false
					elseif modA.statOrder[i] ~= modB.statOrder[i] then
						return modA.statOrder[i] < modB.statOrder[i]
					end
				end
				return modA.level > modB.level
			end)
		elseif sourceId == "VEILED" then
			for i, mod in pairs(self.build.data.veiledMods) do
				if self.displayItem:GetModSpawnWeight(mod) > 0 then
					t_insert(modList, {
						label = table.concat(mod, "/") .. " (" .. mod.type .. ")",
						mod = mod,
						affixType = mod.type,
						type = "custom",
						defaultOrder = i,
					})
				end
			end
			table.sort(modList, function(a, b)
				if a.affixType ~= b.affixType then
					return a.affixType == "Prefix" and b.affixType == "Suffix"
				else
					return a.defaultOrder < b.defaultOrder
				end
			end)
		elseif sourceId == "DELVE" then
			for i, mod in pairs(self.displayItem.affixes) do
				if self.displayItem:CheckIfModIsDelve(mod) and self.displayItem:GetModSpawnWeight(mod) > 0 then
					t_insert(modList, {
						label = table.concat(mod, "/") .. " (" .. mod.type .. ")",
						mod = mod,
						affixType = mod.type,
						type = "custom",
						defaultOrder = i,
					})
				end
			end
			table.sort(modList, function(a, b)
				if a.affixType ~= b.affixType then
					return a.affixType == "Prefix" and b.affixType == "Suffix"
				else
					return a.defaultOrder < b.defaultOrder
				end
			end)
		end
	end
		t_insert(sourceList, { label = "Prefix", sourceId = "PREFIX" })
		t_insert(sourceList, { label = "Suffix", sourceId = "SUFFIX" })
	t_insert(sourceList, { label = "Custom", sourceId = "CUSTOM" })
	buildMods(sourceList[1].sourceId)
	local function addModifier()
		local item = new("Item", self.displayItem:BuildRaw())
		item.id = self.displayItem.id
		local sourceId = sourceList[controls.source.selIndex].sourceId
		if sourceId == "CUSTOM" then
			if controls.custom.buf:match("%S") then
				t_insert(item.explicitModLines, { line = controls.custom.buf, custom = true })
			end
		else
			local listMod = modList[controls.modSelect.selIndex]
			for _, line in ipairs(listMod.mod) do
				t_insert(item.explicitModLines, { line = line, modTags = listMod.mod.modTags, [listMod.type] = true })
			end
		end
		item:BuildAndParseRaw()
		return item
	end
	controls.sourceLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 95, 20, 0, 16, "^7Source:")
	controls.source = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, 100, 20, 150, 18, sourceList, function(index, value)
		buildMods(value.sourceId)
		controls.modSelect:SetSel(1)
	end)
	controls.source.enabled = #sourceList > 1
	controls.modSelectLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 95, 45, 0, 16, "^7Modifier:")
	controls.modSelect = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, 100, 45, 600, 18, modList)
	controls.modSelect.shown = function()
		return sourceList[controls.source.selIndex].sourceId ~= "CUSTOM"
	end
	controls.modSelect.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode ~= "OUT" and value then
			for _, line in ipairs(value.mod) do
				tooltip:AddLine(16, "^7"..line)
			end
			self:AddModComparisonTooltip(tooltip, value.mod)
		end
	end
	controls.custom = new("EditControl", {"TOPLEFT",nil,"TOPLEFT"}, 100, 45, 440, 18)
	controls.custom.shown = function()
		return sourceList[controls.source.selIndex].sourceId == "CUSTOM"
	end
	controls.save = new("ButtonControl", nil, -45, 75, 80, 20, "Add", function()
		self:SetDisplayItem(addModifier())
		main:ClosePopup()
	end)
	controls.save.tooltipFunc = function(tooltip)
		tooltip:Clear()
		self:AddItemTooltip(tooltip, addModifier())
	end
	controls.close = new("ButtonControl", nil, 45, 75, 80, 20, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(710, 105, "Add Modifier to Item", controls, "save", sourceList[controls.source.selIndex].sourceId == "CUSTOM" and "custom")
end

-- Opens the custom Implicit popup
function ItemsTabClass:AddImplicitToDisplayItem()
	local controls = { }
	local sourceList = { }
	local modList = { }
	local modGroups = {}
	---Mutates modList to contain mods from the specified source
	---@param sourceId string @The crafting source id to build the list of mods for
	t_insert(sourceList, { label = "Custom", sourceId = "CUSTOM" })
	local function addModifier()
		local item = new("Item", self.displayItem:BuildRaw())
		item.id = self.displayItem.id
		local sourceId = sourceList[controls.source.selIndex].sourceId
		if sourceId == "CUSTOM" then
			if controls.custom.buf:match("%S") then
				t_insert(item.implicitModLines, { line = controls.custom.buf, custom = true })
			end
		else
			local listMod = modList[modGroups[controls.modGroupSelect.selIndex].modListIndex][controls.modSelect.selIndex]
			for _, line in ipairs(listMod.mod) do
				t_insert(item.implicitModLines, { line = line, modTags = listMod.mod.modTags, [listMod.type] = true })
			end
		end
		item:BuildAndParseRaw()
		return item
	end
	controls.sourceLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 95, 20, 0, 16, "^7Source:")
	controls.source = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, 100, 20, 150, 18, sourceList, function(index, value)
		if value.sourceId ~= "CUSTOM" then
			controls.modSelectLabel.y = 70
			buildMods(value.sourceId)
			controls.modGroupSelect:SetSel(1)
			controls.modSelect.list = modList[modGroups[1].modListIndex]
			controls.modSelect:SetSel(1)
		else
			controls.modSelectLabel.y = 45
		end
	end)
	controls.source.enabled = #sourceList > 1
	controls.modGroupSelectLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 95, 45, 0, 16, "^7Type:")
	controls.modGroupSelect = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, 100, 45, 600, 18, modGroups, function(index, value)
		controls.modSelect.list = modList[value.modListIndex]
		controls.modSelect:SetSel(1)
	end)
	controls.modGroupSelectLabel.shown = function()
		if sourceList[controls.source.selIndex].sourceId == "CUSTOM" then
			controls.modSelectLabel.y = 45
		end
		return sourceList[controls.source.selIndex].sourceId ~= "CUSTOM"
	end
	controls.modGroupSelect.shown = function()
		return sourceList[controls.source.selIndex].sourceId ~= "CUSTOM"
	end
	controls.modGroupSelect.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode ~= "OUT" and value then
			for _, line in ipairs(value.mod) do
				tooltip:AddLine(16, "^7"..line)
			end
			self:AddModComparisonTooltip(tooltip, value.mod)
		end
	end
	controls.modSelectLabel = new("LabelControl", {"TOPRIGHT",nil,"TOPLEFT"}, 95, 70, 0, 16, "^7Modifier:")
	controls.modSelect = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, 100, 70, 600, 18, sourceList[controls.source.selIndex].sourceId ~= "CUSTOM" and modList[modGroups[1].modListIndex] or { })
	controls.modSelect.shown = function()
		return sourceList[controls.source.selIndex].sourceId ~= "CUSTOM"
	end
	controls.modSelect.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode ~= "OUT" and value then
			for _, line in ipairs(value.mod) do
				tooltip:AddLine(16, "^7"..line)
			end
			self:AddModComparisonTooltip(tooltip, value.mod)
		end
	end
	controls.custom = new("EditControl", {"TOPLEFT",nil,"TOPLEFT"}, 100, 45, 440, 18)
	controls.custom.shown = function()
		return sourceList[controls.source.selIndex].sourceId == "CUSTOM"
	end
	controls.save = new("ButtonControl", nil, -45, 100, 80, 20, "Add", function()
		self:SetDisplayItem(addModifier())
		main:ClosePopup()
	end)
	controls.save.tooltipFunc = function(tooltip)
		tooltip:Clear()
		self:AddItemTooltip(tooltip, addModifier())
	end
	controls.close = new("ButtonControl", nil, 45, 100, 80, 20, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(710, 130, "Add Implicit to Item", controls, "save", sourceList[controls.source.selIndex].sourceId == "CUSTOM" and "custom")
end

function ItemsTabClass:AddItemSetTooltip(tooltip, itemSet)
	for _, slot in ipairs(self.orderedSlots) do
		if not slot.nodeId then
			local item = self.items[itemSet[slot.slotName].selItemId]
			if item then
				tooltip:AddLine(16, s_format("^7%s: %s%s", slot.label, colorCodes[item.rarity], item.name))
			end
		end
	end
end

function ItemsTabClass:FormatItemSource(text)
	return text:gsub("unique{([^}]+)}",colorCodes.UNIQUE.."%1"..colorCodes.SOURCE)
			   :gsub("normal{([^}]+)}",colorCodes.NORMAL.."%1"..colorCodes.SOURCE)
			   :gsub("currency{([^}]+)}",colorCodes.CURRENCY.."%1"..colorCodes.SOURCE)
			   :gsub("prophecy{([^}]+)}",colorCodes.PROPHECY.."%1"..colorCodes.SOURCE)
end

function ItemsTabClass:AddItemTooltip(tooltip, item, slot, dbMode)
	-- Item name
	local rarityCode = colorCodes[item.rarity]
	tooltip.center = true
	tooltip.color = rarityCode
	if item.title then
		tooltip:AddLine(20, rarityCode..item.title)
		tooltip:AddLine(20, rarityCode..item.baseName:gsub(" %(.+%)",""))
	else
		tooltip:AddLine(20, rarityCode..item.namePrefix..item.baseName:gsub(" %(.+%)","")..item.nameSuffix)
	end
	for _, curInfluenceInfo in ipairs(influenceInfo) do
		if item[curInfluenceInfo.key] then
			tooltip:AddLine(16, curInfluenceInfo.color..curInfluenceInfo.display.." Item")
		end
	end
	if item.fractured then
		tooltip:AddLine(16, colorCodes.FRACTURED.."Fractured Item")
	end
	if item.synthesised then
		tooltip:AddLine(16, colorCodes.CRAFTED.."Synthesised Item")
	end
	tooltip:AddSeparator(10)

	-- Special fields for database items
	if dbMode then
		if item.variantList then
			if #item.variantList == 1 then
				tooltip:AddLine(16, "^xFFFF30Variant: "..item.variantList[1])
			else
				tooltip:AddLine(16, "^xFFFF30Variant: "..item.variantList[item.variant].." ("..#item.variantList.." variants)")
			end
		end
		if item.league then
			tooltip:AddLine(16, "^xFF5555Exclusive to: "..item.league)
		end
		if item.unreleased then
			tooltip:AddLine(16, colorCodes.NEGATIVE.."Not yet available")
		end
		if item.source then
			tooltip:AddLine(16, colorCodes.SOURCE.."Source: "..self:FormatItemSource(item.source))
		end
		if item.upgradePaths then
			for _, path in ipairs(item.upgradePaths) do
				tooltip:AddLine(16, colorCodes.SOURCE..self:FormatItemSource(path))
			end
		end
		tooltip:AddSeparator(10)
	end

	local base = item.base
	local slotNum = slot and slot.slotNum or (IsKeyDown("SHIFT") and 2 or 1)
	local modList = item.modList or item.slotModList[slotNum]
	if base.weapon then
		-- Weapon-specific info
		tooltip:AddLine(16, s_format("^x7F7F7F%s", self.build.data.weaponTypeInfo[base.type].label or base.type))
		tooltip:AddLine(16, s_format("^x7F7F7FAttacks per Second: %s%.2f", "^7", base.weapon.AttackRateBase))
		tooltip:AddLine(16, s_format("^x7F7F7FWeapon Range: %s%.1f ^x7F7F7Fmetres", "^7", base.weapon.Range))
	end

	tooltip:AddSeparator(10)

	-- Requirements
	self.build:AddRequirementsToTooltip(tooltip, item.requirements.level,
		item.requirements.strMod, item.requirements.dexMod, item.requirements.intMod,
		item.requirements.str or 0, item.requirements.dex or 0, item.requirements.int or 0)

	-- Modifiers
	for _, modList in ipairs{item.enchantModLines, item.implicitModLines, item.explicitModLines} do
		if modList[1] then
			for _, modLine in ipairs(modList) do
				if item:CheckModLineVariant(modLine) then
					tooltip:AddLine(16, itemLib.formatModLine(modLine, dbMode))
				end
			end
			tooltip:AddSeparator(10)
		end
	end

	-- Corrupted item label
	if item.mirrored then
		if #item.explicitModLines == 0 then
			tooltip:AddSeparator(10)
		end
		if item.mirrored then
			tooltip:AddLine(16, colorCodes.NEGATIVE.."Mirrored")
		end
	end
	tooltip:AddSeparator(14)

	-- Stat differences
	local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator()
	-- Build sorted list of slots to compare with
	local compareSlots = { }
	if base.type:find("Idol") or base.type:find("Blessing") then
		-- Idols and blessings slots should not be compared between each other (too many slots)
        if slot then
            t_insert(compareSlots, slot)
        end
    else
		for slotName, slot in pairs(self.slots) do
			if self:IsItemValidForSlot(item, slotName) and not slot.inactive and (not slot.weaponSet or slot.weaponSet == (self.activeItemSet.useSecondWeaponSet and 2 or 1)) then
				t_insert(compareSlots, slot)
			end
		end

	end
	table.sort(compareSlots, function(a, b)
		if a ~= b then
			if slot == a then
				return true
			end
			if slot == b then
				return false
			end
		end
		if a.selItemId ~= b.selItemId then
			if item == self.items[a.selItemId] then
				return true
			end
			if item == self.items[b.selItemId] then
				return false
			end
		end
		local aNum = tonumber(a.slotName:match("%d+"))
		local bNum = tonumber(b.slotName:match("%d+"))
		if aNum and bNum then
			return aNum < bNum
		else
			return a.slotName < b.slotName
		end
	end)

	-- Add comparisons for each slot
	for _, compareSlot in pairs(compareSlots) do
		if not main.slotOnlyTooltips or (slot and (slot.nodeId == compareSlot.nodeId or slot.slotName == compareSlot.slotName)) or not slot or slot == compareSlot then
			local selItem = self.items[compareSlot.selItemId]
			local storedGlobalCacheDPSView = GlobalCache.useFullDPS
			GlobalCache.useFullDPS = GlobalCache.numActiveSkillInFullDPS > 0
			local output = calcFunc({ repSlotName = compareSlot.slotName, repItem = item ~= selItem and item or nil }, {})
			GlobalCache.useFullDPS = storedGlobalCacheDPSView
			local slotLabel = compareSlot.label ~= "" and compareSlot.label or compareSlot.slotName
			local header
			if item == selItem then
				header = "^7Removing this item from " .. slotLabel .. " will give you:"
			else
				header = string.format("^7Equipping this item in %s will give you:%s", slotLabel, selItem and "\n(replacing " .. colorCodes[selItem.rarity] .. selItem.name .. "^7)" or "")
			end
			self.build:AddStatComparesToTooltip(tooltip, calcBase, output, header)
		end
	end

	if launch.devModeAlt then
		-- Modifier debugging info
		tooltip:AddSeparator(10)
		for _, mod in ipairs(modList) do
			tooltip:AddLine(14, "^7"..modLib.formatMod(mod))
		end
	end
end

function ItemsTabClass:CreateUndoState()
	local state = { }
	state.activeItemSetId = self.activeItemSetId
	state.items = { }
	for k, v in pairs(self.items) do
		state.items[k] = copyTableSafe(self.items[k], true, true)
	end
	state.itemOrderList = copyTable(self.itemOrderList)
	state.slotSelItemId = { }
	for slotName, slot in pairs(self.slots) do
		state.slotSelItemId[slotName] = slot.selItemId
	end
	state.itemSets = copyTableSafe(self.itemSets)
	state.itemSetOrderList = copyTable(self.itemSetOrderList)
	return state
end

function ItemsTabClass:RestoreUndoState(state)
	self.items = state.items
	wipeTable(self.itemOrderList)
	for k, v in pairs(state.itemOrderList) do
		self.itemOrderList[k] = v
	end
	for slotName, selItemId in pairs(state.slotSelItemId) do
		self.slots[slotName]:SetSelItemId(selItemId)
	end
	self.itemSets = state.itemSets
	wipeTable(self.itemSetOrderList)
	for k, v in pairs(state.itemSetOrderList) do
		self.itemSetOrderList[k] = v
	end
	self.activeItemSetId = state.activeItemSetId
	self.activeItemSet = self.itemSets[self.activeItemSetId]
	self:PopulateSlots()
end