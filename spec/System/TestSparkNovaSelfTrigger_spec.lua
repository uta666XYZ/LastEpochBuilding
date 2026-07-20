-- @leb-regression-guard:nova-no-self-trigger
-- See REGRESSION_GUARDS.md "nova-no-self-trigger".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a"); f:close()
    return s
end

describe("nova-no-self-trigger (data flag)", function()
    it("SmallLightningNova carries the noSelfTrigger flag and nothing else does", function()
        assert.is_table(data.skills.SmallLightningNova, "SmallLightningNova must exist")
        assert.is_true(data.skills.SmallLightningNova.noSelfTrigger == true,
            "SmallLightningNova must carry noSelfTrigger = true")
        -- Validation provenance is retained in maintainer notes.
        local flagged = {}
        for id, sk in pairs(data.skills) do
            if sk.noSelfTrigger then flagged[#flagged+1] = id end
        end
        table.sort(flagged)
        assert.are.same({ "SmallLightningNova" }, flagged,
            "only SmallLightningNova may carry noSelfTrigger (got: " .. table.concat(flagged, ",") .. ")")
    end)
end)

describe("nova-no-self-trigger (CalcSetup guard)", function()
    local calcSetup = readFile("Modules/CalcSetup.lua")

    it("CalcSetup carries the inline regression-guard marker", function()
        assert.is_truthy(calcSetup:find("@leb%-regression%-guard:nova%-no%-self%-trigger"),
            "inline regression-guard marker must be present in CalcSetup")
    end)

    it("the trigger loop derives the source skill id", function()
        assert.is_truthy(calcSetup:find("local sourceSkillId = activeSkill.activeEffect.grantedEffect.id", 1, true),
            "must derive sourceSkillId from the iterated source skill")
    end)

    it("the grant insertion is gated by the data-driven self-trigger guard", function()
        assert.is_truthy(
            calcSetup:find("not (skillId == sourceSkillId and data.skills[skillId] and data.skills[skillId].noSelfTrigger)", 1, true),
            "the triggered-skill grant must be suppressed when a noSelfTrigger skill would re-trigger itself")
    end)

    it("predicate: a noSelfTrigger skill does NOT self-trigger, but triggers others / is triggered", function()
        local function emits(skillId, sourceSkillId)
            return not (skillId == sourceSkillId and data.skills[skillId] and data.skills[skillId].noSelfTrigger)
        end
        -- Spark Nova must NOT self-trigger
        assert.is_false(emits("SmallLightningNova", "SmallLightningNova"))
        -- Spark Nova STILL triggers other skills (ailments)
        assert.is_true(emits("Ailment_Electrify", "SmallLightningNova"))
        -- Lightning Blast still triggers Spark Nova
        assert.is_true(emits("SmallLightningNova", "LightningBlast"))
        -- a non-flagged skill keeps any self-trigger (e.g. Storm Bolt, Shurikens)
        assert.is_true(emits("PrimalLightning", "PrimalLightning"))
        assert.is_true(emits("Shurikens", "Shurikens"))
    end)
end)

describe("nova-no-self-trigger (Spark Nova chance nodes are not self-scoped)", function()
    it("the Spark Nova chance nodes belong to Lightning Blast's tree / the global tree, not Spark Nova's", function()
        local tree = readFile("TreeData/1_4/tree_1.json")
        assert.is_truthy(tree:find("25%% Spark Nova Chance"),
            "Halo Effect node text must be present (Lightning Blast tree)")
        assert.is_truthy(tree:find("8%% Chance To Cast Spark Nova"),
            "Distant Spark node text must be present (global class tree)")
    end)
end)
