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
end)
