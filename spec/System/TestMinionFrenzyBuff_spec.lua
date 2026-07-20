-- @leb-regression-guard:minion-frenzy-multiplicative
-- cadence measurement. See REGRESSION_GUARDS.md `minion-frenzy-multiplicative`.
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("MinionFrenzyBuff", function()
    local configText

    setup(function()
        configText = readSource("Modules/ConfigOptions.lua")
    end)

    it("ConfigOptions: exposes the minionsConditionFrenzy toggle with the guard marker", function()
        assert.is_truthy(configText:find('@leb%-regression%-guard:minion%-frenzy%-multiplicative'),
            "guard marker must sit on the config entry")
        assert.is_truthy(configText:find('var = "minionsConditionFrenzy"', 1, true),
            "toggle must exist")
    end)

    it("ConfigOptions: delivers Speed MORE 20 (multiplicative), NOT INC, via MinionModifier", function()
        local entry = configText:match('var = "minionsConditionFrenzy".-end },')
        assert.is_not_nil(entry, "config entry body must be findable")
        assert.is_truthy(entry:find('modLib.createMod("Speed", "MORE", 20, "MinionFrenzy")', 1, true),
            "minion Frenzy is x1.2 MULTIPLICATIVE (cadence-measured 0.75s modal); " ..
            "an INC 20 predicts 0.795s and was rejected -- do not harmonise with the player toggle")
        assert.is_falsy(entry:find('createMod("Speed", "INC"', 1, true),
            "must not deliver an INC speed")
        assert.is_truthy(entry:find('modLib.createMod("Condition:Frenzy", "FLAG", true, "Config")', 1, true),
            "Condition:Frenzy must be published for frenzy-conditional minion mods")
        assert.is_truthy(entry:find('NewMod("MinionModifier", "LIST"', 1, true),
            "delivery is via MinionModifier wrappers (player modDB -> minion modDB)")
    end)

    it("player conditionFrenzy stays INC 20 (the two models are intentionally different)", function()
        local player = configText:match('var = "conditionFrenzy".-end },')
        assert.is_not_nil(player, "player Frenzy toggle must exist")
        assert.is_truthy(player:find('NewMod("Speed", "INC", 20, "Frenzy")', 1, true),
            "player Frenzy = 20% increased attack/cast speed (LE tooltip); only the " ..
            "MINION buff is measured multiplicative")
    end)

    it("ModDB contract: Speed MORE 20 yields x1.2 on attack and cast cfgs alike", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        db:NewMod("Speed", "MORE", 20, "MinionFrenzy")
        assert.are.equals(1.2, db:More({ flags = ModFlag.Attack, keywordFlags = KeywordFlag.Melee }, "Speed"),
            "attack context sees x1.2")
        assert.are.equals(1.2, db:More({ flags = ModFlag.Cast }, "Speed"),
            "cast context sees x1.2 (Frenzy is attack AND cast speed)")
    end)
end)
