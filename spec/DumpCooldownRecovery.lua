-- Dump CooldownRecovery modDB entries for triangulation vs LETools.
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
print(string.format("output.CooldownRecovery = %s", tostring(output.CooldownRecovery)))
print(string.format("output.MinionCooldownRecovery = %s", tostring(output.MinionCooldownRecovery)))
print()
print("--- modDB.mods['CooldownRecovery'] ---")
for i, m in ipairs(modDB.mods["CooldownRecovery"] or {}) do
    local val = m.value
    if type(val) == "table" then val = "table:"..(val.type or "?")..":"..tostring(val.value) end
    local tags = {}
    for ti, t in ipairs(m) do tags[#tags+1] = (t.type or "?")..":"..tostring(t.var or t.stat or t.actor or t.skillName or t.skillId or "") end
    print(string.format("  [%2d] type=%-5s value=%-12s tags=%s\n       source=%s",
        i, tostring(m.type), tostring(val), table.concat(tags,","), tostring(m.source)))
end
print(string.format("\n  Sum INC nil tags  = %s", tostring(modDB:Sum("INC", nil, "CooldownRecovery"))))
print(string.format("  Sum INC {} tags   = %s", tostring(modDB:Sum("INC", {}, "CooldownRecovery"))))
