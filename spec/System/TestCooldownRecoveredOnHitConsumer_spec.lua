-- @leb-regression-guard: cooldown-recovered-on-hit-consumer
-- Locks Mod#6: two unique-mod families that grant
-- "remaining cooldown recovered on hit (up to N times)" -- Black
-- Blade of Chaos Mod[4] (Lethal Mirage, 15%/12-times) and
-- Razorfall Mod[4] (Aerial Assault, 17% chance for 8%/3-times).
-- Parser emits a paired BASE mod set (CooldownRecoveryOnHit +
-- CooldownRecoveryOnHitMaxPerCast) tagged with SkillName=<skill>.
-- CalcOffence aggregates both into output.* and CalcSections
-- surfaces them as breakdown rows. Per-cast accumulator semantics
-- are visible-only at v1 -- combat-loop attribution deferred.
-- See game CharacterMutator SinceLast<Skill>Use counters in
-- dump.cs L96712-96719 for the underlying mechanism.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("CooldownRecoveredOnHitConsumer", function()
    local calcText, sectionsText, parserText, cacheText

    setup(function()
        calcText     = readSource("Modules/CalcOffence.lua")
        sectionsText = readSource("Modules/CalcSections.lua")
        parserText   = readSource("Modules/ModParser.lua")
        cacheText    = readSource("Data/ModCache.lua")
    end)

    it("ModParser: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(parserText, '@leb%-regression%-guard:cooldown%-recovered%-on%-hit%-consumer'),
            "ModParser must carry the Mod#6 guard marker"
        )
    end)

    it("ModParser: defines the Lethal Mirage anchored handler", function()
        assert.is_truthy(
            string.find(parserText,
                "lethal mirage's remaining cooldown recovered on melee hit",
                1, true),
            "ModParser must define the Lethal Mirage cooldown anchor"
        )
    end)

    it("ModParser: defines the Aerial Assault anchored handler", function()
        assert.is_truthy(
            string.find(parserText,
                "aerial assault's remaining cooldown on throwing hit",
                1, true),
            "ModParser must define the Aerial Assault cooldown anchor"
        )
    end)

    it("CalcOffence: aggregates CooldownRecoveryOnHit into output", function()
        local pattern = 'output%.CooldownRecoveryOnHit%s*=%s*skillModList:Sum%("BASE",%s*skillCfg,%s*"CooldownRecoveryOnHit"%)'
        assert.is_truthy(
            string.find(calcText, pattern),
            "CalcOffence must aggregate CooldownRecoveryOnHit BASE via skillModList:Sum"
        )
    end)

    it("CalcOffence: aggregates CooldownRecoveryOnHitMaxPerCast into output", function()
        local pattern = 'output%.CooldownRecoveryOnHitMaxPerCast%s*=%s*skillModList:Sum%("BASE",%s*skillCfg,%s*"CooldownRecoveryOnHitMaxPerCast"%)'
        assert.is_truthy(
            string.find(calcText, pattern),
            "CalcOffence must aggregate CooldownRecoveryOnHitMaxPerCast BASE via skillModList:Sum"
        )
    end)

    it("CalcSections: has a CooldownRecoveryOnHit breakdown row", function()
        assert.is_truthy(
            string.find(sectionsText, 'haveOutput%s*=%s*"CooldownRecoveryOnHit"'),
            "CalcSections must define a row with haveOutput='CooldownRecoveryOnHit'"
        )
    end)

    it("CalcSections: has a CooldownRecoveryOnHitMaxPerCast breakdown row", function()
        assert.is_truthy(
            string.find(sectionsText, 'haveOutput%s*=%s*"CooldownRecoveryOnHitMaxPerCast"'),
            "CalcSections must define a row with haveOutput='CooldownRecoveryOnHitMaxPerCast'"
        )
    end)

    it("CalcSections: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(sectionsText, '@leb%-regression%-guard:cooldown%-recovered%-on%-hit%-consumer'),
            "CalcSections must carry the Mod#6 guard marker"
        )
    end)

    it("ModCache: Lethal Mirage anchor carries SkillName-tagged paired mods", function()
        local lineStart = string.find(cacheText,
            '15%% of Lethal Mirage', 1, false)
        assert.is_truthy(lineStart, "Lethal Mirage anchor must exist in ModCache")
        local _, lineEnd = string.find(cacheText, '\n', lineStart, true)
        local line = string.sub(cacheText, lineStart, lineEnd)
        assert.is_truthy(string.find(line, 'name="CooldownRecoveryOnHit"', 1, true),
            "anchor must emit CooldownRecoveryOnHit mod")
        assert.is_truthy(string.find(line, 'name="CooldownRecoveryOnHitMaxPerCast"', 1, true),
            "anchor must emit CooldownRecoveryOnHitMaxPerCast mod")
        assert.is_truthy(string.find(line, 'skillName="Lethal Mirage"', 1, true),
            "anchor must tag both mods with SkillName='Lethal Mirage'")
        assert.is_truthy(string.find(line, 'value=15', 1, true),
            "Lethal Mirage anchor must emit value=15 (percent per hit)")
        assert.is_truthy(string.find(line, 'value=12', 1, true),
            "Lethal Mirage anchor must emit value=12 (max per cast)")
    end)

    it("ModCache: Aerial Assault anchor carries SkillName-tagged paired mods", function()
        local lineStart = string.find(cacheText,
            'recover 8%% of Aerial Assault', 1, false)
        assert.is_truthy(lineStart, "Aerial Assault anchor must exist in ModCache")
        local _, lineEnd = string.find(cacheText, '\n', lineStart, true)
        local line = string.sub(cacheText, lineStart, lineEnd)
        assert.is_truthy(string.find(line, 'name="CooldownRecoveryOnHit"', 1, true),
            "anchor must emit CooldownRecoveryOnHit mod")
        assert.is_truthy(string.find(line, 'name="CooldownRecoveryOnHitMaxPerCast"', 1, true),
            "anchor must emit CooldownRecoveryOnHitMaxPerCast mod")
        assert.is_truthy(string.find(line, 'skillName="Aerial Assault"', 1, true),
            "anchor must tag both mods with SkillName='Aerial Assault'")
        assert.is_truthy(string.find(line, 'value=1.36', 1, true),
            "Aerial Assault anchor must emit value=1.36 (17% chance * 8% = 1.36 effective)")
        assert.is_truthy(string.find(line, 'value=3', 1, true),
            "Aerial Assault anchor must emit value=3 (max per cast)")
    end)

    it("ModCache: Lethal Mirage anchor is NOT a no-op stub", function()
        assert.is_nil(
            string.find(cacheText,
                'c%["15%% of Lethal Mirage\\\'s remaining cooldown recovered on Melee Hit %(up to 12 times%)"%]={{},""%}'),
            "ModCache must not retain the empty {{},\"\"} no-op stub for the Lethal Mirage anchor"
        )
    end)

    it("ModCache: Aerial Assault anchor is NOT a no-op stub", function()
        assert.is_nil(
            string.find(cacheText,
                '"17%% chance to recover 8%% of Aerial Assault\'s remaining cooldown on Throwing Hit %(up to 3 times%)"%]={{},'),
            "ModCache must not retain the no-op stub for the Aerial Assault anchor"
        )
    end)

    -- Runtime guard: locks the parser dispatch convention.
    -- Without these, the static-text checks above happily pass while
    -- a 2-capture handler signature mismatch silently aliases the cap
    -- count to the pct value (BxvJdz2m repro: cap=12 -> 23). The
    -- specialMod dispatcher calls handlers as
    --     specialMod(tonumber(cap[1]), unpack(cap))
    -- so 2-capture handlers must take (numericFirst, rawFirst, rawSecond);
    -- the third arg is the cap. Regression: keeping signature (pct, cap)
    -- binds cap = rawFirst, dropping the (up to N times) capture.
    describe("runtime dispatch (ModParser → modList)", function()
        -- Helper: parse a single rolled-text line and return the BASE value
        -- emitted under the given mod-name, regardless of SkillName tag.
        local function parsedBase(line, modName)
            local list = modLib.parseMod(line)
            assert.is_not_nil(list, "parseMod must return a list for: " .. line)
            for _, m in ipairs(list) do
                if m.name == modName and m.type == "BASE" then
                    return m.value
                end
            end
            return nil
        end

        local function parsedSkillTag(line, modName)
            local list = modLib.parseMod(line)
            assert.is_not_nil(list)
            for _, m in ipairs(list) do
                if m.name == modName then
                    for _, t in ipairs(m) do
                        if t.type == "SkillName" then return t.skillName end
                    end
                end
            end
            return nil
        end

        it("Lethal Mirage: pct and cap are independent values", function()
            local line = "23% of Lethal Mirage's remaining cooldown recovered on Melee Hit (up to 12 times)"
            assert.are.equals(23, parsedBase(line, "CooldownRecoveryOnHit"))
            assert.are.equals(12, parsedBase(line, "CooldownRecoveryOnHitMaxPerCast"))
            assert.are.equals("Lethal Mirage", parsedSkillTag(line, "CooldownRecoveryOnHit"))
            assert.are.equals("Lethal Mirage", parsedSkillTag(line, "CooldownRecoveryOnHitMaxPerCast"))
        end)

        it("Lethal Mirage: distinct pct/cap pair survives dispatch", function()
            -- Values chosen so they cannot coincide if dispatch aliases args.
            local line = "7% of Lethal Mirage's remaining cooldown recovered on Melee Hit (up to 4 times)"
            assert.are.equals(7, parsedBase(line, "CooldownRecoveryOnHit"))
            assert.are.equals(4, parsedBase(line, "CooldownRecoveryOnHitMaxPerCast"))
        end)

        it("Aerial Assault: effective rate = chance * 8 / 100 and cap is literal", function()
            local line = "17% chance to recover 8% of Aerial Assault's remaining cooldown on Throwing Hit (up to 3 times)"
            local effective = parsedBase(line, "CooldownRecoveryOnHit")
            assert.is_not_nil(effective)
            assert.is_true(math.abs(effective - 1.36) < 1e-6,
                "Aerial Assault effective rate must be 1.36, got " .. tostring(effective))
            assert.are.equals(3, parsedBase(line, "CooldownRecoveryOnHitMaxPerCast"))
            assert.are.equals("Aerial Assault", parsedSkillTag(line, "CooldownRecoveryOnHit"))
        end)

        it("Aerial Assault: distinct chance/cap pair survives dispatch", function()
            local line = "25% chance to recover 8% of Aerial Assault's remaining cooldown on Throwing Hit (up to 5 times)"
            local effective = parsedBase(line, "CooldownRecoveryOnHit")
            assert.is_true(math.abs(effective - 2.0) < 1e-6,
                "Aerial Assault effective rate must be 2.0, got " .. tostring(effective))
            assert.are.equals(5, parsedBase(line, "CooldownRecoveryOnHitMaxPerCast"))
        end)
    end)

    it("REGRESSION_GUARDS.md indexes this guard", function()
        local f = io.open("REGRESSION_GUARDS.md", "r") or io.open("../REGRESSION_GUARDS.md", "r")
        assert.is_not_nil(f, "must be able to open REGRESSION_GUARDS.md")
        local text = f:read("*a")
        f:close()
        assert.is_truthy(
            string.find(text, "cooldown%-recovered%-on%-hit%-consumer", 1, false),
            "REGRESSION_GUARDS.md must index the cooldown-recovered-on-hit-consumer guard"
        )
    end)
end)
