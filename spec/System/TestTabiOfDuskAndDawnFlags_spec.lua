-- @leb-regression-guard: tabi-of-dusk-and-dawn-flags
-- Locks the parser/ModCache/CalcOffence wiring for the two Shadow-Rend-
-- specific lines on Tabi of Dusk and Dawn (uniqueID=458, boots):
--   "Shadow Rend no longer moves you"
--   "Shadow Rend always manifests a melee shadow in front of you and a
--    bow shadow behind you"
--
-- Game-file evidence (decisive):
--   dump.cs L77736  public bool shadowRendAlsoCastsOtherWeaponVersion;
--   dump.cs L77737  public bool shadowRendNoPlayerMovement;
-- Both live on CharacterMutator, sandwiched in the lethalMirage* block
-- that backs the cooldown-recovered-on-hit-consumer family. Cross-refs:
--   dump.cs L56914  ShadowRendBowMutator  (has meleeMut)
--   dump.cs L57008  ShadowRendMeleeMutator (has bowMut)
--   ability_keyed_array.json L971 / L3421  {ShadowRend, ShadowRend Bow}
--     share playerAbilityID 'sh4re'
-- v1 surface model: parser emits FLAG mods tagged SkillName="Shadow Rend";
-- CalcOffence consumes ShadowRendAlsoCastsOtherWeaponVersion as +100%
-- MORE Damage (paired-variant composition deferred to v2).
-- ShadowRendNoPlayerMovement has no calc consumer (movement-only).
--
-- See REGRESSION_GUARDS.md "tabi-of-dusk-and-dawn-flags".

describe("TabiOfDuskAndDawnFlags", function()

    local parserSrc, cacheSrc, calcSrc
    setup(function()
        local f = io.open("Modules/ModParser.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/ModParser.lua")
        parserSrc = f:read("*a"):gsub("\r\n", "\n")
        f:close()

        local g = io.open("Data/ModCache.lua", "r")
        assert.is_not_nil(g, "must be able to open Data/ModCache.lua")
        cacheSrc = g:read("*a"):gsub("\r\n", "\n")
        g:close()

        local h = io.open("Modules/CalcOffence.lua", "r")
        assert.is_not_nil(h, "must be able to open Modules/CalcOffence.lua")
        calcSrc = h:read("*a"):gsub("\r\n", "\n")
        h:close()
    end)

    it("parser keeps the @leb-regression-guard anchor", function()
        assert.is_truthy(
            string.find(parserSrc, "tabi-of-dusk-and-dawn-flags", 1, true),
            "ModParser.lua must keep the @leb-regression-guard:tabi-of-dusk-and-dawn-flags comment"
        )
    end)

    it("parser emits ShadowRendNoPlayerMovement flag for 'no longer moves you'", function()
        local needle = '%["%^shadow rend no longer moves you%$"%]%s*=%s*function%(%)%s*return%s*{%s*flag%("ShadowRendNoPlayerMovement"'
        assert.is_truthy(string.find(parserSrc, needle),
            "ModParser must emit flag('ShadowRendNoPlayerMovement', ...) for the 'no longer moves you' line")
        -- And the flag must carry SkillName="Shadow Rend"
        assert.is_truthy(string.find(parserSrc,
            'flag%("ShadowRendNoPlayerMovement",%s*{%s*type%s*=%s*"SkillName",%s*skillName%s*=%s*"Shadow Rend"%s*}%s*%)'),
            "ShadowRendNoPlayerMovement flag must be tagged SkillName=\"Shadow Rend\"")
    end)

    it("parser emits ShadowRendAlsoCastsOtherWeaponVersion flag for the manifests line", function()
        local needle = '%["%^shadow rend always manifests a melee shadow in front of you and a bow shadow behind you%$"%]%s*=%s*function%(%)%s*return%s*{%s*flag%("ShadowRendAlsoCastsOtherWeaponVersion"'
        assert.is_truthy(string.find(parserSrc, needle),
            "ModParser must emit flag('ShadowRendAlsoCastsOtherWeaponVersion', ...) for the 'manifests melee/bow' line")
        assert.is_truthy(string.find(parserSrc,
            'flag%("ShadowRendAlsoCastsOtherWeaponVersion",%s*{%s*type%s*=%s*"SkillName",%s*skillName%s*=%s*"Shadow Rend"%s*}%s*%)'),
            "ShadowRendAlsoCastsOtherWeaponVersion flag must be tagged SkillName=\"Shadow Rend\"")
    end)

    it("ModCache carries the FLAG mod for 'no longer moves you'", function()
        assert.is_truthy(string.find(cacheSrc,
            'c%["Shadow Rend no longer moves you"%]={{%[1%]={%[1%]={skillName="Shadow Rend",type="SkillName"},flags=0,keywordFlags=0,name="ShadowRendNoPlayerMovement",type="FLAG",value=true}},nil}',
            1),
            "ModCache.lua must carry the FLAG entry for 'Shadow Rend no longer moves you'")
    end)

    it("ModCache carries the FLAG mod for the manifests line", function()
        assert.is_truthy(string.find(cacheSrc,
            'c%["Shadow Rend always manifests a melee shadow in front of you and a bow shadow behind you"%]={{%[1%]={%[1%]={skillName="Shadow Rend",type="SkillName"},flags=0,keywordFlags=0,name="ShadowRendAlsoCastsOtherWeaponVersion",type="FLAG",value=true}},nil}',
            1),
            "ModCache.lua must carry the FLAG entry for the manifests melee/bow shadow line")
    end)

    it("CalcOffence keeps the @leb-regression-guard anchor", function()
        assert.is_truthy(
            string.find(calcSrc, "tabi-of-dusk-and-dawn-flags", 1, true),
            "CalcOffence.lua must keep the @leb-regression-guard:tabi-of-dusk-and-dawn-flags comment"
        )
    end)

    it("CalcOffence gates the dual-cast consumer on Shadow Rend + the flag", function()
        assert.is_truthy(string.find(calcSrc,
            'activeGrantedName%s*==%s*"Shadow Rend"%s*and%s*skillModList:Flag%(skillCfg,%s*"ShadowRendAlsoCastsOtherWeaponVersion"%)'),
            "CalcOffence must gate the dual-cast bonus on activeGrantedName==\"Shadow Rend\" AND the flag")
    end)

    it("CalcOffence emits Damage MORE 100 for the dual-cast bonus", function()
        assert.is_truthy(string.find(calcSrc,
            'skillModList:NewMod%("Damage",%s*"MORE",%s*100,%s*"Shadow Rend dual cast %(Tabi of Dusk and Dawn%)"'),
            "CalcOffence must emit Damage MORE 100 with the Tabi-of-Dusk-and-Dawn source label")
    end)
end)
