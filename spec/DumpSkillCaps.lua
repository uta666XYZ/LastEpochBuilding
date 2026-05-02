-- Dump effective skill cap for every active skill in a build XML.
-- Usage: LEB_BUILD=src/Builds/.../foo.xml busted --lua=luajit --run=dumpSkillCaps
-- Output: writes <xml-without-ext>.skillcaps.tsv next to the input XML.
--
-- TSV columns: name, allocated, globalBonus, perSkillBonus, effectiveLevel, skillTypes, attrs
local target = os.getenv("LEB_BUILD")
if not target or target == "" then
    error("LEB_BUILD env var required (path to build XML)")
end

local fileHnd, err = io.open(target, "r")
if not fileHnd then error("Cannot open: " .. tostring(err)) end
local importCode = fileHnd:read("*a"); fileHnd:close()
loadBuildFromXML(importCode, target)
build.calcsTab:BuildOutput()

local outPath = target:gsub("%.xml$", "") .. ".skillcaps.tsv"
local outHnd, err2 = io.open(outPath, "w+")
if not outHnd then error("Cannot write " .. outPath .. ": " .. tostring(err2)) end

outHnd:write("name\tallocated\tglobalBonus\tperSkillBonus\teffective\tskillTypes\tattrs\n")

local groups = build.skillsTab and build.skillsTab.socketGroupList or {}
local globalBonus = build.skillLevelBonus or 0

local function setToList(t)
    if type(t) ~= "table" then return "" end
    local keys = {}
    for k, v in pairs(t) do
        if v then keys[#keys+1] = tostring(k) end
    end
    table.sort(keys)
    return table.concat(keys, "|")
end

for index = 1, #groups do
    local group = groups[index]
    if group and group.grantedEffect then
        local allocated = build.skillsTab:GetUsedSkillPoints(index) or 0
        local perSkill = (build.perSkillLevelBonus and build.perSkillLevelBonus[index]) or 0
        -- Read the authoritative effective level computed in CalcSetup.lua (Base + bonuses).
        local effective = (build.calcsTab and build.calcsTab.mainEnv and build.calcsTab.mainEnv.modDB
            and build.calcsTab.mainEnv.modDB.multipliers
            and build.calcsTab.mainEnv.modDB.multipliers["SkillLevel_" .. tostring(group.grantedEffect.name)])
            or (allocated + globalBonus + perSkill)
        local name = tostring(group.grantedEffect.name or "?")
        local skillTypes = ""
        local attrs = ""
        local ge = group.grantedEffect
        if ge.skillTypes then skillTypes = setToList(ge.skillTypes) end
        if ge.skillAttributes then
            local a = {}
            for k, v in pairs(ge.skillAttributes) do
                if v then a[#a+1] = tostring(k) end
            end
            table.sort(a)
            attrs = table.concat(a, "|")
        end
        outHnd:write(string.format("%s\t%d\t%d\t%d\t%d\t%s\t%s\n",
            name, allocated, globalBonus, perSkill, effective, skillTypes, attrs))
    end
end

outHnd:close()
print(string.format("[DumpSkillCaps] Wrote %s", outPath))
