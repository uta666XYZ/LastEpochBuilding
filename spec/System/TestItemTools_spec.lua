local applyRangeTests = {
    [{ "+(10-20) Health", 128, 1.0, "Integer" }] = "+15 Health",
    [{ "(5-14)% increased Health", 96, 0.38 }] = "3% increased Health",
    [{ "(5-14)% increased Health", 96, 0.38, "Thousandth" }] = "3.2% increased Health",
    [{ "+(2-6) to All Attributes", 48, 1.0, "Integer" }] = "+2 to All Attributes",
    [{ "+(7-8) Attunement", 38, 1.5, "Integer" }] = "+10 Attunement",
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
end)
