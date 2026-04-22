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

local function itemDisplayColor(item)
	-- Idol Altar: always displayed with Exalted (purple) text/frame colour,
	-- regardless of the item's actual rarity.
	if item.type == "Idol Altar" then
		return colorCodes.EXALTED
	end
	if item.type and item.type:find("Idol") then
		if item.rarity == "UNIQUE" or item.rarity == "SET" or item.rarity == "LEGENDARY" then
			return colorCodes[item.rarity]
		end
		return colorCodes.IDOL
	end
	return colorCodes[item.rarity]
end

-- Lazy set data cache keyed by version, shared across tooltips.
local tooltipSetDataCache = {}
local function loadSetDataForTooltip(ver)
	ver = ver or "1_4"
	if tooltipSetDataCache[ver] == nil then
		tooltipSetDataCache[ver] = readJsonFile("Data/Set/set_" .. ver .. ".json")
			or readJsonFile("Data/Set/set_1_4.json")
			or false
	end
	return tooltipSetDataCache[ver] or nil
end

local rarityDropList = {
	{ label = colorCodes.NORMAL.."Normal", rarity = "NORMAL" },
	{ label = colorCodes.MAGIC.."Magic", rarity = "MAGIC" },
	{ label = colorCodes.RARE.."Rare", rarity = "RARE" },
	{ label = colorCodes.UNIQUE.."Unique", rarity = "UNIQUE" },
	{ label = colorCodes.EXALTED.."Exalted", rarity = "EXALTED" },
	{ label = colorCodes.LEGENDARY.."Legendary", rarity = "LEGENDARY" },
	{ label = colorCodes.SET.."Set", rarity = "SET" },
	{ label = colorCodes.WWUNIQUE.."WW Unique", rarity = "WWUNIQUE" },
	{ label = colorCodes.WWLEGENDARY.."WW Legendary", rarity = "WWLEGENDARY" },
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
	-- Sort toggle state: "category" or "equipment". Button label reflects the
	-- NEXT mode to apply, so clicking toggles and re-sorts.
	self.sortMode = "equipment"


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
	-- ===== IDOL ALTAR (S4) =====
	self.activeAltarLayout = "Default"
	do
		local altarSlot = new("ItemSlotControl", {"TOPLEFT",self.controls.specSelect,"BOTTOMLEFT"}, 0, 2, self, "Idol Altar", "Idol Altar")
		self.slots[altarSlot.slotName] = altarSlot
		t_insert(self.orderedSlots, altarSlot)
		self.slotOrder[altarSlot.slotName] = #self.orderedSlots
		t_insert(self.controls, altarSlot)
		self.controls.idolAltarSlot = altarSlot
		-- Wrap SetSelItemId to auto-update altar layout from equipped item
		local origSetSelItemId = altarSlot.SetSelItemId
		altarSlot.SetSelItemId = function(slot, selItemId)
			origSetSelItemId(slot, selItemId)
			local item = self.items[selItemId]
			if item and item.baseName and IDOL_ALTAR_LAYOUTS[item.baseName] then
				self.activeAltarLayout = item.baseName
			else
				self.activeAltarLayout = "Default"
			end
		end
	end
	self.controls.idolAltarTypeLabelRight = new("LabelControl", {"TOPLEFT",self.controls.idolAltarSlot,"BOTTOMLEFT"}, 0, 4, 200, 16, function()
		local item = self.items[self.controls.idolAltarSlot.selItemId]
		if item and item.baseName then
			return "^8" .. item.baseName
		end
		return ""
	end)
	self.controls.idolAltarTypeLabelLeft = new("LabelControl", {"RIGHT",self.controls.idolAltarTypeLabelRight,"LEFT"}, -2, 0, 0, 16, "^7Type:")
	local prevOmenSlot = self.controls.idolAltarTypeLabelRight
	for i = 1, MAX_OMEN_IDOL_SLOTS do
		local omenSlot = new("ItemSlotControl", {"TOPLEFT",prevOmenSlot,"BOTTOMLEFT"}, 0, 2, self, "Omen Idol " .. i, "Fractured " .. i)
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
				{name="Apex of Fortune", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Quiver Drop Rate", label="(15-30)% Inc. Quiver Drop%"},
				{name="Arrogance of Argentus", minVal=10.0, maxVal=20.0, implCount=1, impl1="(10-20)% Increased Helmet Drop Rate", label="(10-20)% Inc. Helmet Drop%"},
				{name="Binds of Sanctuary", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Shield Drop Rate", label="(15-30)% Inc. Shield Drop%"},
				{name="Embrace of Ice", minVal=10.0, maxVal=20.0, implCount=1, impl1="(10-20)% Increased Body Armor Drop Rate", label="(10-20)% Inc. Body Armor Drop%"},
				{name="Grip of the Lance", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Gloves Drop Rate", label="(15-30)% Inc. Gloves Drop%"},
				{name="Might of the Siege", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Belt Drop Rate", label="(15-30)% Inc. Belt Drop%"},
				{name="Reach of Flame", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Off-Hand Catalyst Drop Rate", label="(15-30)% Inc. Off-Hand Catalyst Drop%"},
				{name="Right of Conquest", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Boots Drop Rate", label="(15-30)% Inc. Boots Drop%"},
				{name="Slumber of Morditas", minVal=12.0, maxVal=25.0, implCount=1, impl1="(12-25)% Increased Relic Drop Rate", label="(12-25)% Inc. Relic Drop%"},
				{name="Talon of Grandeur", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Ring Drop Rate", label="(15-30)% Inc. Ring Drop%"},
				{name="Vision of the Aurora", minVal=15.0, maxVal=30.0, implCount=1, impl1="(15-30)% Increased Amulet Drop Rate", label="(15-30)% Inc. Amulet Drop%"},
			},
			grand = {
				{name="Grand Apex of Fortune", minVal=41.0, maxVal=60.0, implCount=1, impl1="(41-60)% Increased Quiver Drop Rate", label="(41-60)% Inc. Quiver Drop%"},
				{name="Grand Arrogance of Argentus", minVal=22.0, maxVal=50.0, implCount=1, impl1="(22-50)% Increased Helmet Drop Rate", label="(22-50)% Inc. Helmet Drop%"},
				{name="Grand Binds of Sanctuary", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Shield Drop Rate", label="(35-75)% Inc. Shield Drop%"},
				{name="Grand Embrace of Ice", minVal=22.0, maxVal=50.0, implCount=1, impl1="(22-50)% Increased Body Armor Drop Rate", label="(22-50)% Inc. Body Armor Drop%"},
				{name="Grand Grip of the Lance", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Gloves Drop Rate", label="(35-75)% Inc. Gloves Drop%"},
				{name="Grand Might of the Siege", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Belt Drop Rate", label="(35-75)% Inc. Belt Drop%"},
				{name="Grand Reach of Flame", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Off-Hand Catalyst Drop Rate", label="(35-75)% Inc. Off-Hand Catalyst Drop%"},
				{name="Grand Right of Conquest", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Boots Drop Rate", label="(35-75)% Inc. Boots Drop%"},
				{name="Grand Slumber of Morditas", minVal=30.0, maxVal=60.0, implCount=1, impl1="(30-60)% Increased Relic Drop Rate", label="(30-60)% Inc. Relic Drop%"},
				{name="Grand Talon of Grandeur", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Ring Drop Rate", label="(35-75)% Inc. Ring Drop%"},
				{name="Grand Vision of the Aurora", minVal=35.0, maxVal=75.0, implCount=1, impl1="(35-75)% Increased Amulet Drop Rate", label="(35-75)% Inc. Amulet Drop%"},
			},
		},
		["The Black Sun"] = {
			normal = {
				{name="Depths of Infinity", minVal=10.0, maxVal=20.0, implCount=1, impl1="+(10-20)% Chance to Shred Void Resistance on Hit", label="+(10-20)% Shred Void Res on Hit"},
				{name="Echo of Solarum", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Void Resistance", label="+(25-40)% Void Res"},
				{name="Emptiness of Ash", minVal=20.0, maxVal=26.0, implCount=1, impl1="+(20-26)% Critical Strike Multiplier", label="+(20-26)% Critical Strike Multiplier"},
				{name="Flames of the Black Sun", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to Ignite on Hit", label="+(40-60)% Chance to Ignite on Hit"},
				{name="Greed of Darkness", minVal=6.0, maxVal=10.0, implCount=2, impl1="(6-10) Ward Gain on Kill", label="(6-10) Ward Gain on Kill", impl2="+(60-100) Ward Decay Threshold"},
				{name="Hunger of the Void", minVal=1.2, maxVal=2.0, implCount=1, impl1="(1.2-2)% of Spell Damage Leeched as Health", label="(1.2-2)% of Spell Dmg Leeched as Health"},
				{name="Memory of Light", minVal=30.0, maxVal=42.0, implCount=1, impl1="+(30-42) Health", label="+(30-42) Health"},
				{name="Shadow of the Eclipse", minVal=60.0, maxVal=100.0, implCount=1, impl1="+(60-100) Dodge Rating", label="+(60-100) Dodge Rating"},
				{name="Strength of the Mountain", minVal=10.0, maxVal=14.0, implCount=1, impl1="(10-14) Health Gain on Block", label="(10-14) Health Gain on Block"},
				{name="Thirst of the Sun", minVal=20.0, maxVal=30.0, implCount=1, impl1="(20-30)% Increased Leech Rate", label="(20-30)% Inc. Leech Rate"},
				{name="Whisper of Orobyss", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Void Damage", label="(40-60)% inc. Void Dmg"},
				{name="Winds of Oblivion", minVal=30.0, maxVal=50.0, implCount=1, impl1="(30-50)% increased Critical Strike Chance", label="(30-50)% inc. Critical Strike Chance"},
				{name="Wrath of Rahyeh", minVal=1.2, maxVal=2.0, implCount=1, impl1="(1.2-2)% of Throwing Damage Leeched as Health", label="(1.2-2)% of Throwing Dmg Leeched as Health"},
			},
			grand = {
				{name="Grand Depths of Infinity", minVal=25.0, maxVal=50.0, implCount=1, impl1="+(25-50)% Chance to Shred Void Resistance on Hit", label="+(25-50)% Shred Void Res on Hit"},
				{name="Grand Echo of Solarum", minVal=55.0, maxVal=75.0, implCount=1, impl1="+(55-75)% Void Resistance", label="+(55-75)% Void Res"},
				{name="Grand Emptiness of Ash", minVal=27.0, maxVal=40.0, implCount=1, impl1="+(27-40)% Critical Strike Multiplier", label="+(27-40)% Critical Strike Multiplier"},
				{name="Grand Flames of the Black Sun", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to Ignite on Hit", label="+(65-100)% Chance to Ignite on Hit"},
				{name="Grand Greed of Darkness", minVal=12.0, maxVal=18.0, implCount=2, impl1="(12-18) Ward Gain on Kill", label="(12-18) Ward Gain on Kill", impl2="+(120-200) Ward Decay Threshold"},
				{name="Grand Hunger of the Void", minVal=2.2, maxVal=3.5, implCount=1, impl1="(2.2-3.5)% of Spell Damage Leeched as Health", label="(2.2-3.5)% of Spell Dmg Leeched as Health"},
				{name="Grand Memory of Light", minVal=45.0, maxVal=70.0, implCount=1, impl1="+(45-70) Health", label="+(45-70) Health"},
				{name="Grand Shadow of the Eclipse", minVal=101.0, maxVal=200.0, implCount=1, impl1="+(101-200) Dodge Rating", label="+(101-200) Dodge Rating"},
				{name="Grand Strength of the Mountain", minVal=15.0, maxVal=22.0, implCount=1, impl1="(15-22) Health Gain on Block", label="(15-22) Health Gain on Block"},
				{name="Grand Thirst of the Sun", minVal=35.0, maxVal=50.0, implCount=1, impl1="(35-50)% Increased Leech Rate", label="(35-50)% Inc. Leech Rate"},
				{name="Grand Whisper of Orobyss", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Void Damage", label="(65-100)% inc. Void Dmg"},
				{name="Grand Winds of Oblivion", minVal=51.0, maxVal=80.0, implCount=1, impl1="(51-80)% increased Critical Strike Chance", label="(51-80)% inc. Critical Strike Chance"},
				{name="Grand Wrath of Rahyeh", minVal=2.2, maxVal=3.5, implCount=1, impl1="(2.2-3.5)% of Throwing Damage Leeched as Health", label="(2.2-3.5)% of Throwing Dmg Leeched as Health"},
			},
		},
		["Blood, Frost, and Death"] = {
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
				{name="Subtlety of Slaughter", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Dagger Drop Rate", label="(30-45)% Inc. Dagger Drop%"},
				{name="Vigilance of the Damned", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Bow Drop Rate", label="(30-45)% Inc. Bow Drop%"},
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
				{name="Grand Subtlety of Slaughter", minVal=50.0, maxVal=75.0, implCount=1, impl1="(50-75)% Increased Dagger Drop Rate", label="(50-75)% Inc. Dagger Drop%"},
				{name="Grand Vigilance of the Damned", minVal=50.0, maxVal=75.0, implCount=1, impl1="(50-75)% Increased Bow Drop Rate", label="(50-75)% Inc. Bow Drop%"},
			},
		},
		["Ending the Storm"] = {
			normal = {
				{name="Bastion of Divinity", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Lightning Resistance", label="+(25-40)% Lightning Res"},
				{name="Chaos of Lagon", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Lightning Damage", label="(40-60)% inc. Lightning Dmg"},
				{name="Crash of the Waves", minVal=50.0, maxVal=90.0, implCount=1, impl1="(50-90)% Increased Stun Chance", label="(50-90)% Inc. Stun Chance"},
				{name="Cruelty of the Meruna", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to Shock on Hit", label="+(40-60)% Chance to Shock on Hit"},
				{name="Grace of Water", minVal=40.0, maxVal=70.0, implCount=2, impl1="(40-70) Ward Gained on Potion Use", label="(40-70) Ward Gained on Potion Use", impl2="+(80-140) Ward Decay Threshold"},
				{name="Intellect of Liath", minVal=15.0, maxVal=25.0, implCount=1, impl1="(15-25)% Chance to Gain 30 Ward when Hit", label="(15-25)% Chance to Gain 30 Ward when Hit"},
				{name="Light of the Moon", minVal=30.0, maxVal=50.0, implCount=1, impl1="+(30-50) Mana", label="+(30-50) Mana"},
				{name="Might of the Sea Titan", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Cold Damage", label="(40-60)% inc. Cold Dmg"},
				{name="Mysteries of the Deep", minVal=10.0, maxVal=20.0, implCount=1, impl1="+(10-20)% Chance to Shred Lightning Resistance on Hit", label="+(10-20)% Shred Lightning Res on Hit"},
				{name="Resonance of the Sea", minVal=17.0, maxVal=25.0, implCount=1, impl1="+(17-25) Ward per Second", label="+(17-25) Ward per Second"},
				{name="Rhythm of the Tide", minVal=60.0, maxVal=100.0, implCount=2, impl1="(60-100)% increased Health Regen", label="(60-100)% inc. Health Regen", impl2="+(6-10) Health Regen"},
				{name="Trance of the Sirens", minVal=10.0, maxVal=14.0, implCount=1, impl1="(10-14)% Increased Shock Duration", label="(10-14)% Inc. Shock Duration"},
				{name="Weight of the Abyss", minVal=100.0, maxVal=180.0, implCount=1, impl1="+(100-180)% Freeze Rate Multiplier", label="+(100-180)% Freeze Rate Multiplier"},
			},
			grand = {
				{name="Grand Bastion of Divinity", minVal=55.0, maxVal=75.0, implCount=1, impl1="+(55-75)% Lightning Resistance", label="+(55-75)% Lightning Res"},
				{name="Grand Chaos of Lagon", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Lightning Damage", label="(65-100)% inc. Lightning Dmg"},
				{name="Grand Crash of the Waves", minVal=100.0, maxVal=160.0, implCount=1, impl1="(100-160)% Increased Stun Chance", label="(100-160)% Inc. Stun Chance"},
				{name="Grand Cruelty of the Meruna", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to Shock on Hit", label="+(65-100)% Chance to Shock on Hit"},
				{name="Grand Grace of Water", minVal=80.0, maxVal=130.0, implCount=2, impl1="(80-130) Ward Gained on Potion Use", label="(80-130) Ward Gained on Potion Use", impl2="+(160-260) Ward Decay Threshold"},
				{name="Grand Intellect of Liath", minVal=30.0, maxVal=50.0, implCount=1, impl1="(30-50)% Chance to Gain 30 Ward when Hit", label="(30-50)% Chance to Gain 30 Ward when Hit"},
				{name="Grand Light of the Moon", minVal=60.0, maxVal=90.0, implCount=1, impl1="+(60-90) Mana", label="+(60-90) Mana"},
				{name="Grand Might of the Sea Titan", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Cold Damage", label="(65-100)% inc. Cold Dmg"},
				{name="Grand Mysteries of the Deep", minVal=25.0, maxVal=50.0, implCount=1, impl1="+(25-50)% Chance to Shred Lightning Resistance on Hit", label="+(25-50)% Shred Lightning Res on Hit"},
				{name="Grand Resonance of the Sea", minVal=30.0, maxVal=42.0, implCount=1, impl1="+(30-42) Ward per Second", label="+(30-42) Ward per Second"},
				{name="Grand Rhythm of the Tide", minVal=120.0, maxVal=200.0, implCount=2, impl1="(120-200)% increased Health Regen", label="(120-200)% inc. Health Regen", impl2="+(12-20) Health Regen"},
				{name="Grand Trance of the Sirens", minVal=15.0, maxVal=22.0, implCount=1, impl1="(15-22)% Increased Shock Duration", label="(15-22)% Inc. Shock Duration"},
				{name="Grand Weight of the Abyss", minVal=200.0, maxVal=300.0, implCount=1, impl1="+(200-300)% Freeze Rate Multiplier", label="+(200-300)% Freeze Rate Multiplier"},
			},
		},
		["Fall of the Empire"] = {
			normal = {
				{name="Boon of the Scarab", minVal=25.0, maxVal=35.0, implCount=1, impl1="(25-35)% Increased Bow Shard Drop Rate", label="(25-35)% Inc. Bow Shard Drop%"},
				{name="Despair of the Empire", minVal=25.0, maxVal=40.0, implCount=1, impl1="(25-40)% Increased Ailment Shard Drop Rate", label="(25-40)% Inc. Ailment Shard Drop%"},
				{name="Hope of the Beginning", minVal=10.0, maxVal=15.0, implCount=1, impl1="(10-15)% Increased Prefix Shard Drop Rate", label="(10-15)% Inc. Prefix Shard Drop%"},
				{name="Inevitability of the Void", minVal=20.0, maxVal=30.0, implCount=1, impl1="(20-30)% Increased Two-Handed Staff Shard Drop Rate", label="(20-30)% Inc. 2H Staff Shard Drop%"},
				{name="Remnants of the Living", minVal=16.0, maxVal=25.0, implCount=1, impl1="(16-25)% Increased Ring Shard Drop Rate", label="(16-25)% Inc. Ring Shard Drop%"},
				{name="Rot of the World", minVal=25.0, maxVal=40.0, implCount=1, impl1="(25-40)% Increased Wand Shard Drop Rate", label="(25-40)% Inc. Wand Shard Drop%"},
				{name="Safety of the Labyrinth", minVal=12.0, maxVal=20.0, implCount=1, impl1="(12-20)% Increased Amulet Shard Drop Rate", label="(12-20)% Inc. Amulet Shard Drop%"},
				{name="Shadows of Infinity", minVal=10.0, maxVal=20.0, implCount=1, impl1="(10-20)% Increased Relic Shard Drop Rate", label="(10-20)% Inc. Relic Shard Drop%"},
				{name="Visions of Death", minVal=25.0, maxVal=40.0, implCount=1, impl1="(25-40)% Increased Two-Handed Spear Shard Drop Rate", label="(25-40)% Inc. 2H Spear Shard Drop%"},
			},
			grand = {
				{name="Grand Boon of the Scarab", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% Increased Bow Shard Drop Rate", label="(40-60)% Inc. Bow Shard Drop%"},
				{name="Grand Despair of the Empire", minVal=45.0, maxVal=70.0, implCount=1, impl1="(45-70)% Increased Ailment Shard Drop Rate", label="(45-70)% Inc. Ailment Shard Drop%"},
				{name="Grand Hope of the Beginning", minVal=15.0, maxVal=25.0, implCount=1, impl1="(15-25)% Increased Prefix Shard Drop Rate", label="(15-25)% Inc. Prefix Shard Drop%"},
				{name="Grand Inevitability of the Void", minVal=30.0, maxVal=45.0, implCount=1, impl1="(30-45)% Increased Two-Handed Staff Shard Drop Rate", label="(30-45)% Inc. 2H Staff Shard Drop%"},
				{name="Grand Remnants of the Living", minVal=33.0, maxVal=50.0, implCount=1, impl1="(33-50)% Increased Ring Shard Drop Rate", label="(33-50)% Inc. Ring Shard Drop%"},
				{name="Grand Rot of the World", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% Increased Wand Shard Drop Rate", label="(40-60)% Inc. Wand Shard Drop%"},
				{name="Grand Safety of the Labyrinth", minVal=22.0, maxVal=35.0, implCount=1, impl1="(22-35)% Increased Amulet Shard Drop Rate", label="(22-35)% Inc. Amulet Shard Drop%"},
				{name="Grand Shadows of Infinity", minVal=22.0, maxVal=35.0, implCount=1, impl1="(22-35)% Increased Relic Shard Drop Rate", label="(22-35)% Inc. Relic Shard Drop%"},
				{name="Grand Visions of Death", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% Increased Two-Handed Spear Shard Drop Rate", label="(40-60)% Inc. 2H Spear Shard Drop%"},
			},
		},
		["Reign of Dragons"] = {
			normal = {
				{name="Allure of Apathy", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to Slow on Hit", label="+(40-60)% Chance to Slow on Hit"},
				{name="Binds of Nature", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Poison Damage", label="(40-60)% inc. Poison Dmg"},
				{name="Cruelty of Strength", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Physical Damage", label="(40-60)% inc. Physical Dmg"},
				{name="Despair of Flesh", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Necrotic Damage", label="(40-60)% inc. Necrotic Dmg"},
				{name="Dream of Eterra", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Necrotic Resistance", label="+(25-40)% Necrotic Res"},
				{name="Guile of Wyrms", minVal=60.0, maxVal=90.0, implCount=1, impl1="+(60-90)% Chance to Shred Poison Resistance on Hit", label="+(60-90)% Shred Poison Res on Hit"},
				{name="Hemmorage of Marrow", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to inflict Bleed on Hit", label="+(40-60)% Chance to inflict Bleed on Hit"},
				{name="Hunger of Dragons", minVal=2.0, maxVal=4.0, implCount=1, impl1="(2-4)% of Melee Damage Leeched as Health", label="(2-4)% of Melee Dmg Leeched as Health"},
				{name="Persistance of Will", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Poison Resistance", label="+(25-40)% Poison Res"},
				{name="Resolve of Humanity", minVal=7.0, maxVal=12.0, implCount=1, impl1="+(7-12)% to All Resistances", label="+(7-12)% to All Ress"},
				{name="Survival of Might", minVal=30.0, maxVal=45.0, implCount=2, impl1="+(30-45)% Critical Strike Avoidance", label="+(30-45)% Critical Strike Avoidance", impl2="+(30-50) Dodge Rating"},
				{name="Taste of Venom", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to Poison on Hit", label="+(40-60)% Chance to Poison on Hit"},
				{name="Virtue of Command", minVal=8.0, maxVal=15.0, implCount=1, impl1="+(8-15)% to Minion All Resistances", label="+(8-15)% to Minion All Ress"},
			},
			grand = {
				{name="Grand Allure of Apathy", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to Slow on Hit", label="+(65-100)% Chance to Slow on Hit"},
				{name="Grand Binds of Nature", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Poison Damage", label="(65-100)% inc. Poison Dmg"},
				{name="Grand Cruelty of Strength", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Physical Damage", label="(65-100)% inc. Physical Dmg"},
				{name="Grand Despair of Flesh", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Necrotic Damage", label="(65-100)% inc. Necrotic Dmg"},
				{name="Grand Dream of Eterra", minVal=45.0, maxVal=75.0, implCount=1, impl1="+(45-75)% Necrotic Resistance", label="+(45-75)% Necrotic Res"},
				{name="Grand Guile of Wyrms", minVal=100.0, maxVal=150.0, implCount=1, impl1="+(100-150)% Chance to Shred Poison Resistance on Hit", label="+(100-150)% Shred Poison Res on Hit"},
				{name="Grand Hemmorage of Marrow", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to inflict Bleed on Hit", label="+(65-100)% Chance to inflict Bleed on Hit"},
				{name="Grand Hunger of Dragons", minVal=4.5, maxVal=7.0, implCount=1, impl1="(4.5-7)% of Melee Damage Leeched as Health", label="(4.5-7)% of Melee Dmg Leeched as Health"},
				{name="Grand Persistance of Will", minVal=55.0, maxVal=75.0, implCount=1, impl1="+(55-75)% Poison Resistance", label="+(55-75)% Poison Res"},
				{name="Grand Resolve of Humanity", minVal=13.0, maxVal=20.0, implCount=1, impl1="+(13-20)% to All Resistances", label="+(13-20)% to All Ress"},
				{name="Grand Survival of Might", minVal=50.0, maxVal=70.0, implCount=2, impl1="+(50-70)% Critical Strike Avoidance", label="+(50-70)% Critical Strike Avoidance", impl2="+(51-90) Dodge Rating"},
				{name="Grand Taste of Venom", minVal=65.0, maxVal=100.0, implCount=1, impl1="+(65-100)% Chance to Poison on Hit", label="+(65-100)% Chance to Poison on Hit"},
				{name="Grand Virtue of Command", minVal=16.0, maxVal=25.0, implCount=1, impl1="+(16-25)% to Minion All Resistances", label="+(16-25)% to Minion All Ress"},
			},
		},
		["The Age of Winter"] = {
			normal = {
				{name="Bones of Eternity", minVal=3.0, maxVal=4.0, implCount=2, impl1="+(3-4)% Block Chance", label="+(3-4)% Block Chance", impl2="+(100-140) Block Effectiveness"},
				{name="Bulwark of the Tundra", minVal=12.0, maxVal=24.0, implCount=1, impl1="(12-24)% increased Armor", label="(12-24)% inc. Armor"},
				{name="Defiance of Yulia", minVal=5.0, maxVal=10.0, implCount=1, impl1="+(5-10) Cold Spell Damage while Channelling", label="+(5-10) Cold Spell Dmg while Channelling"},
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
				{name="Grand Bones of Eternity", minVal=5.0, maxVal=8.0, implCount=2, impl1="+(5-8)% Block Chance", label="+(5-8)% Block Chance", impl2="+(180-240) Block Effectiveness"},
				{name="Grand Bulwark of the Tundra", minVal=25.0, maxVal=55.0, implCount=1, impl1="(25-55)% increased Armor", label="(25-55)% inc. Armor"},
				{name="Grand Defiance of Yulia", minVal=11.0, maxVal=20.0, implCount=1, impl1="+(11-20) Cold Spell Damage while Channelling", label="+(11-20) Cold Spell Dmg while Channelling"},
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
		["Spirits of Fire"] = {
			normal = {
				{name="Body of Obsidian", minVal=120.0, maxVal=180.0, implCount=1, impl1="+(120-180) Armor", label="+(120-180) Armor"},
				{name="Breath of Cinders", minVal=10.0, maxVal=20.0, implCount=1, impl1="+(10-20)% Chance to Shred Fire Resistance on Hit", label="+(10-20)% Shred Fire Res on Hit"},
				{name="Curse of Sulphur", minVal=20.0, maxVal=35.0, implCount=1, impl1="+(20-35)% Chance to apply Frailty on Hit", label="+(20-35)% Chance to apply Frailty on Hit"},
				{name="Embers of Immortality", minVal=10.0, maxVal=14.0, implCount=1, impl1="+(10-14)% Endurance", label="+(10-14)% Endurance"},
				{name="Flames of Calamity", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Fire Damage", label="(40-60)% inc. Fire Dmg"},
				{name="Heart of the Caldera", minVal=25.0, maxVal=40.0, implCount=1, impl1="+(25-40)% Fire Resistance", label="+(25-40)% Fire Res"},
				{name="Might of Bhuldar", minVal=20.0, maxVal=30.0, implCount=1, impl1="(20-30)% Increased Stun Duration", label="(20-30)% Inc. Stun Duration"},
				{name="Patience of Herkir", minVal=200.0, maxVal=350.0, implCount=1, impl1="+(200-350) Armor While Channelling", label="+(200-350) Armor While Channelling"},
				{name="Promise of Death", minVal=10.0, maxVal=20.0, implCount=1, impl1="+(10-20)% Chance to Shred Necrotic Resistance on Hit", label="+(10-20)% Shred Necrotic Res on Hit"},
				{name="Spirit of Command", minVal=40.0, maxVal=60.0, implCount=1, impl1="(40-60)% increased Minion Damage", label="(40-60)% inc. Minion Dmg"},
				{name="Swiftness of Logi", minVal=15.0, maxVal=35.0, implCount=1, impl1="(15-35)% increased Dodge Rating", label="(15-35)% inc. Dodge Rating"},
			},
			grand = {
				{name="Grand Body of Obsidian", minVal=200.0, maxVal=320.0, implCount=1, impl1="+(200-320) Armor", label="+(200-320) Armor"},
				{name="Grand Breath of Cinders", minVal=25.0, maxVal=50.0, implCount=1, impl1="+(25-50)% Chance to Shred Fire Resistance on Hit", label="+(25-50)% Shred Fire Res on Hit"},
				{name="Grand Curse of Sulphur", minVal=40.0, maxVal=60.0, implCount=1, impl1="+(40-60)% Chance to apply Frailty on Hit", label="+(40-60)% Chance to apply Frailty on Hit"},
				{name="Grand Embers of Immortality", minVal=18.0, maxVal=30.0, implCount=1, impl1="+(18-30)% Endurance", label="+(18-30)% Endurance"},
				{name="Grand Flames of Calamity", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Fire Damage", label="(65-100)% inc. Fire Dmg"},
				{name="Grand Heart of the Caldera", minVal=55.0, maxVal=75.0, implCount=1, impl1="+(55-75)% Fire Resistance", label="+(55-75)% Fire Res"},
				{name="Grand Might of Bhuldar", minVal=32.0, maxVal=50.0, implCount=1, impl1="(32-50)% Increased Stun Duration", label="(32-50)% Inc. Stun Duration"},
				{name="Grand Patience of Herkir", minVal=400.0, maxVal=650.0, implCount=1, impl1="+(400-650) Armor While Channelling", label="+(400-650) Armor While Channelling"},
				{name="Grand Promise of Death", minVal=25.0, maxVal=50.0, implCount=1, impl1="+(25-50)% Chance to Shred Necrotic Resistance on Hit", label="+(25-50)% Shred Necrotic Res on Hit"},
				{name="Grand Spirit of Command", minVal=65.0, maxVal=100.0, implCount=1, impl1="(65-100)% increased Minion Damage", label="(65-100)% inc. Minion Dmg"},
				{name="Grand Swiftness of Logi", minVal=40.0, maxVal=70.0, implCount=1, impl1="(40-70)% increased Dodge Rating", label="(40-70)% inc. Dodge Rating"},
			},
		},
		["The Last Ruin"] = {
			normal = {
				{name="Bastion of the Heart", minVal=12.0, maxVal=20.0, implCount=1, impl1="(12-20)% Increased Body Armor Shard Drop Rate", label="(12-20)% Inc. Body Armor Shard Drop%"},
				{name="Binding of Ruin", minVal=20.0, maxVal=30.0, implCount=1, impl1="(20-30)% Increased Belt Shard Drop Rate", label="(20-30)% Inc. Belt Shard Drop%"},
				{name="Comfort of the End", minVal=12.0, maxVal=20.0, implCount=1, impl1="(12-20)% Increased Suffix Shard Drop Rate", label="(12-20)% Inc. Suffix Shard Drop%"},
				{name="Grasp of Hope", minVal=20.0, maxVal=30.0, implCount=1, impl1="(20-30)% Increased Gloves Shard Drop Rate", label="(20-30)% Inc. Gloves Shard Drop%"},
				{name="Knowledge of Skill", minVal=12.0, maxVal=20.0, implCount=1, impl1="(12-20)% Increased Skill Shard Drop Rate", label="(12-20)% Inc. Skill Shard Drop%"},
				{name="Memory of Masters", minVal=10.0, maxVal=18.0, implCount=1, impl1="(10-18)% Increased Class Specific Shard Drop Rate", label="(10-18)% Inc. Class Shard Drop%"},
				{name="Refuge of Despair", minVal=20.0, maxVal=30.0, implCount=1, impl1="(20-30)% Increased Shield Shard Drop Rate", label="(20-30)% Inc. Shield Shard Drop%"},
				{name="Remnants of the Elders", minVal=20.0, maxVal=30.0, implCount=1, impl1="(20-30)% Increased Off-Hand Catalyst Shard Drop Rate", label="(20-30)% Inc. Off-Hand Shard Drop%"},
				{name="Temple of the Mind", minVal=12.0, maxVal=20.0, implCount=1, impl1="(12-20)% Increased Helmet Shard Drop Rate", label="(12-20)% Inc. Helmet Shard Drop%"},
			},
			grand = {
				{name="Grand Bastion of the Heart", minVal=22.0, maxVal=35.0, implCount=1, impl1="(22-35)% Increased Body Armor Shard Drop Rate", label="(22-35)% Inc. Body Armor Shard Drop%"},
				{name="Grand Binding of Ruin", minVal=32.0, maxVal=50.0, implCount=1, impl1="(32-50)% Increased Belt Shard Drop Rate", label="(32-50)% Inc. Belt Shard Drop%"},
				{name="Grand Comfort of the End", minVal=22.0, maxVal=35.0, implCount=1, impl1="(22-35)% Increased Suffix Shard Drop Rate", label="(22-35)% Inc. Suffix Shard Drop%"},
				{name="Grand Grasp of Hope", minVal=32.0, maxVal=50.0, implCount=1, impl1="(32-50)% Increased Gloves Shard Drop Rate", label="(32-50)% Inc. Gloves Shard Drop%"},
				{name="Grand Knowledge of Skill", minVal=22.0, maxVal=35.0, implCount=1, impl1="(22-35)% Increased Skill Shard Drop Rate", label="(22-35)% Inc. Skill Shard Drop%"},
				{name="Grand Memory of Masters", minVal=20.0, maxVal=30.0, implCount=1, impl1="(20-30)% Increased Class Specific Shard Drop Rate", label="(20-30)% Inc. Class Shard Drop%"},
				{name="Grand Refuge of Despair", minVal=32.0, maxVal=50.0, implCount=1, impl1="(32-50)% Increased Shield Shard Drop Rate", label="(32-50)% Inc. Shield Shard Drop%"},
				{name="Grand Remnants of the Elders", minVal=32.0, maxVal=50.0, implCount=1, impl1="(32-50)% Increased Off-Hand Catalyst Shard Drop Rate", label="(32-50)% Inc. Off-Hand Shard Drop%"},
				{name="Grand Temple of the Mind", minVal=22.0, maxVal=35.0, implCount=1, impl1="(22-35)% Increased Helmet Shard Drop Rate", label="(22-35)% Inc. Helmet Shard Drop%"},
			},
		},
	}

	local blessingTimelines = {"Fall of the Outcasts", "The Stolen Lance", "The Black Sun", "Blood, Frost, and Death", "Ending the Storm", "Fall of the Empire", "Reign of Dragons", "The Last Ruin", "Spirits of Fire", "The Age of Winter"}
	self.blessingData = blessingData
	self.blessingTimelines = blessingTimelines
	self.blessingControls = {}

	-- Mock slot proxies for blessing timelines so updateBlessingSlot and NewItemSet work.
	-- These are invisible (IsShown=false) but tracked in self.slots so item-set logic works.
	for _, tl in ipairs(blessingTimelines) do
		local tl_name = tl
		local mockSlot = {
			slotName = tl_name,
			selItemId = 0,
			nodeId = nil,
			controls = {},
		}
		mockSlot.SetSelItemId = function(s, id)
			s.selItemId = id
			if self.activeItemSet and self.activeItemSet[tl_name] then
				self.activeItemSet[tl_name].selItemId = id
			end
		end
		mockSlot.Populate = function() end
		mockSlot.IsShown = function() return false end
		-- A placeholder ItemSlotControl was already inserted into orderedSlots by the
		-- baseSlots loop above (blessing names are members of baseSlots). Replace it in
		-- place so blessing mods are not merged twice during calc setup.
		local existingIdx = self.slotOrder[tl_name]
		self.slots[tl_name] = mockSlot
		if existingIdx then
			self.orderedSlots[existingIdx] = mockSlot
		else
			t_insert(self.orderedSlots, mockSlot)
			self.slotOrder[tl_name] = #self.orderedSlots
		end
	end

	local function updateBlessingSlot(tl, blessEntry, rollFrac)
		local slot = self.slots[tl]
		if not slot then return end
		local oldId = slot.selItemId
		if oldId and oldId ~= 0 then
			self.items[oldId] = nil
			for i, id in ipairs(self.itemOrderList) do
				if id == oldId then t_remove(self.itemOrderList, i); break end
			end
			slot:SetSelItemId(0)
		end
		self.blessingFracs = self.blessingFracs or {}
		self.blessingFracs[tl] = rollFrac or 1.0
		if not blessEntry or not blessEntry.name then
			slot:SetSelItemId(0)
			self.build.buildFlag = true
			return
		end
		local frac = rollFrac or 1.0
		local function resolveImpl(impl)
			return impl:gsub("%([0-9.]+%-[0-9.]+%)", function(range)
				local implMin, implMax = range:match("%(([0-9.]+)%-([0-9.]+)%)")
				local implVal = tonumber(implMin) + frac * (tonumber(implMax) - tonumber(implMin))
				return string.format("%d", math.floor(implVal + 0.5))
			end)
		end
		local implCount = blessEntry.implCount or 1
		local raw = "Rarity: NORMAL\n"..blessEntry.name.."\n"..blessEntry.name
			.."\nImplicits: "..implCount.."\n"..resolveImpl(blessEntry.impl1 or "")
		if blessEntry.impl2 then raw = raw.."\n"..resolveImpl(blessEntry.impl2) end
		local item = new("Item", raw)
		if not item or not item.base then
			ConPrintf("[BLESS] ERR item.base=nil for %s in slot %s", blessEntry.name, tl)
			return
		end
		item.uniqueID = "blessing:" .. tl  -- prevent nil==nil match with regular items in ImportItem
		item.id = nil  -- let AddItem assign a positive ID so blessing appears in All Items
		self:AddItem(item, true)  -- noAutoEquip=true, also calls BuildModList
		slot:SetSelItemId(item.id)
		self.build.buildFlag = true
	end
	self.updateBlessingSlot = updateBlessingSlot
	-- ===== END BLESSING PANEL (UI moved to ConfigTab) =====

	self.controls.slotHeader = new("LabelControl", {"BOTTOMLEFT",self.slotAnchor,"TOPLEFT"}, 0, -4, 0, 16, "^7Equipped items:")

	-- All items list
	if main.portraitMode then
		self.controls.itemList = new("ItemListControl", {"TOPRIGHT",self.lastSlot,"BOTTOMRIGHT"}, 0, 0, 360, 308, self, true)
	else
		self.controls.itemList = new("ItemListControl", {"TOPLEFT",self.controls.setManage,"TOPRIGHT"}, 20, 20, 360, 308, self, true)
	end

	-- Create/import item buttons
	self.controls.craftDisplayItem = new("ButtonControl", {"TOPLEFT",self.controls.itemList,"BOTTOMLEFT"}, 0, 8, 120, 20, "Craft item...", function()
		self:CraftItem()
	end)
	self.controls.craftDisplayItem.shown = function()
		return self.displayItem == nil
	end
	self.controls.newDisplayItem = new("ButtonControl", {"TOPLEFT",self.controls.craftDisplayItem,"TOPRIGHT"}, 8, 0, 120, 20, "Create custom...", function()
		self:EditDisplayItemText()
	end)
	self.controls.newDisplayItem.shown = function()
		return self.displayItem == nil
	end

	-- Paperdoll frame (shown only when no display item; anchor updated below)
	self.controls.paperdoll = new("PaperdollControl",
		{"TOPLEFT", self.controls.craftDisplayItem, "BOTTOMLEFT"}, 0, 50, self)
	self.controls.paperdoll.shown = function()
		return self.displayItem == nil
	end

	-- Display item
	self.displayItemTooltip = new("Tooltip")
	self.displayItemTooltip.maxWidth = 458
	self.anchorDisplayItem = new("Control", {"TOPLEFT",self.controls.itemList,"TOPRIGHT"}, 20, 0, 0, 0)
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
		if self.displayItem and self.displayItem.crafted then
			self:CraftItem(self.displayItem)
		else
			self:EditDisplayItemText()
		end
	end)
	self.controls.removeDisplayItem = new("ButtonControl", {"LEFT",self.controls.editDisplayItem,"RIGHT"}, 8, 0, 60, 20, "Cancel", function()
		self:SetDisplayItem()
	end)

	-- Tooltip anchor (directly after action buttons; old affix/custom/range UI removed)
	self.controls.displayItemTooltipAnchor = new("Control", {"TOPLEFT",self.controls.addDisplayItem,"BOTTOMLEFT"}, 0, 8)

	-- Scroll bars
	self.controls.scrollBarV = new("ScrollBarControl", nil, 0, 0, 18, 0, 100, "VERTICAL", true)

	-- Initialise drag target lists
	t_insert(self.controls.itemList.dragTargetList, build.controls.mainSkillMinion)
	for _, slot in pairs(self.slots) do
		t_insert(self.controls.itemList.dragTargetList, slot)
	end

	-- Initialise item sets
	self.itemSets = { }
	self.itemSetOrderList = { 1 }
	self:NewItemSet(1)
	self:SetActiveItemSet(1)

	-- ===== IDOL GRID IN ITEMS TAB =====
	-- Created here (after drag targets and item sets are ready) so RegisterLateSlot
	-- can safely add the 25 idol slots to the drag lists and all item sets.
	-- cw=48, ch=46 makes the 5x5 grid aspect ratio match idol_container.png's
	-- interior grid so the PNG border and functional cells overlap cleanly.
	-- Y offset (90) clears the container frame's altar-circle + top border (~83px)
	-- above the grid so the circle does not overlap the Fractured 1..4 dropdowns.
	-- Visual centering on the Equipped items dropdown column. Tuned by eye.
	self.controls.idolGrid = new("IdolGridControl",
		-- Y offset raised from 90 to 112 to leave room for the 22px title bar
		-- drawn above the container frame ("Equipped Idols / Idol Altar").
		{"TOPLEFT", self.controls.idolAltarEnd, "BOTTOMLEFT"}, 0, 112,
		self, self.idolGridLayout, 48, 46)
	-- Padding below the grid clears the frame's bottom border (~18px) before
	-- the blessing grid is placed, so Blessing sits fully under the new frame.
	self.controls.idolGridPanelEnd = new("Control", {"TOPLEFT", self.controls.idolGrid, "BOTTOMLEFT"}, 0, 24, 0, 0)
	t_insert(self.controls, self.controls.idolGridPanelEnd)
	-- ===== END IDOL GRID =====

	-- Blessing slot grid: width 292, anchored to idolGrid x with -22 offset to
	-- share the same horizontal center as the idol frame.
	local blessGrid = new("BlessingGridControl",
		{"TOPLEFT", self.controls.idolGridPanelEnd, "TOPLEFT"}, -22, 0, self)
	t_insert(self.controls, blessGrid)
	self.controls.blessingGrid = blessGrid

	-- Craft shortcut buttons: square 48x48 image-only buttons below the paperdoll.
	-- Centered under the 288px-wide paperdoll: 3*48 + 2*4 = 152px → x offset = (288-152)/2 = 68.
	self.controls.craftIdolBtn = new("ButtonControl", {"TOPLEFT", self.controls.paperdoll, "BOTTOMLEFT"}, 68, 8, 48, 48, "", function()
		self:CraftItem()
	end)
	self.controls.craftIdolBtn:SetImage("Assets/idol/smallEterranIdol.png")
	self.controls.craftIdolBtn.tooltipText = "Craft Idol..."
	self.controls.craftIdolBtn.shown = function()
		return self.displayItem == nil
	end
	self.controls.craftIdolAltarBtn = new("ButtonControl", {"LEFT", self.controls.craftIdolBtn, "RIGHT"}, 4, 0, 48, 48, "", function()
		self:CraftItem(nil, "Idol Altar")
	end)
	self.controls.craftIdolAltarBtn:SetImage("Assets/idol/Idol_Altar_Pyramidal_Altar.png")
	self.controls.craftIdolAltarBtn.tooltipText = "Craft Idol Altar..."
	self.controls.craftIdolAltarBtn.shown = function()
		return self.displayItem == nil
	end
	self.controls.craftBlessingBtn = new("ButtonControl", {"LEFT", self.controls.craftIdolAltarBtn, "RIGHT"}, 4, 0, 48, 48, "", function()
		self:EditBlessings(nil)
	end)
	self.controls.craftBlessingBtn:SetImage("Assets/blessings/memory_of_light.png")
	self.controls.craftBlessingBtn.tooltipText = "Craft Blessing..."
	self.controls.craftBlessingBtn.shown = function()
		return self.displayItem == nil
	end

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
		elseif node.elem == "BlessingFracs" then
			self.blessingFracs = self.blessingFracs or {}
			for _, child in ipairs(node) do
				if child.elem == "BlessingFrac" and child.attrib.timeline then
					self.blessingFracs[child.attrib.timeline] = tonumber(child.attrib.frac) or 1.0
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
	-- Save blessing roll fractions so +/- button positions are restored on load
	if self.blessingFracs and next(self.blessingFracs) then
		local fracChild = { elem = "BlessingFracs", attrib = {} }
		for tl, frac in pairs(self.blessingFracs) do
			t_insert(fracChild, { elem = "BlessingFrac", attrib = { timeline = tl, frac = tostring(frac) } })
		end
		t_insert(xml, fracChild)
	end
end

function ItemsTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height
	self.controls.scrollBarV.height = viewPort.height
	self.controls.scrollBarV.x = viewPort.x + viewPort.width - 18
	self.controls.scrollBarV.y = viewPort.y
	do
		local blessGridY = select(2, self.controls.blessingGrid:GetPos())
		local _, blessGridH = self.controls.blessingGrid:GetSize()
		local maxY = m_max(select(2, self.controls.idolGridPanelEnd:GetPos()) + 24, blessGridY + blessGridH + 8)
		if self.displayItem then
			local x, y = self.controls.displayItemTooltipAnchor:GetPos()
			local ttW, ttH = self.displayItemTooltip:GetDynamicSize(viewPort)
			maxY = m_max(maxY, y + ttH + 4)
		end
		local contentHeight = maxY - self.y
		self.controls.scrollBarV:SetContentDimension(contentHeight, viewPort.height)
		self.maxY = viewPort.y + viewPort.height
	end
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
			end
		end
	end
	self:ProcessControlsInput(inputEvents, viewPort)
	for _, event in ipairs(inputEvents) do
		if event.type == "KeyUp" then
			if self.controls.scrollBarV:IsScrollDownKey(event.key) then
				self.controls.scrollBarV:Scroll(1)
			elseif self.controls.scrollBarV:IsScrollUpKey(event.key) then
				self.controls.scrollBarV:Scroll(-1)
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
	-- Restore altar layout: SetActiveItemSet sets selItemId directly (bypasses the
	-- SetSelItemId override), so activeAltarLayout must be updated explicitly here.
	local altarSelId = curSet["Idol Altar"] and curSet["Idol Altar"].selItemId
	local altarItem = altarSelId and self.items[altarSelId]
	if altarItem and altarItem.baseName and IDOL_ALTAR_LAYOUTS[altarItem.baseName] then
		self.activeAltarLayout = altarItem.baseName
	else
		self.activeAltarLayout = "Default"
	end
	self.build.buildFlag = true
	self:PopulateSlots()
end

-- Equips the given item in the given item set
function ItemsTabClass:EquipItemInSet(item, itemSetId)
	local itemSet = self.itemSets[itemSetId]
	local slotName = item:GetPrimarySlot()
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
	-- Idols are placed manually in the grid; skip auto-equip
	if self.displayItem and self.displayItem.type and self.displayItem.type:find("Idol$") then
		noAutoEquip = true
	end
	-- Add it to the list and clear the current display item
	self:AddItem(self.displayItem, noAutoEquip)
	self:SetDisplayItem()

	self:PopulateSlots()
	self:AddUndoState()
	self.build.buildFlag = true
end

-- Sorts the build's item list by equipped state:
-- equipped items (grouped by slot, then set) come before unequipped; ties broken by name.
function ItemsTabClass:SortItemList()
	table.sort(self.itemOrderList, function(a, b)
		local itemA = self.items[a]
		local itemB = self.items[b]
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

-- Toggle between category-based sort and equipped-state sort.
-- Called by the Sort button in ItemListControl; returns the mode that was just applied.
function ItemsTabClass:ToggleSortMode()
	if self.sortMode == "category" then
		self.sortMode = "equipment"
		self:SortItemList()
	else
		self.sortMode = "category"
		self:SortItemListByCategory()
	end
	return self.sortMode
end

-- Category ordering for SortItemListByCategory:
--   Weapon < Armor < Jewelry < Relic < Idol Altar < Idol < Blessing < Other
local SORT_CATEGORY_ORDER = {
	Weapon = 1, Armor = 2, Jewelry = 3, Relic = 4,
	["Idol Altar"] = 5, Idol = 6, Blessing = 7, Other = 8,
}
local SORT_TYPE_TO_CATEGORY = {
	-- Weapons
	["One-Handed Axe"] = "Weapon", ["Two-Handed Axe"] = "Weapon",
	["One-Handed Mace"] = "Weapon", ["Two-Handed Mace"] = "Weapon",
	["One-Handed Sword"] = "Weapon", ["Two-Handed Sword"] = "Weapon",
	["Two-Handed Spear"] = "Weapon", ["Two-Handed Staff"] = "Weapon",
	["Bow"] = "Weapon", ["Dagger"] = "Weapon", ["Wand"] = "Weapon", ["Sceptre"] = "Weapon",
	-- Armor (includes off-hand defensives)
	["Helmet"] = "Armor", ["Body Armor"] = "Armor", ["Gloves"] = "Armor",
	["Boots"] = "Armor", ["Belt"] = "Armor",
	["Shield"] = "Armor", ["Off-Hand Catalyst"] = "Armor", ["Quiver"] = "Armor",
	-- Jewelry
	["Amulet"] = "Jewelry", ["Ring"] = "Jewelry",
	-- Relic
	["Relic"] = "Relic",
	-- Idol Altar is its own category (separated from Idol)
	["Idol Altar"] = "Idol Altar",
	-- Blessing
	["Blessing"] = "Blessing",
}
-- Rarity order within a type group (higher = earlier)
local SORT_RARITY_ORDER = {
	LEGENDARY = 1, UNIQUE = 2, SET = 3, EXALTED = 4, RARE = 5, MAGIC = 6, NORMAL = 7,
}

local function getSortCategory(item)
	if not item or not item.type then return "Other" end
	local c = SORT_TYPE_TO_CATEGORY[item.type]
	if c then return c end
	if item.type:find("Idol") then return "Idol" end
	return "Other"
end

-- Sort items by broad category: Weapon / Armor / Jewelry / Relic / Idol / Blessing.
-- Within a category, groups by item.type, then rarity (Legendary first), then name.
function ItemsTabClass:SortItemListByCategory()
	table.sort(self.itemOrderList, function(a, b)
		local itemA = self.items[a]
		local itemB = self.items[b]
		local catA = SORT_CATEGORY_ORDER[getSortCategory(itemA)] or 99
		local catB = SORT_CATEGORY_ORDER[getSortCategory(itemB)] or 99
		if catA ~= catB then return catA < catB end
		local typeA = itemA.type or ""
		local typeB = itemB.type or ""
		if typeA ~= typeB then return typeA < typeB end
		local rA = SORT_RARITY_ORDER[itemA.rarity] or 99
		local rB = SORT_RARITY_ORDER[itemB.rarity] or 99
		if rA ~= rB then return rA < rB end
		return (itemA.name or "") < (itemB.name or "")
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

		-- Old affix/custom/range UI removed; crafting is handled by CraftingPopup
	else
		self.snapHScroll = "LEFT"
	end
end

function ItemsTabClass:UpdateDisplayItemTooltip()
	self.displayItemTooltip:Clear()
	self:AddItemTooltip(self.displayItemTooltip, self.displayItem)
	self.displayItemTooltip.center = false
end

-- Old affix/custom/range UI removed; crafting handled by CraftingPopup
function ItemsTabClass:UpdateAffixControls() end
function ItemsTabClass:UpdateAffixControl() end
function ItemsTabClass:UpdateCustomControls() end
function ItemsTabClass:UpdateDisplayItemRangeLines() end

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
-- Returns true if the footprint of item placed at slotName overlaps any existing idol,
-- excluding the idol with id excludeItemId (used for replacement checks).
function ItemsTabClass:IdolFootprintOverlaps(item, slotName, excludeItemId)
	local size = idolSize[item.type]
	local pos  = idolSlotPos[slotName]
	if not size or not pos then return false end
	for dr = 0, size[2] - 1 do
		for dc = 0, size[1] - 1 do
			local targetRow = pos[1] + dr
			local targetCol = pos[2] + dc
			for otherSlotName, otherSlot in pairs(self.slots) do
				if otherSlotName:match("^Idol ") and otherSlot.selItemId ~= 0 and otherSlot.selItemId ~= excludeItemId then
					local existItem = self.items[otherSlot.selItemId]
					if existItem then
						local eSize = idolSize[existItem.type] or {1, 1}
						local ePos  = idolSlotPos[otherSlotName]
						if ePos then
							if targetRow >= ePos[1] and targetRow < ePos[1] + eSize[2] and
							   targetCol >= ePos[2] and targetCol < ePos[2] + eSize[1] then
								return true
							end
						end
					end
				end
			end
		end
	end
	return false
end

function ItemsTabClass:IsItemValidForSlot(item, slotName, itemSet)
	itemSet = itemSet or self.activeItemSet
	local slotType, slotId = slotName:match("^([%a ]+) (%d+)$")
	if not slotType then
		slotType = slotName
	end
	if item.type == slotType then
		return true
	elseif item.type == "Blessing" then
		-- Use blessingData as source of truth (bases_1_4.json timeline fields are unreliable)
		local tlData = self.blessingData and self.blessingData[slotName]
		if not tlData then return false end
		for _, b in ipairs(tlData.normal or {}) do
			if b.name == item.name then return true end
		end
		for _, b in ipairs(tlData.grand or {}) do
			if b.name == item.name then return true end
		end
		return false
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
	elseif slotName == "Weapon 1" or slotName == "Weapon" then
		return item.base.weapon ~= nil
	elseif slotName == "Weapon 2" then
		local weapon1Sel = itemSet["Weapon 1"].selItemId or 0
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

-- Opens the item crafting popup (optionally with an existing crafted item to edit)
function ItemsTabClass:CraftItem(existingItem, slotName)
	local popup = new("CraftingPopup", self, existingItem, slotName)
	t_insert(main.popups, 1, popup)
end

-- Opens the blessing selection popup (optionally pre-selecting a timeline)
function ItemsTabClass:EditBlessings(initialTL)
	local popup = new("BlessingsPopup", self, initialTL)
	t_insert(main.popups, 1, popup)
end

-- Public wrapper so BlessingsPopup can call via colon syntax
function ItemsTabClass:UpdateBlessingSlot(tl, blessEntry, rollFrac)
	self.updateBlessingSlot(tl, blessEntry, rollFrac)
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
				tooltip:AddLine(16, s_format("^7%s: %s%s", slot.label, itemDisplayColor(item), item.name))
			end
		end
	end
end

function ItemsTabClass:FormatItemSource(text)
	return text:gsub("unique{([^}]+)}",colorCodes.UNIQUE.."%1"..colorCodes.SOURCE)
			   :gsub("normal{([^}]+)}",colorCodes.NORMAL.."%1"..colorCodes.SOURCE)
			   :gsub("currency{([^}]+)}",colorCodes.CURRENCY.."%1"..colorCodes.SOURCE)
end

function ItemsTabClass:AddItemTooltip(tooltip, item, slot, dbMode)
	-- Item name
	local rarityCode = itemDisplayColor(item)
	tooltip.center = true
	tooltip.color = rarityCode
	if item.title then
		tooltip:AddLine(20, rarityCode..item.title)
		tooltip:AddLine(20, rarityCode..item.baseName:gsub(" %(.+%)",""))
	else
		tooltip:AddLine(20, rarityCode..item.namePrefix..item.baseName:gsub(" %(.+%)","")..item.nameSuffix)
	end
	if item.rarity == "EXALTED" then
		tooltip:AddLine(16, colorCodes.EXALTED.."Exalted Item")
	elseif item.rarity == "LEGENDARY" then
		tooltip:AddLine(16, colorCodes.LEGENDARY.."Legendary Item")
	elseif item.rarity == "SET" then
		tooltip:AddLine(16, colorCodes.SET.."Set Item")
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

	-- Item Set / Set Bonuses panel (mirrors CraftingPopup DrawSetInfo).
	-- Trigger when the item is a real SET, or when setInfo is attached
	-- (e.g. a freshly crafted Reforged basic item), or when the title matches
	-- a known set member (covers saved-and-reloaded items where setInfo was
	-- stripped by BuildRaw).
	do
		local ver = (self.build and self.build.targetVersion) or "1_4"
		local setData = loadSetDataForTooltip(ver)
		local setId, setName, bonus
		if item.setInfo and item.setInfo.setId ~= nil then
			setId   = item.setInfo.setId
			setName = item.setInfo.name
			bonus   = item.setInfo.bonus
		end
		if (not setId) and setData and item.title then
			local titleKey = item.title:gsub(" Reforged$", "")
			for _, e in pairs(setData) do
				if e.set and (e.name == item.title or e.name == titleKey) then
					setId   = e.set.setId
					setName = e.set.name
					bonus   = e.set.bonus
					break
				end
			end
		end
		if setId and setData then
			tooltip:AddSeparator(10)
			tooltip:AddLine(16, colorCodes.SET .. "ITEM SET")
			tooltip:AddLine(14, "^7" .. (setName or ""))
			-- Build equipped-name set for orange highlighting
			local equippedNames = {}
			local function markName(s)
				if not s or s == "" then return end
				equippedNames[s] = true
				local stripped = s:gsub(" Reforged$", "")
				if stripped ~= s then equippedNames[stripped] = true end
			end
			for _, sl in pairs(self.slots or {}) do
				local eq = sl.selItemId and self.items and self.items[sl.selItemId]
				if eq then
					if eq.setInfo and eq.setInfo.setId == setId then
						markName(eq.setInfo.name)
						markName(eq.title)
					elseif eq.rarity == "SET" and eq.title then
						markName(eq.title)
					end
				end
			end
			-- Members
			local members = {}
			for _, si in pairs(setData) do
				if si.set and si.set.setId == setId then
					t_insert(members, si.name)
				end
			end
			table.sort(members)
			local ORANGE = "^xFF9933"
			for _, name in ipairs(members) do
				local col = equippedNames[name] and ORANGE or "^8"
				tooltip:AddLine(13, col .. name)
			end
			-- Bonuses
			if bonus and next(bonus) then
				tooltip:AddSeparator(6)
				tooltip:AddLine(16, colorCodes.SET .. "SET BONUSES")
				local keys = {}
				for k in pairs(bonus) do t_insert(keys, k) end
				table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
				for _, k in ipairs(keys) do
					tooltip:AddLine(13, "^8" .. k .. " set: ^7" .. tostring(bonus[k]))
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
			if self:IsItemValidForSlot(item, slotName) and not slot.inactive then
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
				header = string.format("^7Equipping this item in %s will give you:%s", slotLabel, selItem and "\n(replacing " .. itemDisplayColor(selItem) .. selItem.name .. "^7)" or "")
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