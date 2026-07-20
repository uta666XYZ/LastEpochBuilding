-- @leb-regression-guard: melee-skill-hit-flag
-- Locks the contract that LE weapon-delivery skills (melee/bow/throwing) always
-- derive skillFlags.hit = true, even when skills.json omits baseFlags.hit.
--
-- WHY THIS MATTERS:
-- skillFlags.hit gates the ENTIRE hit-damage crit pass in CalcOffence:
--   `if skillModList:Flag(cfg, "NeverCrit") or not skillFlags.hit then
--        output.CritChance = 0; output.CritMultiplier = 0; output.CritEffect = 1`
-- so a missing hit flag silently zeroes a skill's crit chance AND crit multi.
--
-- ROOT CAUSE (CalcActiveSkill.lua):
-- The PoB-era fallback `skillTypes[SkillType.Attack] or skillTypes[SkillType.Damage]
-- or skillTypes[SkillType.Projectile]` NEVER fires for LE pure-melee skills:
--   * SkillType.Attack = Melee|Throwing|Bow, and DataProcess only sets it when the
--     `band(tags, type) == type` test passes — i.e. ALL three bits present. A
--     Melee-only skill (skillTypeTags bit 512) fails this.
--   * SkillType.Damage is undefined (nil) in the LE enum.
--   * SkillType.Projectile = SkillType.Unsupported.
-- skills.json sets baseFlags.hit for ~135 skills, but a handful of genuine
-- attacks (ShatterStrike, CinderStrike, DarkQuiver) omit it, leaving hit=nil.
-- Observed: in-game ShutFackUp Shatter Strike shows 35% crit / 227% crit multi;
-- LEB computed CritChance=0 / CritMultiplier=0 before this fix.
--
-- THE FIX (CalcActiveSkill.lua):
-- Derive hit from the weapon-delivery baseFlags directly:
--   skillFlags.hit = skillFlags.hit
--     or ((skillFlags.melee or skillFlags.bow or skillFlags.throwing) and not skillFlags.ailment)
--     or <PoB-era skillTypes fallback>
-- The `not skillFlags.ailment` clause excludes pure ailment-delivery skills
-- (Ailment_Laceration carries a melee flag but only applies a DoT — it does not
-- directly hit).
--
-- See REGRESSION_GUARDS.md "melee-skill-hit-flag".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("MeleeSkillHitFlag", function()

    describe("CalcActiveSkill derives hit from weapon-delivery baseFlags", function()
        local source
        setup(function()
            source = readSource("Modules/CalcActiveSkill.lua")
        end)

        it("keeps the @leb-regression-guard marker so future edits trip review", function()
            assert.is_truthy(string.find(source, "melee%-skill%-hit%-flag"),
                "CalcActiveSkill.lua must keep the @leb-regression-guard:melee-skill-hit-flag comment")
        end)

        it("ORs in (melee/bow/throwing) and excludes ailment-delivery skills", function()
            -- Lock the delivery clause and the ailment exclusion together.
            local pat = "skillFlags%.melee%s+or%s+skillFlags%.bow%s+or%s+skillFlags%.throwing%)%s+and%s+not%s+skillFlags%.ailment"
            assert.is_truthy(string.find(source, pat),
                "hit must be derived from (melee or bow or throwing) and not ailment")
        end)

        it("still keeps the PoB-era skillTypes fallback (no regression of other paths)", function()
            assert.is_truthy(string.find(source,
                "activeSkill%.skillTypes%[SkillType%.Attack%]", 1, false),
                "the existing skillTypes[SkillType.Attack] fallback must remain")
        end)
    end)

    describe("skills.json precondition: the affected attacks lack baseFlags.hit", function()
        -- This documents the data state the logic fix compensates for. If a future
        -- data refresh adds baseFlags.hit to these entries, the assertion below trips
        -- and a maintainer must confirm the logic guard is still warranted.
        local source
        setup(function()
            source = readSource("Data/skills.json")
        end)

        local function entryWindow(key)
            local s = string.find(source, '"' .. key .. '"%s*:%s*{')
            assert.is_truthy(s, "skills.json must contain entry for " .. key)
            return string.sub(source, s, s + 2500)
        end

        for _, key in ipairs({ "ShatterStrike", "CinderStrike", "DarkQuiver" }) do
            it(("%s is melee + attack"):format(key), function()
                local w = entryWindow(key)
                assert.is_truthy(string.find(w, '"melee"%s*:%s*true'), key .. " must be melee")
                assert.is_truthy(string.find(w, '"attack"%s*:%s*true'), key .. " must be attack")
            end)
        end
    end)

    describe("functional: data.skills.ShatterStrike is the data shape the fix targets", function()
        setup(function()
            assert.is_not_nil(data, "global data table must be loaded by the headless wrapper")
            assert.is_not_nil(data.skills, "data.skills must be loaded from skills.json")
        end)

        it("data.skills.ShatterStrike is melee/attack without baseFlags.hit", function()
            local ge = data.skills and data.skills.ShatterStrike
            assert.is_not_nil(ge, "data.skills.ShatterStrike must exist")
            local bf = ge.baseFlags or {}
            assert.is_true(bf.melee == true, "ShatterStrike baseFlags.melee must be true")
            assert.is_true(bf.attack == true, "ShatterStrike baseFlags.attack must be true")
            assert.is_falsy(bf.hit, "ShatterStrike baseFlags.hit must be unset (the data gap this fix covers)")
        end)
    end)
end)
