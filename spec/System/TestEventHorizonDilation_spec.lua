-- @leb-regression-guard:event-horizon-config-stacks
-- Event Horizon (Unique 2H Mace / Vault Crusher, Lv80). "When you use a Melee
-- Attack and hit at least one enemy you gain a stack of Dilation (up to 10).
-- Dilation has no time limit and no effects beyond those described. 15% more
-- Melee Damage per stack (multiplicative), 5% less attack/cast speed per stack,
-- 5% less move speed per stack. All stacks lost on Evade."
--
-- Grounding (verbatim):
--   * gear tooltip: 未モデル affix gear grounding (2026-07-12 capture) B5.
--   * datamine buff (ailments_v3.json "Dilation", buffID null, no magnitude
--     array): direction-confirms the per-stack melee more + speed penalties.
--   * the ONLY parseable Dilation mod on the item is the grant line
--     (ModCache.lua ~10793) which is an EMPTY modlist {{}, ...} = no-op; the
--     per-stack magnitude lives in the tooltip (flavor text, unparsed). So the
--     per-stack effect is otherwise completely unmodeled.
--
-- Model shape (config-gated, direct-apply -- the Void Essence / Reen's Ire
-- pattern at ConfigOptions.lua):
--   * config `multiplierDilationStacks` (type "count"), default blank/0.
--   * apply(): per stack N -> Damage MORE (N*15) melee-scoped (ModFlag.Melee,
--     matches the "N% more Melee Damage" form).
--   * capped at 10 stacks. Default 0 -> strict no-op = corpus-neutral (Event
--     Horizon builds stay byte-identical until the user sets the stack count).
--   * NOTE: the per-stack -5% attack/cast speed and -5% move speed downsides are
--     part of the same buff but are intentionally NOT modeled -- this config
--     scopes the offensive per-stack MORE only.
-- ModParser / ModCache are NOT touched -- the mechanic is config-driven.
-- See REGRESSION_GUARDS.md "event-horizon-config-stacks".

describe("EventHorizonDilation #config", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	it("config source: direct-apply count capped 10, melee-scoped MORE Damage of val*15", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierDilationStacks".-end },')
		assert.is_not_nil(entry, "multiplierDilationStacks config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		assert.is_truthy(entry:find("max 10", 1, true),
			"label must carry the '(max 10)' cap hint")
		assert.is_truthy(entry:find("math.min(val, 10)", 1, true),
			"apply must cap the stack count at 10")
		assert.is_truthy(entry:find('NewMod("Damage", "MORE", val * 15, "Dilation", ModFlag.Melee)', 1, true),
			"apply must emit a melee-scoped MORE Damage of val*15")
	end)

	it("behaviour: config 0 default no-op; N stacks add N*15 melee MORE; capped 10", function()
		newBuild()
		local meleeCfg = { flags = ModFlag.Melee }
		local function meleeMore()
			return build.calcsTab.mainEnv.player.modDB:More(meleeCfg, "Damage")
		end

		-- 0 stacks (default) -> no Dilation contribution
		build.configTab.input["multiplierDilationStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local more0 = meleeMore()

		-- 5 stacks -> +75% more melee => x1.75 relative to base
		build.configTab.input["multiplierDilationStacks"] = 5
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(more0 * 1.75, meleeMore())

		-- 10 stacks (cap) -> +150% more melee => x2.5 relative to base
		build.configTab.input["multiplierDilationStacks"] = 10
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(more0 * 2.5, meleeMore())

		-- 20 stacks -> still capped at 10 (x2.5)
		build.configTab.input["multiplierDilationStacks"] = 20
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(more0 * 2.5, meleeMore())
	end)

	it("scoping: the Dilation MORE is MELEE-only (does not leak into spell/DoT damage)", function()
		newBuild()
		local player = build.calcsTab.mainEnv.player
		local spellCfg = { flags = ModFlag.Spell }
		local dotCfg = { flags = ModFlag.Dot }
		local function spellMore() return player.modDB:More(spellCfg, "Damage") end
		local function dotMore() return player.modDB:More(dotCfg, "Damage") end

		build.configTab.input["multiplierDilationStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local spell0, dot0 = spellMore(), dotMore()

		build.configTab.input["multiplierDilationStacks"] = 10
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(spell0, spellMore(),
			"melee-scoped Dilation MORE must not leak into spell damage")
		assert.are.equal(dot0, dotMore(),
			"melee-scoped Dilation MORE must not leak into DoT damage")
	end)

	it("grant mod stays a no-op (per-stack effect is config-driven, not from the item mod)", function()
		local mc = readFile("Data/ModCache.lua")
		assert.is_not_nil(mc, "must read Data/ModCache.lua")
		-- the parseable grant line must remain an empty modlist {{}, ...}
		assert.is_truthy(mc:find('gain Dilation when you use a Melee Attack', 1, true),
			"the Dilation grant line must still be present in ModCache")
		assert.is_truthy(mc:find('when you use a Melee Attack and hit at least one enemy"]={{},', 1, true),
			"the grant line must stay an empty-modlist no-op (per-stack effect lives in the config, not the item mod)")
	end)
end)
