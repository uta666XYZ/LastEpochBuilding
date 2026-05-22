-- One-shot: decode a LE offline save via LEB's ReadJsonSaveData, import it into a
-- build, then serialize that build to an LEB XML file (the same format produced by
-- the in-app "Save"). This materializes the 3 in-game builds (which previously had
-- no stored XML) so GenerateBuilds14.lua can snapshot them.
--
-- Usage:
--   LEB_SAVE="<abs path to 1CHARACTERSLOT_BETA_N>" \
--   LEB_XML_OUT="<abs path to output .xml>" \
--   busted --run=importSaveToXML
local savePath = os.getenv("LEB_SAVE")
if not savePath or savePath == "" then error("LEB_SAVE required") end
local outPath = os.getenv("LEB_XML_OUT")
if not outPath or outPath == "" then error("LEB_XML_OUT required") end

local f = io.open(savePath, "rb"); if not f then error("open fail "..savePath) end
local content = f:read("*a"); f:close()

newBuild()
-- Match in-game tooltip rounding (production floor, not LETools rounding).
if itemLib and not os.getenv("LEB_LETOOLS_ROUND") then itemLib.useLEToolsRounding = false end

local importTab = build.importTab
-- save file is EPOCH-prefixed (5 bytes) + JSON
local char = importTab:ReadJsonSaveData(content:sub(6))
print("=== CHAR ===")
print("name="..tostring(char.name).." level="..tostring(char.level)..
      " class="..tostring(char.class).." mastery="..tostring(char.mastery))

importTab:ImportPassiveTreeAndJewels(char)
importTab:ImportItemsAndSkills(char)
build.buildFlag = true
runCallback("OnFrame")
build.calcsTab:BuildOutput()

-- Serialize to LEB XML.
local xmlText = build:SaveDB(outPath)
if not xmlText then error("SaveDB returned nil for "..outPath) end

local out = io.open(outPath, "w"); if not out then error("cannot write "..outPath) end
out:write(xmlText); out:close()
print("=== WROTE XML ===")
print("bytes="..tostring(#xmlText).." -> "..outPath)
print("=== DONE ===")
