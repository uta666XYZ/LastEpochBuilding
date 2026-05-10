-- Dump Q9J4w8PE Necromancer Health breakdown: list every BASE Life mod and
-- every INC Life mod with source string, so we can compare against LE's
-- tooltip lines.
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
print(string.format("output.Life = %s", tostring(output.Life)))
print(string.format("output.LifeBase = %s", tostring(output.LifeBase)))
print(string.format("output.Vit = %s", tostring(output.Vit)))
print(string.format("modDB:Sum BASE Life = %s", tostring(modDB:Sum("BASE", nil, "Life"))))
print(string.format("modDB:Sum INC  Life = %s", tostring(modDB:Sum("INC",  nil, "Life"))))
print(string.format("modDB:Sum MORE Life = %s", tostring(modDB:Sum("MORE", nil, "Life"))))

print("\n--- All modDB.mods['Life'] entries ---")
for i, m in ipairs(modDB.mods["Life"] or {}) do
    local val = m.value
    if type(val) == "table" then val = "table:"..(val.type or "?")..":"..tostring(val.value) end
    print(string.format("  [%2d] type=%-6s value=%-12s source=%s", i, tostring(m.type), tostring(val), tostring(m.source)))
end

print("\n--- Vit mods ---")
for i, m in ipairs(modDB.mods["Vit"] or {}) do
    print(string.format("  [%2d] type=%-6s value=%-6s source=%s", i, tostring(m.type), tostring(m.value), tostring(m.source)))
end
