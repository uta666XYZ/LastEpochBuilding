-- @leb-regression-guard:ladle-negative-ailment-on-target
-- Mad Alchemist's Ladle (unique, Data/Uniques/uniques_1_4.json id 321):
--   "6% more Spell Damage per Negative Ailment on the Target (up to 8)"
-- Same engine mechanic as Chaos Bolts' "Exult in Misery" -- a
-- DamageEffectMoreDamagePerNegativeAilment scaled by the count of DISTINCT negative
-- ailments on the target (datamined game source
-- factor = 1 + perAilment * GetUniqueNegativeAilmentCount) -- but the ITEM text says
-- "on the Target" (the tree node's rewritten text says "on Enemy").
--
-- LEB BUG this fixes: ModParser's modTagList had only "per negative ailment on enemy",
-- so the item phrase "per negative ailment on the target" was UNRECOGNIZED and left as
-- NON-EMPTY residue ("   per Negative Ailment on the Target  "). Item.lua's mod-line
-- gate (`not modLine.extra`) then DROPPED the mod entirely -- the Ladle contributed
-- NOTHING to spell damage (the "node contributed nothing" class, same as
-- chaos-bolts-exult-in-misery / aerial-prowess, NOT an active over-count). A stale
-- Data/ModCache.lua row cached that dropped shape (flat MORE 6 + residue) and, being
-- cache-first, shadowed any live rule. So the Ladle's real mechanic -- 6% more Spell
-- PER distinct enemy negative ailment up to 8 (max +48%, 0 with none) -- was absent.
--
-- The fix: (1) delete the stale ModCache line; (2) add modTagList
-- ["per negative ailment on the target"] -> Multiplier:EnemyNegativeAilmentCount
-- (actor="enemy", limit=8). "per stack of bleed on the target" already establishes the
-- "on the target" suffix == actor=enemy. limit=8 = the item's own cap (the shared
-- "on enemy" entry stays limit-less: its Chaos Bolts consumer is config-capped at 4).
-- ModParser strips the "(up to 8)" parenthetical before the modTagList lookup, so the
-- key carries no parens (cap rides the tag's limit) and the mod now parses RESIDUE-FREE
-- -> the item loader KEEPS it.
--
-- Default config EnemyNegativeAilmentCount = 0 -> multiplier 0 -> MORE factor 1.0
-- (strict no-op). The fix is therefore CORPUS-NEUTRAL (all 28 corpus Ladle builds
-- byte-identical, NO snapshot regen) and its value is newly ENABLING the per-ailment
-- scaling that was dropped (verified: Rip Blood Warlock om6xj3n8 FullDPS x1.26 at
-- count=8). 5 Maxroll S-tier builds carry the Ladle (Profane Veil / Rip Blood Lich +
-- Warlock / Lightning Blast RM / Shatter Totem Werebear). See REGRESSION_GUARDS.md
-- "ladle-negative-ailment-on-target".

local KEYWORD_SPELL = 256 -- Global.lua KeywordFlag.Spell

describe("LadleNegativeAilmentOnTarget #skills", function()
	local LADLE = "6% more Spell Damage per Negative Ailment on the Target (up to 8)"

	local function findTag(mod, tagType, var)
		for _, tag in ipairs(mod) do
			if tag.type == tagType and (var == nil or tag.var == var) then
				return tag
			end
		end
		return nil
	end

	it("parse contract: item text -> MORE Spell Damage 6% x Multiplier:EnemyNegativeAilmentCount(enemy, limit 8), no residue", function()
		local list, extra = modLib.parseMod(LADLE)
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Damage", mod.name)
		assert.are.equal("MORE", mod.type)
		assert.are.equal(6, mod.value)
		assert.are.equal(KEYWORD_SPELL, mod.keywordFlags, "must carry the Spell keyword (scales spell damage only)")
	end)

	it("scaling contract: the MORE is per-distinct-ailment (NOT a flat +6%) -> 0 at no ailments", function()
		-- A bare MORE (no Multiplier tag) would be an always-on flat +6% -- wrong in the
		-- other direction. The multiplier tag is what makes the Ladle 0 at count=0 and
		-- scale to +48% at 8. (Pre-fix the mod was DROPPED for its residue and contributed
		-- nothing; this asserts the RE-ENABLED mod is correctly count-gated, not flat.)
		local list = modLib.parseMod(LADLE)
		local mod = list[1]
		local mult = findTag(mod, "Multiplier", "EnemyNegativeAilmentCount")
		assert.is_not_nil(mult, "must carry Multiplier:EnemyNegativeAilmentCount (else it is a flat +6% phantom)")
		assert.are.equal("enemy", mult.actor, "the count is read from the enemy modDB (mirrors per-Bleed / Chaos Bolts precedent)")
	end)

	it("cap: the item's (up to 8) is modeled as tag limit=8", function()
		local list = modLib.parseMod(LADLE)
		local mult = findTag(list[1], "Multiplier", "EnemyNegativeAilmentCount")
		assert.are.equal(8, mult.limit, "the '(up to 8)' cap must attach as limit=8 (distinct from the limit-less Chaos Bolts entry)")
	end)

	it("no SkillId: the item mod is global to the wearer's spells, not skill-scoped", function()
		local list = modLib.parseMod(LADLE)
		assert.is_nil(findTag(list[1], "SkillId"), "an item MORE must not carry a SkillId tag")
	end)
end)
