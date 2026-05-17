-- Dump LEB Idol grid evaluation (NoLargerIdolsAboveSmaller condition).
-- Prints cellOwner occupancy + per-column walk trace + final condition.
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

-- Reproduce LEB grid eval (mirrors CalcSetup.lua:1356-1407)
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

-- Access env.player.itemList -> map by slot
local itemBySlot = {}
local itemSet = build.itemsTab.activeItemSet
for slotName, slot in pairs(itemSet) do
    if type(slot) == "table" and slot.selItemId and slot.selItemId ~= 0 then
        local item = build.itemsTab.items[slot.selItemId]
        if item then itemBySlot[slotName] = item end
    end
end

local cellOwner = {}
for r = 1, 5 do cellOwner[r] = {} end
for r = 1, 5 do
    for c = 1, 5 do
        local item = itemBySlot[idolGridSlots[r][c]]
        if item and item.type and idolDims[item.type] then
            local w, h = idolDims[item.type][1], idolDims[item.type][2]
            local size = w * h
            for dr = 0, h - 1 do
                for dc = 0, w - 1 do
                    local rr, cc = r + dr, c + dc
                    if rr <= 5 and cc <= 5 and not cellOwner[rr][cc] then
                        cellOwner[rr][cc] = { id = item, size = size, topRow = r, slot = idolGridSlots[r][c] }
                    end
                end
            end
        end
    end
end

print("=========================================")
print("Build:", path)
print("=========================================")
print("\n=== Idol Grid (cellOwner.size, top-left = (1,1)) ===")
for r = 1, 5 do
    local line = "  "
    for c = 1, 5 do
        local o = cellOwner[r][c]
        line = line .. string.format("%3s ", o and tostring(o.size) or ".")
    end
    print(line)
end

print("\n=== Idol items per cell (top-row origin) ===")
local seen = {}
for r = 1, 5 do
    for c = 1, 5 do
        local o = cellOwner[r][c]
        if o and not seen[o.id] then
            seen[o.id] = true
            print(string.format("  (r=%d,c=%d) size=%d %s [%s] type=%s",
                o.topRow, c, o.size, o.slot, tostring(o.id.title or o.id.name), tostring(o.id.type)))
        end
    end
end

print("\n=== Per-column walk (top -> bottom, no larger above smaller) ===")
local violation, violationCol, violationDetail = false, nil, nil
for col = 1, 5 do
    local prevSize, prevId = nil, nil
    local trace = {}
    for row = 1, 5 do
        local owner = cellOwner[row][col]
        if owner and owner.id ~= prevId then
            if prevSize and owner.size < prevSize then
                table.insert(trace, string.format("r%d size=%d <BELOW r-1 size=%d VIOLATION", row, owner.size, prevSize))
                violation = true
                violationCol = col
                violationDetail = string.format("col=%d: size %d at row %d sits below size %d", col, owner.size, row, prevSize)
                break
            end
            table.insert(trace, string.format("r%d size=%d", row, owner.size))
            prevSize = owner.size
            prevId = owner.id
        end
    end
    print(string.format("  col %d: %s", col, table.concat(trace, " -> ")))
    if violation then break end
end

print()
print(string.format("violation = %s", tostring(violation)))
if violation then print(string.format("  detail: %s", violationDetail)) end
print(string.format("modDB.conditions.NoLargerIdolsAboveSmaller = %s",
    tostring(modDB.conditions["NoLargerIdolsAboveSmaller"])))
