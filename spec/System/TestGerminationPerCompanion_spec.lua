-- @leb-regression-guard:germination-per-companion-scaling
-- See REGRESSION_GUARDS.md "germination-per-companion-scaling".
-- Validation provenance is retained in maintainer notes.

describe("GerminationPerCompanion #skills", function()
	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	local function findTag(mod, tagType, var)
		for _, tag in ipairs(mod) do
			if tag.type == tagType and (var == nil or tag.var == var) then
				return tag
			end
		end
		return nil
	end

	it("parse contract: ProjectileCount BASE 1, SkillName:Spirit Thorns x Multiplier:GerminationStacks (limit 4)", function()
		local list, extra = modLib.parseMod("+1 Projectiles with Spirit Thorns per stack of Germination")
		assert.is_not_nil(list, "must parse")
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("ProjectileCount", mod.name)
		assert.are.equal("BASE", mod.type)
		assert.are.equal(1, mod.value)
		local skill = findTag(mod, "SkillName")
		assert.is_not_nil(skill, "must stay scoped to a skill")
		assert.are.equal("Spirit Thorns", skill.skillName)
		local mult = findTag(mod, "Multiplier", "GerminationStacks")
		assert.is_not_nil(mult, "must carry Multiplier:GerminationStacks")
		assert.are.equal(4, mult.limit, "limit must cap at 4 (datamine MAX_GERMINATION_STACKS)")
		-- the only leftover may be the bare connector "with" (item-tolerated residue)
		assert.is_true(not extra or extra:lower():gsub("%s+", "") == "" or extra:lower():gsub("%s+", "") == "with",
			"residue must be empty or the connector 'with', got: [" .. tostring(extra) .. "]")
	end)

	it("parse contract: Health Regen BASE x Multiplier:GerminationStacks (limit 4), no residue", function()
		local list, extra = modLib.parseMod("+26 Health Regen per stack of Germination")
		assert.is_not_nil(list, "must parse")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(1, #list)
		local mod = list[1]
		assert.are.equal("LifeRegen", mod.name)
		assert.are.equal("BASE", mod.type)
		assert.are.equal(26, mod.value)
		local mult = findTag(mod, "Multiplier", "GerminationStacks")
		assert.is_not_nil(mult, "must carry Multiplier:GerminationStacks")
		assert.are.equal(4, mult.limit, "limit must cap at 4 (datamine MAX_GERMINATION_STACKS)")
		assert.is_nil(findTag(mod, "SkillName"), "Health Regen must be global (no skill scope)")
	end)

	it("behaviour: both mods scale per Germination stack and cap at 4 (matches in-game 1/2/3/4 + 26/52/78/104)", function()
		newBuild()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Test Roots
		Brass Sceptre
		+1 Projectiles with Spirit Thorns per stack of Germination
		+26 Health Regen per stack of Germination]])
		build.itemsTab:AddDisplayItem()

		local thornsCfg = { skillName = "Spirit Thorns" }
		local function thornsProj()
			return build.calcsTab.mainEnv.player.modDB:Sum("BASE", thornsCfg, "ProjectileCount")
		end
		local function lifeRegen()
			return build.calcsTab.mainEnv.player.modDB:Sum("BASE", nil, "LifeRegen")
		end

		local function setStacks(n)
			build.configTab.input["multiplierGerminationStacks"] = n
			build.configTab:BuildModList()
			runCallback("OnFrame")
		end

		-- 0 stacks (default) -> no Germination contribution
		setStacks(0)
		local proj0, regen0 = thornsProj(), lifeRegen()

		-- 1..4 stacks: +1 projectile and +26 Health Regen per stack
		for n = 1, 4 do
			setStacks(n)
			assert.are.equal(proj0 + n, thornsProj(),
				"Spirit Thorns projectiles must be base + " .. n .. " at " .. n .. " stacks")
			assert.are.equal(regen0 + 26 * n, lifeRegen(),
				"Health Regen must be base + 26*" .. n .. " at " .. n .. " stacks")
		end

		-- cap: 5 and 7 stacks must still be the 4-stack values (parser limit 4)
		setStacks(5)
		assert.are.equal(proj0 + 4, thornsProj(), "projectiles must cap at +4")
		assert.are.equal(regen0 + 26 * 4, lifeRegen(), "Health Regen must cap at +104")
		setStacks(7)
		assert.are.equal(proj0 + 4, thornsProj(), "projectiles must cap at +4 (7 stacks)")
		assert.are.equal(regen0 + 26 * 4, lifeRegen(), "Health Regen must cap at +104 (7 stacks)")
	end)

	it("scope: Spirit Thorns projectile bonus does NOT leak to other skills", function()
		newBuild()
		build.itemsTab:CreateDisplayItemFromRaw([[Rarity: RARE
		Test Roots
		Brass Sceptre
		+1 Projectiles with Spirit Thorns per stack of Germination]])
		build.itemsTab:AddDisplayItem()

		build.configTab.input["multiplierGerminationStacks"] = 4
		build.configTab:BuildModList()
		runCallback("OnFrame")

		local otherCfg = { skillName = "Fireball" }
		assert.are.equal(0, build.calcsTab.mainEnv.player.modDB:Sum("BASE", otherCfg, "ProjectileCount"),
			"a non-Spirit-Thorns skill must get no Germination projectiles")
	end)

	it("behaviour: a build WITHOUT any Germination mod ignores the config entirely", function()
		newBuild()
		local function lifeRegen()
			return build.calcsTab.mainEnv.player.modDB:Sum("BASE", nil, "LifeRegen")
		end

		build.configTab.input["multiplierGerminationStacks"] = 0
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local regen0 = lifeRegen()

		build.configTab.input["multiplierGerminationStacks"] = 4
		build.configTab:BuildModList()
		runCallback("OnFrame")
		assert.are.equal(regen0, lifeRegen(), "no Germination mod -> config is inert")
	end)

	it("config: '# of Germination Stacks' is ifMult-gated with the max-4 hint", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "multiplierGerminationStacks".-end },')
		assert.is_not_nil(entry, "multiplierGerminationStacks config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true))
		assert.is_truthy(entry:find('ifMult = "GerminationStacks"', 1, true),
			"must be visibility-gated on the GerminationStacks multiplier being referenced (Throne pattern)")
		assert.is_truthy(entry:find("max 4", 1, true), "label must carry the cap hint '(max 4)'")
		assert.is_truthy(entry:find('NewMod("Multiplier:GerminationStacks", "BASE", val, "Config"', 1, true),
			"apply must set Multiplier:GerminationStacks")
	end)

	it("game-file: Roots of Vithrasil carries both 'per stack of Germination' mods", function()
		local src = readFile("Data/Uniques/uniques_1_4.json")
		assert.is_not_nil(src, "must read Data/Uniques/uniques_1_4.json")
		assert.is_truthy(src:find("Roots of Vithrasil", 1, true), "Roots of Vithrasil unique must be present")
		assert.is_truthy(src:find("Projectiles with Spirit Thorns per stack of Germination", 1, true),
			"must grant '+1 Projectiles with Spirit Thorns per stack of Germination'")
		assert.is_truthy(src:find("Health Regen per stack of Germination", 1, true),
			"must grant '+(20-26) Health Regen per stack of Germination'")
	end)

	it("ModCache: the two stale FLAT germination rows are removed (live parse owns them)", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		assert.is_falsy(src:find("per stack of Germination", 1, true),
			"no stale flat-baked Germination row may shadow the live parser")
	end)
end)
