-- @leb-regression-guard:conversion-base-only-scope
-- @leb-regression-guard:weapon-added-preserved-through-conversion
-- See REGRESSION_GUARDS.md "conversion-base-only-scope" / "weapon-added-preserved-through-conversion".
-- Validation provenance is retained in maintainer notes.

describe("ConversionBaseOnlyScope", function()
	before_each(function()
		newBuild()
	end)

	it("source contract: only the skill's own base converts; ALL added (incl. weapon) is preserved", function()
		-- The "added stays" behavior is anchored by the in-game probes (Acid Flask
		-- TREE phys stays physical; Mana Strike axe-lightning stays lightning). A
		-- synthetic fixture cannot equip a non-weapon flat-damage item in this harness
		-- (ring affixes are pool-validated away), so the behavioral test below uses a
		-- WEAPON flat (which now PRESERVES) and the contract is locked here.
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcOffence.lua")
		local src = f:read("*a"); f:close()
		-- weapon flats fold into the convertible base ONLY for ailment-finishers (to DROP
		-- them). EVERY other skill -- conversion or not, forms included -- keeps its
		-- weapon-sourced added type-preserved (base-only is universal; the convertAllAdded
		-- carve-out was REMOVED 2026-06-14, see weapon-added-base-only-universal). The gate
		-- must be bare `noWeaponAdded`, NOT `skillHasConversion`/`convertAllAdded`.
		assert.is_truthy(src:find("if noWeaponAdded and next(weaponModSources) and addedDmg ~= 0 then", 1, true),
			"weapon-flat collection must be gated on the ailment-finisher ONLY")
		assert.is_falsy(src:find("if (skillHasConversion or noWeaponAdded) and next(weaponModSources)", 1, true),
			"the old bare-skillHasConversion weapon-fold gate must be gone")
		assert.is_falsy(src:find("skillHasConversion and convertAllAdded", 1, true),
			"the convertAllAddedDamage carve-out gate must be gone (forms are base-only)")
		-- the convertAllAddedDamage carve-out table must NOT exist (it was reverted)
		assert.is_falsy(src:find("local convertAllAdded = ({", 1, true),
			"the convertAllAddedDamage carve-out table must be removed (base-only universal)")
		assert.is_truthy(src:find("@leb-regression-guard:weapon-added-base-only-universal", 1, true),
			"the base-only-universal guard marker must be present")
		-- the convertible part = skill base + weaponAdded (weaponAdded is 0 for base-scoped)
		assert.is_truthy(src:find("* baseMultiplier + weaponAdded * damageEffectiveness * addedMult", 1, true),
			"skillPart must add the (conditionally-collected) weaponAdded")
		assert.is_truthy(src:find("local addedPart = (addedDmg - weaponAdded) * damageEffectiveness * addedMult", 1, true),
			"addedPart must be the remaining added pool (type-preserved)")
		-- the composition keeps the added part un-converted and un-zeroed. The converted
		-- skill-base term is retainedIntrinsic[t] (= fix[t]*retention for the acyclic/leaky
		-- path; the conserving sequential re-resolution for a pure cycle, see
		-- @leb-regression-guard:conversion-opposing-cycle-conservation).
		assert.is_truthy(src:find("convBase[t] = (retainedIntrinsic[t] or 0) + (addedBasePart[t] or 0)", 1, true),
			"convBase must compose retained skill base + retained added part")
		-- the hit-stage x convMult is gone
		assert.is_falsy(src:find("output.allMult = convMult * output.ScaledDamageEffect", 1, true),
			"the hit-stage convMult multiplication must be removed")
		-- the corrected guard marker is present
		assert.is_truthy(src:find("@leb-regression-guard:weapon-added-preserved-through-conversion", 1, true),
			"the weapon-added-preserved guard marker must be present")
	end)

	it("WEAPON-sourced added damage PRESERVES its type (does NOT convert)", function()
		-- The +30 phys is a weapon property-0 added stat -> statList -> applied AFTER
		-- conversion -> stays Physical. Only Acid Flask's OWN base (25) converts to Fire.
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Brass Sceptre
		Brass Sceptre
		+30 Physical Damage
		100% of Acid Flask Base Damage converted to Fire]])
		build.itemsTab:AddDisplayItem()
		build.skillsTab:SelSkill(1, "AcidFlask")
		runCallback("OnFrame")

		local o = build.calcsTab.mainOutput
		-- Fire = skill base 25 (converted); the weapon +30 x 1.25 (eff) stays Physical
		assert.are.equals(25, round(o.FireHitAverage, 2))
		assert.are.equals(round(30 * 1.25, 2), round(o.PhysicalHitAverage or 0, 2))
	end)

	it("no-conversion builds are unchanged (partition skipped, single pool)", function()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Brass Sceptre
		Brass Sceptre
		+30 Physical Damage]])
		build.itemsTab:AddDisplayItem()
		build.skillsTab:SelSkill(1, "AcidFlask")
		runCallback("OnFrame")
		local o = build.calcsTab.mainOutput
		assert.are.equals(round(25 + 30 * 1.25, 2), round(o.PhysicalHitAverage, 2))
		assert.are.equals(0, o.FireHitAverage or 0)
	end)
end)
