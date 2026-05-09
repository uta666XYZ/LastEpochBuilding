local applyRangeTests = {
    [{ "+(10-20) Health", 128, 1.0, "Integer" }] = "+15 Health",
    [{ "(5-14)% increased Health", 96, 0.38 }] = "3% increased Health",
    [{ "(5-14)% increased Health", 96, 0.38, "Thousandth" }] = "3.2% increased Health",
    [{ "+(2-6) to All Attributes", 48, 1.0, "Integer" }] = "+2 to All Attributes",
    [{ "+(7-8) Attunement", 38, 1.5, "Integer" }] = "+10 Attunement",
    -- @leb-regression-guard: humble-idol-scalar-scale-first
    -- Humble Weaver Idol (scalar 0.38) on AL07Kea4. byte 221 must yield +3 and
    -- byte 98 must yield +2 to match the in-game tooltip; interpolating first
    -- then scaling under-rounds these to +2 / +1.
    [{ "+(3-7) Vitality", 221, 0.38, "Integer" }] = "+3 Vitality",
    [{ "+(3-7) Vitality", 98,  0.38, "Integer" }] = "+2 Vitality",
    -- @leb-regression-guard: apiarist-scalar-interpolate-first
    -- Apiarist's Suit (scalar 1.5) Strength "+(11-13)" at byte 57 must give
    -- +17 (interpolate-first); scaling endpoints first would give +16.
    [{ "+(11-13) to Strength", 57, 1.5, "Integer" }] = "+17 to Strength",
}

describe("TestItemTools", function()
    for args, expected in pairs(applyRangeTests) do
        it(string.format("tests applyRange('%s', %.2f, %.2f)", unpack(args)), function()
            local result = itemLib.applyRange(unpack(args))
            assert.are.equals(expected, result)
        end)
    end

    it("slotKeyForType maps item types to slot keys", function()
        assert.are.equals("helmet", itemLib.slotKeyForType("Helmet"))
        assert.are.equals("body_armor", itemLib.slotKeyForType("Body Armor"))
        assert.are.equals("amulet", itemLib.slotKeyForType("Amulet"))
        assert.are.equals("catalyst", itemLib.slotKeyForType("Off-Hand Catalyst"))
        assert.is_nil(itemLib.slotKeyForType("Weapon"))
        assert.is_nil(itemLib.slotKeyForType(nil))
    end)

    it("modLinesForSlot returns slot override when present", function()
        local mod = {
            [1] = "(10-12)% increased Health",
            slotOverrides = {
                body_armor = { [1] = "(15-18)% increased Health" },
            },
        }
        local lines = itemLib.modLinesForSlot(mod, "body_armor")
        assert.are.equals("(15-18)% increased Health", lines[1])
    end)

    it("modLinesForSlot falls back to default when slot has no override", function()
        local mod = {
            [1] = "(10-12)% increased Health",
            slotOverrides = {
                body_armor = { [1] = "(15-18)% increased Health" },
            },
        }
        local lines = itemLib.modLinesForSlot(mod, "helmet")
        assert.are.equals("(10-12)% increased Health", lines[1])
    end)

    it("modLinesForSlot falls back to default when mod has no slotOverrides", function()
        local mod = { [1] = "(10-12)% increased Health" }
        local lines = itemLib.modLinesForSlot(mod, "body_armor")
        assert.are.equals("(10-12)% increased Health", lines[1])
    end)

    it("body_armor override produces higher value than helmet default at max roll", function()
        -- Affix 52_4 ("of the Ox"): helmet (10-12)% vs body_armor (15-18)%
        local helmetLine = itemLib.applyRange("(10-12)% increased Health", 255, 1.0, "Integer")
        local bodyArmorLine = itemLib.applyRange("(15-18)% increased Health", 255, 1.0, "Integer")
        assert.are.equals("12% increased Health", helmetLine)
        assert.are.equals("18% increased Health", bodyArmorLine)
    end)

    -- @leb-regression-guard: applyrange-rounding-mode-split
    -- Locks in the two-mode contract:
    --   default (false) = floor = in-game match (production / GUI)
    --   HeadlessWrapper flip (true) = round-half-up = LETools-compat (spec/)
    -- See REGRESSION_GUARDS.md "applyrange-rounding-mode-split"
    -- Establishing commit: 73d6a712c
    --
    -- "% increased/reduced/more/less" affix rounding is mode-switched between
    -- in-game tooltip parity (floor, production default) and LETools/Maxroll
    -- parity (round-half-up, used by spec/ via HeadlessWrapper). The two
    -- diverge by 1 point on rolls whose interpolated value lands at >=.5 of
    -- the precision step. ShutFackUp Mercurial Shrine Boots
    -- "(20-24)% reduced Bonus Damage Taken from Critical Strikes" at range 49
    -- is the canonical case: raw 20 + 49/255*4 = 20.7686 → 20 vs 21.
    describe("applyRange rounding mode (production vs LETools)", function()
        -- Each test sets the flag explicitly and restores HeadlessWrapper's
        -- LETools default afterwards, so test ordering can't cross-contaminate.
        local function withMode(mode, fn)
            local prev = itemLib.useLEToolsRounding
            itemLib.useLEToolsRounding = mode
            local ok, err = pcall(fn)
            itemLib.useLEToolsRounding = prev
            if not ok then error(err) end
        end

        it("HeadlessWrapper enables LETools mode for spec/ runs", function()
            -- HeadlessWrapper.lua flips this on after Launch.lua loads so
            -- every applyRange-using fixture in spec/ keeps LETools rounding
            -- regardless of what the production default becomes.
            assert.is_true(itemLib.useLEToolsRounding)
        end)

        it("production (floor) matches in-game tooltip on % reduced affix", function()
            withMode(false, function()
                local line = itemLib.applyRange(
                    "(20-24)% reduced Bonus Damage Taken from Critical Strikes",
                    49, 1.0, "Integer")
                assert.are.equals(
                    "20% reduced Bonus Damage Taken from Critical Strikes", line)
            end)
        end)

        it("LETools mode (round-half-up) matches LETools display on the same affix", function()
            withMode(true, function()
                local line = itemLib.applyRange(
                    "(20-24)% reduced Bonus Damage Taken from Critical Strikes",
                    49, 1.0, "Integer")
                assert.are.equals(
                    "21% reduced Bonus Damage Taken from Critical Strikes", line)
            end)
        end)

        it("flat-value affixes are unaffected by the mode (always floor)", function()
            -- useRound is gated on `% (increased|reduced|more|less)`; flat
            -- numeric affixes always take the floor path. Both modes must
            -- produce identical output for "+(N-N) Mana" style mods.
            local floorLine, roundLine
            withMode(false, function()
                floorLine = itemLib.applyRange("+(17-26) Mana", 178, 1.0, "Integer")
            end)
            withMode(true, function()
                roundLine = itemLib.applyRange("+(17-26) Mana", 178, 1.0, "Integer")
            end)
            assert.are.equals(floorLine, roundLine)
        end)

        it("flat-percent affixes (no inc/red/more/less word) are unaffected", function()
            -- "% Critical Strike Multiplier" has a percent sign but no
            -- inc/red/more/less keyword, so useRound stays false in both
            -- modes and the value is floored.
            local floorLine, roundLine
            withMode(false, function()
                floorLine = itemLib.applyRange(
                    "+(50-60)% Critical Strike Multiplier", 76, 1.0, "Integer")
            end)
            withMode(true, function()
                roundLine = itemLib.applyRange(
                    "+(50-60)% Critical Strike Multiplier", 76, 1.0, "Integer")
            end)
            assert.are.equals(floorLine, roundLine)
        end)
    end)

    -- @leb-regression-guard: applyrange-fixed-tier-noop
    -- Locks in the contract that `applyRange` leaves fixed-value tier
    -- text (no `(min-max)` pattern) unchanged regardless of the byte
    -- passed as `range`. LETools T1-T7 corrupted tiers of affix 1011
    -- (`+N All Attributes with at least 7 Corrupted non-Idol Items
    -- equipped`) are FIXED 8/9/10/11/12/13/14; only T8 (primordial-only)
    -- carries the `(19-21)` roll range. A misstated REGRESSION_GUARDS
    -- claim that `1011_6 @ range 221 → +11` triggered a bogus
    -- investigation 2026-05-08; this spec prevents the same mistake
    -- from re-entering the codebase via a "scale fixed values too"
    -- patch to applyRange.
    -- See REGRESSION_GUARDS.md "applyrange-fixed-tier-noop".
    describe("applyRange leaves fixed-value tier text unchanged", function()
        local fixedT7 =
            "+14 All Attributes with at least 7 Corrupted non-Idol Items equipped"
        local rangedT8 =
            "+(19-21) All Attributes with at least 7 Corrupted non-Idol Items equipped"

        it("affix 1011 T7 (fixed +14) ignores the range byte", function()
            for _, byte in ipairs({ 0, 64, 128, 221, 255 }) do
                local line = itemLib.applyRange(fixedT7, byte, 1.0, "Integer")
                assert.are.equals(fixedT7, line,
                    "range byte " .. byte .. " mutated a fixed-tier line")
            end
        end)

        it("affix 1011 T8 (range 19-21) still interpolates as expected", function()
            -- T8 IS primordial-only; sanity-check that the (min-max)
            -- path still works so the "fixed" guard above isn't hiding
            -- a broken interpolator. byte=0 → min, byte=255 → max.
            local lo = itemLib.applyRange(rangedT8, 0, 1.0, "Integer")
            assert.are.equals(
                "+19 All Attributes with at least 7 Corrupted non-Idol Items equipped",
                lo)
            local hi = itemLib.applyRange(rangedT8, 255, 1.0, "Integer")
            assert.are.equals(
                "+21 All Attributes with at least 7 Corrupted non-Idol Items equipped",
                hi)
        end)

        it("a generic fixed flat-value line is unaffected by range bytes", function()
            -- Same contract, decoupled from the 1011 affix family so a
            -- future rename of the Shroud affix can't silently weaken
            -- the guard.
            local fixed = "+8 to Strength"
            for _, byte in ipairs({ 0, 50, 200, 255 }) do
                assert.are.equals(fixed,
                    itemLib.applyRange(fixed, byte, 1.0, "Integer"))
            end
        end)
    end)

    -- @leb-regression-guard: vshdm-direct-port
    -- Locks in the game-faithful interpolation formula. These cases were
    -- cross-verified against (a) the LE planner JS function `vshDm` decoded
    -- from planner_app.js 2026-05-09, (b) the IL2CPP dump
    -- `BaseStats.GetValueAfterRounding` at RVA 0x230B940, and (c) a Python
    -- reference implementation at .tmp/vshdm_verify.py.
    --
    -- ModType: 0=ADDED 1=INCREASED 2=MORE 3=QUOTIENT
    -- Rounding: 0=Hundredth 1=Integer 2=Tenth 3=Thousandth
    describe("applyRangeStrict (vshDm direct port)", function()
        it("Hundredth-ADDED reproduces BEdKNL0j relic Phys Res 14-28 byte=100 = 19.49", function()
            -- Mirrors the in-game tooltip base-interp for SP=64 (Phys Res),
            -- ModType=ADDED, rounding=Hundredth. Display "26%" on tooltip is
            -- legendary/effectiveness multiplier, not base interpolation.
            local v = itemLib.applyRangeStrict(14, 28, 100, 1.0, 0, 0)
            assert.are.equals(19.49, v)
        end)

        it("Integer-ADDED interpolates with span+1 so top byte reaches max", function()
            -- "+(2-5) Skill Levels" byte=255 must yield 5 (capped by min(v,d)).
            -- Without the +1/precision span bump the top byte falls short of
            -- max; without the min(v,d) clamp it overshoots to 6.
            assert.are.equals(5, itemLib.applyRangeStrict(2, 5, 255, 1.0, 0, 1))
            -- Mid-byte: floor((4+1-2)*90/255 + 2) = floor(1.058 + 2) = 3
            assert.are.equals(3, itemLib.applyRangeStrict(2, 4, 90, 1.0, 0, 1))
        end)

        it("non-ADDED branch is forced to Hundredth+epsilon regardless of rounding arg", function()
            -- Even if caller passes rounding=Integer (1), modType != 0 must
            -- override and use Hundredth precision with the +0.001 epsilon.
            -- byte=128: e=0.50196; (50.01 * 0.50196 + 50.001) = 75.103
            --   floor(100 * 75.103) / 100 = 75.10
            local v = itemLib.applyRangeStrict(50, 100, 128, 1.0, 1, 1)
            assert.are.equals(75.10, v)
        end)

        it("Tenth precision rounds to nearest 0.1", function()
            -- (1.0-2.5) byte=128: c=1.0 d=2.5 v=floor(10*((2.5+0.1-1.0)*0.5019+1.0))/10
            --   = floor(10*(0.8030+1.0))/10 = floor(18.030)/10 = 1.8
            assert.are.equals(1.8, itemLib.applyRangeStrict(1.0, 2.5, 128, 1.0, 0, 2))
        end)

        it("scalar < 1.0 (Humble idol) scales endpoints first", function()
            -- AL07Kea4 Humble Weaver +(3-7) Vitality byte=221 scalar=0.38:
            -- minN=1.14, maxN=2.66; rounded=1, 3 (Integer); span+1 = 3
            -- v = floor(3 * 221/255 + 1) = floor(2.6 + 1) = 3
            assert.are.equals(3, itemLib.applyRangeStrict(3, 7, 221, 0.38, 0, 1))
        end)

        it("scalar > 1.0 (Apiarist) scales then rounds (interpolation grid shifts)", function()
            -- Apiarist +(11-13) Strength byte=57 scalar=1.5:
            -- scaled minN=16.5, maxN=19.5 -> half-up to 17, 20; span+1 = 4
            -- v = floor(4 * 57/255 + 17) = floor(0.894 + 17) = 17
            assert.are.equals(17, itemLib.applyRangeStrict(11, 13, 57, 1.5, 0, 1))
        end)
    end)
end)
