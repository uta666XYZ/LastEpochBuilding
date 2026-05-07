-- @leb-regression-guard:body_armor-banker-rounding
-- LE applies (1 + affixEffectModifier) to the canonical affix base roll on
-- each equipment slot. body_armor's affixEffectModifier is 0.5 (verified in
-- LE_datamining/extracted/items/equipmentItems.json BaseTypeName="Body Armor"),
-- so body_armor multiplies by x1.5 and rounds with banker's rounding
-- (round-half-to-even). LEB previously used half-up, producing min OR max
-- values one higher than in-game on every .5-boundary tier.
--
-- This spec asserts all 22 patched (affixId, tier) pairs across 9 affix IDs.
-- See REGRESSION_GUARDS.md "body_armor-banker-rounding" for the full table
-- and the audit script `.tmp/audit_body_armor_rounding.py`.

describe("BodyArmorBankerRounding", function()
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

    local function bodyArmorRange(modItem, key)
        if type(modItem) == "table" then
            local entry = modItem[key]
            assert.is_not_nil(entry, "missing affix entry: " .. key)
            local override = entry.slotOverrides and entry.slotOverrides.body_armor
                and entry.slotOverrides.body_armor["1"]
            assert.is_not_nil(override, "missing body_armor slotOverride for " .. key)
            local lo, hi = override:match("%+?%((%-?%d+)%-(%-?%d+)%)")
            return tonumber(lo), tonumber(hi)
        else
            local idx = modItem:find('"' .. key .. '"%s*:')
            assert.is_not_nil(idx, "missing affix entry: " .. key)
            local sub = modItem:sub(idx, idx + 1200)
            local lo, hi = sub:match('"body_armor"%s*:%s*{[^}]-%+?%((%-?%d+)%-(%-?%d+)%)')
            return tonumber(lo), tonumber(hi)
        end
    end

    -- Each row: { key, expected_lo, expected_hi, "affixName tier note" }
    -- Values are banker(base * 1.5). The "(was X)" hint in each name records
    -- what LEB stored under half-up rounding before the fix.
    local cases = {
        -- Dodge Rating (affixId 8)
        { "8_1",    45, 58,  "Dodge Rating T1 (was 45-59)" },
        { "8_6",   226, 300, "Dodge Rating T6 (was 227-300)" },
        -- Health (affixId 25)
        { "25_0",   8,  22,  "Health T0 (was 8-23)" },
        -- Armor flat (affixId 31)
        { "31_1",  32,  52,  "Armor T1 (was 32-53)" },
        { "31_2",  54,  82,  "Armor T2 (was 54-83)" },
        -- Mana (affixId 34)
        { "34_1",  16,  26,  "Mana T1 (was 17-26)" },
        { "34_3",  39,  52,  "Mana T3 (was 39-53)" },
        { "34_6", 136, 180,  "Mana T6 (was 137-180)" },
        -- Ward per Second (affixId 382)
        { "382_6", 64,  84,  "Ward/s T6 (was 65-84)" },
        -- Strength (501)
        { "501_2",  4,   6,  "Strength T2 (was 5-6)" },
        { "501_4", 10,  12,  "Strength T4 (was 11-12)" },
        { "501_5", 16,  20,  "Strength T5 (was 17-20)" },
        -- Intelligence (502)
        { "502_2",  4,   6,  "Intelligence T2 (was 5-6)" },
        { "502_4", 10,  12,  "Intelligence T4 (was 11-12)" },
        { "502_5", 16,  20,  "Intelligence T5 (was 17-20)" },
        -- Dexterity (503)
        { "503_2",  4,   6,  "Dexterity T2 (was 5-6)" },
        { "503_4", 10,  12,  "Dexterity T4 (was 11-12)" },
        { "503_5", 16,  20,  "Dexterity T5 (was 17-20)" },
        -- Attunement (504)
        { "504_2",  4,   6,  "Attunement T2 (was 5-6)" },
        { "504_4", 10,  12,  "Attunement T4 (was 11-12)" },
        { "504_5", 16,  20,  "Attunement T5 (was 17-20)" },
        -- Vitality (505)
        { "505_2",  4,   6,  "Vitality T2 (was 5-6)" },
        { "505_4", 10,  12,  "Vitality T4 (was 11-12)" },
        { "505_5", 16,  20,  "Vitality T5 (was 17-20)" },
    }

    for _, c in ipairs(cases) do
        local key, exp_lo, exp_hi, label = c[1], c[2], c[3], c[4]
        it("ModItem 1_4 " .. label .. " body_armor banker(base*1.5)", function()
            local mi = loadModItem()
            local lo, hi = bodyArmorRange(mi, key)
            assert.are.equals(exp_lo, lo, key .. " min mismatch")
            assert.are.equals(exp_hi, hi, key .. " max mismatch")
        end)
    end
end)
