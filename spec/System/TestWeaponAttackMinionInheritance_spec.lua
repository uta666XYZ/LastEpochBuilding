-- @leb-regression-guard:weapon-attack-minion-weapon-inheritance
-- See REGRESSION_GUARDS.md "weapon-attack-minion-weapon-inheritance".
-- Validation provenance is retained in maintainer notes.
describe("WeaponAttackMinion", function()
	before_each(function()
		newBuild()
		-- Lock the player level so the minion's level-MORE multiplier (and therefore the
		-- absolute per-type hit values asserted below) is deterministic. <26 -> MORE = 1.
		build.characterLevel = 1
	end)

	local function selectBallista()
		build.skillsTab:SelSkill(1, "SummonBallista")
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion = RogueBallista")
		return minion.output
	end

	it("bow-attack minion inherits the equipped bow's per-type added damage, PER TYPE", function()
		-- A bow whose only damage affixes are +10 Bow Fire and +20 Bow Lightning (no cold).
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
Shortbow
Shortbow
+10 Bow Fire Damage
+20 Bow Lightning Damage]])
		build.itemsTab:AddDisplayItem()
		local o = selectBallista()
		-- Fire and Lightning are inherited; Cold (no source affix) stays exactly 0 -> the
		-- inheritance is PER TYPE, not a blanket fold.
		assert.is_true((o.FireHitAverage or 0) > 0, "bolt must inherit bow Fire damage")
		assert.is_true((o.LightningHitAverage or 0) > 0, "bolt must inherit bow Lightning damage")
		assert.are.equals(0, o.ColdHitAverage or 0, "no Cold affix -> bolt deals NO cold (per-type, no fold)")
		-- The two elemental added flats scale through one shared (generic) INC/MORE pool, so
		-- the bolt's per-type hit ratio equals the added ratio exactly: Lightning 20 = 2x Fire 10.
		assert.are.equals(round(2 * o.FireHitAverage, 2), round(o.LightningHitAverage, 2),
			"Lightning (added 20) must be exactly 2x Fire (added 10) -- type-preserved, no cross-type bleed")
	end)

	it("inheriting elemental added does NOT inflate the bolt's Physical (no spurious phys)", function()
		-- Baseline: bow with NO damage affixes -> bolt Physical is the skill stub base only.
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: NORMAL
Shortbow
Shortbow]])
		build.itemsTab:AddDisplayItem()
		local basePhys = selectBallista().PhysicalHitAverage or 0
		assert.is_true(basePhys > 0, "bolt keeps its physical skill-base")

		-- Same bow but with heavy elemental added: Physical must be UNCHANGED (the abandoned
		-- melee fix would have folded the weapon flats into Physical and inflated it).
		newBuild(); build.characterLevel = 1
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
Shortbow
Shortbow
+50 Bow Fire Damage
+50 Bow Cold Damage
+50 Bow Lightning Damage]])
		build.itemsTab:AddDisplayItem()
		local o = selectBallista()
		assert.are.equals(round(basePhys, 2), round(o.PhysicalHitAverage or 0, 2),
			"elemental bow affixes must NOT add to the bolt's Physical")
		assert.is_true((o.FireHitAverage or 0) > 0 and (o.ColdHitAverage or 0) > 0 and (o.LightningHitAverage or 0) > 0,
			"all three elemental affixes inherited")
	end)

	it("SCOPED: a non-bow equipped weapon is NOT inherited by the bow-attack minion", function()
		-- A dagger carrying +Melee Fire Damage. weaponData1.type ~= 'Bow' -> the inheritance
		-- gate (weaponKeyword) never fires; the bolt deals no fire.
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
Poignard
Poignard
+40 Melee Fire Damage]])
		build.itemsTab:AddDisplayItem()
		local o = selectBallista()
		assert.are.equals(0, o.FireHitAverage or 0, "a melee weapon's flats must NOT reach the bow-attack minion")
	end)

	it("SCOPED: a non-weapon-attack minion does NOT inherit the bow (skill-type gate)", function()
		-- Equip the elemental bow but summon a MELEE minion (bear). The bear's granted skill
		-- is not a bow attack (band(skillTypeTags, Bow) == 0), so isWeaponAttackMinion is false
		-- and no bow flats transfer -> the bear deals no fire from the bow.
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
Shortbow
Shortbow
+50 Bow Fire Damage]])
		build.itemsTab:AddDisplayItem()
		build.skillsTab:SelSkill(1, "SummonBear")
		runCallback("OnFrame")
		local minion = build.calcsTab.mainEnv.minion
		assert.is_not_nil(minion, "expected env.minion = bear")
		assert.are.equals(0, minion.output.FireHitAverage or 0,
			"a melee minion must NOT inherit the equipped bow's Fire damage")
	end)

	it("source contract: minion-modDB only, keyword-gated, per-type, no untyped phys fold", function()
		local f = io.open("Modules/CalcPerform.lua", "r") or io.open("src/Modules/CalcPerform.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcPerform.lua")
		local src = f:read("*a"); f:close()
		assert.is_truthy(src:find("@leb-regression-guard:weapon-attack-minion-weapon-inheritance", 1, true),
			"guard marker must be present")
		-- The copy targets the MINION modDB (not the player hit-loop) -> zero player ripple.
		assert.is_truthy(src:find("env.minion.modDB:AddMod(copyTable(mod))", 1, true),
			"inherited mods must be added to env.minion.modDB ONLY")
		-- Gated by the equipped weapon's keyword bit (band) -> global (kw=0) player INC excluded,
		-- and the copy is restricted to flat-added / damage names (no blanket physical fold).
		assert.is_truthy(src:find("band(mod.keywordFlags, weaponKeyword) ~= 0", 1, true),
			"copy must be keyword-gated (only weapon-keyword mods transfer)")
		assert.is_truthy(src:find("weaponData.type == \"Bow\" and ModFlag.Bow", 1, true),
			"the equipped-weapon -> keyword mapping (Bow) must be present")
		-- It must NOT use the abandoned untyped player-hit isWeaponAttack/keywordFlags-Attack gate.
		assert.is_falsy(src:find("isWeaponAttack = band(cfg.keywordFlags", 1, true),
			"must NOT resurrect the abandoned untyped player-hit-loop weapon gate (6eaef6bc9)")
	end)

	it("WHITELIST: gated by LE_WEAPON_ATTACK_MINIONS -- SummonedSkeletonArcher excluded", function()
		-- The skill-type check (fromMinion + attack + Bow keyword) is necessary but NOT
		-- sufficient: SummonedSkeletonArcher also grants a "Summon Skeleton Archer Bow Attack"
		-- (skillTypeTags Bow|Physical) and would otherwise silently inherit the player's bow,
		-- unvalidated. Only the in-game-validated RogueBallista is whitelisted. Lock both the
		-- gate site and the registry membership.
		local f = io.open("Modules/CalcPerform.lua", "r") or io.open("src/Modules/CalcPerform.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcPerform.lua")
		local src = f:read("*a"); f:close()
		assert.is_truthy(src:find("LE_WEAPON_ATTACK_MINIONS[env.minion.type]", 1, true),
			"inheritance must be gated by the LE_WEAPON_ATTACK_MINIONS whitelist (not the skill check alone)")
		assert.is_not_nil(LE_WEAPON_ATTACK_MINIONS, "the whitelist registry must exist")
		assert.is_not_nil(LE_WEAPON_ATTACK_MINIONS.RogueBallista,
			"the in-game-validated RogueBallista must be whitelisted")
		assert.are.equals("Bow", LE_WEAPON_ATTACK_MINIONS.RogueBallista.weapon,
			"RogueBallista fires a Bow")
		assert.is_nil(LE_WEAPON_ATTACK_MINIONS.SummonedSkeletonArcher,
			"unvalidated SummonedSkeletonArcher must NOT be whitelisted (it would inherit the player's bow)")
	end)
end)
