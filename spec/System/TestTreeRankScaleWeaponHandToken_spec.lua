-- @leb-regression-guard:tree-rank-scale-skip-weapon-hand-token
-- Locks the rule that PassiveTree:ProcessStats rank-scaling (multiply leading stat
-- VALUES by node.alloc) must NOT scale the digit inside a 1h/2h weapon-hand token
-- that lives in a CONDITION phrase.
--
-- Bug (Aurora_LEB Forge Guard, in-game vs LEB): Master of Arms (Sentinel-68,
-- tree_2.json, maxPoints 8) has "+2 Strength With 2h Weapon". The bare %d rank scaler
-- turned BOTH the value "2" AND the "2" in "2h" into 2*alloc, so at 8 points the line
-- became "+16 Strength With 16h Weapon". ModParser has "with 2h weapon" but not
-- "with 16h weapon", so the UsingTwoHandedWeapon condition was lost and the whole Str
-- mod dropped -> LEB Brutality 98 vs in-game 116 (the +16 Master of Arms Strength
-- vanished; that was the bulk of the long-chased "-18 Strength" Forge Strike gap).
--
-- Game truth: the node grants +2 Strength per point WHILE WIELDING A 2H WEAPON; at 8
-- points = +16, conditional. datamine passives_raw.json Sentinel-68 property 19
-- ("Strength With 2h Weapon"). In-game Aurora wields a 2H Sunforged Hammer (Eber Head
-- = "Two-Handed Mace") with the shield in inventory (not equipped), so the condition
-- holds and +16 applies; with the fix LEB Brutality 98 -> 114 (remaining -2 is the
-- separate .5 attribute-rounding convention, in-game rounds .5 up / LEB down).
--
-- The fix (Classes/PassiveTree.lua scaleNumbers): a digit run immediately followed by
-- "h"/"H" is a hand token, not a value (stat values are always followed by a space or
-- "%"), so it is left unscaled. Affects every multi-point node carrying a 1h/2h
-- conditional stat (Master of Arms, Battlemaster's Blade "+20% Area With 2h", Heorot's
-- Arsenal "+8 Spell Damage With 2h Weapon", weapon-subtype nodes, ...).
--
-- See REGRESSION_GUARDS.md "tree-rank-scale-skip-weapon-hand-token".

describe("TreeRankScaleWeaponHandToken", function()
    before_each(function()
        newBuild()
    end)

    -- Run ProcessStats on a synthetic node and return it (mirrors
    -- TestTreeAlsoAppliesToMinions_spec's harness).
    local function processed(stats, alloc)
        newBuild()
        local node = { id = "TEST-2h", alloc = alloc or 1, stats = stats, notScalingStats = {} }
        build.spec.tree:ProcessStats(node)
        return node
    end
    local function firstMod(node, name)
        for _, m in ipairs(node.modList) do
            if m.name == name then return m end
        end
        return nil
    end
    local function hasCondition(mod, var)
        for _, tag in ipairs(mod) do
            if tag.type == "Condition" and tag.var == var then return true end
        end
        return false
    end
    local function readSource(relPath)
        local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
        assert.is_not_nil(f, "cannot open " .. relPath)
        local s = f:read("*a"); f:close()
        return s
    end

    it("Master of Arms '+2 Strength With 2h Weapon' @8pts -> Str 16 with UsingTwoHandedWeapon", function()
        local node = processed({ "+2 Strength With 2h Weapon" }, 8)
        local m = firstMod(node, "Str")
        assert.is_not_nil(m, "the 2h-conditional Strength must be emitted (not dropped by '16h' mangling)")
        assert.are.equals(16, m.value, "value rank-scales 2*8=16 (the '2' in '2h' must NOT scale)")
        assert.is_true(hasCondition(m, "UsingTwoHandedWeapon"), "the UsingTwoHandedWeapon condition must survive rank scaling")
    end)

    it("another 2h node: '+8 Spell Damage With 2h Weapon' @5pts -> Damage 40, condition kept", function()
        local node = processed({ "+8 Spell Damage With 2h Weapon" }, 5)
        local m = firstMod(node, "Damage")
        assert.is_not_nil(m)
        assert.are.equals(40, m.value, "8*5=40")
        assert.is_true(hasCondition(m, "UsingTwoHandedWeapon"))
    end)

    it("ordinary numeric values still rank-scale (no over-guard)", function()
        local node = processed({ "+2 Strength" }, 8)
        local m = firstMod(node, "Str")
        assert.is_not_nil(m)
        assert.are.equals(16, m.value)
    end)

    it("inline guard marker present in PassiveTree.lua", function()
        local src = readSource("Classes/PassiveTree.lua")
        assert.is_true(src:find("tree-rank-scale-skip-weapon-hand-token", 1, true) ~= nil,
            "PassiveTree.lua must carry the inline guard marker")
    end)
end)
