-- @leb-regression-guard: channelling-per-second-stacking-buff
-- Locks the bare "+N% Damage Per Second" channelling-stacking-buff
-- parse covering Smelter's Wrath (tree_2.json L14336 "+5%"),
-- Flurry "Accelerating Impact" (tree_4.json flur3-14 "+3%"), and
-- Volcanic Orb (tree_2.json va53st-19 "+20%").
--
-- Before this guard the line fell through to a flat `Damage MORE`
-- with residue "  Per Second " — silently granting the full N% MORE
-- Damage unconditionally, regardless of channelling state or stack
-- count.
--
-- Three sites lock together:
-- a. `Modules/ConfigOptions.lua` declares `multiplierChannellingSeconds`
--    publishing `Multiplier:ChannellingSeconds` gated on Combat +
--    Channelling.
-- b. `Modules/ModParser.lua` specialModList entry maps the bare
--    "+N% damage per second" form to `Damage MORE` gated on
--    Condition:Channelling AND multiplied by
--    Multiplier:ChannellingSeconds.
-- c. `Data/ModCache.lua` 3 patched entries (+3%, +5%, +20%) carry
--    both tags with empty residue.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("ChannellingPerSecondStackingBuff", function()
    local parserText, cacheText, configText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
        configText = readSource("Modules/ConfigOptions.lua")
    end)

    it("ConfigOptions declares multiplierChannellingSeconds publishing Multiplier:ChannellingSeconds", function()
        assert.is_truthy(string.find(configText,
            'var = "multiplierChannellingSeconds"', 1, false),
            "ConfigOptions must declare multiplierChannellingSeconds")
        assert.is_truthy(string.find(configText,
            'Multiplier:ChannellingSeconds', 1, false),
            "ConfigOptions must publish Multiplier:ChannellingSeconds")
    end)

    it("ModParser specialModList maps '+N%% damage per second' to MORE Damage gated on Channelling + Multiplier", function()
        assert.is_truthy(string.find(parserText,
            'specialModList%["%^%%%+%?%(%[%%d%%.%]%+%)%%%% damage per second%$"%]', 1, false),
            "ModParser must register the '+N%% damage per second' pattern")
        assert.is_truthy(string.find(parserText,
            'mod%("Damage", "MORE", num, "", 0, 0, { type = "Condition", var = "Channelling" }, { type = "Multiplier", var = "ChannellingSeconds" }%)', 1, false),
            "Handler must emit Damage MORE gated on Channelling + ChannellingSeconds multiplier")
    end)

    it("ModCache '+5% Damage Per Second' carries Condition:Channelling + Multiplier:ChannellingSeconds", function()
        local needle = 'c%["%+5%% Damage Per Second"%]={{%[1%]={%[1%]={type="Condition",var="Channelling"},%[2%]={type="Multiplier",var="ChannellingSeconds"},flags=0,keywordFlags=0,name="Damage",type="MORE",value=5}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "+5%% Damage Per Second entry must carry both tags with empty residue")
    end)

    it("ModCache '+3% Damage Per Second' carries Condition:Channelling + Multiplier:ChannellingSeconds", function()
        local needle = 'c%["%+3%% Damage Per Second"%]={{%[1%]={%[1%]={type="Condition",var="Channelling"},%[2%]={type="Multiplier",var="ChannellingSeconds"},flags=0,keywordFlags=0,name="Damage",type="MORE",value=3}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "+3%% Damage Per Second entry must carry both tags with empty residue")
    end)

    it("ModCache '+20% Damage Per Second' carries Condition:Channelling + Multiplier:ChannellingSeconds", function()
        local needle = 'c%["%+20%% Damage Per Second"%]={{%[1%]={%[1%]={type="Condition",var="Channelling"},%[2%]={type="Multiplier",var="ChannellingSeconds"},flags=0,keywordFlags=0,name="Damage",type="MORE",value=20}},""}'
        assert.is_truthy(string.find(cacheText, needle, 1, false),
            "+20%% Damage Per Second entry must carry both tags with empty residue")
    end)

    it("ModCache must NOT carry stale unconditional MORE entries for any of the 3 patched values", function()
        for _, num in ipairs({"3", "5", "20"}) do
            local stale = 'c["+' .. num .. '% Damage Per Second"]={{[1]={flags=0,keywordFlags=0,name="Damage",type="MORE",value=' .. num .. '}},"  Per Second "}'
            assert.is_nil(string.find(cacheText, stale, 1, true),
                "+" .. num .. "%% Damage Per Second entry must not carry the stale unconditional MORE form")
        end
    end)
end)
