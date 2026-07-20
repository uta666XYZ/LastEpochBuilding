-- @leb-regression-guard: weaver-set-2pc-ww-weapon-legendary-affix-effect
-- Locks the three layers that make the Weaver Set 2-piece bonus
--   "Legendary affixes on equipped Weaver's Will weapons have 50% increased effect"
-- actually reach the calc. Before this feature the bonus text was run through
-- modLib.parseMod by applySetBonuses and resolved to NOTHING (silent no-op) --
-- the set was functionally UNMODELED (set_1_4.json setId 15 carried the text at
-- lines 1336/1367 but no parser rule and no consumer existed).
--
--   Layer 1 (ModParser): the bonus line parses to
--       Multiplier:WeaverWillWeaponLegendaryAffixEffect BASE 50  (nil extra).
--       The magnitude is data-sourced from the tooltip-fixed 50%, not hardcoded.
--   Layer 2 (CalcSetup.applySetBonuses): when >= 2 Weaver pieces are equipped
--       (wildcard-aware: Legends Entwined + Eyes completes it), the parsed
--       Multiplier lands in env.itemModDB; applySetBonuses reads it and, for each
--       equipped Weaver's Will WEAPON (item.base.weapon AND title in
--       data.weaversWillUniques), boosts every mod flagged legendaryAffix=true
--       (the woven affixes) by a +(N/100) delta so the net effect is (1+N/100)x.
--       Base/implicit/unique-inherent mods (not legendaryAffix) and non-weapon
--       Weaver's Will pieces stay 1x.
--   Layer 3 (this spec).
--
-- Grounding note: Part A save audit (2026-07-15) found ZERO characters equip a
-- Weaver's Will weapon under an active 2-set, so there is no in-game DPS capture
-- to A/B against; N=50 is the exact tooltip value, and the arithmetic below is
-- the ground truth. LE affixes only roll BASE/INC (never MORE), so the delta is
-- exact including "+X per Y" per-stat woven affixes (ScaleAddMod retains the
-- fractional per-stack coefficient -- twin guard
-- scaleaddmod-stacking-coeff-fractional-retention).
-- See REGRESSION_GUARDS.md "weaver-set-2pc-ww-weapon-legendary-affix-effect".

local BONUS_TEXT = "Legendary affixes on equipped Weaver's Will weapons have 50% increased effect"
local WEAVER_SET_ID = 15

describe("WeaverSet2pcWWWeaponLegendaryAffix", function()

    describe("Layer 1 -- ModParser maps the 2pc bonus text to the Multiplier", function()
        it("'...have 50% increased effect' -> Multiplier:WeaverWillWeaponLegendaryAffixEffect BASE 50, nil extra", function()
            local mods, extra = modLib.parseMod(BONUS_TEXT)
            assert.is_table(mods, "bonus line must parse to a mod list")
            assert.are.equals(1, #mods, "must produce exactly one mod")
            assert.are.equals("Multiplier:WeaverWillWeaponLegendaryAffixEffect", mods[1].name)
            assert.are.equals("BASE", mods[1].type)
            assert.are.equals(50, mods[1].value)
            assert.is_nil(extra, "must leave no unparsed residue (got '" .. tostring(extra) .. "')")
        end)

        it("magnitude follows the text (100% variant -> BASE 100)", function()
            local mods = modLib.parseMod("Legendary affixes on equipped Weaver's Will weapons have 100% increased effect")
            assert.are.equals(100, mods[1].value)
        end)
    end)

    describe("Layer 2 -- applySetBonuses boosts only woven affixes on WW weapons", function()
        local calcs
        before_each(function()
            newBuild()
            calcs = build.calcsTab.calcs
        end)

        -- Distinct uniqueID per piece so the dedup guard counts them separately.
        local pieceCounter = 0
        local function weaverPiece()
            pieceCounter = pieceCounter + 1
            return {
                rarity = "SET",
                title = "Weaver fake piece " .. pieceCounter,
                uniqueID = 95000 + pieceCounter,
                setInfo = { setId = WEAVER_SET_ID, name = "Weaver Set", bonus = { ["2"] = BONUS_TEXT } },
            }
        end

        -- Build an env that mimics the post-merge state: the woven affix has
        -- ALREADY been merged into itemModDB at 1x (as the real item loop does).
        -- applySetBonuses then adds the +0.5x delta.
        local function makeEnv(wwWeapon)
            local env = {
                itemModDB = new("ModDB"),
                data = { weaversWillUniques = { ["Scissor of Atropos"] = true } },
                player = { itemList = {} },
            }
            if wwWeapon then
                env.player.itemList["Weapon 1"] = wwWeapon
                for _, m in ipairs(wwWeapon.modList or {}) do
                    env.itemModDB:AddMod(m) -- simulate the 1x merge
                end
            end
            return env
        end

        local function wovenMod(value)
            local m = modLib.createMod("WeaverProbeStat", "BASE", value, "Weaver's Will")
            m.legendaryAffix = true
            return m
        end

        local function wwWeaponWith(mods, title)
            return { base = { weapon = true }, title = title or "Scissor of Atropos", modList = mods }
        end

        local function probe(env)
            return env.itemModDB:Sum("BASE", nil, "WeaverProbeStat")
        end

        it("2 Weaver pieces + WW weapon woven affix -> 1.5x (46 -> 69)", function()
            local env = makeEnv(wwWeaponWith({ wovenMod(46) }))
            calcs.applySetBonuses(env, { weaverPiece(), weaverPiece() }, "1_4")
            assert.are.equals(50, env.itemModDB:Sum("BASE", nil, "Multiplier:WeaverWillWeaponLegendaryAffixEffect"),
                "the 2pc bonus must publish the parsed Multiplier")
            assert.are.equals(69, probe(env), "woven affix must be 46 (1x merge) + 23 (0.5x delta) = 69")
        end)

        it("only 1 Weaver piece -> 2pc inert -> woven affix stays 1x (46)", function()
            local env = makeEnv(wwWeaponWith({ wovenMod(46) }))
            calcs.applySetBonuses(env, { weaverPiece() }, "1_4")
            assert.are.equals(0, env.itemModDB:Sum("BASE", nil, "Multiplier:WeaverWillWeaponLegendaryAffixEffect"))
            assert.are.equals(46, probe(env), "no 2pc bonus -> no boost")
        end)

        it("non-legendaryAffix mod on a WW weapon is NOT boosted (implicit/inherent stay 1x)", function()
            local inherent = modLib.createMod("WeaverProbeStat", "BASE", 46, "Weaver's Will")
            -- no .legendaryAffix flag
            local env = makeEnv(wwWeaponWith({ inherent }))
            calcs.applySetBonuses(env, { weaverPiece(), weaverPiece() }, "1_4")
            assert.are.equals(46, probe(env), "unique-inherent/implicit mods must not be scaled")
        end)

        it("woven affix on a NON-Weaver's-Will weapon is NOT boosted", function()
            local env = makeEnv(wwWeaponWith({ wovenMod(46) }, "Some Reforged Legendary"))
            calcs.applySetBonuses(env, { weaverPiece(), weaverPiece() }, "1_4")
            assert.are.equals(46, probe(env), "only WW-weapon woven affixes qualify")
        end)

        it("woven affix on a non-weapon Weaver's Will item (base.weapon=false) is NOT boosted", function()
            local relic = { base = { weapon = false }, title = "Scissor of Atropos", modList = { wovenMod(46) } }
            local env = makeEnv(relic)
            calcs.applySetBonuses(env, { weaverPiece(), weaverPiece() }, "1_4")
            assert.are.equals(46, probe(env), 'the tooltip says "weapons" -- non-weapon WW pieces do not qualify')
        end)

        it("Reforged-suffixed title still resolves against weaversWillUniques", function()
            local env = makeEnv(wwWeaponWith({ wovenMod(46) }, "Scissor of Atropos Reforged"))
            calcs.applySetBonuses(env, { weaverPiece(), weaverPiece() }, "1_4")
            assert.are.equals(69, probe(env), "trailing ' Reforged' must be stripped before the wwSet lookup")
        end)
    end)

    describe("Layer 2 source guard -- CalcSetup keeps the mechanism wired", function()
        local source
        setup(function()
            local f = io.open("Modules/CalcSetup.lua", "r")
            assert.is_not_nil(f, "must be able to open Modules/CalcSetup.lua")
            source = f:read("*a")
            f:close()
        end)

        it("keeps the @leb-regression-guard comment", function()
            assert.is_truthy(string.find(source, "weaver-set-2pc-ww-weapon-legendary-affix-effect", 1, true))
        end)

        it("reads the parsed Multiplier back from itemModDB", function()
            assert.is_truthy(string.find(source, 'Multiplier:WeaverWillWeaponLegendaryAffixEffect', 1, true),
                "applySetBonuses must Sum the parsed Multiplier to gate + size the boost")
        end)

        it("gates on weapon base + weaversWillUniques title and scales only legendaryAffix mods", function()
            assert.is_truthy(string.find(source, "wItem%.base%.weapon"), "must gate on weapon bases")
            assert.is_truthy(string.find(source, "weaversWillUniques"), "must gate on WW uniques")
            assert.is_truthy(string.find(source, "m%.legendaryAffix"), "must scale only woven (legendaryAffix) mods")
            assert.is_truthy(string.find(source, "ScaleAddMod"), "must apply the boost via ScaleAddMod delta")
        end)
    end)
end)
