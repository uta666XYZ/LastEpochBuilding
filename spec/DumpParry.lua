-- Dump ParryChance modDB entries + relevant Block context for triangulation.
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
print(string.format("output.ParryChance       = %s", tostring(output.ParryChance)))
print(string.format("output.BlockChance       = %s", tostring(output.BlockChance)))
print(string.format("output.BlockChanceMax    = %s", tostring(output.BlockChanceMax)))
print(string.format("output.ShieldBlockChance = %s", tostring(output.ShieldBlockChance)))
print()
print(string.format("Flag MainHandHas:traitor's tongue = %s", tostring(modDB:Flag(nil, "Condition:MainHandHas:traitor's tongue") or false)))
print(string.format("Cond MainHandHas:traitor's tongue (modDB:Sum trick)"))
for _,c in ipairs({"MainHandHas:traitor's tongue","OffHandHas:traitor's tongue","DualWielding","NotUsingShield","UsingShield"}) do
    print(string.format("  Condition:%s = %s", c, tostring(modDB.conditions and modDB.conditions[c])))
end
print()
for _, key in ipairs({"ParryChance","ParryCap","BlockChance","BlockChanceMax","BlockChanceConvertedToParry"}) do
    print(string.format("--- modDB.mods['%s'] ---", key))
    for i, m in ipairs(modDB.mods[key] or {}) do
        local val = m.value
        if type(val) == "table" then val = "table:"..(val.type or "?")..":"..tostring(val.value) end
        local tags = {}
        for ti, t in ipairs(m) do tags[#tags+1] = (t.type or "?")..":"..tostring(t.var or t.stat or t.actor or t.skillName or t.skillId or "") end
        print(string.format("  [%2d] type=%-5s value=%-12s tags=%s\n       source=%s",
            i, tostring(m.type), tostring(val), table.concat(tags,","), tostring(m.source)))
    end
    print(string.format("  Sum BASE = %s, Sum INC = %s, Sum MORE = %s",
        tostring(modDB:Sum("BASE", nil, key)),
        tostring(modDB:Sum("INC", nil, key)),
        tostring(modDB:Sum("MORE", nil, key))))
    print()
end
