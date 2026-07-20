-- @leb-regression-guard: tree-version-loadable-vs-offered
-- Locks the split between "versions LEB can LOAD" (treeVersionList) and "versions
-- the UI OFFERS" (offeredTreeVersionList). Retiring 1.2/1.3 from the UI must not
-- make a build saved on those versions unopenable, and must never silently
-- re-point such a build at a different tree -- that would corrupt a saved build
-- while reporting success.
--
-- @leb-regression-guard: default-tree-version-named-not-positional
-- Locks defaultTreeVersion as a NAME. It used to be treeVersionList[2]; shrinking
-- the list silently rebound it to a different version rather than going nil.
--
-- @leb-regression-guard: legacy-target-version-live
-- Locks legacyTargetVersion at the live version, so a build with no targetVersion
-- attribute is interpreted with live data rather than retired season-2 data.
--
-- See REGRESSION_GUARDS.md for all three.
--
-- The build XML below is synthetic and hand-authored on purpose. No 1.2/1.3 build
-- exists in the corpus (all 644 are treeVersion="1_4"), and the corpus is
-- gitignored, so a corpus-backed test would silently skip here and in CI -- which
-- is exactly how this invariant would rot unnoticed.

local function buildXML(ver)
	return ([[<?xml version="1.0" encoding="UTF-8"?>
<LastEpochBuilding>
	<Build level="100" targetVersion="%s" className="Primalist" ascendClassName="Druid" mainSocketGroup="1" viewMode="TREE" characterLevelAutoMode="false"/>
	<Skills activeSkillSet="1">
		<SkillSet id="1">
			<Skill skillId="Swipe" slot="Skill 1" mainActiveSkill="1" includeInFullDPS="true" index="1" enabled="true"/>
		</SkillSet>
	</Skills>
	<Tree activeSpec="1">
		<Spec treeVersion="%s" classId="0" ascendClassId="3" nodes="Primalist#1"/>
	</Tree>
	<Items/>
	<Config/>
</LastEpochBuilding>]]):format(ver, ver)
end

-- An aborted load leaves the PREVIOUSLY loaded build in place while
-- loadBuildFromXML still returns normally, so asserting on the build straight
-- after a load can pass against stale state. Load a distinguishable build first,
-- then assert the fields actually changed.
local function loadFresh(ver)
	loadBuildFromXML(buildXML(latestTreeVersion):gsub('className="Primalist"', 'className="Sentinel"')
	                                            :gsub('ascendClassName="Druid"', 'ascendClassName="Paladin"')
	                                            :gsub('classId="0"', 'classId="3"')
	                                            :gsub('nodes="Primalist#1"', 'nodes="Sentinel#1"'), "sentinel-decoy")
	loadBuildFromXML(buildXML(ver), "under-test-" .. ver)
end

describe("tree version retire", function()
	describe("loadable vs offered", function()
		it("offers only versions that are also loadable", function()
			for _, ver in ipairs(offeredTreeVersionList) do
				assert.is_truthy(isValueInTable(treeVersionList, ver))
				assert.is_truthy(treeVersions[ver])
			end
		end)

		it("does not offer the retired versions", function()
			assert.is_nil(isValueInTable(offeredTreeVersionList, "1_2"))
			assert.is_nil(isValueInTable(offeredTreeVersionList, "1_3"))
		end)

		it("keeps the retired versions loadable", function()
			-- The whole point of the retire: data stays, only the UI stops offering.
			for _, ver in ipairs({ "1_2", "1_3" }) do
				assert.is_truthy(isValueInTable(treeVersionList, ver))
				assert.is_truthy(treeVersions[ver], ver .. " missing from treeVersions -> Build.lua forces convert-or-cancel")
				assert.is_truthy(data.versionData[ver], ver .. " missing from versionData -> data.setActiveVersion falls back SILENTLY")
				assert.is_truthy(main:LoadTree(ver), ver .. " unloadable -> PassiveSpec dies indexing a nil tree")
			end
		end)

		it("still offers the latest version", function()
			assert.is_truthy(isValueInTable(offeredTreeVersionList, latestTreeVersion))
		end)
	end)

	describe("named constants", function()
		it("pins defaultTreeVersion by name to a loadable version", function()
			assert.are.equal("1_3", defaultTreeVersion)
			assert.is_truthy(treeVersions[defaultTreeVersion])
		end)

		it("declares defaultTreeVersion as a literal, not an index into treeVersionList", function()
			-- A value assertion cannot catch this: treeVersionList[2] still EQUALS
			-- "1_3" today, so the positional form passes every runtime check until
			-- someone shrinks the list -- at which point it silently rebinds to a
			-- different version (measured: 3 entries -> 2 rebinds it to "1_4"; it
			-- does not go nil, so nothing announces the change). The only thing that
			-- distinguishes named from positional right now is the source text.
			local f = assert(io.open("GameVersions.lua", "r"))
			local src = f:read("*a")
			f:close()
			local decl = src:match("\ndefaultTreeVersion%s*=%s*([^\n]*)")
			assert.is_truthy(decl, "defaultTreeVersion assignment not found in GameVersions.lua")
			assert.is_nil(decl:find("treeVersionList", 1, true),
				"defaultTreeVersion must be a literal version name, got: " .. decl)
		end)

		it("keeps legacyTargetVersion on a live, offered version", function()
			assert.are.equal(liveTargetVersion, legacyTargetVersion)
			assert.is_truthy(isValueInTable(offeredTreeVersionList, legacyTargetVersion))
		end)

		it("keeps latestTreeVersion tracking the end of treeVersionList", function()
			-- Positional by design: adding a season must move this automatically.
			assert.are.equal(treeVersionList[#treeVersionList], latestTreeVersion)
		end)
	end)

	describe("a retired-version build still opens and computes", function()
		it("opens as itself rather than being re-pointed at the latest version", function()
			loadFresh("1_2")
			assert.are.equal("1_2", build.spec.treeVersion)
			assert.are.equal("1_2", build.targetVersion)
			assert.are.equal("Primalist", build.spec.curClassName) -- not the Sentinel decoy
		end)

		it("computes on the 1.2 tree and 1.2 data, not the latest ones", function()
			loadFresh("1_2")
			-- Object identity, not DPS: a minimal build can score the same on either
			-- tree, so an equal number would not prove which tree was used.
			assert.are.equal(main.tree["1_2"], build.spec.tree)
			assert.are_not.equal(main.tree[latestTreeVersion], build.spec.tree)
			assert.are.equal(data.versionData["1_2"].uniques, data.uniques)
			assert.is_true((build.calcsTab.mainOutput.FullDPS or 0) > 0)
		end)

		it("offers conversion rather than performing it", function()
			loadFresh("1_2")
			-- PoB-style opt-in: the build stays on 1.2 and merely shows the button.
			assert.is_true(build.treeTab.showConvert)
			assert.are.equal("1_2", build.spec.treeVersion)
		end)

		it("shows the retired version in the dropdown instead of mislabelling it", function()
			local list = build.treeTab:BuildVersionList("1_2")
			assert.are.equal("1.2", list[1])
			assert.is_truthy(isValueInTable(list, treeVersions[latestTreeVersion].display))
		end)

		it("does not list a retired version for a live spec", function()
			local list = build.treeTab:BuildVersionList(latestTreeVersion)
			assert.is_nil(isValueInTable(list, "1.2"))
			assert.is_nil(isValueInTable(list, "1.3"))
			assert.are.equal(#offeredTreeVersionList, #list)
		end)
	end)

	describe("a live build is unaffected", function()
		it("opens on the latest tree with no conversion offered", function()
			loadFresh(latestTreeVersion)
			assert.are.equal(latestTreeVersion, build.spec.treeVersion)
			assert.are.equal(main.tree[latestTreeVersion], build.spec.tree)
			assert.is_falsy(build.treeTab.showConvert)
			assert.is_true((build.calcsTab.mainOutput.FullDPS or 0) > 0)
		end)
	end)
end)
