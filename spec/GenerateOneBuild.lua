-- One-off: generate snapshot for a single XML build specified via env LEB_BUILD
local target = os.getenv("LEB_BUILD")
if not target or target == "" then
    target = "../spec/TestBuilds/1.4/TrainingDummy lv100 VK.xml"
end

local function sanitizeLabel(s)
    s = tostring(s or ""):gsub('[^%w%s%-_]', ''):gsub('%s+', '_')
    if s == "" then s = "unnamed" end
    return s
end

function buildTable(tableName, values, string)
    string = string or ""
    string = string .. tableName .. " = {"
    local keys = {}
    for k in pairs(values) do table.insert(keys, k) end
    table.sort(keys)
    for _, key in pairs(keys) do
        local value = values[key]
        if type(value) == "table" then
            buildTable(key, value, string)
        elseif type(value) == "boolean" then
            string = string .. "[\"" .. key .. "\"] = " .. (value and "true" or "false") .. ",\n"
        elseif type(value) == "string" then
            string = string .. "[\"" .. key .. "\"] = \"" .. value .. "\",\n"
        else
            string = string .. "[\"" .. key .. "\"] = " .. round(value, 4) .. ",\n"
        end
    end
    string = string .. "}\n"
    return string
end

print("Loading build " .. target)
local fileHnd, errMsg = io.open(target, "r")
if not fileHnd then error("Cannot open: " .. tostring(errMsg)) end
local importCode = fileHnd:read("*a"); fileHnd:close()

loadBuildFromXML(importCode, target)
local luaPath = target:gsub("%.xml$", ".lua")
local outHnd, err2 = io.open(luaPath, "w+")
if not outHnd then error("Cannot write " .. luaPath .. ": " .. tostring(err2)) end
outHnd:write("return {\n    ")
outHnd:write(buildTable("output", build.calcsTab.mainOutput) .. "\n")
local socketGroupList = build.skillsTab and build.skillsTab.socketGroupList or {}
outHnd:write("    skills = {\n")
for i = 1, #socketGroupList do
    local ok = pcall(function()
        build.mainSocketGroup = i
        build.calcsTab:BuildOutput()
    end)
    local group = socketGroupList[i]
    local label = sanitizeLabel(group and group.displayLabel or ("slot"..i))
    local slotName = "slot" .. i .. "_" .. label
    outHnd:write("        [\"" .. slotName .. "\"] = ")
    if ok and build.calcsTab and build.calcsTab.mainOutput then
        outHnd:write(buildTable("perSocket", build.calcsTab.mainOutput))
    else
        outHnd:write("{}\n")
    end
    -- ALSO dump minion output for this socket if present
    local mEnv = build.calcsTab.mainEnv
    if mEnv and mEnv.minion and mEnv.minion.output then
        outHnd:write("        [\"" .. slotName .. "_minion\"] = ")
        outHnd:write(buildTable("minion", mEnv.minion.output))
        outHnd:write(",\n")
        -- Dump BleedChance mods on minion modDB and skillCfg flags
        local mModDB = mEnv.minion.modDB
        local mSkill = mEnv.minion.mainSkill
        outHnd:write("        [\"" .. slotName .. "_minion_diag\"] = {\n")
        if mModDB then
            local mods = mModDB.mods["BleedChance"] or {}
            outHnd:write("            bleedChanceModCount = " .. tostring(#mods) .. ",\n")
            for i = 1, #mods do
                local mm = mods[i]
                local tagInfo = ""
                for ti = 1, #mm do
                    local t = mm[ti]
                    if type(t) == "table" then
                        tagInfo = tagInfo .. "[" .. tostring(t.type or "?")
                        for k, v in pairs(t) do if k ~= "type" then tagInfo = tagInfo .. " "..k.."="..tostring(v) end end
                        tagInfo = tagInfo .. "]"
                    end
                end
                outHnd:write(string.format("            [%d] = { source=%q, type=%q, value=%s, flags=%s, kw=%s, tags=%q },\n",
                    i, tostring(mm.source or ""), tostring(mm.type or ""), tostring(mm.value),
                    tostring(mm.flags or 0), tostring(mm.keywordFlags or 0), tagInfo))
            end
            local sumNoCfg = mModDB:Sum("BASE", nil, "BleedChance") or 0
            outHnd:write("            sumNoCfg = " .. tostring(sumNoCfg) .. ",\n")
            if mSkill and mSkill.skillCfg then
                local sumWithCfg = mModDB:Sum("BASE", mSkill.skillCfg, "BleedChance") or 0
                outHnd:write("            sumWithCfg = " .. tostring(sumWithCfg) .. ",\n")
                outHnd:write("            skillCfgFlags = " .. tostring(mSkill.skillCfg.flags or 0) .. ",\n")
                outHnd:write("            skillCfgKw = " .. tostring(mSkill.skillCfg.keywordFlags or 0) .. ",\n")
            else
                outHnd:write("            skillCfg = nil,\n")
            end
        end
        outHnd:write("        },\n")
    end
    -- Also dump player MinionModifier list and player skillModList MinionModifier list
    outHnd:write("        [\"" .. slotName .. "_player_minionMods\"] = {\n")
    local pModDB = mEnv and mEnv.player and mEnv.player.modDB
    if pModDB then
        local mm = pModDB.mods["MinionModifier"] or {}
        outHnd:write("            playerMinionModifierCount = " .. tostring(#mm) .. ",\n")
        for i = 1, #mm do
            local m = mm[i]
            local innerName = "?"
            if type(m.value) == "table" and m.value.mod then
                innerName = tostring(m.value.mod.name) .. "[" .. tostring(m.value.mod.value) .. " " .. tostring(m.value.mod.type) .. " flags=" .. tostring(m.value.mod.flags or 0) .. "]"
            end
            outHnd:write(string.format("            [%d] = { source=%q, type=%q, inner=%q },\n",
                i, tostring(m.source or ""), tostring(m.type or ""), innerName))
        end
    end
    local pSkill = mEnv and mEnv.player and mEnv.player.mainSkill
    -- Dump player BleedChance mods (raw)
    if pModDB and pModDB.mods["BleedChance"] then
        outHnd:write("            playerBleedChanceCount = " .. tostring(#pModDB.mods["BleedChance"]) .. ",\n")
        for i, m in ipairs(pModDB.mods["BleedChance"]) do
            outHnd:write(string.format("            pbc[%d] = { source=%q, type=%q, value=%s, flags=%s },\n",
                i, tostring(m.source or ""), tostring(m.type or ""), tostring(m.value), tostring(m.flags or 0)))
        end
    else
        outHnd:write("            playerBleedChanceCount = 0,\n")
    end
    -- Dump helmet (itemId via slot "Helmet") raw mod lines + parsed mods
    local items = build.itemsTab and build.itemsTab.items
    local helmetSlot = build.itemsTab and build.itemsTab.slots and build.itemsTab.slots["Helmet"]
    local helmetItemId = helmetSlot and helmetSlot.selItemId
    if items and helmetItemId and items[helmetItemId] then
        local h = items[helmetItemId]
        outHnd:write("            helmetItemId = " .. tostring(helmetItemId) .. ",\n")
        outHnd:write("            helmetName = " .. string.format("%q", tostring(h.name or "")) .. ",\n")
        if h.modList then
            outHnd:write("            helmetModListCount = " .. tostring(#h.modList) .. ",\n")
            for i, m in ipairs(h.modList) do
                local innerName = ""
                if m.name == "MinionModifier" and type(m.value) == "table" and m.value.mod then
                    innerName = " inner=" .. string.format("%q", tostring(m.value.mod.name) .. "[" .. tostring(m.value.mod.value) .. "]")
                end
                outHnd:write(string.format("            hml[%d] = { name=%q, type=%q, value=%s%s },\n",
                    i, tostring(m.name or ""), tostring(m.type or ""), tostring(m.value), innerName))
            end
        end
        if h.explicitModLines then
            outHnd:write("            helmetExplicitLineCount = " .. tostring(#h.explicitModLines) .. ",\n")
            for i, ml in ipairs(h.explicitModLines) do
                outHnd:write(string.format("            hel[%d] = { line=%q, range=%s, nMods=%d, extra=%q },\n",
                    i, tostring(ml.line or ""), tostring(ml.range), ml.modList and #ml.modList or 0, tostring(ml.extra or "")))
            end
        end
    end
    if pSkill and pSkill.skillModList then
        local list = pSkill.skillModList:List(pSkill.skillCfg, "MinionModifier") or {}
        outHnd:write("            skillModListMinionModifierCount = " .. tostring(#list) .. ",\n")
        for i = 1, #list do
            local v = list[i]
            local innerName = "?"
            if type(v) == "table" and v.mod then
                innerName = tostring(v.mod.name) .. "[" .. tostring(v.mod.value) .. " " .. tostring(v.mod.type) .. "]"
            end
            outHnd:write(string.format("            sml[%d] = { type=%q, inner=%q },\n", i, tostring(v.type or ""), innerName))
        end
    end
    outHnd:write("        },\n")
    outHnd:write(",\n")
end
outHnd:write("    },\n")
-- Life breakdown: dump every mod in modDB.mods["Life"] + Life INC + LifeMore
local function dumpModList(hnd, label, mods)
    hnd:write("        [\"" .. label .. "\"] = {\n")
    if not mods then
        hnd:write("        },\n")
        return
    end
    for i = 1, #mods do
        local m = mods[i]
        local value
        if m[1] then
            -- has tags (PerStat, Multiplier, etc.) — compute via context if possible
            local ok, v = pcall(function()
                return build.calcsTab.mainEnv.player.modDB:EvalMod(m)
            end)
            value = ok and v or "tagged"
        else
            value = m.value
        end
        local tagInfo = ""
        if m[1] then
            for ti = 1, #m do
                local t = m[ti]
                tagInfo = tagInfo .. (t.type or "?") .. (t.stat and (":"..t.stat) or "") .. (t.var and (":"..t.var) or "") .. ";"
            end
        end
        hnd:write(string.format("            { source=%q, type=%q, value=%s, tags=%q },\n",
            tostring(m.source or ""), tostring(m.type or ""), tostring(value), tagInfo))
    end
    hnd:write("        },\n")
end

-- Restore main socket group for accurate modDB
pcall(function()
    build.mainSocketGroup = 1
    build.calcsTab:BuildOutput()
end)

outHnd:write("    lifeBreakdown = {\n")
local modDB = build.calcsTab.mainEnv and build.calcsTab.mainEnv.player and build.calcsTab.mainEnv.player.modDB
if modDB then
    dumpModList(outHnd, "Life", modDB.mods["Life"])
    dumpModList(outHnd, "LifeMore", modDB.mods["LifeMore"])
    dumpModList(outHnd, "IdolRefractedSuffixEffect", modDB.mods["IdolRefractedSuffixEffect"])
    dumpModList(outHnd, "IdolRefractedPrefixEffect", modDB.mods["IdolRefractedPrefixEffect"])
    dumpModList(outHnd, "IdolRefractedAffixEffect", modDB.mods["IdolRefractedAffixEffect"])
    -- Also dump INC Life — stored under "Life" with type=INC, already in above list
    outHnd:write(string.format("        [\"_summary\"] = { base=%d, inc=%d, more=%.3f, final=%d },\n",
        modDB:Sum("BASE", nil, "Life"),
        modDB:Sum("INC", nil, "Life"),
        modDB:More(nil, "Life"),
        build.calcsTab.mainOutput.Life or 0))
end
outHnd:write("    },\n")

outHnd:write("    etBreakdown = {\n")
if modDB then
    dumpModList(outHnd, "EnduranceThreshold", modDB.mods["EnduranceThreshold"])
    dumpModList(outHnd, "LifeAsEnduranceThreshold", modDB.mods["LifeAsEnduranceThreshold"])
    outHnd:write(string.format("        [\"_summary\"] = { etBase=%d, lifeAsET=%d, life=%d, final=%d },\n",
        modDB:Sum("BASE", nil, "EnduranceThreshold"),
        modDB:Sum("BASE", nil, "LifeAsEnduranceThreshold"),
        build.calcsTab.mainOutput.Life or 0,
        build.calcsTab.mainOutput.EnduranceThreshold or 0))
end
outHnd:write("    },\n")

outHnd:write("    vitBreakdown = {\n")
if modDB then
    dumpModList(outHnd, "Vit", modDB.mods["Vit"])
    outHnd:write(string.format("        [\"_summary\"] = { final=%d },\n", modDB:Sum("BASE", nil, "Vit") or 0))
end
outHnd:write("    },\n")

outHnd:write("    lifeRegenBreakdown = {\n")
if modDB then
    dumpModList(outHnd, "LifeRegen", modDB.mods["LifeRegen"])
    dumpModList(outHnd, "LifeRegenPercent", modDB.mods["LifeRegenPercent"])
    dumpModList(outHnd, "Life", modDB.mods["Life"])
    outHnd:write(string.format("        [\"_summary\"] = { regenBase=%.2f, regenInc=%d, regenMore=%.3f, regenPercentBase=%.2f, lifeBase=%d, lifeInc=%d, pool=%d, output=%.2f },\n",
        modDB:Sum("BASE", nil, "LifeRegen"),
        modDB:Sum("INC", nil, "LifeRegen"),
        modDB:More(nil, "LifeRegen"),
        modDB:Sum("BASE", nil, "LifeRegenPercent"),
        modDB:Sum("BASE", nil, "Life"),
        modDB:Sum("INC", nil, "Life"),
        build.calcsTab.mainOutput.Life or 0,
        build.calcsTab.mainOutput.LifeRegen or 0))
end
outHnd:write("    },\n")

outHnd:write("    manaRegenBreakdown = {\n")
if modDB then
    dumpModList(outHnd, "ManaRegen", modDB.mods["ManaRegen"])
    dumpModList(outHnd, "ManaRegenPercent", modDB.mods["ManaRegenPercent"])
    dumpModList(outHnd, "Mana", modDB.mods["Mana"])
    outHnd:write(string.format("        [\"_summary\"] = { regenBase=%.2f, regenInc=%d, regenMore=%.3f, regenPercentBase=%.2f, manaBase=%d, manaInc=%d, pool=%d, output=%.2f },\n",
        modDB:Sum("BASE", nil, "ManaRegen"),
        modDB:Sum("INC", nil, "ManaRegen"),
        modDB:More(nil, "ManaRegen"),
        modDB:Sum("BASE", nil, "ManaRegenPercent"),
        modDB:Sum("BASE", nil, "Mana"),
        modDB:Sum("INC", nil, "Mana"),
        build.calcsTab.mainOutput.Mana or 0,
        build.calcsTab.mainOutput.ManaRegen or 0))
end
outHnd:write("    },\n")

outHnd:write("    critMultBreakdown = {\n")
if modDB then
    dumpModList(outHnd, "CritMultiplier", modDB.mods["CritMultiplier"])
    dumpModList(outHnd, "SkillBaseCritMultiplier", modDB.mods["SkillBaseCritMultiplier"])
    outHnd:write(string.format("        [\"_summary\"] = { critMultBase=%d, critMultInc=%d, skillBase=%d, output=%.2f },\n",
        modDB:Sum("BASE", nil, "CritMultiplier"),
        modDB:Sum("INC", nil, "CritMultiplier"),
        modDB:Sum("BASE", nil, "SkillBaseCritMultiplier"),
        build.calcsTab.mainOutput.CritMultiplier or 0))
end
outHnd:write("    },\n")

outHnd:write("    lifeOnBlockBreakdown = {\n")
if modDB then
    dumpModList(outHnd, "LifeOnBlock", modDB.mods["LifeOnBlock"])
    outHnd:write(string.format("        [\"_summary\"] = { final=%d },\n", modDB:Sum("BASE", nil, "LifeOnBlock") or 0))
end
outHnd:write("    },\n")

-- MovementSpeed breakdown: dump every INC/MORE mod feeding output.MovementSpeedMod
-- so per-build LE-vs-LEB diff can attribute the gap to a specific source
-- (item / passive / skill tree / mastery / buff).
outHnd:write("    movementSpeedBreakdown = {\n")
if modDB then
    dumpModList(outHnd, "MovementSpeed", modDB.mods["MovementSpeed"])
    local incSum = modDB:Sum("INC", nil, "MovementSpeed") or 0
    local moreMul = modDB:More(nil, "MovementSpeed") or 1
    outHnd:write(string.format("        [\"_summary\"] = { inc=%d, more=%.3f, final=%.3f },\n",
        incSum, moreMul, build.calcsTab.mainOutput.MovementSpeedMod or 0))
end
outHnd:write("    },\n")

-- Dump all mods on shield (item id 11)
outHnd:write("    shieldMods = {\n")
local items = build.itemsTab and build.itemsTab.items
if items and items[11] and items[11].modList then
    for i, m in ipairs(items[11].modList) do
        outHnd:write(string.format("        [%d] = { name=%q, type=%q, value=%s },\n",
            i, tostring(m.name or ""), tostring(m.type or ""), tostring(m.value)))
    end
end
outHnd:write("    },\n")
outHnd:write("    shieldRawLines = {\n")
if items and items[11] and items[11].rawLines then
    for i, l in ipairs(items[11].rawLines) do
        outHnd:write(string.format("        [%d] = %q,\n", i, tostring(l)))
    end
end
outHnd:write("    },\n")

outHnd:write("    parseTest = {\n")
do
    local testLines = {
        "62 Health Gain on Block",
        "+43% Chance to inflict Bleed on Hit",
        "+43% Chance to inflict Bleed on Minion Hit",
        "+112% Chance to inflict Bleed on Minion Hit",
        "+(36-45)% Chance to inflict Bleed on Minion Hit",
    }
    local function dumpModRec(prefix, m)
        if type(m) ~= "table" then return tostring(m) end
        local s = string.format("name=%s type=%s value=%s flags=%s", tostring(m.name), tostring(m.type), tostring(m.value), tostring(m.flags or 0))
        if m.name == "MinionModifier" and type(m.value) == "table" and m.value.mod then
            s = s .. " inner={" .. dumpModRec("", m.value.mod) .. "}"
        end
        return s
    end
    for ti, tl in ipairs(testLines) do
        local mods, extra = modLib.parseMod(tl)
        local n = mods and #mods or 0
        local desc = ""
        if n > 0 then
            for i = 1, n do
                desc = desc .. "[" .. i .. ":" .. dumpModRec("", mods[i]) .. "]"
            end
        end
        outHnd:write(string.format("        [%d] = { line=%q, n=%d, extra=%q, mods=%q },\n", ti, tl, n, tostring(extra or ""), desc))
    end
end
outHnd:write("    },\n")

outHnd:write("    shieldExplicitLines = {\n")
if items and items[11] and items[11].explicitModLines then
    for i, ml in ipairs(items[11].explicitModLines) do
        local nMods = ml.modList and #ml.modList or 0
        outHnd:write(string.format("        [%d] = { line=%q, range=%s, rounding=%q, scalar=%s, crafted=%s, extra=%q, nMods=%d },\n",
            i, tostring(ml.line or ""), tostring(ml.range), tostring(ml.rounding or ""), tostring(ml.valueScalar), tostring(ml.crafted), tostring(ml.extra or ""), nMods))
    end
end
outHnd:write("    },\n")

-- Idol per-stat breakdown: dump mods whose source starts with "Item:" so we can
-- verify per-idol contributions against in-game tooltips.
outHnd:write("    idolStatBreakdown = {\n")
if modDB then
    local stats = {
        "StunAvoidance", "FireResist", "WardRetention", "ColdDamageBase",
        "SpellDamageLeechWhileChannelling", "SpellDamageLeech",
        "StaticChargesGenerationRate", "ManaEfficiency",
        "WardOnMeleeHit", "WardGainedPerRuneConsumed",
        "FrenzyEffect", "MaxOmenIdols", "HealthPerEquippedHereticalIdol",
        "ArmorPerRefractedIdol", "HealthPerEquippedOmenIdol",
    }
    for _, stat in ipairs(stats) do
        local mods = modDB.mods[stat]
        if mods and #mods > 0 then
            outHnd:write("        [\"" .. stat .. "\"] = {\n")
            for i = 1, #mods do
                local m = mods[i]
                local src = tostring(m.source or "")
                if src:find("^Item:") then
                    outHnd:write(string.format("            { source=%q, type=%q, value=%s },\n",
                        src, tostring(m.type or ""), tostring(m.value)))
                end
            end
            outHnd:write("        },\n")
        end
    end
end
outHnd:write("    },\n")

-- Blessing probe: list all blessing items + dump their modLists, and dump
-- modDB sources for each resistance stat. Only emitted when LEB_BLESSING_PROBE=1.
if os.getenv("LEB_BLESSING_PROBE") == "1" then
    outHnd:write("    blessingProbe = {\n")
    outHnd:write("        items = {\n")
    if build.itemsTab and build.itemsTab.items then
        for id, it in pairs(build.itemsTab.items) do
            if it.uniqueID and tostring(it.uniqueID):find("^blessing:") then
                outHnd:write(string.format("            [%d] = { uniqueID=%q, name=%q, modListCount=%d },\n",
                    id, tostring(it.uniqueID), tostring(it.title or it.name or ""), it.modList and #it.modList or 0))
                if it.modList then
                    for i, m in ipairs(it.modList) do
                        outHnd:write(string.format("                mod[%d] = { name=%q, type=%q, value=%s, source=%q },\n",
                            i, tostring(m.name or ""), tostring(m.type or ""), tostring(m.value), tostring(m.source or "")))
                    end
                end
            end
        end
    end
    outHnd:write("        },\n")
    outHnd:write("        slots = {\n")
    if build.itemsTab and build.itemsTab.orderedSlots then
        for _, slot in ipairs(build.itemsTab.orderedSlots) do
            local sn = tostring(slot.slotName or "")
            if sn == "Reign of Dragons" or sn == "Spirits of Fire" or sn == "Fall of the Outcasts" or sn == "The Stolen Lance" or sn == "The Black Sun" or sn == "Blood, Frost, and Death" or sn == "Ending the Storm" or sn == "Fall of the Empire" or sn == "The Last Ruin" or sn == "The Age of Winter" then
                outHnd:write(string.format("            [%q] = { selItemId=%s, isShown=%s },\n",
                    sn, tostring(slot.selItemId), tostring(slot.IsShown and slot:IsShown())))
            end
        end
    end
    outHnd:write("        },\n")
    outHnd:write("        resistSources = {\n")
    local modDB = build.calcsTab and build.calcsTab.mainEnv and build.calcsTab.mainEnv.player and build.calcsTab.mainEnv.player.modDB
    if modDB then
        for _, stat in ipairs({"FireResist","ColdResist","LightningResist","PhysicalResist","NecroticResist","PoisonResist","VoidResist"}) do
            outHnd:write(string.format("            [%q] = {\n", stat))
            local mods = modDB.mods[stat]
            if mods then
                for i, m in ipairs(mods) do
                    outHnd:write(string.format("                { source=%q, type=%q, value=%s },\n",
                        tostring(m.source or ""), tostring(m.type or ""), tostring(m.value)))
                end
            end
            outHnd:write("            },\n")
        end
    end
    outHnd:write("        },\n")
    outHnd:write("    },\n")
end

outHnd:write("}\n")
outHnd:close()
print("Wrote " .. luaPath)
