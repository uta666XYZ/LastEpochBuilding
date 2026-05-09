-- Dump Qb6WlPE5 Lich Physical Resistance breakdown: list every PhysicalResist
-- mod source so we can identify the missing Ring suffix +22%.
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
print(string.format("output.PhysicalResist      = %s", tostring(output.PhysicalResist)))
print(string.format("output.PhysicalResistTotal = %s", tostring(output.PhysicalResistTotal)))
print(string.format("modDB:Sum BASE PhysicalResist = %s", tostring(modDB:Sum("BASE", nil, "PhysicalResist"))))
print(string.format("modDB:Sum INC  PhysicalResist = %s", tostring(modDB:Sum("INC",  nil, "PhysicalResist"))))

print("\n--- modDB.mods['PhysicalResist'] entries ---")
for i, m in ipairs(modDB.mods["PhysicalResist"] or {}) do
    local val = m.value
    if type(val) == "table" then val = "table:"..(val.type or "?")..":"..tostring(val.value) end
    print(string.format("  [%2d] type=%-6s value=%-12s source=%s", i, tostring(m.type), tostring(val), tostring(m.source)))
end

print("\n--- env.player.itemList (post-filter) ---")
for k, v in pairs(env.player.itemList or {}) do
    print(string.format("  [%s] = %s", tostring(k), tostring(v.title or v.name or v)))
end
print(string.format("characterLevel=%s", tostring(build.characterLevel)))
local r1 = build.itemsTab.items[2]
if r1 then
    print(string.format("Ring 1 item.requirements.level=%s", tostring(r1.requirements and r1.requirements.level)))
    print(string.format("Ring 1 item.affixes count=%d", #(r1.affixes or {})))
    for i, a in ipairs(r1.affixes or {}) do
        print(string.format("    affix[%d] modId=%s type=%s level=%s", i, tostring(a.modId), tostring(a.type), tostring(a.level)))
    end
end

print("\n--- Item set / active set probe ---")
print(string.format("activeItemSetId=%s", tostring(build.itemsTab.activeItemSetId)))
print(string.format("itemSets count=%d", #(build.itemsTab.itemSetOrderList or {})))
local activeSet = build.itemsTab.activeItemSet
if activeSet then
    print("activeItemSet slots:")
    for k, v in pairs(activeSet) do
        if type(v) == "table" then
            print(string.format("  [%s] selItemId=%s itemId=%s", tostring(k), tostring(v.selItemId), tostring(v.itemId)))
        end
    end
end
print("\nbuild.itemsTab.slots active flags:")
for slotName, slot in pairs(build.itemsTab.slots) do
    if not slot.nodeId then
        print(string.format("  %-12s active=%s selItemId=%s", slotName, tostring(slot.active), tostring(slot.selItemId)))
    end
end

print("\n--- Probe other Ring 1 mods in modDB to confirm Ring 1 routing ---")
for _, key in ipairs({"Int", "Health", "ManaSpentGainedAsWard", "NecroticResist", "ElementalResist"}) do
    local entries = modDB.mods[key] or {}
    for i, m in ipairs(entries) do
        local src = tostring(m.source or "")
        if src:find("Font of the Erased") then
            print(string.format("  [%s] type=%s value=%s source=%s", key, tostring(m.type), tostring(m.value), src))
        end
    end
end

print("\n--- Iterate item slots to find Ring 1 / Ring 2 contributions ---")
for slotName, slot in pairs(build.itemsTab.slots) do
    if slotName == "Ring 1" or slotName == "Ring 2" then
        local item = build.itemsTab.items[slot.selItemId]
        if item then
            print(string.format("\n[%s] %s", slotName, item.name or "?"))
            print(string.format("  rarity=%s base=%s title=%s", tostring(item.rarity), tostring(item.baseName), tostring(item.title)))
            print(string.format("  slot.selItemId=%s slot.active=%s slot.alsoActive=%s",
                tostring(slot.selItemId), tostring(slot.active), tostring(slot.alsoActive)))
            print(string.format("  item.errMsg=%s", tostring(item.errMsg)))
            -- output all sources for first 5 mods in modList
            print("  modList full sample:")
            for i, m in ipairs(item.modList or {}) do
                if i <= 14 then
                    print(string.format("    [%2d] name=%-25s type=%-6s value=%s", i, tostring(m.name), tostring(m.type), tostring(m.value)))
                end
            end
            print("  rawLines (last 12):")
            local lines = item.rawLines or {}
            local start = math.max(1, #lines - 12)
            for i = start, #lines do
                print(string.format("    %s", lines[i]))
            end
            -- modList for the item
            local modList = item.modList or item.slotModList and item.slotModList[slotName] or {}
            print(string.format("  modList #%d", #modList))
            for i, m in ipairs(modList) do
                if m.name == "PhysicalResist" then
                    print(string.format("    [%2d] PhysicalResist type=%s value=%s source=%s flags=%s kwFlags=%s",
                        i, tostring(m.type), tostring(m.value), tostring(m.source), tostring(m.flags), tostring(m.keywordFlags)))
                    for ti, t in ipairs(m) do
                        local s = ""
                        if type(t) == "table" then
                            for k, v in pairs(t) do s = s .. tostring(k) .. "=" .. tostring(v) .. "," end
                        else s = tostring(t) end
                        print(string.format("        tag[%d] %s", ti, s))
                    end
                end
            end
            -- Also probe slotModList directly
            if item.slotModList and item.slotModList[slotName] then
                print(string.format("  slotModList[%s] #%d", slotName, #item.slotModList[slotName]))
                for i, m in ipairs(item.slotModList[slotName]) do
                    if m.name == "PhysicalResist" then
                        print(string.format("    [%2d] PhysicalResist type=%s value=%s source=%s", i, tostring(m.type), tostring(m.value), tostring(m.source)))
                    end
                end
            end
        end
    end
end
