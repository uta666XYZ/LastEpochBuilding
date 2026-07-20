-- @leb-regression-guard:elemental-dot-flag-parse
-- LE affix "X% increased Elemental Damage Over Time" (Nameless_King carries
-- "(140-170)% increased Elemental Damage Over Time") is the ELEMENTAL AGGREGATE of
-- the per-type "<Type> Damage over Time" name-list entries generated in ModParser
-- (L636 loop). Before the fix, ModParser had NO "elemental damage over time" key,
-- so the string matched only the shorter ["elemental damage"] (non-DoT elemental
-- split, L429) and left residue "over time" -> the INC parsed with flags=0 and did
-- NOT carry ModFlag.Dot. Result: it scaled elemental HITS (or, on tree/affix mods
-- with residue, got dropped) instead of the fire/cold/lightning DoT. Empirically
-- this read Fire Aura's fire+cold DoT ticks ~33% low (light/void flat portions,
-- which are non-DoT constants, matched exact).
--
-- Fix (ModParser.lua, single additive entry after the per-type loop):
--   modNameList["elemental damage over time"] =
--       { "FireDamage", "ColdDamage", "LightningDamage", flags = ModFlag.Dot }
-- This mirrors the per-type "<type> damage over time" form exactly: it splits to
-- the three elemental damage names + ModFlag.Dot. Dot-only keeps HITS excluded
-- (a hit cfg has no Dot flag), and each <Type>Damage name is only summed for a
-- skill that deals that type. Longest-match already prefers this key over the
-- shorter "elemental damage" (same mechanism by which "fire damage over time"
-- beats "fire damage"). See REGRESSION_GUARDS.md "elemental-dot-flag-parse".

describe("ElementalDamageOverTimeParse #skills", function()
	local function hasDot(mod)
		return (bit.band(mod.flags or 0, ModFlag.Dot) ~= 0)
	end

	local function byName(list, name)
		for _, m in ipairs(list) do
			if m.name == name then return m end
		end
		return nil
	end

	it("parse contract: 'X% increased Elemental Damage Over Time' -> Fire/Cold/Lightning INC + ModFlag.Dot, no residue", function()
		local list, extra = modLib.parseMod("150% increased Elemental Damage Over Time")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no 'Over Time' residue, got: " .. tostring(extra))
		assert.are.equal(3, #list, "must split to exactly the three elemental damage types")
		for _, dt in ipairs({ "FireDamage", "ColdDamage", "LightningDamage" }) do
			local mod = byName(list, dt)
			assert.is_not_nil(mod, "must emit " .. dt)
			assert.are.equal("INC", mod.type)
			assert.are.equal(150, mod.value)
			assert.is_true(hasDot(mod), dt .. " must carry ModFlag.Dot (scales DoT, not hits)")
		end
	end)

	it("Dot-only gating: the INC scales a fire DoT cfg but NOT a fire hit cfg", function()
		local list = modLib.parseMod("150% increased Elemental Damage Over Time")
		local modDB = new("ModDB")
		for _, mod in ipairs(list) do modDB:AddMod(mod) end
		-- DoT cfg -> full 150% increase
		assert.are.equal(150, modDB:Sum("INC", { flags = ModFlag.Dot }, "FireDamage"),
			"a DoT cfg must receive the +150% Elemental-DoT increase")
		-- Hit cfg (no Dot flag) -> nothing (the affix must NOT buff hits)
		assert.are.equal(0, modDB:Sum("INC", { flags = ModFlag.Hit }, "FireDamage"),
			"a HIT cfg must NOT receive the Elemental-DoT increase")
		-- Cold + Lightning DoT also covered; void/physical untouched (aggregate is elemental-only)
		assert.are.equal(150, modDB:Sum("INC", { flags = ModFlag.Dot }, "ColdDamage"))
		assert.are.equal(150, modDB:Sum("INC", { flags = ModFlag.Dot }, "LightningDamage"))
		assert.are.equal(0, modDB:Sum("INC", { flags = ModFlag.Dot }, "VoidDamage"),
			"void is not elemental -> must be untouched")
	end)

	it("longest-match: the shorter non-DoT 'Elemental Damage' still parses without a Dot flag", function()
		-- The new key must NOT shadow the plain elemental (hit) form.
		local list = modLib.parseMod("150% increased Elemental Damage")
		assert.is_not_nil(list)
		assert.are.equal(3, #list, "plain 'Elemental Damage' still splits to the three types")
		for _, m in ipairs(list) do
			assert.is_false(hasDot(m), m.name .. " from plain 'Elemental Damage' must NOT carry ModFlag.Dot")
		end
	end)

	it("generic 'increased Damage Over Time' remains type-agnostic Dot (unchanged sibling)", function()
		-- Guards against accidentally narrowing the pre-existing generic entry.
		local list, extra = modLib.parseMod("150% increased Damage Over Time")
		assert.is_not_nil(list)
		assert.is_true(not extra or extra == "", "generic DoT must leave no residue")
		assert.are.equal(1, #list)
		assert.are.equal("Damage", list[1].name)
		assert.is_true(hasDot(list[1]), "generic DoT must carry ModFlag.Dot")
	end)
end)
