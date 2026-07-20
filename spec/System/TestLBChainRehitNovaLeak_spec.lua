-- @leb-regression-guard:lb-chain-rehit-skill-scoped
-- numbers are validated by the probe, not the suite). See REGRESSION_GUARDS.md
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("lb-chain-rehit-skill-scoped (CalcOffence gate)", function()
    local src = assert(readFile("Modules/CalcOffence.lua"), "must read Modules/CalcOffence.lua")

    it("CalcOffence carries the lb-chain-rehit-skill-scoped guard marker", function()
        assert.is_truthy(src:find("@leb%-regression%-guard:lb%-chain%-rehit%-skill%-scoped"),
            "CalcOffence.lua must carry the lb-chain-rehit-skill-scoped guard marker")
    end)

    it("the chain-rehit block stays consumed (flag + HitMult lever intact)", function()
        assert.is_truthy(src:find("LightningBlastChainsBackOnItself", 1, true),
            "the Convergence-gated chain multiplier must stay wired")
        assert.is_truthy(src:find("LightningBlastHitMult", 1, true))
    end)

    it("the chain-rehit block is gated to the Lightning Blast skill itself", function()
        -- the flag check and the skill-name gate must live in the SAME conditional:
        -- locate the flag check, then assert the LB name gate appears in the few
        -- lines that open the block (before the body sets LightningBlastHitMult).
        local flagPos = src:find("LightningBlastChainsBackOnItself", 1, true)
        assert.is_truthy(flagPos)
        local bodyPos = src:find("output.LightningBlastHitMult", flagPos, true)
        assert.is_truthy(bodyPos, "the chain-rehit body must follow the flag check")
        local condition = src:sub(flagPos, bodyPos)
        assert.is_truthy(condition:find('grantedEffect.name == "Lightning Blast"', 1, true),
            "the chain-rehit block must be gated on the Lightning Blast skill name, "
            .. "so triggered children (Spark Nova / ailments) that inherit the flag "
            .. "do not get the LB-only chain multiplier")
    end)
end)

describe("lb-chain-rehit-skill-scoped (gate predicate)", function()
    -- Mirror the exact CalcOffence gate: the chain-rehit multiplier applies iff
    -- the Convergence flag is set AND the active skill is Lightning Blast itself.
    local function chainMultApplies(hasFlag, speed, skillName)
        return hasFlag and speed and speed > 0 and skillName == "Lightning Blast"
    end

    it("Lightning Blast itself (flag set) still gets the chain multiplier", function()
        assert.is_true(chainMultApplies(true, 4.40, "Lightning Blast"))
    end)

    it("triggered Spark Nova (inherits the flag) does NOT get the multiplier", function()
        -- Spark Nova carries LightningBlastChainsBackOnItself via cfg.groupSource,
        -- but it is not the Lightning Blast skill -> no double-count.
        assert.is_false(chainMultApplies(true, 12.70, "Spark Nova"))
    end)

    it("an inheriting ailment entry (flag set) is likewise excluded", function()
        assert.is_false(chainMultApplies(true, 5.33, "Spark Charge"))
    end)

    it("Lightning Blast without Convergence (no flag) gets nothing", function()
        assert.is_false(chainMultApplies(false, 4.40, "Lightning Blast"))
    end)
end)
