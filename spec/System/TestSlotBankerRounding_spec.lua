-- @leb-regression-guard:slot-banker-rounding
-- LE applies (1 + affixEffectModifier) to the canonical affix base roll on
-- each equipment slot. amulet/shield/catalyst share affixEffectModifier=0.17
-- (verified in datamined game source
-- BaseTypeName="Amulet"/"Shield"/"Catalyst"), so they multiply by x1.17 and
-- round with banker's rounding (round-half-to-even). LEB previously stored
-- half-up values for entries hitting a .5 boundary, producing min OR max
-- one higher than in-game.
--
-- Sister guard to body_armor-banker-rounding. Covers the 5 patched
-- (affixId, tier, slot) entries surfaced by .tmp/audit_slot_rounding.py plus
-- one (330_6 amulet) surfaced by the second-pass scope survey.
-- datamining evidence: AscendingValueAfterPropertyRounding (datamined offset)
-- in datamined game source the slot scalar
-- × base rounding happens upstream of this function in affix data prep.
-- Empirical confirmation: existing 22-row body_armor case set.

describe("SlotBankerRounding", function()
    local cjson_ok, cjson = pcall(require, "lua.dkjson")
    if not cjson_ok then cjson_ok, cjson = pcall(require, "dkjson") end

    local function loadModItem()
        local f = assert(io.open("../src/Data/ModItem_1_4.json", "r"))
        local data = f:read("*a")
        f:close()
        if cjson_ok and cjson.decode then
            return cjson.decode(data)
        end
        return data
    end

    local function slotRange(modItem, key, slot)
        if type(modItem) == "table" then
            local entry = modItem[key]
            assert.is_not_nil(entry, "missing affix entry: " .. key)
            local override = entry.slotOverrides and entry.slotOverrides[slot]
                and entry.slotOverrides[slot]["1"]
            assert.is_not_nil(override, "missing " .. slot .. " slotOverride for " .. key)
            local lo, hi = override:match("%+?%((%-?%d+)%-(%-?%d+)%)")
            return tonumber(lo), tonumber(hi)
        else
            local idx = modItem:find('"' .. key .. '"%s*:')
            assert.is_not_nil(idx, "missing affix entry: " .. key)
            local sub = modItem:sub(idx, idx + 2400)
            local pat = '"' .. slot .. '"%s*:%s*{[^}]-%+?%((%-?%d+)%-(%-?%d+)%)'
            local lo, hi = sub:match(pat)
            return tonumber(lo), tonumber(hi)
        end
    end

    -- Each row: { key, slot, expected_lo, expected_hi, "affixName tier note" }
    -- Values are banker(base * 1.17). The "(was X)" hint records what LEB
    -- stored under half-up rounding before the fix.
    local cases = {
        -- Dodge Rating (affixId 8) — base 50..65
        { "8_3",  "amulet",   58, 76, "Dodge Rating T3 amulet (was 59-76)" },
        { "8_3",  "catalyst", 58, 76, "Dodge Rating T3 catalyst (was 59-76)" },
        -- Mana (affixId 34) — base 36..50
        { "34_4", "amulet",   42, 58, "Mana T4 amulet (was 42-59)" },
        { "34_4", "catalyst", 42, 58, "Mana T4 catalyst (was 42-59)" },
        -- Throwing Damage (affixId 88) — base 50..65
        { "88_7", "amulet",   58, 76, "Throwing Damage T7 amulet (was 59-76)" },
        -- Mana Regen % (affixId 330) — second-pass scope-survey addition
        { "330_6", "amulet",  58, 70, "Mana Regen T6 amulet (was 59-70)" },
    }

    for _, c in ipairs(cases) do
        local key, slot, exp_lo, exp_hi, label = c[1], c[2], c[3], c[4], c[5]
        it("ModItem 1_4 " .. label .. " banker(base*1.17)", function()
            local mi = loadModItem()
            local lo, hi = slotRange(mi, key, slot)
            assert.are.equals(exp_lo, lo, key .. " " .. slot .. " min mismatch")
            assert.are.equals(exp_hi, hi, key .. " " .. slot .. " max mismatch")
        end)
    end
end)
