-- @leb-regression-guard:weapon-added-base-only-universal
-- See REGRESSION_GUARDS.md "weapon-added-base-only-universal".
-- Validation provenance is retained in maintainer notes.

describe("FormWeaponAddedBaseOnly", function()
	before_each(function()
		newBuild()
	end)

	it("source contract: the convertAllAddedDamage carve-out is GONE; weapon-fold is finisher-only", function()
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcOffence.lua")
		local src = f:read("*a"); f:close()
		assert.is_falsy(src:find("local convertAllAdded = ({", 1, true),
			"the convertAllAddedDamage carve-out table must be removed")
		assert.is_falsy(src:find("skillHasConversion and convertAllAdded", 1, true),
			"the carve-out gate (skillHasConversion and convertAllAdded) must be gone")
		-- weapon-fold now happens ONLY for the ailment-finisher (to DROP weapon flats)
		assert.is_truthy(src:find("if noWeaponAdded and actor.itemList then", 1, true),
			"weaponModSources must be built for the ailment-finisher path only")
		assert.is_truthy(src:find("if noWeaponAdded and next(weaponModSources) and addedDmg ~= 0 then", 1, true),
			"weaponAdded collection must be gated on noWeaponAdded only")
		assert.is_truthy(src:find("@leb-regression-guard:weapon-added-base-only-universal", 1, true),
			"the base-only-universal guard marker must be present")
	end)

	it("Reaper Form (weapon-path form) PRESERVES its weapon-added type; only its own base converts", function()
		-- The weapon "+30 Necrotic Damage" is a weapon-sourced added flat. With Reaper Form's
		-- base-damage conversion (here injected via the weapon line, as the rf1azz node would),
		-- ONLY the skill's own intrinsic necrotic base (2) converts to Cold; the weapon +30
		-- necrotic STAYS necrotic (base-only). Pre-revert (carve-out) this folded into the
		-- conversion and zeroed necrotic -- the bug this guard prevents.
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Brass Sceptre
		Brass Sceptre
		+30 Necrotic Damage
		100% of Reaper Form Base Damage converted to Cold]])
		build.itemsTab:AddDisplayItem()
		build.skillsTab:SelSkill(1, "ReaperForm")
		runCallback("OnFrame")

		local o = build.calcsTab.mainOutput
		-- skill's own base (necrotic 2) converts -> Cold; weapon +30 necrotic preserved.
		assert.are.equals(2, round(o.ColdDamageBase or 0, 2),
			"only the skill's own intrinsic base (2 necrotic) converts to cold")
		assert.are.equals(30, round(o.NecroticDamageBase or 0, 2),
			"weapon-sourced +30 necrotic must PRESERVE its type (base-only, NOT folded into conversion)")
		assert.is_true((o.NecroticHitAverage or 0) > 0,
			"the preserved necrotic must appear in the hit (carve-out would have zeroed it)")
	end)

	it("without a conversion node Reaper Form keeps its weapon-added typed (no conversion = byte-identical)", function()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Brass Sceptre
		Brass Sceptre
		+30 Necrotic Damage]])
		build.itemsTab:AddDisplayItem()
		build.skillsTab:SelSkill(1, "ReaperForm")
		runCallback("OnFrame")

		local o = build.calcsTab.mainOutput
		-- skill base 2 + weapon 30, all Necrotic; no Cold.
		assert.are.equals(32, round(o.NecroticDamageBase or 0, 2))
		assert.are.equals(0, round(o.ColdDamageBase or 0, 2))
	end)
end)
