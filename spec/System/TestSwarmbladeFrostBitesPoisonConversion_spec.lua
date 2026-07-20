-- @leb-regression-guard:frost-bites-poison-base-to-cold
-- See REGRESSION_GUARDS.md > "frost-bites-poison-base-to-cold".
-- Validation provenance is retained in maintainer notes.

-- Process a REAL tree node at a given rank and hand back its modList.
-- Snapshots/restores node.alloc so the shared tree object stays pristine.
local function processRealNode(nodeId, rank)
	local node = build.spec.tree.nodes[nodeId]
	assert.is_not_nil(node, "tree node " .. nodeId .. " must exist in 1_4 tree data")
	local origAlloc = node.alloc
	node.alloc = rank
	build.spec.tree:ProcessStats(node)
	local mods = node.modList
	node.alloc = origAlloc
	if type(origAlloc) == "number" then
		build.spec.tree:ProcessStats(node)
	end
	return mods
end

local function sumConvert(mods, src, dst)
	local total = 0
	for _, m in ipairs(mods) do
		if m.name == (src .. "DamageConvertTo" .. dst) and m.type == "BASE" then
			total = total + (m.value or 0)
		end
	end
	return total
end

describe("SwarmbladeFrostBitesPoisonConversion", function()
	before_each(function()
		newBuild()
	end)

	it("sbf4m-10 carries BOTH the physical and poison base->cold stats (live tree data)", function()
		local node = build.spec.tree.nodes["sbf4m-10"]
		assert.is_not_nil(node, "Frost Bites node sbf4m-10 must exist in 1_4 tree data")
		assert.are.equals("Frost Bites", node.name)
		local hasPhys, hasPoison = false, false
		for _, s in ipairs(node.stats or {}) do
			if s:gsub("%s+", " "):match("Base Physical Damage %-> Cold") then hasPhys = true end
			if s:gsub("%s+", " "):match("Base Poison Damage %-> Cold") then hasPoison = true end
		end
		assert.is_true(hasPhys, "Frost Bites must keep its existing Base Physical Damage -> Cold stat")
		assert.is_true(hasPoison,
			"Frost Bites must convert the poison half of the form base too (Base Poison Damage -> Cold)")
	end)

	it("Frost Bites emits PoisonDamageConvertToCold = 100 alongside PhysicalDamageConvertToCold (live tree data)", function()
		local mods = processRealNode("sbf4m-10", 1)
		assert.are.equals(100, sumConvert(mods, "Physical", "Cold"),
			"the physical base must still convert to cold (no regression)")
		assert.are.equals(100, sumConvert(mods, "Poison", "Cold"),
			"the poison base must convert to cold so Swarm Strike shows 0% poison (matches in-game)")
	end)
end)
