-- @leb-regression-guard: frozen-ire-per-char-level-mods
-- silently drop the fixed tooltip lines again. See REGRESSION_GUARDS.md
-- Validation provenance is retained in maintainer notes.
local dkjson = require("dkjson")

describe("FrozenIrePerCharLevelMods", function()
    local function readFile(path)
        local f = assert(io.open(path, "r"), "missing: " .. path)
        local s = f:read("*a")
        f:close()
        return s
    end

    -- ----- Fix: uniques_1_4.json #32 carries all four player-facing mods -----
    -- The Tundra-Nova trigger ("15% chance to cast tundra nova on hit with cold
    -- skills") is a triggered subskill and is intentionally out of scope here
    -- (skill-injection plumbing, not a calc-side scalar). The other three are
    -- pure modDB scalars and MUST be present.
    local function findFrozenIre(uniques)
        for _, u in pairs(uniques) do
            if type(u) == "table" and u.name == "Frozen Ire" then
                return u
            end
        end
        return nil
    end

    describe("src/Data/Uniques/uniques_1_4.json #32 Frozen Ire", function()
        local json = readFile("Data/Uniques/uniques_1_4.json")
        local uniques = dkjson.decode(json)
        local fi = findFrozenIre(uniques)

        it("entry exists with name 'Frozen Ire'", function()
            assert.is_not_nil(fi, "Frozen Ire (uniqueID 32) missing from uniques_1_4.json")
        end)

        it("retains the rolled '(80-120)% increased Cold Damage' affix", function()
            local found = false
            for _, m in ipairs(fi.mods) do
                if m:find("%(80%-120%)%% increased Cold Damage") then found = true; break end
            end
            assert.is_true(found, "rolled Cold Damage affix must remain")
        end)

        it("carries '+1% Necrotic Resistance per level' (the SuXes Δ-92 root)", function()
            local found = false
            for _, m in ipairs(fi.mods) do
                if m:find("Necrotic Resistance per level") and m:find("^%+1%%") then
                    found = true; break
                end
            end
            assert.is_true(found,
                "missing '+1% Necrotic Resistance per level' on Frozen Ire — " ..
                "this is the source of the SuXes lv92 Δ=-92 NecroticResistRaw outlier")
        end)

        it("carries '+2% Freeze Rate Multiplier per level'", function()
            local found = false
            for _, m in ipairs(fi.mods) do
                if m:find("Freeze Rate Multiplier per level") and m:find("^%+2%%") then
                    found = true; break
                end
            end
            assert.is_true(found,
                "missing '+2% Freeze Rate Multiplier per level' on Frozen Ire")
        end)

        it("carries '+1 Spell Cold Damage per 5 level'", function()
            local found = false
            for _, m in ipairs(fi.mods) do
                if m:find("Spell Cold Damage per 5 level") then
                    found = true; break
                end
            end
            assert.is_true(found,
                "missing '+1 Spell Cold Damage per 5 level' on Frozen Ire")
        end)

        it("only the cold-damage line rolls; per-char-level lines have nil rollId", function()
            -- The rolled affix is at index 1 (rollId=1, mirrors the legacy single-mod
            -- shape). The three fixed tooltip lines must have rollId=nil so the
            -- ImportTab loop at src/Classes/ImportTab.lua:1383-1394 routes them to
            -- the "no range" branch (`{crafted}` prefix, no `{range:X}`).
            -- (Note: Lua `#` stops at the first nil, so a length compare against
            -- #mods is meaningless once index 2 is nil; we check each slot directly.)
            assert.are.equal(1, fi.rollIds[1],
                "Frozen Ire's rolled '(80-120)% Cold Damage' must keep rollId=1 " ..
                "(LE/LETools planner roll identifier)")
            for i = 2, #fi.mods do
                assert(fi.rollIds[i] == nil,
                    string.format("rollIds[%d] must be nil (per-char-level tooltip mod, no roll)", i))
            end
        end)

        it("carries the @leb-regression-guard anchor at the spec head", function()
            -- This spec file itself documents the guard; the anchor must be present
            -- so a grep-based audit (`grep -r '@leb-regression-guard:frozen-ire' src spec`)
            -- finds at least one anchor pointing to this fix.
            local specSrc = readFile("../spec/System/TestFrozenIrePerCharLevelMods_spec.lua")
            assert.is_truthy(
                specSrc:find("@leb%-regression%-guard:%s*frozen%-ire%-per%-char%-level%-mods"),
                "guard anchor must remain inline at the top of this spec")
        end)
    end)

    -- ----- Calc-side: the per-level mod evaluates to +92 at character level 92 -----
    describe("ModParser + Multiplier:Level evaluation", function()
        it("parses '+1% Necrotic Resistance per level' to a BASE mod with Multiplier:Level", function()
            local mods = modLib.parseMod("+1% Necrotic Resistance per level")
            assert.is_table(mods, "must parse to a mod list")
            assert.are.equal(1, #mods, "expected one mod")
            local m = mods[1]
            assert.are.equal("NecroticResist", m.name)
            assert.are.equal("BASE", m.type)
            assert.are.equal(1, m.value)
            local levelTag
            for _, tag in ipairs(m) do
                if tag.type == "Multiplier" and tag.var == "Level" then
                    levelTag = tag
                end
            end
            assert.is_not_nil(levelTag,
                "Multiplier{var='Level'} tag missing — 'per level' alias regressed")
        end)

        it("evaluates to +characterLevel via modDB:Sum (BASE NecroticResist)", function()
            local db = new("ModDB")
            db.multipliers["Level"] = 92
            db:NewMod("NecroticResist", "BASE", 1, "Frozen Ire",
                { type = "Multiplier", var = "Level" })
            assert.are.equal(92, db:Sum("BASE", nil, "NecroticResist"),
                "Frozen Ire's per-level mod must contribute exactly +characterLevel " ..
                "to BASE NecroticResist (1 × Level multiplier).")
        end)
    end)
end)
