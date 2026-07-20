local CorpusScope = dofile("../spec/CorpusScope.lua")

-- Enumeration (which tree, and what names a build) lives in spec/CorpusScope.lua so
-- this test and the regen drivers cannot drift apart on either -- they did, on both:
-- see guards `regen-root-equals-test-root` and `corpus-build-key-is-path-not-basename`.
-- Keys here are root-relative PATHS ("1.4/bin/X.lua"); keying by basename collapsed 6
-- same-named-but-different builds in 1.4/ vs 1.4/bin/ and never tested them.
local function fetchBuilds(root)
    local buildList = {}
    for _, f in ipairs(CorpusScope.listBuildFiles(root, ".lua")) do
        -- @leb-regression-guard:build-snapshot-fetch-robust
        -- The build-snapshot test re-imports each build from its .xml to
        -- recompute output. Some .lua snapshots are LETools/offline-save
        -- imports with NO stored .xml (io.open returns nil); skip those
        -- gracefully instead of erroring on fileHnd:read, so the suite stays
        -- runnable on a partial-corpus checkout (only XML-backed builds tested).
        local fileHnd = io.open(f:gsub(".lua$", ".xml"), "r")
        if fileHnd then
            local name = CorpusScope.buildName(f, root)
            local ok, mod = pcall(LoadModule, f)
            if ok and type(mod) == "table" then
                buildList[name] = mod
                buildList[name].xml = fileHnd:read("*a")
            else
                -- unparseable snapshot (serializer artifact / truncated): skip
                -- with a visible marker rather than halting the whole suite.
                print("[TestBuilds] SKIP unparseable snapshot: " .. name)
            end
            fileHnd:close()
        end
    end
    return buildList
end

-- @leb-regression-guard:generatebuilds-nested-table-serializer
-- Round numbers to 4dp at ANY depth before comparing. Top-level scalars were
-- already rounded; nested tables (output.Minion / output.SkillDPS) are now
-- serialized by buildTable (previously dropped) at 4dp, while the fresh recompute
-- is full precision -- so the snapshot's nested numbers must be compared rounded,
-- exactly like the top-level ones (probe: <private build> Minion = 89/681 EXACT mismatches
-- from >4dp tails, 0 when rounded). For flat/scalar values roundDeep is identical to
-- the old round(v,4) path, so the current (nested-less) corpus is unaffected.
local function roundDeep(x)
    if type(x) == "number" then
        return round(x, 4)
    elseif type(x) == "table" then
        local t = {}
        for k, v in pairs(x) do t[k] = roundDeep(v) end
        return t
    else
        return x
    end
end

expose("test all builds #builds", function()
    local buildList = fetchBuilds(CorpusScope.ROOT)
    for buildName, testBuild in pairs(buildList) do
        loadBuildFromXML(testBuild.xml, buildName)
        testBuild.result = {}
        for key, value in pairs(testBuild.output) do
            -- Have to assign it to a temporary table here, as the tests will run later, when the 'build' isn't changing
            testBuild.result[key] = build.calcsTab.mainOutput[key]
            it("on build: " .. buildName .. ", key: " .. key, function()
                -- roundDeep both sides so nested tables (Minion/SkillDPS) compare at
                -- 4dp like scalars; identical to the old round(v,4) for flat values.
                assert.are.same(roundDeep(value), roundDeep(testBuild.result[key]))
            end)
        end
    end
end)

describe("test offline build import", function()
    it("should load a build from an offline save file", function()
        local saveFile = io.open("../spec/offline_save.json", "r")
        local saveFileContent = saveFile:read("*a")
        saveFile:close()
        loadBuildFromJSON(saveFileContent)
    end)
end)
