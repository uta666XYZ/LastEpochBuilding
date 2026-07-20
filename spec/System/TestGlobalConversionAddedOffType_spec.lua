-- @leb-regression-guard:global-conversion-converts-added-offtype
-- (@leb-regression-guard:conversion-base-only-scope, locked in
-- run before the typeless/adaptive distribution. See REGRESSION_GUARDS.md.
-- Validation provenance is retained in maintainer notes.

describe("GlobalConversionAddedOffType", function()
	before_each(function()
		newBuild()
	end)

	-- A mod is { name, value } (untagged = player-global) or { name, value, tag }
	-- (tag = skill-scoped, base-only). Mirrors TestAdaptiveAddedPostConversionTyping.
	local function calcWith(skill, mods)
		newBuild()
		build.skillsTab:SelSkill(1, skill)
		runCallback("OnFrame")
		local cfg = build.configTab.modList
		for _, m in ipairs(mods or {}) do
			if m[3] then
				cfg:NewMod(m[1], "BASE", m[2], "GlobalConvSpec", 0, 0, m[3])
			else
				cfg:NewMod(m[1], "BASE", m[2], "GlobalConvSpec")
			end
		end
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end
	local function hit(out, t) return out[t .. "HitAverage"] or 0 end
	local function approx(a, b, tol) return math.abs(a - b) <= (tol or 0.5) end
	local fireballScoped = { type = "SkillName", skillName = "Fireball" }

	it("player-global (untagged) conversion CONVERTS typed added of the source type", function()
		-- Fireball sources Fire. A typed +Fire added flat normally keeps its type; under a
		-- player-global Fire->Void it must be converted to Void (no fire residue) -- the
		-- YsSmiteVK Symbols-of-Hope added-fire case.
		local typedOnly = calcWith("Fireball", { { "FireDamage", 40 } })
		assert.is_true(hit(typedOnly, "Fire") > 0, "sanity: typed Fire added shows as Fire with no conversion")
		assert.are.equals(0, hit(typedOnly, "Void"), "sanity: no Void without a conversion")

		local out = calcWith("Fireball", { { "FireDamageConvertToVoid", 100 }, { "FireDamage", 40 } })
		assert.are.equals(0, hit(out, "Fire"),
			"a player-global Fire->Void must convert the typed added fire (no fire residue)")
		assert.is_true(hit(out, "Void") > 0,
			"the converted added fire must land on Void")
	end)

	it("SKILL-SCOPED (tagged) conversion LEAVES typed added (base-only) -- the discriminator", function()
		-- The SAME conversion %, but skill-scoped, converts ONLY the intrinsic base: the
		-- typed added must keep its type, so it does NOT add to Void. (The intrinsic Fireball
		-- base still converts to Void, so Void is non-zero either way -- we compare deltas.)
		local baseNoAdd = calcWith("Fireball", { { "FireDamageConvertToVoid", 100, fireballScoped } })
		local out = calcWith("Fireball", { { "FireDamageConvertToVoid", 100, fireballScoped }, { "FireDamage", 40 } })
		assert.is_true(hit(out, "Fire") > 0,
			"a skill-scoped Fire->Void converts only the intrinsic base; typed added keeps its type")
		assert.is_true(approx(hit(out, "Void"), hit(baseNoAdd, "Void"), 0.5),
			"the typed added must NOT increase Void under a skill-scoped (base-only) conversion")
	end)

	it("global conversion converts OFF-TYPE typed added (a type the skill does not source)", function()
		-- Fireball sources Fire only. A typed +Physical added is OFF-TYPE; a player-global
		-- Physical->Fire must convert it to Fire (it cannot ride any intrinsic phys base --
		-- there is none -- so this proves the added path, not a base path).
		local noConv = calcWith("Fireball", { { "PhysicalDamage", 40 } })
		assert.is_true(hit(noConv, "Physical") > 0, "sanity: off-type physical added shows as Physical")

		local out = calcWith("Fireball", { { "PhysicalDamageConvertToFire", 100 }, { "PhysicalDamage", 40 } })
		assert.are.equals(0, hit(out, "Physical"),
			"the off-type physical added must be fully converted out")
		assert.is_true(hit(out, "Fire") > hit(noConv, "Fire"),
			"the converted off-type added must land on Fire")
	end)

	it("partial global conversion SPLITS the typed added proportionally", function()
		-- 50% global Fire->Void on a typed +Fire added: half stays Fire, half -> Void.
		local out = calcWith("Fireball", { { "FireDamageConvertToVoid", 50 }, { "FireDamage", 40 } })
		assert.is_true(hit(out, "Fire") > 0 and hit(out, "Void") > 0,
			"both the retained Fire and the converted Void lane must carry the added")
	end)

	it("no global conversion => typed added is UNCHANGED (no over-conversion)", function()
		-- A build with no conversion at all must be byte-identical: the typed added stays.
		local base = calcWith("Fireball", {})
		local out = calcWith("Fireball", { { "FireDamage", 40 } })
		assert.is_true(hit(out, "Fire") > hit(base, "Fire"),
			"typed Fire added rides Fire when there is no conversion")
		assert.are.equals(0, hit(out, "Void"), "no conversion -> no Void")
		assert.are.equals(0, hit(out, "Cold"), "no conversion -> no other type")
	end)

	it("source contract: the global-only conversion table and consumer are present", function()
		local f = io.open("Modules/CalcOffence.lua", "r") or io.open("src/Modules/CalcOffence.lua", "r")
		assert.is_not_nil(f, "must read Modules/CalcOffence.lua")
		local src = f:read("*a"); f:close()
		assert.is_truthy(src:find("activeSkill.globalConversionTable", 1, true),
			"the global-only conversion table must exist")
		assert.is_truthy(src:find("@leb-regression-guard:global-conversion-converts-added-offtype", 1, true),
			"the guard marker must be present")
		-- the consumer reads the global-only table, gated to the player actor (minion
		-- summon-tree conversions are base-only but untagged, so they are excluded).
		assert.is_truthy(src:find("activeSkill.globalConversionTable or nil", 1, true),
			"the consumer must read the global-only table")
		assert.is_truthy(src:find("actor == env.player", 1, true),
			"the added-conversion must be gated to the player actor (minion base-only conversions excluded)")
	end)
end)
