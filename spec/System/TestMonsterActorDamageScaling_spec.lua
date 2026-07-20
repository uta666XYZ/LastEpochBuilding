-- @leb-regression-guard:minion-monster-actor-damage-scaling
-- scale[100]/scale[10] = 10.892858/1.757143. See REGRESSION_GUARDS.md
-- Validation provenance is retained in maintainer notes.

describe("MonsterActorDamageScaling #minions", function()
	local mds = LoadModule("Data/MonsterDamageScaling")

	it("scale table preserves the engine's key level ratios (runtime-captured 1.4.7c)", function()
		-- relative-to-level-1 array: scale[1] == 1, monotone non-decreasing.
		assert.are.equal(1.0, mds.scale[1])
		assert.is_true(mds.scale[100] > mds.scale[10])
		-- Anurok in-game-validated multiplier: scale[100]/scale[10] ~ 6.199.
		assert.is_true(math.abs(mds.scale[100] / mds.scale[10] - 6.199) < 0.01,
			"scale[100]/scale[10] must be ~6.199 (Anurok lv100 from lv10)")
	end)

	it("getMonsterDamageMorePercent returns the table ratio as a MORE percent", function()
		-- (from 10 -> to 100) = (6.199 - 1) * 100 ~ 519.9
		assert.is_true(math.abs(mds.getMonsterDamageMorePercent(10, 100) - 519.92) < 1.0)
		-- identity level -> 0 MORE
		assert.are.equal(0, mds.getMonsterDamageMorePercent(10, 10))
		-- from level 1 -> 100 = (scale[100] - 1) * 100
		assert.is_true(math.abs(mds.getMonsterDamageMorePercent(1, 100) - (mds.scale[100] - 1) * 100) < 0.001)
		-- clamps out-of-range to [0,100]; never errors
		assert.are.equal(mds.getMonsterDamageMorePercent(10, 100), mds.getMonsterDamageMorePercent(10, 250))
		assert.is_number(mds.getMonsterDamageMorePercent(nil, nil))
	end)

	it("repurposed-monster minions carry monsterScaling.fromLevel; companions do not", function()
		-- ActorScaler-scaled monsters (datamined ActorStats level = 10):
		for _, key in ipairs({ "PrimalAnurok", "PrimalTyrannosaur", "TolmatMinionDivine" }) do
			assert.is_table(data.minions[key], key .. " must exist in minions.json")
			assert.is_table(data.minions[key].monsterScaling, key .. " must have monsterScaling")
			assert.are.equal(10, data.minions[key].monsterScaling.fromLevel)
		end
		-- player companions must NOT be tagged (they keep the +0.8%/level MORE):
		for _, key in ipairs({ "PrimalWolf", "PrimalBear", "Bee", "FireBee", "LightningBee" }) do
			if data.minions[key] then
				assert.is_nil(data.minions[key].monsterScaling, key .. " (companion) must NOT have monsterScaling")
			end
		end
	end)
end)
