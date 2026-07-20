-- @leb-regression-guard:damage-over-time-penetration-parse
-- Generic DoT penetration "Damage Over Time Penetration" (uniques_1_4 #116 Atrophy
-- "+(20-25)%", #408 Weaver's Gift "+(22-33)%").
--
-- LEB BUG this fixes: modNameList had no key for the full 4-word phrase, so
-- longest-match fell to the shorter ["damage over time"] ({ "Damage", ModFlag.Dot })
-- and consumed "damage over time"; the leftover "Penetration" was then mangled -- the
-- substring "net" matched an ability named "Net" and was eaten as a {SkillName="Net"}
-- tag, leaving residue "Peration". The line thus parsed to a bogus "Damage MORE (Dot)
-- {SkillName=Net}" with NON-EMPTY residue -> Item.lua:1901 / PassiveSpec DROPPED the
-- whole mod (silent UNDER-count: the unique's DoT penetration contributed NOTHING).
-- Two stale ModCache rows cached that mangled shape and, being cache-first, shadowed
-- any live rule; both were deleted.
--
-- The fix: modNameList ["damage over time penetration"] -> { "Penetration",
-- flags = ModFlag.Dot } -- the penetration sibling of ["damage over time"]'s
-- Dot-flagged Damage. Penetration-family names bake as BASE (LE penetration is
-- additive %-shred). ModFlag.Dot scopes it to DoT: CalcOffence sums generic
-- "Penetration" in both the hit loop and the ailment/DoT loop; the Dot flag makes it
-- apply to DoT/ailment damage and be excluded from hits. NOT corpus-neutral (real
-- DoT-pen): the 8 corpus builds equipping Atrophy / Weaver's Gift were regenerated
-- (e.g. <private build> DoT Spellblade +21% FullDPS; hit-based equippers unchanged).
-- See REGRESSION_GUARDS.md "damage-over-time-penetration-parse".

describe("DamageOverTimePenetrationParse #skills", function()
	local LINE = "22% Damage Over Time Penetration"
	local DOT = 4096 -- Global.lua ModFlag.Dot

	it("parse contract: '... Damage Over Time Penetration' -> Penetration BASE, Dot-flagged, no residue", function()
		local list, extra = modLib.parseMod(LINE)
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue (else Item.lua drops it), got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("Penetration", mod.name, "must be the generic Penetration name, NOT the shorter 'damage over time' -> Damage match")
		assert.are.equal("BASE", mod.type, "LE penetration is additive %-shred -> BASE")
		assert.are.equal(22, mod.value)
	end)

	it("Dot scope: carries ModFlag.Dot (applies to DoT/ailment damage, excluded from hits)", function()
		local mod = modLib.parseMod(LINE)[1]
		assert.are.equal(DOT, mod.flags, "must carry ONLY ModFlag.Dot so CalcOffence applies it to DoTs, not hits")
	end)

	it("no mangled SkillName: the 'net' substring of Penetration must NOT become a {SkillName='Net'} tag", function()
		local mod = modLib.parseMod(LINE)[1]
		for _, tag in ipairs(mod) do
			assert.are_not.equal("SkillName", tag.type, "no SkillName tag (the old mangle ate 'net' -> SkillName='Net')")
		end
	end)

	it("longest-match: the 4-word key wins over 'damage over time' and 'penetration'", function()
		-- if the shorter 'damage over time' had matched, name would be 'Damage' + residue 'Penetration'
		local mod = modLib.parseMod(LINE)[1]
		assert.are_not.equal("Damage", mod.name, "must NOT fall back to the ['damage over time'] Damage match")
	end)
end)
