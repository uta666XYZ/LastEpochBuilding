-- @leb-regression-guard:eye-of-reen-reens-ire
-- Eye of Reen (Unique 1H Katana, Lv70). "[75-100]% Chance to gain a stack of
-- Reen's Ire for 5s when you crit with a melee attack, up to 30 times per 5
-- seconds. Each stack grants 5% melee critical strike multiplier and 10%
-- increased fire damage over time."
--
-- Grounding (verbatim):
--   * gear tooltip: 未モデル affix gear grounding (2026-07-12 capture) B1.
--   * datamine unique mod (uniques_v3.json "Eye of Reen" tooltipDescription):
--       "Each stack of Reen's Ire grants 5% melee critical strike multiplier
--        and 10% increased fire damage over time"
--   * datamine buff (ailments_v3.json nonAilmentUIBuffs[140] "Reens Ire",
--       buffID null, no magnitude array): "Increases fire damage over time and
--        adds melee critical strike multiplier." (direction-confirms the pair)
--   * the ONLY parseable Reen's Ire mod on the item is the grant line
--     (ModCache.lua ~16096) which is an EMPTY modlist {{}, ...} = no-op; the
--     per-stack magnitude lives in a tooltipDescription (flavor text, unparsed).
--     So the per-stack effect is otherwise completely unmodeled.
--
-- Model shape (config-gated, direct-apply — the Void Essence pattern at
-- ConfigOptions.lua):
--   * config `multiplierReensIreStacks` (type "count"), default blank/0.
--   * apply(): per stack N -> CritMultiplier BASE (N*5) melee-scoped
--     (KeywordFlag.Melee, matches the "+N% Melee Critical Multiplier" ModCache
--     form) + FireDamage INC (N*10) with Fire+Dot flags (matches the "N%
--     increased Fire Damage Over Time" ModCache form, flags 4104).
--   * capped at 30 stacks. Default 0 -> strict no-op = corpus-neutral (Eye of
--     Reen builds stay byte-identical until the user sets the stack count).
-- ModParser / ModCache are NOT touched — the mechanic is config-driven.
-- See REGRESSION_GUARDS.md "eye-of-reen-reens-ire".

describe("EyeOfReenReensIre #config", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	it("config source: direct-apply count capped 30, melee crit-multi BASE + fire-DoT INC", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierReensIreStacks".-end },')
		assert.is_not_nil(entry, "multiplierReensIreStacks config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		assert.is_truthy(entry:find("max 30", 1, true),
			"label must carry the '(max 30)' cap hint")
		assert.is_truthy(entry:find("math.min(val, 30)", 1, true),
			"apply must cap the stack count at 30")
		assert.is_truthy(entry:find('NewMod("CritMultiplier", "BASE", val * 5, "Reen\'s Ire", 0, KeywordFlag.Melee)', 1, true),
			"apply must emit melee-scoped BASE CritMultiplier of val*5")
		assert.is_truthy(entry:find('NewMod("FireDamage", "INC", val * 10, "Reen\'s Ire", bit.bor(ModFlag.Dot, ModFlag.Fire))', 1, true),
			"apply must emit Fire+Dot-flagged INC FireDamage of val*10")
	end)

	it("behaviour: config 0 default no-op; N stacks add N*5 melee crit-multi and N*10 fire-DoT INC; capped 30", function()
		newBuild()
		local meleeCritCfg = { keywordFlags = KeywordFlag.Melee }
		local fireDotCfg = { flags = bit.bor(ModFlag.Dot, ModFlag.Fire) }
		local function meleeCrit()
			return build.calcsTab.mainEnv.player.modDB:Sum("BASE", meleeCritCfg, "CritMultiplier")
		end
		local function fireDot()
			return build.calcsTab.mainEnv.player.modDB:Sum("INC", fireDotCfg, "FireDamage")
		end

		-- 0 stacks (default) -> no Reen's Ire contribution
		build.configTab.input["multiplierReensIreStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local crit0, fire0 = meleeCrit(), fireDot()

		-- 10 stacks -> +50 melee crit multi, +100 fire DoT INC
		build.configTab.input["multiplierReensIreStacks"] = 10
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(crit0 + 50, meleeCrit())
		assert.are.equal(fire0 + 100, fireDot())

		-- 30 stacks (cap) -> +150 melee crit multi, +300 fire DoT INC
		build.configTab.input["multiplierReensIreStacks"] = 30
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(crit0 + 150, meleeCrit())
		assert.are.equal(fire0 + 300, fireDot())

		-- 40 stacks -> still capped at 30 (+150 / +300)
		build.configTab.input["multiplierReensIreStacks"] = 40
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(crit0 + 150, meleeCrit())
		assert.are.equal(fire0 + 300, fireDot())
	end)

	it("scoping: the crit multi is MELEE-only and the fire INC is fire-DoT-only", function()
		newBuild()
		local player = build.calcsTab.mainEnv.player
		-- spell-scoped crit multi must NOT see the melee-flagged Reen's Ire mod
		local spellCritCfg = { keywordFlags = KeywordFlag.Spell }
		-- a fire HIT (non-DoT) config must NOT see the Dot-flagged fire INC
		local fireHitCfg = { flags = ModFlag.Fire }
		local function spellCrit() return player.modDB:Sum("BASE", spellCritCfg, "CritMultiplier") end
		local function fireHit() return player.modDB:Sum("INC", fireHitCfg, "FireDamage") end

		build.configTab.input["multiplierReensIreStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local spell0, fireHit0 = spellCrit(), fireHit()

		build.configTab.input["multiplierReensIreStacks"] = 30
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(spell0, spellCrit(),
			"melee-scoped Reen's Ire crit multi must not leak into spell crit multi")
		assert.are.equal(fireHit0, fireHit(),
			"DoT-scoped Reen's Ire fire INC must not leak into fire hit damage")
	end)

	it("grant mod stays a no-op (per-stack effect is config-driven, not from the item mod)", function()
		local mc = readFile("Data/ModCache.lua")
		assert.is_not_nil(mc, "must read Data/ModCache.lua")
		-- the parseable grant line must remain an empty modlist {{}, ...}
		assert.is_truthy(mc:find('to gain a stack of Reen\'s Ire', 1, true),
			"the Reen's Ire grant line must still be present in ModCache")
		assert.is_truthy(mc:find('when you crit with a melee attack, up to 30 times per 5 seconds"]={{},', 1, true),
			"the grant line must stay an empty-modlist no-op (per-stack effect lives in the config, not the item mod)")
	end)
end)
