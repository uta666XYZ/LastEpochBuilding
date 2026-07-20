-- @leb-regression-guard:adaptive-added-base-derived-types-only
-- See REGRESSION_GUARDS.md "adaptive-added-base-derived-types-only".
-- Validation provenance is retained in maintainer notes.

describe("AdaptiveAddedBaseDerivedTypesOnly", function()
	before_each(function() newBuild() end)

	-- Select a skill, inject config (non-weapon) BASE mods, recompute, return output.
	-- A mod is { name, value } or { name, value, tag } (tag => skill-scoped).
	local function calcWith(skill, mods)
		newBuild()
		build.skillsTab:SelSkill(1, skill)
		runCallback("OnFrame")
		local cfg = build.configTab.modList
		for _, m in ipairs(mods or {}) do
			if m[3] then
				cfg:NewMod(m[1], "BASE", m[2], "AdaptiveBaseDerivedSpec", 0, 0, m[3])
			else
				cfg:NewMod(m[1], "BASE", m[2], "AdaptiveBaseDerivedSpec")
			end
		end
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end
	local fireballScoped = { type = "SkillName", skillName = "Fireball" }
	local function hit(out, t) return out[t .. "HitAverage"] or 0 end

	it("SKILL-SCOPED conversion: an OFF-base independently-added lane gets NO adaptive share", function()
		-- Fireball (intrinsic Fire) with a SKILL-SCOPED 100% Fire->Cold conversion + a typed
		-- off-base +Lightning added. Base-derived types = {Fire, Cold}; Lightning is off-base.
		local preserved = calcWith("Fireball", { { "FireDamageConvertToCold", 100, fireballScoped }, { "LightningDamage", 40 } })
		local out = calcWith("Fireball", { { "FireDamageConvertToCold", 100, fireballScoped }, { "LightningDamage", 40 }, { "Damage", 40 } })
		-- The off-base Lightning lane must NOT gain from the typeless pool (this is the fix).
		assert.is_true(math.abs(hit(out, "Lightning") - hit(preserved, "Lightning")) < 0.5,
			"off-base Lightning lane must receive NO share of the typeless adaptive")
		-- The base-derived Cold lane (the conversion destination) DOES receive the pool.
		assert.is_true(hit(out, "Cold") > hit(preserved, "Cold") + 0.5,
			"the base-derived Cold lane must receive the typeless adaptive")
	end)

	it("GLOBAL conversion is EXEMPT: the off-base lane keeps its full-post-conv-base share", function()
		-- Same shape but the Fire->Cold is UNTAGGED = player-global. The base-derived gate is
		-- skipped, so the off-base Lightning lane still gets its proportional share (locks
		-- adaptive-added-distributes-over-full-postconv-base for the global path).
		local preserved = calcWith("Fireball", { { "FireDamageConvertToCold", 100 }, { "LightningDamage", 40 } })
		local out = calcWith("Fireball", { { "FireDamageConvertToCold", 100 }, { "LightningDamage", 40 }, { "Damage", 40 } })
		assert.is_true(hit(out, "Lightning") > hit(preserved, "Lightning") + 0.5,
			"global-conversion exemption: off-base Lightning still shares the typeless adaptive")
	end)

	it("no off-base lane: single base type + conversion is byte-identical (share all lands base-side)", function()
		-- Fireball intrinsic Fire, skill-scoped 100% Fire->Cold, NO off-base added: the pool
		-- goes entirely onto Cold whether or not the gate is applied (no lane is excluded).
		local out = calcWith("Fireball", { { "FireDamageConvertToCold", 100, fireballScoped }, { "Damage", 40 } })
		assert.are.equals(0, hit(out, "Fire"), "Fire fully converted out")
		assert.is_true(hit(out, "Cold") > 0, "the typeless adaptive lands on the converted Cold base")
		assert.are.equals(0, hit(out, "Lightning"), "no Lightning was added")
	end)

	it("source contract: the gate is scoped by applyBaseDerivedGate (skill-scoped only)", function()
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f, "must read CalcOffence.lua")
		local src = f:read("*a"); f:close()
		assert.is_truthy(src:find("applyBaseDerivedGate", 1, true),
			"the base-derived gate must be applied via applyBaseDerivedGate")
		assert.is_truthy(src:find("@leb-regression-guard:adaptive-added-base-derived-types-only", 1, true),
			"the inline guard tag must be present")
	end)
end)
