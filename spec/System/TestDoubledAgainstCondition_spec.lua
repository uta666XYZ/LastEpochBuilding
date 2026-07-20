-- @leb-regression-guard:doubled-against-condition
-- Locks the ENEMY-condition doubling mechanism for tree-node `notScalingStats`
-- lines of the form " Doubled Against <enemy condition>". Sibling of
-- `doubled-if-X-tree-notscaling` (which attaches a PLAYER Condition tag); this
-- one attaches an ENEMY ActorCondition tag instead.
--
-- game-file 2026-06-01 audit (all 1.4 trees) — 9 nodes use the pattern:
--   * ss3tre-7  Cold Presence      — "+10% More Damage", High Health Enemies  (offensive)
--   * javeli-12 Monster Piercer    — "+12% Hit Damage",  High Health          (offensive)
--   * gs15de-16 Executioner        — "+10% Hit Damage",  Low Health (<35%)    (offensive)
--   * fl44-4    Decree of Slaughter — "+8% Hit Damage",  Low Life (<35%)      (offensive)
--   * av75ch-23 Shatter Shot       — "+10% Hit Damage",  Frozen Enemies       (offensive)
--   * ss3tre-25 Glacial Smash      — "+8% Hit Damage",   Frozen Enemies       (offensive)
--   * ss3tre-20 Acclimated         — "5% Less Cold Damage Taken On Hit", Frozen (defensive)
--   * ss3tre-21 Hoarfrost          — "+3 Ward Gained",   Frozen               (utility)
-- " Doubled Against DoTs" (fl71ds-6 Runic Eclipse, "-6% Damage Taken") is an
-- incoming-damage-TYPE defence modifier, NOT an enemy condition, so it is
-- intentionally left unmapped and that mod stays at base.
--
-- Mapping: High Health -> enemy HighHealth, Low Health / Low Life -> enemy
-- LowLife, Frozen -> enemy Frozen. The literal " Doubled Against X" strings
-- stay {} no-ops in ModCache; the doubling SEMANTICS lives in
-- PassiveTree.lua:ProcessStats which attaches
-- {type="ActorCondition", actor="enemy", var=<var>, mult=2} to every scaling
-- mod the node emits. ModStore.lua (`actorcondition-tag-mult` guard) then
-- returns the base value when the enemy condition is OFF (no full gate) and
-- value*2 when ON — exact "doubled against <enemy state>" semantics.
--
-- See REGRESSION_GUARDS.md "doubled-against-condition".

describe("DoubledAgainstCondition", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    it("PassiveTree.lua holds the Doubled-Against scan mapping to enemy ActorCondition tags", function()
        local src = readFile("Classes/PassiveTree.lua")
        assert.is_not_nil(src, "must be able to read Classes/PassiveTree.lua")
        assert.is_truthy(src:find("@leb%-regression%-guard:doubled%-against%-condition", 1, false),
            "PassiveTree.lua must carry the inline guard marker")
        assert.is_truthy(src:find("[Dd]oubled [Aa]gainst", 1, true),
            "PassiveTree.lua must match the 'Doubled Against' notScalingStats pattern")
        assert.is_truthy(src:find('enemyVar = "HighHealth"', 1, true),
            "PassiveTree.lua must map 'High Health' to enemy HighHealth")
        assert.is_truthy(src:find('enemyVar = "LowLife"', 1, true),
            "PassiveTree.lua must map 'Low Health'/'Low Life' to enemy LowLife")
        assert.is_truthy(src:find('enemyVar = "Frozen"', 1, true),
            "PassiveTree.lua must map 'Frozen' to enemy Frozen")
        assert.is_truthy(src:find('type = "ActorCondition", actor = "enemy", var = enemyVar, mult = 2', 1, true),
            "PassiveTree.lua must build an enemy ActorCondition doubling tag with mult=2")
        assert.is_truthy(src:find("actor = doublingTag.actor", 1, true),
            "PassiveTree.lua must copy the tag actor when appending (required for ActorCondition)")
    end)

    it("ModCache keeps the literal ' Doubled Against X' strings as empty no-ops", function()
        -- Semantics is owned by PassiveTree.lua; the cache MUST stay neutral so
        -- the doubling tag is not double-applied (cache mod + tree-handler mod).
        local cacheSrc = readFile("Data/ModCache.lua")
        assert.is_not_nil(cacheSrc, "must read Data/ModCache.lua")
        assert.is_truthy(cacheSrc:find('c%[" Doubled Against High Health Enemies"%]={{},', 1, false),
            "ModCache must keep ' Doubled Against High Health Enemies' as an empty no-op")
        assert.is_truthy(cacheSrc:find('c%[" Doubled Against Frozen Enemies"%]={{},', 1, false),
            "ModCache must keep ' Doubled Against Frozen Enemies' as an empty no-op")
        assert.is_truthy(cacheSrc:find('c%[" Doubled Against Low Life"%]={{},', 1, false),
            "ModCache must keep ' Doubled Against Low Life' as an empty no-op")
    end)

    it("ModStore ActorCondition tag with mult=2 returns base when enemy cond unset and 2*base when set", function()
        -- The exact contract the tree-node handler relies on. An enemy
        -- ActorCondition tag carrying `mult` delivers `value` when the enemy
        -- condition is unset (NOT zero — that's the full-gate path used when
        -- mult is absent) and `value * mult` when set. Models the ss3tre-7 Cold
        -- Presence "+40% More Damage" -> "+80% More against high-health" fold.
        local enemyDB = new("ModDB")
        enemyDB.actor = { modDB = enemyDB }
        local modDB = new("ModDB")
        modDB.actor = { modDB = modDB, enemy = { modDB = enemyDB } }
        modDB:NewMod("Damage", "MORE", 40, "Tree:ss3tre-7-test",
            { type = "ActorCondition", actor = "enemy", var = "HighHealth", mult = 2 })

        local baseSum = modDB:Sum("MORE", nil, "Damage")
        assert.are.equals(40, baseSum,
            "ActorCondition tag with mult must return base value when enemy condition is unset")

        enemyDB:NewMod("Condition:HighHealth", "FLAG", true, "Test")
        local highSum = modDB:Sum("MORE", nil, "Damage")
        assert.are.equals(80, highSum,
            "ActorCondition tag with mult=2 must return 2*base value when enemy condition is set")
    end)

    it("ModStore ActorCondition WITHOUT mult keeps the legacy full-gate (no regression)", function()
        -- The pre-existing enemy-condition modifiers (e.g. "against frozen
        -- enemies") carry no mult and MUST still full-gate to zero when the
        -- enemy condition is unset. The mult path must not change that.
        local enemyDB = new("ModDB")
        enemyDB.actor = { modDB = enemyDB }
        local modDB = new("ModDB")
        modDB.actor = { modDB = modDB, enemy = { modDB = enemyDB } }
        modDB:NewMod("Damage", "INC", 50, "Test",
            { type = "ActorCondition", actor = "enemy", var = "Frozen" })
        assert.are.equals(0, modDB:Sum("INC", nil, "Damage"),
            "ActorCondition without mult must full-gate to zero when enemy condition is unset")
        enemyDB:NewMod("Condition:Frozen", "FLAG", true, "Test")
        assert.are.equals(50, modDB:Sum("INC", nil, "Damage"),
            "ActorCondition without mult must pass value through when enemy condition is set")
    end)

    it("ModStore.lua holds the actorcondition-tag-mult contract this spec depends on", function()
        local src = readFile("Classes/ModStore.lua")
        assert.is_not_nil(src, "must read Classes/ModStore.lua")
        assert.is_truthy(src:find("@leb%-regression%-guard:actorcondition%-tag%-mult", 1, false),
            "ModStore must carry the actorcondition-tag-mult guard marker")
        assert.is_truthy(src:find("value = value * tag.mult", 1, true),
            "ModStore must apply value*mult when an ActorCondition tag's mult is set and match is true")
    end)

    it("ConfigOptions.lua adds the enemy High Health toggle (HighHealth)", function()
        local src = readFile("Modules/ConfigOptions.lua")
        assert.is_not_nil(src, "must read Modules/ConfigOptions.lua")
        assert.is_truthy(src:find('var = "conditionEnemyHighHealth"', 1, true),
            "ConfigOptions must declare conditionEnemyHighHealth")
        assert.is_truthy(src:find('"Condition:HighHealth"', 1, true),
            "conditionEnemyHighHealth must set the enemy Condition:HighHealth flag")
        assert.is_truthy(src:find('ifEnemyCond = "HighHealth"', 1, true),
            "conditionEnemyHighHealth must surface via ifEnemyCond=HighHealth")
    end)

    it("game-file: the audited Doubled-Against nodes carry the expected stats + clauses", function()
        -- Pin the audited universe so a future tree update that adds a new
        -- "Doubled Against X" node forces revisit of this guard's mapping.
        local t1 = readFile("TreeData/1_4/tree_1.json")
        assert.is_not_nil(t1, "must read TreeData/1_4/tree_1.json")
        -- ss3tre-7 Cold Presence: +10% More Damage, " Doubled Against High Health Enemies"
        assert.is_truthy(t1:find('"ss3tre%-7"', 1, false), "ss3tre-7 must exist in tree_1.json")
        assert.is_truthy(t1:find('"Cold Presence"', 1, true), "Cold Presence name must exist")
        assert.is_truthy(t1:find(" Doubled Against High Health Enemies", 1, true),
            "Cold Presence must carry the High Health Enemies clause")
        assert.is_truthy(t1:find('"Glacial Smash"', 1, true), "Glacial Smash (Frozen) must exist")

        local t2 = readFile("TreeData/1_4/tree_2.json")
        assert.is_not_nil(t2, "must read TreeData/1_4/tree_2.json")
        assert.is_truthy(t2:find('"Monster Piercer"', 1, true), "Monster Piercer (High Health) must exist")
        assert.is_truthy(t2:find('"Executioner"', 1, true), "Executioner (Low Health) must exist")
    end)
end)
