-- @leb-regression-guard:set-item-req-level-override-with-native-fallback
-- Locks the native-SET req.level fallback so the LevelReq filter doesn't
-- drop the Relic on Qqwv73q2 lv62 Warlock (Fragments of the Shattered
-- Lance native set, set.req.level=0, base "Silver Grail" req=15). Without
-- the fallback, stored XML "LevelReq: 68" survives, char lv62 < 68 trips
-- the filter, and the relic's 4 affix mods are zeroed (Mana -94, Fire/
-- Necr/Void Res -16 each).

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("../" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("SetItemReqLevelNativeFallback", function()
    local itemSrc

    setup(function()
        itemSrc = readSource("src/Classes/Item.lua")
    end)

    it("Item.lua carries the named guard marker", function()
        assert.is_truthy(string.find(itemSrc,
            "@leb%-regression%-guard: set%-item%-req%-level%-override%-with%-native%-fallback",
            1, false),
            "Item.lua must carry the named guard marker")
    end)

    it("ParseRaw SET override has native fallback to self.base.req.level", function()
        -- The native fallback branch must exist: when e.req.level is 0 or
        -- missing, fall through to self.base.req.level.
        assert.is_truthy(string.find(itemSrc,
            "self%.requirements%.level%s*=%s*self%.base%.req%.level",
            1, false),
            "Native-set fallback to base.req.level must be present in Item.lua")
    end)

    it("ParseRaw SET override branch is not gated only on e.req.level > 0", function()
        -- Locate the SET-rarity native-fallback comment in ParseRaw to confirm
        -- the elseif branch wires up the fallback rather than skipping when
        -- req.level==0.
        assert.is_truthy(string.find(itemSrc,
            "Native set with req%.level=0 inherits base req",
            1, false),
            "Native fallback comment must be present in the ParseRaw SET branch")
    end)

    local function readSnapshot()
        local path = "spec/TestBuilds/1.4/Qqwv73q2 lv62 Warlock.lua"
        local f = io.open(path, "r") or io.open("../" .. path, "r")
        if not f then return nil end
        local text = f:read("*a")
        f:close()
        return text
    end

    it("Qqwv73q2 Warlock snapshot reflects Relic stats applied", function()
        local snap = readSnapshot()
        assert.is_not_nil(snap, "Qqwv73q2 snapshot must exist")
        local function firstNumber(key)
            local _, _, v = string.find(snap, '%["' .. key .. '"%]%s*=%s*([%-%d%.]+)')
            return tonumber(v)
        end
        -- LET values: Fire 274, Necr 265, Void 106, Mana 269.3
        -- Pre-fix LEB: Fire 258, Necr 249, Void 90, Mana 175 (relic filtered)
        -- Post-fix LEB must agree with LET within 1 unit.
        local fire = firstNumber("FireResistTotal")
        local necr = firstNumber("NecroticResistTotal")
        local void = firstNumber("VoidResistTotal")
        local mana = firstNumber("Mana")
        assert.is_true(fire and fire >= 273 and fire <= 275,
            "FireResistTotal must be ~274 (got " .. tostring(fire) .. ")")
        assert.is_true(necr and necr >= 264 and necr <= 266,
            "NecroticResistTotal must be ~265 (got " .. tostring(necr) .. ")")
        assert.is_true(void and void >= 105 and void <= 107,
            "VoidResistTotal must be ~106 (got " .. tostring(void) .. ")")
        assert.is_true(mana and mana >= 268 and mana <= 270,
            "Mana must be ~269 (got " .. tostring(mana) .. ")")
    end)
end)
