-- @leb-regression-guard: ward-one-shot-gain-family
-- Locks ModCache for the one-shot "Ward gain" family (name="Ward" BASE),
-- distinct from the Ward-per-Second regen family. ~193 entries spread
-- across ~80 distinct trigger sub-patterns: on Cast, on Dodge, on Crit,
-- on Hit, on Rune consumed, per Stack, per LowLife, etc.
--
-- This guard advances in waves (O1, O2, ...). Each wave locks a specific
-- sub-pattern of entries that have been verified to either:
-- (a) already carry the correct gating tag and just need residue cleanup, or
-- (b) need parser + ConfigOptions infra additions to gate them properly.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("WardOneShotGainFamily", function()
    local cacheText

    setup(function()
        cacheText = readSource("Data/ModCache.lua")
    end)

    -- O1: LowLife trigger -- correctly tagged already, residue cleanup only.
    -- 10 entries: "+N Ward gained when damage leaves you at low health" where
    -- N in {19, 42, 81, 102, 162, 184, 213, 252, 343, 484} (passive-tree node).
    it("ModCache: 10 'Ward gained when damage leaves you at low health' entries carry Condition:LowLife with empty residue", function()
        local needle = 'c%["%d+ Ward gained when damage leaves you at low health"%]={{%[1%]={%[1%]={type="Condition",var="LowLife"},flags=0,keywordFlags=0,name="Ward",type="BASE",value=%d+}},""}'
        local _, count = string.gsub(cacheText, needle, "")
        assert.are.equal(10, count,
            "expected exactly 10 'damage leaves you at low health' entries with Condition:LowLife and empty residue, got " .. count)
    end)

    it("ModCache: no 'damage leaves you at low health' entry retains stale residue", function()
        local stale = 'c%["%d+ Ward gained when damage leaves you at low health"%]={{[^\n]-}},"[^"][^\n]*"}'
        assert.is_nil(string.find(cacheText, stale),
            "low-health ward entries must have empty residue")
    end)

    -- O2: residue cleanup on entries that already carry adequate gating
    -- (SkillName scope or keywordFlags). Calc-wiring for the "on cast",
    -- "per Rune consumed", "per Silver Shroud stack" triggers remains a
    -- follow-up — but the parser must no longer leak descriptive residue.

    it("ModCache: 10 '+N Ward gained when you directly Cast a Spell' entries carry keywordFlags=256 with empty residue", function()
        local needle = 'c%["%+%d+ Ward gained when you directly Cast a Spell"%]={{%[1%]={flags=0,keywordFlags=256,name="Ward",type="BASE",value=%d+}},""}'
        local _, count = string.gsub(cacheText, needle, "")
        assert.are.equal(10, count, "got " .. count)
    end)

    it("ModCache: 10 '+N Ward gained when you cast Flame Ward' entries carry SkillName=Flame Ward with empty residue", function()
        local needle = 'c%["%+%d+ Ward gained when you cast Flame Ward"%]={{%[1%]={%[1%]={skillName="Flame Ward",type="SkillName"},flags=0,keywordFlags=0,name="Ward",type="BASE",value=%d+}},""}'
        local _, count = string.gsub(cacheText, needle, "")
        assert.are.equal(10, count, "got " .. count)
    end)

    it("ModCache: 17 '+N Ward gained per Rune consumed with Runic Invocation' entries carry SkillName=Runic Invocation with empty residue", function()
        local needle = 'c%["%+%d+ Ward gained per Rune consumed with Runic Invocation"%]={{%[1%]={%[1%]={skillName="Runic Invocation",type="SkillName"},flags=0,keywordFlags=0,name="Ward",type="BASE",value=%d+}},""}'
        local _, count = string.gsub(cacheText, needle, "")
        assert.are.equal(17, count, "got " .. count)
    end)

    it("ModCache: 13 '+N Ward granted by Silver Shroud per stack' entries carry SkillName=Silver Shroud with empty residue", function()
        local needle = 'c%["%+%d+ Ward granted by Silver Shroud per stack"%]={{%[1%]={%[1%]={skillName="Silver Shroud",type="SkillName"},flags=0,keywordFlags=0,name="Ward",type="BASE",value=%d+}},""}'
        local _, count = string.gsub(cacheText, needle, "")
        assert.are.equal(13, count, "got " .. count)
    end)

    -- O3a: bare-body entries (flags=0,keywordFlags=0, no inner tag) neutralized to {{},""}.
    -- These had no gate of any kind; downstream Calcs (Calcs.lua L364) only sums INC Ward,
    -- so bare BASE entries were dead code. Neutralizing them makes the dead code explicit.
    it("ModCache: 0 bare-body name='Ward' BASE stale entries remain", function()
        local pat = 'c%["[^"]+"%]={{%[1%]={flags=0,keywordFlags=0,name="Ward",type="BASE",value=[%-%d%.]+}},"[^"]+"}'
        assert.is_nil(string.find(cacheText, pat),
            "no bare-body Ward BASE entry may retain residue (they should be neutralized to {{},''})")
    end)

    -- O3b: 8 "Overhealing from potions..." entries were mis-parsed: the actual game stat
    -- is "Health Gained on Potion Use" (Health, not Ward); skillName="Healing" is also wrong
    -- (Healing is a tag/category, not a player skill). Body neutralized to {{},""}.
    it("ModCache: 8 'Overhealing from potions...' entries fully neutralized", function()
        local needle = 'c%["%+%d+ Overhealing from potions does not count towards triggering this effect Health Gained on Potion Use"%]={{},""}'
        local _, count = string.gsub(cacheText, needle, "")
        assert.are.equal(8, count, "expected 8 neutralized Overhealing entries, got " .. count)
    end)

    -- O3c: residue cleanup on remaining 33 tagged entries (PerStat / SkillName /
    -- keywordFlags / flags-gated). Tags preserved; only trailing descriptive noise removed.
    it("ModCache: zero stale name='Ward' BASE entries remain across the family", function()
        -- A stale entry has a non-empty residue string AND a non-empty body.
        local stale = 'c%["[^"]+"%]={{%[1%]={[^\n]-name="Ward",type="BASE"[^\n]-}},"[^"][^\n]-"}'
        assert.is_nil(string.find(cacheText, stale),
            "no name='Ward' BASE entry may retain stale residue after the O1+O2+O3 sweep")
    end)

    it("ModCache: no O2 entry retains stale residue", function()
        local keys = {
            '%+%d+ Ward gained when you directly Cast a Spell',
            '%+%d+ Ward gained when you cast Flame Ward',
            '%+%d+ Ward gained per Rune consumed with Runic Invocation',
            '%+%d+ Ward granted by Silver Shroud per stack',
        }
        for _, k in ipairs(keys) do
            local stale = 'c%["' .. k .. '"%]={{[^\n]-}},"[^"][^\n]*"}'
            assert.is_nil(string.find(cacheText, stale),
                "O2 entry must have empty residue: " .. k)
        end
    end)
end)
