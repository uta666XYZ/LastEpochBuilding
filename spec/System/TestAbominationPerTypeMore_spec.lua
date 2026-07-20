-- @leb-regression-guard:abomination-pertype-more
-- Assemble Abomination per-absorbed-minion-type specialization-tree MOREs.
-- These verbatim node strings are present in tree_3.json (treeId aa710):
--   * Sharpened Bones      aa710-2  "+2% Melee Damage and Health per Skeleton Warrior"
--                                   "+3% Attack Speed per Skeleton Rogue"
--                                   "+5% Area per Skeleton Archer"
--   * Engorgement          aa710-26 "+4% Damage per Minion Type Absorbed"
--                                   "+4% Health per Minion Type Absorbed"
--   * Death in the Family  aa710-28 "+20% Damage With All Types Absorbed"
--                                   "+20% Attack Speed With All Types Absorbed"
--                                   "+20% Movement Speed With All Types Absorbed"
--   * Spoils of War        aa710-6  " Double Strike Gained on Warrior or Rogue Absorbed"
--                                   "+30% Double Strike Damage per Warrior or Rogue Absorbed"
-- Implementation (all three coupled sites carry this guard id):
--   (1) ModParser modTagList "per skeleton warrior/rogue/archer", "per minion type
--       absorbed", "with all types absorbed", "per warrior or rogue absorbed" -> the
--       per-type Multiplier (or all-types Condition) tags, with the right limits.
--   (2) Data/Global.lua LE_TREE_NODE_STAT_REWRITE["aa710-2"] splits the compound
--       "Melee Damage and Health per Skeleton Warrior" line to a Damage-only line so it
--       parses with no residue (PassiveTree drops mods with non-empty `extra`).
--   (3) ConfigOptions count/check configs feed those vars onto the abomination minion via
--       MinionModifier (default 0 / OFF -> MORE 1.0 -> corpus-neutral).
--   (4) Data/ModCache.lua: the stale FLAT-baked rows for the 3 modeled damage lines (and
--       the Double Strike line) were REMOVED so they re-parse live WITH the tags.
-- MORE math (one MORE of value x count, additive within the mod):
--   Sharpened Bones:     1 + 0.02 * min(warriors, 20)   -> 10 warriors = x1.20
--   Engorgement:         1 + 0.04 * min(types, 4)        -> 4 types    = x1.16
--   Death in the Family: 1.20 when the all-types condition is set, else 1.0 (binary)
-- Spoils of War's +30% MORE belongs to the granted Double Strike sub-skill and is
--   modeled by `abomination-double-strike-grant`
--   (spec/System/TestAbominationDoubleStrike_spec.lua): data.skills["Abomination Double
--   Strike"] + the ExtraMinionSkill grant make "Double Strike" a recognised skillName, so
--   the +30% line no longer leaves a residue -- it resolves to a Double-Strike-scoped MORE
--   driven by the WarriorsOrRogues count.
-- Remaining scope:
--   * The Health half of Sharpened Bones and the Rogue/Archer attack-speed/area lines are
--     secondary; counts are captured but those non-damage lines are not modeled.
--   * The necrotic base-damage split is not modeled here.
-- See REGRESSION_GUARDS.md "abomination-pertype-more".

describe("AbominationPerTypeMore #abomination #skills", function()
    local function readSource(relPath)
        local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
        assert.is_not_nil(f, "must be able to open " .. relPath)
        local text = f:read("*a"); f:close()
        return text
    end

    local function findTag(mod, tagType, var)
        for _, tag in ipairs(mod) do
            if tag.type == tagType and (var == nil or tag.var == var) then return tag end
        end
        return nil
    end

    before_each(function()
        newBuild()
    end)

    -- 1. Verbatim node strings present in the tree file -------------------------------
    it("tree_3.json carries the verbatim aa710 per-type node strings", function()
        local txt = readSource("TreeData/1_4/tree_3.json")
        assert.is_truthy(string.find(txt, "+2% Melee Damage and Health per Skeleton Warrior", 1, true),
            "Sharpened Bones warrior line must be verbatim")
        assert.is_truthy(string.find(txt, "+3% Attack Speed per Skeleton Rogue", 1, true))
        assert.is_truthy(string.find(txt, "+5% Area per Skeleton Archer", 1, true))
        assert.is_truthy(string.find(txt, "+4% Damage per Minion Type Absorbed", 1, true),
            "Engorgement damage line must be verbatim")
        assert.is_truthy(string.find(txt, "+20% Damage With All Types Absorbed", 1, true),
            "Death in the Family damage line must be verbatim")
        assert.is_truthy(string.find(txt, "+30% Double Strike Damage per Warrior or Rogue Absorbed", 1, true),
            "Spoils of War line must be verbatim")
    end)

    -- 2. Parse contracts -------------------------------------------------------------
    it("Engorgement '+4% Damage per Minion Type Absorbed' -> MORE Damage 4% x Multiplier:AbominationMinionTypesAbsorbed (limit 4)", function()
        local list, extra = modLib.parseMod("+4% Damage per Minion Type Absorbed")
        assert.is_not_nil(list, "must parse")
        assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
        assert.are.equal(1, #list)
        local mod = list[1]
        assert.are.equal("Damage", mod.name)
        assert.are.equal("MORE", mod.type)
        assert.are.equal(4, mod.value)
        local mult = findTag(mod, "Multiplier", "AbominationMinionTypesAbsorbed")
        assert.is_not_nil(mult, "must carry Multiplier:AbominationMinionTypesAbsorbed")
        assert.are.equal(4, mult.limit, "limit must cap at 4 (the 4 minion types)")
    end)

    it("Death in the Family '+20% Damage With All Types Absorbed' -> MORE Damage 20% gated by Condition:AbominationAllTypesAbsorbed", function()
        local list, extra = modLib.parseMod("+20% Damage With All Types Absorbed")
        assert.is_not_nil(list, "must parse")
        assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
        assert.are.equal(1, #list)
        local mod = list[1]
        assert.are.equal("Damage", mod.name)
        assert.are.equal("MORE", mod.type)
        assert.are.equal(20, mod.value)
        assert.is_not_nil(findTag(mod, "Condition", "AbominationAllTypesAbsorbed"),
            "must be gated by the all-types-absorbed condition")
    end)

    it("Sharpened Bones (rewritten) '+2% Melee Damage per Skeleton Warrior' -> MORE Damage 2% x Multiplier:AbominationSkeletonWarriorsAbsorbed (limit 20)", function()
        local list, extra = modLib.parseMod("+2% Melee Damage per Skeleton Warrior")
        assert.is_not_nil(list, "must parse")
        assert.is_true(not extra or extra == "", "no residue, got: " .. tostring(extra))
        assert.are.equal(1, #list)
        local mod = list[1]
        assert.are.equal("Damage", mod.name)
        assert.are.equal("MORE", mod.type)
        assert.are.equal(2, mod.value)
        local mult = findTag(mod, "Multiplier", "AbominationSkeletonWarriorsAbsorbed")
        assert.is_not_nil(mult, "must carry Multiplier:AbominationSkeletonWarriorsAbsorbed")
        assert.are.equal(20, mult.limit, "limit must cap at 20 skeletons")
    end)

    it("Spoils of War '+30% Double Strike Damage per Warrior or Rogue Absorbed' -> Double-Strike-scoped MORE (gap CLOSED by abomination-double-strike-grant)", function()
        -- Previously a DOCUMENTED GAP: "Double Strike" was an unmodeled sub-skill, so the
        -- line left a "Double Strike" residue and PassiveTree dropped it. The
        -- `abomination-double-strike-grant` fix adds data.skills["Abomination Double
        -- Strike"] (name "Double Strike") + the ExtraMinionSkill grant, so the
        -- skillNameList post-scan now recognises the token (no residue) and the line
        -- resolves to a MORE scoped to Double Strike. Full contract + in-game validation:
        -- spec/System/TestAbominationDoubleStrike_spec.lua.
        local list, extra = modLib.parseMod("+30% Double Strike Damage per Warrior or Rogue Absorbed")
        assert.is_not_nil(list, "must parse")
        assert.is_true(not extra or extra == "", "gap CLOSED: no residue, got: " .. tostring(extra))
        local mod = list[1]
        assert.are.equal("Damage", mod.name)
        assert.are.equal("MORE", mod.type)
        assert.are.equal(30, mod.value)
        assert.is_not_nil(findTag(mod, "Multiplier", "AbominationWarriorsOrRoguesAbsorbed"),
            "the 'per warrior or rogue absorbed' tag must be recognised")
        local snTag = findTag(mod, "SkillName")
        assert.is_not_nil(snTag, "the MORE must be SkillName-scoped (so base Melee is untouched)")
        assert.are.equal("Double Strike", snTag.skillName)
    end)

    -- 3. Registry / wiring markers ---------------------------------------------------
    it("LE_TREE_NODE_STAT_REWRITE splits aa710-2 to a Damage-only line", function()
        assert.is_table(LE_TREE_NODE_STAT_REWRITE["aa710-2"], "aa710-2 must be registered")
        local stat = "+2% Melee Damage and Health per Skeleton Warrior"
        for _, rw in ipairs(LE_TREE_NODE_STAT_REWRITE["aa710-2"]) do
            stat = (stat:gsub(rw.pat, rw.repl))
        end
        assert.are.equal("+2% Melee Damage per Skeleton Warrior", stat,
            "the Health half must be dropped, leaving a clean Damage line")
    end)

    it("guard markers + var wiring present across ModParser / ConfigOptions / Global / ModCache", function()
        local mp = readSource("Modules/ModParser.lua")
        assert.is_truthy(string.find(mp, "@leb-regression-guard:abomination-pertype-more", 1, true))
        assert.is_truthy(string.find(mp, '["per minion type absorbed"]', 1, true))
        assert.is_truthy(string.find(mp, '["with all types absorbed"]', 1, true))
        assert.is_truthy(string.find(mp, '["per skeleton warrior"]', 1, true))
        assert.is_truthy(string.find(mp, "AbominationMinionTypesAbsorbed", 1, true))
        assert.is_truthy(string.find(mp, "AbominationAllTypesAbsorbed", 1, true))

        local co = readSource("Modules/ConfigOptions.lua")
        assert.is_truthy(string.find(co, "@leb-regression-guard:abomination-pertype-more", 1, true))
        assert.is_truthy(string.find(co, "multiplierAbominationMinionTypesAbsorbed", 1, true))
        assert.is_truthy(string.find(co, "multiplierAbominationSkeletonWarriorsAbsorbed", 1, true))
        assert.is_truthy(string.find(co, "conditionAbominationAllTypesAbsorbed", 1, true))

        local gl = readSource("Data/Global.lua")
        assert.is_truthy(string.find(gl, "@leb-regression-guard:abomination-pertype-more", 1, true))
        assert.is_truthy(string.find(gl, '["aa710-2"]', 1, true))

        -- The stale flat ModCache rows for the modeled damage lines must be GONE so the
        -- live parser regenerates them with the tags.
        local mc = readSource("Data/ModCache.lua")
        assert.is_falsy(string.find(mc, "+4% Damage per Minion Type Absorbed", 1, true),
            "stale Engorgement ModCache row must be removed")
        assert.is_falsy(string.find(mc, "+20% Damage With All Types Absorbed", 1, true),
            "stale Death-in-the-Family ModCache row must be removed")
        assert.is_falsy(string.find(mc, "+2% Melee Damage and Health per Skeleton Warrior", 1, true),
            "stale Sharpened Bones ModCache row must be removed")
    end)

    -- 4. Behavioural: tree node -> minion-scoped MORE that the config multiplier drives -
    local function nodeDamageMore(nodeId)
        local node = build.spec.nodes[nodeId]
        assert.is_not_nil(node, nodeId .. " must exist in the loaded 1.4 tree")
        node.alloc = 1
        build.spec.tree:ProcessStats(node)
        local found
        for _, mod in ipairs(node.modList) do
            if mod.name == "Damage" and mod.type == "MORE" then found = mod end
        end
        assert.is_not_nil(found, nodeId .. " must emit a MORE Damage mod")
        return found, node
    end

    it("Engorgement aa710-26: MORE = 1 + 0.04*min(types,4); 4 types -> x1.16, capped", function()
        local mod, node = nodeDamageMore("aa710-26")
        local cfg = { skillGrantedEffect = { id = node.skillId } }
        local function moreAt(types)
            local modDB = new("ModDB")
            modDB:AddMod(mod)
            modDB.multipliers.AbominationMinionTypesAbsorbed = types
            return modDB:More(cfg, "Damage")
        end
        assert.are.equal(1, moreAt(0), "0 types -> strict no-op")
        assert.is_true(math.abs(moreAt(4) - 1.16) < 1e-9, "4 types -> x1.16, got " .. tostring(moreAt(4)))
        assert.is_true(math.abs(moreAt(8) - 1.16) < 1e-9, "8 types must cap at x1.16 (limit 4), got " .. tostring(moreAt(8)))
    end)

    it("Sharpened Bones aa710-2: MORE = 1 + 0.02*min(warriors,20); 10 -> x1.20, 20 -> x1.40, capped", function()
        local mod, node = nodeDamageMore("aa710-2")
        assert.is_not_nil(findTag(mod, "Multiplier", "AbominationSkeletonWarriorsAbsorbed"),
            "the aa710-2 damage MORE must be per-Skeleton-Warrior after the rewrite")
        -- This is a MELEE Damage MORE ("Melee Damage" sets KeywordFlag.Melee=512 on the
        -- mod), matching the abomination's melee hits, so the query cfg must request the
        -- Melee keyword flag.
        local cfg = { skillGrantedEffect = { id = node.skillId }, keywordFlags = KeywordFlag.Melee }
        local function moreAt(n)
            local modDB = new("ModDB")
            modDB:AddMod(mod)
            modDB.multipliers.AbominationSkeletonWarriorsAbsorbed = n
            return modDB:More(cfg, "Damage")
        end
        assert.are.equal(1, moreAt(0), "0 warriors -> strict no-op")
        assert.is_true(math.abs(moreAt(10) - 1.20) < 1e-9, "10 warriors -> x1.20, got " .. tostring(moreAt(10)))
        assert.is_true(math.abs(moreAt(20) - 1.40) < 1e-9, "20 warriors -> x1.40, got " .. tostring(moreAt(20)))
        assert.is_true(math.abs(moreAt(30) - 1.40) < 1e-9, "30 warriors must cap at x1.40 (limit 20), got " .. tostring(moreAt(30)))
    end)

    it("Death in the Family aa710-28: binary +20% MORE gated by the all-types condition", function()
        local mod, node = nodeDamageMore("aa710-28")
        assert.is_not_nil(findTag(mod, "Condition", "AbominationAllTypesAbsorbed"),
            "the aa710-28 damage MORE must be gated by the all-types condition")
        local cfg = { skillGrantedEffect = { id = node.skillId } }
        local function moreWhen(allTypes)
            local modDB = new("ModDB")
            modDB:AddMod(mod)
            modDB.conditions.AbominationAllTypesAbsorbed = allTypes
            return modDB:More(cfg, "Damage")
        end
        assert.are.equal(1, moreWhen(false), "condition OFF -> no-op (corpus-neutral default)")
        assert.is_true(math.abs(moreWhen(true) - 1.20) < 1e-9, "condition ON -> x1.20, got " .. tostring(moreWhen(true)))
    end)

    -- 5. Config contracts ------------------------------------------------------------
    it("config entries are count/check typed, ifMult/ifCond gated, and set the minion-scoped vars", function()
        local src = readSource("Modules/ConfigOptions.lua")
        local function entry(var)
            local e = src:match('{ var = "' .. var .. '".-end },')
            assert.is_not_nil(e, var .. " config entry must exist")
            return e
        end
        local eng = entry("multiplierAbominationMinionTypesAbsorbed")
        assert.is_truthy(eng:find('type = "count"', 1, true))
        assert.is_truthy(eng:find('ifMult = "AbominationMinionTypesAbsorbed"', 1, true))
        assert.is_truthy(eng:find('Multiplier:AbominationMinionTypesAbsorbed', 1, true))
        assert.is_truthy(eng:find("MinionModifier", 1, true), "must route via MinionModifier to the abomination")

        local war = entry("multiplierAbominationSkeletonWarriorsAbsorbed")
        assert.is_truthy(war:find('Multiplier:AbominationSkeletonWarriorsAbsorbed', 1, true))
        assert.is_truthy(war:find("MinionModifier", 1, true))

        local dif = entry("conditionAbominationAllTypesAbsorbed")
        assert.is_truthy(dif:find('type = "check"', 1, true))
        assert.is_truthy(dif:find('ifCond = "AbominationAllTypesAbsorbed"', 1, true))
        assert.is_truthy(dif:find('Condition:AbominationAllTypesAbsorbed', 1, true))
        assert.is_truthy(dif:find("MinionModifier", 1, true))
    end)
end)
