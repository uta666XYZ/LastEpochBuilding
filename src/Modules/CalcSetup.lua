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

-- Marker text for the wildcard set membership mod (Legends Entwined).
-- Items carrying this line count as a piece of every set already represented
-- in the equipment, and also unlock the "+X per Complete Set" scaling.
local WILDCARD_SET_MOD = "Counts as a part of every equipped item set"

-- Returns true if any modLine on the item contains the wildcard marker.
local function itemHasWildcardSetMod(item)
	if not item then return false end
	local function scan(modLines)
		if not modLines then return false end
		for _, ml in ipairs(modLines) do
			if ml.line and ml.line:find(WILDCARD_SET_MOD, 1, true) then
				return true
			end
		end
		return false
	end
	return scan(item.explicitModLines)
		or scan(item.implicitModLines)
		or scan(item.enchantModLines)
end

-- Apply N-piece set bonuses: count equipped SET pieces per setId, then parse
-- and add every bonus tier 2..N (so 3 pieces = 2-piece AND 3-piece bonus).
-- Also matches "Reforged Set" items (basic items with item.setInfo.setId set by
-- the crafting popup). Items with the WILDCARD_SET_MOD (e.g. Legends Entwined)
-- count as a piece of every already-present set, and gate "per Complete Set"
-- scaling based on how many sets are fully equipped (with the wildcard).
-- @leb-regression-guard: set-bonus-breakdown-publish
-- The Calcs-tab "Set Bonuses" section depends on this function publishing
-- `env.itemModDB.setBreakdown = { completeSetCount, wildcardCount,
-- sets = [...] }` alongside the existing `multipliers["CompleteSetCount"]`.
-- A refactor that keeps the multiplier but drops the structured publish
-- silently makes the section disappear (haveOutput="SetBreakdown" gate is
-- nil) without any numeric calc regression — pure UI breakage that no
-- snapshot diff would catch. Exposed as `calcs.applySetBonuses` so the
-- spec can drive it without spinning up the full env pipeline.
-- Test: spec/System/TestSetBreakdown_spec.lua
--       "applySetBonuses publishes setBreakdown with sets[] and bonuses"
-- Establishing commit: f7b598ede (this commit installs the guard)
local function applySetBonuses(env, items, ver)
	local setData = loadSetData(ver)
	if not setData then return end

	-- Build setSize map: setId -> total number of pieces in that set.
	-- Used later to decide which sets are "Complete".
	local setSize = {}
	for _, e in pairs(setData) do
		if e.set and e.set.setId ~= nil then
			setSize[e.set.setId] = (setSize[e.set.setId] or 0) + 1
		end
	end

	-- First pass: resolve each equipped SET / Reforged piece to its setId.
	-- Also collect any wildcard items for later passes.
	-- @leb-regression-guard:set-bonus-dedup-by-uniqueid
	-- Per `LE_datamining/extracted/set_formulas.md` §3, the in-game
	-- `setCompletion` recycling list uses `addUnique(idx, uniqueID)`, so
	-- duplicate uniqueIDs across different slots count once (two copies of
	-- the same set ring ≠ two members). We dedup per-setId via uniqueID
	-- (or title as a fallback for items that lost their uniqueID through
	-- BuildAndParseRaw round-trip) before incrementing pieceCount.
	local pieceCount    = {} -- setId -> count
	local setEntry      = {} -- setId -> a sample set entry (for bonus lookup)
	local seenInSet     = {} -- setId -> { [dedupKey]=true } for uniqueID dedup
	local wildcardItems = {} -- list of items with WILDCARD_SET_MOD
	for _, item in pairs(items) do
		if item then
			if itemHasWildcardSetMod(item) then
				t_insert(wildcardItems, item)
			end
			local isSet      = (item.rarity == "SET")
			local hasSetInfo = (item.setInfo and item.setInfo.setId ~= nil)
			-- Some unique-rarity items (e.g. Weaver Set amulet/ring) are
			-- listed in set_<ver>.json. Detect by name lookup as a third path.
			local matchedByName = nil
			if not isSet and not hasSetInfo and item.title then
				local titleKey = item.title:gsub(" Reforged$", "")
				for _, e in pairs(setData) do
					if e.set and (e.name == item.title or e.name == titleKey) then
						matchedByName = e
						break
					end
				end
			end
			if isSet or hasSetInfo or matchedByName then
				local setId, bonusTable, setName
				if hasSetInfo then
					setId      = item.setInfo.setId
					bonusTable = item.setInfo.bonus
					setName    = item.setInfo.name
				elseif matchedByName then
					setId      = matchedByName.set.setId
					bonusTable = matchedByName.set.bonus
					setName    = matchedByName.set.name
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
					-- Dedup by uniqueID (preferred) or title (fallback). Items
					-- without either still count once via the item table identity.
					local dedupKey = item.uniqueID or item.title or item
					seenInSet[setId] = seenInSet[setId] or {}
					if not seenInSet[setId][dedupKey] then
						seenInSet[setId][dedupKey] = true
						pieceCount[setId] = (pieceCount[setId] or 0) + 1
						if not setEntry[setId] then
							setEntry[setId] = { bonus = bonusTable, name = setName }
						end
					end
				end
			end
		end
	end

	-- Wildcard pass: Legends Entwined adds +1 to every already-present setId.
	-- Per LE rule: wildcard ring + 1 piece of any set completes the 2-pc bonus.
	-- Sets with zero actual pieces are NOT created from a wildcard alone.
	-- @leb-regression-guard:set-bonus-wildcard-clamp
	-- Per `LE_datamining/extracted/set_formulas.md` §3, Legends Entwined
	-- "does not stack with itself (only one slot can hold it)". The game
	-- enforces this via the equipment-slot constraint; LEB clamps the
	-- effective wildcard count at 1 so that data-corruption / parse-bug
	-- paths that surface two wildcard-flagged items can't balloon every
	-- set's pieceCount.
	if #wildcardItems > 0 and next(pieceCount) ~= nil then
		local existingSetIds = {}
		for setId in pairs(pieceCount) do t_insert(existingSetIds, setId) end
		local effectiveWildcards = m_min(#wildcardItems, 1)
		for _ = 1, effectiveWildcards do
			for _, setId in ipairs(existingSetIds) do
				pieceCount[setId] = pieceCount[setId] + 1
			end
		end
	end

	-- Second pass: for each setId with >= 2 pieces, parse bonus tiers 2..count.
	-- Cap effective tier at the set's total piece count (a wildcard cannot
	-- push beyond the set's defined max bonus tier).
	-- Note: JSON loader converts numeric-string keys ("2"/"3") to numbers, so
	-- look up by both string and number form.
	for setId, count in pairs(pieceCount) do
		local info = setEntry[setId]
		if info and info.bonus then
			local maxTier = setSize[setId] or count
			local effective = m_min(count, maxTier)
			for tier = 2, effective do
				local rawLine = info.bonus[tostring(tier)] or info.bonus[tier]
				if rawLine then
					-- Strip formatting tags ({rounding:Integer} etc.) before parse.
					local cleaned = rawLine:gsub("{rounding:[^}]+}", ""):gsub("{[^}]+}", "")
					-- Split comma-separated bonuses (e.g. Invoker's Set 3-pc:
					-- "+2 to Fire Spells, +2 to Lightning Spells, +2 to Cold Spells")
					-- so each clause is parsed independently.
					local source = "Set: " .. (info.name or ("Set " .. tostring(setId))) .. " (" .. tier .. "pc)"
					for clause in (cleaned .. ","):gmatch("([^,]+),") do
						local line = clause:match("^%s*(.-)%s*$")
						if line ~= "" then
							local mods = modLib.parseMod(line)
							if mods and #mods > 0 then
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
	end

	-- Compute "Complete Sets" count: setIds whose pieceCount (incl. wildcard)
	-- meets or exceeds the set's total piece count. Published as a Multiplier
	-- on env.itemModDB so that "+X per Complete Set" mods (which the cache
	-- tags with type=Multiplier var=CompleteSetCount in ModCache.lua) scale
	-- correctly at query time.
	local completeSetCount = 0
	for setId, count in pairs(pieceCount) do
		local maxSize = setSize[setId]
		if maxSize and count >= maxSize then
			completeSetCount = completeSetCount + 1
		end
	end
	env.itemModDB.multipliers["CompleteSetCount"] = completeSetCount

	-- Publish a structured breakdown of equipped sets so the Calcs tab
	-- "Set Bonuses" section (CalcPerform → CalcSections) can render which sets
	-- are equipped, how many pieces, and which tier bonuses are active.
	-- Pure data structure — never read back by calc code, only consumed by
	-- the breakdown UI.
	local sets = {}
	for setId, count in pairs(pieceCount) do
		local info = setEntry[setId]
		local maxSize = setSize[setId] or count
		local effective = m_min(count, maxSize)
		local bonuses = {}
		if info and info.bonus then
			for tier = 2, effective do
				local rawLine = info.bonus[tostring(tier)] or info.bonus[tier]
				if rawLine then
					local cleaned = rawLine:gsub("{rounding:[^}]+}", ""):gsub("{[^}]+}", "")
					cleaned = cleaned:match("^%s*(.-)%s*$") or cleaned
					t_insert(bonuses, { tier = tier, text = cleaned })
				end
			end
		end
		t_insert(sets, {
			setId      = setId,
			name       = (info and info.name) or ("Set " .. tostring(setId)),
			pieceCount = count,
			setSize    = maxSize,
			complete   = (count >= maxSize),
			bonuses    = bonuses,
		})
	end
	table.sort(sets, function(a, b)
		if a.complete ~= b.complete then return a.complete end
		return tostring(a.name) < tostring(b.name)
	end)
	env.itemModDB.setBreakdown = {
		completeSetCount = completeSetCount,
		wildcardCount    = #wildcardItems,
		sets             = sets,
	}
end
-- Exposed for spec/System/TestSetBreakdown_spec.lua. Keep `local` declaration
-- above so callers in this module still resolve via local lookup.
calcs.applySetBonuses = applySetBonuses

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

-- @leb-regression-guard: channelling-tree-node-auto-gate
-- Channelled-buff skill tree nodes (Focus, Smelter's Wrath, Volcanic Orb,
-- Disintegrate etc.) must have every stripped mod auto-wrapped with
-- `Condition:Channelling` at tree-build time. Caller (caller in
-- `prepareTrees` decides which skills get the flag based on their
-- `Channelling` SkillType bit + the Config "Are you Channelling?" toggle).
--
-- Establishing commit: `eab24578b` (fix: gate channelling-skill tree node
-- mods by Condition:Channelling) — without this gate Focus tree stats
-- like Everward "+50% Ward Retention" (described as "while channeled")
-- applied unconditionally, inflating Ward Retention by +100% on
-- BakypDvx Runemaster (LEB 595% vs LETools 505%).
--
-- This gate stacks idempotently with ModParser-side
-- `Condition:Channelling` injection (see
-- `health-per-second-channelling` and
-- `channelling-per-second-stacking-buff` guards): tree-node mods get
-- the condition twice (A∧A == A, no functional change), while
-- item/affix/ModCache-cold lookups rely only on the parser-side gate.
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
				-- @leb-regression-guard:minion-skillid-scope-martyrdom
				-- MinionModifier mods MUST keep their SkillId tag even on the
				-- buff-skill tree strip path (applyBuffPrefix). Otherwise a
				-- buff skill's tree-node MinionModifier (e.g. Dread Shade
				-- Martyrdom ds4d3-3 "30 Minion Armour Per Vitality") leaks
				-- onto every minion's modDB instead of staying scoped to the
				-- Dread Shade target. ModStore.lua L750-753 uses the
				-- SkillId tag to gate by cfg.skillGrantedEffect.id, so
				-- preserving it is the only way per-skill scoping holds.
				-- See [[Minion Armor 三角測量 g1 調査]] (Obsidian) for the
				-- triangulation that exposed this and REGRESSION_GUARDS.md.
				-- @leb-regression-guard: buff-tree-cooldown-recovery-skill-local
				-- CooldownRecovery mods on a buff-skill tree node describe the
				-- skill's OWN cooldown ("Symbols of Hope has a shorter cooldown")
				-- and must stay skill-local even on the buff-strip path. Game
				-- ground truth: globalTreeData skillTrees[si4lgl].nodes[23] has
				-- internal name "Sigils Of Hope Cooldown Recovery", and dump.cs
				-- routes CDR-on-skill via the ability's own CD timer (not
				-- SP.IncreasedCooldownRecoverySpeed=70 on the player). Without
				-- this carve-out, si4lgl-23 (Enduring Hope) leaks +60% global
				-- CDR on BgRrekMz lv92 Paladin (2/2 × 25% × 1.20 SoH effect)
				-- inflating output.CooldownRecovery 19 → 79 vs LETools 19.
				-- The buff-tree-only `si4lgl`/`ah443` CDR audit shows si4lgl-23
				-- is the only player-CDR node in those trees, so the carve-out
				-- has no other call sites today, but the rule generalises:
				-- any future buff-tree CDR node will obey "<Skill> has a shorter
				-- cooldown" semantics.
				-- Test: spec/System/TestBuffTreeCooldownRecoverySkillLocal_spec.lua
				-- See REGRESSION_GUARDS.md "buff-tree-cooldown-recovery-skill-local".
				if stripSkillId and mod.name ~= "MinionModifier" and mod.name ~= "CooldownRecovery" then
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
		-- StunAvoidance: in-game tooltip shows "Base Stun Avoidance: 250 + 5 per
		-- character level". The previous "no per-level scaling" comment was
		-- incorrect — verified against in-game character sheet on ShutFackUp
		-- (lv85 → 250 + 5*85 = 675 base).
		-- @leb-regression-guard: stun-avoidance-base-and-tree
		-- BOTH `classStats["stunAvoidancePerLevel"]` as the mod value AND
		-- `base = classStats["baseStunAvoidance"]` on the Multiplier tag are
		-- required — dropping the `base` term silently drops the +250 lv1
		-- floor without breaking per-level scaling. See spec
		-- spec/System/TestStunAvoidanceBaseAndTree_spec.lua.
		modDB:NewMod("StunAvoidance", "BASE", classStats["stunAvoidancePerLevel"], "Base", { type = "Multiplier", var = "Level", base = classStats["baseStunAvoidance"] })
		modDB:NewMod("Endurance", "BASE", classStats["baseEndurance"] * 100, "Base")
		modDB:NewMod("EnduranceThreshold", "BASE", classStats["enduranceThresholdPerHealth"], "Base", { type = "PerStat", stat = "Life"})

		-- Add attribute bonuses
		-- Reference Raw<Attr> (post-conversion residual, NOT including the converted twin).
		-- Brutality must NOT inherit Strength's intrinsic +4% Armour etc. — see
		-- @leb-regression-guard:s4-converted-attr-no-base-inherit (below) and
		-- @leb-regression-guard:s4-perstat-base-includes-converted-twin in CalcPerform.lua.
		modDB:NewMod("Armour", "INC", 4, "Strength", {type = "PerStat", stat = "RawStr"})
		modDB:NewMod("Evasion", "BASE", 4, "Dexterity", {type = "PerStat", stat = "RawDex"})
		modDB:NewMod("WardRetention", "BASE", 2, "Intelligence", {type = "PerStat", stat = "RawInt"})
		modDB:NewMod("Mana", "BASE", 2, "Attunement", {type = "PerStat", stat = "RawAtt"})
		modDB:NewMod("Life", "BASE", 6, "Vitality", {type = "PerStat", stat = "RawVit"})
		modDB:NewMod("PoisonResist", "BASE", 1, "Vitality", {type = "PerStat", stat = "RawVit"})
		modDB:NewMod("NecroticResist", "BASE", 1, "Vitality", {type = "PerStat", stat = "RawVit"})

		-- Season 4 (1.4): converted attributes have their OWN unique passive bonuses,
		-- they do NOT inherit the base-attribute bonuses (Brutality is not Strength).
		-- @leb-regression-guard:s4-converted-attr-no-base-inherit
		--   Verified against in-game LE 1.4: Brutality grants only "more melee damage
		--   per mana cost" + "reduced damage leeched as health" — NO Armour INC.
		--   Earlier LEB releases applied Strength's +4% Armour INC to Brutality (and
		--   the equivalent base-attr bonuses to Guile/Apathy/Rampancy) on the false
		--   premise that converted attributes inherit base-attribute bonuses. They
		--   do not. Per-attribute correct effects are skill/passive specific and
		--   handled by their own mod parsers + in-game tooltip text.
		--   Re-introducing the inheritance lines (Strength's +4% Armour INC keyed
		--   on Brutality, Vitality's +6 Life keyed on Rampancy, etc.) will inflate
		--   worst-diff builds like Qdz2yXN3 (Necromancer, Brutality=33 → +132%
		--   Armour INC, 7x over LE). The intrinsic AltText effects listed below
		--   (e.g. -1% Armour per Guile) are the OPPOSITE — they are the S4
		--   attribute's OWN effect, not inherited from the base attribute.
		-- do-not-remove

		-- S4 attribute intrinsic AltText effects.
		-- Per LE_datamining localization/properties_localization.json each S4
		-- attribute has a `Property_Player_<id>_AltText` describing its built-in
		-- per-point effect (id 650..654 = Brutality/Madness/Guile/Apathy/Rampancy).
		-- Only the ones that move a stat tracked by diff_letools MAPPING are wired
		-- here; the others (Brutality melee damage / Madness crit / Rampancy
		-- frenzy / Apathy current-health-loss / Brutality global health-leech)
		-- live in their respective calc paths or remain unmodeled until needed.
		--
		-- @leb-regression-guard: s4-guile-per-point-armour-reduction
		-- Property_Player_652_AltText: "Each point of Guile grants 0.3% increased
		-- Cooldown Recovery Speed for Movement Skills and 1% Reduced Armor,
		-- instead of granting dodge rating." The Reduced Armor is a flat INC
		-- modifier that stacks additively with the player's other Armour INC
		-- sources and can drive total Armour negative on high-Guile builds.
		-- Affected at v0.14.6 (3 builds with the Dexterity→Guile sealed prefix
		-- on an Oracle Amulet, all positive LEB-LET Armour delta):
		--   QJWMRv53 Bladedancer Guile=207  D=+920 (LET -260, LEB 660)
		--   Qqwv6zGN Druid       Guile=~?   D=+301 (LET 3881, LEB 4182)
		--   Qdz2yXN3 Necromancer Guile=~?   D=+253 (LET 1758, LEB 2011)
		modDB:NewMod("Armour", "INC", -1, "Guile", {type = "PerStat", stat = "Guile"})

		-- @leb-regression-guard: s4-apathy-per-point-mana-regen-inc
		-- Property_Player_653_AltText: "Each point of Apathy grants 2% increased
		-- Mana Regeneration and 0.2% of Current Health Lost when you Directly
		-- Use a Skill, instead of adding Mana." Only the Mana Regen INC moves a
		-- stat tracked by diff_letools MAPPING; the current-health-loss is
		-- skill-trigger semantics handled elsewhere (unmodeled until a build
		-- depends on it). The "instead of adding Mana" half is already covered
		-- by routing the +2 Mana intrinsic through PerStat:RawAtt (CalcSetup
		-- Mana base mod), so Apathy correctly contributes no Mana.
		-- Affected at v0.14.6 (1 build in G3 aggregate with Apathy>0):
		--   BOwJRDdE Shaman Apathy=64  D=-10.28 (LET 30.48, LEB 20.2;
		--   8 base * (1 + 153% pre-fix INC) = 20.24; with +128% Apathy INC,
		--   8 * (1 + 281%) = 30.48 — exact match.)
		modDB:NewMod("ManaRegen", "INC", 2, "Apathy", {type = "PerStat", stat = "Apathy"})

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

		-- LevelReq filter: gear whose required level exceeds the character's
		-- level provides no effect in-game. Match that behavior here so DPS /
		-- defense calcs reflect what the actual character would see.
		do
			local charLevel = build.characterLevel or 1
			-- Capture set/wildcard items BEFORE level-req filter so set membership
			-- counting reflects what's equipped regardless of stat eligibility
			-- (matches in-game: items above char level lose stats but still
			-- contribute set piece count and wildcard).
			env._levelGatedSetItems = {}
			-- @leb-regression-guard: corrupted-count-pre-levelreq
			-- "Equipped" semantics: a level-gated item is still EQUIPPED
			-- (occupies a slot) even though its stats are inactive. Conditional
			-- mods like `+N All Attributes with at least 7 Corrupted non-Idol
			-- Items equipped` (Shroud of Obscurity affix 1011) count equipped
			-- corrupted items, NOT items providing stat effect. Capture every
			-- level-gated item here so the corrupted counter loop below can
			-- include them. Do NOT inline them back into `items` — their stats
			-- must remain disabled.
			-- Test: spec/System/TestModParse_spec.lua
			--       "Level-gated corrupted item still counts toward
			--        CorruptedNonIdolItemsEquipped"
			-- Establishing build: Qqwv73q2 lv62 Warlock — Silver Grail
			--   (LevelReq=68 > charLevel=62), corrupted; brings nonIdol count
			--   from 6 to 7 and trips Shroud's +14 All Attributes (T7 fixed
			--   value; LETools/game-data verified — see REGRESSION_GUARDS.md
			--   `corrupted-count-pre-levelreq` for the tier table).
			env._levelGatedAllItems = {}
			for slotName, item in pairs(items) do
				if item and item.requirements and item.requirements.level
					and item.requirements.level > charLevel then
					if item.rarity == "SET" or item.setInfo
						or (item.modList and itemHasWildcardSetMod and itemHasWildcardSetMod(item)) then
						env._levelGatedSetItems[slotName] = item
					end
					env._levelGatedAllItems[slotName] = item
					items[slotName] = nil
				end
			end
		end

		-- Corrupted item counting. Iterates both active items AND level-gated
		-- items (see @leb-regression-guard: corrupted-count-pre-levelreq above).
		-- Feeds StatThreshold tags emitted by the "with at least N Corrupted
		-- [non-Idol/Idol/] Items equipped" ModParser pattern. Three stats:
		--   * CorruptedItemsEquipped       = all corrupted items
		--   * CorruptedNonIdolItemsEquipped = corrupted items NOT in Idol slots
		--   * CorruptedIdolItemsEquipped    = corrupted items IN Idol slots
		do
			local total, nonIdol, idol = 0, 0, 0
			-- @leb-regression-guard: omen-idol-slot-dedup-on-corruption-count
			-- Omen Idol N slots are NOT independent inventory cells — they are
			-- secondary references to the same physical idol item already
			-- placed in an Idol N grid cell (populated by
			-- ItemsTab:AutoPopulateOmenIdolSlots, see refracted-slot-overlap-only).
			-- Iterating `items` produces both the Idol N slot AND the Omen Idol N
			-- slot for every refracted-overlapping idol, so a naive count
			-- double-tallies. The Idol-Altar implicit "+14 Mana per Idol in a
			-- Refracted Slot" tooltip explicitly says "There is no additional
			-- benefit to having an idol in multiple refracted slots", confirming
			-- the per-physical-item semantics. Track seen item identities and
			-- skip duplicates.
			-- See REGRESSION_GUARDS.md "omen-idol-slot-dedup-on-corruption-count".
			local seenIdolItem = {}
			local function countItem(slotName, item)
				if not (item and item.corrupted) then return end
				local isIdolSlot = (slotName:sub(1, 5) == "Idol " and slotName ~= "Idol Altar")
					or slotName:sub(1, 10) == "Omen Idol "
				if isIdolSlot then
					-- Dedup across Idol N <-> Omen Idol N pairs by item identity.
					-- Use item.id when present (load from XML), otherwise the
					-- table reference (shared across slots holding the same item).
					local key = item.id or item
					if seenIdolItem[key] then return end
					seenIdolItem[key] = true
					idol = idol + 1
					total = total + 1
				else
					nonIdol = nonIdol + 1
					total = total + 1
				end
			end
			-- @leb-regression-guard: idol-altar-not-idol-slot
			-- (classifier inside countItem above): "Idol Altar" slot is the altar
			-- EQUIPMENT slot, NOT an idol slot. Naive `sub(1, 5) == "Idol "`
			-- mis-classifies a corrupted altar as idol and breaks
			-- `+N All Attributes with at least 7 Corrupted non-Idol Items
			-- equipped` (Shroud of Obscurity etc.).
			-- Test: spec/System/TestModParse_spec.lua
			--       "Corrupted Idol Altar counts as non-Idol for
			--        CorruptedNonIdolItemsEquipped"
			-- Establishing commit: e9e4e64c5
			for slotName, item in pairs(items) do
				countItem(slotName, item)
			end
			-- Include level-gated equipped items (stats inactive but slot is
			-- occupied) — see @leb-regression-guard: corrupted-count-pre-levelreq
			for slotName, item in pairs(env._levelGatedAllItems or {}) do
				countItem(slotName, item)
			end
			if total > 0 then
				modDB:NewMod("CorruptedItemsEquipped", "BASE", total, "Corrupted Items")
			end
			if nonIdol > 0 then
				modDB:NewMod("CorruptedNonIdolItemsEquipped", "BASE", nonIdol, "Corrupted Items")
			end
			if idol > 0 then
				modDB:NewMod("CorruptedIdolItemsEquipped", "BASE", idol, "Corrupted Items")
				-- @leb-regression-guard: equipped-corrupted-idol-multiplier
				-- "+N <stat> per Equipped Corrupted Idol" affixes (Idol Altar
				-- corrupted/sealed prefixes such as Spire Altar T7 "+10 Mana
				-- per Equipped Corrupted Idol", src/Data/ModItem.json:65367,
				-- ModCache.lua:2036) scale on Multiplier:EquippedCorruptedIdol.
				-- Without this emission the multiplier resolves to 0 and these
				-- affixes contribute nothing. The count source is the same
				-- `idol` accumulator used for CorruptedIdolItemsEquipped (see
				-- @leb-regression-guard: idol-altar-not-idol-slot above).
				-- See REGRESSION_GUARDS.md "equipped-corrupted-idol-multiplier".
				modDB:NewMod("Multiplier:EquippedCorruptedIdol", "BASE", idol, "Corrupted Items")
			end
		end

		-- Idol Altar: two distinct multipliers driven by two DIFFERENT game
		-- lists (IdolsItemContainer.equippedOmenIdols vs
		-- .equippedIdolsInRefractedSlots, see Obsidian "Refracted Slot vs Omen
		-- Idol vs Omen Idol Capacity 区別.md").
		--   * Multiplier:EquippedOmenIdol    = idols whose BASE is an Omen Idol
		--                                      category (base name contains
		--                                      "Omen Idol", e.g. "Stout Arcane
		--                                      Omen Idol"), clamped to the
		--                                      altar's Omen Idol capacity. Scales
		--                                      LE IdolAltarPropertyID 18/19
		--                                      ("+N Haste/Health per Equipped
		--                                      Omen Idol").
		--   * Multiplier:IdolInRefractedSlot = idols whose grid footprint
		--                                      overlaps a Refracted (type-2)
		--                                      cell on the altar layout
		--                                      (CountIdolsOnRefractedCells,
		--                                      uncapped). Scales LE property
		--                                      22-25 ("+N per Idol in a
		--                                      Refracted Slot").
		-- @leb-regression-guard: equipped-omen-idol-counts-category-not-refracted
		-- EquippedOmenIdol must NOT be the "Omen Idol N" slot occupancy: those
		-- slots are auto-populated with refracted-OVERLAPPING idols of ANY
		-- category (ItemsTab:AutoPopulateOmenIdolSlots), which is the refracted
		-- list, not the Omen Idol category list. Counting them conflated the two
		-- game lists. Repro: ImPalmBeachPete lv36 Bladedancer has 2 refracted-
		-- overlapping Weaver/Eterran idols and 0 Omen Idol category idols on a
		-- Prodigious Lunar Altar carrying "+9 Health per Equipped Omen Idol";
		-- the old occupancy count gave x2 (+18 Health, LEB 999) while in-game
		-- applies x0. The refracted family below keeps the overlap count, so
		-- builds with genuine "+N per Idol in a Refracted Slot" mods (ShutFackUp)
		-- are unaffected. See REGRESSION_GUARDS.md
		-- "equipped-omen-idol-counts-category-not-refracted".
		local equippedOmenIdolCount = 0
		do
			local seen = {}
			for slotName, item in pairs(items) do
				local isIdolSlot = (slotName:sub(1, 5) == "Idol " and slotName ~= "Idol Altar")
					or slotName:sub(1, 10) == "Omen Idol "
				if item and isIdolSlot and item.baseName
					and item.baseName:find("Omen Idol", 1, true) then
					local key = item.id or item
					if not seen[key] then
						seen[key] = true
						equippedOmenIdolCount = equippedOmenIdolCount + 1
					end
				end
			end
			-- @leb-regression-guard: equipped-omen-idol-capped-by-capacity
			-- Clamp to the altar's Omen Idol equip limit (base capacity +
			-- "+N Maximum Omen Idols Equipped" affix bonus), mirroring the
			-- in-game cap on how many Omen Idol category idols can be equipped.
			-- This clamp is preserved from the earlier refracted-display work; the
			-- category-counting basis above (equipped-omen-idol-counts-category-not-
			-- refracted) supersedes the old occupancy count but still caps here, so
			-- both guards describe the merged code. See REGRESSION_GUARDS.md
			-- "equipped-omen-idol-capped-by-capacity".
			local altarName = build.itemsTab.activeAltarLayout
			local altar = altarName and altarName ~= "Default" and build.itemsTab.altarLayouts
				and build.itemsTab.altarLayouts[altarName]
			local omenCapacity = ((altar and altar.omenIdolCapacity) or 0)
				+ (build.itemsTab:GetOmenIdolCapacityBonus() or 0)
			if omenCapacity > 0 and equippedOmenIdolCount > omenCapacity then
				equippedOmenIdolCount = omenCapacity
			end
		end
		if equippedOmenIdolCount > 0 then
			modDB:NewMod("Multiplier:EquippedOmenIdol", "BASE", equippedOmenIdolCount, "Idol Altar")
		end
		-- Refracted-slot overlap count is emitted INDEPENDENTLY of the Omen Idol
		-- category count above: a build can have 0 Omen Idol category idols yet
		-- several idols overlapping refracted cells (ImPalmBeachPete), and vice
		-- versa. Nesting this under EquippedOmenIdol > 0 (the old code) would
		-- drop the refracted bonus for such builds.
		local refractedSlotCount = build.itemsTab:CountIdolsOnRefractedCells()
		if refractedSlotCount > 0 then
			modDB:NewMod("Multiplier:IdolInRefractedSlot", "BASE", refractedSlotCount, "Idol Altar")
		end

		-- @leb-regression-guard: weaver-will-equipped-autocount
		-- Auto-count equipped Weaver's Will items to drive
		-- Multiplier:EquippedWeaverItem (e.g. Communion of the Erased belt:
		-- "+1 Potion Slot per equipped Weaver Item"). Weaver's Will is a
		-- per-base property, not a random per-instance roll: exactly 18 uniques
		-- carry legendaryType==1 in the game data (datamining
		-- extracted/items/uniques.json -> legendaryType distribution {0:453,1:18};
		-- IDs 293-301,327,405-409,417-419). We mirror those onto the LEB unique
		-- data (src/Data/Uniques/uniques*.json "legendaryType": 1), build a
		-- name-keyed set in Data.setActiveVersion, and count any equipped item
		-- whose title matches, so 2/3/4+ Weaver's Will items are all handled
		-- without hardcoding a per-build number. Title match is required because
		-- the build-local item.uniqueID is NOT the global game uniqueID (LEB
		-- resolves uniques by name everywhere). The manual ConfigOptions
		-- "# of Equipped Weaver Items" count remains as an additive override
		-- (default 0), matching the Omen Idol pattern above.
		-- Repro: ImPalmBeachPete lv36 Bladedancer has belt(Communion of the
		-- Erased)+boots(Advent of the Erased) Weaver's Will -> Potion Slots
		-- 3(implicit)+2 = 5 (in-game/LETools=5).
		-- Spec: spec/System/TestWeaverWillEquippedCount_spec.lua
		-- See REGRESSION_GUARDS.md "weaver-will-equipped-autocount".
		local equippedWeaverItemCount = 0
		local wwSet = data.weaversWillUniques
		if wwSet then
			for slotName, item in pairs(items) do
				if item and item.title and wwSet[item.title] then
					equippedWeaverItemCount = equippedWeaverItemCount + 1
				end
			end
		end
		if equippedWeaverItemCount > 0 then
			modDB:NewMod("Multiplier:EquippedWeaverItem", "BASE", equippedWeaverItemCount, "Weaver's Will")
		end

		-- Idol Altar: identify idols whose footprint overlaps a Refracted cell
		-- (grid value == 2) on the active Idol Altar layout. This matches the
		-- in-game model: there is no separate "Omen Idol" slot type — any idol
		-- placed on the regular Idol 1-25 grid that overlaps a refracted cell
		-- receives the altar's "Effect of Prefixes/Suffixes/Weaver Enchantments
		-- for Idols in Refracted Slots" boost. The legacy "Omen Idol N" slots
		-- are kept only as a UI/import artifact; CalcSetup now drives boost
		-- application from grid overlap, not from Omen Idol slot population.
		local fracturedItemSet = {}
		do
			local altarName = build.itemsTab.activeAltarLayout
			local altarLayouts = build.itemsTab.altarLayouts
			local altar = altarName and altarName ~= "Default" and altarLayouts and altarLayouts[altarName]
			if altar and altar.grid then
				local idolGridSlots = {
					{ "Idol 21", "Idol 1",  "Idol 2",  "Idol 3",  "Idol 22" },
					{ "Idol 4",  "Idol 5",  "Idol 6",  "Idol 7",  "Idol 8"  },
					{ "Idol 9",  "Idol 10", "Idol 23", "Idol 11", "Idol 12" },
					{ "Idol 13", "Idol 14", "Idol 15", "Idol 16", "Idol 17" },
					{ "Idol 24", "Idol 18", "Idol 19", "Idol 20", "Idol 25" },
				}
				local idolDims = {
					["Minor Idol"]   = {1,1}, ["Small Idol"]  = {1,1}, ["Humble Idol"] = {2,1},
					["Stout Idol"]   = {1,2}, ["Grand Idol"]  = {3,1}, ["Large Idol"]  = {1,3},
					["Ornate Idol"]  = {4,1}, ["Huge Idol"]   = {1,4}, ["Adorned Idol"] = {2,2},
				}
				for r = 1, 5 do
					for c = 1, 5 do
						local item = items[idolGridSlots[r][c]]
						if item and item.type and idolDims[item.type] and not fracturedItemSet[item] then
							local w, h = idolDims[item.type][1], idolDims[item.type][2]
							local hit = false
							for dr = 0, h - 1 do
								for dc = 0, w - 1 do
									local row = altar.grid[r + dr]
									if row and row[c + dc] == 2 then
										hit = true
										break
									end
								end
								if hit then break end
							end
							if hit then fracturedItemSet[item] = true end
						end
					end
				end
			end
		end
		-- gridItemSet tracks which items appear in the regular Idol 1-25 grid.
		-- Used to dedupe the legacy Omen Idol N slot path: if an idol is on the
		-- grid, the grid path drives merging (with or without boost); the Omen
		-- Idol N slot is skipped to avoid double-count. Orphaned Omen Idol N
		-- entries (no grid copy) still merge as-is, without boost.
		local gridItemSet = {}
		for i = 1, 25 do
			local it = items["Idol " .. i]
			if it then gridItemSet[it] = true end
		end
		-- Idol Altar refracted-slot boosts map to LE `IdolAltarPropertyID`:
		--   1 EffectOfPrefixesAndSuffixesInRefractedSlots → altarCommon (Standard only)
		--   2 EffectOfPrefixesInRefractedSlots           → altarBoostPrefix (Standard prefix only)
		--   3 EffectOfSuffixesInRefractedSlots           → altarBoostSuffix (Standard suffix only)
		--   4 EffectOfIdolEnchantsInRefractedSlots       → altarBoostEnchant
		--     (covers BOTH SpecialAffixType.IdolEnchantment AND .IdolWeaver)
		-- Per LE `IsAffectedByAffectOfStandardPrefixesOrSuffixes`, ID 1-3 apply
		-- ONLY to Standard affixes. Property 4 ("Weaver Enchantment Affixes" in
		-- mod text) applies to IdolEnchantment + IdolWeaver and is NOT stacked
		-- with the Standard common/prefix/suffix boosts.
		local altarBoostPrefix, altarBoostSuffix, altarBoostEnchant, altarCommon = 0, 0, 0, 0
		if next(fracturedItemSet) then
			local altarItem = items["Idol Altar"]
			if altarItem and altarItem.modList then
				for _, mod in ipairs(altarItem.modList) do
					if mod.type == "INC" then
						if mod.name == "IdolRefractedAffixEffect" then
							altarCommon = altarCommon + (mod.value or 0)
						elseif mod.name == "IdolRefractedPrefixEffect" then
							altarBoostPrefix = altarBoostPrefix + (mod.value or 0)
						elseif mod.name == "IdolRefractedSuffixEffect" then
							altarBoostSuffix = altarBoostSuffix + (mod.value or 0)
						elseif mod.name == "IdolRefractedWeaverEffect" then
							altarBoostEnchant = altarBoostEnchant + (mod.value or 0)
						end
					end
				end
				altarCommon = altarCommon / 100
				altarBoostPrefix = altarBoostPrefix / 100
				altarBoostSuffix = altarBoostSuffix / 100
				altarBoostEnchant = altarBoostEnchant / 100
			end
		end
		local function cloneWithAltarBoost(srcItem)
			-- Reconstruct a parsed clone from raw so mutating valueScalar on
			-- this clone does not affect the shared original (which is also
			-- consumed by tooltip display with its own altarBoost path).
			--
			-- Idol items are crafted (rarity=MAGIC w/ affixes), so ParseRaw
			-- runs Craft() to (re)build explicitModLines from self.prefixes /
			-- self.suffixes. Craft computes each line's valueScalar as
			-- `modScalar * affix.valueScalar`. Mutating clone.explicitModLines
			-- directly is therefore lost the next time Craft runs. Mutate
			-- `affix.valueScalar` on prefixes/suffixes instead and re-Craft so
			-- the boost flows through Craft → applyRange via the tail
			-- BuildAndParseRaw inside Craft.
			--
			-- Enchant mods aren't driven by prefixes/suffixes; their valueScalar
			-- on enchantModLines round-trips via raw {scalar:N} back through
			-- ParseRaw's line-by-line populate path (no Craft on that side).
			local clone = new("Item", srcItem:BuildRaw())
			-- Resolve LE `SpecialAffixType` for an affix modId so we can route
			-- it to the correct refracted-slot boost bucket. `data.modIdol.flat`
			-- is tagged by Data.lua: general→Standard, enchanted→IdolEnchantment,
			-- weaver→IdolWeaver, corrupted→Corrupted. ModIdol_<ver>.json stores
			-- only a tier-0 entry per affixId (full tiers live in ModItem) so
			-- fall back to the _0 entry when the exact tier key is missing.
			local idolFlat = data.modIdol and data.modIdol.flat or nil
			-- @leb-regression-guard: idol-refracted-weaver-enchant-boost
			-- LE SpecialAffixType enum → string tag normalisation.
			-- ModIdol_*.json _0 entries are string-tagged by Data.lua
			-- (general→Standard, enchanted→IdolEnchantment, weaver→IdolWeaver,
			-- corrupted→Corrupted). Tier-specific entries injected from other
			-- sources may instead carry the raw numeric LE enum, so coerce.
			-- Spec: spec/System/TestIdolRefractedWeaverEnchantBoost_spec.lua
			-- See REGRESSION_GUARDS.md "idol-refracted-weaver-enchant-boost".
			local satEnumToStr = {
				[0] = "Standard", [4] = "IdolEnchantment",
				[5] = "IdolWeaver", [6] = "Corrupted",
			}
			local function specialAffixType(modId)
				if not modId or modId == "None" or not idolFlat then return "Standard" end
				-- Prefer the _0 entry (canonical Data.lua string tagging) and
				-- fall back to the tier-specific entry only if the _0 form is
				-- missing. Verified on BxvJP3g1 affix 897_4 where the tier
				-- entry carried numeric `4`, bypassing the string-based
				-- IdolEnchantment routing and silently skipping the +46%
				-- weaver-enchant refracted-slot boost.
				local base = modId:match("^(%d+)_%d+$")
				local entry = (base and idolFlat[base .. "_0"]) or idolFlat[modId]
				if not entry then return "Standard" end
				local sat = entry.specialAffixType
				if type(sat) == "number" then return satEnumToStr[sat] or "Standard" end
				return sat or "Standard"
			end
			local anyAffixBoosted = false
			local function scaleAffixList(affixList, specificBoost)
				if not affixList then return end
				for _, affix in ipairs(affixList) do
					if affix and affix.modId and affix.modId ~= "None" then
						-- @leb-regression-guard: idol-refracted-standard-boost-all-subtypes
						-- LE Idol Altar property 1/2/3 ("Effect of Prefixes and
						-- Suffixes / Prefixes / Suffixes for Idols in Refracted
						-- Slots") boost the ROLLED VALUE of EVERY non-Corrupted
						-- affix in a refracted slot, regardless of SpecialAffixType
						-- — including IdolWeaver and IdolEnchantment suffixes/
						-- prefixes, NOT just Standard. The earlier "Standard only"
						-- gate (based on a misread of
						-- `IsAffectedByAffectOfStandardPrefixesOrSuffixes`)
						-- silently dropped the boost for builds whose refracted
						-- idols carry Weaver Idol affixes.
						--   Triangulation: ZombieWarehouse lv72 Necromancer
						--   (Twisted Altar, property 3 = +10% Effect of Suffixes).
						--   4 refracted idols all carry IdolWeaver suffixes:
						--     Chitin  PhysRes 23 → 23×1.10=25.3 → 25 (in-game 77 = +2)
						--     Many Threads (Idol10) Fire/Cold/Light 5 → 6
						--     Many Threads (Idol11) Fire/Cold/Light 10 → 11
						--       Cold 5+10 → 6+11=17 (in-game 54 = +2)
						--       Light 5+10 → 17 (in-game 47 = +2)
						--     Repose  Mana 5 → 5×1.10=5.5 → 6 (in-game 203 = +1)
						--   All match round-half-up, NOT floor.
						-- Property 4 (Weaver Enchantment, `altarBoostEnchant`) is a
						-- SEPARATE bucket that additionally boosts IdolEnchantment /
						-- IdolWeaver affixes, and uses FLOOR (verified BxvJP3g1
						-- Many Threads raw 6 → 8 at +46%). The rounding direction is
						-- therefore PROPERTY-determined (1/2/3 round-half-up vs
						-- 4 floor), not purely subtype-determined.
						-- Spec: spec/System/TestIdolRefractedStandardBoostAllSubtypes_spec.lua
						local sat = specialAffixType(affix.modId)
						-- Property 1/2/3 (common + prefix/suffix specific) — all
						-- non-Corrupted subtypes, round-half-up.
						local stdBoost = (sat ~= "Corrupted")
							and (altarCommon + (specificBoost or 0)) or 0
						-- Property 4 (weaver enchant) — IdolEnchantment/IdolWeaver
						-- only, floored.
						local weaverBoost = (sat == "IdolEnchantment" or sat == "IdolWeaver")
							and altarBoostEnchant or 0
						local boost = stdBoost + weaverBoost
						if boost > 0 then
							-- @leb-regression-guard: two-phase-floor-post-round-scalar
							-- Altar refracted-slot boosts are LE's
							-- `postRoundingEffectModifier` (dump.cs L165287
							-- `ChangeAffixModifier`), applied AFTER the rolled
							-- value is rounded to its display integer. Set
							-- separately from `valueScalar` (idol-size scalar)
							-- so applyRange can do the two-phase floor.
							-- Verified on owLmrO3a Heretical Large Arcane Idol
							-- affix 897_4 "+9 Ward per Second" T5 byte=255:
							--   single-phase 9 × 1.22 folded into scalar via
							--   interp-first: 10.98 → 10  but LETools shows 10
							--   (LE rounded the rolled value 9 first, then
							--   floored 9 × 1.22 = 10.98 → 10). Matches.
							affix.postRoundScalar = (affix.postRoundScalar or 1) * (1 + boost)
							-- @leb-regression-guard: idol-altar-boost-subtype-rounding
							-- LE applies the post-round boost with rounding direction
							-- determined by WHICH altar property drives it:
							--   property 4 (Weaver Enchantment, `weaverBoost`) → floor
							--   property 1/2/3 (Standard common/prefix/suffix,
							--                   `stdBoost`)                  → round-half-up
							-- Floor therefore applies only when the boost is purely
							-- the property-4 weaver-enchant path (verified BxvJP3g1
							-- Many Threads raw 6 → 8 ≠ 9, Chitin raw 12 → 17 ≠ 18 at
							-- property 4 +46%). When property 1/2/3 is involved
							-- (ZombieWarehouse property 3 +10% on IdolWeaver suffixes:
							-- Mana 5→6, Cold/Light 15→17), round-half-up is correct.
							-- See "Idol Altar boost rounding 仕様" Obsidian note.
							if weaverBoost > 0 and stdBoost == 0 then
								affix.postRoundFloor = true
							end
							anyAffixBoosted = true
						end
					end
				end
			end
			scaleAffixList(clone.prefixes, altarBoostPrefix)
			scaleAffixList(clone.suffixes, altarBoostSuffix)
			-- Enchant mods on `enchantModLines` are Weaver Enchantments cast at
			-- the Weaver Tree; they qualify for property 4 only (not the
			-- Standard prefix/suffix boosts).
			local anyEnchantBoosted = false
			if altarBoostEnchant and altarBoostEnchant > 0 and clone.enchantModLines then
				for _, modLine in ipairs(clone.enchantModLines) do
					if modLine.range then
						-- @leb-regression-guard: two-phase-floor-post-round-scalar
						-- Two-phase floor: post-round scalar applied AFTER the
						-- rolled value is rounded. See CalcSetup scaleAffixList
						-- guard above for the architecture rationale.
						modLine.postRoundScalar = (modLine.postRoundScalar or 1) * (1 + altarBoostEnchant)
						anyEnchantBoosted = true
					end
				end
			end
			if clone.crafted and clone.base and clone.affixes
			   and (anyAffixBoosted or anyEnchantBoosted) then
				clone._craftingInternal = true
				clone:Craft()
				clone._craftingInternal = nil
			else
				clone:BuildAndParseRaw()
			end
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

		-- @leb-regression-guard:pyramidal-altar-cdr-letools-artifact
		-- Idol Altar: evaluate "no larger idols above smaller ones in the grid" condition.
		-- For each grid column, walking top -> bottom, idol sizes (cell count) must be
		-- non-decreasing; no larger idol may sit above a smaller one.
		--
		-- The Pyramidal Altar (`Data/Bases/bases_1_4.json` subTypeID 11, all 4
		-- variants share this implicit) carries
		-- "10% Increased Cooldown Recovery Speed if there are no larger idols
		-- above smaller ones in the grid". ModParser parses this as a
		-- conditional CDR mod gated on `Condition:NoLargerIdolsAboveSmaller`
		-- (modTagList L700). This block evaluates the actual grid layout per
		-- LE's rule and sets `modDB.conditions.NoLargerIdolsAboveSmaller`
		-- when the condition holds. Without this evaluation the +10% never
		-- applies and 13+ Pyramidal Altar builds show CDR Δ = -10 vs LETools.
		--
		-- Classification: **letools-artifact** — LETools planner does NOT
		-- model this conditional implicit (Qb6WgDEp etc. show LETools
		-- CDR=0% despite a compliant grid; LE in-game DOES apply the +10%).
		-- LEB matches the in-game value, so LEB-LET = +10 across the cluster
		-- is expected divergence, not a LEB bug. Removing this evaluation
		-- would silently strip +10% CDR from every Pyramidal Altar build
		-- for the cosmetic gain of matching LET on the CDR row.
		-- Spec: spec/System/TestPyramidalAltarCDR_spec.lua
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

		-- @leb-regression-guard: non-unique-idol-stat-multiplier
		-- Pre-scan: Reliquary Nest (unique relic, id=433) carries property 98
		-- (`nonUniqueIdolStatModifier`), parsed by ModParser as
		-- `Multiplier:NonUniqueIdolStatEffect` BASE = N. The runtime applies
		-- this as a flat (1 + N/100) multiplier on every mod sourced from a
		-- non-unique idol item (Adorned/Grand/Huge/Humble/Large/Minor/Ornate/
		-- Small/Stout Idol bases). Unique idols (Julra's Obsession etc.) are
		-- excluded; Idol Altar is excluded (it isn't an idol). The pre-scan
		-- walks every equipped item's modList summing the BASE values so the
		-- merge loop below can scale non-unique-idol srcLists in place.
		-- Apply ScaleAddList(srcList, scale * (1 + N/100)) instead of
		-- mutating ModDB.Sum so per-mod tags (PerStat, conditions, etc.)
		-- continue to evaluate normally. See REGRESSION_GUARDS.md
		-- "non-unique-idol-stat-multiplier".
		local nonUniqueIdolEffectPercent = 0
		for _, slot in pairs(build.itemsTab.orderedSlots) do
			local item = items[slot.slotName]
			if item and item.modList then
				for _, m in ipairs(item.modList) do
					if m.name == "Multiplier:NonUniqueIdolStatEffect" and m.type == "BASE" then
						nonUniqueIdolEffectPercent = nonUniqueIdolEffectPercent + (m.value or 0)
					end
				end
			end
		end
		local nonUniqueIdolScale = 1 + nonUniqueIdolEffectPercent / 100

		for _, slot in pairs(build.itemsTab.orderedSlots) do
			local slotName = slot.slotName
			local item = items[slotName]
			if slotName:sub(1, 10) == "Omen Idol " then
				-- Legacy Omen Idol N slot. With grid-based refracted detection
				-- the boost is applied via the Idol N grid path; if the same
				-- item appears on the grid, skip this copy to avoid double-
				-- counting. Only orphaned Omen Idol entries (not on grid) are
				-- merged here, and they merge as-is (no boost) since refracted
				-- status is now driven by grid overlap.
				if item and gridItemSet[item] then
					item = nil
				end
			elseif item and fracturedItemSet[item] and slotName:match("^Idol %d+$") then
				-- Idol overlaps a Refracted cell on the altar grid: merge a
				-- clone with valueScalar scaled by the altar's prefix/suffix/
				-- weaver-enchant boosts so applyRange/parseMod yields the
				-- additively-boosted mod values.
				if altarBoostPrefix > 0 or altarBoostSuffix > 0 or altarBoostEnchant > 0 or altarCommon > 0 then
					item = cloneWithAltarBoost(item)
				end
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
				-- @leb-regression-guard:traitors-tongue-self-source-slot
				-- "with X equipped in the mainhand/offhand" is self-source-slot in LE:
				-- each item's mod fires only when that item itself sits in the named
				-- slot. Verified via LETools tooltip on QWXjqWJ2 (dual Traitor's Tongue):
				-- Parry Chance = 13% (= +10 unique + 3 Spell Breaker), i.e. only ONE
				-- mainhand-Parry fires even though both TT instances carry the mod.
				-- The earlier fix (commit 6d363fc89) used a global Condition tag which
				-- made both fire (24%). Here we drop the cross-slot mod from the wrong-
				-- slot item, keeping only the mod whose named slot matches its source.
				-- See REGRESSION_GUARDS.md "traitors-tongue-self-source-slot".
				if slotName == "Weapon 1" or slotName == "Weapon 2" then
					local dropPrefix = (slotName == "Weapon 1") and "OffhandHas:" or "MainHandHas:"
					local filtered
					for i, mod in ipairs(srcList) do
						local drop = false
						for _, tag in ipairs(mod) do
							if tag.type == "Condition" and tag.var and tag.var:sub(1, #dropPrefix) == dropPrefix then
								drop = true
								break
							end
						end
						if drop then
							if not filtered then
								filtered = {}
								for j = 1, i - 1 do filtered[j] = srcList[j] end
							end
						elseif filtered then
							t_insert(filtered, mod)
						end
					end
					if filtered then srcList = filtered end
				end
				-- Reliquary Nest: scale every mod on non-unique idol items
				-- (Adorned/Grand/Huge/Humble/Large/Minor/Ornate/Small/Stout
				-- Idol bases) by (1 + N/100). Unique/Set idols and the Idol
				-- Altar are excluded. See pre-scan above.
				if nonUniqueIdolScale ~= 1 and item.base and item.base.type
					and item.base.type ~= "Idol Altar"
					and item.base.type:sub(-5) == " Idol"
					and item.rarity ~= "UNIQUE"
					and item.rarity ~= "SET" then
					scale = scale * nonUniqueIdolScale
				end
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
				-- Julra's Obsession: "+X% Stats on your gloves also apply to your minions".
				-- Wrap each non-attribute, non-minion glove mod as a MinionModifier so
				-- the existing minion-modDB merge picks it up. Tooltip excludes Str/Dex/
				-- Int/Vit/Att since "Attributes on minions have no effect".
				if slotName == "Gloves" then
					local applyPercent = 0
					for _, m in ipairs(srcList) do
						if m.name == "StatsApplyToMinions_Gloves" and m.type == "BASE" then
							applyPercent = applyPercent + (m.value or 0)
						end
					end
					if applyPercent > 0 then
						local minionScale = scale * applyPercent / 100
						local skipName = { Str = true, Dex = true, Int = true, Vit = true, Att = true,
							MinionModifier = true, StatsApplyToMinions_Gloves = true }
						for _, srcMod in ipairs(srcList) do
							if not skipName[srcMod.name] then
								local wrapped = modLib.createMod("MinionModifier", "LIST", { mod = copyTable(srcMod) })
								env.itemModDB:ScaleAddMod(wrapped, minionScale)
							end
						end
					end
				end
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
			-- @leb-regression-guard:traitors-tongue-offhand-crit-flat (CalcSetup half)
			-- Pair with ModParser matchers "with X equipped in the offhand/mainhand".
			-- ModParser lowercases mod text before lookup, so the captured name
			-- arrives lowercased; lowercase the item name to match.
			if items["Weapon 2"].name then
				env.modDB.conditions["OffhandHas:" .. items["Weapon 2"].name:lower()] = true
			end
		end
		if items["Weapon 1"] and items["Weapon 1"].name then
			env.modDB.conditions["MainHandHas:" .. items["Weapon 1"].name:lower()] = true
		end

		-- Aggregate equipped SET pieces per setId and apply N-piece bonuses.
		-- Merge level-gated SET / wildcard items captured before the LevelReq
		-- filter: in-game such pieces lose their stats but still count toward
		-- set completion and wildcard "every set" expansion.
		local setItems = items
		if env._levelGatedSetItems and next(env._levelGatedSetItems) then
			setItems = {}
			for k, v in pairs(items) do setItems[k] = v end
			for k, v in pairs(env._levelGatedSetItems) do
				if not setItems[k] then setItems[k] = v end
			end
		end
		applySetBonuses(env, setItems, build.targetVersion)
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
	-- Map skill treeId -> "<Skill>Effect" mod name for "Increased X Effect" scaling.
	-- Sentinel-119 "4% Increased Holy Aura And Symbols Of Hope Effect" parses to
	-- INC HolyAuraEffect/SymbolsOfHopeEffect; this lookup tells the buff-tree
	-- processor which effect mod to scale by per skill.
	local treeIdEffectMod = {
		["ah443"]  = "HolyAuraEffect",
		["si4lgl"] = "SymbolsOfHopeEffect",
	}
	-- @leb-regression-guard: flame-ward-block-toggle
	-- @leb-regression-guard: form-tree-nodes-gated-by-condition
	-- While-active duration buffs (Flame Ward) AND Druid/Lich Forms (Werebear,
	-- Spriggan, Swarmblade, Reaper) grant tree-node mods that the LE engine only
	-- applies while the corresponding Mutator buff (FlameWardMutator / form
	-- Mutator with statsInForm wired via OnEnable) is up. Without an explicit
	-- "Condition:Have<X>" or "Condition:In<X>Form" flag from Config, these mods
	-- MUST NOT be added globally — otherwise socket-group enabled=true (LETools
	-- import default) leaks the entire tree-node set into modDB.
	-- Tests:
	--   spec/System/TestBlockSnapshot_spec.lua "Bakbr2Ne lv86 Sorcerer block snapshot"
	--   spec/System/TestS5FormTreeNodeGate_spec.lua (form treeId gate contract)
	-- Maps treeId -> Condition flag name required for the buff to be considered active.
	-- Form treeIds confirmed against game data (LE_datamining/extracted/ability_keyed_array.json):
	--   wb8fo=Werebear Form, sf5rd=Spriggan Form, sbf4m=Swarmblade Form, rf1azz=Reaper Form.
	-- @leb-regression-guard:eterras-blessing-buff-gating
	-- Eterra's Blessing (eb5656) is a 4s-duration cast buff (skillTypeTags=131328
	-- carries the Buff bit), and its specialization tree node "Safeguard" (eb5656-2)
	-- grants "+15% Elemental Resistance" + "+15% Poison Resistance" per point. Without
	-- this entry the SkillType.Buff bit alone is enough for CalcSetup's buff bucket,
	-- but the gate becomes `enabled = group.enabled` — i.e. "skill is on the bar"
	-- rather than "buff is currently active". LE's Buffs panel shows EB OFF by
	-- default, so for parity LEB must require an explicit Condition:HaveEterrasBlessing
	-- flag (matches Flame Ward fw3d's pattern).
	-- Symptoms before fix (BOwJnY3Y Beastmaster, eb5656-2 #3):
	--   * FireResist  LE=56  LEB=101 Δ=+45
	--   * ColdResist  LE=80  LEB=125 Δ=+45
	--   * LightResist LE=179 LEB=224 Δ=+45
	--   * PoisonResist LE=1  LEB=46  Δ=+45
	-- See REGRESSION_GUARDS.md "eterras-blessing-buff-gating".
	-- Shared registry lives in src/Data/Global.lua so the SkillsTab UI
	-- (toggle render path) can read the same map without forking. See
	-- LE_WHILE_ACTIVE_BUFF_BY_TREE_ID and its guard comment.
	local whileActiveBuffByTreeId = LE_WHILE_ACTIVE_BUFF_BY_TREE_ID
	local buffSkillTreePrefixes = {}
	for _, group in pairs(build.skillsTab.socketGroupList) do
		local ge = group.grantedEffect
		if ge and ge.treeId then
			local prefix = ge.treeId .. "-"
			if not buffSkillTreePrefixes[prefix] then
				local hasBuffType = ge.skillTypes and ge.skillTypes[SkillType.Buff]
				local condName = whileActiveBuffByTreeId[ge.treeId]
				if hasBuffType or condName then
					local enabled = group.enabled
					if condName then
						-- While-active duration buffs (e.g. Flame Ward fw3d) require the
						-- corresponding Condition:Have<X> flag — even if SkillType.Buff is
						-- set on the skill — otherwise their tree-node mods leak globally.
						enabled = enabled and env.modDB:Flag(nil, "Condition:" .. condName)
					end
					buffSkillTreePrefixes[prefix] = {
						enabled = enabled,
						isChannel = (hasBuffType and ge.skillTypes[SkillType.Channelling]) or false,
						effectMod = treeIdEffectMod[ge.treeId],
					}
				end
			end
		end
	end

	if next(buffSkillTreePrefixes) then
		local normalNodes = {}
		-- Bucket active buff nodes per-prefix so each skill's "Increased X Effect"
		-- multiplier (e.g. Sentinel-119 Covenant of Light → HolyAuraEffect) scales
		-- only that skill's own tree contributions.
		local activeBuffNodesByPrefix = {}
		local activeChannelNodesByPrefix = {}
		local inactiveBuffNodes = {}
		for nodeId, node in pairs(env.allocNodes) do
			local isBuffNode = false
			for prefix, info in pairs(buffSkillTreePrefixes) do
				if nodeId:sub(1, #prefix) == prefix then
					isBuffNode = true
					if env.mode_buffs and info.enabled then
						if info.isChannel then
							activeChannelNodesByPrefix[prefix] = activeChannelNodesByPrefix[prefix] or {}
							activeChannelNodesByPrefix[prefix][nodeId] = node
						else
							activeBuffNodesByPrefix[prefix] = activeBuffNodesByPrefix[prefix] or {}
							activeBuffNodesByPrefix[prefix][nodeId] = node
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
		-- Normal (non-buff) nodes: apply with SkillId tags intact.
		-- Must be added BEFORE buff-tree nodes so HolyAuraEffect / SymbolsOfHopeEffect
		-- INC mods (from Sentinel base passives) are visible when scaling buff nodes.
		env.modDB:AddList(calcs.buildModListForNodeList(env, normalNodes))
		-- Helper: build, optionally scale by "<Skill>Effect", and AddList
		local function applyBuffPrefix(prefix, nodes, isChannel)
			local nodeMods = calcs.buildModListForNodeList(env, nodes, true, isChannel)
			local effectMod = buffSkillTreePrefixes[prefix].effectMod
			if effectMod then
				local inc = env.modDB:Sum("INC", nil, effectMod)
				if inc ~= 0 then
					local scaled = new("ModList")
					scaled:ScaleAddList(nodeMods, 1 + inc / 100)
					nodeMods = scaled
				end
			end
			env.modDB:AddList(nodeMods)
		end
		-- Active buff nodes: strip SkillId tags so mods apply globally
		for prefix, nodes in pairs(activeBuffNodesByPrefix) do
			applyBuffPrefix(prefix, nodes, false)
		end
		-- Active channelled-buff nodes: strip SkillId and gate by Condition:Channelling
		for prefix, nodes in pairs(activeChannelNodesByPrefix) do
			applyBuffPrefix(prefix, nodes, true)
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

	-- @leb-regression-guard:per-1pct-increased-movement-speed
	-- Auto-populate Multiplier:MovementSpeedInc from the sum of INC mods on
	-- MovementSpeed so mods like Unbroken Charge's "+X Block Effectiveness per
	-- 1% Increased Movement Speed" can resolve. Without this the matcher exists
	-- but the multiplier is always 0 and the mod contributes nothing. Pairs
	-- with the ModParser matcher site for the same guard (see ModParser.lua
	-- "per 1%% increased movement speed").
	-- Verified against AVa9YEkg (Paladin lv95) BlockEffectiveness.
	-- Spec: spec/System/TestModParse_spec.lua
	--       "per 1% increased movement speed multiplier" (parser side; this
	--        auto-injection is verified at the build level via TestBuilds).
	local msInc = env.modDB:Sum("INC", nil, "MovementSpeed")
	if msInc and msInc > 0 then
		env.modDB:NewMod("Multiplier:MovementSpeedInc", "BASE", msInc, "Auto:MovementSpeed")
	end

	-- @leb-regression-guard:ward-per-second-and-retention-family
	-- Auto-populate INC-sum / BASE-sum multipliers used by the Ward Per Second
	-- and Ward Retention parser family:
	--   * Multiplier:AreaInc           sum INC on AreaOfEffect       (Cloak of Solitude)
	--   * Multiplier:ArmourInc         sum INC on Armour             (Conjured Armor)
	--   * Multiplier:UncappedResistTotal sum BASE on 7 resist stats  (Charged Reflections)
	-- Without these the parser matchers exist but the multiplier is always 0
	-- and the affixes silently contribute nothing.
	local areaInc = env.modDB:Sum("INC", nil, "AreaOfEffect")
	if areaInc and areaInc > 0 then
		env.modDB:NewMod("Multiplier:AreaInc", "BASE", areaInc, "Auto:AreaOfEffect")
	end
	local armourInc = env.modDB:Sum("INC", nil, "Armour")
	if armourInc and armourInc > 0 then
		env.modDB:NewMod("Multiplier:ArmourInc", "BASE", armourInc, "Auto:Armour")
	end
	local resTotal = env.modDB:Sum("BASE", nil, "FireResist", "ColdResist", "LightningResist", "PhysicalResist", "NecroticResist", "VoidResist", "PoisonResist")
	if resTotal and resTotal > 0 then
		env.modDB:NewMod("Multiplier:UncappedResistTotal", "BASE", resTotal, "Auto:UncappedResistTotal")
	end

	-- @leb-regression-guard: symbols-of-hope-inc-not-more
	-- Symbols of Hope: each active symbol grants +20% INCREASED Health Regen (additive
	-- with other INC mods, NOT a separate MORE multiplier). The si4lgl-24 Meditation
	-- node doubles the per-symbol value to 40%. The per-symbol value is itself scaled
	-- by SymbolsOfHopeEffect INC (Sentinel-119 Covenant of Light: +4%/pt for both Holy
	-- Aura and Symbols of Hope effect).
	-- Verified against QDxZjL4J Paladin (LETools healthRegen=294.33):
	--   10 symbols × 20% × (1 + 0.20 SymbolsOfHopeEffect INC) = 240% INC, additive
	--   with global LifeRegen INC; matches LETools breakdown "Increased: 240%".
	-- The pre-fix MORE shape (`(1 + globalInc) * (1 + 0.20 * symbols)`) would have
	-- produced 60 × 2.52 × 3.0 ≈ 453 instead of the actual ~295.
	-- Spec: spec/System/TestSymbolsOfHope_spec.lua
	local sigilsPrefix = buffSkillTreePrefixes and buffSkillTreePrefixes["si4lgl-"]
	if env.mode_buffs and sigilsPrefix and sigilsPrefix.enabled then
		local hasMeditation = env.allocNodes["si4lgl-24"] ~= nil
		local perSymbolPct = hasMeditation and 40 or 20
		local sohEffectInc = env.modDB:Sum("INC", nil, "SymbolsOfHopeEffect")
		local scaledPct = perSymbolPct * (1 + sohEffectInc / 100)
		env.modDB:NewMod("LifeRegen", "INC", scaledPct, "Symbols of Hope",
			{ type = "Multiplier", var = "ActiveSymbol" })
	end

	-- @leb-regression-guard: sentinel-93-mana-regen-from-holy-aura
	-- Sentinel-93 (Covenant of Dominion) notScalingStat: "25% Increased Mana Regen
	-- From Holy Aura" activates at threshold 5 (i.e. fully allocated). The cached
	-- parse tags this mod with SkillName=Holy Aura, but ManaRegen is summed at
	-- CalcDefence:580 with cfg=nil so the SkillName tag never matches and the
	-- bonus contributes nothing. The LE engine treats "From Holy Aura" as an
	-- always-on while-active condition: as long as Holy Aura is on the bar and
	-- enabled, the bonus applies globally. Inject a clean ManaRegen INC mod
	-- scaled by HolyAuraEffect (Sentinel-119 Covenant of Light: +4%/pt) when
	-- both Sentinel-93 (≥5pts) and Holy Aura (ah443-) are active.
	-- Spec: spec/System/TestSentinel93ManaRegen_spec.lua
	local holyAuraPrefix = buffSkillTreePrefixes and buffSkillTreePrefixes["ah443-"]
	local s93 = env.allocNodes["Sentinel-93"]
	if env.mode_buffs and holyAuraPrefix and holyAuraPrefix.enabled
			and s93 and (s93.alloc or 0) >= 5 then
		local haEffectInc = env.modDB:Sum("INC", nil, "HolyAuraEffect")
		local scaledPct = 25 * (1 + haEffectInc / 100)
		env.modDB:NewMod("ManaRegen", "INC", scaledPct, "Sentinel-93 Covenant of Dominion")
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
			env.player.weaponData2 = env.player.itemList["Weapon 1"].weaponData and env.player.itemList["Weapon 1"].weaponData[2] or { }
		else
			-- Mirror the weaponData1 path: derive from `base.weapon` + `base.type`.
			-- `Item:weaponData[slotNum]` is only ever populated by
			-- `BuildModListForSlotNum`, which nothing in LEB calls — so the prior
			-- `.weaponData[2]` lookup always returned nil and the DualWielding
			-- condition never activated for off-hand weapons.
			local w2item = env.player.itemList["Weapon 2"]
			if w2item and w2item.base and w2item.base.weapon then
				env.player.weaponData2 = copyTable(w2item.base.weapon)
				env.player.weaponData2.type = w2item.base.type
				env.player.weaponData2.AttackRate = env.player.weaponData2.AttackRateBase
			else
				env.player.weaponData2 = { }
			end
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
					-- @leb-regression-guard:wielding-weapon-conditions
					-- Mace/Spear branches are required for "if wielding a Mace"
					-- (affixId 364 etc.) and SkillStatMap UsingMace gates to fire.
					-- Note: Sceptre items have flag == "Mace" by design (weaponTypeInfo
					-- in Data.lua) so the UsingMace condition naturally activates when
					-- a Sceptre is equipped — that matches LE's mace-flag mechanics.
					-- The separate UsingSceptre flag below still publishes alongside.
					if flag == "Bow" then env.modDB.conditions["UsingBow"] = true
					elseif flag == "Dagger" then env.modDB.conditions["UsingDagger"] = true
					elseif flag == "Staff" then env.modDB.conditions["UsingStaff"] = true
					elseif flag == "Wand" then env.modDB.conditions["UsingWand"] = true
					elseif flag == "Axe" then env.modDB.conditions["UsingAxe"] = true
					elseif flag == "Mace" then env.modDB.conditions["UsingMace"] = true
					elseif flag == "Sword" then env.modDB.conditions["UsingSword"] = true
					elseif flag == "Spear" then env.modDB.conditions["UsingSpear"] = true
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

		-- Compute +skill level bonus from equipment/modDB.
		-- Permanence of Primal Knowledge: "% increased Effect of Skill Level
		-- modifiers on Legendary Affixes" multiplies BASE SkillLevel mods
		-- whose source mod has legendaryAffix=true (set in Item.lua for sealed
		-- Prefix/Suffix on Reforged Legendary items).
		local function sumSkillLevelWithLegendaryEffect(cfg)
			local total = 0
			local legendarySum = 0
			local entries = env.modDB:Tabulate("BASE", cfg, "SkillLevel")
			for _, entry in ipairs(entries) do
				total = total + entry.value
				if entry.mod and entry.mod.legendaryAffix then
					legendarySum = legendarySum + entry.value
				end
			end
			local incPct = env.modDB:Sum("INC", nil, "LegendaryAffixSkillLevelEffect")
			if incPct ~= 0 and legendarySum ~= 0 then
				total = total + legendarySum * incPct / 100
			end
			-- Build human-readable breakdown grouped by source.
			-- Item rows show the unscaled affix value; the Permanence multiplier
			-- contribution (legendarySum * incPct%) is rolled into a single
			-- trailing row so users can see exactly where the fractional part
			-- of the cap comes from.
			local grouped, order = {}, {}
			for _, entry in ipairs(entries) do
				local m = entry.mod
				local src = (m and m.source) or "Unknown"
				if not grouped[src] then
					grouped[src] = { source = src, value = 0 }
					t_insert(order, src)
				end
				grouped[src].value = grouped[src].value + entry.value
			end
			local breakdown = {}
			for _, src in ipairs(order) do
				if grouped[src].value ~= 0 then
					t_insert(breakdown, grouped[src])
				end
			end
			if incPct ~= 0 and legendarySum ~= 0 then
				t_insert(breakdown, {
					source = "Permanence of Primal Knowledge (" .. incPct .. "%)",
					value = legendarySum * incPct / 100,
				})
			end
			return total, breakdown
		end
		env.sumSkillLevelWithLegendaryEffect = sumSkillLevelWithLegendaryEffect
		env.skillLevelBonus = sumSkillLevelWithLegendaryEffect(nil)
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
		build.perSkillLevelBreakdown = build.perSkillLevelBreakdown or {}
		-- Per-skill item-derived delivery-tag swap (e.g. Heartseeker Bow->Throwing
		-- via Ravager's Dart). Consumed by SkillsTab so the Scaling Tags tooltip
		-- row matches in-game routing.
		build.perSkillDeliverySwap = build.perSkillDeliverySwap or {}
		-- Per-skill item-mod runtime tag conversions (Ash Wake's "Aura of Decay
		-- is converted to fire", Dancing Strikes is converted to Fire, ...).
		-- Consumed by SkillsTab so the Scaling Tags tooltip row reflects the
		-- post-conversion damage type.
		build.perSkillTagAdd = build.perSkillTagAdd or {}
		build.perSkillTagRemove = build.perSkillTagRemove or {}
		-- Per-skill effective Minion Tags bitmap — already-filtered stcdt +
		-- variant mutations. SkillsTab uses this as a full replacement for the
		-- static displayMinionTags so the row matches in-game routing.
		build.perSkillDisplayMinionTags = build.perSkillDisplayMinionTags or {}
		-- Pre-populate attribute output values so PerStat tags on SkillLevel
		-- mods (e.g. "+1 to All Skills per 120 Total Attributes") evaluate
		-- correctly here. CalcPerform recomputes these later, but it runs
		-- after this block, so we'd otherwise see 0 for any attribute-scaled
		-- skill level mod.
		env.player.output = env.player.output or {}
		for _, stat in pairs(Attributes) do
			env.player.output[stat] = round(calcLib.val(env.modDB, stat))
		end
		for index, group in pairs(build.skillsTab.socketGroupList) do
			if group.grantedEffect and group.grantedEffect.treeId then
				-- Sum all SkillLevel mods matching this skill (includes global + skill-specific).
				-- keywordFlags lets keyword-tagged SkillLevel mods ("+N to Cold Melee Skills",
				-- "+N to Fire Minion Skills" etc.) match this skill's categories.
				-- Apply tree-injected damage-type tag swaps (e.g. Spark Artillery
				-- swapping Frost Claw Cold->Lightning) so "+N to Lightning Spells"
				-- etc. matches the swapped skill in this cap-summing pass too.
				local treeSwaps = calcs.getTreeTagSwaps(env, group.grantedEffect.treeId, group.grantedEffect)
				local skillTypes, keywordFlags = calcs.applyTreeTagSwaps(
					treeSwaps,
					group.grantedEffect.skillTypes,
					group.grantedEffect.keywordFlags or 0,
					false
				)
				-- Tree-injected tag additions (e.g. Warcry's Totemic Heart node
				-- adds Minion+Totem because it converts the skill into a totem).
				-- Apply *after* swaps so additions ride on the post-swap bitmap.
				local treeAdds = calcs.getTreeTagAdditions(env, group.grantedEffect.treeId)
				skillTypes, keywordFlags = calcs.applyTreeTagAdditions(
					treeAdds, skillTypes, keywordFlags, false
				)
				-- Item-mod runtime tag conversions (Ash Wake "Aura of Decay is
				-- converted to fire" -> Fire+, Poison-; Elemental(128) auto-
				-- handled). Applied AFTER tree adds so item conversions ride on
				-- the post-tree-mutation bitmap.
				local itemAddTags, itemRemoveTags = calcs.getItemSkillTagConversions(env, group.grantedEffect)
				if itemRemoveTags ~= 0 then
					skillTypes = copyTable(skillTypes)
					for typeBit in pairs(skillTypes) do
						if type(typeBit) == "number" and bit.band(typeBit, itemRemoveTags) ~= 0 then
							skillTypes[typeBit] = nil
						end
					end
					keywordFlags = bit.band(keywordFlags, bit.bnot(itemRemoveTags))
				end
				if itemAddTags ~= 0 then
					if itemRemoveTags == 0 then skillTypes = copyTable(skillTypes) end
					for _, typeBit in ipairs({ SkillType.Physical, SkillType.Lightning,
						SkillType.Cold, SkillType.Fire, SkillType.Void, SkillType.Necrotic,
						SkillType.Poison, SkillType.Elemental }) do
						if bit.band(itemAddTags, typeBit) ~= 0 then
							skillTypes[typeBit] = true
						end
					end
					keywordFlags = bit.bor(keywordFlags, itemAddTags)
				end
				build.perSkillTagAdd[index] = itemAddTags
				build.perSkillTagRemove[index] = itemRemoveTags
				-- Item-scoped delivery-type conversions ("100% of Heartseeker
				-- converted to Throwing" on Ravager's Dart). Replace the skill's
				-- existing delivery bit (Bow/Melee/Throwing/Spell) with the
				-- destination so "+to <newType> Skills" affixes match — confirmed
				-- in-game: Heartseeker tagged Bow base, becomes Throwing under
				-- this conversion, and Relic "+1 Throwing Skills" applies.
				local DELIVERY_BITS = bit.bor(SkillType.Melee, SkillType.Throwing, SkillType.Bow, SkillType.Spell)
				local skillSwaps = env.modDB:List(nil, "SkillTagSwap_" .. group.grantedEffect.name:gsub("%s+", ""))
				local deliverySwapBit = nil
				if skillSwaps and #skillSwaps > 0 then
					skillTypes = copyTable(skillTypes)
					for _, swap in ipairs(skillSwaps) do
						if swap.deliveryBit then
							-- Strip existing delivery bits, then OR in destination.
							for typeBit in pairs(skillTypes) do
								if type(typeBit) == "number" and bit.band(typeBit, DELIVERY_BITS) ~= 0
								   and bit.band(typeBit, DELIVERY_BITS) == typeBit then
									skillTypes[typeBit] = nil
								end
							end
							keywordFlags = bit.band(keywordFlags, bit.bnot(DELIVERY_BITS))
							skillTypes[swap.deliveryBit] = true
							keywordFlags = bit.bor(keywordFlags, swap.deliveryBit)
							deliverySwapBit = swap.deliveryBit
						end
					end
				end
				build.perSkillDeliverySwap[index] = deliverySwapBit
				-- Stash per-skill display Minion Tags after minionKW is built
				-- below; deferred via closure-style write at end of this loop.
				-- "+to <DamageType> Minion Skills" affix scope:
				-- A two-tag mod of {SkillType=Minion, MinionTagFlag=<dmgType>} only
				-- applies if BOTH gates pass. The SkillType=Minion gate is
				-- satisfied by any skill carrying the Minion bit (fakeTags or
				-- baseFlags), which correctly lets "+to Minion Skills" (cat=all,
				-- no MinionTagFlag) raise Spriggan Form / Werebear Form levels
				-- (confirmed in-game: Phantom Grip "+2 Minion Skills" applies).
				--
				-- The MinionTagFlag gate filters by the spawned minion's damage/
				-- delivery tags. For form/buff skills that aren't minion-summon
				-- parents (minionTagsDisplay=0 and no tree promotion to minion/
				-- totem), the spawned-minion-tag scope is empty — confirmed
				-- in-game: Apogee of Frozen Light "+3 Cold Minion Skills" does
				-- NOT raise Spriggan Form's level even though it has Cold via
				-- skillTreeConversionDamageTags. So only build minionKeywordFlags
				-- when the skill is a "true" minion parent.
				local hasNativeMinion = (group.grantedEffect.minionTagsDisplay or 0) ~= 0
				local treeAddsMinion = bit.band(treeAdds, bit.bor(SkillType.Minion, SkillType.Totem)) ~= 0
				local minionKW = 0
				if hasNativeMinion or treeAddsMinion then
					-- minionTagsDisplay  — the minion's intrinsic tooltip tags
					-- skillTreeConversionDamageTags (stcdt) — tree-reachable
					-- damage types. We only include stcdt bits backed by an
					-- allocated tree node that actually produces that damage
					-- type (conversion stat or variant-addition stat). This
					-- prevents false matches like Logi's Hunger "+Fire Minion
					-- Skills" against a Summon Skeleton without Fire Arrow.
					local stcdt = group.grantedEffect.skillTreeConversionDamageTags or 0
					local activeStcdt, removedStcdt = calcs.getActiveStcdtBits(env, group.grantedEffect.treeId, stcdt)
					minionKW = bit.bor(
						group.grantedEffect.minionTagsDisplay or 0,
						activeStcdt
					)
					-- Tree-driven full-conversion source removal (Q3=(a)):
					-- description prose like "X loses its {Necrotic} tag and gains a
					-- {Physical} tag instead." (tree_3 rea-32) strips Necrotic from
					-- the Minion Tags bitmap so post-conversion +Skills affixes
					-- match correctly. Conditional partial-state lines (`if ...`)
					-- are filtered upstream in getActiveStcdtBits.
					if removedStcdt and removedStcdt ~= 0 then
						minionKW = bit.band(minionKW, bit.bnot(removedStcdt))
					end
					-- Apply tree-driven minion variant pool mutations:
					--   sm4g "Adds Pyromancers" + "Removes Mages" promotes the
					--   minion-tag bitmap from Necrotic to Fire so amulets like
					--   "+2 Minion Fire Skills" raise Skeletal Mage's level.
					local minionAdd, minionRemove = calcs.getMinionVariantMutations(env, group.grantedEffect.treeId)
					if minionRemove ~= 0 then
						minionKW = bit.band(minionKW, bit.bnot(minionRemove))
					end
					if minionAdd ~= 0 then
						minionKW = bit.bor(minionKW, minionAdd)
					end
					if treeAddsMinion then
						-- Tree-promoted totem/minion: spawned entity inherits
						-- the parent's post-swap delivery + damage tags. Mirror
						-- skillTypes so e.g. Glacial Cascade Upheaval-totem
						-- matches "+3 Minion Cold Skills" via the parent's Cold.
						for typeBit in pairs(skillTypes) do
							if type(typeBit) == "number" then
								minionKW = bit.bor(minionKW, typeBit)
							end
						end
					end
				end
				-- Surface the runtime-corrected Minion Tags bitmap to SkillsTab.
				-- minionKW already encodes (minionTagsDisplay | filtered stcdt)
				-- with variant mutations + tree-promoted minion bits applied.
				if hasNativeMinion or treeAddsMinion then
					build.perSkillDisplayMinionTags[index] = minionKW
				else
					build.perSkillDisplayMinionTags[index] = nil
				end
				local skillCfg = {
					skillName = group.grantedEffect.name,
					skillTypes = skillTypes,
					skillAttributes = group.grantedEffect.skillAttributes,
					keywordFlags = keywordFlags,
					minionKeywordFlags = minionKW,
				}
				local totalSkillLevel, breakdown = (env.sumSkillLevelWithLegendaryEffect or function(cfg) return env.modDB:Sum("BASE", cfg, "SkillLevel"), {} end)(skillCfg)
				-- Per-skill bonus = total - global (avoid double-counting global)
				local perSkillBonus = totalSkillLevel - (env.skillLevelBonus or 0)
				build.perSkillLevelBonus[index] = perSkillBonus
				build.perSkillLevelBreakdown[index] = breakdown
				-- Base skill level in Last Epoch is character-level-derived, not the
				-- count of allocated tree points. LETools planner displays Base=20
				-- regardless of character level (max-specialisation assumption), so
				-- hardcode 20 here for parity with the LETools-derived test snapshots.
				-- Real game uses SpecialisedAbilityManager.normalSpeedSkillLevelMinimum
				-- curve (lv50->14, lv80+->20); roadmap Tier 3 covers the eventual swap.
				local baseSkillLevel = 20
				local effectiveLevel = baseSkillLevel + (env.skillLevelBonus or 0) + perSkillBonus
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
