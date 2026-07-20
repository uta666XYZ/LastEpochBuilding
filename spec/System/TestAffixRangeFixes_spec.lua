-- @leb-regression-guard: affix-range-percent-format
-- (C) @leb-regression-guard: affix-412-leech-default-x10
-- (D) @leb-regression-guard: affix-417-marrow-bleed-wrong-stat
--     See REGRESSION_GUARDS.md "affix-417-marrow-bleed-wrong-stat".
-- See REGRESSION_GUARDS.md "affix-range-percent-format".
-- Validation provenance is retained in maintainer notes.

describe("TestAffixRangeFixes #affixRangeData", function()
	setup(function()
		newBuild()
	end)

	-- key, field, exact expected display string (datamine-verified)
	local MODITEM_EXPECTED = {
		{ "839_0", "2", "{rounding:Integer}(50-100) Damage Reflected to Attackers" },
		{ "964_7", "1", "+100% Chance on Block to apply Marked For Death to the Attacker" },
		{ "980_7", "1", "+(170-200)% Chance for non-Critical Strikes to inflict Critical Vulnerability" },
		{ "947_5", "1", "+(100-139)% Increased Damage for skills used by Shadows" },
		{ "947_6", "1", "+(140-180)% Increased Damage for skills used by Shadows" },
		{ "947_7", "1", "+(240-300)% Increased Damage for skills used by Shadows" },
		{ "948_7", "1", "+(125-150)% Chance to gain a stack of Dusk Shroud when you consume a Shadow" },
		{ "959_7", "1", "+100% Chance to cast cold Volcanic Orb when you directly use a cold melee attack or cold traversal skill (3 second cooldown)" },
		-- 959/960/961/986/1090 damage lines carry "increased" per guard
		-- bare-form-damage-affix-increased (modifierType 1 = Increased).
		{ "959_7", "2", "(160-200)% increased Cold Damage" },
		{ "960_7", "1", "+100% Chance to cast fire Volcanic Orb when you directly use a fire melee attack or fire traversal skill (3 second cooldown)" },
		{ "960_7", "2", "(160-200)% increased Fire Damage" },
		{ "961_7", "1", "+(100-120)% chance to throw a Burning Dagger when you use a melee fire attack and hit at least one enemy, doubled for Dancing Strikes (up to 4 times per second)" },
		{ "961_7", "2", "(150-170)% increased Fire Damage" },
		{ "962_7", "1", "+100% Chance to Blind on Fire Hit" },
		{ "967_3", "1", "+(100-109)% Damage Over Time" },
		{ "967_4", "1", "+(110-119)% Damage Over Time" },
		{ "967_5", "1", "+(120-129)% Damage Over Time" },
		{ "967_6", "1", "+(130-140)% Damage Over Time" },
		{ "967_7", "1", "+(190-210)% Damage Over Time" },
		{ "985_3", "1", "+(100-109)% Damage Over Time" },
		{ "985_4", "1", "+(110-119)% Damage Over Time" },
		{ "985_5", "1", "+(120-129)% Damage Over Time" },
		{ "985_6", "1", "+(130-140)% Damage Over Time" },
		{ "985_7", "1", "+(190-210)% Damage Over Time" },
		{ "986_3", "1", "(100-109)% increased Melee Damage" },
		{ "986_4", "1", "(110-119)% increased Melee Damage" },
		{ "986_5", "1", "(120-129)% increased Melee Damage" },
		{ "986_6", "1", "(130-140)% increased Melee Damage" },
		{ "986_7", "1", "(190-210)% increased Melee Damage" },
		{ "1007_7", "1", "+(110-120)% Armor" },
		{ "1081_7", "1", "+100% chance to gain Haste for 5 seconds after you Block" },
		{ "1090_7", "2", "(160-200)% increased Throwing Damage" },
		-- affixId 412 leech-as-health: Helmet default = raw x10 (was wrongly raw x100).
		{ "412_0", "1", "(1.2-1.6)% of Damage dealt by Harvest Leeched as Health" },
		{ "412_4", "1", "(3.2-4)% of Damage dealt by Harvest Leeched as Health" },
		{ "412_6", "1", "(6.1-7.5)% of Damage dealt by Harvest Leeched as Health" },
		{ "412_7", "1", "(12-15)% of Damage dealt by Harvest Leeched as Health" },
		-- affixId 417 marrow-bleed: wrong stat (Projectile Speed) -> correct
		-- "more Damage Over Time to Bleeding Enemies for Marrow Shards", raw range.
		{ "417_0", "1", "1% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
		{ "417_4", "1", "5% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
		{ "417_5", "1", "(7-8)% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
		{ "417_7", "1", "(13-15)% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
		-- affixId 302 idol sibling: same wrong-stat (Projectile Speed Marrow/Bone Nova)
		-- -> correct "more DoT to Bleeding for Marrow Shards", idol single tier 2-4% raw.
		{ "302_0", "1", "(2-4)% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
	}

	it("ModItem_1_4 affix lines match the datamine-verified corrections", function()
		local mods = readJsonFile("Data/ModItem_1_4.json")
		assert.is_not_nil(mods, "ModItem_1_4.json must load")
		local offenders = {}
		for _, row in ipairs(MODITEM_EXPECTED) do
			local key, field, want = row[1], row[2], row[3]
			-- jsonToLua (Common.lua) converts purely-numeric JSON keys to
			-- integer Lua keys, so stat fields "1"/"2" are indexed numerically.
			local entry = mods[key]
			local got = entry and entry[tonumber(field)]
			if got ~= want then
				table.insert(offenders, string.format(
					"%s[%s]\n     want: %q\n     got:  %q",
					key, field, want, tostring(got)))
			end
		end
		assert.are.equal(0, #offenders,
			"affix lines drifted from datamine-verified values:\n  " ..
			table.concat(offenders, "\n  "))
	end)

	it("no x100 percent affix regresses to the raw-fraction {rounding:Integer} form", function()
		-- The exact buggy fingerprints we removed must never reappear: a
		-- `{rounding:Integer}` line whose value is a sub-10 fraction for a
		-- percent stat. Listed verbatim so a re-import that reverts them fails.
		local mods = readJsonFile("Data/ModItem_1_4.json")
		local FORBIDDEN = {
			["947_5"] = "{rounding:Integer}+(1-1.39) Increased Damage for skills used by Shadows",
			["967_3"] = "{rounding:Integer}+(1-1.09) Damage Over Time",
			["986_3"] = "{rounding:Integer}+(1-1.09) Melee Damage",
			["1007_7"] = "{rounding:Integer}+(1.1-1.2) Armor",
			["839_0_field2"] = "{rounding:Integer}(50-150) Damage Reflected to Attackers",
			-- affixId 412 Helmet default at the buggy raw x100 scale.
			["412_0"] = "(12-16)% of Damage dealt by Harvest Leeched as Health",
			["412_7"] = "(120-150)% of Damage dealt by Harvest Leeched as Health",
		}
		local hits = {}
		if mods["947_5"] and mods["947_5"][1] == FORBIDDEN["947_5"] then table.insert(hits, "947_5[1]") end
		if mods["967_3"] and mods["967_3"][1] == FORBIDDEN["967_3"] then table.insert(hits, "967_3[1]") end
		if mods["986_3"] and mods["986_3"][1] == FORBIDDEN["986_3"] then table.insert(hits, "986_3[1]") end
		if mods["1007_7"] and mods["1007_7"][1] == FORBIDDEN["1007_7"] then table.insert(hits, "1007_7[1]") end
		if mods["839_0"] and mods["839_0"][2] == FORBIDDEN["839_0_field2"] then table.insert(hits, "839_0[2]") end
		if mods["412_0"] and mods["412_0"][1] == FORBIDDEN["412_0"] then table.insert(hits, "412_0[1]") end
		if mods["412_7"] and mods["412_7"][1] == FORBIDDEN["412_7"] then table.insert(hits, "412_7[1]") end
		assert.are.equal(0, #hits,
			"buggy raw-fraction form regressed on: " .. table.concat(hits, ", "))
	end)

	it("affixId 412 leech-as-health: Helmet default is raw x10 and Body Armor override (x1.5) is unchanged", function()
		-- @leb-regression-guard: affix-412-leech-default-x10
		-- default field "1" = Helmet (aem=0); slotOverrides.body_armor = Body Armor
		-- (aem=0.5, x1.5). Both confirmed by in-game bazaar + LETools DB with the
		-- 1-indexed-vs-0-indexed tier offset accounted for (bazaar Tier7 = t6).
		local mods = readJsonFile("Data/ModItem_1_4.json")
		assert.is_not_nil(mods, "ModItem_1_4.json must load")
		-- key, helmet default, body_armor override (raw x10, raw x10 x1.5)
		local EXPECTED = {
			{ "412_0", "(1.2-1.6)% of Damage dealt by Harvest Leeched as Health", "(1.8-2.4)% of Damage dealt by Harvest Leeched as Health" },
			{ "412_1", "(1.7-2.1)% of Damage dealt by Harvest Leeched as Health", "(2.6-3.2)% of Damage dealt by Harvest Leeched as Health" },
			{ "412_2", "(2.2-2.6)% of Damage dealt by Harvest Leeched as Health", "(3.3-3.9)% of Damage dealt by Harvest Leeched as Health" },
			{ "412_3", "(2.7-3.1)% of Damage dealt by Harvest Leeched as Health", "(4-4.6)% of Damage dealt by Harvest Leeched as Health" },
			{ "412_4", "(3.2-4)% of Damage dealt by Harvest Leeched as Health", "(4.8-6)% of Damage dealt by Harvest Leeched as Health" },
			{ "412_5", "(4.8-6)% of Damage dealt by Harvest Leeched as Health", "(7.2-9)% of Damage dealt by Harvest Leeched as Health" },
			{ "412_6", "(6.1-7.5)% of Damage dealt by Harvest Leeched as Health", "(9.2-11.2)% of Damage dealt by Harvest Leeched as Health" },
			{ "412_7", "(12-15)% of Damage dealt by Harvest Leeched as Health", "(18-22.5)% of Damage dealt by Harvest Leeched as Health" },
		}
		local offenders = {}
		for _, row in ipairs(EXPECTED) do
			local key, wantDefault, wantBody = row[1], row[2], row[3]
			local entry = mods[key]
			local gotDefault = entry and entry[1]
			local gotBody = entry and entry.slotOverrides
				and entry.slotOverrides.body_armor and entry.slotOverrides.body_armor[1]
			if gotDefault ~= wantDefault then
				table.insert(offenders, string.format("%s default\n     want: %q\n     got:  %q",
					key, wantDefault, tostring(gotDefault)))
			end
			if gotBody ~= wantBody then
				table.insert(offenders, string.format("%s body_armor\n     want: %q\n     got:  %q",
					key, wantBody, tostring(gotBody)))
			end
		end
		assert.are.equal(0, #offenders,
			"affixId 412 leech ranges drifted:\n  " .. table.concat(offenders, "\n  "))
	end)

	it("affixId 417 marrow-bleed: is the DoT-to-bleeding 'more' stat, never Projectile Speed, single field", function()
		-- @leb-regression-guard: affix-417-marrow-bleed-wrong-stat
		-- Locks both the corrected stat text/range AND the absence of the stale
		-- "Increased Projectile Speed with Marrow Shards/Bone Nova" mapping and its
		-- second field. Raw datamine range (LEB applies Body-Armor ×1.5 live).
		local mods = readJsonFile("Data/ModItem_1_4.json")
		assert.is_not_nil(mods, "ModItem_1_4.json must load")
		local EXPECTED = {
			{ "417_0", "1% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
			{ "417_1", "2% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
			{ "417_2", "3% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
			{ "417_3", "4% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
			{ "417_4", "5% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
			{ "417_5", "(7-8)% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
			{ "417_6", "(9-10)% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
			{ "417_7", "(13-15)% more Damage Over Time to Bleeding Enemies for Marrow Shards" },
		}
		local offenders = {}
		for _, row in ipairs(EXPECTED) do
			local key, want = row[1], row[2]
			local entry = mods[key]
			local got = entry and entry[1]
			if got ~= want then
				table.insert(offenders, string.format("%s\n     want: %q\n     got:  %q",
					key, want, tostring(got)))
			end
			-- the bogus second (Bone Nova) field must be gone
			if entry and entry[2] ~= nil then
				table.insert(offenders, string.format("%s[2] should be nil, got %q",
					key, tostring(entry[2])))
			end
			-- never the stale Projectile-Speed mapping
			if got and tostring(got):find("Projectile Speed", 1, true) then
				table.insert(offenders, string.format("%s regressed to Projectile Speed: %q",
					key, tostring(got)))
			end
		end
		assert.are.equal(0, #offenders,
			"affixId 417 marrow-bleed drifted:\n  " .. table.concat(offenders, "\n  "))
	end)

	it("affixId 302 idol marrow-bleed sibling: is the DoT-to-bleeding 'more' stat, never Projectile Speed, single field", function()
		-- @leb-regression-guard: affix-417-marrow-bleed-wrong-stat
		-- 302 is the idol sibling of 417 (canRollOn [32] = idol). Same stale
		-- affixId-divergence bug: it carried two "Increased Projectile Speed with
		-- Marrow Shards / Bone Nova" fields plus placeholder modName/affix
		-- "Fractured". Correct = single field "1" raw idol range 2-4% (datamine 302
		-- single tier minRoll .02/maxRoll .04, modifierType 2 = more); LEB applies
		-- idol aem live via modScalar (Item.lua:1448).
		local mods = readJsonFile("Data/ModItem_1_4.json")
		assert.is_not_nil(mods, "ModItem_1_4.json must load")
		local entry = mods["302_0"]
		assert.is_not_nil(entry, "302_0 must exist")
		assert.are.equal(
			"(2-4)% more Damage Over Time to Bleeding Enemies for Marrow Shards",
			entry[1],
			"302_0 field 1 must be the idol DoT-to-bleeding 'more' stat (2-4% raw)")
		assert.is_nil(entry[2], "302_0 bogus second (Bone Nova) field must be removed")
		assert.is_falsy(tostring(entry[1] or ""):find("Projectile Speed", 1, true),
			"302_0 must never regress to the stale Projectile Speed mapping")
		assert.is_not.equal("Fractured", entry.affix,
			"302_0 affix must no longer be the placeholder 'Fractured'")
	end)

	it("idol affix 839 'of the Briar' Damage Reflected to Attackers max is 100 (in-game verified)", function()
		local idol = readJsonFile("Data/ModIdol_1_4.json")
		assert.is_not_nil(idol, "ModIdol_1_4.json must load")
		assert.is_not_nil(idol.weaver, "ModIdol weaver section must exist")
		local entry = idol.weaver["839_0"]
		assert.is_not_nil(entry, "weaver 839_0 must exist")
		assert.are.equal(
			"{rounding:Integer}(50-100) Damage Reflected to Attackers",
			entry[2],
			"idol 839 field 2 must be the datamine (50-100), not (50-150) -- " ..
			"in-game MyLittleStJames Defense sheet = 108")
	end)

	it("affixId 95/96 keep per-slot pre-baking (Shield default != Body Armor override); 815 unchanged", function()
		-- @leb-regression-guard: affix-95-96-815-no-letools-rescale
		-- STOP guard. Reverted commit <see git log> tried to x1.5 the whole affix
		-- (overwriting the Shield default with the Body-Armor value) and re-set
		-- 815 to raw datamine tiers, citing LETools. The revert (<see git log>) was
		-- correct. 95/96 canRollOn [1,18]: default "1" = Shield (datamine x1.17),
		-- slotOverrides.body_armor = Body Armor (datamine x1.5). 815 canRollOn [18]
		-- only (unique-item affix, specialAffixType 3); current tiers stand --
		-- no datamine/in-game grounding to change them, and LETools is not authority.
		-- See REGRESSION_GUARDS.md "affix-95-96-815-no-letools-rescale".
		local mods = readJsonFile("Data/ModItem_1_4.json")
		assert.is_not_nil(mods, "ModItem_1_4.json must load")
		-- key, Shield default field "1", Body Armor override field "1"
		local PERSLOT = {
			{ "95_0", "{rounding:Integer}(12-18) Damage Reflected to Attackers", "{rounding:Integer}(15-22) Damage Reflected to Attackers" },
			{ "95_4", "{rounding:Integer}(105-176) Damage Reflected to Attackers", "{rounding:Integer}(135-225) Damage Reflected to Attackers" },
			{ "95_7", "{rounding:Integer}(749-936) Damage Reflected to Attackers", "{rounding:Integer}(960-1200) Damage Reflected to Attackers" },
			{ "96_0", "(6-12)% of Damage Reflected", "(8-15)% of Damage Reflected" },
			{ "96_4", "(46-58)% of Damage Reflected", "(58-75)% of Damage Reflected" },
			{ "96_7", "(187-234)% of Damage Reflected", "(240-300)% of Damage Reflected" },
		}
		local offenders = {}
		for _, row in ipairs(PERSLOT) do
			local key, wantDef, wantBody = row[1], row[2], row[3]
			local entry = mods[key]
			local gotDef = entry and entry[1]
			local gotBody = entry and entry.slotOverrides
				and entry.slotOverrides.body_armor and entry.slotOverrides.body_armor[1]
			if gotDef ~= wantDef then
				table.insert(offenders, string.format("%s default(Shield)\n     want: %q\n     got:  %q",
					key, wantDef, tostring(gotDef)))
			end
			if gotBody ~= wantBody then
				table.insert(offenders, string.format("%s body_armor\n     want: %q\n     got:  %q",
					key, wantBody, tostring(gotBody)))
			end
			-- the reverted bug collapsed default == body_armor; assert they differ
			if gotDef ~= nil and gotDef == gotBody then
				table.insert(offenders, string.format("%s default must NOT equal body_armor (per-slot collapse): %q",
					key, tostring(gotDef)))
			end
		end
		-- 815 unique-item affix tiers stand as-is (no LETools rescale)
		local EXP_815 = {
			{ "815_0", "{rounding:Integer}(19-29)% increased Minion Health" },
			{ "815_4", "{rounding:Integer}(66-79)% increased Minion Health" },
			{ "815_7", "{rounding:Integer}(254-301)% increased Minion Health" },
		}
		for _, row in ipairs(EXP_815) do
			local key, want = row[1], row[2]
			local entry = mods[key]
			local got = entry and entry[1]
			if got ~= want then
				table.insert(offenders, string.format("%s\n     want: %q\n     got:  %q",
					key, want, tostring(got)))
			end
		end
		assert.are.equal(0, #offenders,
			"affix 95/96/815 drifted from the post-revert per-slot values:\n  " ..
			table.concat(offenders, "\n  "))
	end)

	it("affixId 52 'of the Ox' Increased Health: tier-2 body_armor override is banker-rounded (9-10), not (9-11)", function()
		-- @leb-regression-guard: bodyarmor-health-affix-banker-round
		-- Body Armor affixEffectModifier=0.5 (datamine equipmentItems.json "Body
		-- Armor") scales health affixes x1.5. The baked body_armor slotOverride
		-- RANGE endpoints MUST be BANKER-rounded (round-half-to-even), matching
		-- LE's AscendingValueAfterPropertyRounding, NOT round-half-up. "of the Ox"
		-- (affixId 52) tier index 2 (tooltip "Tier 3") base (6-7)% x1.5 = (9-10.5)%;
		-- banker(10.5)=10 (10 is even) -> override is (9-10)%. It was wrongly baked
		-- as (9-11)% (round-half-up of 10.5), over-rolling byte values near the top
		-- of the range by +1: DoNotReleaseThem lv69 Beastmaster's "Primalist's
		-- Kolheim Armor of the Turtle" (in-game Tier 3 "Range: 9% to 10%", value 9%)
		-- was read as 10%, pushing INC Health 37%->38% and Health 1903->1917 (+14),
		-- with a derived Endurance Threshold +2.
		-- See REGRESSION_GUARDS.md "bodyarmor-health-affix-banker-round".
		local mods = readJsonFile("Data/ModItem_1_4.json")
		assert.is_not_nil(mods, "ModItem_1_4.json must load")
		local entry = mods["52_2"]
		assert.is_not_nil(entry, "52_2 must exist")
		local body = entry.slotOverrides
			and entry.slotOverrides.body_armor and entry.slotOverrides.body_armor[1]
		assert.are.equal(
			"{rounding:Integer}(9-10)% increased Health",
			body,
			"52_2 body_armor override must be banker-rounded (9-10), not round-half-up (9-11)")
		assert.is_falsy(tostring(body or ""):find("(9-11)", 1, true),
			"52_2 body_armor override must never regress to the round-half-up (9-11)")
		-- base (Helmet aem=0) field stays the raw datamine (6-7)%
		assert.are.equal(
			"{rounding:Integer}(6-7)% increased Health",
			entry[1],
			"52_2 default (Helmet) field must remain the raw datamine (6-7)%")
	end)

	-- @leb-regression-guard: area-level-multiplier-decoupled-from-mitigation
	-- The "Enemy / Area Level" config field feeds TWO consumers whose correct
	-- DEFAULTS differ, so ConfigOptions.lua decouples them:
	--   (1) Armor/Block/Dodge mitigation (env.config.enemyLevel) defaults to the
	--       CHARACTER LEVEL, matching the in-game character sheet (validated vs
	--       ShutFackUp lv85 / MyLittleStJames lv79).
	--   (2) "depending on Area Level" affixes (Cursed Veteran's Boots etc.) read
	--       Multiplier:AreaLevel and default to AREA LEVEL 100 (Empowered Monolith,
	--       Bosses.lua), independent of character level -- a lv70 char still runs
	--       empowered monos at area level 100.
	-- An EXPLICIT value typed into the field overrides BOTH.
	-- See REGRESSION_GUARDS.md "area-level-multiplier-decoupled-from-mitigation".
	it("area level default (100) is decoupled from the character-level mitigation default", function()
		newBuild()
		build.characterLevel = 70
		build.configTab.input.enemyLevel = nil -- no explicit override -> use defaults
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- mitigation default tracks character level, NOT the area-level 100
		assert.are.equal(70, build.calcsTab.mainEnv.config.enemyLevel)
		-- "depending on Area Level" scaling defaults to empowered monolith = 100
		assert.are.equal(100, build.calcsTab.mainEnv.player.modDB:GetMultiplier("AreaLevel"))
	end)

	it("an explicit Enemy / Area Level overrides BOTH mitigation and area-level scaling", function()
		newBuild()
		build.characterLevel = 70
		build.configTab.input.enemyLevel = 85
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(85, build.calcsTab.mainEnv.config.enemyLevel)
		assert.are.equal(85, build.calcsTab.mainEnv.player.modDB:GetMultiplier("AreaLevel"))
		build.configTab.input.enemyLevel = nil -- reset shared build for later tests
	end)
end)
