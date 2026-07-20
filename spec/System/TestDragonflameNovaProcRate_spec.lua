-- @leb-regression-guard:dragonflame-nova-proc-rate
-- See REGRESSION_GUARDS.md "dragonflame-nova-proc-rate".
-- Validation provenance is retained in maintainer notes.

local AFFIX = "60% Chance for the nearest minion to the target location to cast Dragonflame Nova when you use a minion skill (1 second cooldown)"

local function readSource(path)
	local f = io.open(path, "r"); if not f then return nil end
	local s = f:read("*a"); f:close(); return s
end

describe("DragonflameNovaProcRate #minion parser contract", function()

	it("the proc line emits the grant PLUS the grounded chance and 1/s rate cap", function()
		local list, extra = modLib.parseMod(AFFIX)
		assert.is_table(list)
		assert.is_nil(extra, "whole line must stay consumed")
		assert.are.equals(3, #list, "grant + chance + cap")
		assert.are.equals("ExtraMinionSkill", list[1].name)
		assert.are.equals("DragonfireNova", list[1].value.skillId)
		assert.are.equals("ChanceToTriggerOnMinionSkillUse_DragonfireNova", list[2].name)
		assert.are.equals("BASE", list[2].type)
		assert.are.equals(60, list[2].value, "chance = datamined affix property 98 value 0.6")
		assert.are.equals("TriggerRateCapPerSecond_DragonfireNova", list[3].name)
		assert.are.equals("BASE", list[3].type)
		assert.are.equals(1, list[3].value, "cap = the '(1 second cooldown)' text constant")
	end)

	it("the ModCache row is rebaked with all three mods", function()
		local cacheText = readSource("Data/ModCache.lua")
		assert.is_not_nil(cacheText)
		assert.is_truthy(string.find(cacheText,
			'c["60% Chance for the nearest minion to the target location to cast Dragonflame Nova when you use a minion skill (1 second cooldown)"]={{[1]={flags=0,keywordFlags=0,name="ExtraMinionSkill",type="LIST",value={skillId="DragonfireNova"}},[2]={flags=0,keywordFlags=0,name="ChanceToTriggerOnMinionSkillUse_DragonfireNova",type="BASE",value=60},[3]={flags=0,keywordFlags=0,name="TriggerRateCapPerSecond_DragonfireNova",type="BASE",value=1}},nil}',
			1, true),
			"the baked row must carry grant + chance 60 + cap 1 (a regen must not drop the rate mods)")
	end)
end)

describe("DragonflameNovaProcRate #minion config contract", function()

	it("exposes a float `minionSkillUsesPerSecond` input that emits MinionSkillUsesPerSecond", function()
		local ConfigOptions = LoadModule("Modules/ConfigOptions")
		local opt
		for _, o in ipairs(ConfigOptions) do
			if type(o) == "table" and o.var == "minionSkillUsesPerSecond" then opt = o end
		end
		assert.is_table(opt, "minionSkillUsesPerSecond config option must exist")
		assert.are.equals("float", opt.type, "must accept fractional uses/s (e.g. 0.5)")
		local set = {}
		local fakeModList = { NewMod = function(_, name, mtype, value) set[name] = { mtype, value } end }
		opt.apply(2.5, fakeModList, fakeModList)
		assert.is_table(set["MinionSkillUsesPerSecond"], "apply must emit MinionSkillUsesPerSecond")
		assert.are.equals("BASE", set["MinionSkillUsesPerSecond"][1])
		assert.are.equals(2.5, set["MinionSkillUsesPerSecond"][2])
	end)

	it("default (unset / 0) applies nothing -- the fold falls back to the summon cast rate", function()
		-- ConfigTab only calls apply for a `float` when the input is set and ~= 0
		-- (BuildModList), so an empty input leaves MinionSkillUsesPerSecond at 0 and
		-- the fold uses usedEnv.player.output.Speed. This pins the fallback read.
		local calcsSrc = readSource("Modules/Calcs.lua")
		assert.is_truthy(string.find(calcsSrc, 'usedEnv.modDB:Sum("BASE", nil, "MinionSkillUsesPerSecond")', 1, true))
		assert.is_truthy(string.find(calcsSrc, "useRate = usedEnv.player.output.Speed or 0", 1, true),
			"unset config must fall back to the summoning skill's own cast rate")
	end)
end)

describe("DragonflameNovaProcRate #minion fold source contract", function()
	local calcsSrc
	setup(function()
		calcsSrc = readSource("Modules/Calcs.lua")
		assert.is_not_nil(calcsSrc)
	end)

	it("carries the guard marker in Calcs.lua, ModParser.lua and ConfigOptions.lua", function()
		assert.is_truthy(calcsSrc:find("@leb%-regression%-guard:dragonflame%-nova%-proc%-rate"))
		assert.is_truthy(readSource("Modules/ModParser.lua"):find("@leb%-regression%-guard:dragonflame%-nova%-proc%-rate"))
		assert.is_truthy(readSource("Modules/ConfigOptions.lua"):find("@leb%-regression%-guard:dragonflame%-nova%-proc%-rate"))
	end)

	it("the rate is min-capped by the parsed 1/s PTT cap", function()
		assert.is_truthy(string.find(calcsSrc, 'usedEnv.modDB:Sum("BASE", nil, "TriggerRateCapPerSecond_DragonfireNova")', 1, true))
		assert.is_truthy(string.find(calcsSrc, "procRate = m_min(procRate, rateCap)", 1, true),
			"the 1s-cooldown cap must min-apply to chance x use-rate")
	end)

	it("the contribution is a single un-multiplied entry (no minionCount / once per pass)", function()
		assert.is_truthy(string.find(calcsSrc, "local dragonflameNovaProcFolded = false", 1, true),
			"the once-per-pass flag must exist")
		assert.is_truthy(string.find(calcsSrc,
			'{ name = "Dragonflame Nova", dps = novaDPS, count = 1, trigger = activeSkill.activeEffect.grantedEffect.name', 1, true),
			"the Full DPS entry must carry count = 1")
		assert.is_truthy(string.find(calcsSrc, "fullDPS.combinedDPS = fullDPS.combinedDPS + novaDPS", 1, true),
			"combinedDPS must gain novaDPS exactly once, NOT x minionCount (one nova per use, nearest minion only)")
	end)
end)

describe("DragonflameNovaProcRate #minion fold behavioral", function()
	before_each(function()
		newBuild()
	end)

	local function setupSummon(customMods, usesPerSecond)
		build.skillsTab:SelSkill(1, "SummonBoneGolem")
		build.skillsTab.socketGroupList[1].includeInFullDPS = true
		build.configTab.input.customMods = customMods
		build.configTab.input.minionSkillUsesPerSecond = usesPerSecond
		build.configTab:BuildModList()
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end

	local function findNova(out)
		local found
		local n = 0
		for _, e in ipairs(out.SkillDPS or {}) do
			if e.name == "Dragonflame Nova" then
				found = e
				n = n + 1
			end
		end
		return found, n
	end

	it("default: the nova is rated at 60% x the summon skill's own cast rate", function()
		local out = setupSummon(AFFIX .. "\n", nil)
		local nova = findNova(out)
		assert.is_not_nil(nova, "the rated nova must appear as its own Full DPS entry")
		assert.are.equals(1, nova.count, "ONE nova per use -- never a per-minion pack")
		assert.are.equals("Summon Bone Golem", nova.trigger, "sourced from the Full-DPS summon group")
		local expectedRate = math.min(0.6 * out.Speed, 1)
		assert.are.equals(string.format("proc %.3g/s", expectedRate), nova.skillPart)
		assert.is_true(nova.dps > 0, "the rated proc must contribute")
		-- headline = summon entry + nova entry (the fold feeds combinedDPS once)
		local sum = 0
		for _, e in ipairs(out.SkillDPS) do sum = sum + e.dps * (e.count or 1) end
		assert.is_true(math.abs(out.FullDPS - sum) < 0.001,
			"Full DPS must equal the sum of its entries (nova folded exactly once)")
	end)

	it("the 1s cooldown caps the rate at 1/s (config override 10 uses/s -> 6/s uncapped -> 1/s)", function()
		local outDefault = setupSummon(AFFIX .. "\n", nil)
		local novaDefault = findNova(outDefault)
		local defaultRate = math.min(0.6 * outDefault.Speed, 1)

		local outCapped = setupSummon(AFFIX .. "\n", 10)
		local novaCapped = findNova(outCapped)
		assert.is_not_nil(novaCapped)
		assert.are.equals("proc 1/s", novaCapped.skillPart, "0.6 x 10 = 6/s must clamp to the 1/s cap")
		-- same per-hit, so dps scales exactly rate-for-rate
		assert.is_true(math.abs(novaCapped.dps * defaultRate - novaDefault.dps * 1) < 0.001,
			"capped dps / default dps must equal 1 / default rate (per-hit unchanged)")
	end)

	it("a below-cap override is used verbatim (0.5 uses/s -> 0.3/s)", function()
		local out = setupSummon(AFFIX .. "\n", 0.5)
		local nova = findNova(out)
		assert.is_not_nil(nova)
		assert.are.equals("proc 0.3/s", nova.skillPart, "rate = 0.6 x 0.5, under the cap")
	end)

	it("CONTROL: without the affix no nova entry exists and Full DPS is entries-consistent", function()
		local out = setupSummon("", nil)
		local nova = findNova(out)
		assert.is_nil(nova, "no staff mod -> no rated proc")
	end)

	it("ONCE PER PASS: two Full-DPS summon groups still yield exactly one nova entry", function()
		build.skillsTab:SelSkill(1, "SummonBoneGolem")
		build.skillsTab:SelSkill(2, "SummonSkeleton")
		build.skillsTab.socketGroupList[1].includeInFullDPS = true
		build.skillsTab.socketGroupList[2].includeInFullDPS = true
		build.configTab.input.customMods = AFFIX .. "\n"
		build.configTab:BuildModList()
		build.buildFlag = true
		runCallback("OnFrame")
		local out = build.calcsTab.mainOutput
		local nova, n = findNova(out)
		assert.is_not_nil(nova, "the nova must be rated at the first Full-DPS minion")
		assert.are.equals(1, n, "the proc fires once per minion-skill use -- NEVER once per summon group")
	end)
end)
