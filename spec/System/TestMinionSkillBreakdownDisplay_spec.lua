-- @leb-regression-guard:minion-skill-breakdown-display
-- See REGRESSION_GUARDS.md "minion-skill-breakdown-display".
-- Validation provenance is retained in maintainer notes.

-- busted runs with cwd = src (directory="src"), so source files resolve as
-- "Modules/..." and spec-dir files as "../spec/...". Try the common prefixes so
-- the spec works from either the worktree root or the src cwd.
local function readFile(relPath)
    local fh = io.open(relPath, "r")
        or io.open("src/" .. relPath, "r")
        or io.open("../src/" .. relPath, "r")
        or io.open("../spec/" .. relPath, "r")
        or io.open("spec/" .. relPath, "r")
        or io.open("../" .. relPath, "r")
    assert(fh, "cannot open " .. relPath)
    local c = fh:read("*a"); fh:close()
    return c
end

describe("MinionSkillBreakdownDisplay #minionbreakdown Calcs.lua contracts", function()
    local cc = readFile("Modules/Calcs.lua")

    it("calcFullDPS declares the minionBreakdown table and the perf gate", function()
        assert.is_truthy(cc:find("@leb%-regression%-guard:minion%-skill%-breakdown%-display"),
            "Calcs.lua must carry the guard marker")
        assert.is_truthy(cc:find("minionBreakdown", 1, true),
            "fullDPS must declare a minionBreakdown table")
        assert.is_truthy(cc:find("wantMinionBreakdown", 1, true),
            "the breakdown compute must be gated by wantMinionBreakdown (MAIN pass only)")
        assert.is_truthy(cc:find("computeMinionBreakdown", 1, true),
            "buildOutput must pass computeMinionBreakdown only for the MAIN display pass")
    end)

    it("the breakdown compute restores the minion main skill and never feeds the total", function()
        -- isolate the guarded do/if block
        local blockStart = cc:find("if wantMinionBreakdown then")
        assert.is_truthy(blockStart, "the wantMinionBreakdown block must exist")
        local block = cc:sub(blockStart, blockStart + 1200)
        assert.is_truthy(block:find("mEnv.mainSkill = savedMain", 1, true),
            "must restore the minion's main skill after probing sub-skills")
        assert.is_truthy(block:find("calcs.offence", 1, true),
            "must compute each sub-skill via calcs.offence")
        assert.is_nil(block:find("combinedDPS", 1, true),
            "the breakdown block must NOT add to combinedDPS (display-only, no-regen)")
    end)
end)

describe("MinionSkillBreakdownDisplay #minionbreakdown snapshot neutrality", function()
    it("the snapshot serializer skips MinionSkillBreakdown", function()
        local gb = readFile("GenerateBuilds.lua")
        assert.is_truthy(gb:find('key == "MinionSkillBreakdown"', 1, true),
            "buildTable must skip the MinionSkillBreakdown output key so corpus snapshots stay byte-identical")
        assert.is_truthy(gb:find("@leb%-regression%-guard:minion%-skill%-breakdown%-display"),
            "GenerateBuilds.lua must carry the guard marker")
    end)
end)

describe("MinionSkillBreakdownDisplay #minionbreakdown render", function()
    it("Build.lua renders the breakdown rows from output.MinionSkillBreakdown", function()
        local bl = readFile("Modules/Build.lua")
        assert.is_truthy(bl:find("MinionSkillBreakdown", 1, true),
            "Build.lua must read output.MinionSkillBreakdown to render the indented breakdown")
        assert.is_truthy(bl:find("@leb%-regression%-guard:minion%-skill%-breakdown%-display"),
            "Build.lua must carry the guard marker")
    end)
end)
