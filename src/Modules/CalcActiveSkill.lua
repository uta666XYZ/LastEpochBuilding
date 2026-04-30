-- Last Epoch Building
--
-- Module: Calc Active Skill
-- Active skill setup.
--
local calcs = ...

local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_floor = math.floor
local m_min = math.min
local m_max = math.max
local bor = bit.bor
local band = bit.band
local bnot = bit.bnot

-- Merge level modifier with given mod list
local mergeLevelCache = { }
local function mergeLevelMod(modList, mod, value)
	if not value then
		modList:AddMod(mod)
		return
	end
	if not mergeLevelCache[mod] then
		mergeLevelCache[mod] = { }
	end
	if mergeLevelCache[mod][value] then
		modList:AddMod(mergeLevelCache[mod][value])
	elseif value then
		local newMod = copyTable(mod, true)
		if type(newMod.value) == "table" then
			newMod.value = copyTable(newMod.value, true)
			if newMod.value.mod then
				newMod.value.mod = copyTable(newMod.value.mod, true)
				newMod.value.mod.value = value
			else
				newMod.value.value = value
			end
		else
			newMod.value = value
		end
		mergeLevelCache[mod][value] = newMod
		modList:AddMod(newMod)
	else
		modList:AddMod(mod)
	end
end

-- Merge skill modifiers with given mod list
function calcs.mergeSkillInstanceMods(env, modList, skillEffect, extraStats)
	local grantedEffect = skillEffect.grantedEffect
	local stats = grantedEffect.stats
	if extraStats and extraStats[1] then
		for _, stat in pairs(extraStats) do
			stats[stat.key] = (stats[stat.key] or 0) + stat.value
		end
	end
	for stat, statValue in pairs(stats) do
		local map = grantedEffect.statMap[stat]
		if map then
			-- Some mods need different scalars for different stats, but the same value.  Putting them in a group allows this
			for _, modOrGroup in ipairs(map) do
				-- Found a mod, since all mods have names
				if modOrGroup.name then
					mergeLevelMod(modList, modOrGroup, map.value or statValue * (map.mult or 1) / (map.div or 1) + (map.base or 0))
				else
					for _, mod in ipairs(modOrGroup) do
						mergeLevelMod(modList, mod, modOrGroup.value or statValue * (modOrGroup.mult or 1) / (modOrGroup.div or 1) + (modOrGroup.base or 0))
					end
				end
			end
		end
	end
	modList:AddList(grantedEffect.baseMods)
end

-- Create an active skill using the given active gem and list of support gems
-- It will determine the base flag set, and check which of the support gems can support this skill
function calcs.createActiveSkill(activeEffect, supportList, actor, socketGroup, summonSkill)
	local activeSkill = {
		activeEffect = activeEffect,
		supportList = supportList,
		actor = actor,
		summonSkill = summonSkill,
		socketGroup = socketGroup,
		skillData = { },
		buffList = { },
	}

	local activeGrantedEffect = activeEffect.grantedEffect
	
	-- Initialise skill types
	activeSkill.skillTypes = copyTable(activeGrantedEffect.skillTypes)
	if activeGrantedEffect.minionSkillTypes then
		activeSkill.minionSkillTypes = copyTable(activeGrantedEffect.minionSkillTypes)
	end

	-- Initialise skill flag set ('attack', 'projectile', etc)
	local skillFlags = copyTable(activeGrantedEffect.baseFlags)
	activeSkill.skillFlags = skillFlags
	skillFlags.hit = skillFlags.hit or activeSkill.skillTypes[SkillType.Attack] or activeSkill.skillTypes[SkillType.Damage] or activeSkill.skillTypes[SkillType.Projectile]

	-- Process support skills
	activeSkill.effectList = { activeEffect }
	local rejectedSupportsIndices = {}

	for index, supportEffect in ipairs(supportList) do
		-- Pass 1: Add skill types from compatible supports
		if calcLib.canGrantedEffectSupportActiveSkill(supportEffect.grantedEffect, activeSkill) then
			for _, skillType in pairs(supportEffect.grantedEffect.addSkillTypes) do
				activeSkill.skillTypes[skillType] = true
			end
		else
			t_insert(rejectedSupportsIndices, index)
		end
	end

	-- loop over rejected supports until none are added.
	-- Makes sure that all skillType flags that should be added are added regardless of support gem order in group
	local notAddedNewSupport = true
	repeat
		notAddedNewSupport = true
		for index, supportEffectIndex in ipairs(rejectedSupportsIndices) do
			local supportEffect = supportList[supportEffectIndex]
			if calcLib.canGrantedEffectSupportActiveSkill(supportEffect.grantedEffect, activeSkill) then
				notAddedNewSupport = false
				rejectedSupportsIndices[index] = nil
				for _, skillType in pairs(supportEffect.grantedEffect.addSkillTypes) do
					activeSkill.skillTypes[skillType] = true
				end
			end
		end
	until (notAddedNewSupport)
	
	for _, supportEffect in ipairs(supportList) do
		-- Pass 2: Add all compatible supports
		if calcLib.canGrantedEffectSupportActiveSkill(supportEffect.grantedEffect, activeSkill) then
			t_insert(activeSkill.effectList, supportEffect)
			if supportEffect.isSupporting and activeEffect.srcInstance then
				supportEffect.isSupporting[activeEffect.srcInstance] = true
			end
			if supportEffect.grantedEffect.addFlags and not summonSkill then
				-- Support skill adds flags to supported skills (eg. Remote Mine adds 'mine')
				for k in pairs(supportEffect.grantedEffect.addFlags) do
					skillFlags[k] = true
				end
			end
		end
	end

	return activeSkill
end

-- Copy an Active Skill
function calcs.copyActiveSkill(env, mode, skill)
	local activeEffect = {
		grantedEffect = skill.activeEffect.grantedEffect,
		level = skill.activeEffect.srcInstance.level,
		quality = skill.activeEffect.srcInstance.quality,
		qualityId = skill.activeEffect.srcInstance.qualityId,
		srcInstance = skill.activeEffect.srcInstance,
		gemData = skill.activeEffect.srcInstance.gemData,
	}
	local newSkill = calcs.createActiveSkill(activeEffect, skill.supportList, skill.actor, skill.socketGroup, skill.summonSkill)
	local newEnv, _, _, _ = calcs.initEnv(env.build, mode, env.override)
	calcs.buildActiveSkillModList(newEnv, newSkill)
	newSkill.skillModList = new("ModList", newSkill.baseSkillModList)
	if newSkill.minion then
		newSkill.minion.modDB = new("ModDB")
		newSkill.minion.modDB.actor = newSkill.minion
		calcs.createMinionSkills(env, newSkill)
		newSkill.skillPartName = newSkill.minion.mainSkill.activeEffect.grantedEffect.name
	end
	return newSkill, newEnv
end

-- Get weapon flags and info for given weapon
local function getWeaponFlags(env, weaponData, weaponTypes)
	local info = env.data.weaponTypeInfo[weaponData.type]
	if not info then
		return
	end
	if weaponTypes then
		for _, types in ipairs(weaponTypes) do
			if not types[weaponData.type] then
				return nil, info
			end
		end
	end
	local flags = ModFlag[info.flag] or 0
	if weaponData.type ~= "None" then
		flags = bor(flags, ModFlag.Weapon)
		if info.oneHand then
			flags = bor(flags, ModFlag.Weapon1H)
		else
			flags = bor(flags, ModFlag.Weapon2H)
		end
		if info.melee then
			flags = bor(flags, ModFlag.WeaponMelee)
		else
			flags = bor(flags, ModFlag.WeaponRanged)
		end
	end
	return flags, info
end

-- Build list of modifiers for given active skill
-- Compute tree-injected damage-type tag swaps (LE's `fakeTags` mechanism)
-- for a given treeId. Returns a {[srcBit]=dstBit} table or nil. Examples:
--   Spark Artillery: " Cold -> Lightning Damage" -> {Cold=Lightning}
--   Electrify: "Fire Damage -> Lightning Damage"
--   Crackling Barrier: "Cold -> Lightning Conversion"
-- Confirmed via descriptions like "Swaps Frost Claw's {Cold} tag for a {Lightning} tag.".
local damageTypeBitsByName = {
	Physical = SkillType.Physical, Lightning = SkillType.Lightning,
	Cold = SkillType.Cold, Fire = SkillType.Fire, Void = SkillType.Void,
	Necrotic = SkillType.Necrotic, Poison = SkillType.Poison,
}
function calcs.getTreeTagSwaps(env, treeId, grantedEffect)
	if not (treeId and env and env.allocNodes) then return nil end
	local prefix = treeId .. "-"
	local swaps
	-- For source-less "<X> Conversion" stats (e.g. Earth Smasher's
	-- "Physical Conversion" on Gathering Storm), infer the source bit from
	-- the skill's intrinsic damage tags. Earth Smasher's tooltip explicitly
	-- says "Swaps Gathering Storm's Lightning tag for a Physical tag" — i.e.
	-- the skill's existing damage-type bit becomes the destination.
	local DAMAGE_TYPE_BITS = bit.bor(SkillType.Physical, SkillType.Lightning,
		SkillType.Cold, SkillType.Fire, SkillType.Void, SkillType.Necrotic,
		SkillType.Poison)
	local intrinsicDmgBits = {}
	if grantedEffect then
		local tags = bit.bor(grantedEffect.skillTypeTags or 0, grantedEffect.fakeTags or 0)
		local dmgMask = bit.band(tags, DAMAGE_TYPE_BITS)
		for _, b in pairs(damageTypeBitsByName) do
			if bit.band(dmgMask, b) == b then
				t_insert(intrinsicDmgBits, b)
			end
		end
	end
	for nodeId, node in pairs(env.allocNodes) do
		if nodeId:sub(1, #prefix) == prefix and node.stats then
			for _, stat in ipairs(node.stats) do
				local src, dst = stat:match("^%s*(%w+)%s*%->%s*(%w+)%s+Damage%s*$")
				if not src then
					src, dst = stat:match("^%s*(%w+)%s+Damage%s*%->%s*(%w+)%s+Damage%s*$")
				end
				if not src then
					src, dst = stat:match("^%s*(%w+)%s*%->%s*(%w+)%s+Conversion%s*$")
				end
				if src and dst and damageTypeBitsByName[src] and damageTypeBitsByName[dst]
				   and damageTypeBitsByName[src] ~= damageTypeBitsByName[dst] then
					swaps = swaps or {}
					swaps[damageTypeBitsByName[src]] = damageTypeBitsByName[dst]
				else
					-- Source-less "<X> Conversion" — infer source from skill's
					-- intrinsic damage type. Matches LE's per-skill tooltip
					-- behaviour ("Swaps <Skill>'s <SrcType> tag for a <DstType>
					-- tag.") for nodes like Earth Smasher.
					local soloDst = stat:match("^%s*(%w+)%s+Conversion%s*$")
					if soloDst and damageTypeBitsByName[soloDst] then
						local dstBit = damageTypeBitsByName[soloDst]
						for _, srcBit in ipairs(intrinsicDmgBits) do
							if srcBit ~= dstBit then
								swaps = swaps or {}
								swaps[srcBit] = dstBit
							end
						end
					end
				end
			end
		end
	end
	return swaps
end

-- Compute tree-injected tag *additions* for a given treeId. Returns a bitmap
-- of SkillType bits to OR into the skill's effective tags, or 0. This is for
-- specialization nodes that convert/extend a skill into something with extra
-- intrinsic tags — e.g. Warcry's "Totemic Heart" node ("Create Warcry Totem")
-- turns the skill into Summon Warcry Totem, which is a Minion+Totem ability.
-- Without this, affixes like "+1 to Minion Skills" from Beastmaster Ancient
-- Might wouldn't apply to a totem-converted Warcry, and the Scaling Tags row
-- would miss the Minion/Totem markers the in-game tooltip shows.
--
-- Pattern detected: stat lines matching "Creates? <name> Totem" — used by
-- Warcry/Totemic Heart, Upheaval/Upheaval Totems, etc. The encoding has no
-- explicit ability reference; LEB recognises the phrase and adds Minion+Totem
-- bits since every "Create X Totem" node turns the skill into a totem-minion.
function calcs.getTreeTagAdditions(env, treeId)
	if not (treeId and env and env.allocNodes) then return 0 end
	local prefix = treeId .. "-"
	local adds = 0
	for nodeId, node in pairs(env.allocNodes) do
		if nodeId:sub(1, #prefix) == prefix then
			if node.stats then
				for _, stat in ipairs(node.stats) do
					-- "Create Warcry Totem" / "Creates Upheaval Totem"
					if stat:lower():match("^%s*creates?%s+.+%s+totem%s*$") then
						adds = bor(adds, SkillType.Minion, SkillType.Totem)
					end
				end
			end
			-- Split-effect damage-type additions parsed from node descriptions.
			-- Per LE_datamining findings: per-node mutator state (e.g. Black Hole's
			-- BinaryStar bool) isn't serialized — only `<Skill>Tree.updateMutator()`
			-- C# bytecode knows the exact mapping. As a fallback we pattern-match
			-- description text for split-effect phrasing like Binary System
			-- ("One deals fire damage and the other deals cold damage"), which
			-- introduces both damage types as base. Cap-summing needs these
			-- bits so e.g. "+to Fire Spell Skills" matches a Black Hole that
			-- has Binary System allocated.
			if node.description then
				for _, line in ipairs(node.description) do
					local lo = line:lower()
					local oneType, otherType = lo:match("one deals (%a+) damage and the other deals (%a+) damage")
					if oneType and otherType then
						local DT_BITS = {
							physical = SkillType.Physical, lightning = SkillType.Lightning,
							cold = SkillType.Cold, fire = SkillType.Fire, void = SkillType.Void,
							necrotic = SkillType.Necrotic, poison = SkillType.Poison,
						}
						if DT_BITS[oneType] then adds = bor(adds, DT_BITS[oneType]) end
						if DT_BITS[otherType] then adds = bor(adds, DT_BITS[otherType]) end
					end
				end
			end
		end
	end
	return adds
end

-- Apply tree tag swaps to a skillTypes set + keywordFlags integer; returns
-- (newSkillTypes, newKeywordFlags). Pass mutable=true to mutate skillTypes
-- in place (used at ActiveSkill build time).
function calcs.applyTreeTagSwaps(swaps, skillTypes, keywordFlags, mutable)
	if not swaps then return skillTypes, keywordFlags end
	local out = mutable and skillTypes or copyTable(skillTypes)
	local kw = keywordFlags or 0
	for srcBit, dstBit in pairs(swaps) do
		if out[srcBit] then
			out[srcBit] = nil
			out[dstBit] = true
			kw = bor(band(kw, bnot(srcBit)), dstBit)
		end
	end
	return out, kw
end

-- Variant-name -> AT bit mapping for tree-driven minion-pool mutations.
-- Stat lines like " Adds Pyromancers" / " Removes Mages" appear on summon
-- skill trees (Skeletal Mage, Summon Skeleton, etc.) and modify which minion
-- variants get summoned. Each variant has an associated damage/delivery type.
-- LE confirms via tooltips like "Adds Pyromancers ... Pyromancers deal fire
-- damage" — so the variant's bits should be added/removed from the minion-tag
-- bitmap used for "+X <DmgType> Minion Skills" affix matching.
local minionVariantBits = {
	-- Skeletal Mage (sm4g) variants
	Mages              = SkillType.Necrotic,
	Pyromancers        = SkillType.Fire,
	Cryomancers        = SkillType.Cold,
	["Death Knights"]  = SkillType.Necrotic,
	-- Summon Skeleton (ss37kl) variants
	Warriors           = bor(SkillType.Melee, SkillType.Physical),
	Archers            = bor(SkillType.Bow, SkillType.Physical),
	Rogues             = bor(SkillType.Melee, SkillType.Physical),
	Vanguards          = bor(SkillType.Melee, SkillType.Physical),
}

-- Returns (addBits, removeBits) for tree-driven minion-pool variant mutations
-- on the given treeId. Walks allocated nodes for stats matching:
--   " Adds <Variant>"     -> OR variant's bits into add mask
--   " Removes <Variant>"  -> OR variant's bits into remove mask
-- Caller applies as: minionKW = (minionKW & ~remove) | add
function calcs.getMinionVariantMutations(env, treeId)
	if not (treeId and env and env.allocNodes) then return 0, 0 end
	local prefix = treeId .. "-"
	local addBits, removeBits = 0, 0
	for nodeId, node in pairs(env.allocNodes) do
		if nodeId:sub(1, #prefix) == prefix and node.stats then
			for _, stat in ipairs(node.stats) do
				local addV = stat:match("^%s*Adds%s+(.+)%s*$")
				if addV and minionVariantBits[addV] then
					addBits = bor(addBits, minionVariantBits[addV])
				end
				local remV = stat:match("^%s*Removes%s+(.+)%s*$")
				if remV and minionVariantBits[remV] then
					removeBits = bor(removeBits, minionVariantBits[remV])
				end
			end
		end
	end
	return addBits, removeBits
end

-- Returns the subset of `stcdt` (skillTreeConversionDamageTags) that should
-- contribute to minionKW. A bit is kept only if the build has at least one
-- allocated tree node that explicitly produces that damage type — either via
-- damage-conversion stats (" X -> Y", " Y Conversion") or variant additions
-- (" Adds <Pyromancers/Cryomancers/...>").
--
-- Rationale: stcdt enumerates damage types REACHABLE via the tree. For skills
-- like Summon Skeleton with stcdt=Phys+Cold+Fire (Cold via Cryomancers,
-- Fire via Fire Arrow), unioning stcdt unconditionally falsely matches gear
-- like Logi's Hunger ("+X Fire Minion Skills") even when no Fire-producing
-- node is allocated. LETools / in-game match only the actually-active types.
function calcs.getActiveStcdtBits(env, treeId, stcdt)
	if not stcdt or stcdt == 0 then return 0 end
	if not (treeId and env and env.allocNodes) then return 0 end
	local prefix = treeId .. "-"
	local active = 0
	for nodeId, node in pairs(env.allocNodes) do
		if nodeId:sub(1, #prefix) == prefix and node.stats then
			for _, stat in ipairs(node.stats) do
				-- damage conversion: produces dst type
				local _, dst = stat:match("^%s*(%w+)%s*%->%s*(%w+)%s+Damage%s*$")
				if not dst then
					_, dst = stat:match("^%s*(%w+)%s+Damage%s*%->%s*(%w+)%s+Damage%s*$")
				end
				if not dst then
					_, dst = stat:match("^%s*(%w+)%s*%->%s*(%w+)%s+Conversion%s*$")
				end
				if not dst then
					dst = stat:match("^%s*(%w+)%s+Conversion%s*$")
				end
				if not dst then
					-- " <Type> Base Damage -> <DmgType>" (e.g. bg36nl-7 Pyre Golem: " Melee Base Damage -> Fire")
					_, dst = stat:match("^%s*(%w+)%s+Base%s+Damage%s*%->%s*(%w+)%s*$")
				end
				if dst and damageTypeBitsByName[dst] then
					active = bor(active, damageTypeBitsByName[dst])
				end
				-- variant addition: produces variant's damage bits
				local addV = stat:match("^%s*Adds%s+(.+)%s*$")
				if addV and minionVariantBits[addV] then
					active = bor(active, minionVariantBits[addV])
				end
			end
		end
		-- Description-driven explicit tag promotion: "<Minion> gain the {<type>}
		-- tag" / "gain the <type> tag" (e.g. fs3e3-21 "Forged by Fire" promotes
		-- Forged Weapons to Fire). Backs the Minion Tags row's Fire entry on
		-- Forge Strike with Forged by Fire allocated, matching LETools.
		-- Defensive: node.description may be a string or table per
		-- PassiveTree:ProcessStats's handling pattern.
		if nodeId:sub(1, #prefix) == prefix and node.description then
			local descList = type(node.description) == "table" and node.description or { node.description }
			-- LEB's tooltip preprocessing rewrites JSON `{fire}` into runtime
			-- form like `{[0]=fire}` (Lua table-literal-ish), so the captured
			-- token between braces may include `[0]=` etc. Scan known damage
			-- type names directly within the "gain the ... tag" phrase rather
			-- than trying to parse the brace syntax.
			for _, line in ipairs(descList) do
				local lo = line:lower()
				-- Capture the inner phrase between "gain the" and "tag"
				-- (single word, allowing `\n`/`\r` since `.` excludes them).
				for inner in lo:gmatch("gain the[%s%S]-tag") do
					for typeName, bit in pairs(damageTypeBitsByName) do
						if inner:find(typeName:lower(), 1, true) then
							active = bor(active, bit)
						end
					end
				end
			end
		end
	end
	return band(stcdt, active)
end

-- Item-mod driven runtime tag conversions (e.g. Ash Wake's
-- "Aura of Decay is converted to fire, inflicting ignite instead of poison",
-- Dancing Strikes is converted to Fire). Returns (addBits, removeBits) to be
-- applied to the skill's effective tag bitmap so:
--   * "+to <NewType> Skills" / "+to Elemental Skills" affixes match.
--   * Scaling Tags tooltip row shows the post-conversion damage type.
-- removeBits = skill's intrinsic damage-type bits (Phys/Light/Cold/Fire/Void/
-- Necrotic/Poison) that the conversion supplants. Don't remove what we add.
-- addBits auto-includes Elemental(128) when adding Fire/Cold/Lightning;
-- removeBits auto-includes Elemental when removing the only ele source.
function calcs.getItemSkillTagConversions(env, grantedEffect)
	if not (env and env.player and env.player.itemList and grantedEffect and grantedEffect.name) then
		return 0, 0
	end
	local DAMAGE_TYPE_BITS = bor(SkillType.Physical, SkillType.Lightning,
		SkillType.Cold, SkillType.Fire, SkillType.Void, SkillType.Necrotic,
		SkillType.Poison)
	-- Build case-insensitive prefix match: skill names in skills.json use Title
	-- Case ("Aura Of Decay") but in-game mod text uses "Aura of Decay" (lower
	-- "of"). Compare lowercased.
	local nameLower = grantedEffect.name:lower()
	local addBits = 0
	local found = false
	local function scan(modLines)
		if not modLines then return end
		for _, line in ipairs(modLines) do
			local text = (line.line or ""):lower()
			local dst = text:match("^" .. nameLower:gsub("(%W)", "%%%1") .. " is converted to (%w+)")
			if dst then
				local dstCap = dst:sub(1, 1):upper() .. dst:sub(2):lower()
				if damageTypeBitsByName[dstCap] then
					addBits = bor(addBits, damageTypeBitsByName[dstCap])
					found = true
				end
			end
		end
	end
	for _, item in pairs(env.player.itemList) do
		if item then
			scan(item.explicitModLines)
			scan(item.implicitModLines)
			scan(item.enchantModLines)
		end
	end
	if not found then return 0, 0 end
	local intrinsic = bor(grantedEffect.skillTypeTags or 0, grantedEffect.fakeTags or 0)
	local removeBits = band(intrinsic, DAMAGE_TYPE_BITS)
	removeBits = band(removeBits, bnot(addBits))
	local ELE_BITS = bor(SkillType.Fire, SkillType.Cold, SkillType.Lightning)
	if band(addBits, ELE_BITS) ~= 0 then
		addBits = bor(addBits, SkillType.Elemental)
	end
	if band(removeBits, ELE_BITS) ~= 0 and band(addBits, SkillType.Elemental) == 0
	   and band(intrinsic, SkillType.Elemental) ~= 0 then
		removeBits = bor(removeBits, SkillType.Elemental)
	end
	return addBits, removeBits
end

-- OR an additions bitmap into a skillTypes set + keywordFlags integer.
local TAG_ADDITION_BITS = {
	SkillType.Minion, SkillType.Totem, SkillType.Spell, SkillType.Buff,
	SkillType.Melee, SkillType.Bow, SkillType.Throwing, SkillType.DoT,
}
function calcs.applyTreeTagAdditions(adds, skillTypes, keywordFlags, mutable)
	if not adds or adds == 0 then return skillTypes, keywordFlags end
	local out = mutable and skillTypes or copyTable(skillTypes)
	local kw = bor(keywordFlags or 0, adds)
	for _, typeBit in ipairs(TAG_ADDITION_BITS) do
		if band(adds, typeBit) ~= 0 then out[typeBit] = true end
	end
	return out, kw
end

function calcs.buildActiveSkillModList(env, activeSkill)
	local skillTypes = activeSkill.skillTypes
	local skillFlags = activeSkill.skillFlags
	local activeEffect = activeSkill.activeEffect
	local activeGrantedEffect = activeEffect.grantedEffect
	local effectiveRange = 0

	-- Apply tree-injected damage-type tag swaps so affixes like
	-- "+N to Lightning Spells" match a Cold->Lightning-swapped Frost Claw.
	local treeSwaps = calcs.getTreeTagSwaps(env, activeGrantedEffect.treeId, activeGrantedEffect)
	if treeSwaps then
		local _, newKw = calcs.applyTreeTagSwaps(treeSwaps, skillTypes, activeSkill.skillCfg and activeSkill.skillCfg.keywordFlags or 0, true)
		for _, cfg in ipairs({ activeSkill.skillCfg, activeSkill.weapon1Cfg, activeSkill.weapon2Cfg }) do
			if cfg and cfg.keywordFlags then
				cfg.keywordFlags = newKw
			end
		end
	end
	-- Tree-injected tag *additions* (e.g. Totemic Heart adds Minion+Totem to
	-- Warcry). Mutate skillTypes in place and propagate to skillCfg/weaponCfg
	-- keywordFlags so affix matching at this active skill's runtime sees them.
	local treeAdds = calcs.getTreeTagAdditions(env, activeGrantedEffect.treeId)
	if treeAdds ~= 0 then
		local _, newKw2 = calcs.applyTreeTagAdditions(treeAdds, skillTypes, activeSkill.skillCfg and activeSkill.skillCfg.keywordFlags or 0, true)
		for _, cfg in ipairs({ activeSkill.skillCfg, activeSkill.weapon1Cfg, activeSkill.weapon2Cfg }) do
			if cfg and cfg.keywordFlags then
				cfg.keywordFlags = newKw2
			end
		end
	end

	-- Set mode flags
	if env.mode_buffs then
		skillFlags.buffs = true
	end
	if env.mode_combat then
		skillFlags.combat = true
	end
	if env.mode_effective then
		skillFlags.effective = true
	end

	-- Handle multipart skills
	local activeGemParts = activeGrantedEffect.parts
	if activeGemParts and #activeGemParts > 1 then
		if env.mode == "CALCS" and activeSkill == env.player.mainSkill then
			activeEffect.srcInstance.skillPartCalcs = m_min(#activeGemParts, activeEffect.srcInstance.skillPartCalcs or 1)
			activeSkill.skillPart = activeEffect.srcInstance.skillPartCalcs
		else
			activeEffect.srcInstance.skillPart = m_min(#activeGemParts, activeEffect.srcInstance.skillPart or 1)
			activeSkill.skillPart = activeEffect.srcInstance.skillPart
		end
		local part = activeGemParts[activeSkill.skillPart]
		for k, v in pairs(part) do
			if v == true then
				skillFlags[k] = true
			elseif v == false then
				skillFlags[k] = nil
			end
		end
		activeSkill.skillPartName = part.name
		skillFlags.multiPart = #activeGemParts > 1
	elseif activeEffect.srcInstance and not (activeEffect.gemData and activeEffect.gemData.secondaryGrantedEffect) then
		activeEffect.srcInstance.skillPart = nil
		activeEffect.srcInstance.skillPartCalcs = nil
	end

	if (skillTypes[SkillType.RequiresShield] or skillFlags.shieldAttack) and not activeSkill.summonSkill and (not activeSkill.actor.itemList["Weapon 2"] or activeSkill.actor.itemList["Weapon 2"].type ~= "Shield") then
		-- Skill requires a shield to be equipped
		skillFlags.disable = true
		activeSkill.disableReason = "This skill requires a Shield"
	end

	if skillFlags.shieldAttack then
		-- Special handling for Spectral Shield Throw
		skillFlags.weapon2Attack = true
		activeSkill.weapon2Flags = 0
	else
		-- Set weapon flags
		local weaponTypes = { activeGrantedEffect.weaponTypes }
		for _, skillEffect in pairs(activeSkill.effectList) do
			if skillEffect.grantedEffect.support and skillEffect.grantedEffect.weaponTypes then
				t_insert(weaponTypes, skillEffect.grantedEffect.weaponTypes)
			end
		end
		local weapon1Flags, weapon1Info = getWeaponFlags(env, activeSkill.actor.weaponData1, weaponTypes)
		if not weapon1Flags and activeSkill.summonSkill then
			-- Minion skills seem to ignore weapon types
			weapon1Flags, weapon1Info = ModFlag[env.data.weaponTypeInfo["None"].flag], env.data.weaponTypeInfo["None"]
		end
		if weapon1Flags then
			if skillFlags.attack then
				activeSkill.weapon1Flags = weapon1Flags
				skillFlags.weapon1Attack = true
				if weapon1Info.melee and skillFlags.melee then
					skillFlags.projectile = nil
				elseif not weapon1Info.melee and skillFlags.projectile then
					skillFlags.melee = nil
				end
			end
		elseif (skillTypes[SkillType.DualWieldOnly] or skillTypes[SkillType.MainHandOnly] or skillFlags.forceMainHand or weapon1Info) and not activeSkill.summonSkill then
			-- Skill requires a compatible main hand weapon
			skillFlags.disable = true
			activeSkill.disableReason = "Main Hand weapon is not usable with this skill"
		end
		if not skillTypes[SkillType.MainHandOnly] and not skillFlags.forceMainHand then
			local weapon2Flags, weapon2Info = getWeaponFlags(env, activeSkill.actor.weaponData2, weaponTypes)
			if weapon2Flags then
				if skillFlags.attack then
					activeSkill.weapon2Flags = weapon2Flags
					skillFlags.weapon2Attack = true
				end
			elseif (skillTypes[SkillType.DualWieldOnly] or weapon2Info) and not activeSkill.summonSkill then
				-- Skill requires a compatible off hand weapon
				skillFlags.disable = true
				activeSkill.disableReason = activeSkill.disableReason or "Off Hand weapon is not usable with this skill"
			elseif skillFlags.disable then
				-- Neither weapon is compatible
				activeSkill.disableReason = "No usable weapon equipped"
			end
		end
		if skillFlags.attack then
			skillFlags.bothWeaponAttack = skillFlags.weapon1Attack and skillFlags.weapon2Attack
		end
	end

	-- Build skill mod flag set
	local skillModFlags = 0
	if skillFlags.hit then
		skillModFlags = bor(skillModFlags, ModFlag.Hit)
	end
	if skillFlags.attack then
		skillModFlags = bor(skillModFlags, ModFlag.Attack)
	else
		skillModFlags = bor(skillModFlags, ModFlag.Cast)
		if skillFlags.spell then
			skillModFlags = bor(skillModFlags, ModFlag.Spell)
		end
	end
	if skillFlags.melee then
		skillModFlags = bor(skillModFlags, ModFlag.Melee)
	elseif skillFlags.projectile then
		skillModFlags = bor(skillModFlags, ModFlag.Projectile)
		skillFlags.chaining = true
	end
	if skillFlags.area then
		skillModFlags = bor(skillModFlags, ModFlag.Area)
	end

	-- Build skill keyword flag set
	local skillKeywordFlags = 0
	if skillFlags.hit then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Hit)
	end
	if skillTypes[SkillType.Aura] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Aura)
	end
	if skillTypes[SkillType.AppliesCurse] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Curse)
	end
	if skillTypes[SkillType.Warcry] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Warcry)
	end
	if skillTypes[SkillType.Movement] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Movement)
	end
	if skillTypes[SkillType.Lightning] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Lightning)
	end
	if skillTypes[SkillType.Cold] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Cold)
	end
	if skillTypes[SkillType.Fire] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Fire)
	end
	if skillTypes[SkillType.Chaos] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Chaos)
	end
	if skillTypes[SkillType.Physical] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Physical)
	end
	if skillFlags.weapon1Attack and band(activeSkill.weapon1Flags, ModFlag.Bow) ~= 0 then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Bow)
	end
	if skillFlags.totem then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Totem)
	elseif not skillTypes[SkillType.Triggered] then
		skillFlags.selfCast = true
	end
	if skillTypes[SkillType.Melee] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Attack)
	end
	if skillTypes[SkillType.Spell] and not skillFlags.cast then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Spell)
	end
	if skillTypes[SkillType.Throwing] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Throwing)
	end

	-- Get skill totem ID for totem skills
	-- This is used to calculate totem life
	if skillFlags.totem then
		activeSkill.skillTotemId = activeGrantedEffect.skillTotemId
		if not activeSkill.skillTotemId then
			if activeGrantedEffect.color == 2 then
				activeSkill.skillTotemId = 2
			elseif activeGrantedEffect.color == 3 then
				activeSkill.skillTotemId = 3
			else
				activeSkill.skillTotemId = 1
			end
		end
	end

	-- Calculate Distance for meleeDistance or projectileDistance (for melee proximity, e.g. Impact)
	if skillFlags.melee then
		effectiveRange = env.config.meleeDistance
	else
		effectiveRange = env.config.projectileDistance
	end
	
	-- Build config structure for modifier searches
	activeSkill.skillCfg = {
		flags = bor(skillModFlags, activeSkill.weapon1Flags or activeSkill.weapon2Flags or 0),
		keywordFlags = skillKeywordFlags,
		skillName = activeGrantedEffect.name,
		summonSkillName = activeSkill.summonSkill and activeSkill.summonSkill.activeEffect.grantedEffect.name,
		skillGem = activeEffect.gemData,
		skillGrantedEffect = activeGrantedEffect,
		skillPart = activeSkill.skillPart,
		skillTypes = activeSkill.skillTypes,
		skillAttributes = activeGrantedEffect.skillAttributes,
		skillCond = { },
		skillDist = env.mode_effective and effectiveRange,
		slotName = activeSkill.slotName
	}
	if activeSkill.socketGroup then
		activeSkill.skillCfg.groupSource = activeSkill.socketGroup.source
	end
	if skillFlags.weapon1Attack then
		activeSkill.weapon1Cfg = copyTable(activeSkill.skillCfg, true)
		activeSkill.weapon1Cfg.skillCond = setmetatable({ ["MainHandAttack"] = true }, { __index = activeSkill.skillCfg.skillCond })
		activeSkill.weapon1Cfg.flags = bor(skillModFlags, activeSkill.weapon1Flags)
	end
	if skillFlags.weapon2Attack then
		activeSkill.weapon2Cfg = copyTable(activeSkill.skillCfg, true)
		activeSkill.weapon2Cfg.skillCond = setmetatable({ ["OffHandAttack"] = true }, { __index = activeSkill.skillCfg.skillCond })
		activeSkill.weapon2Cfg.flags = bor(skillModFlags, activeSkill.weapon2Flags)
	end

	-- Initialise skill modifier list
	local skillModList = new("ModList", activeSkill.actor.modDB)
	activeSkill.skillModList = skillModList
	activeSkill.baseSkillModList = skillModList
	
	-- The damage fixup stat applies x% less base Attack Damage and x% more base Attack Speed as confirmed by Openarl Jan 4th 2024
	-- Implemented in this manner as the stat exists on the minion not the skills 
	if activeSkill.actor and activeSkill.actor.minionData and activeSkill.actor.minionData.damageFixup then
		skillModList:NewMod("Damage", "MORE", -100 * activeSkill.actor.minionData.damageFixup, "Damage Fixup", ModFlag.Attack)
		skillModList:NewMod("Speed", "MORE", 100 * activeSkill.actor.minionData.damageFixup, "Damage Fixup", ModFlag.Attack)
	end

	if skillModList:Flag(activeSkill.skillCfg, "DisableSkill") and not skillModList:Flag(activeSkill.skillCfg, "EnableSkill") then
		skillFlags.disable = true
		activeSkill.disableReason = "Skills of this type are disabled"
	end

	if skillFlags.disable then
		wipeTable(skillFlags)
		skillFlags.disable = true
		return
	end

	-- Add support gem modifiers to skill mod list
	for _, skillEffect in pairs(activeSkill.effectList) do
		if skillEffect.grantedEffect.support then
			calcs.mergeSkillInstanceMods(env, skillModList, skillEffect)
			local level = skillEffect.grantedEffect.levels[skillEffect.level]
			if level.manaMultiplier then
				skillModList:NewMod("SupportManaMultiplier", "MORE", level.manaMultiplier, skillEffect.grantedEffect.modSource)
			end
			if level.manaReservationPercent then
				activeSkill.skillData.manaReservationPercent = level.manaReservationPercent
			end	
			-- Handle multiple triggers situation and if triggered by a trigger skill save a reference to the trigger.
			local match = skillEffect.grantedEffect.addSkillTypes and (not skillFlags.disable)
			if match and skillEffect.grantedEffect.isTrigger then
				if activeSkill.triggeredBy then
					skillFlags.disable = true
					activeSkill.disableReason = "This skill is supported by more than one trigger"
				else
					activeSkill.triggeredBy = skillEffect
				end
			end
			if level.storedUses then
				activeSkill.skillData.storedUses = level.storedUses
			end
		end
	end

	-- Apply gem/quality modifiers from support gems
	for _, value in ipairs(skillModList:List(activeSkill.skillCfg, "SupportedGemProperty")) do
		if value.keyword == "grants_active_skill" and activeSkill.activeEffect.gemData and not activeSkill.activeEffect.gemData.tags.support  then
			activeEffect[value.key] = activeEffect[value.key] + value.value
		end
	end

	-- Add active gem modifiers
	activeEffect.actorLevel = activeSkill.actor.minionData and activeSkill.actor.level
	calcs.mergeSkillInstanceMods(env, skillModList, activeEffect, skillModList:List(activeSkill.skillCfg, "ExtraSkillStat"))

	-- Add extra modifiers from granted effect level
	local stats = activeGrantedEffect.stats
	activeSkill.skillData.CritChance = stats.critChance
	if stats.cooldown then
		activeSkill.skillData.cooldown = stats.cooldown
	end

	-- Add extra modifiers from other sources
	activeSkill.extraSkillModList = { }
	for _, value in ipairs(skillModList:List(activeSkill.skillCfg, "ExtraSkillMod")) do
		skillModList:AddMod(value.mod)
		t_insert(activeSkill.extraSkillModList, value.mod)
	end

	-- Add buff mods
	if activeGrantedEffect.buffs then
		for _, buff in ipairs(activeGrantedEffect.buffs) do
			local mods, extra = modLib.parseMod(buff)

			if mods and not extra then
				local source = activeGrantedEffect.modSource
				for i = 1, #mods do
					local mod = mods[i]
					if mod then
						mod = modLib.setSource(mod, source)
						t_insert(mod, { type = "GlobalEffect", effectType = "Debuff", effectStackVar = activeGrantedEffect.id.."Stack"})
						skillModList:AddMod(mod)
					end
				end
			end
		end
	end

	-- Find totem level
	if skillFlags.totem then
		activeSkill.skillData.totemLevel = activeEffect.grantedEffectLevel.levelRequirement
	end

	-- Determine if it possible to have a stage on this skill based upon skill parts.
	local noPotentialStage = true
	if activeEffect.grantedEffect.parts then
		for _, part in ipairs(activeEffect.grantedEffect.parts) do
			if part.stages then 
				noPotentialStage = false
				break
			end
		end
	end

	if skillModList:Sum("BASE", activeSkill.skillCfg, "Multiplier:"..activeGrantedEffect.name:gsub("%s+", "").."MaxStages") > 0 then
		skillFlags.multiStage = true
		activeSkill.activeStageCount = m_max((env.mode == "CALCS" and activeEffect.srcInstance.skillStageCountCalcs) or (env.mode ~= "CALCS" and activeEffect.srcInstance.skillStageCount) or 1, 1 + skillModList:Sum("BASE", activeSkill.skillCfg, "Multiplier:"..activeGrantedEffect.name:gsub("%s+", "").."MinimumStage"))
		local limit = skillModList:Sum("BASE", activeSkill.skillCfg, "Multiplier:"..activeGrantedEffect.name:gsub("%s+", "").."MaxStages")
		if limit > 0 then
			if activeSkill.activeStageCount and activeSkill.activeStageCount > 0 then
				skillModList:NewMod("Multiplier:"..activeGrantedEffect.name:gsub("%s+", "").."Stage", "BASE", m_min(limit, activeSkill.activeStageCount), "Base")
				activeSkill.activeStageCount = (activeSkill.activeStageCount or 0) - 1
				skillModList:NewMod("Multiplier:"..activeGrantedEffect.name:gsub("%s+", "").."StageAfterFirst", "BASE", m_min(limit - 1, activeSkill.activeStageCount), "Base")
			end
		end
	elseif noPotentialStage and activeEffect.srcInstance and not (activeEffect.gemData and activeEffect.gemData.secondaryGrantedEffect) then
		activeEffect.srcInstance.skillStageCountCalcs = nil
		activeEffect.srcInstance.skillStageCount = nil
	end

	-- Extract skill data
	for _, value in ipairs(env.modDB:List(activeSkill.skillCfg, "SkillData")) do
		activeSkill.skillData[value.key] = value.value
	end
	for _, value in ipairs(skillModList:List(activeSkill.skillCfg, "SkillData")) do
		activeSkill.skillData[value.key] = value.value
	end

	-- Create minion
	local minionList, isSpectre
	if activeGrantedEffect.minionList then
		if activeGrantedEffect.minionList[1] then
			minionList = copyTable(activeGrantedEffect.minionList)
		else
			minionList = copyTable(env.build.spectreList)
			isSpectre = true
		end
	else
		minionList = { }
	end
	for _, skillEffect in ipairs(activeSkill.effectList) do
		if skillEffect.grantedEffect.support and skillEffect.grantedEffect.addMinionList then
			for _, minionType in ipairs(skillEffect.grantedEffect.addMinionList) do
				t_insert(minionList, minionType)
			end
		end
	end
	activeSkill.minionList = minionList
	if minionList[1] and not activeSkill.actor.minionData then
		local minionType
		if env.mode == "CALCS" and activeSkill == env.player.mainSkill then
			local index = isValueInArray(minionList, activeEffect.srcInstance.skillMinionCalcs) or 1
			minionType = minionList[index]
			activeEffect.srcInstance.skillMinionCalcs = minionType
		else
			local index = isValueInArray(minionList, activeEffect.srcInstance.skillMinion) or 1
			minionType = minionList[index]
			activeEffect.srcInstance.skillMinion = minionType
		end
		if minionType then
			local minion = { }
			activeSkill.minion = minion
			skillFlags.haveMinion = true
			minion.parent = env.player
			minion.enemy = env.enemy
			minion.type = minionType
			minion.minionData = env.data.minions[minionType]
			minion.level = env.build and env.build.characterLevel
			minion.itemList = { }
			minion.uses = activeGrantedEffect.minionUses
			minion.weaponData1 = env.player.weaponData1
			minion.weaponData2 = { }
		end
	elseif activeEffect.srcInstance and not (activeEffect.gemData and activeEffect.gemData.secondaryGrantedEffect) then
		activeEffect.srcInstance.skillMinionCalcs = nil
		activeEffect.srcInstance.skillMinion = nil
		activeEffect.srcInstance.skillMinionItemSetCalcs = nil
		activeEffect.srcInstance.skillMinionItemSet = nil
		activeEffect.srcInstance.skillMinionSkill = nil
		activeEffect.srcInstance.skillMinionSkillCalcs = nil
	end

	-- Separate global effect modifiers (mods that can affect defensive stats or other skills)
	local i = 1
	while skillModList[i] do
		local effectType, effectName, effectTag
		for _, tag in ipairs(skillModList[i]) do
			if tag.type == "GlobalEffect" then
				effectType = tag.effectType
				effectName = tag.effectName or activeGrantedEffect.name
				effectTag = tag
				break
			end
		end
		if effectTag and effectTag.modCond and not skillModList:GetCondition(effectTag.modCond, activeSkill.skillCfg) then
			t_remove(skillModList, i)
		elseif effectType then
			local buff
			for _, skillBuff in ipairs(activeSkill.buffList) do
				if skillBuff.type == effectType and skillBuff.name == effectName then
					buff = skillBuff
					break
				end
			end
			if not buff then
				buff = {
					type = effectType,
					name = effectName,
					allowTotemBuff = effectTag.allowTotemBuff,
					cond = effectTag.effectCond,
					enemyCond = effectTag.effectEnemyCond,
					stackVar = effectTag.effectStackVar,
					stackLimit = effectTag.effectStackLimit,
					stackLimitVar = effectTag.effectStackLimitVar,
					applyNotPlayer = effectTag.applyNotPlayer,
					applyMinions = effectTag.applyMinions,
					modList = { },
				}
				if skillModList[i].source == activeGrantedEffect.modSource then
					-- Inherit buff configuration from the active skill
					buff.activeSkillBuff = true
					buff.applyNotPlayer = buff.applyNotPlayer or activeSkill.skillData.buffNotPlayer
					buff.applyMinions = buff.applyMinions or activeSkill.skillData.buffMinions
					buff.applyAllies = activeSkill.skillData.buffAllies
					buff.allowTotemBuff = activeSkill.skillData.allowTotemBuff
				end
				t_insert(activeSkill.buffList, buff)
			end
			local match = false
			local modList = buff.modList
			for d = 1, #modList do
				local destMod = modList[d]
				if modLib.compareModParams(skillModList[i], destMod) and (destMod.type == "BASE" or destMod.type == "INC") then
					destMod = copyTable(destMod)
					destMod.value = destMod.value + skillModList[i].value
					modList[d] = destMod
					match = true
					break
				end
			end
			if not match then
				t_insert(modList, skillModList[i])
			end
			t_remove(skillModList, i)
		else
			i = i + 1
		end
	end

	if activeSkill.buffList[1] then
		-- Add to auxiliary skill list
		t_insert(env.auxSkillList, activeSkill)
	end
end

-- Initialise the active skill's minion skills
function calcs.createMinionSkills(env, activeSkill)
	local activeEffect = activeSkill.activeEffect
	local minion = activeSkill.minion
	local minionData = minion.minionData

	minion.activeSkillList = { }
	local skillIdList = { }
	for _, skillId in ipairs(minionData.skillList) do
		if env.data.skills[skillId] then
			t_insert(skillIdList, skillId)
		end
	end
	for _, skill in ipairs(activeSkill.skillModList:List(activeSkill.skillCfg, "ExtraMinionSkill")) do
		if not skill.minionList or isValueInArray(skill.minionList, minion.type) then
			t_insert(skillIdList, skill.skillId)
		end
	end
	if #skillIdList == 0 then
		-- Not ideal, but let's avoid crashes
		t_insert(skillIdList, "Default")
	end
	for _, skillId in ipairs(skillIdList) do
		local activeEffect = {
			grantedEffect = env.data.skills[skillId],
			level = 1,
			quality = 0,
		}
		local minionSkill = calcs.createActiveSkill(activeEffect, activeSkill.supportList, minion, nil, activeSkill)
		calcs.buildActiveSkillModList(env, minionSkill)
		minionSkill.skillFlags.minion = true
		minionSkill.skillFlags.minionSkill = true
		minionSkill.skillFlags.haveMinion = true
		minionSkill.skillFlags.spectre = activeSkill.skillFlags.spectre
		minionSkill.skillData.damageEffectiveness = 1 + (activeSkill.skillData.minionDamageEffectiveness or 0) / 100
		t_insert(minion.activeSkillList, minionSkill)
	end
	local skillIndex 
	if env.mode == "CALCS" then
		skillIndex = m_max(m_min(activeEffect.srcInstance.skillMinionSkillCalcs or 1, #minion.activeSkillList), 1)
		activeEffect.srcInstance.skillMinionSkillCalcs = skillIndex
	else
		skillIndex = m_max(m_min(activeEffect.srcInstance.skillMinionSkill or 1, #minion.activeSkillList), 1)
		if env.mode == "MAIN" then
			activeEffect.srcInstance.skillMinionSkill = skillIndex
		end
	end
	minion.mainSkill = minion.activeSkillList[skillIndex]
end
