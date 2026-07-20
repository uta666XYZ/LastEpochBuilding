-- @leb-regression-guard: smelters-wrath-charge-scaling-nodes
-- See REGRESSION_GUARDS.md "smelters-wrath-charge-scaling-nodes".
-- Validation provenance is retained in maintainer notes.

describe("SmeltersWrathChargeNodes", function()
	local function readFile(path)
		local f = io.open(path, "r") or io.open("src/" .. path, "r") or io.open("../src/" .. path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	-- find a tag {type=..,var=..} on a parsed mod
	local function tag(m, ttype, var)
		for _, t in ipairs(m) do
			if type(t) == "table" and t.type == ttype and (var == nil or t.var == var) then return t end
		end
		return nil
	end

	describe("ModParser: charge-scaling node forms parse to MORE (no dropped residue)", function()
		it("'15% More Damage Per Second' => Damage MORE 15 x Channelling x ChannellingSeconds", function()
			local mods, extra = modLib.parseMod("15% More Damage Per Second")
			assert.is_nil(extra, "the whole line must be consumed (no residue => not dropped)")
			assert.are.equal(1, #mods)
			assert.are.equal("Damage", mods[1].name)
			assert.are.equal("MORE", mods[1].type)
			assert.are.equal(15, mods[1].value)
			assert.is_not_nil(tag(mods[1], "Condition", "Channelling"))
			assert.is_not_nil(tag(mods[1], "Multiplier", "ChannellingSeconds"))
		end)

		it("'+2% Melee Damage per Second' => Damage MORE 2 (Melee) x Channelling x ChannellingSeconds", function()
			local mods, extra = modLib.parseMod("+2% Melee Damage per Second")
			assert.is_nil(extra)
			assert.are.equal("Damage", mods[1].name)
			assert.are.equal("MORE", mods[1].type)
			assert.are.equal(2, mods[1].value)
			assert.are.equal(KeywordFlag.Melee, mods[1].keywordFlags)
			assert.is_not_nil(tag(mods[1], "Multiplier", "ChannellingSeconds"))
		end)

		it("'+2% Fire Damage per Second' => FireDamage MORE 2 x Channelling x ChannellingSeconds", function()
			local mods, extra = modLib.parseMod("+2% Fire Damage per Second")
			assert.is_nil(extra)
			assert.are.equal("FireDamage", mods[1].name)
			assert.are.equal("MORE", mods[1].type)
			assert.are.equal(2, mods[1].value)
			assert.is_not_nil(tag(mods[1], "Multiplier", "ChannellingSeconds"))
		end)

		it("'+50% Damage At Full Charge' => Damage MORE 50 x FullyCharged", function()
			local mods, extra = modLib.parseMod("+50% Damage At Full Charge")
			assert.is_nil(extra)
			assert.are.equal("Damage", mods[1].name)
			assert.are.equal("MORE", mods[1].type)
			assert.are.equal(50, mods[1].value)
			assert.is_not_nil(tag(mods[1], "Condition", "FullyCharged"))
		end)

		it("'100% More Crit Chance At Full Charge' => CritChance MORE 100 x FullyCharged", function()
			local mods, extra = modLib.parseMod("100% More Crit Chance At Full Charge")
			assert.is_nil(extra)
			assert.are.equal("CritChance", mods[1].name)
			assert.are.equal("MORE", mods[1].type)
			assert.are.equal(100, mods[1].value)
			assert.is_not_nil(tag(mods[1], "Condition", "FullyCharged"))
		end)
	end)

	describe("ModCache: stale flat-MORE-plus-residue rows removed (re-parse live)", function()
		it("none of the charge-scaling node strings remain baked with their dropped residue", function()
			local cache = readFile("Data/ModCache.lua")
			assert.is_not_nil(cache, "must read Data/ModCache.lua")
			for _, key in ipairs({
				"15% More Damage Per Second",
				"+2% Melee Damage per Second",
				"+2% Fire Damage per Second",
				"+50% Damage At Full Charge",
				"100% More Crit Chance At Full Charge",
			}) do
				assert.is_falsy(cache:find('c["' .. key .. '"]', 1, true),
					"stale ModCache row must be removed so '" .. key .. "' re-parses live: " .. key)
			end
		end)
	end)

	describe("source contract", function()
		it("ModParser carries the guard + the new full-line handlers", function()
			local src = readFile("Modules/ModParser.lua")
			assert.is_not_nil(src)
			assert.is_truthy(src:find("@leb%-regression%-guard:smelters%-wrath%-charge%-scaling%-nodes"))
			assert.is_truthy(src:find("more damage per second", 1, true))
			assert.is_truthy(src:find("damage at full charge", 1, true))
		end)

		it("CalcOffence publishes the charge=channel state scoped to the skill's modList", function()
			local src = readFile("Modules/CalcOffence.lua")
			assert.is_not_nil(src)
			assert.is_truthy(src:find("@leb%-regression%-guard:smelters%-wrath%-charge%-scaling%-nodes"))
			assert.is_truthy(src:find('skillModList:NewMod("Multiplier:ChannellingSeconds"', 1, true),
				"ChannellingSeconds must be set on the skill modList (scoped), not the global modDB")
			assert.is_truthy(src:find('skillModList:NewMod("Condition:Channelling"', 1, true))
			assert.is_truthy(src:find('skillModList:NewMod("Condition:FullyCharged"', 1, true))
		end)
	end)
end)
