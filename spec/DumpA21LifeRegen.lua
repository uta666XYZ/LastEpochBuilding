-- Dump A21 LifeRegen breakdown: per-idol HR modLine values + modDB sources.
-- Usage:
--   LEB_BUILD="spec/TestBuilds/1.4/A21YaLpz lv98 Necromancer.xml" busted --lua=luajit --run=dumpA21LifeRegen

local path = os.getenv("LEB_BUILD")
if not path or path == "" then error("LEB_BUILD is required") end

local fileHnd = io.open(path, "r")
if not fileHnd then error("Cannot open: " .. path) end
local importCode = fileHnd:read("*a"); fileHnd:close()

newBuild()
loadBuildFromXML(importCode, path)
build.buildFlag = true
runCallback("OnFrame")
build.calcsTab:BuildOutput()

local env = build.calcsTab.mainEnv
if not env or not env.player or not env.player.modDB then
    print("[ERR] no env.player.modDB")
    return
end
local modDB = env.player.modDB
local output = env.player.output

print("=========================================")
print("Build:", path)
print("=========================================")
print(string.format("output.LifeRegen     = %s", tostring(output.LifeRegen)))
print(string.format("output.LifeRegenBase = %s", tostring(output.LifeRegenBase)))
print(string.format("output.LifeRegenInc  = %s", tostring(output.LifeRegenInc)))
print(string.format("output.LifeRegenMore = %s", tostring(output.LifeRegenMore)))
print(string.format("Sum BASE LifeRegen = %s", tostring(modDB:Sum("BASE", nil, "LifeRegen"))))
print(string.format("Sum INC  LifeRegen = %s", tostring(modDB:Sum("INC",  nil, "LifeRegen"))))
print(string.format("Multiplier:SummonedMinion = %s", tostring(modDB.multipliers and modDB.multipliers["SummonedMinion"])))
print(string.format("Sum BASE Multiplier:SummonedMinion = %s", tostring(modDB:Sum("BASE", nil, "Multiplier:SummonedMinion"))))
print("\n--- modDB.mods['Multiplier:SummonedMinion'] ---")
for i, m in ipairs(modDB.mods["Multiplier:SummonedMinion"] or {}) do
    print(string.format("  [%d] %s val=%s src=%s", i, tostring(m.type), tostring(m.value), tostring(m.source)))
end
print(string.format("activeSkillList count = %d", #env.player.activeSkillList))
for i, sk in ipairs(env.player.activeSkillList) do
    local name = tostring(sk.activeEffect and sk.activeEffect.grantedEffect and sk.activeEffect.grantedEffect.name)
    print(string.format("  [%d] %s minion=%s", i, name, tostring(sk.minion and "yes" or "no")))
    if sk.minion then
        local md = sk.minion.minionData or {}
        for k, v in pairs(md) do
            if k ~= "modList" and k ~= "skillList" then
                print(string.format("       minionData.%s = %s", k, tostring(v):sub(1, 80)))
            end
        end
        local sd = sk.skillData or {}
        for k, v in pairs(sd) do
            if tostring(k):lower():find("minion") or tostring(k):lower():find("limit") or tostring(k):lower():find("max") or tostring(k):lower():find("skeleton") then
                print(string.format("       skillData.%s = %s", k, tostring(v):sub(1, 80)))
            end
        end
    end
end

-- Per-source breakdown
print("\n=== modDB:ListSources BASE LifeRegen ===")
local ok, baseSrcs = pcall(modDB.ListSources, modDB, "BASE", nil, "LifeRegen")
if ok and baseSrcs then
    local keys = {}
    for k in pairs(baseSrcs) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        print(string.format("  +%s  src=%s", tostring(baseSrcs[k]), tostring(k)))
    end
else
    print("  (err: "..tostring(baseSrcs)..")")
end

print("\n=== modDB:ListSources INC LifeRegen ===")
local ok2, incSrcs = pcall(modDB.ListSources, modDB, "INC", nil, "LifeRegen")
if ok2 and incSrcs then
    local keys = {}
    for k in pairs(incSrcs) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        print(string.format("  %s%%  src=%s", tostring(incSrcs[k]), tostring(k)))
    end
end

-- Raw modDB.mods["LifeRegen"]
print("\n--- modDB.mods.LifeRegen (full list) ---")
for i, m in ipairs(modDB.mods["LifeRegen"] or {}) do
    local tagInfo = ""
    for ti = 1, #m do
        local t = m[ti]
        tagInfo = tagInfo .. "{" .. (t.type or "?")
        for tk, tv in pairs(t) do
            if tk ~= "type" then tagInfo = tagInfo .. " " .. tk .. "=" .. tostring(tv) end
        end
        tagInfo = tagInfo .. "}"
    end
    print(string.format("  [%d] %s val=%s src=%s tags=%s",
        i, tostring(m.type), tostring(m.value), tostring(m.source), tagInfo))
end

-- Per-idol modLine dump
print("\n=========================================")
print("=== Per-idol modLine HR dump ===")
print("=========================================")
local items = build.itemsTab.items
for _, slot in pairs(build.itemsTab.orderedSlots) do
    local slotName = slot.slotName
    if slotName:match("^Idol %d+$") or slotName:sub(1, 10) == "Omen Idol " then
        local itemId = build.itemsTab.activeItemSet[slotName] and build.itemsTab.activeItemSet[slotName].selItemId
        local item = itemId and items[itemId]
        if item then
            print(string.format("\n[%s] %s (id=%s)", slotName, tostring(item.name or "?"), tostring(itemId)))
            if item.prefixes then
                for i, pfx in ipairs(item.prefixes) do
                    print(string.format("    prefix[%d] modId=%s range=%s vs=%s",
                        i, tostring(pfx.modId), tostring(pfx.range), tostring(pfx.valueScalar)))
                end
            end
            if item.suffixes then
                for i, sfx in ipairs(item.suffixes) do
                    print(string.format("    suffix[%d] modId=%s range=%s vs=%s",
                        i, tostring(sfx.modId), tostring(sfx.range), tostring(sfx.valueScalar)))
                end
            end
            for i, ml in ipairs(item.explicitModLines or {}) do
                local hr = (ml.line or ""):match("[Hh]ealth [Rr]egen") or (ml.line or ""):match("[Hh]ealth Regeneration")
                local marker = hr and " <== HR" or ""
                print(string.format("    modLine[%d] line=%q range=%s vs=%s dvs=%s%s",
                    i, tostring(ml.line):sub(1,80), tostring(ml.range),
                    tostring(ml.valueScalar), tostring(ml.displayValueScalar), marker))
            end
        end
    end
end

print("\n=== DONE ===")
