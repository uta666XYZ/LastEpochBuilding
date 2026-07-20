-- @leb-regression-guard:grounding-totem-condition
-- Locks the parser + ModCache contract for the Avalanche specialization node
-- av75ch-12 "Grounding".
--
-- Ground truth (LEB tree data == in-game node, TreeData/1_4/tree_0.json):
--   name "Grounding", maxPoints 3, stats ["+15% Hit Damage While Totem Active"],
--   description "Avalanche hits deal more damage (multiplicative with other
--   modifiers) while you have at least one active totem."
--
-- The description says MORE (multiplicative), NOT increased. The datamine field
-- AvalancheSnowballMutator.increasedDamageWithATotem is only the engine variable
-- name; the SuXes per-hit ladder measured a clean totem factor of x1.4521
-- (~= 3pt x 15% MORE), which an `increased` could never net (it would be diluted
-- by the build's increased pool). So "+15% Hit Damage" -> {Damage, MORE, 15,
-- ModFlag.Hit} (already correct in the parser) and the totem suffix must attach
-- a Condition:HaveTotem tag rather than be dropped.
--
-- The bug: before the fix the trailing " While Totem Active" survived as parser
-- residue, so the ModCache row carried an unconsumed `extra` string and
-- PassiveTree.lua:ProcessStats ("if mod.list and (not mod.extra or extra=='')")
-- silently DROPPED the whole MORE mod. SuXes (lv92 Shaman, Avalanche + totem)
-- thereby lost the entire Grounding x1.45 contribution.
--
-- The fix: a modTagList entry ["while totem active"] = Condition:HaveTotem. The
-- bonus is gated by the pre-existing conditionHaveTotem config / CalcPerform
-- auto-set, so it applies only while a totem is active (OFF -> no contribution,
-- matching the in-game conditional). Only the Grounding node uses this string
-- (no affix/unique), so the general suffix entry has a Grounding-only reach.
--
-- See REGRESSION_GUARDS.md > "grounding-totem-condition".

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

describe("GroundingTotemCondition", function()
    before_each(function()
        newBuild()
    end)

    ---------------------------------------------------------------------------
    -- Parse-level: MORE Hit Damage gated on the totem condition, no residue
    ---------------------------------------------------------------------------
    it("parses '+15% Hit Damage While Totem Active' to a MORE Hit Damage mod tagged HaveTotem (nil extra)", function()
        local mods, extra = modLib.parseMod("+15% Hit Damage While Totem Active")
        assert.is_nil(extra, "the totem suffix must be consumed, leaving no residue")
        assert.is_not_nil(mods)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type, "in-game node says 'more damage (multiplicative)' -> MORE, not INC")
        assert.are.equals(15, m.value, "per-point value; the tree applies x maxPoints (3 -> 45) at alloc time")
        assert.are.equals(ModFlag.Hit, m.flags, "must keep the Hit damage flag (8388608)")
        local cond = findTag(m, "Condition")
        assert.is_not_nil(cond, "the mod must carry the totem Condition gate")
        assert.are.equals("HaveTotem", cond.var)
        assert.is_nil(cond.mult, "a plain Condition tag (no mult) full-gates to zero when the totem is absent")
    end)

    ---------------------------------------------------------------------------
    -- ModDB resolution: OFF -> filtered (no-op), ON -> the MORE applies
    ---------------------------------------------------------------------------
    it("Condition gates the MORE: no totem -> 0 (no contribution), totem active -> 15", function()
        local db = new("ModDB")
        db.actor = { modDB = db }
        db:AddList(modLib.parseMod("+15% Hit Damage While Totem Active"))
        local cfg = { flags = ModFlag.Hit }
        assert.are.equals(0, db:Sum("MORE", cfg, "Damage"),
            "no totem -> the Grounding MORE must be fully gated out (x1.00)")
        db:NewMod("Condition:HaveTotem", "FLAG", true, "Test")
        assert.are.equals(15, db:Sum("MORE", cfg, "Damage"),
            "totem active -> the +15% Hit Damage MORE applies")
    end)

    ---------------------------------------------------------------------------
    -- Regression: the bare "+15% Hit Damage" must NOT gain a totem gate
    ---------------------------------------------------------------------------
    it("the unconditional '+15% Hit Damage' still parses ungated (no Condition tag)", function()
        local mods, extra = modLib.parseMod("+15% Hit Damage")
        assert.is_nil(extra)
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type)
        assert.are.equals(15, m.value)
        assert.is_nil(findTag(m, "Condition"),
            "the unconditional Hit Damage form must not pick up the totem gate")
    end)

    ---------------------------------------------------------------------------
    -- ModCache: the baked row is fixed (tag present, residue gone) so the
    -- runtime short-circuit returns the gated mod instead of dropping it.
    ---------------------------------------------------------------------------
    it("the ModCache row carries the HaveTotem tag and no leftover residue", function()
        local body = readSource("Data/ModCache.lua")
        assert.is_truthy(body:find('c["+15%% Hit Damage While Totem Active"]', 1, false),
            "the Grounding ModCache row must exist")
        -- The fixed row: {{[1]={[1]={type="Condition",var="HaveTotem"},...,type="MORE",value=15}},nil}
        assert.is_truthy(body:find('{type="Condition",var="HaveTotem"},flags=8388608,keywordFlags=0,name="Damage",type="MORE",value=15}},nil}', 1, true),
            "the cached Grounding mod must carry Condition:HaveTotem + MORE 15 + nil residue")
        assert.is_nil(body:find('value=15}},"   While Totem Active "', 1, true),
            "the stale ' While Totem Active ' residue string must be gone (it caused the drop)")
    end)

    ---------------------------------------------------------------------------
    -- Tree data pin: a future tree update that retitles/rescopes Grounding or
    -- changes its per-point value forces this guard to be revisited.
    ---------------------------------------------------------------------------
    it("game-file: av75ch-12 Grounding still carries the audited stat (1.4 tree)", function()
        local t0 = readSource("TreeData/1_4/tree_0.json")
        assert.is_not_nil(t0, "must read TreeData/1_4/tree_0.json")
        assert.is_truthy(t0:find('"av75ch%-12"', 1, false), "av75ch-12 must exist in tree_0.json")
        assert.is_truthy(t0:find('"Grounding"', 1, true), "the node name must be Grounding")
        assert.is_truthy(t0:find("+15%% Hit Damage While Totem Active", 1, false),
            "Grounding must carry the '+15% Hit Damage While Totem Active' stat")
    end)

    ---------------------------------------------------------------------------
    -- Inline guard marker stays put.
    ---------------------------------------------------------------------------
    it("carries the inline regression-guard marker in ModParser.lua", function()
        local parserText = readSource("Modules/ModParser.lua")
        assert.is_truthy(parserText:find("@leb%-regression%-guard:grounding%-totem%-condition", 1, false),
            "inline guard ID must remain in ModParser.lua")
        assert.is_truthy(parserText:find('%["while totem active"%] = { tag = { type = "Condition", var = "HaveTotem" } }', 1, false),
            "the modTagList entry must remain")
    end)
end)
