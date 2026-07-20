-- @leb-regression-guard:skill-mana-cost-data
-- Validation provenance is retained in maintainer notes.

describe("skill base Mana cost data (datamine-grounded)", function()
    it("Forge Strike base Mana cost = 25 (Property_650 Brutality MORE prerequisite)", function()
        local d = data.skills.ForgeStrike
        assert.is_table(d.stats.cost, "ForgeStrike must have stats.cost")
        assert.are.equals(25, d.stats.cost.Mana)
    end)
    it("Smelter's Wrath base Mana cost = 30 (player 'SmeltersWrath' prefab, NOT enemy 35)", function()
        assert.are.equals(30, data.skills.SmeltersWrath.stats.cost.Mana)
    end)
    it("a sample of newly-filled costs match datamine", function()
        assert.are.equals(10, data.skills.AcidFlask.stats.cost.Mana)
        assert.are.equals(60, data.skills.ManifestArmor.stats.cost.Mana)
        assert.are.equals(65, data.skills.AssembleAbomination.stats.cost.Mana)
    end)
    it("pre-existing curated costs are NOT overwritten (player-prefab disambiguation)", function()
        assert.are.equals(56, data.skills.Meteor.stats.cost.Mana, "Meteor stays 56, not enemy 60")
        assert.are.equals(3, data.skills.Fireball.stats.cost.Mana, "Fireball stays 3, not variant 4")
    end)
end)
