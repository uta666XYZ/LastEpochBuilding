-- @leb-regression-guard: movement-speed-base-additive
-- Locks the MovementSpeed BASE term in the Movement Speed formula.
--
-- LE's actual formula is `(1 + (BASE + INC)/100) * More`. LEB previously
-- used `calcLib.mod(modDB, nil, "MovementSpeed")` which returns only
-- `(1 + INC/100) * More` and silently drops BASE. Passive nodes that grant
-- "+X% Movement Speed" (BASE) such as Beastmaster's Predator
-- (+1% Movement Speed per point, up to 5 points) thus contributed
-- nothing — Qb6WgDEp lv95 Beastmaster snapshot was -5% short of the
-- LETools breakdown until this fix.
--
-- See REGRESSION_GUARDS.md "movement-speed-base-additive".

describe("MovementSpeedBaseAdditive", function()
    local f = io.open("Modules/CalcDefence.lua", "r")
    local src = f and f:read("*a") or nil
    if f then f:close() end

    it("CalcDefence Movement Speed line includes BASE", function()
        assert.is_not_nil(src, "must read CalcDefence.lua")
        -- The fixed formula sums BASE explicitly via modDB:Sum("BASE", ..., "MovementSpeed")
        assert.is_truthy(string.find(src, 'modDB:Sum%("BASE",%s*nil,%s*"MovementSpeed"%)', 1, false),
            "Movement Speed calc must read BASE term explicitly")
        -- And combines it with INC inside the (1 + (... + ...)/100) shape
        assert.is_truthy(string.find(src, '%(msBase %+ msInc%)%s*/%s*100', 1, false),
            "Movement Speed calc must add BASE to INC before /100")
    end)

    it("plain calcLib.mod is no longer used for the Movement Speed slot", function()
        assert.is_not_nil(src, "must read CalcDefence.lua")
        -- Allow the function to exist elsewhere in the file but the specific
        -- "MovementSpeed" usage must NOT use the plain calcLib.mod helper
        -- (which drops BASE).
        assert.is_falsy(string.find(src, 'calcLib%.mod%(modDB,%s*nil,%s*"MovementSpeed"%)', 1, false),
            "Movement Speed slot must not call calcLib.mod (it drops BASE)")
    end)
end)
