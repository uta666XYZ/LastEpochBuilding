-- @leb-regression-guard:config-highlight-item-slot-kind
-- @leb-regression-guard:config-highlight-tooltip-maxwidth
-- Phase 6 (2026-05-29) of the Config-highlight family. Two user-reported
-- in-game refinements:
--
--   (1) Slot-specific source labels. The equipped-item source label was a
--       generic "item 'X'" for every slot. Phase 6 derives the specific
--       kind from item.type via getItemSourceKind(item, slotName):
--         "Idol Altar"  -> "idol altar"
--         "Blessing"    -> "blessing (<timeline>)"
--         "<size> Idol" -> "idol"
--         everything else -> item.type:lower()  (ring / helmet / boots / ...)
--         nil / unknown -> "item"  (graceful fallback)
--       so the tooltip reads e.g. "ring 'Red Ring of Atlaria'" or
--       "idol altar 'Sunrise Prophesied Altar of Arctus'".
--
--   (2) Tooltip width. The config tab never set a tooltip maxWidth, so
--       TooltipClass:AddLine's wrap path (gated on self.maxWidth) was
--       skipped and long lines (source trailers with full affix text,
--       multi-source lists, the old all-patterns enumeration) ran off
--       the right edge of the screen. Phase 6 sets tooltip.maxWidth in
--       the config tooltipFunc and drops the redundant all-patterns
--       enumeration from the suggestPattern message (the source trailer
--       already shows the actual matched line).
--
-- These are source-text structural assertions (consistent with the rest
-- of the config-highlight spec family, which lock the ConfigTab.lua
-- implementation shape rather than instantiating the closures).
--
-- See REGRESSION_GUARDS.md "config-highlight-item-slot-kind" +
-- "config-highlight-tooltip-maxwidth".

describe("ConfigHighlightItemSlotKind", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local cfgTabSrc
    setup(function()
        cfgTabSrc = readFile("Classes/ConfigTab.lua")
        assert.is_not_nil(cfgTabSrc, "must read Classes/ConfigTab.lua")
    end)

    it("Phase 6 inline guard markers are present", function()
        assert.is_truthy(cfgTabSrc:find("@leb%-regression%-guard:config%-highlight%-item%-slot%-kind", 1, false),
            "ConfigTab.lua must carry the item-slot-kind guard marker")
        assert.is_truthy(cfgTabSrc:find("@leb%-regression%-guard:config%-highlight%-tooltip%-maxwidth", 1, false),
            "ConfigTab.lua must carry the tooltip-maxwidth guard marker")
    end)

    it("getItemSourceKind helper exists and maps item.type to slot-specific kinds", function()
        local startIdx = cfgTabSrc:find("local function getItemSourceKind", 1, true)
        assert.is_not_nil(startIdx, "getItemSourceKind helper must be declared")
        local nextFn = cfgTabSrc:find("\n%s*local function ", startIdx + 1)
        local fnBody = cfgTabSrc:sub(startIdx, nextFn or #cfgTabSrc)

        -- Signature carries (item, slotName).
        assert.is_truthy(fnBody:find("getItemSourceKind(item, slotName)", 1, true),
            "signature must be getItemSourceKind(item, slotName)")
        -- Reads item.type as the classifying signal.
        assert.is_truthy(fnBody:find("item.type", 1, true) or fnBody:find("item%.type", 1, false),
            "must classify by item.type")
        -- Idol Altar special-case.
        assert.is_truthy(fnBody:find('"Idol Altar"', 1, true) and fnBody:find('"idol altar"', 1, true),
            "must map type 'Idol Altar' -> 'idol altar'")
        -- Blessing special-case + timeline (slotName) surfaced.
        assert.is_truthy(fnBody:find('"Blessing"', 1, true) and fnBody:find('"blessing', 1, true),
            "must map type 'Blessing' -> 'blessing'")
        assert.is_truthy(fnBody:find("slotName", 1, true),
            "blessing branch must surface the timeline via slotName")
        -- Idol footprint collapse: any '<size> Idol' type -> 'idol'.
        assert.is_truthy(fnBody:find('"Idol$"', 1, true) or fnBody:find('Idol%$', 1, false),
            "must collapse any '...Idol' type to 'idol' via an Idol$ pattern")
        assert.is_truthy(fnBody:find('"idol"', 1, true),
            "idol branch must return 'idol'")
        -- Generic fall-through lowercases the type (ring / helmet / boots / ...).
        assert.is_truthy(fnBody:find("t:lower()", 1, true) or fnBody:find("type:lower", 1, true),
            "generic fall-through must lowercase item.type (ring / helmet / boots / ...)")
        -- Graceful fallback to 'item' for nil / empty type.
        assert.is_truthy(fnBody:find('"item"', 1, true),
            "must fall back to 'item' for nil / unknown type")
    end)

    it("Pass 3 and Source B both route their label through getItemSourceKind", function()
        -- Count plain-text occurrences (string.find with plain=true; gsub
        -- would treat the parens/dots as Lua-pattern metacharacters).
        local count, pos = 0, 1
        while true do
            local s = cfgTabSrc:find("getItemSourceKind(item, slot.slotName)", pos, true)
            if not s then break end
            count = count + 1
            pos = s + 1
        end
        assert.is_true(count >= 2,
            "both Pass 3 (detectGrantedBuffs) and Source B (corpus) must call getItemSourceKind(item, slot.slotName); found " .. tostring(count))
        -- The old hardcoded generic "item '" .. itemName label must be gone.
        assert.falsy(cfgTabSrc:find('"item \'" .. itemName', 1, true),
            "no hardcoded generic \"item '\" .. itemName label may remain (Phase 6 replaced both with getItemSourceKind)")
    end)

    it("config tooltipFunc sets tooltip.maxWidth so AddLine wraps", function()
        -- The wrap path in TooltipClass:AddLine only runs when self.maxWidth
        -- is set. The config tab must set it (idempotently) in the tooltip
        -- closure so long source trailers wrap instead of running off-screen.
        assert.is_truthy(cfgTabSrc:find("if not tooltip.maxWidth then", 1, true),
            "config tooltipFunc must set tooltip.maxWidth idempotently")
        assert.is_truthy(cfgTabSrc:find("tooltip.maxWidth = ", 1, true),
            "config tooltipFunc must assign tooltip.maxWidth")
    end)

    it("suggestPattern message no longer enumerates ALL declared patterns (width fix)", function()
        -- The old message built `'a' / 'b' / 'c' / ...` from the full
        -- declared pattern list via table.concat(pattern, "' / '"), which
        -- produced one very long unbreakable line. Phase 6 drops it; the
        -- source trailer shows the actual matched line instead.
        assert.falsy(cfgTabSrc:find('table.concat(pattern', 1, true),
            "suggestPattern render must NOT enumerate all declared patterns via table.concat(pattern, ...) anymore")
        assert.falsy(cfgTabSrc:find("Your build mentions ", 1, true),
            "the old 'Your build mentions <all patterns>' message must be gone")
        -- The concise replacement lead-in is present.
        assert.is_truthy(cfgTabSrc:find("Your build references this state", 1, true),
            "suggestPattern must use the concise 'Your build references this state' lead-in")
    end)

    it("source trailers still use ASCII hyphen / colon, never em-dash (font U+2014 trap preserved)", function()
        for line in cfgTabSrc:gmatch("[^\n]+") do
            if line:find("trailer", 1, true) and line:find("%.%.") then
                assert.falsy(line:find("\xe2\x80\x94", 1, true),
                    "tooltip trailer expression must not contain em-dash U+2014; offending line: " .. line)
            end
        end
    end)
end)
