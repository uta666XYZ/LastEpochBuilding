-- @leb-regression-guard:pyramidal-altar-cdr-letools-artifact
-- Locks the Pyramidal Altar conditional CDR evaluation against silent
-- regressions where the grid-layout check gets reverted (e.g. someone
-- "simplifies" the cluster after reading aggregate diff and seeing all
-- 13 Pyramidal Altar builds at LEB-LET = +10).
--
-- Classification: letools-artifact. LETools planner does not model this
-- conditional implicit at all (Qb6WgDEp letools.json reports
-- "Increased Cooldown Recovery Speed: 0%" despite the build's compliant
-- grid layout). LE in-game DOES apply the bonus; LEB matches LE.
-- Removing the evaluation would close the +10 cosmetic diff vs LET but
-- silently strip a real 10% CDR from every Pyramidal Altar build.
--
-- The 13 anchor builds (LEB - LETools = +10 each):
--   BgRrekzd, BxvJKdPR, QDxZjPX8, QWXjk5R9, QWXjqWJ2, Qb6WgDEp,
--   Qb6WlbxD, QeY7962P, Qqwv6zbR, oXz3VaZg, om6xa9dY, oy4Jk2Y9, ozwXnlqx

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

local function readRepoRel(relPath)
    -- Read a path relative to the repo root (not src/). When busted is
    -- invoked from src/ the cwd shifts; try both src-rooted and one-up.
    local f = io.open(relPath, "r") or io.open("../" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("PyramidalAltarCDR", function()
    local calcSetupText, modParserText, basesText, diffTools, sigmaRank

    setup(function()
        calcSetupText = readSource("Modules/CalcSetup.lua")
        modParserText = readSource("Modules/ModParser.lua")
        basesText = readSource("Data/Bases/bases_1_4.json")
        diffTools = readRepoRel("spec/tools/diff_letools.py")
        sigmaRank = readRepoRel("spec/tools/sigma_rank.py")
    end)

    it("CalcSetup carries the @leb-regression-guard:pyramidal-altar-cdr-letools-artifact marker", function()
        assert.is_truthy(string.find(calcSetupText,
            "@leb-regression-guard:pyramidal-altar-cdr-letools-artifact", 1, true),
            "CalcSetup grid evaluation must carry the named guard marker")
    end)

    it("CalcSetup sets modDB.conditions.NoLargerIdolsAboveSmaller when no violation", function()
        assert.is_truthy(string.find(calcSetupText,
            'modDB%.conditions%["NoLargerIdolsAboveSmaller"%]%s*=%s*true', 1, false),
            "Grid evaluator must set the NoLargerIdolsAboveSmaller condition flag")
    end)

    it("CalcSetup still walks per column with violation detection", function()
        -- Locks the algorithm shape so a refactor doesn't collapse the
        -- per-column non-decreasing-size check into something that always
        -- passes (which would over-apply) or always fails (which would
        -- never apply).
        assert.is_truthy(string.find(calcSetupText, "for col = 1, 5 do", 1, true),
            "Column-walk loop must remain present")
        assert.is_truthy(string.find(calcSetupText, "owner%.size < prevSize", 1, false),
            "Non-decreasing-size violation check must remain present")
        assert.is_truthy(string.find(calcSetupText, "violation = true", 1, true),
            "Violation flag must remain present")
    end)

    it("ModParser maps the altar's conditional clause to Condition:NoLargerIdolsAboveSmaller", function()
        assert.is_truthy(string.find(modParserText,
            'if there are no larger idols above smaller ones in the grid', 1, true),
            "Parser must hook the altar's conditional clause")
        assert.is_truthy(string.find(modParserText, 'NoLargerIdolsAboveSmaller', 1, true),
            "Parser must wire the clause to the NoLargerIdolsAboveSmaller condition")
    end)

    it("Pyramidal Altar implicit text matches the parser hook verbatim", function()
        -- If LE renames or re-words the altar implicit, this assertion fires
        -- so we know to update both the bases JSON and the modTagList key.
        assert.is_truthy(string.find(basesText,
            '"10%% Increased Cooldown Recovery Speed if there are no larger idols above smaller ones in the grid"', 1, false),
            "Pyramidal Altar implicit text must remain stable for the parser hook to match")
    end)

    it("diff_letools.py KNOWN_SEMANTIC_GAPS includes CDR with pyramidal-altar guard marker", function()
        -- Tooling-side enforcement: the artifact row must be footnoted in
        -- diff_letools so a reader sees the LET-side limitation, and the
        -- entry must carry the named guard marker so a grep for the guard
        -- id finds all sites (CalcSetup, REGRESSION_GUARDS, diff_letools).
        assert.is_truthy(string.find(diffTools,
            "@leb-regression-guard: pyramidal-altar-cdr-letools-artifact", 1, true),
            "diff_letools.py must carry the named guard marker on the CDR entry")
        assert.is_truthy(string.find(diffTools,
            "%('Other','Increased Cooldown Recovery Speed'%):", 1, false),
            "diff_letools.py KNOWN_SEMANTIC_GAPS must include the CDR row key")
    end)

    it("sigma_rank.py imports KNOWN_SEMANTIC_GAPS and skips them in Σ", function()
        -- @leb-regression-guard: sigma-rank-excludes-known-semantic-gaps
        -- Without this skip, the 4 Pyramidal Altar builds with LET CDR=0
        -- and LEB CDR=10 hit |Δ%|=inf -> CLIP_INF=10000 and dominate G1
        -- despite being LEB-correct. The skip keeps real LEB regressions
        -- (small-but-systemic drifts) at the top of the ranking.
        assert.is_truthy(string.find(sigmaRank,
            "from diff_letools import .*KNOWN_SEMANTIC_GAPS", 1, false),
            "sigma_rank.py must import KNOWN_SEMANTIC_GAPS")
        assert.is_truthy(string.find(sigmaRank,
            "if %(tab, name%) in KNOWN_SEMANTIC_GAPS:", 1, false),
            "sigma_rank.py must short-circuit KNOWN_SEMANTIC_GAPS rows in sigma_for_build")
        assert.is_truthy(string.find(sigmaRank,
            "@leb-regression-guard: sigma-rank-excludes-known-semantic-gaps", 1, true),
            "sigma_rank.py must carry the named guard marker on the exclusion")
    end)
end)
