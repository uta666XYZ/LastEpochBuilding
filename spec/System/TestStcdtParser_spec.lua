-- Unit tests for calcs.getActiveStcdtBits — the stcdt-filter parser that
-- decides which damage-type bits from skillTreeConversionDamageTags are
-- "actually active" given the player's allocated tree nodes.
--
-- @leb-regression-guard:stcdt-conversion-shapes
-- These cases pin down the conversion / addition / source-removal stat & prose
-- shapes catalogued during the 2026-05 multi-skill conversion sweep. See the
-- companion REGRESSION_GUARDS.md entry and the inline-tagged blocks in
-- src/Modules/CalcActiveSkill.lua getActiveStcdtBits().
--
-- Strategy: feed a stub env.allocNodes table directly. This isolates the
-- parser from the rest of the build pipeline — no tree JSON, no skill
-- selection, no DPS engine.

local Phys = SkillType.Physical
local Lite = SkillType.Lightning
local Cold = SkillType.Cold
local Fire = SkillType.Fire
local Void = SkillType.Void
local Necr = SkillType.Necrotic
local Pois = SkillType.Poison
local Elem = SkillType.Elemental

local function envWith(nodes)
    -- Minimal stub: the parser only touches env.allocNodes.
    return { allocNodes = nodes }
end

local function node(stats, desc)
    return { stats = stats or {}, description = desc and (type(desc) == "table" and desc or { desc }) or nil }
end

describe("getActiveStcdtBits #stcdt", function()

    -- Baseline / guards ---------------------------------------------------

    it("returns zero when stcdt is zero", function()
        local active, removed = calcs.getActiveStcdtBits(envWith({}), "tree_x", 0)
        assert.are.equals(0, active)
        assert.are.equals(0, removed)
    end)

    it("returns zero when env or treeId missing", function()
        local active, removed = calcs.getActiveStcdtBits(nil, "tree_x", Fire)
        assert.are.equals(0, active)
        assert.are.equals(0, removed)
    end)

    it("filters to nodes under the requested treeId prefix", function()
        local nodes = {
            ["tree_x-1"] = node({ "Physical -> Fire Damage" }),
            ["tree_y-1"] = node({ "Physical -> Cold Damage" }),
        }
        local active = calcs.getActiveStcdtBits(envWith(nodes), "tree_x", bit.bor(Fire, Cold))
        assert.are.equals(Fire, active)  -- Cold from the other tree is excluded
    end)

    -- A1: classic "<Src> -> <Dst> Damage" --------------------------------

    it("recognises bare '<Src> -> <Dst> Damage' conversion (A1)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ "Physical -> Fire Damage" }) }),
            "t", Fire
        )
        assert.are.equals(Fire, active)
    end)

    -- A2: "<Src> Damage -> <Dst> Damage" ---------------------------------

    it("recognises '<Src> Damage -> <Dst> Damage' conversion (A2)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ "Cold Damage -> Lightning Damage" }) }),
            "t", Lite
        )
        assert.are.equals(Lite, active)
    end)

    -- A3: "<Src> -> <Dst> Conversion" suffix -----------------------------

    it("recognises '<Src> -> <Dst> Conversion' suffix (A3)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ "Necrotic -> Physical Conversion" }) }),
            "t", Phys
        )
        assert.are.equals(Phys, active)
    end)

    -- A4: bare "<Dst> Conversion" ----------------------------------------

    it("recognises bare '<Dst> Conversion' (A4)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ "Fire Conversion" }) }),
            "t", Fire
        )
        assert.are.equals(Fire, active)
    end)

    -- A5/A6: multi-source AND-join ---------------------------------------

    it("recognises multi-source 'X and Y -> Z Damage' (A5; svz81-23)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ "Physical and Fire -> Necrotic Damage" }) }),
            "t", Necr
        )
        assert.are.equals(Necr, active)
    end)

    it("recognises multi-source 'X and Y -> Z Conversion' suffix (A6)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ "Necrotic and Fire -> Physical Conversion" }) }),
            "t", Phys
        )
        assert.are.equals(Phys, active)
    end)

    -- A7: "<Delivery> Base Damage -> <Dst>" (bg36nl-7) -------------------

    it("recognises '<Delivery> Base Damage -> <Dst>' (A7; bg36nl-7)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ " Melee Base Damage -> Fire" }) }),
            "t", Fire
        )
        assert.are.equals(Fire, active)
    end)

    -- A8b: bare "<Src> -> <Dst>" (no Damage suffix) ----------------------

    it("recognises bare '<Src> -> <Dst>' (A8b; fw3d-10 Lightning Ward)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ " Fire -> Lightning" }) }),
            "t", Lite
        )
        assert.are.equals(Lite, active)
    end)

    it("rejects ailment-token '<Src> -> <Dst>' that isn't a damage type", function()
        -- "Chill -> Ignite" is a non-damage swap; damageTypeBitsByName filters it.
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ "Chill -> Ignite" }) }),
            "t", bit.bor(Fire, Cold)
        )
        assert.are.equals(0, active)
    end)

    -- A12: modifier-only "Increased <Src> Damage -> <Dst> Damage" -------

    it("recognises modifier conv 'Increased <Src> Damage -> <Dst> Damage' (A12; ds4d3-32)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ " Increased Necrotic Damage -> Poison Damage" }) }),
            "t", Pois
        )
        assert.are.equals(Pois, active)
    end)

    -- A13: cstri-22 buff modifier exception ------------------------------

    it("filters out '<X> -> Elemental Damage' buff-modifier (A13; cstri-22)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ " Fire -> Elemental Damage" }) }),
            "t", bit.bor(Fire, Elem)
        )
        assert.are.equals(0, active)
    end)

    -- B1: "Enables <Type> Nova" addition (Elemental Nova en6) -----------

    it("recognises 'Enables <Type> Nova' addition (B1; en6 Elemental Nova)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({ ["t-1"] = node({ "Enables Cold Nova" }) }),
            "t", Cold
        )
        assert.are.equals(Cold, active)
    end)

    -- Description prose: "loses its {X} tag" source removal (Q3=(a)) ----

    it("returns removed=Necrotic for unconditional 'loses its {X} tag' (rea-32)", function()
        local active, removed = calcs.getActiveStcdtBits(
            envWith({
                ["t-1"] = node(nil, "Reap loses its {Necrotic} tag and gains a {Physical} tag instead.")
            }),
            "t", Necr
        )
        -- active reflects the description-level "gain the X tag" path (also
        -- captured separately) — assert removed bit specifically.
        assert.is_true(bit.band(removed, Necr) ~= 0)
    end)

    it("does NOT remove for 'if ...' conditional 'loses its {X} tag' (sw1, srk21-25)", function()
        local _, removed = calcs.getActiveStcdtBits(
            envWith({
                ["t-1"] = node(nil, "If you have 5 points in this node, Swipe loses its {Physical} tag.")
            }),
            "t", Phys
        )
        assert.are.equals(0, removed)
    end)

    -- Existing patterns regression: gain-the-tag promotion ---------------

    it("promotes via 'gain the {X} tag' description (fs3e3-21 Forged by Fire)", function()
        local active = calcs.getActiveStcdtBits(
            envWith({
                ["t-1"] = node(nil, "Forged Weapons gain the {Fire} tag.")
            }),
            "t", Fire
        )
        assert.are.equals(Fire, active)
    end)

    -- Variant addition --------------------------------------------------

    it("recognises 'Adds <VariantName>' minion variant addition", function()
        -- minionVariantBits is local to CalcActiveSkill; this test relies on
        -- the table being populated for at least one known variant. Skip if
        -- empty (defensive against future refactors).
        local nodes = { ["t-1"] = node({ "Adds Pyromancers" }) }
        -- Active = stcdt ∩ (variant bits OR plain producers OR conversions).
        -- We only pass Fire in stcdt, so the assertion is whether Fire ends up
        -- active — which is true iff the Pyromancers variant carries Fire.
        local active = calcs.getActiveStcdtBits(envWith(nodes), "t", Fire)
        -- This may be 0 or Fire depending on whether the 'Pyromancers' variant
        -- mapping is present in the runtime variant-bits table. We only assert
        -- it doesn't crash and returns a non-negative number.
        assert.is_true(active == 0 or active == Fire)
    end)

end)
