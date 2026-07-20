-- @leb-regression-guard:refracted-rank-gating
-- Locks refracted-cell activation-rank gating. Game data encodes refracted
-- cells in IdolsContainerGridData.unlockMatrix as `100 + rank`
-- (RefractedSlotIdJump = 100, MaxIdolSlotUnlockRewards = 8): below that
-- altar unlock rank the cell behaves as a NORMAL slot — no refracted affix
-- boosts, no "per Idol in a Refracted Slot" count. Source: resources.assets
-- IdolsContainerGridDataList (path_id 270533) decoded 2026-06-10; 13/13
-- altars' blocked/refracted layouts match Data/IdolAltarLayouts.lua.
-- Ground truth: StarSeaVnV Ocular Altar 3-layer ledger — the idol on the
-- (5,1) rank-1 corner IS altar-boosted in-game while the idol on the (1,1)
-- rank-7 corner is NOT (in-game sheet cc 119% closes only with that
-- asymmetry). Config `idolAltarUnlockRank` (count, default 8 = all active)
-- drives the gate in CalcSetup (fracturedItemSet) and ItemsTab
-- (CountIdolsOnRefractedCells). See REGRESSION_GUARDS.md
-- "refracted-rank-gating".

describe("RefractedRankGating data", function()
    local layouts = LoadModule("Data/IdolAltarLayouts")

    it("every base altar carries refractedRanks matching its type-2 cells", function()
        for name, layout in pairs(layouts) do
            if layout.grid and not layout.mirrorOf then
                local hasRefracted = false
                for r = 1, 5 do
                    for c = 1, 5 do
                        if layout.grid[r][c] == 2 then
                            hasRefracted = true
                            local rank = layout.refractedRanks and layout.refractedRanks[r] and layout.refractedRanks[r][c]
                            assert.is_not_nil(rank, name .. " (" .. r .. "," .. c .. ") missing activation rank")
                            assert.is_true(rank >= 1 and rank <= 8, name .. " rank out of 1..8")
                        end
                    end
                end
                if hasRefracted then
                    -- no stray rank entries on non-refracted cells
                    for r, cols in pairs(layout.refractedRanks or {}) do
                        for c in pairs(cols) do
                            assert.are.equals(2, layout.grid[r][c],
                                name .. " refractedRanks entry on non-refracted cell (" .. r .. "," .. c .. ")")
                        end
                    end
                end
            end
        end
    end)

    it("Ocular Altar ranks match the decoded unlockMatrix exactly", function()
        local rr = layouts["Ocular Altar"].refractedRanks
        assert.are.equals(7, rr[1][1])
        assert.are.equals(5, rr[1][5])
        assert.are.equals(1, rr[5][1])
        assert.are.equals(3, rr[5][5])
    end)
end)

describe("RefractedRankGating config + wiring", function()
    it("the idolAltarUnlockRank config exists and defaults to 8", function()
        local found
        for _, opt in ipairs(LoadModule("Modules/ConfigOptions")) do
            if opt.var == "idolAltarUnlockRank" then found = opt end
        end
        assert.is_not_nil(found, "idolAltarUnlockRank config option must exist")
        assert.are.equals("count", found.type)
        assert.are.equals(8, found.defaultPlaceholderState, "default must be 8 (all cells active)")
    end)

    it("CalcSetup and ItemsTab gate refraction on the activation rank", function()
        local f = assert(io.open("Modules/CalcSetup.lua", "r"))
        local cs = f:read("*a"); f:close()
        assert.is_truthy(cs:find("@leb%-regression%-guard:refracted%-rank%-gating"),
            "inline guard marker must be present in CalcSetup")
        assert.is_truthy(cs:find("env.config.idolAltarUnlockRank or 8", 1, true),
            "CalcSetup must read the config with default 8")
        assert.is_truthy(cs:find("needed <= unlockRank", 1, true),
            "fracturedItemSet membership must respect the activation rank")
        local g = assert(io.open("Classes/ItemsTab.lua", "r"))
        local it_ = g:read("*a"); g:close()
        assert.is_truthy(it_:find("@leb%-regression%-guard:refracted%-rank%-gating"),
            "inline guard marker must be present in ItemsTab")
        assert.is_truthy(it_:find("refractedCellActive(altar, r + dr, c + dc, unlockRank)", 1, true),
            "CountIdolsOnRefractedCells must use the rank-aware check")
    end)
end)

describe("RefractedRankGating end-to-end (StarSeaVnV, Ocular Altar)", function()
    local function loadStarSea()
        local fh = io.open("../spec/TestBuilds/StarSeaVnV_LEB.xml", "r")
        if not fh then return nil end
        local xml = fh:read("*a"); fh:close()
        loadBuildFromXML(xml)
        local grp
        for i, g in ipairs(build.skillsTab.socketGroupList) do
            if not g.triggeredOnHit and not g.triggeredByTimer then
                for _, sk in ipairs(g.displaySkillList or {}) do
                    local nm = sk.activeEffect and sk.activeEffect.grantedEffect and sk.activeEffect.grantedEffect.name
                    if nm == "Shurikens" then grp = grp or i end
                end
            end
        end
        build.mainSocketGroup = grp
        build.calcsTab.input.skill_number = grp
        return true
    end
    local function ferretCC()
        build.buildFlag = false
        build.calcsTab:BuildOutput()
        local ms = build.calcsTab.calcsEnv.player.mainSkill
        for _, e in ipairs(ms.skillModList:Tabulate("INC", ms.skillCfg, "CritChance")) do
            if (e.mod.source or ""):find("Ferret") then return e.value end
        end
        return 0
    end

    it("mirrored altars inherit flipped refractedRanks", function()
        if not loadStarSea() then pending("StarSeaVnV_LEB.xml not present (spec/TestBuilds is gitignored)"); return end
        local mirrored = build.itemsTab.altarLayouts["Twisted Altar (Mirrored)"]
        assert.is_not_nil(mirrored.refractedRanks, "mirror expansion must carry refractedRanks")
        -- Twisted (1,2) rank 8 mirrors to (1,4)
        assert.are.equals(8, mirrored.refractedRanks[1][4])
    end)

    it("rank 6 turns the rank-7 corner into a normal slot (Ferret loses the altar boost)", function()
        if not loadStarSea() then pending("StarSeaVnV_LEB.xml not present (spec/TestBuilds is gitignored)"); return end
        -- default rank 8: Ferret 53 x (1 + 0.557 + 1.0) = 136/dagger -> 272
        assert.are.equals(272, ferretCC())
        local refractedAt8 = build.calcsTab.calcsEnv.player.modDB:Sum("BASE", nil, "Multiplier:IdolInRefractedSlot")
        assert.are.equals(4, refractedAt8)
        -- rank 6: (1,1) needs 7 -> inactive; Ferret keeps only Wings x2 = 106/dagger -> 212
        build.configTab.input.idolAltarUnlockRank = 6
        build.configTab:BuildModList()
        assert.are.equals(212, ferretCC())
        local refractedAt6 = build.calcsTab.calcsEnv.player.modDB:Sum("BASE", nil, "Multiplier:IdolInRefractedSlot")
        assert.are.equals(3, refractedAt6, "the rank-7 corner idol must drop out of the refracted count")
        -- rank 0: nothing refracted
        build.configTab.input.idolAltarUnlockRank = 0
        build.configTab:BuildModList()
        ferretCC()
        local refractedAt0 = build.calcsTab.calcsEnv.player.modDB:Sum("BASE", nil, "Multiplier:IdolInRefractedSlot")
        assert.are.equals(0, refractedAt0)
        build.configTab.input.idolAltarUnlockRank = nil
        build.configTab:BuildModList()
    end)
end)
