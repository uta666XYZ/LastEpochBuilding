-- @leb-regression-guard:raptor-phys-to-fire
-- See REGRESSION_GUARDS.md "raptor-phys-to-fire".
-- Validation provenance is retained in maintainer notes.

local function buildXML(mainSocketGroup, raptorNodes)
	return ([[<?xml version="1.0" encoding="UTF-8"?>
<LastEpochBuilding>
	<Build level="100" targetVersion="1_4" pantheonMajorGod="None" bandit="None" className="Primalist" ascendClassName="Beastmaster" characterLevelAutoMode="false" mainSocketGroup="%MSG%" viewMode="SKILLS" pantheonMinorGod="None"></Build>
	<Import/>
	<Calcs/>
	<Skills sortGemsByDPSField="CombinedDPS" activeSkillSet="1" sortGemsByDPS="true" defaultGemQuality="0" defaultGemLevel="normalMaximum" showSupportGemTypes="ALL" showAltQualityGems="false">
		<SkillSet id="1">
			<Skill skillId="SummonScorpion" slot="Skill 1" mainActiveSkill="1" includeInFullDPS="false" index="1" enabled="true" mainActiveSkillCalcs="1"/>
			<Skill skillId="SummonRaptor" slot="Skill 2" mainActiveSkill="1" includeInFullDPS="false" index="2" enabled="true" mainActiveSkillCalcs="1"/>
		</SkillSet>
	</Skills>
	<Tree activeSpec="1">
		<Spec ascendClassId="1" nodes="Beastmaster#1,Primalist#1,%NODES%" treeVersion="1_4" classId="0"/>
	</Tree>
	<Items activeItemSet="1"><ItemSet useSecondWeaponSet="false" id="1"/></Items>
	<Config/>
</LastEpochBuilding>
]]):gsub("%%MSG%%", tostring(mainSocketGroup)):gsub("%%NODES%%", raptorNodes)
end

-- Raptor specialization path that reaches srtor-9 (mirrors the user build).
local SRTOR_WITH_9    = "srtor-0#1,srtor-2#4,srtor-3#1,srtor-7#1,srtor-8#3,srtor-9#1"
local SRTOR_WITHOUT_9 = "srtor-0#1,srtor-2#4,srtor-3#1,srtor-7#1,srtor-8#3"

local function baseOf(output, t) return output[t .. "DamageBase"] or 0 end

describe("RaptorPhysToFire parse contract", function()
	it("'100% Base Melee Damage -> Fire' -> PhysicalDamageConvertToFire BASE 100, residue-free", function()
		local mods, extra = modLib.parseMod("100% Base Melee Damage -> Fire")
		assert.is_true(extra == nil or extra == "", "must parse residue-free")
		assert.are.equals(1, #mods)
		assert.are.equals("PhysicalDamageConvertToFire", mods[1].name)
		assert.are.equals("BASE", mods[1].type)
		assert.are.equals(100, mods[1].value)
	end)

	it("the rate is value-faithful (50% variant scales, type follows the arrow)", function()
		local mods = modLib.parseMod("50% Base Melee Damage -> Cold")
		assert.are.equals("PhysicalDamageConvertToCold", mods[1].name)
		assert.are.equals(50, mods[1].value)
	end)
end)

describe("RaptorPhysToFire build integration (synthetic Beastmaster lv100)", function()
	before_each(function() newBuild() end)

	local function load(mainSocketGroup, raptorNodes)
		loadBuildFromXML(buildXML(mainSocketGroup, raptorNodes), "RaptorPhysToFire synth")
		runCallback("OnFrame")
		local env = build.calcsTab.mainEnv
		assert.is_table(env.player.mainSkill.minion, "summon skill must produce a minion")
		return env, env.player.mainSkill.minion
	end

	it("srtor-9 wiring is intact (node id, name, and the conversion stat string)", function()
		local env = load(2, SRTOR_WITH_9)
		local node = env.allocNodes and env.allocNodes["srtor-9"]
		assert.is_table(node, "srtor-9 must be allocated")
		assert.are.equals("Volcanic Adaptation", node.dn or node.name)
		local hasConvStat = false
		for _, s in ipairs(node.stats or {}) do
			if s == "100% Base Melee Damage -> Fire" then hasConvStat = true end
		end
		assert.is_true(hasConvStat, "srtor-9 must carry the '100% Base Melee Damage -> Fire' stat")
	end)

	it("WITH srtor-9: raptor melee base is 100% FIRE (no physical)", function()
		local env, minion = load(2, SRTOR_WITH_9)
		assert.are.equals("PrimalRaptor", minion.minionData.name)
		local cfg = minion.mainSkill.skillCfg
		assert.are.equals(100, minion.modDB:Sum("BASE", cfg, "PhysicalDamageConvertToFire"),
			"the srtor-9 conversion must reach the raptor minion's modDB")
		assert.are.equals(0, baseOf(minion.output, "Physical"), "no physical base survives the 100% conversion")
		assert.is_true(baseOf(minion.output, "Fire") > 0, "the base melee is retyped to fire")
	end)

	it("WITHOUT srtor-9 (node-gated control): raptor melee base stays PHYSICAL", function()
		local env, minion = load(2, SRTOR_WITHOUT_9)
		assert.are.equals("PrimalRaptor", minion.minionData.name)
		local cfg = minion.mainSkill.skillCfg
		assert.are.equals(0, minion.modDB:Sum("BASE", cfg, "PhysicalDamageConvertToFire"),
			"with no Dragon Raptor node, no conversion is present")
		assert.is_true(baseOf(minion.output, "Physical") > 0, "base melee stays physical")
		assert.are.equals(0, baseOf(minion.output, "Fire"), "no fire without the node")
	end)

	it("sibling Scorpion in the SAME build (srtor-9 allocated) stays PHYSICAL (scope control)", function()
		-- mainSocketGroup 1 = SummonScorpion; the Dragon Raptor node is still
		-- allocated on the SummonRaptor tree, but its conversion is SummonRaptor-
		-- scoped and must NOT leak onto the scorpion.
		local env, minion = load(1, SRTOR_WITH_9)
		assert.are.equals("PrimalScorpion", minion.minionData.name)
		local cfg = minion.mainSkill.skillCfg
		assert.are.equals(0, minion.modDB:Sum("BASE", cfg, "PhysicalDamageConvertToFire"),
			"the raptor's conversion must not reach the scorpion")
		assert.is_true(baseOf(minion.output, "Physical") > 0, "scorpion melee stays physical")
		assert.are.equals(0, baseOf(minion.output, "Fire"), "scorpion gains no fire from the raptor node")
	end)
end)
