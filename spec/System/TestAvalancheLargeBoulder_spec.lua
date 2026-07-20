-- @leb-regression-guard:avalanche-large-boulder-double-damage
-- Locks the parser + ModCache contract for the Avalanche specialization node
-- av75ch-15 "Intensity" ("5% Large Boulder Chance", maxPoints 4).
--
-- Ground truth (LEB tree data == in-game node, TreeData/1_4/tree_0.json):
--   name "Intensity", maxPoints 4, stats ["5% Large Boulder Chance"],
--   description "Small boulders have a chance to be replaced by large boulders."
--
-- Game mechanic (datamine): a "large boulder" deals
-- AvalancheSnowballMutator.BIG_BOULDER_MORE_DAMAGE = 1 (datamined game source) = +1.0 MORE
-- = exactly x2.0 = DOUBLE damage. The bigBoulderChance field (0x114) is driven by
-- this node (property 5076, 5%/pt). The SuXes lv92 Shaman per-hit ladder measured a
-- clean x2.0000 large cluster at an observed ~18% (= the 20% node within finite-sample
-- error). A p-chance to deal double damage is exactly LEB's existing DoubleDamageChance
-- mechanic, whose expected-value MORE is CalcOffence ScaledDamageEffect *= (1 + p) =
-- (1 + p*(2-1)); at 20% that is x1.20.
--
-- The bug (before this fix): "5% Large Boulder Chance" was a ModCache no-op
-- ({{}," Large Boulder Chance "}) -- the entire large-boulder contribution was dropped.
--
-- The fix: an anchored specialModList entry
--   ["^([%d%.]+)%% large boulder chance$"] = function(num)
--       return { mod("DoubleDamageChance", "BASE", num) } end
-- The per-point value (5) is multiplied by allocated points by PassiveTree (x4 -> 20).
-- Anchored ^...$ so the sibling stats "50% Large Boulder Chance To Leave Frozen Ground"
-- (a chill-ground effect, NOT damage) and "50% Upheaval Chance From Large Boulder" do
-- NOT match. Only the Avalanche tree carries "Large Boulder Chance" (no affix/unique),
-- and skill-tree node mods are SkillId-scoped by PassiveTree.lua, so the mod reaches
-- Avalanche only.
--
-- See REGRESSION_GUARDS.md > "avalanche-large-boulder-double-damage".

local function findTag(m, ttype)
    for _, tag in ipairs(m) do
        if tag.type == ttype then return tag end
    end
end

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("AvalancheLargeBoulder", function()
    before_each(function()
        newBuild()
    end)

    ---------------------------------------------------------------------------
    -- Parse-level: the per-point stat becomes a BASE DoubleDamageChance, no residue
    ---------------------------------------------------------------------------
    it("parses '5% Large Boulder Chance' to a BASE DoubleDamageChance 5 mod (nil extra)", function()
        local mods, extra = modLib.parseMod("5% Large Boulder Chance")
        assert.is_nil(extra, "the whole stat must be consumed, leaving no residue")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("DoubleDamageChance", m.name,
            "large boulder = BIG_BOULDER_MORE_DAMAGE 1 = x2.0 = double damage")
        assert.are.equals("BASE", m.type,
            "DoubleDamageChance is read via Sum('BASE', ...) in CalcOffence")
        assert.are.equals(5, m.value, "per-point value; PassiveTree applies x maxPoints (4 -> 20)")
        assert.are.equals(ModFlag.Hit, m.flags,
            "ModFlag.Hit: the large boulder doubles the boulder HIT only, never the DoT ailments it inflicts")
        assert.is_nil(findTag(m, "SkillId"),
            "parse stays skill-agnostic; PassiveTree adds the av75ch SkillId scope at alloc time")
    end)

    ---------------------------------------------------------------------------
    -- The anchored pattern: sibling "Large Boulder" stats must NOT be hijacked
    ---------------------------------------------------------------------------
    it("does NOT turn '50% Large Boulder Chance To Leave Frozen Ground' into DoubleDamageChance", function()
        local mods, extra = modLib.parseMod("50% Large Boulder Chance To Leave Frozen Ground")
        for _, m in ipairs(mods or {}) do
            assert.are_not.equals("DoubleDamageChance", m.name,
                "the frozen-ground sibling is a chill effect; the $-anchor must exclude it")
        end
        -- it remains an unmodelled no-op (empty mod list), exactly as before the fix
        assert.are.equals(0, #(mods or {}),
            "frozen-ground large-boulder stat stays a no-op (unmodelled)")
    end)

    it("does NOT turn '50% Upheaval Chance From Large Boulder' into DoubleDamageChance", function()
        local mods = modLib.parseMod("50% Upheaval Chance From Large Boulder")
        for _, m in ipairs(mods or {}) do
            assert.are_not.equals("DoubleDamageChance", m.name,
                "the upheaval-from-boulder stat must not collide with the large-boulder-chance rule")
        end
    end)

    ---------------------------------------------------------------------------
    -- ModDB resolution: at 4/4 (BASE 20) the EV multiplier is (1 + 20/100) = x1.20,
    -- and it is HIT-ONLY (a DoT/ailment context gets nothing).
    ---------------------------------------------------------------------------
    it("DoubleDamageChance is hit-only; 4 points (20) -> x1.20 EV on hits, 0 on ailments", function()
        local db = new("ModDB")
        db.actor = { modDB = db }
        -- simulate PassiveTree scaling the per-point parse by the 4 allocated points
        for _ = 1, 4 do
            db:AddList(modLib.parseMod("5% Large Boulder Chance"))
        end
        local hitChance = db:Sum("BASE", { flags = ModFlag.Hit }, "DoubleDamageChance")
        assert.are.equals(20, hitChance, "4 x 5% = 20% Large Boulder (= double damage) chance on the hit")
        -- CalcOffence computes ScaledDamageEffect *= (1 + DoubleDamageChance/100)
        assert.are.equals(1.20, 1 + hitChance / 100,
            "20% double-damage chance is a x1.20 expected-value multiplier on the boulder hit")
        -- A DoT/ailment cfg (no Hit flag) must NOT pick it up: the boulder doubles the hit,
        -- not the Frostbite/Chill/Shock it inflicts (LE ailments don't scale with hit size).
        local dotChance = db:Sum("BASE", { flags = ModFlag.Dot }, "DoubleDamageChance")
        assert.are.equals(0, dotChance,
            "ailment/DoT context gets no double-damage: large boulder is a HIT mechanic only")
    end)

    ---------------------------------------------------------------------------
    -- ModCache: the baked row matches the new parse (DoubleDamageChance BASE 5,
    -- nil residue) so the runtime short-circuit returns the mod instead of dropping it.
    ---------------------------------------------------------------------------
    it("the ModCache row carries DoubleDamageChance BASE 5 and no leftover residue", function()
        local body = readSource("Data/ModCache.lua")
        assert.is_truthy(body:find('c["5%% Large Boulder Chance"]', 1, false),
            "the Intensity ModCache row must exist")
        assert.is_truthy(body:find('{flags=8388608,keywordFlags=0,name="DoubleDamageChance",type="BASE",value=5}},nil}', 1, true),
            "the cached mod must be DoubleDamageChance BASE 5, ModFlag.Hit (8388608), nil residue")
        assert.is_nil(body:find('c["5%% Large Boulder Chance"]={{}," Large Boulder Chance "}', 1, false),
            "the stale no-op row (empty mods + ' Large Boulder Chance ' residue) must be gone")
    end)

    ---------------------------------------------------------------------------
    -- Tree data pin: a future tree update that retitles/rescopes Intensity or
    -- changes its per-point value / maxPoints forces this guard to be revisited.
    ---------------------------------------------------------------------------
    it("game-file: av75ch-15 Intensity still carries the audited stat (1.4 tree)", function()
        local t0 = readSource("TreeData/1_4/tree_0.json")
        assert.is_not_nil(t0, "must read TreeData/1_4/tree_0.json")
        assert.is_truthy(t0:find('"av75ch%-15"', 1, false), "av75ch-15 must exist in tree_0.json")
        assert.is_truthy(t0:find('"Intensity"', 1, true), "the node name must be Intensity")
        assert.is_truthy(t0:find("5%% Large Boulder Chance", 1, false),
            "Intensity must carry the '5% Large Boulder Chance' stat")
        assert.is_truthy(t0:find('"maxPoints": 4', 1, true),
            "Intensity maxPoints must be 4 (4 x 5%% = 20%% large boulder)")
    end)

    ---------------------------------------------------------------------------
    -- Inline guard marker stays put.
    ---------------------------------------------------------------------------
    it("carries the inline regression-guard marker in ModParser.lua", function()
        local parserText = readSource("Modules/ModParser.lua")
        assert.is_truthy(parserText:find("@leb%-regression%-guard:avalanche%-large%-boulder%-double%-damage", 1, false),
            "inline guard ID must remain in ModParser.lua")
        assert.is_truthy(parserText:find('%["%^%(%[%%d%%.%]%+%)%%%% large boulder chance%$"%]', 1, false),
            "the specialModList anchored entry must remain")
    end)
end)
