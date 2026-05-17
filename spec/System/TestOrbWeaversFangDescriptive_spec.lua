-- @leb-regression-guard: orb-weavers-fang-descriptive
-- Locks the parser anchor and ModCache neutralization for the
-- single-source conditional self-mult line on Orb Weaver's Fang
-- (uniqueID=405, sword): "+100% Stats on this item are doubled for
-- 3 seconds after hitting a boss or rare enemy that is low life".
-- The semantics require per-item-scope multiplier infra that LEB
-- does not have today; v1 is parser-only flag (recognise-but-emit-
-- nothing), matching Tabi of Dusk and Dawn / W6 precedents.
--
-- Before this anchor the line parsed to an empty modList with
-- mangled residue (" Stats on this item are doubled  after ting a
-- boss or rare enemy that is low life ") where generic parsers had
-- eaten "+100%", "for 3 seconds", and "hit". The anchor wins by
-- being a full-line specialModList regex.
--
-- See REGRESSION_GUARDS.md "orb-weavers-fang-descriptive".

describe("OrbWeaversFangDescriptive", function()

    local parserSrc, cacheSrc
    setup(function()
        local f = io.open("Modules/ModParser.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/ModParser.lua")
        parserSrc = f:read("*a"):gsub("\r\n", "\n")
        f:close()

        local g = io.open("Data/ModCache.lua", "r")
        assert.is_not_nil(g, "must be able to open Data/ModCache.lua")
        cacheSrc = g:read("*a"):gsub("\r\n", "\n")
        g:close()
    end)

    it("parser keeps the @leb-regression-guard anchor", function()
        assert.is_truthy(
            string.find(parserSrc, "orb-weavers-fang-descriptive", 1, true),
            "ModParser.lua must keep the @leb-regression-guard comment so future edits trip review"
        )
    end)

    it("parser anchors the full Orb Weaver's Fang line to empty mods", function()
        -- Match the specialModList key + function returning {}.
        -- The key uses Lua pattern specials (%+, %%, %d) so we search
        -- for the verbatim string presence rather than re-pattern it.
        local key = '["^%+?100%% stats on this item are doubled for %d+ seconds? after hitting a boss or rare enemy that is low life$"]'
        assert.is_truthy(string.find(parserSrc, key, 1, true),
            "ModParser.lua must contain the anchored specialModList key for Orb Weaver's Fang descriptive line")
        -- And the value must be a function returning {} (no mods emitted).
        local needle = '%["%^%%%+%?100%%%% stats on this item are doubled for %%d%+ seconds%? after hitting a boss or rare enemy that is low life%$"%]%s*=%s*function%(%)%s*return%s*{}%s*end'
        assert.is_truthy(string.find(parserSrc, needle),
            "anchored handler must be `function() return {} end`")
    end)

    it("ModCache entry is empty/empty (no mangled residue)", function()
        local needle = 'c%["%+100%% Stats on this item are doubled for 3 seconds after hitting a boss or rare enemy that is low life"%]={{}, ""}'
        assert.is_truthy(string.find(cacheSrc, needle),
            "ModCache.lua must carry the neutralized {{}, \"\"} entry for the Orb Weaver's Fang line")
    end)
end)
