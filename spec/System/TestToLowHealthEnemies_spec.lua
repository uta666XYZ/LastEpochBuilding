-- @leb-regression-guard:to-low-health-enemies
-- Enemy-scoped "to low health enemies" damage conditional (uniques_1_4 #293
-- Swaddling of the Erased: "(12-17)% more Spell Damage to Low Health Enemies").
--
-- LEB BUG this fixes: ModParser's modTagList had the PLAYER-self "at low health" /
-- "while at low health" -> Condition:LowLife forms, but NO enemy-scoped "to low
-- health enemies" phrase. So the item stat parsed its leading "more Spell Damage"
-- but left "to Low Health Enemies" as NON-EMPTY residue -> Item.lua's mod-line gate
-- (isConnectorOnlyExtra, Item.lua:1901) DROPPED the whole mod -- the unique's
-- execute-range MORE contributed NOTHING (the "node contributed nothing" class,
-- same as ladle-negative-ailment-on-target / against-rares-and-bosses, NOT an
-- over-count). A stale Data/ModCache.lua row cached that dropped shape (flat MORE 14
-- + residue) and, being cache-first, shadowed any live rule; it was deleted.
--
-- The fix: modTagList ["to low health enemies"] -> ActorCondition{var=LowLife,
-- actor=enemy} -- the mirror of the pre-existing "against full health enemies"
-- (var=FullLife) entry. conditionEnemyLowLife (ConfigOptions ~L980) already
-- anticipates this exact vocabulary in its suggestPattern.
--
-- CORPUS-NEUTRAL: conditionEnemyLowLife defaults OFF -> the enemy is not flagged
-- low life -> the (non-neg) LowLife enemy condition is FALSE -> the MORE is inert
-- by default (verified: all 22 corpus builds equipping Swaddling have LowLife OFF,
-- 0/22 change, NO snapshot regen). Enabling the config (execute/burst evaluation)
-- makes it live. See REGRESSION_GUARDS.md "to-low-health-enemies".

local KEYWORD_SPELL = 256 -- Global.lua KeywordFlag.Spell

describe("ToLowHealthEnemies #skills", function()
	-- item-loader-resolved (range already collapsed to a concrete roll)
	local LINE = "12% more Spell Damage to Low Health Enemies"

	local function findTag(mod, tagType, var)
		for _, tag in ipairs(mod) do
			if tag.type == tagType and (var == nil or tag.var == var) then
				return tag
			end
		end
		return nil
	end

	it("parse contract: item text -> MORE Spell Damage 12% x ActorCondition:LowLife(enemy), no residue", function()
		local list, extra = modLib.parseMod(LINE)
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue (else Item.lua drops it), got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(12, mod.value)
		assert.are.equal(KEYWORD_SPELL, mod.keywordFlags, "must carry the Spell keyword (scales spell damage only)")
	end)

	it("conditional contract: the MORE is enemy-LowLife-gated (NOT an always-on flat MORE)", function()
		-- A bare MORE (no ActorCondition) would apply unconditionally = wrong: the item
		-- only buffs damage vs low-health (execute-range) enemies. The tag is what makes
		-- it inert by default (enemy not low life) and live only under the LowLife config.
		local list = modLib.parseMod(LINE)
		local cond = findTag(list[1], "ActorCondition", "LowLife")
		assert.is_not_nil(cond, "must carry ActorCondition:LowLife (else it is an always-on MORE phantom)")
		assert.are.equal("enemy", cond.actor, "the low-life condition is read from the ENEMY (execute range), not the player")
	end)

	it("enemy scope: must NOT be the player-self LowLife (a Condition tag), which is a different mechanic", function()
		local list = modLib.parseMod(LINE)
		-- the player-self forms ("at low health") produce a plain Condition{var=LowLife}
		-- with no actor=enemy; assert we did not collapse to that.
		local selfCond = findTag(list[1], "Condition", "LowLife")
		assert.is_nil(selfCond, "must not be the player-self Condition:LowLife (that is 'while at low health')")
	end)

	it("no SkillId: the item mod is global to the wearer's spells, not skill-scoped", function()
		local list = modLib.parseMod(LINE)
		assert.is_nil(findTag(list[1], "SkillId"), "an item MORE must not carry a SkillId tag")
	end)
end)
