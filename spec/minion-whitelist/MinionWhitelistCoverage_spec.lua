-- @leb-regression-guard:minion-whitelist-3surface-union
-- Locks the contract that the LEB minion-stat whitelist is shipped as the
-- UNION of three independent game-data surfaces (altText / affixTag /
-- runtime), as merged by `LE_datamining/merge_minion_whitelist_3surfaces.py`.
--
-- The merged JSON sits at `spec/minion-whitelist/whitelist_final.json` and
-- documents which (sp, tagBits, specialTag) tuples game-side routes to
-- minions. Downstream LEB consumer is the `sumMinion` bucket loop in
-- `CalcDefence.lua` (~line 1735), which reads `MinionModifier` LIST
-- entries emitted by `ModParser.lua` / `SkillStatMap.lua`. Adding a new
-- Minion* output without a backing whitelist entry, OR shrinking the
-- whitelist to an intersection of the three surfaces, would silently
-- drop legitimate minion stats.
--
-- See REGRESSION_GUARDS.md "minion-whitelist-3surface-union".

describe("Minion whitelist 3-surface union", function()
    local cjson_ok, cjson = pcall(require, "lua.dkjson")
    if not cjson_ok then cjson_ok, cjson = pcall(require, "dkjson") end

    local function loadWhitelist()
        local f = assert(io.open("../spec/minion-whitelist/whitelist_final.json", "r"),
            "whitelist_final.json must be present alongside the surface JSONs")
        local data = f:read("*a")
        f:close()
        assert.is_truthy(cjson_ok and cjson.decode, "dkjson must be available")
        local parsed, _, err = cjson.decode(data)
        assert.is_nil(err, "whitelist_final.json must be valid JSON: " .. tostring(err))
        return parsed
    end

    it("loads with 3 surfaces and a non-empty entry list", function()
        local wl = loadWhitelist()
        assert.is_not_nil(wl._meta, "missing _meta")
        assert.are.same({"altText", "affixTag", "runtime"}, wl._meta.surfaces)
        assert.is_table(wl.entries)
        assert.is_true(#wl.entries > 0, "entries must be non-empty (union, not intersection)")
        -- 152 is the as-shipped count; if a re-merge legitimately changes this,
        -- update the assertion AND the count in REGRESSION_GUARDS.md.
        assert.are.equals(152, wl._meta.merged_entries)
    end)

    it("every entry carries property/tagBits/specialTag/surfaces/confidence", function()
        local wl = loadWhitelist()
        for i, e in ipairs(wl.entries) do
            assert.is_number(e.property, "entry " .. i .. " property must be a number")
            assert.is_table(e.tagBits, "entry " .. i .. " tagBits must be a table")
            assert.is_number(e.specialTag, "entry " .. i .. " specialTag must be a number")
            assert.is_table(e.surfaces, "entry " .. i .. " surfaces must be a table")
            assert.is_true(#e.surfaces > 0,
                "entry " .. i .. " must have at least one contributing surface " ..
                "(zero surfaces means the merge script has a bug)")
            assert.is_truthy(e.confidence == "high" or e.confidence == "medium" or e.confidence == "low",
                "entry " .. i .. " confidence must be one of {high, medium, low}")
        end
    end)

    it("confidence tier matches surface count", function()
        local wl = loadWhitelist()
        for i, e in ipairs(wl.entries) do
            local n = #e.surfaces
            if n >= 2 then
                assert.are.equals("high", e.confidence,
                    "entry " .. i .. " has " .. n .. " surfaces -> must be high")
            else
                local sole = e.surfaces[1]
                if sole == "altText" or sole == "affixTag" then
                    assert.are.equals("medium", e.confidence,
                        "entry " .. i .. " single-source static surface -> medium")
                else
                    assert.are.equals("low", e.confidence,
                        "entry " .. i .. " runtime-only -> low (advisory until player-only re-capture)")
                end
            end
        end
    end)

    it("CalcDefence sumMinion block carries the guard marker", function()
        local f = assert(io.open("Modules/CalcDefence.lua", "r"))
        local body = f:read("*a")
        f:close()
        assert.is_truthy(
            body:find("@leb-regression-guard: minion-whitelist-3surface-union", 1, true),
            "CalcDefence.lua sumMinion block must keep the minion-whitelist-3surface-union marker")
        -- The wire-in must point at the spec/minion-whitelist directory so a
        -- future maintainer can find the provenance for any new Minion* output.
        assert.is_truthy(
            body:find("spec/minion-whitelist/whitelist_final.json", 1, true),
            "CalcDefence.lua must cite the whitelist_final.json path as the provenance source")
    end)

    -- =================================================================
    -- Drift detection (B15 wire-in C改, 2026-05-18)
    --
    -- Forward drift: every HIGH/MEDIUM whitelist entry must EITHER map
    -- to a `Minion*` output in CalcDefence.lua sumMinion block, OR
    -- appear in INTENTIONAL_OMISSIONS with a documented reason. New
    -- HIGH/MEDIUM whitelist entries added by a future re-merge (script
    -- `merge_minion_whitelist_3surfaces.py`) will fail this test until
    -- explicitly classified, preventing silent under-coverage of the
    -- LEB minion-tab summary.
    --
    -- Reverse drift: every key in WHITELIST_TO_MINION_OUTPUT must still
    -- appear in whitelist_final.json with HIGH or MEDIUM confidence —
    -- catches the case where a stat was removed from game data (or
    -- demoted to LOW / runtime-only) but the LEB output is still wired.
    --
    -- LOW (runtime-only) entries are intentionally outside this drift
    -- check; they remain advisory until a player-only re-capture
    -- promotes them to HIGH/MEDIUM (see README.md "Runtime capture
    -- procedure"). MinionCompanionReviveSpeed/Range / MinionReduceCrit-
    -- ExtraDamage are LOW-only outputs that ship today as best-effort.
    -- =================================================================

    local function whitelistKey(sp, tagBits, specialTag)
        local bits = {}
        for _, b in ipairs(tagBits) do bits[#bits + 1] = b end
        table.sort(bits)
        return tostring(sp) .. "/" .. table.concat(bits, ",") .. "/" .. tostring(specialTag)
    end

    -- Maps (sp, sortedTagBits, specialTag) → expected Minion* output
    -- name in CalcDefence.lua. The output name must appear as
    -- `output.<name> = sumMinion(...)` in the sumMinion block.
    local WHITELIST_TO_MINION_OUTPUT = {
        -- sp=0 Damage per element (HIGH — affixTag ∪ altText)
        ["0/1,8192/0"]   = "MinionPhysicalDamageInc",
        ["0/2,8192/0"]   = "MinionLightningDamageInc",
        ["0/4,8192/0"]   = "MinionColdDamageInc",
        ["0/8,8192/0"]   = "MinionFireDamageInc",
        ["0/16,8192/0"]  = "MinionVoidDamageInc",
        ["0/32,8192/0"]  = "MinionNecroticDamageInc",
        ["0/64,8192/0"]  = "MinionPoisonDamageInc",
        -- HIGH non-damage primaries
        ["7/8192/0"]     = "MinionLifeInc",       -- Health
        ["10/8192/0"]    = "MinionArmour",        -- Armor (BASE; companion *Inc not on whitelist)
        ["11/8192/0"]    = "MinionEvasion",       -- Dodge Rating
        ["17/8192/0"]    = "MinionLifeRegen",     -- Health Regen
        -- MEDIUM with shipped Minion* output
        ["9/8192/0"]     = "MinionMovementSpeed",
        ["13/8192/0"]    = "MinionFireResist",
        ["14/8192/0"]    = "MinionColdResist",
        ["15/8192/0"]    = "MinionLightningResist",
        ["26/8192/0"]    = "MinionVoidResist",
        ["27/8192/0"]    = "MinionNecroticResist",
        ["28/8192/0"]    = "MinionPoisonResist",
        ["44/8192/0"]    = "MinionHealingEffectiveness",
        ["59/1,8192/0"]  = "MinionPhysicalPenetration",
        ["59/2,8192/0"]  = "MinionLightningPenetration",
        ["59/4,8192/0"]  = "MinionColdPenetration",
        ["59/8,8192/0"]  = "MinionFirePenetration",
        ["59/16,8192/0"] = "MinionVoidPenetration",
        ["59/32,8192/0"] = "MinionNecroticPenetration",
        ["59/64,8192/0"] = "MinionPoisonPenetration",
        ["64/8192/0"]    = "MinionPhysicalResist",
        ["70/8192/0"]    = "MinionCooldownRecovery",
        ["86/8192/0"]    = "MinionDamageReflected",
        ["89/8192/0"]    = "MinionCritAvoidance",
        -- B15 HIGH-gap closure (2026-05-18): inner mod is `Speed INC` with
        -- ModFlag.Attack / ModFlag.Cast so the sumMinion bucket key is
        -- partitioned by flag (guard "minion-bucket-flags-partition" in
        -- CalcDefence.lua). Promoted from INTENTIONAL_OMISSIONS once the
        -- two `output.MinionAttackSpeed = sumMinion(...)` /
        -- `output.MinionCastSpeed = sumMinion(...)` lines landed.
        ["2/512,8192/0"] = "MinionAttackSpeed",  -- HIGH 3-surface (Melee tag bit + Minion tag bit)
        ["3/8192/0"]     = "MinionCastSpeed",    -- HIGH 3-surface (Minion tag bit only; Cast = Spell internally)
    }

    -- Whitelist entries deliberately not surfaced as a Minion* output.
    -- HIGH entries here are explicit UI follow-ups (track on the LE_-
    -- datamining 16-batch board); MEDIUM entries are design omissions
    -- (sub-skill bucketing already aggregated, stat displayed on a
    -- different surface, etc.). Adding a new key must come with a
    -- one-line reason so a future reader sees the rationale.
    local INTENTIONAL_OMISSIONS = {
        -- HIGH gaps (UI follow-up; whitelist HIGH but no Minion* output yet)
        ["0/8192/0"]       = "HIGH bare-Damage minion stat (no element bit) — subsumed by per-element MinionXxxDamageInc outputs; no separate UI tile.",
        -- 2026-05-18 promoted from HIGH gap → WHITELIST_TO_MINION_OUTPUT:
        --   2/512,8192/0 → MinionAttackSpeed   (via ModFlag.Attack bucket)
        --   3/8192/0     → MinionCastSpeed     (via ModFlag.Cast bucket)
        -- MEDIUM Damage sub-bucketing (per-element × skill-tag, or skill-tag-only)
        ["0/2,512,8192/0"] = "Sub-bucketed Lightning Melee minion damage — LEB minion tab does not split sub-element × skill-tag Σ.",
        ["0/4,512,8192/0"] = "Sub-bucketed Cold Melee minion damage — see 0/2,512,8192/0.",
        ["0/8,512,8192/0"] = "Sub-bucketed Fire Melee minion damage — see 0/2,512,8192/0.",
        ["0/256,8192/0"]   = "Sub-skill minion damage (DoT) — LEB does not split by skill-tag.",
        ["0/512,8192/0"]   = "Sub-skill minion damage (Melee) — LEB does not split by skill-tag.",
        ["0/1024,8192/0"]  = "Sub-skill minion damage (Bow) — LEB does not split by skill-tag.",
        ["0/2048,8192/0"]  = "Sub-skill minion damage (Throwing) — LEB does not split by skill-tag.",
        ["0/4096,8192/0"]  = "Sub-skill minion damage (Spell) — LEB does not split by skill-tag.",
        -- MEDIUM other
        ["1/512,8192/0"]   = "Minion Melee Ailment Chance not surfaced in minion tab.",
        ["1/8192/0"]       = "Minion Ailment Chance not surfaced in minion tab.",
        ["2/1024,8192/0"]  = "Minion Bow Attack Speed not surfaced; subsumed by tree.",
        ["2/2048,8192/0"]  = "Minion Throwing Attack Speed not surfaced; subsumed by tree.",
        ["4/2,8192/0"]     = "Minion Lightning Crit Chance not surfaced.",
        ["4/256,8192/0"]   = "Minion DoT Crit Chance not surfaced.",
        ["4/512,8192/0"]   = "Minion Melee Crit Chance not surfaced.",
        ["4/8192/0"]       = "Minion Crit Chance not surfaced in LEB minion tab.",
        ["5/8192/0"]       = "Minion Crit Multiplier not surfaced in LEB minion tab.",
        ["30/8192/0"]      = "Minion All Resistances — subsumed by per-type MinionXxxResist outputs.",
        ["42/8192/0"]      = "Minion Ailment Duration not surfaced in minion tab.",
        ["43/8192/0"]      = "Minion Ailment Effect not surfaced in minion tab.",
        ["45/512,8192/0"]  = "Minion Melee Stun Chance not surfaced in minion tab.",
        ["51/1,8192/0"]    = "Minion Physical Damage Leeched as Health not surfaced.",
        ["51/8192/0"]      = "Minion Damage Leeched as Health (generic) not surfaced.",
        ["52/8192/0"]      = "Minion Elemental Resistance — subsumed by per-element MinionXxxResist outputs.",
        ["67/8192/0"]      = "Minion Freeze Rate Multiplier not surfaced in minion tab.",
        ["88/8192/0"]      = "Minion Level of Skills — rendered via skill panel, not minion tab summary.",
        ["116/8192/0"]     = "Minion Increased Area not surfaced in minion tab.",
        ["128/8192/0"]     = "Minion Immunity not surfaced in minion tab.",
    }

    it("HIGH/MEDIUM whitelist entries must map to a Minion* output or be intentionally waived", function()
        local wl = loadWhitelist()
        local f = assert(io.open("Modules/CalcDefence.lua", "r"))
        local body = f:read("*a")
        f:close()

        local violations = {}
        for i, e in ipairs(wl.entries) do
            if e.confidence == "high" or e.confidence == "medium" then
                local key = whitelistKey(e.property, e.tagBits, e.specialTag)
                local mappedOutput = WHITELIST_TO_MINION_OUTPUT[key]
                local omissionReason = INTENTIONAL_OMISSIONS[key]

                if mappedOutput then
                    -- Forward drift: mapping says there should be a
                    -- `output.<name> = sumMinion(...)` line; verify it.
                    local needle = "output." .. mappedOutput .. " = sumMinion"
                    if not body:find(needle, 1, true) then
                        violations[#violations + 1] = string.format(
                            "entry #%d %s (sp=%d %s, conf=%s) maps to output.%s, but " ..
                            "`%s` not found in CalcDefence.lua — the Minion* output was renamed or removed.",
                            i, key, e.property, tostring(e.propertyName), e.confidence,
                            mappedOutput, needle)
                    end
                elseif omissionReason then
                    -- Documented omission, OK. (Sanity: reason must be non-empty.)
                    if type(omissionReason) ~= "string" or #omissionReason < 8 then
                        violations[#violations + 1] = string.format(
                            "entry #%d %s has INTENTIONAL_OMISSIONS reason that is empty or too short — " ..
                            "the reason field is required so future readers understand why no Minion* " ..
                            "output was wired.", i, key)
                    end
                else
                    violations[#violations + 1] = string.format(
                        "entry #%d %s (sp=%d %s, tags=[%s], st=%d, conf=%s) has neither a " ..
                        "WHITELIST_TO_MINION_OUTPUT mapping nor an INTENTIONAL_OMISSIONS reason. " ..
                        "Either add a `Minion%s = sumMinion(...)` line to CalcDefence.lua AND a " ..
                        "mapping entry, OR add an INTENTIONAL_OMISSIONS reason explaining why this " ..
                        "stat is not surfaced.",
                        i, key, e.property, tostring(e.propertyName),
                        table.concat(e.tagBits, ","), e.specialTag, e.confidence,
                        tostring(e.propertyName or "<NAME>"):gsub(" ", ""))
                end
            end
        end
        assert.are.equals(0, #violations,
            "Forward coverage drift detected (whitelist HIGH/MEDIUM ↛ CalcDefence):\n  " ..
            table.concat(violations, "\n  "))
    end)

    it("reverse drift: every mapped output key must still appear as HIGH/MEDIUM in the whitelist", function()
        local wl = loadWhitelist()
        local present = {}
        for _, e in ipairs(wl.entries) do
            present[whitelistKey(e.property, e.tagBits, e.specialTag)] = e.confidence
        end

        local orphans = {}
        for key, outputName in pairs(WHITELIST_TO_MINION_OUTPUT) do
            local conf = present[key]
            if not conf then
                orphans[#orphans + 1] = string.format(
                    "mapping %s -> output.%s no longer appears in whitelist_final.json " ..
                    "(re-derive whitelist OR remove the LEB Minion* output).",
                    key, outputName)
            elseif conf == "low" then
                orphans[#orphans + 1] = string.format(
                    "mapping %s -> output.%s is now LOW (runtime-only) — review whether " ..
                    "to gate it behind LEB_FEATURE_MINION_RUNTIME_ADVISORY.",
                    key, outputName)
            end
        end
        assert.are.equals(0, #orphans,
            "Reverse coverage drift detected (mapping has keys not on whitelist):\n  " ..
            table.concat(orphans, "\n  "))
    end)

    it("intentional omissions also reference valid whitelist keys", function()
        local wl = loadWhitelist()
        local present = {}
        for _, e in ipairs(wl.entries) do
            present[whitelistKey(e.property, e.tagBits, e.specialTag)] = e.confidence
        end

        local dangling = {}
        for key, _ in pairs(INTENTIONAL_OMISSIONS) do
            local conf = present[key]
            if not conf then
                dangling[#dangling + 1] = string.format(
                    "INTENTIONAL_OMISSIONS key %s is not a whitelist entry — either the " ..
                    "whitelist changed (re-derive) or remove the stale omission.", key)
            elseif conf == "low" then
                dangling[#dangling + 1] = string.format(
                    "INTENTIONAL_OMISSIONS key %s is LOW confidence — LOW entries are " ..
                    "outside the drift check; remove this stale omission.", key)
            end
        end
        assert.are.equals(0, #dangling,
            "Stale INTENTIONAL_OMISSIONS entries:\n  " .. table.concat(dangling, "\n  "))
    end)

    it("mapped Minion* outputs and waivers together cover every HIGH/MEDIUM whitelist entry exactly once", function()
        -- Belt-and-braces: a key in BOTH the mapping AND the omissions
        -- table indicates a maintainer pasted it into the wrong list
        -- and would otherwise be silently allowed.
        local doubled = {}
        for key, _ in pairs(WHITELIST_TO_MINION_OUTPUT) do
            if INTENTIONAL_OMISSIONS[key] then
                doubled[#doubled + 1] = key
            end
        end
        assert.are.equals(0, #doubled,
            "Keys appear in both WHITELIST_TO_MINION_OUTPUT and INTENTIONAL_OMISSIONS " ..
            "(pick one):\n  " .. table.concat(doubled, "\n  "))
    end)

    -- @leb-regression-guard:minion-melee-attack-speed-label
    -- The calcs-tab minion section must label the attack-speed row "Increased
    -- Minion Melee Attack Speed" (not bare "Attack Speed") and carry a separate
    -- "Increased Minion Cast Speed" row, matching the in-game minion character
    -- sheet. Game files (dump.cs AT enum: Melee/Throwing/Bow; SP AttackSpeed=2)
    -- have no unqualified attack-speed stat; minions surface the Melee tag plus
    -- their own Cast Speed. Both rows must be wired to the existing
    -- MinionAttackSpeed / MinionCastSpeed outputs. See REGRESSION_GUARDS.md.
    it("calcs-tab minion section labels attack/cast speed per the in-game sheet", function()
        local f = assert(io.open("Modules/CalcSections.lua", "r"),
            "CalcSections.lua must be present")
        local body = f:read("*a")
        f:close()

        assert.is_truthy(
            body:find('label = "Increased Minion Melee Attack Speed", haveOutput = "MinionAttackSpeed"', 1, true),
            'minion section must show "Increased Minion Melee Attack Speed" wired to MinionAttackSpeed ' ..
            '(game files have no unqualified attack speed; minions use the Melee tag)')
        assert.is_truthy(
            body:find('label = "Increased Minion Cast Speed", haveOutput = "MinionCastSpeed"', 1, true),
            'minion section must show a separate "Increased Minion Cast Speed" row wired to MinionCastSpeed')
        assert.is_falsy(
            body:find('label = "Increased Minion Attack Speed", haveOutput = "MinionAttackSpeed"', 1, true),
            'attack-speed row must be labeled "Melee Attack Speed", not bare "Attack Speed"')
    end)
end)
