-- @leb-regression-guard:granted-summon-pipeline
-- Validation provenance is retained in maintainer notes.

local function read(path)
    local f = io.open(path, "r")
    assert.is_not_nil(f, "must be able to open " .. path)
    local t = f:read("*a"); f:close()
    return t
end

describe("GrantedSummonPipeline", function()
    it("SubSkillGrants registers the Spriggan Form Healing Totem summon grant", function()
        local t = read("Data/SubSkillGrants.lua")
        assert.is_truthy(string.find(t, 'skillId = "SummonHealingTotem"', 1, true),
            "SprigganForm must grant SummonHealingTotem")
        assert.is_truthy(string.find(t, "summon = true", 1, true), "the grant must be marked summon=true")
        assert.is_truthy(string.find(t, "summonCount = 3", 1, true), "Unbound Garden summons 3")
        assert.is_truthy(string.find(t, 'requiresNode = "sf5rd%-22"'), "summon gated on Unbound Garden sf5rd-22")
        assert.is_truthy(string.find(t, 'grantMinionSkillId = "ThornTotemAttack"', 1, true),
            "Healing Totems cast ThornTotemAttack (Mystic Thorns)")
        assert.is_truthy(string.find(t, 'grantMinionRequiresNode = "sf5rd%-21"'),
            "thorns grant gated on Spiked Totems sf5rd-21")
    end)

    it("grantedSubSkills consumer wires summon grants (includeInFullDPS + fixed count + minion-skill)", function()
        local t = read("Modules/CalcSetup.lua")
        assert.is_truthy(string.find(t, "if grant.summon then", 1, true),
            "consumer must branch on grant.summon")
        assert.is_truthy(string.find(t, "subEntry.autoSummonFixedCount = grant.summonCount", 1, true),
            "fixed pack count carried")
        assert.is_truthy(string.find(t, "subEntry.minionSkillGrant", 1, true),
            "minion-skill grant carried (node-gated)")
        assert.is_truthy(string.find(t, "group.autoSummonFixedCount = grantedSkill.autoSummonFixedCount", 1, true),
            "fixed count carried onto the socket group")
        assert.is_truthy(string.find(t, "group.minionSkillGrant = grantedSkill.minionSkillGrant", 1, true),
            "minion-skill grant carried onto the socket group")
    end)

    it("calcFullDPS honours the fixed pack count", function()
        local t = read("Modules/Calcs.lua")
        assert.is_truthy(string.find(t, "sg.autoSummonFixedCount", 1, true),
            "calcFullDPS must use the fixed pack count for SubSkillGrants summons")
    end)

    it("createMinionSkills applies the socket-group minion-skill grant + replaces", function()
        local t = read("Modules/CalcActiveSkill.lua")
        assert.is_truthy(string.find(t, "activeSkill.socketGroup.minionSkillGrant", 1, true),
            "createMinionSkills must read the socket-group minionSkillGrant")
        -- replaces mechanism: since minion-grant-replacement-in-place, the replacement
        -- grant is placed IN the replaced base skill's kit slot (replacementFor map),
        -- not merely dropped-then-appended (which let an unrelated additive grant win
        -- index 1 alphabetically on an emptied kit -- see that guard).
        assert.is_truthy(string.find(t, "replacementFor", 1, true),
            "the replaces mechanism must be present (grant replaces a base skill)")
        assert.is_truthy(string.find(t, "local replacement = replacementFor[skillId]", 1, true),
            "replaced base skills must be substituted in place by their replacement grant")
        assert.is_truthy(string.find(t, "placedGrants", 1, true),
            "in-kit-placed grants must not be appended a second time")
    end)

    -- @leb-regression-guard:healing-totem-thorn-totem-swap
    -- sf5rd-21 "Thorn Totem Tree Benefits Healing Totems": when allocated the Healing
    -- Totems become Thorn Totems (in-game HT==TT per instance, differ only in count),
    -- so the summon swaps to SummonThornTotem (correct minion prefab / ActorStats /
    -- th39 tree) instead of a weak HealingTotem casting a borrowed skill.
    it("sf5rd-21 swaps the granted summon to the Thorn Totem skill", function()
        local g = read("Data/SubSkillGrants.lua")
        assert.is_truthy(string.find(g, "summonSkillWhenNode", 1, true),
            "the grant must carry a node-gated summon-skill swap")
        assert.is_truthy(string.find(g, 'node = "sf5rd%-21"'), "swap gated on Spiked Totems sf5rd-21")
        assert.is_truthy(string.find(g, 'skillId = "SummonThornTotem"', 1, true),
            "swap target is SummonThornTotem (Thorn Totem minion scaling)")
        local c = read("Modules/CalcSetup.lua")
        assert.is_truthy(string.find(c, "grant.summonSkillWhenNode", 1, true),
            "consumer must honour the node-gated summon-skill swap")
        assert.is_truthy(string.find(c, "subEntry.skillId = grant.summonSkillWhenNode.skillId", 1, true),
            "consumer overrides the summon skillId when the swap node is allocated")
    end)

    -- @leb-regression-guard:thorn-totem-attack-ignores-cast-speed
    -- Totem attacks fire at a fixed prefab interval; general cast speed is NOT applied
    -- (in-game WARRIOR95: 1.6/s despite +124% cast speed). ThornTotemAttack is pinned
    -- to its base cast time, bypassing the spuriously-applied speed.
    it("ThornTotemAttack ignores cast speed (fixed at base cast time)", function()
        local t = read("Modules/CalcActiveSkill.lua")
        assert.is_truthy(string.find(t, 'ge.id == "ThornTotemAttack"', 1, true),
            "the cadence fix must target ThornTotemAttack")
        assert.is_truthy(string.find(t, "ms.skillData.timeOverride = thornAttack.castTime", 1, true),
            "ThornTotemAttack must be pinned to its base cast time")
    end)

    -- @leb-regression-guard:totem-active-count-from-limit
    -- Validation provenance is retained in maintainer notes.
    it("totem active-count uses the totem LIMIT (base + Additional Max Totems), not per-cast count", function()
        local g = read("Data/SubSkillGrants.lua")
        assert.is_truthy(string.find(g, 'summonActiveCountNode = "sf5rd%-22"'),
            "the Healing Totem grant must carry the totem-limit node")
        assert.is_truthy(string.find(g, "summonActiveCountBase = 2", 1, true),
            "baseTotemLimit = 2 (game-source, datamined ThornTotemMutator)")
        assert.is_truthy(string.find(g, "summonActiveCountPerPoint = 1", 1, true),
            "+1 Additional Max Totems per allocated point (sf5rd-22 stats)")

        local c = read("Modules/CalcSetup.lua")
        assert.is_truthy(string.find(c, "grant.summonActiveCountNode and env.allocNodes", 1, true),
            "CalcSetup must compute the cap from the limit node when present")
        assert.is_truthy(string.find(c, "limitNode.alloc or 0) * (grant.summonActiveCountPerPoint", 1, true),
            "cap = base + node.alloc x perPoint (reads the allocated point count)")
    end)
end)
