-- @leb-regression-guard:fulldps-fold-same-skill-cycle
-- User-reported (2026-06-09): the Full DPS breakdown showed a skill split across
-- multiple lines — "Shurikens" + "Shurikens (Shurikens) x1/2 cycle" — when the
-- build runs the same skill in N socket groups (cycle-split, each weighted x1/N)
-- or a skill that triggers itself. The "(<self>)" source and "x1/N cycle" labels
-- are internal cycle-weighting detail the user does not want surfaced.
--
-- calcs.foldSameSkillCycleEntries merges those own/self same-name entries into ONE
-- summed "<skill>" line (cycle WEIGHTS preserved: each dps is already x1/N, the sum
-- == the skill's full Full DPS contribution). Only own/self entries merge, so
-- cross-skill triggers stay separate and a lone skill is untouched. It runs in the
-- Full DPS display AFTER foldAilmentsIntoParents; output.SkillDPS and the FullDPS
-- total are unchanged. The active-skill dropdown also hides the self-triggered
-- duplicate group "<X> (from <X>)" (RefreshSkillSelectControls).
-- See REGRESSION_GUARDS.md "fulldps-fold-same-skill-cycle".

describe("TestFullDPSFoldSameSkillCycle", function()
	local calcs
	before_each(function()
		newBuild()
		calcs = build.calcsTab.calcs
	end)

	describe("foldSameSkillCycleEntries (behavioral)", function()
		it("merges two own/self same-name entries into one summed line (Shurikens case)", function()
			local list = {
				{ name = "Shurikens", trigger = "",          dps = 62290, count = 1, skillPart = "x1/2 cycle" },
				{ name = "Shurikens", trigger = "Shurikens", dps = 19394, count = 1, skillPart = "x1/2 cycle" },
			}
			local folded = calcs.foldSameSkillCycleEntries(list)
			assert.are.equals(1, #folded)
			assert.are.equals("Shurikens", folded[1].name)
			assert.are.equals(81684, folded[1].dps * folded[1].count)
			-- internal labels dropped on merge
			assert.is_nil(folded[1].skillPart)
			assert.is_falsy(folded[1].trigger and folded[1].trigger ~= "")
		end)

		it("respects per-entry count when summing", function()
			local list = {
				{ name = "X", trigger = "",  dps = 10, count = 3 },
				{ name = "X", trigger = "X", dps = 5,  count = 2 },
			}
			local folded = calcs.foldSameSkillCycleEntries(list)
			assert.are.equals(1, #folded)
			assert.are.equals(40, folded[1].dps * folded[1].count) -- 10*3 + 5*2
		end)

		it("leaves a lone (non-duplicated) skill untouched, preserving skillPart", function()
			local list = { { name = "Shurikens", trigger = "", dps = 100, count = 1, skillPart = "keepme" } }
			local folded = calcs.foldSameSkillCycleEntries(list)
			assert.are.equals(1, #folded)
			assert.are.equals(100, folded[1].dps)
			assert.are.equals("keepme", folded[1].skillPart)
		end)

		it("does NOT merge cross-skill triggers (different source skill stays separate)", function()
			local list = {
				{ name = "Shurikens", trigger = "",    dps = 100, count = 1 },
				{ name = "Shurikens", trigger = "Net", dps = 50,  count = 1 }, -- triggered by a DIFFERENT skill
			}
			local folded = calcs.foldSameSkillCycleEntries(list)
			assert.are.equals(2, #folded) -- not merged: only one is an own/self entry
		end)

		it("does not mutate the input list", function()
			local list = {
				{ name = "Shurikens", trigger = "",          dps = 62290, count = 1 },
				{ name = "Shurikens", trigger = "Shurikens", dps = 19394, count = 1 },
			}
			calcs.foldSameSkillCycleEntries(list)
			assert.are.equals(2, #list)
			assert.are.equals(62290, list[1].dps)
			assert.are.equals(19394, list[2].dps)
		end)
	end)

	describe("wiring (source contract)", function()
		local function readFile(path)
			local f = io.open(path, "r"); if not f then return nil end
			local s = f:read("*a"); f:close(); return s
		end
		local calcsSrc, buildSrc
		setup(function()
			calcsSrc = readFile("Modules/Calcs.lua")
			buildSrc = readFile("Modules/Build.lua")
			assert.is_not_nil(calcsSrc); assert.is_not_nil(buildSrc)
		end)

		it("carries the guard marker in Calcs.lua and Build.lua", function()
			assert.is_truthy(calcsSrc:find("@leb%-regression%-guard:fulldps%-fold%-same%-skill%-cycle"))
			assert.is_truthy(buildSrc:find("@leb%-regression%-guard:fulldps%-fold%-same%-skill%-cycle"))
		end)

		it("the SkillDPS breakdown folds same-skill cycles after the ailment fold", function()
			local ailAt = buildSrc:find("foldAilmentsIntoParents(actor.output.SkillDPS", 1, true)
			local cycAt = buildSrc:find("foldSameSkillCycleEntries(foldedList)", 1, true)
			assert.is_not_nil(ailAt); assert.is_not_nil(cycAt)
			assert.is_true(ailAt < cycAt, "same-skill fold must run after the ailment fold")
		end)

		it("the active-skill dropdown hides the self-triggered '<X> (from <X>)' group", function()
			assert.is_truthy(buildSrc:find("hideSelfTrigger", 1, true), "must compute hideSelfTrigger")
			assert.is_truthy(
				buildSrc:find("data.skills[gsid].name == data.skills[socketGroup.triggeredOnHit].name", 1, true),
				"self-trigger = granted skill name equals source skill name")
			assert.is_truthy(buildSrc:find("not (hideAilment or hideSelfTrigger or hideTimerDuplicate)", 1, true),
				"the dropdown filter must combine hideAilment, hideSelfTrigger and hideTimerDuplicate")
		end)

		it("the active-skill dropdown hides a TIMER-triggered duplicate ('<X> (every Ns)') of a manually-socketed skill", function()
			-- build the set of manually-socketed skill ids (not trigger-granted)
			assert.is_truthy(buildSrc:find("manualSkillIds", 1, true), "must build the manualSkillIds set")
			assert.is_truthy(
				buildSrc:find("not sg.triggeredByTimer and not sg.triggeredOnHit", 1, true),
				"manualSkillIds = groups that are neither timer- nor hit-triggered")
			-- hide a timer-triggered grant whose skill is also manually socketed
			assert.is_truthy(
				buildSrc:find("socketGroup.triggeredByTimer and gsid and manualSkillIds[gsid]", 1, true),
				"hideTimerDuplicate = triggeredByTimer AND the same skill is manually socketed")
		end)

		it("calcFullDPS redirects a timer-triggered duplicate's slot to the manual skill's value", function()
			-- map of manual skill id -> activeSkill (neither timer- nor hit-triggered)
			assert.is_truthy(calcsSrc:find("manualActiveSkillBySkillId", 1, true),
				"calcFullDPS must build manualActiveSkillBySkillId")
			assert.is_truthy(calcsSrc:find("not mSg.triggeredByTimer and not mSg.triggeredOnHit", 1, true),
				"the map is keyed by manual (non-triggered) groups")
			-- redirect: a timer-triggered duplicate whose manual original is NOT separately
			-- included becomes the manual activeSkill, so Full DPS shows the real value, not the copy
			assert.is_truthy(calcsSrc:find("_sg.triggeredByTimer and _sg.skillId", 1, true),
				"redirect gates on triggeredByTimer")
			assert.is_truthy(calcsSrc:find("not manual.socketGroup.includeInFullDPS", 1, true),
				"redirect only when the manual group is NOT separately included (no double-count)")
			assert.is_truthy(calcsSrc:find("activeSkill = manual", 1, true),
				"redirect reassigns the slot to the manual activeSkill")
		end)
	end)
end)
