-- @leb-regression-guard:tree-also-applies-to-minions
-- Locks the propagation of the LE follow-up modifier " Also Applies To Minions"
-- (leading space, its own stat line) onto the player's minions. The phrase makes
-- the PRECEDING stat lines of the same passive-tree node ALSO apply to minions.
-- Canonical node: Sentinel-37 "Smelter's Might" (tree_2.json), stats =
--   "+7% Bleed Chance", "+7% Ignite Chance",
--   " Also Applies To Minions", " Doubled for you with a 2h weapon"
-- In-game: "You and your minions have a chance to inflict bleeding and ignite on
-- hit." parseMod returns `unknown` for the bare follow-up line, so before this fix
-- the minion never received the bonus.
--
-- PassiveTree.lua:ProcessStats scans node.sd for the follow-up and, for every real
-- mod parsed on a line BEFORE it (back to the previous follow-up boundary or node
-- start), emits an ADDITIONAL `MinionModifier` LIST copy of the freshly-copied
-- parsed mod. CalcPerform.lua's MinionModifier dispatch then lands the inner mod on
-- env.minion.modDB. The player's own copy is left intact ("Also" = player AND
-- minion); player-only follow-ups that come AFTER (e.g. " Doubled for you with a
-- 2h weapon") are NOT inherited by the minion copy.
--
-- Invariants this spec locks:
--   (1) PassiveTree.lua holds the inline guard + the boundary scan.
--   (2) A node with [<mod>, " Also Applies To Minions"] emits exactly one
--       MinionModifier per preceding real mod, wrapping the same inner mod.
--   (3) The handler is GENERIC (not ailment-specific): a Damage mod is wrapped too.
--   (4) A node WITHOUT the follow-up emits NO MinionModifier (corpus-neutral).
--   (5) Mods on lines AFTER the follow-up boundary are NOT wrapped.
--   (6) Rank scaling carries into the minion copy (alloc=5 -> value*5).
--   (7) game-file: Sentinel-37 "Smelter's Might" still carries the phrase.
-- See REGRESSION_GUARDS.md "tree-also-applies-to-minions".

describe("TreeAlsoAppliesToMinions #minion", function()
    local function readSource(relPath)
        local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
        assert.is_not_nil(f, "must be able to open " .. relPath)
        local text = f:read("*a"); f:close()
        return text
    end

    local function processNode(stats, alloc)
        newBuild()
        local node = { id = "TEST-aatm", alloc = alloc or 1, stats = stats, notScalingStats = {} }
        build.spec.tree:ProcessStats(node)
        return node
    end

    local function minionMods(node)
        return node.modList:List(nil, "MinionModifier")
    end

    it("PassiveTree.lua holds the inline guard and the boundary scan", function()
        local src = readSource("Classes/PassiveTree.lua")
        assert.is_truthy(src:find("@leb%-regression%-guard:tree%-also%-applies%-to%-minions", 1, false),
            "PassiveTree.lua must carry the inline guard marker")
        assert.is_truthy(src:find("also applies to minions", 1, true),
            "PassiveTree.lua must match the normalized follow-up phrase")
        assert.is_truthy(src:find("minionApplyBoundaries", 1, true),
            "PassiveTree.lua must declare the minionApplyBoundaries scan")
        assert.is_truthy(src:find('"MinionModifier", "LIST"', 1, true),
            "PassiveTree.lua must emit MinionModifier LIST copies")
    end)

    it("Smelter's-Might shape wraps each preceding ailment-chance mod and excludes the trailing 'Doubled' line", function()
        local node = processNode({
            "+7% Bleed Chance", "+7% Ignite Chance",
            " Also Applies To Minions", " Doubled for you with a 2h weapon",
        })
        local mm = minionMods(node)
        assert.are.equals(2, #mm, "exactly two MinionModifier copies (bleed + ignite); the trailing 'Doubled' line is not wrapped")
        local seen = {}
        for _, inner in ipairs(mm) do
            assert.is_not_nil(inner.mod, "MinionModifier must wrap an inner mod")
            seen[inner.mod.name] = inner.mod.value
        end
        assert.are.equals(7, seen["ChanceToTriggerOnHit_Ailment_Bleed"], "bleed chance must propagate to minion")
        assert.are.equals(7, seen["ChanceToTriggerOnHit_Ailment_Ignite"], "ignite chance must propagate to minion")
    end)

    it("the player keeps its own copy of the preceding mod (Also = player AND minion)", function()
        local node = processNode({ "+10% Bleed Chance", " Also Applies To Minions" })
        -- player copy carries ModFlag.Hit, so it sums under a Hit cfg
        local playerVal = node.modList:Sum("BASE", { flags = ModFlag.Hit }, "ChanceToTriggerOnHit_Ailment_Bleed")
        assert.are.equals(10, playerVal, "player must still receive the bleed chance")
        assert.are.equals(1, #minionMods(node), "minion must also receive it")
    end)

    it("the handler is generic, not ailment-specific (a Damage mod is wrapped)", function()
        local node = processNode({ "+20% Increased Damage", " Also Applies To Minions" })
        local mm = minionMods(node)
        assert.are.equals(1, #mm)
        assert.are.equals("Damage", mm[1].mod.name)
        assert.are.equals(20, mm[1].mod.value)
    end)

    it("a node without the follow-up emits no MinionModifier (corpus-neutral)", function()
        local node = processNode({ "+10% Bleed Chance" })
        assert.are.equals(0, #minionMods(node), "no follow-up -> no minion propagation")
    end)

    it("rank scaling carries into the minion copy (alloc=5 -> value*5)", function()
        local node = processNode({ "+7% Bleed Chance", " Also Applies To Minions" }, 5)
        local mm = minionMods(node)
        assert.are.equals(1, #mm)
        assert.are.equals(35, mm[1].mod.value, "5 points -> 7*5 = 35 on the minion copy")
    end)

    it("game-file: Sentinel-37 'Smelter's Might' still carries ' Also Applies To Minions'", function()
        local treeFile = readSource("TreeData/1_4/tree_2.json")
        assert.is_truthy(treeFile:find('"Smelter\'s Might"', 1, true),
            "Smelter's Might node must exist in tree_2.json")
        assert.is_truthy(treeFile:find("Also Applies To Minions", 1, true),
            "tree_2.json must still carry the ' Also Applies To Minions' follow-up phrase")
    end)
end)
