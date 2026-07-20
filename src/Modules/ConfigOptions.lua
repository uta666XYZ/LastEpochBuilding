-- Last Epoch Building
--
-- Module: Config Options
-- List of options for the Configuration tab.
--

local m_min = math.min
local m_max = math.max
local s_format = string.format

local function LowLifeTooltip(modList, build)
	local out = 'You will automatically be considered to be on Low ^xE05030Life ^7if you have at least '..100 - build.calcsTab.mainOutput.LowLifePercentage..'% ^xE05030Life ^7reserved'
	out = out..'\nbut you can use this option to force it if necessary.'
	return out
end

local function FullLifeTooltip(modList, build)
	local out = 'You can be considered to be on Full ^xE05030Life ^7if you have at least '..build.calcsTab.mainOutput.FullLifePercentage..'% ^xE05030Life ^7left.'
	out = out..'\nYou will automatically be considered to be on Full ^xE05030Life ^7if you have Chaos Inoculation,'
	out = out..'\nbut you can use this option to force it if necessary.'
	return out
end


-- @leb-regression-guard:config-tooltip-no-internal-info
-- Config `tooltip` strings are USER-FACING. They must not leak internal
-- developer info: internal tree/node ids (e.g. "eb5656-2"), references to
-- REGRESSION_GUARDS.md, internal code symbols (e.g. "DreadShadeMutator."),
-- or raw mod-tag syntax ("Condition:X" / "Multiplier:X"). Use plain
-- in-game language and real node/skill display names only. The 2026-05-30
-- pass removed an "eb5656-2" node id + two REGRESSION_GUARDS.md references
-- + a "DreadShadeMutator.DelayedCastOnMinion" symbol + a "Condition:Cursed"
-- tag from these tooltips. Spec: spec/System/TestConfigTooltipNoInternalInfo_spec.lua.
local options = {
	-- Section: General options
	{ section = "General", col = 1 },
	{ var = "questApophisMajasa", type = "check", label = "Apophis and Majasa?", tooltip = "Quest reward: +1 to all attributes. Enable once you have defeated Apophis and Majasa on this character.", apply = function(val, modList, enemyModList)
		-- @leb-regression-guard:quest-apophis-majasa-plus-one
		-- LE in-game Completed Quests panel shows "Attribute Points: 1" for the
		-- Apophis and Majasa quest. Granted as +1 to each of Str/Dex/Int/Att/Vit.
		-- Verified via in-game screenshot 2026-05-08 (Total 2/2 across both
		-- Apophis and Temple of Eterra; each contributes 1).
		modList:NewMod("Str", "BASE", 1, "Quest")
		modList:NewMod("Dex", "BASE", 1, "Quest")
		modList:NewMod("Int", "BASE", 1, "Quest")
		modList:NewMod("Att", "BASE", 1, "Quest")
		modList:NewMod("Vit", "BASE", 1, "Quest")
	end },
	{ var = "questTempleOfEterra", type = "check", label = "Temple of Eterra?", tooltip = "Quest reward: +1 to all attributes. Enable once you have completed the Temple of Eterra quest on this character.", apply = function(val, modList, enemyModList)
		-- @leb-regression-guard:quest-apophis-majasa-plus-one
		-- LE in-game Completed Quests panel shows "Attribute Points: 1" for the
		-- Temple of Eterra quest. Granted as +1 to each of Str/Dex/Int/Att/Vit.
		-- Verified via in-game screenshot 2026-05-08 (sibling site of the
		-- Apophis and Majasa apply block above — shares the same index entry
		-- because both rewards must coexist as separate +1/+1, never +2/0).
		-- Spec: spec/System/TestQuestApophisMajasa_spec.lua
		--       "QuestTempleOfEterra applies +1 BASE to all five attributes"
		modList:NewMod("Str", "BASE", 1, "Quest")
		modList:NewMod("Dex", "BASE", 1, "Quest")
		modList:NewMod("Int", "BASE", 1, "Quest")
		modList:NewMod("Att", "BASE", 1, "Quest")
		modList:NewMod("Vit", "BASE", 1, "Quest")
	end },
	-- @leb-regression-guard:refracted-rank-gating
	-- Character progression input: how many of the altar's idol-slot unlock
	-- rewards this character has earned (game: IdolsContainerGridData
	-- MaxIdolSlotUnlockRewards = 8; refracted cells encode activation rank as
	-- unlockMatrix value - 100). Cells above the current rank act as NORMAL
	-- slots — no refracted-slot boost, no Multiplier:IdolInRefractedSlot count.
	-- Default 8 = all cells active (pre-existing behavior).
	{ var = "idolAltarUnlockRank", type = "count", label = "Idol Altar unlock rank:", defaultPlaceholderState = 8,
		tooltip = "How many Idol Altar slot-unlock rewards this character has earned (0-8).\nRefracted cells with a higher activation rank act as normal slots:\nthey grant no refracted-slot affix boosts and don't count for 'per Idol in a Refracted Slot' modifiers.\nDefault 8 = fully unlocked altar." },
	{ var = "conditionStationary", type = "count", label = "Time spent stationary", ifCond = "Stationary",
		tooltip = "Applies mods that use `while stationary` and `per / every second while stationary`",
		apply = function(val, modList, enemyModList)
		if type(val) == "boolean" then
			-- Backwards compatibility with older versions that set this condition as a boolean
			val = val and 1 or 0
		end
		local sanitizedValue = m_max(0, val)
		modList:NewMod("Multiplier:StationarySeconds", "BASE", sanitizedValue, "Config")
		if sanitizedValue > 0 then
			modList:NewMod("Condition:Stationary", "FLAG", true, "Config")
		end
	end },
	{ var = "conditionMoving", type = "check", label = "Are you always moving?", ifCond = "Moving", tooltip = "Enable if your build is always moving during combat (e.g., movement-based attack builds).\nEnables 'while moving' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Moving", "FLAG", true, "Config")
	end },
	{ var = "conditionCharging", type = "check", label = "Are you Charging?", ifCond = "Charging", tooltip = "Check if the player is Charging (Shield Charge, Lunge, etc.).\nEnables 'while charging' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Charging", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionFullLife", type = "check", label = "Are you always on Full ^xE05030Life?", ifCond = "FullLife", suggestPattern = { "while at full health", "while at full life", "while on full health", "on full health" }, tooltip = FullLifeTooltip, apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:FullLife", "FLAG", true, "Config")
	end },
	-- @leb-regression-guard:config-highlight-suggest-pattern (Phase 5 Low Health 系)
	-- Phrases verified against LEB src/Data/Uniques/uniques_1_4.json and
	-- src/TreeData/1_4/tree_*.json — DO NOT add a phrase you cannot grep
	-- to actual 1.4 content. Architects of Astral Blood (uniques L9209)
	-- is the canonical "20% of Current Health Lost per second" / "Low
	-- Health" build trigger; many other uniques + several idol affixes
	-- use the same vocabulary.
	{ var = "conditionLowLife", type = "check", label = "Are you always on Low ^xE05030Life?", ifCond = "LowLife", suggestPattern = { "low health", "low life", "current health lost per second", "current health drained per second", "while at low", "while on low life", "while on low health", "below half health", "below 35% of your maximum health", "missing health" }, tooltip = LowLifeTooltip, apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:LowLife", "FLAG", true, "Config")
	end },
	-- @leb-regression-guard:mana-missing-not-full-mechanics
	-- LE mana scaling is "Missing Mana" (continuous: "per 5 missing mana",
	-- "per 2% missing mana") + "While Not Full Mana" (binary). LE has NO
	-- "full mana" / "low mana" threshold-bonus affix -- so the previous
	-- conditionFullMana / conditionLowMana checks (Condition:FullMana /
	-- Condition:LowMana, which had ZERO calc consumers) were the wrong
	-- abstraction and are replaced by this single missing-mana% count. The
	-- planner models current mana as FULL by default (see ModParser "per N
	-- current mana" guard), so missing mana defaults to 0 and "while not full
	-- mana" mods are OFF until the user sets this. Mirrors
	-- playerMissingHealthPercent. Drives, via ModParser modTagList entries:
	--   * Multiplier:MissingManaPercent (this value)        -> "per N% missing mana"
	--   * Multiplier:MissingMana (Mana x %/100, CalcPerform) -> "per N missing mana"
	--   * Condition:NotFullMana (when > 0)                   -> "while not full mana"
	-- Spec: spec/System/TestConfigManaMechanics_spec.lua
	{ var = "playerMissingManaPercent", type = "count", label = "Your Missing ^x7070FFMana ^7%:", suggestPattern = { "missing mana", "while not full mana", "not full mana", "per missing mana" }, tooltip = "Percentage of your maximum ^x7070FFmana ^7that is currently missing.\nLE has no static current mana (it fluctuates per cast); the planner models FULL mana by default, so set this to model 'per missing mana' and 'while not full mana' modifiers (e.g. Smite / Paladin missing-mana scaling).", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:MissingManaPercent", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		if val > 0 then
			modList:NewMod("Condition:NotFullMana", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		end
	end },
	{ var = "minionsConditionFullLife", type = "check", label = "Are your Minions always on Full ^xE05030Life?", ifMinionCond = "FullLife", tooltip = "Enables 'while at full life' modifiers for minions.\nLeave unchecked for realistic estimates unless your minions never take damage.", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Condition:FullLife", "FLAG", true, "Config") }, "Config")
	end },
	{ var = "minionsConditionCreatedRecently", type = "check", label = "Have your Minions been created Recently?", ifCond = "MinionsCreatedRecently", tooltip = "Enable if your minions are regularly re-summoned during combat.\nFor boss DPS estimates, leave unchecked unless you refresh minions frequently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:MinionsCreatedRecently", "FLAG", true, "Config")
	end },
	-- @leb-regression-guard:minion-frenzy-multiplicative
	-- Validation provenance is retained in maintainer notes.
	{ var = "minionsConditionFrenzy", type = "check", label = "Do your Minions have Frenzy?", tooltip = "Minions with the Frenzy buff attack and cast 20% faster (multiplicative).\nMeasured on Manifest Armor melee cadence; sources include 'seconds of Haste and Frenzy for your minions' effects.", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Condition:Frenzy", "FLAG", true, "Config") }, "Config")
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Speed", "MORE", 20, "MinionFrenzy") }, "Config")
	end },
	-- @leb-regression-guard:minion-multiskill-cadence-fold (config gate)
	-- Validation provenance is retained in maintainer notes.
	{ var = "minionMultiSkillCadenceFold", type = "check", defaultState = true, label = "Fold multi-skill minion cadence into Full DPS?", tooltip = "Some minions cast several damaging skills on one action timeline (e.g. Manifest Armor: Melee + Forge Breath + Whirlwind + Charge), but Full DPS otherwise counts only the minion's main skill.\nThis folds the secondary skills in using their measured firing cadence x per-hit damage — far closer to the true output than the main-skill-only number.\nApplies only to minions with a measured cadence table whose skill set matches the measurement. The cadence is measured at a reference minion speed, so a much faster or slower minion carries a small error on the melee/spin terms. Uncheck for the conservative main-skill-only estimate.", apply = function(val, modList, enemyModList)
		if val then
			modList:NewMod("Condition:MinionMultiSkillCadenceFold", "FLAG", true, "Config")
		end
	end },
	-- @leb-regression-guard:dragonflame-nova-proc-rate (config input)
	-- "When you use a minion skill" trigger sources (today: Dragonflame Edict's
	-- Dragonflame Nova, rate = min(60% x use-rate, 1/s) -- both factors datamined)
	-- need the PLAYER's minion-skill use cadence. Default (0 / unset) = the summoning
	-- skill's own cast rate at the fold site (usedEnv.player.output.Speed -- the rate
	-- the build could actually re-use its minion skill; steady-state re-summon spam).
	-- A build whose real cadence differs (e.g. permanent companions, minion skill
	-- pressed rarely) sets the true uses-per-second here. NO curve-fit: the default
	-- is the build's own modeled cast rate, the override is user ground truth.
	{ var = "minionSkillUsesPerSecond", type = "float", label = "Minion skill uses per second:", tooltip ="How often you actually USE a minion skill (uses per second), for 'when you use a minion skill' proc triggers (e.g. Dragonflame Edict's Dragonflame Nova).\nLeave empty to use the summoning skill's own cast rate (steady-state re-summon spam).\nSet a lower value if you rarely press your minion skills (e.g. permanent companions).", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionSkillUsesPerSecond", "BASE", val, "Config")
	end },
	-- @leb-regression-guard:no-vestigial-liferegen-burst-config
	-- "lifeRegenMode" (PoB burst-life-regen averaging: LifeRegenBurstAvg/Full)
	-- was removed 2026-06-02. LE life regen is continuous — there is no "burst
	-- regen" mechanic, and the LifeRegenBurst* conditions were read NOWHERE in
	-- the calc (the PoB burst-regen pipeline was never ported). It was an inert
	-- selector that did nothing. Do NOT re-port it from PoB (no-PoE-in-LEB).
	-- Spec: spec/System/TestConfigNoVestigialBurstRegen_spec.lua
	{ var = "resourceGainMode", type = "list", label = "Resource gain calculation mode:", ifCond = "AverageResourceGain", defaultIndex = 2, tooltip = "Controls how resource on hit/kill is calculated:\n\tMinimum: does not include chances\n\tAverage: includes chance gains, averaged based on uptime\n\tMaximum: treats all chances as certain", list = {{val="MIN",label="Minimum"},{val="AVERAGE",label="Average"},{val="MAX",label="Maximum"}}, apply = function(val, modList, enemyModList)
		if val == "AVERAGE" then
			modList:NewMod("Condition:AverageResourceGain", "FLAG", true, "Config")
		elseif val == "MAX" then
			modList:NewMod("Condition:MaxResourceGain", "FLAG", true, "Config")
		end
	end },
	{ var = "EHPUnluckyWorstOf", type = "list", label = "EHP calc unlucky:", tooltip = "Sets the EHP calc to pretend its unlucky and reduce the effects of random events", list = {{val=1,label="Average"},{val=2,label="Unlucky"},{val=4,label="Very Unlucky"}} },
	{ var = "DisableEHPGainOnBlock", type = "check", label = "Disable EHP gain on block:", ifMod = {"LifeOnBlock", "ManaOnBlock"}, tooltip = "Sets the EHP calc to not apply gain on block effects"},

	-- Section: Skill-specific options
	{ section = "Skill Options", col = 2 },

	{ label = "Player is cursed by:" },
	-- @leb-regression-guard:config-highlight-suggest-pattern (player-cursed)
	-- suggestPattern fires the orange-label highlight (ConfigTab.lua) when the
	-- allocated passive tree mentions any of these phrases. ' doubled if cursed'
	-- catches ch0fs-20 Death from Below / ch0fs-14 Eradication (notScalingStats,
	-- via PassiveTree node.sd). 'while you are cursed' / 'while cursed' catches
	-- assorted self-curse interactions. Highlight only — does NOT toggle.
	{ var = "conditionCursed", type = "check", label = "Are you Cursed?", suggestPattern = { "doubled if cursed", "while you are cursed", "while cursed" }, suggestCond = "Cursed", tooltip = "Check if the player is Cursed (e.g. via Acolyte passives/skills).\nEnables 'while cursed' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Cursed", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:ward-per-second-and-retention-family (W5)
	-- @leb-regression-guard:config-highlight-suggest-pattern (curse-on-self count)
	{ var = "multiplierCurseOnSelf", type = "count", label = "# of Curses on you:", ifMult = "CurseOnSelf", implyCond = "Cursed", suggestPattern = { "curse on you", "curses on you", "curses affecting you", "per curse on you", "bone curse self" }, tooltip = "Number of distinct Curses currently affecting you.\nEnables 'for each Curse affecting you' modifiers (e.g. Bone Curse self-curse stacking).\nAlso treats you as Cursed.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:CurseOnSelf", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:Cursed", "FLAG", val >= 1, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:config-visibility-gating
	-- E batch 1 (2026-06-01): gate previously-always-shown "while you have
	-- <buff>" / "per <stack>" state configs with ifCond/ifMult = the SAME
	-- Condition/Multiplier their apply sets. They then appear in the Config
	-- tab only when the build actually has a modifier referencing that
	-- state (mainEnv.conditionsUsed[key] / multipliersUsed[key] non-empty),
	-- instead of cluttering every build's tab. Correct-by-construction:
	-- the config is shown iff a mod uses the state, which is exactly when
	-- toggling it matters; if no such mod exists, the toggle is inert so
	-- hiding is right. An enabled (non-default) config still shows (the
	-- shown-closure keeps value-set configs visible) and "Show All
	-- Configurations" reveals everything, so nothing becomes unreachable.
	--
	-- CRITICAL — only gate keys the MOD PARSER actually emits. A gate key
	-- that no parsed mod ever produces would make the config PERMANENTLY
	-- hidden (conditionsUsed[key] always empty). The spec enforces this:
	-- every gate var here must appear as `var = "<key>"` in ModParser. That
	-- is why these are NOT gated in this batch (their Condition var is never
	-- emitted, only set by the config's own apply): conditionHaveFlameWard,
	-- conditionHaveEterrasBlessing, and the four *Overload configs (mods use
	-- the generic HaveAilmentOverload / Multiplier:ActiveOverload, never the
	-- per-ailment Condition). Base-calc configs (Full/Low Life, Full/Low
	-- Mana, High Health) also stay gateless — they affect EHP/resource even
	-- without a conditional mod, so gating them would over-hide.
	-- Spec: spec/System/TestConfigVisibilityGating_spec.lua.
	{ var = "conditionTransformed", type = "check", label = "Are you Transformed?", ifCond = "Transformed", tooltip = "Check if the player is Transformed (Werebear, Spriggan Form, etc.).\nEnables 'while transformed' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Transformed", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:druid-form-base-aura
	-- Werebear/Spriggan forms grant an inherent "base aura" buff while transformed.
	-- LEB previously only set the Condition:In*Form / Condition:Transformed FLAGs (so
	-- "while transformed" modifiers applied) but NEVER applied the form's own base
	-- buff stats, so a transformed Druid was missing flat form bonuses. The base-aura
	-- stats are datamined ground truth (datamined game source extracted/form_auras_decoded.json,
	-- BuffParent.stats of each form's buff prefab):
	--   WerebearForm  : Damage(Melee) increased 0.5 (+50%), Health increased 0.15 (+15%),
	--                   ManaRegen more -1.0 (-100%), ManaDrain added 5.
	--   SprigganForm  : Damage(Spell) increased 0.5 (+50%), Armour added 300,
	--                   ManaRegen more -1.0 (-100%), ManaDrain added 5.
	-- We apply every stat LEB can represent. ManaDrain is intentionally OMITTED: LEB has
	-- no ManaDrain / mana-degen-per-second stat (grep: 0 hits), so there is nothing to
	-- map it onto -- modelling in-form mana drain is a separate follow-up. The values are
	-- transcribed verbatim from the datamine (no fabrication). Spec: TestDruidFormBaseAura.
	{ var = "conditionInWerebearForm", type = "check", label = "Are you in Werebear Form?", ifCond = "InWerebearForm", implyCond = "Transformed", tooltip = "This also implies that you are Transformed.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:InWerebearForm", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:Transformed", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		-- Werebear Form base aura (form_auras_decoded.json: WerebearForm.aura_stats)
		modList:NewMod("Damage", "INC", 50, "Werebear Form", ModFlag.Melee)
		modList:NewMod("Life", "INC", 15, "Werebear Form")
		modList:NewMod("ManaRegen", "MORE", -100, "Werebear Form")
	end },
	{ var = "conditionInSprigganForm", type = "check", label = "Are you in Spriggan Form?", ifCond = "InSprigganForm", implyCond = "Transformed", tooltip = "This also implies that you are Transformed.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:InSprigganForm", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:Transformed", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		-- Spriggan Form base aura (form_auras_decoded.json: SprigganForm.aura_stats)
		modList:NewMod("Damage", "INC", 50, "Spriggan Form", ModFlag.Spell)
		modList:NewMod("Armour", "BASE", 300, "Spriggan Form")
		modList:NewMod("ManaRegen", "MORE", -100, "Spriggan Form")
	end },
	-- @leb-regression-guard:minion-aura-player-application (config site)
	-- The Summon Spriggan companion's Healing Aura (sp38 "Aura of X" nodes) buffs
	-- ALL ALLIES within 20m of the Spriggan, i.e. the player. This toggle gates that
	-- player-side application (LE_MINION_AURA_PLAYER_NODES -> Condition:InSprigganHealingAura).
	-- It is INDEPENDENT of Spriggan Form (a Beastmaster can run the companion without
	-- transforming) so it does NOT imply Transformed. Default off; for an in-form melee
	-- basic attack (Spirit Thorns: in-game stdev=0) the player is co-located with the
	-- companion every cast, so the aura is effectively always up for those skills.
	{ var = "conditionInSprigganHealingAura", type = "check", label = "Within your Spriggan's Healing Aura?", ifCond = "InSprigganHealingAura", tooltip = "Check if you are standing inside your Summon Spriggan companion's Healing Aura (20 metre radius).\nEnables the Summon Spriggan 'Aura of ...' tree nodes that grant you and your allies bonuses, e.g. +5 Spell Damage per point of Aura of Kinship.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:InSprigganHealingAura", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionInSwarmbladeForm", type = "check", label = "Are you in Swarmblade Form?", ifCond = "InSwarmbladeForm", implyCond = "Transformed", tooltip = "This also implies that you are Transformed.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:InSwarmbladeForm", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:Transformed", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionInReaperForm", type = "check", label = "Are you in Reaper Form?", ifCond = "InReaperForm", implyCond = "Transformed", tooltip = "This also implies that you are Transformed.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:InReaperForm", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:Transformed", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHighHealth", type = "check", label = "Are you at High Health?", tooltip = "Check if you are at High Health (typically 50%+ of max health).\nEnables 'while at high health' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HighHealth", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:config-highlight-suggest-pattern (Phase 5 Ward 系)
	-- Phrases verified against src/Data/Uniques/uniques_1_4.json — `ward per
	-- second` / `ward retention` / `ward decay threshold` / `gained as ward`
	-- / `ward gained on` / `ward limit` are the canonical Ward-generation
	-- / Ward-modification vocabulary; any build carrying these affixes
	-- clearly cares about Ward state, so `conditionHaveWard` should
	-- highlight. `while you have ward` is the consumption phrasing that
	-- equally indicates relevance.
	{ var = "conditionHaveWard", type = "check", label = "Do you have Ward?", ifCond = "HaveWard", suggestPattern = { "ward per second", "ward retention", "ward decay threshold", "gained as ward", "ward gained on", "ward limit", "while you have ward", "ward on hit", "of mana spent gained as ward" }, tooltip = "Enable if your build generates Ward during combat.\nWard is a temporary shield that absorbs damage before Health. Enables 'while you have Ward' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveWard", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHaveLightningAegis", type = "check", label = "Do you have Lightning Aegis?", ifCond = "HaveLightningAegis", suggestBuff = "LightningAegis", tooltip = "Check if you have the Lightning Aegis buff active (Runemaster).\nEnables 'while you have lightning aegis' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveLightningAegis", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHaveFlameWard", type = "check", label = "Do you have Flame Ward active?", suggestBuff = "FlameWard", tooltip = "Check if Flame Ward is currently active (Mage).\nFlame Ward is a 3-second duration defensive buff (not a permanent aura), so its skill-tree contributions only apply while the buff is up.\nEnabling this gates Flame Ward tree node mods (e.g. +10% Block Chance from Glacial Reinforcement) on top of the SkillsTab toggle.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveFlameWard", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHaveEterrasBlessing", type = "check", label = "Do you have Eterra's Blessing active?", suggestBuff = "EterrasBlessing", tooltip = "Check if Eterra's Blessing is currently active (Primalist).\nEterra's Blessing is a 4-second-duration cast buff, so its skill-tree contributions only apply while the buff is up.\nEnabling this gates Eterra's Blessing tree node mods (e.g. 'Safeguard') on top of the SkillsTab toggle.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveEterrasBlessing", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:vengeance-bolster-player-buff (config site)
	-- Vengeance tree node gs15de-19 "Bolster" grants a PLAYER-WIDE conditional
	-- defensive self-buff (-13% Less Damage Taken MORE / +25% Increased Armour per
	-- point) "if you've hit an enemy with Vengeance in the past 2 seconds". The mod
	-- is lifted to the player sheet (SkillId stripped) via
	-- LE_TREE_NODE_PLAYER_CONDITIONAL_BUFF and gated by this Condition. Default OFF:
	-- the description trigger is a 2s recency window, but for a Vengeance build that
	-- spams the skill it is effectively always up in combat — enable to model that.
	{ var = "conditionHaveBolster", type = "check", label = "Do you have Bolster active? (Vengeance)", ifCond = "HaveBolster", tooltip = "Check if Vengeance's 'Bolster' node buff is active (Forge Guard / Paladin).\nBolster grants 'less damage taken (multiplicative)' and 'increased armour' if you have hit an enemy with Vengeance in the past 2 seconds.\nEnabling this applies the Bolster tree node's defensive mods to the player sheet (e.g. -26% damage taken / +50% increased armour at 2/2).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveBolster", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:holy-aura-damage-mutator-buff (config site)
	-- Holy Aura's INTRINSIC default damage aura ("+30% increased damage" passive,
	-- abilities_localization.json Ability_HolyAura_Description) is absent from
	-- skills.json + all tree data, so LEB contributed 0 for it. This toggle gates
	-- injecting it as a config-gated GLOBAL buff in CalcSetup (scaled by HolyAuraEffect;
	-- see that guard + calcs.holyAuraDamageAuraMods for the game-source derivation).
	-- Default OFF (opt-in; matches the conditionHave* buff-toggle convention) so the
	-- corpus is unchanged and a build that took a disable-default-stats node stays at 0.
	-- The Condition var is set only by this apply (not ModParser-emitted), so no ifCond
	-- highlight -- like conditionHaveFlameWard. The elemental fire/light damage some
	-- Holy Aura builds show is the ah443-7 "Firestorm" TREE node, already modelled via
	-- the buff-tree path -- NOT this toggle (it would double-count).
	-- Spec: spec/System/TestHolyAuraDamageMutator_spec.lua
	{ var = "conditionHolyAuraDamageAura", type = "check", label = "Holy Aura grants its damage aura?", suggestBuff = "HolyAura", tooltip = "Check if your Holy Aura grants its intrinsic damage aura (Paladin).\nHoly Aura's passive '30% increased damage' aura is applied globally, scaled by your Holy Aura effect.\nLeave OFF if your build disables Holy Aura's default stats. The fire/lightning damage from the 'Firestorm' tree node is modelled separately and is NOT gated by this toggle.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HolyAuraDamageAura", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:enchant-weapon-buff (config site)
	-- Enchant Weapon's ACTIVE tier: "Active: ... Your melee attacks deal 50% more elemental
	-- damage for 5 seconds" (abilities_localization.json Ability_EnchantWeapon_Description;
	-- serialized EnchantWeaponMutator.defaultStat = Damage [Elemental, Melee] MORE 0.5).
	-- The Active REPLACES the always-on Passive tier (15% more, applied automatically in
	-- CalcSetup whenever Enchant Weapon is on the bar + enabled) -- capture-proven on
	-- 4guanghuan (Cold in-game/LEB ~= 1.5, not 1.725). Default OFF (opt-in; matches the
	-- conditionHave* buff-toggle convention) so the corpus only gains the passive tier.
	-- The Condition var is set only by this apply (not ModParser-emitted), so no ifCond.
	-- Spec: spec/System/TestEnchantWeaponBuff_spec.lua
	{ var = "conditionEnchantWeaponActive", type = "check", label = "Is Enchant Weapon's Active buff up?", suggestBuff = "EnchantWeapon", tooltip = "Check if Enchant Weapon's ACTIVE enchantment is currently up (Spellblade).\nActivating Enchant Weapon makes your melee attacks deal 50% MORE elemental damage for 5 seconds, replacing the passive 15% tier (which LEB applies automatically while the skill is slotted and enabled).\nWith the 'Kindling Blade' tree node (auto-cast on melee attack) the Active tier has effectively 100% uptime.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:EnchantWeaponActive", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionMinionsHaveDreadShade", type = "check", label = "Do your minions have Dread Shade?", suggestBuff = "DreadShade", tooltip = "Check if at least one of your minions currently has the Dread Shade buff active (Necromancer).\nDread Shade is a per-target buff, so its tree-node contributions to minions (e.g. Martyrdom's '30 Minion Armour per Vitality') only apply to minions that actually carry the buff.\nEnabling this gates Dread Shade tree node minion-side mods on top of the SkillsTab toggle.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:MinionsHaveDreadShade", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:tyrant-skull-per-attribute-minion-scope (config gate)
	-- Validation provenance is retained in maintainer notes.
	{ var = "conditionTyrantSkullPerAttribute", type = "check", label = "Apply Tyrant's Skull per-attribute Tyrannosaur block?", tooltip = "Check to apply Tyrant's Skull's per-attribute scaling to its summoned Tyrannosaur (+Melee Damage per Strength, more Health/Damage per Uncapped Endurance, per-Int phys pen, per-Att crit multi, per-Dex attack/cast speed).\nCoefficients are confirmed from the in-game item tooltip, but the applied magnitude currently OVERSHOOTS the deterministic in-game per-hit (engine added-damage-scaling/baseline not yet pinned), so this is OFF by default. Leave OFF for accurate Tyrannosaur DPS.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:TyrantSkullPerAttribute", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionStandingOnGlyphOfDominion", type = "check", label = "Standing on Glyph of Dominion?", tooltip = "Check if you are standing on your Glyph of Dominion (Runemaster).\nEnables 'while standing on your Glyph of Dominion' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:StandingOnGlyphOfDominion", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:ward-stop-moving-config-amortize (config site)
	-- Gates the Transient Rest unique affix "X% of Current Mana gained as Ward
	-- when you stop moving (2 second cooldown)". Game-side field is
	-- `currentManaGainedAsWardOnStopMoving` (datamined game source offset 0xDB0) with
	-- a hardcoded 2-second cooldown (L95851). The contribution is event-driven
	-- in-game; LEB amortizes it as a steady-state continuous wps in
	-- CalcPerform's post-offence ward fold-in, but ONLY when this Condition is
	-- on (default off — preserves baseline parity with LETools UI which does
	-- not surface event-driven ward sources).
	-- Spec: spec/System/TestWardStopMovingConfigAmortize_spec.lua
	{ var = "conditionStoppedMoving", type = "check", label = "Stopped Moving?", ifCond = "StoppedMoving", tooltip = "Assume you have stopped moving for at least 2 seconds.\nEnables Transient Rest's '(40-60)% of Current Mana gained as Ward when you stop moving (2 second cooldown)' affix.\nAmortized as a continuous Ward per Second contribution: Current Mana * pct / 100 / 2 (per the 2s game-side cooldown).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:StoppedMoving", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:stormhide-empowered-swipe (config site)
	-- Gates Stormhide Paws' (uniques_1_4.json #202) intermittent empowered-Swipe
	-- effect. In-game tooltip (datamine tooltipDescriptions, single combined
	-- stat string, 2026-06-01): "Every 3 seconds your next Swipe has 100% of its
	-- base damage converted to Lightning and deals +(30-45) Melee Lightning
	-- Damage". The effect only applies to the empowered (every-3s) Swipe cast,
	-- so default OFF preserves baseline (the average Swipe is NOT empowered).
	-- When ON, the Condition:EmpoweredSwipe flag enables both the Swipe-scoped
	-- base->Lightning conversion and the +Melee Lightning Damage (both tagged
	-- with this Condition in ModParser). Mirrors conditionStoppedMoving.
	-- Spec: spec/System/TestStormhideEmpoweredSwipe_spec.lua
	{ var = "conditionEmpoweredSwipe", type = "check", label = "Empowered Swipe active? (Stormhide Paws, every 3s)", ifCond = "EmpoweredSwipe", tooltip = "Stormhide Paws: 'Every 3 seconds your next Swipe has 100% of its base damage converted to Lightning and deals +(30-45) Melee Lightning Damage'.\nThis only applies to the empowered Swipe (once every 3 seconds), so it is OFF by default (the average Swipe is not empowered).\nEnable to model the empowered Swipe: Swipe's base damage is converted to Lightning and the bonus Melee Lightning Damage is added.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:EmpoweredSwipe", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:icicle-cold-to-lightning-conversion-toggle (config + conversion site)
	-- Icicle (skills.json HeorotUniqueBowIcicle, granted by the unique "Reign of
	-- Winter" #159 "(23-28)% Chance to cast Icicle on Bow Hit") is pure Cold by
	-- default: skills.json stats spell_base_cold_damage:100, no lightning base.
	-- IcicleMutator.Mutate (datamined game source) performs a
	-- 100% Cold->Lightning BASE-damage conversion:
	--   DamageStatsHolder.convertBaseDamage(holder, from=2 COLD, to=3 LIGHTNING,
	--                                       proportion=DAT_183d71c08, 0)
	-- then re-tags the hit Lightning (field 0xd1 := 3 = LIGHTNING). DamageType enum
	-- 2=COLD / 3=LIGHTNING is confirmed in src/Data game_enums.json. The proportion
	-- DAT_183d71c08 is the GENERIC 1.0f float shared across the binary (the universal
	-- "+1" base in Ability.c; the SAME const drives the (field + DAT_183d71c08) * x
	-- increase->multiplier lines at datamined game source and it is independently
	-- asserted = 1.0 in ChaosBoltsDamage.fixspec) -- so the rate is 100%, NOT an
	-- Icicle-specific magnitude (no fabricated number).
	-- WHY default OFF: the in-mutator conversion is gated on a bool spec field
	-- (param_1+0x118, read at getTags():23 + Mutate():157). Icicle has NO skill tree,
	-- so no game-data node/affix can write that bool -- the conversion is normally
	-- inert. Default OFF keeps Icicle pure Cold (matches current dev skills.json) and
	-- leaves the corpus byte-identical; a user who knows their build triggers it (or
	-- for what-if modelling) opts in. ConfigTab runs apply() ONLY for a checked box
	-- (ConfigTab.lua type=="check" -> input[var] truthy), so OFF emits nothing.
	-- When ON, apply() emits the Condition flag AND a Skill-scoped + Condition-gated
	-- ColdDamageConvertToLightning BASE 100 that CalcOffence's existing conversionTable
	-- consumer (globalConv, mult = 1 - converted -> Cold base goes to 0, Lightning
	-- receives the former Cold) applies -- the SAME channel as the Stormhide empowered
	-- Swipe / Acid Flask base conversions, scoped to the active Icicle skill
	-- (cfg.skillName == grantedEffect.name == "Icicle"). Mirrors
	-- conditionHolyAuraDamageAura (a config-gated intrinsic absent from skills.json/tree).
	-- Spec: spec/System/TestIcicleColdToLightning_spec.lua
	{ var = "conditionIcicleConvertedToLightning", type = "check", label = "Icicle converted to Lightning?", suggestBuff = "HeorotUniqueBowIcicle", tooltip = "Check if your Icicle (from Reign of Winter) converts its Cold base damage to Lightning. The game performs a 100% Cold->Lightning base-damage conversion on Icicle. Since Icicle has no skill tree, this is exposed as a toggle. Leave OFF to keep Icicle pure Cold.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:IcicleConvertedToLightning", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		-- @leb-regression-guard:icicle-cold-to-lightning-conversion-toggle (conversion site)
		-- 100% Cold->Lightning, Icicle-scoped, gated on the toggle Condition.
		modList:NewMod("ColdDamageConvertToLightning", "BASE", 100, "Config", { type = "SkillName", skillName = "Icicle" }, { type = "Condition", var = "IcicleConvertedToLightning" })
	end },
	-- @leb-regression-guard:trigger-chance-to-cast-on-bow-hit (config site)
	-- Gates the Reign of Winter (uniques_1_4.json #159) affix "(23-28)% Chance to
	-- cast Icicle on Bow Hit" proc into Full DPS. The affix parses (ModParser bow-hit
	-- bridge) to a functional ChanceToTriggerOnBowHit_HeorotUniqueBowIcicle mod, but
	-- the CalcSetup fold reads it ONLY when this toggle is on (see the sourceIsBow /
	-- modelBowHitProc gate). WHY default OFF: the proc's rate cap / internal cooldown
	-- is NOT datamined, so folding at the full bow-hit rate x chance would be a
	-- fabricated magnitude. OFF keeps the corpus byte-identical (nothing consumes the
	-- OnBowHit mod); a user who wants to model the proc opts in, and the fold then uses
	-- the datamined affix chance and the bow skill's build-derived hit rate. Mirrors
	-- conditionHolyAuraDamageAura (a config-gated intrinsic read via env.modDB:Flag).
	-- Spec: spec/System/TestReignOfWinterIcicleProc_spec.lua
	{ var = "conditionModelReignOfWinterIcicleProc", type = "check", label = "Model Reign of Winter Icicle proc?", suggestBuff = "HeorotUniqueBowIcicle", tooltip = "Check to model Reign of Winter's '(23-28)% Chance to cast Icicle on Bow Hit' proc in Full DPS.\nIcicle is triggered per bow hit at the affix chance; its rate is derived from your bow skill's hit rate.\nOFF by default because the proc's internal cooldown / rate cap is not known, so it is opt-in.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:ModelReignOfWinterIcicleProc", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:ward-per-second-and-retention-family (W4)
	{ var = "conditionDuringProfaneVeil", type = "check", label = "During Profane Veil?", suggestBuff = "ProfaneVeil", tooltip = "Check if Profane Veil is currently active (Acolyte).\nProfane Veil is a 4-second-duration cast buff, so its 'during Profane Veil' contributions only apply while the buff is up.\nEnables `+97 Ward per Second during Profane Veil` (Lich tree).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:DuringProfaneVeil", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:bulwark-of-the-last-abyss-apocalypse
	{ var = "conditionDuringApocalypse", type = "check", label = "During Apocalypse?", tooltip = "Check if the Apocalypse buff is currently active.\nApocalypse is a 3-second buff that Bulwark of the Last Abyss self-applies every 3 seconds while on high health (costing 25% current health); its only effects are the damage modifiers listed on that shield.\nEnables `70% increased Void Damage during Apocalypse` and `+70% Melee Critical Strike Multiplier during Apocalypse`.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:DuringApocalypse", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:flow-conditional-damage (config toggles)
	-- Validation provenance is retained in maintainer notes.
	{ var = "conditionGeneratingOrConsumingFlow", type = "check", label = "Generating or Consuming Flow?", ifCond = "GeneratingOrConsumingFlow", tooltip = "Check if your skills are generating or consuming Flow (Rogue / Bladedancer).\nA stack of Flow is gained on every direct unique-skill use, so this is effectively always-on in combat for a Flow build.\nEnables `X% increased Damage / +X% Critical Multiplier when generating or consuming Flow` (Bladedancer mastery 'Rhythm').", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:GeneratingOrConsumingFlow", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionConsumingFlow", type = "check", label = "Consuming Flow (burst hit only)?", ifCond = "ConsumingFlow", tooltip = "Check ONLY to inspect the single Flow-consuming hit (Rogue / Bladedancer).\nFlow is consumed when you use a 4th (with 'Pulse': 5th) unique skill; only that one hit gets the bonus, then Flow rebuilds. It is NOT a sustained buff.\nEnabling this for sustained DPS comparisons can substantially overestimate damage. Leave OFF for sustained DPS.\nEnables `100% More Damage (Flow) / +50% More Crit Chance / +100% More DoT (Pulse) when Consuming Flow`.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:ConsumingFlow", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:flame-reave-rhythm-consume (config toggle)
	-- Flame Reave "Rhythm of Fire" (fr11mv-3): using Flame Reave grants 4 stacks
	-- (cap 12); at 12 the next use CONSUMES all for +130% Damage (MORE, multiplicative,
	-- Flame-Reave-scoped). Naive duty = 25% (every 4th use), but the 4guanghuan capture
	-- (20260707_140512_03) shows the consume band DOMINATES (86% of Flame Reave hits at
	-- the x2.50 level) for a Flame-Reave-spam rotation. Like Consuming Flow this is a
	-- per-hit STATE, so the toggle applies the +130% to EVERY Flame Reave hit -> it
	-- models the fully-stacked (consume-active) view, not the blended sustained mean.
	-- Default OFF (corpus-neutral: the 3 corpus Flame Reave builds with fr11mv-3 are
	-- unchanged until set). ifCond hides it unless the build carries the node.
	{ var = "conditionConsumingRhythmOfFire", type = "check", label = "Flame Reave: Consuming Rhythm of Fire?", ifCond = "ConsumingRhythmOfFire", tooltip = "Check to model Flame Reave's 'Rhythm of Fire' consume (Spellblade).\nUsing Flame Reave grants 4 stacks (cap 12); at 12 stacks the next use consumes all of them for +130% MORE damage. In a Flame-Reave-spam rotation the consume dominates (~86% of hits, measured 2026-07-07).\nEnabling this applies the +130% MORE to every Flame Reave hit (the consume-active view). Leave OFF for the non-consuming baseline.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:ConsumingRhythmOfFire", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionRecentlyUsedTeleport", type = "check", label = "Recently Used Teleport?", tooltip = "Check if you have cast Teleport within the past 4 seconds (Mage / Spellblade).\nEnables Teleport skill tree nodes that only apply after casting Teleport recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:RecentlyUsedTeleport", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierArcaneShieldStack", type = "count", label = "# of Arcane Shields:", ifMult = "ArcaneShieldStack", implyCond = "HaveArcaneShield", suggestBuff = "ArcaneShield", tooltip ="Number of active Arcane Shield stacks (Mage).\nEnables 'with Arcane Shield' and 'per Arcane Shield' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ArcaneShieldStack", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveArcaneShield", "FLAG", val >= 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierArcaneMomentumStack", type = "count", label = "Arcane Momentum Stacks:", tooltip = "Number of active Arcane Momentum stacks (Runemaster).\nEach stack grants increased cast speed.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ArcaneMomentumStack", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionOnConsecratedGround", type = "check", label = "Are you on Consecrated Ground?", ifCond = "OnConsecratedGround", tooltip = "Check if you are standing on Consecrated Ground (Paladin).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:OnConsecratedGround", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHaveCompanion", type = "check", label = "Do you have a Companion?", ifCond = "HaveCompanion", tooltip = "Check if you have at least one Companion (Beastmaster/Falconer).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveCompanion", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierCompanion", type = "count", label = "# of Companions:", ifMult = "Companion", implyCond = "HaveCompanion", tooltip = "Number of active Companions. Also implies HaveCompanion condition.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:Companion", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveCompanion", "FLAG", val >= 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionFrenzy", type = "check", label = "Do you have Frenzy?", ifCond = "Frenzy", suggestBuff = "Frenzy", suggestCond = "Frenzy", tooltip ="Check if you have Frenzy stacks (Beastmaster).\n20% increased Attack and Cast Speed.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Frenzy", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Speed", "INC", 20, "Frenzy")
	end },
	{ var = "conditionHaste", type = "check", label = "Do you have Haste?", ifCond = "Haste", suggestBuff = "Haste", suggestCond = "Haste", tooltip ="30% increased Movement Speed for 4 seconds.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Haste", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("MovementSpeed", "INC", 30, "Haste")
	end },
	{ var = "conditionConcentration", type = "check", label = "Do you have Concentration?", ifCond = "Concentration", suggestBuff = "Concentration", tooltip ="Marksman buff (Rogue-22 passive). Enables 'with Concentration' modifiers (Dodge Rating, Movement Speed, Damage, Hit Damage Taken).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Concentration", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:chronowarp-buff-conditional
	-- FLAG only -- deliberately unlike the Frenzy/Haste entries above, which also emit
	-- their stats (Speed INC 20 / MovementSpeed INC 30) because those are global game
	-- buffs no item text describes. Chronowarp's numbers are stated by Wrongwarp's own
	-- data line, so ModParser's chronowarp-buff-conditional handler emits the stats
	-- tagged {Condition:Chronowarp} and this option only answers "is it up?". Emitting
	-- them here too would DOUBLE-COUNT. Follows the conditionConcentration shape.
	-- ifCond="Chronowarp" reads mainEnv.conditionsUsed (ConfigTab.lua:791-797), so the
	-- option stays hidden until a mod tagged with the condition exists -- i.e. until
	-- Wrongwarp (unique 310) is equipped. No suggestBuff (needs a detectGrantedBuffs
	-- row, ConfigTab.lua:189, else the highlight is dead) and no suggestPattern (that
	-- matches the allocated PASSIVE TREE, ConfigTab.lua:451-463; Chronowarp is an item
	-- buff and appears in no tree). Default OFF: uptime depends on how often the build
	-- actually casts Teleport/Transplant, so auto-on would be fake DPS.
	{ var = "conditionChronowarp", type = "check", label = "Do you have Chronowarp?", ifCond = "Chronowarp", tooltip = "Wrongwarp (unique) buff. Granted for 10 seconds when you cast Teleport or Transplant.\nGrants increased cast speed and movement speed (the amount is read from the item).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Chronowarp", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- Overloads (Warlock)
	-- @leb-regression-guard:config-highlight-suggest-pattern (Phase 5 Overload 系)
	-- Phrases verified against src/TreeData/1_4/tree_3.json (Warlock mastery
	-- tree) — `bleed overload`, `ignite overload`, `poison overload`,
	-- `damned overload`, and the generic `ailment overload` are the exact
	-- vocabulary used by the Warlock skill / passive tree. Each per-
	-- ailment condition gets its specific phrase + the generic umbrella;
	-- a passive node like `12s Bleed Overload duration` highlights both
	-- the matching condition AND any builds that grant the ailment via
	-- a Cauldron of Blood passive node.
	{ var = "conditionBleedOverload", type = "check", label = "Bleed Overload active?", suggestPattern = { "bleed overload", "ailment overload" }, tooltip = "Warlock: 15% more physical DoT vs bosses and moving enemies.\nRequires Cauldron of Blood (5pt).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BleedOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveAilmentOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Multiplier:ActiveOverload", "BASE", 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionIgniteOverload", type = "check", label = "Ignite Overload active?", suggestPattern = { "ignite overload", "ailment overload" }, tooltip = "Warlock: 1% more fire damage to ignited enemies per 20% global ignite chance for fire skills.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:IgniteOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveAilmentOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Multiplier:ActiveOverload", "BASE", 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionPoisonOverload", type = "check", label = "Poison Overload active?", suggestPattern = { "poison overload", "ailment overload" }, tooltip = "Warlock: +4% Poison Penetration per stack of poison on the target, up to 100 stacks.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:PoisonOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveAilmentOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Multiplier:ActiveOverload", "BASE", 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionDamnedOverload", type = "check", label = "Damned Overload active?", suggestPattern = { "damned overload", "ailment overload" }, tooltip = "Warlock: 2% more damned damage per 1% missing health on you\nand 1% more damned damage per 2% missing health on target.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:DamnedOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveAilmentOverload", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Multiplier:ActiveOverload", "BASE", 1, "Config", { type = "Condition", var = "Combat" })
	end },
	-- Positive buff stacks
	-- @leb-regression-guard:config-visibility-gating (E batch 2)
	{ var = "multiplierDuskShroudStacks", type = "count", ifMult = "DuskShroudStacks", label = "Dusk Shroud Stacks:", tooltip = "5% Glancing Blow chance and +50 Dodge Rating per stack. Also drives the Rogue 'Edge of Obscurity' node (Umbral Blades tree): +2% more Umbral Blades damage per allocated point per Dusk Shroud (so +6% at 3/3), capped at 20 Dusk Shrouds. Set 0 outside combat / when not stacked.", apply = function(val, modList, enemyModList)
		modList:NewMod("GlancingBlowChance", "BASE", val * 5, "Dusk Shroud")
		modList:NewMod("Evasion", "BASE", val * 50, "Dusk Shroud")
		-- @leb-regression-guard:umbral-blades-edge-of-obscurity-per-shroud (config site)
		-- Drive the offensive Multiplier:DuskShroudStacks off the SAME stack count
		-- (the in-game Dusk Shroud stacks gate both the defensive Glancing
		-- Blow/Evasion above and the "Edge of Obscurity" MORE damage). Default
		-- count 0 -> strict no-op, so the corpus stays byte-identical until set.
		modList:NewMod("Multiplier:DuskShroudStacks", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierVoidEssenceStacks", type = "count", label = "Void Essence Stacks:", tooltip = "3% more Void Damage, 3% more Melee Damage, 15% reduced stun duration per stack. Max 3.", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		modList:NewMod("VoidDamage", "MORE", val * 3, "Void Essence")
		modList:NewMod("Damage", "MORE", val * 3, "Void Essence", ModFlag.Melee)
	end },
	-- @leb-regression-guard:eye-of-reen-reens-ire (config site)
	-- Eye of Reen (Unique 1H Katana): crit with a melee attack grants a stack of
	-- Reen's Ire (5s, up to 30 stacks). Each stack grants "5% melee critical strike
	-- multiplier and 10% increased fire damage over time" (datamined verbatim from
	-- the unique's tooltipDescription; the parseable grant mod, ModCache.lua ~16096,
	-- is an empty modlist no-op, so the per-stack effect is otherwise unmodeled).
	-- LEB cannot know the live stack count (it depends on melee-crit uptime), so it
	-- is a user input. Default count 0 -> strict no-op = corpus-neutral. Direct-apply
	-- of the per-stack scalars (same pattern as Void Essence above); the effect is
	-- capped at 30 stacks. Melee crit multiplier is BASE + KeywordFlag.Melee (matches
	-- the "+N% Melee Critical Multiplier" ModCache form, keywordFlags 512); the fire
	-- DoT increase is FireDamage INC + Fire/Dot flags (matches "N% increased Fire
	-- Damage Over Time", flags 4104). Set 0 outside combat / when not stacked.
	{ var = "multiplierReensIreStacks", type = "count", label = "# of Reen's Ire Stacks (max 30):", tooltip = "Number of active Reen's Ire stacks (Eye of Reen). You gain a stack for 5s when you crit with a melee attack, up to 30. Each stack grants 5% melee critical strike multiplier and 10% increased fire damage over time. The effect is capped at 30 stacks. Leave blank / set 0 when not stacked.", apply = function(val, modList, enemyModList)
		val = math.min(val, 30)
		modList:NewMod("CritMultiplier", "BASE", val * 5, "Reen's Ire", 0, KeywordFlag.Melee)
		modList:NewMod("FireDamage", "INC", val * 10, "Reen's Ire", bit.bor(ModFlag.Dot, ModFlag.Fire))
	end },
	-- @leb-regression-guard:event-horizon-config-stacks (config site)
	-- Event Horizon (Unique 2H Mace / Vault Crusher, Lv80): "When you use a Melee
	-- Attack and hit at least one enemy you gain a stack of Dilation (up to 10).
	-- Dilation has no time limit and no effects beyond those described. 15% more
	-- Melee Damage per stack (multiplicative), 5% less attack/cast speed per stack,
	-- 5% less move speed per stack. All stacks lost on Evade." (datamined verbatim
	-- from the unique's tooltip -- 未モデル affix gear grounding 2026-07-12, B5.)
	-- The only parseable Dilation mod on the item is the grant line (ModCache.lua
	-- ~10793) which is an EMPTY modlist {{}, ...} = no-op, so the per-stack effect
	-- is otherwise completely unmodeled. LEB cannot know the live stack count (it
	-- depends on melee-hit uptime and is wiped on Evade), so it is a user input.
	-- Default count 0 -> strict no-op = corpus-neutral (Event Horizon builds stay
	-- byte-identical until the user sets the stack count). Direct-apply of the
	-- per-stack MORE (same pattern as Void Essence / Reen's Ire above); capped at
	-- 10 stacks. Scope: melee-only MORE (ModFlag.Melee), matching the "N% more
	-- Melee Damage" form. NOTE: the per-stack -5% attack/cast speed and -5% move
	-- speed downsides are part of the same buff but are intentionally NOT modeled
	-- here -- this config scopes the offensive per-stack MORE only. Set 0 outside
	-- combat / when not stacked / after an Evade.
	{ var = "multiplierDilationStacks", type = "count", label = "# of Dilation Stacks (max 10):", tooltip = "Number of active Dilation stacks (Event Horizon). You gain a stack for as long as you keep landing melee hits, up to 10 (no time limit), and lose ALL stacks on Evade. Each stack grants 15% more Melee Damage (multiplicative). The effect is capped at 10 stacks. (The item's -5% attack/cast speed and -5% move speed per stack are not modeled here.) Leave blank / set 0 when not stacked.", apply = function(val, modList, enemyModList)
		val = math.min(val, 10)
		modList:NewMod("Damage", "MORE", val * 15, "Dilation", ModFlag.Melee)
	end },
	-- @leb-regression-guard:scales-eterra-infusion (config site)
	-- Validation provenance is retained in maintainer notes.
	{ var = "multiplierFireInfusionStacks", type = "count", label = "# of Fire Infusion Stacks (max 10):", tooltip = "Number of active Fire Infusion stacks (Scales of Eterra). You gain Fire Infusion when you cast a fire spell; it starts at 1 stack and gains +1 per second up to 10 (10s duration, 20s re-grant cooldown). Each stack grants 10% more Fire damage and 6% less Cold damage and 6% less Lightning damage (all multiplicative). The effect is capped at 10 stacks. Leave blank / set 0 when not stacked.", apply = function(val, modList, enemyModList)
		val = math.min(val, 10)
		modList:NewMod("FireDamage", "MORE", val * 10, "Fire Infusion")
		modList:NewMod("ColdDamage", "MORE", -val * 6, "Fire Infusion")
		modList:NewMod("LightningDamage", "MORE", -val * 6, "Fire Infusion")
	end },
	{ var = "multiplierLightningInfusionStacks", type = "count", label = "# of Lightning Infusion Stacks (max 10):", tooltip = "Number of active Lightning Infusion stacks (Scales of Eterra). You gain Lightning Infusion when you cast a lightning spell; it starts at 1 stack and gains +1 per second up to 10 (10s duration, 20s re-grant cooldown). Each stack grants 10% more Lightning damage and 6% less Fire damage and 6% less Cold damage (all multiplicative). The effect is capped at 10 stacks. Leave blank / set 0 when not stacked.", apply = function(val, modList, enemyModList)
		val = math.min(val, 10)
		modList:NewMod("LightningDamage", "MORE", val * 10, "Lightning Infusion")
		modList:NewMod("FireDamage", "MORE", -val * 6, "Lightning Infusion")
		modList:NewMod("ColdDamage", "MORE", -val * 6, "Lightning Infusion")
	end },
	{ var = "multiplierColdInfusionStacks", type = "count", label = "# of Cold Infusion Stacks (max 10):", tooltip = "Number of active Cold Infusion stacks (Scales of Eterra). You gain Cold Infusion when you cast a cold spell; it starts at 1 stack and gains +1 per second up to 10 (10s duration, 20s re-grant cooldown). Each stack grants 10% more Cold damage and 6% less Fire damage and 6% less Lightning damage (all multiplicative). The effect is capped at 10 stacks. Leave blank / set 0 when not stacked.", apply = function(val, modList, enemyModList)
		val = math.min(val, 10)
		modList:NewMod("ColdDamage", "MORE", val * 10, "Cold Infusion")
		modList:NewMod("FireDamage", "MORE", -val * 6, "Cold Infusion")
		modList:NewMod("LightningDamage", "MORE", -val * 6, "Cold Infusion")
	end },
	-- @leb-regression-guard:scissor-of-atropos-kismet-stacks (config site)
	-- Scissor of Atropos (Unique 1H Sword, Lv60). "1 Kismet Stack gained when you
	-- directly use a Melee Attack and hit at least one enemy" (up to 8). Kismet is a
	-- player-direct throwing buff: each stack grants +8% throwing critical strike
	-- chance and +8 added throwing physical damage; stacks are BUILT by melee hits and
	-- CONSUMED on throw (consume-on-throw burst), so the two attack types are coupled
	-- and dual-wield increases stack-gain rate. (未モデル affix gear grounding B-group,
	-- datamine-confirmed per-stack magnitudes: 8% throw crit + 8 throw phys per stack,
	-- cap 8. Item mods carry only the grant line -- see below.) The ONLY parseable
	-- Kismet mod on the item is the grant line (ModCache.lua ~L10122,
	-- "1 Kismet Stacks gained when you directly use a Melee Attack and hit at least one
	-- enemy") which compiles to an EMPTY modlist {{}, ...} = no-op; the per-stack
	-- magnitude lives in the buff definition (unparsed), so the per-stack effect is
	-- otherwise completely unmodeled. Modeled with the Void Essence / Reen's Ire /
	-- Dilation / Infusion direct-apply config pattern (same section): a type "count"
	-- option whose apply() emits, per stack N, CritChance BASE (N*8) throwing-scoped
	-- (KeywordFlag.Throwing) + added PhysicalDamage BASE (N*8) throwing-scoped. Capped
	-- at 8 stacks. LEB cannot know the live stack count -- it depends on melee-hit
	-- uptime and is wiped on every throw (consume-on-throw) -- so it is a user input.
	-- Default count 0 -> strict no-op = corpus-neutral (CritChance BASE 0 + Physical-
	-- Damage BASE 0 = byte-identical; Scissor builds stay unchanged until the user sets
	-- the stack count). Same default-0-inert pattern as the shipped eye-of-reen-reens-
	-- ire / event-horizon-config-stacks / scales-eterra-infusion siblings. NOTE: the
	-- consume-on-throw BURST rotation (melee to build, throw to spend) is stack-count/
	-- rotation-dependent and is intentionally NOT modeled -- this config scopes the
	-- steady per-stack offensive effect only, gated behind an explicit user opt-in.
	{ var = "multiplierKismetStacks", type = "count", label = "# of Kismet Stacks (max 8):", tooltip = "Number of active Kismet stacks (Scissor of Atropos). You gain a Kismet stack when you directly use a Melee Attack and hit at least one enemy, up to 8; stacks are consumed on throw (dual-wield builds gain them faster). Each stack grants 8% throwing critical strike chance and 8 added throwing physical damage. The effect is capped at 8 stacks. Leave blank / set 0 when not stacked.", apply = function(val, modList, enemyModList)
		val = math.min(val, 8)
		modList:NewMod("CritChance", "BASE", val * 8, "Kismet", 0, KeywordFlag.Throwing)
		modList:NewMod("PhysicalDamage", "BASE", val * 8, "Kismet", 0, KeywordFlag.Throwing)
	end },
	-- @leb-regression-guard:config-visibility-gating (E batch 2)
	{ var = "multiplierActiveSymbols", type = "count", ifMult = "ActiveSymbol", label = "# of Active Symbols:", tooltip = "Override for active Symbols of Hope (Paladin). Leave blank for auto (3 baseline + 'Maximum Symbols' passives).", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ActiveSymbol", "BASE", val, "Config")
		modList:NewMod("Condition:HaveActiveSymbol", "FLAG", val >= 1, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:ward-per-second-and-retention-family (config site)
	{ var = "multiplierFirebrandStack", type = "count", label = "# of Firebrand Stacks:", ifMult = "FirebrandStack", tooltip = "Number of active Firebrand stacks (Sorcerer / Spellblade). Drives the intrinsic +5 added melee fire damage per stack on Firebrand's hit AND 'per stack of Firebrand' Ward per Second modifiers. Leave blank to auto-default to max stacks (4 base; the Firebrand skill is modeled at max stacks).", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:FirebrandStack", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierActiveDreadShade", type = "count", label = "# of Active Dread Shades:", ifMult = "ActiveDreadShade", tooltip = "Number of active Dread Shades (Acolyte/Warlock). Used for 'per active Dread Shade' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ActiveDreadShade", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierActiveMaelstrom", type = "count", label = "# of Active Maelstrom Stacks:", ifMult = "ActiveMaelstrom", tooltip = "Number of active Maelstrom stacks (Shaman/Druid). Used for 'per active Maelstrom' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ActiveMaelstrom", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierActiveAmbition", type = "count", label = "# of Active Ambition Stacks:", ifMult = "AmbitionStacks", tooltip = "Number of active Ambition stacks (Throne of Ambition; gained on hitting a boss/rare, max 20). Drives 'per stack of Ambition' modifiers (2% more Fire/Cold/Armor each). The parser limit caps the effect at 20.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:AmbitionStacks", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:rhythm-stack-crit-multi (config site)
	{ var = "multiplierRhythmStacks", type = "count", label = "# of Rhythm Stacks (max 10 at 5/5 Rhythm):", ifMult = "RhythmStacks", tooltip = "Number of active Rhythm stacks (Bladedancer, Dancing Strikes tree). You gain a stack when Dancing Strikes hits at least one enemy; maximum stacks = 2 per point in the Rhythm node (10 at 5/5). Drives 'per stack of Rhythm' modifiers: Art of Blades global critical multiplier and Rhythm's global more damage. The effect is capped at 10 stacks.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:RhythmStacks", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:berserk-stack-melee-damage (config site)
	{ var = "multiplierBerserkStacks", type = "count", label = "# of Berserk Stacks (max 15 at 5/5 Brutality):", ifMult = "BerserkStacks", tooltip = "Number of active Berserk stacks (Primalist, Warcry 'Berserker' node). You gain Berserk for 1.5s on Warcry use and a stack on each melee hit while Berserk; maximum = 10 (Berserker) + 1 per Brutality point (15 at 5/5). Drives 'per stack of Berserk' modifiers: +4 flat Melee Damage per stack (global). The effect is capped at 15 stacks.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:BerserkStacks", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:germination-per-companion-scaling (config site)
	{ var = "multiplierGerminationStacks", type = "count", label = "# of Germination Stacks (max 4):", ifMult = "GerminationStacks", tooltip = "Number of active Germination stacks (Druid, while in Spriggan Form with Roots of Vithrasil). A stack is gained on a 0.5s timer while in Spriggan Form (max 4). Drives Roots of Vithrasil's 'per stack of Germination' modifiers: +1 Projectile with Spirit Thorns and +Health Regen per stack. The effect is capped at 4 stacks. Stacks only exist in Spriggan Form, so set 0 outside it.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:GerminationStacks", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:aerial-prowess-per-stack (config site)
	{ var = "multiplierAerialProwessStacks", type = "count", label = "# of Aerial Prowess Stacks (max 12):", ifMult = "AerialProwessStacks", tooltip = "Number of active Aerial Prowess stacks (Falconer, the 'Aerial Prowess' node in the Aerial Assault tree). For 8s after using Aerial Assault you or your Falcon gain a stack on critical strike (plus one on dodge with Wind Rider); the next Aerial Assault consumes all stacks to deal more damage (multiplicative) per stack. This drives 'Aerial Prowess' modifiers: +2% more Aerial Assault damage per stack, capped at 12 stacks. Set 0 when not mid-combo.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:AerialProwessStacks", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:falcon-avian-arsenal-buff (config site)
	-- Avian Arsenal (Falconry skill tree, maxPoints 3, 10%/pt <=30%). When you CONSUME
	-- a Falconer's Mark, the consuming ability's damage-type tag selects ONE of your
	-- added-damage pools (Bow > Spell > Throwing > else Melee); that pool x the node %
	-- is granted to the Falcon as MELEE flat added damage, once per stack (10s, up to 5).
	-- LEB cannot know which ability you use to consume the mark, so the pool is a user
	-- input. BOTH inputs default OFF (pool = "Off", stacks = 0) -> the whole mechanic is
	-- inert = corpus-neutral by construction. Gated ifMult = "FalconAvianArsenalStacks"
	-- (the parsed node % mod carries that Multiplier tag) so the options only surface for
	-- a build that actually allocates the node. The stack-count drives that Multiplier so
	-- the node % is auto-scaled by stacks; CalcPerform reads the pre-scaled Sum. Buff
	-- applies only when stacks > 0 (Sum 0 -> inert). NOT capture-validated (wired, awaiting
	-- a specced Mark-consume capture). See REGRESSION_GUARDS.md "falcon-avian-arsenal-buff".
	{ var = "falconAvianArsenalPool", type = "list", label = "Avian Arsenal mark-consuming ability type:", ifMult = "FalconAvianArsenalStacks", defaultIndex = 1,
	  tooltip = "Falconry's Avian Arsenal node: when you consume a Falconer's Mark, your Falcon gains added Melee damage equal to a portion of your added damage of the type used to consume the mark. Pick which added-damage pool the consuming ability draws from (in-game priority is Bow > Spell > Throwing > else Melee). Leave 'Off' to disable the buff (default). Set the stack count below to how many stacks are active.",
	  list = {
		{ val = 0,    label = "Off (no Mark consumed)" },
		{ val = 512,  label = "Melee" },
		{ val = 1024, label = "Throwing" },
		{ val = 2048, label = "Bow" },
		{ val = 256,  label = "Spell" },
	  },
	  apply = function(val, modList, enemyModList)
		if val ~= 0 then
			modList:NewMod("FalconAvianArsenalPoolKeyword", "BASE", val, "Config")
		end
	end },
	{ var = "falconAvianArsenalStacks", type = "count", label = "# of Avian Arsenal Stacks (max 5):", ifMult = "FalconAvianArsenalStacks", tooltip = "Number of active Avian Arsenal buff stacks (Falconer). Each stack grants the Falcon added Melee damage equal to the node % of your selected added-damage pool; stacks accumulate up to 5 (10s duration). Set 0 (default) to disable the buff.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:FalconAvianArsenalStacks", "BASE", math.min(val, 5), "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:razorfall-umbral-blades-per-dex (config site)
	-- (ifMult) only for a build that equips Razorfall. See REGRESSION_GUARDS.md
	-- Validation provenance is retained in maintainer notes.
	{ var = "razorfallBurstOfFeathersBlades", type = "count", label = "Base Umbral Blades per Aerial Assault Burst of Feathers (Razorfall; 0 = off):", ifMult = "RazorfallEquipped", tooltip = "Razorfall unique: Aerial Assault's Burst of Feathers throws a burst of Umbral Blades on landing, and Razorfall adds +1 blade per 20 Dexterity. Set this to the base number of Umbral Blades the Burst of Feathers node throws before Razorfall's per-Dex bonus (read it from the in-game Aerial Assault tree). When > 0, the burst's Umbral Blades are folded as a single-target DPS multiplier on your specialized Umbral Blades skill (base count here + 1 per 20 Dex). Set 0 (default) to disable. UPPER BOUND -- assumes every burst blade connects on a single target; not yet validated against an in-game capture.", apply = function(val, modList, enemyModList)
		if val > 0 then
			modList:NewMod("Condition:RazorfallBurstOfFeathers", "FLAG", true, "Config")
			modList:NewMod("ProjectileCount", "BASE", val, "Config", { type = "SkillName", skillName = "Umbral Blades" }, { type = "Condition", var = "RazorfallBurstOfFeathers" })
		end
	end },
	-- @leb-regression-guard:avalanche-boulder-burst-per-cast (config site)
	-- on there compounds that error ~10x. See REGRESSION_GUARDS.md "avalanche-boulder-
	-- Validation provenance is retained in maintainer notes.
	{ var = "avalancheBouldersPerCast", type = "count", label = "Avalanche boulders per cast (manual cast only; datamined 10; 0 = off):", ifSkill = "Avalanche", tooltip = "Each Avalanche CAST spawns a burst of boulders (datamined: 10 per cast, hard-capped, all landing within the ability's 2.5s lifespan). LEB models only 1 boulder-hit per cast, so a build that actively CASTS Avalanche under-reads its per-cast output. Set this to the number of boulders one cast drops (datamined default 10) to fold the burst as a single-target DPS multiplier on Avalanche. Set 0 (default) to disable -> corpus-neutral, no change. ONLY the per-cast burst COUNT is grounded; the sustained recast rate (cast-speed/mana/animation) is behavioral and NOT modelled here. DO NOT enable this if your Avalanche boulders come from a 'Chance for an Avalanche Boulder to drop ... (up to 3 times per second)' idol affix -- that is an idol-proc that drops ONE boulder per spell/melee cast (not a 10-boulder Avalanche cast), and LEB already models it at the player's full cast rate; enabling this there over-counts by ~10x.", apply = function(val, modList, enemyModList)
		if val > 1 then
			-- N boulders per cast = 1 base hit + (N-1) extra same-target hits.
			modList:NewMod("AdditionalSameTargetHits", "BASE", val - 1, "Config", { type = "SkillName", skillName = "Avalanche" })
		end
	end },
	-- @leb-regression-guard:aura-of-decay-ailment-application (config site -- INTENTIONALLY EMPTY)
	-- See REGRESSION_GUARDS.md "aura-of-decay-ailment-application".
	-- @leb-regression-guard:warpath-warslash-spin-duration-more (config site)
	-- Validation provenance is retained in maintainer notes.
	{ var = "multiplierWarpathSpinSeconds", type = "count", label = "Seconds spent Spinning (Warpath, max 5):", ifMult = "WarpathSpinSeconds", tooltip = "Number of seconds spent Spinning with Warpath (the 'Giant Splitter' node in the Warpath tree). After spinning for at least 2 seconds, the next time you stop spinning Warpath deals a Warslash that deals more damage for each second spent spinning, up to 5 seconds. This drives Giant Splitter's 'per second spinning' modifier: +15% more Warpath damage per second per point, so at 5 points 5 seconds gives +375% more damage, capped at 5 seconds. Set 0 outside the spin. UPPER BOUND -- this MORE lands ONLY on the separate Warslash hit that fires when you STOP spinning, NOT on the Warpath spin ticks; this config applies it to the whole Warpath line as a proxy, so a build that spins continuously (rarely stopping) is over-counted (up to the full multiplier). Treat the result as a best case; the real contribution scales with how often you actually stop to fire the Warslash.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:WarpathSpinSeconds", "BASE", math.min(val, 5), "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:dragonfang-stack-fire-damage (config site)
	{ var = "multiplierDragonfangStacks", type = "count", label = "# of Dragonfang Stacks (max 20):", ifMult = "DragonfangStacks", tooltip = "Number of active Dragonfang stacks (Marksman, the 'Dragonfang' node in the Heartseeker tree). Consecutive Recurves each grant a stack for 10s, up to 20. Drives the node's +1 Bow/Spell/Throwing flat Fire Damage per stack. Capped at 20.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:DragonfangStacks", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierActiveRune", type = "count", label = "# of Active Runes:", ifMult = "ActiveRune", tooltip = "Number of active Runes (Runemaster). Used for 'per active Rune' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ActiveRune", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:gon-rune-multiplier (config site)
	-- @leb-regression-guard:heo-rah-rune-multiplier (config site)
	-- Per-rune-type counts driving "per Gon/Heo/Rah Rune" multipliers.
	-- Gon Rune: Rune Master ward-regen node (tree_1.json L12835).
	-- Heo Rune: Dodge Rating per Heo Rune affixes + "+8% Freeze Rate
	-- Multiplier per Heo Rune" tree node.
	-- Rah Rune: Armour per Rah Rune affixes + "2% Increased Mana Regen
	-- per Rah Rune" tree node.
	{ var = "multiplierGonRune", type = "count", label = "# of Active Gon Runes:", ifMult = "GonRune", tooltip = "Number of active Gon Runes (Runemaster). Used for 'per Gon Rune' modifiers such as 'Ward Gain Per Second per Gon Rune'.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:GonRune", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierHeoRune", type = "count", label = "# of Active Heo Runes:", ifMult = "HeoRune", tooltip = "Number of active Heo Runes (Runemaster). Used for 'per Heo Rune' modifiers such as Dodge Rating per Heo Rune and Freeze Rate Multiplier per Heo Rune.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:HeoRune", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierRahRune", type = "count", label = "# of Active Rah Runes:", ifMult = "RahRune", tooltip = "Number of active Rah Runes (Runemaster). Used for 'per Rah Rune' modifiers such as Armour per Rah Rune and Mana Regen per Rah Rune.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:RahRune", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:channelling-seconds-multiplier (config site)
	-- Channelling-stacking-buff seconds count. Drives "+N% Damage Per
	-- Second" style nodes whose per-tick stacks accumulate while the
	-- player is channelling (Smelter's Wrath tree_2.json L14336;
	-- Flurry "Accelerating Impact" flur3-14; Volcanic Orb va53st-19;
	-- channelling Arcane Ascendance et al.). Modifier-side mod is gated
	-- on Condition:Channelling so the bonus is fully suppressed when
	-- the player is not channelling.
	{ var = "multiplierChannellingSeconds", type = "count", label = "# of Channelling Seconds:", ifMult = "ChannellingSeconds", tooltip = "Number of seconds the player has been channelling. Used for 'Per Second' stacking buffs such as Smelter's Wrath '+5% Damage Per Second' and Flurry 'Accelerating Impact'.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ChannellingSeconds", "BASE", val, "Config", { type = "Condition", var = "Combat" }, { type = "Condition", var = "Channelling" })
	end },
	-- @leb-regression-guard: smelters-wrath-max-charge-more (config site)
	-- Smelter's Wrath intrinsic charge ramp: +100% more damage at maximum charge,
	-- reached at maxDuration = 2.0s of channelling (SmeltersWrathEndMutator
	-- age/maxDuration MoreStat; .ctor maxDuration = 2.0). CalcOffence defaults the
	-- charge to the full 2.0s (max) when this is unset; set 0-2 here to model a
	-- partial charge. This is the SEPARATE intrinsic ramp, not the "More Damage
	-- From Charging" skill-tree node.
	{ var = "multiplierSmeltersWrathChargeSeconds", type = "count", label = "Smelter's Wrath Charge Seconds (max 2):", ifMult = "SmeltersWrathChargeSeconds", tooltip = "Seconds of channelling charge for Smelter's Wrath. The base ability deals +100% more damage at maximum charge, reached after 2 seconds of channelling (a linear ramp: +50% per second). Leave blank to model maximum charge (the default); set 0-2 to model a partial charge. This is the intrinsic charge ramp only -- the 'More Damage From Charging' tree node is a separate, additional bonus modeled via the skill tree.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:SmeltersWrathChargeSeconds", "BASE", m_min(val, 2), "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierActiveWanderingSpirit", type = "count", label = "# of Active Wandering Spirits:", ifMult = "ActiveWanderingSpirit", tooltip = "Number of active Wandering Spirits (Warlock). Used for 'per active Wandering Spirit' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ActiveWanderingSpirit", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:chthonic-fissure-torment-multistack
	-- Chthonic Fissure (Warlock) releases Spirits that each apply Torment (a Necrotic
	-- curse DoT, base 120 over 3s = 40/s; Data.lua) to the target. In-game these
	-- multi-stack -- one Torment per Spirit -- making Torment the DOMINANT Chthonic
	-- Fissure damage. Data.lua keeps Torment at maxStacks=1 (the default single curse),
	-- so this count OVERRIDES the Torment stack count in CalcOffence's ailment loop.
	-- Default 0 -> override skipped -> stacks unchanged -> corpus-neutral. The 2026-06-25
	-- Spine-OFF blank capture observed ~13 coexisting Torment stacks (~3281/s total).
	-- With Spine of Malatros equipped the Spirits are swapped for Flame Whip and no
	-- Torment is applied, so set this to 0 when Spine is equipped.
	{ var = "multiplierChthonicTormentStacks", type = "count", label = "# of Chthonic Fissure Torment stacks:", ifMult = "ChthonicTormentStacks", tooltip = "Number of coexisting Torment ailments applied by Chthonic Fissure's Spirits (Warlock). Each Spirit applies one Torment (Necrotic curse DoT, base 120 over 3 seconds). Set to the number of Torment stacks you sustain on the target. Leave 0 if you do not run native Chthonic Fissure Spirits, or if Spine of Malatros is equipped (Spirits are then swapped for Flame Whip and apply no Torment).", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ChthonicTormentStacks", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierActiveCrimsonShroud", type = "count", label = "# of Active Crimson Shrouds:", ifMult = "ActiveCrimsonShroud", tooltip = "Number of active Crimson Shrouds (Blademaster). Used for 'per active Crimson Shroud' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ActiveCrimsonShroud", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierActiveShadow", type = "count", label = "# of Active Shadows:", ifMult = "ActiveShadow", tooltip = "Number of active Shadows (Bladedancer). Used for 'per active Shadow' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ActiveShadow", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:condition-on-shadow-create-consume-config
	-- Bladedancer Shadow event-time conditions. The parser already
	-- emits Condition:OnShadowCreate / OnShadowConsume tags on the
	-- affix families "+N Ward/Health Gained on Shadow Creation" and
	-- "+N% Chance to gain a stack of Dusk Shroud when you consume a
	-- Shadow" (see src/Modules/ModParser.lua L615-619 and the dozens
	-- of correctly tagged ModCache entries). Without these Config
	-- toggles those Condition flags can never resolve to true, so
	-- the tagged mods are gated off in every snapshot -- silent
	-- failure visible only as missing Ward/Health/Dusk Shroud
	-- contributions in the player's defence/buff breakdown.
	{ var = "conditionOnShadowCreate", type = "check", label = "Shadow just Created?", ifCond = "OnShadowCreate", tooltip = "Bladedancer: enables 'on Shadow Creation' modifiers (Ward/Health Gained on Shadow Creation affix family).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:OnShadowCreate", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionOnShadowConsume", type = "check", label = "Shadow just Consumed?", ifCond = "OnShadowConsume", tooltip = "Bladedancer: enables 'when you consume a Shadow' modifiers (Dusk Shroud chance on Shadow consume affix family).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:OnShadowConsume", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierEquippedOmenIdol", type = "count", label = "# of Equipped Omen Idols:", ifMult = "EquippedOmenIdol", tooltip = "Number of equipped Omen Idols. Used for 'per equipped Omen Idol' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:EquippedOmenIdol", "BASE", val, "Config")
	end },
	{ var = "multiplierEquippedWeaverItem", type = "count", label = "# of Equipped Weaver Items:", ifMult = "EquippedWeaverItem", tooltip = "Number of equipped Weaver items. Used for 'per equipped Weaver Item' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:EquippedWeaverItem", "BASE", val, "Config")
	end },
	{ var = "multiplierArrowsWithMultishot", type = "count", label = "# of Arrows with Multishot:", ifMult = "ArrowsWithMultishot", tooltip = "Number of arrows fired by Multishot (base 5 + passives/items). Used for 'per arrow with Multishot' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ArrowsWithMultishot", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierProjectileCountConfig", type = "count", label = "# of Projectiles (generic):", ifMult = "ProjectileCountConfig", tooltip = "Generic projectile count for 'per Projectile' modifiers on your main skill.\nSet to your main skill's typical projectile count.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ProjectileCountConfig", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierAdditionalTotem", type = "count", label = "# of Additional Totems:", ifMult = "AdditionalTotem", tooltip = "Number of Totems beyond the baseline for 'per Additional Totem Summoned' cost modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:AdditionalTotem", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierContemptStacks", type = "count", label = "Contempt Stacks:", tooltip = "+10% All Resistances and 10% more Armor per stack. Max 5.", apply = function(val, modList, enemyModList)
		val = math.min(val, 5)
		for _, res in ipairs({"FireResist", "LightningResist", "ColdResist", "PhysicalResist", "PoisonResist", "NecroticResist", "VoidResist"}) do
			modList:NewMod(res, "BASE", val * 10, "Contempt")
		end
		modList:NewMod("Armour", "MORE", val * 10, "Contempt")
	end },
	{ var = "multiplierVoidBarrierStacks", type = "count", label = "Void Barrier Stacks:", tooltip = "5% less Damage Taken per stack. Max 6.", apply = function(val, modList, enemyModList)
		val = math.min(val, 6)
		modList:NewMod("DamageTaken", "MORE", -val * 5, "Void Barrier")
	end },
	{ var = "multiplierTotemArmorStacks", type = "count", label = "Totem Armor Stacks:", tooltip = "80% increased Armor and 15% more Damage per stack. Max 3.", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		modList:NewMod("Armour", "INC", val * 80, "Totem Armor")
		modList:NewMod("Damage", "MORE", val * 15, "Totem Armor")
	end },
	{ var = "multiplierMoltenInfusionStacks", type = "count", label = "Molten Infusion Stacks:", tooltip = "+15 Fire Melee Damage and +30% Ignite Chance per stack.", apply = function(val, modList, enemyModList)
		modList:NewMod("FireDamage", "BASE", val * 15, "Molten Infusion", ModFlag.Melee)
		modList:NewMod("IgniteChance", "BASE", val * 30, "Molten Infusion")
	end },
	{ var = "multiplierStormInfusionStacks", type = "count", label = "Storm Infusion Stacks:", tooltip = "+21 Lightning Spell/Melee/Bow/Throwing Damage per stack. Max 3.", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		modList:NewMod("LightningDamage", "BASE", val * 21, "Storm Infusion")
	end },
	{ var = "conditionDamageImmunity", type = "check", label = "Damage Immunity active?", tooltip = "100% less Damage Taken for 3 seconds.", apply = function(val, modList, enemyModList)
		modList:NewMod("DamageTaken", "MORE", -100, "Damage Immunity")
	end },
	-- Missing health for Damned Overload
	{ var = "playerMissingHealthPercent", type = "count", label = "Your Missing Health %:", tooltip = "Percentage of your maximum health that is missing.\nUsed for Damned Overload calculation (2% more damned per 1% missing).", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:MissingHealthPercent", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "enemyMissingHealthPercent", type = "count", label = "Enemy Missing Health %:", tooltip = "Percentage of the enemy's maximum health that is missing.\nUsed for Damned Overload calculation (1% more damned per 2% missing).", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:MissingHealthPercent", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:raptor-execute-missing-health-more (config site)
	-- Beastmaster Raptor "Cornered" (srtor-20) scales the Raptor's MORE damage on
	-- the RAPTOR's OWN missing health (capped at 50% missing). That missing-health
	-- share is a MINION state, so inject Multiplier:MissingHealthPercent onto the
	-- minion modDBs via MinionModifier (mirrors minionsConditionFullLife). Default
	-- 0 => Raptor at full HP => Cornered MORE x1.0 (inert) => corpus-neutral. Only
	-- the Raptor's Cornered node consumes minion MissingHealthPercent, so setting
	-- it build-wide is harmless. See ModParser.lua specialModList "raptor damage
	-- per 1% missing health" + Global.lua LE_TREE_NODE_STAT_REWRITE["srtor-20"].
	{ var = "raptorMissingHealthPercent", type = "count", label = "Raptor Missing Health %:", tooltip = "Percentage of your Raptor's maximum health that is missing.\nDrives the Cornered node: the Raptor deals more damage per 1% of its missing health, capped at 50% missing (so up to +50% more per allocated point at low health).\nLeave at 0 (full health) for boss DPS estimates unless your Raptor is reliably kept low.", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Multiplier:MissingHealthPercent", "BASE", val, "Config") }, "Config")
	end },
	{ var = "multiplierNearbyCorpses", type = "count", label = "# of Nearby Corpses:", tooltip = "Number of corpses near you. Used for 'per nearby corpse' modifiers (Necromancer, Acolyte).\nSet a realistic value for your typical combat scenario.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:NearbyCorpse", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionUsedPotionRecently", type = "check", label = "Used a Potion Recently?", tooltip = "Enable if you regularly use potions during combat to maintain 'after using a potion' modifiers.\nFor boss fights with limited potion uses, consider leaving unchecked.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:UsedPotionRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionUsingEvade", type = "check", label = "Are you Using Evade?", ifCond = "UsingEvade", tooltip = "Enable only if your build has modifiers that specifically apply while actively using the Evade action.\nNot the same as having Dodge Chance.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:UsingEvade", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierForgedWeapons", type = "count", label = "# of Forged Weapons:", implyCond = "HaveForgedWeapon", tooltip = "Number of Forged Weapons active (Forge Guard).", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ForgedWeapon", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveForgedWeapon", "FLAG", val >= 1, "Config", { type = "Condition", var = "Combat" })
	end },

	-- Section: Combat options
	{ section = "When In Combat", col = 1 },
	{ var = "repeatMode", type = "list", label = "Repeat Mode:", ifCond = "alwaysFinalRepeat", list = {
		{val="NONE",label="None"},
		{val="AVERAGE",label="Average"},
		{val="FINAL",label="Final only"},
		{val="FINAL_DPS",label="Final (all hits use final)"}
	}, defaultIndex = 2, apply = function(val, modList, enemyModList)
		if val == "AVERAGE" then
			modList:NewMod("Condition:averageRepeat", "FLAG", true, "Config")
		elseif val == "FINAL" or val == "FINAL_DPS" then
			modList:NewMod("Condition:alwaysFinalRepeat", "FLAG", true, "Config")
		end
	end },
	{ var = "conditionLeeching", type = "check", label = "Are you Leeching?", ifCond = "Leeching", tooltip = "You will automatically be considered to be Leeching if you have '^xE05030Life ^7Leech effects are not removed at Full ^xE05030Life^7',\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Leeching", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionLeechingLife", type = "check", label = "Are you Leeching ^xE05030Life?", ifCond = "LeechingLife", implyCond = "Leeching", tooltip = "You are Leeching Life. Also implies that you are Leeching.\nEnable if your build uses Life Leech and has 'while Leeching Life' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Leeching", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHaveTotem", type = "check", label = "Do you have a Totem summoned?", ifCond = "HaveTotem", tooltip = "You will automatically be considered to have a Totem if your main skill is a Totem,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HaveTotem", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionSummonedTotemRecently", type = "check", label = "Have you Summoned a Totem Recently?", ifCond = "SummonedTotemRecently", tooltip = "You will automatically be considered to have Summoned a Totem Recently if your main skill is a Totem,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:SummonedTotemRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "TotemsSummoned", type = "count", label = "# of Summoned Totems (if not maximum):", ifStat = "TotemsSummoned", ifFlag = "totem", implyCond = "HaveTotem", tooltip = "This also implies that you have a Totem summoned.\nThis will affect all 'per Summoned Totem' modifiers, even for non-Totem skills.", apply = function(val, modList, enemyModList)
		modList:NewMod("TotemsSummoned", "OVERRIDE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HaveTotem", "FLAG", val >= 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierNearbyAlly", type = "count", label = "# of Nearby Allies:", ifMult = "NearbyAlly", tooltip = "Number of allied players or persistent minions near you. Used for 'per nearby ally' modifiers.\nFor solo play with no summons, set to 0.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:NearbyAlly", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierSummonedMinion", type = "count", label = "# of Summoned Minions:", ifMult = "SummonedMinion", tooltip = "Number of active summoned minions. Used for 'per summoned minion' modifiers.\nSet to your typical active minion count during combat.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:SummonedMinion", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBlinded", type = "check", label = "Are you Blinded?", ifCond = "Blinded", tooltip = "You are Blinded by an enemy debuff.\nOnly enable if your build has modifiers that specifically benefit from being Blinded.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Blinded", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionIgnited", type = "check", label = "Are you ^xB97123Ignited?", ifCond = "Ignited", implyCond = "Burning", tooltip = "You are on fire. Only enable if your build has 'while Ignited' modifiers or benefits from being Ignited.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Ignited", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionChilled", type = "check", label = "Are you ^x3F6DB3Chilled?", tooltip = "You are Chilled (Action Speed reduced). Only enable if your build has 'while Chilled' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Chilled", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionChilledEffect", type = "count", label = "Effect of ^x3F6DB3Chill:", ifOption = "conditionChilled", apply = function(val, modList, enemyModList)
		modList:NewMod("ChillVal", "OVERRIDE", val, "Chill", { type = "Condition", var = "Chilled" })
	end },
	{ var = "conditionFrozen", type = "check", label = "Are you ^x3F6DB3Frozen?", ifCond = "Frozen", tooltip = "You are Frozen (unable to act). Only enable if your build has 'while Frozen' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Frozen", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionShocked", type = "check", label = "Are you ^xADAA47Shocked?", ifCond = "Shocked", tooltip = "You are ^xADAA47Shocked ^7(15% increased Damage Taken). Only enable if your build has 'while Shocked' modifiers that benefit from being Shocked.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Shocked", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("DamageTaken", "INC", 15, "Shock", { type = "Condition", var = "Shocked" })
	end },
	{ var = "conditionBleeding", type = "check", label = "Are you Bleeding?", ifCond = "Bleeding", tooltip = "You are Bleeding. Only enable if your build has 'while Bleeding' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Bleeding", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionPoisoned", type = "check", label = "Are you Poisoned?", ifCond = "Poisoned", tooltip = "You are Poisoned. Only enable if your build has 'while Poisoned' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Poisoned", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierPoisonOnSelf", type = "count", label = "# of Poison on You:", ifMult = "PoisonStack", implyCond = "Poisoned", tooltip = "This also implies that you are Poisoned.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:PoisonStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionBlocking", type = "check", label = "Are you Blocking?", ifCond = "Blocking", tooltip = "You are actively blocking with a shield. Enable for high-block builds with 'while Blocking' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Blocking", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionNearEnemy", type = "check", label = "Are you Near an Enemy?", ifCond = "NearEnemy", tooltip = "You are in close proximity to an enemy. Enable for melee builds or builds that fight at point-blank range.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:NearEnemy", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierNearbyEnemies", type = "count", label = "# of nearby Enemies:", ifMult = "NearbyEnemies", tooltip = "Number of enemies near you. Used for 'per nearby enemy' modifiers.\nFor single-target boss DPS, set to 1. For AoE clear evaluation, set higher.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:NearbyEnemies", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:OnlyOneNearbyEnemy", "FLAG", val == 1, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHitRecently", type = "check", label = "Have you Hit Recently?", ifCond = "HitRecently", tooltip = "You will automatically be considered to have Hit Recently if your main skill Hits and is self-cast,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HitRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHitSpellRecently", type = "check", label = "Have you Hit with a Spell Recently?", ifCond = "HitSpellRecently", implyCond = "HitRecently", tooltip = "This also implies that you have Hit Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HitSpellRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:HitRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionCritRecently", type = "check", label = "Have you Crit Recently?", ifCond = "CritRecently", implyCond = "SkillCritRecently", tooltip = "This also implies that your Skills have Crit Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:CritRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:SkillCritRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionSkillCritRecently", type = "check", label = "Have your Skills Crit Recently?", ifCond = "SkillCritRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:SkillCritRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionNonCritRecently", type = "check", label = "Have you dealt a Non-Crit Recently?", ifCond = "NonCritRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:NonCritRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionChannelling", type = "check", label = "Are you Channelling?", ifCond = "Channelling", tooltip = "You will automatically be considered to be Channeling if your main skill is a channelled skill,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:Channelling", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierChannelling", type = "count", label = "Channeling for # seconds:", ifMult = "ChannellingTime", implyCond = "Channelling", tooltip = "This also implies that you are channelling", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ChannellingTime", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:Channelling", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionHitRecentlyWithWeapon", type = "check", label = "Have you Hit Recently with Your Weapon?", ifCond = "HitRecentlyWithWeapon", tooltip = "This also implies that you have Hit Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:HitRecentlyWithWeapon", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:config-highlight-suggest-pattern (killed-recently)
	-- 'doubled if killed recently' catches srtor-11 Taste for Flesh.
	-- 'killed recently' / 'on kill' catch related passive interactions.
	{ var = "conditionKilledRecently", type = "check", label = "Have you Killed Recently?", ifCond = "KilledRecently", suggestPattern = { "doubled if killed recently", "killed recently", "if you have killed" }, tooltip = "You killed an enemy in the last 4 seconds.\nFor accurate DPS vs bosses, leave unchecked — kills don't happen during a boss fight.\nEnable only when evaluating clear speed or trash mob scenarios.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:KilledRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierKilledRecently", type = "count", label = "# of Enemies Killed Recently:", ifMult = "EnemyKilledRecently", implyCond = "KilledRecently", tooltip = "Number of enemies killed in the last 4 seconds. Also implies Killed Recently.\nFor accurate boss DPS, leave at 0. Set higher only for clear speed evaluation.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:EnemyKilledRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:KilledRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionKilledLast3Seconds", type = "check", label = "Have you Killed in the last 3 Seconds?", ifCond = "KilledLast3Seconds", implyCond = "KilledRecently", tooltip = "This also implies that you have Killed Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:KilledLast3Seconds", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionMinionsKilledRecently", type = "check", label = "Have your Minions Killed Recently?", ifCond = "MinionsKilledRecently", tooltip = "Your minions killed an enemy in the last 4 seconds.\nFor accurate boss DPS, leave unchecked. Enable only for trash clear or AoE evaluation.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:MinionsKilledRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionMinionsDiedRecently", type = "check", label = "Has a Minion Died Recently?", ifCond = "MinionsDiedRecently", tooltip = "One of your minions died in the last 4 seconds.\nEnable only if your build specifically benefits when minions die (e.g., on-death triggers).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:MinionsDiedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:abomination-minions-consumed-more
	-- Assemble Abomination snapshots the minions absorbed on summon: "5% more damage per
	-- minion consumed, up to 20" (skills.json baseMod + ModParser "per minion consumed",
	-- datamined game source). This count feeds that MORE. Wrapped
	-- in a MinionModifier so the multiplier lands on the abomination minion's modDB (where the
	-- skill-scoped MORE reads it); the tag's limit=20 caps the bonus at +100% (x2.0). Default 0
	-- -> MORE 1.0 -> corpus-neutral.
	{ var = "multiplierAbominationMinionsConsumed", type = "count", label = "# of Minions Absorbed by Abomination:", ifMult = "AbominationMinionsConsumed", tooltip = "Assemble Abomination absorbs your nearby minions (Wraiths, Summoned Skeletons, Skeletal Mages, Golems, Volatile Zombies) when summoned and gains 5% more damage per minion consumed, up to 20 minions (+100% / x2.0 at the cap). This is snapshotted at summon. Enter how many minions you absorb.", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Multiplier:AbominationMinionsConsumed", "BASE", val, "Config") }, "Config")
	end },
	-- @leb-regression-guard:abomination-pertype-more
	-- Assemble Abomination per-absorbed-TYPE specialization-tree MOREs (Necromancer,
	-- TreeData/1_4/tree_3.json, treeId "aa710"). The abomination snapshots WHICH minions
	-- it absorbed on summon; several tree nodes turn those per-type counts into MORE
	-- damage (multiplicative). These configs feed the Multiplier/Condition vars that the
	-- corresponding ModParser modTagList entries (same guard) attach to the node MORE
	-- lines, which are already minion-scoped (they live on the abomination's own skill
	-- tree). Each is wrapped in a MinionModifier so the var lands on the abomination
	-- minion's modDB. All default 0 / OFF -> MORE 1.0 -> corpus-neutral.
	--   * Sharpened Bones (aa710-2): "+2% Melee Damage ... per Skeleton Warrior" (cap 20).
	--   * Engorgement (aa710-26): "+4% Damage per Minion Type Absorbed" (max 4 types).
	--   * Death in the Family (aa710-28): "+20% Damage With All Types Absorbed" (binary gate).
	-- (aa710-2's Rogue attack-speed / Archer area lines and the Health half of the
	-- Damage-and-Health line are secondary/defensive and intentionally not modeled; the
	-- Double Strike sub-skill granted by Spoils of War (aa710-6) is not modeled in LEB,
	-- so its +30%/warrior-rogue MORE has nothing to attach to -- see ModParser + spec.)
	-- See REGRESSION_GUARDS.md "abomination-pertype-more".
	{ var = "multiplierAbominationSkeletonWarriorsAbsorbed", type = "count", label = "# of Skeleton Warriors Absorbed by Abomination:", ifMult = "AbominationSkeletonWarriorsAbsorbed", tooltip = "Sharpened Bones (Assemble Abomination tree): the abomination gains +2% more Melee Damage per Skeleton Warrior absorbed, considering up to 20 skeletons total (warriors prioritised). +40% / x1.4 at 20 warriors. Snapshotted at summon.", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Multiplier:AbominationSkeletonWarriorsAbsorbed", "BASE", val, "Config") }, "Config")
	end },
	{ var = "multiplierAbominationMinionTypesAbsorbed", type = "count", label = "# of Minion Types Absorbed by Abomination:", ifMult = "AbominationMinionTypesAbsorbed", tooltip = "Engorgement (Assemble Abomination tree): the abomination deals +4% more Damage per type of minion absorbed (Summoned Skeleton, Skeletal Mage, Wraith, Bone Golem), max 4 types (+16% / x1.16 at all four). Snapshotted at summon.", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Multiplier:AbominationMinionTypesAbsorbed", "BASE", val, "Config") }, "Config")
	end },
	{ var = "multiplierAbominationSkeletonRoguesAbsorbed", type = "count", label = "# of Skeleton Rogues Absorbed by Abomination:", ifMult = "AbominationSkeletonRoguesAbsorbed", tooltip = "Sharpened Bones (Assemble Abomination tree) grants +3% Attack Speed per Skeleton Rogue absorbed (cap 20 skeletons total). This count is captured for completeness; the attack-speed line is secondary and the +3% is not currently applied (only the damage MOREs are modeled).", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Multiplier:AbominationSkeletonRoguesAbsorbed", "BASE", val, "Config") }, "Config")
	end },
	{ var = "multiplierAbominationSkeletonArchersAbsorbed", type = "count", label = "# of Skeleton Archers Absorbed by Abomination:", ifMult = "AbominationSkeletonArchersAbsorbed", tooltip = "Sharpened Bones (Assemble Abomination tree) grants +5% Area per Skeleton Archer absorbed (cap 20 skeletons total). This count is captured for completeness; the area line is secondary and the +5% is not currently applied (only the damage MOREs are modeled).", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Multiplier:AbominationSkeletonArchersAbsorbed", "BASE", val, "Config") }, "Config")
	end },
	{ var = "multiplierAbominationWarriorsOrRoguesAbsorbed", type = "count", label = "# of Warriors or Rogues Absorbed by Abomination:", ifMult = "AbominationWarriorsOrRoguesAbsorbed", tooltip = "Spoils of War (Assemble Abomination tree): if a Skeleton Warrior or Rogue is absorbed, the abomination is granted a Double Strike sub-skill that deals +30% more damage per Warrior or Rogue absorbed (cap 20). The Double Strike sub-skill IS modeled (data.skills 'Abomination Double Strike', Physical 40 / eff 2.0) and appears in the abomination's skill breakdown; this count drives its +30% MORE per Warrior/Rogue (in-game per-hit reproduced: base 40 x this-count-scaled MORE). With `minionMultiSkillCadenceFold` on (default), setting this count > 0 also folds Double Strike into the abomination's headline Full DPS at its measured 0.336 hits/s cadence (Melee 0.635/s); at 0 absorbs the fold is gated off so the headline stays single-skill Melee (byte-identical). See data.minionSkillCadence.", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Multiplier:AbominationWarriorsOrRoguesAbsorbed", "BASE", val, "Config") }, "Config")
	end },
	{ var = "conditionAbominationAllTypesAbsorbed", type = "check", label = "Abomination absorbed all 4 minion types?", ifCond = "AbominationAllTypesAbsorbed", tooltip = "Death in the Family (Assemble Abomination tree): if the abomination was made by absorbing at least one of each of Summoned Skeleton, Skeletal Mage, Wraith, and Bone Golem, it deals +20% more Damage (multiplicative). Enable if your Engorgement count reaches all 4 types.", apply = function(val, modList, enemyModList)
		modList:NewMod("MinionModifier", "LIST", { mod = modLib.createMod("Condition:AbominationAllTypesAbsorbed", "FLAG", true, "Config") }, "Config")
	end },
	{ var = "multiplierMinionsKilledRecently", type = "count", label = "# of Enemies Killed by Minions Recently:", ifMult = "EnemyKilledByMinionsRecently", implyCond = "MinionsKilledRecently", tooltip = "This also implies that your Minions have Killed Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:EnemyKilledByMinionsRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:MinionsKilledRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierManaSpentRecently", type = "count", label = "# of ^x7070FFMana ^7spent Recently:", ifMult = "ManaSpentRecently", tooltip = "Total mana spent in the last 4 seconds.\nEstimate: your skill's mana cost multiplied by casts per 4 seconds.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:ManaSpentRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBeenHitRecently", type = "check", label = "Have you been Hit Recently?", ifCond = "BeenHitRecently", tooltip = "You were hit by an enemy in the last 4 seconds.\nFor boss fights, you are typically being hit — enable for realistic defensive evaluation.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BeenHitRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierBeenHitRecently", type = "count", label = "# of times you have been Hit Recently:", ifMult = "BeenHitRecently", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:BeenHitRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:BeenHitRecently", "FLAG", 1 <= val, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBeenCritRecently", type = "check", label = "Have you been Crit Recently?", ifCond = "BeenCritRecently", tooltip = "You were critically hit by an enemy in the last 4 seconds.\nEnable only if your build has modifiers that activate on being critically hit.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BeenCritRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBlockedRecently", type = "check", label = "Have you Blocked Recently?", ifCond = "BlockedRecently", tooltip = "You blocked an incoming hit in the last 4 seconds.\nEnable for shield builds with 'after blocking' modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BlockedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBlockedAttackRecently", type = "check", label = "Have you Blocked an Attack Recently?", ifCond = "BlockedAttackRecently", implyCond = "BlockedRecently", tooltip = "This also implies that you have Blocked Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BlockedAttackRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:BlockedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionBlockedSpellRecently", type = "check", label = "Have you Blocked a Spell Recently?", ifCond = "BlockedSpellRecently", implyCond = "BlockedRecently", tooltip = "This also implies that you have Blocked Recently.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:BlockedSpellRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:BlockedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionUsedSkillRecently", type = "check", label = "Have you used a Skill Recently?", ifCond = "UsedSkillRecently", tooltip = "You used any skill in the last 4 seconds.\nFor most active builds this is always true in combat — enable freely if your build has these modifiers.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:UsedSkillRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierSkillUsedRecently", type = "count", label = "# of Skills Used Recently:", ifMult = "SkillUsedRecently", implyCond = "UsedSkillRecently", tooltip = "Number of skill uses in the last 4 seconds. Also implies Used Skill Recently.\nEstimate based on your cast rate × 4 seconds.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:SkillUsedRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:UsedSkillRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionAttackedRecently", type = "check", label = "Have you Attacked Recently?", ifCond = "AttackedRecently", implyCond = "UsedSkillRecently", tooltip = "This also implies that you have used a Skill Recently.\nYou will automatically be considered to have Attacked Recently if your main skill is an attack,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:AttackedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:UsedSkillRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionCastSpellRecently", type = "check", label = "Have you Cast a Spell Recently?", ifCond = "CastSpellRecently", implyCond = "UsedSkillRecently", tooltip = "This also implies that you have used a Skill Recently.\nYou will automatically be considered to have Cast a Spell Recently if your main skill is a spell,\nbut you can use this option to force it if necessary.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:CastSpellRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
		modList:NewMod("Condition:UsedSkillRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionStunnedEnemyRecently", type = "check", label = "Have you Stunned an Enemy Recently?", ifCond = "StunnedEnemyRecently", tooltip = "You stunned an enemy in the last 4 seconds.\nEnable only if your build has modifiers that trigger after stunning an enemy.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:StunnedEnemyRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionEchoedRecently", type = "check", label = "Have you Echoed Recently?", ifCond = "EchoedRecently", tooltip = "A skill was echoed (Shaman) in the last 4 seconds.\nEnable if Echo is a regular part of your skill rotation.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:EchoedRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionDirectlyCastColdSpellRecently", type = "check", label = "Have you Directly Cast a Cold Spell Recently?", ifCond = "DirectlyCastColdSpellRecently", tooltip = "You directly cast a Cold spell in the last 4 seconds (not via trigger or echo).\nEnable if Cold spells are in your regular skill rotation.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:DirectlyCastColdSpellRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionDirectlyCastPhysSpellRecently", type = "check", label = "Have you Directly Cast a Physical Spell Recently?", ifCond = "DirectlyCastPhysSpellRecently", tooltip = "You directly cast a Physical spell in the last 4 seconds (not via trigger or echo).\nEnable if Physical spells are in your regular skill rotation.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:DirectlyCastPhysSpellRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	-- @leb-regression-guard:ward-on-cast-health-config-amortize (config site)
	-- Opt-in gates for the Current-Health -> Ward on directly-cast-spell affixes
	-- (Twisted Heart of Uhkeiros #216 Necrotic/Elemental variants, crafted affix
	-- 766). Event-driven (game `ProtectionClass.GainWard` on cast), so kept off
	-- by default to preserve baseline parity. When enabled, CalcPerform amortizes
	-- the affix into a steady-state Ward per Second (per-cast Life% x cast rate).
	{ var = "conditionDirectlyCastNecroticSpellRecently", type = "check", label = "Have you Directly Cast a Necrotic Spell Recently?", ifCond = "DirectlyCastNecroticSpellRecently", tooltip = "You directly cast a Necrotic spell in the last 4 seconds (not via trigger or echo).\nEnable if Necrotic spells are in your regular skill rotation.\nEnables Twisted Heart of Uhkeiros' / crafted affix 766's '(5-8)% of Current Health converted to Ward when you directly cast a Necrotic Spell' as a steady-state Ward per Second (Current Life * pct / 100 * cast rate).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:DirectlyCastNecroticSpellRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionDirectlyCastElementalSpellRecently", type = "check", label = "Have you Directly Cast an Elemental Spell Recently?", ifCond = "DirectlyCastElementalSpellRecently", tooltip = "You directly cast an Elemental (Fire/Cold/Lightning) spell in the last 4 seconds (not via trigger or echo).\nEnable if Elemental spells are in your regular skill rotation.\nEnables Twisted Heart of Uhkeiros' '(5-8)% of Current Health converted to Ward when you directly cast an Elemental Spell' as a steady-state Ward per Second (Current Life * pct / 100 * cast rate).", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:DirectlyCastElementalSpellRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "conditionCastDevouringOrbRecently", type = "check", label = "Have you Cast Devouring Orb Recently?", ifCond = "CastDevouringOrbRecently", tooltip = "You cast Devouring Orb in the last 4 seconds.\nEnable if Devouring Orb is part of your regular skill rotation.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:CastDevouringOrbRecently", "FLAG", true, "Config", { type = "Condition", var = "Combat" })
	end },
	{ var = "multiplierMeteorCastRecently", type = "count", label = "# of Meteors Cast Recently (max 18):", ifMult = "MeteorCastRecently", tooltip = "Meteors cast in the last 4 seconds (max 18). Used for 'per recent meteor' modifiers (Sorcerer).\nEstimate: your Meteor cast rate × 4 seconds.", apply = function(val, modList, enemyModList)
		modList:NewMod("Multiplier:MeteorCastRecently", "BASE", val, "Config", { type = "Condition", var = "Combat" })
	end },
	-- Section: Effective DPS options
	{ section = "For Effective DPS", col = 1 },
	{ var = "meleeDistance", type = "count", label = "Melee distance to enemy:", ifTagType = "MeleeProximity", ifFlag = "melee" },
	{ var = "projectileDistance", type = "count", label = "Projectile travel distance:", ifTagType = "DistanceRamp", ifFlag = "projectile" },
	{ var = "conditionAtCloseRange", type = "check", label = "Is the enemy at Close Range?", ifCond = "AtCloseRange", tooltip = "The enemy is within close range (melee or point-blank). Enable for melee builds or builds that fight at close quarters.", apply = function(val, modList, enemyModList)
		modList:NewMod("Condition:AtCloseRange", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyMoving", type = "check", label = "Is the enemy Moving?", ifMod = "BleedChance", tooltip = "The enemy is moving. Required for Bleed application and 'against moving enemies' modifiers.\nEnable when fighting mobile enemies or adds.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Moving", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyFullLife", type = "check", label = "Is the enemy on Full ^xE05030Life?", ifEnemyCond = "FullLife", suggestPattern = { "against full health enemies", "to full life enemies", "to full health enemies" }, tooltip = "The enemy is at full health.\nFor realistic sustained DPS, leave unchecked — most combat occurs below full life.\nEnable only to evaluate opener burst or 'against full life' specific modifiers.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:FullLife", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:doubled-against-condition (enemy High Health config)
	-- Enemy is above 65% max health (LE "high health" threshold, per ss3tre-7
	-- Cold Presence / javeli-12 Monster Piercer reminderText). Distinct from
	-- FullLife (100%). Surfaces via ifEnemyCond="HighHealth" once a tree node's
	-- " Doubled Against High Health" tag registers HighHealth in
	-- enemyConditionsUsed (Calcs.lua addModTags). Default OFF: the doubling tag
	-- holds the base value until toggled, so sustained-DPS baselines are unchanged.
	{ var = "conditionEnemyHighHealth", type = "check", label = "Is the enemy at High Health?", ifEnemyCond = "HighHealth", suggestPattern = { "high health enemies", "against high health", "to high health enemies", "doubled against high health" }, tooltip = "The enemy is above 65% health.\nFor realistic sustained DPS, leave unchecked — most combat occurs below high health.\nEnable to evaluate opener burst or 'against high health' modifiers (e.g. Cold Presence, Monster Piercer).", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:HighHealth", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:config-highlight-suggest-pattern (Phase 5 Enemy Low Life)
	-- Execute-range / sub-N% boss kill modifiers — verified vocabulary
	-- from uniques_1_4.json (`below.*health`, `low health enemies`,
	-- `low life enemies`, `instantly kill enemies that are left below`).
	{ var = "conditionEnemyLowLife", type = "check", label = "Is the enemy on Low ^xE05030Life?", ifEnemyCond = "LowLife", suggestPattern = { "low health enemies", "low life enemies", "below 40% health", "instantly kill enemies that are left below", "to low health enemies", "to low life enemies", "more spell damage to low health" }, tooltip = "The enemy is below 35% health.\nEnable only to evaluate execute-range burst damage. Leave unchecked for average sustained DPS.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:LowLife", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyStunned", type = "check", label = "Is the enemy Stunned?", ifEnemyCond = "Stunned", tooltip = "The enemy is Stunned (briefly unable to act). Enable only if your build has 'against Stunned enemies' modifiers.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Stunned", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyBleeding", type = "check", label = "Is the enemy Bleeding?", ifEnemyCond = "Bleeding", tooltip = "The enemy is Bleeding. Enables Bleed DoT and 'against Bleeding enemies' modifiers.\nEnable if your build applies and benefits from Bleed.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Bleeding", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyPoisoned", type = "check", label = "Is the enemy Poisoned?", ifEnemyCond = "Poisoned", tooltip = "The enemy is Poisoned. Enables Poison DoT and 'against Poisoned enemies' modifiers.\nEnable if your build applies and benefits from Poison.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Poisoned", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierPoisonOnEnemy", type = "count", label = "# of Poison on enemy:", ifEnemyMult = "PoisonStack", implyCond = "Poisoned", tooltip = "Number of Poison stacks on the enemy. Also implies Poisoned.\nSet a realistic average value — avoid setting to max to prevent inflated DPS estimates.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:PoisonStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyBlinded", type = "check", label = "Is the enemy Blinded?", tooltip = "In addition to allowing 'against Blinded Enemies' modifiers to apply,\n Blind applies the following effects.\n -20% Accuracy \n -20% ^x33FF77Evasion", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Blinded", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyIgnited", type = "check", label = "Is the enemy ^xB97123Ignited?", ifEnemyCond = "Ignited", implyCond = "Burning", tooltip = "The enemy is ^xB97123Ignited. ^7Enables ^xB97123Ignite ^7DoT and 'against Ignited enemies' modifiers. Also implies the enemy is Burning.\nEnable if your build applies and benefits from ^xB97123Ignite.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Ignited", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:config-visibility-gating (E batch 2)
	{ var = "conditionEnemyChilled", type = "check", ifEnemyCond = "Chilled", label = "Is the enemy ^x3F6DB3Chilled?", tooltip = "The enemy is ^x3F6DB3Chilled ^7(Action Speed reduced). Enables Chill DoT and 'against Chilled enemies' modifiers.\nEnable if your build applies and benefits from Chill.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Chilled", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:ChilledConfig", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyFrozen", type = "check", label = "Is the enemy ^x3F6DB3Frozen?", ifEnemyCond = "Frozen", tooltip = "The enemy is Frozen (unable to act). Enable only if your build has 'against Frozen enemies' modifiers.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Frozen", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:config-visibility-gating (E batch 2)
	{ var = "conditionEnemyShocked", type = "check", ifEnemyCond = "Shocked", label = "Is the enemy ^xADAA47Shocked?", tooltip = "In addition to allowing any 'against ^xADAA47Shocked ^7Enemies' modifiers to apply,\nthis will allow you to input the effect of the ^xADAA47Shock ^7applied to the enemy.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Shocked", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:ShockedConfig", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:config-highlight-suggest-pattern (enemy-cursed)
	-- Highlights when the build applies/scales-with curse on the enemy.
	-- Includes 'doubled if cursed' for ch0fs-14 Eradication's OR semantics
	-- ("doubled if the enemy or you are cursed" — same notScalingStats
	-- string as ch0fs-20, so both player and enemy curse configs flag).
	{ var = "conditionEnemyCursed", type = "check", label = "Is the enemy Cursed?", suggestPattern = { "doubled if cursed", "against cursed enemies", "to cursed enemies", "curse on hit", "chance to curse" }, suggestEnemyCond = "Cursed", tooltip = "The enemy is Cursed. Enables 'against Cursed enemies' modifiers.\nEnable only if your build has curse-interaction mechanics.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Cursed", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:config-enemy-marked-for-death
	-- Marked for Death (AilmentID 17, isCurse, 8s, maxInstances 1) is a Curse
	-- that lowers ALL of the enemy's resistances by 25 (datamine ailments_v3:
	-- MarkedForDeath buff addedValue -0.25, property 30 = resistances,
	-- description "Your resistances are 25% lower"; matches tree_3 tooltip
	-- "reduces all resistances by 25%. It cannot stack"). LEB previously
	-- parsed only the application chance/duration (MarkedForDeathChance /
	-- EnemyMarkedForDeathDuration) but never applied the resistance-reduction
	-- EFFECT to the enemy. This toggle models it as -25 BASE to every
	-- <Type>Resist (all 7 DamageTypes incl. Physical), mirroring the enemy-
	-- resistance config loop below, and flags the enemy as Cursed (MfD
	-- isCurse=true) so 'against Cursed enemies' modifiers also apply.
	-- DEFAULT-OFF => corpus-neutral (no snapshot enables it, no regen). It is
	-- a static 100%-uptime toggle: in-game MfD is chance/duration-gated (e.g.
	-- a "Chance to Marked For Death on Hit" affix), so enable only when the
	-- build reliably sustains the curse.
	{ var = "conditionEnemyMarkedForDeath", type = "check", label = "Is the enemy ^xC0C0C0Marked for Death?", implyCond = "Cursed", suggestPattern = { "marked for death", "to apply marked for death" }, suggestEnemyCond = "Cursed", tooltip = "The enemy is ^xC0C0C0Marked for Death^7 — a Curse that lowers ALL of the enemy's resistances by 25 (single stack, cannot stack).\nModels the resistance-reduction effect (e.g. from a 'Chance to Marked For Death on Hit' affix, Flay, or Soul Feast). Also flags the enemy as Cursed.\nStatic toggle assumes 100% uptime — in-game Marked for Death is chance/duration-gated, so enable only if your build reliably keeps it applied.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:MarkedForDeath", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Cursed", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
		for _, damageType in ipairs(DamageTypes) do
			enemyModList:NewMod(damageType .. "Resist", "BASE", -25, "Config", { type = "Condition", var = "Effective" })
		end
	end },
	{ var = "conditionEnemySlowed", type = "check", label = "Is the enemy Slowed?", tooltip = "The enemy's Movement and Action Speed is reduced. Enable if your build has 'against Slowed enemies' modifiers.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Slowed", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyTimeRotted", type = "check", label = "Does the enemy have Time Rot?", tooltip = "The enemy has Time Rot applied. Enables 'to/from Time Rotting enemies' modifiers.\nEnable if your build applies Time Rot and has modifiers for it.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:TimeRotted", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "warMachine237", type = "list", label = "# of WarMachine:", ifCond = "WarMachine237", doNotHighlight = true,
	  list = { { val = "none", label = "None" }, { val = "237", label = "237" } },
	  apply = function(val, modList, enemyModList, build)
		if build and build.configTab then
			local customControl = build.configTab.varControls["customMods"]
			if customControl then
				if val == "237" then
					customControl:SetPlaceholder("^x66AAFFThank you very much for your support!")
				else
					customControl:SetPlaceholder("")
				end
			end
		end
	end },
	{ var = "conditionEnemyHitRecently", type = "check", label = "Was the enemy Hit Recently?", tooltip = "The enemy was hit in the last 4 seconds.\nFor most active builds this is always true — enable freely if your build has these modifiers.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:HitRecently", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyStunnedRecently", type = "check", label = "Was the enemy Stunned Recently?", tooltip = "The enemy was stunned in the last 4 seconds.\nEnable only if your build has modifiers that activate after the enemy is stunned.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:StunnedRecently", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "conditionEnemyKilledRecently", type = "check", label = "Was an enemy Killed Recently?", tooltip = "A different enemy was killed in the last 4 seconds.\nRelevant for on-kill auras that affect the current target. Leave unchecked for boss DPS estimates.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:KilledRecently", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	end },
	-- Enemy ailment stack counts (for per-stack modifiers)
	-- @leb-regression-guard:config-visibility-gating (E batch 2)
	{ var = "multiplierEnemyBleedStacks", type = "count", ifEnemyMult = "BleedStack", label = "Enemy Bleed Stacks:", implyCond = "Bleeding", tooltip = "Number of Bleed stacks on the enemy. Also implies the enemy is Bleeding.\nSet a realistic average value for your typical combat scenario.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:BleedStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Bleeding", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:config-visibility-gating (E batch 2)
	{ var = "multiplierEnemyIgniteStacks", type = "count", ifEnemyMult = "IgniteStack", label = "Enemy Ignite Stacks:", implyCond = "Ignited", tooltip = "Number of Ignite stacks on the enemy. Also implies the enemy is Ignited.\nSet a realistic average value for your typical combat scenario.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:IgniteStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Ignited", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:config-visibility-gating (E batch 2)
	{ var = "multiplierEnemyShockStacks", type = "count", ifEnemyMult = "ShockStack", label = "Enemy Shock Stacks:", implyCond = "Shocked", tooltip = "Number of Shock stacks (max 10). Each stack increases damage the enemy takes.\nAlso implies the enemy is Shocked. Set a realistic sustained value.", apply = function(val, modList, enemyModList)
		val = math.min(val, 10)
		enemyModList:NewMod("Multiplier:ShockStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Shocked", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("DamageTaken", "INC", val * 5, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyChillStacks", type = "count", label = "Enemy Chill Stacks:", implyCond = "Chilled", tooltip = "Number of Chill stacks (max 3). Reduces enemy Movement and Action Speed.\nAlso implies the enemy is Chilled.", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		enemyModList:NewMod("Multiplier:ChillStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Chilled", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyTimeRotStacks", type = "count", label = "Enemy Time Rot Stacks:", tooltip = "Number of Time Rot stacks on the enemy (max 12). Lich skill mechanic.", apply = function(val, modList, enemyModList)
		val = math.min(val, 12)
		enemyModList:NewMod("Multiplier:TimeRotStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyDoomStacks", type = "count", label = "Enemy Doom Stacks:", tooltip = "Number of Doom stacks on the enemy (max 4). Used for 'per Doom stack' modifiers.", apply = function(val, modList, enemyModList)
		val = math.min(val, 4)
		enemyModList:NewMod("Multiplier:DoomStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemySlowStacks", type = "count", label = "Enemy Slow Stacks:", implyCond = "Slowed", tooltip = "Number of Slow stacks (max 3). Also implies the enemy is Slowed.\nUsed for 'per Slow stack' modifiers.", apply = function(val, modList, enemyModList)
		val = math.min(val, 3)
		enemyModList:NewMod("Multiplier:SlowStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Slowed", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	{ var = "multiplierEnemyFrailtyStacks", type = "count", label = "Enemy Frailty Stacks:", implyCond = "Frail", tooltip = "Number of Frailty stacks on the enemy. Also implies the enemy is Frail.\nUsed for 'per Frailty stack' modifiers.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:FrailtyStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Frail", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:config-highlight-suggest-pattern (enemy-curse-stacks)
	{ var = "multiplierEnemyCurseStacks", type = "count", label = "Enemy Curse Stacks:", implyCond = "Cursed", suggestPattern = { "per curse stack", "per curse on enemy", "per curse on the enemy", "for each curse" }, tooltip = "Number of Curse stacks on the enemy. Also implies the enemy is Cursed.\nUsed for 'per Curse stack' modifiers.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Multiplier:CurseStack", "BASE", val, "Config", { type = "Condition", var = "Effective" })
		enemyModList:NewMod("Condition:Cursed", "FLAG", val >= 1, "Config", { type = "Condition", var = "Effective" })
	end },
	-- @leb-regression-guard:chaos-bolts-exult-in-misery-enemy-ailment (config site)
	-- Drives the Warlock "Exult in Misery" node (ch4bo-11, Chaos Bolts tree):
	-- Chaos Bolts hits deal +4% MORE damage per allocated point per DISTINCT
	-- negative ailment on the target (3/3 with all four = x1.48). ifMult-gated so
	-- the option only surfaces when a build references the multiplier (i.e. has the
	-- node), mirroring multiplierAerialProwessStacks. Default 0 -> multiplier 0 ->
	-- MORE factor 1.0 -> strict no-op. The count is capped at 4 (the four distinct
	-- ailments the node names); the engine itself is uncapped (maxAilments arg = 0).
	-- Fed to enemyDB.multipliers via the CalcPerform enemy-stack propagation loop.
	{ var = "multiplierEnemyNegativeAilmentCount", type = "count", label = "# Distinct Negative Ailments on Enemy (max 4):", ifMult = "EnemyNegativeAilmentCount", tooltip = "Number of DISTINCT negative ailments (damned, ignited, bleeding, frostbitten) on the enemy. Drives Chaos Bolts' 'Exult in Misery' node: Chaos Bolts hits deal +4% MORE damage per allocated point per distinct ailment, so 3/3 with all 4 = x1.48. Set 0 unless evaluating Chaos Bolts against a multi-ailment target.", apply = function(val, modList, enemyModList)
		val = math.min(val, 4)
		enemyModList:NewMod("Multiplier:EnemyNegativeAilmentCount", "BASE", val, "Config", { type = "Condition", var = "Effective" })
	end },
	-- Section: Enemy Stats
	{ section = "Enemy Stats", col = 3 },
	{ var = "leBossCategory", type = "list", label = "Is the enemy a Boss?",
	  tooltip = data.enemyIsBossTooltip,
	  defaultIndex = 2,
	  list = {
		{ val = "none",                    label = "None" },
		{ val = "Empowered Monolith Boss", label = "Empowered Monolith Boss" },
		{ val = "Dungeon Boss",            label = "Dungeon Boss (Tier 4)" },
		{ val = "Pinnacle Boss",           label = "Pinnacle Boss" },
		{ val = "Uber Boss",               label = "Uber Boss (Herald of Oblivion)" },
	  },
	  apply = function(val, modList, enemyModList)
		if val ~= "none" and data.bossStats[val] then
			local s = data.bossStats[val]
			if s.healthMean > 0 then
				enemyModList:NewMod("Life", "BASE", s.healthMean, "BossConfig")
			end
			if s.wardMean > 0 then
				enemyModList:NewMod("Ward", "BASE", s.wardMean, "BossConfig")
			end
			if s.damageModMean > 0 then
				enemyModList:NewMod("Damage", "MORE", s.damageModMean, "BossConfig")
			end
			enemyModList:NewMod("Condition:Boss", "FLAG", true, "BossConfig")
			-- @leb-regression-guard:boss-crit-damage-taken (config source)
			-- Validation provenance is retained in maintainer notes.
			enemyModList:NewMod("ReducedBonusDamageTakenFromCrits", "BASE", 0.35, "BossConfig")
		end
	  end },
	-- @leb-regression-guard:against-rares-and-bosses (config toggle)
	-- Validation provenance is retained in maintainer notes.
	{ var = "conditionEnemyRare", type = "check", label = "Is the enemy a Rare?", ifEnemyCond = "Rare", suggestPattern = { "rares and bosses", "bosses and rares" }, suggestEnemyCond = "Rare", tooltip = "The enemy is a Rare (yellow-pack) monster. Enables 'against Rares and Bosses' modifiers when the boss category is None.\nWith a Boss selected above, those modifiers already apply.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Rare", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	  end },
	-- @leb-regression-guard:against-distant-enemies (config toggle)
	-- Publishes the enemy "Distant" condition for the "Against/To Distant
	-- Enemies" conditional registered in ModParser.lua. Default OFF: the Boss
	-- Dummy capture target is at standard/point-blank range, so these
	-- range-gated mods correctly contribute 0 by default. Enable to model a
	-- far target (e.g. ranged/bow builds evaluating long-range scaling).
	{ var = "conditionEnemyDistant", type = "check", label = "Is the enemy Distant?", ifEnemyCond = "Distant", suggestPattern = { "against distant enemies", "to distant enemies" }, suggestEnemyCond = "Distant", tooltip = "The enemy is far away. Enables 'against Distant Enemies' modifiers.\nFor close-range DPS, leave unchecked. Enable only for long-range build evaluation.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:Distant", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	  end },
	-- @leb-regression-guard:against-high-health-enemies (config toggle)
	-- Validation provenance is retained in maintainer notes.
	{ var = "conditionEnemyHighHealth", type = "check", label = "Is the enemy on High ^xE05030Health?", ifEnemyCond = "HighHealth", suggestPattern = { "against high health", "to high health", "high health enemies" }, suggestEnemyCond = "HighHealth", tooltip = "The enemy is at high ^xE05030Health^7 (for example, at the opening of a boss fight). Enables 'to/against High Health' modifiers.\nLeave unchecked for a conservative full-fight average.", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Condition:HighHealth", "FLAG", true, "Config", { type = "Condition", var = "Effective" })
	  end },
	{ var = "enemyLevel", type = "count", label = "Enemy / Area Level:", defaultPlaceholderState = 100, tooltip = "This overrides the default enemy / area level used to estimate your armor reduction, ^x33FF77dodge ^7chance, and scaling of 'depending on Area Level' modifiers.\n\nThe default level is 100 and cannot exceed 100.", apply = function(val, modList, enemyModList, build)
		-- Guard: BuildModList can fire from inside ConfigTab's own constructor (before
		-- build.configTab is assigned) when placeholders are pre-seeded. The mod still
		-- needs to be added; only the varControls UI sync is skipped in that window.
		local configTab = build.configTab
		if configTab and configTab.varControls and configTab.varControls['enemyLevel'] then
			configTab.varControls['enemyLevel']:SetPlaceholder(configTab.enemyLevel, true)
		end
		-- @leb-regression-guard: area-level-multiplier-decoupled-from-mitigation
		-- The "Enemy / Area Level" field feeds TWO consumers whose correct DEFAULTS
		-- differ, so they are decoupled here:
		--   (1) Armor/Block/Dodge mitigation reads env.config.enemyLevel (set from the
		--       placeholder above = ConfigTab:UpdateLevel default = CHARACTER LEVEL).
		--       That matches the in-game character sheet (validated vs ShutFackUp lv85
		--       / MyLittleStJames lv79) and must NOT change.
		--   (2) "depending on Area Level" affixes (e.g. Cursed Veteran's Boots) read
		--       Multiplier:AreaLevel and scale with the ZONE you fight in. The endgame
		--       default is the Empowered Monolith = AREA LEVEL 100 (Bosses.lua),
		--       independent of character level (a lv70 char still runs empowered monos
		--       at area level 100).
		-- An EXPLICIT value typed into the field (input.enemyLevel > 0) overrides BOTH;
		-- only the *default* is decoupled (mitigation -> char level, area scaling -> 100).
		local explicit = configTab and configTab.input and tonumber(configTab.input.enemyLevel)
		local areaLevel = (explicit and explicit > 0) and explicit or 100
		areaLevel = m_max(m_min(areaLevel, 100), 1)
		modList:NewMod("Multiplier:AreaLevel", "BASE", areaLevel, "Config")
	end },
	{ var = "corruption", type = "count", label = "Corruption:", tooltip = "Monolith Corruption level (0-10000).\nScales enemy HP and hit damage (More %):\n  C<=100: 0.6 * C%\n  C>100:  0.002 * C^1.52 + 1.055 * C - 47.69%\nMore Damage over Time = half of the above.",
	  apply = function(val, modList, enemyModList)
		local c = m_max(val or 0, 0)
		local morePct
		if c <= data.misc.CorruptionBreakpoint then
			morePct = data.misc.CorruptionLinearRate * c
		else
			morePct = data.misc.CorruptionPowerCoeff * c ^ data.misc.CorruptionPower
			        + data.misc.CorruptionLinearCoeff * c
			        + data.misc.CorruptionConstant
		end
		if morePct > 0 then
			enemyModList:NewMod("Life", "MORE", morePct, "CorruptionConfig")
		end
	  end },
}

for i,damageType in ipairs(DamageTypes) do
    table.insert(options,  { var = "enemy" .. damageType .. "Resist", type = "integer", label = "Enemy " .. DamageTypesColored[i] .. " Resistance:", apply = function(val, modList, enemyModList)
		enemyModList:NewMod(damageType .. "Resist", "BASE", val, "EnemyConfig")
	end })
end

tableInsertAll(options, {
	{ var = "enemyBlockChance", type = "integer", label = "Enemy Block Chance:", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("BlockChance", "BASE", val, "Config")
	end },
	{ var = "enemyEvasion", type = "count", label = "Enemy Base ^x33FF77Evasion:", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Evasion", "BASE", val, "Config")
	end },
	{ var = "enemyArmour", type = "count", label = "Enemy Base Armour:", apply = function(val, modList, enemyModList)
		enemyModList:NewMod("Armour", "BASE", val, "Config")
	end },
	-- @leb-regression-guard:no-vestigial-enemy-damage-roll-range
	-- "enemyDamageRollRange" (PoB boss-skill min-max damage roll %) was removed
	-- 2026-06-05. It was doubly inert: (1) gated by ifFlag = "BossSkillActive", a
	-- flag NOTHING in LEB ever sets, so the config never even rendered; and (2)
	-- its value was read NOWHERE -- LEB models enemy hit damage as a single
	-- configured value per type (env.config.enemy<Type>Damage in CalcDefence),
	-- with no min/max roll for a "roll range %" to interpolate. The PoB
	-- boss-skill-damage model it belongs to was never ported. Removing it (vs
	-- building that model + porting PoE boss-skill data, which violates
	-- no-PoE-in-LEB) is the consistent action -- same class as lifeRegenMode.
	-- Spec: spec/System/TestConfigNoVestigialEnemyRollRange_spec.lua
	{ var = "enemySpeed", type = "integer", label = "Enemy attack / cast time in ms:", defaultPlaceholderState = 700 },
	{ var = "enemyCritChance", type = "integer", label = "Enemy critical strike chance:", defaultPlaceholderState = 5 },
	{ var = "enemyCritDamage", type = "integer", label = "Enemy critical strike multiplier:", defaultPlaceholderState = 30 }
})

for _,damageType in ipairs(DamageTypes) do
    table.insert(options,  { var = "enemy"..damageType.."Damage", type = "integer", label = "Enemy Skill "..damageType.." Damage:", defaultPlaceholderState = 1000})
end

tableInsertAll(options, {
-- Section: Custom mods
	{ section = "Custom Modifiers", col = 1 },
	{ var = "customMods", type = "text", label = "", doNotHighlight = true,
		apply = function(val, modList, enemyModList, build)
			for line in val:gmatch("([^\n]*)\n?") do
				local strippedLine = StripEscapes(line):gsub("^[%s?]+", ""):gsub("[%s?]+$", "")
				local mods, extra = modLib.parseMod(strippedLine)

				if mods and not extra then
					local source = "Custom"
					for i = 1, #mods do
						local mod = mods[i]

						if mod then
							mod = modLib.setSource(mod, source)
							modList:AddMod(mod)
						end
					end
				end
			end
		end,
		inactiveText = function(val)
			local inactiveText = ""
			for line in val:gmatch("([^\n]*)\n?") do
				local strippedLine = StripEscapes(line):gsub("^[%s?]+", ""):gsub("[%s?]+$", "")
				local mods, extra = modLib.parseMod(strippedLine)
				inactiveText = inactiveText .. ((mods and not extra) and colorCodes.MAGIC or colorCodes.UNSUPPORTED).. (IsKeyDown("ALT") and strippedLine or line) .. "\n"
			end
			return inactiveText
		end,
		tooltip = function(modList)
			if not launch.devModeAlt then
				return
			end

			local out
			for _, mod in ipairs(modList) do
				if mod.source == "Custom" then
					out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
				end
			end
			return out
		end},
})

return options
