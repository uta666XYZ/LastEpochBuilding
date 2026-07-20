-- @leb-regression-guard:typeless-split-player-direct-only
-- (@leb-regression-guard:nonconv-typeless-added-proportional): the split applies ONLY to a
-- See REGRESSION_GUARDS.md "typeless-split-player-direct-only".
-- Validation provenance is retained in maintainer notes.

describe("TypelessSplitPlayerDirectOnly", function()
	local function readCalcOffence()
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcOffence.lua")
		local src = f:read("*a"); f:close()
		return src
	end

	it("source contract: the proportional split requires the PLAYER actor", function()
		local src = readCalcOffence()
		assert.is_truthy(src:find("@leb-regression-guard:typeless-split-player-direct-only", 1, true),
			"the guard marker must be present")
		-- The split (genericAdded * ratio) must be gated on actor == env.player; a minion's
		-- inherited typeless pool must NOT take the proportional path.
		assert.is_truthy(src:find("nonConvIntrinsicTotal > 0 and actor == env.player", 1, true),
			"the proportional split must require `nonConvIntrinsicTotal > 0 and actor == env.player`")
	end)

	it("source contract: the non-split branch applies the FULL typeless pool (minion-inherited = full per-type)", function()
		local src = readCalcOffence()
		-- The else-branch (minion actor, OR all-zero base) applies the FULL genericAdded so a
		-- minion's inherited "+X Damage" lands full on every intrinsic type.
		assert.is_truthy(src:find("allAddedDmg = genericAdded%s*\n"),
			"the non-split branch must apply the FULL typeless pool: `allAddedDmg = genericAdded`")
		-- And the player split line is still present (the player path is preserved unchanged).
		assert.is_truthy(src:find("genericAdded * ((sv > 0 and sv or 0) / nonConvIntrinsicTotal)", 1, true),
			"the player-direct proportional split line must remain intact")
	end)
end)
