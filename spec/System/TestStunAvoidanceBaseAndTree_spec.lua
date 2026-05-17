-- @leb-regression-guard: stun-avoidance-base-and-tree
-- Locks the two terms that make up `output.StunAvoidance`:
--
--   1. Class base = `baseStunAvoidance` + `stunAvoidancePerLevel * Level`
--      registered via a `Multiplier{var="Level"}` tag on the BASE mod in
--      CalcSetup.lua. If the `base = classStats["baseStunAvoidance"]` tag
--      argument is dropped, the +250 floor silently vanishes (the per-level
--      term still scales, but the lv1 base disappears).
--   2. Aggregate Sum over BASE — passive tree nodes such as Acolyte-19
--      "Towering Death" (+50 Stun Avoidance per point, up to 5 scaling
--      points = +250) contribute via `modDB:Sum("BASE", nil, "StunAvoidance")`
--      in CalcDefence.lua. If that call narrows to an item-only lookup,
--      passive contributions disappear without any LEB-internal error.
--
-- Triangulation case study: BxvJP3g1 lv99 Necromancer
--   745 (base 250 + 5*99) + 250 (Towering Death 5pt) + 562 (3 affixes)
--   = 1557 — matches LEB snapshot and LE datamining; LETools displayed
--   1075 (-482) because its left panel omits passive node contributions
--   (filed as "LETools 表示バグ集" 事例 5).
--
-- See REGRESSION_GUARDS.md "stun-avoidance-base-and-tree".

describe("StunAvoidanceBaseAndTree", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local setupSrc = readFile("Modules/CalcSetup.lua")
    local defenceSrc = readFile("Modules/CalcDefence.lua")

    it("CalcSetup registers StunAvoidance with both base and per-level terms", function()
        assert.is_not_nil(setupSrc, "must read CalcSetup.lua")
        -- The mod must carry stunAvoidancePerLevel as its value AND
        -- baseStunAvoidance as the Multiplier tag's `base` field — the two
        -- together are what produces 250 + 5*Level. Dropping either silently
        -- breaks the floor or the scaling.
        local pattern = 'modDB:NewMod%("StunAvoidance",%s*"BASE",%s*classStats%["stunAvoidancePerLevel"%]'
        assert.is_truthy(string.find(setupSrc, pattern, 1, false),
            "StunAvoidance BASE mod must use classStats[stunAvoidancePerLevel] as its scaling value")
        assert.is_truthy(string.find(setupSrc,
            'base%s*=%s*classStats%["baseStunAvoidance"%]', 1, false),
            "StunAvoidance BASE mod must keep `base = classStats[baseStunAvoidance]` on its Multiplier tag")
        -- And the multiplier var must be Level — anything else stops per-level
        -- scaling cold.
        assert.is_truthy(string.find(setupSrc,
            'type%s*=%s*"Multiplier",%s*var%s*=%s*"Level",%s*base%s*=%s*classStats%["baseStunAvoidance"%]',
            1, false),
            "StunAvoidance Multiplier tag must use var=Level with base=baseStunAvoidance")
    end)

    it("CalcDefence reads StunAvoidance via Sum over BASE (no item-only narrowing)", function()
        assert.is_not_nil(defenceSrc, "must read CalcDefence.lua")
        -- Passive node BASE contributions (e.g. Acolyte-19 Towering Death)
        -- only reach the player stat through an unconstrained BASE Sum.
        assert.is_truthy(string.find(defenceSrc,
            'modDB:Sum%("BASE",%s*nil,%s*"StunAvoidance"%)', 1, false),
            "StunAvoidance flat term must be modDB:Sum over BASE with no source filter")
    end)
end)
