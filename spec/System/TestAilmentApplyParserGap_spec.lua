-- @leb-regression-guard:ailment-apply-parser-gap
-- Locks the ModParser aliases that make the "to apply <ailment> on Hit" phrasing
-- of Doom and Time Rot parse. Both ailments previously registered only their
-- "to inflict X" (+ "doom chance") forms, but several uniques carry the "apply"
-- phrasing instead -- and for Doom the OFFICIAL game descriptor is literally
-- "Chance to apply Doom on Hit" (datamine descriptors "1,0,90,0").
--
-- Affected items (verbatim src/Data/Uniques text):
--   Siphon of Anguish     "+(10-30)% Chance to apply Doom on Hit"      (blast 64)
--   Stymied Fate          "+(14-22)% Chance to apply Doom on Hit"      (blast  2)
--   Apathy's Maw          "+100% Chance to apply Doom on Hit"          (blast  0)
--   Black Blade of Chaos  "+(6-60)% Chance to apply Time Rot on Hit"   (blast  1)
--
-- Bug: with no "to apply doom" / "to apply time rot" modNameList key the generic
-- parse chain found no modName and returned {} (empty modList) -> the DoomChance /
-- TimeRotChance addend never reached modDB (silent UNDER-count). The consumers are
-- already fully modeled (DoomChance @ CalcOffence L2531, TimeRotChance @ L2527), so
-- the ONLY gap was the parser entry point -- identical shape to the C9 Chronicle of
-- the Damned "to inflict damned" fix.
--
-- Invariants locked:
--   1. Each "apply <ailment> on Hit" string parses to exactly one <X>Chance BASE mod
--      carrying ModFlag.Hit, value = the rolled number.
--   2. PARITY: the "apply" form parses to the same mod name/type/value as the
--      sanctioned "inflict" form (structural equality with the working mechanism).
--   3. End-to-end: a plain "chance to apply <ailment>" yields the same nonzero
--      consumer output as "chance to inflict <ailment>".
--   4. NON-HIJACK: the DEFENSIVE reflect variant "Chance to apply Time Rot to
--      Attackers when Hit" (Property_Player_39, descriptors "98,39,0,0" -- Defiance
--      of the Forgotten Knight) must NOT resolve to offensive TimeRotChance.
--   5. NON-FABRICATION: each affix string is present verbatim in src/Data/Uniques.
--   6. The stale empty ModCache rows are gone (no longer short-circuit live parse).
--
-- See REGRESSION_GUARDS.md "ailment-apply-parser-gap".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

local function hasHitFlag(mod)
    -- Validation provenance is retained in maintainer notes.
    return mod.flags and (mod.flags % (2 * 8388608)) >= 8388608
end

describe("AilmentApplyParserGap", function()
    local parserText, cacheText, uniquesText, setText
    setup(function()
        newBuild()
        parserText  = readSource("Modules/ModParser.lua")
        cacheText   = readSource("Data/ModCache.lua")
        uniquesText = readSource("Data/Uniques/uniques_1_4.json")
        setText     = readSource("Data/Set/set_1_4.json")
    end)

    it("inline guard marker present in ModParser.lua", function()
        assert.is_truthy(string.find(parserText, "ailment-apply-parser-gap", 1, true))
    end)

    it("registers the 'to apply doom' / 'to apply time rot' modNameList keys", function()
        assert.is_truthy(string.find(parserText, '%["to apply doom"%]%s*=%s*"DoomChance"'),
            "ModParser must map 'to apply doom' to DoomChance")
        assert.is_truthy(string.find(parserText, '%["to apply time rot"%]%s*=%s*"TimeRotChance"'),
            "ModParser must map 'to apply time rot' to TimeRotChance")
    end)

    -- Invariant 1 + 5: each real affix string parses to one <X>Chance BASE Hit mod
    local cases = {
        { text = "+(10-30)% Chance to apply Doom on Hit",     roll = 10, name = "DoomChance",    item = "Siphon of Anguish" },
        { text = "+(14-22)% Chance to apply Doom on Hit",     roll = 14, name = "DoomChance",    item = "Stymied Fate" },
        { text = "+100% Chance to apply Doom on Hit",         roll = 100, name = "DoomChance",   item = "Apathy's Maw" },
        { text = "+(6-60)% Chance to apply Time Rot on Hit",  roll = 6,  name = "TimeRotChance", item = "Black Blade of Chaos" },
    }
    for _, c in ipairs(cases) do
        it("parses '" .. c.text .. "' (" .. c.item .. ") to one " .. c.name .. " BASE Hit mod", function()
            -- non-fabrication: the exact affix string exists in the shipped unique data
            assert.is_truthy(string.find(uniquesText, c.text, 1, true),
                "affix string must exist verbatim in uniques_1_4.json: " .. c.text)
            -- feed the parser the concrete-rolled form (ranges resolve to their low end here)
            local concrete = c.text:gsub("%(%d+%-%d+%)", tostring(c.roll)):gsub("^%+", "")
            local list = modLib.parseMod(concrete)
            assert.is_not_nil(list, "must parse: " .. concrete)
            assert.are.equals(1, #list, "exactly one mod for: " .. concrete)
            local m = list[1]
            assert.are.equals(c.name, m.name)
            assert.are.equals("BASE", m.type)
            assert.are.equals(c.roll, m.value)
            assert.is_true(hasHitFlag(m), "must carry ModFlag.Hit for: " .. concrete)
        end)
    end

    it("PARITY: 'apply' form matches the sanctioned 'inflict' form (doom + time rot)", function()
        for _, ail in ipairs({ "doom", "time rot" }) do
            local applyL   = modLib.parseMod("20% Chance to apply " .. ail .. " on Hit")
            local inflictL = modLib.parseMod("20% Chance to inflict " .. ail .. " on Hit")
            assert.are.equals(1, #applyL, "apply " .. ail)
            assert.are.equals(1, #inflictL, "inflict " .. ail)
            assert.are.equals(inflictL[1].name, applyL[1].name)
            assert.are.equals(inflictL[1].type, applyL[1].type)
            assert.are.equals(inflictL[1].value, applyL[1].value)
        end
    end)

    it("end-to-end: 'apply' feeds the consumer identically to 'inflict' (nonzero)", function()
        local function chanceOf(mods, outName)
            newBuild()
            build.configTab.input.customMods = mods
            build.configTab:BuildModList(); runCallback("OnFrame")
            build.calcsTab:BuildOutput()
            return build.calcsTab.mainOutput[outName]
        end
        local applyDoom   = chanceOf("50% chance to apply doom", "DoomChance")
        local inflictDoom = chanceOf("50% chance to inflict doom", "DoomChance")
        assert.are.equals(inflictDoom, applyDoom, "apply doom must match inflict doom")
        assert.is_true((applyDoom or 0) > 0, "apply doom must be nonzero (was silently dropped)")

        local applyTR   = chanceOf("50% chance to apply time rot", "TimeRotChance")
        local inflictTR = chanceOf("50% chance to inflict time rot", "TimeRotChance")
        assert.are.equals(inflictTR, applyTR, "apply time rot must match inflict time rot")
        assert.is_true((applyTR or 0) > 0, "apply time rot must be nonzero (was silently dropped)")
    end)

    it("NON-HIJACK: defensive reflect 'apply Time Rot to Attackers when Hit' is NOT offensive TimeRotChance", function()
        -- Defiance of the Forgotten Knight / set bonus; distinct stat Property_Player_39.
        local reflect = "25% Chance to apply Time Rot to Attackers when Hit"
        assert.is_truthy(string.find(setText, "Chance to apply Time Rot to Attackers when Hit", 1, true),
            "reflect affix must exist verbatim in current-version set data (set_1_4.json)")
        local list = modLib.parseMod(reflect)
        for _, m in ipairs(list or {}) do
            assert.are_not.equals("TimeRotChance", m.name,
                "reflect line must not resolve to offensive TimeRotChance (got hijacked)")
        end
    end)

    it("stale empty ModCache rows for the apply-on-hit affixes are gone", function()
        assert.is_nil(string.find(cacheText, "apply Doom on Hit", 1, true),
            "stale empty 'apply Doom on Hit' ModCache rows must be deleted")
        assert.is_nil(string.find(cacheText, "apply Time Rot on Hit", 1, true),
            "stale empty 'apply Time Rot on Hit' ModCache rows must be deleted")
    end)
end)
