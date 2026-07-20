-- @leb-regression-guard:no-spectre-library
-- Locks the removal of the upstream PoB "spectre library" -- a feature LE has no
-- mechanic for, which survived the fork as unreachable code and one guaranteed crash.
--
-- In PoB, a granted effect with an EMPTY minionList meant "the user picks which
-- spectres this skill raises", and the picks came from a build-level library
-- (`build.spectreList`) populated from `data.spectres`. LEB never ported any of it:
--   * `data.spectres` was never assigned anywhere (only ever READ, in OpenSpectreLibrary),
--     so the popup died on `pairs(nil)` before it could open;
--   * `build.spectreList` was never initialised, so the CalcActiveSkill fallback
--     `copyTable(env.build.spectreList)` would have thrown on `pairs(nil)` too;
--   * `skillFlags.spectre` was never set, so the CalcsTab "Spectre Library" section
--     was permanently hidden;
--   * MinionListControl's tooltip read `minion.fireResist/.coldResist/.lightningResist/
--     .chaosResist` and `minion.damage/.attackTime` -- NONE of which minions.json carries
--     (its entire field set is skillList/modList/name/life/monsterScaling/
--     noInherentDamageScaling) -- and coloured the chaos term with `colorCodes.CHAOS`,
--     which does not exist, LE having no Chaos damage type at all.
--
-- Three invariants below. Each one, if broken, silently resurrects part of that chain.
-- NOTE: "Blood Spectre" (Necromancer tree) and `ActiveSpectreLimit` are REAL LE game
-- data and are deliberately untouched -- do not widen these greps to plain "Spectre".
-- See REGRESSION_GUARDS.md "no-spectre-library".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a"); f:close()
    return text
end

-- Resolve the src/ tree root regardless of whether busted runs with cwd=src or repo root.
local function srcRoot()
    for _, candidate in ipairs({ "src", ".", "../src" }) do
        if lfs.attributes(candidate .. "/Data/Global.lua", "mode") == "file" then
            return candidate
        end
    end
    error("cannot locate the src/ tree")
end

-- Every .lua under src/, excluding TreeData/ (huge generated JSON-ish blobs, no code).
local function eachSourceFile(fn)
    local root = srcRoot()
    local function walk(dir)
        for entry in lfs.dir(dir) do
            if entry ~= "." and entry ~= ".." then
                local path = dir .. "/" .. entry
                local mode = lfs.attributes(path, "mode")
                if mode == "directory" then
                    if entry ~= "TreeData" then walk(path) end
                elseif mode == "file" and entry:match("%.lua$") then
                    fn(path, readSource(path))
                end
            end
        end
    end
    walk(root)
end

describe("NoSpectreLibrary #spectre", function()
    it("no source file references the spectre-library symbols", function()
        -- Plain substring scan (find with plain=true), so `data.spectres` etc. are literal.
        local banned = {
            "spectreList",           -- the build-level library list (never initialised)
            "data.spectres",         -- the source table (never assigned)
            "OpenSpectreLibrary",    -- the popup that died on pairs(nil)
            "MinionListControl",     -- the control whose tooltip read fields minions never had
            "mainSkillMinionLibrary",-- the "Manage Spectres..." button
        }
        local offenders = {}
        eachSourceFile(function(path, text)
            -- The guard comment in CalcActiveSkill.lua names these symbols on purpose.
            local code = text:gsub("%-%-[^\n]*", "")
            for _, symbol in ipairs(banned) do
                if code:find(symbol, 1, true) then
                    table.insert(offenders, path .. " -> " .. symbol)
                end
            end
        end)
        assert.are.same({}, offenders)
    end)

    it("every skills.json minionList is non-empty, so no spectre fallback is needed", function()
        -- This is the invariant that made the removal safe: the empty-minionList branch
        -- (PoB's "user picks the minions" case) is the ONLY thing spectreList ever fed.
        -- A skill shipping an empty minionList would silently get no minions at all.
        -- Read the table the engine actually loaded, not a re-parse of the file.
        assert.is_not_nil(data and data.skills, "data.skills must be loaded")
        local empty, withList = {}, 0
        for id, skill in pairs(data.skills) do
            if type(skill) == "table" and type(skill.minionList) == "table" then
                withList = withList + 1
                if skill.minionList[1] == nil then table.insert(empty, id) end
            end
        end
        assert.is_true(withList > 0, "expected at least one skill to declare a minionList")
        assert.are.same({}, empty)
    end)

    it("every colorCodes key referenced in source is actually defined", function()
        -- Generalises the original defect: `colorCodes.CHAOS` was referenced but never
        -- defined, so s_format("%s", nil) faulted. LE's damage types are Physical/Fire/
        -- Cold/Lightning/Void/Necrotic/Poison -- there is no Chaos.
        local global = readSource("Data/Global.lua")
        local defined = {}
        -- Keys in the `colorCodes = { ... }` literal, plus later `colorCodes.X = ...` aliases.
        local literal = global:match("colorCodes%s*=%s*(%b{})")
        assert.is_not_nil(literal, "must find the colorCodes table literal in Global.lua")
        for key in literal:gmatch("[%s{,]([%a_][%w_]*)%s*=") do defined[key] = true end
        for key in global:gmatch("colorCodes%.([%a_][%w_]*)%s*=") do defined[key] = true end
        assert.is_true(defined.FIRE and defined.VOID and defined.NECROTIC and defined.POISON,
            "sanity: LE's own damage-type colours must be among the defined keys")
        assert.is_nil(defined.CHAOS, "LE has no Chaos damage type; CHAOS must not be defined")

        local offenders = {}
        eachSourceFile(function(path, text)
            local code = text:gsub("%-%-[^\n]*", "")
            for key in code:gmatch("colorCodes%.([%a_][%w_]*)") do
                -- Skip the definition sites themselves (`colorCodes.X = ...`).
                if not defined[key] then
                    table.insert(offenders, path .. " -> colorCodes." .. key)
                end
            end
        end)
        assert.are.same({}, offenders)
    end)
end)
