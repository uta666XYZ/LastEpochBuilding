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
	-- @leb-regression-guard: deterministic-skill-stat-merge-order
	-- Iterate the granted-effect stats in a STABLE (sorted-key) order, not raw
	-- pairs() order. Several stat keys map to the same skillData key — e.g.
	-- both `None_base_fire_damage` and `spell_base_fire_damage` map to
	-- SkillData "FireDamage" (SkillStatMap.lua) — and skillData is populated by
	-- a last-wins assignment (`skillData[value.key] = value.value`, ~L1170).
	-- Lua randomises string-key hash order per process, so raw pairs() made the
	-- last-merged (winning) FireDamage nondeterministic: <private build> Runemaster's
	-- Flame Rush base fire damage flipped 20<->40 run-to-run (FireDamageBase
	-- 128<->148), cascading into FullDPS / Lightning*/Stun / EHP families and
	-- producing the flaky TestBuilds_spec snapshot mismatches. Sorting the keys
	-- makes the winning value deterministic (delivery-tagged `spell_*`=40 sorts
	-- after the generic `None_*`=20, matching the in-game spell value). See
	-- spec/System/TestSkillStatMergeDeterminism_spec.lua and REGRESSION_GUARDS.md.
	local sortedStatKeys = {}
	for stat in pairs(stats) do sortedStatKeys[#sortedStatKeys + 1] = stat end
	table.sort(sortedStatKeys)
	for _, stat in ipairs(sortedStatKeys) do
		local statValue = stats[stat]
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
	-- @leb-regression-guard: melee-skill-hit-flag
	-- In LE every weapon-delivery skill (melee/bow/throwing) lands a damaging hit;
	-- the hit flag gates crit, on-hit effects and the entire hit-damage pass in
	-- CalcOffence (`if NeverCrit or not skillFlags.hit then CritChance=0`). skills.json
	-- sets baseFlags.hit for most skills, but a few attacks (ShatterStrike, CinderStrike,
	-- DarkQuiver) omit it, and the PoB-era skillTypes fallback below never fires for LE
	-- pure-melee skills: SkillType.Attack = Melee|Throwing|Bow and the `band(tags,type)==type`
	-- test in DataProcess requires ALL three bits, SkillType.Damage is undefined (nil), and
	-- SkillType.Projectile = Unsupported. So a Melee-only skill (skillTypeTags bit 512) was
	-- left with hit=nil, zeroing its crit (in-game ShutFackUp Shatter Strike shows 35% crit,
	-- LEB computed 0%). Ailment-delivery skills (Ailment_Laceration) carry a melee flag but
	-- only apply a DoT — they do not directly hit, so exclude baseFlags.ailment.
	skillFlags.hit = skillFlags.hit
		or ((skillFlags.melee or skillFlags.bow or skillFlags.throwing) and not skillFlags.ailment)
		or activeSkill.skillTypes[SkillType.Attack] or activeSkill.skillTypes[SkillType.Damage] or activeSkill.skillTypes[SkillType.Projectile]

	-- @leb-regression-guard:pure-dot-skill-dot-flag
	-- A PURE damage-over-time skill (Profane Veil, Aura of Decay, ...) carries the DoT
	-- bit in skillTypeTags (skillTypes[SkillType.Dot]=true) but its baseFlags omit 'dot',
	-- so skillFlags.dot stayed nil and the pure-dot-skill-modflag-dot block below (which
	-- carries ModFlag.Dot so "increased Damage over Time" applies) never fired -- dropping
	-- all increased-DoT (Profane Veil: LEB 178.5 vs in-game 400.8, +521% DoT INC filtered).
	-- Derive dot for PURE-DoT skills only (DoT type, no hit) so hit+dot skills
	-- (DevouringOrb/EntanglingRoots/HungeringSouls/Chthonic Fissure/Judgement) are untouched.
	-- SkillType.Dot = 4096 (SkillType.DoT is nil -- a latent typo). See REGRESSION_GUARDS.md.
	skillFlags.dot = skillFlags.dot or (activeSkill.skillTypes[SkillType.Dot] and not skillFlags.hit) or nil

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
	-- @leb-regression-guard:tree-tag-swap-determinism (producer site)
	-- Two allocated nodes on one tree can both write swaps[srcBit] (YsSmiteVK's
	-- Smite: sm87r4-21 " Fire -> Lightning Damage" vs sm87r4-32 " Void Conversion"
	-- whose inferred source is also Fire). swaps[src] is last-writer-wins, and
	-- pairs(env.allocNodes) iterates string keys in per-process hash order, so the
	-- winner flapped run-to-run (Smite's Void tag appearing/vanishing => the VK Echo
	-- 10% MORE gate flipping => a uniform x1.10 swing on ~32 output keys). Iterate
	-- node ids in sorted order so the LEXICALLY-LAST allocated node deterministically
	-- wins a same-source collision — for Smite that is sm87r4-32, i.e. Void, matching
	-- the snapshot corpus. See REGRESSION_GUARDS.md "tree-tag-swap-determinism".
	local swapNodeIds = {}
	for nodeId, node in pairs(env.allocNodes) do
		if nodeId:sub(1, #prefix) == prefix and node.stats then
			t_insert(swapNodeIds, nodeId)
		end
	end
	table.sort(swapNodeIds)
	for _, nodeId in ipairs(swapNodeIds) do
		local node = env.allocNodes[nodeId]
		do
			for _, stat in ipairs(node.stats) do
				local src, dst = stat:match("^%s*(%w+)%s*%->%s*(%w+)%s+Damage%s*$")
				if not src then
					src, dst = stat:match("^%s*(%w+)%s+Damage%s*%->%s*(%w+)%s+Damage%s*$")
				end
				if not src then
					src, dst = stat:match("^%s*(%w+)%s*%->%s*(%w+)%s+Conversion%s*$")
				end
				if not src then
					-- Bare "<Src> -> <Dst>" form (no Damage / Conversion suffix).
					-- Used by Flame Ward's Lightning Ward (fw3d-10: " Fire -> Lightning")
					-- and Cold Ward (fw3d-?: " Fire -> Cold"). The damageTypeBitsByName
					-- filter below rejects ailment swaps like " Chill -> Ignite",
					-- " Frostbite -> Shock", " Ignite -> Frostbite" since Chill/
					-- Frostbite/Ignite/Shock aren't in the damage-type bit table.
					src, dst = stat:match("^%s*(%w+)%s*%->%s*(%w+)%s*$")
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
					-- Plain damage producer: stats ending in "<DmgType> Damage"
					-- (e.g. wc57-30 Kinetic Scream "40 Spell Physical Damage" gives
					-- Warcry the Physical bit so "+to Physical Skills" applies).
					-- damageTypeBitsByName lookup filters spurious matches.
					local plainType = stat:match("(%w+)%s+[Dd]amage%s*$")
					if plainType and damageTypeBitsByName[plainType] then
						adds = bor(adds, damageTypeBitsByName[plainType])
					end
				end
			end
			-- Split-effect damage-type additions parsed from node descriptions.
			-- Per datamined game source findings: per-node mutator state (e.g. Black Hole's
			-- BinaryStar bool) isn't serialized — only `<Skill>Tree.updateMutator()`
			-- C# bytecode knows the exact mapping. As a fallback we pattern-match
			-- description text for split-effect phrasing like Binary System
			-- ("One deals fire damage and the other deals cold damage"), which
			-- introduces both damage types as base. Cap-summing needs these
			-- bits so e.g. "+to Fire Spell Skills" matches a Black Hole that
			-- has Binary System allocated.
			if node.description then
				for _, line in ipairs(node.description) do
					-- Per-sub-line gating: descriptions can pack multiple
					-- sentences with `\n\n` separators; conditional ("if ...")
					-- sub-lines must not promote unconditional tag additions.
					for sub in (line .. "\n"):gmatch("([^\n]*)\n") do
						local lo = sub:lower()
						if lo ~= "" and not lo:match("^%s*if%s") then
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
							-- Delivery-class promotion: nodes that convert a spell
							-- into a melee/throwing/bow attack add the new delivery
							-- bit so "+to <Delivery> Skills" affixes match.
							-- Healing Hands' Seraph Blade (hh7pa3-8): "Healing Hands
							-- is converted into a melee attack..." — confirmed via
							-- LETools applying "+6 to Level of Melee Skills" from
							-- Two-Handed Axe to a build with Seraph Blade allocated.
							-- Note: we ADD the delivery bit rather than swap-out
							-- Spell so DoT/Buff-related Spell-tagged behaviour is
							-- preserved (the in-game tooltip drops Spell, but
							-- LEB's downstream code assumes Spell tag elsewhere).
							if lo:match("is converted into a melee attack") then
								adds = bor(adds, SkillType.Melee)
							elseif lo:match("is converted into a throwing attack") then
								adds = bor(adds, SkillType.Throwing)
							elseif lo:match("is converted into a bow attack") then
								adds = bor(adds, SkillType.Bow)
							end
							-- Damage-type addition phrase: "deal[s]?[ing]? [<adj>]
							-- <type> damage". Examples:
							--   hh7pa3-1 Searing Light: "dealing spell fire damage"
							--   wo42-14 Tundra Stalkers: "deal additional cold damage"
							--   wc57-30 Kinetic Scream: "deals spell physical damage"
							-- Filtered through damageTypeBitsByName so spurious matches
							-- like "deals more damage" / "deals increased damage" miss.
							if lo:find("deal", 1, true) then
								for typeName, b in pairs(damageTypeBitsByName) do
									local needle = " " .. typeName:lower() .. " damage"
									if lo:find(needle, 1, true) then
										adds = bor(adds, b)
									end
								end
							end
						end
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
	-- @leb-regression-guard:tree-tag-swap-determinism (consumer site)
	-- Two-phase apply against the PRE-swap tag set. The old incremental loop let
	-- one swap's destination feed another swap's source test, so chained swaps
	-- ({A->B, B->C}) double-hopped or not depending on pairs() hash order (swaps
	-- is keyed by numeric bits whose table layout follows insertion order).
	-- Deciding every swap against the original set makes the result independent
	-- of iteration order: sources present up-front are removed, their
	-- destinations added, and a destination that is also a removed source stays
	-- present. See REGRESSION_GUARDS.md "tree-tag-swap-determinism".
	local removeMask, addMask = 0, 0
	for srcBit, dstBit in pairs(swaps) do
		if out[srcBit] then
			removeMask = bor(removeMask, srcBit)
			addMask = bor(addMask, dstBit)
		end
	end
	for srcBit in pairs(swaps) do
		if band(removeMask, srcBit) ~= 0 then
			out[srcBit] = nil
		end
	end
	for srcBit, dstBit in pairs(swaps) do
		if band(removeMask, srcBit) ~= 0 then
			out[dstBit] = true
		end
	end
	kw = bor(band(kw, bnot(removeMask)), addMask)
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
-- @leb-regression-guard:stcdt-conversion-shapes
-- Pattern catalogue covering every conversion / addition / source-removal
-- stat & description prose shape used across LE's skill trees as of 2026-05.
-- Each shape has a corresponding case in spec/System/TestStcdtParser_spec.lua;
-- see REGRESSION_GUARDS.md#stcdt-conversion-shapes for the full inventory.
function calcs.getActiveStcdtBits(env, treeId, stcdt)
	if not stcdt or stcdt == 0 then return 0, 0 end
	if not (treeId and env and env.allocNodes) then return 0, 0 end
	local prefix = treeId .. "-"
	local active = 0
	local removed = 0
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
				if not dst then
					-- Multi-source AND-join conversion: "<Src1> and <Src2> -> <Dst> Damage"
					-- (e.g. svz81-23 Horrific Vessels: "Physical and Fire -> Necrotic Damage").
					-- Only the destination matters here; source-side removal is
					-- handled by getTreeTagSwaps below.
					_, _, dst = stat:match("^%s*(%w+)%s+and%s+(%w+)%s*%->%s*(%w+)%s+Damage%s*$")
				end
				if not dst then
					-- Multi-source AND-join Conversion suffix: "<Src1> and <Src2> -> <Dst> Conversion"
					-- (e.g. tree_3 cb52d2-? "Necrotic and Fire -> Physical Conversion").
					_, _, dst = stat:match("^%s*(%w+)%s+and%s+(%w+)%s*%->%s*(%w+)%s+Conversion%s*$")
				end
				if not dst then
					-- Qualifier-prefixed modifier conversion: "Increased <Src> Damage -> <Dst> Damage"
					-- (e.g. ds4d3-32 Vile Ghast: "Increased Necrotic Damage -> Poison Damage").
					-- Modifier-conversion only — does not strip the source damage type
					-- but DOES introduce the destination as a relevant scaling tag.
					_, dst = stat:match("^%s*Increased%s+(%w+)%s+Damage%s*%->%s*(%w+)%s+Damage%s*$")
				end
				if not dst then
					-- Addition: "Enables <Type> Nova" (e.g. en6-2/8/12 Elemental Nova
					-- "Enables Cold/Lightning/Fire Nova"). The named type becomes a
					-- legitimate damage type when the gating node is allocated.
					dst = stat:match("^%s*Enables%s+(%w+)%s+Nova%s*$")
				end
				if not dst then
					-- Bare "<Src> -> <Dst>" form (no suffix). Same fallback as
					-- getTreeTagSwaps; see comment there. Filtered safely via
					-- damageTypeBitsByName lookup (rejects ailment swaps).
					local _src
					_src, dst = stat:match("^%s*(%w+)%s*%->%s*(%w+)%s*$")
					if dst and not damageTypeBitsByName[dst] then dst = nil end
				end
				-- Per Q2: "<X> -> Elemental Damage" (e.g. cstri-22 Elemental
				-- Vulnerability) is a buff-modifier rewrite, not a skill damage
				-- tag change. Skip the Elemental aggregate entirely.
				if dst and dst:lower() == "elemental" then dst = nil end
				if dst and damageTypeBitsByName[dst] then
					active = bor(active, damageTypeBitsByName[dst])
				end
				-- variant addition: produces variant's damage bits
				local addV = stat:match("^%s*Adds%s+(.+)%s*$")
				if addV and minionVariantBits[addV] then
					active = bor(active, minionVariantBits[addV])
				end
				-- Plain damage producer: stats ending in "<DmgType> Damage"
				-- (e.g. wo42-14 Tundra Stalkers "+2 Cold Damage", wc57-30
				-- Kinetic Scream "40 Spell Physical Damage", wc57-6 Frost Claw
				-- "50% Increased Cold Damage"). The damageTypeBitsByName lookup
				-- filters out matches like "Increased Damage" / "More Damage".
				local plainType = stat:match("(%w+)%s+[Dd]amage%s*$")
				if plainType and damageTypeBitsByName[plainType] then
					active = bor(active, damageTypeBitsByName[plainType])
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
				for sub in (line .. "\n"):gmatch("([^\n]*)\n") do
					local lo = sub:lower()
					if lo ~= "" and not lo:match("^%s*if%s") then
						-- Capture the inner phrase between "gain the" and "tag"
						-- (single word, allowing `\n`/`\r` since `.` excludes them).
						for inner in lo:gmatch("gain the[%s%S]-tag") do
							for typeName, b in pairs(damageTypeBitsByName) do
								if inner:find(typeName:lower(), 1, true) then
									active = bor(active, b)
								end
							end
						end
						-- "deal[s]?[ing]? [<adj>] [<adj>] <type> damage"
						-- Matches: "deals spell physical damage" (wc57-30),
						-- "deal additional cold damage" (wo42-14 Tundra Stalkers),
						-- "dealing spell fire damage" (hh7pa3-1 Searing Light).
						local verbStart, verbEnd = lo:find("deal[s]?[ing]*%s")
						if verbStart then
							for typeName, b in pairs(damageTypeBitsByName) do
								local needle = " " .. typeName:lower() .. " damage"
								if lo:find(needle, verbEnd, true) then
									active = bor(active, b)
								end
							end
						end
						-- Source-bit removal: "loses its <type> tag" /
						-- "loses its {<type>} tag" without an `if` conditional
						-- prefix (the `if` filter above already gates that).
						-- Per Q3=(a) only unconditional/full-conversion source
						-- removal is recognised here; partial-% conditionals
						-- are skipped. Examples that DO match:
						--   tree_3 rea-32: "Reap loses its {Necrotic} tag and
						--     gains a {Physical} tag instead."
						-- Examples that don't match (have `if` prefix):
						--   tree_0 sw1, tree_4 srk21-25.
						for inner in lo:gmatch("loses its[%s%S]-tag") do
							for typeName, b in pairs(damageTypeBitsByName) do
								if inner:find(typeName:lower(), 1, true) then
									removed = bor(removed, b)
								end
							end
						end
					end
				end
			end
		end
	end
	return band(stcdt, active), removed
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
			if not dst then
				-- @leb-regression-guard: lament-base-damage-conversion
				-- Lament of the Lost Refuge: "100% of Volcanic Orb Base Damage
				-- Converted to Void". Only the full 100% form swaps the skill's
				-- intrinsic damage tag; partial conversions stay handled by the
				-- generic "% damage converted" suffix chain elsewhere.
				dst = text:match("^100%% of " .. nameLower:gsub("(%W)", "%%%1") .. " base damage converted to (%w+)$")
			end
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

-- @leb-regression-guard: lament-base-damage-conversion
-- Returns the lower-case destination damage type ("fire" / "cold" /
-- "lightning" / "necrotic" / "void" / "physical" / "poison") that the
-- equipped item set forces this skill's BASE DAMAGE stat keys onto, or
-- nil if no full conversion applies. Used by mergeSkillInstanceMods to
-- rewrite stat keys like `spell_base_fire_damage` -> `spell_base_void_damage`
-- so the skill's stats.json base value flows into the destination type's
-- damage pool. Pairs with getItemSkillTagConversions, which swaps the
-- skill's intrinsic damage tag for matching affix targeting.
--
-- Pattern matched: "100% of <Skill> Base Damage Converted to <Type>"
-- (Lament of the Lost Refuge, etc.). Only 100% performs the full swap;
-- partial conversions are handled by the generic conversion suffix chain
-- and don't rewrite the base damage stat key.
function calcs.getItemSkillBaseDamageConversion(env, grantedEffect)
	if not (env and env.player and env.player.itemList and grantedEffect and grantedEffect.name) then
		return nil
	end
	local nameLower = grantedEffect.name:lower()
	local namePat = "^100%% of " .. nameLower:gsub("(%W)", "%%%1") .. " base damage converted to (%w+)$"
	local function scan(modLines)
		if not modLines then return nil end
		for _, line in ipairs(modLines) do
			local text = (line.line or ""):lower()
			local dst = text:match(namePat)
			if dst then
				local dstCap = dst:sub(1, 1):upper() .. dst:sub(2):lower()
				if damageTypeBitsByName[dstCap] then
					return dst
				end
			end
		end
		return nil
	end
	for _, item in pairs(env.player.itemList) do
		if item then
			local r = scan(item.explicitModLines) or scan(item.implicitModLines) or scan(item.enchantModLines)
			if r then return r end
		end
	end
	return nil
end

-- Damage-type stat-key prefixes recognized by SkillStatMap. When a skill is
-- under a "100% of <Skill> Base Damage Converted to <Type>" item conversion
-- (e.g. Lament -> Volcanic Orb), the stat key is rewritten from
-- "<prefix><srcType>_damage" to "<prefix><dstType>_damage" before lookup so
-- the skill's base damage flows into the destination damage pool.
local BASE_DAMAGE_STAT_PREFIXES = {
	"spell_base_", "melee_base_", "bow_base_", "throwing_base_", "None_base_",
}
local BASE_DAMAGE_STAT_TYPES = {
	"fire", "cold", "lightning", "necrotic", "void", "physical", "poison",
}
function calcs.swapBaseDamageStatKey(stat, dstType)
	if not (stat and dstType) then return stat end
	for _, prefix in ipairs(BASE_DAMAGE_STAT_PREFIXES) do
		for _, dt in ipairs(BASE_DAMAGE_STAT_TYPES) do
			if dt ~= dstType and stat == prefix .. dt .. "_damage" then
				return prefix .. dstType .. "_damage"
			end
		end
	end
	return stat
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
	-- @leb-regression-guard:pure-dot-skill-modflag-dot
	-- A PURE damage-over-time skill (skillFlags.dot, but it does NOT hit and is
	-- NOT an ailment) deals all of its damage as a degen, so its damage cfg must
	-- carry ModFlag.Dot for "increased/more Damage over Time" modifiers (parsed
	-- as { "Damage", flags = ModFlag.Dot }, ModParser) to apply -- calcDamage()
	-- sums INC/MORE with this single cfg (there is no separate dotCfg). Without
	-- it, e.g. Consecrated Ground (granted by Judgement) silently dropped the
	-- "Anointed" node "+100% Damage Over Time" (pa67ju-3) and every other DoT
	-- scalar, undercounting by the build's whole DoT multiplier stack
	-- (MyLittleStJames CG was 32x below the in-game per-tick).
	--   * Gated to NOT hit  -> a hit+dot skill keeps its hit damage clean (the
	--     merged calcDamage path cannot split hit vs dot scaling).
	--   * Gated to NOT ailment -> ailments compute on the data.damagingAilment
	--     path with their own AilmentDamage scaling; leave that untouched.
	-- See REGRESSION_GUARDS.md "pure-dot-skill-modflag-dot".
	if skillFlags.dot and not skillFlags.hit and not skillFlags.ailment then
		skillModFlags = bor(skillModFlags, ModFlag.Dot)
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
	if skillFlags.weapon1Attack and band(activeSkill.weapon1Flags, ModFlag.Bow) ~= 0
		and not skillTypes[SkillType.Throwing] then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Bow)
	end
	if skillFlags.totem then
		skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Totem)
	elseif not skillTypes[SkillType.Triggered] then
		skillFlags.selfCast = true
	end
	if skillTypes[SkillType.Melee] then
		-- @leb-regression-guard:ailment-finisher-scaling (strict delivery keyword)
		-- @leb-regression-guard:minion-melee-keyword-no-bundle (strict minion melee)
		-- Validation provenance is retained in maintainer notes.
		if activeGrantedEffect.ailmentFinisher then
			skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Melee)
		elseif activeSkill.actor and activeSkill.actor.minionData then
			skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Melee)
		else
			skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Attack)
		end
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
		-- @leb-regression-guard:minion-granted-weapon-attack-base-inheritance
		-- skillNameForMatch decouples MOD-MATCHING from the DISPLAY name. It is set only on a
		-- minion weapon-base clone (createMinionSkills below) whose display name is re-skinned to
		-- the player skill (e.g. "Earthquake") but which must NOT inherit that player skill's
		-- SkillName-tagged tree mods (the bear's "-60% Earthquake" node be36ar-15). The F4 oracle
		-- proved those do not apply in-game (EQ element-MORE 9.98 == Melee's). Nil for every normal
		-- skill => identical behaviour (falls back to the display name).
		skillName = activeGrantedEffect.skillNameForMatch or activeGrantedEffect.name,
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
		-- @leb-regression-guard:ailment-finisher-scaling (parent-tree cut)
		-- Validation provenance is retained in maintainer notes.
		if not activeGrantedEffect.ailmentFinisher then
			activeSkill.skillCfg.groupSource = activeSkill.socketGroup.source
		end
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

	-- @leb-regression-guard:void-knight-echo-more (consumer site)
	-- Void Knight mastery echo bonus: a P% chance to fully re-cast the ability 0.5s
	-- later = +P% average damage (full re-cast, no chain, full damage). The parser
	-- (ModParser specialModList, tree_2.json "Void Knight") lands the chance as a
	-- VoidKnightEchoChance BASE player mod; here it becomes a Damage MORE scoped to the
	-- eligible skill set: melee attacks OR throwing attacks OR void spells, EXCLUDING
	-- movement skills and Anomaly (game text). This any-of-minus-exclusions gate can't be
	-- expressed as one keyword-tagged mod, so it is resolved per-skill at setup. Reading
	-- actor.modDB keeps it player-only (minions carry no VK flag). Spec: TestVoidKnightEcho.
	local vkEchoChance = activeSkill.actor.modDB:Sum("BASE", nil, "VoidKnightEchoChance")
	if vkEchoChance > 0
		and activeGrantedEffect.name ~= "Anomaly"
		and not activeSkill.skillTypes[SkillType.Movement]
		and (skillFlags.melee or skillFlags.throwing or (activeSkill.skillTypes[SkillType.Void] and skillFlags.spell)) then
		skillModList:NewMod("Damage", "MORE", vkEchoChance, "Void Knight Echo")
	end

	-- @leb-regression-guard:javelin-spear-melee-to-throwing-conversion
	-- Validation provenance is retained in maintainer notes.
	if activeGrantedEffect.id == "Javelin" and activeSkill.skillTypes[SkillType.Throwing] then
		local weaponData1 = activeSkill.actor.weaponData1
		local weapon1Type = weaponData1 and env.data.weaponTypeInfo[weaponData1.type]
		local weapon1Item = activeSkill.actor.itemList and activeSkill.actor.itemList["Weapon 1"]
		if weapon1Type and weapon1Type.flag == "Spear" and weapon1Item and weapon1Item.modSource then
			local weaponSource = weapon1Item.modSource
			local meleeCfg = { keywordFlags = KeywordFlag.Melee }
			-- typeless "Damage" last: converted generic added rides the skill's own type set
			for _, modName in ipairs({ "PhysicalDamage", "FireDamage", "ColdDamage", "LightningDamage", "VoidDamage", "NecroticDamage", "PoisonDamage", "Damage" }) do
				local spearMeleeAdded = 0
				for _, entry in ipairs(skillModList:Tabulate("BASE", meleeCfg, modName)) do
					if entry.mod.source == weaponSource then
						spearMeleeAdded = spearMeleeAdded + (entry.value or 0)
					end
				end
				if spearMeleeAdded ~= 0 then
					skillModList:NewMod(modName, "BASE", spearMeleeAdded * 0.5, "Javelin Spear Melee Conversion")
				end
			end
		end
	end

	-- The damage fixup stat applies x% less base Attack Damage and x% more base Attack Speed as confirmed by Openarl Jan 4th 2024
	-- Implemented in this manner as the stat exists on the minion not the skills
	if activeSkill.actor and activeSkill.actor.minionData and activeSkill.actor.minionData.damageFixup then
		skillModList:NewMod("Damage", "MORE", -100 * activeSkill.actor.minionData.damageFixup, "Damage Fixup", ModFlag.Attack)
		skillModList:NewMod("Speed", "MORE", 100 * activeSkill.actor.minionData.damageFixup, "Damage Fixup", ModFlag.Attack)
	end

	if skillModList:Flag(activeSkill.skillCfg, "DisableSkill") and not skillModList:Flag(activeSkill.skillCfg, "EnableSkill") then
		skillFlags.disable = true
		activeSkill.disableReason = "Skills of this type are disabled"
		-- @leb-regression-guard:upheaval-totem-disable-reason
		-- uph41-30 "Upheaval Totems" disables the PLAYER-cast Upheaval because the totem now
		-- casts it "rather than yourself" (CalcSetup injects a SkillName-scoped DisableSkill
		-- with source "uph41-30:replacesParentHit"; see @leb-regression-guard:upheaval-totem-grant).
		-- Surface that real reason instead of the generic "type is disabled" text, which
		-- misleads here (the skill TYPE is not disabled -- this specific cast is replaced).
		for _, entry in ipairs(skillModList:Tabulate("FLAG", activeSkill.skillCfg, "DisableSkill")) do
			if entry.mod and entry.mod.source == "uph41-30:replacesParentHit" then
				activeSkill.disableReason = "Cast by Upheaval Totem\nsee Summon Upheaval Totem"
				break
			end
		end
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
	-- @leb-regression-guard: inherent-base-crit-chance
	-- LE gives every hit an inherent 5% base crit (datamined game source Stats.baseCritChance = 0.05). This becomes
	-- skillData.CritChance, consumed in CalcOffence as `baseCrit` (source = skillData, line ~1648/2125).
	-- skills.json declares critChance=5 on 137 abilities but OMITS it on ~206 others (Shatter Strike,
	-- Wandering Spirits, ...), which left them at baseCrit=0 -- dropping the inherent 5%. Verified in-game:
	-- ShutFackUp Shatter Strike melee crit (5 inherent + 5 sword-melee + 2 Phantom) * (1+3.95) = 59.4 -> 59,
	-- generic (5 + 2) * 4.95 = 34.65 -> 35. `or` (not nil-coalesce on 0) keeps explicit critChance=0 at 0,
	-- and never double-counts the 137 skills that already declare 5.
	activeSkill.skillData.CritChance = stats.critChance or data.misc.BaseCritChance
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
						-- @leb-regression-guard:nondamaging-ailment-stack-cap
						-- non-damaging (debuff) gap. See REGRESSION_GUARDS.md
						-- Validation provenance is retained in maintainer notes.
					local effectStackLimit = (activeGrantedEffect.baseFlags and activeGrantedEffect.baseFlags.ailment
						and stats and stats.maximum_stacks and stats.maximum_stacks > 0) and stats.maximum_stacks or nil
						t_insert(mod, { type = "GlobalEffect", effectType = "Debuff", effectStackVar = activeGrantedEffect.id.."Stack", effectStackLimit = effectStackLimit})
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
	-- @leb-regression-guard:no-spectre-library
	-- Upstream PoB had an empty `minionList` mean "user picks the minions", filling it from
	-- a build-level spectre library (`env.build.spectreList`). LE has no such mechanic: a
	-- skill's minions are fixed by its data, and every minionList in skills.json is non-empty.
	-- The library was never ported (`data.spectres` was never assigned), so that fallback was
	-- unreachable and would have thrown on `copyTable(nil)` had it ever been hit. Do not
	-- reintroduce a spectreList branch here; an empty minionList must stay an empty minionList.
	-- Spec: spec/System/TestNoSpectreLibrary_spec.lua
	local minionList
	if activeGrantedEffect.minionList then
		minionList = copyTable(activeGrantedEffect.minionList)
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
	-- @leb-regression-guard:granted-summon-pipeline
	-- A granted minion skill may REPLACE a base minion skill rather than add to it,
	-- so the granted skill becomes the minion's main / FullDPS skill. Two sources:
	--   * ExtraMinionSkill mods carrying a `replaces` field (tree-node grants);
	--   * the socket group's minionSkillGrant (SubSkillGrants summons, e.g. Spriggan
	--     Form Healing Totems cast Mystic Thorns / ThornTotemAttack instead of their
	--     default ButterflyHeal). Collect replaced base-skill ids first.
	-- Backward-compatible: no replaces / no minionSkillGrant -> behaviour unchanged.
	local extraMinionSkills = activeSkill.skillModList:List(activeSkill.skillCfg, "ExtraMinionSkill")
	local sgGrant = activeSkill.socketGroup and activeSkill.socketGroup.minionSkillGrant
	-- @leb-regression-guard:minion-grant-replacement-in-place
	-- A REPLACEMENT grant stands IN the replaced skill's base-kit position, so the
	-- pipeline's stated invariant ("the granted skill becomes the minion's main /
	-- FullDPS skill") holds structurally. Previously the replaced base skill was
	-- dropped and ALL grants were appended in one sorted pool -- correct only while
	-- the replacement was the sole grant. With an ADDITIVE grant co-present (e.g.
	-- Dragonflame Edict's any-minion Dragonflame Nova proc), an emptied base kit
	-- (Skeletal Mage + "Adds Pyromancers" replaces its only base skill) made index 1
	-- fall to the alphabetically-first grant: "DragonfireNova" < "Skeletal Mages
	-- Fire Projectile" -> the PROC became the mage's scored main and FullDPS x3
	-- (QqwprgdN probe). Now replacementFor maps replaced id -> grant id; the
	-- replacement is placed in-kit and only unplaced grants append (sorted).
	-- Spec: spec/System/TestDragonflameNovaGrant_spec.lua (ordering cases).
	local replacementFor = { }
	for _, skill in ipairs(extraMinionSkills) do
		if skill.replaces and (not skill.minionList or isValueInArray(skill.minionList, minion.type)) then
			replacementFor[skill.replaces] = replacementFor[skill.replaces] or skill.skillId
		end
	end
	if sgGrant and sgGrant.replaces then
		replacementFor[sgGrant.replaces] = replacementFor[sgGrant.replaces] or sgGrant.skillId
	end
	local placedGrants = { }
	local skillIdList = { }
	for _, skillId in ipairs(minionData.skillList) do
		local replacement = replacementFor[skillId]
		if replacement then
			-- the replacement grant takes the replaced skill's slot (once)
			if env.data.skills[replacement] and not placedGrants[replacement] then
				t_insert(skillIdList, replacement)
				placedGrants[replacement] = true
			end
		elseif env.data.skills[skillId] then
			t_insert(skillIdList, skillId)
		end
	end
	-- Non-replacement grants append AFTER the minion's base kit (so index 1 / the
	-- default selected skill stays the base attack), sorted by skillId:
	-- ExtraMinionSkill mods surface in modDB hash order, which is not
	-- deterministic across runs — unsorted, the minion-skill selector index
	-- and snapshot output would flap between runs. A grant whose `replaces`
	-- target is absent from this minion's kit still appends here (not lost).
	local extraSkillIds = { }
	for _, skill in ipairs(extraMinionSkills) do
		if (not skill.minionList or isValueInArray(skill.minionList, minion.type)) and not placedGrants[skill.skillId] then
			t_insert(extraSkillIds, skill.skillId)
		end
	end
	if sgGrant and sgGrant.skillId and env.data.skills[sgGrant.skillId] and not placedGrants[sgGrant.skillId] then
		t_insert(extraSkillIds, sgGrant.skillId)
	end
	table.sort(extraSkillIds)
	for _, skillId in ipairs(extraSkillIds) do
		t_insert(skillIdList, skillId)
	end
	if #skillIdList == 0 then
		-- Not ideal, but let's avoid crashes
		t_insert(skillIdList, "Default")
	end
	-- @leb-regression-guard:minion-granted-weapon-attack-base-inheritance
	-- A granted minion skill flagged `inheritsMinionAttackBase` (ModParser "bears use swipe") is a
	-- PLAYER weapon skill reused by the minion. In-game LE computes it off the MINION's basic-attack
	-- damage (the bear's weapon base ~50), NOT the player skill's tiny declared intrinsic (Swipe
	-- melee_base 2) + the player Swipe skill-tree. F4 minion-breakdown oracle (DoNotReleaseThem
	-- 2026-07-01): Swipe final 5139 ~= Melee final 5415 (the bear's basic attack); base-2 would be
	-- ~1/25 of Melee, and the player Swipe-tree MOREs (sw43-21/-13) do NOT apply (Swipe 5139 < Melee
	-- 5415 = no +23% boost). So build the granted skill from a CLONE of the minion's primary basic
	-- attack (base + the minion's base-kit damage profile), re-skinned with the granted skill's
	-- display name and a distinct non-player-skill id (so player SkillId:Swipe tree mods do NOT
	-- re-attach). SCOPE = opt-in flag ONLY: Manifest Armor's Charge/Whirlwind/ForgeBreath are
	-- minion-only skills with their own datamined bases (<see git log>), are NOT flagged, stay untouched.
	local inheritBaseSkills = { }
	for _, skill in ipairs(extraMinionSkills) do
		if skill.inheritsMinionAttackBase and (not skill.minionList or isValueInArray(skill.minionList, minion.type)) then
			inheritBaseSkills[skill.skillId] = skill
		end
	end
	local primaryAttackId, primaryAttackEff
	if next(inheritBaseSkills) then
		for _, sid in ipairs(minionData.skillList) do
			local ge = env.data.skills[sid]
			if ge and ge.baseFlags and ge.baseFlags.attack and ge.baseFlags.melee and not replacementFor[sid] then
				primaryAttackId = sid
				primaryAttackEff = (ge.stats and ge.stats.damageEffectiveness) or 1
				break
			end
		end
	end
	for _, skillId in ipairs(skillIdList) do
		local grantedEffect = env.data.skills[skillId]
		local grantSkill = inheritBaseSkills[skillId]
		if grantSkill and primaryAttackId and env.data.skills[primaryAttackId] then
			-- clone the minion's primary basic-attack profile, re-skin as this granted skill
			local orig = grantedEffect
			grantedEffect = copyTable(env.data.skills[primaryAttackId], true)
			grantedEffect.name = (orig and orig.name) or grantedEffect.name
			grantedEffect.id = skillId .. "_MinionWeaponBase"
			-- match-name = the distinct clone id so player SkillName:<orig> tree mods (the bear's
			-- "-60% Earthquake" node) do NOT re-attach (F4 oracle: they don't apply in-game).
			grantedEffect.skillNameForMatch = grantedEffect.id
		end
		local activeEffect = {
			grantedEffect = grantedEffect,
			level = 1,
			quality = 0,
		}
		local minionSkill = calcs.createActiveSkill(activeEffect, activeSkill.supportList, minion, nil, activeSkill)
		calcs.buildActiveSkillModList(env, minionSkill)
		-- @leb-regression-guard:minion-skill-redundant-attr-scaling
		-- Drop a minion ATTACK skill's own "increased Damage per player <Attr>"
		-- modifier when the parent summon already scales the minion's damage off
		-- the SAME player attribute (skills.json baked it onto both -> the
		-- actor="parent" PerStat resolve double-counts it). See
		-- LE_MINION_SKILL_REDUNDANT_ATTR_SCALING (Data/Global.lua) for the
		-- in-game-validated whitelist and the Dread Bolt 1832.7 capture.
		local redundantAttrs = LE_MINION_SKILL_REDUNDANT_ATTR_SCALING[skillId]
		if redundantAttrs then
			-- ModList stores its mods as a plain sequential array on itself.
			local sml = minionSkill.skillModList
			for i = #sml, 1, -1 do
				local mod = sml[i]
				if mod.name == "Damage" and (mod.type == "INC" or mod.type == "MORE") then
					for _, tag in ipairs(mod) do
						if tag.type == "PerStat" then
							local stat = tag.stat
							if not stat and tag.statList then stat = tag.statList[1] end
							if stat and redundantAttrs[stat] then
								t_remove(sml, i)
								break
							end
						end
					end
				end
			end
		end
		minionSkill.skillFlags.minion = true
		minionSkill.skillFlags.minionSkill = true
		minionSkill.skillFlags.haveMinion = true
		minionSkill.skillData.damageEffectiveness = 1 + (activeSkill.skillData.minionDamageEffectiveness or 0) / 100
		-- @leb-regression-guard:minion-granted-weapon-attack-base-inheritance
		-- A weapon-base clone whose granted skill hits at a higher added-damage-effectiveness
		-- than the minion's basic attack (bear Earthquake eff 6 vs Melee eff 1, datamine pid
		-- 261582) applies that ratio. In LE, effectiveness scales the whole weapon-base hit
		-- (base + added) before inc/more; LEB's damageEffectiveness (pinned to 1 above for
		-- minions) only scales ADDED, and baseMultiplier only scales the skill base, so neither
		-- alone reproduces a uniform x(eff). Since base*(1+inc)*more*k == base*k*(1+inc)*more, we
		-- apply the ratio as a single Hit-scoped MORE (ailments keep their own scaling). eff 6
		-- validated by the F4 oracle: bear EQ ref-slam == Melee-clone x 6.
		if grantSkill and grantSkill.minionAttackEffectiveness and primaryAttackEff and primaryAttackEff > 0 then
			local effRatio = grantSkill.minionAttackEffectiveness / primaryAttackEff
			if effRatio ~= 1 then
				minionSkill.skillModList:NewMod("Damage", "MORE", (effRatio - 1) * 100, "MinionWeaponAttackEffectiveness", ModFlag.Hit)
			end
		end
		-- @leb-regression-guard:minion-granted-weapon-attack-base-inheritance
		-- eq5s-21 "Seismic Tide": the granted skill's initial slam occurs THREE times (0.70/0.95/
		-- 1.30x, datamine tree_0.json, sum 2.95). The node's stat parses to the EarthquakeSeismicTide
		-- FLAG on the player modDB (env.modDB), which the clone's distinct id/name deliberately does
		-- NOT inherit (it drops the whole eq5s SkillId tree). So we detect the flag's existence
		-- directly on env.modDB (allocation => the mod bucket is non-empty; tag-independent) and,
		-- for the grant that declares it, fuse the 3 slams into one per-cast hit (Glacier-idiom:
		-- ref x 2.95). F4 oracle validated: bear EQ per-cast ~= Melee-clone x eff6 x 2.95 (-2.2%).
		if grantSkill and grantSkill.minionSlamNodeMod and grantSkill.minionSlamSum then
			local bucket = env.modDB.mods[grantSkill.minionSlamNodeMod]
			if bucket and #bucket > 0 and grantSkill.minionSlamSum ~= 1 then
				minionSkill.skillModList:NewMod("Damage", "MORE", (grantSkill.minionSlamSum - 1) * 100, "MinionEarthquakeSeismicTide", ModFlag.Hit)
			end
		end
		t_insert(minion.activeSkillList, minionSkill)
	end
	-- @leb-regression-guard:storm-totem-unmatched-storms-cadence
	-- Validation provenance is retained in maintainer notes.
	for _, fixed in ipairs(activeSkill.skillModList:List(activeSkill.skillCfg, "MinionFixedCastTime")) do
		if not fixed.minionList or isValueInArray(fixed.minionList, minion.type) then
			for _, ms in ipairs(minion.activeSkillList) do
				ms.skillData.timeOverride = fixed.time
			end
		end
	end
	-- @leb-regression-guard:thorn-totem-attack-ignores-cast-speed
	-- Validation provenance is retained in maintainer notes.
	local thornAttack = env.data.skills["ThornTotemAttack"]
	if thornAttack and thornAttack.castTime then
		for _, ms in ipairs(minion.activeSkillList) do
			local ge = ms.activeEffect and ms.activeEffect.grantedEffect
			if ge and ge.id == "ThornTotemAttack" and not ms.skillData.timeOverride then
				ms.skillData.timeOverride = thornAttack.castTime
			end
		end
	end
	-- @leb-regression-guard:minion-default-skill-index
	-- Most minions list their primary (basic) attack at skillList[1], so the
	-- unselected default is index 1. A few minions list a non-attack ability first
	-- (e.g. SummonedAbomination -> "Devour" consume spell at 1, "Melee Attack" at 2)
	-- and would default to a 0-DPS sub-skill, mis-reporting FullDPS. LE_MINION_
	-- DEFAULT_SKILL_INDEX (Data/Global.lua) overrides the unselected default per
	-- minion type to the in-game-validated DPS attack. A user's explicit selection
	-- (srcInstance.skillMinionSkill*) is stored/non-nil and still takes precedence.
	local defaultSkillIndex = LE_MINION_DEFAULT_SKILL_INDEX[minion.type] or 1
	local skillIndex
	if env.mode == "CALCS" then
		skillIndex = m_max(m_min(activeEffect.srcInstance.skillMinionSkillCalcs or defaultSkillIndex, #minion.activeSkillList), 1)
		activeEffect.srcInstance.skillMinionSkillCalcs = skillIndex
	else
		skillIndex = m_max(m_min(activeEffect.srcInstance.skillMinionSkill or defaultSkillIndex, #minion.activeSkillList), 1)
		if env.mode == "MAIN" then
			activeEffect.srcInstance.skillMinionSkill = skillIndex
		end
	end
	minion.mainSkill = minion.activeSkillList[skillIndex]
end
