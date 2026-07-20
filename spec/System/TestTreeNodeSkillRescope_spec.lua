-- @leb-regression-guard:tree-node-skill-rescope
-- See REGRESSION_GUARDS.md > "tree-node-skill-rescope".
-- Validation provenance is retained in maintainer notes.

local function findTag(mod, tagType)
    for _, tag in ipairs(mod) do
        if tag.type == tagType then return tag end
    end
end

-- Process a REAL tree node at a given rank and hand back its modList.
-- Snapshots/restores node.alloc so the shared tree object stays pristine
-- for other specs (ProcessStats fully rebuilds node state on each call).
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

local function dbWithMods(mods, currentMana)
    local db = new("ModDB")
    db.actor = { output = { CurrentMana = currentMana or 0 }, modDB = db }
    for _, m in ipairs(mods) do
        db:AddMod(m)
    end
    return db
end

describe("TreeNodeSkillRescope", function()
    before_each(function()
        newBuild()
    end)

    -- ---- registry / tagging layer ----

    it("ga2st-14 Excited Bolts is re-tagged to PrimalLightning (live tree data)", function()
        local mods = processRealNode("ga2st-14", 1)
        local found
        for _, m in ipairs(mods) do
            if m.name == "Damage" and m.type == "MORE" then found = m end
        end
        assert.is_not_nil(found, "Excited Bolts must emit its Damage MORE")
        local perStat = findTag(found, "PerStat")
        assert.is_not_nil(perStat)
        assert.are.equals("CurrentMana", perStat.stat)
        local skillTag = findTag(found, "SkillId")
        assert.is_not_nil(skillTag)
        assert.are.equals("PrimalLightning", skillTag.skillId,
            "Excited Bolts targets the shared Storm Bolt ability, not the melee attack")
        assert.is_nil(skillTag.skillIdList)
    end)

    it("ga2st-13 Thunderous Strikes pen targets BOTH GS and Storm Bolt (live tree data)", function()
        local mods = processRealNode("ga2st-13", 4)
        local found
        for _, m in ipairs(mods) do
            if m.name == "LightningPenetration" and m.type == "BASE" then found = m end
        end
        assert.is_not_nil(found, "Thunderous Strikes must emit LightningPenetration")
        assert.are.equals(40, found.value, "rank 4 scales +10% per point to +40%")
        local skillTag = findTag(found, "SkillId")
        assert.is_not_nil(skillTag)
        assert.is_not_nil(skillTag.skillIdList, "pen applies to the attack AND every bolt instance")
        assert.are.same({ "GatheringStormMelee", "PrimalLightning" }, skillTag.skillIdList)
    end)

    it("ga2st-3 Concentrated Storm keeps GS scope but is flagged directOnly (live tree data)", function()
        local mods = processRealNode("ga2st-3", 3)
        local found
        for _, m in ipairs(mods) do
            if m.name == "Damage" and m.type == "MORE" then found = m end
        end
        assert.is_not_nil(found, "Concentrated Storm must emit its Damage MORE")
        assert.are.equals(24, found.value, "rank 3 scales +8% per point to +24%")
        local skillTag = findTag(found, "SkillId")
        assert.is_not_nil(skillTag)
        assert.are.equals("GatheringStormMelee", skillTag.skillId)
        assert.is_true(skillTag.directOnly == true,
            "'Gathering Storm deals more damage' must not flow to triggered Storm Bolts")
    end)

    it("nodes without a rescope entry keep the default tree-skill tag", function()
        -- ga2st-16 Windfury Blows "+5% Attack Speed" parses residue-free
        -- (unlike ga2st-22, whose shock-chance string drops on extra residue),
        -- so it pins the unrescoped default tagging path.
        local mods = processRealNode("ga2st-16", 3)
        local found
        for _, m in ipairs(mods) do
            local skillTag = findTag(m, "SkillId")
            if skillTag then found = skillTag end
        end
        assert.is_not_nil(found, "ga2st-16 mods still carry a SkillId tag")
        assert.are.equals("GatheringStormMelee", found.skillId)
        assert.is_nil(found.directOnly)
    end)

    it("lb23il-26 Mortal Capacitor is re-tagged to SparkChargeExplosion (live tree data)", function()
        -- "+40% Spark Charge Damage" lives in the Lightning Blast tree, so the
        -- default tag would be skillId=LightningBlast -- which fails the
        -- SparkChargeExplosion detonation's groupSource (SkillId:Ailment_SparkCharge)
        -- and DROPS this legit Spark-Charge MORE. Rescope to SparkChargeExplosion.
        local mods = processRealNode("lb23il-26", 5)
        local found
        for _, m in ipairs(mods) do
            if m.name == "Damage" and m.type == "MORE" then found = m end
        end
        assert.is_not_nil(found, "Mortal Capacitor must emit its Spark Charge Damage MORE")
        assert.are.equals(200, found.value, "rank 5 scales +40% per point to +200%")
        local skillTag = findTag(found, "SkillId")
        assert.is_not_nil(skillTag)
        assert.are.equals("SparkChargeExplosion", skillTag.skillId,
            "rescoped off the owning Lightning Blast tree onto the detonation")
        assert.is_nil(skillTag.skillIdList)
        local nameTag = findTag(found, "SkillName")
        assert.is_not_nil(nameTag, "the Spark-Charge skillName tag must remain (gates it out of Lightning Blast)")
        assert.are.equals("spark charge", nameTag.skillName:lower())
    end)

    it("ch4bo-2 Sanguine Reverie keeps Chaos Bolts scope but is flagged directOnly (live tree data)", function()
        -- "Chaos Bolts' base necrotic damage is converted to physical" -- the
        -- conversion belongs to Chaos Bolts ONLY, but PassiveTree tags it with the
        -- owning tree's skill (Warlock 01 Chaos Bolts) and the groupSource channel
        -- then leaked it onto group-mate skills (Damned/Bleed/Ignite/Harvest/Rip
        -- Blood). directOnly keeps the Chaos Bolts scope but suppresses groupSource.
        local mods = processRealNode("ch4bo-2", 1)
        local found
        for _, m in ipairs(mods) do
            if m.name == "NecroticDamageConvertToPhysical" and m.type == "BASE" then found = m end
        end
        assert.is_not_nil(found, "Sanguine Reverie must emit its Necrotic->Physical conversion")
        assert.are.equals(100, found.value, "full base conversion")
        local skillTag = findTag(found, "SkillId")
        assert.is_not_nil(skillTag)
        assert.are.equals("Warlock 01 Chaos Bolts", skillTag.skillId)
        assert.is_true(skillTag.directOnly == true,
            "'Chaos Bolts' base necrotic damage' must not flow to group-mate skills")
    end)

    it("ch4bo-13 Call of Morditas keeps Chaos Bolts scope but is flagged directOnly (live tree data)", function()
        -- "Chaos Bolts' base fire damage is converted to cold ... Swaps Chaos Bolts'
        -- Fire tag for a Cold tag" -- same Chaos-Bolts-only pattern as ch4bo-2.
        local mods = processRealNode("ch4bo-13", 1)
        local found
        for _, m in ipairs(mods) do
            if m.name == "FireDamageConvertToCold" and m.type == "BASE" then found = m end
        end
        assert.is_not_nil(found, "Call of Morditas must emit its Fire->Cold conversion")
        assert.are.equals(100, found.value, "full base conversion")
        local skillTag = findTag(found, "SkillId")
        assert.is_not_nil(skillTag)
        assert.are.equals("Warlock 01 Chaos Bolts", skillTag.skillId)
        assert.is_true(skillTag.directOnly == true,
            "'Chaos Bolts' base fire damage' must not flow to group-mate skills/ailments")
    end)

    -- ---- ModStore gate layer (end-to-end through ModDB) ----

    it("re-tagged Excited Bolts reaches EVERY Storm Bolt instance but not the GS attack", function()
        local db = dbWithMods(processRealNode("ga2st-14", 1), 711)
        local boltDirect = { skillGrantedEffect = { id = "PrimalLightning" } }
        local boltFromMaelstrom = { skillGrantedEffect = { id = "PrimalLightning" }, groupSource = "SkillId:Maelstrom" }
        local boltFromGS = { skillGrantedEffect = { id = "PrimalLightning" }, groupSource = "SkillId:GatheringStormMelee" }
        local gsAttack = { skillGrantedEffect = { id = "GatheringStormMelee" } }
        assert.are.equals(3.13, round(db:More(boltDirect, "Damage"), 2))
        assert.are.equals(3.13, round(db:More(boltFromMaelstrom, "Damage"), 2),
            "non-GS-triggered Storm Bolt must receive the mana MORE (Gap A)")
        assert.are.equals(3.13, round(db:More(boltFromGS, "Damage"), 2))
        assert.are.equals(1, db:More(gsAttack, "Damage"),
            "the melee attack itself must NOT carry '{Storm Bolts} now consume...'")
    end)

    it("directOnly Concentrated Storm stays on the GS attack and off triggered bolts", function()
        local db = dbWithMods(processRealNode("ga2st-3", 3))
        local gsAttack = { skillGrantedEffect = { id = "GatheringStormMelee" } }
        local boltFromGS = { skillGrantedEffect = { id = "PrimalLightning" }, groupSource = "SkillId:GatheringStormMelee" }
        assert.are.equals(1.24, round(db:More(gsAttack, "Damage"), 2),
            "GS keeps its own x1.24 MORE")
        assert.are.equals(1, db:More(boltFromGS, "Damage"),
            "the groupSource channel must not deliver a directOnly mod")
    end)

    it("skillIdList pen applies via either skill id and via the trigger channel", function()
        local db = dbWithMods(processRealNode("ga2st-13", 4))
        local gsAttack = { skillGrantedEffect = { id = "GatheringStormMelee" } }
        local boltFromEterra = { skillGrantedEffect = { id = "PrimalLightning" }, groupSource = "SkillId:Eterras Blessing" }
        local unrelated = { skillGrantedEffect = { id = "Maelstrom" } }
        assert.are.equals(40, db:Sum("BASE", gsAttack, "LightningPenetration"))
        assert.are.equals(40, db:Sum("BASE", boltFromEterra, "LightningPenetration"),
            "every Storm Bolt instance penetrates (in-game pen canary 0.48 uniform)")
        assert.are.equals(0, db:Sum("BASE", unrelated, "LightningPenetration"))
    end)

    it("rescoped Mortal Capacitor reaches the SparkChargeExplosion detonation but not Lightning Blast", function()
        local db = dbWithMods(processRealNode("lb23il-26", 5))
        local detonation = { skillGrantedEffect = { id = "SparkChargeExplosion" }, skillName = "Spark Charge", groupSource = "SkillId:Ailment_SparkCharge" }
        local lightningBlast = { skillGrantedEffect = { id = "LightningBlast" }, skillName = "Lightning Blast" }
        assert.are.equals(3, round(db:More(detonation, "Damage"), 2),
            "+200% Spark Charge Damage (x3.0) reaches the detonation via skillId + skillName match")
        assert.are.equals(1, db:More(lightningBlast, "Damage"),
            "skillName='Spark Charge' still gates the node OUT of Lightning Blast (no LB regression)")
    end)

    it("directOnly Sanguine Reverie converts Chaos Bolts but not its group-mate skills", function()
        -- Validation provenance is retained in maintainer notes.
        local db = dbWithMods(processRealNode("ch4bo-2", 1))
        local chaosBolts = { skillGrantedEffect = { id = "Warlock 01 Chaos Bolts" }, skillName = "Chaos Bolts" }
        local harvestInGroup = { skillGrantedEffect = { id = "Harvest" }, skillName = "Harvest", groupSource = "SkillId:Warlock 01 Chaos Bolts" }
        local damnedInGroup = { skillGrantedEffect = { id = "Ailment_Damned" }, skillName = "Damned", groupSource = "SkillId:Warlock 01 Chaos Bolts" }
        assert.are.equals(100, db:Sum("BASE", chaosBolts, "NecroticDamageConvertToPhysical"),
            "Chaos Bolts keeps its own necrotic->physical conversion")
        assert.are.equals(0, db:Sum("BASE", harvestInGroup, "NecroticDamageConvertToPhysical"),
            "group-mate Harvest must not receive Chaos Bolts' conversion (in-game: Harvest stays necrotic)")
        assert.are.equals(0, db:Sum("BASE", damnedInGroup, "NecroticDamageConvertToPhysical"),
            "group-mate Damned ailment must not flip to physical via the groupSource channel")
    end)

    it("directOnly Call of Morditas converts Chaos Bolts but not its group-mate Ignite ailment", function()
        -- Corpus build Warlo lv82 Warlock (main = Chaos Bolts) carried "Ignite (from
        -- Chaos Bolts)" whose base fire was wrongly converted to cold by this node via
        -- the groupSource channel. In-game (Sanguine Reverie A/B, _06 capture) Chaos
        -- Bolts' own Ignite stayed FIRE under a hit conversion -> hit conversions do
        -- not convert the ailment's damage. So the Ignite must keep its fire.
        local db = dbWithMods(processRealNode("ch4bo-13", 1))
        local chaosBolts = { skillGrantedEffect = { id = "Warlock 01 Chaos Bolts" }, skillName = "Chaos Bolts" }
        local igniteInGroup = { skillGrantedEffect = { id = "Ailment_Ignite" }, skillName = "Ignite", groupSource = "SkillId:Warlock 01 Chaos Bolts" }
        assert.are.equals(100, db:Sum("BASE", chaosBolts, "FireDamageConvertToCold"),
            "Chaos Bolts keeps its own fire->cold hit conversion")
        assert.are.equals(0, db:Sum("BASE", igniteInGroup, "FireDamageConvertToCold"),
            "the Chaos Bolts Ignite ailment must not inherit the hit's fire->cold conversion")
    end)

    it("plain single-id SkillId tags behave exactly as before (regression control)", function()
        local db = new("ModDB")
        db.actor = { output = { }, modDB = db }
        db:NewMod("Damage", "INC", 50, "Control", { type = "SkillId", skillId = "SomeSkill" })
        assert.are.equals(50, db:Sum("INC", { skillGrantedEffect = { id = "SomeSkill" } }, "Damage"))
        assert.are.equals(50, db:Sum("INC", { skillGrantedEffect = { id = "Other" }, groupSource = "SkillId:SomeSkill" }, "Damage"),
            "groupSource trigger channel still delivers non-directOnly mods")
        assert.are.equals(0, db:Sum("INC", { skillGrantedEffect = { id = "Other" } }, "Damage"))
        assert.are.equals(0, db:Sum("INC", nil, "Damage"), "no cfg still gates the mod off")
    end)
end)
