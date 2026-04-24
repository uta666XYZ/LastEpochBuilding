-- Last Epoch Building
-- @leb-canary v1 / id:leb-a89c5e-calcsetup-2026 / do-not-remove (see Development/リリース手順.md)
--
-- Module: Calc Setup
-- Initialises the environment for calculations.
--
local calcs = ...

local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max

local tempTable1 = { }

-- Cache of set data keyed by version, loaded lazily from Data/Set/set_<ver>.json.
-- Used by set-bonus aggregation below.
local setDataCache = {}
local function loadSetData(ver)
	ver = ver or "1_4"
	if setDataCache[ver] == nil then
		setDataCache[ver] = readJsonFile("Data/Set/set_" .. ver .. ".json")
			or readJsonFile("Data/Set/set_1_4.json")
			or false
	end
	return setDataCache[ver] or nil
end

-- Apply N-piece set bonuses: count equipped SET pieces per setId, then parse
-- and add every bonus tier 2..N (so 3 pieces = 2-piece AND 3-piece bonus).
-- Also matches "Reforged Set" items (basic items with item.setInfo.setId set by
-- the crafting popup).
local function applySetBonuses(env, items, ver)
	local setData = loadSetData(ver)
	if not setData then return end

	-- First pass: resolve each equipped SET / Reforged piece to its setId.
	local pieceCount = {} -- setId -> count
	local setEntry   = {} -- setId -> a sample set entry (for bonus lookup)
	for _, item in pairs(items) do
		if item then
			local isSet      = (item.rarity == "SET")
			local hasSetInfo = (item.setInfo and item.setInfo.setId ~= nil)
			if isSet or hasSetInfo then
				local setId, bonusTable, setName
				if hasSetInfo then
					setId      = item.setInfo.setId
					bonusTable = item.setInfo.bonus
					setName    = item.setInfo.name
				end
				if not bonusTable then
					-- Fallback: match by item.title against set_<ver>.json.
					-- Strip trailing " Reforged" suffix for crafted Reforged items
					-- whose setInfo was lost on BuildAndParseRaw round-trip.
					local titleKey = item.title and item.title:gsub(" Reforged$", "") or nil
					for _, e in pairs(setData) do
						if e.set and (e.name == item.title or e.name == titleKey) then
							setId      = e.set.setId
							bonusTable = e.set.bonus
							setName    = e.set.name
							break
						end
					end
				end
				if not bonusTable and setId then
					-- Bonus missing but setId known: look up any member of the same set.
					for _, e in pairs(setData) do
						if e.set and e.set.setId == setId then
							bonusTable = e.set.bonus
							setName    = setName or e.set.name
							break
						end
					end
				end
				if setId then
					pieceCount[setId] = (pieceCount[setId] or 0) + 1
					if not setEntry[setId] then
						setEntry[setId] = { bonus = bonusTable, name = setName }
					end
				end
			end
		end
	end

	-- Second pass: for each setId with >= 2 pieces, parse bonus tiers 2..count.
	-- Note: JSON loader converts numeric-string keys ("2"/"3") to numbers, so
	-- look up by both string and number form.
	for setId, count in pairs(pieceCount) do
		local info = setEntry[setId]
		if info and info.bonus then
			for tier = 2, count do
				local rawLine = info.bonus[tostring(tier)] or info.bonus[tier]
				if rawLine then
					-- Strip formatting tags ({rounding:Integer} etc.) before parse.
					local line = rawLine:gsub("{rounding:[^}]+}", ""):gsub("{[^}]+}", "")
					local mods = modLib.parseMod(line)
					if mods and #mods > 0 then
						local source = "Set: " .. (info.name or ("Set " .. tostring(setId))) .. " (" .. tier .. "pc)"
						for _, mod in ipairs(mods) do
							modLib.setSource(mod, source)
							env.itemModDB:AddMod(mod)
						end
					end
				end
			end
		end
	end
end

-- Initialise modifier database with stats and conditions common to all actors
function calcs.initModDB(env, modDB)
	for _, damageType in ipairs(DamageTypes) do
		modDB:NewMod(damageType.."ResistMax", "BASE", 75, "Base")
		modDB:NewMod("Totem".. damageType.."ResistMax", "BASE", 75, "Base")
	end
	modDB:NewMod("Blind", "FLAG", true, "Base", { type = "Condition", var = "Blinded" })
	modDB:NewMod("Chill", "FLAG", true, "Base", { type = "Condition", var = "Chilled" })
	modDB:NewMod("Freeze", "FLAG", true, "Base", { type = "Condition", var = "Frozen" })
	modDB:NewMod("CritChanceCap", "BASE", 100, "Base")
	modDB:NewMod("BlockChanceMax", "BASE", 75, "Base")
	modDB:NewMod("SpellBlockChanceMax", "BASE", 75, "Base")
	modDB.conditions["Buffed"] = env.mode_buffs
	modDB.conditions["Combat"] = env.mode_combat
	modDB.conditions["Effective"] = env.mode_effective
end

function calcs.buildModListForNode(env, node)
	local modList = new("ModList")
	if node.type == "Keystone" then
		modList:AddMod(node.keystoneMod)
	else
		modList:AddList(node.modList)
	end

	if modList:Flag(nil, "PassiveSkillHasNoEffect") or (env.allocNodes[node.id] and modList:Flag(nil, "AllocatedPassiveSkillHasNoEffect")) then
		wipeTable(modList)
	end

	-- Apply effect scaling
	local scale = calcLib.mod(modList, nil, "PassiveSkillEffect")
	if scale ~= 1 then
		local scaledList = new("ModList")
		scaledList:ScaleAddList(modList, scale)
		modList = scaledList
	end

	if modList:Flag(nil, "PassiveSkillHasOtherEffect") then
		for i, mod in ipairs(modList:List(skillCfg, "NodeModifier")) do
			if i == 1 then wipeTable(modList) end
			modList:AddMod(mod.mod)
		end
	end

	node.grantedSkills = { }
	for _, skill in ipairs(modList:List(nil, "ExtraSkill")) do
		if skill.name ~= "Unknown" then
			t_insert(node.grantedSkills, {
				skillId = skill.skillId,
				level = skill.level,
				noSupports = true,
				source = "Tree:"..node.id
			})
		end
	end

	if modList:Flag(nil, "CanExplode") then
		t_insert(env.explodeSources, node)
	end

	return modList
end

-- Build list of modifiers from the listed tree nodes
function calcs.buildModListForNodeList(env, nodeList, stripSkillId, gateByChannelling)
	-- Add node modifiers
	local modList = new("ModList")
	for _, node in pairs(nodeList) do
		local nodeModList = calcs.buildModListForNode(env, node)
		if stripSkillId or gateByChannelling then
			local transformedList = new("ModList")
			for _, mod in ipairs(nodeModList) do
				local hasSkillId = false
				if stripSkillId then
					for _, tag in ipairs(mod) do
						if tag.type == "SkillId" then
							hasSkillId = true
							break
						end
					end
				end
				local needsCopy = hasSkillId or gateByChannelling
				local newMod = needsCopy and copyTable(mod, true) or mod
				if hasSkillId then
					local j = 1
					while newMod[j] do
						if newMod[j].type == "SkillId" then
							t_remove(newMod, j)
						else
							j = j + 1
						end
					end
				end
				if gateByChannelling then
					t_insert(newMod, { type = "Condition", var = "Channelling" })
				end
				transformedList:AddMod(newMod)
			end
			nodeModList = transformedList
		end
		modList:AddList(nodeModList)
		if env.mode == "MAIN" then
			node.finalModList = nodeModList
		end
	end

	return modList
end

function wipeEnv(env, accelerate)
	-- Always wipe the below as we will be pushing in the modifiers,
	-- multipliers and conditions for player and enemy DBs via `parent`
	-- extensions of those DBs later which allow us to do a table-pointer
	-- link and save time on having to do a copyTable() function.
	wipeTable(env.modDB.mods)
	wipeTable(env.modDB.conditions)
	wipeTable(env.modDB.multipliers)
	wipeTable(env.enemyDB.mods)
	wipeTable(env.enemyDB.conditions)
	wipeTable(env.enemyDB.multipliers)
	if env.minion then
		wipeTable(env.minion.modDB.mods)
		wipeTable(env.minion.modDB.conditions)
		wipeTable(env.minion.modDB.multipliers)
	end

	if accelerate.everything then
		return
	end

	-- Passive tree node allocations
	-- Also in a further pass tracks Legion influenced mods
	if not accelerate.nodeAlloc then
		wipeTable(env.allocNodes)
		-- Usually states: `Allocates <NAME>` (e.g., amulet anointment)
		wipeTable(env.grantedPassives)
		wipeTable(env.grantedSkillsNodes)
	end

	if not accelerate.requirementsItems then
		-- Item-related tables
		wipeTable(env.itemModDB.mods)
		wipeTable(env.itemModDB.conditions)
		wipeTable(env.itemModDB.multipliers)
		-- 2) Player items
		-- 3) Granted Skill from items (e.g., Curse on Hit rings)
		-- 4) Flasks
		wipeTable(env.extraRadiusNodeList)
		wipeTable(env.player.itemList)
		wipeTable(env.grantedSkillsItems)
		wipeTable(env.flasks)

		-- Special / Unique Items that have their own ModDB()
		if env.aegisModList then
			wipeTable(env.aegisModList)
		end
		if env.theIronMass then
			wipeTable(env.theIronMass)
		end
		if env.weaponModList1 then
			wipeTable(env.weaponModList1)
		end

		-- Requirements from Items (Str, Dex, Int)
		wipeTable(env.requirementsTableItems)
	end

	-- Requirements from Gems (Str, Dex, Int)
	if not accelerate.requirementsGems then
		wipeTable(env.requirementsTableGems)
	end

	if not accelerate.skills then
		-- Player Active Skills generation
		wipeTable(env.player.activeSkillList)

		-- Enhances Active Skills with skill ModFlags, KeywordFlags
		-- and modifiers that affect skill scaling (e.g., global buffs/effects)
		wipeTable(env.auxSkillList)
	end
end

local function getGemModList(env, groupCfg, socketColor, socketNum)
	local gemCfg = copyTable(groupCfg, true)
	gemCfg.socketColor = socketColor
	gemCfg.socketNum = socketNum
	return env.modDB:List(gemCfg, "GemProperty")
end

local function applyGemMods(effect, modList)
	for _, value in ipairs(modList) do
		local match = true
		if value.keywordList then
			for _, keyword in ipairs(value.keywordList) do
				if not calcLib.gemIsType(effect.gemData, keyword, true) then
					match = false
					break
				end
			end
		elseif not calcLib.gemIsType(effect.gemData, value.keyword, true) then
			match = false
		end
		if match then
			effect[value.key] = (effect[value.key] or 0) + value.value
		end
	end
end

local function applySocketMods(env, gem, groupCfg, socketNum, modSource)
	local socketCfg = copyTable(groupCfg, true)
	socketCfg.skillGem = gem
	socketCfg.socketNum = socketNum
	for _, value in ipairs(env.modDB:List(socketCfg, "SocketProperty")) do
		env.player.modDB:AddMod(modLib.setSource(value.value, modSource or groupCfg.slotName or ""))
	end
end

local function addBestSupport(supportEffect, appliedSupportList, mode)
	local add = true
	for index, otherSupport in ipairs(appliedSupportList) do
		-- Check if there's another better support already present
		if supportEffect.grantedEffect == otherSupport.grantedEffect then
			add = false
			if supportEffect.level > otherSupport.level or (supportEffect.level == otherSupport.level and supportEffect.quality > otherSupport.quality) then
				if mode == "MAIN" then
					otherSupport.superseded = true
				end
				appliedSupportList[index] = supportEffect
			else
				supportEffect.superseded = true
			end
			break
		elseif supportEffect.grantedEffect.plusVersionOf == otherSupport.grantedEffect.id then
			add = false
			if mode == "MAIN" then
				otherSupport.superseded = true
			end
			appliedSupportList[index] = supportEffect
		elseif otherSupport.grantedEffect.plusVersionOf == supportEffect.grantedEffect.id then
			add = false
			supportEffect.superseded = true
		end
	end
	if add then
		t_insert(appliedSupportList, supportEffect)
	end
end

-- Initialise environment:
-- 1. Initialises the player and enemy modifier databases
-- 2. Merges modifiers for all items
-- 3. Builds a list of jewels with radius functions
-- 4. Merges modifiers for all allocated passive nodes
-- 5. Builds a list of active skills and their supports (calcs.createActiveSkill)
-- 6. Builds modifier lists for all active skills (calcs.buildActiveSkillModList)
function calcs.initEnv(build, mode, override, specEnv)
	-- accelerator variables
	local cachedPlayerDB = specEnv and specEnv.cachedPlayerDB or nil
	local cachedEnemyDB = specEnv and specEnv.cachedEnemyDB or nil
	local cachedMinionDB = specEnv and specEnv.cachedMinionDB or nil
	local env = specEnv and specEnv.env or nil
	local accelerate = specEnv and specEnv.accelerate or { }

	-- environment variables
	local override = override or { }
	local modDB = nil
	local enemyDB = nil
	local classStats = nil

	if not env then
		env = { }
		env.build = build
		env.data = build.data
		-- Combine configTab input and placeholder into env.config
		env.config = {}
		for k, v in pairs(build.configTab.input) do
			env.config[k] = v
		end
		for k, v in pairs(build.configTab.placeholder) do
			if env.config[k] == nil then
				env.config[k] = v
			end
		end

		env.calcsInput = build.calcsTab.input
		env.mode = mode
		env.spec = override.spec or build.spec
		env.classId = env.spec.curClassId

		modDB = new("ModDB")
		env.modDB = modDB
		enemyDB = new("ModDB")
		env.enemyDB = enemyDB
		env.itemModDB = new("ModDB")

		env.enemyLevel = build.configTab.enemyLevel or m_min(data.misc.MaxEnemyLevel, 100)

		-- Create player/enemy actors
		env.player = {
			modDB = env.modDB,
			level = build.characterLevel,
		}
		env.modDB.actor = env.player
		env.enemy = {
			modDB = env.enemyDB,
			level = env.enemyLevel,
		}
		enemyDB.actor = env.enemy
		env.player.enemy = env.enemy
		env.enemy.enemy = env.player
		enemyDB.actor.player = env.player
		env.modDB.actor.player = env.player

		-- Set up requirements tracking
		env.requirementsTableItems = { }
		env.requirementsTableGems = { }

		-- Prepare item, skill, flask tables
		env.player.itemList = { }
		env.grantedSkills = { }
		env.grantedSkillsNodes = { }
		env.grantedSkillsItems = { }
		env.explodeSources = { }
		env.itemWarnings = { }
		env.flasks = { }

		-- tree based
		env.grantedPassives = { }

		-- skill-related
		env.player.activeSkillList = { }
		env.auxSkillList = { }
	--elseif accelerate.everything then
	--	local minionDB = nil
	--	env.modDB.parent, env.enemyDB.parent, minionDB = specCopy(env)
	--	if minionDB then
	--		env.minion.modDB.parent = minionDB
	--	end
	--	wipeEnv(env, accelerate)
	else
		wipeEnv(env, accelerate)
		modDB = env.modDB
		enemyDB = env.enemyDB
	end

	-- Set buff mode
	local buffMode
	if mode == "CALCS" then
		buffMode = env.calcsInput.misc_buffMode
	else
		buffMode = "EFFECTIVE"
	end
	if buffMode == "EFFECTIVE" then
		env.mode_buffs = true
		env.mode_combat = true
		env.mode_effective = true
	elseif buffMode == "COMBAT" then
		env.mode_buffs = true
		env.mode_combat = true
		env.mode_effective = false
	elseif buffMode == "BUFFED" then
		env.mode_buffs = true
		env.mode_combat = false
		env.mode_effective = false
	else
		env.mode_buffs = false
		env.mode_combat = false
		env.mode_effective = false
	end
	classStats = env.spec.tree.characterData and env.spec.tree.characterData[env.classId] or env.spec.tree.classes[env.classId]

	if not cachedPlayerDB then
		-- Initialise modifier database with base values
		for _, stat in pairs(Attributes) do
			modDB:NewMod(stat, "BASE", classStats["base"..stat], "Base")
		end
		modDB.multipliers["Level"] = m_max(1, m_min(100, build.characterLevel))
		calcs.initModDB(env, modDB)
		modDB:NewMod("Life", "BASE", classStats["healthPerLevel"], "Base", { type = "Multiplier", var = "Level", base = classStats["baseHealth"] })
		modDB:NewMod("LifeRegen", "BASE", classStats["healthRegenPerLevel"], "Base", { type = "Multiplier", var = "Level", base = classStats["healthRegen"] })
		modDB:NewMod("Mana", "BASE", classStats["manaPerLevel"], "Base", { type = "Multiplier", var = "Level", base = classStats["baseMana"] })
		modDB:NewMod("ManaRegen", "BASE", classStats["manaRegen"], "Base")
		modDB:NewMod("StunAvoidance", "BASE", classStats["stunAvoidancePerLevel"], "Base", { type = "Multiplier", var = "Level", base = classStats["baseStunAvoidance"] })
		modDB:NewMod("Endurance", "BASE", classStats["baseEndurance"] * 100, "Base")
		modDB:NewMod("EnduranceThreshold", "BASE", classStats["enduranceThresholdPerHealth"], "Base", { type = "PerStat", stat = "Life"})

		-- Add attribute bonuses
		modDB:NewMod("Armour", "INC", 4, "Strength", {type = "PerStat", stat = "Str"})
		modDB:NewMod("Evasion", "BASE", 4, "Dexterity", {type = "PerStat", stat = "Dex"})
		modDB:NewMod("WardRetention", "BASE", 2, "Intelligence", {type = "PerStat", stat = "Int"})
		modDB:NewMod("Mana", "BASE", 2, "Attunement", {type = "PerStat", stat = "Att"})
		modDB:NewMod("Life", "BASE", 6, "Vitality", {type = "PerStat", stat = "Vit"})
		modDB:NewMod("PoisonResist", "BASE", 1, "Vitality", {type = "PerStat", stat = "Vit"})
		modDB:NewMod("NecroticResist", "BASE", 1, "Vitality", {type = "PerStat", stat = "Vit"})

		-- Season 4 (1.4): converted attribute bonuses (same values as base attributes)
		modDB:NewMod("Armour", "INC", 4, "Brutality", {type = "PerStat", stat = "Brutality"})
		modDB:NewMod("Evasion", "BASE", 4, "Guile", {type = "PerStat", stat = "Guile"})
		modDB:NewMod("Mana", "BASE", 2, "Apathy", {type = "PerStat", stat = "Apathy"})
		modDB:NewMod("Life", "BASE", 6, "Rampancy", {type = "PerStat", stat = "Rampancy"})
		modDB:NewMod("PoisonResist", "BASE", 1, "Rampancy", {type = "PerStat", stat = "Rampancy"})
		modDB:NewMod("NecroticResist", "BASE", 1, "Rampancy", {type = "PerStat", stat = "Rampancy"})

		-- Season 4 (1.4): Acolyte converts all base attributes into their mastery variants
		-- (Str→Brutality, Dex→Guile, Int→Madness, Att→Apathy, Vit→Rampancy). classId 3 = Acolyte.
		if env.spec.treeVersion == "1_4" and env.classId == 3 then
			modDB:NewMod("StrengthConvertedToBrutality", "BASE", 100, "Acolyte")
			modDB:NewMod("DexterityConvertedToGuile", "BASE", 100, "Acolyte")
			modDB:NewMod("IntelligenceConvertedToMadness", "BASE", 100, "Acolyte")
			modDB:NewMod("AttunementConvertedToApathy", "BASE", 100, "Acolyte")
			modDB:NewMod("VitalityConvertedToRampancy", "BASE", 100, "Acolyte")
		end

		-- Initialise enemy modifier database
		calcs.initModDB(env, enemyDB)
		enemyDB:NewMod("Condition:AgainstDamageOverTime", "FLAG", true, "Base", ModFlag.Dot, { type = "ActorCondition", actor = "player", var = "Combat" })

		-- Add mods from the config tab
		env.modDB:AddList(build.configTab.modList)
		env.enemyDB:AddList(build.configTab.enemyModList)

		-- Add mods from the party tab
		env.enemyDB:AddList(build.partyTab.enemyModList)

		cachedPlayerDB, cachedEnemyDB, cachedMinionDB = specCopy(env)
	else
		env.modDB.parent = cachedPlayerDB
		env.enemyDB.parent = cachedEnemyDB
		if cachedMinionDB and env.minion then
			env.minion.modDB.parent = cachedMinionDB
		end
	end

	if override.conditions then
		for _, flag in ipairs(override.conditions) do
			modDB.conditions[flag] = true
		end
	end

	local allocatedNotableCount = env.spec.allocatedNotableCount
	local allocatedMasteryCount = env.spec.allocatedMasteryCount
	local allocatedMasteryTypeCount = env.spec.allocatedMasteryTypeCount
	local allocatedMasteryTypes = copyTable(env.spec.allocatedMasteryTypes)



	if not accelerate.nodeAlloc then
		-- Build list of passive nodes
		local nodes
		if override.addNodes or override.removeNodes then
			nodes = { }
			if override.addNodes then
				for node in pairs(override.addNodes) do
					nodes[node.id] = node
					if node.type == "Mastery" then
						allocatedMasteryCount = allocatedMasteryCount + 1

						if not allocatedMasteryTypes[node.name] then
							allocatedMasteryTypes[node.name] = 1
							allocatedMasteryTypeCount = allocatedMasteryTypeCount + 1
						else
							local prevCount = allocatedMasteryTypes[node.name]
							allocatedMasteryTypes[node.name] = prevCount + 1
							if prevCount == 0 then
								allocatedMasteryTypeCount = allocatedMasteryTypeCount + 1
							end
						end
					elseif node.type == "Notable" then
						allocatedNotableCount = allocatedNotableCount + 1
					end
				end
			end
			for _, node in pairs(env.spec.allocNodes) do
				if not override.removeNodes or not override.removeNodes[node] then
					nodes[node.id] = node
				elseif override.removeNodes[node] then
					if node.type == "Mastery" then
						allocatedMasteryCount = allocatedMasteryCount - 1

						allocatedMasteryTypes[node.name] = allocatedMasteryTypes[node.name] - 1
						if allocatedMasteryTypes[node.name] == 0 then
							allocatedMasteryTypeCount = allocatedMasteryTypeCount - 1
						end
					elseif node.type == "Notable" then
						allocatedNotableCount = allocatedNotableCount - 1
					end
				end
			end
		else
			nodes = copyTable(env.spec.allocNodes, true)
		end
		env.allocNodes = nodes
	end

	if allocatedNotableCount and allocatedNotableCount > 0 then
		modDB:NewMod("Multiplier:AllocatedNotable", "BASE", allocatedNotableCount)
	end
	if allocatedMasteryCount and allocatedMasteryCount > 0 then
		modDB:NewMod("Multiplier:AllocatedMastery", "BASE", allocatedMasteryCount)
	end
	if allocatedMasteryTypeCount and allocatedMasteryTypeCount > 0 then
		modDB:NewMod("Multiplier:AllocatedMasteryType", "BASE", allocatedMasteryTypeCount)
	end
	if allocatedMasteryTypes["Life Mastery"] and allocatedMasteryTypes["Life Mastery"] > 0 then
		modDB:NewMod("Multiplier:AllocatedLifeMastery", "BASE", allocatedMasteryTypes["Life Mastery"])
	end

	-- Build and merge item modifiers, and create list of radius jewels
	if not accelerate.requirementsItems then
		local items = {}
		for _, slot in pairs(build.itemsTab.orderedSlots) do
			local slotName = slot.slotName
			local item
			if slotName == override.repSlotName then
				item = override.repItem
			elseif override.repItem and override.repSlotName:match("^Weapon 1") and slotName:match("^Weapon 2") and
			(override.repItem.base.type == "Staff" or override.repItem.base.type == "Two Handed Sword" or override.repItem.base.type == "Two Handed Axe" or override.repItem.base.type == "Two Handed Mace"
			or (override.repItem.base.type == "Bow" and item and item.base.type ~= "Quiver")) then
				item = nil
			else
				item = build.itemsTab.items[slot.selItemId]
			end
			if item and item.grantedSkills then
				-- Find skills granted by this item
				for _, skill in ipairs(item.grantedSkills) do
					local skillData = env.data.skills[skill.skillId]
					local grantedSkill = copyTable(skill)
					grantedSkill.nameSpec = skillData and skillData.name or nil
					grantedSkill.sourceItem = item
					grantedSkill.slotName = slotName
					t_insert(env.grantedSkillsItems, grantedSkill)
				end
			end
			if item and item.baseModList and item.baseModList:Flag(nil, "CanExplode") then
				t_insert(env.explodeSources, item)
			end
			items[slotName] = item
		end

		if not env.config.ignoreItemDisablers then
			local itemDisabled = {}
			local itemDisablers = {}
			if modDB:Flag(nil, "CanNotUseHelm") then
				itemDisabled["Helmet"] = { disabled = true, size = 1 }
			end
			for _, slot in pairs(build.itemsTab.orderedSlots) do
				local slotName = slot.slotName
				if items[slotName] then
					local srcList = items[slotName].modList or items[slotName].slotModList[slot.slotNum]
					for _, mod in ipairs(srcList) do
						-- checks if it disables another slot
						for _, tag in ipairs(mod) do
							if tag.type == "DisablesItem" then
								-- e.g. Tincture in Flask 5 while using a Micro-Distillery Belt
								if tag.excludeItemType and items[tag.slotName] and items[tag.slotName].type == tag.excludeItemType then
									break
								end
								itemDisablers[slotName] = tag.slotName
								itemDisabled[tag.slotName] = slotName
								break
							end
						end
					end
				end
			end
			local visited = {}
			local trueDisabled = {}
			for slot in pairs(itemDisablers) do
				if not visited[slot] then
					-- find chain start
					local curChain = { slot = true }
					while itemDisabled[slot] do
						slot = itemDisabled[slot]
						if curChain[slot] then break end -- detect cycles
						curChain[slot] = true
					end

					-- step through the chain of disabled items, disabling every other one
					repeat
						visited[slot] = true
						slot = itemDisablers[slot]
						if not slot then break end
						visited[slot] = true
						trueDisabled[slot] = true
						slot = itemDisablers[slot]
					until(not slot or visited[slot])
				end
			end
			for slot in pairs(trueDisabled) do
				items[slot] = nil
			end
		end

		-- Idol Altar: count idols equipped in Omen Idol (Refracted) slots
		-- so mods like "+N per Idol in a Refracted Slot" can scale.
		local idolInRefractedSlotCount = 0
		for slotName, item in pairs(items) do
			if item and slotName:sub(1, 10) == "Omen Idol " then
				idolInRefractedSlotCount = idolInRefractedSlotCount + 1
			end
		end
		if idolInRefractedSlotCount > 0 then
			modDB:NewMod("Multiplier:IdolInRefractedSlot", "BASE", idolInRefractedSlotCount, "Idol Altar")
		end

		-- Idol Altar: collect items in Omen Idol (Refracted) slots and compute
		-- altar boost fractions for prefix / suffix / weaver-enchant affixes.
		-- The matching idol in the regular Idol 1-25 grid contributes its base
		-- (un-boosted) mods; the Omen Idol slot path below contributes the
		-- boost delta via a cloned item with scaled valueScalars. To avoid
		-- double-count, the regular-grid copy is skipped in the main merge
		-- loop when the same item reference is present in an Omen Idol slot.
		local fracturedItemSet = {}
		for slotName, item in pairs(items) do
			if item and slotName:sub(1, 10) == "Omen Idol " then
				fracturedItemSet[item] = true
			end
		end
		local altarBoostPrefix, altarBoostSuffix, altarBoostWeaver = 0, 0, 0
		if next(fracturedItemSet) then
			local altarItem = items["Idol Altar"]
			if altarItem and altarItem.modList then
				local common = 0
				for _, mod in ipairs(altarItem.modList) do
					if mod.type == "INC" then
						if mod.name == "IdolRefractedAffixEffect" then
							common = common + (mod.value or 0)
						elseif mod.name == "IdolRefractedPrefixEffect" then
							altarBoostPrefix = altarBoostPrefix + (mod.value or 0)
						elseif mod.name == "IdolRefractedSuffixEffect" then
							altarBoostSuffix = altarBoostSuffix + (mod.value or 0)
						elseif mod.name == "IdolRefractedWeaverEffect" then
							altarBoostWeaver = altarBoostWeaver + (mod.value or 0)
						end
					end
				end
				altarBoostPrefix = (altarBoostPrefix + common) / 100
				altarBoostSuffix = (altarBoostSuffix + common) / 100
				altarBoostWeaver = (altarBoostWeaver + common) / 100
			end
		end
		local function cloneWithAltarBoost(srcItem)
			-- Reconstruct a parsed clone from raw so mutating valueScalar on
			-- this clone does not affect the shared original (which is also
			-- consumed by tooltip display with its own altarBoost path).
			-- Each boosted modLine's valueScalar becomes value * (1 + boost)
			-- so applyRange/parseMod during BuildAndParseRaw yields the
			-- additively-boosted mod values in clone.modList.
			local clone = new("Item", srcItem:BuildRaw())
			local function scaleList(lines, boost)
				if not boost or boost <= 0 then return end
				for _, modLine in ipairs(lines) do
					if modLine.range then
						modLine.valueScalar = (modLine.valueScalar or 1) * (1 + boost)
					end
				end
			end
			scaleList(clone.enchantModLines, altarBoostWeaver)
			for _, modLine in ipairs(clone.explicitModLines) do
				if modLine.range then
					local boost
					if modLine.affixType == "Prefix" then
						boost = altarBoostPrefix
					elseif modLine.affixType == "Suffix" then
						boost = altarBoostSuffix
					end
					if boost and boost > 0 then
						modLine.valueScalar = (modLine.valueScalar or 1) * (1 + boost)
					end
				end
			end
			clone:BuildAndParseRaw()
			return clone
		end

		-- Idol Altar: count equipped idols by type/designation for "per Equipped X Idol" mods.
		-- Uses normal idol grid slots (Idol 1-25); dedupes by itemId to avoid double-counting
		-- idols that also appear in Omen Idol slots.
		do
			local idolTypeCount = {}
			local hereticalCount = 0
			local seen = {}
			for i = 1, 25 do
				local item = items["Idol " .. i]
				if item and not seen[item] then
					seen[item] = true
					if item.type then
						idolTypeCount[item.type] = (idolTypeCount[item.type] or 0) + 1
					end
					if item.baseName and item.baseName:sub(1, 10) == "Heretical " then
						hereticalCount = hereticalCount + 1
					end
				end
			end
			local typeToVar = {
				["Minor Idol"]   = "EquippedMinorIdol",
				["Small Idol"]   = "EquippedSmallIdol",
				["Humble Idol"]  = "EquippedHumbleIdol",
				["Stout Idol"]   = "EquippedStoutIdol",
				["Grand Idol"]   = "EquippedGrandIdol",
				["Large Idol"]   = "EquippedLargeIdol",
				["Ornate Idol"]  = "EquippedOrnateIdol",
				["Huge Idol"]    = "EquippedHugeIdol",
				["Adorned Idol"] = "EquippedAdornedIdol",
			}
			for typeName, varName in pairs(typeToVar) do
				local n = idolTypeCount[typeName]
				if n and n > 0 then
					modDB:NewMod("Multiplier:" .. varName, "BASE", n, "Idol Altar")
				end
			end
			if hereticalCount > 0 then
				modDB:NewMod("Multiplier:EquippedHereticalIdol", "BASE", hereticalCount, "Idol Altar")
			end
		end

		-- Idol Altar: evaluate "no larger idols above smaller ones in the grid" condition.
		-- For each grid column, walking top -> bottom, idol sizes (cell count) must be
		-- non-decreasing; no larger idol may sit above a smaller one.
		do
			local idolDims = {
				["Minor Idol"] = {1,1}, ["Small Idol"] = {1,1}, ["Humble Idol"] = {2,1},
				["Stout Idol"] = {1,2}, ["Grand Idol"] = {3,1}, ["Large Idol"] = {1,3},
				["Ornate Idol"] = {4,1}, ["Huge Idol"] = {1,4}, ["Adorned Idol"] = {2,2},
			}
			local idolGridSlots = {
				{ "Idol 21", "Idol 1",  "Idol 2",  "Idol 3",  "Idol 22" },
				{ "Idol 4",  "Idol 5",  "Idol 6",  "Idol 7",  "Idol 8"  },
				{ "Idol 9",  "Idol 10", "Idol 23", "Idol 11", "Idol 12" },
				{ "Idol 13", "Idol 14", "Idol 15", "Idol 16", "Idol 17" },
				{ "Idol 24", "Idol 18", "Idol 19", "Idol 20", "Idol 25" },
			}
			-- Build per-cell occupancy map (cellOwner[row][col] = {id, size})
			local cellOwner = {}
			for r = 1, 5 do cellOwner[r] = {} end
			for r = 1, 5 do
				for c = 1, 5 do
					local item = items[idolGridSlots[r][c]]
					if item and item.type and idolDims[item.type] then
						local w, h = idolDims[item.type][1], idolDims[item.type][2]
						local size = w * h
						for dr = 0, h - 1 do
							for dc = 0, w - 1 do
								local rr, cc = r + dr, c + dc
								if rr <= 5 and cc <= 5 and not cellOwner[rr][cc] then
									cellOwner[rr][cc] = { id = item, size = size, topRow = r }
								end
							end
						end
					end
				end
			end
			local violation = false
			for col = 1, 5 do
				local prevSize, prevId = nil, nil
				for row = 1, 5 do
					local owner = cellOwner[row][col]
					if owner and owner.id ~= prevId then
						if prevSize and owner.size < prevSize then
							violation = true
							break
						end
						prevSize = owner.size
						prevId = owner.id
					end
				end
				if violation then break end
			end
			if not violation then
				modDB.conditions["NoLargerIdolsAboveSmaller"] = true
			end
		end

		for _, slot in pairs(build.itemsTab.orderedSlots) do
			local slotName = slot.slotName
			local item = items[slotName]
			if slotName:sub(1, 10) == "Omen Idol " then
				-- Idol is merged via the Omen Idol (Refracted) slot path so the
				-- Idol Altar "increased Effect of Prefixes/Suffixes/Weaver
				-- Enchantments for Idols in Refracted Slots" boost can be
				-- applied. If any boost > 0, merge a clone with scaled
				-- valueScalars; else merge the item as-is. The matching copy
				-- in the regular Idol 1-25 grid is skipped below to avoid
				-- double-count.
				if item and (altarBoostPrefix > 0 or altarBoostSuffix > 0 or altarBoostWeaver > 0) then
					item = cloneWithAltarBoost(item)
				end
			elseif item and fracturedItemSet[item] and slotName:match("^Idol %d+$") then
				-- Same idol is also in an Omen Idol slot; the boosted clone is
				-- merged from the Omen Idol path. Skip this copy to avoid
				-- double-counting base mod values.
				item = nil
			end
			if item and item.type == "Flask" then
				if slot.active then
					env.flasks[item] = true
				end
				if item.base.subType == "Life" then
					local highestLifeRecovery = env.itemModDB.multipliers["LifeFlaskRecovery"] or 0
					if item.flaskData.lifeTotal > highestLifeRecovery then
						env.itemModDB.multipliers["LifeFlaskRecovery"] = item.flaskData.lifeTotal
					end
				end
				item = nil
			end
			local scale = 1
			if item then
				env.player.itemList[slotName] = item
				-- Merge mods for this item
				local srcList = item.modList or (item.slotModList and item.slotModList[slot.slotNum]) or {}
				if item.requirements and not accelerate.requirementsItems then
					t_insert(env.requirementsTableItems, {
						source = "Item",
						sourceItem = item,
						sourceSlot = slotName,
						Str = item.requirements.strMod,
						Dex = item.requirements.dexMod,
						Int = item.requirements.intMod,
					})
				end
				if item.type == "Shield" and env.allocNodes[45175] and env.allocNodes[45175].dn == "Necromantic Aegis" then
					-- Special handling for Necromantic Aegis
					env.aegisModList = new("ModList")
					for _, mod in ipairs(srcList) do
						-- Filter out mods that apply to socketed gems, or which add supports
						local add = true
						for _, tag in ipairs(mod) do
							if tag.type == "SocketedIn" then
								add = false
								break
							end
						end
						if add then
							env.aegisModList:ScaleAddMod(mod, scale)
						else
							env.itemModDB:ScaleAddMod(mod, scale)
						end
					end
				elseif (slotName == "Weapon 1" or slotName == "Weapon 2") and modDB.conditions["AffectedByEnergyBlade"] then
					local previousItem = env.player.itemList[slotName]
					local type = previousItem and previousItem.weaponData and previousItem.weaponData[1].type
					local info = env.data.weaponTypeInfo[type]
					if info and type ~= "Bow" then
						local name = info.oneHand and "Energy Blade One Handed" or "Energy Blade Two Handed"
						local item = new("Item")
						item.name = name
						item.base = data.itemBases[name]
						item.baseName = name
						item.classRequirementModLines = { }
						item.buffModLines = { }
						item.enchantModLines = { }
						item.implicitModLines = { }
						item.explicitModLines = { }
						item.quality = 0
						item.rarity = "NORMAL"
						if item.baseName.implicit then
							local implicitIndex = 1
							for line in item.baseName.implicit:gmatch("[^\n]+") do
								local modList, extra = modLib.parseMod(line)
								t_insert(item.implicitModLines, { line = line, extra = extra, modList = modList or { }, modTags = item.baseName.implicitModTypes and item.baseName.implicitModTypes[implicitIndex] or { } })
								implicitIndex = implicitIndex + 1
							end
						end
						item:NormaliseQuality()
						item:BuildAndParseRaw()
						item.sockets = previousItem.sockets
						item.abyssalSocketCount = previousItem.abyssalSocketCount
						env.player.itemList[slotName] = item
					else
						env.itemModDB:ScaleAddList(srcList, scale)
					end
				elseif slotName == "Weapon 1" and item.name == "The Iron Mass, Gladius" then
					-- Special handling for The Iron Mass
					env.theIronMass = new("ModList")
					for _, mod in ipairs(srcList) do
						-- Filter out mods that apply to socketed gems, or which add supports
						local add = true
						for _, tag in ipairs(mod) do
							if tag.type == "SocketedIn" then
								add = false
								break
							end
						end
						if add then
							env.theIronMass:ScaleAddMod(mod, scale)
						end
						-- Add all the stats to player as well
						env.itemModDB:ScaleAddMod(mod, scale)
					end
				elseif slotName == "Weapon 1" and item.grantedSkills[1] and item.grantedSkills[1].skillId == "UniqueAnimateWeapon" then
					-- Special handling for The Dancing Dervish
					env.weaponModList1 = new("ModList")
					for _, mod in ipairs(srcList) do
						-- Filter out mods that apply to socketed gems, or which add supports
						local add = true
						for _, tag in ipairs(mod) do
							if tag.type == "SocketedIn" then
								add = false
								break
							end
						end
						if add then
							env.weaponModList1:ScaleAddMod(mod, scale)
						else
							env.itemModDB:ScaleAddMod(mod, scale)
						end
					end
				elseif item.name:match("Kalandra's Touch") then
					local otherRing = (slotName == "Ring 1" and build.itemsTab.items[build.itemsTab.orderedSlots[59].selItemId]) or (slotName == "Ring 2" and build.itemsTab.items[build.itemsTab.orderedSlots[58].selItemId])
					if otherRing and not otherRing.name:match("Kalandra's Touch") then
						local otherRingList = otherRing and copyTable(otherRing.modList or otherRing.slotModList[slot.slotNum]) or {}
						for index, mod in ipairs(otherRingList) do
							modLib.setSource(mod, item.modSource)
							for _, tag in ipairs(mod) do
								if tag.type == "SocketedIn" then
									otherRingList[index] = nil
									break
								end
							end
						end
						env.itemModDB:ScaleAddList(otherRingList, scale)
					end
					env.itemModDB:ScaleAddList(srcList, scale)
				elseif item.type == "Quiver" and items["Weapon 1"] and items["Weapon 1"].name:match("Widowhail") then
					scale = scale * (1 + (items["Weapon 1"].baseModList:Sum("INC", nil, "EffectOfBonusesFromQuiver") or 100) / 100)
					local combinedList = new("ModList")
					for _, mod in ipairs(srcList) do
						combinedList:MergeMod(mod)
					end
					env.itemModDB:ScaleAddList(combinedList, scale)
				else
					env.itemModDB:ScaleAddList(srcList, scale)
				end
				-- set conditions on restricted items
				if item.classRestriction then
					env.itemModDB.conditions[item.title:gsub(" ", "")] = item.classRestriction
				end
				local key
				if item.rarity == "UNIQUE" then
					key = "UniqueItem"
				elseif item.rarity == "LEGENDARY" then
					key = "LegendaryItem"
				elseif item.rarity == "EXALTED" then
					key = "ExaltedItem"
				elseif item.rarity == "SET" then
					key = "SetItem"
				elseif item.rarity == "RARE" then
					key = "RareItem"
				elseif item.rarity == "MAGIC" then
					key = "MagicItem"
				else
					key = "NormalItem"
				end
				env.itemModDB.multipliers[key] = (env.itemModDB.multipliers[key] or 0) + 1
				env.itemModDB.conditions[key .. "In" .. slotName] = true
				env.itemModDB.multipliers[item.type:gsub(" ", ""):gsub(".+Handed", "").."Item"] = (env.itemModDB.multipliers[item.type:gsub(" ", ""):gsub(".+Handed", "").."Item"] or 0) + 1
			end
			::continue_orderedSlot::
		end
		-- Override empty socket calculation if set in config
		env.itemModDB.multipliers.EmptyRedSocketsInAnySlot = (env.config.overrideEmptyRedSockets or env.itemModDB.multipliers.EmptyRedSocketsInAnySlot)
		env.itemModDB.multipliers.EmptyGreenSocketsInAnySlot = (env.config.overrideEmptyGreenSockets or env.itemModDB.multipliers.EmptyGreenSocketsInAnySlot)
		env.itemModDB.multipliers.EmptyBlueSocketsInAnySlot = (env.config.overrideEmptyBlueSockets or env.itemModDB.multipliers.EmptyBlueSocketsInAnySlot)
		env.itemModDB.multipliers.EmptyWhiteSocketsInAnySlot = (env.config.overrideEmptyWhiteSockets or env.itemModDB.multipliers.EmptyWhiteSocketsInAnySlot)
		if override.toggleFlask then
			if env.flasks[override.toggleFlask] then
				env.flasks[override.toggleFlask] = nil
			else
				env.flasks[override.toggleFlask] = true
			end
		end
		-- Auto-detect offhand type conditions
		if items["Weapon 2"] then
			local offhandType = items["Weapon 2"].type
			if offhandType == "Shield" then
				env.modDB.conditions["UsingShield"] = true
			elseif offhandType == "Catalyst" then
				env.modDB.conditions["UsingCatalyst"] = true
			end
		end

		-- Aggregate equipped SET pieces per setId and apply N-piece bonuses.
		applySetBonuses(env, items, build.targetVersion)
	end

	-- Merge env.itemModDB with env.ModDB
	mergeDB(env.modDB, env.itemModDB)

	-- Add granted passives (e.g., amulet anoints)
	if not accelerate.nodeAlloc then
		for _, passive in pairs(env.modDB:List(nil, "GrantedPassive")) do
			local node = env.spec.tree.notableMap[passive]
			if node and (not override.removeNodes or not override.removeNodes[node.id]) then
				env.allocNodes[node.id] = env.spec.nodes[node.id] or node -- use the conquered node data, if available
				env.grantedPassives[node.id] = true
				env.extraRadiusNodeList[node.id] = nil
			end
		end
	end

	-- Add granted ascendancy node (e.g., Forbidden Flame/Flesh combo)
	local matchedName = { }
	for _, ascTbl in pairs(env.modDB:List(nil, "GrantedAscendancyNode")) do
		local name = ascTbl.name
		if matchedName[name] and matchedName[name].side ~= ascTbl.side and matchedName[name].matched == false then
			matchedName[name].matched = true
			local node = env.spec.tree.ascendancyMap[name]
			if node and (not override.removeNodes or not override.removeNodes[node.id]) then
				if env.itemModDB.conditions["ForbiddenFlesh"] == env.spec.curClassName and env.itemModDB.conditions["ForbiddenFlame"] == env.spec.curClassName then
					env.allocNodes[node.id] = node
					env.grantedPassives[node.id] = true
				end
			end
		else
			matchedName[name] = { side = ascTbl.side, matched = false }
		end
	end

	-- Merge modifiers for allocated passives
	-- Buff skill tree nodes are conditional: only apply when mode_buffs is true AND the skill is enabled
	-- Their mods also have SkillId tags stripped so they apply globally (as buff effects should)
	-- Channelled-buff skills (e.g. Focus) additionally gate their node mods behind Condition:Channelling,
	-- so tooltip-text like Everward "+50% Ward Retention" (description clarifies "while channeled") only
	-- applies when the main skill is channelled or the Config "Are you Channelling?" toggle is on.
	local buffSkillTreePrefixes = {}
	for _, group in pairs(build.skillsTab.socketGroupList) do
		local ge = group.grantedEffect
		if ge and ge.treeId and ge.skillTypes and ge.skillTypes[SkillType.Buff] then
			local prefix = ge.treeId .. "-"
			local existing = buffSkillTreePrefixes[prefix]
			if not existing then
				buffSkillTreePrefixes[prefix] = {
					enabled = group.enabled,
					isChannel = ge.skillTypes[SkillType.Channelling] or false,
				}
			end
		end
	end

	if next(buffSkillTreePrefixes) then
		local normalNodes = {}
		local activeBuffNodes = {}
		local activeChannelNodes = {}
		local inactiveBuffNodes = {}
		for nodeId, node in pairs(env.allocNodes) do
			local isBuffNode = false
			for prefix, info in pairs(buffSkillTreePrefixes) do
				if nodeId:sub(1, #prefix) == prefix then
					isBuffNode = true
					if env.mode_buffs and info.enabled then
						if info.isChannel then
							activeChannelNodes[nodeId] = node
						else
							activeBuffNodes[nodeId] = node
						end
					else
						inactiveBuffNodes[nodeId] = node
					end
					break
				end
			end
			if not isBuffNode then
				normalNodes[nodeId] = node
			end
		end
		-- Normal (non-buff) nodes: apply with SkillId tags intact
		env.modDB:AddList(calcs.buildModListForNodeList(env, normalNodes))
		-- Active buff nodes: strip SkillId tags so mods apply globally
		if next(activeBuffNodes) then
			env.modDB:AddList(calcs.buildModListForNodeList(env, activeBuffNodes, true))
		end
		-- Active channelled-buff nodes: strip SkillId and gate by Condition:Channelling
		if next(activeChannelNodes) then
			env.modDB:AddList(calcs.buildModListForNodeList(env, activeChannelNodes, true, true))
		end
		-- Process inactive buff nodes for side effects (grantedSkills, finalModList) without adding mods
		if next(inactiveBuffNodes) then
			calcs.buildModListForNodeList(env, inactiveBuffNodes)
		end
	else
		env.modDB:AddList(calcs.buildModListForNodeList(env, env.allocNodes))
	end

	-- Auto-compute active Symbols of Hope count (baseline 3 + MaximumSymbols from tree).
	-- Top up Multiplier:ActiveSymbol so it reaches the gameplay max; Config can still
	-- override HIGHER via the 'multiplierActiveSymbols' slider.
	local maxSymbols = 3 + env.modDB:Sum("BASE", nil, "MaximumSymbols")
	local curSymbols = env.modDB:Sum("BASE", nil, "Multiplier:ActiveSymbol")
	if curSymbols < maxSymbols then
		env.modDB:NewMod("Multiplier:ActiveSymbol", "BASE", maxSymbols - curSymbols, "Auto:Symbols of Hope")
	end

	-- Find skills granted by tree nodes
	if not accelerate.nodeAlloc then
		for _, node in pairs(env.allocNodes) do
			for _, skill in ipairs(node.grantedSkills) do
				local grantedSkill = copyTable(skill)
				grantedSkill.sourceNode = node
				t_insert(env.grantedSkillsNodes, grantedSkill)
			end
		end
	end

	-- Add triggered skills
	-- We need the skillModList computed to calculate the skill chance to trigger a given skill
	local grantedTriggeredSkills = {}
	if env.mode ~= "CACHE" then
		for index, group in pairsSortByKey(build.skillsTab.socketGroupList) do
			-- Ailments cannot trigger spells and ailments
			if not group.grantedEffect.baseFlags.ailment and group.enabled then
				local uuid = cacheSkillUUIDFromGroup(group, env)
				local cache = GlobalCache.cachedData["CACHE"][uuid]
				if not GlobalCache.cachedData["CACHE"][uuid]  then
					local activeEffect = {
						grantedEffect = group.grantedEffect,
						srcInstance = group
					}
					local activeSkill = calcs.createActiveSkill(activeEffect, {}, env.player, group)
					calcs.buildActiveSkill(env, "CACHE", activeSkill)
				end
				cache = GlobalCache.cachedData["CACHE"][uuid]
				local activeSkill = cache.ActiveSkill
				for skillId, skill in pairsSortByKey(data.skills) do
					local triggerChance = activeSkill.skillModList:Sum("BASE", activeSkill.skillCfg, "ChanceToTriggerOnHit_"..skillId)
					if triggerChance > 0 then
						t_insert(grantedTriggeredSkills, {
							skillId = skillId,
							source = "SkillId:"..activeSkill.activeEffect.grantedEffect.id,
							triggered = true,
							triggeredOnHit = activeSkill.activeEffect.grantedEffect.id
						})
					end
				end
			end
		end
	end

	-- Merge Granted Skills Tables
	env.grantedSkills = tableConcat(env.grantedSkillsNodes, env.grantedSkillsItems)
	env.grantedSkills = tableConcat(env.grantedSkills, grantedTriggeredSkills)


	if not accelerate.skills then
		if env.mode == "MAIN" then
			-- Process extra skills granted by items or tree nodes
			local markList = wipeTable(tempTable1)
			for grantedIndex, grantedSkill in ipairs(env.grantedSkills) do
				-- Check if a matching group already exists
				local group
				for index, socketGroup in pairs(build.skillsTab.socketGroupList) do
					if socketGroup.source == grantedSkill.source and socketGroup.slot == grantedSkill.slotName then
						if socketGroup.skillId == grantedSkill.skillId then
							group = socketGroup
							markList[socketGroup] = true
							break
						end
					end
				end
				if not group then
					-- Create a new group for this skill
					group = { label = "", enabled = true, source = grantedSkill.source, slot = grantedSkill.slotName }
					build.skillsTab.socketGroupList[5 + grantedIndex] = group
					markList[group] = true
				end

				-- Update the group
				group.sourceItem = grantedSkill.sourceItem
				group.sourceNode = grantedSkill.sourceNode
				group.skillId = grantedSkill.skillId
				group.nameSpec = grantedSkill.nameSpec
				group.noSupports = grantedSkill.noSupports
				group.triggered = grantedSkill.triggered
				group.includeInFullDPS = grantedSkill.includeInFullDPS
				if grantedSkill.triggeredOnHit then
					group.triggeredOnHit = grantedSkill.triggeredOnHit
					group.label = data.skills[grantedSkill.skillId].name .. " (from " .. data.skills[grantedSkill.triggeredOnHit].name ..")"
					for index, socketGroup in pairs(build.skillsTab.socketGroupList) do
						-- find the source socket group and inherit the includeInFullDPS stats
						if socketGroup.skillId == group.triggeredOnHit then
							group.includeInFullDPS = socketGroup.includeInFullDPS
							break
						end
					end
				end
				group.triggerChance = grantedSkill.triggerChance
				build.skillsTab:ProcessSocketGroup(group)
			end

			-- Remove any socket groups that no longer have a matching item
			local i = 1
			while build.skillsTab.socketGroupList[i] do
				local socketGroup = build.skillsTab.socketGroupList[i]
				if socketGroup.source and not markList[socketGroup] then
					t_remove(build.skillsTab.socketGroupList, i)
					if build.skillsTab.displayGroup == socketGroup then
						build.skillsTab.displayGroup = nil
					end
				else
					i = i + 1
				end
			end
		end

		-- Get the weapon data tables for the equipped weapons
		env.player.weaponData1 = env.player.itemList["Weapon 1"] and env.player.itemList["Weapon 1"].base.weapon
		if env.player.weaponData1 then
			env.player.weaponData1.type = env.player.itemList["Weapon 1"].base.type
			env.player.weaponData1.AttackRate = env.player.weaponData1.AttackRateBase
		else
			env.player.weaponData1 = copyTable(env.data.unarmedWeaponData[env.classId])
		end
		if env.player.weaponData1.countsAsDualWielding then
			env.player.weaponData2 = env.player.itemList["Weapon 1"].weaponData[2]
		else
			env.player.weaponData2 = env.player.itemList["Weapon 2"] and env.player.itemList["Weapon 2"].weaponData and env.player.itemList["Weapon 2"].weaponData[2] or { }
		end

		-- Set weapon-type conditions derived from equipped weapons
		do
			local w1type = env.player.weaponData1.type
			local w1info = env.data.weaponTypeInfo[w1type]
			if w1info then
				if w1type == "None" then
					env.modDB.conditions["Unarmed"] = true
				else
					local flag = w1info.flag
					if flag == "Bow" then env.modDB.conditions["UsingBow"] = true
					elseif flag == "Dagger" then env.modDB.conditions["UsingDagger"] = true
					elseif flag == "Staff" then env.modDB.conditions["UsingStaff"] = true
					elseif flag == "Wand" then env.modDB.conditions["UsingWand"] = true
					elseif flag == "Axe" then env.modDB.conditions["UsingAxe"] = true
					elseif flag == "Sword" then env.modDB.conditions["UsingSword"] = true
					end
					if w1type == "Sceptre" then env.modDB.conditions["UsingSceptre"] = true end
					if not w1info.oneHand then env.modDB.conditions["UsingTwoHandedWeapon"] = true end
					if w1info.melee then env.modDB.conditions["UsingMeleeWeapon"] = true end
				end
			end
			local w2type = env.player.weaponData2 and env.player.weaponData2.type
			if w2type and env.data.weaponTypeInfo[w2type] then
				env.modDB.conditions["DualWielding"] = true
			end
		end

		-- Compute +skill level bonus from equipment/modDB
		env.skillLevelBonus = env.modDB:Sum("BASE", nil, "SkillLevel")
		build.skillLevelBonus = env.skillLevelBonus

		-- Determine main skill group
		if env.mode == "CALCS" then
			env.calcsInput.skill_number = m_min(m_max(1, unpack(tableKeys(build.skillsTab.socketGroupList))), env.calcsInput.skill_number or 1)
			env.mainSocketGroup = env.calcsInput.skill_number
		else
			build.mainSocketGroup = m_min(m_max(1, unpack(tableKeys(build.skillsTab.socketGroupList))), build.mainSocketGroup or 1)
			env.mainSocketGroup = build.mainSocketGroup
		end

		-- Process supports and put them into the correct buckets
		env.crossLinkedSupportGroups = {}
		for _, mod in ipairs(env.modDB:Tabulate("LIST", nil, "LinkedSupport")) do
			env.crossLinkedSupportGroups[mod.mod.sourceSlot] = env.crossLinkedSupportGroups[mod.mod.sourceSlot] or {}
			t_insert(env.crossLinkedSupportGroups[mod.mod.sourceSlot], mod.value.targetSlotName)
		end

		local supportLists = { }
		local groupCfgList = { }
		-- Process active skills adding the applicable supports
		local socketGroupSkillListList = { }
		for index, group in pairs(build.skillsTab.socketGroupList) do
			if index == env.mainSocketGroup or group.enabled then
				local slotName = group.slot or "noSlot"
				groupCfgList[slotName] = groupCfgList[slotName] or {}
				groupCfgList[slotName][group] = groupCfgList[slotName][group] or {
					slotName = slotName,
					propertyModList = env.modDB:List({slotName = slotName}, "GemProperty")
				}
				socketGroupSkillListList[slotName] = socketGroupSkillListList[slotName] or {}
				socketGroupSkillListList[slotName][group] = socketGroupSkillListList[slotName][group] or {}
				local socketGroupSkillList = socketGroupSkillListList[slotName][group]
				local groupCfg = groupCfgList[slotName][group]
				local activeEffect = {
					grantedEffect = group.grantedEffect,
					srcInstance = group,
					gemData = {group.grantedEffect},
				}
				applyGemMods(activeEffect, getGemModList(env, groupCfg))
				local activeSkill = calcs.createActiveSkill(activeEffect, {}, env.player, group)
				activeSkill.slotName = groupCfg.slotName
				t_insert(socketGroupSkillList, activeSkill)
				t_insert(env.player.activeSkillList, activeSkill)
			end
		end

		-- Process calculated active skill lists
		for index, group in pairs(build.skillsTab.socketGroupList) do
			local slotName = group.slot
			socketGroupSkillListList[slotName or "noSlot"] = socketGroupSkillListList[slotName or "noSlot"] or {}
			socketGroupSkillListList[slotName or "noSlot"][group] = socketGroupSkillListList[slotName or "noSlot"][group] or {}
			local socketGroupSkillList = socketGroupSkillListList[slotName or "noSlot"][group]
			if index == env.mainSocketGroup or (group.enabled and group.slotEnabled) then
				groupCfgList[slotName or "noSlot"][group] = groupCfgList[slotName or "noSlot"][group] or {
					slotName = slotName,
					propertyModList = env.modDB:List({slotName = slotName}, "GemProperty")
				}
				local groupCfg = groupCfgList[slotName or "noSlot"][group]
				for _, value in ipairs(env.modDB:List(groupCfg, "GroupProperty")) do
					env.player.modDB:AddMod(modLib.setSource(value.value, groupCfg.slotName or ""))
				end

				if index == env.mainSocketGroup and #socketGroupSkillList > 0 then
					-- Select the main skill from this socket group
					local activeSkillIndex
					if env.mode == "CALCS" then
						group.mainActiveSkillCalcs = m_min(#socketGroupSkillList, group.mainActiveSkillCalcs or 1)
						activeSkillIndex = group.mainActiveSkillCalcs
					else
						activeSkillIndex = m_min(#socketGroupSkillList, group.mainActiveSkill or 1)
						if env.mode == "MAIN" then
							group.mainActiveSkill = activeSkillIndex
						end
					end
					env.player.mainSkill = socketGroupSkillList[activeSkillIndex]
				end
			end

			if env.mode == "MAIN" then
				-- Create display label for the socket group if the user didn't specify one
				if group.label and group.label:match("%S") then
					group.displayLabel = group.label
				else
					group.displayLabel = nil
					local grantedEffect = group.grantedEffect
					if grantedEffect and not grantedEffect.support and group.enabled then
						group.displayLabel = grantedEffect.name
					end
					group.displayLabel = group.displayLabel or "<No active skills>"
				end

				-- Save the active skill list for display in the socket group tooltip
				group.displaySkillList = socketGroupSkillList
			elseif env.mode == "CALCS" then
				group.displaySkillListCalcs = socketGroupSkillList
			end
		end

		if not env.player.mainSkill then
			-- Add a default main skill if none are specified
			local defaultEffect = {
				grantedEffect = env.data.skills["Default"],
				level = 1,
				quality = 0,
				enabled = true,
			}
			env.player.mainSkill = calcs.createActiveSkill(defaultEffect, { }, env.player)
			t_insert(env.player.activeSkillList, env.player.mainSkill)
		end

		-- Set effective skill level multipliers for each specialized skill
		-- Effective level = allocated tree points + global bonus from "+X Skills" + per-skill bonus from "+X to [SkillName]"
		-- Note: modDB:Sum with a skillCfg also includes untagged (global) mods, so we subtract
		-- the global bonus to get only the skill-specific portion.
		build.perSkillLevelBonus = build.perSkillLevelBonus or {}
		for index, group in pairs(build.skillsTab.socketGroupList) do
			if group.grantedEffect and group.grantedEffect.treeId then
				local allocatedPoints = build.skillsTab:GetUsedSkillPoints(index)
				-- Sum all SkillLevel mods matching this skill (includes global + skill-specific)
				local skillCfg = { skillName = group.grantedEffect.name, skillTypes = group.grantedEffect.skillTypes }
				local totalSkillLevel = env.modDB:Sum("BASE", skillCfg, "SkillLevel")
				-- Per-skill bonus = total - global (avoid double-counting global)
				local perSkillBonus = totalSkillLevel - (env.skillLevelBonus or 0)
				build.perSkillLevelBonus[index] = perSkillBonus
				local effectiveLevel = allocatedPoints + (env.skillLevelBonus or 0) + perSkillBonus
				env.modDB.multipliers["SkillLevel_" .. group.grantedEffect.name] = effectiveLevel
			end
		end

		-- Build skill modifier lists
		for _, activeSkill in pairs(env.player.activeSkillList) do
			calcs.buildActiveSkillModList(env, activeSkill)
		end
	else
		-- Wipe skillData and readd required data the rest of the data will be added by the rest of code this stops iterative calculations on skillData not being reset
		for _, activeSkill in pairs(env.player.activeSkillList) do
			local skillData = copyTable(activeSkill.skillData, true)
			activeSkill.skillData = { }
			for _, value in ipairs(env.modDB:List(activeSkill.skillCfg, "SkillData")) do
				activeSkill.skillData[value.key] = value.value
			end
			for _, value in ipairs(activeSkill.skillModList:List(activeSkill.skillCfg, "SkillData")) do
				activeSkill.skillData[value.key] = value.value
			end
			-- These mods were modified with special expressions in buildActiveSkillModList() use old one to avoid more calculations
			activeSkill.skillData.manaReservationPercent = skillData.manaReservationPercent
			activeSkill.skillData.cooldown = skillData.cooldown
			activeSkill.skillData.storedUses = skillData.storedUses
			activeSkill.skillData.CritChance = skillData.CritChance
			activeSkill.skillData.attackTime = skillData.attackTime
			activeSkill.skillData.totemLevel = skillData.totemLevel
			activeSkill.skillData.damageEffectiveness = skillData.damageEffectiveness
			activeSkill.skillData.manaReservationPercent = skillData.manaReservationPercent
		end
	end


	-- Merge Requirements Tables
	env.requirementsTable = tableConcat(env.requirementsTableItems, env.requirementsTableGems)

	return env, cachedPlayerDB, cachedEnemyDB, cachedMinionDB
end
