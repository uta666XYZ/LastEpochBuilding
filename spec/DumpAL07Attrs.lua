-- Dump AL07Kea4 attribute breakdown
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
for _, attr in ipairs({"Str","Dex","Int","Att","Vit","Brutality","Rampancy"}) do
    print(string.format("output.%s = %s  (Raw%s = %s)",
        attr, tostring(output[attr]), attr, tostring(output["Raw"..attr])))
end
print()

for _, attr in ipairs({"Str","Dex","Int","Att","Vit","Brutality","Rampancy"}) do
    print("=== "..attr.." BASE sources ===")
    local ok, srcs = pcall(modDB.ListSources, modDB, "BASE", nil, attr)
    if ok and srcs then
        local keys = {}
        for k in pairs(srcs) do table.insert(keys, k) end
        table.sort(keys)
        local total = 0
        for _, k in ipairs(keys) do
            print(string.format("  +%s  src=%s", tostring(srcs[k]), tostring(k)))
            total = total + (tonumber(srcs[k]) or 0)
        end
        print(string.format("  TOTAL BASE = %s", total))
    else
        print("  (err)")
    end
    print()
end

for _, attr in ipairs({"Vit","Str","Dex","Int","Att"}) do
    print("--- modDB.mods."..attr.." (full) ---")
    for i, m in ipairs(modDB.mods[attr] or {}) do
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
    print()
end

-- old single block kept for reference
print("--- modDB.mods._old_Att placeholder ---")
for i, m in ipairs({}) do
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

print("\n=== DONE ===")
