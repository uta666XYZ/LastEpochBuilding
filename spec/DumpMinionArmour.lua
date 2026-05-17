-- Minion Armour breakdown dump.
-- Usage:
--   LEB_BUILD="spec/TestBuilds/1.4/<NAME>.xml" busted --lua=luajit --run=dumpMinionArmour

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
local modDB = env.player.modDB
local output = env.player.output

print("=========================================")
print("Build:", path)
print("=========================================")
print(string.format("output.MinionArmour    = %s", tostring(output.MinionArmour)))
print(string.format("output.MinionArmourInc = %s", tostring(output.MinionArmourInc)))

-- Replicate sumMinion logic but with source info
local minionMods = {}
local minionModSources = {}
for _, value in ipairs(modDB:List(nil, "MinionModifier")) do
    local m = value.mod
    if m and m.name and m.type and m.name:find("Armour") then
        local key = m.name .. "|" .. m.type
        local effective = modDB:EvalMod(m)
        if type(effective) == "number" then
            minionMods[key] = (minionMods[key] or 0) + effective
            minionModSources[key] = minionModSources[key] or {}
            local srcInfo = string.format("%s val=%s eff=%s outerSrc=%s",
                tostring(m.source), tostring(m.value), tostring(effective), tostring(value.mod and value.source or "?"))
            -- Build flag tag info
            local tagStr = ""
            for ti = 1, #m do
                local t = m[ti]
                tagStr = tagStr .. "{" .. (t.type or "?")
                for tk, tv in pairs(t) do
                    if tk ~= "type" then tagStr = tagStr .. " " .. tk .. "=" .. tostring(tv) end
                end
                tagStr = tagStr .. "}"
            end
            table.insert(minionModSources[key], srcInfo .. " tags=" .. tagStr)
        end
    end
end

print("\n=== MinionModifier (Armour entries) ===")
for key, total in pairs(minionMods) do
    print(string.format("  [%s] total=%s", key, tostring(total)))
    for _, src in ipairs(minionModSources[key]) do
        print("    - " .. src)
    end
end

-- Also dump the wrapper MinionModifier entries directly
print("\n=== Raw modDB:List(nil, 'MinionModifier') entries with Armour ===")
for i, value in ipairs(modDB:List(nil, "MinionModifier")) do
    local m = value.mod
    if m and m.name and m.name:find("Armour") then
        print(string.format("  [%d] outer.source=%s inner.name=%s inner.type=%s inner.value=%s inner.source=%s",
            i, tostring(value.source), tostring(m.name), tostring(m.type), tostring(m.value), tostring(m.source)))
    end
end
