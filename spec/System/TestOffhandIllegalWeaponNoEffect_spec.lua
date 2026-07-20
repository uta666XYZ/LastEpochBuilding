-- @leb-regression-guard:offhand-illegal-weapon-no-effect
-- Locks the contract that a true weapon-base item (base.weapon ~= nil -- i.e. a
-- melee/ranged weapon, NOT a Catalyst/Shield/Quiver) placed in the OFF-HAND
-- (Weapon 2) of a MAGE grants NO effect, reproducing the in-game ✖ the Mage
-- off-hand slot shows (it accepts only a Catalyst; Mage cannot dual-wield).
--
-- Three sites in CalcSetup.lua must agree (all keyed on the single
-- env.player.offhandWeaponIllegal flag computed in the item pre-scan):
--   1. Flag: offhandWeaponIllegal = Weapon 2 exists AND its base.weapon ~= nil
--      AND class is in the banned set { Mage }.
--   2. Mod merge: when slotName == "Weapon 2" and the flag is set, srcList is
--      emptied so none of the off-hand's affixes/implicits reach modDB.
--   3. weaponData2: the base-damage mirror is skipped when the flag is set,
--      which (empty weaponData2 -> nil .type) also suppresses the DualWielding
--      condition.
--
-- SCOPE — Mage ONLY. The corpus blast (ProbeOffhandBlast, 639 builds) proved
-- every OTHER class dual-wields legitimately with an off-hand weapon in real
-- player builds -- Rogue (34, daggers), Acolyte/Lich (41, daggers), Primalist
-- (17, 1H), Sentinel (3, 1H). Banning any class beyond Mage would wrongly strip
-- those. Only the single Mage off-hand-weapon build (Nameless King) is affected.
-- See REGRESSION_GUARDS.md "offhand-illegal-weapon-no-effect".

local function readSource(relPath)
    local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
    assert.is_not_nil(f, "must be able to open " .. relPath)
    local text = f:read("*a")
    f:close()
    return text
end

describe("OffhandIllegalWeaponNoEffect", function()
    local source

    setup(function()
        source = readSource("Modules/CalcSetup.lua")
    end)

    it("keeps the @leb-regression-guard comment so future edits trip review", function()
        assert.is_truthy(string.find(source, "offhand-illegal-weapon-no-effect", 1, true),
            "CalcSetup.lua must keep the @leb-regression-guard id")
    end)

    it("bans ONLY Mage (Acolyte/Primalist/Rogue/Sentinel dual-wield legitimately)", function()
        assert.is_truthy(string.find(source, "offhandWeaponBannedClass%s*=%s*{%s*Mage%s*=%s*true%s*}"),
            "the banned-class set must be exactly { Mage = true }")
        -- Guard against regression to the earlier (wrong) allow-list that would
        -- have stripped 41 legitimate Lich dagger builds.
        assert.is_nil(string.find(source, "offhandWeaponBannedClass%s*=%s*{[^}]*Acolyte"),
            "Acolyte must NOT be banned -- Lich dual-wields daggers")
        assert.is_nil(string.find(source, "offhandWeaponBannedClass%s*=%s*{[^}]*Rogue"),
            "Rogue must NOT be banned -- Bladedancer dual-wields")
        assert.is_nil(string.find(source, "offhandWeaponBannedClass%s*=%s*{[^}]*Primalist"),
            "Primalist must NOT be banned")
        assert.is_nil(string.find(source, "offhandWeaponBannedClass%s*=%s*{[^}]*Sentinel"),
            "Sentinel must NOT be banned")
    end)

    it("computes the flag from Weapon 2 + base.weapon + banned class (conjunction)", function()
        local i = string.find(source, "env%.player%.offhandWeaponIllegal%s*=")
        assert.is_not_nil(i, "the flag assignment must exist")
        local window = string.sub(source, i, i + 220)
        assert.is_truthy(string.find(window, "w2i%.base%.weapon%s*~=%s*nil"),
            "flag must require a true weapon base (excludes Catalyst/Shield/Quiver)")
        assert.is_truthy(string.find(window, "offhandWeaponBannedClass%[env%.spec%.curClassName%]"),
            "flag must be keyed on the class via env.spec.curClassName")
    end)

    it("empties the off-hand mod list only for Weapon 2 when the flag is set", function()
        local needle = 'if slotName == "Weapon 2" and env%.player%.offhandWeaponIllegal then%s*srcList = {}'
        assert.is_truthy(string.find(source, needle),
            "the mod-merge suppression must gate on slotName == 'Weapon 2' AND the flag")
    end)

    it("skips the weaponData2 base-damage mirror when the flag is set", function()
        local i = string.find(source, "env%.player%.weaponData2%s*=%s*copyTable%(w2item%.base%.weapon%)")
        assert.is_not_nil(i, "the weaponData2 copy site must exist")
        local window = string.sub(source, math.max(1, i - 160), i)
        assert.is_truthy(string.find(window, "not%s+env%.player%.offhandWeaponIllegal"),
            "the weaponData2 copy must be gated with `not env.player.offhandWeaponIllegal`")
    end)

    -- Behavioral smoke test -- runs only where the (gitignored) corpus build is
    -- present (local dev). CI without spec/TestBuilds skips it; the source locks
    -- above are the always-on guard.
    describe("behavioral (corpus build present)", function()
        local xmlCandidates = {
            "../spec/TestBuilds/1.4/bin/Nameless King Mage Legacy.xml",
            "spec/TestBuilds/1.4/bin/Nameless King Mage Legacy.xml",
        }
        local xmlPath
        for _, p in ipairs(xmlCandidates) do
            local fh = io.open(p, "r")
            if fh then fh:close(); xmlPath = p; break end
        end

        if not xmlPath then
            pending("Nameless King corpus build not present (gitignored) -- source locks cover the contract")
            return
        end

        local env
        setup(function()
            local fh = io.open(xmlPath, "r"); local xml = fh:read("*a"); fh:close()
            newBuild()
            loadBuildFromXML(xml, "OffhandIllegalSpec")
            build.buildFlag = true
            runCallback("OnFrame")
            build.calcsTab:BuildOutput()
            env = build.calcsTab.mainEnv
        end)

        it("is a Mage with a weapon-base item in Weapon 2", function()
            assert.are.equals("Mage", env.spec.curClassName)
            local w2 = env.player.itemList["Weapon 2"]
            assert.is_not_nil(w2, "Weapon 2 item must be present")
            assert.is_not_nil(w2.base and w2.base.weapon, "Weapon 2 must be a weapon base")
        end)

        it("flags the off-hand weapon as illegal", function()
            assert.is_true(env.player.offhandWeaponIllegal)
        end)

        it("leaves weaponData2 empty (no base-damage mirror, DualWielding not set)", function()
            assert.is_true(next(env.player.weaponData2 or {}) == nil,
                "weaponData2 must be empty for the illegal off-hand")
            assert.is_falsy(env.modDB.conditions["DualWielding"])
        end)

        it("leaks NO modDB mods sourced from the off-hand sword", function()
            local cnt = 0
            for _, modList in pairs(env.player.modDB.mods) do
                for _, m in ipairs(modList) do
                    local src = tostring(m.source or "")
                    if src:lower():find("longsword") or src:lower():find("acid") then cnt = cnt + 1 end
                end
            end
            assert.are.equals(0, cnt, "no off-hand-sourced mods may remain in modDB")
        end)

        it("keeps the main-hand (Weapon 1) weapon intact", function()
            assert.is_not_nil(env.player.weaponData1, "weaponData1 must survive")
            assert.is_not_nil(env.player.weaponData1.type, "weaponData1.type must be set")
        end)
    end)
end)
