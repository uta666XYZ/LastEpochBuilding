-- @leb-regression-guard:minion-aura-player-application
-- documented follow-up. See REGRESSION_GUARDS.md > "minion-aura-player-application".
-- Validation provenance is retained in maintainer notes.

local function findTag(mod, tagType)
    for _, tag in ipairs(mod) do
        if tag.type == tagType then return tag end
    end
end

-- Process a REAL tree node at a given rank and return its modList. Snapshots and
-- restores node.alloc so the shared tree object stays pristine for other specs.
local function processRealNode(nodeId, rank)
    local node = build.spec.tree.nodes[nodeId]
    assert.is_not_nil(node, "tree node " .. nodeId .. " must exist in 1_4 tree data")
    local origAlloc = node.alloc
    node.alloc = rank
    build.spec.tree:ProcessStats(node)
    local mods = node.modList
    node.alloc = origAlloc
    if type(origAlloc) == "number" then
        build.spec.tree:ProcessStats(node)
    end
    return mods
end

local function addedSpellDamage(mods)
    for _, m in ipairs(mods) do
        if m.name == "Damage" and m.type == "BASE" then return m end
    end
end

describe("MinionAuraPlayerApplication", function()
    before_each(function()
        newBuild()
    end)

    -- ---- registry / game-data pin ----

    it("sp38-13 is 'Aura of Kinship' carrying '+5 Spell Damage' (live tree data)", function()
        local node = build.spec.tree.nodes["sp38-13"]
        assert.is_not_nil(node, "sp38-13 must exist in 1_4 tree data")
        assert.are.equals("Aura of Kinship", node.name)
        local hasStat = false
        for _, s in ipairs(node.stats or {}) do
            if s == "+5 Spell Damage" then hasStat = true end
        end
        assert.is_true(hasStat, "sp38-13 must carry the '+5 Spell Damage' stat (game property 41, +5/pt)")
    end)

    it("registry maps sp38-13 -> InSprigganHealingAura", function()
        assert.are.equals("InSprigganHealingAura", LE_MINION_AURA_PLAYER_NODES["sp38-13"])
    end)

    -- ---- tagging layer ----

    it("sp38-13 is lifted to the player (no SkillId) and gated by the aura Condition", function()
        local mod = addedSpellDamage(processRealNode("sp38-13", 2))
        assert.is_not_nil(mod, "Aura of Kinship must emit an added-spell Damage BASE mod")
        assert.are.equals(10, mod.value, "rank 2 scales +5/pt to +10")
        assert.is_truthy(bit.band(mod.keywordFlags or 0, KeywordFlag.Spell) ~= 0,
            "must be added SPELL damage (folds into the skill's native type via effectiveness)")
        assert.is_nil(findTag(mod, "SkillId"),
            "aura node mods reach the PLAYER sheet -> no SkillId:SummonSpriggan scope")
        local cond = findTag(mod, "Condition")
        assert.is_not_nil(cond, "aura node mods must be gated by the proximity Condition")
        assert.are.equals("InSprigganHealingAura", cond.var)
    end)

    it("Aura of Kinship scales with allocated points (rank 3 -> +15, the SuXes case)", function()
        local mod = addedSpellDamage(processRealNode("sp38-13", 3))
        assert.is_not_nil(mod)
        assert.are.equals(15, mod.value)
    end)

    -- ---- control: a NON-aura sp38 node keeps the minion scope ----

    it("sp38-7 Floral Ascendance (the Spriggan's OWN spell damage) keeps SkillId:SummonSpriggan", function()
        -- "+12% Spell Damage" described "Your Spriggan deals more spell damage" — the
        -- minion's own buff, must NOT be lifted to the player.
        local mods = processRealNode("sp38-7", 1)
        local skillTag
        for _, m in ipairs(mods) do
            local st = findTag(m, "SkillId")
            if st then skillTag = st end
        end
        assert.is_not_nil(skillTag, "non-aura sp38 nodes still scope to the minion skill")
        assert.are.equals("SummonSpriggan", skillTag.skillId)
        assert.is_nil(LE_MINION_AURA_PLAYER_NODES["sp38-7"], "sp38-7 is NOT a registered ally-aura node")
    end)

    -- ---- end-to-end through ModDB: Condition gates the player buff ----

    it("Aura of Kinship adds +10 to a player spell ONLY while inside the aura", function()
        local db = new("ModDB")
        db.actor = { output = {}, modDB = db }
        for _, m in ipairs(processRealNode("sp38-13", 2)) do db:AddMod(m) end
        local cfg = { skillGrantedEffect = { id = "SpiritThorns" }, keywordFlags = KeywordFlag.Spell }
        assert.are.equals(0, db:Sum("BASE", cfg, "Damage"), "aura OFF -> no contribution")
        db.conditions["InSprigganHealingAura"] = true
        assert.are.equals(10, db:Sum("BASE", cfg, "Damage"), "aura ON -> +10 added spell damage")
    end)

    -- ---- config toggle source pin ----

    it("ConfigOptions exposes the proximity toggle that sets the Condition", function()
        local f = assert(io.open("Modules/ConfigOptions.lua", "r"))
        local src = f:read("*a"); f:close()
        assert.is_truthy(src:find('var = "conditionInSprigganHealingAura"', 1, true),
            "ConfigOptions must declare the conditionInSprigganHealingAura toggle")
        assert.is_truthy(src:find("Condition:InSprigganHealingAura", 1, true),
            "the toggle's apply must set Condition:InSprigganHealingAura")
    end)
end)
