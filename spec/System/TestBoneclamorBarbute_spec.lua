-- @leb-regression-guard: boneclamor-barbute-ward-per-uncapped-necrotic-res
-- Boneclamor Barbute (unique helmet): "1 Ward per Second per 3% uncapped Necrotic Resistance"
-- Parser must consume the entire phrase (extra == nil) and emit a single BASE mod for
-- WardPerSecondPerUncappedNecroticRes_Per3 with the captured number. CalcDefence then
-- floors NecroticResistTotal/3 and adds it to output.WardPerSecond before the primary
-- Ward calculation (CalcDefence.lua:432) consumes WardPerSecond.
describe("BoneclamorBarbute", function()
	it("'1 Ward per Second per 3% uncapped Necrotic Resistance' parses cleanly", function()
		local mods, extra = modLib.parseMod("1 Ward per Second per 3% uncapped Necrotic Resistance")
		assert.is_nil(extra)
		assert.is_table(mods)
		assert.are.equal(1, #mods)
		assert.are.equal("WardPerSecondPerUncappedNecroticRes_Per3", mods[1].name)
		assert.are.equal("BASE", mods[1].type)
		assert.are.equal(1, mods[1].value)
	end)

	it("'2 Ward per Second per 3% uncapped Necrotic Resistance' scales linearly", function()
		local mods, extra = modLib.parseMod("2 Ward per Second per 3% uncapped Necrotic Resistance")
		assert.is_nil(extra)
		assert.is_table(mods)
		assert.are.equal(1, #mods)
		assert.are.equal("WardPerSecondPerUncappedNecroticRes_Per3", mods[1].name)
		assert.are.equal(2, mods[1].value)
	end)
end)
