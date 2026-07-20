-- @leb-regression-guard:subskill-grant-registry
-- Validation provenance is retained in maintainer notes.
return {
	-- @leb-regression-guard:shadow-cascade-dagger-dance
	-- Validation provenance is retained in maintainer notes.
	ShadowCascade = {
		{ skillId = "ShadowCascadeDagger", requiresNode = "dagg3-21" },
	},
	-- @leb-regression-guard:consecrated-ground
	-- Validation provenance is retained in maintainer notes.
	Judgement = {
		{ skillId = "ConsecratedGround" },
	},
	-- @leb-regression-guard:chthonic-fissure-fire-dot
	-- Chthonic Fissure's base kit leaves a FIRE ground DoT line (the "fissure")
	-- that deals fire damage over time to enemies on it. Granted as a base-kit
	-- sub-skill (ConsecratedGround pattern): source="SkillId:Warlock 04 Chthonic
	-- Fissure" routes the CF tree (Blood Gulch fire->phys, Valley of Defilement
	-- fire->poison) + per-Int onto it via groupSource. Base GROUNDED by datamine
	-- ('Fire Fissure' fs47re: Fire 5/tick, addedDamageScaling 0.25 = eff;
	-- damage_interval 258ms) and VALIDATED in-game (dicey_blank native, 2026-06-25:
	-- line fire DoT 172.5/tick @ 259ms = ~665/s, 5% of CF total). NOT the dominant
	-- component (Torment is 74-78%); this is the persistent line. Spine builds keep
	-- it too (Spine swaps Spirits->Flame Whip but the line persists).
	-- @leb-regression-guard:chthonic-fissure-soul-blast
	-- "Warlock 04.2 Arcing Soul Explosion" (Soul Blast, the Spirit's Necrotic HIT)
	-- is GRANTED here (2026-06-26 ailment-source refactor). In-game the CF cast is
	-- isHit=0 (it leaves the fire DoT line); the periodic Spirits are the ONLY
	-- isHit=1 component, so they -- not the cast -- are the real on-hit ailment +
	-- Torment source (dicey_blank capture: Soul Blast n == Torment n == 144).
	-- Pre-refactor LEB modelled the CAST as the hit, so it spawned the build's
	-- on-hit ailments ("(from Chthonic Fissure)") and triggered Torment; granting
	-- Soul Blast then would DOUBLE-count those ailments. The refactor removed the
	-- cast's `hit` flag and moved chance_to_cast_Ailment_Torment_on_hit_%=100 onto
	-- Soul Blast (skills.json), so once granted Soul Blast is a real hit: it sources
	-- the on-hit ailments + Torment as "(from Soul Blast)" with NO "(from Chthonic
	-- Fissure)" cast duplicates. As a granted sub-skill it is scanned as a trigger
	-- source by the grantedTriggeredSkills loop (it persists in socketGroupList), so
	-- the ailments attribute to it. Base GROUNDED (Necrotic 6.0 / eff 0.30) +
	-- VALIDATED in-game (dicey_blank 2026-06-26: LEB non-crit 137.26 vs in-game
	-- 155.9, -12%, enemy-cursed state LEB does not flag). Torment PRESERVED EXACTLY
	-- by the cast->spirit move (2541.6 DPS / 423.6 per-app / 6 stacks, identical;
	-- maxStacks=6 caps both rates). SPINE GATE (requiresAbsentParentTrigger): Spine
	-- of Malatros replaces the Spirits with Flame Whip ("...cast Flame Whip instead
	-- of releasing Spirits" -> ChanceToTriggerOnHit_<Flame Whip> scoped to Chthonic
	-- Fissure), so a Spine build has NO Soul Blast in-game; the grant is suppressed
	-- when the parent triggers Flame Whip on hit, and Flame Whip carries the on-hit
	-- ailments for those builds instead. BLAST RADIUS: CF is includeInFullDPS=false
	-- (display-only) in 8/9 corpus CF builds; the exception <private build> sockets CF as
	-- its includeInFullDPS=true MAIN (-2.7% FullDPS = correct cast->spirit
	-- decomposition). The CF cast's phantom base was ALSO zeroed in skills.json so
	-- the now-non-hit cast contributes 0 (the engine counts hit damage in TotalDPS
	-- regardless of the hit flag, so dropping the flag alone left a ~43% over-count
	-- on the CF-main build). See skills.json docNotes + REGRESSION_GUARDS.md
	-- "chthonic-fissure-soul-blast".
	["Warlock 04 Chthonic Fissure"] = {
		{ skillId = "Warlock Unique Chthonic Fissure DoT" },
		{ skillId = "Warlock 04.2 Arcing Soul Explosion", requiresAbsentParentTrigger = "Warlock Unique Flame Whip" },
	},
	-- @leb-regression-guard:profane-orb-grant
	-- Validation provenance is retained in maintainer notes.
	["Warlock 05 Profane Veil"] = {
		{ skillId = "Warlock 05.2 Profane Orb", requiresNode = "pr5fm-28" },
	},
	-- @leb-regression-guard:divineflare-grant
	-- Validation provenance is retained in maintainer notes.
	SigilsOfHope = {
		{ skillId = "DivineFlare", requiresNode = "si4lgl-17" },
	},
	-- @leb-regression-guard:firebrand-flame-wave-grant
	-- @leb-regression-guard:flamewave-caster-hit-context-inc
	-- Validation provenance is retained in maintainer notes.
	Firebrand = {
		{ skillId = "FlameWave", requiresNode = "f1b4d-22", inheritCasterHitContextInc = true },
	},
	-- @leb-regression-guard:charged-ground-grant
	-- @leb-regression-guard:static-orb-body-impact
	-- Validation provenance is retained in maintainer notes.
	StaticOrb = {
		{ skillId = "StaticOrbBody" },
		{ skillId = "ChargedGround", requiresNode = "so35a-4" },
	},
	-- @leb-regression-guard:avalanche-fissure-grant
	-- Validation provenance is retained in maintainer notes.
	Avalanche = {
		{ skillId = "AvalancheFissure", requiresNode = "av75ch-17" },
	},
	-- @leb-regression-guard:iron-blade-grant
	-- Validation provenance is retained in maintainer notes.
	Vengeance = {
		{ skillId = "DarkBlade", requiresNode = "gs15de-7" },
	},
	-- @leb-regression-guard:spark-discharge-base
	-- Validation provenance is retained in maintainer notes.
	["Falconer 04 Explosive Trap"] = {
		{ skillId = "SparkDischarge" },
	},
	SprigganForm = {
		-- In-form basic attack (player-cast; rate = own cast speed).
		{ skillId = "SpiritThorns" },
		-- In-form auto-cast shield; its damage output is the
		-- "Thorn Shield Burst" nova (thornShieldNova, datamined game source ID 561).
		{ skillId = "ThornShield" },
		-- @leb-regression-guard:granted-summon-pipeline
		-- @leb-regression-guard:totem-active-count-from-limit
		-- Validation provenance is retained in maintainer notes.
			{ skillId = "SummonHealingTotem", requiresNode = "sf5rd-22", summon = true, summonCount = 3,
			  summonActiveCountNode = "sf5rd-22", summonActiveCountBase = 2, summonActiveCountPerPoint = 1,
		  summonSkillWhenNode = { node = "sf5rd-21", skillId = "SummonThornTotem" },
		  grantMinionSkillId = "ThornTotemAttack", grantMinionReplaces = "ButterflyHeal", grantMinionRequiresNode = "sf5rd-21" },
	},

	-- @leb-regression-guard:upheaval-totem-grant
	-- @leb-regression-guard:shatter-totem-upheaval-child
	-- @leb-regression-guard:shatter-totem-count-fold
	-- Test: spec/System/TestShatterTotemUpheavalChild_spec.lua
	-- Validation provenance is retained in maintainer notes.
	Upheaval = {
		{ skillId = "SummonUpheavalTotem", requiresNode = "uph41-30", summon = true, summonCount = 1,
		  replacesParentHit = true,
		  summonActiveCountBase = 1, summonActiveCountNodes = { ["uph41-10"] = 1, ["uph41-11"] = 1 } },
		{ skillId = "ShatterTotem", requiresNode = "uph41-29",
		  shatterFoldCountBase = 2, shatterFoldCountNodes = { ["th39-2"] = 1 },
		  shatterFoldCountNegNodes = { ["th39-3"] = 1 } },
	},

	-- @leb-regression-guard:shadow-rend-manifest-base
	-- Test: spec/System/TestShadowRendManifestBase_spec.lua
	-- Validation provenance is retained in maintainer notes.
}
