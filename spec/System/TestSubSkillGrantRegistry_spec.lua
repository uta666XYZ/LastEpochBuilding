-- @leb-regression-guard:subskill-grant-registry
-- See REGRESSION_GUARDS.md "subskill-grant-registry".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("SubSkillGrantRegistry data (no fabrication)", function()
    it("every granted skillId exists in data.skills", function()
        assert.is_table(data.subSkillGrants, "data.subSkillGrants must be loaded")
        for parentId, grants in pairs(data.subSkillGrants) do
            assert.is_table(data.skills[parentId],
                "registry parent " .. parentId .. " must exist in data.skills")
            for _, grant in ipairs(grants) do
                assert.is_table(data.skills[grant.skillId],
                    "granted skill " .. grant.skillId .. " must exist in data.skills")
            end
        end
    end)

    it("SprigganForm grants SpiritThorns and ThornShield (Phase 1 pair)", function()
        local grants = data.subSkillGrants.SprigganForm
        assert.is_table(grants)
        local ids = {}
        for _, g in ipairs(grants) do ids[g.skillId] = true end
        assert.is_true(ids.SpiritThorns, "SpiritThorns must be granted")
        assert.is_true(ids.ThornShield, "ThornShield must be granted")
    end)

    it("the granted skills carry their skills.json base data (tb47 / ts48)", function()
        -- Validation provenance is retained in maintainer notes.
        local st = data.skills.SpiritThorns
        assert.are.equals("Spirit Thorns", st.name)
        assert.are.equals(20, st.stats.spell_base_physical_damage)
        assert.are.equals(1, st.stats.damageEffectiveness)
        local ts = data.skills.ThornShield
        assert.are.equals("Thorn Shield", ts.name)
        assert.are.equals(20, ts.stats.spell_base_physical_damage)
        assert.are.equals(1, ts.stats.damageEffectiveness)
    end)
end)

describe("SubSkillGrantRegistry thorn-burst alias (parser)", function()
    it("'+12% Thorn Burst Damage' parses to a Thorn-Shield-scoped MORE Damage", function()
        local mods, extra = modLib.parseMod("+12% Thorn Burst Damage")
        assert.is_nil(extra, "must parse cleanly (was dropped with residue ' Thorn Burst ')")
        assert.are.equals(1, #mods)
        local m = mods[1]
        assert.are.equals("Damage", m.name)
        assert.are.equals("MORE", m.type)
        assert.are.equals(12, m.value)
        local hasTag = false
        for _, tag in ipairs(m) do
            if tag.type == "SkillName" and tag.skillName == "Thorn Shield" then hasTag = true end
        end
        assert.is_true(hasTag, "must carry SkillName='Thorn Shield'")
    end)

    it("multi-point scaled variant '+24% Thorn Burst Damage' parses the same way", function()
        local mods, extra = modLib.parseMod("+24% Thorn Burst Damage")
        assert.is_nil(extra)
        assert.are.equals("MORE", mods[1].type)
        assert.are.equals(24, mods[1].value)
    end)

    it("'+20% Thorn Burst Bleed Chance' scopes the bleed chance to Thorn Shield", function()
        local mods, extra = modLib.parseMod("+20% Thorn Burst Bleed Chance")
        assert.is_nil(extra)
        assert.are.equals("ChanceToTriggerOnHit_Ailment_Bleed", mods[1].name)
        local hasTag = false
        for _, tag in ipairs(mods[1]) do
            if tag.type == "SkillName" and tag.skillName == "Thorn Shield" then hasTag = true end
        end
        assert.is_true(hasTag)
    end)

    it("no stale leftover-parse 'Thorn Burst' rows remain in ModCache", function()
        local body = assert(readFile("Data/ModCache.lua"))
        assert.is_nil(body:find('," Thorn Burst  "}', 1, true),
            "stale ModCache rows with ' Thorn Burst ' residue would re-mask the alias")
    end)
end)

describe("SubSkillGrantRegistry source invariants", function()
    it("CalcSetup injects registry grants into env.grantedSkills", function()
        local text = assert(readFile("Modules/CalcSetup.lua"))
        assert.is_truthy(text:find("data.subSkillGrants", 1, true),
            "CalcSetup must consume data.subSkillGrants")
        assert.is_truthy(text:find("grantedSubSkills", 1, true),
            "CalcSetup must build the grantedSubSkills table")
        assert.is_truthy(text:find("subSkillOf", 1, true),
            "granted groups must be marked subSkillOf for labeling/inheritance")
    end)
end)

describe("SubSkillGrantRegistry end-to-end (empty build + Spriggan Form)", function()
    it("socketing Spriggan Form grants Spirit Thorns + Thorn Shield as active skills", function()
        newBuild()
        local sgl = build.skillsTab.socketGroupList
        -- A real LE bar always has 5 socket groups; granted groups are
        -- inserted at index 5+N and the removal walk stops at the first
        -- hole, so model the realistic contiguous 1..5 layout.
        local group = { label = "", enabled = true, skillId = "SprigganForm", slotNumber = 1 }
        sgl[1] = group
        for i = 2, 5 do
            sgl[i] = { label = "", enabled = true, skillId = "Maelstrom", slotNumber = i }
            build.skillsTab:ProcessSocketGroup(sgl[i])
        end
        build.skillsTab:ProcessSocketGroup(group)
        build.buildFlag = true
        runCallback("OnFrame")

        local found = {}
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local ge = s.activeEffect and s.activeEffect.grantedEffect
            local sg = s.socketGroup
            if ge and sg and sg.subSkillOf == "SprigganForm" then
                found[ge.name] = s
            end
        end
        assert.is_not_nil(found["Spirit Thorns"], "Spirit Thorns must be granted")
        assert.is_not_nil(found["Thorn Shield"], "Thorn Shield must be granted")

        -- Active grants, NOT trigger-modeled: they compute their own cast rate.
        assert.is_falsy(found["Spirit Thorns"].socketGroup.triggered)
        assert.is_falsy(found["Thorn Shield"].socketGroup.triggered)
        -- The grant channel for parent-tree mods: groupSource = SkillId:<parent>
        assert.are.equals("SkillId:SprigganForm", found["Spirit Thorns"].socketGroup.source)
        assert.are.equals("SkillId:SprigganForm", found["Thorn Shield"].socketGroup.source)
        -- Labeled like the trigger grants
        assert.are.equals("Spirit Thorns (from Spriggan Form)", found["Spirit Thorns"].socketGroup.label)

        -- Disabling the parent group removes the grants on the next pass.
        group.enabled = false
        build.buildFlag = true
        runCallback("OnFrame")
        local stillThere = false
        for _, s in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
            local sg = s.socketGroup
            if sg and sg.subSkillOf == "SprigganForm" then stillThere = true end
        end
        assert.is_false(stillThere, "grants must disappear when the parent is disabled")

        -- @leb-regression-guard:granted-group-placement-no-holes
        -- The legacy placement `socketGroupList[5 + grantedIndex]` left HOLES when
        -- grantedIndex was inflated (duplicate Timer:<id> entries from the
        -- per-activeSkill timer scan; XML-persisted granted groups matching early
        -- entries). Lua's `#` stops at the first nil, so every
        -- `for i = 1, #socketGroupList` consumer (snapshot slot dump, Full DPS UI)
        -- silently lost the groups placed beyond the hole. Probe-confirmed on the
        -- FugginBEESSS corpus build: Spirit Thorns/Thorn Shield landed at [11]/[12]
        -- with [7]-[10] nil -> #list = 6 -> grants never reached the snapshot.
        -- Placement now keeps the legacy index only when free AND contiguous, else
        -- falls back to the first free index (hole-free, collision-safe).
        local f2 = io.open("Modules/CalcSetup.lua", "r") or io.open("src/Modules/CalcSetup.lua", "r")
        assert.is_not_nil(f2, "must read Modules/CalcSetup.lua")
        local setupSrc = f2:read("*a"); f2:close()
        assert.is_truthy(setupSrc:find("@leb%-regression%-guard:granted%-group%-placement%-no%-holes"),
            "CalcSetup must carry the granted-group-placement-no-holes guard marker")
        assert.is_truthy(setupSrc:find("if list[at] ~= nil or (at > 1 and list[at - 1] == nil) then", 1, true),
            "placement must fall back when the legacy index is occupied or non-contiguous")
        assert.is_falsy(setupSrc:find("socketGroupList[5 + grantedIndex] = group", 1, true),
            "the raw fixed-index write must be gone")
        -- behavioral canary: after the grant passes above, the list must be DENSE
        local list = build.skillsTab.socketGroupList
        local dense, total = #list, 0
        for _ in pairs(list) do total = total + 1 end
        assert.are.equals(total, dense,
            "socketGroupList must be hole-free (# == pairs count) after grant placement")
    end)
end)
