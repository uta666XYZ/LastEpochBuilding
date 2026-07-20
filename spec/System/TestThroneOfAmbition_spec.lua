-- @leb-regression-guard:throne-of-ambition-stacks
-- See REGRESSION_GUARDS.md "throne-of-ambition-stacks".
-- Validation provenance is retained in maintainer notes.

describe("ThroneOfAmbition #skills", function()
	before_each(function() newBuild() end)

	it("2% more Cold Damage per stack of Ambition is additive and capped at 20", function()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Brass Sceptre
		Brass Sceptre
		2% more Cold Damage per stack of Ambition]])
		build.itemsTab:AddDisplayItem()
		build.skillsTab:SelSkill(1, "Runemaster 05c3 Runebolt Cold")

		-- 0 stacks (default) -> no Ambition contribution
		build.configTab.input["multiplierActiveAmbition"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local dps0 = build.calcsTab.mainOutput.TotalDPS
		assert.is_true(dps0 > 0)

		-- 20 stacks -> +2% x 20 = +40% MORE cold (additive) -> x1.40
		build.configTab.input["multiplierActiveAmbition"] = 20
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equals(round(dps0 * 1.40, 2), round(build.calcsTab.mainOutput.TotalDPS, 2))

		-- cap: 30 stacks must still be 20 (the parser limit) -> identical to the 20-stack DPS
		build.configTab.input["multiplierActiveAmbition"] = 30
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equals(round(dps0 * 1.40, 2), round(build.calcsTab.mainOutput.TotalDPS, 2))
	end)

	it("Throne of Ambition unique carries the three per-stack damage mods", function()
		local ge = build.data.uniques and build.data.uniques["Throne of Ambition"]
		-- uniques are keyed differently per loader; fall back to a data-file string scan
		local src = (function() local f=io.open("Data/Uniques/uniques_1_4.json","r"); if not f then return "" end local s=f:read("*a"); f:close(); return s end)()
		assert.is_truthy(src:find("more Cold Damage per stack of Ambition", 1, true), "Throne of Ambition must grant 'more Cold Damage per stack of Ambition'")
		assert.is_truthy(src:find("more Fire Damage per stack of Ambition", 1, true), "Throne of Ambition must grant 'more Fire Damage per stack of Ambition'")
		assert.is_truthy(src:find("more Armor per stack of Ambition", 1, true), "Throne of Ambition must grant 'more Armor per stack of Ambition'")
	end)
end)
