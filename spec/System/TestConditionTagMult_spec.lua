-- @leb-regression-guard: condition-tag-mult
-- @leb-regression-guard: doubled-for-shadow-attack
-- @leb-regression-guard: doubled-with-bow
-- Locks the F4 stack:
--   1. Consumer infra: ModStore Condition tag honours `tag.mult`
--      (mirror of StatThreshold mult path)
--   2. Parser entries: ", doubled for shadow attack" emits
--      Condition{ShadowAttack, mult=2}; ", doubled with bow" emits
--      Condition{UsingBow, mult=2}
--   3. ModCache: the 2 known affected entries carry the new shape

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ConditionTagMult", function()
    local storeText, parserText, cacheText

    setup(function()
        storeText  = readSource("Classes/ModStore.lua")
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModStore: Condition handler reads tag.mult", function()
        -- The infra must reference tag.mult inside the Condition
        -- branch. We anchor to the comment marker so future
        -- refactors don't silently drop the mult support.
        local idx = string.find(storeText, '@leb%-regression%-guard:condition%-tag%-mult')
        assert.is_truthy(idx, "Condition handler must carry the infra guard marker")
    end)

    it("ModStore: Condition mult multiplies on match", function()
        -- Look for the post-marker pattern `value = value * tag.mult`.
        local pattern = 'elseif tag%.mult then%s*value = value %* tag%.mult'
        assert.is_truthy(string.find(storeText, pattern),
            "Condition tag must multiply value by tag.mult when the condition matches")
    end)

    it("ModStore: Condition mult falls through when condition unmet", function()
        -- Look for `if not match then if not tag.mult then return end end`.
        local pattern = 'if not match then%s*if not tag%.mult then%s*return%s*end%s*elseif tag%.mult then'
        assert.is_truthy(string.find(storeText, pattern),
            "Condition tag must pass through (no return) when match is false but tag.mult is set")
    end)

    it("ModParser: ', doubled for shadow attack' emits Condition+mult=2", function()
        local needle = '%[", doubled for shadow attack"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"ShadowAttack",%s*mult%s*=%s*2%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "modTagList[', doubled for shadow attack'] must emit Condition{ShadowAttack, mult=2}")
    end)

    it("ModParser: ', doubled with bow' emits Condition+mult=2", function()
        local needle = '%[", doubled with bow"%]%s*=%s*{%s*tag%s*=%s*{%s*type%s*=%s*"Condition",%s*var%s*=%s*"UsingBow",%s*mult%s*=%s*2%s*}'
        assert.is_truthy(string.find(parserText, needle),
            "modTagList[', doubled with bow'] must emit Condition{UsingBow, mult=2}")
    end)

    it("ModCache: '+25% Bleed Chance, Doubled for Shadow Attack' carries mult=2", function()
        local needle = '"%+25%% Bleed Chance, Doubled for Shadow Attack"%]={{%[1%]={%[1%]={mult=2,type="Condition",var="ShadowAttack"}'
        assert.is_truthy(string.find(cacheText, needle),
            "Bleed-Chance Doubled-for-Shadow-Attack entry must carry mult=2 on the Condition tag")
    end)

    it("ModCache: '+34# Armor Shred Chance ... Doubled with Bow' carries mult=2 on UsingBow", function()
        local needle = '"%+34# Armor Shred Chance for Shadow Attack, Doubled with Bow"%]={{%[1%]={%[1%]={type="Condition",var="ShadowAttack"},%[2%]={mult=2,type="Condition",var="UsingBow"}'
        assert.is_truthy(string.find(cacheText, needle),
            "Armor-Shred Doubled-with-Bow entry must carry mult=2 on the UsingBow Condition (gate-only on ShadowAttack)")
    end)
end)
