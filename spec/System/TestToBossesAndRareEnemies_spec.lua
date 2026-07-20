-- @leb-regression-guard:to-bosses-and-rare-enemies
-- Reversed-word-order enemy rarity-tier conditional "<stat> to Bosses and Rare Enemies"
-- (uniques_1_4 #290 Apostate's Sanctuary "(6-14)% more Damage to Bosses and Rare Enemies",
-- #289 Bo's Anarchy "(12-18)% more Throwing Damage to Bosses and Rare Enemies").
--
-- LEB BUG this fixes: ModParser's modTagList had ONLY the "rares and bosses" word order
-- (against/to/vs), so the unique's reversed "to Bosses and Rare Enemies" parsed the
-- leading stat but left "to Bosses and Rare Enemies" as NON-EMPTY residue -> Item.lua's
-- mod-line gate (isConnectorOnlyExtra, Item.lua:1901) DROPPED the whole mod (silent
-- UNDER-count, "node contributed nothing" class, like against-rares-and-bosses /
-- to-low-health-enemies). Two stale ModCache rows (the dropped flat-MORE + residue shape)
-- were deleted so the lines re-parse live.
--
-- The fix: modTagList ["to bosses and rare enemies"] -> ActorCondition{varList{Rare,Boss},
-- actor=enemy} (OR semantics) -- the reversed-order sibling of "to rares and bosses".
--
-- CORPUS-NEUTRAL (verified by A/B, fix-on vs fix-off): Apostate's Sanctuary / Bo's Anarchy
-- are in 0 corpus builds; the Acolyte node Ravenous (svz81-28) IS in 18 Necro/Lich builds
-- but is a PLAYER Hit MORE that their minion/DoT FullDPS does not use -> all 18 give
-- byte-identical FullDPS with the fix on or off. The fix ENABLES the node (correct) for any
-- hit-based Acolyte build. See REGRESSION_GUARDS.md "to-bosses-and-rare-enemies".

describe("ToBossesAndRareEnemies #skills", function()
	local APOSTATE = "10% more Damage to Bosses and Rare Enemies"       -- item-loader-resolved roll
	local BOS      = "15% more Throwing Damage to Bosses and Rare Enemies"
	local KEYWORD_THROWING = 1024 -- Global.lua KeywordFlag.Throwing

	local function findActorCond(mod)
		for _, tag in ipairs(mod) do
			if tag.type == "ActorCondition" then return tag end
		end
		return nil
	end
	local function hasVar(list, v)
		if not list then return false end
		for _, x in ipairs(list) do if x == v then return true end end
		return false
	end

	it("parse contract: '... to Bosses and Rare Enemies' -> MORE Damage x ActorCondition{Rare,Boss}(enemy), no residue", function()
		local list, extra = modLib.parseMod(APOSTATE)
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue (else Item.lua drops it), got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(10, mod.value)
	end)

	it("condition contract: enemy-scoped ActorCondition covering BOTH Rare and Boss (OR semantics)", function()
		local cond = findActorCond(modLib.parseMod(APOSTATE)[1])
		assert.is_not_nil(cond, "must carry an ActorCondition (else the mod is dropped/unconditional)")
		assert.are.equal("enemy", cond.actor, "the rarity tier is a property of the ENEMY")
		assert.is_not_nil(cond.varList, "must use varList for the Rare-OR-Boss disjunction")
		assert.is_true(hasVar(cond.varList, "Rare"), "must include Rare")
		assert.is_true(hasVar(cond.varList, "Boss"), "must include Boss")
	end)

	it("keyword preservation: 'more Throwing Damage ...' keeps the Throwing keyword", function()
		local mod = modLib.parseMod(BOS)[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(KEYWORD_THROWING, mod.keywordFlags, "Throwing scope must survive the tag attach")
		assert.is_not_nil(findActorCond(mod), "Throwing variant must also carry the enemy rarity condition")
	end)

	it("no SkillId: the item mod is global to the wearer, not skill-scoped", function()
		local mod = modLib.parseMod(APOSTATE)[1]
		for _, tag in ipairs(mod) do
			assert.are_not.equal("SkillId", tag.type, "an item MORE must not carry a SkillId tag")
		end
	end)

	-- Acolyte passive node "Ravenous" (svz81-28), allocated by 18 corpus Necro/Lich builds.
	-- Its tree description is "You deal more damage (multiplicative with other modifiers) to
	-- Bosses and Rare enemies", so MORE is the correct (multiplicative) type. A stale ModCache
	-- row kept it dropped (residue) until deleted; assert it now parses KEPT with the condition.
	it("Ravenous node (svz81-28): '+30% Hit Damage to Bosses And Rare Enemies' parses KEPT, MORE, Hit-flagged, enemy-conditioned", function()
		local list, extra = modLib.parseMod("+30% Hit Damage to Bosses And Rare Enemies")
		assert.is_true(not extra or extra == "", "must be residue-free (else PassiveSpec drops the node); got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type, "Ravenous is 'more damage (multiplicative)' per its tree description")
		assert.are.equal(30, mod.value)
		assert.are.equal(ModFlag.Hit, mod.flags, "must carry the Hit flag (scales hit damage)")
		local cond = findActorCond(mod)
		assert.is_not_nil(cond, "must carry the enemy Rare/Boss condition")
		assert.is_true(hasVar(cond.varList or {}, "Rare") and hasVar(cond.varList or {}, "Boss"), "condition covers Rare and Boss")
	end)
end)
