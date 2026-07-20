-- @leb-regression-guard: deterministic-skill-stat-merge-order
-- Locks the contract that calcs.mergeSkillInstanceMods iterates a granted
-- effect's stats in a STABLE (sorted-key) order, so the value that wins a
-- last-wins skillData assignment is deterministic.
--
-- Several stat keys map to the SAME skillData key. e.g. both
-- "None_base_fire_damage" and "spell_base_fire_damage" map to SkillData
-- "FireDamage" (SkillStatMap.lua), and CalcActiveSkill populates skillData by a
-- last-wins assignment (`skillData[value.key] = value.value`). Lua randomises
-- string-key hash order per process, so raw pairs() made the winner
-- nondeterministic: <private build>'s Flame Rush (which declares both
-- None_base_fire_damage=20 and spell_base_fire_damage=40) had its base fire
-- damage flip 20<->40 (FireDamageBase 128<->148) run-to-run, cascading into
-- FullDPS / Lightning* / Stun / EHP and producing flaky snapshot mismatches.
--
-- After the fix the keys are visited in sorted order, so the delivery-tagged
-- "spell_base_fire_damage" (sorts after the generic "None_base_fire_damage")
-- deterministically wins -- matching the in-game spell base damage of 40 and the
-- snapshot value FireDamageBase = 40 + 54*2 = 148.
-- See REGRESSION_GUARDS.md > "deterministic-skill-stat-merge-order".

describe("SkillStatMergeDeterminism", function()
    local calcs
    before_each(function()
        newBuild()
        calcs = build.calcsTab.calcs
    end)

    -- Build a granted effect whose stats contain two keys that both map to the
    -- same SkillData key, mirroring Flame Rush's None/spell base fire damage.
    local function makeGrantedEffect()
        local function sdMod(key)
            return { name = "SkillData", type = "LIST", value = { key = key, value = nil }, flags = 0, keywordFlags = 0 }
        end
        return {
            name = "TestColliding",
            stats = { ["None_base_fire_damage"] = 20, ["spell_base_fire_damage"] = 40 },
            statMap = {
                ["None_base_fire_damage"]  = { sdMod("FireDamage") },
                ["spell_base_fire_damage"] = { sdMod("FireDamage") },
            },
            baseMods = {},
        }
    end

    -- Reproduce CalcActiveSkill's last-wins skillData extraction.
    local function resolveFireDamage(modList)
        local fire
        for _, value in ipairs(modList:List(nil, "SkillData")) do
            if value.key == "FireDamage" then fire = value.value end
        end
        return fire
    end

    it("colliding base-damage stat keys resolve deterministically to the delivery-tagged value", function()
        -- Run repeatedly: the result must be identical and equal to the spell
        -- (delivery-tagged) value every time, never the generic None value.
        for _ = 1, 20 do
            local modList = new("ModList")
            calcs.mergeSkillInstanceMods({}, modList, { grantedEffect = makeGrantedEffect() })
            assert.are.equals(40, resolveFireDamage(modList),
                "delivery-tagged spell_base_fire_damage (40) must deterministically win over None (20)")
        end
    end)
end)
