-- @leb-regression-guard:known-build-gaps-per-build-scoped
-- Locks the per-build-scoped artifact skip surface (KNOWN_BUILD_GAPS in
-- diff_letools.py + sigma_rank.py wiring). Without these:
--   * QJWMRv53 lv98 Bladedancer (armour-floor-at-zero anchor) dominates Σ
--     because LET's signed-Armor display drifts from LEB's floored 0 by
--     +260 → 100% rows for Armor / Glancing Blow Chance.
--   * AVa9YEkg lv95 Paladin (unbroken-charge-be anchor) inflates Σ from
--     three correlated Block rows (BE +28.6%, Mitigation +11.9%,
--     Chance +4.2%) all rooted in the same LET ModRange index swap.
--   * BZ37RPdY / QnaLnRKV lv100 Bladedancer (no-shield) inflate Σ from
--     LET's phantom 2% Block Chance with no shield equipped (LE truth = 0).
--   * o3Zl6qDJ lv78 Sorcerer inflates Σ from LET's Necrotic Resistance
--     display artifact (LET 138% vs LEB 60% — the 78-pt gap = charLevel
--     exactly; sweep_necrotic.py confirms this pattern is unique to that
--     one build out of 119).
-- All four are LEB-correct vs in-game; LET is the outlier. Suppressing
-- them stat-globally would hide legitimate diffs on other builds, hence
-- the per-build scoped form.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("../" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("KnownBuildGaps", function()
    local diffTools, sigmaRank

    setup(function()
        diffTools = readSource("spec/tools/diff_letools.py")
        sigmaRank = readSource("spec/tools/sigma_rank.py")
    end)

    it("diff_letools.py defines KNOWN_BUILD_GAPS dict", function()
        assert.is_truthy(string.find(diffTools, "KNOWN_BUILD_GAPS = {", 1, true),
            "KNOWN_BUILD_GAPS dict must be declared")
        assert.is_truthy(string.find(diffTools,
            "@leb%-regression%-guard: known%-build%-gaps%-per%-build%-scoped", 1, false),
            "KNOWN_BUILD_GAPS must carry the named guard marker")
    end)

    it("diff_letools.py defines is_known_gap(build, tab, name) helper", function()
        assert.is_truthy(string.find(diffTools,
            "def is_known_gap%(build, tab, name%):", 1, false),
            "is_known_gap helper must be declared")
        assert.is_truthy(string.find(diffTools, "KNOWN_BUILD_GAPS%[", 1, false),
            "is_known_gap must consult KNOWN_BUILD_GAPS")
        assert.is_truthy(string.find(diffTools, "KNOWN_SEMANTIC_GAPS%[", 1, false),
            "is_known_gap must also consult KNOWN_SEMANTIC_GAPS for back-compat")
    end)

    local anchorEntries = {
        { "QJWMRv53 lv98 Bladedancer", "General", "Armor",
          "armour%-floor%-at%-zero%-letools%-artifact anchor" },
        { "QJWMRv53 lv98 Bladedancer", "Defense", "Glancing Blow Chance",
          "Glancing Blow Chance collateral on the same anchor" },
        { "AVa9YEkg lv95 Paladin", "General", "Block Effectiveness",
          "unbroken%-charge%-block%-effectiveness%-per%-ms%-letools%-artifact" },
        { "AVa9YEkg lv95 Paladin", "General", "Block Mitigation",
          "downstream of unbroken%-charge BE" },
        { "AVa9YEkg lv95 Paladin", "General", "Block Chance",
          "AVa9YEkg Block Chance collateral" },
        { "BZ37RPdY lv100 Bladedancer", "General", "Block Chance",
          "no%-shield Bladedancer LET phantom 2%% block" },
        { "QnaLnRKV lv100 Bladedancer", "General", "Block Chance",
          "duplicate of BZ37RPdY save" },
        { "o3Zl6qDJ lv78 Sorcerer", "General", "Necrotic Resistance",
          "o3Zl6qDJ Necrotic LET display artifact" },
        { "owLm3nZ7 lv81 Runemaster", "General", "Intelligence",
          "Mental Catalysis Int LET overcount (2x anchor)" },
        { "BgRrpjdv lv50 Runemaster", "General", "Intelligence",
          "Mental Catalysis Int LET overcount" },
        { "Q0VbpL4J lv100 Runemaster", "General", "Intelligence",
          "Mental Catalysis Int LET overcount" },
        { "QkY5Lr96 lv95 Runemaster", "General", "Intelligence",
          "Mental Catalysis Int LET overcount" },
        { "o3Zl6qDJ lv78 Sorcerer", "General", "Intelligence",
          "Mental Catalysis Int LET overcount (no-Catalyst sorcerer)" },
        { "AKg973wG lv84 Sorcerer", "General", "Intelligence",
          "Mental Catalysis Int LET overcount" },
        { "QDxZjPX8 lv95 Sorcerer", "General", "Intelligence",
          "Mental Catalysis Int LET overcount" },
        { "oYEOpZmJ lv87 Spellblade", "General", "Mana",
          "Atropos Mana prefix LET overcount (179 > affix 718_6 max 120)" },
        { "oYEOpZmJ lv87 Spellblade", "General", "Mana Regen",
          "Mana Regen partner stat on the same 718_6 dual-mod prefix" },
        { "Qb6WlbxD lv100 Druid", "General", "Physical Resistance",
          "LET drops PhysRes from per-Complete-Set All Resistances expansion" },
    }
    for _, entry in ipairs(anchorEntries) do
        local build, tab, name, why = entry[1], entry[2], entry[3], entry[4]
        it("KNOWN_BUILD_GAPS includes " .. build .. " / " .. tab .. " / " .. name, function()
            local pattern = "%('" .. build .. "', '" .. tab .. "', '" .. name .. "'%):"
            assert.is_truthy(string.find(diffTools, pattern, 1, false),
                "Missing per-build skip for " .. why)
        end)
    end

    it("sigma_rank.py imports KNOWN_BUILD_GAPS + is_known_gap", function()
        assert.is_truthy(string.find(sigmaRank,
            "from diff_letools import .*KNOWN_BUILD_GAPS", 1, false),
            "sigma_rank.py must import KNOWN_BUILD_GAPS")
    end)

    it("sigma_rank.py short-circuits KNOWN_BUILD_GAPS in sigma_for_build", function()
        assert.is_truthy(string.find(sigmaRank,
            "if %(build_basename, tab, name%) in KNOWN_BUILD_GAPS:", 1, false),
            "sigma_for_build must skip per-build gaps")
        assert.is_truthy(string.find(sigmaRank,
            "@leb%-regression%-guard: sigma%-rank%-excludes%-known%-build%-gaps", 1, false),
            "sigma_rank.py must carry the named guard marker")
    end)

    it("sigma_for_build takes build_basename as first arg", function()
        assert.is_truthy(string.find(sigmaRank,
            "def sigma_for_build%(build_basename, lua_path, json_path%):", 1, false),
            "Signature must include build_basename so per-build skip can apply")
        assert.is_truthy(string.find(sigmaRank,
            "sigma_for_build%(base, lua, js%)", 1, false),
            "Caller must pass the build basename")
    end)
end)
