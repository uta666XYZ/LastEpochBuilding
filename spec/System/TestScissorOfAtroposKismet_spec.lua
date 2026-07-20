-- @leb-regression-guard:scissor-of-atropos-kismet-stacks
-- Scissor of Atropos (Unique 1H Sword, Lv60). "1 Kismet Stack gained when you
-- directly use a Melee Attack and hit at least one enemy" (up to 8). Kismet is a
-- player-direct throwing buff: each stack grants +8% throwing critical strike
-- chance and +8 added throwing physical damage; stacks are BUILT by melee hits and
-- CONSUMED on throw (consume-on-throw burst), so the two attack types are coupled
-- (dual-wield raises the stack-gain rate).
--
-- Grounding (verbatim):
--   * gear tooltip + datamine: 未モデル affix gear grounding (B-group). Per-stack
--     magnitudes datamine-confirmed: 8% throwing crit chance + 8 added throwing
--     physical damage per stack, cap 8. NO curve-fit.
--   * the ONLY parseable Kismet mod on the item is the grant line
--     (ModCache.lua ~L10122, "1 Kismet Stacks gained when you directly use a Melee
--     Attack and hit at least one enemy") which compiles to an EMPTY modlist
--     {{}, ...} = no-op; the per-stack magnitude lives in the buff definition
--     (unparsed). So the per-stack effect is otherwise completely unmodeled.
--
-- Model shape (config-gated, direct-apply -- the Void Essence / Reen's Ire /
-- Dilation / Infusion pattern at ConfigOptions.lua):
--   * config `multiplierKismetStacks` (type "count"), default blank/0.
--   * apply(): per stack N -> CritChance BASE (N*8) throwing-scoped
--     (KeywordFlag.Throwing) + added PhysicalDamage BASE (N*8) throwing-scoped
--     (KeywordFlag.Throwing).
--   * capped at 8 stacks. Default 0 -> strict no-op = corpus-neutral (Scissor
--     builds stay byte-identical until the user sets the stack count).
--   * NOTE: the consume-on-throw BURST rotation (melee builds, throw spends) is
--     stack-count/rotation-dependent and is intentionally NOT modeled -- this
--     config scopes the steady per-stack offensive effect only (user opt-in).
-- ModParser / ModCache are NOT touched -- the mechanic is config-driven.
-- See REGRESSION_GUARDS.md "scissor-of-atropos-kismet-stacks".

describe("ScissorOfAtroposKismet #config", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	it("config source: direct-apply count capped 8, throwing crit-chance BASE + throwing phys BASE", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierKismetStacks".-end },')
		assert.is_not_nil(entry, "multiplierKismetStacks config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		assert.is_truthy(entry:find("max 8", 1, true),
			"label must carry the '(max 8)' cap hint")
		assert.is_truthy(entry:find("math.min(val, 8)", 1, true),
			"apply must cap the stack count at 8")
		assert.is_truthy(entry:find('NewMod("CritChance", "BASE", val * 8, "Kismet", 0, KeywordFlag.Throwing)', 1, true),
			"apply must emit throwing-scoped BASE CritChance of val*8")
		assert.is_truthy(entry:find('NewMod("PhysicalDamage", "BASE", val * 8, "Kismet", 0, KeywordFlag.Throwing)', 1, true),
			"apply must emit throwing-scoped BASE PhysicalDamage of val*8")
	end)

	it("behaviour: config 0 default no-op; N stacks add N*8 throwing crit-chance and N*8 throwing phys; capped 8", function()
		newBuild()
		local throwCfg = { keywordFlags = KeywordFlag.Throwing }
		local function throwCrit()
			return build.calcsTab.mainEnv.player.modDB:Sum("BASE", throwCfg, "CritChance")
		end
		local function throwPhys()
			return build.calcsTab.mainEnv.player.modDB:Sum("BASE", throwCfg, "PhysicalDamage")
		end

		-- 0 stacks (default) -> no Kismet contribution
		build.configTab.input["multiplierKismetStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local crit0, phys0 = throwCrit(), throwPhys()

		-- 4 stacks -> +32 throwing crit chance, +32 throwing phys
		build.configTab.input["multiplierKismetStacks"] = 4
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(crit0 + 32, throwCrit())
		assert.are.equal(phys0 + 32, throwPhys())

		-- 8 stacks (cap) -> +64 throwing crit chance, +64 throwing phys
		build.configTab.input["multiplierKismetStacks"] = 8
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(crit0 + 64, throwCrit())
		assert.are.equal(phys0 + 64, throwPhys())

		-- 12 stacks -> still capped at 8 (+64 / +64)
		build.configTab.input["multiplierKismetStacks"] = 12
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(crit0 + 64, throwCrit())
		assert.are.equal(phys0 + 64, throwPhys())
	end)

	it("scoping: the Kismet crit/phys is THROWING-only (does not leak into melee/spell)", function()
		newBuild()
		local player = build.calcsTab.mainEnv.player
		-- melee-scoped crit chance / phys must NOT see the throwing-flagged Kismet mods
		local meleeCfg = { keywordFlags = KeywordFlag.Melee }
		local spellCfg = { keywordFlags = KeywordFlag.Spell }
		local function meleeCrit() return player.modDB:Sum("BASE", meleeCfg, "CritChance") end
		local function meleePhys() return player.modDB:Sum("BASE", meleeCfg, "PhysicalDamage") end
		local function spellCrit() return player.modDB:Sum("BASE", spellCfg, "CritChance") end

		build.configTab.input["multiplierKismetStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local meleeCrit0, meleePhys0, spellCrit0 = meleeCrit(), meleePhys(), spellCrit()

		build.configTab.input["multiplierKismetStacks"] = 8
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(meleeCrit0, meleeCrit(),
			"throwing-scoped Kismet crit chance must not leak into melee crit chance")
		assert.are.equal(meleePhys0, meleePhys(),
			"throwing-scoped Kismet phys must not leak into melee phys")
		assert.are.equal(spellCrit0, spellCrit(),
			"throwing-scoped Kismet crit chance must not leak into spell crit chance")
	end)

	it("grant mod stays a no-op (per-stack effect is config-driven, not from the item mod)", function()
		local mc = readFile("Data/ModCache.lua")
		assert.is_not_nil(mc, "must read Data/ModCache.lua")
		-- the parseable grant line must remain an empty modlist {{}, ...}
		assert.is_truthy(mc:find('Kismet Stacks gained when you directly use a Melee Attack', 1, true),
			"the Kismet grant line must still be present in ModCache")
		assert.is_truthy(mc:find('when you directly use a Melee Attack and hit at least one enemy"]={{},', 1, true),
			"the grant line must stay an empty-modlist no-op (per-stack effect lives in the config, not the item mod)")
	end)
end)
