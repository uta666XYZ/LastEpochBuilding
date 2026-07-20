-- @leb-regression-guard: health-regen-applies-to-ward-plus-prefix
-- Locks the fix for the silent-failure parser bug where the affix
-- "+N% Health Regen also applies to Ward" (real item / idol affix,
-- see src/Data/ModItem.json L65861, L73496+ and ModItem_1_4.json
-- L108786+, ModIdol_1_4.json L7429) was falling through to the
-- generic "+N% health regen" handler. That generic handler emits
-- LifeRegen INC, which is the wrong stat AND silently strands the
-- "also applies to Ward" half of the line in the parser residue;
-- the LifeRegenAppliesToWard BASE stat that
-- CalcDefence.lua:641, :796 actually consumes was never set.
--
-- Three layers:
--   1. Parser entries: both anchored patterns accept the optional
--      leading '+'.
--   2. ModCache: the 5 affected entries (+2/+3/+4/+6/+9%) carry
--      the LifeRegenAppliesToWard BASE shape with nil residue.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("HealthRegenAppliesToWardPlusPrefix", function()
    local parserText, cacheText

    setup(function()
        parserText = readSource("Modules/ModParser.lua")
        cacheText  = readSource("Data/ModCache.lua")
    end)

    it("ModParser: '(N)% of health regen also applies to ward' accepts '+' prefix", function()
        local literal = '["^%+?(%d+)%% of health regen also applies to ward$"]'
        assert.is_truthy(
            string.find(parserText, literal, 1, true),
            "Parser anchor for '% of health regen also applies to ward' must include '%+?'"
        )
    end)

    it("ModParser: '(N)% health regen also applies to ward' accepts '+' prefix", function()
        local literal = '["^%+?(%d+)%% health regen also applies to ward$"]'
        assert.is_truthy(
            string.find(parserText, literal, 1, true),
            "Parser anchor for '% health regen also applies to ward' must include '%+?'"
        )
    end)

    it("ModParser: carries the regression-guard marker", function()
        assert.is_truthy(
            string.find(parserText, '@leb%-regression%-guard:health%-regen%-applies%-to%-ward%-plus%-prefix'),
            "Parser must carry the regression-guard marker so future refactors don't silently drop the '+' fix"
        )
    end)

    local tiers = { 2, 3, 4, 6, 9 }
    for _, n in ipairs(tiers) do
        it(string.format("ModCache: '+%d%%%% Health Regen also applies to Ward' resolves to LifeRegenAppliesToWard BASE=%d", n, n), function()
            local needle = string.format(
                '"%%+%d%%%% Health Regen also applies to Ward"%%]={{%%[1%%]={flags=0,keywordFlags=0,name="LifeRegenAppliesToWard",type="BASE",value=%d}},nil}',
                n, n
            )
            assert.is_truthy(
                string.find(cacheText, needle),
                string.format("+%d%% entry must carry LifeRegenAppliesToWard BASE %d with nil residue", n, n)
            )
        end)
    end

    it("ModCache: no '+N% Health Regen also applies to Ward' entry retains the wrong LifeRegen INC shape", function()
        -- Catch any future regen that re-introduces the legacy bug shape.
        local pattern = '"%+%d+%% Health Regen also applies to Ward"%]={{%[1%]={[^}]-name="LifeRegen",type="INC"'
        assert.is_nil(
            string.find(cacheText, pattern),
            "No '+N% Health Regen also applies to Ward' entry may carry LifeRegen INC -- that's the silent-failure shape"
        )
    end)

    it("ModCache: no '+N% Health Regen also applies to Ward' entry leaves residue", function()
        -- Residue presence means the parser only ate the prefix and
        -- dropped the rest of the line. After the fix all 5 entries
        -- end with `,nil}`.
        local pattern = '"%+%d+%% Health Regen also applies to Ward"%][^\n]-",  also applies to Ward "}'
        assert.is_nil(
            string.find(cacheText, pattern),
            "No '+N% Health Regen also applies to Ward' entry may keep the 'also applies to Ward' residue"
        )
    end)
end)
