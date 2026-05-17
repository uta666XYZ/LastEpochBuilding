-- Deep Ward Regen (WardPerSecond / NetWardRegen) breakdown for a single build.
-- Usage:
--   LEB_BUILD="spec/TestBuilds/1.4/<NAME>.xml" busted --lua=luajit --run=dumpWardRegen

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
print(string.format("output.Ward             = %s", fmt(output.Ward)))
print(string.format("output.WardPerSecond    = %s", fmt(output.WardPerSecond)))
print(string.format("output.WardDecayPerSec  = %s", fmt(output.WardDecayPerSecond)))
print(string.format("output.NetWardRegen     = %s", fmt(output.NetWardRegen)))
print(string.format("output.WardRetention    = %s", fmt(output.WardRetention)))
print(string.format("output.WardDecayThresh  = %s", fmt(output.WardDecayThreshold)))
print(string.format("output.ManaPerSecondCost= %s", fmt(output.ManaPerSecondCost)))

local sumBase = modDB:Sum("BASE", nil, "WardPerSecond")
local sumInc  = modDB:Sum("INC",  nil, "WardPerSecond")
local moreVal = modDB:More(nil, "WardPerSecond")
print(string.format("Sum BASE WardPerSecond  = %s", fmt(sumBase)))
print(string.format("Sum INC  WardPerSecond  = %s%%", fmt(sumInc)))
print(string.format("More     WardPerSecond  = %sx", fmt(moreVal)))
print(string.format("Computed = %s * (1+%s/100) * %s = %s",
    fmt(sumBase), fmt(sumInc), fmt(moreVal),
    fmt(sumBase * (1 + sumInc/100) * moreVal)))

local mspW = modDB:Sum("BASE", nil, "ManaSpentGainedAsWard")
print(string.format("ManaSpentGainedAsWard   = %s%% (bonus = ManaPerSec * %s/100)", fmt(mspW), fmt(mspW)))

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

dumpKey("WardPerSecond")
dumpKey("ManaSpentGainedAsWard")
dumpKey("CurrentManaGainedAsWardPerSecond")
dumpKey("MissingHealthGainedAsWardPerSecond")
dumpKey("LifeRegenAppliesToWard")
dumpKey("WardRetention")
dumpKey("WardDecayThreshold")

print(string.format("\noutput.CurrentMana       = %s", fmt(output.Mana)))
print(string.format("output.MissingHealthPct  = %s", fmt(output.MissingHealthPercent)))
print(string.format("output.Life              = %s", fmt(output.Life)))
print(string.format("output.LifeRegen         = %s", fmt(output.LifeRegen)))

print("\n=== Per-mod BASE WardPerSecond attribution ===")
local total = 0
for _, m in ipairs(modDB.mods["WardPerSecond"] or {}) do
    if m.type == "BASE" then
        local v = m.value
        local applied = true
        local mults = ""
        for ti = 1, #m do
            local t = m[ti]
            if t.type == "Multiplier" then
                local mv = modDB:Sum("BASE", nil, "Multiplier:"..t.var) or 0
                v = v * mv
                mults = mults .. string.format(" *Mult:%s(%s)=%s", t.var, mv, v)
            elseif t.type == "PerStat" then
                local sv = output[t.stat] or 0
                v = v * sv
                mults = mults .. string.format(" *PerStat:%s(%s)=%s", t.stat, sv, v)
            elseif t.type == "Condition" then
                local cv = modDB.conditions and modDB.conditions[t.var or "?"]
                mults = mults .. string.format(" cond:%s=%s", t.var or "?", tostring(cv))
                if not cv then applied = false end
            elseif t.type == "SkillId" then
                mults = mults .. string.format(" SkillId:%s", t.skillId or "?")
            end
        end
        if applied then total = total + v end
        print(string.format("  %s %s%s  src=%s applied=%s",
            m.type, m.value, mults, m.source, tostring(applied)))
    end
end
print(string.format("  total resolved BASE = %s", total))

print("\n=== Skills (mainSkill) ===")
if env.player.mainSkill then
    print("  mainSkill:", env.player.mainSkill.activeEffect and env.player.mainSkill.activeEffect.grantedEffect and env.player.mainSkill.activeEffect.grantedEffect.name or "?")
end

print("\n=== Conditions (Ward-related) ===")
for _, k in ipairs({"LowLife","FullWard","CastSpellRecently","CastFireSpellRecently","HitRecently","UsingShield","DualWielding"}) do
    local v = modDB.conditions and modDB.conditions[k]
    if v ~= nil then print(string.format("  %s = %s", k, tostring(v))) end
end

print("\n=== DONE ===")
