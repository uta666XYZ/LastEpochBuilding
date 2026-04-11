-- Last Epoch Building
--
-- Module: Tree Tab
-- Passive skill tree tab for the current build.
--
local ipairs = ipairs
local pairs = pairs
local next = next
local t_insert = table.insert
local t_remove = table.remove
local t_sort = table.sort
local t_concat = table.concat
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local m_abs = math.abs
local s_format = string.format
local s_gsub = string.gsub
local s_byte = string.byte
local dkjson = require "dkjson"

-- Layout constants for Maxroll-style header and skill bar
local HEADER_HEIGHT = 130
local SKILL_BAR_HEIGHT = 90

local TreeTabClass = newClass("TreeTab", "ControlHost", function(self, build)
	self.ControlHost()

	self.build = build
	self.isComparing = false

	-- Badge image cache for class/mastery icons
	self.badgeHandles = {}

	self.viewer = new("PassiveTreeView")
	self.viewer.filterMode = "passive"  -- TreeTab shows passive tree only (skill trees are in SkillsTab)
	self.viewer.selectedMastery = 0     -- Default: show base class tree (0=base, 1-3=masteries)
	self.viewer.disableDragging = true  -- No panning (Maxroll-style fixed layout)
	self.viewer.disableZooming = true   -- No zooming (Maxroll-style fixed layout)

	self.specList = { }
	self.specList[1] = new("PassiveSpec", build, latestTreeVersion)
	self:SetActiveSpec(1)
	self:SetCompareSpec(1)

	self.anchorControls = new("Control", nil, 0, 0, 0, 20)

	-- Tree list dropdown
	self.controls.specSelect = new("DropDownControl", {"LEFT",self.anchorControls,"RIGHT"}, 0, 0, 190, 20, nil, function(index, value)
		if self.specList[index] then
			self.build.modFlag = true
			self:SetActiveSpec(index)
		else
			self:OpenSpecManagePopup()
		end
	end)
	self.controls.specSelect.maxDroppedWidth = 1000
	self.controls.specSelect.enableDroppedWidth = true
	self.controls.specSelect.enableChangeBoxWidth = true
	self.controls.specSelect.controls.scrollBar.enabled = true
	self.controls.specSelect.tooltipFunc = function(tooltip, mode, selIndex, selVal)
		tooltip:Clear()
		if mode ~= "OUT" then
			local spec = self.specList[selIndex]
			if spec then
				local used = spec:CountAllocNodes()
				tooltip:AddLine(16, "Class: "..spec.curClassName)
				tooltip:AddLine(16, "Points used: "..used)
				if selIndex ~= self.activeSpec then
					local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator()
					if calcFunc then
						local output = calcFunc({ spec = spec }, {})
						self.build:AddStatComparesToTooltip(tooltip, calcBase, output, "^7Switching to this tree will give you:")
					end
				end
				tooltip:AddLine(16, "Game Version: "..treeVersions[spec.treeVersion].display)
			end
		end
	end

	-- Compare checkbox
	self.controls.compareCheck = new("CheckBoxControl", { "LEFT", self.controls.specSelect, "RIGHT" }, 74, 0, 20, "Compare:", function(state)
		self.isComparing = state
		self:SetCompareSpec(self.activeCompareSpec)
		self.controls.compareSelect.shown = state
		if state then
			self.controls.reset:SetAnchor("LEFT", self.controls.compareSelect, "RIGHT", nil, nil, nil)
		else
			self.controls.reset:SetAnchor("LEFT", self.controls.compareCheck, "RIGHT", nil, nil, nil)
		end
	end)

	-- Compare tree dropdown
	self.controls.compareSelect = new("DropDownControl", { "LEFT", self.controls.compareCheck, "RIGHT" }, 8, 0, 190, 20, nil, function(index, value)
		if self.specList[index] then
			self:SetCompareSpec(index)
		end
	end)
	self.controls.compareSelect.shown = false
	self.controls.compareSelect.maxDroppedWidth = 1000
	self.controls.compareSelect.enableDroppedWidth = true
	self.controls.compareSelect.enableChangeBoxWidth = true
	self.controls.reset = new("ButtonControl", { "LEFT", self.controls.compareCheck, "RIGHT" }, 8, 0, 60, 20, "Reset", function()
		main:OpenConfirmPopup("Reset Tree", "Are you sure you want to reset your passive tree?", "Reset", function()
			self.build.spec:ResetNodes()
			self.build.spec:BuildAllDependsAndPaths()
			self.build.spec:AddUndoState()
			self.build.buildFlag = true
		end)
	end)

	-- Tree Version Dropdown
	self.treeVersions = { }
	for _, num in ipairs(treeVersionList) do
		t_insert(self.treeVersions, treeVersions[num].display)
	end
	self.controls.versionText = new("LabelControl", { "LEFT", self.controls.reset, "RIGHT" }, 8, 0, 0, 16, "Version:")
	self.controls.versionSelect = new("DropDownControl", { "LEFT", self.controls.versionText, "RIGHT" }, 8, 0, 100, 20, self.treeVersions, function(index, value)
		if value ~= self.build.spec.treeVersion then
			self:OpenVersionConvertPopup(value:gsub("[%(%)]", ""):gsub("[%.%s]", "_"), true)
		end
	end)
	self.controls.versionSelect.maxDroppedWidth = 1000
	self.controls.versionSelect.enableDroppedWidth = true
	self.controls.versionSelect.enableChangeBoxWidth = true
	self.controls.versionSelect.selIndex = #self.treeVersions

	-- Tree Search Textbox
	self.controls.treeSearch = new("EditControl", { "LEFT", self.controls.versionSelect, "RIGHT" }, 8, 0, main.portraitMode and 200 or 300, 20, "", "Search", "%c", 100, function(buf)
		self.viewer.searchStr = buf
		self.searchFlag = buf ~= self.viewer.searchStrSaved
	end, nil, nil, true)
	self.controls.treeSearch.tooltipText = "Uses Lua pattern matching for complex searches"

	self.tradeLeaguesList = { }

	-- Show Node Power Checkbox
	self.controls.treeHeatMap = new("CheckBoxControl", { "LEFT", self.controls.treeSearch, "RIGHT" }, 130, 0, 20, "Show Node Power:", function(state)
		self.viewer.showHeatMap = state
		self.controls.treeHeatMapStatSelect.shown = state

		if state == false then
			self.controls.powerReportList.shown = false 
		end
	end)

	-- Control for setting max node depth to limit calculation time of the heat map
	self.controls.nodePowerMaxDepthSelect = new("DropDownControl",
	{ "LEFT", self.controls.treeHeatMap, "RIGHT" }, 8, 0, 50, 20, { "All", 5, 10, 15 }, function(index, value)
		local oldMax = self.build.calcsTab.nodePowerMaxDepth

		if type(value) == "number" then
			self.build.calcsTab.nodePowerMaxDepth = value
		else
			self.build.calcsTab.nodePowerMaxDepth = nil
		end

		-- If the heat map is shown, tell it to recalculate
		-- if the new value is larger than the old
		if oldMax ~= value and self.viewer.showHeatMap then
			if oldMax ~= nil and (self.build.calcsTab.nodePowerMaxDepth == nil or self.build.calcsTab.nodePowerMaxDepth > oldMax) then
				self:SetPowerCalc(self.build.calcsTab.powerStat)
			end
		end
	end)
	self.controls.nodePowerMaxDepthSelect.tooltipText = "Limit of Node distance to search (lower = faster)"

	-- Control for selecting the power stat to sort by (Defense, DPS, etc)
	self.controls.treeHeatMapStatSelect = new("DropDownControl", { "LEFT", self.controls.nodePowerMaxDepthSelect, "RIGHT" }, 8, 0, 150, 20, nil, function(index, value)
		self:SetPowerCalc(value)
	end)
	self.controls.treeHeatMap.tooltipText = function()
		local offCol, defCol = main.nodePowerTheme:match("(%a+)/(%a+)")
		return "When enabled, an estimate of the offensive and defensive strength of\neach unallocated passive is calculated and displayed visually.\nOffensive power shows as "..offCol:lower()..", defensive power as "..defCol:lower().."."
	end

	self.powerStatList = { }
	for _, stat in ipairs(data.powerStatList) do
		if not stat.ignoreForNodes then
			t_insert(self.powerStatList, stat)
		end
	end

	-- Show/Hide Power Report Button
	self.controls.powerReport = new("ButtonControl", { "LEFT", self.controls.treeHeatMapStatSelect, "RIGHT" }, 8, 0, 150, 20,
		function() return self.controls.powerReportList.shown and "Hide Power Report" or "Show Power Report" end, function()
		self.controls.powerReportList.shown = not self.controls.powerReportList.shown
	end)

	-- Power Report List
	local yPos = self.controls.treeHeatMap.y == 0 and self.controls.specSelect.height + 4 or self.controls.specSelect.height * 2 + 8
	self.controls.powerReportList = new("PowerReportListControl", {"TOPLEFT", self.controls.specSelect, "BOTTOMLEFT"}, 0, yPos, 700, 220, function(selectedNode)
		-- this code is called by the list control when the user "selects" one of the passives in the list.
		-- we use this to set a flag which causes the next Draw() to recenter the passive tree on the desired node.
		if selectedNode.x then
			self.jumpToNode = true
			self.jumpToX = selectedNode.x
			self.jumpToY = selectedNode.y
		end
	end)
	self.controls.powerReportList.shown = false
	self.build.powerBuilderCallback = function()
		local powerStat = self.build.calcsTab.powerStat or data.powerStatList[1]
		local report = self:BuildPowerReportList(powerStat)
		self.controls.powerReportList:SetReport(powerStat, report)
	end

	self.controls.specConvertText = new("LabelControl", { "BOTTOMLEFT", self.controls.specSelect, "TOPLEFT" }, 0, -14, 0, 16, "^7This is an older tree version, which may not be fully compatible with the current game version.")
	self.controls.specConvertText.shown = function()
		return self.showConvert
	end
	local function getLatestTreeVersion()
		return latestTreeVersion .. (self.specList[self.activeSpec].treeVersion:match("^" .. latestTreeVersion .. "(.*)") or "")
	end
	local function buildConvertButtonLabel()
		return colorCodes.POSITIVE.."Convert to "..treeVersions[getLatestTreeVersion()].display
	end
	local function buildConvertAllButtonLabel()
		return colorCodes.POSITIVE.."Convert all trees to "..treeVersions[getLatestTreeVersion()].display
	end
	self.controls.specConvert = new("ButtonControl", { "LEFT", self.controls.specConvertText, "RIGHT" }, 8, 0, function() return DrawStringWidth(16, "VAR", buildConvertButtonLabel()) + 20 end, 20, buildConvertButtonLabel, function()
		self:ConvertToVersion(getLatestTreeVersion(), false, true)
	end)
	self.controls.specConvertAll = new("ButtonControl", { "LEFT", self.controls.specConvert, "RIGHT" }, 8, 0, function() return DrawStringWidth(16, "VAR", buildConvertAllButtonLabel()) + 20 end, 20, buildConvertAllButtonLabel, function()
		self:OpenVersionConvertAllPopup(getLatestTreeVersion())
	end)
	self.jumpToNode = false
	self.jumpToX = 0
	self.jumpToY = 0
end)

function TreeTabClass:GetBadgeHandle(name)
	if not name then return nil end
	local key = name:lower():gsub(" ", "_")
	if not self.badgeHandles[key] then
		self.badgeHandles[key] = NewImageHandle()
		self.badgeHandles[key]:Load("TreeData/sprites/badge_" .. key .. ".png")
	end
	return self.badgeHandles[key]
end

-- Lazy-load a sprite from Assets/tree/ directory (extracted from panels_ui.webp)
function TreeTabClass:GetSpriteHandle(spriteName)
	local key = "sprite_" .. spriteName
	if not self.badgeHandles[key] then
		self.badgeHandles[key] = NewImageHandle()
		self.badgeHandles[key]:Load("Assets/tree/" .. spriteName .. ".png")
	end
	return self.badgeHandles[key]
end

-- Skill unlock data per mastery: maps mastery index to the skills unlocked
-- by spending points in that mastery's passive tree.
-- Format: { name = "SkillId", label = "Display Name", treeId = "treeId", level = unlockPoints }
-- level = nil means unlocked by selecting the mastery (star skill)
local MASTERY_SKILL_UNLOCKS = {
	-- Primalist (classId 0)
	["Primalist"] = {
		[0] = { -- Base class
			{ name = "Eterras Blessing", label = "Eterra's Blessing", treeId = "eb5656", level = 5, iconKey = "eterras_blessing" },
			{ name = "Warcry", label = "Warcry", treeId = "wc57", level = 10, iconKey = "warcry" },
			{ name = "SummonStormCrow", label = "Summon Storm Crows", treeId = "ssc50", level = 15, iconKey = "summon_storm_crows" },
			{ name = "SerpentStrike", label = "Serpent Strike", treeId = "st31et", level = 20, iconKey = "serpent_strike" },
		},
		[1] = { -- Beastmaster
			{ name = "SummonBear", label = "Summon Bear", treeId = "be36ar", level = 5, iconKey = "summon_bear" },
			{ name = "SummonScorpion", label = "Summon Scorpion", treeId = "sc36pi", level = 15, iconKey = "summon_scorpion" },
			{ name = "SummonFrenzyTotem", label = "Summon Frenzy Totem", treeId = "sf37", level = 25, iconKey = "summon_frenzy_totem" },
			{ name = "SummonSabertooth", label = "Summon Sabertooth", treeId = "sa36oh", level = 35, iconKey = "summon_sabertooth" },
		},
		[2] = { -- Shaman
			{ name = "Tornado", label = "Tornado", treeId = "to50", level = 5, iconKey = "tornado" },
			{ name = "EarthquakeSlam", label = "Earthquake", treeId = "eq5s", level = 15, iconKey = "earthquake" },
			{ name = "Avalanche", label = "Avalanche", treeId = "av75ch", level = 25, iconKey = "avalanche" },
		},
		[3] = { -- Druid
			{ name = "SprigganForm", label = "Spriggan Form", treeId = "sf5rd", level = 5, iconKey = "spriggan_form" },
			{ name = "SummonSpriggan", label = "Summon Spriggan", treeId = "sp38", level = 15, iconKey = "summon_spriggan" },
			{ name = "Swarmblade Form", label = "Swarmblade Form", treeId = "sbf4m", level = 25, iconKey = "swarmblade_form" },
			{ name = "EntanglingRoots", label = "Entangling Roots", treeId = "er6no", level = 35, iconKey = "entangling_roots" },
		},
	},
	-- Mage (classId 1)
	["Mage"] = {
		[0] = { -- Base class
			{ name = "Glacier", label = "Glacier", treeId = "gl14", level = 5 },
			{ name = "Disintegrate", label = "Disintegrate", treeId = "dig5", level = 10 },
			{ name = "VolcanicOrb", label = "Volcanic Orb", treeId = "vo54", level = 15 },
			{ name = "Focus", label = "Focus", treeId = "vm53dx", level = 20 },
		},
		[1] = { -- Sorcerer
			{ name = "StaticOrb", label = "Static Orb", treeId = "so35a", level = 5 },
			{ name = "IceBarrage", label = "Ice Barrage", treeId = "ib5g3", level = 15 },
			{ name = "ArcaneAscendance", label = "Arcane Ascendance", treeId = "arcas", level = 30 },
			{ name = "BlackHole", label = "Black Hole", treeId = "bh2", level = 40 },
		},
		[2] = { -- Spellblade
			{ name = "FlameReave", label = "Flame Reave", treeId = "fr11mv", level = 5 },
			{ name = "EnchantWeapon", label = "Enchant Weapon", treeId = "sb44eQ", level = 15 },
			{ name = "Firebrand", label = "Firebrand", treeId = "f1b4d", level = 30 },
			{ name = "Surge", label = "Surge", treeId = "su5g3", level = 40 },
		},
		[3] = { -- Runemaster
			{ name = "FlameRush", label = "Flame Rush", treeId = "fl71ds", level = 5 },
			{ name = "FrostWall", label = "Frost Wall", treeId = "fr4wl", level = 15 },
			{ name = "Runebolt", label = "Runebolt", treeId = "fb8fe", level = 30 },
			{ name = "GlyphOfDominion", label = "Glyph of Dominion", treeId = "gy2dm", level = 35 },
		},
	},
	-- Sentinel (classId 2)
	["Sentinel"] = {
		[0] = { -- Base class
			{ name = "Rebuke", label = "Rebuke", treeId = "re82ke", level = 5 },
			{ name = "ShieldRush", label = "Shield Rush", treeId = "sr31hu", level = 10 },
			{ name = "Multistrike", label = "Multistrike", treeId = "multis", level = 15 },
			{ name = "Smite", label = "Smite", treeId = "sm87r4", level = 20 },
		},
		[1] = { -- Void Knight
			{ name = "VolatileReversal", label = "Volatile Reversal", treeId = "vr53sl", level = 5 },
			{ name = "AbyssalEchoes", label = "Abyssal Echoes", treeId = "ab0lh", level = 10 },
			{ name = "DevouringOrb", label = "Devouring Orb", treeId = "do5vr", level = 15 },
			{ name = "Anomaly", label = "Anomaly", treeId = "an0my", level = 30 },
		},
		[2] = { -- Forge Guard
			{ name = "ShieldThrow", label = "Shield Throw", treeId = "st31io", level = 5 },
			{ name = "ManifestArmor", label = "Manifest Armor", treeId = "ma6hdr", level = 15 },
			{ name = "RingOfShields", label = "Ring of Shields", treeId = "rs31hi", level = 30 },
			{ name = "SmeltersWrath", label = "Smelter's Wrath", treeId = "st4th", level = 40 },
		},
		[3] = { -- Paladin
			{ name = "HealingHands", label = "Healing Hands", treeId = "hh7pa3", level = 5 },
			{ name = "SymbolsOfHope", label = "Symbols of Hope", treeId = "si4lgl", level = 15 },
			{ name = "Judgement", label = "Judgement", treeId = "pa67ju", level = 30 },
		},
	},
	-- Acolyte (classId 3)
	["Acolyte"] = {
		[0] = { -- Base class
			{ name = "HungeringSouls", label = "Hungering Souls", treeId = "hs18gu", level = 5 },
			{ name = "SummonBoneGolem", label = "Summon Bone Golem", treeId = "bg36nl", level = 10 },
			{ name = "SpiritPlague", label = "Spirit Plague", treeId = "sp5g2", level = 15 },
			{ name = "InfernalShade", label = "Infernal Shade", treeId = "is40", level = 20 },
		},
		[1] = { -- Necromancer
			{ name = "SummonSkeletalMage", label = "Summon Skeletal Mage", treeId = "sm4g", level = 5 },
			{ name = "Sacrifice", label = "Sacrifice", treeId = "sf31rc", level = 10 },
			{ name = "DreadShade", label = "Dread Shade", treeId = "ds4d3", level = 30 },
			{ name = "AssembleAbomination", label = "Assemble Abomination", treeId = "aa710", level = 40 },
		},
		[2] = { -- Lich
			{ name = "DrainLife", label = "Drain Life", treeId = "dl73", level = 5 },
			{ name = "AuraOfDecay", label = "Aura of Decay", treeId = "ad0ry", level = 10 },
			{ name = "Flay", label = "Flay", treeId = "fl44", level = 30 },
			{ name = "DeathSeal", label = "Death Seal", treeId = "ds34l", level = 35 },
		},
		[3] = { -- Warlock
			{ name = "ChaosBolts", label = "Chaos Bolts", treeId = "ch4bo", level = 5 },
			{ name = "Ghostflame", label = "Ghostflame", treeId = "gh0fl", level = 15 },
			{ name = "SoulFeast", label = "Soul Feast", treeId = "fe8at", level = 30 },
			{ name = "ProfaneVeil", label = "Profane Veil", treeId = "pr5fm", level = 35 },
		},
	},
	-- Rogue (classId 4)
	["Rogue"] = {
		[0] = { -- Base class
			{ name = "SmokeBomb", label = "Smoke Bomb", treeId = "smbmb", level = 5 },
			{ name = "Bladestorm", label = "Bladestorm", treeId = "bl5st", level = 10 },
			{ name = "SummonBallista", label = "Ballista", treeId = "ba1574", level = 15 },
			{ name = "UmbralBlades", label = "Umbral Blades", treeId = "ub5d9", level = 20 },
		},
		[1] = { -- Bladedancer
			{ name = "ShadowCascade", label = "Shadow Cascade", treeId = "dagg3", level = 5 },
			{ name = "SynchronizedStrike", label = "Synchronized Strike", treeId = "sync5", level = 10 },
			{ name = "LethalMirage", label = "Lethal Mirage", treeId = "mira59", level = 30 },
		},
		[2] = { -- Marksman
			{ name = "Multishot", label = "Multishot", treeId = "mush9", level = 5 },
			{ name = "DarkQuiver", label = "Dark Quiver", treeId = "dqv5", level = 15 },
			{ name = "Heartseeker", label = "Heartseeker", treeId = "htsk5", level = 30 },
			{ name = "HailOfArrows", label = "Hail of Arrows", treeId = "exvol8", level = 35 },
		},
		[3] = { -- Falconer
			{ name = "ExplosiveTrap", label = "Explosive Trap", treeId = "ex4tp", level = 5 },
			{ name = "Net", label = "Net", treeId = "ne01t", level = 15 },
			{ name = "AerialAssault", label = "Aerial Assault", treeId = "aa989", level = 30 },
			{ name = "DiveBomb", label = "Dive Bomb", treeId = "db992", level = 35 },
		},
	},
}

function TreeTabClass:GetMasterySkillUnlocks(spec, masteryIndex)
	local className = spec.curClassName or ""
	local classData = MASTERY_SKILL_UNLOCKS[className]
	if classData and classData[masteryIndex or 0] then
		return classData[masteryIndex or 0]
	end
	return {}
end

function TreeTabClass:Draw(viewPort, inputEvents)
	local spec = self.build.spec
	local tree = spec.tree

	self.anchorControls.x = viewPort.x + 4
	self.anchorControls.y = viewPort.y + viewPort.height - 24

	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "z" and IsKeyDown("CTRL") then
				self.build.spec:Undo()
				self.build.buildFlag = true
				inputEvents[id] = nil
			elseif event.key == "y" and IsKeyDown("CTRL") then
				self.build.spec:Redo()
				self.build.buildFlag = true
				inputEvents[id] = nil
			elseif event.key == "f" and IsKeyDown("CTRL") then
				self:SelectControl(self.controls.treeSearch)
			elseif event.key == "m" and IsKeyDown("CTRL") then
				self:OpenSpecManagePopup()
			end
		end
	end

	-- Handle badge clicks before processing controls
	local cursorX, cursorY = GetCursorPos()
	local badgeSize = 80
	local badgeGap = 6
	local badgeStartX = viewPort.x + 10
	local badgeY = viewPort.y + 6
	local isMouseDown = IsKeyDown("LEFTBUTTON")
	if not self.badgeMouseWasDown then self.badgeMouseWasDown = false end
	local badgeClicked = self.badgeMouseWasDown and not isMouseDown
	local inBadgeArea = cursorY >= badgeY and cursorY <= badgeY + badgeSize
		and cursorX >= badgeStartX and cursorX <= badgeStartX + 4 * (badgeSize + badgeGap)
	if isMouseDown and inBadgeArea then
		self.badgeMouseWasDown = true
	elseif not isMouseDown then
		self.badgeMouseWasDown = false
	end

	if badgeClicked and inBadgeArea then
		if cursorX >= badgeStartX and cursorX <= badgeStartX + badgeSize then
			self.viewer.selectedMastery = 0
		else
			if spec.curClass then
				for i, ascClass in ipairs(spec.curClass.classes) do
					local bx = badgeStartX + i * (badgeSize + badgeGap)
					if cursorX >= bx and cursorX <= bx + badgeSize then
						self.viewer.selectedMastery = i
						break
					end
				end
			end
		end
	end

	self:ProcessControlsInput(inputEvents, viewPort)

	-- Determine positions if one line of controls doesn't fit in the screen width
	local twoLineHeight = 24
	if viewPort.width >= 1336 + (self.isComparing and 198 or 0) + (self.viewer.showHeatMap and 316 or 0) then
		twoLineHeight = 0
		self.controls.treeSearch:SetAnchor("LEFT", self.controls.versionSelect, "RIGHT", 8, 0)
		self.controls.powerReportList:SetAnchor("TOPLEFT", self.controls.specSelect, "BOTTOMLEFT", 0, self.controls.specSelect.height + 4)
	else
		self.controls.treeSearch:SetAnchor("TOPLEFT", self.controls.specSelect, "BOTTOMLEFT", 0, 4)
		self.controls.powerReportList:SetAnchor("TOPLEFT", self.controls.treeSearch, "BOTTOMLEFT", 0, self.controls.treeHeatMap.y + self.controls.treeHeatMap.height + 4)
	end
	local convertTwoLineHeight = 24
	local convertMaxWidth = 900
	if viewPort.width >= convertMaxWidth then
		convertTwoLineHeight = 0
		self.controls.specConvert:SetAnchor("LEFT", self.controls.specConvertText, "RIGHT", 8, 0)
		self.controls.specConvertText:SetAnchor("BOTTOMLEFT", self.controls.specSelect, "TOPLEFT", 0, -14)
	else
		self.controls.specConvert:SetAnchor("TOPLEFT", self.controls.specConvertText, "BOTTOMLEFT", 0, 4)
		self.controls.specConvertText:SetAnchor("BOTTOMLEFT", self.controls.specSelect, "TOPLEFT", 0, -38)
	end

	local bottomDrawerHeight = self.controls.powerReportList.shown and 194 or 0
	self.controls.specSelect.y = -bottomDrawerHeight - twoLineHeight

	-- Calculate bottom controls height
	local bottomBarHeight = self.showConvert and 64 + bottomDrawerHeight + twoLineHeight or 32 + bottomDrawerHeight + twoLineHeight

	-- Tree viewport: shrink from top (header) and bottom (skill bar + controls)
	local treeViewPort = {
		x = viewPort.x,
		y = viewPort.y + HEADER_HEIGHT,
		width = viewPort.width,
		height = viewPort.height - HEADER_HEIGHT - SKILL_BAR_HEIGHT - bottomBarHeight
	}
	if self.jumpToNode then
		self.viewer:Focus(self.jumpToX, self.jumpToY, treeViewPort, self.build)
		self.jumpToNode = false
	end
	self.viewer.compareSpec = self.isComparing and self.specList[self.activeCompareSpec] or nil
	local treeInputEvents = {}
	for i, e in ipairs(inputEvents) do
		treeInputEvents[i] = e
	end
	self.viewer:Draw(self.build, treeViewPort, treeInputEvents)

	local newSpecList = self:GetSpecList()
	self.controls.compareSelect.selIndex = self.activeCompareSpec
	self.controls.compareSelect:SetList(newSpecList)
	t_insert(newSpecList, "Manage trees... (ctrl-m)")
	self.controls.specSelect.selIndex = self.activeSpec
	self.controls.specSelect:SetList(newSpecList)

	if not self.controls.treeSearch.hasFocus then
		self.controls.treeSearch:SetText(self.viewer.searchStr)
	end

	self.controls.treeHeatMap.state = self.viewer.showHeatMap
	self.controls.treeHeatMapStatSelect.shown = self.viewer.showHeatMap
	self.controls.treeHeatMapStatSelect.list = self.powerStatList
	self.controls.treeHeatMapStatSelect.selIndex = 1
	self.controls.treeHeatMapStatSelect:CheckDroppedWidth(true)
	if self.build.calcsTab.powerStat then
		self.controls.treeHeatMapStatSelect:SelByValue(self.build.calcsTab.powerStat.stat, "stat")
	end

	SetDrawLayer(1)

	-- =====================
	-- HEADER AREA (Maxroll-style class badges + name)
	-- =====================
	-- Frame logic (4 states):
	--   chosen  + viewing   -> class-base-selected  (circular bright,  ss2)
	--   chosen  + not view  -> class-base            (circular dark,    ss1)
	--   unchosen + viewing  -> class-mastery-selected (square bright,   ss4)
	--   unchosen + not view -> class-mastery          (square dark,     ss3)
	-- Base class is always "chosen".
	local selMastery = self.viewer.selectedMastery or 0
	local baseViewing = (selMastery == 0)
	local baseSprName = baseViewing and "badges/class-base-selected" or "badges/class-base"
	local baseBadgeSpr = self:GetSpriteHandle(baseSprName)
	SetDrawColor(1, 1, 1)
	DrawImage(baseBadgeSpr, badgeStartX, badgeY, badgeSize, badgeSize)

	if spec.curClass then
		for i, ascClass in ipairs(spec.curClass.classes) do
			local bx = badgeStartX + i * (badgeSize + badgeGap)
			local isViewing = (selMastery == i)
			local isChosen = ascClass.startNodeId and spec.allocNodes[ascClass.startNodeId]
			local ascSprName
			if isChosen then
				ascSprName = isViewing and "badges/class-base-selected" or "badges/class-base"
			else
				ascSprName = isViewing and "badges/class-mastery-selected" or "badges/class-mastery"
			end
			local ascBadgeSpr = self:GetSpriteHandle(ascSprName)
			SetDrawColor(1, 1, 1)
			DrawImage(ascBadgeSpr, bx, badgeY, badgeSize, badgeSize)
		end
	end

	-- Badge icon overlay (viewing = full brightness, not viewing = dimmed)
	local baseBadge = self:GetBadgeHandle(spec.curClassName)
	if baseBadge then
		SetDrawColor(baseViewing and 1 or 0.55, baseViewing and 1 or 0.55, baseViewing and 1 or 0.55)
		local iconInset = 6
		DrawImage(baseBadge, badgeStartX + iconInset, badgeY + iconInset, badgeSize - iconInset * 2, badgeSize - iconInset * 2)
	end
	if spec.curClass then
		for i, ascClass in ipairs(spec.curClass.classes) do
			local ascBadge = self:GetBadgeHandle(ascClass.name)
			if ascBadge then
				local bx = badgeStartX + i * (badgeSize + badgeGap)
				local isViewing = (selMastery == i)
				local c = isViewing and 1 or 0.55
				SetDrawColor(c, c, c)
				local iconInset = 6
				DrawImage(ascBadge, bx + iconInset, badgeY + iconInset, badgeSize - iconInset * 2, badgeSize - iconInset * 2)
			end
		end
	end

	-- Lock icon on non-allocated mastery badges (bottom-center of badge)
	if spec.curClass then
		local lockSpr = self:GetSpriteHandle("badges/class-mastery-locked")
		local lockSize = 32
		for i, ascClass in ipairs(spec.curClass.classes) do
			local isAllocated = false
			if ascClass.startNodeId and spec.allocNodes[ascClass.startNodeId] then
				isAllocated = true
			end
			if not isAllocated then
				local bx = badgeStartX + i * (badgeSize + badgeGap)
				SetDrawColor(1, 1, 1)
				DrawImage(lockSpr, bx + (badgeSize - lockSize) / 2, badgeY + badgeSize - lockSize - 2, lockSize, lockSize)
			end
		end
	end

	-- Class/mastery name display
	local nameX = badgeStartX + 4 * (badgeSize + badgeGap) + 16
	SetDrawColor(1, 1, 1)
	local selMastery = self.viewer.selectedMastery or 0
	if selMastery > 0 and spec.curClass then
		local ascClass = spec.curClass.classes[selMastery]
		local ascName = ascClass and ascClass.name or ("Mastery " .. selMastery)
		DrawString(nameX, viewPort.y + 8, "LEFT", 20, "VAR", "^7" .. ascName)
		DrawString(nameX, viewPort.y + 30, "LEFT", 14, "VAR", "^8PASSIVE BONUSES")
		if ascClass and ascClass.startNodeId then
			local startNode = spec.nodes[ascClass.startNodeId]
			if startNode and startNode.sd then
				local bonusY = viewPort.y + 48
				for idx, line in ipairs(startNode.sd) do
					if idx <= 3 then
						DrawString(nameX + 8, bonusY, "LEFT", 12, "VAR", "^x8888FF" .. "* " .. line)
						bonusY = bonusY + 16
					end
				end
			end
		end
	else
		DrawString(nameX, viewPort.y + 12, "LEFT", 20, "VAR", "^7" .. (spec.curClassName or "No Class"))
		DrawString(nameX, viewPort.y + 36, "LEFT", 14, "VAR", "^8BASE CLASS")
	end

	-- Unspent points display
	local used = spec:CountAllocNodes()
	local unspentText = (113 - used) .. " UNSPENT POINTS"
	local unspentY = viewPort.y + HEADER_HEIGHT - 22
	SetDrawColor(1, 1, 1)
	DrawString(viewPort.x + viewPort.width / 2, unspentY, "CENTER_X", 14, "VAR", "^x8888AA" .. unspentText)

	-- =====================
	-- SKILL UNLOCK BAR (gold progress line with skill icons)
	-- =====================
	local skillBarY = viewPort.y + viewPort.height - bottomBarHeight - SKILL_BAR_HEIGHT

	SetDrawColor(0.05, 0.05, 0.08)
	DrawImage(nil, viewPort.x, skillBarY, viewPort.width, SKILL_BAR_HEIGHT)

	local masterySkills = self:GetMasterySkillUnlocks(spec, selMastery)

	-- Calculate points spent in current mastery
	local masteryPointsSpent = 0
	for nodeId, node in pairs(spec.allocNodes) do
		if nodeId:match("^" .. (spec.curClassName or "")) and node.mastery == selMastery then
			if node.type ~= "ClassStart" and node.type ~= "AscendClassStart" then
				masteryPointsSpent = masteryPointsSpent + (node.alloc or 0)
			end
		end
	end

	local maxSkillLevel = 0
	local minUnlockLevel = 999
	for _, sk in ipairs(masterySkills) do
		if sk.level then
			if sk.level > maxSkillLevel then maxSkillLevel = sk.level end
			if sk.level < minUnlockLevel then minUnlockLevel = sk.level end
		end
	end
	if maxSkillLevel == 0 then maxSkillLevel = 20 end
	if minUnlockLevel == 999 then minUnlockLevel = 5 end
	-- Tree point cap: base class = 25, mastery = 45
	local maxUnlockLevel = (selMastery == 0) and 25 or 45

	local numSkills = #masterySkills
	local frameSizeLocked   = 68  -- Skill_Locked_Default: 143px source
	local frameSizeUnlocked = 75  -- Skill_Learned_Default: 158px source, scaled to match locked visual size
	local iconSize = 52
	local fs2 = frameSizeLocked / 2  -- used for drop-line positioning (locked is baseline)
	local slotY = skillBarY + 50

	-- Align bar with the leftmost/rightmost passive node columns in the tree viewport
	local lineLeft, lineRight
	local vwrScale = self.viewer.currentScale
	local vwrOffX = self.viewer.currentOffsetX
	local passMinX = self.viewer.passiveNodeMinX
	local passMaxX = self.viewer.passiveNodeMaxX
	if vwrScale and vwrOffX and passMinX and passMaxX then
		lineLeft = m_max(viewPort.x + 10, passMinX * vwrScale + vwrOffX)
		lineRight = m_min(viewPort.x + viewPort.width - 10, passMaxX * vwrScale + vwrOffX)
	else
		local barPadding = 50
		lineLeft = viewPort.x + barPadding
		lineRight = viewPort.x + viewPort.width - barPadding
	end
	local lineWidth = lineRight - lineLeft
	local lineY = skillBarY + 14

	local progressFrac = m_min(1.0, masteryPointsSpent / maxUnlockLevel)
	local progressX = lineLeft + lineWidth * progressFrac

	-- Progress bar assets
	local barBgHandle = self:GetSpriteHandle("passive-slider-bg")
	local barHorizFillHandle = self:GetSpriteHandle("progress-fill")
	local sliderBarHandle = self:GetSpriteHandle("passive-slider-bar")
	local barBgH = 34
	local barFillH = 12

	-- Draw full background track (includes ornate arrow endpoints)
	SetDrawColor(1, 1, 1)
	DrawImage(barBgHandle, lineLeft - 30, lineY - barBgH / 2, lineWidth + 60, barBgH)

	-- Draw gold fill using progress-fill.png (horizontal bar asset)
	if progressFrac > 0 then
		SetDrawColor(1, 1, 1)
		DrawImage(barHorizFillHandle, lineLeft, lineY - barFillH / 2, progressX - lineLeft, barFillH)
	end

	-- Tick marks on progress bar (1 per point, taller every 5 points)
	for pt = 1, maxUnlockLevel - 1 do
		local tickX = lineLeft + lineWidth * (pt / maxUnlockLevel)
		local isPassed = masteryPointsSpent >= pt
		if pt % 5 == 0 then
			-- Large tick (diamond marker) every 5 points
			local tickH = 16
			if isPassed then
				SetDrawColor(1, 0.85, 0.2)
			else
				SetDrawColor(0.35, 0.30, 0.12)
			end
			DrawImage(nil, tickX - 1, lineY - tickH / 2, 2, tickH)
		else
			-- Small tick every 1 point
			local tickH = 8
			if isPassed then
				SetDrawColor(0.8, 0.68, 0.15)
			else
				SetDrawColor(0.25, 0.22, 0.08)
			end
			DrawImage(nil, tickX, lineY - tickH / 2, 1, tickH)
		end
	end

	-- Native aspect ratio for passive-slider-bar / passive-lock-bar (19x372)
	local barNativeW = 19
	local barNativeH = 372
	local barAspect = barNativeW / barNativeH
	local barTop = viewPort.y + HEADER_HEIGHT

	-- Passive lock bar at 22.5/45 midpoint for unselected mastery trees
	-- Disappears when this mastery is the build's chosen mastery
	-- Medallion (bottom of image) sits on the progress bar
	if selMastery > 0 and spec.curAscendClassId ~= selMastery then
		local lockBarHandle = self:GetSpriteHandle("passive-lock-bar")
		local lockFrac = 22.5 / maxUnlockLevel
		local lockX = lineLeft + lineWidth * lockFrac
		local lockBot = lineY + 20
		local lockH = lockBot - barTop
		local lockW = lockH * barAspect
		SetDrawColor(1, 1, 1)
		DrawImage(lockBarHandle, lockX - lockW / 2, barTop, lockW, lockH)
	end

	-- Upward vertical indicator line from progress bar to tree bottom (Maxroll-style)
	local sliderBot = lineY + 6
	local sliderH = sliderBot - barTop
	local sliderW = sliderH * barAspect
	SetDrawColor(1, 0.85, 0.2)
	DrawImage(sliderBarHandle, progressX - sliderW / 2, barTop, sliderW, sliderH)

	local frameHandle = self:GetSpriteHandle("skill-icon-frame")
	local frameLockedHandle = self:GetSpriteHandle("skill-icon-frame-locked")
	local levelBadgeHandle = self:GetSpriteHandle("skill-req-mastery-level")
	local levelLockedHandle = self:GetSpriteHandle("skill-req-mastery-level")

	if numSkills > 0 then
		for idx, sk in ipairs(masterySkills) do
			local frac = (sk.level or (idx * 5)) / maxUnlockLevel
			local slotCenterX = lineLeft + lineWidth * frac
			local isUnlocked = masteryPointsSpent >= (sk.level or 0)

			-- Vertical drop line from bar to skill frame using passive-slider-bar
			-- The asset is 19x372 vertical: diamond at top, gold line descending
			local dropTop = lineY - 6
			local dropBot = slotY - fs2
			local dropW = 19
			if isUnlocked then
				SetDrawColor(1, 1, 1)
			else
				SetDrawColor(0.25, 0.22, 0.10)
			end
			DrawImage(sliderBarHandle, slotCenterX - dropW / 2, dropTop, dropW, dropBot - dropTop)

			-- Skill icon (drawn first so frame overlays on top)
			local rootNodeId = sk.treeId and (sk.treeId .. "-0") or nil
			local rootNode = rootNodeId and spec.nodes[rootNodeId] or nil
			local iconName = rootNode and rootNode.icon or nil
			if iconName then
				local squareName = iconName:gsub("%-root$", "")
				local cacheKey = "sqicon_" .. squareName
				if not self.badgeHandles[cacheKey] then
					self.badgeHandles[cacheKey] = NewImageHandle()
					self.badgeHandles[cacheKey]:Load("TreeData/sprites/" .. squareName .. ".png")
					local w, h = self.badgeHandles[cacheKey]:ImageSize()
					if (not w or w == 0) and squareName ~= iconName then
						self.badgeHandles[cacheKey]:Load("TreeData/sprites/" .. iconName .. ".png")
					end
				end
				local iconHandle = self.badgeHandles[cacheKey]
				if iconHandle then
					if isUnlocked then
						SetDrawColor(1, 1, 1)
					else
						SetDrawColor(0.35, 0.35, 0.35)
					end
					DrawImage(iconHandle, slotCenterX - iconSize / 2, slotY - iconSize / 2, iconSize, iconSize)
				end
			end

			-- Skill frame (drawn on top of icon to contain it visually)
			if isUnlocked then
				local fh = frameSizeUnlocked / 2
				SetDrawColor(1, 1, 1)
				DrawImage(frameHandle, slotCenterX - fh, slotY - fh, frameSizeUnlocked, frameSizeUnlocked)
			else
				SetDrawColor(0.6, 0.6, 0.6)
				DrawImage(frameLockedHandle, slotCenterX - fs2, slotY - fs2, frameSizeLocked, frameSizeLocked)
			end

			-- Level badge (centered on skill icon)
			if sk.level then
				local lvBadgeW = 38
				local lvBadgeH = 32
				local lvBadgeX = slotCenterX - lvBadgeW / 2
				local lvBadgeY = slotY - lvBadgeH / 2
				if isUnlocked then
					SetDrawColor(1, 1, 1)
					DrawImage(levelBadgeHandle, lvBadgeX, lvBadgeY, lvBadgeW, lvBadgeH)
				else
					SetDrawColor(0.6, 0.6, 0.6)
					DrawImage(levelLockedHandle, lvBadgeX, lvBadgeY, lvBadgeW, lvBadgeH)
				end
				SetDrawColor(1, 1, 1)
				DrawString(lvBadgeX + lvBadgeW / 2, lvBadgeY + lvBadgeH / 2 - 5, "CENTER_X", 10, "VAR", "^7" .. tostring(sk.level))
			end

			-- Skill name below frame
			local skillName = (sk.label or sk.name or ""):upper()
			if isUnlocked then
				SetDrawColor(1, 1, 1)
			else
				SetDrawColor(0.4, 0.4, 0.4)
			end
			DrawString(slotCenterX, slotY + fs2 + 4, "CENTER_X", 9, "VAR", skillName)
		end
	end

	-- =====================
	-- BOTTOM CONTROLS BAR
	-- =====================
	SetDrawColor(0.05, 0.05, 0.05)
	DrawImage(nil, viewPort.x, viewPort.y + viewPort.height - (28 + bottomDrawerHeight + twoLineHeight), viewPort.width, 28 + bottomDrawerHeight + twoLineHeight)
	if self.showConvert then
		local height = viewPort.width < convertMaxWidth and (bottomDrawerHeight + twoLineHeight) or 0
		SetDrawColor(0.05, 0.05, 0.05)
		DrawImage(nil, viewPort.x, viewPort.y + viewPort.height - (60 + bottomDrawerHeight + twoLineHeight + convertTwoLineHeight), viewPort.width, 28 + height)
		SetDrawColor(0.85, 0.85, 0.85)
		DrawImage(nil, viewPort.x, viewPort.y + viewPort.height - (64 + bottomDrawerHeight + twoLineHeight + convertTwoLineHeight), viewPort.width, 4)
	end
	SetDrawColor(0.85, 0.85, 0.85)
	DrawImage(nil, viewPort.x, viewPort.y + viewPort.height - (32 + bottomDrawerHeight + twoLineHeight), viewPort.width, 4)

	self:DrawControls(viewPort)
end

function TreeTabClass:GetSpecList()
	local newSpecList = { }
	for _, spec in ipairs(self.specList) do
		t_insert(newSpecList, (spec.treeVersion ~= latestTreeVersion and ("["..treeVersions[spec.treeVersion].display.."] ") or "")..(spec.title or "Default"))
	end
	return newSpecList
end

function TreeTabClass:Load(xml, dbFileName)
	self.specList = { }
	if xml.elem == "Spec" then
		-- Import single spec from old build
		self.specList[1] = new("PassiveSpec", self.build, defaultTreeVersion)
		self.specList[1]:Load(xml, dbFileName)
		self.activeSpec = 1
		self.build.spec = self.specList[1]
		return
	end
	for _, node in pairs(xml) do
		if type(node) == "table" then
			if node.elem == "Spec" then
				if node.attrib.treeVersion and not treeVersions[node.attrib.treeVersion] then
					main:OpenMessagePopup("Unknown Passive Tree Version", "The build you are trying to load uses an unrecognised version of the passive skill tree.\nYou may need to update the program before loading this build.")
					return true
				end
				local newSpec = new("PassiveSpec", self.build, node.attrib.treeVersion or defaultTreeVersion)
				newSpec:Load(node, dbFileName)
				t_insert(self.specList, newSpec)
			end
		end
	end
	if not self.specList[1] then
		self.specList[1] = new("PassiveSpec", self.build, latestTreeVersion)
	end
	self:SetActiveSpec(tonumber(xml.attrib.activeSpec) or 1)
end

function TreeTabClass:PostLoad()
	for _, spec in ipairs(self.specList) do
		spec:PostLoad()
	end
end

function TreeTabClass:Save(xml)
	xml.attrib = {
		activeSpec = tostring(self.activeSpec)
	}
	for specId, spec in ipairs(self.specList) do
		local child = {
			elem = "Spec"
		}
		spec:Save(child)
		t_insert(xml, child)
	end
end

function TreeTabClass:SetActiveSpec(specId)
	local prevSpec = self.build.spec
	self.activeSpec = m_min(specId, #self.specList)
	local curSpec = self.specList[self.activeSpec]
	self.build.spec = curSpec
	self.build.buildFlag = true
	self.build.spec:SetWindowTitleWithBuildClass()
	self.showConvert = not curSpec.treeVersion:match("^" .. latestTreeVersion)
	if self.build.itemsTab.itemOrderList[1] then
		-- Update item slots if items have been loaded already
		self.build.itemsTab:PopulateSlots()
	end
	-- Update the passive tree dropdown control in itemsTab
	self.build.itemsTab.controls.specSelect.selIndex = specId
	-- Update Version dropdown to active spec's
	if self.controls.versionSelect then
		self.controls.versionSelect:SelByValue(curSpec.treeVersion:gsub("%_", "."):gsub(".ruthless", " (ruthless)"))
	end
end

function TreeTabClass:SetCompareSpec(specId)
	self.activeCompareSpec = m_min(specId, #self.specList)
	local curSpec = self.specList[self.activeCompareSpec]

	self.compareSpec = curSpec
end

function TreeTabClass:ConvertToVersion(version, remove, success, ignoreRuthlessCheck)
	if not ignoreRuthlessCheck and self.build.spec.treeVersion:match("ruthless") and not version:match("ruthless") then
		if isValueInTable(treeVersionList, version.."_ruthless") then
			version = version.."_ruthless"
		end
	end
	local newSpec = new("PassiveSpec", self.build, version)
	newSpec.title = self.build.spec.title
	newSpec:RestoreUndoState(self.build.spec:CreateUndoState(), version)
	t_insert(self.specList, self.activeSpec + 1, newSpec)
	if remove then
		t_remove(self.specList, self.activeSpec)
		-- activeSpec + 1 is shifted down one on remove, otherwise we would set the spec below it if it exists
		self:SetActiveSpec(self.activeSpec)
	else
		self:SetActiveSpec(self.activeSpec + 1)
	end
	self.modFlag = true
	if success then
		main:OpenMessagePopup("Tree Converted", "The tree has been converted to "..treeVersions[version].display..".\nNote that some or all of the passives may have been de-allocated due to changes in the tree.\n\nYou can switch back to the old tree using the tree selector at the bottom left.")
	end
end

function TreeTabClass:ConvertAllToVersion(version)
	local currActiveSpec = self.activeSpec
	local specVersionList = { }
	for _, spec in ipairs(self.specList) do
		t_insert(specVersionList, spec.treeVersion)
	end
	for index, specVersion in ipairs(specVersionList) do
		if specVersion ~= version then
			self:SetActiveSpec(index)
			self:ConvertToVersion(version, true, false)
		end
	end
	self:SetActiveSpec(currActiveSpec)
end

function TreeTabClass:OpenSpecManagePopup()
	local importTree =
		new("ButtonControl", nil, -99, 259, 90, 20, "Import Tree", function()
			self:OpenImportPopup()
		end)
	local exportTree =
		new("ButtonControl", { "LEFT", importTree, "RIGHT" }, 8, 0, 90, 20, "Export Tree", function()
			self:OpenExportPopup()
		end)

	main:OpenPopup(370, 290, "Manage Passive Trees", {
		new("PassiveSpecListControl", nil, 0, 50, 350, 200, self),
		importTree,
		exportTree,
		new("ButtonControl", {"LEFT", exportTree, "RIGHT"}, 8, 0, 90, 20, "Done", function()
			main:ClosePopup()
		end),
	})
end

function TreeTabClass:OpenVersionConvertPopup(version, ignoreRuthlessCheck)
	local controls = { }
	controls.warningLabel = new("LabelControl", nil, 0, 20, 0, 16, "^7Warning: some or all of the passives may be de-allocated due to changes in the tree.\n\n" ..
		"Convert will replace your current tree.\nCopy + Convert will backup your current tree.\n")
	controls.convert = new("ButtonControl", nil, -125, 105, 100, 20, "Convert", function()
		self:ConvertToVersion(version, true, false, ignoreRuthlessCheck)
		main:ClosePopup()
	end)
	controls.convertCopy = new("ButtonControl", nil, 0, 105, 125, 20, "Copy + Convert", function()
		self:ConvertToVersion(version, false, false, ignoreRuthlessCheck)
		main:ClosePopup()
	end)
	controls.cancel = new("ButtonControl", nil, 125, 105, 100, 20, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(570, 140, "Convert to Version "..treeVersions[version].display, controls, "convert", "edit")
end

function TreeTabClass:OpenVersionConvertAllPopup(version)
	local controls = { }
	controls.warningLabel = new("LabelControl", nil, 0, 20, 0, 16, "^7Warning: some or all of the passives may be de-allocated due to changes in the tree.\n\n" ..
		"Convert will replace all trees that are not Version "..treeVersions[version].display..".\nThis action cannot be undone.\n")
	controls.convert = new("ButtonControl", nil, -58, 105, 100, 20, "Convert", function()
		self:ConvertAllToVersion(version)
		main:ClosePopup()
	end)
	controls.cancel = new("ButtonControl", nil, 58, 105, 100, 20, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(570, 140, "Convert all to Version "..treeVersions[version].display, controls, "convert", "edit")
end

function TreeTabClass:OpenImportPopup()
	local versionLookup = "tree/([0-9]+)%.([0-9]+)%.([0-9]+)/"
	local controls = { }
	local function decodePoePlannerTreeLink(treeLink)
		-- treeVersion is not known at this point. We need to decode the URL to get it.
		local tmpSpec = new("PassiveSpec", self.build, latestTreeVersion)
		local newTreeVersion_or_errMsg = tmpSpec:DecodePoePlannerURL(treeLink, true)
		-- Check for an error message
		if string.find(newTreeVersion_or_errMsg, "Invalid") then
			controls.msg.label = "^1"..newTreeVersion_or_errMsg
			return
		end

		-- 20230908. We always create a new Spec()
		local newSpec = new("PassiveSpec", self.build, newTreeVersion_or_errMsg)
		newSpec.title = controls.name.buf
		newSpec:DecodePoePlannerURL(treeLink, false)  --DecodePoePlannerURL was used above and URL proven correct.
		t_insert(self.specList, newSpec)
		-- trigger all the things that go with changing a spec
		self:SetActiveSpec(#self.specList)
		self.modFlag = true
		self.build.spec:AddUndoState()
		self.build.buildFlag = true
		main:ClosePopup()
	end

	local function decodeTreeLink(treeLink, newTreeVersion)
		-- newTreeVersion is passed in as an output of validateTreeVersion(). It will always be a valid tree version text string
		-- 20230908. We always create a new Spec()
		local newSpec = new("PassiveSpec", self.build, newTreeVersion)
		newSpec.title = controls.name.buf
		local errMsg = newSpec:DecodeURL(treeLink)
		if errMsg then
			controls.msg.label = "^1"..errMsg.."^7"
		else
			t_insert(self.specList, newSpec)
			-- trigger all the things that go with changing a spec
			self:SetActiveSpec(#self.specList)
			self.modFlag = true
			self.build.spec:AddUndoState()
			self.build.buildFlag = true
			main:ClosePopup()
		end
	end
	local function validateTreeVersion(isRuthless, major, minor)
		-- Take the Major and Minor version numbers and confirm it is a valid tree version. The point release is also passed in but it is not used
		-- Return: the passed in tree version as text or latestTreeVersion
		if major and minor then
			--need leading 0 here
			local newTreeVersionNum = tonumber(string.format("%d.%02d", major, minor))
			if newTreeVersionNum >= treeVersions[defaultTreeVersion].num and newTreeVersionNum <= treeVersions[latestTreeVersion].num then
				-- no leading 0 here
				return string.format("%s_%s", major, minor) .. (isRuthless and "_ruthless" or "")
			else
				print(string.format("Version '%d_%02d' is out of bounds", major, minor))
			end
		end
		return latestTreeVersion .. (isRuthless and "_ruthless" or "")
	end

	controls.nameLabel = new("LabelControl", nil, -180, 20, 0, 16, "Enter name for this passive tree:")
	controls.name = new("EditControl", nil, 100, 20, 350, 18, "", nil, nil, nil, function(buf)
		controls.msg.label = ""
		controls.import.enabled = buf:match("%S") and controls.edit.buf:match("%S")
	end)
	controls.editLabel = new("LabelControl", nil, -150, 45, 0, 16, "Enter passive tree link:")
	controls.edit = new("EditControl", nil, 100, 45, 350, 18, "", nil, nil, nil, function(buf)
		controls.msg.label = ""
		controls.import.enabled = buf:match("%S") and controls.name.buf:match("%S")
	end)
	controls.msg = new("LabelControl", nil, 0, 65, 0, 16, "")
	controls.import = new("ButtonControl", nil, -45, 85, 80, 20, "Import", function()
		local treeLink = controls.edit.buf
		if #treeLink == 0 then
			return
		end
		-- EG: http://poeurl.com/dABz
		if treeLink:match("poeurl%.com/") then
			controls.import.enabled = false
			controls.msg.label = "Resolving PoEURL link..."
			local id = LaunchSubScript([[
				local treeLink = ...
				local curl = require("lcurl.safe")
				local easy = curl.easy()
				easy:setopt_url(treeLink)
				easy:setopt_writefunction(function(data)
					return true
				end)
				easy:perform()
				local redirect = easy:getinfo(curl.INFO_REDIRECT_URL)
				easy:close()
				if not redirect or redirect:match("poeurl%.com/") then
					return nil, "Failed to resolve PoEURL link"
				end
				return redirect
			]], "", "", treeLink)
			if id then
				launch:RegisterSubScript(id, function(treeLink, errMsg)
					if errMsg then
						controls.msg.label = "^1"..errMsg.."^7"
						controls.import.enabled = true
						return
					else
						decodeTreeLink(treeLink, validateTreeVersion(treeLink:match("tree/ruthless"), treeLink:match(versionLookup)))
					end
				end)
			end
		elseif treeLink:match("poeplanner.com/") then
			decodePoePlannerTreeLink(treeLink:gsub("/%?v=.+#","/"))
		elseif treeLink:match("poeskilltree.com/") then
			local oldStyleVersionLookup = "/%?v=([0-9]+)%.([0-9]+)%.([0-9]+)%-?r?u?t?h?l?e?s?s?#"
			-- Strip the version from the tree : https://poeskilltree.com/?v=3.6.0#AAAABAMAABEtfIOFMo6-ksHfsOvu -> https://poeskilltree.com/AAAABAMAABEtfIOFMo6-ksHfsOvu
			decodeTreeLink(treeLink:gsub("/%?v=.+#","/"), validateTreeVersion(treeLink:match("-ruthless#"), treeLink:match(oldStyleVersionLookup)))
		else
			-- EG: https://www.pathofexile.com/passive-skill-tree/3.15.0/AAAABgMADI6-HwKSwQQHLJwtH9-wTLNfKoP3ES3r5AAA
			-- EG: https://www.pathofexile.com/fullscreen-passive-skill-tree/3.15.0/AAAABgMADAQHES0fAiycLR9Ms18qg_eOvpLB37Dr5AAA
			-- EG: https://www.pathofexile.com/passive-skill-tree/ruthless/AAAABgAAAAAA (Ruthless doesn't have versions)
			decodeTreeLink(treeLink, validateTreeVersion(treeLink:match("tree/ruthless"), treeLink:match(versionLookup)))
		end
	end)
	controls.import.enabled = false
	controls.cancel = new("ButtonControl", nil, 45, 85, 80, 20, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(580, 115, "Import Tree", controls, "import", "name")
end

function TreeTabClass:OpenExportPopup()
	local treeLink = self.build.spec:EncodeURL(treeVersions[self.build.spec.treeVersion].url)
	local popup
	local controls = { }
	controls.label = new("LabelControl", nil, 0, 20, 0, 16, "Passive tree link:")
	controls.edit = new("EditControl", nil, 0, 40, 350, 18, treeLink, nil, "%Z")
	controls.shrink = new("ButtonControl", nil, -90, 70, 140, 20, "Shrink with PoEURL", function()
		controls.shrink.enabled = false
		controls.shrink.label = "Shrinking..."
		launch:DownloadPage("http://poeurl.com/shrink.php?url="..treeLink, function(response, errMsg)
			controls.shrink.label = "Done"
			if errMsg or not response.body:match("%S") then
				main:OpenMessagePopup("PoEURL Shortener", "Failed to get PoEURL link. Try again later.")
			else
				treeLink = "http://poeurl.com/"..response.body
				controls.edit:SetText(treeLink)
				popup:SelectControl(controls.edit)
			end
		end)
	end)
	controls.copy = new("ButtonControl", nil, 30, 70, 80, 20, "Copy", function()
		Copy(treeLink)
	end)
	controls.done = new("ButtonControl", nil, 120, 70, 80, 20, "Done", function()
		main:ClosePopup()
	end)
	popup = main:OpenPopup(380, 100, "Export Tree", controls, "done", "edit")
end

function TreeTabClass:ModifyNodePopup(selectedNode)
	local controls = { }
	local function addModifier(selectedNode)
		local stats = {}
		for line in controls.stats.buf:gmatch("([^\n]*)\n?") do
			local strippedLine = StripEscapes(line):gsub("^[%s?]+", ""):gsub("[%s?]+$", "")
			if strippedLine ~= "" then
				t_insert(stats, strippedLine)
			end
		end
		self.build.spec.hashOverrides[selectedNode.id] = stats
		self.build.spec:BuildAllDependsAndPaths()
	end

	local stats = ""
	for _,stat in ipairs(selectedNode.stats) do
		stats = stats .. stat .. "\n"
	end
	for _,stat in ipairs(selectedNode.notScalingStats) do
		stats = stats .. "{NotScaling}" .. stat .. "\n"
	end
	controls.stats = new("EditControl", nil, 0, 20, 550, 120, stats, nil, "^%C\t\n", nil, nil, 16)
	controls.stats.inactiveText = function(val)
		local inactiveText = ""
		for line in val:gmatch("([^\n]*)\n?") do
			local strippedLine = StripEscapes(line):gsub("^[%s?]+", ""):gsub("[%s?]+$", "")
			local mods, extra = modLib.parseMod(strippedLine)
			inactiveText = inactiveText .. ((mods and not extra) and colorCodes.MAGIC or colorCodes.UNSUPPORTED).. (IsKeyDown("ALT") and strippedLine or line) .. "\n"
		end
		return inactiveText
	end
	controls.save = new("ButtonControl", nil, -90, 175, 80, 20, "Replace", function()
		addModifier(selectedNode)
		self.build.spec:AddUndoState()
		self.modFlag = true
		self.build.buildFlag = true
		main:ClosePopup()
	end)
	controls.reset = new("ButtonControl", nil, 0, 175, 80, 20, "Reset Node", function()
		self.build.spec.hashOverrides[selectedNode.id] = nil
		self.build.spec:BuildAllDependsAndPaths()
		self.build.spec:AddUndoState()
		self.modFlag = true
		self.build.buildFlag = true
		main:ClosePopup()
	end)
	controls.close = new("ButtonControl", nil, 90, 175, 80, 20, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(600, 205, "Replace Modifier of Node", controls)
end

function TreeTabClass:SetPowerCalc(powerStat)
	self.viewer.showHeatMap = true
	self.build.buildFlag = true
	self.build.calcsTab.powerBuildFlag = true
	self.build.calcsTab.powerStat = powerStat
	self.controls.powerReportList:SetReport(powerStat, nil)
end

function TreeTabClass:BuildPowerReportList(currentStat)
	local report = {}

	if not (currentStat and currentStat.stat) then
		return report
	end

	-- locate formatting information for the type of heat map being used.
	-- maybe a better place to find this? At the moment, it is the only place
	-- in the code that has this information in a tidy place.
	local displayStat = nil

	for index, ds in ipairs(self.build.displayStats) do
		if ds.stat == currentStat.stat then
			displayStat = ds
			break
		end
	end

	-- not every heat map has an associated "stat" in the displayStats table
	-- this is due to not every stat being displayed in the sidebar, I believe.
	-- But, we do want to use the formatting knowledge stored in that table rather than duplicating it here.
	-- If no corresponding stat is found, just default to a generic stat display (>0=good, one digit of precision).
	if not displayStat then
		displayStat = {
			fmt = ".1f"
		}
	end

	-- search all nodes, ignoring ascendancies, sockets, etc.
	for nodeId, node in pairs(self.build.spec.visibleNodes) do
		local isAlloc = node.alloc > 0 or self.build.calcsTab.mainEnv.grantedPassives[nodeId]
		if (node.type == "Normal" or node.type == "Keystone" or node.type == "Notable") and not node.ascendancyName then
			local pathDist
			if isAlloc then
				pathDist = #(node.depends or { }) == 0 and 1 or #node.depends
			else
				pathDist = #(node.path or { }) == 0 and 1 or #node.path
			end
			local nodePower = (node.power.singleStat or 0) * ((displayStat.pc or displayStat.mod) and 100 or 1)
			local pathPower = (node.power.pathPower or 0) / pathDist * ((displayStat.pc or displayStat.mod) and 100 or 1)
			local nodePowerStr = s_format("%"..displayStat.fmt, nodePower)
			local pathPowerStr = s_format("%"..displayStat.fmt, pathPower)

			nodePowerStr = formatNumSep(nodePowerStr)
			pathPowerStr = formatNumSep(pathPowerStr)

			if (nodePower > 0 and not displayStat.lowerIsBetter) or (nodePower < 0 and displayStat.lowerIsBetter) then
				nodePowerStr = colorCodes.POSITIVE .. nodePowerStr
			elseif (nodePower < 0 and not displayStat.lowerIsBetter) or (nodePower > 0 and displayStat.lowerIsBetter) then
				nodePowerStr = colorCodes.NEGATIVE .. nodePowerStr
			end
			if (pathPower > 0 and not displayStat.lowerIsBetter) or (pathPower < 0 and displayStat.lowerIsBetter) then
				pathPowerStr = colorCodes.POSITIVE .. pathPowerStr
			elseif (pathPower < 0 and not displayStat.lowerIsBetter) or (pathPower > 0 and displayStat.lowerIsBetter) then
				pathPowerStr = colorCodes.NEGATIVE .. pathPowerStr
			end

			t_insert(report, {
				name = node.dn,
				power = nodePower,
				powerStr = nodePowerStr,
				pathPower = pathPower,
				pathPowerStr = pathPowerStr,
				allocated = isAlloc,
				id = node.id,
				x = node.x,
				y = node.y,
				type = node.type,
				pathDist = pathDist
			})
		end
	end

	-- sort it
	if displayStat.lowerIsBetter then
		t_sort(report, function (a,b)
			return a.power < b.power
		end)
	else
		t_sort(report, function (a,b)
			return a.power > b.power
		end)
	end

	return report
end