-- @leb-regression-guard:ice-spiral-double-chance-ev
-- Locks the parser + ModCache contract for the Frost Claw specialization node
-- frc87w-21 "Chaos Whirl" (maxPoints 4).
--
-- Ground truth (LEB tree data == in-game node, TreeData/1_4/tree_1.json):
--   name "Chaos Whirl", maxPoints 4,
--   stats           ["25% Chance for Double Ice Spirals"]            (per-point scaling)
--   notScalingStats ["+100% Ice Spiral Damage when Doubled"]         (flat magnitude descriptor)
--   description "When you cast Ice Spirals there is a chance that the number of projectiles
--               will be doubled and they'll all deal double damage."
--
-- Game mechanic: a successful roll makes the cast's spirals deal DOUBLE damage. The doubled
-- magnitude is +100% = exactly x2.0; the game's own IceSpiralMutator.getTempStatsForTooltipDPS
-- folds extra = chance, i.e. the displayed EV multiplier is (1 + chance*(2-1)). A p-chance to
-- deal double damage is exactly LEB's existing DoubleDamageChance mechanic, whose expected-value
-- MORE is CalcOffence ScaledDamageEffect *= (1 + DoubleDamageChance/100).
--
-- The bug (before this fix): the node pair OVER-counted --
--   * "+100% Ice Spiral Damage when Doubled" was a ModCache Damage MORE 100 applied
--     UNCONDITIONALLY (always x2.0, never gated on the roll), and
--   * "25% Chance for Double Ice Spirals" was a ModCache no-op (dropped).
-- So any allocation (1..4 pts) inflated Ice Spiral hits to a flat x2.0.
--
-- The fix:
--   * ModParser specialModList anchored entry
--       ["^([%d%.]+)%% chance for double ice spirals$"] = function(num)
--           return { mod("DoubleDamageChance", "BASE", num, "", ModFlag.Hit) } end
--     The per-point value (25) is multiplied by allocated points by PassiveTree
--     (1pt -> 25 -> x1.25 ; 4pt -> 100 -> x2.0 = guaranteed double = the old number).
--   * ModCache row "+100% Ice Spiral Damage when Doubled" rewritten to an empty no-op so the
--     standalone +100% stops applying.
--   * ModCache row "25% Chance for Double Ice Spirals" REMOVED so the line cache-misses and is
--     parsed live by the specialModList entry above.
-- Anchored ^...$ and value-tolerant; "Chance for Double Ice Spirals" exists ONLY on the Frost
-- Claw tree (tree_1.json frc87w-21; no affix/unique/idol/set), and skill-tree node mods are
-- SkillId-scoped by PassiveTree.lua, so the mod reaches Frost Claw only.
--
-- ModFlag.Hit confines the x(1+p) to the hit: LE ailments are stack-based with fixed per-stack
-- damage and do NOT scale with the applying hit's size, so the doubled hit must NOT double the
-- Frostbite/Chill it inflicts (mirrors avalanche-large-boulder-double-damage).
--
-- See REGRESSION_GUARDS.md > "ice-spiral-double-chance-ev".

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

describe("IceSpiralDoubleChance", function()
    before_each(function()
        newBuild()
    end)

    ---------------------------------------------------------------------------
    -- (a) Parse-level: the per-point chance stat becomes a BASE DoubleDamageChance
    --     (NOT a Damage MORE), hit-flagged, skill-agnostic, no residue.
    ---------------------------------------------------------------------------
    it("parses '25% Chance for Double Ice Spirals' to a BASE DoubleDamageChance 25 mod (nil extra)", function()
        local mods, extra = modLib.parseMod("25% Chance for Double Ice Spirals")
        assert.is_nil(extra, "the whole stat must be consumed, leaving no residue")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("DoubleDamageChance", m.name,
            "double ice spirals = a p-chance to deal x2.0 = DoubleDamageChance, NOT an unconditional Damage MORE")
        assert.are.equals("BASE", m.type,
            "DoubleDamageChance is read via Sum('BASE', ...) in CalcOffence")
        assert.are.equals(25, m.value, "per-point value; PassiveTree applies x allocated points (4 -> 100)")
        assert.are.equals(ModFlag.Hit, m.flags,
            "ModFlag.Hit: the roll doubles the Ice Spiral HIT only, never the Frostbite/Chill it inflicts")
        assert.is_nil(findTag(m, "SkillId"),
            "parse stays skill-agnostic; PassiveTree adds the frc87w SkillId scope at alloc time")
    end)

    ---------------------------------------------------------------------------
    -- (a) The +100% descriptor must NOT survive as a standalone Damage MORE in ModCache.
    --     (Asserted against the source text so the result is independent of which modules
    --      the test harness happens to have loaded the cache from.)
    ---------------------------------------------------------------------------
    it("the '+100% Ice Spiral Damage when Doubled' ModCache row is an empty no-op (no Damage MORE 100)", function()
        local body = readSource("Data/ModCache.lua")
        -- plain=true: the row text contains [ ] + { } which are Lua pattern magic.
        assert.is_truthy(body:find('c["+100% Ice Spiral Damage when Doubled"]', 1, true),
            "the descriptor ModCache row must still exist (as a no-op)")
        assert.is_truthy(body:find('c["+100% Ice Spiral Damage when Doubled"]={{},', 1, true),
            "the row must be an EMPTY mod list (no-op) -- the unconditional +100% is gone")
        assert.is_nil(body:find('c["+100% Ice Spiral Damage when Doubled"]={{[1]={flags=0,keywordFlags=0,name="Damage",type="MORE",value=100}}', 1, true),
            "the stale UNCONDITIONAL Damage MORE 100 row must be gone")
    end)

    ---------------------------------------------------------------------------
    -- (a) The chance stat must NOT be a baked no-op anymore (so it cache-misses and is
    --     parsed live by specialModList into a DoubleDamageChance).
    ---------------------------------------------------------------------------
    it("the '25% Chance for Double Ice Spirals' ModCache no-op row is removed", function()
        local body = readSource("Data/ModCache.lua")
        -- plain=true: literal substring search (the row text contains pattern-magic chars).
        assert.is_nil(body:find('c["25% Chance for Double Ice Spirals"]={{}," for Double Ice Spirals "}', 1, true),
            "the stale no-op row (empty mods + ' for Double Ice Spirals ' residue) must be gone")
        assert.is_nil(body:find('c["25% Chance for Double Ice Spirals"]=', 1, true),
            "no baked row for the chance stat: the line must cache-miss to the live specialModList parse")
    end)

    ---------------------------------------------------------------------------
    -- (b)+(c) ModDB resolution: PassiveTree per-point scaling, EV multiplier, hit-only.
    --   1 pt (BASE 25)  -> x1.25 EV on hits ; 4 pt (BASE 100) -> x2.0 (= the old number).
    --   A DoT/ailment cfg (no Hit flag) gets nothing.
    ---------------------------------------------------------------------------
    it("1 point (25) -> x1.25 EV on the hit; ailment/DoT context gets 0", function()
        local db = new("ModDB")
        db.actor = { modDB = db }
        db:AddList(modLib.parseMod("25% Chance for Double Ice Spirals"))
        local hitChance = db:Sum("BASE", { flags = ModFlag.Hit }, "DoubleDamageChance")
        assert.are.equals(25, hitChance, "1 x 25% double-ice-spirals chance on the hit")
        -- CalcOffence computes ScaledDamageEffect *= (1 + DoubleDamageChance/100)
        assert.are.equals(1.25, 1 + hitChance / 100,
            "25% double-damage chance is a x1.25 expected-value multiplier on the Ice Spiral hit")
        -- A DoT/ailment cfg (no Hit flag) must NOT pick it up: the roll doubles the hit, not
        -- the Frostbite/Chill it inflicts (LE ailments don't scale with hit size).
        local dotChance = db:Sum("BASE", { flags = ModFlag.Dot }, "DoubleDamageChance")
        assert.are.equals(0, dotChance,
            "ailment/DoT context gets no double-damage: the double-spirals roll is a HIT mechanic only")
    end)

    it("4 points (100) -> x2.0 -- the previously-inflated number is only correct at full allocation", function()
        local db = new("ModDB")
        db.actor = { modDB = db }
        for _ = 1, 4 do
            db:AddList(modLib.parseMod("25% Chance for Double Ice Spirals"))
        end
        local hitChance = db:Sum("BASE", { flags = ModFlag.Hit }, "DoubleDamageChance")
        assert.are.equals(100, hitChance, "4 x 25% = 100% (guaranteed double) at 4/4")
        assert.are.equals(2.0, 1 + hitChance / 100,
            "at 4/4 the EV multiplier is x2.0, matching the old unconditional +100% -- the bug was for partial allocations")
    end)

    ---------------------------------------------------------------------------
    -- Calc channel pin: CalcOffence folds DoubleDamageChance into ScaledDamageEffect
    -- (the same channel avalanche-large-boulder uses); no calc-side change was needed.
    ---------------------------------------------------------------------------
    it("CalcOffence folds DoubleDamageChance into ScaledDamageEffect", function()
        local body = readSource("Modules/CalcOffence.lua")
        assert.is_truthy(body:find('output.DoubleDamageEffect = output.DoubleDamageChance / 100', 1, true),
            "DoubleDamageChance must drive DoubleDamageEffect")
        assert.is_truthy(body:find('output.ScaledDamageEffect = output.ScaledDamageEffect * (1 + output.DoubleDamageEffect', 1, true),
            "ScaledDamageEffect must multiply by (1 + DoubleDamageEffect ...)")
    end)

    ---------------------------------------------------------------------------
    -- Tree data pin: a future tree update that retitles/rescopes Chaos Whirl or moves
    -- the stat between the scaling/non-scaling arrays forces this guard to be revisited.
    ---------------------------------------------------------------------------
    it("game-file: frc87w-21 Chaos Whirl still carries the audited stats (1.4 tree)", function()
        local t1 = readSource("TreeData/1_4/tree_1.json")
        assert.is_not_nil(t1, "must read TreeData/1_4/tree_1.json")
        assert.is_truthy(t1:find('"frc87w%-21"', 1, false), "frc87w-21 must exist in tree_1.json")
        assert.is_truthy(t1:find('"Chaos Whirl"', 1, true), "the node name must be Chaos Whirl")
        assert.is_truthy(t1:find('"maxPoints": 4', 1, true),
            "Chaos Whirl maxPoints must be 4 (4 x 25%% = 100%% double-spirals chance)")
        assert.is_truthy(t1:find("25%% Chance for Double Ice Spirals", 1, false),
            "Chaos Whirl must carry the '25% Chance for Double Ice Spirals' scaling stat")
        assert.is_truthy(t1:find("%+100%% Ice Spiral Damage when Doubled", 1, false),
            "Chaos Whirl must carry the '+100% Ice Spiral Damage when Doubled' descriptor (notScalingStats)")
    end)

    ---------------------------------------------------------------------------
    -- Inline guard markers stay put (ModParser pattern + both ModCache edit sites).
    ---------------------------------------------------------------------------
    it("carries the inline regression-guard markers and the anchored specialModList entry", function()
        local parserText = readSource("Modules/ModParser.lua")
        assert.is_truthy(parserText:find("@leb%-regression%-guard:ice%-spiral%-double%-chance%-ev", 1, false),
            "inline guard ID must remain in ModParser.lua")
        assert.is_truthy(parserText:find('%["%^%(%[%%d%%.%]%+%)%%%% chance for double ice spirals%$"%]', 1, false),
            "the specialModList anchored entry must remain")
        local cacheText = readSource("Data/ModCache.lua")
        local _, count = cacheText:gsub("@leb%-regression%-guard:ice%-spiral%-double%-chance%-ev", "")
        assert.are.equals(2, count,
            "both ModCache edit sites (the +100% no-op and the removed chance row) must carry the inline guard marker")
    end)
end)
