-- @leb-regression-guard:truesight-glass-super-crit
-- Forge Guard/Sorcerer). See REGRESSION_GUARDS.md "truesight-glass-super-crit".
-- Validation provenance is retained in maintainer notes.

local function buildXML(mainSocketGroup)
	return ([[<?xml version="1.0" encoding="UTF-8"?>
<LastEpochBuilding>
	<Build level="100" targetVersion="1_4" pantheonMajorGod="None" bandit="None" className="Mage" ascendClassName="Sorcerer" characterLevelAutoMode="false" mainSocketGroup="%MSG%" viewMode="SKILLS" pantheonMinorGod="None"></Build>
	<Import/>
	<Calcs/>
	<Skills sortGemsByDPSField="CombinedDPS" activeSkillSet="1" sortGemsByDPS="true" defaultGemQuality="0" defaultGemLevel="normalMaximum" showSupportGemTypes="ALL" showAltQualityGems="false">
		<SkillSet id="1">
			<Skill skillId="Fireball" slot="Skill 1" mainActiveSkill="1" includeInFullDPS="false" index="1" enabled="true" mainActiveSkillCalcs="1"/>
		</SkillSet>
	</Skills>
	<Tree activeSpec="1">
		<Spec ascendClassId="1" nodes="Sorcerer#1,Mage#1" treeVersion="1_4" classId="1"/>
	</Tree>
	<Items activeItemSet="1"><ItemSet useSecondWeaponSet="false" id="1"/></Items>
	<Config/>
</LastEpochBuilding>
]]):gsub("%%MSG%%", tostring(mainSocketGroup))
end

local FLAG_LINE = "100% You can deal Super Critical Strikes"
local OVERCAP_CRIT = "5000% increased Critical Strike Chance" -- overcaps any positive base

describe("TruesightGlassSuperCrit", function()
	local function readSource(relPath)
		local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
		assert.is_not_nil(f, "must be able to open " .. relPath)
		local text = f:read("*a"); f:close()
		return text
	end

	-- Load synthetic Fireball build, apply customMods, return the main output table.
	local function measure(customMods)
		loadBuildFromXML(buildXML(1), "TruesightSuperCrit synth")
		build.configTab.input.customMods = customMods
		build.configTab:BuildModList()
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.calcsOutput
	end

	before_each(function() newBuild() end)

	describe("parser / grant", function()
		it("parses the Truesight Glass grant to a CanSuperCrit FLAG (ModCache row)", function()
			-- The exact item line short-circuits through the baked ModCache row.
			local modList = modLib.parseMod(FLAG_LINE)
			assert.is_not_nil(modList[1], "the grant must parse to a mod, not an empty list")
			assert.are.equal("CanSuperCrit", modList[1].name)
			assert.are.equal("FLAG", modList[1].type)
			assert.are.equal(true, modList[1].value)
		end)

		it("live specialModList parses the grant even without the value prefix", function()
			-- Regen-safe path: a variant not in ModCache must still parse via the
			-- specialModList pattern (so a re-baked ModCache stays correct).
			local modList = modLib.parseMod("You can deal Super Critical Strikes")
			assert.is_not_nil(modList[1], "live parser must recognise the bare grant")
			assert.are.equal("CanSuperCrit", modList[1].name)
			assert.are.equal("FLAG", modList[1].type)
		end)

		it("the flag reaches modDB from customMods", function()
			build.configTab.input.customMods = FLAG_LINE
			build.configTab:BuildModList()
			runCallback("OnFrame")
			assert.is_true(build.configTab.modList:Flag(nil, "CanSuperCrit"),
				"CanSuperCrit must be live in modDB when the grant is present")
		end)
	end)

	describe("gating (item-gated, no leak)", function()
		it("no super-crit without the grant, even when crit is overcapped", function()
			local o = measure(OVERCAP_CRIT)
			assert.is_true(o.CritChance >= 99.9, "crit must be (over)capped for this control")
			assert.is_true((o.SuperCritChance or 0) == 0,
				"SuperCritChance must stay 0 with no CanSuperCrit grant (no leak to other builds)")
		end)

		it("no super-crit with the grant but crit chance <= 100%", function()
			-- Fireball's small base crit (~5%) is well under 100%, so even with the
			-- grant the overflow gate is never crossed.
			local o = measure(FLAG_LINE)
			assert.is_true(o.PreEffectiveCritChance <= 100, "control: uncapped crit must be <= 100%")
			assert.is_true((o.SuperCritChance or 0) == 0,
				"SuperCritChance must stay 0 below 100% crit (overflow gate)")
		end)
	end)

	describe("effect (overcapped + granted)", function()
		it("super-crit activates and is capped at 40%", function()
			local o = measure(FLAG_LINE .. "\n" .. OVERCAP_CRIT)
			assert.is_true(o.SuperCritChance > 0, "super-crit must activate when overcapped + granted")
			assert.is_true(o.SuperCritChance <= 40.0001, "super-crit rate is capped at maxSuperCritChance = 40%")
			assert.near(40, o.SuperCritChance, 0.001, "5000% increased overcaps far past +140%, so rate hits the 40% cap")
		end)

		it("AverageHit gains exactly totalHitAvg x critChance x superCritChance x 3", function()
			local base = measure(OVERCAP_CRIT)                          -- overcapped, NO grant
			local sc   = measure(FLAG_LINE .. "\n" .. OVERCAP_CRIT)     -- overcapped, WITH grant
			-- Crit chance / non-crit hit are identical across the pair (the grant only
			-- adds super-crits), so the AverageHit delta must equal the folded bonus.
			local cc = sc.CritChance / 100
			local scFrac = sc.SuperCritChance / 100
			local expectedDelta = sc.NonCritAverageHit * cc * scFrac * 3
			local measuredDelta = sc.AverageHit - base.AverageHit
			assert.is_true(expectedDelta > 0, "sanity: the folded bonus must be positive")
			assert.near(expectedDelta, measuredDelta, math.max(1, expectedDelta * 0.001),
				"AverageHit super-crit bonus must be totalHitAvg x critChance x superCritChance x 3")
			assert.is_true(sc.TotalDPS > base.TotalDPS,
				"TotalDPS must rise with super-crit active (real DPS impact, not display-only)")
		end)
	end)

	describe("source contract", function()
		it("ModParser registers the grant pattern and carries the guard", function()
			local src = readSource("Modules/ModParser.lua")
			assert.is_truthy(src:find("@leb%-regression%-guard:truesight%-glass%-super%-crit"),
				"ModParser must carry the guard marker")
			assert.is_truthy(src:find("you can deal super critical strikes", 1, true),
				"ModParser must register the super-crit grant pattern")
		end)

		it("CalcOffence gates the rate on the flag and the 100% overflow, capped at 0.4", function()
			local src = readSource("Modules/CalcOffence.lua")
			assert.is_truthy(src:find('skillModList:Flag(cfg, "CanSuperCrit") and preCapCritChance > 100', 1, true),
				"super-crit must be gated on CanSuperCrit AND uncapped crit > 100%")
			assert.is_truthy(src:find("m_min(preCapCritChance / 100 - 1, 0.4)", 1, true),
				"rate must be min(uncapped/100 - 1, 0.4) per datamine §32")
			assert.is_truthy(src:find("totalHitAvg %* %(output%.CritChance / 100%) %* superCritChance %* 3"),
				"AverageHit must fold in totalHitAvg x critChance x superCritChance x 3")
		end)
	end)
end)
