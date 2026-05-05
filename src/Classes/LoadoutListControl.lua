-- Last Epoch Building
--
-- Class: Loadout List
-- Loadout list control used in the Manage Loadouts popup.
-- A loadout = a name shared by an entry in TreeTab.specList,
-- ItemsTab.itemSets, SkillsTab.skillSets, and ConfigTab.configSets.
--
local t_insert = table.insert
local t_remove = table.remove

local function trim(s)
	return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function lowerTrim(s)
	return trim(s):lower()
end

local LoadoutListClass = newClass("LoadoutListControl", "ListControl", function(self, anchor, x, y, width, height, build)
	self.build = build
	self.ListControl(anchor, x, y, width, height, 16, "VERTICAL", true, { })
	self:Rebuild()

	self.controls.new = new("ButtonControl", {"BOTTOMLEFT",self,"TOP"}, 2, -4, 70, 18, "New", function()
		self:OpenRenamePopup(nil, "New Loadout")
	end)
	self.controls.rename = new("ButtonControl", {"LEFT",self.controls.new,"RIGHT"}, 4, 0, 70, 18, "Rename", function()
		if self.selValue then self:OpenRenamePopup(self.selValue.name, "Rename Loadout") end
	end)
	self.controls.rename.enabled = function() return self.selValue ~= nil end
	self.controls.delete = new("ButtonControl", {"BOTTOMRIGHT",self,"TOP"}, -2, -4, 70, 18, "Delete", function()
		if self.selValue then self:DeleteLoadout(self.selValue.name) end
	end)
	self.controls.delete.enabled = function()
		return self.selValue ~= nil and #self.list > 1
	end
end)

-- Collect the union of loadout names across the four tabs.
function LoadoutListClass:Rebuild()
	local build = self.build
	local seen = { }
	local newList = { }

	local function addFromList(orderList, sets)
		for _, id in ipairs(orderList) do
			local set = sets[id]
			if set then
				local name = trim(set.title or "Default")
				if name == "" then name = "Default" end
				local key = name:lower()
				if not seen[key] then
					seen[key] = true
					t_insert(newList, { name = name })
				end
			end
		end
	end

	if build.treeTab then
		for _, spec in ipairs(build.treeTab.specList) do
			local name = trim(spec.title or "Default")
			if name == "" then name = "Default" end
			local key = name:lower()
			if not seen[key] then
				seen[key] = true
				t_insert(newList, { name = name })
			end
		end
	end
	if build.itemsTab then addFromList(build.itemsTab.itemSetOrderList, build.itemsTab.itemSets) end
	if build.skillsTab then addFromList(build.skillsTab.skillSetOrderList, build.skillsTab.skillSets) end
	if build.configTab then addFromList(build.configTab.configSetOrderList, build.configTab.configSets) end

	-- Mutate the existing list table in place so ListControl's reference stays valid.
	for i = #self.list, 1, -1 do t_remove(self.list, i) end
	for _, entry in ipairs(newList) do t_insert(self.list, entry) end

	-- Try to keep the selection on the active loadout.
	local active = build.GetActiveLoadoutName and build:GetActiveLoadoutName()
	if active then
		for i, entry in ipairs(self.list) do
			if entry.name == active then
				self.selIndex = i
				self.selValue = entry
				return
			end
		end
	end
	self.selIndex = nil
	self.selValue = nil
end

function LoadoutListClass:GetRowValue(column, index, entry)
	if column == 1 then
		local active = self.build.GetActiveLoadoutName and self.build:GetActiveLoadoutName()
		local suffix = (active and active == entry.name) and "  ^9(Current)" or ""
		return "^7" .. entry.name .. suffix
	end
end

function LoadoutListClass:OnSelClick(index, entry, doubleClick)
	if doubleClick and entry and self.build.SwitchLoadout then
		if self.build:SwitchLoadout(entry.name) then
			self.build:SyncLoadouts()
			main:ClosePopup()
		end
	end
end

function LoadoutListClass:OnSelKeyDown(index, entry, key)
	if key == "F2" and entry then
		self:OpenRenamePopup(entry.name, "Rename Loadout")
	elseif key == "DELETE" and entry and #self.list > 1 then
		self:DeleteLoadout(entry.name)
	end
end

-- name=nil → create new. name=existing → rename.
function LoadoutListClass:OpenRenamePopup(name, title)
	local build = self.build
	local controls = { }
	local prompt = name and ("^7Rename loadout '" .. name .. "' to:") or "^7Enter name for the new loadout:"
	controls.label = new("LabelControl", nil, 0, 20, 0, 16, prompt)
	controls.edit = new("EditControl", nil, 0, 40, 350, 20, name or "New Loadout", nil, nil, 100, function(buf)
		local trimmed = trim(buf)
		controls.save.enabled = trimmed ~= "" and (not name or trimmed ~= name) and not self:NameCollides(trimmed, name)
	end)
	controls.save = new("ButtonControl", nil, -45, 70, 80, 20, "Save", function()
		local newName = trim(controls.edit.buf)
		if newName == "" then return end
		if name then
			self:RenameLoadout(name, newName)
		else
			self:CreateLoadout(newName)
		end
		main:ClosePopup()
	end)
	controls.save.enabled = false
	controls.cancel = new("ButtonControl", nil, 45, 70, 80, 20, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(370, 100, title, controls, "save", "edit", "cancel")
end

-- Reject empty / duplicate names. `excluding` is the original name during rename.
function LoadoutListClass:NameCollides(candidate, excluding)
	local key = lowerTrim(candidate)
	if excluding and key == lowerTrim(excluding) then return false end
	for _, entry in ipairs(self.list) do
		if entry.name:lower() == key then return true end
	end
	return false
end

function LoadoutListClass:CreateLoadout(name)
	local build = self.build
	local newSpec = new("PassiveSpec", build, latestTreeVersion)
	newSpec.title = name
	t_insert(build.treeTab.specList, newSpec)
	build.treeTab:SetActiveSpec(#build.treeTab.specList)

	local itemSet = build.itemsTab:NewItemSet(#build.itemsTab.itemSets + 1)
	itemSet.title = name
	t_insert(build.itemsTab.itemSetOrderList, itemSet.id)

	local skillSet = build.skillsTab:NewSkillSet(#build.skillsTab.skillSets + 1)
	skillSet.title = name
	t_insert(build.skillsTab.skillSetOrderList, skillSet.id)

	local newConfigId = #build.configTab.configSetOrderList + 1
	while build.configTab.configSets[newConfigId] do
		newConfigId = newConfigId + 1
	end
	local configSet = build.configTab:NewConfigSet(newConfigId, name)
	t_insert(build.configTab.configSetOrderList, configSet.id)

	build.modFlag = true
	build:SyncLoadouts()
	self:Rebuild()
end

function LoadoutListClass:RenameLoadout(oldName, newName)
	local build = self.build
	local needle = oldName:lower()

	local function renameIn(list)
		for _, entry in ipairs(list) do
			if (entry.title or "Default"):lower() == needle then
				entry.title = newName
			end
		end
	end
	renameIn(build.treeTab.specList)
	for _, id in ipairs(build.itemsTab.itemSetOrderList) do
		local s = build.itemsTab.itemSets[id]
		if s and (s.title or "Default"):lower() == needle then s.title = newName end
	end
	for _, id in ipairs(build.skillsTab.skillSetOrderList) do
		local s = build.skillsTab.skillSets[id]
		if s and (s.title or "Default"):lower() == needle then s.title = newName end
	end
	for _, id in ipairs(build.configTab.configSetOrderList) do
		local s = build.configTab.configSets[id]
		if s and (s.title or "Default"):lower() == needle then s.title = newName end
	end

	build.modFlag = true
	build:SyncLoadouts()
	self:Rebuild()
end

function LoadoutListClass:DeleteLoadout(name)
	local build = self.build
	main:OpenConfirmPopup("Delete Loadout", "Delete loadout '"..name.."'?\nThis removes the matching passive tree, item set, skill set, and config set.", "Delete", function()
		local needle = name:lower()

		local function removeFrom(orderList, sets)
			for i = #orderList, 1, -1 do
				local id = orderList[i]
				local s = sets[id]
				if s and (s.title or "Default"):lower() == needle then
					t_remove(orderList, i)
					sets[id] = nil
				end
			end
		end
		removeFrom(build.itemsTab.itemSetOrderList, build.itemsTab.itemSets)
		if not build.itemsTab.itemSets[build.itemsTab.activeItemSetId] then
			build.itemsTab:SetActiveItemSet(build.itemsTab.itemSetOrderList[1])
		end
		removeFrom(build.skillsTab.skillSetOrderList, build.skillsTab.skillSets)
		if not build.skillsTab.skillSets[build.skillsTab.activeSkillSetId] then
			build.skillsTab:SetActiveSkillSet(build.skillsTab.skillSetOrderList[1])
		end
		removeFrom(build.configTab.configSetOrderList, build.configTab.configSets)
		if not build.configTab.configSets[build.configTab.activeConfigSetId] then
			build.configTab:SetActiveConfigSet(build.configTab.configSetOrderList[1])
		end

		for i = #build.treeTab.specList, 1, -1 do
			if (build.treeTab.specList[i].title or "Default"):lower() == needle and #build.treeTab.specList > 1 then
				t_remove(build.treeTab.specList, i)
			end
		end
		build.treeTab:SetActiveSpec(math.min(build.treeTab.activeSpec, #build.treeTab.specList))

		build.modFlag = true
		build.buildFlag = true
		build:SyncLoadouts()
		self:Rebuild()
	end)
end
