-- @leb-regression-guard:to-moving-enemies
-- Enemy-motion damage conditional "<stat> to Moving Enemies"
-- (uniques_1_4 #306 Blood of the Exile "(30-40)% more Physical Ailment Damage to
-- Moving Enemies"; also the affix/tree "+15% Hit Damage To Moving Enemies" carried
-- by ~29 corpus builds).
--
-- LEB BUG this fixes: ModParser's modTagList had ONLY the PLAYER-self "while moving"
-- -> Condition:Moving form, NO enemy-scoped "to moving enemies" phrase, so the
-- unique/affix parsed the leading stat but left "to Moving Enemies" as NON-EMPTY
-- residue -> Item.lua's mod-line gate (isConnectorOnlyExtra, Item.lua:1901) DROPPED
-- the whole mod (silent UNDER-count, "node contributed nothing" class, same as
-- ladle-negative-ailment-on-target / to-low-health-enemies). Two stale ModCache rows
-- (the dropped MORE + residue shape, for both the ailment line and the "+15% Hit
-- Damage To Moving Enemies" affix) were deleted so the lines re-parse live.
--
-- The fix: modTagList ["to moving enemies"] -> ActorCondition{var=Moving, actor=enemy}
-- -- the enemy-scoped sibling of the player "while moving", matching the exact enemy
-- Condition:Moving that conditionEnemyMoving raises (ConfigOptions.lua ~L960/982).
--
-- CORPUS-NEUTRAL (no snapshot regen): the ONLY code path that sets the enemy
-- Condition:Moving flag is the conditionEnemyMoving config's apply function, and that
-- config is absent from EVERY corpus snapshot -> default OFF -> enemy is never flagged
-- moving -> the ActorCondition evaluates FALSE (CalcOffence.lua:2724
-- enemyDB:Flag("Condition:Moving")) -> the kept MORE is inert, byte-identical to the
-- pre-fix dropped state, across all ~29 equipping builds. Enable the config to make it
-- live (e.g. Bleed-on-moving evaluation). See REGRESSION_GUARDS.md "to-moving-enemies".

describe("ToMovingEnemies #skills", function()
	local BLOOD    = "35% more Physical Ailment Damage to Moving Enemies"  -- Blood of the Exile resolved roll
	local HIT_AFFIX = "+15% Hit Damage To Moving Enemies"                   -- affix/tree, capitalized "To"
	local HIT = 8388608 -- Global.lua ModFlag.Hit

	local function findActorCond(mod)
		for _, tag in ipairs(mod) do
			if tag.type == "ActorCondition" then return tag end
		end
		return nil
	end

	it("parse contract: '... to Moving Enemies' -> MORE AilmentDamage x ActorCondition(enemy), no residue", function()
		local list, extra = modLib.parseMod(BLOOD)
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue (else Item.lua drops it), got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("AilmentDamage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(35, mod.value)
	end)

	it("condition contract: enemy-scoped ActorCondition var=Moving (mirror of player 'while moving')", function()
		local cond = findActorCond(modLib.parseMod(BLOOD)[1])
		assert.is_not_nil(cond, "must carry an ActorCondition (else the mod is dropped/unconditional)")
		assert.are.equal("enemy", cond.actor, "the motion is a property of the ENEMY, not the player")
		assert.are.equal("Moving", cond.var)
	end)

	it("keyword/flag preservation: '+15% Hit Damage To Moving Enemies' keeps the Hit flag + condition", function()
		local mod = modLib.parseMod(HIT_AFFIX)[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(15, mod.value)
		assert.are.equal(HIT, mod.flags, "Hit scope must survive the tag attach")
		local cond = findActorCond(mod)
		assert.is_not_nil(cond, "Hit variant must also carry the enemy motion condition")
		assert.are.equal("enemy", cond.actor)
		assert.are.equal("Moving", cond.var)
	end)

	it("no SkillId: the item/affix mod is global to the wearer, not skill-scoped", function()
		local mod = modLib.parseMod(BLOOD)[1]
		for _, tag in ipairs(mod) do
			assert.are_not.equal("SkillId", tag.type, "an item MORE must not carry a SkillId tag")
		end
	end)
end)
