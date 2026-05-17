-- @leb-regression-guard: ward-regen-passive-vs-event-split
-- Locks the display vs inversion-math split for Ward Regen post-offence fold-in.
-- Display `pOut.WardPerSecond` MUST equal `passiveWardPerSecond` (base +
-- CurrentManaGainedAsWardPerSecond + MissingHealthGainedAsWardPerSecond);
-- the event-driven `ManaSpentGainedAsWard` contribution lives in the local
-- `wps` used only by the Ward / WardDecay inversion + NetWardRegen — never
-- in the display stat.
--
-- Pre-fix evidence: 7 G1-G6 canonical builds carrying ManaSpentGainedAsWard
-- (QDxZjPX8 lv95 Sorcerer +354.77, BZ37dR2l lv100 Sorcerer +105.46,
-- BgRrekOY lv82 Sorcerer +42.16, Bakbr2Ne lv86 Sorcerer +34.04,
-- oR6qaLp4 lv80 Spellblade +29.12, Qdz2yXLk lv100 Warlock +22.64,
-- o3Zlpkxd lv98 Necromancer +10.01) accounted for ≈ 598 of Σ|Δ| on
-- WardPerSecond. Game ground truth: ProtectionClass.Update RVA 0x234B8C0
-- writes `wardRegen + wardRegenFromStats` from passive sources only;
-- ManaSpentGainedAsWard fires via GainWard() on spell cast.
--
-- See REGRESSION_GUARDS.md "ward-regen-passive-vs-event-split".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardRegenPassiveVsEventSplit", function()
    local performText

    setup(function()
        performText = readSource("Modules/CalcPerform.lua")
    end)

    describe("display assignment uses passive-only", function()
        it("assigns pOut.WardPerSecond = passiveWardPerSecond (not base + totalContribution)", function()
            assert.is_truthy(string.find(performText,
                "pOut%.WardPerSecond%s*=%s*passiveWardPerSecond", 1, false),
                "display WardPerSecond must equal passiveWardPerSecond")
        end)

        it("does NOT assign pOut.WardPerSecond from baseWardPerSecond + totalContribution", function()
            -- The pre-fix line was:
            --   pOut.WardPerSecond = baseWardPerSecond + totalContribution
            -- It must NOT come back. (The local `totalContribution` may still be
            -- computed for early-exit gating, but it must never reach pOut.WardPerSecond.)
            assert.is_nil(string.find(performText,
                "pOut%.WardPerSecond%s*=%s*baseWardPerSecond%s*%+%s*totalContribution", 1, false),
                "display WardPerSecond must NOT be baseWardPerSecond + totalContribution (pre-fix bug)")
        end)
    end)

    describe("event-driven mana-spent lives in local wps only", function()
        it("local wps adds manaSpentContribution to passiveWardPerSecond", function()
            -- The inversion math (Ward / WardDecay equilibrium, NetWardRegen)
            -- needs the full sustained WPS including event-driven mana-spent.
            assert.is_truthy(string.find(performText,
                "local%s+wps%s*=%s*passiveWardPerSecond%s*%+%s*manaSpentContribution",
                1, false),
                "local wps must equal passiveWardPerSecond + manaSpentContribution")
        end)
    end)

    describe("decay floor gate keys on passive only", function()
        it("0.5 decay floor is gated on passiveWardPerSecond <= 0, not wps", function()
            -- Game `ProtectionClass.Update` keys the 0.5/s floor on
            -- `wardRegen + wardRegenFromStats <= 0` (passive only). LEB matches.
            assert.is_truthy(string.find(performText,
                "if%s+passiveWardPerSecond%s*<=%s*0%s+then", 1, false),
                "the 0.5 decay floor must be gated on passiveWardPerSecond (not wps)")
        end)
    end)

    describe("inline guard marker", function()
        it("carries exactly one ward-regen-passive-vs-event-split marker", function()
            local _, count = string.gsub(performText,
                "@leb%-regression%-guard:ward%-regen%-passive%-vs%-event%-split", "")
            assert.are.equals(1, count,
                "CalcPerform must carry exactly 1 ward-regen-passive-vs-event-split marker (at the display assignment)")
        end)
    end)
end)
