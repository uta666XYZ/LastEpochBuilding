-- @leb-regression-guard:generatebuilds-nested-table-serializer
-- spec/GenerateBuilds.lua's buildTable() must serialize NESTED tables (it silently
-- dropped every table-valued key: the old nested branch called
-- `buildTable(key, value, string)` and discarded the return, so mainOutput's
-- `Minion` (701 entries on a Beastmaster) / `SkillDPS` sub-tables vanished from the
-- snapshot, and the #63/#70 regen corrupted Druid snapshots). The fix must ALSO keep
-- the flat string-keyed output byte-identical (no corpus churn) and round-trip
-- numeric keys.  See REGRESSION_GUARDS.md "generatebuilds-nested-table-serializer".

-- Load the REAL buildTable out of GenerateBuilds.lua without running its regen loop.
-- `local buildList` is the first statement after the serializer, so the function's
-- terminal `end` is the LAST `end` before it.
--
-- This used to anchor on the literal `end\n\nlocal buildList` adjacency, which meant
-- nothing could be written between them -- not even a `@leb-regression-guard` marker,
-- which is exactly where one belongs (it is the line the regen root is read on).
-- `regen-root-equals-test-root` hit that and errored this whole spec out. Extraction
-- machinery only: the invariants asserted below are unchanged.
local function loadRealBuildTable()
	local f = io.open("../spec/GenerateBuilds.lua", "r") or io.open("spec/GenerateBuilds.lua", "r")
	assert(f, "must read spec/GenerateBuilds.lua")
	local src = f:read("*a"); f:close()
	local head = src:match("^(.-)\nlocal buildList")
	assert(head, "must locate `local buildList` in spec/GenerateBuilds.lua (the anchor "
		.. "that terminates the buildTable function)")
	local fnSrc = head:match("(function buildTable%(.*\nend)")
	assert(fnSrc, "must locate the buildTable function before `local buildList`")
	local chunk = assert(load(fnSrc .. "\nreturn buildTable"))
	return chunk(), src
end

-- Parse a `name = {...}` chunk produced by buildTable back into a Lua value.
local function loadBack(serialized)
	local body = serialized:gsub("^[%w_]* = ", "")        -- strip "name = "
	local chunk = assert(load("return " .. body))
	return chunk()
end

local function deepEq(a, b, path)
	path = path or "root"
	if type(a) ~= type(b) then return false, path .. ": type " .. type(a) .. " vs " .. type(b) end
	if type(a) ~= "table" then
		if type(a) == "number" then
			if math.abs(a - b) > 1e-4 then return false, path .. ": " .. a .. " vs " .. b end
			return true
		end
		if a ~= b then return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b) end
		return true
	end
	for k, v in pairs(a) do
		local ok, why = deepEq(v, b[k], path .. "." .. tostring(k))
		if not ok then return false, why end
	end
	for k in pairs(b) do
		if a[k] == nil then return false, path .. "." .. tostring(k) .. ": missing in A" end
	end
	return true
end

describe("GenerateBuildsNestedSerializer", function()
	local buildTable, src
	setup(function() buildTable, src = loadRealBuildTable() end)

	it("source contract: nested branch captures the recursion (not the discarded-return bug)", function()
		assert.is_truthy(src:find("local nested = buildTable(", 1, true),
			"nested table branch must CAPTURE buildTable's return")
		assert.is_falsy(src:find("        if type(value) == \"table\" then\n            buildTable(key, value, string)", 1, true),
			"the discarded-return nested call must be gone")
		assert.is_truthy(src:find("@leb-regression-guard:generatebuilds-nested-table-serializer", 1, true),
			"guard marker must be present")
	end)

	it("flat string-keyed table stays byte-identical to the legacy format (no corpus churn)", function()
		local out = buildTable("output", { Zebra = 1.5, Apple = 2.25, Flag = true, Name = "x" })
		assert.are.equals(
			'output = {["Apple"] = 2.25,\n["Flag"] = true,\n["Name"] = "x",\n["Zebra"] = 1.5,\n}\n',
			out)
	end)

	it("nested tables round-trip (Minion/SkillDPS-style sub-tables are no longer dropped)", function()
		local t = {
			TotalDPS = 12345.6789,
			SkillDPS = { 111.5, 222.25 },                 -- numeric keys
			Minion = { ColdDamageBase = 50.1234, sub = { x = 1, y = 2 } },
		}
		local back = loadBack(buildTable("output", t))
		local ok, why = deepEq(t, back)
		assert.is_true(ok, "round-trip mismatch: " .. tostring(why))
		assert.is_table(back.Minion, "Minion sub-table must survive serialization")
		assert.is_table(back.Minion.sub, "deeply-nested table must survive")
		assert.are.equals(2, back.Minion.sub.y)
	end)

	it("the serialized output is valid loadable Lua even with nested tables", function()
		local s = buildTable("output", { a = 1, b = { c = { d = { e = 5 } } } })
		assert.has_no.errors(function() loadBack(s) end)
	end)
end)
