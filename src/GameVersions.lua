-- Game versions
--
-- @leb-regression-guard: tree-version-loadable-vs-offered
-- Two DIFFERENT lists, and conflating them corrupts saved builds:
--
--   treeVersionList        -- versions LEB can LOAD. Never shrink it.
--   offeredTreeVersionList -- versions the UI OFFERS. Retire versions here only.
--
-- 1.2/1.3 are retired from the UI but remain loadable: their data files
-- (bases_1_2.json, ModItem_1_2.json, uniques_1_2.json, TreeData/1_2, ...) are
-- kept on disk and still loaded, because a build saved with treeVersion="1_2"
-- must still open on its OWN tree and compute correctly. Such a build is
-- converted only if the user presses "Convert to <latest>" (PassiveSpec.lua
-- showConvert) -- LEB never re-points a saved build at a different version.
--
-- Measured failure modes if a version is dropped from treeVersionList:
--   * Dropped from treeVersionList only -> Data.lua stops building
--     data.versionData[ver] AND main:LoadTree returns nil, so opening such a
--     build dies at PassiveSpec.lua "attempt to index field 'tree' (a nil value)".
--   * Also dropped from the treeVersions table -> Build.lua's
--     `if not treeVersions[self.targetVersion]` fires OpenConversionPopup, a
--     modal whose only options are "Convert to <latest>" or "Cancel". The build
--     can then no longer be opened in its own version at all.
-- Neither is acceptable. Retire in offeredTreeVersionList and nowhere else.
--
-- Test: spec/System/TestTreeVersionRetire_spec.lua
--   "keeps the retired versions loadable"
--   "opens as itself rather than being re-pointed at the latest version"
--   "computes on the 1.2 tree and 1.2 data, not the latest ones"
-- See REGRESSION_GUARDS.md "tree-version-loadable-vs-offered".

---Default target version for builds whose XML carries no targetVersion attribute.
---Drives data.setActiveVersion (Build.lua), i.e. which game version's item /
---unique / base data such a build is interpreted with.
---@leb-regression-guard: legacy-target-version-live
---Was "1_2", so an attribute-less build silently got season-2 item data: data
---inherited from the fork, whose source LEB cannot verify, for a season LEB has
---no game files for. Nobody chose it; it was a default. Live data is the only
---defensible interpretation of a build whose version is unknown. Measured blast:
---0 builds (all 644 corpus builds carry targetVersion="1_4"; none take this path).
---Test: spec/System/TestTreeVersionRetire_spec.lua
---  "keeps legacyTargetVersion on a live, offered version"
legacyTargetVersion = "1_4"
---Default target for new builds and target to convert legacy builds to.
liveTargetVersion = "1_4"

-- Skill tree versions
---Every skill tree version LEB can LOAD. Grows as seasons are added; entries are
---never removed, so previously saved builds keep opening on their own tree.
---Data.lua loads per-version data by iterating this list, and main:LoadTree
---gates lazy tree loading on membership here.
---@type string[]
treeVersionList = { "1_2", "1_3", "1_4" }
---Skill tree versions the UI OFFERS for creating or converting a build.
---Retiring a version from the UI means removing it HERE and only here.
---@type string[]
offeredTreeVersionList = { "1_4" }
--- Always points to the latest skill tree version.
--- Positional BY DESIGN: "last entry == newest" stays true as seasons are added,
--- so adding "1_5" to treeVersionList automatically makes 1_4 builds show the
--- "Convert to 1.5" button. Do not convert this one to a name.
latestTreeVersion = treeVersionList[#treeVersionList]
---Version assumed for a <Spec> element that carries no treeVersion attribute.
---@leb-regression-guard: default-tree-version-named-not-positional
---Was `treeVersionList[2]`, whose meaning is a NAME ("1_3"), not a position.
---Measured: shrinking treeVersionList to 2 entries silently rebound this to
---"1_4" -- it does not go nil, so nothing announces the change. Keep it a name.
---Test: spec/System/TestTreeVersionRetire_spec.lua
---  "pins defaultTreeVersion by name to a loadable version"
---  "declares defaultTreeVersion as a literal, not an index into treeVersionList"
defaultTreeVersion = "1_3"
---Display, comparison and export data for all supported skill tree versions.
---Keyed by every LOADABLE version (treeVersionList), not just the offered ones:
---Build.lua treats a missing key as "unsupported, convert or cancel".
---@type table<string, {display: string, num: number, url: string}>
treeVersions = {
	["1_2"] = {
		display = "1.2",
		num = 1.2,
		url = "",
	},
	["1_3"] = {
		display = "1.3",
		num = 1.3,
		url = "",
	},
	["1_4"] = {
		display = "1.4",
		num = 1.4,
		url = "",
	},
}
