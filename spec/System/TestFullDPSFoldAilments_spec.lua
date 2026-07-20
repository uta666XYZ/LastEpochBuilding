-- @leb-regression-guard: main-skill-ailment-upper-panel
-- @leb-regression-guard: main-skill-ignite-upper-panel
-- @leb-regression-guard: fulldps-fold-ailments-into-parent
-- Locks the pure helpers behind LEB's PoB-parity DPS display:
--   1. calcs.aggregateMainSkillAilment -> generic per-ailment upper-panel aggregator.
--      When separate-skill ailment entries (trigger == main skill) exist they ARE the
--      canonical full contribution, so it uses ONLY their sum; output.<Ailment>DPS is
--      the parent's partial value already folded inside and would double-count. Falls
--      back to output.<Ailment>DPS only when no separate entry matches.
--   2. calcs.aggregateMainSkillIgnite  -> thin Ignite-named wrapper over (1), kept so the
--      original guard/spec name and the "Total DPS inc. Ignite" row keep working.
--   3. calcs.foldAilmentsIntoParents   -> Full DPS breakdown folds each damaging
--      ailment row (LEB imports ailments as separate active skills) back into the
--      parent skill's single line, leaving output.SkillDPS itself UNMUTATED so the
--      snapshot deep-compare is unaffected.
-- See REGRESSION_GUARDS.md "main-skill-ailment-upper-panel" /
-- "main-skill-ignite-upper-panel" / "fulldps-fold-ailments-into-parent".

describe("TestFullDPSFoldAilments", function()
    local calcs

    before_each(function()
        newBuild()
        calcs = build.calcsTab.calcs
    end)

    -- damaging-ailment set mirror (the real set comes from data.damagingAilment)
    local AIL = { Ignite = true, Bleed = true, Poison = true, Electrify = true }

    describe("aggregateMainSkillIgnite", function()
        it("returns 0 when main skill name is nil", function()
            assert.are.equals(0, calcs.aggregateMainSkillIgnite({ IgniteDPS = 999 }, {}, nil))
        end)

        it("falls back to output.IgniteDPS when NO separate entry matches", function()
            -- ailment carried on the parent's own output (not imported as a skill)
            local r = calcs.aggregateMainSkillIgnite({ IgniteDPS = 100 }, {}, "Judgement")
            assert.are.equals(100, r)
        end)

        it("uses ONLY matching separate Ignite entries, NOT output (no double-count)", function()
            local list = {
                { name = "Ignite", trigger = "Judgement", dps = 200, count = 2 },
                { name = "Ignite", trigger = "OtherSkill", dps = 500, count = 1 },
                { name = "Judgement", trigger = "", dps = 1000, count = 1 },
            }
            -- 200*2 (matching) only; output.IgniteDPS=100 is the parent's partial value
            -- already folded inside the entry (Warlock Soul Feast proved adding it double-
            -- counts). The OtherSkill ignite is excluded (wrong trigger).
            local r = calcs.aggregateMainSkillIgnite({ IgniteDPS = 100 }, list, "Judgement")
            assert.are.equals(400, r)
        end)

        it("treats missing count as 1", function()
            local list = { { name = "Ignite", trigger = "Judgement", dps = 333 } }
            local r = calcs.aggregateMainSkillIgnite({}, list, "Judgement")
            assert.are.equals(333, r)
        end)
    end)

    describe("aggregateMainSkillAilment (generic per-ailment)", function()
        it("returns 0 when main skill name or ailment name is nil", function()
            assert.are.equals(0, calcs.aggregateMainSkillAilment({ DamnedDPS = 9 }, {}, nil, "Damned"))
            assert.are.equals(0, calcs.aggregateMainSkillAilment({ DamnedDPS = 9 }, {}, "Soul Feast", nil))
        end)

        it("sums any named ailment's matching separate entries (Damned)", function()
            local list = {
                { name = "Damned", trigger = "Soul Feast", dps = 1099.96, count = 1 },
                { name = "Poison", trigger = "Soul Feast", dps = 42.39, count = 1 },
                { name = "Soul Feast", trigger = "", dps = 3813, count = 1 },
            }
            assert.are.equals(1099.96, calcs.aggregateMainSkillAilment({}, list, "Soul Feast", "Damned"))
            assert.are.equals(42.39, calcs.aggregateMainSkillAilment({}, list, "Soul Feast", "Poison"))
        end)

        it("ignores output.<Ailment>DPS when a separate entry matches (no double-count)", function()
            -- Warlock Soul Feast regression: output.DamnedDPS (467) is already inside the
            -- separate Damned skill entry (1100); using only the entry keeps the sum equal
            -- to FullDPS - TotalDPS.
            local list = { { name = "Damned", trigger = "Soul Feast", dps = 1100, count = 1 } }
            local r = calcs.aggregateMainSkillAilment({ DamnedDPS = 467 }, list, "Soul Feast", "Damned")
            assert.are.equals(1100, r)
        end)

        it("falls back to output.<Ailment>DPS when no separate entry matches", function()
            local r = calcs.aggregateMainSkillAilment({ BleedDPS = 250 }, {}, "Rip Blood", "Bleed")
            assert.are.equals(250, r)
        end)
    end)

    describe("foldAilmentsIntoParents", function()
        it("folds an ailment row into its parent, preserving the grand total", function()
            local list = {
                { name = "Judgement", trigger = "", dps = 1000, count = 1 },
                { name = "Ignite", trigger = "Judgement", dps = 200, count = 1 },
                { name = "Electrify", trigger = "Judgement", dps = 50, count = 1 },
            }
            local folded = calcs.foldAilmentsIntoParents(list, AIL)
            assert.are.equals(1, #folded)
            assert.are.equals("Judgement", folded[1].name)
            -- 1000 + 200 + 50 folded into the single parent line
            assert.are.equals(1250, folded[1].dps * folded[1].count)
        end)

        it("preserves parent.count when folding (dps adjusted per cycle)", function()
            local list = {
                { name = "Judgement", trigger = "", dps = 1000, count = 3 },
                { name = "Ignite", trigger = "Judgement", dps = 300, count = 1 },
            }
            local folded = calcs.foldAilmentsIntoParents(list, AIL)
            assert.are.equals(3, folded[1].count)
            -- grand total preserved: 1000*3 + 300*1 = 3300
            assert.are.equals(3300, folded[1].dps * folded[1].count)
        end)

        it("does NOT mutate the input list (snapshot safety)", function()
            local list = {
                { name = "Judgement", trigger = "", dps = 1000, count = 1 },
                { name = "Ignite", trigger = "Judgement", dps = 200, count = 1 },
            }
            calcs.foldAilmentsIntoParents(list, AIL)
            assert.are.equals(2, #list)
            assert.are.equals(1000, list[1].dps)
            assert.are.equals(200, list[2].dps)
        end)

        it("keeps an orphan ailment row when no parent matches its trigger", function()
            local list = {
                { name = "Ignite", trigger = "GhostSkill", dps = 77, count = 1 },
            }
            local folded = calcs.foldAilmentsIntoParents(list, AIL)
            assert.are.equals(1, #folded)
            assert.are.equals("Ignite", folded[1].name)
            assert.are.equals(77, folded[1].dps)
        end)

        it("does not fold a damaging-ailment-named skill that has no trigger", function()
            -- e.g. a directly-cast skill literally named like an ailment but
            -- with trigger=="" is a real parent, not a folded ailment.
            local list = {
                { name = "Ignite", trigger = "", dps = 400, count = 1 },
            }
            local folded = calcs.foldAilmentsIntoParents(list, AIL)
            assert.are.equals(1, #folded)
            assert.are.equals(400, folded[1].dps)
        end)
    end)
end)
