-- @leb-regression-guard: elemental-nova-tree-gated-base-intrinsic
-- Locks the contract that Elemental Nova's tree-gated per-type base (granted by
-- the en6 specialization nodes as a skillModList "<T>Damage" BASE mod, NOT a
-- skills.json intrinsic base) is registered as INTRINSIC `source[<T>Damage]` in
-- CalcOffence, so the skill's typeless/adaptive added pool (genericAdded, "+X
-- Damage" / Added Spell Damage) is DISTRIBUTED onto the gated types.
--
-- Bug this locks (pre-fix): source[<T>Damage] was nil for the nova (its base
-- lived only in skillModList), so the genericAdded distribution gate
-- (`source[damageTypeMod]`) failed and routed ZERO added onto the gated Fire/
-- Cold/Lightning types -- they emitted only the bare tree base (~9.6 = 8 x 1.2eff),
-- making LEB ~24x UNDER on the gated type vs in-game.
--
-- LE behaviour / grounding: in-game the nova routes the character's Added Spell
-- Damage into each cast at damageEffectiveness (1.2). Tru_Flamer save-08
-- (lightning-only spec), paired character sheet Added Spell Damage = 179 ->
-- in-game per-hit lightning 1379.6; the fix routes LEB's pool onto the gated
-- lightning type (pre-mit 56.6 -> ~825), closing 24.4x -> ~1.67x (the residual is
-- a separate external-added under-read, LEB pool 110 vs in-game 179).
--
-- The fix also corrects a minor base over-scale: the tree base 8 now rides
-- skillPart at x1 (intrinsic) instead of addedPart at xEff (8 -> 9.6).
--
-- Scope: nova only (grantedEffect.name == "Elemental Nova"); it is the sole
-- tree-gated-base skill (see elemental-nova-spec-tree-gated-damage-type). Non-nova
-- skills are byte-identical. Establishing reference: see git log
-- Ice + Lightning, NO Fire node -> Fire stays gated off; Cold + Lightning receive
-- the routed pool). See REGRESSION_GUARDS.md > "elemental-nova-tree-gated-base-intrinsic".

describe("ElementalNovaTreeGatedBaseIntrinsic", function()
    before_each(function()
        newBuild()
    end)

    local function selectElementalNova()
        for i, g in ipairs(build.skillsTab.socketGroupList) do
            if g.displaySkillList then
                for k, sk in ipairs(g.displaySkillList) do
                    local ge = sk.activeEffect and sk.activeEffect.grantedEffect
                    if ge and tostring(ge.name):lower():find("elemental nova", 1, true) then
                        build.mainSocketGroup = i
                        build.calcsTab.input.skill_number = i
                        g.mainActiveSkill = k
                        g.mainActiveSkillCalcs = k
                    end
                end
            end
        end
        build.buildFlag = true
        build.calcsTab:BuildOutput()
    end

    it("routes the added pool onto the tree-gated nova types (Cold/Lightning) and keeps un-allocated Fire at zero", function()
        local f = io.open("../spec/TestBuilds/1.4/Bakbr2Ne lv86 Sorcerer.xml", "r")
        if not f then
            pending("Bakbr2Ne XML fixture missing in this worktree; covered where spec/TestBuilds is populated")
            return
        end
        local xml = f:read("*a")
        f:close()
        loadBuildFromXML(xml, "Bakbr2Ne lv86 Sorcerer")
        runCallback("OnFrame")
        selectElementalNova()

        local o = (build.calcsTab.calcsEnv or build.calcsTab.mainEnv).player.output

        -- Fire node NOT allocated on <private build> -> Fire type stays gated off.
        assert.are.equal(0, o.FireDamageBase or 0)

        -- Cold + Lightning ARE allocated. With the pool routed, their per-type base
        -- must exceed the BARE tree base (8 x 1.2eff = 9.6); pre-fix they were ~9.6.
        assert.is_true((o.ColdDamageBase or 0) > 12,
            "Cold nova base should exceed the bare tree base once the added pool is routed (got "..tostring(o.ColdDamageBase)..")")
        assert.is_true((o.LightningDamageBase or 0) > 12,
            "Lightning nova base should exceed the bare tree base once the added pool is routed (got "..tostring(o.LightningDamageBase)..")")

        -- And they deal damage (routing produced a nonzero hit).
        assert.is_true((o.ColdHitAverage or 0) > 0)
        assert.is_true((o.LightningHitAverage or 0) > 0)
    end)
end)
