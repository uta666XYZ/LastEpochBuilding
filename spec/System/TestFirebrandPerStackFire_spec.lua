-- @leb-regression-guard: firebrand-per-stack-added-fire
-- See REGRESSION_GUARDS.md "firebrand-per-stack-added-fire".
-- Validation provenance is retained in maintainer notes.

local function buildXML(mainSocketGroup)
	return ([[<?xml version="1.0" encoding="UTF-8"?>
<LastEpochBuilding>
	<Build level="100" targetVersion="1_4" pantheonMajorGod="None" bandit="None" className="Mage" ascendClassName="Spellblade" characterLevelAutoMode="false" mainSocketGroup="%MSG%" viewMode="SKILLS" pantheonMinorGod="None"></Build>
	<Import/>
	<Calcs/>
	<Skills sortGemsByDPSField="CombinedDPS" activeSkillSet="1" sortGemsByDPS="true" defaultGemQuality="0" defaultGemLevel="normalMaximum" showSupportGemTypes="ALL" showAltQualityGems="false">
		<SkillSet id="1">
			<Skill skillId="Firebrand" slot="Skill 1" mainActiveSkill="1" includeInFullDPS="false" index="1" enabled="true" mainActiveSkillCalcs="1"/>
			<Skill skillId="Fireball" slot="Skill 2" mainActiveSkill="1" includeInFullDPS="false" index="2" enabled="true" mainActiveSkillCalcs="1"/>
		</SkillSet>
	</Skills>
	<Tree activeSpec="1">
		<Spec ascendClassId="2" nodes="Spellblade#1,Mage#1" treeVersion="1_4" classId="1"/>
	</Tree>
	<Items activeItemSet="1"><ItemSet useSecondWeaponSet="false" id="1"/></Items>
	<Config/>
</LastEpochBuilding>
]]):gsub("%%MSG%%", tostring(mainSocketGroup))
end

describe("FirebrandPerStackFire", function()
	local function readFile(path)
		local f = io.open(path, "r") or io.open("src/" .. path, "r") or io.open("../src/" .. path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	-- Load the synthetic build, optionally override the stack-count config, and
	-- return the main skill's added FireDamage BASE on its active-skill cfg. On a
	-- clean synthetic build (no items) the per-stack mod (5 x stacks) is the only
	-- FireDamage BASE source, so this isolates the mechanic.
	local function fireBase(mainSocketGroup, stacks)
		loadBuildFromXML(buildXML(mainSocketGroup), "FirebrandPerStackFire synth")
		if stacks ~= nil then
			build.configTab.input["multiplierFirebrandStack"] = stacks
			build.configTab:BuildModList()
		end
		runCallback("OnFrame")
		local skill = build.calcsTab.mainEnv.player.mainSkill
		return skill.skillModList:Sum("BASE", skill.skillCfg, "FireDamage"), skill.activeEffect.grantedEffect.name
	end

	describe("intrinsic per-stack added fire (synthetic Spellblade lv100)", function()
		before_each(function() newBuild() end)

		-- NOTE: the config is type="count"; a value of 0 reads as blank/unset (so
		-- CalcOffence falls back to the max-stack default). The +5/stack rate is
		-- therefore proven base-independently via the DELTA between two positive
		-- stack values, which cancels any other FireDamage base.
		it("each stack adds exactly +5 added melee fire damage; default = max (4)", function()
			local f1, name = fireBase(1, 1)
			assert.are.equal("Firebrand", name)
			local f2 = fireBase(1, 2)
			local f4 = fireBase(1, 4)
			local fUnset = fireBase(1, nil)
			assert.near(5, f2 - f1, 0.001, "each Firebrand stack must add +5 flat fire (datamine constant)")
			assert.near(15, f4 - f1, 0.001, "4 stacks - 1 stack = +15 flat fire")
			assert.near(f4, fUnset, 0.001, "unset stacks must model the 4-stack maximum (default)")
		end)

		it("absolute magnitude on a clean synthetic build: 4 stacks => 20 added fire", function()
			-- no items => the per-stack mod is the only FireDamage BASE => 4 x 5 = 20
			assert.near(20, fireBase(1, nil), 0.001,
				"max-stack default on a clean build = 4 x 5 = 20 added fire")
			assert.near(5, fireBase(1, 1), 0.001, "1 stack = 5 added fire")
		end)

		it("scope: the per-stack fire does NOT apply to a non-Firebrand skill", function()
			-- mainSocketGroup 2 = Fireball; the gate is name == \"Firebrand\"
			local g0, ctrlName = fireBase(2, nil)
			assert.are.equal("Fireball", ctrlName)
			assert.near(0, g0, 0.001, "Fireball must carry no Firebrand per-stack fire")
			local g4 = fireBase(2, 4) -- Firebrand stack cfg set, but evaluating Fireball
			assert.near(0, g4, 0.001,
				"the Firebrand stack config must not add fire to a different skill")
		end)
	end)

	describe("source contract", function()
		it("CalcOffence carries the firebrand-per-stack-added-fire guard, gated on the skill", function()
			local src = readFile("Modules/CalcOffence.lua")
			assert.is_not_nil(src, "must read Modules/CalcOffence.lua")
			assert.is_truthy(src:find("@leb%-regression%-guard: firebrand%-per%-stack%-added%-fire"),
				"CalcOffence.lua must carry the guard marker")
			assert.is_truthy(src:find('grantedEffect.name == "Firebrand"', 1, true),
				"the per-stack fire must be gated on the Firebrand skill name")
			assert.is_truthy(src:find("Multiplier:FirebrandStack", 1, true),
				"the added fire must be driven by the FirebrandStack multiplier")
			assert.is_truthy(src:find("baseMaxStacks = 4", 1, true),
				"the datamined base max stacks (4) default must be present")
		end)

		it("ConfigOptions declares multiplierFirebrandStack (publishes the multiplier)", function()
			local cfg = readFile("Modules/ConfigOptions.lua")
			assert.is_not_nil(cfg, "must read Modules/ConfigOptions.lua")
			local entry = cfg:match('{ var = "multiplierFirebrandStack".-end },')
			assert.is_not_nil(entry, "the multiplierFirebrandStack config entry must exist")
			assert.is_truthy(entry:find('ifMult = "FirebrandStack"', 1, true),
				"must be visibility-gated on the multiplier being referenced")
			assert.is_truthy(entry:find('Multiplier:FirebrandStack', 1, true),
				"apply must publish Multiplier:FirebrandStack")
		end)
	end)
end)
