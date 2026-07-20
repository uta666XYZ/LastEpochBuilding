-- @leb-regression-guard: firebrand-per-stack-tree-damage
-- Firebrand specialization-tree (treeId f1b4d, Spellblade) CONTINUOUS per-stack damage
-- nodes were silently dropped: their "...Per Stack" stat strings had no ModParser handler,
-- so the allocated nodes produced ZERO damage mods (confirmed on 4guanghuan_LEB: f1b4d
-- allocated [14,9,7,8,19,18,20,23,27,10] yet 0 Tree:f1b4d-* mods).
--
-- Game source (TreeData/1_4/tree_1.json):
--   f1b4d-2  Charring        stats ["+4% Melee Damage Per Stack"]  (maxPoints 3)
--   f1b4d-18 Ardent Branding stats ["+3 Maximum Stacks","+3% Damage Per Stack","-20% Attack Speed"]
--   Descriptions: "Firebrand deals more ... per stack of Firebrand (multiplicative with other
--   modifiers)" -> CONTINUOUS per-live-stack MORE.
--
-- Fix = two sites:
--   a. Data/Global.lua LE_TREE_NODE_STAT_REWRITE node-id-keys f1b4d-2 / f1b4d-18 rewrite the
--      "...Damage Per Stack" line to append "per stack of Firebrand".
--   b. Modules/ModParser.lua modTagList ["per stack of firebrand"] attaches
--      Multiplier:FirebrandStack (CalcOffence sets it; default 4, "# of Firebrand Stacks" config).
-- NODE-ID-KEYED is load-bearing: f1b4d-7 Incineration "+12% Damage Per Stack" is the IDENTICAL
-- text but a CONSUMED-stack proc ("Other Melee Consumes Stacks") and must NOT be wired.
-- State-matched proof (4guanghuan_LEB save _175002_01, Ardent Branding 1pt allocated, default 4
-- stacks): per-type pre-mit rose ~+11.7% (3% x 4 = +12% MORE) uniformly on phys/fire/cold.
-- Max-stack modeling (Wildfire/Ardent Branding "+X Maximum Stacks" -> raise FirebrandStack above 4)
-- is a SEPARATE follow-up. See REGRESSION_GUARDS.md "firebrand-per-stack-tree-damage".

describe("FirebrandTreePerStackDamage", function()
	local function readFile(path)
		local f = io.open(path, "r") or io.open("src/" .. path, "r") or io.open("../src/" .. path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	local function tagHasFirebrandStack(mod)
		for _, t in ipairs(mod) do
			if type(t) == "table" and t.type == "Multiplier" and t.var == "FirebrandStack" then
				return true
			end
		end
		return false
	end

	describe("ModParser handler", function()
		it("'X% Damage per stack of Firebrand' parses to a Damage mod tagged Multiplier:FirebrandStack", function()
			local mods = modLib.parseMod("3% Damage per stack of Firebrand")
			assert.is_not_nil(mods, "must parse")
			local m = mods[1]
			assert.is_not_nil(m, "must yield a mod")
			assert.are.equal("Damage", m.name)
			assert.are.equal(3, m.value)
			assert.is_true(tagHasFirebrandStack(m),
				"the mod must carry a Multiplier:FirebrandStack tag")
		end)

		it("'X% Melee Damage per stack of Firebrand' (Charring) tags FirebrandStack on Damage+Melee", function()
			local mods = modLib.parseMod("4% Melee Damage per stack of Firebrand")
			assert.is_not_nil(mods and mods[1], "must parse Charring form")
			assert.are.equal("Damage", mods[1].name)
			assert.is_true(tagHasFirebrandStack(mods[1]), "must tag FirebrandStack")
		end)
	end)

	describe("Global.lua node-keyed rewrites", function()
		local rw = LE_TREE_NODE_STAT_REWRITE
		it("rewrites f1b4d-2 (Charring) and f1b4d-18 (Ardent Branding) Damage-Per-Stack lines", function()
			assert.is_not_nil(rw, "LE_TREE_NODE_STAT_REWRITE must exist")
			assert.is_not_nil(rw["f1b4d-2"], "Charring must have a rewrite")
			assert.is_not_nil(rw["f1b4d-18"], "Ardent Branding must have a rewrite")
			-- applying f1b4d-18's rewrite to its real stat must append "per stack of Firebrand"
			local s = "+3% Damage Per Stack"
			for _, r in ipairs(rw["f1b4d-18"]) do s = s:gsub(r.pat, r.repl) end
			assert.is_truthy(s:lower():find("per stack of firebrand", 1, true),
				"f1b4d-18 rewrite must append 'per stack of Firebrand'")
		end)

		it("does NOT rewrite f1b4d-7 Incineration (consumed-stack, identical text)", function()
			assert.is_nil(rw["f1b4d-7"],
				"f1b4d-7 Incineration must NOT be wired (consumed-stack proc, not continuous)")
		end)
	end)

	describe("max-stacks modeling (firebrand-tree-max-stacks)", function()
		it("'X Firebrand Maximum Stacks' parses to BASE FirebrandMaxStacks", function()
			local mods = modLib.parseMod("3 Firebrand Maximum Stacks")
			assert.is_not_nil(mods and mods[1], "must parse")
			assert.are.equal("FirebrandMaxStacks", mods[1].name)
			assert.are.equal("BASE", mods[1].type)
			assert.are.equal(3, mods[1].value)
		end)
		it("f1b4d-9 (Wildfire) and f1b4d-18 rewrite '+X Maximum Stacks' -> 'Firebrand Maximum Stacks'", function()
			local rw = LE_TREE_NODE_STAT_REWRITE
			assert.is_not_nil(rw["f1b4d-9"], "Wildfire must have a rewrite")
			local s = "+1 Maximum Stacks"
			for _, r in ipairs(rw["f1b4d-9"]) do s = s:gsub(r.pat, r.repl) end
			assert.is_truthy(s:lower():find("firebrand maximum stacks", 1, true),
				"f1b4d-9 must rewrite to 'Firebrand Maximum Stacks'")
			-- f1b4d-18 also carries the max-stacks rewrite (alongside its Damage-Per-Stack one)
			local s2 = "+3 Maximum Stacks"
			for _, r in ipairs(rw["f1b4d-18"]) do s2 = s2:gsub(r.pat, r.repl) end
			assert.is_truthy(s2:lower():find("firebrand maximum stacks", 1, true),
				"f1b4d-18 must also rewrite its Maximum Stacks line")
		end)
		it("CalcOffence raises baseMaxStacks by FirebrandMaxStacks (source contract)", function()
			local src = readFile("Modules/CalcOffence.lua")
			assert.is_not_nil(src)
			assert.is_truthy(src:find("@leb%-regression%-guard:firebrand%-tree%-max%-stacks"),
				"CalcOffence must carry the max-stacks guard marker")
			assert.is_truthy(src:find('4 + (skillModList:Sum("BASE", skillCfg, "FirebrandMaxStacks")', 1, true),
				"baseMaxStacks must add the FirebrandMaxStacks sum to the datamined base 4")
		end)
	end)

	describe("source contract", function()
		it("ModParser carries the handler + guard marker", function()
			local src = readFile("Modules/ModParser.lua")
			assert.is_not_nil(src)
			assert.is_truthy(src:find("@leb%-regression%-guard:firebrand%-per%-stack%-tree%-damage"),
				"ModParser must carry the guard marker")
			assert.is_truthy(src:find('%["per stack of firebrand"%]'),
				"ModParser must declare the 'per stack of firebrand' handler")
			assert.is_truthy(src:find('var = "FirebrandStack"', 1, true),
				"handler must attach Multiplier:FirebrandStack")
		end)
		it("Global.lua carries the rewrite + guard marker", function()
			local src = readFile("Data/Global.lua")
			assert.is_not_nil(src)
			assert.is_truthy(src:find("@leb%-regression%-guard:firebrand%-per%-stack%-tree%-damage"),
				"Global.lua must carry the guard marker")
			assert.is_truthy(src:find('%["f1b4d%-18"%]'), "Global.lua must key f1b4d-18")
			assert.is_truthy(src:find('%["f1b4d%-2"%]'), "Global.lua must key f1b4d-2")
		end)
	end)
end)
