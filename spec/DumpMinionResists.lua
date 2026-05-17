-- Minion All-Resistance breakdown dump.
-- Usage:
--   LEB_BUILD="spec/TestBuilds/1.4/<NAME>.xml" busted --lua=luajit --run=dumpMinionResists

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
local resistNames = {"FireResist","ColdResist","LightningResist","PhysicalResist","NecroticResist","PoisonResist","VoidResist"}
for _, rn in ipairs(resistNames) do
    print(string.format("output.Minion%s = %s", rn, tostring(output["Minion"..rn])))
end

print("\n=== modDB:List(nil, 'MinionModifier') resist entries ===")
local byResist = {}
for _, rn in ipairs(resistNames) do byResist[rn] = {} end

for i, value in ipairs(modDB:List(nil, "MinionModifier")) do
    local m = value.mod
    if m and m.name then
        for _, rn in ipairs(resistNames) do
            if m.name == rn then
                table.insert(byResist[rn], {idx=i, mod=m, outerSrc=value.source})
                break
            end
        end
    end
end

for _, rn in ipairs(resistNames) do
    print(string.format("\n--- Minion %s (%d entries) ---", rn, #byResist[rn]))
    for _, e in ipairs(byResist[rn]) do
        local m = e.mod
        local tagStr = ""
        for ti = 1, #m do
            local t = m[ti]
            tagStr = tagStr .. "{" .. (t.type or "?")
            for tk, tv in pairs(t) do
                if tk ~= "type" then tagStr = tagStr .. " " .. tk .. "=" .. tostring(tv) end
            end
            tagStr = tagStr .. "}"
        end
        local eff = modDB:EvalMod(m)
        print(string.format("  [#%d] type=%s value=%s eff=%s source=%s tags=%s",
            e.idx, tostring(m.type), tostring(m.value), tostring(eff), tostring(m.source), tagStr))
    end
end
