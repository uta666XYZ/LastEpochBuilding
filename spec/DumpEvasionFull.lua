-- Deep Evasion (Dodge Rating) breakdown for a single build.
-- Usage:
--   LEB_BUILD="spec/TestBuilds/1.4/<NAME>.xml" busted --lua=luajit --run=dumpEvasionFull

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

local function fmt(x) return tostring(x) end

print("=========================================")
print("Build:", path)
print("=========================================")
print(string.format("output.Evasion         = %s", fmt(output.Evasion)))
print(string.format("output.MeleeEvasion    = %s", fmt(output.MeleeEvasion)))
print(string.format("output.AttackDodgeChance = %s", fmt(output.AttackDodgeChance)))

local sumBaseEv  = modDB:Sum("BASE", nil, "Evasion", "ArmourAndEvasion")
local sumIncEv   = modDB:Sum("INC",  nil, "Evasion", "ArmourAndEvasion", "Defences")
local moreEv     = modDB:More(nil, "Evasion", "ArmourAndEvasion", "Defences")
print(string.format("Sum BASE Evasion,ArmourAndEvasion              = %s", fmt(sumBaseEv)))
print(string.format("Sum INC  Evasion,ArmourAndEvasion,Defences     = %s%%", fmt(sumIncEv)))
print(string.format("More     Evasion,ArmourAndEvasion,Defences     = %sx", fmt(moreEv)))
print(string.format("Computed = %s * (1+%s/100) * %s = %s",
    fmt(sumBaseEv), fmt(sumIncEv), fmt(moreEv),
    fmt(sumBaseEv * (1 + sumIncEv/100) * moreEv)))

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
        print(string.format("  [%d] %s val=%s src=%s tags=%s",
            i, fmt(m.type), fmt(m.value), fmt(m.source), tagInfo))
    end
end

dumpKey("Evasion")
dumpKey("ArmourAndEvasion")

print("\n=== ListSources BASE Evasion (+ ArmourAndEvasion) ===")
local ok1, baseSrcs = pcall(modDB.ListSources, modDB, "BASE", nil, "Evasion", "ArmourAndEvasion")
if ok1 and baseSrcs then
    for k, v in pairs(baseSrcs) do print(string.format("  %s -> %s", fmt(k), fmt(v))) end
else
    print("  (no/err: "..fmt(baseSrcs)..")")
end

print("\n=== ListSources INC Evasion (+ ArmourAndEvasion + Defences) ===")
local ok2, incSrcs = pcall(modDB.ListSources, modDB, "INC", nil, "Evasion", "ArmourAndEvasion", "Defences")
if ok2 and incSrcs then
    for k, v in pairs(incSrcs) do print(string.format("  %s -> %s%%", fmt(k), fmt(v))) end
else
    print("  (no/err: "..fmt(incSrcs)..")")
end

print("\n=== ListSources MORE Evasion (+ ArmourAndEvasion + Defences) ===")
local ok3, moreSrcs = pcall(modDB.ListSources, modDB, "MORE", nil, "Evasion", "ArmourAndEvasion", "Defences")
if ok3 and moreSrcs then
    for k, v in pairs(moreSrcs) do print(string.format("  %s -> %sx", fmt(k), fmt(v))) end
else
    print("  (no/err: "..fmt(moreSrcs)..")")
end

print("\n=== Multipliers (via modDB:Sum BASE Multiplier:X) ===")
for _, name in ipairs({"EquippedCorruptedIdol","CorruptedItemsEquipped","CorruptedIdolItemsEquipped","CorruptedNonIdolItemsEquipped","EquippedOmenIdol","IdolInRefractedSlot","RawDex","RawStr","RawAtt","RawVit","RawInt"}) do
    print(string.format("  %s = %s", name, tostring(modDB:Sum("BASE", nil, "Multiplier:"..name))))
end

print("\n=== Conditions (Evasion-related) ===")
for _, k in ipairs({"UsingSmokeBomb","ChannellingSmokeBomb","ShadowDaggers","SynchronizedStrike","Stealth","HasShadow"}) do
    local v = modDB.conditions and modDB.conditions[k]
    if v ~= nil then print(string.format("  %s = %s", k, tostring(v))) end
end

print("\n=== Per-item Evasion mod attribution ===")
-- Walk every modDB Evasion mod and add up tagged Multipliers in resolved form
local total = 0
for _, m in ipairs(modDB.mods["Evasion"] or {}) do
    if m.type == "BASE" then
        local v = m.value
        local applied = true
        local mults = ""
        for ti = 1, #m do
            local t = m[ti]
            if t.type == "Multiplier" then
                local mv = (modDB.multipliers and modDB.multipliers[t.var]) or 0
                v = v * mv
                mults = mults .. string.format(" *%s(%s)=%s", t.var, mv, v)
            elseif t.type == "PerStat" then
                local sv = (build.calcsTab.mainEnv.player.output[t.stat]) or 0
                v = v * sv
                mults = mults .. string.format(" *%s(%s)=%s", t.stat, sv, v)
            elseif t.type == "SkillId" or t.type == "Condition" then
                local cv = modDB.conditions and modDB.conditions[t.var or "?"]
                mults = mults .. string.format(" cond:%s=%s", t.var or t.skillId, tostring(cv))
                if t.type == "Condition" and not cv then applied = false end
            end
        end
        if applied then total = total + v end
        print(string.format("  %s %s%s  src=%s applied=%s",
            m.type, m.value, mults, m.source, tostring(applied)))
    end
end
print(string.format("  total resolved BASE = %s", total))

print("\n=== DONE ===")
