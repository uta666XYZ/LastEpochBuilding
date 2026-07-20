-- Last Epoch Building
--
-- Class: Passive Tree
-- Passive skill tree class.
-- Responsible for downloading and loading the passive tree data and assets
-- Also pre-calculates and pre-parses most of the data need to use the passive tree, including the node modifiers
--
local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_remove = table.remove
local m_floor = math.floor
local m_min = math.min
local m_max = math.max
local m_pi = math.pi
local m_rad = math.rad
local m_sin = math.sin
local m_cos = math.cos
local m_tan = math.tan
local m_sqrt = math.sqrt

local classArt = {
    [0] = "centerscion",
    [1] = "centermarauder",
    [2] = "centerranger",
    [3] = "centerwitch",
    [4] = "centerduelist",
    [5] = "centertemplar",
    [6] = "centershadow"
}

-- These values are from the 3.6 tree; older trees are missing values for these constants
local legacySkillsPerOrbit = { 1, 6, 12, 12, 40 }
local legacyOrbitRadii = { 0, 82, 162, 335, 493 }

-- Retrieve the file at the given URL
local function getFile(URL)
    local page = ""
    local easy = common.curl.easy()
    easy:setopt_url(URL)
    easy:setopt_writefunction(function(data)
        page = page .. data
        return true
    end)
    easy:perform()
    easy:close()
    return #page > 0 and page
end

local PassiveTreeClass = newClass("PassiveTree", function(self, treeVersion)
    self.treeVersion = treeVersion
    local versionNum = treeVersions[treeVersion].num

    MakeDir("TreeData")

    ConPrintf("Loading passive tree data for version '%s'...", treeVersions[treeVersion].display)
    local treeText
    local treeFile = io.open("TreeData/" .. treeVersion .. "/tree.lua", "r")
    if treeFile then
        treeText = treeFile:read("*a")
        treeFile:close()
    else
        ConPrintf("Downloading passive tree data...")
        local page
        local pageFile = io.open("TreeData/" .. treeVersion .. "/data.json", "r")
        if pageFile then
            page = pageFile:read("*a")
            pageFile:close()
        else
            page = getFile("https://www.pathofexile.com/passive-skill-tree")
        end
        local treeData = page:match("var passiveSkillTreeData = (%b{})")
        if treeData then
            treeText = "local tree=" .. jsonToLua(page:match("var passiveSkillTreeData = (%b{})"))
            treeText = treeText .. "return tree"
        else
            treeText = "return " .. jsonToLua(page)
        end
        treeFile = io.open("TreeData/" .. treeVersion .. "/tree.lua", "w")
        treeFile:write(treeText)
        treeFile:close()
    end
    for k, v in pairs(assert(loadstring(treeText))()) do
        self[k] = v
    end

    function table.merge(t1, t2)
        for k,v in ipairs(t2) do
            table.insert(t1, v)
        end

        return t1
    end

    -- Add json data from game files extracts
    self.nodes = {}
    self.classes = {}
    local minAbilityPosY = 0
    local maxAbilityPosY = 0
    for i = 0, 4 do
        local treeData = readJsonFile("TreeData/" .. treeVersion .. "/tree_" .. i .. ".json")
        for k,v in pairs(treeData["nodes"]) do
            self.nodes[k] = v
            if not k:match('^[A-Z]') then
                if v.y and maxAbilityPosY < v.y then
                    maxAbilityPosY = v.y
                end
                if v.y and minAbilityPosY > v.y then
                    minAbilityPosY = v.y
                end
                -- Should match the skill id of the related skill
                local skillList = treeData.classes[1].skills
                local treeId = k:match("^[^-]+")
                for _, skill in ipairs(skillList) do
                    if skill.treeId == treeId then
                        self.nodes[k].skillId = skill.name
                    end
                end
            end
        end
        for k,v in pairs(treeData["classes"]) do
            table.insert(self.classes, v)
        end
    end

    self.decAbilityPosY = (maxAbilityPosY - minAbilityPosY)

    local cdnRoot = ""

    self.size = m_min(self.max_x - self.min_x, self.max_y - self.min_y) * 1.1

    -- Migrate to old format
    for i = 0, 6 do
        self.classes[i] = self.classes[i + 1]
        self.classes[i + 1] = nil
    end

    -- Build maps of class name -> class table
    self.classNameMap = { }
    self.ascendNameMap = { }
    self.classNotables = { }

    for classId, class in pairs(self.classes) do
        -- Migrate to old format
        class.classes = class.ascendancies
        class.classes[0] = { name = "None" }
        self.classNameMap[class.name] = classId
        for ascendClassId, ascendClass in pairs(class.classes) do
            self.ascendNameMap[ascendClass.name] = {
                classId = classId,
                class = class,
                ascendClassId = ascendClassId,
                ascendClass = ascendClass
            }
        end
    end

    if self.alternate_ascendancies then
        self.secondaryAscendNameMap = { }
        local alternate_ascendancies_class = {
            ["name"] = "alternate_ascendancies",
            ["classes"] = self.alternate_ascendancies
        }
        for ascendClassId, ascendClass in pairs(self.alternate_ascendancies) do
            self.ascendNameMap[ascendClass.id] = {
                classId = "alternate_ascendancies",
                class = alternate_ascendancies_class,
                ascendClassId = ascendClassId,
                ascendClass = ascendClass
            }
            self.secondaryAscendNameMap[ascendClass.id] = self.ascendNameMap[ascendClass.id]
        end
    end

    self.skillsPerOrbit = self.constants.skillsPerOrbit or legacySkillsPerOrbit
    self.orbitRadii = self.constants.orbitRadii or legacyOrbitRadii
    self.orbitAnglesByOrbit = {}
    for orbit, skillsInOrbit in ipairs(self.skillsPerOrbit) do
        self.orbitAnglesByOrbit[orbit] = self:CalcOrbitAngles(skillsInOrbit)
    end

    ConPrintf("Loading passive tree assets...")
    for name, data in pairs(self.assets) do
        self:LoadImage(name .. ".png", cdnRoot .. (data[1] or ""), data, not name:match("[OL][ri][bn][ie][tC]") and "ASYNC" or nil)--, not name:match("[OL][ri][bn][ie][tC]") and "MIPMAP" or nil)
    end

    -- Load game-accurate tree UI assets (requirement dots)
    self.treeUI = { }
    local function loadTreeUIAsset(name, path)
        local data = { handle = NewImageHandle(), width = 0, height = 0, [1] = 0, [2] = 0, [3] = 1, [4] = 1 }
        data.handle:Load(path)
        data.width, data.height = data.handle:ImageSize()
        self.treeUI[name] = data
    end
    -- Requirement dots (dot-N-M: N = required points, M = filled count)
    for n = 1, 5 do
        for m = 0, n do
            local name = "dot-" .. n .. "-" .. m
            local path = "Assets/tree/" .. name .. ".png"
            loadTreeUIAsset(name, path)
        end
    end

    -- Load node frame assets
    local frameNames = {
        "frame-hex-alloc", "frame-hex-unalloc", "frame-hex-hover",
        "frame-skill-hex-alloc", "frame-skill-hex-unalloc",
        "frame-circle-alloc", "frame-circle-unalloc",
        "frame-root-alloc", "frame-root-unalloc", "frame-root-hover",
    }
    for _, name in ipairs(frameNames) do
        loadTreeUIAsset(name, "Assets/tree/" .. name .. ".png")
    end

    -- Background plate behind node alloc/max counter (matches in-game UI).
    loadTreeUIAsset("node-count-bg", "Assets/tree/node-count-bg.png")

    -- Load sprite sheets and build sprite map
    self.spriteMap = { }
    self.nodeOverlay = {
        Normal = {
            artWidth = 40,
        },
        ClassStart = {
            artWidth = 80,
        },
        AscendClassStart = {
            artWidth = 80,
        }
    }
    for type, data in pairs(self.nodeOverlay) do
        local size = data.artWidth * 1.33
        data.size = size
        data.rsq = size * size
    end

    -- Go away
    self.nodes.root = nil

    ConPrintf("Processing tree...")
    self.ascendancyMap = { }
    self.keystoneMap = { }
    self.notableMap = { }
    self.clusterNodeMap = { }
    self.sockets = { }
    self.masteryEffects = { }
    local nodeMap = { }
    for _, node in pairs(self.nodes) do
        node.alloc = 0
        node.maxPoints = node.maxPoints or 0
        -- Fix coordinates (avoid overlaps of masteries and skills)
        -- v1.2 coordinate system is 4x larger than v1.3/v1.4; normalize to same display scale
        local coordScale = versionNum < 1.3 and 0.5 or 2
        if versionNum < 1.3 then
            -- v1.2 encodes mastery sections as vertical y offsets (1600 units per section).
            -- Detect mastery from y position and remove section offset before scaling,
            -- so the existing mastery*1000 offset produces correct screen positions.
            local masterySection = m_max(0, m_min(3, m_floor((node.y + 800) / 1600)))
            node.mastery = masterySection
            node.y = node.y - masterySection * 1600
        end
        node.x = node.x * coordScale
        node.y = node.y * coordScale
        -- mastery * 1000 vertical offset separates passive tree sections (base + 3 ascendancies).
        -- Skill tree nodes use lowercase IDs (node.skill); they must NOT receive this offset.
        -- Note: node.id is assigned later; use node.skill here.
        if node.mastery and node.skill and node.skill:sub(1,1):match("%u") then
            node.y = node.y + node.mastery * 1000
        end
        if node.skillId then
            node.x = node.x + 3000
        end
        -- Migration...
        -- To old format
        node.id = node.skill
        node.g = node.group
        node.o = node.orbit
        node.oidx = node.orbitIndex
        node.dn = node.name
        node.sd = node.stats
        node.passivePointsGranted = node.grantedPassivePoints or 0

        node.__index = node
        node.linkedId = { }
        nodeMap[node.id] = node

        -- Determine node type
        if node.classStartIndex then
            node.type = "ClassStart"
            local class = self.classes[node.classStartIndex]
            class.startNodeId = node.id
            node.x = -1200
        elseif node.isAscendancyStart then
            node.type = "AscendClassStart"
            local ascendClass = self.ascendNameMap[node.ascendancyName].ascendClass
            ascendClass.startNodeId = node.id
            node.x = -1200
        else
            node.type = "Normal"
        end

        self:ProcessNode(node)
    end

    -- Pregenerate the polygons for the node connector lines
    self.connectors = { }
    for _, node in pairs(self.nodes) do
        for _, otherId in pairs(node.out or {}) do
            local other = nodeMap[otherId]
            t_insert(node.linkedId, otherId)
            if node.type ~= "ClassStart" and other.type ~= "ClassStart"
                    and node.type ~= "Mastery" and other.type ~= "Mastery"
                    and node.ascendancyName == other.ascendancyName
                    and not node.isProxy and not other.isProxy then
                local connectors = self:BuildConnector(node, other)
                t_insert(self.connectors, connectors[1])
                if connectors[2] then
                    t_insert(self.connectors, connectors[2])
                end
            end
        end
        for _, otherId in pairs(node["in"] or {}) do
            t_insert(node.linkedId, otherId)
        end
    end

    -- Build reqPoints lookup: node.reqPointsMap[parentId] = requiredPoints
    -- reqPoints array in JSON corresponds 1:1 with the "in" array
    for _, node in pairs(self.nodes) do
        if node.reqPoints and node["in"] then
            node.reqPointsMap = { }
            for i, parentId in ipairs(node["in"]) do
                if node.reqPoints[i] then
                    node.reqPointsMap[parentId] = node.reqPoints[i]
                end
            end
        end
    end

    for classId, class in pairs(self.classes) do
        local startNode = nodeMap[class.startNodeId]
        for _, nodeId in ipairs(startNode.linkedId) do
            local node = nodeMap[nodeId]
            if node.type == "Normal" then
                node.modList:NewMod("Condition:ConnectedTo" .. class.name .. "Start", "FLAG", true, "Tree:" .. nodeId)
            end
        end
    end
end)

-- Mapping from description substrings to Condition var names.
-- When a node's description contains any of these phrases, all of its mods
-- receive the corresponding Condition tag so they are only applied when that
-- config condition is enabled.
local nodeDescriptionConditions = {
    { phrase = "if you have cast teleport recently", condVar = "RecentlyUsedTeleport" },
}

function PassiveTreeClass:ProcessStats(node, startIndex)
    startIndex = startIndex or 1
    if startIndex == 1 then
        node.modKey = ""
        node.mods = { }
        node.modList = new("ModList")
        -- Detect conditional descriptions and cache the required condition var
        node.descConditionVar = nil
        if node.description then
            local descList = type(node.description) == "table" and node.description or { node.description }
            for _, descLine in ipairs(descList) do
                local lower = descLine:lower()
                for _, entry in ipairs(nodeDescriptionConditions) do
                    if lower:find(entry.phrase, 1, true) then
                        node.descConditionVar = entry.condVar
                        break
                    end
                end
                if node.descConditionVar then break end
            end
        end
    end

    node.sd = {}
    local statRewrites = LE_TREE_NODE_STAT_REWRITE[node.id]
    if node.stats then
        for _, stat in ipairs(node.stats) do
            -- @leb-regression-guard:tree-node-defensive-hit-damage (consumer site)
            -- Re-express node-scoped DEFENSIVE stats whose bare string would
            -- otherwise misparse as offensive (e.g. fw3d-18 "Barrier"
            -- "X% Less Hit Damage" -> "X% less hit damage taken"). Applied on the
            -- raw per-point string BEFORE rank scaling so the leading value still
            -- multiplies. Registry + rationale: Data/Global.lua
            -- LE_TREE_NODE_STAT_REWRITE.
            if statRewrites then
                for _, rw in ipairs(statRewrites) do
                    stat = (stat:gsub(rw.pat, rw.repl))
                end
            end
            if node.alloc > 1 and stat:match("%d") then
                -- @leb-regression-guard:tree-rank-per-stat-divisor
                -- Rank scaling must multiply LEADING values only, not divisors
                -- in "per N <attr>" clauses. e.g. "+3 Ward per 15 Int" at rank 5
                -- becomes "+15 Ward per 15 Int" (NOT "+15 per 75 Int") so that the
                -- parsed mod ends up as BASE=15, PerStat div=15. Same protection
                -- applies to any "per N <anything>" tail (e.g. "per 10 stacks").
                local function scaleNumbers(s)
                    -- @leb-regression-guard:tree-rank-scale-skip-weapon-hand-token
                    -- Do NOT rank-scale a digit glued to "h" -- that is the 1h/2h
                    -- weapon-hand token inside a CONDITION phrase ("With 2h Weapon",
                    -- "With 1h Sword"), not a stat value. The bare %d scaler turned the
                    -- "2" in "2h" into "<2*alloc>h" (Master of Arms Sentinel-68 at 8 pts:
                    -- "+2 Strength With 2h Weapon" -> "+16 Strength With 16h Weapon"),
                    -- which ModParser no longer recognises -> the UsingTwoHandedWeapon
                    -- condition is lost and the whole mod is dropped (Aurora Brutality
                    -- 98 vs in-game 116; the +16 Master of Arms Strength vanished). Stat
                    -- VALUES are always followed by a space or "%", never a letter, so a
                    -- digit run immediately followed by "h"/"H" is a hand token, not a
                    -- value. Affects every multi-point node with a 1h/2h-conditional stat
                    -- (Master of Arms, Battlemaster's Blade "+20% Area With 2h",
                    -- Heorot's Arsenal "+8 Spell Damage With 2h Weapon", weapon-subtype
                    -- nodes, etc.). See REGRESSION_GUARDS.md.
                    return (s:gsub("(%d[%d.]*)(%a?)", function(valueStr, suffix)
                        if suffix == "h" or suffix == "H" then return valueStr .. suffix end
                        return tostring(tonumber(valueStr) * node.alloc) .. suffix
                    end))
                end
                local rebuilt, pos = "", 1
                while pos <= #stat do
                    local s, e = stat:find("[Pp]er%s+%d[%d.]*", pos)
                    if not s then
                        rebuilt = rebuilt .. scaleNumbers(stat:sub(pos))
                        break
                    end
                    rebuilt = rebuilt .. scaleNumbers(stat:sub(pos, s - 1)) .. stat:sub(s, e)
                    pos = e + 1
                end
                stat = rebuilt
            end
            -- @leb-regression-guard:chaos-bolts-exult-in-misery-enemy-ailment (empty-line skip)
            -- A node-keyed rewrite (Data/Global.lua LE_TREE_NODE_STAT_REWRITE) may
            -- COLLAPSE several display stat lines into ONE and EMPTY the rest -- e.g.
            -- ch4bo-11 "Exult in Misery" folds four "+4% Hit Damage to <ailment>"
            -- lines into a single "+X% Hit Damage per Negative Ailment on Enemy" and
            -- rewrites the other three to "". An emptied line carries no modifier;
            -- skip it so it neither reaches parseMod (which returns a space residue
            -- and would falsely set node.extra, flagging the node as unsupported in
            -- the tree UI) nor produces a phantom empty mod. Raw tree stats are never
            -- blank, so this fires only on rewrite-emptied lines.
            if stat:match("%S") then
                table.insert(node.sd, stat)
            end
        end
    end
    if node.noScalingPointThreshold and node.alloc >= node.noScalingPointThreshold then
        for _,stat in ipairs(node.notScalingStats) do
            -- @leb-regression-guard:rhythm-stack-crit-multi (notScaling rewrite site)
            -- LE_TREE_NODE_STAT_REWRITE also applies to notScalingStats lines.
            -- These never rank-scale, so order vs the scaling block is moot;
            -- needed for dacn33-23 "Rhythm" whose per-stack "3% Global More
            -- Damage" lives in notScalingStats (see Data/Global.lua registry).
            if statRewrites then
                for _, rw in ipairs(statRewrites) do
                    stat = (stat:gsub(rw.pat, rw.repl))
                end
            end
            -- @leb-regression-guard:chaos-bolts-exult-in-misery-enemy-ailment (empty-line skip, notScaling)
            -- Same rewrite-collapse guard as the scaling-stats loop above: drop a
            -- line a node-keyed rewrite emptied so it never becomes a phantom mod.
            if stat:match("%S") then
                table.insert(node.sd, stat)
            end
        end
    end

    if not node.sd then
        return
    end

    -- Parse node modifier lines
    local i = startIndex
    while node.sd[i] do
        if node.sd[i]:match("\n") then
            local line = node.sd[i]
            local il = i
            t_remove(node.sd, i)
            for line in line:gmatch("[^\n]+") do
                t_insert(node.sd, il, line)
                il = il + 1
            end
        end
        local line = node.sd[i]
        local list, extra = modLib.parseMod(line)
        if not list then
            -- Parser had no idea how to read this modifier
            node.unknown = true
        elseif extra then
            -- Parser recognised this as a modifier but couldn't understand all of it
            node.extra = true
        else
            for _, mod in ipairs(list) do
                node.modKey = node.modKey .. "[" .. modLib.formatMod(mod) .. "]"
            end
        end
        node.mods[i] = { list = list, extra = extra }
        i = i + 1
        while node.mods[i] do
            -- Skip any lines with dummy lists added by the line combining code
            i = i + 1
        end
    end

    -- @leb-regression-guard:doubled-if-X-tree-notscaling
    -- Generic doubling for tree-node `notScalingStats` lines of the form
    -- " Doubled if <X>" (game-file 2026-05-28 audit: 3 nodes use this pattern
    -- across all 1.4 trees — ch0fs-20 Death from Below / ch0fs-14 Eradication
    -- with X="Cursed", srtor-11 Taste for Flesh with X="Killed Recently").
    -- The literal " Doubled if Cursed" / " Doubled if Killed Recently" strings
    -- themselves are baked into ModCache as empty mod lists ({}) — the
    -- doubling SEMANTICS lives here: we map <X> to a player Condition var and
    -- attach `{type="Condition", var=<var>, mult=2}` as a TAG on every
    -- scaling mod the node already emits. ModStore.lua:607-621 (guard
    -- `condition-tag-mult`) interprets this exactly: when the matching
    -- `condition<X>` config toggle in ConfigOptions.lua is OFF, the tag
    -- returns the base value (NOT a full gate, since `mult` is set); when
    -- ON, the value is multiplied by 2 — delivering exact in-game
    -- "this effect is doubled" semantics while preserving the always-on base
    -- contribution required to keep the pre-toggle baseline stable.
    --
    -- Limitations (documented intentional scope):
    -- * ch0fs-14 Eradication's scaling stat "+8% Damage to Rares and Bosses"
    --   now parses cleanly (empty `extra`) thanks to the
    --   `against-rares-and-bosses` guard (ModParser maps "to/against/vs rares
    --   and bosses" to an enemy ActorCondition varList {Rare,Boss}). It passes
    --   the L468 gate and this handler's doubling tag (Condition:Cursed mult=2)
    --   attaches to it as intended; the rare/boss gate is satisfied by default
    --   because leBossCategory defaults to a Boss (Condition:Boss).
    -- * ch0fs-14 description also reads "doubled if **the enemy or you are
    --   cursed**" (OR), but the notScalingStats string is plain
    --   " Doubled if Cursed" — same as ch0fs-20 (player-only). The generic
    --   handler maps both uniformly to player Condition:Cursed; the
    --   "or enemy" half is out of this handler's textual scope.
    -- Spec: spec/System/TestDoubledIfXTreeNotScaling_spec.lua.
    local doublingTag
    for j = startIndex, #node.sd do
        local s = node.sd[j]
        if type(s) == "string" then
            local x = s:match("^%s*[Dd]oubled [Ii]f%s+(.-)%s*$")
            if x then
                local lc = x:lower()
                if lc == "cursed" then
                    doublingTag = { type = "Condition", var = "Cursed", mult = 2 }
                elseif lc == "killed recently" then
                    doublingTag = { type = "Condition", var = "KilledRecently", mult = 2 }
                end
                if doublingTag then break end
            end
            -- @leb-regression-guard:doubled-against-condition
            -- Sibling of the " Doubled if X" scan above, for tree-node
            -- notScalingStats of the form " Doubled Against <enemy condition>".
            -- (game-file 2026-06-01 audit, 1.4 trees: High Health / Low Health /
            -- Low Life / Frozen are mapped here. " Doubled Against DoTs" is an
            -- incoming-damage-type DEFENCE modifier — not an enemy condition — so
            -- it is intentionally left unmapped and that mod stays at base.)
            -- Maps <X> to an ENEMY ActorCondition tag with mult=2, evaluated by
            -- the `actorcondition-tag-mult` guard in ModStore.lua. The matching
            -- enemy config toggle (conditionEnemyHighHealth / conditionEnemyLowLife
            -- / conditionEnemyFrozen in ConfigOptions.lua) drives the doubling:
            -- OFF -> base value (no gate, mult present), ON -> value*2.
            local against = s:match("^%s*[Dd]oubled [Aa]gainst%s+(.-)%s*$")
            if against then
                local alc = against:lower():gsub("%s+enemies$", ""):gsub("%s+enemy$", "")
                local enemyVar
                if alc == "high health" then
                    enemyVar = "HighHealth"
                elseif alc == "low health" or alc == "low life" then
                    enemyVar = "LowLife"
                elseif alc == "frozen" then
                    enemyVar = "Frozen"
                end
                if enemyVar then
                    doublingTag = { type = "ActorCondition", actor = "enemy", var = enemyVar, mult = 2 }
                    break
                end
            end
        end
    end

    -- @leb-regression-guard:tree-also-applies-to-minions
    -- LE follow-up modifier " Also Applies To Minions" (leading space, its own
    -- stat line) makes the PRECEDING stat lines of the same node ALSO apply to
    -- the player's minions. e.g. Sentinel-37 "Smelter's Might" stats =
    --   "+7% Bleed Chance", "+7% Ignite Chance",
    --   " Also Applies To Minions", " Doubled for you with a 2h weapon"
    -- (in-game: "You and your minions have a chance to inflict bleeding and
    -- ignite on hit"). parseMod returns `unknown` for the bare follow-up line,
    -- so without this handler the minion never receives the bonus — on a Forge
    -- Guard Manifest Armor build that node is the minion's ONLY ailment source,
    -- giving 0 minion ailment DPS vs ~73% of the minion's in-game DPS.
    --
    -- For every real mod parsed on a line BEFORE the follow-up (back to the
    -- previous follow-up boundary or node start), emit an ADDITIONAL
    -- MinionModifier LIST copy whose inner mod is the freshly-copied parsed mod
    -- (taken before the player loop below appends any SkillId/Condition tags),
    -- so it dispatches onto env.minion.modDB (CalcPerform.lua, guard
    -- minion-modifier-multi-type-gate). The player's own copy is left intact
    -- ("Also" = player AND minion). Player-only follow-ups that come AFTER (e.g.
    -- " Doubled for you with a 2h weapon") are not inherited by the minion copy.
    -- Spec: spec/System/TestTreeAlsoAppliesToMinions_spec.lua.
    local minionApplyBoundaries
    for j = startIndex, #node.sd do
        local s = node.sd[j]
        if type(s) == "string" then
            local norm = s:lower():gsub("%s+", " "):gsub("^%s", ""):gsub("%s$", "")
            if norm == "also applies to minions" then
                minionApplyBoundaries = minionApplyBoundaries or {}
                t_insert(minionApplyBoundaries, j)
            end
        end
    end
    if minionApplyBoundaries then
        local prev = startIndex - 1
        for _, boundary in ipairs(minionApplyBoundaries) do
            for li = prev + 1, boundary - 1 do
                local entry = node.mods[li]
                if entry and entry.list and (not entry.extra or entry.extra == "") then
                    for _, srcMod in ipairs(entry.list) do
                        local innerMod = copyTable(srcMod, true)
                        node.modList:AddMod(modLib.createMod("MinionModifier", "LIST", { mod = innerMod }, "Tree:" .. node.id))
                    end
                end
            end
            prev = boundary
        end
    end

    -- Build unified list of modifiers from all recognised modifier lines
    for i = startIndex, #node.mods do
        local mod = node.mods[i]
        -- @leb-regression-guard:conversion-extra-nil-not-empty (consumer site)
        -- A fully-parsed mod leaves either nil (live parse, ModParser.lua tail)
        -- or "" (legacy ModCache.lua entries baked by the old conversion path,
        -- e.g. `c[" Fire -> Cold"]={{...},""}`) as `extra`. Both mean "no
        -- residue" and the mod MUST be applied. Only a NON-EMPTY string is a
        -- real leftover signalling an incomplete parse. The old guard
        -- `not mod.extra` treated "" as truthy and silently dropped every
        -- skill-tree / passive-tree conversion node (Flame Ward "fw3d-6 Frost
        -- Ward" " Fire -> Cold" never reached node.modList), breaking
        -- cross-skill conversion to Fire Aura. Spec: spec/System/TestConversionExtraNil_spec.lua
        if mod.list and (not mod.extra or mod.extra == "") then
            for i, mod in ipairs(mod.list) do
                mod = modLib.setSource(mod, "Tree:" .. node.id)
                -- @leb-regression-guard:minion-aura-player-application (tagging site)
                -- Validation provenance is retained in maintainer notes.
                local auraPlayerCond = LE_MINION_AURA_PLAYER_NODES[node.id]
                -- @leb-regression-guard:vengeance-bolster-player-buff (tagging site)
                -- Nodes registered in LE_TREE_NODE_PLAYER_CONDITIONAL_BUFF
                -- (Data/Global.lua) grant a PLAYER-WIDE conditional self-buff (e.g.
                -- Vengeance gs15de-19 "Bolster": -13% DamageTaken MORE / +25% Armour
                -- INC per point, while you've hit with Vengeance recently). Like the
                -- minion-aura case their mods (1) skip the owning-skill SkillId tag so
                -- they reach the player defensive panel and (2) carry a gating
                -- Condition (config toggle, default OFF). Without the lift the
                -- SkillId:Vengeance tag confines them to the Vengeance cfg and they
                -- never apply to the player sheet (cfg=nil).
                local playerBuffCond = LE_TREE_NODE_PLAYER_CONDITIONAL_BUFF[node.id]
                -- A node lifted to the player sheet by EITHER registry omits its
                -- owning-skill SkillId tag and instead carries its gating Condition.
                local liftCond = auraPlayerCond or playerBuffCond
                -- @leb-regression-guard:rhythm-stack-crit-multi (SkillId-lift site)
                -- Nodes registered in LE_TREE_NODE_GLOBAL_SCOPE (Data/Global.lua)
                -- are GLOBAL in-game: their mods must reach the player sheet,
                -- so the [SkillId] scoping tag is NOT appended. e.g. dacn33-26
                -- "Art of Blades" (+20% crit multi per Rhythm stack at 2/2)
                -- contributed nothing to sheet CritMultiplier while scoped.
                if node.skillId and not LE_TREE_NODE_GLOBAL_SCOPE[node.id] and not liftCond then
                    -- @leb-regression-guard:tree-node-skill-rescope (tagging site)
                    -- Default: scope the mod to the owning tree's skill. A
                    -- LE_TREE_NODE_SKILL_RESCOPE entry (Data/Global.lua) overrides
                    -- this for nodes whose stats target a shared sub-ability
                    -- (skillId / skillIdList) or must not flow through the
                    -- triggered-group groupSource channel (directOnly).
                    local rescope = LE_TREE_NODE_SKILL_RESCOPE[node.id]
                    if rescope and rescope.skillIdList then
                        table.insert(mod, {type = "SkillId", skillIdList = rescope.skillIdList, directOnly = rescope.directOnly})
                    elseif rescope then
                        table.insert(mod, {type = "SkillId", skillId = rescope.skillId or node.skillId, directOnly = rescope.directOnly})
                    else
                        table.insert(mod, {type = "SkillId", skillId = node.skillId})
                    end
                end
                if liftCond then
                    -- Player-lifted node (SkillId omitted above): gate it behind its
                    -- Condition so it only applies while active — for the minion-aura
                    -- case the proximity gate (inside the Spriggan's Healing Aura),
                    -- for the player conditional self-buff case its trigger window
                    -- (e.g. Bolster: hit with Vengeance in the past 2s).
                    table.insert(mod, { type = "Condition", var = liftCond })
                end
                if node.descConditionVar then
                    table.insert(mod, { type = "Condition", var = node.descConditionVar })
                end
                if doublingTag then
                    -- Fresh tag table per mod — tags must not share refs across
                    -- mods (other tag-append sites above follow the same rule).
                    -- `actor` is nil for the player Condition tags (Cursed /
                    -- KilledRecently) and "enemy" for the ActorCondition tags
                    -- ("Doubled Against <enemy condition>"); copying it is a
                    -- no-op for the former and required for the latter.
                    table.insert(mod, { type = doublingTag.type, actor = doublingTag.actor, var = doublingTag.var, mult = doublingTag.mult })
                end
                if node.alloc > 1 then
                    if type(mod.value) == "table" then
                        for _, mod in ipairs(mod.value) do
                            mod.value = mod.value
                        end
                    else
                        mod.value = mod.value
                    end
                end
                node.modList:AddMod(mod)
            end
        end
    end
    if node.type == "Keystone" then
        node.keystoneMod = modLib.createMod("Keystone", "LIST", node.dn, "Tree" .. node.id)
    end
end

-- Common processing code for nodes (used for both real tree nodes and subgraph nodes)
function PassiveTreeClass:ProcessNode(node)
    node.overlay = self.nodeOverlay[node.type]
    if node.overlay then
        node.rsq = node.overlay.rsq
        node.size = node.overlay.size
    end

    -- Derive the true position of the node
    if node.group then
        node.angle = self.orbitAnglesByOrbit[node.o + 1][node.oidx + 1]
        local orbitRadius = self.orbitRadii[node.o + 1]
        node.x = node.group.x + m_sin(node.angle) * orbitRadius
        node.y = node.group.y - m_cos(node.angle) * orbitRadius
    end

    self:ProcessStats(node)
end

-- Checks if a given image is present and downloads it from the given URL if it isn't there
function PassiveTreeClass:LoadImage(imgName, url, data, ...)
    local imgFile = io.open("TreeData/" .. imgName, "r")
    if imgFile then
        imgFile:close()
    else
        imgFile = io.open("TreeData/" .. self.treeVersion .. "/" .. imgName, "r")
        if imgFile then
            imgFile:close()
            imgName = self.treeVersion .. "/" .. imgName
        elseif main.allowTreeDownload then
            -- Enable downloading with Ctrl+Shift+F5
            ConPrintf("Downloading '%s'...", imgName)
            local data = getFile(url)
            if data and not data:match("<!DOCTYPE html>") then
                imgFile = io.open("TreeData/" .. imgName, "wb")
                imgFile:write(data)
                imgFile:close()
            else
                ConPrintf("Failed to download: %s", url)
            end
        end
    end
    data.handle = NewImageHandle()
    data.handle:Load("TreeData/" .. imgName, ...)
    data.width, data.height = data.handle:ImageSize()
end

-- Generate the quad used to render the line between the two given nodes
function PassiveTreeClass:BuildConnector(node1, node2)
    local connector = {
        ascendancyName = node1.ascendancyName,
        nodeId1 = node1.id,
        nodeId2 = node2.id,
        c = { } -- This array will contain the quad's data: 1-8 are the vertex coordinates, 9-16 are the texture coordinates
        -- Only the texture coords are filled in at this time; the vertex coords need to be converted from tree-space to screen-space first
        -- This will occur when the tree is being drawn; .vert will map line state (Normal/Intermediate/Active) to the correct tree-space coordinates
    }
    -- Generate a straight line
    connector.type = "LineConnector"
    local art = self.assets.LineConnectorNormal
    local vX, vY = node2.x - node1.x, node2.y - node1.y
    local dist = m_sqrt(vX * vX + vY * vY)
    local scale = art.height * 1.33 / dist
    local nX, nY = vX * scale, vY * scale
    local endS = dist / (art.width * 1.33)
    connector[1], connector[2] = node1.x - nY, node1.y + nX
    connector[3], connector[4] = node1.x + nY, node1.y - nX
    connector[5], connector[6] = node2.x + nY, node2.y - nX
    connector[7], connector[8] = node2.x - nY, node2.y + nX
    connector.c[9], connector.c[10] = 0, 1
    connector.c[11], connector.c[12] = 0, 0
    connector.c[13], connector.c[14] = endS, 0
    connector.c[15], connector.c[16] = endS, 1
    connector.vert = { Normal = connector, Intermediate = connector, Active = connector }
    return { connector }
end

function PassiveTreeClass:BuildArc(arcAngle, node1, connector, isMirroredArc)
    connector.type = "Orbit" .. node1.o
    -- This is an arc texture mapped onto a kite-shaped quad
    -- Calculate how much the arc needs to be clipped by
    -- Both ends of the arc will be clipped by this amount, so 90 degree arc angle = no clipping and 30 degree arc angle = 75 degrees of clipping
    -- The clipping is accomplished by effectively moving the bottom left and top right corners of the arc texture towards the top left corner
    -- The arc texture only shows 90 degrees of an arc, but some arcs must go for more than 90 degrees
    -- Fortunately there's nowhere on the tree where we can't just show the middle 90 degrees and rely on the node artwork to cover the gaps :)
    local clipAngle = m_pi / 4 - arcAngle / 2
    local p = 1 - m_max(m_tan(clipAngle), 0)
    local angle = node1.angle - clipAngle
    if isMirroredArc then
        -- The center of the mirrored angle should be positioned at 75% of the way between nodes.
        angle = angle + arcAngle
    end
    connector.vert = { }
    for _, state in pairs({ "Normal", "Intermediate", "Active" }) do
        -- The different line states have differently-sized artwork, so the vertex coords must be calculated separately for each one
        local art = self.assets[connector.type .. state]
        local size = art.width * 2 * 1.33
        local oX, oY = size * m_sqrt(2) * m_sin(angle + m_pi / 4), size * m_sqrt(2) * -m_cos(angle + m_pi / 4)
        local cX, cY = node1.group.x + oX, node1.group.y + oY
        local vert = { }
        vert[1], vert[2] = node1.group.x, node1.group.y
        vert[3], vert[4] = cX + (size * m_sin(angle) - oX) * p, cY + (size * -m_cos(angle) - oY) * p
        vert[5], vert[6] = cX, cY
        vert[7], vert[8] = cX + (size * m_cos(angle) - oX) * p, cY + (size * m_sin(angle) - oY) * p
        if (isMirroredArc) then
            -- Flip the quad's non-origin, non-center vertexes when drawing a mirrored arc so that the arc actually mirrored
            -- This is required to prevent the connection of the 2 arcs appear to have a 'seam'
            local temp1, temp2 = vert[3], vert[4]
            vert[3], vert[4] = vert[7], vert[8]
            vert[7], vert[8] = temp1, temp2
        end
        connector.vert[state] = vert
    end
    connector.c[9], connector.c[10] = 1, 1
    connector.c[11], connector.c[12] = 0, p
    connector.c[13], connector.c[14] = 0, 0
    connector.c[15], connector.c[16] = p, 0
end

function PassiveTreeClass:CalcOrbitAngles(nodesInOrbit)
    local orbitAngles = {}

    if nodesInOrbit == 16 then
        -- Every 30 and 45 degrees, per https://github.com/grindinggear/skilltree-export/blob/3.17.0/README.md
        orbitAngles = { 0, 30, 45, 60, 90, 120, 135, 150, 180, 210, 225, 240, 270, 300, 315, 330 }
    elseif nodesInOrbit == 40 then
        -- Every 10 and 45 degrees
        orbitAngles = { 0, 10, 20, 30, 40, 45, 50, 60, 70, 80, 90, 100, 110, 120, 130, 135, 140, 150, 160, 170, 180, 190, 200, 210, 220, 225, 230, 240, 250, 260, 270, 280, 290, 300, 310, 315, 320, 330, 340, 350 }
    else
        -- Uniformly spaced
        for i = 0, nodesInOrbit do
            orbitAngles[i + 1] = 360 * i / nodesInOrbit
        end
    end

    for i, degrees in ipairs(orbitAngles) do
        orbitAngles[i] = m_rad(degrees)
    end

    return orbitAngles
end
