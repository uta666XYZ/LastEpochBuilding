-- @leb-regression-guard:singular-purpose-low-block-double
-- Validation provenance is retained in maintainer notes.

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("SingularPurposeLowBlock", function()
    before_each(function()
        newBuild()
    end)

    it("tree_2.json still carries the display string AND the doubling clause", function()
        local tree = readSource("TreeData/1_4/tree_2.json")
        assert.is_truthy(tree:find('"Sentinel%-61"'), "node present")
        assert.is_truthy(tree:find('2%% More Void Damage', 1, false), "per-point display string")
        assert.is_truthy(tree:find('doubled if you have less than 30%% block chance', 1, false),
            "the doubling clause must still exist in the node description -- if LE " ..
            "re-tunes it, RE-MEASURE the 0.20 anchor before touching this model")
    end)

    it("LE_TREE_NODE_STAT_REWRITE blanks the tree line (granted in CalcPerform instead)", function()
        local rw = LE_TREE_NODE_STAT_REWRITE["Sentinel-61"]
        assert.is_not_nil(rw, "rewrite registered")
        assert.are.equals("", rw[1].repl, "line blanked -- the mod is code-granted with the block gate")
    end)

    it("ProcessStats at rank 5 yields NO VoidDamage mod from the tree", function()
        local spec = build.spec
        local node = spec.nodes["Sentinel-61"]
        assert.is_not_nil(node, "Sentinel-61 must exist in the loaded tree")
        node.alloc = 5
        spec.tree:ProcessStats(node)
        for _, mod in ipairs(node.modList or { }) do
            assert.is_not.equals("VoidDamage", mod.name,
                "the tree line must stay blanked; a tree-side MORE would stack " ..
                "multiplicatively with the code grant (x1.21+ instead of x1.20)")
        end
    end)

    it("CalcPerform grants ONE value-doubled MORE gated on computed block chance", function()
        local src = readSource("Modules/CalcPerform.lua")
        local block = src:match("singular%-purpose%-low%-block%-double.-\n\tlocal s61.-SingularPurpose\"%)")
        assert.is_not_nil(block, "grant block must exist after calcs.defence")
        assert.is_truthy(block:find('env.allocNodes and env.allocNodes["Sentinel-61"]', 1, true), "node-gated")
        assert.is_truthy(block:find('env.player.output.BlockChanceTotal or env.player.output.BlockChance or 0', 1, true),
            "gate reads the raw computed block chance (post-calcs.defence)")
        assert.is_truthy(block:find('blockChance < 30', 1, true), "threshold 30")
        assert.is_truthy(block:find('2 * (s61.alloc or 0) * (double and 2 or 1)', 1, true),
            "VALUE doubling of one mod (2%/pt, x2 under 30%% block) -- never two stacked MOREs")
        local defencePos = src:find("calcs.defence(env, env.player)", 1, true)
        local grantPos = src:find("SingularPurpose\")", 1, true)
        assert.is_true(defencePos < grantPos, "grant must run AFTER calcs.defence (block chance must be final)")
    end)

    it("ModDB semantics: one MORE 20 = x1.20 exactly (two 10s would be x1.21)", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        db:NewMod("VoidDamage", "MORE", 20, "SingularPurpose")
        assert.are.equals(1.2, db:More(nil, "VoidDamage"), "single value-doubled mod")
        local db2 = new("ModDB")
        db2.actor = { output = {}, modDB = db2 }
        db2:NewMod("VoidDamage", "MORE", 10, "A")
        db2:NewMod("VoidDamage", "MORE", 10, "B")
        assert.is_true(math.abs(db2:More(nil, "VoidDamage") - 1.21) < 1e-9,
            "stacked MOREs compound -- this is the WRONG shape the engine refutes")
    end)
end)
