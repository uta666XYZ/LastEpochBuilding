-- @leb-regression-guard: game-faithful-parry-conversion
-- Pins LE game-faithful Block→Parry conversion semantics for the unique sword
-- `Clotho's Needle` (uniques_1_4.json #417) mod text
--   "+N Block Chance converted to Parry Chance while not wielding a shield".
--
-- Decompile reference (LE_datamining/extracted/block_decompile.txt):
--   * Mod property #531 `playerPropertyBlockChanceConvertedToParryWithoutShield`
--   * `blockChanceForCharacterSheet`  (RVA 0x2344f70): returns 0 when
--     blockConversion != None
--   * `parryChanceForCharacterSheet`  (RVA 0x2345390): when blockConversion ==
--     Parry, returns min(blockBase, maxBlock) + parryBonus, capped at ParryCap
--     (DAT_183d81c00 = 75)
--
-- Layers exercised here:
--   1. ModParser  : "+N block chance converted to parry chance while not
--                    wielding a shield" → BlockChance BASE +N + FLAG mod
--                    `BlockChanceConvertedToParryWithoutShield`.
--   2. CalcDefence: when the flag is set AND `UsingShield` condition is false,
--                    output.ParryChance := min(BlockChanceTotal, BlockChanceMax)
--                    + parryBase, capped at ParryCap (75). All Block-display
--                    stats are zeroed (the character-sheet getter returns 0).
--   3. CalcDefence: when the flag is set AND `UsingShield` is true, the
--                    conversion is bypassed; Block stats are kept and Parry
--                    uses only parryBase (vanilla path).
--   4. CalcDefence: without the flag, Parry is just min(parryBase, ParryCap).
describe("TestParryConversion", function()
	before_each(function()
		newBuild()
	end)

	it("ModParser emits BlockChance BASE + FLAG for the converted mod", function()
		build.configTab.input.customMods = [[
		+1 Block Chance converted to Parry Chance while not wielding a shield
		]]
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local modDB = build.calcsTab.mainEnv.modDB
		assert.are.equals(1, modDB:Sum("BASE", nil, "BlockChance"))
		assert.is_true(modDB:Flag(nil, "BlockChanceConvertedToParryWithoutShield"))
	end)

	it("no flag: vanilla parry path uses only ParryChance base", function()
		build.configTab.input.customMods = [[
		+25 Parry Chance
		+10 Block Chance
		]]
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local out = build.calcsTab.calcsOutput
		assert.are.equals(25, out.ParryChance)
		assert.are.equals(10, out.BlockChance)
	end)

	it("flag + no shield: Block routes into Parry, Block stats zero", function()
		build.configTab.input.customMods = [[
		+50 Block Chance
		+1 Block Chance converted to Parry Chance while not wielding a shield
		]]
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local out = build.calcsTab.calcsOutput
		-- Total raw block = 50 + 1 = 51, max = 75 → min = 51 → Parry = 51
		assert.are.equals(51, out.ParryChance)
		-- Game's blockChanceForCharacterSheet returns 0 when blockConversion!=None
		assert.are.equals(0, out.BlockChance)
		assert.are.equals(0, out.BlockChanceTotal)
		assert.are.equals(0, out.SpellBlockChance)
	end)

	it("flag + no shield + ParryBonus stacks under ParryCap", function()
		build.configTab.input.customMods = [[
		+30 Parry Chance
		+40 Block Chance
		+1 Block Chance converted to Parry Chance while not wielding a shield
		]]
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local out = build.calcsTab.calcsOutput
		-- min(40+1, 75) + 30 = 41 + 30 = 71 ≤ 75
		assert.are.equals(71, out.ParryChance)
		assert.are.equals(0, out.BlockChance)
	end)

	it("flag + no shield: Parry capped at ParryCap (75)", function()
		build.configTab.input.customMods = [[
		+50 Parry Chance
		+90 Block Chance
		+1 Block Chance converted to Parry Chance while not wielding a shield
		]]
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local out = build.calcsTab.calcsOutput
		-- min(90+1, 75) + 50 = 75 + 50 = 125 → capped at ParryCap (75)
		assert.are.equals(75, out.ParryChance)
		assert.are.equals(0, out.BlockChance)
	end)

	-- NOTE: The "flag + UsingShield = bypass conversion" branch is exercised by
	-- the live CalcDefence logic but not unit-testable via customMods, because
	-- `UsingShield` is set in CalcSetup.lua only when a Shield item is actually
	-- equipped in Weapon 2 and runCallback("OnFrame") rebuilds modDB.conditions
	-- before our calc sees it. Wiring up a shield-equipped XML build would test
	-- this branch, but no real build currently combines Clotho's Needle (a
	-- two-hand sword that occupies Weapon 1) with a shield (Weapon 2). The
	-- decompile semantics make this combination impossible in-game (two-hand
	-- weapons block Weapon 2), so the branch is dead-code-for-future-safety.
end)
