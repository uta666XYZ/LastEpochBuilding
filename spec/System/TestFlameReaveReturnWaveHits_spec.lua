-- @leb-regression-guard:flame-reave-return-wave-hits
-- Flame Reave return-waves are full-damage, same-cast hits on the SAME target, so
-- they scale sustained single-target DPS directly (dpsMultiplier, like ProjectileCount),
-- NOT AverageBurstHits (a burst-DISPLAY field that does not feed TotalDPS). Two nodes:
--   * "Flame Caller" (fr11mv-18, " Returns To You") = +1 UNCONDITIONAL same-target hit.
--   * "Reflash" (fr11mv-16, " Expands and Returns Again" + "3 Cooldown (seconds)") =
--     +2 same-target hits but on its OWN 3s cooldown -> fires >=once per 3s regardless
--     of cast rate -> cast-rate-AVERAGED +min(2, 2/(3*castRate)) hits/cast.
-- Both raw stats parse to 0 hit-count mods, so the effect is injected in CalcPerform
-- (SkillId:FlameReave-scoped, Sentinel-61 precedent) and consumed in CalcOffence. The
-- natural phrase "Additional Same Target Hits" collides with ModParser "additional"/
-- "hits" tokens, so parse is NOT used. Capture (4guanghuan 20260707_140512_03) hits/cast
-- ~2.5 (250ms cast-grouping) = Flame Caller (+1) + Reflash (~+0.5 at the in-game cast
-- rate). See REGRESSION_GUARDS.md "flame-reave-return-wave-hits".

describe("FlameReaveReturnWaveHits #skills", function()
	local function readSource(p) local f = io.open(p, "r"); if not f then return nil end local s = f:read("*a"); f:close(); return s end

	it("raw node stats parse to no hit-count mod (justifies the CalcPerform inject)", function()
		local fc = modLib.parseMod(" Returns To You")
		assert.are.equal(0, #(fc or {}), "Flame Caller stat yields no mod")
		local rf = modLib.parseMod(" Expands and Returns Again")
		assert.are.equal(0, #(rf or {}), "Reflash stat yields no mod")
	end)

	it("no LE_TREE_NODE_STAT_REWRITE for fr11mv-18 / fr11mv-16 (injected, not parsed)", function()
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["fr11mv-18"], "Flame Caller is CalcPerform-injected")
		assert.is_nil(LE_TREE_NODE_STAT_REWRITE["fr11mv-16"], "Reflash is CalcPerform-injected")
	end)

	it("CalcPerform: Flame Caller fr11mv-18 -> AdditionalSameTargetHits BASE 0.5 (return hit at 50% dmg), SkillId:FlameReave", function()
		local src = readSource("Modules/CalcPerform.lua")
		assert.is_not_nil(src)
		assert.is_truthy(src:find('env.allocNodes["fr11mv-18"]', 1, true), "node-gated on Flame Caller")
		assert.is_truthy(src:find('NewMod("AdditionalSameTargetHits", "BASE", 0.5', 1, true), "+1 return hit x 0.5 dmg = +0.5 equivalent")
		assert.is_truthy(src:find('skillId = "FlameReave"', 1, true), "scoped to Flame Reave")
	end)

	it("CalcPerform: Reflash fr11mv-16 -> FlameReaveReflashActive flag, SkillId:FlameReave", function()
		local src = readSource("Modules/CalcPerform.lua")
		assert.is_truthy(src:find('env.allocNodes["fr11mv-16"]', 1, true), "node-gated on Reflash")
		assert.is_truthy(src:find('NewMod("FlameReaveReflashActive", "FLAG", true', 1, true), "flag emitted")
	end)

	it("CalcOffence: return-waves scale dpsMultiplier; Reflash cast-rate-averaged min(1, 1/(3*Speed))", function()
		local src = readSource("Modules/CalcOffence.lua")
		assert.is_not_nil(src)
		assert.is_truthy(src:find("AdditionalSameTargetHits", 1, true), "reads Flame Caller hit-equivalents")
		assert.is_truthy(src:find('Flag(skillCfg, "FlameReaveReflashActive")', 1, true), "reads Reflash flag (skill-scoped)")
		assert.is_truthy(src:find("m_min(1, 1 / (3 * output.Speed))", 1, true), "Reflash 2 hits x 0.5 = 1.0 equiv/firing, cast-rate-averaged, cap 1")
		assert.is_truthy(src:find("dpsMultiplier * (1 + additionalSameTargetHits)", 1, true), "one combined return-wave multiplier")
	end)

	it("Reflash cast-rate-average formula: min(1, 1/(3*castRate)) -- 2 hits x 0.5 penalty, cap 1, scales with 1/castRate", function()
		local function reflash(cr) return math.min(1, 1 / (3 * cr)) end
		assert.is_true(math.abs(reflash(3.696) - 0.09019) < 1e-4, "fast (LEB) cast rate -> small per-cast add")
		assert.is_true(math.abs(reflash(1.26) - 0.26455) < 1e-4, "in-game cast rate -> ~+0.26 equivalents/cast")
		assert.are.equal(1, reflash(0.1), "very slow cast -> full +2 hits x 0.5 = +1.0 equivalent (capped)")
	end)

	it("dpsMultiplier composition: base(full) + FlameCaller(0.5) + Reflash = one (1 + sum) factor", function()
		-- 1 (base, full) + 0.5 (Flame Caller return @50%) + 0.09 (Reflash @3.696) = x1.59 (verified 4guanghuan)
		local fc, rf = 0.5, math.min(1, 1 / (3 * 3.696))
		assert.is_true(math.abs((1 + fc + rf) - 1.59019) < 1e-4, "combined return-wave multiplier at LEB cast rate")
	end)
end)
