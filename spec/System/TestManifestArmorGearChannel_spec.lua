-- @leb-regression-guard:manifest-armor-redistributed-steel-7pct
-- @leb-regression-guard:manifest-armor-weapon-stats-copy
-- @leb-regression-guard:manifest-armor-armor-slot-copy
-- See REGRESSION_GUARDS.md and memory project_minion_ailment_unmodeled_and_idol_decode.
-- Validation provenance is retained in maintainer notes.

local function readSrc(rel)
    local f = io.open(rel, "r") or io.open("src/" .. rel, "r")
    assert.is_not_nil(f, rel .. " must be readable")
    local s = f:read("*a"); f:close()
    return s
end

describe("ManifestArmorGearChannel", function()
    before_each(function()
        newBuild()
    end)

    -- ---- tree-data pins: the raw display strings this model retunes ----

    it("tree_2.json still carries the display strings the rewrites target", function()
        local tree = readSrc("TreeData/1_4/tree_2.json")
        assert.is_truthy(tree:find('"ma6hdr%-25"'), "Redistributed Steel node present")
        assert.is_truthy(tree:find('%+15%% Damage', 1, false),
            "ma6hdr-25 display stat is '+15% Damage' -- if LE re-tunes this, RE-MEASURE " ..
            "the x1.28 anchor before touching the 7%/pt rewrite")
        assert.is_truthy(tree:find('%+40%% Stats From Armor', 1, false),
            "ma6hdr-1 Platemail display stat present")
        assert.is_truthy(tree:find(' Equip Sword', 1, true), "ma6hdr-26 Titan Sword stat present")
        assert.is_truthy(tree:find(' Equip Shield', 1, true), "ma6hdr-4 Shield-Bearer stat present")
    end)

    -- ---- registry pins ----

    it("LE_TREE_NODE_STAT_REWRITE carries the ma6hdr-25 and ma6hdr-1 entries", function()
        local rs = LE_TREE_NODE_STAT_REWRITE["ma6hdr-25"]
        assert.is_not_nil(rs, "Redistributed Steel rewrite registered")
        assert.are.equals("7%% more Damage", rs[1].repl,
            "the engine-measured per-point value is 7 (x1.2800 EXACT at rank 4 in two " ..
            "independent channels) -- do NOT restore the tooltip 15")
        local pm = LE_TREE_NODE_STAT_REWRITE["ma6hdr-1"]
        assert.is_not_nil(pm, "Platemail phantom-armor rewrite registered")
        assert.are.equals("", pm[1].repl, "Platemail line is blanked (scalar, not a stat)")
    end)

    -- ---- live tree contract: ProcessStats at rank 4 ----

    it("ma6hdr-25 at rank 4 yields Damage MORE 28 (not BASE, not 60) and keeps the armor downside", function()
        local spec = build.spec
        local node = spec.nodes["ma6hdr-25"]
        assert.is_not_nil(node, "ma6hdr-25 must exist in the loaded tree")
        node.alloc = 4
        spec.tree:ProcessStats(node)
        local foundMore, foundArmour = nil, nil
        for _, mod in ipairs(node.modList) do
            if mod.name == "Damage" then
                assert.are.equals("MORE", mod.type,
                    "the rewritten line must parse as MORE (a bare rank-scaled '+28% Damage' " ..
                    "live-parses as BASE; the rewrite must keep the explicit 'more' keyword)")
                foundMore = mod.value
            elseif mod.name == "Armour" then
                foundArmour = mod.value
            end
        end
        assert.are.equals(28, foundMore, "rank 4 = 7 x 4 = 28% more")
        assert.are.equals(-24, foundArmour, "the -6%/pt armor downside still parses")
    end)

    it("ma6hdr-1 Platemail at rank 4 yields NO phantom Armour BASE mod", function()
        local spec = build.spec
        local node = spec.nodes["ma6hdr-1"]
        assert.is_not_nil(node, "ma6hdr-1 must exist in the loaded tree")
        node.alloc = 4
        spec.tree:ProcessStats(node)
        for _, mod in ipairs(node.modList) do
            assert.is_not.equals("Armour", mod.name,
                "Platemail is a stat-copy scalar; 'Armour BASE 160' was a parse phantom")
        end
    end)

    -- ---- parse contract for the rewritten string at every measured rank ----

    it("the rewritten per-point string parses cleanly at ranks 1-4", function()
        for rank = 1, 4 do
            local list, extra = modLib.parseMod(tostring(7 * rank) .. "% more Damage")
            assert.is_true(extra == nil or extra == "", "no residue at rank " .. rank)
            assert.are.equals("Damage", list[1].name)
            assert.are.equals("MORE", list[1].type)
            assert.are.equals(7 * rank, list[1].value)
        end
    end)

    -- ---- source pins: the CalcPerform copy block ----

    it("CalcPerform carries the node-gated numeric-only gear copy", function()
        local src = readSrc("Modules/CalcPerform.lua")
        local block = src:match("manifest%-armor%-weapon%-stats%-copy.-\n\t\t%-%- @leb%-regression%-guard:weapon%-attack")
        assert.is_not_nil(block, "the copy block must sit before the Ballista inheritance block")
        assert.is_truthy(block:find('env.minion.type == "ManifestedArmor"', 1, true),
            "scoped to the Manifest Armor minion only")
        assert.is_truthy(block:find('env.allocNodes["ma6hdr-26"]', 1, true), "weapon copy gated on Titan Sword")
        assert.is_truthy(block:find('env.allocNodes["ma6hdr-4"]', 1, true), "shield copy gated on Shield-Bearer")
        assert.is_truthy(block:find('w2.base.type == "Shield"', 1, true),
            "shield path requires an actual shield in Weapon 2")
        assert.is_truthy(block:find('(mod.type == "BASE" or mod.type == "INC" or mod.type == "MORE") and type(mod.value) == "number"', 1, true),
            "only plain numeric stats transfer -- LIST (MinionModifier wrappers, already " ..
            "player-delivered) and FLAG mods must NOT be copied")
        assert.is_truthy(block:find('ManifestArmorGearCopy', 1, true), "copy source is labeled")
    end)

    -- ---- ModDB contract: what the copied weapon implicit does on the minion ----

    it("the copied Bone-Scythe-style implicit lands as melee-flagged added Damage on a minion ModDB", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        -- "+113 Melee Damage" parses to Damage BASE 113 kw=Melee (ModCache-verified)
        db:NewMod("Damage", "BASE", 113, "ManifestArmorGearCopy:Weapon 1", 0, KeywordFlag.Melee)
        local meleeCfg = { keywordFlags = KeywordFlag.Melee }
        assert.are.equals(113, db:Sum("BASE", meleeCfg, "Damage"),
            "a melee attack cfg must see the copied weapon flat")
    end)

    -- Validation provenance is retained in maintainer notes.

    it("tree_2.json still carries the three slot-node display strings", function()
        local tree = readSrc("TreeData/1_4/tree_2.json")
        assert.is_truthy(tree:find('%+60%% Stats From Helmet', 1, false), "ma6hdr-9 Great Helm")
        assert.is_truthy(tree:find('%+60%% Stats From Boots', 1, false), "ma6hdr-16 Steel Greaves")
        assert.is_truthy(tree:find('%+60%% Gloves Stats', 1, false), "ma6hdr-21 Iron Grasp")
    end)

    it("the three slot-node strings stay parse-inert (no phantom mods at any rank)", function()
        local spec = build.spec
        for _, id in ipairs({ "ma6hdr-9", "ma6hdr-16", "ma6hdr-21" }) do
            local node = spec.nodes[id]
            assert.is_not_nil(node, id .. " must exist in the loaded tree")
            node.alloc = 4
            spec.tree:ProcessStats(node)
            assert.are.equals(0, #(node.modList or { }),
                id .. " is a stat-copy scalar handled in CalcPerform; if the parser " ..
                "starts recognising its display string, blank it via LE_TREE_NODE_STAT_REWRITE " ..
                "like ma6hdr-1 Platemail")
        end
    end)

    it("CalcPerform carries the armour-slot copy with the measured multipliers", function()
        local src = readSrc("Modules/CalcPerform.lua")
        local block = src:match("manifest%-armor%-armor%-slot%-copy.-\n\t\t%-%- @leb%-regression%-guard:weapon%-attack")
        assert.is_not_nil(block, "the armour-slot copy block must sit in the MA copy section")
        assert.is_truthy(block:find('{ slot = "Helmet",     node = "ma6hdr%-9",  perPoint = 0.60 }'),
            "helmet multiplier 60%/pt (Great Helm)")
        assert.is_truthy(block:find('{ slot = "Body Armor", node = "ma6hdr%-1",  perPoint = 0.40 }'),
            "chest multiplier 40%/pt (Platemail)")
        assert.is_truthy(block:find('{ slot = "Boots",      node = "ma6hdr%-16", perPoint = 0.60 }'),
            "boots multiplier 60%/pt (Steel Greaves)")
        assert.is_truthy(block:find('{ slot = "Gloves",     node = "ma6hdr%-21", perPoint = 0.60 }'),
            "gloves multiplier 60%/pt (Iron Grasp) -- CADENCE-VALIDATED, do not halve " ..
            "by analogy with Redistributed Steel")
        assert.is_truthy(block:find("newMod.value = mod.value * entry.mult", 1, true),
            "the multiplier scales the copied VALUE (engine scales Stat.value)")
        assert.is_truthy(block:find("1 + (node and (node.alloc or 0) or 0) * def.perPoint", 1, true),
            "unallocated slot nodes leave the base-kit x1.0 copy in place (NOT a gate)")
    end)

    -- ==== phase 3: Force of Impact + Lambent Metal (banked residuals) ====

    it("tree_2.json still carries the Force of Impact / Lambent Metal display strings", function()
        local tree = readSrc("TreeData/1_4/tree_2.json")
        assert.is_truthy(tree:find('1 Melee Physical Damage per 10 Armor On Chest', 1, true), "ma6hdr-2")
        assert.is_truthy(tree:find('50%% Increased Effect From Health Regeneration', 1, false), "ma6hdr-6")
    end)

    it("ma6hdr-2 and ma6hdr-6 strings stay parse-inert (handled in CalcPerform, not as stats)", function()
        local spec = build.spec
        for _, id in ipairs({ "ma6hdr-2", "ma6hdr-6" }) do
            local node = spec.nodes[id]
            assert.is_not_nil(node, id .. " must exist in the loaded tree")
            node.alloc = 1
            spec.tree:ProcessStats(node)
            assert.are.equals(0, #(node.modList or { }),
                id .. " must yield no phantom mods (both strings parse with residue and drop; " ..
                "if the parser starts recognising them, blank via LE_TREE_NODE_STAT_REWRITE)")
        end
    end)

    it("CalcPerform carries Force of Impact (chest flat armour x 0.1 as melee phys)", function()
        local src = readSrc("Modules/CalcPerform.lua")
        local block = src:match("manifest%-armor%-force%-of%-impact.-\n\t\t%-%- @leb%-regression%-guard:weapon%-attack")
        assert.is_not_nil(block, "Force of Impact block must sit in the MA section")
        assert.is_truthy(block:find('env.allocNodes["ma6hdr-2"]', 1, true), "gated on the node")
        assert.is_truthy(block:find('mod.name == "Armour" and mod.type == "BASE"', 1, true),
            "FLAT armour entries only -- the item's own '%% increased Armor' lines are a " ..
            "different engine property and must NOT feed this")
        assert.is_truthy(block:find('flatArmour * 0.1', 1, true), "1 per 10 armor")
        assert.is_truthy(block:find('"ManifestArmorForceOfImpact", 0, KeywordFlag.Melee', 1, true),
            "lands as melee-kw PhysicalDamage BASE")
    end)

    it("CalcPerform carries Lambent Metal (copied flat LifeRegen x1.5)", function()
        local src = readSrc("Modules/CalcPerform.lua")
        local block = src:match("manifest%-armor%-lambent%-metal.-ManifestArmorGearCopy")
        assert.is_not_nil(block, "Lambent Metal block must sit before the copy loop")
        assert.is_truthy(block:find('env.allocNodes["ma6hdr-6"]', 1, true), "reads the node rank")
        assert.is_truthy(block:find('mod.name == "LifeRegen" and mod.type == "BASE"', 1, true),
            "applies to copied FLAT regen only (engine GetPropertySpecificMultiplier is " ..
            "property-17-scoped); %% increased regen must NOT get the extra multiplier")
    end)

    it("a copied throwing-speed affix stays invisible to the minion melee attack", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        -- Immortal Vise carries BOTH "+29% Throwing Attack Speed" (kw=1024) and
        -- "+15% Melee Attack Speed" (kw=512); only the melee one may drive
        -- the MA melee cadence (this is what makes the 0.75s fit unambiguous)
        db:NewMod("Speed", "INC", 98.6, "ManifestArmorGearCopy:Gloves", ModFlag.Attack, KeywordFlag.Throwing)
        db:NewMod("Speed", "INC", 51, "ManifestArmorGearCopy:Gloves", ModFlag.Attack, KeywordFlag.Melee)
        local meleeCfg = { flags = ModFlag.Attack, keywordFlags = KeywordFlag.Melee }
        assert.are.equals(51, db:Sum("INC", meleeCfg, "Speed"),
            "melee attack cfg must see only the melee-kw speed")
    end)
end)
