-- Last Epoch Building
--
-- Module: Calcs
-- Manages the calculation system.
--
local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local s_format = string.format
local m_min = math.min
local m_max = math.max
local m_floor = math.floor

local calcs = { }
calcs.breakdownModule = "Modules/CalcBreakdown"
LoadModule("Modules/CalcSetup", calcs)
LoadModule("Modules/CalcPerform", calcs)
LoadModule("Modules/CalcActiveSkill", calcs)
LoadModule("Modules/CalcDefence", calcs)
LoadModule("Modules/CalcOffence", calcs)
LoadModule("Modules/CalcTriggers", calcs)
LoadModule("Modules/CalcMirages.lua", calcs)

-- Get the average value of a table -- note this is unused
function math.average(t)
	local sum = 0
	local count = 0
	for k,v in pairs(t) do
		if type(v) == 'number' then
			sum = sum + v
			count = count + 1
		end
	end
	return (sum / count)
end

-- Print various tables to the console
local function infoDump(env)
	if env.modDB.parent then
		env.modDB.parent:Print()
	end
	env.modDB:Print()
	if env.minion then
		ConPrintf("=== Minion Mod DB ===")
		env.minion.modDB:Print()
	end
	ConPrintf("=== Enemy Mod DB ===")
	env.enemyDB:Print()
	local mainSkill = env.minion and env.minion.mainSkill or env.player.mainSkill
	ConPrintf("=== Main Skill ===")
	for _, skillEffect in ipairs(mainSkill.effectList) do
		ConPrintf("%s %d/%d", skillEffect.grantedEffect.name, skillEffect.level, skillEffect.quality)
	end
	ConPrintf("=== Main Skill Flags ===")
	ConPrintf("Mod: %s", modLib.formatFlags(mainSkill.skillCfg.flags, ModFlag))
	ConPrintf("Keyword: %s", modLib.formatFlags(mainSkill.skillCfg.keywordFlags, KeywordFlag))
	ConPrintf("=== Main Skill Mods ===")
	mainSkill.skillModList.parent:Print()
	mainSkill.skillModList:Print()
	ConPrintf("=== Main Skill Data ===")
	prettyPrintTable(mainSkill.skillData)
	ConPrintf("== Aux Skills ==")
	for i, aux in ipairs(env.auxSkillList) do
		ConPrintf("Skill #%d:", i)
		for _, skillEffect in ipairs(aux.effectList) do
			ConPrintf("  %s %d/%d", skillEffect.grantedEffect.name, skillEffect.level, skillEffect.quality)
		end
	end
	ConPrintf("== Output Table ==")
	prettyPrintTable(env.player.output)
end

-- Generate a function for calculating the effect of some modification to the environment
local function getCalculator(build, fullInit, modFunc)
	-- Initialise environment
	local env, cachedPlayerDB, cachedEnemyDB, cachedMinionDB = calcs.initEnv(build, "CALCULATOR")

	-- Run base calculation pass
	calcs.perform(env)
	local fullDPS = calcs.calcFullDPS(build, "CALCULATOR", {}, { cachedPlayerDB = cachedPlayerDB, cachedEnemyDB = cachedEnemyDB, cachedMinionDB = cachedMinionDB, env = nil })
	env.player.output.SkillDPS = fullDPS.skills
	env.player.output.FullDPS = fullDPS.combinedDPS
	local baseOutput = env.player.output

	env.modDB.parent = cachedPlayerDB
	env.enemyDB.parent = cachedEnemyDB
	if cachedMinionDB then
		env.minion.modDB.parent = cachedMinionDB
	end

	return function(...)
		-- Remove mods added during the last pass
		wipeTable(env.modDB.mods)
		wipeTable(env.modDB.conditions)
		wipeTable(env.modDB.multipliers)
		wipeTable(env.enemyDB.mods)
		wipeTable(env.enemyDB.conditions)
		wipeTable(env.enemyDB.multipliers)

		-- Call function to make modifications to the environment
		modFunc(env, ...)
		
		-- Run calculation pass
		calcs.perform(env)
		fullDPS = calcs.calcFullDPS(build, "CALCULATOR", {}, { cachedPlayerDB = cachedPlayerDB, cachedEnemyDB = cachedEnemyDB, cachedMinionDB = cachedMinionDB, env = env})
		env.player.output.SkillDPS = fullDPS.skills
		env.player.output.FullDPS = fullDPS.combinedDPS

		return env.player.output
	end, baseOutput	
end

-- Get fast calculator for adding tree node modifiers
function calcs.getNodeCalculator(build)
	return getCalculator(build, true, function(env, nodeList)
		-- Build and merge modifiers for these nodes
		env.modDB:AddList(calcs.buildModListForNodeList(env, nodeList))
	end)
end

-- Get calculator for other changes (adding/removing nodes, items, gems, etc)
function calcs.getMiscCalculator(build)
	-- Run base calculation pass
	local env, cachedPlayerDB, cachedEnemyDB, cachedMinionDB = calcs.initEnv(build, "CALCULATOR")
	calcs.perform(env)
	local fullDPS = calcs.calcFullDPS(build, "CALCULATOR", {}, { cachedPlayerDB = cachedPlayerDB, cachedEnemyDB = cachedEnemyDB, cachedMinionDB = cachedMinionDB, env = env})
	env.player.output.SkillDPS = fullDPS.skills
	env.player.output.FullDPS = fullDPS.combinedDPS

	local baseOutput = env.player.output

	return function(override, accelerate)
		local env, cachedPlayerDB, cachedEnemyDB, cachedMinionDB = calcs.initEnv(build, "CALCULATOR", override)
		-- we need to preserve the override somewhere for use by possible trigger-based build-outs with overrides
		env.override = override
		calcs.perform(env)
		if GlobalCache.useFullDPS or build.viewMode == "TREE" then
			-- prevent upcoming calculation from using Cached Data and thus forcing it to re-calculate new FullDPS roll-up 
			-- without this, FullDPS increase/decrease when for node/item/gem comparison would be all 0 as it would be comparing
			-- A with A (due to cache reuse) instead of A with B
			local fullDPS = calcs.calcFullDPS(build, "CALCULATOR", override, { cachedPlayerDB = cachedPlayerDB, cachedEnemyDB = cachedEnemyDB, cachedMinionDB = cachedMinionDB, env = env, accelerate = accelerate })
			-- reset cache usage
			env.player.output.SkillDPS = fullDPS.skills
			env.player.output.FullDPS = fullDPS.combinedDPS
		end
		return env.player.output
	end, baseOutput	
end

-- @leb-regression-guard:main-skill-ailment-upper-panel
-- Pure helper: aggregate ONE named damaging ailment's DPS for the main skill, for the
-- upper display panel. LEB imports each damaging ailment as a SEPARATE active skill
-- (entry name == the ailment name e.g. "Ignite"/"Bleed"/"Poison"/"Damned", trigger ==
-- parent skill name). When such separate-skill entries exist they are the CANONICAL full
-- contribution (their dps*count sums exactly to FullDPS - TotalDPS), so we use ONLY their
-- sum. output[ailmentName.."DPS"] is the parent hit's own partial value which is already
-- folded inside that entry; adding it would double-count (verified on Warlock Soul Feast:
-- output.DamnedDPS 467 was inside SkillDPS Damned 1100). Fall back to output[..DPS] ONLY
-- when NO separate-skill entry matches (ailment carried on the parent's own output).
-- Returns a number (0 if none). Pure: no env mutation, unit-testable with synthetic inputs.
function calcs.aggregateMainSkillAilment(output, skillDPSList, mainSkillName, ailmentName)
	if not mainSkillName or not ailmentName then return 0 end
	local skillTotal, matched = 0, false
	if skillDPSList then
		for _, skillData in ipairs(skillDPSList) do
			if skillData.name == ailmentName and skillData.trigger == mainSkillName then
				skillTotal = skillTotal + (skillData.dps or 0) * (skillData.count or 1)
				matched = true
			end
		end
	end
	if matched then return skillTotal end
	return (output and output[ailmentName .. "DPS"]) or 0
end

-- @leb-regression-guard:main-skill-ignite-upper-panel
-- Backward-compatible Ignite-specific wrapper (kept so the original guard/spec name holds).
function calcs.aggregateMainSkillIgnite(output, skillDPSList, mainSkillName)
	return calcs.aggregateMainSkillAilment(output, skillDPSList, mainSkillName, "Ignite")
end

-- @leb-regression-guard:fulldps-fold-ailments-into-parent
-- Pure helper: fold separately-imported damaging-ailment entries into their parent skill
-- for the Full DPS breakdown display (PoB parity = one line per skill = hit + all its
-- ailments). `damagingAilmentSet` is data.damagingAilment. An entry is an ailment iff its
-- name is in that set AND it carries a non-empty trigger that matches a parent entry's name.
-- The ailment's total (dps*count) is added into the parent (preserving parent.count so the
-- rendered dps*count still sums correctly) and the ailment row is dropped. Ailments with no
-- matching parent are kept as their own row (fallback). Returns a NEW list; the input list
-- (output.SkillDPS) is never mutated, so the snapshot deep-compare is unaffected.
function calcs.foldAilmentsIntoParents(skillDPSList, damagingAilmentSet)
	local function isAilment(entry)
		return damagingAilmentSet and damagingAilmentSet[entry.name] and entry.trigger and entry.trigger ~= ""
	end
	local foldedList = {}
	local parentByName = {}
	for _, skillData in ipairs(skillDPSList) do
		if not isAilment(skillData) then
			local copy = {}
			for k, v in pairs(skillData) do copy[k] = v end
			t_insert(foldedList, copy)
			parentByName[copy.name] = parentByName[copy.name] or copy
		end
	end
	for _, skillData in ipairs(skillDPSList) do
		if isAilment(skillData) then
			local parent = parentByName[skillData.trigger]
			if parent then
				parent.dps = parent.dps + (skillData.dps * skillData.count) / parent.count
			else
				local copy = {}
				for k, v in pairs(skillData) do copy[k] = v end
				t_insert(foldedList, copy)
			end
		end
	end
	return foldedList
end

-- @leb-regression-guard:fulldps-fold-same-skill-cycle
-- Fold multiple Full DPS entries of the SAME skill that arise from cycle-splitting
-- (N socket groups sharing a treeId -> each weighted x1/N and labelled "x1/N cycle")
-- or self-triggering (trigger == the skill's own name, e.g. "Shurikens (Shurikens)")
-- into ONE summed "<skill>" line. The per-entry "(<self-trigger>)" source and the
-- "x1/N cycle" skillPart are internal cycle-weighting detail the user does not want
-- surfaced. The cycle WEIGHTS are preserved: each entry's dps is already x1/N, so the
-- merged sum equals the skill's full Full DPS contribution. ONLY own/self entries are
-- merged (trigger empty or == name), so cross-skill triggers ("X (from OtherSkill)")
-- stay separate, and a lone skill with no duplicate is left untouched (its skillPart
-- is preserved). Display-only: callers pass a fresh list (post foldAilmentsIntoParents);
-- output.SkillDPS and the FullDPS total are unchanged.
-- See REGRESSION_GUARDS.md "fulldps-fold-same-skill-cycle".
function calcs.foldSameSkillCycleEntries(skillDPSList)
	local function isOwn(e)
		return (not e.trigger) or e.trigger == "" or e.trigger == e.name
	end
	-- Count own-entries per name so a single (non-duplicated) skill is left as-is.
	local ownCount = {}
	for _, e in ipairs(skillDPSList) do
		if isOwn(e) then ownCount[e.name] = (ownCount[e.name] or 0) + 1 end
	end
	local out = {}
	local mergedByName = {}
	for _, e in ipairs(skillDPSList) do
		if isOwn(e) and (ownCount[e.name] or 0) >= 2 then
			local m = mergedByName[e.name]
			if m then
				m.dps = m.dps + e.dps * (e.count or 1)
			else
				-- count=1 + dps=sum(dps*count) keeps dps*count == the combined total, and
				-- drops the "Nx" prefix / "(trigger)" / "x1/N cycle" labels on the merged line.
				m = { name = e.name, dps = e.dps * (e.count or 1), count = 1, source = e.source }
				mergedByName[e.name] = m
				t_insert(out, m)
			end
		else
			t_insert(out, e)
		end
	end
	return out
end

function calcs.calcFullDPS(build, mode, override, specEnv)
	local fullEnv, cachedPlayerDB, cachedEnemyDB, cachedMinionDB = calcs.initEnv(build, mode, override, specEnv)
	local usedEnv = nil
	-- @leb-regression-guard:minion-skill-breakdown-display
	-- Only the MAIN display pass (buildOutput mode=="MAIN") asks for the multi-skill
	-- minion breakdown; the node/misc comparison calculators (per-node hover) skip it
	-- so they don't pay the extra per-sub-skill calcs.offence on every hover.
	local wantMinionBreakdown = specEnv and specEnv.computeMinionBreakdown

	local fullDPS = {
		combinedDPS = 0,
		skills = { },
		poisonDPS = 0,
		causticGroundDPS = 0,
		impaleDPS = 0,
		igniteDPS = 0,
		burningGroundDPS = 0,
		bleedDPS = 0,
		corruptingBloodDPS = 0,
		decayDPS = 0,
		cullingMulti = 0,
		-- @leb-regression-guard:minion-skill-breakdown-display
		-- DISPLAY-ONLY breakdown of every damaging skill a multi-skill minion casts
		-- (Manifest Armor: Melee + Forge Breath + Whirlwind + Charge; Bear: Melee +
		-- Earthquake + Swipe; etc.). Keyed by the FullDPS skill-entry name. This does
		-- NOT feed combinedDPS / fullDPS.skills -- the headline FullDPS is unchanged
		-- (a minion still contributes only its single default skill, per the user's
		-- "breakdown display only, do not change the total" decision), so corpus
		-- snapshots are byte-identical (output.MinionSkillBreakdown is a NEW key,
		-- skipped by the snapshot serializer in spec/GenerateBuilds.lua). The Full DPS
		-- panel (Build.lua) renders these as indented info rows under the minion. The
		-- naive SUM of these would over-count (a minion shares its action time across
		-- skills; e.g. Forge Breath's standalone 1.0/s assumes 100% uptime vs the
		-- in-game ~0.47/s), which is exactly why this is informational, not summed.
		minionBreakdown = { }
	}

	local bleedSource = ""
	local corruptingBloodSource = ""
	local igniteSource = ""
	local burningGroundSource = ""
	local causticGroundSource = ""
	
	-- calc defences extra part should only run on the last skill of FullDPS
	-- Also count skills per treeId to detect cycling skill groups (e.g. Runebolt Tri-Elemental)
	local numActiveSkillInFullDPS = 0
	local treeIdGroupCount = {}
	for _, activeSkill in ipairs(fullEnv.player.activeSkillList) do
		if activeSkill.socketGroup and activeSkill.socketGroup.includeInFullDPS and not GlobalCache.excludeFullDpsList[cacheSkillUUID(activeSkill, fullEnv)] then
			numActiveSkillInFullDPS = numActiveSkillInFullDPS + 1
			local ge = activeSkill.activeEffect and activeSkill.activeEffect.grantedEffect
			local treeId = ge and ge.treeId
			-- @leb-regression-guard:cycle-weight-exclude-triggered
			-- Only MANUALLY-cast groups form a cast "cycle" (you alternate between them, so
			-- each is weighted x1/N). A TRIGGERED group (skillData.triggered:
			-- triggeredOnHit / triggerTime / triggerRate) fires AUTOMATICALLY and
			-- ADDITIVELY on top of the manual cast, so it must NOT be counted toward the
			-- cycle -- otherwise a self-triggered copy (e.g. "Shurikens (from Shurikens)")
			-- halves the manual skill and makes Full DPS LESS than the single skill.
			-- In-game confirmed: StarSeaVnV Shurikens in-game 142,136 vs cycle-halved
			-- 81,684 (-43%); the trigger is additive (+~22k on top of the ~120k manual).
			-- See REGRESSION_GUARDS.md "cycle-weight-exclude-triggered".
			-- A self-triggered grant ("X (from X)") sets socketGroup.triggeredOnHit but NOT
			-- skillData.triggered, so check BOTH (else the manual skill stays cycle-halved).
			if treeId and not ((activeSkill.skillData and activeSkill.skillData.triggered) or (activeSkill.socketGroup and activeSkill.socketGroup.triggeredOnHit)) then
				treeIdGroupCount[treeId] = (treeIdGroupCount[treeId] or 0) + 1
			end
		end
	end
	
	-- @leb-regression-guard:fulldps-fold-same-skill-cycle
	-- Map of MANUALLY-socketed skill id -> its activeSkill (groups that are neither timer-
	-- nor hit-triggered). Used to redirect a timer-triggered duplicate's Full DPS slot to the
	-- real maintained skill (see below).
	local manualActiveSkillBySkillId = {}
	for _, mAskill in ipairs(fullEnv.player.activeSkillList) do
		local mSg = mAskill.socketGroup
		if mSg and mSg.skillId and not mSg.triggeredByTimer and not mSg.triggeredOnHit then
			manualActiveSkillBySkillId[mSg.skillId] = mAskill
		end
	end
	-- @leb-regression-guard:dragonflame-nova-proc-rate
	-- Dragonflame Edict's nova procs ONCE per player minion-skill use ("the nearest
	-- minion ... casts"), regardless of how many minions are out or how many summon
	-- groups are in Full DPS -- so its rated contribution is folded at most ONCE per
	-- Full DPS pass (at the FIRST Full-DPS minion carrying the granted sub-skill).
	local dragonflameNovaProcFolded = false
	GlobalCache.numActiveSkillInFullDPS = 0
	for _, activeSkill in ipairs(fullEnv.player.activeSkillList) do
		if activeSkill.socketGroup and activeSkill.socketGroup.includeInFullDPS and not GlobalCache.excludeFullDpsList[cacheSkillUUID(activeSkill, fullEnv)] then
			-- @leb-regression-guard:fulldps-fold-same-skill-cycle
			-- A timer-triggered duplicate ("<X> (every Ns)", triggeredByTimer, from a "chance
			-- to cast <X>" affix) is the SAME skill as a manually-socketed one — the auto-cast
			-- copy feeds the same maintained pool. The import defaults such grants to
			-- includeInFullDPS=true while the manual group may be false, so Full DPS would show
			-- the tiny triggered copy instead of the real maintained skill. When the manual
			-- group is NOT separately included, redirect this Full DPS slot to the manual skill
			-- so the skill is counted ONCE at its real value. (If the manual IS also included it
			-- is counted on its own; leave this entry as-is.) Counts are preserved: the slot is
			-- still one Full DPS entry, just filled with the manual skill's value.
			do
				local _sg = activeSkill.socketGroup
				if _sg.triggeredByTimer and _sg.skillId then
					local manual = manualActiveSkillBySkillId[_sg.skillId]
					if manual and manual.socketGroup and not manual.socketGroup.includeInFullDPS then
						activeSkill = manual
					end
				end
			end
			local activeSkillCount = 1
			GlobalCache.numActiveSkillInFullDPS = GlobalCache.numActiveSkillInFullDPS + 1
			local cachedData = GlobalCache.cachedData[mode][cacheSkillUUID(activeSkill, fullEnv)]
			if cachedData and next(override) == nil then
				usedEnv = cachedData.Env
				activeSkill = usedEnv.player.mainSkill
			else
				fullEnv.player.mainSkill = activeSkill
				calcs.perform(fullEnv, (GlobalCache.numActiveSkillInFullDPS ~= numActiveSkillInFullDPS))
				usedEnv = fullEnv
			end
			local minionName = nil
			if activeSkill.minion or usedEnv.minion then
				-- @leb-regression-guard:auto-summon-pack-dps
				-- For auto-summon minions (Apiarist bees etc.) the active count is
				-- the build's count stat (e.g. BeesPerTenSeconds), carried onto the
				-- socket group as autoSummonCountStat by CalcSetup (guard
				-- `auto-summon-registry`). The count stat lives on the PLAYER modDB
				-- (the minion modDB is built fresh and does NOT inherit it), so
				-- resolve it against usedEnv.modDB here -- NOT via minionData.limit,
				-- which would resolve against the minion's own modList (= 0). Pack
				-- DPS = single-minion DPS x count. All OTHER minions keep the
				-- existing behavior (count = activeSkillCount = 1).
				local minionCount = activeSkillCount
				local sg = activeSkill.socketGroup
				local countStat = sg and sg.autoSummonCountStat
				-- @leb-regression-guard:granted-summon-pipeline
				-- SubSkillGrants summons (e.g. Spriggan Form Healing Totems x3) carry a
				-- FIXED pack count (autoSummonFixedCount); the count is a skill-tree-node
				-- value, not on the player modDB. Use it directly when present.
				if sg and sg.autoSummonFixedCount then
					minionCount = m_max(1, m_floor(sg.autoSummonFixedCount))
				elseif countStat then
					-- The GATE stat (countStat, >0 only when the granting item is
					-- equipped) can differ from the ACTIVE pack size: e.g. Anurok
					-- "fills your Companion Limit" -> gate is a flag (AnuroksSummoned=1)
					-- but the count is MaxCompanions. autoSummonPackCountStat (optional)
					-- overrides the RESOLVED count while countStat still gates injection
					-- in CalcSetup. Most auto-summons (bees/T-Rex/Tolmat) set no pack
					-- stat -> count = countStat as before.
					local resolveStat = sg.autoSummonPackCountStat or countStat
					-- @leb-regression-guard:auto-summon-packcount-base-companions
					-- A packCountStat that names a COMPUTED player output (Anurok's
					-- MaxCompanions = 2 base companions + Sum(BASE)) must be read from the
					-- player OUTPUT, not the raw modDB. The base companions are added in
					-- CalcDefence (output.MaxCompanions = 2 + modDB:Sum("BASE",...)), NOT as
					-- a modDB BASE mod, so calcLib.val(usedEnv.modDB, "MaxCompanions")
					-- returns ONLY the bonus and undercounts the Anurok pack by the base 2
					-- (worst case count 1 vs 2 -> FullDPS ~2x low). Chorus of the Anurok
					-- summons "up to your Companion Limit" = the FULL limit (datamined unique
					-- text, AutoSummons.lua). Plain count stats (BeesPerTenSeconds etc.) have
					-- no output entry -> fall back to the modDB value as before.
					local resolved
					if sg.autoSummonPackCountStat and usedEnv.player.output[sg.autoSummonPackCountStat] ~= nil then
						resolved = usedEnv.player.output[sg.autoSummonPackCountStat]
					else
						resolved = calcLib.val(usedEnv.modDB, resolveStat, nil)
					end
					minionCount = m_max(1, m_floor(resolved))
				end
				if usedEnv.minion.output.TotalDPS and usedEnv.minion.output.TotalDPS > 0 then
					minionName = (activeSkill.minion and activeSkill.minion.minionData.name..": ") or (usedEnv.minion and usedEnv.minion.minionData.name..": ") or ""
					t_insert(fullDPS.skills, { name = activeSkill.activeEffect.grantedEffect.name, dps = usedEnv.minion.output.TotalDPS, count = minionCount, trigger = activeSkill.infoTrigger, skillPart = minionName..activeSkill.skillPartName })
					fullDPS.combinedDPS = fullDPS.combinedDPS + usedEnv.minion.output.TotalDPS * minionCount
				end
				if usedEnv.minion.output.BleedDPS and usedEnv.minion.output.BleedDPS > fullDPS.bleedDPS then
					fullDPS.bleedDPS = usedEnv.minion.output.BleedDPS
					bleedSource = activeSkill.activeEffect.grantedEffect.name
				end
				if usedEnv.minion.output.IgniteDPS and usedEnv.minion.output.IgniteDPS > fullDPS.igniteDPS then
					fullDPS.igniteDPS = usedEnv.minion.output.IgniteDPS
					igniteSource = activeSkill.activeEffect.grantedEffect.name
				end
				if usedEnv.minion.output.PoisonDPS and usedEnv.minion.output.PoisonDPS > 0 then
					fullDPS.poisonDPS = fullDPS.poisonDPS + usedEnv.minion.output.PoisonDPS * (usedEnv.minion.output.TotalPoisonStacks or 1) * activeSkillCount
				end
				if usedEnv.minion.output.ImpaleDPS and usedEnv.minion.output.ImpaleDPS > 0 then
					fullDPS.impaleDPS = fullDPS.impaleDPS + usedEnv.minion.output.ImpaleDPS * activeSkillCount
				end
				if usedEnv.minion.output.DecayDPS and usedEnv.minion.output.DecayDPS > 0 then
					fullDPS.decayDPS = fullDPS.decayDPS + usedEnv.minion.output.DecayDPS
				end
				if usedEnv.minion.output.CullMultiplier and usedEnv.minion.output.CullMultiplier > 1 and usedEnv.minion.output.CullMultiplier > fullDPS.cullingMulti then
					fullDPS.cullingMulti = usedEnv.minion.output.CullMultiplier
				end
				-- This is a fix to prevent Absolution spell hit from being counted multiple times when increasing minions count
				if activeSkill.activeEffect.grantedEffect.name == "Absolution" and fullEnv.modDB:Flag(false, "Condition:AbsolutionSkillDamageCountedOnce") then
					activeSkillCount = 1
					activeSkill.infoMessage2 = "Skill Damage"
				end

				-- @leb-regression-guard:minion-skill-breakdown-display
				-- Validation provenance is retained in maintainer notes.
				if wantMinionBreakdown then
					local mEnv = usedEnv.minion
					if mEnv and mEnv.activeSkillList and #mEnv.activeSkillList > 1 then
						local savedMain = mEnv.mainSkill
						local breakdown = {}
						for _, mSkill in ipairs(mEnv.activeSkillList) do
							mEnv.mainSkill = mSkill
							local ok = pcall(calcs.offence, usedEnv, mEnv, mSkill)
							local sdps = ok and mEnv.output and mEnv.output.TotalDPS or 0
							if sdps and sdps > 0 then
								local ge = mSkill.activeEffect and mSkill.activeEffect.grantedEffect
								t_insert(breakdown, { name = (ge and ge.name) or "?", dps = sdps })
							end
						end
						-- restore the minion's main skill + recompute so the cached env is clean
						mEnv.mainSkill = savedMain
						if savedMain then pcall(calcs.offence, usedEnv, mEnv, savedMain) end
						if #breakdown > 1 then
							fullDPS.minionBreakdown[activeSkill.activeEffect.grantedEffect.name] = breakdown
						end
					end
				end

				-- @leb-regression-guard:minion-multiskill-cadence-fold
				-- When the default-OFF `minionMultiSkillCadenceFold` config is enabled,
				-- REPLACE this minion's single-default-skill headline contribution with the
				-- cadence-weighted sum over ALL its damaging skills: Sum_S cadence_S x perHit_S,
				-- where cadence_S is the empirically MEASURED firing rate (data.minionSkillCadence,
				-- keyed minion name -> grantedEffect.id) and perHit_S is the skill's LEB-validated
				-- AverageDamage. Only minions present in the table are folded; a minion without a
				-- cadence row keeps the single-skill headline. The flag is unset by default, so
				-- this whole block is skipped and combinedDPS / fullDPS.skills stay byte-identical
				-- (corpus-neutral). Melee (the default skill) is itself one of the folded skills at
				-- its MEASURED cadence, so subtracting the original single-skill DPS and adding
				-- foldDPS does not double-count it. Ailment DPS (Bleed/Ignite) is handled by the
				-- separate *DPS paths above and is deliberately NOT in the cadence table.
				--
				-- CONFIGURATION-MATCH GATE: a measured cadence is only valid for the EXACT
				-- skill set it was captured with -- the minion time-shares ONE action economy,
				-- so Manifest Armor's melee 0.338/s was suppressed by the 3 co-active grants; a
				-- build missing some grants melees FASTER. Fold ONLY when every skill in the
				-- minion's cadence table is present in this build's activeSkillList (full
				-- measured configuration); a partial build keeps the single-skill headline.
				-- See src/Data/MinionSkillCadence.lua + REGRESSION_GUARDS.md.
				if fullEnv.modDB:Flag(false, "Condition:MinionMultiSkillCadenceFold")
						and usedEnv.minion and usedEnv.minion.output.TotalDPS and usedEnv.minion.output.TotalDPS > 0 then
					local mEnv = usedEnv.minion
					local mName = mEnv.minionData and mEnv.minionData.name
					local cadTbl = mName and data.minionSkillCadence and data.minionSkillCadence[mName]
					if cadTbl and mEnv.activeSkillList and #mEnv.activeSkillList > 1 then
						local nTbl = 0
						for _ in pairs(cadTbl) do nTbl = nTbl + 1 end
						local savedMain = mEnv.mainSkill
						local foldDPS, nMatched = 0, 0
						for _, mSkill in ipairs(mEnv.activeSkillList) do
							local ge = mSkill.activeEffect and mSkill.activeEffect.grantedEffect
							local geId = ge and ge.id
							local cadEntry = ge and (cadTbl[geId] or cadTbl[ge.name]
								or (geId and cadTbl[(geId:gsub("_MinionWeaponBase$", ""))]))
							-- A cadence entry is normally a number, but may be a table
							-- { rate = <hits/s>, requires = "Multiplier:<name>" } for a granted
							-- sub-skill that only FIRES while a state multiplier is non-zero (e.g. the
							-- abomination's Double Strike, granted per Warrior/Rogue absorbed -- it is
							-- always in activeSkillList because its Spoils node is allocated, but must
							-- not fold at a 0-absorb state). When the requirement is unmet the skill is
							-- skipped, so nMatched < nTbl and the whole fold is disabled (single-skill
							-- headline) -- which keeps a 0-absorb build byte-identical.
							local cad
							if type(cadEntry) == "table" then
								if not cadEntry.requires or (mEnv.modDB:Sum("BASE", nil, cadEntry.requires) or 0) > 0 then
									cad = cadEntry.rate
								end
							else
								cad = cadEntry
							end
							if cad and cad > 0 then
								mEnv.mainSkill = mSkill
								local ok = pcall(calcs.offence, usedEnv, mEnv, mSkill)
								local perHit = ok and mEnv.output and mEnv.output.AverageDamage or 0
								if perHit and perHit > 0 then
									foldDPS = foldDPS + cad * perHit
									nMatched = nMatched + 1
								end
							end
						end
						-- restore the minion's main skill + recompute so the cached env stays clean
						mEnv.mainSkill = savedMain
						if savedMain then pcall(calcs.offence, usedEnv, mEnv, savedMain) end
						if nMatched == nTbl and foldDPS > 0 then
							local singleDPS = usedEnv.minion.output.TotalDPS
							fullDPS.combinedDPS = fullDPS.combinedDPS - singleDPS * minionCount + foldDPS * minionCount
							-- reflect the fold on this minion's skills-list entry (last inserted)
							local entry = fullDPS.skills[#fullDPS.skills]
							if entry and entry.dps == singleDPS then
								entry.dps = foldDPS
								entry.skillPart = (entry.skillPart or "") .. " [cadence-folded]"
							end
						end
					end
				end

				-- @leb-regression-guard:dragonflame-nova-proc-rate
				-- Rate the Dragonflame Edict nova proc where its per-hit already lives: the
				-- minion's granted DragonfireNova sub-skill (guard dragonflame-nova-grant).
				-- GROUNDED, not curve-fit (2026-07-10 datamine): chance = affix property 98
				-- value 0.6 (uniques_v3.json, parsed to ChanceToTriggerOnMinionSkillUse_
				-- DragonfireNova = 60); the 1s cooldown is the game's text constant
				-- (descriptor 98,83,0,0; sibling "up to 3 times per second" = the pre-cap
				-- family), parsed to TriggerRateCapPerSecond_DragonfireNova = 1. So
				--   proc rate = min(chance x minion_skill_use_rate, 1/s).
				-- minion_skill_use_rate = the config input MinionSkillUsesPerSecond when
				-- set, else THIS summoning skill's own cast rate (usedEnv.player.output.
				-- Speed -- the rate the build could re-use its minion skill; steady-state
				-- re-summon spam). Contribution = rate x the sub-skill's AverageDamage
				-- (same per-hit source as the cadence fold above -- NO second scoring
				-- path), added as its OWN Full DPS entry: it does not touch the minion's
				-- default-skill entry, is NOT multiplied by minionCount/activeSkillCount
				-- (ONE nova per use, cast by the nearest minion only), and folds at most
				-- once per pass (see dragonflameNovaProcFolded above). No staff -> chance
				-- 0 -> block inert; staff but no Full-DPS minion group -> no entry
				-- (respects the Full DPS gating). VALIDATION: rate factors datamined;
				-- cadence validated only against the QqwprgdN probe context -- a future
				-- in-game proc-rate capture upgrades this to MATCH.
				-- Spec: spec/System/TestDragonflameNovaProcRate_spec.lua.
				if not dragonflameNovaProcFolded and usedEnv.minion then
					local dfChance = usedEnv.modDB:Sum("BASE", nil, "ChanceToTriggerOnMinionSkillUse_DragonfireNova")
					if dfChance > 0 then
						local mEnv = usedEnv.minion
						local novaSkill
						for _, mSkill in ipairs(mEnv.activeSkillList or { }) do
							local ge = mSkill.activeEffect and mSkill.activeEffect.grantedEffect
							if ge and ge.id == "DragonfireNova" then
								novaSkill = mSkill
								break
							end
						end
						if novaSkill then
							local useRate = usedEnv.modDB:Sum("BASE", nil, "MinionSkillUsesPerSecond")
							if useRate <= 0 then
								useRate = usedEnv.player.output.Speed or 0
							end
							local rateCap = usedEnv.modDB:Sum("BASE", nil, "TriggerRateCapPerSecond_DragonfireNova")
							local procRate = dfChance / 100 * useRate
							if rateCap > 0 then
								procRate = m_min(procRate, rateCap)
							end
							if procRate > 0 then
								local savedMain = mEnv.mainSkill
								mEnv.mainSkill = novaSkill
								local ok = pcall(calcs.offence, usedEnv, mEnv, novaSkill)
								local perHit = ok and mEnv.output and mEnv.output.AverageDamage or 0
								-- restore the minion's main skill + recompute so the cached env stays clean
								mEnv.mainSkill = savedMain
								if savedMain then pcall(calcs.offence, usedEnv, mEnv, savedMain) end
								if perHit > 0 then
									local novaDPS = procRate * perHit
									t_insert(fullDPS.skills, { name = "Dragonflame Nova", dps = novaDPS, count = 1, trigger = activeSkill.activeEffect.grantedEffect.name, skillPart = s_format("proc %.3g/s", procRate) })
									fullDPS.combinedDPS = fullDPS.combinedDPS + novaDPS
									dragonflameNovaProcFolded = true
								end
							end
						end
					end
				end
			end

			if activeSkill.mirage then
				local mirageCount = (activeSkill.mirage.count or 1) * activeSkillCount
				if activeSkill.mirage.output.TotalDPS and activeSkill.mirage.output.TotalDPS > 0 then
					t_insert(fullDPS.skills, { name = activeSkill.mirage.name, dps = activeSkill.mirage.output.TotalDPS, count = mirageCount, trigger = activeSkill.mirage.infoTrigger, skillPart = activeSkill.mirage.skillPartName })
					fullDPS.combinedDPS = fullDPS.combinedDPS + activeSkill.mirage.output.TotalDPS * mirageCount
				end
				if activeSkill.mirage.output.BleedDPS and activeSkill.mirage.output.BleedDPS > fullDPS.bleedDPS then
					fullDPS.bleedDPS = activeSkill.mirage.output.BleedDPS
					bleedSource = activeSkill.activeEffect.grantedEffect.name .. " (Mirage)"
				end
				if activeSkill.mirage.output.IgniteDPS and activeSkill.mirage.output.IgniteDPS > fullDPS.igniteDPS then
					fullDPS.igniteDPS = activeSkill.mirage.output.IgniteDPS
					igniteSource = activeSkill.activeEffect.grantedEffect.name .. " (Mirage)"
				end
				if activeSkill.mirage.output.PoisonDPS and activeSkill.mirage.output.PoisonDPS > 0 then
					fullDPS.poisonDPS = fullDPS.poisonDPS + activeSkill.mirage.output.PoisonDPS * (activeSkill.mirage.output.TotalPoisonStacks or 1) * mirageCount
				end
				if activeSkill.mirage.output.ImpaleDPS and activeSkill.mirage.output.ImpaleDPS > 0 then
					fullDPS.impaleDPS = fullDPS.impaleDPS + activeSkill.mirage.output.ImpaleDPS * mirageCount
				end
				if activeSkill.mirage.output.DecayDPS and activeSkill.mirage.output.DecayDPS > 0 then
					fullDPS.decayDPS = fullDPS.decayDPS + activeSkill.mirage.output.DecayDPS
				end
				if activeSkill.mirage.output.CullMultiplier and activeSkill.mirage.output.CullMultiplier > 1 and activeSkill.mirage.output.CullMultiplier > fullDPS.cullingMulti then
					fullDPS.cullingMulti = activeSkill.mirage.output.CullMultiplier
				end
			end

			if usedEnv.player.output.TotalDPS and usedEnv.player.output.TotalDPS > 0 then
				local cycleGE = activeSkill.activeEffect and activeSkill.activeEffect.grantedEffect
				local cycleN = (cycleGE and cycleGE.treeId and treeIdGroupCount[cycleGE.treeId]) or 1
				-- @leb-regression-guard:cycle-weight-exclude-triggered (triggered = additive -> full weight)
				local cycleIsTriggered = (activeSkill.skillData and activeSkill.skillData.triggered) or (activeSkill.socketGroup and activeSkill.socketGroup.triggeredOnHit)
				local cycleWeight = (not cycleIsTriggered and cycleN > 1) and (1 / cycleN) or 1
				-- @leb-regression-guard:shatter-totem-count-fold
				-- Validation provenance is retained in maintainer notes.
				local shatterFold = (activeSkill.socketGroup and activeSkill.socketGroup.shatterTotemFoldCount) or 1
				local packCount = activeSkillCount * shatterFold
				local basePart = (minionName and activeSkill.infoMessage2) or activeSkill.skillPartName
				local skillPartLabel = (not cycleIsTriggered and cycleN > 1) and (((basePart and basePart ~= "") and (basePart .. " ") or "") .. "x1/" .. cycleN .. " cycle") or basePart
				t_insert(fullDPS.skills, { name = activeSkill.activeEffect.grantedEffect.name, dps = usedEnv.player.output.TotalDPS * cycleWeight, count = packCount, trigger = activeSkill.infoTrigger, skillPart = skillPartLabel })
				fullDPS.combinedDPS = fullDPS.combinedDPS + usedEnv.player.output.TotalDPS * packCount * cycleWeight
			end
			if usedEnv.player.output.CullMultiplier and usedEnv.player.output.CullMultiplier > 1 and usedEnv.player.output.CullMultiplier > fullDPS.cullingMulti then
				fullDPS.cullingMulti = usedEnv.player.output.CullMultiplier
			end

			-- Re-Build env calculator for new run
			local accelerationTbl = {
				nodeAlloc = true,
				requirementsItems = true,
				requirementsGems = true,
				skills = true,
				everything = true,
			}
			fullEnv, _, _, _ = calcs.initEnv(build, mode, override, { cachedPlayerDB = cachedPlayerDB, cachedEnemyDB = cachedEnemyDB, cachedMinionDB = cachedMinionDB, env = fullEnv, accelerate = accelerationTbl })
		end
	end

	-- Re-Add ailment DPS components
	if fullDPS.cullingMulti > 0 then
		fullDPS.cullingDPS = fullDPS.combinedDPS * (fullDPS.cullingMulti - 1)
		t_insert(fullDPS.skills, { name = "Full Culling DPS", dps = fullDPS.cullingDPS, count = 1 })
		fullDPS.combinedDPS = fullDPS.combinedDPS + fullDPS.cullingDPS
	end

	return fullDPS
end

-- Process active skill
function calcs.buildActiveSkill(env, mode, skill, limitedProcessingFlags)
	local fullEnv, _, _, _ = calcs.initEnv(env.build, mode, env.override)
	for _, activeSkill in ipairs(fullEnv.player.activeSkillList) do
		if cacheSkillUUID(activeSkill, fullEnv) == cacheSkillUUID(skill, env) then
			fullEnv.player.mainSkill = activeSkill
			fullEnv.player.mainSkill.skillData.limitedProcessing = limitedProcessingFlags and limitedProcessingFlags[cacheSkillUUID(activeSkill, fullEnv)]
			calcs.perform(fullEnv)
			return
		end
	end
	ConPrintf("[calcs.buildActiveSkill] Failed to process skill: " .. skill.activeEffect.grantedEffect.name)
end

-- Build output for display in the side bar or calcs tab
function calcs.buildOutput(build, mode)
	-- Build output for selected main skill
	local env, cachedPlayerDB, cachedEnemyDB, cachedMinionDB = calcs.initEnv(build, mode)
	calcs.perform(env)

	local output = env.player.output

	-- Build output across all skills added to FullDPS skills
	-- computeMinionBreakdown: only the MAIN display pass requests the (display-only)
	-- multi-skill minion breakdown (@leb-regression-guard:minion-skill-breakdown-display).
	local fullDPS = calcs.calcFullDPS(build, "CALCULATOR", {}, { cachedPlayerDB = cachedPlayerDB, cachedEnemyDB = cachedEnemyDB, cachedMinionDB = cachedMinionDB, env = nil, computeMinionBreakdown = (mode == "MAIN") })

	-- Add Full DPS data to main `env`
	env.player.output.SkillDPS = fullDPS.skills
	env.player.output.FullDPS = fullDPS.combinedDPS
	env.player.output.MinionSkillBreakdown = fullDPS.minionBreakdown

	-- @leb-regression-guard:main-skill-ailment-upper-panel
	-- Display-only: surface the main skill's damaging-ailment contributions in the upper panel
	-- (PoB parity). LEB imports each damaging ailment as a SEPARATE active skill (name == ailment
	-- name, trigger == parent skill name), so the main hit skill's own output has no <Ailment>DPS.
	-- For every damaging ailment, aggregate the matching-trigger entries from the Full DPS
	-- breakdown into output.MainSkill<Ailment>DPS, and publish a single combined
	-- output.MainSkillWithAilmentsDPS = TotalDPS + sum(all main-skill ailments). These are NEW
	-- output keys (not iterated by the snapshot deep-compare) so they are snapshot-safe.
	local mainSkill = env.player.mainSkill
	local mainSkillName = mainSkill and mainSkill.activeEffect and mainSkill.activeEffect.grantedEffect and mainSkill.activeEffect.grantedEffect.name
	local mainAilmentTotal = 0
	for ailmentName in pairs(data.damagingAilment) do
		local a = calcs.aggregateMainSkillAilment(output, fullDPS.skills, mainSkillName, ailmentName)
		if a > 0 then
			output["MainSkill" .. ailmentName .. "DPS"] = a
			mainAilmentTotal = mainAilmentTotal + a
		end
	end
	-- @leb-regression-guard:main-skill-ignite-upper-panel
	-- Preserve the original Ignite-specific keys (existing display rows + guard depend on them).
	local mainIgnite = output.MainSkillIgniteDPS or 0
	if mainIgnite > 0 then
		output.MainSkillWithIgniteDPS = (output.TotalDPS or 0) + mainIgnite
	end
	if mainAilmentTotal > 0 then
		output.MainSkillWithAilmentsDPS = (output.TotalDPS or 0) + mainAilmentTotal
	end

	-- @leb-regression-guard:total-dot-dps-row
	-- "Total DoT DPS" upper-panel row (PoB-parity, LE-correct). The selected skill's total
	-- damage-over-time = sum of its damaging-ailment DPS PLUS the skill's own DoT DPS when the
	-- skill is itself a damage-over-time skill (skillFlags.dot -> output.TotalDPS already IS the
	-- DoT, not a hit). LE ailments STACK, so this is a TOTAL (sum), NOT PoB's "Best"/max (a PoE
	-- non-stacking-ailment semantic); aggregateMainSkillAilment already sums each ailment with its
	-- per-ailment maxStacks clamp. "DoT" is LE-native vocabulary (AT_DoT / StatsPanel "Damage Over
	-- Time"), not a PoE-only term. Display-only NEW output key (snapshot-safe, same as the sibling
	-- MainSkill<Ailment>DPS keys). The display row's condFunc hides it when it would merely
	-- duplicate a single ailment row or the Hit DPS.
	-- See wiki concepts/le-dot-vs-ailment-and-stacking + REGRESSION_GUARDS.md "total-dot-dps-row".
	local mainSkillIsDot = mainSkill and mainSkill.skillFlags and mainSkill.skillFlags.dot
	local mainDotTotal = mainAilmentTotal + (mainSkillIsDot and (output.TotalDPS or 0) or 0)
	if mainDotTotal > 0 then
		output.MainSkillDotDPS = mainDotTotal
	end

	if mode == "MAIN" then
		for _, skill in ipairs(env.player.activeSkillList) do
			local uuid = cacheSkillUUID(skill, env)
			if not GlobalCache.cachedData["CACHE"][uuid] then
				calcs.buildActiveSkill(env, "CACHE", skill)
			end
			if GlobalCache.cachedData["CACHE"][uuid] then
				-- LE has no mana/life reservation: compare cost directly against the full pool.
				for pool, costResource in pairs({["Life"] = "LifeCost", ["Mana"] = "ManaCost", ["Rage"] = "RageCost"}) do
					local cachedCost = GlobalCache.cachedData["CACHE"][uuid].Env.player.output[costResource]
					if cachedCost then
						local totalPool = output[pool] or 0
						if totalPool < cachedCost then
							output[costResource.."Warning"] = output[costResource.."Warning"] or {}
							t_insert(output[costResource.."Warning"], skill.activeEffect.grantedEffect.name)
						end
					end
				end
				for _, costResource in pairs({"LifePercentCost", "ManaPercentCost"}) do
					local cachedCost = GlobalCache.cachedData["CACHE"][uuid].Env.player.output[costResource]
					if cachedCost and cachedCost > 100 then
						output[costResource.."PercentCostWarning"] = output[costResource.."PercentCostWarning"] or {}
						t_insert(output[costResource.."PercentCostWarning"], skill.activeEffect.grantedEffect.name)
					end
				end
			end
		end
	
		output.ExtraPoints = env.modDB:Sum("BASE", nil, "ExtraPoints")

		local specCfg = {
			source = "Tree"
		}
		output["Spec:LifeInc"] = env.modDB:Sum("INC", specCfg, "Life")
		output["Spec:ManaInc"] = env.modDB:Sum("INC", specCfg, "Mana")
		output["Spec:ArmourInc"] = env.modDB:Sum("INC", specCfg, "Armour", "ArmourAndEvasion")
		output["Spec:EvasionInc"] = env.modDB:Sum("INC", specCfg, "Evasion", "ArmourAndEvasion")
		output["Spec:WardInc"] = env.modDB:Sum("INC", specCfg, "Ward")

		-- Per-damage-type Crit Multiplier overview (player-level, no skill-specific scoping).
		-- Sums BASE CritMultiplier mods that match each damage-source's keywordFlags so users
		-- can sanity-check against LETools' per-type crit multi columns. Default base 100
		-- mirrors LE's baseCritMulti = 2.0 (i.e. +100% bonus on crit) before player extras.
		-- @leb-regression-guard:per-type-crit-multi-overview-keywordflags
		-- ModParser tags damage-source-prefixed mods (e.g. "Throwing Critical Strike Multiplier")
		-- via keywordFlags = KeywordFlag.<Source> (see ModParser.lua DamageSourceTypes loop).
		-- The cfg here MUST filter via keywordFlags (not flags) to actually match those mods;
		-- ModFlag.<Source> shares the same numeric value but lives in a different cfg bucket.
		-- Hit context is conveyed via flags = ModFlag.Hit, which is consistent with the
		-- modFlagList["on hit"] tagging in ModParser.lua.
		local critTypeKeywordFlags = {
			Melee = KeywordFlag.Melee,
			Spell = KeywordFlag.Spell,
			Bow = KeywordFlag.Bow,
			Throwing = KeywordFlag.Throwing,
		}
		for typeName, kwFlags in pairs(critTypeKeywordFlags) do
			local extra = env.modDB:Sum("BASE", { flags = ModFlag.Hit, keywordFlags = kwFlags }, "CritMultiplier")
			output[typeName .. "CritMultiplier"] = round(1 + (100 + extra) / 100, 2)
		end

		env.skillsUsed = { }
		for _, activeSkill in ipairs(env.player.activeSkillList) do
			for _, skillEffect in ipairs(activeSkill.effectList) do
				env.skillsUsed[skillEffect.grantedEffect.name] = true
			end
			if activeSkill.minion then
				for	_, activeSkill in ipairs(activeSkill.minion.activeSkillList) do
					env.skillsUsed[activeSkill.activeEffect.grantedEffect.id] = true
				end
			end
		end

		env.conditionsUsed = { }
		env.enemyConditionsUsed = { }
		env.minionConditionsUsed = { }
		env.multipliersUsed = { }
		env.enemyMultipliersUsed = { }
		env.perStatsUsed = { }
		env.enemyPerStatsUsed = { }
		env.tagTypesUsed = { }
		env.modsUsed = { }
		local function addTo(out, var, mod)
			-- Do not count Base mods as mods being actually used as they are only used as descriptors for mods
			if mod.source == "Base" then
				return
			end
			if not out[var] then
				out[var] = { }
			end
			t_insert(out[var], mod)
		end
		local function addVarTag(out, tag, mod)
			if tag.varList then
				for _, var in ipairs(tag.varList) do
					addTo(out, var, mod)
				end
			else
				addTo(out, tag.var, mod)
			end
		end
		local function addStatTag(out, tag, mod)
			if tag.varList then
				for _, var in ipairs(tag.statList) do
					addTo(out, var, mod)
				end
			elseif tag.stat then
				addTo(out, tag.stat, mod)
			end
		end
		local function addModTags(actor, mod)
			addTo(env.modsUsed, mod.name, mod)
			
			-- Imply enemy conditionals based on damage type
			-- Needed to preemptively show config options for elemental ailments
			for dmgType, conditions in pairs({["[fi][ig][rn][ei]t?e?"] = {"Ignited", "Burning"}, ["[cf][or][le][de]z?e?"] = {"Frozen"}}) do
				if mod.name:lower():match(dmgType) then
					for _, var in ipairs(conditions) do
						addTo(env.enemyConditionsUsed, var, mod)
					end
				end
			end
			
			for _, tag in ipairs(mod) do
				addTo(env.tagTypesUsed, tag.type, mod)
				if tag.type == "IgnoreCond" then
					break
				elseif tag.type == "Condition" then
					if actor == env.player then
						addVarTag(env.conditionsUsed, tag, mod)
					else
						addVarTag(env.minionConditionsUsed, tag, mod)
					end
				elseif tag.type == "ActorCondition" and tag.var then
					if tag.actor == "enemy" then
						addTo(env.enemyConditionsUsed, tag.var, mod)
					else
						addTo(env.conditionsUsed, tag.var, mod)
					end
				elseif tag.type == "Multiplier" or tag.type == "MultiplierThreshold" then
					if not tag.actor then
						if actor == env.player then
							addVarTag(env.multipliersUsed, tag, mod)
						end
					elseif tag.actor == "enemy" then
						addVarTag(env.enemyMultipliersUsed, tag, mod)
					end
				elseif tag.type == "PerStat" or tag.type == "StatThreshold" then
					if not tag.actor then
						if actor == env.player then
							addStatTag(env.perStatsUsed, tag, mod)
						end
					elseif tag.actor == "enemy" then
						addStatTag(env.enemyPerStatsUsed, tag, mod)
					end
				end
			end
		end
		for _, actor in ipairs({env.player, env.minion}) do
			for modName, modList in pairs(actor.modDB.mods) do
				for _, mod in ipairs(modList) do
					addModTags(actor, mod)
				end
			end
		end
		for _, activeSkill in pairs(env.player.activeSkillList) do
			for _, mod in ipairs(activeSkill.baseSkillModList) do
				addModTags(env.player, mod)
			end
			for _, mod in ipairs(activeSkill.skillModList) do
				addTo(env.modsUsed, mod.name, mod)
				for _, tag in ipairs(mod) do
					addTo(env.tagTypesUsed, tag.type, mod)
				end
			end
			if activeSkill.minion then
				for _, activeSkill in pairs(activeSkill.minion.activeSkillList) do
					for _, mod in ipairs(activeSkill.baseSkillModList) do
						addModTags(env.minion, mod)
					end
				end
			end
		end
		for modName, modList in pairs(env.enemyDB.mods) do
			for _, mod in ipairs(modList) do
				for _, tag in ipairs(mod) do
					if tag.type == "IgnoreCond" then
						break
					elseif tag.type == "Condition" then
						addVarTag(env.enemyConditionsUsed, tag, mod)
					elseif tag.type == "ActorCondition" and tag.var then
						if tag.actor == "enemy" or tag.actor == "player" then
							addTo(env.conditionsUsed, tag.var, mod)
						else
							addTo(env.enemyConditionsUsed, tag.var, mod)
						end
					elseif tag.type == "Multiplier" or tag.type == "MultiplierThreshold" then
						if not tag.actor then
							addVarTag(env.enemyMultipliersUsed, tag, mod)
						end
					end
				end
			end
		end
--		ConPrintf("=== Cond ===")
--		ConPrintTable(env.conditionsUsed)
--		ConPrintf("=== Mult ===")
--		ConPrintTable(env.multipliersUsed)
--		ConPrintf("=== Minion Cond ===")
--		ConPrintTable(env.minionConditionsUsed)
--		ConPrintf("=== Enemy Cond ===")
--		ConPrintTable(env.enemyConditionsUsed)
--		ConPrintf("=== Enemy Mult ===")
--		ConPrintTable(env.enemyMultipliersUsed)
	elseif mode == "CALCS" then
		local buffList = { }
		local combatList = { }
		local curseList = { }
		for name in pairs(env.buffs) do
			t_insert(buffList, name)
		end
		table.sort(buffList)
		env.player.breakdown.SkillBuffs = { modList = { } }
		for _, name in ipairs(buffList) do
			for _, mod in ipairs(env.buffs[name]) do
				local value = env.modDB:EvalMod(mod)
				if value and value ~= 0 then
					t_insert(env.player.breakdown.SkillBuffs.modList, {
						mod = mod,
						value = value,
					})
				end
			end
		end
		env.player.breakdown.SkillDebuffs = { modList = { } }
		for name, modList in pairs(env.debuffs) do
			t_insert(curseList, name)
		end
		table.sort(curseList)
		for index, name in ipairs(curseList) do
			for _, mod in ipairs(env.debuffs[name]) do
				local value = env.enemy.modDB:EvalMod(mod)
				if value and value ~= 0 then
					t_insert(env.player.breakdown.SkillDebuffs.modList, {
						mod = mod,
						value = value,
					})
				end
			end
			local stackCount = env.debuffs[name]:Sum("BASE", nil, "Multiplier:"..name.."Stack")
			if stackCount > 0 then
				curseList[index] = name .. " (" .. round(stackCount, 2) .. " stack" .. (stackCount > 1 and "s" or "") .. ")"
			end
		end
		for _, slot in ipairs(env.curseSlots) do
			t_insert(curseList, slot.name)
			if slot.modList then
				for _, mod in ipairs(slot.modList) do
					local value = env.enemy.modDB:EvalMod(mod)
					if value and value ~= 0 then
						t_insert(env.player.breakdown.SkillDebuffs.modList, {
							mod = mod,
							value = value,
						})
					end
				end
			end
		end
		output.BuffList = table.concat(buffList, ", ")
		output.CombatList = table.concat(combatList, ", ")
		output.CurseList = table.concat(curseList, ", ")
		if env.minion then
			local buffList = { }
			local combatList = { }
			for name in pairs(env.minionBuffs) do
				t_insert(buffList, name)
			end
			table.sort(buffList)
			env.minion.breakdown.SkillBuffs = { modList = { } }
			for _, name in ipairs(buffList) do
				for _, mod in ipairs(env.minionBuffs[name]) do
					local value = env.minion.modDB:EvalMod(mod)
					if value and value ~= 0 then
						t_insert(env.minion.breakdown.SkillBuffs.modList, {
							mod = mod,
							value = value,
						})
					end
				end
			end
			env.minion.breakdown.SkillDebuffs = env.player.breakdown.SkillDebuffs
			output.Minion.BuffList = table.concat(buffList, ", ")
			output.Minion.CombatList = table.concat(combatList, ", ")
			output.Minion.CurseList = output.CurseList
		end

		-- infoDump(env)
	end

	return env
end

return calcs
