-- Dump Endurance + EnduranceThreshold modDB entries for triangulation vs LE.
local path = os.getenv("LEB_BUILD")
if not path or path == "" then error("LEB_BUILD is required") end
local fh = io.open(path, "r")
if not fh then error("Cannot open: " .. path) end
local xml = fh:read("*a"); fh:close()

newBuild()
loadBuildFromXML(xml, path)
build.buildFlag = true
runCallback("OnFrame")
build.calcsTab:BuildOutput()

local env = build.calcsTab.mainEnv
local modDB = env.player.modDB
local output = env.player.output

print("=========================================")
print("Build:", path)
print("=========================================")
for _, k in ipairs({"Endurance","EnduranceTotal","EnduranceOverCap","EnduranceThreshold","EnduranceThresholdValue","Life","LifeAsEnduranceThreshold","Str","FireResistTotal","ColdResistTotal","LightningResistTotal"}) do
    print(string.format("output.%s = %s", k, tostring(output[k])))
end

for _, stat in ipairs({"Endurance","EnduranceThreshold","EnduranceThresholdPerUncappedEleRes","ManaAsEnduranceThreshold","LifeAsEnduranceThreshold","EnduranceThresholdAddedAsWardDecayThreshold"}) do
    print(string.format("\n--- modDB.mods['%s'] ---", stat))
    for i, m in ipairs(modDB.mods[stat] or {}) do
        local val = m.value
        if type(val) == "table" then val = "table:"..(val.type or "?")..":"..tostring(val.value) end
        local tags = {}
        for ti, t in ipairs(m) do tags[#tags+1] = (t.type or "?")..":"..tostring(t.var or t.stat or t.actor or "") end
        print(string.format("  [%2d] type=%-5s value=%-12s tags=%s source=%s",
            i, tostring(m.type), tostring(val), table.concat(tags,","), tostring(m.source)))
    end
    print(string.format("  Sum BASE = %s", tostring(modDB:Sum("BASE", nil, stat))))
    print(string.format("  Sum INC  = %s", tostring(modDB:Sum("INC",  nil, stat))))
end
