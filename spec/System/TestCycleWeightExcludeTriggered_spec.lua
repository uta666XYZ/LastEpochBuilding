-- @leb-regression-guard:cycle-weight-exclude-triggered
-- In-game-confirmed fix (2026-06-09): LEB's Full DPS cycle-weighting (N socket groups
-- sharing a treeId -> each x1/N, for genuine cast rotations like Runebolt Tri-Elemental)
-- wrongly counted TRIGGERED groups too. A self-triggered copy ("Shurikens (from
-- Shurikens)") fires additively on top of the manual cast, so halving both made Full DPS
-- LESS than the single skill. In-game StarSeaVnV: Shurikens 142,136 DPS vs LEB
-- cycle-halved 81,684 (-43%); the trigger adds ~22k on top of the ~120k manual.
--
-- Fix (calcs.calcFullDPS):
--   (1) treeIdGroupCount counts only NON-triggered groups (skillData.triggered excluded).
--   (2) a triggered skill always gets cycleWeight = 1 (full, additive) and no "x1/N cycle"
--       label, regardless of cycleN.
-- Genuine multi-cast rotations (non-triggered, e.g. Runebolt variants) keep cycle weighting.
-- Source-contract spec (the behavioral effect is validated by the build-snapshot regen).
-- See REGRESSION_GUARDS.md "cycle-weight-exclude-triggered".

describe("CycleWeightExcludeTriggered", function()
	local function readFile(path)
		local f = io.open(path, "r"); if not f then return nil end
		local s = f:read("*a"); f:close(); return s
	end
	local src
	setup(function()
		src = readFile("Modules/Calcs.lua")
		assert.is_not_nil(src, "must read Modules/Calcs.lua")
	end)

	it("carries the guard marker", function()
		assert.is_truthy(src:find("@leb%-regression%-guard:cycle%-weight%-exclude%-triggered"))
	end)

	it("treeIdGroupCount excludes triggered groups from the cycle count", function()
		-- Discriminator checks BOTH skillData.triggered AND socketGroup.triggeredOnHit: a
		-- self-triggered grant "X (from X)" sets triggeredOnHit but NOT skillData.triggered.
		assert.is_truthy(
			src:find("(activeSkill.skillData and activeSkill.skillData.triggered) or (activeSkill.socketGroup and activeSkill.socketGroup.triggeredOnHit)", 1, true),
			"the count increment must exclude triggered AND triggeredOnHit groups")
	end)

	it("a triggered skill always gets full cycleWeight (additive, never x1/N)", function()
		assert.is_truthy(src:find("local cycleIsTriggered = (activeSkill.skillData and activeSkill.skillData.triggered) or (activeSkill.socketGroup and activeSkill.socketGroup.triggeredOnHit)", 1, true),
			"must detect cycleIsTriggered via skillData.triggered OR socketGroup.triggeredOnHit")
		assert.is_truthy(src:find("local cycleWeight = (not cycleIsTriggered and cycleN > 1) and (1 / cycleN) or 1", 1, true),
			"cycleWeight must be 1 for triggered skills")
	end)

	it("the 'x1/N cycle' label is suppressed for triggered skills", function()
		assert.is_truthy(
			src:find('local skillPartLabel = (not cycleIsTriggered and cycleN > 1) and', 1, true),
			"the cycle label must be gated on not-triggered too")
	end)

	it("genuine (non-triggered) cycle weighting is preserved", function()
		-- cycleN-based 1/N weighting still exists for the non-triggered path
		assert.is_truthy(src:find("(1 / cycleN)", 1, true), "1/cycleN weighting must remain for non-triggered rotations")
	end)
end)
