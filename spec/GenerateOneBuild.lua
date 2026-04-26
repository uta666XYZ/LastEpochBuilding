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

outHnd:write("    lifeOnBlockBreakdown = {\n")
if modDB then
    dumpModList(outHnd, "LifeOnBlock", modDB.mods["LifeOnBlock"])
    outHnd:write(string.format("        [\"_summary\"] = { final=%d },\n", modDB:Sum("BASE", nil, "LifeOnBlock") or 0))
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
    local testLines = { "62 Health Gain on Block", "+62 Health Gain on Block", "62 health gain on block" }
    for ti, tl in ipairs(testLines) do
        local mods, extra = modLib.parseMod(tl)
        local n = mods and #mods or 0
        local first = ""
        if n > 0 then first = string.format("name=%s type=%s value=%s", tostring(mods[1].name), tostring(mods[1].type), tostring(mods[1].value)) end
        outHnd:write(string.format("        [%d] = { line=%q, n=%d, extra=%q, first=%q },\n", ti, tl, n, tostring(extra or ""), first))
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

outHnd:write("}\n")
outHnd:close()
print("Wrote " .. luaPath)
