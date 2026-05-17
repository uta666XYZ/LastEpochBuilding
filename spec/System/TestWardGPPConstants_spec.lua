-- @leb-regression-guard: ward-decay-gpp-constants
-- Locks the GlobalPlayerProperties ward-decay constants verbatim into the
-- LEB ward formulas. Source anchors (verbatim from
-- LE_datamining/extracted/typetree_dumps/GlobalPlayerProperties.json):
--
--     minimumWardDecayWithoutRegen = 0.5   (already guarded by ward-decay-floor-zero-passive)
--     linearWardDecay              = 0.2
--     quadraticWardDecay           = 5E-05
--
-- Plus the retention divisor anchors from ProtectionClass.Update
-- (LE_datamining/extracted/ward_decompile.txt L77-78):
--
--     DAT_183d81bf0 = 0.5    (retention-divisor scalar)
--     DAT_183d81c08 = 1.0    (retention-divisor constant term)
--
-- Smooth ward decay (game):
--     wardLost/s = (Q*(W-T)^2 + B*(W-T)) / (1 + 0.5*R/100)
--                = (5E-05*(W-T)^2 + 0.2*(W-T)) / (1 + 0.5*R/100)
--
-- Stable ward (algebraic inversion solving wgain = wardLost/s for W):
--     W = T + (-B + sqrt(B^2 + 2Q*wgain*(1 + 0.5*R/100))) / Q
--       = T + (-0.2 + sqrt(0.04 + 0.0002*wgain*(1 + 0.5*R/100))) / 0.0001
--
-- A regression here silently rounds 5E-05 -> 0 (drops quadratic), or swaps
-- 0.2 for an older tunklab approximation, or simplifies the retention
-- divisor — none of which the single-point `ward-retention-negative-clamp`
-- behavioural spec catches. See REGRESSION_GUARDS.md "ward-decay-gpp-constants".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardDecayGPPConstants", function()
    local defenceText, performText

    setup(function()
        defenceText = readSource("Modules/CalcDefence.lua")
        performText = readSource("Modules/CalcPerform.lua")
    end)

    describe("inline guard markers", function()
        it("CalcDefence.lua carries 3 inline guard markers (passive / display / Sanguine)", function()
            local _, count = string.gsub(defenceText, "@leb%-regression%-guard:ward%-decay%-gpp%-constants", "")
            assert.are.equals(3, count,
                "expected 3 inline ward-decay-gpp-constants markers in CalcDefence.lua " ..
                "(passive stable-ward inversion + display decay + Sanguine Runestones recompute)")
        end)

        it("CalcPerform.lua carries 1 inline guard marker (post-offence ManaSpentGainedAsWard)", function()
            local _, count = string.gsub(performText, "@leb%-regression%-guard:ward%-decay%-gpp%-constants", "")
            assert.are.equals(1, count,
                "expected 1 inline ward-decay-gpp-constants marker in CalcPerform.lua")
        end)
    end)

    describe("stable-ward inversion constants", function()
        -- Inversion form: T + (-0.2 + sqrt(0.04 + 0.0002 * wgain * (1 + 0.5 * R/100))) / 0.0001
        -- Constants: -B=-0.2, B^2=0.04, 2Q=0.0002 (numerator coeff), Q=0.0001 (divisor)
        local STABLE_PATTERNS = {
            { pat = "%-0%.2 %+ math%.sqrt%(0%.04 %+ 0%.0002 %* ",
              desc = "leading `-0.2 + sqrt(0.04 + 0.0002 *` form" },
            { pat = "%* %(1 %+ 0%.5 %* wardRetention / 100%)%)%) / 0%.0001",
              desc = "retention divisor `* (1 + 0.5 * wardRetention / 100))) / 0.0001` tail" },
        }

        it("CalcDefence.lua passive stable-ward inversion uses the verified constants", function()
            for _, p in ipairs(STABLE_PATTERNS) do
                assert.is_truthy(string.find(defenceText, p.pat),
                    "CalcDefence.lua stable-ward inversion missing " .. p.desc)
            end
        end)

        it("CalcPerform.lua post-offence stable-ward inversion uses the verified constants", function()
            for _, p in ipairs(STABLE_PATTERNS) do
                assert.is_truthy(string.find(performText, p.pat),
                    "CalcPerform.lua stable-ward inversion missing " .. p.desc)
            end
        end)

        it("CalcDefence.lua stable-ward inversion appears at both passive + Sanguine sites", function()
            local _, count = string.gsub(defenceText,
                "%-0%.2 %+ math%.sqrt%(0%.04 %+ 0%.0002 %* ", "")
            assert.are.equals(2, count,
                "CalcDefence.lua must have the inversion at 2 sites (passive + Sanguine Runestones)")
        end)
    end)

    describe("ward-decay-per-second numerator constants (B=0.2, Q=5E-05)", function()
        it("CalcDefence.lua display-decay numerator = 0.2 * W + 0.00005 * W^2", function()
            assert.is_truthy(string.find(defenceText,
                "local decayNumerator = 0%.2 %* effectiveWard %+ 0%.00005 %* effectiveWard %^ 2", 1, false),
                "display-decay numerator must be `0.2 * effectiveWard + 0.00005 * effectiveWard ^ 2`")
        end)

        it("CalcDefence.lua decay numerator appears at both passive + Sanguine sites", function()
            local _, count = string.gsub(defenceText,
                "0%.2 %* effectiveWard %+ 0%.00005 %* effectiveWard %^ 2", "")
            assert.are.equals(2, count,
                "decay numerator literal must appear at 2 sites in CalcDefence.lua")
        end)

        it("CalcPerform.lua post-offence decay numerator uses the verified constants", function()
            assert.is_truthy(string.find(performText,
                "local decayNumerator = 0%.2 %* effectiveWard %+ 0%.00005 %* effectiveWard %^ 2", 1, false),
                "CalcPerform.lua decay numerator must be `0.2 * effectiveWard + 0.00005 * effectiveWard ^ 2`")
        end)
    end)

    describe("retention divisor form (1 + 0.5 * R/100)", function()
        it("CalcDefence.lua display-decay divisor uses retentionClamped at -90 floor", function()
            assert.is_truthy(string.find(defenceText,
                "local retentionDivisor = 1 %+ 0%.5 %* retentionClamped / 100", 1, false),
                "display-decay retentionDivisor must be `1 + 0.5 * retentionClamped / 100`")
        end)

        it("Sanguine + CalcPerform divisor uses wardRetention at -90 floor", function()
            -- Sanguine path lives in CalcDefence.lua, post-offence path in CalcPerform.lua.
            -- Both name the local `wardRetention` (clamped at -90).
            local _, defCount = string.gsub(defenceText,
                "local retentionDivisor = 1 %+ 0%.5 %* wardRetention / 100", "")
            assert.are.equals(1, defCount,
                "Sanguine path retentionDivisor must be `1 + 0.5 * wardRetention / 100` (1 site in CalcDefence.lua)")
            local _, perfCount = string.gsub(performText,
                "local retentionDivisor = 1 %+ 0%.5 %* wardRetention / 100", "")
            assert.are.equals(1, perfCount,
                "post-offence retentionDivisor must be `1 + 0.5 * wardRetention / 100` (1 site in CalcPerform.lua)")
        end)
    end)
end)
