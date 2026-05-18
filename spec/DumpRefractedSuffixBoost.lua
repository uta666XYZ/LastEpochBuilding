-- Lane D probe: Sunset Auric Altar refracted-slot suffix-boost diagnosis.
-- Prints altarBoost* values, fracturedItemSet membership, per-idol affix
-- modId/sat/postRoundScalar, and PhysicalResist mod sources in modDB.
local path = os.getenv("LEB_BUILD")
if not path or path == "" then error("LEB_BUILD is required") end
local fh = io.open(path, "r"); if not fh then error("Cannot open: " .. path) end
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
print(string.format("activeAltarLayout = %s", tostring(build.itemsTab.activeAltarLayout)))

local itemsBySlot = {}
local activeSet = build.itemsTab.activeItemSet
for slotName, slot in pairs(activeSet or {}) do
    if type(slot) == "table" and slot.selItemId and slot.selItemId ~= 0 then
        local it = build.itemsTab.items[slot.selItemId]
        if it then itemsBySlot[slotName] = it end
    end
end

local altarItem = itemsBySlot["Idol Altar"]
print(string.format("\nIdol Altar slot item = %s", tostring(altarItem and (altarItem.title or altarItem.name) or "nil")))
if altarItem and altarItem.modList then
    print(string.format("Idol Altar modList (%d entries):", #altarItem.modList))
    for i, m in ipairs(altarItem.modList) do
        print(string.format("  [%2d] name=%-30s type=%-6s value=%s", i, tostring(m.name), tostring(m.type), tostring(m.value)))
    end
end

print(string.format("\nCountIdolsOnRefractedCells = %s", tostring(build.itemsTab:CountIdolsOnRefractedCells())))

-- Replicate fracturedItemSet eval
local idolDims = {
    ["Minor Idol"] = {1,1}, ["Small Idol"] = {1,1}, ["Humble Idol"] = {2,1},
    ["Stout Idol"] = {1,2}, ["Grand Idol"] = {3,1}, ["Large Idol"] = {1,3},
    ["Ornate Idol"] = {4,1}, ["Huge Idol"] = {1,4}, ["Adorned Idol"] = {2,2},
}
local idolGridSlots = {
    { "Idol 21", "Idol 1",  "Idol 2",  "Idol 3",  "Idol 22" },
    { "Idol 4",  "Idol 5",  "Idol 6",  "Idol 7",  "Idol 8"  },
    { "Idol 9",  "Idol 10", "Idol 23", "Idol 11", "Idol 12" },
    { "Idol 13", "Idol 14", "Idol 15", "Idol 16", "Idol 17" },
    { "Idol 24", "Idol 18", "Idol 19", "Idol 20", "Idol 25" },
}
local altarLayouts = build.itemsTab.altarLayouts
local altarName = build.itemsTab.activeAltarLayout
local altar = altarName and altarName ~= "Default" and altarLayouts and altarLayouts[altarName]
if altar and altar.grid then
    print(string.format("\nAltar layout grid (%s):", altarName))
    for r = 1, 5 do
        local line = "  "
        for c = 1, 5 do
            line = line .. (altar.grid[r] and tostring(altar.grid[r][c] or 0) or "0") .. " "
        end
        print(line)
    end
end

print("\n=== fracturedItemSet (replicated) ===")
local fracturedItemSet = {}
if altar and altar.grid then
    for r = 1, 5 do
        for c = 1, 5 do
            local item = itemsBySlot[idolGridSlots[r][c]]
            if item and item.type and idolDims[item.type] and not fracturedItemSet[item] then
                local w, h = idolDims[item.type][1], idolDims[item.type][2]
                local hit = false
                for dr = 0, h - 1 do
                    for dc = 0, w - 1 do
                        local row = altar.grid[r + dr]
                        if row and row[c + dc] == 2 then hit = true; break end
                    end
                    if hit then break end
                end
                if hit then fracturedItemSet[item] = true end
            end
        end
    end
end
local fracturedCount = 0
for it in pairs(fracturedItemSet) do
    fracturedCount = fracturedCount + 1
    print(string.format("  [%d] %s type=%s", fracturedCount, tostring(it.title or it.name), tostring(it.type)))
    if it.prefixes then
        for i, a in ipairs(it.prefixes) do
            print(string.format("    prefix[%d] modId=%s postRoundScalar=%s", i, tostring(a.modId), tostring(a.postRoundScalar)))
        end
    end
    if it.suffixes then
        for i, a in ipairs(it.suffixes) do
            print(string.format("    suffix[%d] modId=%s postRoundScalar=%s", i, tostring(a.modId), tostring(a.postRoundScalar)))
        end
    end
end
print(string.format("fracturedCount = %d", fracturedCount))

print("\n=== env.player.itemList (post-cloneWithAltarBoost) ===")
for slotName, item in pairs(env.player.itemList or {}) do
    if slotName:match("^Idol ") then
        print(string.format("  [%s] %s", slotName, tostring(item.title or item.name)))
        if item.prefixes then
            for i, a in ipairs(item.prefixes) do
                print(string.format("    prefix[%d] modId=%s postRoundScalar=%s", i, tostring(a.modId), tostring(a.postRoundScalar)))
            end
        end
        if item.suffixes then
            for i, a in ipairs(item.suffixes) do
                print(string.format("    suffix[%d] modId=%s postRoundScalar=%s", i, tostring(a.modId), tostring(a.postRoundScalar)))
            end
        end
        if item.modList then
            for _, m in ipairs(item.modList) do
                if m.name == "PhysicalResist" or m.name == "MinionPhysicalResist" then
                    print(string.format("    modList: name=%s type=%s value=%s source=%s", tostring(m.name), tostring(m.type), tostring(m.value), tostring(m.source)))
                end
            end
        end
    end
end

print("\n=== modDB.mods PhysicalResist (Idol sources only) ===")
for _, m in ipairs(modDB.mods["PhysicalResist"] or {}) do
    local src = tostring(m.source or "")
    if src:find("Idol") or src:find("Chitin") then
        print(string.format("  type=%-6s value=%-6s source=%s", tostring(m.type), tostring(m.value), src))
    end
end
print("\n=== modDB.mods MinionPhysicalResist (all) ===")
for _, m in ipairs(modDB.mods["MinionPhysicalResist"] or {}) do
    print(string.format("  type=%-6s value=%-6s source=%s", tostring(m.type), tostring(m.value), tostring(m.source)))
end

print(string.format("\noutput.PhysicalResistTotal = %s (expected 84)", tostring(output.PhysicalResistTotal)))
print(string.format("output.PhysicalResist      = %s", tostring(output.PhysicalResist)))
