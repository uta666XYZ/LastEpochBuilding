-- @leb-regression-guard:elemental-arrows-resource (busted spec)
-- Rogue/Marksman "Elemental Arrows" resource: bow attacks consume Elemental Arrows and each
-- consumed arrow adds fire+lightning + increased-elemental (game Property_Player_113/115).
-- Before this fix LEB dropped the "... with Elemental Arrow" / "... per Elemental Arrow used"
-- tree stats entirely (no skill named "Elemental Arrow") -> AmHoA Hail of Arrows lightning was
-- ~4.8x UNDER in-game. Root: datamined game source Property_Player_109-115; validated on AmHoA save
-- (lightning HitAverage 3105 -> 16354 vs in-game mean 14870 = 1.10x).
describe("TestElementalArrows", function()
    before_each(function()
        newBuild()
    end)

    local function apply(mods)
        build.configTab.input.customMods = mods
        build.configTab:BuildModList()
        build.buildFlag = true
        runCallback("OnFrame")
    end

    it("computes consumed count = 1 base + extra-consumed, capped at max", function()
        -- Rogue-32 Elemental Barrage: +2 consumed. Base game cap = 3.
        apply("+2 Elemental Arrow consumed per bow attack")
        local modDB = build.calcsTab.calcsEnv.player.modDB
        assert.are.equals(2, modDB:Sum("BASE", nil, "ElementalArrowExtraConsume"))
        -- 1 (base) + 2 (extra) = 3, at/under the cap of 3
        assert.are.equals(3, modDB:Sum("BASE", nil, "Multiplier:ElementalArrowConsumed"))
    end)

    it("caps consumed at the game-base maximum of 3", function()
        -- An over-large extra-consume must not exceed the max cap.
        apply("+9 Elemental Arrow consumed per bow attack")
        local modDB = build.calcsTab.calcsEnv.player.modDB
        assert.are.equals(3, modDB:Sum("BASE", nil, "Multiplier:ElementalArrowConsumed"))
    end)

    it("does NOT trigger for builds without the Elemental Arrows mechanism", function()
        apply("+100 Health")
        local modDB = build.calcsTab.calcsEnv.player.modDB
        assert.are.equals(0, modDB:Sum("BASE", nil, "Multiplier:ElementalArrowConsumed"))
    end)

    it("parses '+X Fire/Lightning Damage with Elemental Arrow' as per-consumed-arrow added", function()
        -- Rogue-24 Elemental Arrows (8 pts) = +24 fire + +24 lightning per arrow used.
        apply("+24 Fire Damage with Elemental Arrow\n\z
               +24 Lightning Damage with Elemental Arrow\n\z
               +2 Elemental Arrow consumed per bow attack")
        local modDB = build.calcsTab.calcsEnv.player.modDB
        -- consumed = 3, so the added scales 24 -> 72 for each element.
        assert.are.equals(3, modDB:Sum("BASE", nil, "Multiplier:ElementalArrowConsumed"))
        assert.are.equals(72, modDB:Sum("BASE", nil, "FireDamage"))
        assert.are.equals(72, modDB:Sum("BASE", nil, "LightningDamage"))
    end)

    -- @leb-regression-guard:elemental-arrows-resource (ModCache shadow)
    -- ModCache.lua carried stale pre-fix entries for the per-point Elemental Arrows lines --
    -- empty modlists for the resource-config stats ("3 Maximum Elemental Arrows", "+1 Elemental
    -- Arrow consumed per bow attack", ...) and tag-less mods for the per-arrow added / increased
    -- lines. parseMod is cache-first, so those entries shadowed the live ModParser rules for any
    -- node rank whose exact text matched (the v1 "max parses unreliably" limitation): a Rogue-24-
    -- only build (no Elemental Barrage) got Multiplier:ElementalArrowConsumed = 0 and lost its
    -- +24 fire/+24 lightning entirely. The 7 stale entries are DELETED; these tests go through
    -- the normal cache-first parseMod path to lock that nothing shadows the live rules again.
    it("parses the resource-config lines through the cache-first path", function()
        local mods = modLib.parseMod("3 Maximum Elemental Arrows")
        assert.is_not_nil(mods)
        assert.are.equals("ElementalArrowMax", mods[1].name)
        assert.are.equals(3, mods[1].value)

        mods = modLib.parseMod("+1 Elemental Arrow consumed per bow attack")
        assert.is_not_nil(mods)
        assert.are.equals("ElementalArrowExtraConsume", mods[1].name)
        assert.are.equals(1, mods[1].value)
    end)

    it("parses the per-point added/increased lines with their arrow tags (cache-first path)", function()
        -- 1-pt Rogue-24: the added must carry the per-consumed-arrow Multiplier.
        local mods = modLib.parseMod("+3 Fire Damage with Elemental Arrow")
        assert.is_not_nil(mods)
        assert.are.equals("FireDamage", mods[1].name)
        assert.are.equals("Multiplier", mods[1][1].type)
        assert.are.equals("ElementalArrowConsumed", mods[1][1].var)

        -- 1-pt Rogue-35: the increased must be Condition-gated (x1), not unconditional.
        mods = modLib.parseMod("25% Increased Elemental Damage with Elemental Arrow")
        assert.is_not_nil(mods)
        assert.are.equals("Condition", mods[1][1].type)
        assert.are.equals("HaveElementalArrows", mods[1][1].var)
    end)

    it("triggers the mechanism for a Rogue-24-only build (max cap parsed, no Elemental Barrage)", function()
        -- No extra-consume source: detection must come from the max-cap stat alone, and the
        -- steady-state consumed count is the 1 base arrow.
        apply("3 Maximum Elemental Arrows\n\z
               +24 Fire Damage with Elemental Arrow\n\z
               +24 Lightning Damage with Elemental Arrow")
        local modDB = build.calcsTab.calcsEnv.player.modDB
        assert.are.equals(3, modDB:Sum("BASE", nil, "ElementalArrowMax"))
        assert.are.equals(1, modDB:Sum("BASE", nil, "Multiplier:ElementalArrowConsumed"))
        -- per-arrow added scales x1 (one arrow consumed per attack)
        assert.are.equals(24, modDB:Sum("BASE", nil, "FireDamage"))
        assert.are.equals(24, modDB:Sum("BASE", nil, "LightningDamage"))
    end)

    it("scopes the per-arrow ADDED to the 'with Elemental Arrow' phrasing, not the increased", function()
        -- Rogue-35 "125% increased Elemental Damage with Elemental Arrow" is a x1 Condition
        -- (HaveElementalArrows), NOT per-arrow -- applying it x consumed over-shot AmHoA in-game
        -- lightning ~1.6x (non-crit floor 9681 / median 10384 match added-x3 + increased-x1).
        -- The "with elemental arrow" phrase does NOT attach the ElementalArrowConsumed Multiplier
        -- to a non-added line (only the specialModList "+N <type> damage with elemental arrow"
        -- added lines carry it). Assert the increased line does NOT gain the per-arrow Multiplier.
        apply("125% increased Elemental Damage with Elemental Arrow\n\z
               +2 Elemental Arrow consumed per bow attack")
        local modDB = build.calcsTab.calcsEnv.player.modDB
        -- Multiplier still computed (=3) for the ADDED path, but the increased line must NOT
        -- have produced a x3 (375) elemental-increased -- verified in-game via ProbePreMitHit
        -- (FireINC 772 -> 897 = +125 x1, NOT +375).
        assert.are.equals(3, modDB:Sum("BASE", nil, "Multiplier:ElementalArrowConsumed"))
        assert.is_true(modDB:Sum("INC", nil, "ElementalDamage") ~= 375,
            "increased elemental with elemental arrow must apply x1, not x consumed")
    end)
end)
