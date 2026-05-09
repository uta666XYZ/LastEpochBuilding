-- Dump all 7 resists for the build set in LEB_BUILD: print modDB BASE sum
-- (float) AND output.<elem>ResistTotal so we can identify any remaining Δ=-1.
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
local elems = {"Physical","Fire","Cold","Lightning","Necrotic","Poison","Void"}
for _, e in ipairs(elems) do
    local key = e .. "Resist"
    local baseSum = modDB:Sum("BASE", nil, key)
    local incSum  = modDB:Sum("INC",  nil, key)
    print(string.format("\n%-10s | output.%-18s = %s | BASE=%s | INC=%s",
        e, e .. "ResistTotal", tostring(output[key .. "Total"]), tostring(baseSum), tostring(incSum)))
    -- enumerate non-int sources only
    for i, m in ipairs(modDB.mods[key] or {}) do
        local val = m.value
        if type(val) == "number" then
            print(string.format("  [%2d] type=%-6s value=%-12s source=%s",
                i, tostring(m.type), tostring(val), tostring(m.source)))
        end
    end
end
