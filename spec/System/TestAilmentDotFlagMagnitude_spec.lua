-- @leb-regression-guard:ailment-dot-flag-magnitude
-- See REGRESSION_GUARDS.md > "ailment-dot-flag-magnitude".
-- Validation provenance is retained in maintainer notes.

local function readSrc(rel)
    local f = io.open(rel, "r") or io.open("src/" .. rel, "r")
    assert.is_not_nil(f, rel .. " must be readable")
    local s = f:read("*a"); f:close()
    return s
end

describe("AilmentDotFlagMagnitude", function()
    before_each(function()
        newBuild()
    end)

    -- ---- ModDB contract: what the cfg change makes matchable ----

    it("a Dot-flagged INC in a ModDB matches a hit+Dot cfg but not a hit-only cfg", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        -- what "increased Minion Damage Over Time" lands as (probe-verified on
        -- VoidMaster: Damage INC 429 flags=ModFlag.Dot on minion.modDB)
        db:NewMod("Damage", "INC", 429, "Item:Scales of Lemniscate", ModFlag.Dot)
        db:NewMod("Damage", "INC", 100, "Item:generic")
        local hitCfg = { flags = ModFlag.Melee + ModFlag.Hit }
        local ailmentCfg = { flags = ModFlag.Melee + ModFlag.Hit + ModFlag.Dot }
        assert.are.equals(100, db:Sum("INC", hitCfg, "Damage"),
            "hit-only cfg must NOT see the Dot-gated mod (the pre-fix behavior)")
        assert.are.equals(529, db:Sum("INC", ailmentCfg, "Damage"),
            "the ailment cfg must include Dot-gated INC on top of everything the hit saw")
    end)

    it("a Dot-flagged MORE (phys-DoT tree node shape) matches only the ailment cfg", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        -- ma6hdr-23 "Sharper Metal" rank5 shape: PhysicalDamage MORE 150 flags=Dot
        db:NewMod("PhysicalDamage", "MORE", 150, "Tree:ma6hdr-23", ModFlag.Dot)
        local hitCfg = { flags = ModFlag.Melee + ModFlag.Hit }
        local ailmentCfg = { flags = ModFlag.Melee + ModFlag.Hit + ModFlag.Dot }
        assert.are.equals(1, db:More(hitCfg, "PhysicalDamage"),
            "the hit itself must not receive the DoT-only MORE")
        assert.are.equals(2.5, db:More(ailmentCfg, "PhysicalDamage"),
            "ailment magnitude must receive the full x2.5 (ratio-solved vs in-game)")
    end)

    -- ---- source pins: the cfg construction + consumption sites ----

    it("CalcOffence builds ailmentCfg by ADDING Dot to the hit flags (minimal-diff contract)", function()
        local src = readSrc("Modules/CalcOffence.lua")
        assert.is_truthy(src:find("@leb-regression-guard:ailment-dot-flag-magnitude", 1, true),
            "CalcOffence must carry the guard")
        assert.is_truthy(src:find("local ailmentCfg = copyTable(skillCfg, true)", 1, true),
            "cfg must be a shallow copy of the hit skillCfg (cyclic refs)")
        assert.is_truthy(src:find("ailmentCfg.flags = bor(skillCfg.flags or 0, ModFlag.Dot)", 1, true),
            "flags must ADD Dot on top of the hit flags -- nothing that matched before may stop matching")
    end)

    it("both damagingAilment branches (dualType and single-type) consume ailmentCfg", function()
        local src = readSrc("Modules/CalcOffence.lua")
        local loop = src:match("output%.TotalAilmentDPS = 0.-\n\tend")
        assert.is_not_nil(loop, "damagingAilment loop must be locatable")
        assert.is_truthy(loop:find('calcLib.mod(skillModList, ailmentCfg, ailmentName .. "Damage", "AilmentDamage", dmgType .. "Damage", "Damage")', 1, true),
            "dualType branch must use ailmentCfg for incDamage")
        assert.is_truthy(loop:find('calcLib.mod(skillModList, ailmentCfg, ailmentName .. "Damage", "AilmentDamage", ailmentData.associatedType .. "Damage", "Damage")', 1, true),
            "single-type branch must use ailmentCfg for incDamage")
        assert.is_truthy(loop:find('calcLib.mod(skillModList, ailmentCfg, ailmentName .. "DamageMore")', 1, true),
            "the ailment MORE mod must also be evaluated under the DoT context")
        assert.is_falsy(loop:find('calcLib.mod(skillModList, skillCfg, ailmentName', 1, true),
            "no magnitude call in the loop may still use the raw hit skillCfg")
    end)
end)
