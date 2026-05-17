-- Dump Lethal Mirage cooldown-related outputs for a build XML.
-- Usage: LEB_BUILD=path/to/build.xml busted --lua=luajit --run=dumpLethalMirageCD
-- Output: writes <xml-without-ext>.lethalmirage_cd.tsv
local target = os.getenv("LEB_BUILD")
if not target or target == "" then
    error("LEB_BUILD env var required (path to build XML)")
end

local fileHnd, err = io.open(target, "r")
if not fileHnd then error("Cannot open: " .. tostring(err)) end
local importCode = fileHnd:read("*a"); fileHnd:close()
loadBuildFromXML(importCode, target)
build.calcsTab:BuildOutput()

local outPath = target:gsub("%.xml$", "") .. ".lethalmirage_cd.tsv"
local outHnd, err2 = io.open(outPath, "w+")
if not outHnd then error("Cannot write " .. outPath .. ": " .. tostring(err2)) end

outHnd:write("scope\tskill\tkey\tvalue\n")

local function writeKV(scope, skill, key, value)
    outHnd:write(string.format("%s\t%s\t%s\t%s\n", scope, skill, key,
        tostring(value)))
end

-- Player root outputs
local mainOutput = build.calcsTab.mainOutput or {}
local keys = {
    "Cooldown",
    "Speed",
    "HitSpeed",
    "HitRate",
    "HitsPerSecond",
    "AverageHit",
    "AverageDamage",
    "TotalDPS",
    "CooldownRecoveryOnHit",
    "CooldownRecoveryOnHitMaxPerCast",
    "Repeats",
    "HitChance",
    "CritChance",
}
for _, k in ipairs(keys) do
    writeKV("mainOutput", "*", k, mainOutput[k])
end

-- Iterate active skills + their breakdowns
local mainEnv = build.calcsTab.mainEnv
if mainEnv and mainEnv.player and mainEnv.player.activeSkillList then
    for i, skill in ipairs(mainEnv.player.activeSkillList) do
        local name = (skill.activeEffect and skill.activeEffect.grantedEffect
            and skill.activeEffect.grantedEffect.name) or ("skill" .. i)
        local out = skill.skillFlags and skill.skillData or {}
        local skillOutput = mainEnv.player.output_by_skill and mainEnv.player.output_by_skill[i]
            or skill.output or {}
        for _, k in ipairs(keys) do
            writeKV("activeSkill", name, k, skillOutput[k])
        end
        -- Skill data raw (base cooldown)
        writeKV("activeSkill", name, "skillData.cooldown",
            skill.skillData and skill.skillData.cooldown)
    end
end

-- Diagnostic: enumerate every CooldownRecoveryOnHit* BASE mod across
-- candidate modList sources, with full tag dump.
local function dumpModsByName(label, modDB, name)
    if not modDB or not modDB.mods then
        outHnd:write(string.format("\n# diag: %s mods=nil\n", label)); return
    end
    local list = modDB.mods[name]
    if not list then
        outHnd:write(string.format("\n# diag: %s.mods[%s] = nil\n", label, name)); return
    end
    outHnd:write(string.format("\n# diag: %s.mods[%s] (n=%d)\n", label, name, #list))
    for i, m in ipairs(list) do
        local tags = {}
        for ti, tag in ipairs(m) do
            local kv = {}
            for k, v in pairs(tag) do kv[#kv+1] = k .. "=" .. tostring(v) end
            table.sort(kv)
            tags[#tags+1] = "{" .. table.concat(kv, ",") .. "}"
        end
        outHnd:write(string.format("# [%d] type=%s value=%s source=%s tags=%s\n",
            i, tostring(m.type), tostring(m.value), tostring(m.source), table.concat(tags, "|")))
    end
end

if mainEnv and mainEnv.player then
    local p = mainEnv.player
    for _, name in ipairs({ "CooldownRecoveryOnHit", "CooldownRecoveryOnHitMaxPerCast" }) do
        dumpModsByName("player.modDB", p.modDB, name)
    end
end

-- Dump the BBoC item's rolled mod lines to see what text the parser sees.
local bboc = build.itemsTab and build.itemsTab.items
if bboc then
    for id, item in pairs(bboc) do
        if item.title and item.title:find("Black Blade") then
            outHnd:write(string.format("\n# diag: item[%s] = %s\n", tostring(id), tostring(item.title)))
            for _, listName in ipairs({ "explicitModLines", "implicitModLines", "enchantModLines" }) do
                local list = item[listName]
                if list then
                    for i, ml in ipairs(list) do
                        if ml.line and (ml.line:lower():find("cooldown") or ml.line:lower():find("lethal mirage")) then
                            outHnd:write(string.format("# %s[%d]: line=%q range=%s valueScalar=%s\n",
                                listName, i, tostring(ml.line), tostring(ml.range), tostring(ml.valueScalar)))
                            if ml.modList then
                                for j, mm in ipairs(ml.modList) do
                                    outHnd:write(string.format("#    parsed[%d]: name=%s type=%s value=%s\n",
                                        j, tostring(mm.name), tostring(mm.type), tostring(mm.value)))
                                end
                            end
                        end
                    end
                end
            end
            if item.rawLines then
                for i, line in ipairs(item.rawLines) do
                    if line:lower():find("lethal mirage") or line:lower():find("cooldown recovered") then
                        outHnd:write(string.format("# rawLines[%d]: %q\n", i, line))
                    end
                end
            end
            if item.modList then
                for i, m in ipairs(item.modList) do
                    if m.name == "CooldownRecoveryOnHit" or m.name == "CooldownRecoveryOnHitMaxPerCast" then
                        outHnd:write(string.format("# modList[%d] %s BASE=%s\n", i, m.name, tostring(m.value)))
                    end
                end
            end
        end
    end
end

outHnd:close()
print(string.format("[DumpLethalMirageCD] Wrote %s", outPath))
