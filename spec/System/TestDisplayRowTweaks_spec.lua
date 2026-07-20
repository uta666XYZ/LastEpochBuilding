-- User-requested display tweaks (2026-06-09):
--   @leb-regression-guard:combined-dps-row-label
--     The per-skill total (Hit DPS + main-skill ailments, output.MainSkillWithAilmentsDPS)
--     is labelled "Combined DPS" (PoB parity), replacing "Total DPS inc. Ailments". The
--     legacy PoE output.CombinedDPS row is suppressed whenever this row shows, so there is
--     never a duplicate "Combined DPS" label.
--   @leb-regression-guard:endurance-threshold-neutral-color
--     The Endurance Threshold defensive row renders in default white (no colorCodes.LIFE
--     red tint), matching the sibling defensive rows.
-- Source-contract spec (mirrors the sibling display-stat specs).
-- See REGRESSION_GUARDS.md "combined-dps-row-label" / "endurance-threshold-neutral-color".

describe("DisplayRowTweaks", function()
	local function readFile(path)
		local f = io.open(path, "r"); if not f then return nil end
		local s = f:read("*a"); f:close(); return s
	end
	local buildSrc
	setup(function()
		buildSrc = readFile("Modules/Build.lua")
		assert.is_not_nil(buildSrc, "must read Modules/Build.lua")
	end)

	describe("combined-dps-row-label", function()
		it("carries the guard marker", function()
			assert.is_truthy(buildSrc:find("@leb%-regression%-guard:combined%-dps%-row%-label"))
		end)
		it("labels MainSkillWithAilmentsDPS as 'Combined DPS'", function()
			assert.is_truthy(buildSrc:find('stat = "MainSkillWithAilmentsDPS", label = "Combined DPS"', 1, true),
				"the per-skill total row must be labelled 'Combined DPS'")
		end)
		it("no longer uses the old 'Total DPS inc. Ailments' label", function()
			assert.is_falsy(buildSrc:find('label = "Total DPS inc. Ailments"', 1, true),
				"the old 'Total DPS inc. Ailments' label must be gone")
		end)
		it("suppresses the legacy CombinedDPS row to avoid a duplicate label", function()
			-- the legacy output.CombinedDPS row's condFunc must hide when MainSkillWithAilmentsDPS shows
			assert.is_truthy(
				buildSrc:find("not ((o.MainSkillWithAilmentsDPS or 0) > 0 and o.MainSkillWithAilmentsDPS ~= o.TotalDPS)", 1, true),
				"legacy CombinedDPS row must be suppressed when the Combined DPS row is shown")
		end)
	end)

	describe("endurance-threshold-neutral-color", function()
		it("carries the guard marker", function()
			assert.is_truthy(buildSrc:find("@leb%-regression%-guard:endurance%-threshold%-neutral%-color"))
		end)
		it("the EnduranceThreshold row has no colorCodes.LIFE tint", function()
			local rowAt = buildSrc:find('stat = "EnduranceThreshold"', 1, true)
			assert.is_not_nil(rowAt, "EnduranceThreshold row must exist")
			local rowEnd = buildSrc:find("\n", rowAt)
			local row = buildSrc:sub(rowAt, rowEnd or #buildSrc)
			assert.is_falsy(row:find("color = colorCodes.LIFE", 1, true),
				"EnduranceThreshold row must not use colorCodes.LIFE (renders default white)")
			assert.is_falsy(row:find("color =", 1, true),
				"EnduranceThreshold row must not set any color (default white)")
		end)
	end)

	-- User-requested sidebar tweaks (2026-06-10):
	--   @leb-regression-guard:sidebar-defence-display-tweaks
	--   (a) "Increased Healing Effectiveness" wrapped to two lines in the sidebar; the row
	--       is SHORTENED to "Healing Effectiveness" (kept, not hidden, for in-game
	--       character-sheet parity; the row is v>0-gated).
	--   (b) a blank-row group separator splits the Armor block (Armor / Armor Mitigation)
	--       from the Endurance block (Endurance / Endurance Threshold), matching the
	--       Dodge <-> Armor spacing.
	describe("sidebar-defence-display-tweaks", function()
		it("carries the guard marker", function()
			assert.is_truthy(buildSrc:find("@leb%-regression%-guard:sidebar%-defence%-display%-tweaks"))
		end)
		it("the HealingEffectiveness row uses the short 'Healing Effectiveness' label", function()
			assert.is_truthy(
				buildSrc:find('stat = "HealingEffectiveness", label = "Healing Effectiveness"', 1, true),
				"the row must be labelled 'Healing Effectiveness'")
			assert.is_falsy(buildSrc:find('label = "Increased Healing Effectiveness"', 1, true),
				"the long wrapping label must be gone")
		end)
		it("a group separator splits Armor Mitigation from the Endurance block", function()
			local mitAt = buildSrc:find('label = "Armor Mitigation"', 1, true)
			local endAt = buildSrc:find('stat = "Endurance", label = "Endurance"', 1, true)
			assert.is_not_nil(mitAt); assert.is_not_nil(endAt)
			assert.is_true(mitAt < endAt, "Armor Mitigation must precede Endurance")
			assert.is_truthy(buildSrc:sub(mitAt, endAt):find("{ },", 1, true),
				"a blank-row separator '{ },' must sit between Armor Mitigation and Endurance")
		end)
	end)
end)
