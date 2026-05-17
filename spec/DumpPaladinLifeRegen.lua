-- Dump Paladin LifeRegen breakdown for BgRrP5rr drift triangulation.
-- Usage:
--   LEB_BUILD="spec/TestBuilds/1.4/BgRrP5rr lv98 Paladin.xml" busted --lua=luajit --run=dumpPaladinLifeRegen
-- Hypothesis (worktree note L621): Holy Aura multiplier missing + Refracted
-- Slot Mana per Idol unaggregated + OverkillLeech ModParser missing.

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
print(string.format("output.WardPerSecond = %s", tostring(output.WardPerSecond)))
print(string.format("output.NetWardRegen  = %s", tostring(output.NetWardRegen)))
print(string.format("Sum BASE LifeRegen = %s", tostring(modDB:Sum("BASE", nil, "LifeRegen"))))
print(string.format("Sum INC  LifeRegen = %s", tostring(modDB:Sum("INC",  nil, "LifeRegen"))))
print(string.format("Sum MORE LifeRegen = %s", tostring(modDB:Sum("MORE", nil, "LifeRegen"))))

-- Throne of Ambition propagation: LifeRegenAppliesToWard
print(string.format("Sum BASE LifeRegenAppliesToWard = %s", tostring(modDB:Sum("BASE", nil, "LifeRegenAppliesToWard"))))

-- Paladin Faith/Devotion conditions/multipliers
print("\n--- Paladin Faith / Devotion stacks ---")
for _, key in ipairs({"Faith", "Devotion", "FaithStack", "DevotionStack", "HolyAuraActive"}) do
    print(string.format("  Multiplier:%s = %s", key, tostring(modDB.multipliers and modDB.multipliers[key])))
    print(string.format("  Condition:%s   = %s", key, tostring(modDB.conditions and modDB.conditions[key])))
end

print("\n--- Active skills ---")
print(string.format("activeSkillList count = %d", #env.player.activeSkillList))
for i, sk in ipairs(env.player.activeSkillList) do
    local name = tostring(sk.activeEffect and sk.activeEffect.grantedEffect and sk.activeEffect.grantedEffect.name)
    print(string.format("  [%d] %s", i, name))
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

print("\n=== modDB:ListSources MORE LifeRegen ===")
local ok3, moreSrcs = pcall(modDB.ListSources, modDB, "MORE", nil, "LifeRegen")
if ok3 and moreSrcs then
    local keys = {}
    for k in pairs(moreSrcs) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        print(string.format("  %s%%  src=%s", tostring(moreSrcs[k]), tostring(k)))
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

-- Look for overkill/leech-related mod keys
print("\n--- modDB mod keys containing 'Overkill' or 'Leech' ---")
local matchedKeys = {}
for key in pairs(modDB.mods) do
    if tostring(key):find("Overkill") or tostring(key):find("Leech") then
        table.insert(matchedKeys, key)
    end
end
table.sort(matchedKeys)
for _, key in ipairs(matchedKeys) do
    print(string.format("  [%s] count=%d", key, #modDB.mods[key]))
    for i, m in ipairs(modDB.mods[key]) do
        print(string.format("      [%d] %s val=%s src=%s", i, tostring(m.type), tostring(m.value), tostring(m.source)))
    end
end

-- Per-idol modLine dump — Refracted Slot detection
print("\n=========================================")
print("=== Per-idol modLine dump (Refracted Slot + HR) ===")
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
                local line = ml.line or ""
                local hr = line:lower():find("health regen") or line:lower():find("life regen") or line:lower():find("refracted slot") or line:lower():find("overkill")
                local marker = hr and " <== MATCH" or ""
                print(string.format("    modLine[%d] line=%q range=%s vs=%s dvs=%s%s",
                    i, tostring(line):sub(1,120), tostring(ml.range),
                    tostring(ml.valueScalar), tostring(ml.displayValueScalar), marker))
            end
        end
    end
end

print("\n=== DONE ===")
