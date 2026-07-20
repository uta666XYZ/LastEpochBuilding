-- @leb-regression-guard:razorfall-umbral-blades-per-dex
-- Razorfall (uniques.json uniqueID 337) "+1 Umbral Blades per 20 Dexterity
-- thrown with Aerial Assault's Burst of Feathers". Aerial Assault's "Burst of
-- Feathers" node releases a burst of Umbral Blades on landing; Razorfall adds
-- one extra Umbral Blade per 20 Dexterity. The extra blades are Umbral Blades
-- (skills.json "Umbral Blades 1"), so the count scales the Umbral Blades
-- ProjectileCount by PerStat Dexterity/20 (continuous, per the project's
-- "per N stat" convention).
--
-- Before this fix the whole affix was a baked no-op ModCache row ({{}, ""}) --
-- a silent failure -- so the extra projectiles never reached the computed
-- skill. The DPS reach is DELIBERATELY gated behind the default-OFF config
-- "razorfallBurstOfFeathersBlades" (Condition:RazorfallBurstOfFeathers): the
-- single-target ProjectileCount -> dpsMultiplier fold (CalcOffence
-- SequentialProjectiles) is NOT capture-validated (the burst blades'
-- single-target hit fraction is assumed 100%, and the base burst count is a
-- separate unmodeled node supplied by the user). Default OFF => the parsed
-- per-Dex mod is inert and no SequentialProjectiles flag is set =>
-- corpus-neutral by construction.
-- See REGRESSION_GUARDS.md "razorfall-umbral-blades-per-dex".

describe("RazorfallUmbralBladesPerDex #skills", function()
	local RAZORFALL_MOD = "+1 Umbral Blades per 20 Dexterity thrown with Aerial Assault's Burst of Feathers"

	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	local function findTag(mod, tagType, key, keyVal)
		for _, tag in ipairs(mod) do
			if tag.type == tagType and (key == nil or tag[key] == keyVal) then
				return tag
			end
		end
		return nil
	end

	local function findMod(list, name)
		for _, m in ipairs(list) do
			if m.name == name then return m end
		end
		return nil
	end

	it("game-file: uniques.json carries the verbatim Razorfall affix (a rename/retune should fail loudly)", function()
		local src = readFile("Data/Uniques/uniques.json")
		assert.is_not_nil(src, "must read Data/Uniques/uniques.json")
		assert.is_truthy(src:find("Razorfall", 1, true), "the unique name must still be present")
		assert.is_truthy(src:find(RAZORFALL_MOD, 1, true),
			"the verbatim affix string the parser keys on must still be present")
	end)

	it("ModCache: the shadowing no-op stub row is removed so the live parser runs", function()
		local src = readFile("Data/ModCache.lua")
		assert.is_not_nil(src, "must read Data/ModCache.lua")
		assert.is_falsy(src:find('c%["%+1 Umbral Blades per 20 Dexterity'),
			"the baked no-op ModCache row must be deleted (it would shadow the specialModList rule)")
	end)

	it("parse contract: affix -> Multiplier:RazorfallEquipped + ProjectileCount BASE 1 (SkillName Umbral Blades, PerStat Dex/20, Condition), no residue", function()
		local list, extra = modLib.parseMod(RAZORFALL_MOD)
		assert.is_not_nil(list, "must parse to a mod list")
		assert.is_true(not extra or extra == "", "must leave no residue, got: " .. tostring(extra))
		assert.are.equal(2, #list, "must produce exactly the equipped-marker mod and the ProjectileCount mod")

		local marker = findMod(list, "Multiplier:RazorfallEquipped")
		assert.is_not_nil(marker, "must emit Multiplier:RazorfallEquipped to surface the config (ifMult gate)")
		assert.are.equal("BASE", marker.type)
		assert.are.equal(1, marker.value)

		local proj = findMod(list, "ProjectileCount")
		assert.is_not_nil(proj, "must emit a ProjectileCount mod")
		assert.are.equal("BASE", proj.type)
		assert.are.equal(1, proj.value, "the '+1' Umbral Blade base coefficient")
		assert.is_not_nil(findTag(proj, "SkillName", "skillName", "Umbral Blades"),
			"ProjectileCount must be scoped to the Umbral Blades skill")
		local perStat = findTag(proj, "PerStat")
		assert.is_not_nil(perStat, "must carry a PerStat tag")
		assert.are.equal("Dexterity", perStat.stat, "per Dexterity")
		assert.are.equal(20, perStat.div, "per 20 Dexterity")
		assert.is_not_nil(findTag(proj, "Condition", "var", "RazorfallBurstOfFeathers"),
			"the per-Dex ProjectileCount must be gated on Condition:RazorfallBurstOfFeathers (default OFF)")
	end)

	it("behaviour: ProjectileCount is inert by default and scales as Dex/20 for Umbral Blades only when the condition is set", function()
		local ubCfg = { skillName = "Umbral Blades" }
		local otherCfg = { skillName = "Shadow Cascade" }

		-- default: condition unset -> the per-Dex mod contributes nothing (corpus-neutral)
		local dbOff = new("ModDB")
		dbOff.actor = { modDB = dbOff, output = { Dexterity = 260 } }
		dbOff:AddList(modLib.parseMod(RAZORFALL_MOD))
		assert.are.equal(0, dbOff:Sum("BASE", ubCfg, "ProjectileCount"),
			"with the config OFF (no condition) Razorfall must add 0 projectiles -> inert")

		-- config on: condition set -> 1 x (Dex/20) continuous
		local dbOn = new("ModDB")
		dbOn.actor = { modDB = dbOn, output = { Dexterity = 260 } }
		dbOn:AddList(modLib.parseMod(RAZORFALL_MOD))
		dbOn:NewMod("Condition:RazorfallBurstOfFeathers", "FLAG", true, "test")
		assert.is_true(math.abs(dbOn:Sum("BASE", ubCfg, "ProjectileCount") - 13) < 1e-9,
			"260 Dexterity / 20 = 13 extra Umbral Blades (continuous per-N-stat)")
		-- scope: a different skill gets nothing even with the condition on
		assert.are.equal(0, dbOn:Sum("BASE", otherCfg, "ProjectileCount"),
			"the ProjectileCount is scoped to Umbral Blades, so other skills are unaffected")
	end)

	it("config: razorfallBurstOfFeathersBlades is a default-off count gated by ifMult, setting the condition + base ProjectileCount only when > 0", function()
		local src = readFile("Modules/ConfigOptions.lua")
		assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
		local entry = src:match('{ var = "razorfallBurstOfFeathersBlades".-end },')
		assert.is_not_nil(entry, "razorfallBurstOfFeathersBlades config entry must exist")
		assert.is_truthy(entry:find('type = "count"', 1, true), "must be a count option (default 0 = off)")
		assert.is_truthy(entry:find('ifMult = "RazorfallEquipped"', 1, true),
			"must be gated on the equipped marker so it only surfaces for a Razorfall build")
		assert.is_truthy(entry:find('if val > 0 then', 1, true),
			"the mechanic must only activate when the base burst count is > 0 (default 0 -> no-op)")
		assert.is_truthy(entry:find('NewMod("Condition:RazorfallBurstOfFeathers", "FLAG", true', 1, true),
			"enabling must set Condition:RazorfallBurstOfFeathers")
		assert.is_truthy(entry:find('NewMod("ProjectileCount", "BASE", val, "Config"', 1, true),
			"enabling must add the user-supplied base burst count as ProjectileCount")
	end)

	it("CalcOffence: SequentialProjectiles is enabled for Umbral Blades ONLY under the condition + a positive base count (guards zeroing, keeps corpus-neutral)", function()
		local src = readFile("Modules/CalcOffence.lua")
		assert.is_not_nil(src, "must read Modules/CalcOffence.lua")
		local guard = src:match('activeGrantedName == "Umbral Blades".-SequentialProjectiles", "FLAG", true, "Razorfall Burst of Feathers"%)')
		assert.is_not_nil(guard, "the Razorfall SequentialProjectiles enablement block must exist")
		assert.is_truthy(guard:find('Condition:RazorfallBurstOfFeathers', 1, true),
			"the enablement must be gated on the default-off Razorfall condition")
		assert.is_truthy(guard:find('Sum("BASE", skillCfg, "ProjectileCount") > 0', 1, true),
			"the enablement must require a positive ProjectileCount so the fold never multiplies by 0 (damage-zeroing guard)")
	end)
end)
