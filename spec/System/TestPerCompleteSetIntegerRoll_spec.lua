-- @leb-regression-guard:per-set-integer-source-not-halfstep
-- See REGRESSION_GUARDS.md "per-set-integer-source-not-halfstep".
-- Validation provenance is retained in maintainer notes.

describe("PerCompleteSetIntegerRoll", function()
	local PERSET = "{rounding:Integer}+(2-5) to All Attributes per Complete Set"

	-- applyRange byte -> rendered integer (verified against the in-game floor path,
	-- the same path validated on Phantom Grip "+(1-2) to All Minion Skills").
	local cases = {
		{ 0,   "+2" },   -- min
		{ 41,  "+2" },   -- BxvJP3g1 establishing roll (was half-step 2.5)
		{ 128, "+4" },
		{ 203, "+5" },   -- Qqwv73q2 establishing roll (was half-step 4.5)
		{ 205, "+5" },   -- Aurora_blank in-game roll
		{ 255, "+5" },   -- max -- must NOT overshoot to 6
	}

	for _, c in ipairs(cases) do
		local byte, want = c[1], c[2]
		it(string.format("byte=%d rolls an integer per-source (%s), never a half-step", byte, want), function()
			local out = itemLib.applyRange(PERSET, byte, 1.0, "Integer")
			assert.are.equals("{rounding:Integer}" .. want .. " to All Attributes per Complete Set", out)
			assert.is_nil(out:find("%.5 "), "per-source value must never be a half-step (x.5): " .. out)
		end)
	end

	it("the plain (1-2) attribute affix on the same item is unaffected (normal floor path)", function()
		-- Legends Entwined also carries "{rounding:Integer}+(1-2) to All Attributes"
		-- at byte 218 -> +2 (matches the loaded save's stored value).
		assert.are.equals("{rounding:Integer}+1 to All Attributes",
			itemLib.applyRange("{rounding:Integer}+(1-2) to All Attributes", 90, 1.0, "Integer"))
		assert.are.equals("{rounding:Integer}+2 to All Attributes",
			itemLib.applyRange("{rounding:Integer}+(1-2) to All Attributes", 218, 1.0, "Integer"))
	end)

	it("parses '+5 to All Attributes per Complete Set' to BASE attribute mods with the CompleteSetCount multiplier (roundAfterMultiply)", function()
		local list = modLib.parseMod("+5 to All Attributes per Complete Set")
		assert.is_not_nil(list, "must parse")
		local strMod
		for _, m in ipairs(list) do
			if m.name == "Str" and m.type == "BASE" then strMod = m end
		end
		assert.is_not_nil(strMod, "must emit a Str BASE mod")
		assert.are.equals(5, strMod.value)
		local mult
		for _, t in ipairs(strMod) do
			if t.type == "Multiplier" and t.var == "CompleteSetCount" then mult = t end
		end
		assert.is_not_nil(mult, "must carry Multiplier:CompleteSetCount")
		assert.is_true(mult.roundAfterMultiply == true, "the CompleteSetCount tag must roundAfterMultiply")
	end)

	-- End-to-end: integer per-source × CompleteSetCount, floored after multiply.
	-- This is the exact Aurora_blank scenario (5 per-source, CompleteSetCount=2):
	-- the grounded engine value is 10. The pre-fix half-step model produced 9.
	local function attrAt(perSourceText, setCount)
		local list = modLib.parseMod(perSourceText)
		local modDB = new("ModDB")
		for _, m in ipairs(list) do modDB:AddMod(m) end
		modDB.multipliers.CompleteSetCount = setCount
		return modDB:Sum("BASE", nil, "Str")
	end

	it("Aurora_blank: +5 per Complete Set × CompleteSetCount 2 = 10 (was 9 under the half-step model)", function()
		assert.are.equals(10, attrAt("+5 to All Attributes per Complete Set", 2))
	end)

	it("Qqwv73q2 roll (+5) × CompleteSetCount 6 = 30 (the grounded value; LETools showed 27)", function()
		assert.are.equals(30, attrAt("+5 to All Attributes per Complete Set", 6))
	end)

	it("BxvJP3g1 roll (+2) × CompleteSetCount 3 = 6 (the grounded value; LETools showed 7)", function()
		assert.are.equals(6, attrAt("+2 to All Attributes per Complete Set", 3))
	end)

	it("CompleteSetCount 0 (no complete set) contributes nothing", function()
		assert.are.equals(0, attrAt("+5 to All Attributes per Complete Set", 0))
	end)

	it("regression sentinel: ItemTools must NOT re-introduce a per-set half-step precision bump", function()
		local f = io.open("Modules/ItemTools.lua", "r")
		assert.is_not_nil(f, "must read Modules/ItemTools.lua")
		local src = f:read("*a"); f:close()
		assert.is_nil(src:match("per %[Cc%]omplete %[Ss%]et\".-precision = 2"),
			"the half-step 'precision = 2' bump for per-Complete-Set Integer affixes must stay removed")
	end)
end)
