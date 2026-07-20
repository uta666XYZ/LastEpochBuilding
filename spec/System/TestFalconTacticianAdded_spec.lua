-- @leb-regression-guard:falcon-tactician-flat-added
-- See REGRESSION_GUARDS.md "falcon-tactician-flat-added".
-- Validation provenance is retained in maintainer notes.

local function falconAdd(list)
	assert.is_table(list, "the node stat must parse to a mod list")
	assert.are.equals("MinionModifier", list[1].name)
	assert.are.equals("LIST", list[1].type)
	assert.are.equals("RogueFalcon", list[1].value.minionTypes[1])
	return list[1].value.mod
end

describe("FalconTacticianAdded #falcon parser contract", function()

	it("melee line routes a RogueFalcon-scoped Melee (512) flat Damage BASE", function()
		local m = falconAdd(modLib.parseMod("+3 Melee Damage For Falcon"))
		assert.are.equals("Damage", m.name)
		assert.are.equals("BASE", m.type)
		assert.are.equals(3, m.value)
		assert.are.equals(512, m.keywordFlags)
	end)

	it("throwing line routes a RogueFalcon-scoped Throwing (1024) flat Damage BASE", function()
		local m = falconAdd(modLib.parseMod("+3 Throwing Damage For Falcon"))
		assert.are.equals("Damage", m.name)
		assert.are.equals("BASE", m.type)
		assert.are.equals(3, m.value)
		assert.are.equals(1024, m.keywordFlags)
	end)

	it("both lines are fully consumed (nil extra so PassiveTree keeps the mod)", function()
		local _, meleeExtra = modLib.parseMod("+3 Melee Damage For Falcon")
		local _, throwExtra = modLib.parseMod("+3 Throwing Damage For Falcon")
		assert.is_nil(meleeExtra, "melee extra must be nil -- a non-empty residue is dropped at the tree gate")
		assert.is_nil(throwExtra, "throwing extra must be nil -- a non-empty residue is dropped at the tree gate")
	end)

	it("the live parser rule covers non-cached point values too", function()
		-- The +3 strings hit ModCache; other magnitudes exercise the ModParser rule
		-- directly (cache miss) -- both paths must produce the same scoped shape.
		local m = falconAdd(modLib.parseMod("+6 Melee Damage For Falcon"))
		assert.are.equals(6, m.value)
		assert.are.equals(512, m.keywordFlags)
	end)

	it("SCOPED: the Ballista sibling stays unwired (capture-gated)", function()
		-- "+3 Bow Damage For Ballista" is the same node's grant to RogueBallista, but the
		-- Ballista per-hit MATCH was established without isolating it -- wiring it blind
		-- could over-correct a validated skill. It must stay a residue no-op until a
		-- decomposed Ballista capture grounds it (then flip this case with the fix).
		local list, extra = modLib.parseMod("+3 Bow Damage For Ballista")
		local isWired = list and list[1] and list[1].name == "MinionModifier"
		assert.is_false(not not isWired, "Bow Damage For Ballista must not be MinionModifier-wired yet")
		assert.is_not_nil(extra, "Bow Damage For Ballista must remain residue-dropped (inert) until grounded")
	end)
end)
