-- @leb-regression-guard: totem-damage-minion-scope
-- Locks the parser contract that totem-scoped damage tree-node stats route to
-- the TOTEM minion family instead of leaking onto the player:
--   "+1 Totem Spell Damage"       - Primalist-115 "Elder Branch" (tree_0.json;
--     node description "You and your totems deal additional spell damage.";
--     the sibling stat "+1 Spell Damage" is the player half)
--   "+10% Increased Totem Damage" - Primalist-35 "Fate Carver" (tree_0.json)
--
-- Before the fix, Data/ModCache.lua baked both strings as PLAYER-scoped Damage
-- mods with the "Totem" scope eaten into parse residue:
--   c["+1 Totem Spell Damage"]={{...name="Damage",type="BASE"...}},"tem   "}
--   c["+10% Increased Totem Damage"]={{...name="Damage",type="INC"...}}," Totem  "}
-- silent-failure parser fallthrough: the bonus landed on the player's main
-- skill and the totems got nothing. The fix mirrors
-- @leb-regression-guard:crit-for-totems-per-int-and-multi - two specialModList
-- patterns emit a MinionModifier LIST with minionTypes = the 8-key totem
-- family; CalcPerform dispatch (`minion-modifier-multi-type-gate`) routes it.
--
-- ModCache note: the two stale rows are REMOVED (not patched) so the strings
-- live-parse; that also covers the point-scaled variants ("+2".."+5" Totem
-- Spell Damage, "+20%".."+80%" Increased Totem Damage) that were never baked.
-- The Elder Branch companion stat " Tripled while using an Axe" stays
-- recognition-only (no-op, zero mods) - the tripling is NOT modeled. The
-- sibling "on Hit" rows ("+1 Totem Spell/Melee Damage on Hit") are a different
-- stat family and stay baked; the `$`-anchored patterns cannot match them.
--
-- No corpus build allocates either node (grep Primalist-115 / Primalist-35
-- over spec/TestBuilds 2026-06-11: zero hits), so zero snapshot impact.
--
-- See REGRESSION_GUARDS.md > "totem-damage-minion-scope".

local TOTEM_FAMILY = {
    "Frenzy Totem",
    "Thorn Totem",
    "StormTotem",
    "HealingTotem",
    "ClawTotem",
    "TempestTotem",
    "WarcryTotem",
    "UpheavalTotem",
}

local function assertTotemMinionModifier(mods, extra)
    assert.is_nil(extra, "a fully-parsed totem damage line must leave no residue")
    assert.are.equals(1, #mods)
    local m = mods[1]
    assert.are.equals("MinionModifier", m.name)
    assert.are.equals("LIST", m.type)
    assert.is_table(m.value)
    assert.is_table(m.value.minionTypes, "must carry the totem-family minionTypes array")
    assert.are.equals(#TOTEM_FAMILY, #m.value.minionTypes)
    for i, key in ipairs(TOTEM_FAMILY) do
        assert.are.equals(key, m.value.minionTypes[i],
            "minionTypes[" .. i .. "] must be the minions.json totem key")
    end
    return m
end

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("TotemDamageMinionScope", function()
    before_each(function()
        newBuild()
    end)

    it("'+1 Totem Spell Damage' live-parses to a Spell-flagged Damage BASE for the totem family", function()
        local mods, extra = modLib.parseMod("+1 Totem Spell Damage")
        local m = assertTotemMinionModifier(mods, extra)
        local inner = m.value.mod
        assert.are.equals("Damage", inner.name)
        assert.are.equals("BASE", inner.type)
        assert.are.equals(1, inner.value)
        assert.are.equals(0, inner.flags)
        assert.are.equals(KeywordFlag.Spell, inner.keywordFlags,
            "flat totem spell damage must keep the Spell keyword flag (was keywordFlags=256 in the old baked row)")
    end)

    it("'+10% Increased Totem Damage' live-parses to a Damage INC for the totem family", function()
        local mods, extra = modLib.parseMod("+10% Increased Totem Damage")
        local m = assertTotemMinionModifier(mods, extra)
        local inner = m.value.mod
        assert.are.equals("Damage", inner.name)
        assert.are.equals("INC", inner.type)
        assert.are.equals(10, inner.value)
        assert.are.equals(0, inner.flags)
        assert.are.equals(0, inner.keywordFlags)
    end)

    it("point-scaled variants (never baked) parse through the same handlers", function()
        -- Elder Branch maxPoints=5, Fate Carver maxPoints=8 => the tree
        -- presents scaled strings that ModCache never carried.
        local m5 = assertTotemMinionModifier(modLib.parseMod("+5 Totem Spell Damage"))
        assert.are.equals(5, m5.value.mod.value)
        assert.are.equals("BASE", m5.value.mod.type)
        local m80 = assertTotemMinionModifier(modLib.parseMod("+80% Increased Totem Damage"))
        assert.are.equals(80, m80.value.mod.value)
        assert.are.equals("INC", m80.value.mod.type)
    end)

    it("the player no longer receives the Damage mod from either line", function()
        local node = { modList = new("ModList") }
        for _, line in ipairs({ "+1 Totem Spell Damage", "+10% Increased Totem Damage" }) do
            local mods = modLib.parseMod(line)
            for _, m in ipairs(mods) do node.modList:AddMod(m) end
        end
        -- Pre-fix these summed 1 / 10 onto the player's own Damage stat.
        assert.are.equals(0, node.modList:Sum("BASE", nil, "Damage"),
            "flat totem spell damage must not land on the player")
        assert.are.equals(0, node.modList:Sum("INC", nil, "Damage"),
            "increased totem damage must not land on the player")
    end)

    it("ModCache no longer carries the stale player-scoped rows", function()
        local cacheText = readSource("Data/ModCache.lua")
        assert.is_nil(string.find(cacheText,
            'c["+1 Totem Spell Damage"]=', 1, true),
            "the stale '+1 Totem Spell Damage' row must be removed so the line live-parses")
        assert.is_nil(string.find(cacheText,
            'c["+10% Increased Totem Damage"]=', 1, true),
            "the stale '+10% Increased Totem Damage' row must be removed so the line live-parses")
    end)

    it("Elder Branch ' Tripled while using an Axe' companion stat stays recognition-only (no mods)", function()
        -- Documented limitation: the axe tripling is NOT modeled. The line must
        -- keep producing zero mods (and in particular must never start emitting
        -- a player-scoped Damage mod by accident).
        local mods = modLib.parseMod(" Tripled while using an Axe")
        assert.are.equals(0, #mods)
    end)

    it("the '$' anchors do not swallow the sibling 'on Hit' stat family", function()
        -- "+1 Totem Spell Damage on Hit" is a DIFFERENT stat (still baked,
        -- player-scoped, out of this guard's scope). The new handlers must not
        -- match it - it must keep its old baked shape, not a MinionModifier.
        local mods = modLib.parseMod("+1 Totem Spell Damage on Hit")
        for _, m in ipairs(mods) do
            assert.are_not.equals("MinionModifier", m.name,
                "the on-Hit family must not be rerouted by the anchored totem handlers")
        end
    end)
end)
