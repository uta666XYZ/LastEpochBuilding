-- @leb-regression-guard:shadow-cascade-dagger-dance
-- See REGRESSION_GUARDS.md "shadow-cascade-dagger-dance".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("DaggerDance registry + base data (no fabrication)", function()
    it("Shadow Cascade grants ShadowCascadeDagger gated on dagg3-21", function()
        local grants = data.subSkillGrants.ShadowCascade
        assert.is_table(grants, "ShadowCascade must be in the grant registry")
        assert.are.equals(1, #grants)
        assert.are.equals("ShadowCascadeDagger", grants[1].skillId)
        assert.are.equals("dagg3-21", grants[1].requiresNode,
            "the dagger grant must be node-conditional on Dagger Dance (dagg3-21)")
    end)

    it("ShadowCascadeDagger carries the DaggerThrow base (24 x eff 1.2) as a weapon attack", function()
        local d = data.skills.ShadowCascadeDagger
        assert.is_table(d, "ShadowCascadeDagger must exist in data.skills")
        assert.are.equals("Dagger Throw", d.name,
            "name must be exactly 'Dagger Throw' (SkillName-scoped mods + activeGrantedName depend on it)")
        assert.are.equals(24, d.stats.melee_base_physical_damage)
        assert.are.equals(1.2, d.stats.damageEffectiveness)
        -- Validation provenance is retained in maintainer notes.
        assert.are.equals(1537, d.skillTypeTags)
        assert.is_true(d.baseFlags.melee)
        assert.is_true(d.baseFlags.projectile)
        assert.is_true(d.baseFlags.attack)
        assert.is_true(d.baseFlags.hit)
    end)
end)

describe("DaggerDance tree-stat parsing (were empty before)", function()
    it("'1 Daggers Thrown' parses to ProjectileCount BASE 1", function()
        local mods, extra = modLib.parseMod("1 Daggers Thrown")
        assert.is_truthy(extra == nil or extra == "",
            "must parse cleanly (was dropped with residue ' s Thrown ')")
        assert.are.equals(1, #mods)
        assert.are.equals("ProjectileCount", mods[1].name)
        assert.are.equals("BASE", mods[1].type)
        assert.are.equals(1, mods[1].value)
    end)

    it("rank-scaled '4 Daggers Thrown' parses to ProjectileCount BASE 4", function()
        local mods = modLib.parseMod("4 Daggers Thrown")
        assert.are.equals(1, #mods)
        assert.are.equals("ProjectileCount", mods[1].name)
        assert.are.equals(4, mods[1].value)
    end)

    it("'+3 Daggers Thrown' (Porcupine's Wrath) parses to ProjectileCount BASE 3", function()
        local mods = modLib.parseMod("+3 Daggers Thrown")
        assert.are.equals(1, #mods)
        assert.are.equals("ProjectileCount", mods[1].name)
        assert.are.equals(3, mods[1].value)
    end)

    it("' No Melee Attack' parses to a NoMeleeAttack flag", function()
        local mods, extra = modLib.parseMod(" No Melee Attack")
        assert.is_truthy(extra == nil or extra == "")
        assert.are.equals(1, #mods)
        assert.are.equals("NoMeleeAttack", mods[1].name)
        assert.are.equals("FLAG", mods[1].type)
        assert.is_true(mods[1].value)
    end)

    it("no stale ' s Thrown ' residue rows remain in ModCache", function()
        local body = assert(readFile("Data/ModCache.lua"))
        assert.is_nil(body:find('," s Thrown "}', 1, true),
            "stale ModCache rows with ' s Thrown ' residue would re-mask the dagger count")
    end)
end)

describe("DaggerDance calc wiring (source invariants)", function()
    it("CalcSetup gates the grant on env.allocNodes[requiresNode]", function()
        local text = assert(readFile("Modules/CalcSetup.lua"))
        assert.is_truthy(text:find("grant.requiresNode", 1, true),
            "CalcSetup grant loop must honor the optional requiresNode gate")
        assert.is_truthy(text:find("@leb%-regression%-guard:shadow%-cascade%-dagger%-dance"),
            "CalcSetup must carry the guard marker")
    end)

    it("CalcOffence applies SequentialProjectiles + Porcupine MORE + melee suppression", function()
        local text = assert(readFile("Modules/CalcOffence.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:shadow%-cascade%-dagger%-dance"),
            "CalcOffence must carry the guard marker")
        assert.is_truthy(text:find('SequentialProjectiles", "FLAG"', 1, true),
            "the dagger must set SequentialProjectiles so ProjectileCount multiplies DPS")
        assert.is_truthy(text:find("Porcupine's Wrath (No Melee Attack)", 1, true),
            "Shadow Cascade's melee hit must be suppressed when No Melee Attack")
    end)
end)
