-- @leb-regression-guard:upheaval-totem-grant
-- See REGRESSION_GUARDS.md "upheaval-totem-grant".
-- Validation provenance is retained in maintainer notes.

local function readFile(path)
    local f = io.open(path, "r") or io.open("src/" .. path, "r")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

describe("UpheavalTotem grant registry (node-gated, no fabrication)", function()
    it("Upheaval grants SummonUpheavalTotem gated on uph41-30, replacing the player cast", function()
        local grants = data.subSkillGrants.Upheaval
        assert.is_table(grants, "Upheaval must be in the grant registry")
        local g
        for _, grant in ipairs(grants) do
            if grant.skillId == "SummonUpheavalTotem" then g = grant end
        end
        assert.is_table(g, "Upheaval must grant SummonUpheavalTotem")
        assert.is_true(g.summon, "the grant is a SUMMON (totem pack in Full DPS)")
        -- The node gate is load-bearing: dropping requiresNode would inject an always-on
        -- Upheaval Totem into EVERY Upheaval build's Full DPS (inflating the corpus).
        assert.are.equals("uph41-30", g.requiresNode,
            "the totem grant must be node-conditional on Upheaval Totems (uph41-30)")
        -- The replacement gate prevents double-counting the player-cast Upheaval.
        assert.is_true(g.replacesParentHit,
            "uph41-30 replaces the player cast -> replacesParentHit must suppress the player hit")
    end)

    it("totem count scales off uph41-10 + uph41-11 (each +1 Maximum Upheaval Totem)", function()
        local grants = data.subSkillGrants.Upheaval
        local g
        for _, grant in ipairs(grants) do
            if grant.skillId == "SummonUpheavalTotem" then g = grant end
        end
        assert.are.equals(1, g.summonActiveCountBase, "base totem count is 1")
        assert.is_table(g.summonActiveCountNodes, "the +1 limit nodes must be a node->perPoint table")
        assert.are.equals(1, g.summonActiveCountNodes["uph41-10"], "uph41-10 grants +1 totem")
        assert.are.equals(1, g.summonActiveCountNodes["uph41-11"], "uph41-11 grants +1 totem")
    end)

    it("SummonUpheavalTotem skill summons the UpheavalTotem minion (treeId uph41)", function()
        local d = data.skills.SummonUpheavalTotem
        assert.is_table(d, "SummonUpheavalTotem must exist in data.skills")
        assert.is_table(d.minionList)
        local hasTotem = false
        for _, m in ipairs(d.minionList) do if m == "UpheavalTotem" then hasTotem = true end end
        assert.is_true(hasTotem, "must summon the UpheavalTotem minion")
        assert.are.equals("uph41", d.treeId, "shares the Upheaval tree so the totem inherits its nodes")
        assert.is_true(d.baseFlags.minion and d.baseFlags.duration,
            "a duration-limited summon (8s)")
    end)

    it("the UpheavalTotem minion natively casts Upheaval", function()
        local m = data.minions.UpheavalTotem
        assert.is_table(m, "UpheavalTotem minion must exist")
        assert.is_table(m.skillList)
        local castsUpheaval = false
        for _, s in ipairs(m.skillList) do if s == "Upheaval" then castsUpheaval = true end end
        assert.is_true(castsUpheaval, "the totem's skillList must contain Upheaval (no grantMinionSkillId needed)")
    end)
end)

describe("UpheavalTotem player-added-flat whitelist (over-copy guard)", function()
    it("LE_PLAYER_ADDED_FLAT_MINIONS whitelists ONLY the UpheavalTotem -> Upheaval", function()
        assert.is_table(LE_PLAYER_ADDED_FLAT_MINIONS, "the whitelist registry must exist")
        assert.is_table(LE_PLAYER_ADDED_FLAT_MINIONS.UpheavalTotem,
            "the in-game-validated UpheavalTotem must be whitelisted")
        assert.are.equals("Upheaval", LE_PLAYER_ADDED_FLAT_MINIONS.UpheavalTotem.skill,
            "the totem inherits the player's added-flat for its granted Upheaval delivery")
        -- Opt-in only: no other minion may be swept in (the over-copy danger). Count entries.
        local n = 0
        for _ in pairs(LE_PLAYER_ADDED_FLAT_MINIONS) do n = n + 1 end
        assert.are.equals(1, n, "the registry must contain ONLY UpheavalTotem (no unvalidated minions)")
    end)
end)

describe("UpheavalTotem grant calc wiring (source invariants)", function()
    it("CalcPerform routes player BASE added-flat onto the MINION modDB, whitelist+flag gated", function()
        local src = assert(readFile("Modules/CalcPerform.lua"))
        assert.is_truthy(src:find("@leb%-regression%-guard:upheaval%-totem%-grant"),
            "CalcPerform must carry the guard marker")
        -- Whitelist-keyed by minion type (opt-in per minion, not a structural gate).
        assert.is_truthy(src:find("LE_PLAYER_ADDED_FLAT_MINIONS[env.minion.type]", 1, true),
            "routing must be gated by the LE_PLAYER_ADDED_FLAT_MINIONS whitelist")
        -- Copies onto the MINION modDB ONLY -> zero player ripple.
        assert.is_truthy(src:find("env.minion.modDB:AddMod(copyTable(mod))", 1, true),
            "inherited flats must be added to env.minion.modDB ONLY")
        -- BASE-only: the heart of the over-copy guard. INC/MORE already inherit; copying them
        -- would overshoot. The copy condition must require mod.type == "BASE".
        assert.is_truthy(src:find('mod.type == "BASE" and inheritNames[mod.name]', 1, true),
            "the copy must be restricted to BASE added-flat (never INC/MORE)")
        -- Delivery-flag gated -> a spell-only / wrong-weapon flat is skipped (no blanket fold).
        assert.is_truthy(src:find("band(cfgFlags, mod.flags) == mod.flags", 1, true),
            "the copy must pass the granted skill's delivery flags")
        assert.is_truthy(src:find("MatchKeywordFlags(cfgKw, mod.keywordFlags)", 1, true),
            "the copy must pass the granted skill's keyword flags")
        -- GLOBAL flats only: SkillId/SkillName-scoped player flats and Tree: sources are owned
        -- by the inheritIds channel; excluding them prevents double-routing.
        assert.is_truthy(src:find('tag.type == "SkillId" or tag.type == "SkillName"', 1, true),
            "skill-scoped player flats must be excluded (handled by the inheritIds channel)")
        assert.is_truthy(src:find('src:match("^Tree:")', 1, true),
            "Tree-sourced flats must be excluded (owned by the inheritIds channel)")
    end)

    it("CalcSetup injects a SkillName DisableSkill when replacesParentHit + node allocated", function()
        local text = assert(readFile("Modules/CalcSetup.lua"))
        assert.is_truthy(text:find("grant.replacesParentHit", 1, true),
            "CalcSetup must honor the replacesParentHit flag")
        assert.is_truthy(text:find('env.modDB:NewMod("DisableSkill", "FLAG", true', 1, true),
            "the replacement must inject a DisableSkill FLAG onto the player modDB")
        assert.is_truthy(text:find('type = "SkillName", skillName = group.grantedEffect.name', 1, true),
            "the DisableSkill must be SkillName-scoped to the parent (player-cast Upheaval) only")
        -- The multi-node count consumer must exist (cap = base + allocated +1 nodes).
        assert.is_truthy(text:find("grant.summonActiveCountNodes and env.allocNodes", 1, true),
            "CalcSetup must consume summonActiveCountNodes for the multi-node totem cap")
    end)

    it("CalcActiveSkill surfaces the accurate reason (points to Summon Upheaval Totem)", function()
        -- @leb-regression-guard:upheaval-totem-disable-reason
        -- The player-cast Upheaval is disabled by the replacesParentHit injection above. The
        -- disableReason must NOT read as the generic "type is disabled" here -- it must name the
        -- totem AND point the user to the "Summon Upheaval Totem" skill (where the DPS now lives),
        -- keyed on the SAME source string CalcSetup injects ("uph41-30:replacesParentHit").
        local text = assert(readFile("Modules/CalcActiveSkill.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:upheaval%-totem%-disable%-reason"),
            "CalcActiveSkill must carry the disable-reason guard marker")
        assert.is_truthy(text:find('entry.mod.source == "uph41-30:replacesParentHit"', 1, true),
            "the accurate reason must be keyed on the CalcSetup-injected DisableSkill source")
        assert.is_truthy(text:find('activeSkill.disableReason = "Cast by Upheaval Totem\\nsee Summon Upheaval Totem"', 1, true),
            "the disable reason must name the totem and point to the Summon Upheaval Totem skill (2 lines, \\n-split)")
    end)

    it("Build.lua renders a multi-line disableReason as one statBox row per line", function()
        -- The statBox truncates a long single line; the disable-reason renderer must split the
        -- "\n"-separated reason so the Upheaval Totem text fits on two centered rows.
        local text = assert(readFile("Modules/Build.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:upheaval%-totem%-disable%-reason"),
            "Build.lua must carry the disable-reason guard marker at the render site")
        assert.is_truthy(text:find('disableReason or ""):gmatch("[^\\n]+")', 1, true),
            "the disableReason must be rendered line-by-line (\\n-split) so long reasons wrap")
    end)

    it("Build.lua centers a long UNTRIGGERED Full DPS label (e.g. 3x Summon Upheaval Totem)", function()
        -- @leb-regression-guard:fulldps-wrap-long-untriggered-label
        -- A wide skill label with NO trigger (the Upheaval Totem summon) must NOT be right-aligned
        -- at the box edge (x=278) -- it must wrap to a CENTERED two-line block so it stays readable.
        local text = assert(readFile("Modules/Build.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:fulldps%-wrap%-long%-untriggered%-label"),
            "Build.lua must carry the untriggered-label wrap guard marker")
        -- The old right-aligned-at-edge form for the untriggered SkillDPS wrap must be gone.
        local _, wrapAt = text:find("@leb%-regression%-guard:fulldps%-wrap%-long%-untriggered%-label")
        local block = text:sub(wrapAt, wrapAt + 800)
        assert.is_truthy(block:find('align = "CENTER_X", x = 140', 1, true),
            "the untriggered long label must render centered (CENTER_X x=140), not edge-right")
        assert.is_falsy(block:find('x = 278', 1, true),
            "the untriggered long label must not right-align at the box edge (x=278)")
    end)

    it("SubSkillGrants carries the guard marker", function()
        local text = assert(readFile("Data/SubSkillGrants.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:upheaval%-totem%-grant"),
            "SubSkillGrants must carry the guard marker at the Upheaval entry")
    end)

    it("the whitelist registry carries the guard marker", function()
        local text = assert(readFile("Data/Global.lua"))
        assert.is_truthy(text:find("@leb%-regression%-guard:upheaval%-totem%-grant"),
            "Global.lua must carry the guard marker at LE_PLAYER_ADDED_FLAT_MINIONS")
    end)
end)
