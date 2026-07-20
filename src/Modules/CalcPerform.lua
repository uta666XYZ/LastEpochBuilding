-- Last Epoch Building
-- @leb-canary v1 / id:leb-d5b194-calcperform-2026 / do-not-remove (see Development/リリース手順.md)
--
-- Module: Calc Perform
-- Manages the offence/defence calculations.
--
local calcs = ...

local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max
local m_ceil = math.ceil
local m_floor = math.floor
local m_modf = math.modf
local s_format = string.format
local m_huge = math.huge
local bor = bit.bor
local band = bit.band

-- @leb-regression-guard: maxlife-maxmana-banker-round
-- See REGRESSION_GUARDS.md "maxlife-maxmana-banker-round".
-- Validation provenance is retained in maintainer notes.
local function bankerRound(x)
	local f = m_floor(x)
	local frac = x - f
	if frac < 0.5 then
		return f
	elseif frac > 0.5 then
		return f + 1
	else
		return (f % 2 == 0) and f or (f + 1)
	end
end

-- Merge an instance of a buff, taking the highest value of each modifier
local function mergeBuff(src, destTable, destKey)
	if not destTable[destKey] then
		destTable[destKey] = new("ModList")
	end
	local dest = destTable[destKey]
	for _, mod in ipairs(src) do
		local match = false
		if mod.type ~= "LIST" then
			for index, destMod in ipairs(dest) do
				if modLib.compareModParams(mod, destMod) then
					if type(destMod.value) == "number" and mod.value > destMod.value then
						dest[index] = mod
					end
					match = true
					break
				end
			end
		end
		if not match then
			t_insert(dest, mod)
		end
	end
end

local function doActorLifeMana(actor)
	local modDB = actor.modDB
	local output = actor.output
	local breakdown = actor.breakdown
	local condList = modDB.conditions

	local lowLifePerc = modDB:Sum("BASE", nil, "LowLifePercentage")
	output.LowLifePercentage = 100.0 * (lowLifePerc > 0 and lowLifePerc or data.misc.LowPoolThreshold)
	local fullLifePerc = modDB:Sum("BASE", nil, "FullLifePercentage")
	output.FullLifePercentage = 100.0 * (fullLifePerc > 0 and fullLifePerc or 1.0)

	local base = modDB:Sum("BASE", nil, "Life")
	local inc = modDB:Sum("INC", nil, "Life")
	local more = modDB:More(nil, "Life")
	-- @leb-regression-guard: maxlife-maxmana-banker-round
	-- LE finalizes maxHealth via Mathf.RoundToInt = banker's rounding (round half
	-- to even), NOT truncation. See the guard block near the top of this file and
	-- REGRESSION_GUARDS.md "maxlife-maxmana-banker-round". `.5`-at-even cases (e.g.
	-- 1572.5 -> 1572) round down and so coincide with floor, but non-`.5` fractions
	-- (e.g. ShutFackUp Mana 251.607 -> 252) diverge: banker matches in-game, floor
	-- does not.
	output.Life = m_max(bankerRound(base * (1 + inc/100) * more), 1)
	if breakdown then
		if inc ~= 0 or more ~= 1 then
			breakdown.Life = { }
			breakdown.Life[1] = s_format("%g ^8(base)", base)
			if inc ~= 0 then
				t_insert(breakdown.Life, s_format("x %.2f ^8(increased/reduced)", 1 + inc/100))
			end
			if more ~= 1 then
				t_insert(breakdown.Life, s_format("x %.2f ^8(more/less)", more))
			end
			t_insert(breakdown.Life, s_format("= %g", output.Life))
		end
	end
	-- @leb-regression-guard: maxlife-maxmana-banker-round (paired with output.Life above)
	output.Mana = bankerRound(calcLib.val(modDB, "Mana"))
	local base = modDB:Sum("BASE", nil, "Mana")
	local inc = modDB:Sum("INC", nil, "Mana")
	local more = modDB:More(nil, "Mana")
	if breakdown then
		if inc ~= 0 or more ~= 1 or manaConv ~= 0 then
			breakdown.Mana = { }
			breakdown.Mana[1] = s_format("%g ^8(base)", base)
			if inc ~= 0 then
				t_insert(breakdown.Mana, s_format("x %.2f ^8(increased/reduced)", 1 + inc/100))
			end
			if more ~= 1 then
				t_insert(breakdown.Mana, s_format("x %.2f ^8(more/less)", more))
			end
			t_insert(breakdown.Mana, s_format("= %g", output.Mana))
		end
	end
	-- @leb-regression-guard:mana-missing-not-full-mechanics
	-- Derive absolute output.MissingMana from Config "Your Missing Mana %"
	-- (Multiplier:MissingManaPercent) x max mana, so LE "per N missing mana" mods
	-- (e.g. Smite/Paladin) scale via a PerStat tag. This MUST be an idempotent
	-- output assignment, NOT an additive modDB:NewMod -- doActorLifeMana runs more
	-- than once per BuildOutput, so a NewMod would double-count (probe: 50% of
	-- 219 mana gave 220 instead of 110). The static planner models full mana by
	-- default (ModParser "per N current mana" guard), so this is 0 unless the
	-- user sets the missing-mana% config. Percent-based "per N% missing mana"
	-- reads the config multiplier directly. See ConfigOptions playerMissingManaPercent.
	output.MissingMana = bankerRound(output.Mana * modDB:Sum("BASE", nil, "Multiplier:MissingManaPercent") / 100)
	output.LowestOfMaximumLifeAndMaximumMana = m_min(output.Life, output.Mana)
	-- @leb-regression-guard:current-mana-damage-scaling
	-- Static planners have no live "current mana" (it fluctuates per cast), so
	-- "X% Damage per N current mana" mods (Excited Bolts / Flame Rush / Stygian
	-- Beam) model current mana as FULL mana == max Mana — the in-game dominant
	-- case (mana parked at the cap). PerStat:CurrentMana reads this field; without
	-- it GetStat returns 0 and the mod silently contributes nothing. See
	-- ModParser.lua "per (%d+) current mana" and REGRESSION_GUARDS.md.
	output.CurrentMana = output.Mana
end

-- Calculate attributes, and set conditions
---@param env table
---@param actor table
local function doActorAttribsConditions(env, actor)
	local modDB = actor.modDB
	local output = actor.output
	local breakdown = actor.breakdown
	local condList = modDB.conditions

	-- Set conditions
	if (actor.itemList["Weapon 2"] and actor.itemList["Weapon 2"].type == "Shield") or (actor == env.player and env.aegisModList) then
		condList["UsingShield"] = true
	end
	if not actor.itemList["Weapon 2"] then
		condList["OffHandIsEmpty"] = true
	end
	if actor.weaponData1.type == "None" then
		condList["Unarmed"] = true
		if not actor.itemList["Weapon 2"] and not actor.itemList["Gloves"] then
			condList["Unencumbered"] = true
		end
	else
		local info = env.data.weaponTypeInfo[actor.weaponData1.type]
		condList["Using"..info.flag] = true
		if info.melee then
			condList["UsingMeleeWeapon"] = true
		end
		if info.oneHand then
			condList["UsingOneHandedWeapon"] = true
		else
			condList["UsingTwoHandedWeapon"] = true
		end
	end
	local armourSlots = { "Helmet", "Body Armor", "Gloves", "Boots" }
	for _, slotName in ipairs(armourSlots) do
		if actor.itemList[slotName] then
			condList["Using"..slotName] = true
		end
	end
	if actor.weaponData2.type then
		local info = env.data.weaponTypeInfo[actor.weaponData2.type]
		condList["Using"..info.flag] = true
		if info.melee then
			condList["UsingMeleeWeapon"] = true
		end
		if info.oneHand then
			condList["UsingOneHandedWeapon"] = true
		else
			condList["UsingTwoHandedWeapon"] = true
		end
	end
	if actor.weaponData1.type and actor.weaponData2.type then
		condList["DualWielding"] = true
		if (env.data.weaponTypeInfo[actor.weaponData1.type].label or actor.weaponData1.type) ~= (env.data.weaponTypeInfo[actor.weaponData2.type].label or actor.weaponData2.type) then
			local info1 = env.data.weaponTypeInfo[actor.weaponData1.type]
			local info2 = env.data.weaponTypeInfo[actor.weaponData2.type]
			if info1.oneHand and info2.oneHand then
				condList["WieldingDifferentWeaponTypes"] = true
			end
		end
	end
	if env.mode_combat then
		if not modDB:Flag(env.player.mainSkill.skillCfg, "NeverCrit") then
			condList["CritInPast8Sec"] = true
		end
		if not actor.mainSkill.skillData.triggered and not actor.mainSkill.skillFlags.trap and not actor.mainSkill.skillFlags.mine and not actor.mainSkill.skillFlags.totem then
			if actor.mainSkill.skillFlags.attack then
				condList["AttackedRecently"] = true
			elseif actor.mainSkill.skillFlags.spell then
				condList["CastSpellRecently"] = true
			end
			if actor.mainSkill.skillTypes[SkillType.Movement] then
				condList["UsedMovementSkillRecently"] = true
			end
			if actor.mainSkill.skillFlags.minion and not actor.mainSkill.skillFlags.permanentMinion then
				condList["UsedMinionSkillRecently"] = true
			end
			if actor.mainSkill.skillTypes[SkillType.Vaal] then
				condList["UsedVaalSkillRecently"] = true
			end
			if actor.mainSkill.skillTypes[SkillType.Channel] then
				condList["Channelling"] = true
			end
		end
		-- Per-skill channelling flag (for "while channelling <skill>" affixes).
		-- Set whenever Channelling is true, either from mainSkill type above or via the
		-- Config tab "Are you Channelling?" toggle (which injects Condition:Channelling
		-- as a FLAG mod). GetCondition() checks both paths.
		if modDB:GetCondition("Channelling") then
			local skillName = actor.mainSkill.activeEffect and actor.mainSkill.activeEffect.grantedEffect and actor.mainSkill.activeEffect.grantedEffect.name
			if skillName then
				condList["Channelling" .. skillName:gsub("%s+", "")] = true
			end
		end
		if actor.mainSkill.skillFlags.hit and not actor.mainSkill.skillFlags.trap and not actor.mainSkill.skillFlags.mine and not actor.mainSkill.skillFlags.totem then
			condList["HitRecently"] = true
			if actor.mainSkill.skillFlags.spell then
				condList["HitSpellRecently"] = true
			end
		end
		if actor.mainSkill.skillFlags.totem then
			condList["HaveTotem"] = true
			condList["SummonedTotemRecently"] = true
			if actor.mainSkill.skillFlags.hit then
				condList["TotemsHitRecently"] = true
				if actor.mainSkill.skillFlags.spell then
					condList["TotemsSpellHitRecently"] = true
				end
			end
		end
		if actor.mainSkill.skillFlags.mine then
			condList["DetonatedMinesRecently"] = true
		end
		if actor.mainSkill.skillFlags.trap then
			condList["TriggeredTrapsRecently"] = true
		end
	end

	-- @leb-regression-guard: idol-altar-not-idol-slot
	-- StatThreshold tags resolve via ModStore:GetStat which reads
	-- actor.output[stat]. The corrupted-counter mods are emitted into modDB
	-- by CalcSetup (CorruptedItemsEquipped / CorruptedNonIdolItemsEquipped /
	-- CorruptedIdolItemsEquipped) but were never published to `output`, so
	-- `+N to All Attributes with at least N Corrupted [non-Idol/Idol] items
	-- equipped` (Shroud of Obscurity etc.) never tripped. Publish them BEFORE
	-- the Attributes loop so calcLib.val sees the threshold satisfied.
	-- Test: spec/System/TestModParse_spec.lua
	--       "Corrupted Idol Altar counts as non-Idol for
	--        CorruptedNonIdolItemsEquipped"
	-- Establishing reference: see git log
	output.CorruptedItemsEquipped = modDB:Sum("BASE", nil, "CorruptedItemsEquipped")
	output.CorruptedNonIdolItemsEquipped = modDB:Sum("BASE", nil, "CorruptedNonIdolItemsEquipped")
	output.CorruptedIdolItemsEquipped = modDB:Sum("BASE", nil, "CorruptedIdolItemsEquipped")

	-- @leb-regression-guard: set-bonus-breakdown-bridge
	-- env.itemModDB.setBreakdown (built in CalcSetup.applySetBonuses) MUST
	-- be bridged to actor.output so the CalcSections "Set Bonuses" row can
	-- gate via haveOutput="SetBreakdown". Skipping this bridge silently
	-- hides the entire section even when the data is fully populated. The
	-- companion guard "set-bonus-breakdown-publish" locks the producer side.
	-- Test: spec/System/TestSetBreakdown_spec.lua
	--       "applySetBonuses publishes setBreakdown with sets[] and bonuses"
	-- Establishing reference: see git log
	--
	-- env.itemModDB.setBreakdown contains { completeSetCount, wildcardCount,
	-- sets = { {name, pieceCount, setSize, complete, bonuses}... } }. Pure
	-- UI-side; no calc reads output.SetBreakdown.
	local setBreakdownData = env.itemModDB and env.itemModDB.setBreakdown
	if setBreakdownData and setBreakdownData.sets and #setBreakdownData.sets > 0 then
		output.SetBreakdown = #setBreakdownData.sets
		output.CompleteSetCount = setBreakdownData.completeSetCount
		if breakdown then
			local lines = {}
			if setBreakdownData.wildcardCount and setBreakdownData.wildcardCount > 0 then
				t_insert(lines, string.format("^7Wildcard items: %d", setBreakdownData.wildcardCount))
			end
			for _, s in ipairs(setBreakdownData.sets) do
				local marker = s.complete and (colorCodes.SET .. "* ") or "^7  "
				t_insert(lines, string.format("%s%s ^7(%d/%d)", marker, tostring(s.name), s.pieceCount, s.setSize))
				for _, b in ipairs(s.bonuses) do
					t_insert(lines, string.format("    ^8%dpc: ^7%s", b.tier, b.text))
				end
			end
			breakdown.SetBreakdown = lines
		end
	end

	output.TotalAttr = 0
	for _, stat in pairs(Attributes) do
		output[stat] = round(calcLib.val(modDB, stat))
		if breakdown then
			breakdown[stat] = breakdown.simple(nil, nil, output[stat], stat)
		end
		output.TotalAttr = output.TotalAttr + output[stat]
	end

	-- Cleaver Solution (Rusted Cleaver unique): "Your Intelligence is equal to your Strength"
	-- Overrides Int with the Str value; other Int sources are replaced, not added.
	if modDB:Flag(nil, "IntEqualsStr") then
		output.TotalAttr = output.TotalAttr - output.Int + output.Str
		output.Int = output.Str
		if breakdown then
			breakdown.Int = breakdown.simple(nil, nil, output.Int, "Int")
		end
	end

	-- Season 4 (1.4): attribute conversion
	-- First initialise S4 attributes from direct grants (passives/gear granting Guile, Brutality, etc.)
	-- Converted amount is then added on top, and subtracted from the source so PerStat bonuses don't double-count.
	local attrConversions = {
		{ src = "Str", dst = "Brutality", modName = "StrengthConvertedToBrutality" },
		{ src = "Dex", dst = "Guile",     modName = "DexterityConvertedToGuile" },
		{ src = "Int", dst = "Madness",   modName = "IntelligenceConvertedToMadness" },
		{ src = "Att", dst = "Apathy",    modName = "AttunementConvertedToApathy" },
		{ src = "Vit", dst = "Rampancy",  modName = "VitalityConvertedToRampancy" },
	}
	for _, conv in ipairs(attrConversions) do
		output[conv.dst] = round(calcLib.val(modDB, conv.dst))
		conv.directGrant = output[conv.dst]
	end
	for _, conv in ipairs(attrConversions) do
		local pct = modDB:Sum("BASE", nil, conv.modName)
		conv.convPct = pct or 0
		conv.convSrcValue = output[conv.src]
		if pct and pct > 0 then
			local converted = round(output[conv.src] * pct / 100)
			conv.convertedAmount = converted
			output[conv.dst] = output[conv.dst] + converted
			output[conv.src] = output[conv.src] - converted
		else
			conv.convertedAmount = 0
		end
	end
	-- @leb-regression-guard:s4-perstat-base-includes-converted-twin
	-- Validation provenance is retained in maintainer notes.
	output.RawStr = output.Str
	output.RawDex = output.Dex
	output.RawInt = output.Int
	output.RawAtt = output.Att
	output.RawVit = output.Vit
	-- Build breakdowns for converted attributes (Madness/Rampancy/Brutality/Guile/Apathy)
	-- so the Calcs tab tooltip explains the conversion contribution + direct grants.
	-- @leb-regression-guard:s4-converted-attr-source-breakdown
	-- A converted attribute (e.g. Brutality) draws its value from the SOURCE
	-- attribute it replaced (Str). The user must be able to see WHERE that value
	-- comes from, in the SAME per-source TABLE format every other attribute uses
	-- (Value / Notes / Source / Source Name, with item names, passive-node display
	-- names and equipment slots resolved). That per-source table is produced by the
	-- standard mod-section: CalcSections points the converted attribute's row at the
	-- SOURCE attribute's modName (`{ modName = <base attr> }`), so AddModSection
	-- tabulates Str's mods and resolves their sources — see guard
	-- `s4-converted-attr-table-from-source`. THIS block only adds the short textual
	-- summary that sits above that table (converted-from + direct grants + total),
	-- mirroring how a normal attribute shows breakdown.simple above its source
	-- table. It reads output/modDB but writes nothing to output, so it stays
	-- corpus-neutral (snapshots compare output, not breakdown text). Spec:
	--   spec/System/TestS4ConvertedAttrBreakdown_spec.lua
	if breakdown then
		for _, conv in ipairs(attrConversions) do
			if conv.convertedAmount ~= 0 or conv.directGrant ~= 0 then
				local lines = {}
				if conv.convertedAmount ~= 0 then
					if conv.convPct ~= 100 then
						t_insert(lines, s_format("%g ^8(%g%% of %s [%g] converted to %s)",
							conv.convertedAmount, conv.convPct, conv.src, conv.convSrcValue, conv.dst))
					else
						t_insert(lines, s_format("%g ^8(converted from %s)", conv.convertedAmount, conv.src))
					end
				end
				if conv.directGrant ~= 0 then
					t_insert(lines, s_format("+ %g ^8(direct grants of %s)", conv.directGrant, conv.dst))
				end
				-- Only add a total line when more than one component contributes,
				-- mirroring breakdown.simple (no redundant "= N" under a lone line).
				if #lines > 1 then
					t_insert(lines, s_format("= %g", output[conv.dst]))
				end
				if #lines > 0 then
					breakdown[conv.dst] = lines
				end
			end
		end
	end

	-- Capped PerStat bonuses (e.g. +2 Dodge Rating per 1 Int, up to +100)
	local evasionPerInt = modDB:Sum("BASE", nil, "EvasionPerInt")
	if evasionPerInt > 0 then
		local evasionPerIntCap = modDB:Sum("BASE", nil, "EvasionPerIntCap")
		if evasionPerIntCap == 0 then evasionPerIntCap = 100 end
		local bonus = math.min(output.Int * evasionPerInt, evasionPerIntCap)
		modDB:NewMod("Evasion", "BASE", bonus, "EvasionPerIntBonus")
	end

	doActorLifeMana(actor)
end

-- Process enemy modifiers and other buffs
local function doActorMisc(env, actor)
	local modDB = actor.modDB
	local enemyDB = actor.enemy.modDB
	local output = actor.output
	local condList = modDB.conditions

	-- Process enemy modifiers
	for _, value in ipairs(modDB:Tabulate(nil, nil, "EnemyModifier")) do
		enemyDB:AddMod(modLib.setSource(value.value.mod, value.value.mod.source or value.mod.source))
	end

	-- Add misc buffs/debuffs
	if env.mode_combat then
		if modDB:Flag(nil, "CanLeechLifeOnFullLife") then
			condList["Leeching"] = true
			condList["LeechingLife"] = true
		end
	end
end

function calcs.actionSpeedMod(actor)
	local modDB = actor.modDB
	local minimumActionSpeed = modDB:Max(nil, "MinimumActionSpeed") or 0
	local maximumActionSpeedReduction = modDB:Max(nil, "MaximumActionSpeedReduction")
	local actionSpeedMod = 1 + (m_max(-data.misc.TemporalChainsEffectCap, modDB:Sum("INC", nil, "TemporalChainsActionSpeed")) + modDB:Sum("INC", nil, "ActionSpeed")) / 100
	actionSpeedMod = m_max(minimumActionSpeed / 100, actionSpeedMod)
	if maximumActionSpeedReduction then
		actionSpeedMod = m_min((100 - maximumActionSpeedReduction) / 100, actionSpeedMod)
	end
	return actionSpeedMod
end

-- Finalises the environment and performs the stat calculations:
-- 1. Merges keystone modifiers
-- 2. Initialises minion skills
-- 3. Initialises the main skill's minion, if present
-- 4. Merges flask effects
-- 5. Sets conditions and calculates attributes (doActorAttribsConditions)
-- 6. Calculates life and mana (doActorLifeMana)
-- 6. Calculates reservations
-- 7. Sets life/mana reservation (doActorLifeManaReservation)
-- 8. Processes buffs and debuffs
-- 9. Processes charges and misc buffs (doActorCharges, doActorMisc)
-- 10. Calculates defence and offence stats (calcs.defence, calcs.offence)
function calcs.perform(env, fullDPSSkipEHP)
	local modDB = env.modDB
	local enemyDB = env.enemyDB

	local fullDPSSkipEHP = fullDPSSkipEHP or false

	-- Process ailment debuffs stack count
	-- @leb-regression-guard:nondamaging-ailment-stack-cap (consumer note)
	-- Each non-damaging-ailment applier's MaxStacks is summed into Multiplier:<id>Stack
	-- here; the per-ailment cap (Shock=10 etc.) is applied downstream when the debuff buff
	-- is consumed (buff.stackLimit, set from maximum_stacks in CalcActiveSkill ~L1187).
	-- The Spark Charge detonation participates like every Lightning hit (its Shock is no
	-- longer suppressed -- the cap makes the in-game-validated saturation match): in-game
	-- the detonation does apply Shock (capture: Shock instances after Spark Charge), and
	-- the enemy total saturates at the cap of 10 regardless of how many skills feed it.
	if env.mode ~= "CACHE" then
		for _, activeSkill in ipairs(env.player.activeSkillList) do
			if activeSkill.skillFlags.ailment and activeSkill.skillFlags.buffs then
				local uuid = cacheSkillUUID(activeSkill, env)
				local cache = GlobalCache.cachedData["CACHE"][uuid]
				if not GlobalCache.cachedData["CACHE"][uuid] then
					calcs.buildActiveSkill(env, "CACHE", activeSkill)
				end
				cache = GlobalCache.cachedData["CACHE"][uuid]
				local skillId = activeSkill.activeEffect.grantedEffect.id
				if cache.Env.player.output.MaxStacks > 0 then
					modDB:NewMod("Multiplier:" .. skillId .. "Stack", "BASE", cache.Env.player.output.MaxStacks)
				end
			end
		end
	end

	-- @leb-regression-guard:elemental-arrows-resource (consumer)
	-- Rogue/Marksman "Elemental Arrows" resource (game Property_Player_109-115). Bow attacks
	-- consume Elemental Arrows; each consumed arrow adds fire+lightning + increased-elemental
	-- (the "... with Elemental Arrow" / "... per Elemental Arrow used" tree stats, parsed to
	-- Multiplier:ElementalArrowConsumed in ModParser). Steady-state consumed = min(1 base +
	-- extra-per-attack, max cap) -- validated on AmHoA (save_20260703_031914) whose in-game
	-- lightning FLOOR already reflects the full 3-arrow consume (no 0-arrow cluster). A build
	-- lacking the mechanic has ElementalArrowMax == 0 and is untouched.
	if env.mode ~= "CACHE" then
		local maxArrows = modDB:Sum("BASE", nil, "ElementalArrowMax")
		local extraConsume = modDB:Sum("BASE", nil, "ElementalArrowExtraConsume")
		-- Mechanism present when the build shows any Elemental Arrows signal. The max-cap
		-- notScalingStat ("3 Maximum Elemental Arrows") parses via the ModParser bare-number
		-- rule; stale empty ModCache entries that shadowed it (and the +N-with-Elemental-Arrow
		-- added lines) were deleted. Keep the game base cap of 3 (Rogue-24 grants it alongside
		-- the resource) as a fallback for text variants that miss the max-cap parse.
		if maxArrows > 0 or extraConsume > 0 then
			local cap = (maxArrows > 0) and maxArrows or 3
			local consumed = m_min(1 + extraConsume, cap)
			modDB:NewMod("Multiplier:ElementalArrowConsumed", "BASE", consumed, "Elemental Arrows")
			-- The build sustains the resource, so the "with Elemental Arrow" Condition (x1
			-- increased-elemental bonus, Rogue-35) is active. Only the per-arrow ADDED scales
			-- by the Multiplier above; the increased applies once, matching the AmHoA in-game
			-- non-crit median (~10384) that x-consumed on the increased over-shot (~1.6x).
			modDB:NewMod("Condition:HaveElementalArrows", "FLAG", true, "Elemental Arrows")
		end
	end

	-- Build minion skills
	for _, activeSkill in ipairs(env.player.activeSkillList) do
		activeSkill.skillModList = new("ModList", activeSkill.baseSkillModList)
		if activeSkill.minion then
			activeSkill.minion.modDB = new("ModDB")
			activeSkill.minion.modDB.actor = activeSkill.minion
			calcs.createMinionSkills(env, activeSkill)
			activeSkill.skillPartName = activeSkill.minion.mainSkill.activeEffect.grantedEffect.name
		end
	end

	env.player.output = { }
	env.enemy.output = { }
	local output = env.player.output

	env.partyMembers = env.build.partyTab.actor
	env.player.partyMembers = env.partyMembers
	local partyTabEnableExportBuffs = env.build.partyTab.enableExportBuffs

	env.minion = env.player.mainSkill.minion
	if env.minion then
		-- Initialise minion modifier database
		output.Minion = { }
		env.minion.output = output.Minion
		env.minion.modDB.multipliers["Level"] = env.minion.level
		calcs.initModDB(env, env.minion.modDB)
		env.minion.modDB:NewMod("Life", "BASE", env.minion.minionData.life, "Base")
		env.minion.modDB:NewMod("Armour", "BASE", 0, "Base")
		env.minion.modDB:NewMod("Evasion", "BASE", 0, "Base")
		-- @leb-regression-guard:minion-crit-multiplier-base-2
		-- LE minion base crit multiplier is 2.0 with NO extra base bonus —
		-- the former `NewMod("CritMultiplier", "BASE", 30, ...)` was a PoB
		-- inheritance (PoE minions get +30% base crit multi; LE minions do
		-- not). Game source: datamined game source baseCritMulti=2 + every extracted bear
		-- ability prefab carries baseDamageStats.critMultiplier=2.0
		-- (datamined game source). In-game: VoidMaster
		-- Manifest Armor CM=2.0 with zero minion-crit affixes (2026-05-30) and
		-- DoNotReleaseThem PrimalBear CM=3.11 = 2.0 base + 1.00 (be36ar-17
		-- Unstoppable Force 4pts) + 0.11 (Ursine ring implicit roll) exactly;
		-- the old +30 made LEB report 2.41. Druid "Minion CM 2.3 vs sheet 2.0"
		-- (2026-06-10 batch) is the same artifact.
		env.minion.modDB:NewMod("CritDegenMultiplier", "BASE", 30, "Base")
		env.minion.modDB:NewMod("ProjectileCount", "BASE", 1, "Base")
		-- @leb-regression-guard:minion-level-more-scaling
		-- Validation provenance is retained in maintainer notes.
		local charLevel = env.build.characterLevel or 1
		-- @leb-regression-guard:minion-monster-actor-damage-scaling
		-- @leb-regression-guard:detonation-minion-no-inherent-damage-scaling
		-- is a per-minion bypass, not a global change. See REGRESSION_GUARDS.md.
		-- Validation provenance is retained in maintainer notes.
		local noInherentDamageScaling = env.minion.minionData.noInherentDamageScaling
		local monsterScaling = env.minion.minionData.monsterScaling
		if monsterScaling then
			local morePct = env.data.monsterDamageScaling.getMonsterDamageMorePercent(monsterScaling.fromLevel or 10, charLevel)
			if morePct ~= 0 then
				env.minion.modDB:NewMod("Damage", "MORE", morePct, "MonsterActorLevelScaling")
			end
		elseif charLevel > 26 and not noInherentDamageScaling then
			env.minion.modDB:NewMod("Damage", "MORE", 0.8 * (charLevel - 26), "MinionLevelScaling")
		end
		for _, mod in ipairs(env.minion.minionData.modList) do
			-- detonation minions skip their actor "Damage" MORE (see guard above);
			-- defensive/utility actor stats (DamageTaken, MovementSpeed, ...) still apply.
			if not (noInherentDamageScaling and mod.name == "Damage" and mod.type == "MORE") then
				env.minion.modDB:AddMod(mod)
			end
		end
		for _, mod in ipairs(env.player.mainSkill.extraSkillModList) do
			env.minion.modDB:AddMod(mod)
		end
		-- @leb-regression-guard:minion-skill-tree-mods-to-minion
		-- Validation provenance is retained in maintainer notes.
		do
			local parentId = env.player.mainSkill.activeEffect.grantedEffect
				and env.player.mainSkill.activeEffect.grantedEffect.id
			local inheritIds = { }
			for _, minionSkill in ipairs(env.minion.activeSkillList or { }) do
				local ge = minionSkill.activeEffect and minionSkill.activeEffect.grantedEffect
				if ge and ge.id ~= parentId and ge.treeId then
					inheritIds[ge.id] = true
				end
			end
			-- MinionModifier wrappers are routed by the dispatch below —
			-- transferring the wrapper too would leave a second, latent copy
			-- on the minion's own modDB. CooldownRecovery stays player-side:
			-- minion cast cadence is not cooldown-modeled (the granted skills
			-- use their castTime; see the bear-tree-grants-minion-skills guard
			-- in ModParser), and an unscoped tree CDR value (be36ar-12 "+40%
			-- Swipe Cooldown Recovery Speed" x3 bakes as a bare CooldownRecovery
			-- BASE 120) collapses a castTime-based minion skill's Speed to
			-- 1/120s if it lands on the minion's modDB.
			local skipNames = { ExtraSkill = true, ExtraMinionSkill = true, SkillLevel = true, MinionModifier = true, CooldownRecovery = true }
			for _, modList in pairs(env.modDB.mods) do
				for _, mod in ipairs(modList) do
					if not skipNames[mod.name] and type(mod.source) == "string" and mod.source:match("^Tree:") then
						local skillIdTag
						for _, tag in ipairs(mod) do
							if tag.type == "SkillId" then
								skillIdTag = tag.skillId
								break
							end
						end
						if skillIdTag and (skillIdTag == parentId or inheritIds[skillIdTag]) then
							local newMod = copyTable(mod)
							for i = #newMod, 1, -1 do
								local tag = newMod[i]
								if tag.type == "SkillId" and skillIdTag == parentId then
									t_remove(newMod, i)
								elseif tag.type == "PerStat" and not tag.actor then
									tag.actor = "parent"
								end
							end
							env.minion.modDB:AddMod(newMod)
						end
					end
				end
			end
		end
		-- @leb-regression-guard:manifest-armor-weapon-stats-copy
		-- Validation provenance is retained in maintainer notes.
		if env.minion and env.minion.type == "ManifestedArmor" then
			local copySlots = { }
			if env.allocNodes["ma6hdr-26"] then
				t_insert(copySlots, { slot = "Weapon 1", mult = 1 })
			end
			if env.allocNodes["ma6hdr-4"] then
				local w2 = env.player.itemList and env.player.itemList["Weapon 2"]
				if w2 and w2.base and w2.base.type == "Shield" then
					t_insert(copySlots, { slot = "Weapon 2", mult = 1 })
				end
			end
			-- @leb-regression-guard:manifest-armor-armor-slot-copy
			-- The armour-slot copy is Manifest Armor's BASE KIT (no node needed):
			-- GetArmourStats admits Helmet/Body/Gloves/Boots unless an ignore flag
			-- (0x118-0x11B, no known source) is set, and GetValueMultiplier
			-- (datamined offset) scales each slot's stat VALUES by
			--   1 + increasedGearStats(0x13C, no known source)
			--     + per-slot node term + slot-pair extra (0x12C/0x138, no known source)
			-- Per-slot nodes (ManifestArmorTree per-point tooltip values):
			--   ma6hdr-1  Platemail     +40%/pt (chest,  baseType 1, 0x128)
			--   ma6hdr-9  Great Helm    +60%/pt (helmet, baseType 0, 0x124)
			--   ma6hdr-16 Steel Greaves +60%/pt (boots,  baseType 3, 0x130)
			--   ma6hdr-21 Iron Grasp    +60%/pt (gloves, baseType 4, 0x134)
			-- CAUTION: tooltip-vs-DAT mismatch is a proven MA failure mode
			-- (Redistributed Steel tooltip 15 = engine 7, see
			-- manifest-armor-redistributed-steel-7pct); the gloves multiplier is the
			-- one validated axis (attack-speed cadence, see spec), the other three
			-- ride the tooltip values until a per-slot measurement exists.
			-- The multiplier scales the copied mod VALUE (engine scales Stat.value),
			-- flat and percentage stats alike.
			for _, def in ipairs({
				{ slot = "Helmet",     node = "ma6hdr-9",  perPoint = 0.60 },
				{ slot = "Body Armor", node = "ma6hdr-1",  perPoint = 0.40 },
				{ slot = "Boots",      node = "ma6hdr-16", perPoint = 0.60 },
				{ slot = "Gloves",     node = "ma6hdr-21", perPoint = 0.60 },
			}) do
				local node = env.allocNodes[def.node]
				t_insert(copySlots, { slot = def.slot, mult = 1 + (node and (node.alloc or 0) or 0) * def.perPoint })
			end
			-- @leb-regression-guard:manifest-armor-lambent-metal
			-- Lambent Metal (ma6hdr-6, maxPoints 1, "increased effect for health
			-- regeneration from all items that affect Manifest Armor"):
			-- GetPropertySpecificMultiplier (datamined offset) applies
			-- 1 + increasedHealthRegenFromItems(0x140) to property 17 (flat
			-- "Health Regenerated Per Second") stats ONLY, on top of the slot
			-- multiplier. LEB: copied LifeRegen BASE mods get the extra x1.5.
			-- datamining; no dedicated capture. Tooltip 50%/pt.
			local lambent = env.allocNodes["ma6hdr-6"]
			local regenMult = 1 + (lambent and (lambent.alloc or 0) or 0) * 0.50
			for _, entry in ipairs(copySlots) do
				local item = env.player.itemList and env.player.itemList[entry.slot]
				for _, mod in ipairs(item and item.modList or { }) do
					if (mod.type == "BASE" or mod.type == "INC" or mod.type == "MORE") and type(mod.value) == "number" then
						local newMod = copyTable(mod)
						newMod.value = mod.value * entry.mult
						if mod.name == "LifeRegen" and mod.type == "BASE" then
							newMod.value = newMod.value * regenMult
						end
						newMod.source = "ManifestArmorGearCopy:" .. entry.slot
						env.minion.modDB:AddMod(newMod)
					end
				end
			end
			-- @leb-regression-guard:manifest-armor-force-of-impact
			-- Force of Impact (ma6hdr-2, maxPoints 1, "melee physical damage equal
			-- to a proportion of the armour on your body armour"): the engine walks
			-- the CHEST item's FLAT-armour stat entries and adds
			-- value x meleePhysicalDamagePerArmourOnChest(0x144) as melee physical
			-- (ManifestArmorMutator.c L1845: per-mod getValue x 0x144 -> new
			-- Stats.Stat, chest baseType gate) -- tooltip "1 Melee Physical Damage
			-- per 10 Armor On Chest" -> 0.1/pt. FLAT armour entries only: the
			-- item's own "% increased Armor" lines are a different property and do
			-- NOT feed this. No slot multiplier (the Stat is constructed outside
			-- the GetValueMultiplier path). datamining; no dedicated capture
			-- (VoidMaster does not take ma6hdr-2).
			local foi = env.allocNodes["ma6hdr-2"]
			if foi then
				local chest = env.player.itemList and env.player.itemList["Body Armor"]
				local flatArmour = 0
				for _, mod in ipairs(chest and chest.modList or { }) do
					if mod.name == "Armour" and mod.type == "BASE" and type(mod.value) == "number" then
						flatArmour = flatArmour + mod.value
					end
				end
				if flatArmour > 0 then
					env.minion.modDB:NewMod("PhysicalDamage", "BASE", flatArmour * 0.1 * (foi.alloc or 1), "ManifestArmorForceOfImpact", 0, KeywordFlag.Melee)
				end
			end
		end
		-- @leb-regression-guard:weapon-attack-minion-weapon-inheritance
		-- Validation provenance is retained in maintainer notes.
		if env.minion then
			-- Gate on the in-game-VALIDATED whitelist (Data/Global.lua LE_WEAPON_ATTACK_MINIONS):
			-- the qualifying-skill check below is necessary but NOT sufficient -- more than one
			-- minion grants a bow attack (e.g. SummonedSkeletonArcher's "Summon Skeleton Archer
			-- Bow Attack"), and only RogueBallista is validated to fire the player's bow. Without
			-- this whitelist, Skeleton-Archer-with-bow builds would silently inherit the player's
			-- bow damage unvalidated. The registry's `weapon` must match the equipped weapon type.
			local weaponAttackMinion = LE_WEAPON_ATTACK_MINIONS[env.minion.type]
			local weaponData = env.player.weaponData1
			-- Map the validated equipped weapon's source to its damage-source keyword bit. Only Bow
			-- (Falconer Ballista) is in-game-validated; extending to other weapon-attack minions
			-- requires its own capture + a registry entry + a mapping here.
			local weaponKeyword = weaponAttackMinion and weaponData
				and weaponData.type == weaponAttackMinion.weapon
				and weaponData.type == "Bow" and ModFlag.Bow or nil
			if weaponKeyword then
				-- Qualify: the minion grants a weapon ATTACK whose weapon-source tag matches
				-- the equipped weapon (here: a Bow attack, e.g. BallistaBolt).
				local isWeaponAttackMinion = false
				for _, minionSkill in ipairs(env.minion.activeSkillList or { }) do
					local ge = minionSkill.activeEffect and minionSkill.activeEffect.grantedEffect
					if ge and ge.fromMinion and ge.baseFlags and ge.baseFlags.attack
						and ge.skillTypeTags and band(ge.skillTypeTags, weaponKeyword) ~= 0 then
						isWeaponAttackMinion = true
						break
					end
				end
				if isWeaponAttackMinion then
					-- LE flat added damage is a single <Type>Damage BASE (no min/max range);
					-- "Damage" is the typeless/generic weapon add. INC/MORE of the same names
					-- carry the keyword too ("increased Bow <Type> Damage").
					local inheritNames = { Damage = true, PhysicalDamage = true, FireDamage = true,
						ColdDamage = true, LightningDamage = true, NecroticDamage = true,
						PoisonDamage = true, VoidDamage = true }
					for _, modList in pairs(env.modDB.mods) do
						for _, mod in ipairs(modList) do
							if inheritNames[mod.name] and mod.keywordFlags
								and band(mod.keywordFlags, weaponKeyword) ~= 0 then
								env.minion.modDB:AddMod(copyTable(mod))
							end
						end
					end
				end
			end
		end
		-- @leb-regression-guard:falcon-avian-hurl-conversion
		-- Avian Hurl (Rogue-90, Falconer, 6pts) grants the Falcon added Throwing AND
		-- Melee damage equal to N% (fixed 50%) of the PLAYER's added throwing flat.
		-- datamining field `falconAddedThrowingAndMeleeDamagePercentageFromPlayerThrowingDamage`
		-- (AbilityStatsMutatorManager bucket 0x2d7) -- EHG's tree text "Conversion To
		-- Falcon" is a GRANT/transfer, NOT an LE damage-TYPE conversion. Structurally the
		-- same PLAYER-modDB -> MINION-modDB per-type copy as the weapon-attack inheritance
		-- above, with three differences:
		--   * source keyword = Throwing (the player's added-throwing flats), not the weapon's Bow;
		--   * value scaled by pct/100 (0.5);
		--   * output re-tagged Melee|Throwing so BOTH the Falcon's melee (Aerial Assault)
		--     and throwing (Feather Knives) skills receive it -- the field grants "Throwing
		--     AND Melee". Falcon per-Dex adds are tag-specific; this transfer is not.
		-- Only FLAT ADDED damage transfers (Damage / <Type>Damage BASE); the player's
		-- INC/MORE throwing is the player's own scaling and stays behind (the mechanic is an
		-- "Added ... Damage ... From Player Throwing Damage" transfer). The "added flat vs
		-- total throwing" read is INFERRED (the consumer multiply-site is absent from the
		-- datamining subset; the field name + the crit-inheritance sibling favour added-flat)
		-- -- if a future capture with player-added-throwing contradicts this, revisit here.
		-- Independent of the per-Dex adds (Dex source vs added-throwing source are disjoint
		-- pools -> no double count). Corpus-neutral where the player has no added throwing
		-- flat (Rem-MK3: 0 -> inert). Spec: spec/System/TestFalconAvianHurl_spec.lua
		if env.minion and env.minion.type == "RogueFalcon" then
			local conversionPct = env.modDB:Sum("BASE", nil, "FalconAddedThrowingConversion")
			if conversionPct > 0 then
				local frac = conversionPct / 100
				local falconTags = bor(KeywordFlag.Melee, KeywordFlag.Throwing)
				local addedNames = { Damage = true, PhysicalDamage = true, FireDamage = true,
					ColdDamage = true, LightningDamage = true, NecroticDamage = true,
					PoisonDamage = true, VoidDamage = true }
				for _, modList in pairs(env.modDB.mods) do
					for _, srcMod in ipairs(modList) do
						if addedNames[srcMod.name] and srcMod.type == "BASE" and srcMod.keywordFlags
							and band(srcMod.keywordFlags, KeywordFlag.Throwing) ~= 0 then
							local copy = copyTable(srcMod)
							copy.value = srcMod.value * frac
							copy.keywordFlags = falconTags
							env.minion.modDB:AddMod(copy)
						end
					end
				end
			end
		end
		-- @leb-regression-guard:falcon-avian-arsenal-buff
		-- Validation provenance is retained in maintainer notes.
		if env.minion and env.minion.type == "RogueFalcon" then
			local arsenalPct = env.modDB:Sum("BASE", nil, "FalconAvianArsenalPercent")
			local arsenalPoolKw = env.modDB:Sum("BASE", nil, "FalconAvianArsenalPoolKeyword")
			if arsenalPct > 0 and arsenalPoolKw > 0 then
				local frac = arsenalPct / 100
				local addedNames = { Damage = true, PhysicalDamage = true, FireDamage = true,
					ColdDamage = true, LightningDamage = true, NecroticDamage = true,
					PoisonDamage = true, VoidDamage = true }
				for _, modList in pairs(env.modDB.mods) do
					for _, srcMod in ipairs(modList) do
						if addedNames[srcMod.name] and srcMod.type == "BASE" and srcMod.keywordFlags
							and band(srcMod.keywordFlags, arsenalPoolKw) ~= 0 then
							local copy = copyTable(srcMod)
							copy.value = srcMod.value * frac
							copy.keywordFlags = KeywordFlag.Melee
							env.minion.modDB:AddMod(copy)
						end
					end
				end
			end
		end
		-- @leb-regression-guard:upheaval-totem-grant
		-- PLAYER GLOBAL ADDED-FLAT -> totem-cast minion (Upheaval Totem, uph41-30).
		-- The Upheaval Totem casts the player's Upheaval (SubSkillGrants, node-gated).
		-- In-game the UpheavalTotemAdapter copies the player's stat fields onto the totem,
		-- so the totem hit deals the player's GLOBAL gear added-flat (e.g. Apiarist's Comb
		-- generic "+42 Damage") in addition to its own base + minion-damage gear. Without
		-- this the totem nc was 428 vs capture 3686 (x8.6 under) -- the ENTIRE residual is
		-- the missing player added-flat (decompose: minion base ~12 vs player ~86; the
		-- minion INC 1180% is already correct = inherited player Upheaval INC via the
		-- treeId inheritIds channel above + minion-damage gear, do NOT touch it).
		-- This copies, from the PLAYER modDB onto the MINION modDB, ONLY the player's
		-- BASE added-flat <Type>Damage that is GLOBAL (no SkillId/SkillName tag) and not
		-- Tree-sourced, and that PASSES the granted skill's delivery flags. It is gated
		-- exactly like the weapon-attack channel above and inherits its discipline:
		--   * MINION modDB ONLY -> the player hit-loop is byte-identical; zero ripple.
		--   * BASE ONLY, never INC/MORE -> INC already flows via inheritIds + minion gear;
		--     copying INC/MORE would double-count and overshoot (validated arithmetic:
		--     base 86 x INC 1233% x MORE 3.21 = 3,680 ~= capture 3,686).
		--   * GLOBAL flats only -> SkillId/SkillName-scoped player flats are excluded
		--     (Upheaval-tree flats already route via the inheritIds channel; other-skill
		--     flats must not fold in). Tree: sources are likewise owned by that channel.
		--   * DELIVERY-FLAG GATED -> a "+X Spell Damage" / wrong-weapon flat fails the
		--     granted skill's cfg flags and is skipped (no blanket fold; the abandoned
		--     melee fix <see git log> over-folded untyped physical for +16.7% ShutFackUp --
		--     this cannot, being minion-only + flag-gated + opt-in per minion type).
		--   * WHITELIST (Data/Global.lua LE_PLAYER_ADDED_FLAT_MINIONS) keyed by minion
		--     type -> opt-in; no other summon/minion/build is affected.
		-- Spec: spec/System/TestUpheavalTotemGrant_spec.lua.
		do
			local addedFlatReg = LE_PLAYER_ADDED_FLAT_MINIONS[env.minion.type]
			if addedFlatReg then
				local grantSkill
				for _, minionSkill in ipairs(env.minion.activeSkillList or { }) do
					local ge = minionSkill.activeEffect and minionSkill.activeEffect.grantedEffect
					if ge and ge.id == addedFlatReg.skill then
						grantSkill = minionSkill
						break
					end
				end
				if grantSkill then
					local cfg = grantSkill.skillCfg
					local cfgFlags = (cfg and cfg.flags) or 0
					local cfgKw = (cfg and cfg.keywordFlags) or 0
					local inheritNames = { Damage = true, PhysicalDamage = true, FireDamage = true,
						ColdDamage = true, LightningDamage = true, NecroticDamage = true,
						PoisonDamage = true, VoidDamage = true }
					for _, modList in pairs(env.modDB.mods) do
						for _, mod in ipairs(modList) do
							if mod.type == "BASE" and inheritNames[mod.name]
								and band(cfgFlags, mod.flags) == mod.flags
								and MatchKeywordFlags(cfgKw, mod.keywordFlags) then
								local skillScoped = false
								for _, tag in ipairs(mod) do
									if tag.type == "SkillId" or tag.type == "SkillName" then
										skillScoped = true
										break
									end
								end
								local src = type(mod.source) == "string" and mod.source or ""
								if not skillScoped and not src:match("^Tree:") then
									env.minion.modDB:AddMod(copyTable(mod))
								end
							end
						end
					end
				end
			end
		end
	end

	for _, activeSkill in ipairs(env.player.activeSkillList) do
		if activeSkill.skillData.triggeredOnDeath and not activeSkill.skillFlags.minion then
			activeSkill.skillData.triggered = true
			for _, value in ipairs(activeSkill.skillModList:Tabulate("INC", env.player.mainSkill.skillCfg, "TriggeredDamage")) do
				activeSkill.skillModList:NewMod("Damage", "INC", value.mod.value, value.mod.source, value.mod.flags, value.mod.keywordFlags, unpack(value.mod))
			end
			for _, value in ipairs(activeSkill.skillModList:Tabulate("MORE", env.player.mainSkill.skillCfg, "TriggeredDamage")) do
				activeSkill.skillModList:NewMod("Damage", "MORE", value.mod.value, value.mod.source, value.mod.flags, value.mod.keywordFlags, unpack(value.mod))
			end
			-- Set trigger time to 1 min in ms ( == 6000 ). Technically any large value would do.
			activeSkill.skillData.triggerTime = 60 * 1000
		end
	end

	local breakdown = nil
	if env.mode == "CALCS" then
		-- Initialise breakdown module
		breakdown = LoadModule(calcs.breakdownModule, modDB, output, env.player)
		env.player.breakdown = breakdown
		if env.minion then
			env.minion.breakdown = LoadModule(calcs.breakdownModule, env.minion.modDB, env.minion.output, env.minion)
		end
	end

	-- Calculate attributes and life/mana pools
	doActorAttribsConditions(env, env.player)
	doActorLifeMana(env.player)
	if env.minion then
		for _, value in ipairs(env.player.mainSkill.skillModList:List(env.player.mainSkill.skillCfg, "MinionModifier")) do
			-- @leb-regression-guard:minion-modifier-multi-type-gate
			-- Dispatch matches when:
			--   (1) no type/minionTypes filter → applies to all minions, OR
			--   (2) value.type matches env.minion.type, OR
			--   (3) value.minionTypes is a non-empty array containing env.minion.type
			-- Path (3) supports "for Skeletons" idol/item affixes (prefix 313 in
			-- src/Data/ModItem_1_4.json) that should hit multiple minion-family
			-- members (SummonedSkeleton + Archer/Harvester/Vanguard/Rogue) with a
			-- single MinionModifier mod. Before this guard the bare CritChance
			-- parse leaked the +N% onto the PLAYER's crit chance instead of any
			-- minion. Mirror site below in this file (~line 1164) must stay in sync.
			local pass = (not value.type and not value.minionTypes)
				or (value.type and env.minion.type == value.type)
			if not pass and value.minionTypes then
				for _, mt in ipairs(value.minionTypes) do
					if env.minion.type == mt then pass = true; break end
				end
			end
			if pass then
				-- @leb-regression-guard:minion-modifier-perstat-parent-actor
				-- LE minions don't carry primary attributes (Vit/Str/Dex/
				-- Int/Att) of their own — those stats live on the player.
				-- Tree passives like Acolyte-59's `notScalingStats`
				--   "2% Increased Minion Armor Per Intelligence"
				-- parse as a MinionModifier whose inner mod carries a
				-- PerStat:Int tag. When the inner mod lands on
				-- env.minion.modDB and ModStore L398 resolves PerStat,
				-- `target = self` defaults to minion.modDB and
				-- GetStat("Int") returns 0, zeroing the 86% INC that
				-- LETools shows for <private build> lv99 Necromancer (player
				-- Int=43, 2% × 43 = 86%).
				--
				-- Inject `actor = "parent"` on PerStat tags that target
				-- a primary attribute and don't already carry an explicit
				-- actor binding, so the resolve routes through
				-- minion.actor.parent.modDB (= env.player.modDB) and
				-- LE's "Per <Attr>" wording matches game semantics.
				--
				-- Copy the mod (and the affected tags) before mutating
				-- so shared references in skillModList stay clean across
				-- minions and re-runs.
				local injected = value.mod
				local copied = false
				local buffSwap = nil -- { tagIndex, condVar } when SkillId→ActorCondition swap is needed
				for ti, tag in ipairs(value.mod) do
					if tag.type == "PerStat" and not tag.actor then
						local routeToParent = false
						if tag.stat and LE_MINION_PERSTAT_PARENT_ATTRS[tag.stat] then
							routeToParent = true
						elseif tag.statList then
							for _, s in ipairs(tag.statList) do
								if LE_MINION_PERSTAT_PARENT_ATTRS[s] then
									routeToParent = true
									break
								end
							end
						end
						if routeToParent then
							if not copied then
								injected = copyTable(value.mod, true)
								copied = true
							end
							injected[ti] = copyTable(tag)
							injected[ti].actor = "parent"
						end
					end
					-- @leb-regression-guard:minions-have-dread-shade-buff-gating
					-- Detect SkillId tags belonging to buff-skills whose
					-- effect lives on a per-target Buff Component in-game
					-- (e.g. Dread Shade's DreadShadeMutator.auraStats,
					-- datamined game source). In LE the contribution is
					-- conditioned on whether the *individual minion*
					-- actually carries the buff Component, not on which
					-- skill the calc is currently scoped to. ModStore.lua
					-- L750-753, however, treats SkillId tags as a hard
					-- "only resolve when calc cfg matches this skill"
					-- filter, which silently zeroes Martyrdom's
					-- "30 Minion Armour per Vitality" on every minion
					-- because the minion-side calc cfg isn't scoped to
					-- DreadShade. Replacing the SkillId tag in-place with
					-- an ActorCondition tag (actor="parent") routes the
					-- gating through the player's modDB Condition flag —
					-- which is closer to LE's Buff Component model and
					-- exposes the contribution as a togglable row in the
					-- minion breakdown. Default OFF → existing snapshots
					-- unchanged.
					if tag.type == "SkillId" and tag.skillId and LE_MINION_BUFF_SKILL_TO_CONDITION[tag.skillId] then
						buffSwap = { ti = ti, condVar = LE_MINION_BUFF_SKILL_TO_CONDITION[tag.skillId] }
					end
				end
				if buffSwap then
					if not copied then
						injected = copyTable(value.mod, true)
						copied = true
					end
					injected[buffSwap.ti] = { type = "ActorCondition", actor = "parent", var = buffSwap.condVar }
				end
				env.minion.modDB:AddMod(injected)
			end
		end
		for _, name in ipairs(env.minion.modDB:List(nil, "Keystone")) do
			if env.spec.tree.keystoneMap[name] then
				env.minion.modDB:AddList(env.spec.tree.keystoneMap[name].modList)
			end
		end
		doActorAttribsConditions(env, env.minion)
	end

	-- Process attribute requirements
	do
		local reqMult = calcLib.mod(modDB, nil, "GlobalAttributeRequirements")
		for _, attr in ipairs(Attributes) do
			local breakdownAttr = attr
			if breakdown then
				breakdown["Req"..attr] = {
					rowList = { },
					colList = {
						{ label = attr, key = "req" },
						{ label = "Source", key = "source" },
						{ label = "Source Name", key = "sourceName" },
					}
				}
			end
			local out = 0
			for _, reqSource in ipairs(env.requirementsTable) do
				if reqSource[attr] and reqSource[attr] > 0 then
					local req = m_floor(reqSource[attr] * reqMult)
					out = m_max(out, req)
					if breakdown then
						local row = {
							req = req > output[breakdownAttr] and colorCodes.NEGATIVE..req or req,
							reqNum = req,
							source = reqSource.source,
						}
						if reqSource.source == "Item" then
							local item = reqSource.sourceItem
							row.sourceName = colorCodes[item.rarity]..item.name
							row.sourceNameTooltip = function(tooltip)
								env.build.itemsTab:AddItemTooltip(tooltip, item, reqSource.sourceSlot)
							end
						end
						t_insert(breakdown["Req"..breakdownAttr].rowList, row)
					end
				end
			end
			if modDB:Flag(nil, "IgnoreAttributeRequirements") then
				out = 0
			end
			output["Req"..attr.."String"] = 0
			if out > (output["Req"..breakdownAttr] or 0) then
				output["Req"..breakdownAttr.."String"] = out
				output["Req"..breakdownAttr] = out
				if breakdown then
					output["Req"..breakdownAttr.."String"] = out > (output[breakdownAttr] or 0) and colorCodes.NEGATIVE..out or out
				end
			end
		end
	end

	-- Calculate number of active auras affecting self
	if env.mode_buffs then
		local auraList = { }
		for _, activeSkill in ipairs(env.player.activeSkillList) do
			if activeSkill.skillTypes[SkillType.Aura] and not activeSkill.skillTypes[SkillType.AuraAffectsEnemies] and not activeSkill.skillData.auraCannotAffectSelf and not auraList[activeSkill.skillCfg.skillName] then
				auraList[activeSkill.skillCfg.skillName] = true
				modDB.multipliers["AuraAffectingSelf"] = (modDB.multipliers["AuraAffectingSelf"] or 0) + 1
			end
		end
	end

	-- Combine buffs/debuffs
	local buffs = { }
	env.buffs = buffs
	local guards = { }
	local minionBuffs = { }
	env.minionBuffs = minionBuffs
	local debuffs = { }
	env.debuffs = debuffs
	local curses = { }
	local minionCurses = {
		limit = 1,
	}
	local allyBuffs = env.partyMembers["Aura"]
	local buffExports = { Aura = {}, Curse = {}, Link = {}, EnemyMods = {}, EnemyConditions = {}, PlayerMods = {} }
	for _, activeSkill in ipairs(env.player.activeSkillList) do
		local skillModList = activeSkill.skillModList
		local skillCfg = activeSkill.skillCfg
		for _, buff in ipairs(activeSkill.buffList) do
			if buff.cond and not skillModList:GetCondition(buff.cond, skillCfg) then
				-- Nothing!
			elseif buff.enemyCond and not enemyDB:GetCondition(buff.enemyCond) then
				-- Also nothing :/
			elseif buff.type == "Buff" then
				if env.mode_buffs and (not activeSkill.skillFlags.totem or buff.allowTotemBuff) then
					local skillCfg = buff.activeSkillBuff and skillCfg
					local modStore = buff.activeSkillBuff and skillModList or modDB
				 	if not buff.applyNotPlayer then
						activeSkill.buffSkill = true
						modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
						local srcList = new("ModList")
						local inc = modStore:Sum("INC", skillCfg, "BuffEffect", "BuffEffectOnSelf", "BuffEffectOnPlayer") + skillModList:Sum("INC", skillCfg, buff.name:gsub(" ", "").."Effect")
						local more = modStore:More(skillCfg, "BuffEffect", "BuffEffectOnSelf")
						srcList:ScaleAddList(buff.modList, (1 + inc / 100) * more)
						mergeBuff(srcList, buffs, buff.name)
						if activeSkill.skillData.thisIsNotABuff then
							buffs[buff.name].notBuff = true
						end
					end
					if env.minion and (buff.applyMinions or buff.applyAllies or skillModList:Flag(nil, "BuffAppliesToAllies")) then
						activeSkill.minionBuffSkill = true
						env.minion.modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
						local srcList = new("ModList")
						local inc = modStore:Sum("INC", skillCfg, "BuffEffect") + env.minion.modDB:Sum("INC", nil, "BuffEffectOnSelf")
						local more = modStore:More(skillCfg, "BuffEffect") * env.minion.modDB:More(nil, "BuffEffectOnSelf")
						srcList:ScaleAddList(buff.modList, (1 + inc / 100) * more)
						mergeBuff(srcList, minionBuffs, buff.name)
					end
					if partyTabEnableExportBuffs and (buff.applyAllies or skillModList:Flag(nil, "BuffAppliesToAllies") or skillModList:Flag(nil, "BuffAppliesToPartyMembers")) then
						local inc = modStore:Sum("INC", skillCfg, "BuffEffect") + skillModList:Sum("INC", skillCfg, buff.name:gsub(" ", "").."Effect")
						local more = modStore:More(skillCfg, "BuffEffect")
						buffExports["Aura"]["otherEffects"] = buffExports["Aura"]["otherEffects"] or { }
						buffExports["Aura"]["otherEffects"][buff.name] =  { effectMult = (1 + inc / 100) * more, modList = buff.modList }
					end
				end
			elseif buff.type == "Guard" then
				if env.mode_buffs and (not activeSkill.skillFlags.totem or buff.allowTotemBuff) then
					local skillCfg = buff.activeSkillBuff and skillCfg
					local modStore = buff.activeSkillBuff and skillModList or modDB
				 	if not buff.applyNotPlayer then
						activeSkill.buffSkill = true
						local srcList = new("ModList")
						local inc = modStore:Sum("INC", skillCfg, "BuffEffect", "BuffEffectOnSelf", "BuffEffectOnPlayer")
						local more = modStore:More(skillCfg, "BuffEffect", "BuffEffectOnSelf")
						srcList:ScaleAddList(buff.modList, (1 + inc / 100) * more)
						mergeBuff(srcList, guards, buff.name)
					end
				end
			elseif buff.type == "Aura" then
				if env.mode_buffs then
					-- Check for extra modifiers to apply to aura skills
					local extraAuraModList = { }
					for _, value in ipairs(modDB:List(skillCfg, "ExtraAuraEffect")) do
						local add = true
						for _, mod in ipairs(extraAuraModList) do
							if modLib.compareModParams(mod, value.mod) then
								mod.value = mod.value + value.mod.value
								add = false
								break
							end
						end
						if add then
							t_insert(extraAuraModList, copyTable(value.mod, true))
						end
					end
					if not activeSkill.skillData.auraCannotAffectSelf then
						local inc = skillModList:Sum("INC", skillCfg, "AuraEffect", "BuffEffect", "BuffEffectOnSelf", "AuraEffectOnSelf", "AuraBuffEffect", "SkillAuraEffectOnSelf")
						local more = skillModList:More(skillCfg, "AuraEffect", "BuffEffect", "BuffEffectOnSelf", "AuraEffectOnSelf", "AuraBuffEffect", "SkillAuraEffectOnSelf")
						local mult = (1 + inc / 100) * more
						if modDB:Flag(nil, "AlliesAurasCannotAffectSelf") or not allyBuffs["Aura"] or not allyBuffs["Aura"][buff.name] or allyBuffs["Aura"][buff.name].effectMult / 100 <= mult then
							activeSkill.buffSkill = true
							modDB.conditions["AffectedByAura"] = true
							if buff.name:sub(1,4) == "Vaal" then
								modDB.conditions["AffectedBy"..buff.name:sub(6):gsub(" ","")] = true
							end
							modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
							local srcList = new("ModList")
							srcList:ScaleAddList(buff.modList, mult)
							srcList:ScaleAddList(extraAuraModList, mult)
							mergeBuff(srcList, buffs, buff.name)
						end
					end
					if not (modDB:Flag(nil, "SelfAurasCannotAffectAllies") or modDB:Flag(nil, "SelfAurasOnlyAffectYou") or modDB:Flag(nil, "SelfAuraSkillsCannotAffectAllies")) then
						if env.minion then
							local inc = skillModList:Sum("INC", skillCfg, "AuraEffect", "BuffEffect") + env.minion.modDB:Sum("INC", skillCfg, "BuffEffectOnSelf", "AuraEffectOnSelf")
							local more = skillModList:More(skillCfg, "AuraEffect", "BuffEffect") * env.minion.modDB:More(skillCfg, "BuffEffectOnSelf", "AuraEffectOnSelf")
							local mult = (1 + inc / 100) * more
							if not allyBuffs["Aura"] or  not allyBuffs["Aura"][buff.name] or allyBuffs["Aura"][buff.name].effectMult / 100 <= mult then
								activeSkill.minionBuffSkill = true
								env.minion.modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
								env.minion.modDB.conditions["AffectedByAura"] = true
								local srcList = new("ModList")
								srcList:ScaleAddList(buff.modList, mult)
								srcList:ScaleAddList(extraAuraModList, mult)
								mergeBuff(srcList, minionBuffs, buff.name)
							end
						end
						local inc = skillModList:Sum("INC", skillCfg, "AuraEffect", "BuffEffect")
						local more = skillModList:More(skillCfg, "AuraEffect", "BuffEffect")
						local mult = (1 + inc / 100) * more
						local newModList = new("ModList")
						newModList:AddList(buff.modList)
						newModList:AddList(extraAuraModList)
						if buffExports["Aura"][buff.name] then
							buffExports["Aura"][buff.name.."_Debuff"] = buffExports["Aura"][buff.name]
						end
						buffExports["Aura"][buff.name] = { effectMult = mult, modList = newModList }
					end
					if env.player.mainSkill.skillFlags.totem and not (modDB:Flag(nil, "SelfAurasCannotAffectAllies") or modDB:Flag(nil, "SelfAuraSkillsCannotAffectAllies")) then
						activeSkill.totemBuffSkill = true
						env.player.mainSkill.skillModList.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
						env.player.mainSkill.skillModList.conditions["AffectedByAura"] = true

						local srcList = new("ModList")
						local inc = skillModList:Sum("INC", skillCfg, "AuraEffect", "BuffEffect", "AuraBuffEffect")
						local more = skillModList:More(skillCfg, "AuraEffect", "BuffEffect", "AuraBuffEffect")
						local lists = {extraAuraModList, buff.modList}
						local scale = (1 + inc / 100) * more
						scale = m_max(scale, 0)

						for _, modList in ipairs(lists) do
							for _, mod in ipairs(modList) do
								if mod.name == "Armour" or mod.name == "Evasion" or mod.name:match("Resist?M?a?x?$") then
									local totemMod = copyTable(mod)
									totemMod.name = "Totem"..totemMod.name
									if scale ~= 1 then
										if type(totemMod.value) == "number" then
											totemMod.value = (m_floor(totemMod.value) == totemMod.value) and m_modf(round(totemMod.value * scale, 2)) or totemMod.value * scale
										elseif type(totemMod.value) == "table" and totemMod.value.mod then
											totemMod.value.mod.value = (m_floor(totemMod.value.mod.value) == totemMod.value.mod.value) and m_modf(round(totemMod.value.mod.value * scale, 2)) or totemMod.value.mod.value * scale
										end
									end
									srcList:AddMod(totemMod)
								end
							end
						end
						mergeBuff(srcList, buffs, "Totem "..buff.name)
					end
				end
			elseif buff.type == "Debuff" or buff.type == "AuraDebuff" then
				local stackCount
				if buff.stackVar then
					stackCount = skillModList:Sum("BASE", skillCfg, "Multiplier:"..buff.stackVar)
					if buff.stackLimit then
						stackCount = m_min(stackCount, buff.stackLimit)
					elseif buff.stackLimitVar then
						stackCount = m_min(stackCount, skillModList:Sum("BASE", skillCfg, "Multiplier:"..buff.stackLimitVar))
					end
				else
					stackCount = activeSkill.skillData.stackCount or 1
				end
				if env.mode_effective and stackCount > 0 then
					activeSkill.debuffSkill = true
					enemyDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
					modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
					local srcList = new("ModList")
					local mult = 1
					if buff.type == "AuraDebuff" then
						mult = 0
						if not modDB:Flag(nil, "SelfAurasOnlyAffectYou") then
							local inc = skillModList:Sum("INC", skillCfg, "AuraEffect", "BuffEffect", "DebuffEffect")
							local more = skillModList:More(skillCfg, "AuraEffect", "BuffEffect", "DebuffEffect")
							mult = (1 + inc / 100) * more
							buffExports["Aura"][buff.name..(buffExports["Aura"][buff.name] and "_Debuff" or "")] = { effectMult = mult, modList = buff.modList }
							if allyBuffs["AuraDebuff"] and allyBuffs["AuraDebuff"][buff.name] and allyBuffs["AuraDebuff"][buff.name].effectMult / 100 > mult then
								mult = 0
							end
						end
					end
					if buff.type == "Debuff" then
						local inc = skillModList:Sum("INC", skillCfg, "DebuffEffect")
						local more = skillModList:More(skillCfg, "DebuffEffect")
						mult = (1 + inc / 100) * more
					end
					srcList:ScaleAddList(buff.modList, mult * stackCount)
					if activeSkill.skillData.stackCount or buff.stackVar then
						srcList:NewMod("Multiplier:"..buff.name.."Stack", "BASE", stackCount, buff.name)
					end
					mergeBuff(srcList, debuffs, buff.name)
				end
			elseif buff.type == "Curse" or buff.type == "CurseBuff" then
				local mark = activeSkill.skillTypes[SkillType.Mark]
				modDB.conditions["SelfCast"..buff.name:gsub(" ","")] = not (activeSkill.skillTypes[SkillType.Triggered] or activeSkill.skillTypes[SkillType.Aura])
				if env.mode_effective and (not enemyDB:Flag(nil, "Hexproof") or modDB:Flag(nil, "CursesIgnoreHexproof") or activeSkill.skillData.ignoreHexLimit or activeSkill.skillData.ignoreHexproof) or mark then
					local curse = {
						name = buff.name,
						fromPlayer = true,
						isMark = mark,
						ignoreHexLimit = (modDB:Flag(activeSkill.skillCfg, "CursesIgnoreHexLimit") or activeSkill.skillData.ignoreHexLimit) and not mark or false,
						socketedCursesHexLimit = modDB:Flag(activeSkill.skillCfg, "SocketedCursesAdditionalLimit")
					}
					local inc = skillModList:Sum("INC", skillCfg, "CurseEffect") + enemyDB:Sum("INC", nil, "CurseEffectOnSelf")
					if activeSkill.skillTypes[SkillType.Aura] then
						inc = inc + skillModList:Sum("INC", skillCfg, "AuraEffect")
					end
					local more = skillModList:More(skillCfg, "CurseEffect")
					local moreMark = more
					-- This is non-ideal, but the only More for enemy is the boss effect
					if not curse.isMark then
						more = more * enemyDB:More(nil, "CurseEffectOnSelf")
					end
					local mult = 0
					if not (modDB:Flag(nil, "SelfAurasOnlyAffectYou") and activeSkill.skillTypes[SkillType.Aura]) then --If your aura only effect you blasphemy does nothing
						mult = (1 + inc / 100) * more
					end
					if buff.type == "Curse" then
						curse.modList = new("ModList")
						curse.modList:ScaleAddList(buff.modList, mult)
						if partyTabEnableExportBuffs then
							buffExports["Curse"][buff.name] = { isMark = curse.isMark, effectMult = curse.isMark and mult or (1 + inc / 100) * moreMark, modList = buff.modList }
						end
					else
						-- Curse applies a buff; scale by curse effect, then buff effect
						local temp = new("ModList")
						temp:ScaleAddList(buff.modList, mult)
						curse.buffModList = new("ModList")
						local buffInc = modDB:Sum("INC", skillCfg, "BuffEffectOnSelf")
						local buffMore = modDB:More(skillCfg, "BuffEffectOnSelf")
						curse.buffModList:ScaleAddList(temp, (1 + buffInc / 100) * buffMore)
						if env.minion then
							curse.minionBuffModList = new("ModList")
							local buffInc = env.minion.modDB:Sum("INC", nil, "BuffEffectOnSelf")
							local buffMore = env.minion.modDB:More(nil, "BuffEffectOnSelf")
							curse.minionBuffModList:ScaleAddList(temp, (1 + buffInc / 100) * buffMore)
						end
					end
					t_insert(curses, curse)
				end
			end
		end
		if activeSkill.minion and activeSkill.minion.activeSkillList then
			local castingMinion = activeSkill.minion
			for _, activeMinionSkill in ipairs(activeSkill.minion.activeSkillList) do
				local skillModList = activeMinionSkill.skillModList
				local skillCfg = activeMinionSkill.skillCfg
				for _, buff in ipairs(activeMinionSkill.buffList) do
					if buff.type == "Buff" then
						if env.mode_buffs and activeMinionSkill.skillData.enable then
							local skillCfg = buff.activeSkillBuff and skillCfg
							local modStore = buff.activeSkillBuff and skillModList or castingMinion.modDB
							if buff.applyAllies then
								activeMinionSkill.buffSkill = true
								modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
								local srcList = new("ModList")
								local inc = modStore:Sum("INC", skillCfg, "BuffEffect", "BuffEffectOnPlayer") + modDB:Sum("INC", nil, "BuffEffectOnSelf")
								local more = modStore:More(skillCfg, "BuffEffect", "BuffEffectOnPlayer") * modDB:More(nil, "BuffEffectOnSelf")
								srcList:ScaleAddList(buff.modList, (1 + inc / 100) * more)
								mergeBuff(srcList, buffs, buff.name)
								mergeBuff(buff.modList, buffs, buff.name)
								if activeMinionSkill.skillData.thisIsNotABuff then
									buffs[buff.name].notBuff = true
								end
								if partyTabEnableExportBuffs then
									local inc = modStore:Sum("INC", skillCfg, "BuffEffect")
									local more = modStore:More(skillCfg, "BuffEffect")
									buffExports["Aura"]["otherEffects"] = buffExports["Aura"]["otherEffects"] or { }
									buffExports["Aura"]["otherEffects"][buff.name] =  { effectMult = (1 + inc / 100) * more, modList = buff.modList }
								end
							end
							local envMinionCheck = (env.minion and (env.minion == castingMinion or buff.applyAllies))
							if buff.applyMinions or envMinionCheck then
								activeMinionSkill.minionBuffSkill = true
								if envMinionCheck then
									env.minion.modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
								else
									activeSkill.minion.modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
								end
								local srcList = new("ModList")
								local inc = modStore:Sum("INC", skillCfg, "BuffEffect", (env.minion == castingMinion) and "BuffEffectOnSelf" or nil)
								local more = modStore:More(skillCfg, "BuffEffect", (env.minion == castingMinion) and "BuffEffectOnSelf" or nil)
								srcList:ScaleAddList(buff.modList, (1 + inc / 100) * more)
								mergeBuff(srcList, minionBuffs, buff.name)
								mergeBuff(buff.modList, minionBuffs, buff.name)
								if activeMinionSkill.skillData.thisIsNotABuff then
									buffs[buff.name].notBuff = true
								end
							end
						end
					elseif buff.type == "Aura" then
						if env.mode_buffs and activeMinionSkill.skillData.enable then
							-- Check for extra modifiers to apply to aura skills
							local extraAuraModList = { }
							for _, value in ipairs(activeSkill.minion.modDB:List(skillCfg, "ExtraAuraEffect")) do
								local add = true
								for _, mod in ipairs(extraAuraModList) do
									if modLib.compareModParams(mod, value.mod) then
										mod.value = mod.value + value.mod.value
										add = false
										break
									end
								end
								if add then
									t_insert(extraAuraModList, copyTable(value.mod, true))
								end
							end
							if not (activeSkill.minion.modDB:Flag(nil, "SelfAurasCannotAffectAllies") or activeSkill.minion.modDB:Flag(nil, "SelfAurasOnlyAffectYou") or activeSkill.minion.modDB:Flag(nil, "SelfAuraSkillsCannotAffectAllies")) then
								if not modDB:Flag(nil, "AlliesAurasCannotAffectSelf") and not modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] then
									local inc = skillModList:Sum("INC", skillCfg, "AuraEffect", "BuffEffect", "BuffEffectOnPlayer", "AuraBuffEffect") + modDB:Sum("INC", skillCfg, "BuffEffectOnSelf", "AuraEffectOnSelf")
									local more = skillModList:More(skillCfg, "AuraEffect", "BuffEffect", "AuraBuffEffect") * modDB:More(skillCfg, "BuffEffectOnSelf", "AuraEffectOnSelf")
									local mult = (1 + inc / 100) * more
									if not allyBuffs["Aura"] or not allyBuffs["Aura"][buff.name] or allyBuffs["Aura"][buff.name].effectMult / 100 <= mult then
										activeMinionSkill.buffSkill = true
										modDB.conditions["AffectedByAura"] = true
										if buff.name:sub(1,4) == "Vaal" then
											modDB.conditions["AffectedBy"..buff.name:sub(6):gsub(" ","")] = true
										end
										modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
										local srcList = new("ModList")
										srcList:ScaleAddList(buff.modList, mult)
										srcList:ScaleAddList(extraAuraModList, mult)
										mergeBuff(srcList, buffs, buff.name)
									end
								end
								if env.minion and not env.minion.modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] and (env.minion ~= activeSkill.minion or not activeSkill.skillData.auraCannotAffectSelf)  then
									local inc = skillModList:Sum("INC", skillCfg, "AuraEffect", "BuffEffect") + env.minion.modDB:Sum("INC", skillCfg, "BuffEffectOnSelf", "AuraEffectOnSelf")
									local more = skillModList:More(skillCfg, "AuraEffect", "BuffEffect") * env.minion.modDB:More(skillCfg, "BuffEffectOnSelf", "AuraEffectOnSelf")
									local mult = (1 + inc / 100) * more
									if not allyBuffs["Aura"] or  not allyBuffs["Aura"][buff.name] or allyBuffs["Aura"][buff.name].effectMult / 100 <= mult then
										activeMinionSkill.minionBuffSkill = true
										env.minion.modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
										env.minion.modDB.conditions["AffectedByAura"] = true
										local srcList = new("ModList")
										srcList:ScaleAddList(buff.modList, mult)
										srcList:ScaleAddList(extraAuraModList, mult)
										mergeBuff(srcList, minionBuffs, buff.name)
									end
								end
								local inc = skillModList:Sum("INC", skillCfg, "AuraEffect", "BuffEffect")
								local more = skillModList:More(skillCfg, "AuraEffect", "BuffEffect")
								local mult = (1 + inc / 100) * more
								local newModList = new("ModList")
								newModList:AddList(buff.modList)
								newModList:AddList(extraAuraModList)
								if buffExports["Aura"][buff.name] then
									buffExports["Aura"][buff.name.."_Debuff"] = buffExports["Aura"][buff.name]
								end
								buffExports["Aura"][buff.name] = { effectMult = mult, modList = newModList }
								if env.player.mainSkill.skillFlags.totem and not env.player.mainSkill.skillModList.conditions["AffectedBy"..buff.name:gsub(" ","")] then
									activeMinionSkill.totemBuffSkill = true
									env.player.mainSkill.skillModList.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
									env.player.mainSkill.skillModList.conditions["AffectedByAura"] = true

									local srcList = new("ModList")
									local inc = skillModList:Sum("INC", skillCfg, "AuraEffect", "BuffEffect", "AuraBuffEffect")
									local more = skillModList:More(skillCfg, "AuraEffect", "BuffEffect", "AuraBuffEffect")
									local lists = {extraAuraModList, buff.modList}
									local scale = (1 + inc / 100) * more
									scale = m_max(scale, 0)

									for _, modList in ipairs(lists) do
										for _, mod in ipairs(modList) do
											if mod.name == "Armour" or mod.name == "Evasion" or mod.name:match("Resist?M?a?x?$") then
												local totemMod = copyTable(mod)
												totemMod.name = "Totem"..totemMod.name
												if scale ~= 1 then
													if type(totemMod.value) == "number" then
														totemMod.value = (m_floor(totemMod.value) == totemMod.value) and m_modf(round(totemMod.value * scale, 2)) or totemMod.value * scale
													elseif type(totemMod.value) == "table" and totemMod.value.mod then
														totemMod.value.mod.value = (m_floor(totemMod.value.mod.value) == totemMod.value.mod.value) and m_modf(round(totemMod.value.mod.value * scale, 2)) or totemMod.value.mod.value * scale
													end
												end
												srcList:AddMod(totemMod)
											end
										end
									end
									mergeBuff(srcList, buffs, "Totem "..buff.name)
								end
							end
						end
					elseif buff.type == "Curse" then
						if env.mode_effective and activeMinionSkill.skillData.enable and (not enemyDB:Flag(nil, "Hexproof") or activeMinionSkill.skillTypes[SkillType.Mark]) then
							local curse = {
								name = buff.name,
							}
							local inc = skillModList:Sum("INC", skillCfg, "CurseEffect") + enemyDB:Sum("INC", nil, "CurseEffectOnSelf")
							local more = skillModList:More(skillCfg, "CurseEffect") * enemyDB:More(nil, "CurseEffectOnSelf")
							curse.modList = new("ModList")
							curse.modList:ScaleAddList(buff.modList, (1 + inc / 100) * more)
							t_insert(minionCurses, curse)
						end
					elseif buff.type == "Debuff" or buff.type == "AuraDebuff" then
						local stackCount
						if buff.stackVar then
							stackCount = skillModList:Sum("BASE", skillCfg, "Multiplier:"..buff.stackVar)
							if buff.stackLimit then
								stackCount = m_min(stackCount, buff.stackLimit)
							elseif buff.stackLimitVar then
								stackCount = m_min(stackCount, skillModList:Sum("BASE", skillCfg, "Multiplier:"..buff.stackLimitVar))
							end
						else
							stackCount = activeMinionSkill.skillData.stackCount or 1
						end
						if env.mode_effective and stackCount > 0 then
							activeMinionSkill.debuffSkill = true
							local srcList = new("ModList")
							local mult = 1
							if buff.type == "AuraDebuff" then
								mult = 0
								if not skillModList:Flag(nil, "SelfAurasOnlyAffectYou") then
									local inc = skillModList:Sum("INC", skillCfg, "AuraEffect", "BuffEffect", "DebuffEffect")
									local more = skillModList:More(skillCfg, "AuraEffect", "BuffEffect", "DebuffEffect")
									mult = (1 + inc / 100) * more
									if not enemyDB.conditions["AffectedBy"..buff.name:gsub(" ","")] then
										buffExports["Aura"][buff.name..(buffExports["Aura"][buff.name] and "_Debuff" or "")] = { effectMult = mult, modList = buff.modList }
										if allyBuffs["AuraDebuff"] and allyBuffs["AuraDebuff"][buff.name] and allyBuffs["AuraDebuff"][buff.name].effectMult / 100 > mult then
											mult = 0
										end
									else
										mult = 0
									end
								end
							end
							enemyDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
							if env.minion and env.minion == activeSkill.minion then
								env.minion.modDB.conditions["AffectedBy"..buff.name:gsub(" ","")] = true
							end
							if buff.type == "Debuff" then
								local inc = skillModList:Sum("INC", skillCfg, "DebuffEffect")
								local more = skillModList:More(skillCfg, "DebuffEffect")
								mult = (1 + inc / 100) * more
							end
							srcList:ScaleAddList(buff.modList, mult * stackCount)
							if activeMinionSkill.skillData.stackCount or buff.stackVar then
								srcList:NewMod("Multiplier:"..buff.name.."Stack", "BASE", activeMinionSkill.skillData.stackCount, buff.name)
							end
							mergeBuff(srcList, debuffs, buff.name)
						end
					end
				end
			end
		end
	end
	if allyBuffs["otherEffects"] then
		for buffName, buff in pairs(allyBuffs["otherEffects"]) do
			modDB.conditions["AffectedBy"..buffName:gsub(" ","")] = true
			local inc = modDB:Sum("INC", nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
			local more = modDB:More(nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
			local srcList = new("ModList")
			srcList:ScaleAddList(buff.modList, (buff.effectMult + inc) / 100 * more)
			mergeBuff(srcList, buffs, buffName)
			if env.minion then
				env.minion.modDB.conditions["AffectedBy"..buffName:gsub(" ","")] = true
				local inc = env.minion.modDB:Sum("INC", nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
				local more = env.minion.modDB:More(nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
				local srcList = new("ModList")
				srcList:ScaleAddList(buff.modList, (buff.effectMult + inc) / 100 * more)
				mergeBuff(srcList, minionBuffs, buffName)
			end
		end
	end
	if allyBuffs["Aura"] then
		for auraName, aura in pairs(allyBuffs["Aura"]) do
			if auraName ~= "Vaal" then
				local auraNameCompressed = auraName:gsub(" ","")
				if not modDB:Flag(nil, "AlliesAurasCannotAffectSelf") and not modDB.conditions["AffectedBy"..auraNameCompressed] then
					modDB.conditions["AffectedByAura"] = true
					modDB.conditions["AffectedBy"..auraNameCompressed] = true
					local srcList = new("ModList")
					srcList:ScaleAddList(aura.modList, aura.effectMult / 100)
					mergeBuff(srcList, buffs, auraName)
				end
				if env.minion and not env.minion.modDB.conditions["AffectedBy"..auraNameCompressed] then
					env.minion.modDB.conditions["AffectedByAura"] = true
					env.minion.modDB.conditions["AffectedBy"..auraNameCompressed] = true
					local srcList = new("ModList")
					srcList:ScaleAddList(aura.modList, aura.effectMult / 100)
					mergeBuff(srcList, minionBuffs, auraName)
				end
			end
		end
	end
	if allyBuffs["AuraDebuff"] and env.mode_effective then
		for auraName, aura in pairs(allyBuffs["AuraDebuff"]) do
			if auraName ~= "Vaal" then
				local auraNameCompressed = auraName:gsub(" ","")
				if not enemyDB.conditions["AffectedBy"..auraNameCompressed] then
					enemyDB.conditions["AffectedBy"..auraNameCompressed] = true
					modDB.conditions["AffectedBy"..auraNameCompressed] = true
					local srcList = new("ModList")
					srcList:ScaleAddList(aura.modList, aura.effectMult / 100)
					mergeBuff(srcList, debuffs, auraName)
				end
			end
		end
	end

	-- Check for extra curses
	for dest, modDB in pairs({[curses] = modDB, [minionCurses] = env.minion and env.minion.modDB}) do
		for _, value in ipairs(modDB:List(nil, "ExtraCurse")) do
			local gemModList = new("ModList")
			local grantedEffect = env.data.skills[value.skillId]
			if grantedEffect then
				calcs.mergeSkillInstanceMods(env, gemModList, {
					grantedEffect = grantedEffect,
					level = value.level,
					quality = 0,
				})
				local curseModList = { }
				for _, mod in ipairs(gemModList) do
					for _, tag in ipairs(mod) do
						if tag.type == "GlobalEffect" and tag.effectType == "Curse" then
							t_insert(curseModList, mod)
							break
						end
					end
				end
				if value.applyToPlayer then
					-- Sources for curses on the player don't usually respect any kind of limit, so there's little point bothering with slots
					if modDB:Sum("BASE", nil, "AvoidCurse") < 100 then
						modDB.conditions["Cursed"] = true
						modDB.multipliers["CurseOnSelf"] = (modDB.multipliers["CurseOnSelf"] or 0) + 1
						modDB.conditions["AffectedBy"..grantedEffect.name:gsub(" ","")] = true
						local cfg = { skillName = grantedEffect.name }
						local inc = modDB:Sum("INC", cfg, "CurseEffectOnSelf") + gemModList:Sum("INC", nil, "CurseEffectAgainstPlayer")
						local more = modDB:More(cfg, "CurseEffectOnSelf") * gemModList:More(nil, "CurseEffectAgainstPlayer")
						modDB:ScaleAddList(curseModList, (1 + inc / 100) * more)
					end
				elseif not enemyDB:Flag(nil, "Hexproof") or modDB:Flag(nil, "CursesIgnoreHexproof") then
					local curse = {
						name = grantedEffect.name,
						fromPlayer = (dest == curses),
					}
					curse.modList = new("ModList")
					curse.modList:ScaleAddList(curseModList, (1 + enemyDB:Sum("INC", nil, "CurseEffectOnSelf") / 100) * enemyDB:More(nil, "CurseEffectOnSelf"))
					t_insert(dest, curse)
				end
			end
		end
	end
	local allyCurses = {}
	local allyPartyCurses = env.partyMembers["Curse"]
	if allyPartyCurses["Curse"] then
		allyCurses.limit = allyPartyCurses.limit
	else
		allyPartyCurses = { Curse = {} }
	end
	for curseName, curse in pairs(allyPartyCurses["Curse"]) do
		local newCurse = {
			name = curseName,
			priority = 0,
			modList = new("ModList")
		}
		local mult = curse.effectMult / 100
		if curse.isMark then
			newCurse.isMark = true
		else
			mult = mult * enemyDB:More(nil, "CurseEffectOnSelf")
		end
		newCurse.modList:ScaleAddList(curse.modList, mult)
		t_insert(allyCurses, newCurse)
	end


	-- Assign curses to slots
	local curseSlots = tableConcat(curses, minionCurses)
	env.curseSlots = curseSlots

	-- Apply buff/debuff modifiers
	for _, modList in pairs(buffs) do
		modDB:AddList(modList)
		if not modList.notBuff then
			modDB.multipliers["BuffOnSelf"] = (modDB.multipliers["BuffOnSelf"] or 0) + 1
		end
		if env.minion then
			for _, value in ipairs(modList:List(env.player.mainSkill.skillCfg, "MinionModifier")) do
				-- @leb-regression-guard:minion-modifier-multi-type-gate (mirror)
				local pass = (not value.type and not value.minionTypes)
					or (value.type and env.minion.type == value.type)
				if not pass and value.minionTypes then
					for _, mt in ipairs(value.minionTypes) do
						if env.minion.type == mt then pass = true; break end
					end
				end
				if pass then
					env.minion.modDB:AddMod(value.mod)
				end
			end
		end
	end
	if env.minion then
		for _, modList in pairs(minionBuffs) do
			env.minion.modDB:AddList(modList)
		end
	end
	for _, modList in pairs(debuffs) do
		enemyDB:AddList(modList)
	end
	modDB.multipliers["CurseOnEnemy"] = #curseSlots
	for _, slot in ipairs(curseSlots) do
		enemyDB.conditions["Cursed"] = true
		if slot.modList then
			enemyDB:AddList(slot.modList)
		end
		if slot.buffModList then
			modDB:AddList(slot.buffModList)
		end
		if slot.minionBuffModList then
			env.minion.modDB:AddList(slot.minionBuffModList)
		end
	end

	-- Check for extra auras
	buffExports["Aura"]["extraAura"] = { effectMult = 1, modList = new("ModList") }
	for _, value in ipairs(modDB:List(nil, "ExtraAura")) do
		local modList = { value.mod }
		if not value.onlyAllies then
			local inc = modDB:Sum("INC", nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
			local more = modDB:More(nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
			modDB:ScaleAddList(modList, (1 + inc / 100) * more)
			if not value.notBuff then
				modDB.multipliers["BuffOnSelf"] = (modDB.multipliers["BuffOnSelf"] or 0) + 1
			end
		end
		if not modDB:Flag(nil, "SelfAurasCannotAffectAllies") then
			if env.minion then
				local inc = env.minion.modDB:Sum("INC", nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
				local more = env.minion.modDB:More(nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
				env.minion.modDB:ScaleAddList(modList, (1 + inc / 100) * more)
			end
			buffExports["Aura"]["extraAura"].modList:AddMod(value.mod)
			local totemModBlacklist = value.mod.name and (value.mod.name == "Speed" or value.mod.name == "CritMultiplier" or value.mod.name == "CritChance")
			if env.player.mainSkill.skillFlags.totem and not totemModBlacklist then
				local totemMod = copyTable(value.mod)
				local totemModName, matches = totemMod.name:gsub("Condition:", "Condition:Totem")
				if matches < 1 then
					totemModName = "Totem" .. totemMod.name
				end
				totemMod.name = totemModName
				modDB:AddMod(totemMod)
			end
		end
	end
	if allyBuffs["extraAura"] then
		for _, buff in pairs(allyBuffs["extraAura"]) do
			local modList = buff.modList
			local inc = modDB:Sum("INC", nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
			local more = modDB:More(nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
			modDB:ScaleAddList(modList, (1 + inc / 100) * more)
			if env.minion then
				local inc = env.minion.modDB:Sum("INC", nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
				local more = env.minion.modDB:More(nil, "BuffEffectOnSelf", "AuraEffectOnSelf")
				env.minion.modDB:ScaleAddList(modList, (1 + inc / 100) * more)
			end
		end
	end

	-- Check for modifiers to apply to actors affected by player auras or curses
	for _, value in ipairs(modDB:List(nil, "AffectedByAuraMod")) do
		for actor in pairs(affectedByAura) do
			actor.modDB:AddMod(value.mod)
		end
	end

	-- Special handling for Dancing Dervish
	if modDB:Flag(nil, "DisableWeapons") then
		env.player.weaponData1 = copyTable(env.data.unarmedWeaponData[env.classId])
		modDB.conditions["Unarmed"] = true
		if not env.player.Gloves or env.player.Gloves == None then
			modDB.conditions["Unencumbered"] = true
		end
	elseif env.weaponModList1 then
		modDB:AddList(env.weaponModList1)
	end

	-- Process misc buffs/modifiers
	doActorMisc(env, env.player)
	if env.minion then
		doActorMisc(env, env.minion)
	end

	doActorMisc(env, env.enemy)

	-- @leb-regression-guard:multiplier-propagation-loop-no-double-count
	-- (REMOVED loop) Enemy ailment/curse "per X stack" counts (BleedStack, IgniteStack,
	-- ShockStack, ChillStack, PoisonStack, TimeRotStack, DoomStack, SlowStack,
	-- FrailtyStack, CurseStack, EnemyNegativeAilmentCount) are fed by config
	-- "Multiplier:XStack" BASE mods on the enemy modList (with Condition:Effective).
	-- These MUST NOT be copied into enemyDB.multipliers: ModStore:GetMultiplier already
	-- reads them via its 3rd term `Sum("BASE", cfg, "Multiplier:"..var)`, and
	-- enemyDB.conditions.Effective is true in the effective-DPS pass, so the config mod
	-- IS summed there. A propagation loop `multipliers[var] = Sum("BASE",...)` therefore
	-- made GetMultiplier = multipliers[var] + Sum(BASE) = 2N -- an unconditional doubler
	-- for every "per X stack" consumer (Chaos Bolts ch4bo-11, Mad Alchemist's Ladle,
	-- Profane Orb Hex Flurry, per-bleed/per-curse mods). The loop is deleted so the
	-- BASE-sum is the single source of truth: GetMultiplier(var, cfg) == N.
	-- (There is ZERO direct reader of enemyDB.multipliers[<stackvar>] in src/, so nothing
	-- depended on the propagated copy.) See REGRESSION_GUARDS.md
	-- "multiplier-propagation-loop-no-double-count". Do NOT reintroduce this loop.

	for _, activeSkill in ipairs(env.player.activeSkillList) do
		if activeSkill.skillFlags.totem then
			local limit = env.player.mainSkill.skillModList:Sum("BASE", env.player.mainSkill.skillCfg, "ActiveTotemLimit", "ActiveBallistaLimit" )
			output.ActiveTotemLimit = m_max(limit, output.ActiveTotemLimit or 0)
			output.TotemsSummoned = modDB:Override(nil, "TotemsSummoned") or output.ActiveTotemLimit
			enemyDB.multipliers["TotemsSummoned"] = m_max(output.TotemsSummoned or 0, enemyDB.multipliers["TotemsSummoned"] or 0)
		end
	end

	-- Defence/offence calculations
	for _, stat in ipairs({"WardRetention", "Endurance", "EnduranceThreshold", "WardPerSecond", "WardDecayThreshold"}) do
		output[stat] = round(calcLib.val(modDB, stat))
		-- "X% Endurance Threshold added as Ward Decay Threshold" conversion is
		-- applied later in CalcDefence, AFTER EnduranceThreshold is finalized
		-- (Mana/Life/Defiance contributions are merged in CalcDefence:1507-1521).
		if breakdown then
			breakdown[stat] = breakdown.simple(nil, nil, output[stat], stat)
		end
	end
	calcs.defence(env, env.player)
	if not fullDPSSkipEHP then
		calcs.buildDefenceEstimations(env, env.player)
	end

	-- @leb-regression-guard:singular-purpose-low-block-double
	-- Sentinel-61 "Singular Purpose": 2% more Void Damage per point, VALUE-DOUBLED
	-- while block chance < 30% (node description clause). Engine truth
	-- (stat-composition oracle Ctrl+Num5, TitoGaoS4_blank 2026-07-06, 2H World
	-- Splitter = 0% block): the void-tag Damage bucket holds a SINGLE MoreStat
	-- 0.20 = 2%/pt x 5 x2 — a value doubling, NOT a second multiplicative mod
	-- (10+10 stacked would give x1.21). The tree line is blanked in
	-- LE_TREE_NODE_STAT_REWRITE; the mod is granted here, after calcs.defence,
	-- so the gate reads the computed block chance (raw uncapped total, same
	-- basis as the Sentinel-70 Dedication precedent; below-30 questions only
	-- arise under the cap anyway). Spec: TestSingularPurposeLowBlock_spec.lua.
	local s61 = env.allocNodes and env.allocNodes["Sentinel-61"]
	if s61 and (s61.alloc or 0) > 0 then
		local blockChance = env.player.output.BlockChanceTotal or env.player.output.BlockChance or 0
		local double = blockChance < 30
		env.player.modDB:NewMod("VoidDamage", "MORE", 2 * (s61.alloc or 0) * (double and 2 or 1), "SingularPurpose")
	end

	-- @leb-regression-guard:flame-reave-return-wave-hits
	-- Flame Reave "Flame Caller" (fr11mv-18): "Flame Reave returns to you. This can hit
	-- the same enemy again." = +1 UNCONDITIONAL same-target return hit, but the returning
	-- hit ALWAYS deals 50% LESS damage (in-game tooltip: "Flame Reave's baseline damage
	-- penalty from expansion still applies, meaning a returning hit always has 50% less
	-- damage"). So it is +1 hit x 0.5 = +0.5 hit-EQUIVALENT of sustained single-target DPS.
	-- The raw stat " Returns To You" parses to 0 mods, so LEB modeled Flame Reave at
	-- AverageBurstHits 1 / TotalNumberOfHits 0.89 (verified probe, dev <see git log>).
	-- AdditionalSameTargetHits is a damage-equivalent addend that CalcOffence folds into
	-- dpsMultiplier (NOT AverageBurstHits, a burst-DISPLAY field). Injected here
	-- (Sentinel-61 precedent) instead of via parse: the natural phrase "Additional Same
	-- Target Hits" collides with ModParser's "additional"/"hits" tokens. SkillId:FlameReave
	-- -scoped so it only multiplies Flame Reave. Spec: TestFlameReaveReturnWaveHits_spec.lua.
	local flameCaller = env.allocNodes and env.allocNodes["fr11mv-18"]
	if flameCaller and (flameCaller.alloc or 0) > 0 then
		env.player.modDB:NewMod("AdditionalSameTargetHits", "BASE", 0.5, "FlameReaveFlameCaller", { type = "SkillId", skillId = "FlameReave" })
	end
	-- Flame Reave "Reflash" (fr11mv-16): "expands and returns a second time ... two
	-- additional hits", but on its OWN 3s cooldown, and its hits ALSO carry the 50%-less
	-- returning-hit penalty. So it fires at most once per 3s (independent of cast rate)
	-- for +2 hits x 0.5 = +1.0 hit-equivalent per firing -> cast-rate-AVERAGED in
	-- CalcOffence (where output.Speed is known): +min(1, 1/(3*castRate)) equivalents/cast.
	-- Flag it here (SkillId:FlameReave-scoped) so CalcOffence applies it only to Flame
	-- Reave. NOT parsed (raw " Expands and Returns Again" + "3 Cooldown (seconds)" yield
	-- no hit-count mod). See flame-reave-return-wave-hits guard.
	local reflash = env.allocNodes and env.allocNodes["fr11mv-16"]
	if reflash and (reflash.alloc or 0) > 0 then
		env.player.modDB:NewMod("FlameReaveReflashActive", "FLAG", true, "FlameReaveReflash", { type = "SkillId", skillId = "FlameReave" })
	end

	calcs.triggers(env, env.player)
	if not calcs.mirages(env) then
		calcs.offence(env, env.player, env.player.mainSkill)
	end

	-- Post-offence ward regen integration. Three contributions are folded
	-- into output.WardPerSecond here because they need values that are not
	-- known until after calcs.offence / final Mana+Life are computed:
	--   1. "X% of Mana Spent Gained as Ward" (event-driven, needs MainSkill.ManaPerSecondCost)
	--   2. "X% of Current Mana gained as Ward per second" (passive, needs final Mana)
	--   3. "X% of Missing Health gained as Ward per second" (passive, needs final Life
	--      and Multiplier:MissingHealthPercent from Config)
	-- Then Ward/WardDecay are recomputed because calcs.defence ran first.
	-- @leb-regression-guard:ward-regen-resource-conversion (post-offence fold-in site)
	-- The floor gate keys on PASSIVE regen only (game `wardRegen + wardRegenFromStats`);
	-- mana-spent is event-driven (game `GainWard` call), so it accumulates into wps
	-- for the inversion but does NOT count toward the floor gate snapshot.
	do
		local pOut = env.player.output
		local manaSpentGainedAsWard = env.player.modDB:Sum("BASE", nil, "ManaSpentGainedAsWard")
		local manaPerSecondCost = pOut.ManaPerSecondCost or 0
		local currentManaGainedAsWardPerSec = env.player.modDB:Sum("BASE", nil, "CurrentManaGainedAsWardPerSecond")
		local missingHealthGainedAsWardPerSec = env.player.modDB:Sum("BASE", nil, "MissingHealthGainedAsWardPerSecond")
		local missingHealthPercent = env.player.modDB:Sum("BASE", nil, "Multiplier:MissingHealthPercent") or 0
		-- @leb-regression-guard:ward-stop-moving-config-amortize (fold-in site)
		-- Transient Rest "(40-60)% of Current Mana gained as Ward when you stop
		-- moving (2 second cooldown)". Game-side field
		-- `Character.currentManaGainedAsWardOnStopMoving` (datamined game source offset
		-- 0xDB0) with const `currentManaGainedAsWardOnStopMovingCooldown = 2`
		-- (L95851). Event-driven (separate field from the continuous PerSecond
		-- form), so the contribution is gated on the Config toggle
		-- `conditionStoppedMoving` (Condition:StoppedMoving) and amortized over
		-- the 2-second hard cooldown: `currentMana * pct / 100 / 2`. Default
		-- off; opting in surfaces the affix as a steady-state continuous wps.
		-- Spec: spec/System/TestWardStopMovingConfigAmortize_spec.lua
		local currentManaGainedAsWardOnStopMoving = env.player.modDB:Sum("BASE", nil, "CurrentManaGainedAsWardOnStopMoving")
		local isStoppedMoving = env.player.modDB:Flag(nil, "Condition:StoppedMoving")
		-- @leb-regression-guard:ward-on-cast-health-config-amortize (fold-in site)
		-- Current Health -> Ward on directly casting a Necrotic / Elemental spell
		-- (Twisted Heart of Uhkeiros #216, crafted affix 766). Event-driven (game
		-- `ProtectionClass.GainWard` fires per cast), so each school's BASE % is
		-- gated on its Config toggle (`Condition:DirectlyCast{Necrotic|Elemental}
		-- SpellRecently`, default off) and amortized into a steady-state Ward per
		-- Second as `Life * pct / 100 * castRate`. Cast rate = `pOut.Speed`, the
		-- main skill's casts/second, populated by calcs.offence (run just above at
		-- `calcs.offence(env, env.player, env.player.mainSkill)`). Like the on-
		-- block / on-stop-moving / mana-spent sources this is event-driven, so it
		-- is EXCLUDED from the passive-WPS floor snapshot.
		-- Spec: spec/System/TestWardOnCastHealthConfigAmortize_spec.lua
		local healthWardOnCastNecrotic = env.player.modDB:Sum("BASE", nil, "CurrentHealthGainedAsWardOnCastNecrotic")
		local healthWardOnCastElemental = env.player.modDB:Sum("BASE", nil, "CurrentHealthGainedAsWardOnCastElemental")
		local isCastingNecrotic = env.player.modDB:Flag(nil, "Condition:DirectlyCastNecroticSpellRecently")
		local isCastingElemental = env.player.modDB:Flag(nil, "Condition:DirectlyCastElementalSpellRecently")
		local castRate = pOut.Speed or 0

		local manaSpentContribution = (manaSpentGainedAsWard > 0 and manaPerSecondCost > 0)
			and manaPerSecondCost * manaSpentGainedAsWard / 100 or 0
		local currentManaContribution = currentManaGainedAsWardPerSec > 0
			and (pOut.Mana or 0) * currentManaGainedAsWardPerSec / 100 or 0
		local missingHealthContribution = (missingHealthGainedAsWardPerSec > 0 and missingHealthPercent > 0)
			and (pOut.Life or 0) * (missingHealthPercent / 100) * missingHealthGainedAsWardPerSec / 100 or 0
		local stopMovingContribution = (isStoppedMoving and currentManaGainedAsWardOnStopMoving > 0)
			and (pOut.Mana or 0) * currentManaGainedAsWardOnStopMoving / 100 / 2 or 0
		-- Per-cast Life% amortized by cast rate (casts/sec) -> continuous wps.
		local healthWardOnCastNecroticContribution = (isCastingNecrotic and healthWardOnCastNecrotic > 0 and castRate > 0)
			and (pOut.Life or 0) * healthWardOnCastNecrotic / 100 * castRate or 0
		local healthWardOnCastElementalContribution = (isCastingElemental and healthWardOnCastElemental > 0 and castRate > 0)
			and (pOut.Life or 0) * healthWardOnCastElemental / 100 * castRate or 0
		local castWardContribution = healthWardOnCastNecroticContribution + healthWardOnCastElementalContribution

		local totalContribution = manaSpentContribution + currentManaContribution + missingHealthContribution + stopMovingContribution + castWardContribution

		if totalContribution > 0 then
			-- Snapshot passive WPS BEFORE folding in event-driven mana-spent.
			-- Current-mana and missing-health contributions ARE passive
			-- (continuous regen), so they belong in the passive snapshot.
			-- StopMoving is event-driven (game `GainWard` call on the 2s CD
			-- event), so like mana-spent it does NOT count toward the floor
			-- gate snapshot. See `datamined game source §2`.
			local baseWardPerSecond = pOut.WardPerSecond or 0
			local passiveWardPerSecond = baseWardPerSecond + currentManaContribution + missingHealthContribution
			-- @leb-regression-guard:ward-regen-passive-vs-event-split
			-- Display Ward Regen = passive sum only (game `wardRegen +
			-- wardRegenFromStats`, ProtectionClass.Update datamined offset).
			-- Event-driven ManaSpentGainedAsWard is applied via GainWard() on
			-- spell-cast and must NOT appear in the display stat — it folds into
			-- the local `wps` used for the Ward / WardDecay inversion only.
			-- Spec: spec/System/TestWardRegenPassiveVsEventSplit_spec.lua.
			pOut.WardPerSecond = passiveWardPerSecond
			-- Event-driven contributions (mana-spent + cast-driven health->ward)
			-- feed the local `wps` used for the Ward / WardDecay inversion but are
			-- kept out of the passive display stat / floor gate above.
			local wps = passiveWardPerSecond + manaSpentContribution + castWardContribution
			-- @leb-regression-guard:ward-regen-resource-conversion (breakdown site)
			-- Surface the per-source arithmetic in the Calcs tab so resource→ward
			-- contributions are visible (the modName="WardPerSecond" auto-breakdown
			-- only sees BASE/INC/MORE stat-source mods, not these post-offence
			-- fold-ins). Spec: spec/System/TestWardRegenResourceConversion_spec.lua.
			if env.player.breakdown then
				local lines = {
					s_format("%.1f ^8(base Ward per Second)", baseWardPerSecond),
				}
				if missingHealthContribution > 0 then
					t_insert(lines, s_format("+ %.1f ^8(%.1f%% of Life %d x Missing Health %.0f%%)",
						missingHealthContribution, missingHealthGainedAsWardPerSec, pOut.Life or 0, missingHealthPercent))
				end
				if currentManaContribution > 0 then
					t_insert(lines, s_format("+ %.1f ^8(%.1f%% of Current Mana %d)",
						currentManaContribution, currentManaGainedAsWardPerSec, pOut.Mana or 0))
				end
				t_insert(lines, s_format("= %.1f ^8(passive Ward per Second)", passiveWardPerSecond))
				if manaSpentContribution > 0 then
					t_insert(lines, s_format("+ %.1f ^8(%.1f%% of Mana Spent/sec %.1f, event-driven via GainWard)",
						manaSpentContribution, manaSpentGainedAsWard, manaPerSecondCost))
					t_insert(lines, s_format("= %.1f ^8(effective Ward per Second incl. event-driven)", wps))
				end
				if stopMovingContribution > 0 then
					t_insert(lines, s_format("+ %.1f ^8(%.1f%% of Current Mana %d / 2s CD; Stopped Moving)",
						stopMovingContribution, currentManaGainedAsWardOnStopMoving, pOut.Mana or 0))
				end
				if healthWardOnCastNecroticContribution > 0 then
					t_insert(lines, s_format("+ %.1f ^8(%.1f%% of Life %d x %.2f casts/s, event-driven; Cast Necrotic Spell)",
						healthWardOnCastNecroticContribution, healthWardOnCastNecrotic, pOut.Life or 0, castRate))
				end
				if healthWardOnCastElementalContribution > 0 then
					t_insert(lines, s_format("+ %.1f ^8(%.1f%% of Life %d x %.2f casts/s, event-driven; Cast Elemental Spell)",
						healthWardOnCastElementalContribution, healthWardOnCastElemental, pOut.Life or 0, castRate))
				end
				if castWardContribution > 0 then
					t_insert(lines, s_format("= %.1f ^8(effective Ward per Second incl. event-driven)", wps))
				end
				t_insert(lines, s_format("= %.1f ^8(total Ward per Second)", pOut.WardPerSecond))
				env.player.breakdown.WardPerSecond = lines
			end
			local wardDecayThreshold = pOut.WardDecayThreshold or 0
			-- @leb-regression-guard:ward-retention-negative-clamp (post-offence ManaSpentGainedAsWard path)
			-- @leb-regression-guard:ward-decay-gpp-constants (post-offence ManaSpentGainedAsWard path)
			local wardRetention = m_max(pOut.WardRetention or 0, -90)
			local ward = wardDecayThreshold + ((-0.2 + math.sqrt(0.04 + 0.0002 * wps * (1 + 0.5 * wardRetention / 100))) / 0.0001)
			ward = ward * calcLib.mod(env.player.modDB, nil, "Ward", "Defences")
			pOut.Ward = m_max(round(ward), 0)
			local rawWardDecayPerSecond = 0
			if pOut.Ward > 0 then
				local effectiveWard = m_max(pOut.Ward - wardDecayThreshold, 0)
				local retentionDivisor = 1 + 0.5 * wardRetention / 100
				local decayNumerator = 0.2 * effectiveWard + 0.00005 * effectiveWard ^ 2
				rawWardDecayPerSecond = decayNumerator / retentionDivisor
				-- @leb-regression-guard:ward-decay-floor-zero-passive
				-- Game `ProtectionClass.Update` (datamined offset) clamps per-frame
				-- decay to `dt * minimumWardDecayWithoutRegen` (= dt * 0.5) iff
				-- `wardRegen + wardRegenFromStats <= 0`. In LEB terms passive WPS
				-- corresponds to that pair; the ManaSpentGainedAsWard contribution
				-- is event-driven (GainWard call), not part of the floor gate.
				-- See `datamined game source §2`.
				if passiveWardPerSecond <= 0 then
					rawWardDecayPerSecond = m_max(rawWardDecayPerSecond, 0.5)
				end
				pOut.WardDecayPerSecond = round(rawWardDecayPerSecond)
			else
				pOut.WardDecayPerSecond = 0
			end
			-- Use unrounded decay for net regen so steady-state stays ~0 instead of
			-- the rounding residual.
			pOut.NetWardRegen = wps > 0 and (wps - rawWardDecayPerSecond) or 0
		end
	end

	if env.minion then
		doActorLifeMana(env.minion)

		calcs.defence(env, env.minion)
		if not fullDPSSkipEHP then -- main.build.calcsTab.input.showMinion and -- should be disabled unless "calcsTab.input.showMinion" is true
			calcs.buildDefenceEstimations(env, env.minion)
		end
		calcs.triggers(env, env.minion)
		calcs.offence(env, env.minion, env.minion.mainSkill)
	end

	 -- Export modifiers to enemy conditions and stats for party tab
	if partyTabEnableExportBuffs then
        for k, mod in pairs(enemyDB.mods) do
            if k:find("Condition") and not k:find("Party") then
                buffExports["EnemyConditions"][k] = true
            elseif (k:find("Resist") and not k:find("Totem") and not k:find("Max")) or k:find("Damage") or k:find("ActionSpeed") or k:find("SelfCrit") or (k:find("Multiplier") and not k:find("Max") and not k:find("Impale")) then
                for _, v in ipairs(mod) do
                    if not v.party and v.value ~= 0 and v.source ~= "EnemyConfig" and v.source ~= "Base" and not v.source:find("Delirious") and not v.source:find("^Party") then
						local skipValue = false
						for _, tag in ipairs(v) do
							if tag.effectType == "Curse" or tag.effectType == "AuraDebuff" then
								skipValue = true
								break
							end
						end
                        if not skipValue and (not v[1] or (
								(v[1].type ~= "Condition" or (v[1].var and (enemyDB.mods["Condition:"..v[1].var] and enemyDB.mods["Condition:"..v[1].var][1].value) or v[1].varList and (enemyDB.mods["Condition:"..v[1].varList[1]] and enemyDB.mods["Condition:"..v[1].varList[1]][1].value)))
								and (v[1].type ~= "Multiplier" or (enemyDB.mods["Multiplier:"..v[1].var] and enemyDB.mods["Multiplier:"..v[1].var][1].value)))) then
                            if buffExports["EnemyMods"][k] then
								if not buffExports["EnemyMods"][k].MultiStat then
									buffExports["EnemyMods"][k] = { MultiStat = true, buffExports["EnemyMods"][k] }
								end
								t_insert(buffExports["EnemyMods"][k], v)
							else
								buffExports["EnemyMods"][k] = v
							end
                        end
                    end
                end
            end
        end

		for _, damageType in ipairs(DamageTypes) do
			if env.modDB:Flag(nil, "Enemy"..damageType.."ResistEqualToYours") and output[damageType.."Resist"] then
				buffExports.PlayerMods["Enemy"..damageType.."ResistEqualToYours"] = true
				buffExports.PlayerMods[damageType.."Resist="..tostring(output[damageType.."Resist"])] = true
			end
		end

		buffExports.PlayerMods["MovementSpeedMod|percent|max="..tostring(output["MovementSpeedMod"] * 100)] = true

		env.build.partyTab:setBuffExports(buffExports)
	end

	cacheData(cacheSkillUUID(env.player.mainSkill, env), env)
end
