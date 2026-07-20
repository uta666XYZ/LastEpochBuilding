-- @leb-regression-guard:storm-sprite-tempest-maw
-- WARRIOR95 root C: Tempest Maw's intrinsic "When you summon a totem you also
-- summon 4 Storm Sprites ... (up to 2 times per 6 seconds)" -> 4 Storm Sprites
-- casting stormSpriteDash. All 4 wiring parts are game-source (live 1.4.7 bundles,
-- _extract_storm_sprite.py): the StormSprite minion already pointed skillList at
-- stormSpriteDash (a dangling ref until now). Per-hit is correct vs in-game
-- (crit-corrected ~12.3k); the summon is modelled at full uptime (planner
-- convention) -- in-game the dash whiffs ~52% (HitDetector connection rate, no
-- game-source constant, datamining single-hit prefab), left unmodelled.
-- See memory project_warrior95_storm_totem_multiroot.

local function read(path)
    local f = io.open(path, "r")
    assert.is_not_nil(f, "must be able to open " .. path)
    local t = f:read("*a"); f:close()
    return t
end

describe("StormSpriteTempestMaw", function()
    it("skills.json defines stormSpriteDash (Lightning 20, the StormSprite attack)", function()
        local t = read("Data/skills.json")
        assert.is_truthy(string.find(t, '"stormSpriteDash"', 1, true),
            "stormSpriteDash must be defined (StormSprite.skillList pointed at it)")
        assert.is_truthy(string.find(t, '"spell_base_lightning_damage": 20', 1, true),
            "stormSpriteDash base Lightning 20 (game-source from live 1.4.7 bundles)")
    end)

    it("AutoSummons maps StormSpritesSummoned -> SummonStormSprite", function()
        local t = read("Data/AutoSummons.lua")
        assert.is_truthy(string.find(t, 'countStat = "StormSpritesSummoned"', 1, true),
            "AutoSummons registry must carry the StormSpritesSummoned count")
        assert.is_truthy(string.find(t, 'summonSkill = "SummonStormSprite"', 1, true),
            "mapped to the SummonStormSprite skill")
    end)

    it("ModParser parses Tempest Maw's summon line to StormSpritesSummoned (full-line anchored)", function()
        local t = read("Modules/ModParser.lua")
        assert.is_truthy(string.find(t, "you also summon ([%d%.]+) storm sprites.*$", 1, true),
            "the pattern must be full-line ($-anchored .*$) so the trailing flavour is consumed")
        assert.is_truthy(string.find(t, 'mod("StormSpritesSummoned", "BASE", tonumber(num))', 1, true),
            "captured count -> StormSpritesSummoned BASE")
    end)

    it("Tempest Maw carries the intrinsic summon line", function()
        local t = read("Data/Uniques/uniques_1_4.json")
        assert.is_truthy(string.find(t, "When you summon a totem you also summon 4 Storm Sprites", 1, true),
            "Tempest Maw must carry the Storm Sprite summon (absent from its 5 rollable mods)")
    end)
end)
