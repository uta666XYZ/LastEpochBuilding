-- @leb-regression-guard:while-at-full-health
-- Player-self "at Full Health/Life" damage/crit conditional (uniques_1_4 #133 Xithara's
-- Conundrum "(25-30)% more Physical Damage while at Full Health"; also the common
-- "+40% <Melee/Throwing> Critical Strike Multiplier while at Full Health" affix and
-- "10% Increased Damage at Full Health").
--
-- LEB BUG this fixes: the parser had the ENEMY form ("against full health enemies" ->
-- ActorCondition FullLife) but NO player-self "while at full health" phrase. So these
-- parsed the leading stat but left "while at Full Health" as NON-EMPTY residue ->
-- Item.lua's mod-line gate (isConnectorOnlyExtra, Item.lua:1901) / PassiveSpec DROPPED
-- the whole mod (silent UNDER-count, "node contributed nothing" class, same as
-- to-low-health-enemies / to-moving-enemies). Stale ModCache rows cached those dropped
-- shapes; they were deleted so the lines re-parse live.
--
-- The fix: modTagList player forms ("at full health" / "while at full health" / "at
-- full life" / "while at full life" / "on full health" / "while on full health") ->
-- Condition{var=FullLife} -- the player-self FullLife mirror of the LowLife player
-- forms, and the player sibling of the enemy "against full health enemies". These are
-- exactly conditionFullLife's own suggestPattern vocabulary (ConfigOptions L92); it
-- just had no modTagList entry to resolve them.
--
-- CORPUS-NEUTRAL (deductively proven, no snapshot regen): the ONLY setter of the player
-- Condition:FullLife flag is conditionFullLife's apply (ConfigOptions L93), and that
-- config is absent from EVERY corpus snapshot -> default OFF -> the player is never
-- flagged full life -> the Condition evaluates FALSE -> the kept mod is inert,
-- byte-identical to the pre-fix dropped state (all 23 equipping builds unaffected).
-- Enable the config (opener/burst) to make it live. See REGRESSION_GUARDS.md
-- "while-at-full-health".

describe("WhileAtFullHealth #skills", function()
	local XITHARA = "27% more Physical Damage while at Full Health"  -- Xithara resolved roll
	local CRIT    = "+40% Melee Critical Strike Multiplier while at Full Health"
	local KEYWORD_MELEE = 512 -- Global.lua KeywordFlag.Melee

	local function findTag(mod, tagType)
		for _, tag in ipairs(mod) do
			if tag.type == tagType then return tag end
		end
		return nil
	end

	it("parse contract: '... while at Full Health' -> MORE PhysicalDamage x Condition:FullLife, no residue", function()
		local list, extra = modLib.parseMod(XITHARA)
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue (else Item.lua drops it), got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("PhysicalDamage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(27, mod.value)
	end)

	it("player scope: a self Condition:FullLife (actor=nil), NOT the enemy ActorCondition", function()
		local mod = modLib.parseMod(XITHARA)[1]
		local cond = findTag(mod, "Condition")
		assert.is_not_nil(cond, "must carry a player-self Condition (else the mod is dropped/unconditional)")
		assert.are.equal("FullLife", cond.var)
		assert.is_nil(cond.actor, "must be the PLAYER self-condition, not an enemy ActorCondition")
		assert.is_nil(findTag(mod, "ActorCondition"), "must NOT be enemy-scoped (that is 'against full health enemies')")
	end)

	it("keyword preservation: crit-mult 'while at Full Health' keeps Melee + FullLife condition", function()
		local mod = modLib.parseMod(CRIT)[1]
		assert.are.equal("CritMultiplier", mod.name)
		assert.are.equal("BASE", mod.type)
		assert.are.equal(40, mod.value)
		assert.are.equal(KEYWORD_MELEE, mod.keywordFlags, "Melee scope must survive the tag attach")
		local cond = findTag(mod, "Condition")
		assert.is_not_nil(cond)
		assert.are.equal("FullLife", cond.var)
	end)

	it("'at full health' (no 'while') and 'on full health' variants also resolve", function()
		for _, line in ipairs({ "10% Increased Damage at Full Health", "15% Increased Damage while on Full Health" }) do
			local list, extra = modLib.parseMod(line)
			assert.is_true(not extra or extra == "", "no residue for: " .. line .. " got: " .. tostring(extra))
			local cond = findTag(list[1], "Condition")
			assert.is_not_nil(cond, "must carry Condition for: " .. line)
			assert.are.equal("FullLife", cond.var)
		end
	end)
end)
