-- @leb-regression-guard: hammer-of-lorent-tooltipdescriptions-missing-mods
-- Hammer of Lorent (unique Hammer, uniqueID=41) in `src/Data/Uniques/uniques_1_4.json`
-- previously stored ONLY its two rolled affixes:
--   * "(20-80)% Chance to Chill on Hit"        (rollId 0)
--   * "(20-80)% increased Melee Damage"         (rollId 1)
-- and dropped the two fixed per-character-level tooltip lines that LE itself
-- surfaces (datamined game source `tooltipDescriptions`):
--
--   1. "+1 melee physical damage per level ([1,c])"
--   2. "1% increased melee stun chance per level ([1,c]%)"
--
-- This is the SAME drop class as Frozen Ire (#32, fixed in <see git log>): the
-- per-character-level lines live ONLY in the `tooltipDescriptions` block of the
-- datamining export and NEVER in the structured `mods` roll table, so the LEB
-- transcription that walked the roll table silently lost them. The systematic
-- audit (spec/tools/audit_uniques_tooltipdescriptions.py) found Frozen Ire and
-- Hammer of Lorent to be the ONLY two uniques carrying bracket "[..,c,..]"
-- (per-character-level) tooltip lines in the entire 471-unique corpus; every
-- other "per <X>" line is per-stat / per-stack and was already modelled.
--
-- Calc impact: at character level L a Hammer-of-Lorent build gains +L flat melee
-- physical damage and +L% increased melee stun chance (e.g. +100 / +100% at lv100).
-- The 4th tooltip line of Calamity-style triggers does not apply here; Hammer of
-- Lorent has no triggered subskill, so there is no carve-out.
--
-- ModParser already understands both lines (no parser change):
--   "+1 Melee Physical Damage per level"        -> PhysicalDamage BASE 1,
--        keywordFlags=Melee, tag Multiplier{var="Level"}
--   "1% increased Melee Stun Chance per level"  -> StunChance INC 1,
--        keywordFlags=Melee, tag Multiplier{var="Level"}
-- CalcSetup.lua sets multipliers["Level"] = build.characterLevel, so each mod
-- evaluates to 1 x characterLevel. The "per level" alias is the same path
-- Frozen Ire relies on.
--
-- The fix lives entirely in `src/Data/Uniques/uniques_1_4.json` Hammer of Lorent
-- (#41) `mods` (two new entries) and `rollIds` (two new `null`s so the rolled
-- affixes keep rollId 0/1). This spec pins the JSON shape so a future regen /
-- merge of datamined game source cannot silently drop the fixed tooltip lines again.
-- See REGRESSION_GUARDS.md "hammer-of-lorent-tooltipdescriptions-missing-mods".
local dkjson = require("dkjson")

describe("HammerOfLorentTooltipDescriptionsMods", function()
    local function readFile(path)
        local f = assert(io.open(path, "r"), "missing: " .. path)
        local s = f:read("*a")
        f:close()
        return s
    end

    local function findByName(uniques, name)
        for _, u in pairs(uniques) do
            if type(u) == "table" and u.name == name then
                return u
            end
        end
        return nil
    end

    -- ----- Fix: uniques_1_4.json #41 carries both per-char-level scalars -----
    describe("src/Data/Uniques/uniques_1_4.json #41 Hammer of Lorent", function()
        local json = readFile("Data/Uniques/uniques_1_4.json")
        local uniques = dkjson.decode(json)
        local hl = findByName(uniques, "Hammer of Lorent")

        it("entry exists with name 'Hammer of Lorent'", function()
            assert.is_not_nil(hl, "Hammer of Lorent (uniqueID 41) missing from uniques_1_4.json")
        end)

        it("is keyed at id '41'", function()
            assert.is_not_nil(uniques["41"], "id-keyed entry '41' must exist")
            assert.are.equal("Hammer of Lorent", uniques["41"].name)
        end)

        it("retains the rolled '(20-80)% Chance to Chill on Hit' affix", function()
            local found = false
            for _, m in ipairs(hl.mods) do
                if m:find("%(20%-80%)%% Chance to Chill on Hit") then found = true; break end
            end
            assert.is_true(found, "rolled Chance-to-Chill affix must remain")
        end)

        it("retains the rolled '(20-80)% increased Melee Damage' affix", function()
            local found = false
            for _, m in ipairs(hl.mods) do
                if m:find("%(20%-80%)%% increased Melee Damage") then found = true; break end
            end
            assert.is_true(found, "rolled increased-Melee-Damage affix must remain")
        end)

        it("carries '+1 Melee Physical Damage per level'", function()
            local found = false
            for _, m in ipairs(hl.mods) do
                if m:find("Melee Physical Damage per level") and m:find("^%+1 ") then
                    found = true; break
                end
            end
            assert.is_true(found,
                "missing '+1 Melee Physical Damage per level' on Hammer of Lorent — " ..
                "dropped per-character-level tooltipDescription (Frozen Ire drop class)")
        end)

        it("carries '1% increased Melee Stun Chance per level'", function()
            local found = false
            for _, m in ipairs(hl.mods) do
                if m:find("increased Melee Stun Chance per level") and m:find("^1%% ") then
                    found = true; break
                end
            end
            assert.is_true(found,
                "missing '1% increased Melee Stun Chance per level' on Hammer of Lorent")
        end)

        it("only the rolled lines roll; per-char-level lines have nil rollId", function()
            -- The two rolled affixes keep rollId 0/1 (LE/LETools roll identifiers).
            -- The two fixed per-char-level lines must have rollId=nil so ImportTab
            -- routes them to the "no range" (crafted) branch.
            assert.are.equal(0, hl.rollIds[1],
                "rolled 'Chance to Chill' must keep rollId=0")
            assert.are.equal(1, hl.rollIds[2],
                "rolled 'increased Melee Damage' must keep rollId=1")
            for i = 3, #hl.mods do
                assert(hl.rollIds[i] == nil,
                    string.format("rollIds[%d] must be nil (per-char-level tooltip mod, no roll)", i))
            end
        end)

        it("carries the @leb-regression-guard anchor at the spec head", function()
            local specSrc = readFile("../spec/System/TestHammerOfLorentTooltipDescriptionsMods_spec.lua")
            assert.is_truthy(
                specSrc:find("@leb%-regression%-guard:%s*hammer%-of%-lorent%-tooltipdescriptions%-missing%-mods"),
                "guard anchor must remain inline at the top of this spec")
        end)
    end)

    -- ----- Calc-side: each per-level mod evaluates to +characterLevel -----
    describe("ModParser + Multiplier:Level evaluation", function()
        it("parses '+1 Melee Physical Damage per level' to PhysicalDamage BASE w/ Melee + Multiplier:Level", function()
            local mods = modLib.parseMod("+1 Melee Physical Damage per level")
            assert.is_table(mods, "must parse to a mod list")
            assert.are.equal(1, #mods, "expected one mod")
            local m = mods[1]
            assert.are.equal("PhysicalDamage", m.name)
            assert.are.equal("BASE", m.type)
            assert.are.equal(1, m.value)
            assert.are.equal(KeywordFlag.Melee, m.keywordFlags,
                "must carry the Melee keyword flag")
            local levelTag
            for _, tag in ipairs(m) do
                if tag.type == "Multiplier" and tag.var == "Level" then levelTag = tag end
            end
            assert.is_not_nil(levelTag,
                "Multiplier{var='Level'} tag missing — 'per level' alias regressed")
        end)

        it("parses '1% increased Melee Stun Chance per level' to StunChance INC w/ Melee + Multiplier:Level", function()
            local mods = modLib.parseMod("1% increased Melee Stun Chance per level")
            assert.is_table(mods, "must parse to a mod list")
            assert.are.equal(1, #mods, "expected one mod")
            local m = mods[1]
            assert.are.equal("StunChance", m.name)
            assert.are.equal("INC", m.type)
            assert.are.equal(1, m.value)
            assert.are.equal(KeywordFlag.Melee, m.keywordFlags,
                "must carry the Melee keyword flag")
            local levelTag
            for _, tag in ipairs(m) do
                if tag.type == "Multiplier" and tag.var == "Level" then levelTag = tag end
            end
            assert.is_not_nil(levelTag,
                "Multiplier{var='Level'} tag missing — 'per level' alias regressed")
        end)

        it("evaluates per-level melee phys to +characterLevel via modDB:Sum", function()
            -- Parse the real mod string and add it end-to-end (avoids the
            -- positional flags/keywordFlags arg trap of NewMod; faithful to the
            -- actual ImportTab -> ModParser -> ModDB path).
            local db = new("ModDB")
            db.multipliers["Level"] = 100
            for _, m in ipairs(modLib.parseMod("+1 Melee Physical Damage per level")) do
                db:AddMod(m)
            end
            assert.are.equal(100, db:Sum("BASE", { keywordFlags = KeywordFlag.Melee }, "PhysicalDamage"),
                "Hammer of Lorent's per-level melee phys must contribute exactly " ..
                "+characterLevel (1 x Level multiplier) at lv100.")
        end)
    end)
end)
