-- @leb-regression-guard: form-tree-nodes-gated-by-condition
-- Locks the contract that Druid/Lich Form skills (Werebear, Spriggan,
-- Swarmblade, Reaper) gate their skill-tree node mods behind the
-- corresponding Calcs-tab "Are you in <X> Form?" Condition flag, the same
-- way Flame Ward (treeId fw3d) is gated.
--
-- Background: LE Form skills are implemented as Mutators whose statsInForm
-- mod set is only added in OnEnable. Without a gate, LEB's default
-- socket-group enabled=true (the LETools import default) would leak the
-- whole Form tree-node set into modDB unconditionally, inflating armour /
-- HP / damage relative to Form-OFF LETools snapshots. Form playerAbilityIDs
-- (treeIds in LEB) come from LE_datamining/extracted/ability_keyed_array.json.
--
-- See REGRESSION_GUARDS.md "form-tree-nodes-gated-by-condition".

describe("S5FormTreeNodeGate", function()

    describe("CalcSetup whileActiveBuffByTreeId table contains the 4 player Forms", function()
        local source
        setup(function()
            local f = io.open("Modules/CalcSetup.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
            source = f:read("*a")
            f:close()
        end)

        local forms = {
            { treeId = "wb8fo",  cond = "InWerebearForm",   name = "Werebear Form" },
            { treeId = "sf5rd",  cond = "InSprigganForm",   name = "Spriggan Form" },
            { treeId = "sbf4m",  cond = "InSwarmbladeForm", name = "Swarmblade Form" },
            { treeId = "rf1azz", cond = "InReaperForm",     name = "Reaper Form" },
        }
        for _, f in ipairs(forms) do
            it(("maps %s (%s) -> %s"):format(f.treeId, f.name, f.cond), function()
                local pat = '%["?' .. f.treeId .. '"?%]%s*=%s*"' .. f.cond .. '"'
                assert.is_truthy(string.find(source, pat),
                    ("CalcSetup.lua whileActiveBuffByTreeId must map %s -> %s"):format(f.treeId, f.cond))
            end)
        end

        it("retains the existing fw3d -> HaveFlameWard mapping (no regression)", function()
            assert.is_truthy(string.find(source, '%["?fw3d"?%]%s*=%s*"HaveFlameWard"'),
                "CalcSetup.lua must keep fw3d -> HaveFlameWard alongside the new Form entries")
        end)

        it("regression-guard comment block is present", function()
            assert.is_truthy(string.find(source, "form-tree-nodes-gated-by-condition", 1, true),
                "CalcSetup.lua must keep the @leb-regression-guard comment so future edits trip review")
        end)
    end)

    describe("ConfigOptions Calcs-tab checkboxes still publish Condition:In<X>Form FLAG", function()
        local source
        setup(function()
            local f = io.open("Modules/ConfigOptions.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/ConfigOptions.lua")
            source = f:read("*a")
            f:close()
        end)

        local forms = { "Werebear", "Spriggan", "Swarmblade", "Reaper" }
        for _, name in ipairs(forms) do
            it("conditionIn" .. name .. "Form var exists with matching FLAG mod", function()
                local varPat = 'var%s*=%s*"conditionIn' .. name .. 'Form"'
                assert.is_truthy(string.find(source, varPat),
                    "ConfigOptions.lua must declare var conditionIn" .. name .. "Form")
                local flagPat = '"Condition:In' .. name .. 'Form"%s*,%s*"FLAG"%s*,%s*true'
                assert.is_truthy(string.find(source, flagPat),
                    "ConfigOptions.lua must publish Condition:In" .. name .. "Form FLAG=true when checkbox is set")
            end)
        end
    end)
end)
