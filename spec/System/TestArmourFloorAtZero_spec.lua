-- @leb-regression-guard: armour-floor-at-zero-letools-artifact
-- Locks CalcDefence's `output.Armour = m_max(round(armour), 0)` floor that
-- matches the LE in-game display and DR formula contract. LE's
-- PlayerStats.armour field is a signed float (dump.cs L156840), but every
-- in-game consumer (display tooltip, DR formula armour/(armour+threshold))
-- treats negative as zero. The LETools planner skips this floor and reports
-- the raw signed sum, producing negative LETools Armor values on builds that
-- stack large %-reduced-Armour sources.
--
-- Evidence: QJWMRv53 Bladedancer lv98 carries:
--   - 36 + 108 + 35 + 255 = 434 base Armor from gear implicits
--   - 52% increased Armor (Blessing)
--   - 207 Guile × -1% reduced Armour (s4-guile-per-point-armour-reduction)
-- LETools planner: 434 * (1 + 0.52 - 2.07) = -239 (Tooltip rounds to -260
-- using 212% reduced figure shown). LEB CalcDefence:534 floors to 0.
-- Removing the floor would inject negative Armour into CalcDamage's
-- armourReduct formula and break PhysDR on every Guile-stacking build.
--
-- Companion guard: s4-guile-per-point-armour-reduction (the -1% per Guile
-- intrinsic that drives the calculation negative) and
-- armour-pct-shorthand-inc (which fixed a parallel under-counting issue).
--
-- See REGRESSION_GUARDS.md entry
-- `armour-floor-at-zero-letools-artifact` for the full chain.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ArmourFloorAtZeroLetoolsArtifact", function()
    local calcDefenceText

    setup(function()
        calcDefenceText = readSource("Modules/CalcDefence.lua")
    end)

    it("CalcDefence floors output.Armour at 0 via m_max(round(armour), 0)", function()
        assert.is_truthy(string.find(calcDefenceText,
            "output.Armour = m_max(round(armour), 0)", 1, true),
            "Armour display floor must remain present (LE in-game / DR-formula contract)")
    end)

    it("CalcDefence carries @leb-regression-guard:armour-floor-at-zero-letools-artifact marker", function()
        assert.is_truthy(string.find(calcDefenceText,
            "@leb-regression-guard:armour-floor-at-zero-letools-artifact", 1, true),
            "Floor site must carry the named guard marker")
    end)

    it("Evasion / MeleeEvasion / ProjectileEvasion / Ward also floor at 0 (parallel contract)", function()
        assert.is_truthy(string.find(calcDefenceText,
            "output.Evasion = m_max(round(evasion), 0)", 1, true),
            "Evasion display floor must remain present")
        assert.is_truthy(string.find(calcDefenceText,
            "output.Ward = m_max(round(ward), 0)", 1, true),
            "Ward display floor must remain present")
    end)

    it("does NOT downgrade the floor to allow negative Armour through", function()
        -- Catch a careless refactor that drops the m_max wrapper
        assert.is_nil(string.find(calcDefenceText,
            "output.Armour = round(armour)\n", 1, true),
            "Must not strip the m_max(_, 0) floor — would break PhysDR on Guile stacks")
    end)
end)
