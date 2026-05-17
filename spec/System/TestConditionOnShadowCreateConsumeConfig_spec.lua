-- @leb-regression-guard: condition-on-shadow-create-consume-config
-- Locks F6: Config tab toggles for the Bladedancer Shadow event-time
-- conditions OnShadowCreate / OnShadowConsume. The parser already
-- emits these Condition tags on the affix families
--   "+N Ward Gained on Shadow Creation" (9+ tiers, ModItem/ModIdol)
--   "+N Health Gained on Shadow Creation" (8 tiers, ModItem)
--   "+N% Chance to gain a stack of Dusk Shroud when you consume a Shadow"
-- (see src/Modules/ModParser.lua L615-619 and dozens of correctly
-- tagged ModCache entries). Without these Config toggles those
-- Conditions can never be true at snapshot time, so the tagged mods
-- are gated off entirely -- silent failure with the symptom of
-- missing Ward/Health/Dusk Shroud contributions in the player
-- breakdown.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ConditionOnShadowCreateConsumeConfig", function()
    local configText

    setup(function()
        configText = readSource("Modules/ConfigOptions.lua")
    end)

    it("ConfigOptions: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(configText, '@leb%-regression%-guard:condition%-on%-shadow%-create%-consume%-config'),
            "ConfigOptions must carry the F6 guard marker"
        )
    end)

    it("ConfigOptions: declares conditionOnShadowCreate toggle with ifCond='OnShadowCreate'", function()
        local pattern = 'var%s*=%s*"conditionOnShadowCreate".-ifCond%s*=%s*"OnShadowCreate"'
        assert.is_truthy(
            string.find(configText, pattern),
            "Must declare conditionOnShadowCreate toggle with ifCond='OnShadowCreate'"
        )
    end)

    it("ConfigOptions: declares conditionOnShadowConsume toggle with ifCond='OnShadowConsume'", function()
        local pattern = 'var%s*=%s*"conditionOnShadowConsume".-ifCond%s*=%s*"OnShadowConsume"'
        assert.is_truthy(
            string.find(configText, pattern),
            "Must declare conditionOnShadowConsume toggle with ifCond='OnShadowConsume'"
        )
    end)

    it("ConfigOptions: conditionOnShadowCreate sets Condition:OnShadowCreate FLAG true", function()
        -- Match the full apply assignment for the Create toggle.
        local pattern = 'conditionOnShadowCreate.-modList:NewMod%("Condition:OnShadowCreate",%s*"FLAG",%s*true'
        assert.is_truthy(
            string.find(configText, pattern),
            "conditionOnShadowCreate apply must set Condition:OnShadowCreate FLAG true"
        )
    end)

    it("ConfigOptions: conditionOnShadowConsume sets Condition:OnShadowConsume FLAG true", function()
        local pattern = 'conditionOnShadowConsume.-modList:NewMod%("Condition:OnShadowConsume",%s*"FLAG",%s*true'
        assert.is_truthy(
            string.find(configText, pattern),
            "conditionOnShadowConsume apply must set Condition:OnShadowConsume FLAG true"
        )
    end)

    it("ConfigOptions: both toggles scoped by Condition:Combat parent tag", function()
        -- Combat-scoped so they don't leak outside combat snapshot.
        local createPattern = 'Condition:OnShadowCreate".-"Config".-Condition",%s*var%s*=%s*"Combat"'
        local consumePattern = 'Condition:OnShadowConsume".-"Config".-Condition",%s*var%s*=%s*"Combat"'
        assert.is_truthy(string.find(configText, createPattern),
            "OnShadowCreate apply must be Combat-scoped")
        assert.is_truthy(string.find(configText, consumePattern),
            "OnShadowConsume apply must be Combat-scoped")
    end)
end)
