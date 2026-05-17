-- Dump Druid ward regen sources.
-- Usage:
--   LEB_BUILD="spec/TestBuilds/1.4/QeY7m5Xq lv97 Druid.xml" busted --lua=luajit --run=dumpDruidWard

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
print(string.format("output.LifeRegen          = %s", tostring(output.LifeRegen)))
print(string.format("output.WardPerSecond      = %s", tostring(output.WardPerSecond)))
print(string.format("output.Ward               = %s", tostring(output.Ward)))
print(string.format("output.WardDecayThreshold = %s", tostring(output.WardDecayThreshold)))
print(string.format("output.WardRetention      = %s", tostring(output.WardRetention)))
print(string.format("output.WardDecayPerSecond = %s", tostring(output.WardDecayPerSecond)))
print(string.format("output.NetWardRegen       = %s", tostring(output.NetWardRegen)))
print(string.format("Sum BASE LifeRegenAppliesToWard = %s", tostring(modDB:Sum("BASE", nil, "LifeRegenAppliesToWard"))))
print(string.format("Sum BASE WardPerSecond  = %s", tostring(modDB:Sum("BASE", nil, "WardPerSecond"))))
print(string.format("Sum INC  WardPerSecond  = %s", tostring(modDB:Sum("INC",  nil, "WardPerSecond"))))
print(string.format("Sum INC  Ward           = %s", tostring(modDB:Sum("INC",  nil, "Ward"))))

local items = build.itemsTab.items
for _, slot in pairs(build.itemsTab.orderedSlots) do
    if slot.slotName == "Relic" then
        local itemId = build.itemsTab.activeItemSet[slot.slotName] and build.itemsTab.activeItemSet[slot.slotName].selItemId
        local item = itemId and items[itemId]
        if item then
            print("\nRelic: " .. tostring(item.name or "?"))
            for i, ml in ipairs(item.explicitModLines or item.modLines or {}) do
                print(string.format("  modLine[%d] line=%q", i, tostring(ml.line):sub(1,160)))
            end
        end
    end
end

print("\n--- modDB.mods.LifeRegenAppliesToWard ---")
for i, m in ipairs(modDB.mods["LifeRegenAppliesToWard"] or {}) do
    print(string.format("  [%d] %s val=%s src=%s", i, tostring(m.type), tostring(m.value), tostring(m.source)))
end

print("\n--- modDB.mods.WardPerSecond ---")
for i, m in ipairs(modDB.mods["WardPerSecond"] or {}) do
    print(string.format("  [%d] %s val=%s src=%s", i, tostring(m.type), tostring(m.value), tostring(m.source)))
end

print("\n=== DONE ===")
