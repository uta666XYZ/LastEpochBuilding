-- Deep Armour breakdown dump for a single build.
-- Usage:
--   LEB_BUILD="spec/TestBuilds/1.4/<NAME>.xml" busted --lua=luajit --run=dumpArmourFull

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
    print("[ERR] no env.player.modDB — calc env missing")
    return
end
local modDB = env.player.modDB
local output = env.player.output

print("=========================================")
print("Build:", path)
print("=========================================")
print(string.format("output.Armour = %s", tostring(output.Armour)))
print(string.format("output.ArmourBase = %s", tostring(output.ArmourBase)))
print(string.format("output.ArmourInc  = %s", tostring(output.ArmourInc)))
print(string.format("output.ArmourMore = %s", tostring(output.ArmourMore)))
print(string.format("Sum BASE Armour,ArmourAndEvasion = %s", tostring(modDB:Sum("BASE", nil, "Armour", "ArmourAndEvasion"))))
print(string.format("Sum INC  Armour,ArmourAndEvasion,Defences = %s", tostring(modDB:Sum("INC",  nil, "Armour", "ArmourAndEvasion", "Defences"))))
print(string.format("More     Armour,ArmourAndEvasion,Defences = %s", tostring(modDB:More(nil, "Armour", "ArmourAndEvasion", "Defences"))))
print(string.format("output.Str=%s Brutality=%s Att=%s", tostring(output.Str), tostring(output.Brutality), tostring(output.Att)))

-- modDB:List with full ListSources behavior
local function dumpKey(k)
    print(string.format("\n--- modDB.mods[%q] ---", k))
    local mods = modDB.mods[k]
    if not mods then print("(empty)"); return end
    for i, m in ipairs(mods) do
        local tagInfo = ""
        for ti = 1, #m do
            local t = m[ti]
            tagInfo = tagInfo .. "{" .. (t.type or "?")
            for tk, tv in pairs(t) do
                if tk ~= "type" then
                    tagInfo = tagInfo .. " " .. tk .. "=" .. tostring(tv)
                end
            end
            tagInfo = tagInfo .. "}"
        end
        print(string.format("  [%d] %s %s val=%s src=%s tags=%s",
            i, tostring(m.type), tostring(m.name or k), tostring(m.value), tostring(m.source), tagInfo))
    end
end

dumpKey("Armour")
dumpKey("ArmourAndEvasion")
dumpKey("Defences")

-- Try ListSources for Armour BASE and INC
print("\n=== modDB:ListSources (BASE, Armour) ===")
local ok1, baseSrcs = pcall(modDB.ListSources, modDB, "BASE", nil, "Armour", "ArmourAndEvasion")
if ok1 and baseSrcs then
    for k, v in pairs(baseSrcs) do
        print(string.format("  %s -> %s", tostring(k), tostring(v)))
    end
else
    print("  (no ListSources or err: "..tostring(baseSrcs)..")")
end

print("\n=== modDB:ListSources (INC, Armour+ArmourAndEvasion+Defences) ===")
local ok2, incSrcs = pcall(modDB.ListSources, modDB, "INC", nil, "Armour", "ArmourAndEvasion", "Defences")
if ok2 and incSrcs then
    for k, v in pairs(incSrcs) do
        print(string.format("  %s -> %s%%", tostring(k), tostring(v)))
    end
else
    print("  (no ListSources or err: "..tostring(incSrcs)..")")
end

-- Per-tag mods that may slip through
print("\n=== Defences-tagged mods affecting INC ===")
local incMods = modDB:List(nil, "Defences") or {}
for i, m in ipairs(incMods) do
    if m.type == "INC" or m.type == "BASE" then
        print(string.format("  %s %s val=%s src=%s name=%s", m.type, m.name or "?", m.value or "?", m.source or "?", m.name or "?"))
    end
end

print("\n=== DONE ===")
