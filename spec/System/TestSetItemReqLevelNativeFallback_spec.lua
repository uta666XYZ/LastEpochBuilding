-- @leb-regression-guard:set-item-req-level-override-with-native-fallback
-- Locks the native-SET req.level fallback so the LevelReq filter doesn't
-- drop the Relic on <private build> lv62 Warlock (Fragments of the Shattered
-- Lance native set, set.req.level=0, base "Silver Grail" req=15). Without
-- the fallback, stored XML "LevelReq: 68" survives, char lv62 < 68 trips
-- the filter, and the relic's 4 affix mods are zeroed (Mana -94, Fire/
-- Necr/Void Res -16 each).

local OptionalArtifact = dofile("../spec/OptionalArtifact.lua")
local buildsIt = OptionalArtifact.gatedIt(it, pending, "spec/TestBuilds")

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

    -- Validation provenance is retained in maintainer notes.
    buildsIt("Qqwv73q2 Warlock snapshot reflects Relic stats applied", function()
        local snap = readSnapshot()
        assert.is_not_nil(snap, "Qqwv73q2 snapshot must exist")
        local function firstNumber(key)
            local _, _, v = string.find(snap, '%["' .. key .. '"%]%s*=%s*([%-%d%.]+)')
            return tonumber(v)
        end
        -- @leb-regression-guard: per-set-integer-source-not-halfstep
        -- Necr/Mana bands are anchored to LEB == in-game, NOT LETools. Do NOT
        -- "correct" them down to LET's 265/269 — that would re-introduce the
        -- refuted half-step per-Complete-Set model. Run this spec if you touch
        -- them. Test: spec/System/TestPerCompleteSetIntegerRoll_spec.lua.
        -- Fire 274 / Void 106: LEB == LETools == in-game (no attribute term),
        -- so these stay anchored to LET.
        -- Necr 268 / Mana 275: anchored to LEB == IN-GAME, NOT LETools. LETools
        -- reads Necr 265 / Mana 269, under by 3/6 because it models Legends
        -- Entwined's "+(2-5) to All Attributes per Complete Set" as a half-step
        -- (4.5/set) instead of the in-game integer (5/set). That is +3 on every
        -- attribute for this build (Vit 47 vs LET 44 -> Necr & Poison +3; Att 50
        -- vs 47 -> Mana +6 via x2). Confirmed in-game 2026-07-15 (Aurora capture,
        -- all 5 attributes LEB == engine, LETools uniformly -1). See guard
        -- per-set-integer-source-not-halfstep (src/Modules/ItemTools.lua) +
        -- spec/System/TestPerCompleteSetIntegerRoll_spec.lua.
        -- Pre-fix LEB: Fire 258, Necr 249, Void 90, Mana 175 (relic filtered).
        local fire = firstNumber("FireResistTotal")
        local necr = firstNumber("NecroticResistTotal")
        local void = firstNumber("VoidResistTotal")
        local mana = firstNumber("Mana")
        assert.is_true(fire and fire >= 273 and fire <= 275,
            "FireResistTotal must be ~274 (got " .. tostring(fire) .. ")")
        assert.is_true(necr and necr >= 267 and necr <= 269,
            "NecroticResistTotal must be ~268 (LEB==in-game; LETools 265 under-reads) (got " .. tostring(necr) .. ")")
        assert.is_true(void and void >= 105 and void <= 107,
            "VoidResistTotal must be ~106 (got " .. tostring(void) .. ")")
        assert.is_true(mana and mana >= 274 and mana <= 276,
            "Mana must be ~275 (LEB==in-game; LETools 269 under-reads) (got " .. tostring(mana) .. ")")
    end)
end)
