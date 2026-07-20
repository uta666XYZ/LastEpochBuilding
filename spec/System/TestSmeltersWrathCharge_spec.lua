-- @leb-regression-guard: smelters-wrath-max-charge-more
-- (residual ~8%, an ungrounded open item documented in REGRESSION_GUARDS.md).
-- See REGRESSION_GUARDS.md "smelters-wrath-max-charge-more".
-- Validation provenance is retained in maintainer notes.

local function buildXML(mainSocketGroup)
	return ([[<?xml version="1.0" encoding="UTF-8"?>
<LastEpochBuilding>
	<Build level="100" targetVersion="1_4" pantheonMajorGod="None" bandit="None" className="Sentinel" ascendClassName="Forge Guard" characterLevelAutoMode="false" mainSocketGroup="%MSG%" viewMode="SKILLS" pantheonMinorGod="None"></Build>
	<Import/>
	<Calcs/>
	<Skills sortGemsByDPSField="CombinedDPS" activeSkillSet="1" sortGemsByDPS="true" defaultGemQuality="0" defaultGemLevel="normalMaximum" showSupportGemTypes="ALL" showAltQualityGems="false">
		<SkillSet id="1">
			<Skill skillId="SmeltersWrath" slot="Skill 1" mainActiveSkill="1" includeInFullDPS="false" index="1" enabled="true" mainActiveSkillCalcs="1"/>
			<Skill skillId="ForgeStrike" slot="Skill 2" mainActiveSkill="1" includeInFullDPS="false" index="2" enabled="true" mainActiveSkillCalcs="1"/>
		</SkillSet>
	</Skills>
	<Tree activeSpec="1">
		<Spec ascendClassId="1" nodes="ForgeGuard#1,Sentinel#1" treeVersion="1_4" classId="3"/>
	</Tree>
	<Items activeItemSet="1"><ItemSet useSecondWeaponSet="false" id="1"/></Items>
	<Config/>
</LastEpochBuilding>
]]):gsub("%%MSG%%", tostring(mainSocketGroup))
end

describe("SmeltersWrathCharge", function()
	local function readFile(path)
		local f = io.open(path, "r") or io.open("src/" .. path, "r") or io.open("../src/" .. path, "r")
		if not f then return nil end
		local s = f:read("*a"); f:close()
		return s
	end

	-- Load the synthetic build, optionally override the charge-seconds config,
	-- and return the main skill's More("Damage") on the active skill cfg.
	local function moreDamage(mainSocketGroup, chargeSeconds)
		loadBuildFromXML(buildXML(mainSocketGroup), "SmeltersWrathCharge synth")
		if chargeSeconds ~= nil then
			build.configTab.input["multiplierSmeltersWrathChargeSeconds"] = chargeSeconds
			build.configTab:BuildModList()
		end
		runCallback("OnFrame")
		local skill = build.calcsTab.mainEnv.player.mainSkill
		return skill.skillModList:More(skill.skillCfg, "Damage"), skill.activeEffect.grantedEffect.name
	end

	describe("intrinsic charge ramp (build integration, synthetic Forge Guard lv100)", function()
		before_each(function() newBuild() end)

		-- NOTE: the config is type="count"; a value of 0 is treated as blank/unset
		-- (so CalcOffence falls back to the max-charge default). The ramp is therefore
		-- proven base-independently via the ratio between two positive charge values.
		it("charge ramp is +50% per second (=> +100% at the 2.0s max), default = max", function()
			local m1, name = moreDamage(1, 1) -- 1s -> +50%
			assert.are.equal("Smelter's Wrath", name)
			local m2 = moreDamage(1, 2)        -- 2s -> +100%
			local mUnset = moreDamage(1, nil)  -- default
			local m4 = moreDamage(1, 4)        -- over-charge
			-- (1 + 2*0.5) / (1 + 1*0.5) = 2.0 / 1.5 = 4/3, independent of the build's
			-- other Damage MORE -- proves the +50%/s rate, hence +100% at 2s.
			assert.near(4 / 3, m2 / m1, 0.001, "ramp must be +50% per charge-second")
			assert.near(m2, mUnset, 0.001, "unset charge must model the 2.0s maximum (default)")
			assert.near(m2, m4, 0.001, "over-charge config must clamp to the 2.0s max, not exceed it")
		end)

		it("absolute magnitude: clean synthetic build => max charge is exactly x2.0 (+100%)", function()
			-- the control skill (Forge Strike, no charge ramp) reveals the build's
			-- base Damage MORE; a clean synthetic Forge Guard has none (== 1.0).
			local baseMore, ctrlName = moreDamage(2, nil)
			assert.are.equal("Forge Strike", ctrlName)
			assert.near(1.0, baseMore, 0.001, "synthetic build must carry no other Damage MORE")
			assert.near(2.0, moreDamage(1, nil), 0.001,
				"Smelter's Wrath at max charge = base x2.0 = the datamined +100% more")
		end)

		it("scope control: the Smelter charge config does NOT change a non-Smelter skill", function()
			-- mainSocketGroup 2 = Forge Strike; the charge ramp must not leak onto it
			local f0 = moreDamage(2, nil)
			local f2 = moreDamage(2, 2) -- Smelter charge cfg set, but evaluating Forge Strike
			assert.near(f0, f2, 0.001,
				"the Smelter's Wrath charge config must not change a different skill's MORE")
			assert.near(1.0, f0, 0.001, "the control skill has no charge MORE")
		end)
	end)

	describe("source contract", function()
		it("CalcOffence carries the smelters-wrath-max-charge-more guard, gated on the skill", function()
			local src = readFile("Modules/CalcOffence.lua")
			assert.is_not_nil(src, "must read Modules/CalcOffence.lua")
			assert.is_truthy(src:find("@leb%-regression%-guard: smelters%-wrath%-max%-charge%-more"),
				"CalcOffence.lua must carry the guard marker")
			assert.is_truthy(src:find('grantedEffect.name == "Smelter\'s Wrath"', 1, true),
				"the charge MORE must be gated on the Smelter's Wrath skill name")
			assert.is_truthy(src:find("Multiplier:SmeltersWrathChargeSeconds", 1, true),
				"the MORE must be driven by the SmeltersWrathChargeSeconds multiplier")
			assert.is_truthy(src:find("maxChargeSeconds = 2.0", 1, true),
				"the datamined maxDuration (2.0s) default must be present")
		end)

		it("ConfigOptions declares multiplierSmeltersWrathChargeSeconds (capped at 2)", function()
			local cfg = readFile("Modules/ConfigOptions.lua")
			assert.is_not_nil(cfg, "must read Modules/ConfigOptions.lua")
			local entry = cfg:match('{ var = "multiplierSmeltersWrathChargeSeconds".-end },')
			assert.is_not_nil(entry, "the multiplierSmeltersWrathChargeSeconds config entry must exist")
			assert.is_truthy(entry:find('ifMult = "SmeltersWrathChargeSeconds"', 1, true),
				"must be visibility-gated on the multiplier being referenced")
			assert.is_truthy(entry:find("m_min(val, 2)", 1, true),
				"apply must cap the config at the 2.0s maximum")
		end)
	end)
end)
