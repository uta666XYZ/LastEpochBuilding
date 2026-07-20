-- @leb-regression-guard:per-mana-cost-melee-affix
-- Locks the "X% [Damage/Crit/Area] for Melee ... per 1 Mana Cost" affix family.
-- These were mis-modelled corpus-wide: the ModCache bake scoped them to
-- SkillName "Melee Attack" (the BASIC attack only, so they applied to nothing on
-- Warpath / Forge Strike / Rive etc.) AND dropped both the per-mana scaling and
-- the "(up to 20)" cap -> they contributed ~0. Fix: scope to the Melee KEYWORD and
-- scale by the active skill's Mana cost via a PerStat:ManaCost tag (limit 20 on the
-- Damage prefix which alone carries "(up to 20)"). The basis is output.ManaCost,
-- which for the channeled Warpath is the ability's nominal manaCost field = 1
-- (datamine ability_attribute_scaling.json va53st manaCost 1.0, NOT channelCost 18,
-- NOT 0; confirmed in-engine by spec/tools/ProbePerManaBasis.lua: Warpath
-- output.ManaCost 1, Forge Strike 20). Shares the basis with the Brutality attribute
-- intrinsic (CalcOffence brutality-per-manacost-melee-more).
-- See ModParser.lua / ModCache.lua "per-mana-cost-melee-affix" anchors and
-- REGRESSION_GUARDS.md > "per-mana-cost-melee-affix".

local function findPerStat(mod, stat)
    for _, tag in ipairs(mod) do
        if tag.type == "PerStat" and tag.stat == stat then return tag end
    end
end

describe("PerManaCostMeleeAffix", function()
    before_each(function()
        newBuild()
    end)

    it("Damage prefix -> Damage MORE, Melee flag, PerStat:ManaCost limit 20, no residue", function()
        local mods, extra = modLib.parseMod("+0.2% Damage for Melee Attacks per 1 Mana Cost (up to 20)")
        assert.is_nil(extra, "fully-parsed affix must leave no residue (else PassiveTree drops it)")
        assert.are.equals(1, #mods)
        assert.are.equals("Damage", mods[1].name)
        assert.are.equals("MORE", mods[1].type)
        assert.are.equals(0.2, mods[1].value)
        assert.are.equals(ModFlag.Melee, mods[1].flags, "must scope to the Melee KEYWORD, not SkillName Melee Attack")
        local tag = findPerStat(mods[1], "ManaCost")
        assert.is_not_nil(tag, "must scale by the skill's Mana cost")
        assert.are.equals(1, tonumber(tag.div))
        assert.are.equals(20, tonumber(tag.limit), "the Damage prefix caps at 20 (game '(up to 20)')")
    end)

    it("Critical Strike Chance variant (live ModParser roll) -> CritChance BASE, Melee, PerStat:ManaCost, no cap", function()
        -- A rolled value (0.28) is not a baked ModCache key, so this exercises the
        -- live ModParser special pattern.
        local mods, extra = modLib.parseMod("+0.28% Critical Strike Chance for Melee Attacks per 1 Mana Cost")
        assert.is_nil(extra)
        assert.are.equals("CritChance", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(0.28, mods[1].value)
        assert.are.equals(ModFlag.Melee, mods[1].flags)
        local tag = findPerStat(mods[1], "ManaCost")
        assert.is_not_nil(tag)
        assert.is_nil(tag.limit, "the crit variant has no '(up to 20)' text -> no cap")
    end)

    it("Area variant -> AreaOfEffect INC, Melee keywordFlag, PerStat:ManaCost", function()
        local mods, extra = modLib.parseMod("+2% increased Area for Melee Area Skills per 1 Mana Cost")
        assert.is_nil(extra)
        assert.are.equals("AreaOfEffect", mods[1].name)
        assert.are.equals("INC", mods[1].type)
        assert.are.equals(2, mods[1].value)
        assert.are.equals(KeywordFlag.Melee, mods[1].keywordFlags)
        assert.is_not_nil(findPerStat(mods[1], "ManaCost"))
    end)

    it("Damage MORE scales by Mana cost and caps at 20", function()
        local db = new("ModDB")
        db.actor = { output = { ManaCost = 20 }, modDB = db }
        db:NewMod("Damage", "MORE", 0.2, "PerMana", ModFlag.Melee, { type = "PerStat", stat = "ManaCost", div = 1, limit = 20 })
        assert.are.equals(1.04, round(db:More({ flags = ModFlag.Melee }, "Damage"), 2),
            "0.2% x min(20,20) = +4% MORE")
    end)

    it("cap binds above 20 mana cost", function()
        local db = new("ModDB")
        db.actor = { output = { ManaCost = 100 }, modDB = db }
        db:NewMod("Damage", "MORE", 0.2, "PerMana", ModFlag.Melee, { type = "PerStat", stat = "ManaCost", div = 1, limit = 20 })
        assert.are.equals(1.04, round(db:More({ flags = ModFlag.Melee }, "Damage"), 2),
            "min(100,20)=20 -> still +4% (the '(up to 20)' cap)")
    end)

    it("channel basis: Warpath-style ManaCost 1 gives a tiny (not zero, not x18) bonus", function()
        local db = new("ModDB")
        db.actor = { output = { ManaCost = 1 }, modDB = db }
        -- use a visible coefficient so the sub-percent rounding does not hide the basis
        db:NewMod("Damage", "MORE", 10, "PerMana", ModFlag.Melee, { type = "PerStat", stat = "ManaCost", div = 1, limit = 20 })
        assert.are.equals(1.10, round(db:More({ flags = ModFlag.Melee }, "Damage"), 2),
            "basis is the nominal manaCost=1 (channelCost 18 would give x2.8)")
    end)

    it("contributes nothing at ManaCost 0 (mana-gated, not flat)", function()
        local db = new("ModDB")
        db.actor = { output = { ManaCost = 0 }, modDB = db }
        db:NewMod("Damage", "MORE", 10, "PerMana", ModFlag.Melee, { type = "PerStat", stat = "ManaCost", div = 1, limit = 20 })
        assert.are.equals(1, db:More({ flags = ModFlag.Melee }, "Damage"))
    end)

    it("Melee-scoped: applies to a melee skill, not to a spell", function()
        local db = new("ModDB")
        db.actor = { output = { ManaCost = 20 }, modDB = db }
        db:NewMod("Damage", "MORE", 0.2, "PerMana", ModFlag.Melee, { type = "PerStat", stat = "ManaCost", div = 1, limit = 20 })
        assert.are.equals(1.04, round(db:More({ flags = ModFlag.Melee }, "Damage"), 2), "melee skill gets it")
        assert.are.equals(1, db:More({ flags = ModFlag.Spell }, "Damage"), "spell skill excluded")
    end)

    it("Crit BASE scales by Mana cost (uncapped)", function()
        local db = new("ModDB")
        db.actor = { output = { ManaCost = 20 }, modDB = db }
        db:NewMod("CritChance", "BASE", 0.28, "PerMana", ModFlag.Melee, { type = "PerStat", stat = "ManaCost", div = 1 })
        assert.are.equals(5.6, round(db:Sum("BASE", { flags = ModFlag.Melee }, "CritChance"), 2),
            "0.28 x 20 = +5.6% base crit chance")
    end)

    -- @leb-regression-guard: per-mana-cost-melee-affix-fractional-precision
    -- itemLib.applyRange's generic "% => integer percent" collapse (default
    -- rounding => precision 100, then /100 => 1) inflated the FRACTIONAL
    -- per-mana sub-line under a weapon-slot scalar: 0.3 x 1.829 = 0.549 was
    -- round-half-up'd to 1 (~3-5x too high). The "per 1 Mana Cost" family must
    -- keep sub-integer precision so the scaled fraction survives.
    describe("applyRange keeps the fractional per-mana value (no integer collapse)", function()
        it("Damage per-mana at weapon scalar 1.829 stays fractional (0.3 -> 0.55, not 1)", function()
            local out = itemLib.applyRange("+0.3% Damage for Melee Attacks per 1 Mana Cost (up to 20)", 54, 1.829)
            assert.are.equals("+0.55% Damage for Melee Attacks per 1 Mana Cost (up to 20)", out)
        end)
        it("Damage per-mana at scalar 1.0 is unchanged (0.3)", function()
            local out = itemLib.applyRange("+0.3% Damage for Melee Attacks per 1 Mana Cost (up to 20)", 54, 1.0)
            assert.are.equals("+0.3% Damage for Melee Attacks per 1 Mana Cost (up to 20)", out)
        end)
        it("Crit per-mana range respects {rounding:Thousandth} (not collapsed to Tenth)", function()
            -- YsAberrothKiller slot roll: {range:143}{rounding:Thousandth}+(0.2-0.3)%
            local out = itemLib.applyRange("+(0.2-0.3)% Critical Strike Chance for Melee Attacks per 1 Mana Cost", 143, 1.0, "Thousandth")
            assert.are.equals("+0.256% Critical Strike Chance for Melee Attacks per 1 Mana Cost", out)
        end)
        it("regression: a normal '% increased Melee Damage' still rounds to integer percent", function()
            local out = itemLib.applyRange("(20-30)% increased Melee Damage", 54, 1.829)
            assert.are.equals("40% increased Melee Damage", out)
        end)
    end)
end)
