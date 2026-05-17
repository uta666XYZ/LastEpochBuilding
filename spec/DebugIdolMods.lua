-- Debug: inspect parsed mods on a target idol.
-- Configure with env: LEB_BUILD (XML path) + LEB_IDOL_NAME (substring match).
local path = os.getenv("LEB_BUILD")
local needle = os.getenv("LEB_IDOL_NAME")
if not path or path == "" then error("LEB_BUILD required") end
if not needle or needle == "" then error("LEB_IDOL_NAME required") end

local fileHnd = io.open(path, "r")
if not fileHnd then error("Cannot open: " .. path) end
local importCode = fileHnd:read("*a"); fileHnd:close()

newBuild()
loadBuildFromXML(importCode, path)
build.buildFlag = true
runCallback("OnFrame")
build.calcsTab:BuildOutput()

local itemsTab = build.itemsTab
print(string.format("=== Looking for %s ===", needle))
for id, item in pairs(itemsTab.items) do
    if item and item.name and item.name:find(needle, 1, true) then
        print(string.format("\n>>> Item id=%s name=%s baseName=%s", tostring(id), tostring(item.name), tostring(item.baseName)))
        if item.base then
            print(string.format("    base.affixEffectModifier=%s", tostring(item.base.affixEffectModifier)))
        end
        print(string.format("\n--- raw text (first 1200 chars) ---\n%s", (item.raw or ""):sub(1, 1200)))
        print("\n--- explicitModLines ---")
        for i, ml in ipairs(item.explicitModLines) do
            print(string.format("[%d] line=%q range=%s scalar=%s rounding=%s kind=%s",
                i, tostring(ml.line), tostring(ml.range), tostring(ml.valueScalar),
                tostring(ml.rounding), tostring(ml.kind)))
            if ml.modList then
                for j, m in ipairs(ml.modList) do
                    if type(m.value) == "table" and m.value.mod then
                        local im = m.value.mod
                        print(string.format("    mod[%d] %s LIST -> inner name=%s type=%s value=%s",
                            j, tostring(m.name), tostring(im.name), tostring(im.type), tostring(im.value)))
                    else
                        print(string.format("    mod[%d] name=%s type=%s value=%s",
                            j, tostring(m.name), tostring(m.type), tostring(m.value)))
                    end
                end
            end
        end
    end
end
