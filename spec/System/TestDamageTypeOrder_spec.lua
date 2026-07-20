-- @leb-regression-guard:damage-type-ingame-order
-- Pins the in-game resistance ordering and the index alignment between
-- DamageTypes / DamageTypesColored / DamageTypeColors (src/Data/Global.lua).
-- The Resists panel (CalcSections.lua) and the max-hit / resist-over-cap /
-- power-stat rows (Build.lua, Data.lua) zip these arrays by index, so any
-- reorder that touches one array but not the others mis-orders and
-- mis-colors the display.
describe("TestDamageTypeOrder", function()
	-- In-game order shown on the character sheet Resistances panel.
	local expectedOrder = { "Fire", "Lightning", "Cold", "Physical", "Poison", "Necrotic", "Void" }

	it("damage type arrays share in-game order", function()
		assert.are.same(expectedOrder, DamageTypes)
	end)

	it("DamageTypesColored is index-aligned with DamageTypes", function()
		assert.are.equals(#DamageTypes, #DamageTypesColored)
		for i, damageType in ipairs(DamageTypes) do
			-- Each colored label must end with (and be tinted for) its own type.
			assert.is_truthy(DamageTypesColored[i]:find(damageType, 1, true),
				"DamageTypesColored[" .. i .. "] (" .. DamageTypesColored[i] ..
				") does not match DamageTypes[" .. i .. "] (" .. damageType .. ")")
			assert.are.equals(colorCodes[damageType:upper()] .. damageType, DamageTypesColored[i])
		end
	end)

	it("DamageTypeColors is index-aligned with DamageTypes", function()
		assert.are.equals(#DamageTypes, #DamageTypeColors)
		for i, damageType in ipairs(DamageTypes) do
			assert.are.equals(colorCodes[damageType:upper()], DamageTypeColors[i],
				"DamageTypeColors[" .. i .. "] does not match DamageTypes[" .. i .. "] (" .. damageType .. ")")
		end
	end)
end)
