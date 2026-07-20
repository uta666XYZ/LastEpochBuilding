-- @leb-regression-guard:iron-blade-grant
-- See REGRESSION_GUARDS.md "iron-blade-grant".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("Iron Blade (DarkBlade) grant + base data (no fabrication)", function()
    it("Vengeance grants DarkBlade gated on the gs15de-7 Blade Assault node", function()
        local grants = data.subSkillGrants.Vengeance
        assert.is_table(grants, "Vengeance must be in the grant registry")
        local g
        for _, x in ipairs(grants) do if x.skillId == "DarkBlade" then g = x end end
        assert.is_table(g, "Vengeance must grant DarkBlade")
        -- The node gate is the load-bearing invariant: Iron Blade is NOT base kit;
        -- it requires the gs15de-7 "Blade Assault" node, so non-Blade-Assault
        -- Vengeance builds stay byte-identical.
        assert.are.equals("gs15de-7", g.requiresNode,
            "Iron Blade is node-gated on gs15de-7 (Blade Assault), not base kit")
    end)

    it("DarkBlade carries the datamined Physical melee-attack hit base", function()
        local d = data.skills.DarkBlade
        assert.is_table(d, "DarkBlade must exist in data.skills")
        assert.are.equals("Iron Blade", d.name)
        assert.are.equals(513, d.skillTypeTags, "tagsBitmap 513 = 1 Attack + 512 Melee")
        assert.are.equals(18, d.stats.melee_base_physical_damage, "datamined base 18 Physical")
        assert.are.equals(1, d.stats.damageEffectiveness, "addedDamageScaling 1.0")
        assert.are.equals(5, d.stats.critChance, "critChance 0.05 -> 5")
        assert.are.equals(100, d.stats["base_critical_strike_multiplier_+"], "critMultiplier 2.0 -> +100%")
        assert.is_true(d.baseFlags.hit, "Iron Blade is a hit (isHit=1)")
        assert.is_true(d.baseFlags.melee, "Iron Blade is a melee attack")
        assert.is_true(d.baseFlags.attack, "Iron Blade is an attack (tag bit 1)")
        assert.is_nil(d.baseFlags.dot, "Iron Blade is not a DoT")
        assert.is_true(d.excludeFromTriggerNameList,
            "granted sub-skill must not pollute trigger-name resolution")
    end)

    it("SubSkillGrants carries the guard marker", function()
        local text = assert(readFile("Data/SubSkillGrants.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:iron%-blade%-grant"),
            "SubSkillGrants must carry the iron-blade-grant guard marker")
    end)
end)

describe("Iron Blade tree-node ModCache rescope (no global leak)", function()
    -- With DarkBlade (name "Iron Blade") now in data.skills, the parser scopes the
    -- Iron Blade tree stats to SkillName="Iron Blade". The stale ModCache had baked
    -- these as GLOBAL mods with an unconsumed " Iron Blade " leftover: PassiveTree
    -- tags Vengeance-tree node mods {SkillId="Vengeance"}, so the un-scoped
    -- "+15% Iron Blade Damage" MORE LEAKED onto Vengeance's own hit. Removing the
    -- stale rows lets them re-parse live with the correct SkillName scope. This test
    -- locks the live-parse scoping so a future ModCache re-bake keeps it correct.
    it("'+15% Iron Blade Damage' scopes to SkillName Iron Blade (not a global MORE)", function()
        local parseFn = require("Modules.ModParser")
        local entry = parseFn("+15% Iron Blade Damage", false)
        local modList = entry and entry[1]
        assert.is_table(modList, "must parse to a mod list")
        -- The mod list is a list of mods; each mod table carries .name/.type/.value
        -- and its tags as the array part. Find the Damage MORE.
        local m
        for _, x in ipairs(modList) do
            if type(x) == "table" and x.name == "Damage" then m = x end
        end
        -- Some parse paths return the single mod directly (not wrapped); accept that too.
        if not m and modList.name == "Damage" then m = modList end
        assert.is_table(m, "must produce a Damage mod")
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type)
        assert.are.equals(15, m.value)
        local scoped = false
        for _, t in ipairs(m) do
            if type(t) == "table" and t.type == "SkillName" and t.skillName == "Iron Blade" then
                scoped = true
            end
        end
        assert.is_true(scoped,
            "the MORE must be SkillName-scoped to Iron Blade (else it leaks onto Vengeance)")
        assert.is_nil(entry[2], "extra/leftover must be consumed (nil) so tree sources do not drop it")
    end)

    it("the stale un-scoped Iron Blade rows are gone from ModCache", function()
        local text = assert(readFile("Data/ModCache.lua"))
        -- The exact stale baked forms (global Damage MORE / dropped chance) must not
        -- reappear; a re-bake will write the SkillName-scoped form instead.
        assert.is_nil(text:find('%["%+15%% Iron Blade Damage"%]=%{%{%[1%]=%{flags=0'),
            "stale GLOBAL '+15% Iron Blade Damage' MORE must not be baked")
    end)
end)
