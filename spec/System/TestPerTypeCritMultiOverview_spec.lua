-- @leb-regression-guard: per-type-crit-multi-overview-keywordflags
-- Locks Calcs.lua's per-damage-type Crit Multiplier overview to filter via
-- keywordFlags (not flags) for the damage-source dimension. ModParser tags
-- damage-source-prefixed mods (e.g. "Throwing Critical Strike Multiplier"
-- from Li'raka's Claws) with keywordFlags = KeywordFlag.<Source>; cfg.flags
-- and cfg.keywordFlags live in different buckets in ModStore:Sum so filtering
-- via ModFlag.<Source> + ModFlag.Hit would silently drop those mods even
-- though the numeric values coincide.
--
-- Establishing build: QWXjqWJ2 lv100 Bladedancer. LETools Throwing CritMulti
-- 609% vs LEB pre-fix 485% (Δ=-124% ≈ Li'raka's Claws "+123% Throwing
-- Critical Strike Multiplier"). Melee/Spell/Bow happened to coincide because
-- no items in that build attached the damage-source keywordFlag to their
-- CritMulti mods, hiding the bug on the other three buckets.
--
-- See REGRESSION_GUARDS.md "per-type-crit-multi-overview-keywordflags".

describe("PerTypeCritMultiOverview", function()

    local source
    setup(function()
        local f = io.open("Modules/Calcs.lua", "r")
        assert.is_not_nil(f, "must be able to open Modules/Calcs.lua")
        source = f:read("*a")
        f:close()
    end)

    it("regression-guard comment block is present", function()
        assert.is_truthy(string.find(source, "per-type-crit-multi-overview-keywordflags", 1, true),
            "Calcs.lua must keep the @leb-regression-guard comment so future edits trip review")
    end)

    it("damage-source table is keyed to KeywordFlag.<Source>, not ModFlag.<Source>", function()
        -- Locate the table and assert each entry uses KeywordFlag.
        local block = string.match(source, "critTypeKeywordFlags%s*=%s*%b{}")
        assert.is_not_nil(block, "critTypeKeywordFlags table must exist in Calcs.lua")
        for _, src in ipairs({ "Melee", "Spell", "Bow", "Throwing" }) do
            assert.is_truthy(string.find(block, src .. "%s*=%s*KeywordFlag%." .. src),
                src .. " must filter via KeywordFlag." .. src .. " (not ModFlag." .. src .. ") "
                .. "so damage-source-prefixed CritMultiplier mods actually match")
        end
    end)

    it("cfg passes Hit via flags and the damage-source via keywordFlags", function()
        -- The Sum call must combine flags = ModFlag.Hit with keywordFlags = <kwFlags>
        -- inside the iteration over critTypeKeywordFlags.
        local pat = 'env%.modDB:Sum%("BASE",%s*{%s*flags%s*=%s*ModFlag%.Hit'
                 .. ',%s*keywordFlags%s*=%s*kwFlags%s*}%s*,%s*"CritMultiplier"%s*%)'
        assert.is_truthy(string.find(source, pat),
            "Calcs.lua must pass `flags = ModFlag.Hit, keywordFlags = kwFlags` to Sum so the "
            .. "Hit context is in the flags bucket and the damage-source filter is in the "
            .. "keywordFlags bucket (matching how ModParser tags damage-source-prefixed mods)")
    end)
end)
