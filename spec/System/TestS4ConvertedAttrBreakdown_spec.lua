-- @leb-regression-guard:s4-converted-attr-source-breakdown
-- @leb-regression-guard:s4-converted-attr-table-from-source
-- Locks that a Season-4 converted attribute (Brutality/Guile/Madness/Apathy/
-- Rampancy) shows WHERE its value comes from, in the SAME per-source TABLE format
-- (Value / Notes / Source / Source Name) every other attribute uses — with item
-- names, passive-node DISPLAY names and equipment slots resolved, NOT raw internal
-- node ids and NOT a collapsed "100% of Str converted" text line.
--
-- Mechanism (two parts):
--  1. CalcSections points the converted attribute's mod-section at the SOURCE
--     attribute's modName (`{ modName = <base attr> }`, e.g. Str for Brutality),
--     so AddModSection tabulates and resolves the source attribute's mods. The
--     converted attribute has (almost) no mods under its OWN name, so without this
--     its table would be empty — guard `s4-converted-attr-table-from-source`.
--  2. CalcPerform builds a short textual summary (converted-from + direct grants +
--     total) shown above that table, mirroring breakdown.simple on a normal
--     attribute — guard `s4-converted-attr-source-breakdown`.
--
-- Both are UI/breakdown-only (nothing written to output) so corpus-neutral.
--
-- See REGRESSION_GUARDS.md "s4-converted-attr-source-breakdown" and
-- "s4-converted-attr-table-from-source".

describe("S4ConvertedAttrSourceBreakdown", function()
	before_each(function()
		newBuild()
	end)

	-- Locate a converted-attribute row in the CalcSections module by its dst stat.
	local function findConvRow(dst)
		local sections = LoadModule("Modules/CalcSections")
		local found
		local function scan(t, depth)
			if type(t) ~= "table" or depth > 8 or found then return end
			if type(t.label) == "string" and t.label:find(dst, 1, true) and t.haveOutput == dst then
				found = t
				return
			end
			for _, v in pairs(t) do scan(v, depth + 1) end
		end
		scan(sections, 0)
		return found
	end

	-- The modName the row's mod-section (the per-source TABLE) tabulates.
	local function rowModSectionName(row)
		for _, sd in ipairs(row and row[1] or {}) do
			if sd.modName then return sd.modName end
		end
	end

	-- Inject { name, value, source } BASE mods into the config modList (preserved
	-- into the player modDB), recompute, return the recomputed player env.
	local function calcWith(mods)
		local cfg = build.configTab.modList
		for _, m in ipairs(mods) do
			cfg:NewMod(m.name, "BASE", m.value, m.source)
		end
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.calcsEnv.player
	end

	it("wires each converted attribute's per-source TABLE to its SOURCE attribute", function()
		local cases = {
			{ dst = "Brutality", src = "Str" },
			{ dst = "Guile",     src = "Dex" },
			{ dst = "Madness",   src = "Int" },
			{ dst = "Apathy",    src = "Att" },
			{ dst = "Rampancy",  src = "Vit" },
		}
		for _, c in ipairs(cases) do
			local row = findConvRow(c.dst)
			assert.is_table(row, c.dst .. " must have an attribute row in CalcSections")
			assert.are.equal(c.src, rowModSectionName(row),
				c.dst .. " per-source TABLE must tabulate its SOURCE attribute '" .. c.src ..
				"' (so it shows the same per-source list as every other attribute), not its own empty mod set")
		end
	end)

	it("renders the converted TABLE with resolved per-source rows (node display name, never the raw id)", function()
		-- Sentinel-31 is a real passive node whose display name (dn) is "Might".
		calcWith({
			{ name = "Str", value = 10, source = "Tree:Sentinel-31" },
			{ name = "StrengthConvertedToBrutality", value = 100, source = "Spec" },
		})
		local row = findConvRow("Brutality")
		local ctrl = build.calcsTab.controls.breakdown
		-- Drive the breakdown control with the REAL row data (wiring + render).
		ctrl:SetBreakdownData(row[1], true)

		local tableSec
		for _, sec in ipairs(ctrl.sectionList) do
			if sec.type == "TABLE" then tableSec = sec break end
		end
		assert.is_table(tableSec, "converted attribute must render a per-source TABLE section")

		local sawMight, sawRawId = false, false
		for _, r in ipairs(tableSec.rowList) do
			if r.sourceName == "Might" and r.source == "Passive Tree" then sawMight = true end
			if type(r.sourceName) == "string" and r.sourceName:find("Sentinel-31", 1, true) then sawRawId = true end
		end
		assert.is_true(sawMight,
			"the TABLE must resolve Tree:Sentinel-31 to the node DISPLAY name 'Might' under source 'Passive Tree'")
		assert.is_false(sawRawId,
			"the TABLE must never show the raw internal node id 'Sentinel-31'")
	end)

	it("shows a concise conversion summary above the table", function()
		local player = calcWith({
			{ name = "Str", value = 20, source = "Item:99:Suloron's Step" },
			{ name = "StrengthConvertedToBrutality", value = 100, source = "Spec" },
		})
		local bd = player.breakdown.Brutality
		assert.is_table(bd, "Brutality must have a breakdown summary")
		local text = table.concat(bd, "\n")
		assert.is_truthy(text:find("converted from Str", 1, true),
			"summary must state the value is converted from Str:\n" .. text)
	end)

	it("adds direct destination grants and a total when both contribute", function()
		local player = calcWith({
			{ name = "Str", value = 20, source = "Item:99:Suloron's Step" },
			{ name = "Brutality", value = 7, source = "Item:88:Some Brutality Item" },
			{ name = "StrengthConvertedToBrutality", value = 100, source = "Spec" },
		})
		local bd = player.breakdown.Brutality
		local text = table.concat(bd, "\n")
		assert.is_truthy(text:find("direct grants of Brutality", 1, true),
			"direct Brutality grants must be shown in the summary:\n" .. text)
		local total = tonumber(bd[#bd]:match("^= (%-?%d+%.?%d*)$"))
		assert.are.equal(player.output.Brutality, total,
			"summary total must equal output.Brutality")
	end)
end)
