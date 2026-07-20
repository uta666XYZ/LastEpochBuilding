-- @leb-regression-guard: stormcarved-for-totems-scope
-- The fix mirrors @leb-regression-guard:crit-for-totems-per-int-and-multi and
-- @leb-regression-guard:totem-damage-minion-scope: four $-anchored specialModList
-- See REGRESSION_GUARDS.md > "stormcarved-for-totems-scope".
-- Validation provenance is retained in maintainer notes.

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
    assert.is_nil(extra, "a fully-parsed 'for Totems' line must leave no residue")
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

describe("StormcarvedForTotemsScope", function()
    before_each(function()
        newBuild()
    end)

    it("'+12% Lightning Penetration for Totems' -> LightningPenetration BASE for the totem family", function()
        local mods, extra = modLib.parseMod("+12% Lightning Penetration for Totems")
        local m = assertTotemMinionModifier(mods, extra)
        local inner = m.value.mod
        assert.are.equals("LightningPenetration", inner.name)
        assert.are.equals("BASE", inner.type)
        assert.are.equals(12, inner.value)
        assert.are.equals(0, inner.flags)
        assert.are.equals(0, inner.keywordFlags)
    end)

    it("'+6 Spell Lightning Damage for Totems' -> Spell-flagged LightningDamage BASE for the totem family", function()
        local mods, extra = modLib.parseMod("+6 Spell Lightning Damage for Totems")
        local m = assertTotemMinionModifier(mods, extra)
        local inner = m.value.mod
        assert.are.equals("LightningDamage", inner.name)
        assert.are.equals("BASE", inner.type)
        assert.are.equals(6, inner.value)
        assert.are.equals(0, inner.flags)
        assert.are.equals(KeywordFlag.Spell, inner.keywordFlags,
            "flat spell lightning damage must keep the Spell keyword flag (was keywordFlags=256 in the old baked row)")
    end)

    it("'+77% Chance to Shock on Hit for Totems' -> Hit-flagged Shock chance BASE for the totem family", function()
        local mods, extra = modLib.parseMod("+77% Chance to Shock on Hit for Totems")
        local m = assertTotemMinionModifier(mods, extra)
        local inner = m.value.mod
        assert.are.equals("ChanceToTriggerOnHit_Ailment_Shock", inner.name)
        assert.are.equals("BASE", inner.type)
        assert.are.equals(77, inner.value)
        assert.are.equals(ModFlag.Hit, inner.flags,
            "chance to shock on hit must keep the Hit flag (was flags=8388608 in the old baked row)")
        assert.are.equals(0, inner.keywordFlags)
    end)

    it("'+40% Lightning Resistance for Totems' -> LightningResist BASE for the totem family", function()
        local mods, extra = modLib.parseMod("+40% Lightning Resistance for Totems")
        local m = assertTotemMinionModifier(mods, extra)
        local inner = m.value.mod
        assert.are.equals("LightningResist", inner.name)
        assert.are.equals("BASE", inner.type)
        assert.are.equals(40, inner.value)
        assert.are.equals(0, inner.flags)
        assert.are.equals(0, inner.keywordFlags)
    end)

    it("rolled values (never baked) parse through the same handlers", function()
        local mShock = assertTotemMinionModifier(modLib.parseMod("+94% Chance to Shock on Hit for Totems"))
        assert.are.equals(94, mShock.value.mod.value)
        assert.are.equals("ChanceToTriggerOnHit_Ailment_Shock", mShock.value.mod.name)
        local mRes = assertTotemMinionModifier(modLib.parseMod("+36% Lightning Resistance for Totems"))
        assert.are.equals(36, mRes.value.mod.value)
        assert.are.equals("LightningResist", mRes.value.mod.name)
    end)

    it("the player no longer receives any of the four leaked stats", function()
        local node = { modList = new("ModList") }
        local lines = {
            "+12% Lightning Penetration for Totems",
            "+6 Spell Lightning Damage for Totems",
            "+77% Chance to Shock on Hit for Totems",
            "+40% Lightning Resistance for Totems",
        }
        for _, line in ipairs(lines) do
            local mods = modLib.parseMod(line)
            for _, m in ipairs(mods) do node.modList:AddMod(m) end
        end
        -- Pre-fix these summed onto the player's own stats.
        assert.are.equals(0, node.modList:Sum("BASE", nil, "LightningPenetration"),
            "lightning penetration for totems must not land on the player")
        assert.are.equals(0, node.modList:Sum("BASE", { flags = ModFlag.Hit }, "ChanceToTriggerOnHit_Ailment_Shock"),
            "shock chance for totems must not land on the player")
        assert.are.equals(0, node.modList:Sum("BASE", nil, "LightningResist"),
            "lightning resistance for totems must not land on the player")
        assert.are.equals(0, node.modList:Sum("BASE", { keywordFlags = KeywordFlag.Spell }, "LightningDamage"),
            "spell lightning damage for totems must not land on the player")
    end)

    it("the bare player-sibling lines (no 'for Totems') still land on the player", function()
        -- The anchored 'for totems' handlers must not disturb the base parse of
        -- the sibling stats Stormcarved also carries player-side.
        local penMods = modLib.parseMod("+12% Lightning Penetration")
        local node = { modList = new("ModList") }
        for _, m in ipairs(penMods) do node.modList:AddMod(m) end
        assert.are.equals(12, node.modList:Sum("BASE", nil, "LightningPenetration"),
            "the player-sibling '+12% Lightning Penetration' must still apply to the player")
    end)

    it("ModCache no longer carries the stale player-scoped rows", function()
        local cacheText = readSource("Data/ModCache.lua")
        for _, key in ipairs({
            'c["+12% Lightning Penetration for Totems"]=',
            'c["+14% Lightning Penetration for Totems"]=',
            'c["+6 Spell Lightning Damage for Totems"]=',
            'c["+77% Chance to Shock on Hit for Totems"]=',
            'c["+40% Lightning Resistance for Totems"]=',
        }) do
            assert.is_nil(string.find(cacheText, key, 1, true),
                "stale ModCache row must be removed so the line live-parses: " .. key)
        end
    end)
end)
