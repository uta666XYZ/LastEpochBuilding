-- @leb-regression-guard:config-highlight-autoshow
-- Orange/highlighted (build-relevant) config options must be visible even when
-- "Show All Configurations" is OFF, so the user no longer has to toggle Show All
-- to find every highlighted option (user-requested 2026-06-09).
--
-- Mechanism: a local isHighlighted(varData) in the control-build loop mirrors the
-- three orange-label detections used by the labelControl.label closures --
--   suggestBuff    -> detectGrantedBuffs()[buffName]
--   suggestPattern -> detectMatchingPattern(pattern)
--   suggestCond/suggestEnemyCond/suggestMult -> conditionsUsed / enemyConditionsUsed
--        / multipliersUsed count > 0
-- control.shown ORs `not highlighted` into its gate alongside isShowAllConfig, so
-- ONLY highlighted configs bypass their ifCond/ifMult/... predicate; non-
-- highlighted gated configs stay hidden until Show All. Display-only (the change
-- is purely UI visibility -- no calc / DPS / EHP impact).
--
-- This is a source-contract spec (mirrors the sibling config-visibility specs,
-- which grep ConfigTab.lua rather than rendering controls). See
-- REGRESSION_GUARDS.md "config-highlight-autoshow".

describe("ConfigHighlightAutoShow", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	local src
	setup(function()
		src = readFile("Classes/ConfigTab.lua")
		assert.is_not_nil(src, "must read Classes/ConfigTab.lua")
	end)

	it("carries the autoshow guard marker", function()
		assert.is_truthy(src:find("@leb%-regression%-guard:config%-highlight%-autoshow", 1, false),
			"ConfigTab.lua must carry the config-highlight-autoshow guard marker")
	end)

	it("defines isHighlighted(varData) mirroring all three orange detections", function()
		assert.is_truthy(src:find("local function isHighlighted(varData)", 1, true),
			"must define isHighlighted(varData)")
		-- suggestBuff path
		assert.is_truthy(src:find("varData.suggestBuff and detectGrantedBuffs()", 1, true),
			"isHighlighted must check suggestBuff via detectGrantedBuffs")
		-- suggestPattern path
		assert.is_truthy(src:find("varData.suggestPattern and detectMatchingPattern(", 1, true),
			"isHighlighted must check suggestPattern via detectMatchingPattern")
		-- modDB-signal path: all three usage tables
		assert.is_truthy(src:find("conditionsUsed", 1, true), "must tally conditionsUsed")
		assert.is_truthy(src:find("enemyConditionsUsed", 1, true), "must tally enemyConditionsUsed")
		assert.is_truthy(src:find("multipliersUsed", 1, true), "must tally multipliersUsed")
		assert.is_truthy(src:find("varData.suggestCond", 1, true), "must read suggestCond")
		assert.is_truthy(src:find("varData.suggestEnemyCond", 1, true), "must read suggestEnemyCond")
		assert.is_truthy(src:find("varData.suggestMult", 1, true), "must read suggestMult")
	end)

	it("control.shown ORs `not highlighted` into the gate alongside isShowAllConfig", function()
		assert.is_truthy(src:find("local highlighted = isHighlighted(varData)", 1, true),
			"control.shown must compute highlighted = isHighlighted(varData)")
		assert.is_truthy(
			src:find("not shownFunc() and not isShowAllConfig(varData) and not highlighted", 1, true),
			"the gate must bypass when highlighted (alongside isShowAllConfig)")
	end)

	it("isHighlighted is defined before control.shown uses it", function()
		local defAt = src:find("local function isHighlighted(varData)", 1, true)
		local useAt = src:find("local highlighted = isHighlighted(varData)", 1, true)
		assert.is_not_nil(defAt); assert.is_not_nil(useAt)
		assert.is_true(defAt < useAt, "isHighlighted must be defined before control.shown references it")
	end)

	it("detectGrantedBuffs / detectMatchingPattern exist (the detections isHighlighted reuses)", function()
		assert.is_truthy(src:find("local function detectGrantedBuffs()", 1, true),
			"detectGrantedBuffs must exist")
		assert.is_truthy(src:find("local function detectMatchingPattern(", 1, true),
			"detectMatchingPattern must exist")
	end)
end)
