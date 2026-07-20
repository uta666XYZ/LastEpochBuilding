-- @leb-regression-guard: ballista-per-dex-attack-speed-intrinsic
-- @leb-regression-guard: ballista-minion-ignores-owner-weapon-attack-rate
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("BallistaPerDexAttackSpeed", function()
    it("SummonBallista restores the intrinsic per-Dexterity Minion Attack Speed baseMod", function()
        local skills = readSource("Data/skills.json")
        -- both intrinsic per-Dex lines must be present (damage survivor + restored speed)
        assert.is_truthy(string.find(skills,
            "1% increased Minion Attack Speed per player Dexterity", 1, true),
            "SummonBallista must carry the intrinsic '1% increased Minion Attack Speed per player Dexterity'")
        assert.is_truthy(string.find(skills,
            "4% increased Minion Damage per player Dexterity", 1, true),
            "the sibling damage intrinsic must remain")
    end)

    it("the 5x-misparsed BallistaBolt per-Dex attack speed stays removed", function()
        local skills = readSource("Data/skills.json")
        assert.is_nil(string.find(skills,
            "5% increased Attack Speed per player Dexterity", 1, true),
            "the 5%/Dex misparse (fix#1) must NOT be reintroduced")
    end)

    it("BallistaBolt uses the datamined base castTime and ignores the owner weapon rate", function()
        local skills = readSource("Data/skills.json")
        assert.is_truthy(string.find(skills, '"castTime": 1.5333333', 1, true),
            "BallistaBolt.castTime must be the datamined base 1.5333333 (=2.3/1.5)")
        assert.is_nil(string.find(skills, '"castTime": 1.3939393', 1, true),
            "the old too-fast castTime 1.3939393 must be gone")
        assert.is_truthy(string.find(skills, '"minionIgnoresOwnerWeaponAttackRate": true', 1, true),
            "BallistaBolt must carry the minionIgnoresOwnerWeaponAttackRate flag")
    end)

    it("RogueBallista no longer carries a separate innate Speed INC (baked into base)", function()
        local minions = readSource("Data/minions.json")
        -- isolate the RogueBallista block and assert it has no Speed mod
        local block = string.match(minions, '"RogueBallista":%s*{.-"life"')
        assert.is_not_nil(block, "must find the RogueBallista block")
        assert.is_nil(string.find(block, '"name": "Speed"', 1, true),
            "RogueBallista must not model a separate innate Speed INC (it corrupts per-Dex scaling)")
    end)

    it("CalcOffence gates the owner-weapon AttackRate multiply on the ballista flag", function()
        local calc = readSource("Modules/CalcOffence.lua")
        assert.is_truthy(string.find(calc,
            "minionIgnoresOwnerWeaponAttackRate", 1, true),
            "the minion Speed formula must honour minionIgnoresOwnerWeaponAttackRate")
        assert.is_truthy(string.find(calc,
            "not activeSkill.activeEffect.grantedEffect.minionIgnoresOwnerWeaponAttackRate", 1, true),
            "the weapon-rate multiply must be skipped when the flag is set")
    end)
end)
