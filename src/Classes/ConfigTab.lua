-- Last Epoch Building
--
-- Module: Config Tab
-- Configuration tab for the current build.
--
local t_insert = table.insert
local m_min = math.min
local m_max = math.max
local m_floor = math.floor
local s_upper = string.upper

local varList = LoadModule("Modules/ConfigOptions")

-- @leb-regression-guard: config-label-fit
-- Config-label wrapping constants. File-level so BOTH the constructor
-- (wrapLabel / section height) AND ConfigTabClass:Draw (the per-frame layout
-- loop that also sizes rows by label line count) can see them -- a
-- constructor-local here would be nil inside Draw and crash every frame.
-- Test: spec/System/TestConfigTabDrawSmoke_spec.lua, TestConfigLabelFit_spec.lua
local CONFIG_LABEL_FONT = 14          -- uniform label font size
local CONFIG_LABEL_MAXWIDTH = 228     -- box inner width from control left to border
local CONFIG_LABEL_LINE_H = CONFIG_LABEL_FONT + 2  -- per wrapped line (font + gap)

local ConfigTabClass = newClass("ConfigTab", "UndoHandler", "ControlHost", "Control", function(self, build)
	self.UndoHandler()
	self.ControlHost()
	self.Control()

	self.build = build

	-- ConfigSet system (mirrors ItemsTab.itemSets / SkillsTab.skillSets).
	-- self.input and self.placeholder are *aliases* onto the active set's tables,
	-- so every existing call site continues to work unchanged.
	self.configSets = { }
	self.configSetOrderList = { 1 }
	self.activeConfigSetId = 1
	self:NewConfigSet(1, "Default")
	self.input = self.configSets[1].input
	self.placeholder = self.configSets[1].placeholder
	self.defaultState = { }

	self.enemyLevel = 100

	self.sectionList = { }
	self.varControls = { }
	
	self:BuildModList()
	
	self.toggleConfigs = false

	self.controls.sectionAnchor = new("LabelControl", { "TOPLEFT", self, "TOPLEFT" }, 0, 20, 0, 0, "")
	self.controls.search = new("EditControl", { "TOPLEFT", self.controls.sectionAnchor, "TOPLEFT" }, 8, -15, 360, 20, "", "Search", "%c", 100, function()
		self:UpdateControls()
	end, nil, nil, true)
	self.controls.toggleConfigs = new("ButtonControl", { "LEFT", self.controls.search, "RIGHT" }, 10, 0, 200, 20, function()
		-- dynamic text
		return self.toggleConfigs and "Hide Ineligible Configurations" or "Show All Configurations"
	end, function()
		self.toggleConfigs = not self.toggleConfigs
	end)
	self.controls.resetDefaults = new("ButtonControl", { "LEFT", self.controls.toggleConfigs, "RIGHT" }, 10, 0, 120, 20, "Reset to Defaults", function()
		-- Wipe the active set's tables in-place so external aliases stay valid.
		wipeTable(self.input)
		wipeTable(self.placeholder)
		self:AddUndoState()
		self:BuildModList()
		self:UpdateControls()
		self.build.buildFlag = true
	end)
	self.controls.resetDefaults.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip:AddLine(14, "Clear all configuration options back to their default values.")
		tooltip:AddLine(14, "Useful when you want a clean baseline for DPS comparison.")
	end

	-- @leb-regression-guard:config-sets-ui
	-- Config-set selector (ported from PoB, adapted to LEB). The config-set
	-- backend (configSets / configSetOrderList / NewConfigSet /
	-- SetActiveConfigSet + multi-set Save/Load) was already inherited and
	-- functional; this surfaces it: a dropdown to switch the active set and a
	-- "Manage..." button opening the ConfigSetListControl popup
	-- (New/Copy/Rename/Delete/reorder). Lets users keep named presets like
	-- "Boss" / "Mapping" / "Single Target". Generic planner UX — no LE/PoE
	-- game content. Spec: spec/System/TestConfigSetsUI_spec.lua.
	self.controls.setSelect = new("DropDownControl", { "LEFT", self.controls.resetDefaults, "RIGHT" }, 90, 0, 180, 20, nil, function(index, value)
		self:SetActiveConfigSet(self.configSetOrderList[index])
		self:AddUndoState()
		self.build.buildFlag = true
	end)
	self.controls.setSelect.enableDroppedWidth = true
	self.controls.setSelect.enabled = function()
		return #self.configSetOrderList > 1
	end
	self.controls.setLabel = new("LabelControl", { "RIGHT", self.controls.setSelect, "LEFT" }, -2, 0, 0, 16, "^7Config set:")
	self.controls.setManage = new("ButtonControl", { "LEFT", self.controls.setSelect, "RIGHT" }, 4, 0, 90, 20, "Manage...", function()
		self:OpenConfigSetManagePopup()
	end)

	local function searchMatch(varData)
		local searchStr = self.controls.search.buf:lower():gsub("[%-%.%+%[%]%$%^%%%?%*]", "%%%0")
		if searchStr and searchStr:match("%S") then
			local err, match = PCall(string.matchOrPattern, (varData.label or ""):lower(), searchStr)
			if not err and match then
				return true
			end
			return false
		end
		return true
	end

	-- blacklist for Show All Configurations
	local function isShowAllConfig(varData)
		local labelMatch = varData.label:lower()
		local excludeKeywords = { "recently", "in the last", "in the past", "in last", "in past", "pvp" }

		if not self.toggleConfigs then
			return false
		end
		if varData.ifOption or varData.ifSkill or varData.ifSkillData or varData.ifSkillFlag or varData.legacy then
			return false
		end
		for _, keyword in pairs(excludeKeywords) do
			if labelMatch:find(keyword) then
				return false
			end
		end
		return true
	end

	local function implyCond(varData)
		local mainEnv = self.build.calcsTab.mainEnv
		if self.input[varData.var] then
			if varData.implyCondList then
				for _, implyCond in ipairs(varData.implyCondList) do
					if (implyCond and mainEnv.conditionsUsed[implyCond]) then
						return true
					end
				end
			end
			if (varData.implyCond and mainEnv.conditionsUsed[varData.implyCond]) or
			   (varData.implyMinionCond and mainEnv.minionConditionsUsed[varData.implyMinionCond]) or
			   (varData.implyEnemyCond and mainEnv.enemyConditionsUsed[varData.implyEnemyCond]) then
				return true
			end
		end

		return false
	end

	-- @leb-regression-guard:config-highlight-suggest-pattern (Phase 1.5 buffDetectPatterns gap fix)
	-- Up to Phase 1, 9 ConfigOptions entries declared `suggestBuff = "X"` but
	-- only 5 X values had a corresponding row in `buffDetectPatterns` below.
	-- The four buff-condition configs `conditionHaveFlameWard` /
	-- `conditionHaveEterrasBlessing` / `conditionMinionsHaveDreadShade` /
	-- `conditionDuringProfaneVeil` therefore had highlights that could never
	-- fire because `detectGrantedBuffs()[buffName]` returned nil for the
	-- corresponding key. Phase 1.5 (2026-05-29 game-data audit) adds those
	-- four rows. Patterns chosen from grep of 1.4 tree json `stats` /
	-- `notScalingStats` for grant phrasing (NOT consumption — the existing
	-- `while/if you have` filter in detectGrantedBuffs strips consumption
	-- mentions so the pattern is matched only against grant lines like
	-- "Cast Flame Ward When Stunned" / "Chance To Cast Eterra's Blessing
	-- While In Range" / "Maximum Dread Shades").
	--
	-- Profane Veil note: 1.4 trees have **zero** non-consumption mentions of
	-- "profane veil" — the pattern is registered for symmetry and forward
	-- compatibility (Warlock skill that some future passive may grant), but
	-- detection from the current passive tree alone will not fire. Catching
	-- it for present Warlock builds requires extending detectGrantedBuffs to
	-- also scan the skill loadout (build.skillsTab.socketGroupList) for
	-- buff-named skills — that's a separate, framework-touching Phase 1.6
	-- task (Phase 1.5 is data-only by design).
	local buffDetectPatterns = {
		{ name = "Haste", pat = "haste" },
		{ name = "Frenzy", pat = "frenzy" },
		{ name = "Concentration", pat = "concentration" },
		{ name = "LightningAegis", pat = "lightning aegis" },
		{ name = "ArcaneShield", pat = "arcane shield" },
		-- Phase 1.5 additions (2026-05-29)
		{ name = "FlameWard", pat = "flame ward" },
		{ name = "EterrasBlessing", pat = "eterra's blessing" },
		{ name = "DreadShade", pat = "dread shade" },
		{ name = "ProfaneVeil", pat = "profane veil" },
		-- @leb-regression-guard:holy-aura-damage-mutator-buff (highlight row)
		-- Pairs with the conditionHolyAuraDamageAura config's suggestBuff = "HolyAura".
		-- Holy Aura is a bar SKILL (Paladin), so Pass 2 (skill-loadout scan) wakes this
		-- pattern when "Holy Aura" is slotted -- exactly when the damage-aura toggle is
		-- relevant. The contract spec (TestConfigHighlightSuggestPattern) requires a row
		-- for every suggestBuff value, else detectGrantedBuffs() returns nil (dead highlight).
		{ name = "HolyAura", pat = "holy aura" },
		-- @leb-regression-guard:icicle-cold-to-lightning-conversion-toggle (highlight row)
		-- Pairs with the conditionIcicleConvertedToLightning config's
		-- suggestBuff = "HeorotUniqueBowIcicle". Icicle is a unique-PROC skill granted by
		-- "Reign of Winter" (#159) "(23-28)% Chance to cast Icicle on Bow Hit", so Pass 3
		-- (equipped-item affix scan) wakes this pattern when that affix text is present --
		-- exactly when the Cold->Lightning toggle is relevant. The `name` must equal the
		-- suggestBuff value so detectGrantedBuffs()[name] is non-nil (else the highlight is
		-- structurally dead and TestConfigHighlightSuggestPattern fails).
		{ name = "HeorotUniqueBowIcicle", pat = "icicle" },
		-- @leb-regression-guard:enchant-weapon-buff (highlight row)
		-- Pairs with the conditionEnchantWeaponActive config's suggestBuff = "EnchantWeapon".
		-- Enchant Weapon is a bar SKILL (Spellblade), so Pass 2 (skill-loadout scan) wakes
		-- this pattern when "Enchant Weapon" is slotted -- exactly when the Active-tier
		-- toggle is relevant. The contract spec (TestConfigHighlightSuggestPattern) requires
		-- a row for every suggestBuff value, else detectGrantedBuffs() returns nil.
		{ name = "EnchantWeapon", pat = "enchant weapon" },
	}
	-- @leb-regression-guard:config-highlight-source-attribution
	-- Phase 3 (2026-05-29) enriches every detection-positive entry with the
	-- SOURCE that produced the match: which passive node, which equipped
	-- skill, or which equipped item — plus the actual line text that hit.
	-- The shape of `detected[buffName]` changes from boolean `true` to a
	-- table `{ source = <label>, line = <text> }`. The label / tooltip
	-- render hooks downstream perform a truthy check on `detected[name]`,
	-- which continues to work because a non-empty table is truthy in Lua —
	-- the existing Phase 1/1.5/1.6/2 highlight behaviour is preserved.
	-- Source labels follow a uniform "<kind> 'X'" convention, using only the
	-- in-game display name (no internal node ids etc.):
	--   * Pass 1 (passive):      "passive node 'Death from Below'"
	--   * Pass 1 (skill subtree): "skill subtree 'Chthonic Fissure' node 'X'"
	--   * Pass 2:                "skill 'Profane Veil'"
	--   * Pass 3:                "item 'Boneclamor Barbute'"
	-- First match wins (the canonical attribution); subsequent matches in
	-- later passes do not overwrite. `line` carries the ORIGINAL (non-
	-- lowered) text so the tooltip can show the human-readable affix /
	-- stat verbatim.
	-- Spec: spec/System/TestConfigHighlightSourceAttribution_spec.lua.

	-- @leb-regression-guard:config-highlight-skill-subtree-scan
	-- Phase 4 (2026-05-29): `self.build.spec.allocNodes` is a single unified
	-- table that contains BOTH player passive tree nodes (UpperCamelCase /
	-- hex ids) AND skill subtree nodes (lowercase treeId-prefixed ids such
	-- as `ch0fs-20` for Chthonic Fissure). Pass 1 already iterates them
	-- transparently — Phase 1 / 1.5 / 3 silently covered skill subtrees but
	-- mislabelled their nodes as `"passive node 'X'"`, leaking the wrong
	-- attribution to the tooltip. Phase 4 introduces a treeId → skill name
	-- lookup so the source label correctly identifies skill subtree nodes
	-- as `"skill subtree '<skill>' node '<name>'"`. The skill name comes
	-- from `socketGroupList[*].grantedEffect.name` and the treeId from
	-- `grantedEffect.treeId` (the canonical pair used by CalcSetup). Node
	-- ids are matched against `treeId .. "-"` to avoid false positives. If
	-- a node id does not match any registered treeId, the legacy "passive
	-- node 'X'" label is preserved unchanged.
	-- Spec: spec/System/TestConfigHighlightSkillSubtreeScan_spec.lua.
	local function getTreeIdToSkillName()
		if self.treeIdToSkillName then
			return self.treeIdToSkillName
		end
		local map = {}
		if self.build.skillsTab and self.build.skillsTab.socketGroupList then
			for _, group in ipairs(self.build.skillsTab.socketGroupList) do
				local ge = group.grantedEffect
				if ge and ge.treeId and ge.name then
					map[ge.treeId] = ge.name
				end
			end
		end
		self.treeIdToSkillName = map
		return map
	end
	local function getNodeSourceLabel(nodeId, node)
		-- Phase 4: lowercase-treeId-prefixed node id → skill subtree label.
		-- Player passive tree node id → unchanged "passive node 'X'" label.
		local label = node.name or node.dn or "unnamed"
		if nodeId then
			local map = getTreeIdToSkillName()
			for treeId, skillName in pairs(map) do
				if type(nodeId) == "string" and nodeId:sub(1, #treeId + 1) == treeId .. "-" then
					return "skill subtree '" .. skillName .. "' node '" .. label .. "'"
				end
			end
		end
		return "passive node '" .. label .. "'"
	end

	-- @leb-regression-guard:config-highlight-item-slot-kind
	-- Phase 6 (2026-05-29): the equipped-item source label was a generic
	-- "item 'X'" for every slot (ring, helmet, idol, idol altar, blessing,
	-- ...). Users asked for the specific slot kind so the tooltip reads e.g.
	-- "ring 'Red Ring of Atlaria'" / "idol altar 'Sunrise...'" /
	-- "blessing (Fall of the Outcasts) 'X'". The kind is derived from
	-- `item.type` (the authoritative item classification — see
	-- ItemsTab SORT_TYPE_TO_CATEGORY), NOT the slot name, because the type
	-- is robust across slot numbering (Ring 1 / Ring 2 → "ring") and
	-- already distinguishes idol sizes / altar / blessing. Special cases:
	--   * "Idol Altar"  → "idol altar"
	--   * "Blessing"    → "blessing (<timeline>)"  (blessing slots are keyed
	--                     by their timeline name, surfaced via slotName)
	--   * "<size> Idol" → "idol"   (collapse every idol footprint to "idol")
	--   * everything else → `item.type:lower()` (ring, helmet, boots, gloves,
	--     body armor, amulet, belt, relic, bow, wand, sceptre, dagger, ...)
	--   * nil / unknown → "item"   (graceful fallback, preserves old label)
	-- Spec: spec/System/TestConfigHighlightItemSlotKind_spec.lua.
	local function getItemSourceKind(item, slotName)
		local t = item and item.type
		if not t or t == "" then return "item" end
		if t == "Idol Altar" then return "idol altar" end
		if t == "Blessing" then
			if slotName and slotName ~= "" then
				return "blessing (" .. slotName .. ")"
			end
			return "blessing"
		end
		if t:find("Idol$") then return "idol" end
		return t:lower()
	end

	-- @leb-regression-guard:config-highlight-multi-source
	-- Phase 4 (2026-05-29, multi-source extension): a single buff / pattern
	-- can be evidenced by MULTIPLE build elements (e.g. two skill subtree
	-- nodes both mentioning "you have haste", or a passive node + an item
	-- affix both granting Frenzy). The single-source first-match-wins shape
	-- established in Phase 3 hid that — the tooltip showed only one
	-- canonical source, leading users to miss other contributors.
	--
	-- Shape (backward-compatible — `attrib.source` / `attrib.line` keep their
	-- Phase 3 meaning as the canonical first hit):
	--   detected[buffName] = {
	--       source  = <first hit's source>,    -- mirror of sources[1].source
	--       line    = <first hit's line>,      -- mirror of sources[1].line
	--       sources = {                        -- ALL hits, append order
	--           { source = "passive node 'A'",            line = "..." },
	--           { source = "skill subtree 'X' node 'Y'",  line = "..." },
	--           ...
	--       },
	--   }
	--
	-- `addBuffSource(detected, buffName, source, line)` is the single
	-- write site shared by Pass 1 / 2 / 3. It (a) initialises the entry
	-- with the canonical first source/line mirrors on first call, and
	-- (b) always appends to `sources`. No dedup — the same (source, line)
	-- pair shouldn't recur within a single Pass loop (each node / skill
	-- / item is iterated once), and if two different lines on the same
	-- node both hit a pattern that's information the tooltip SHOULD show.
	-- Spec: spec/System/TestConfigHighlightMultiSource_spec.lua.
	local function addBuffSource(detected, buffName, source, line)
		local entry = detected[buffName]
		if not entry then
			entry = { source = source, line = line, sources = {} }
			detected[buffName] = entry
		end
		t_insert(entry.sources, { source = source, line = line })
	end
	local function detectGrantedBuffs()
		if self.detectedBuffs then
			return self.detectedBuffs
		end
		local detected = {}
		-- Pass 1: passive tree allocated nodes (Phase 1 establishing path).
		-- Grant phrasing only — the `while/if you have` filter strips
		-- consumption lines so a node saying "while you have Haste" is NOT
		-- treated as evidence the build grants Haste. Phase 4 (2026-05-29):
		-- iteration key now used to differentiate player passive nodes
		-- from skill subtree nodes via getNodeSourceLabel(); both kinds
		-- live in the same allocNodes table.
		-- Phase 4 multi-source extension: collect ALL evidence, not just
		-- first match. addBuffSource() appends to detected[name].sources.
		for nodeId, node in pairs(self.build.spec.allocNodes) do
			local sdList = node.sd or node.stats
			if sdList then
				for _, statText in ipairs(sdList) do
					local lower = statText:lower()
					if not lower:match("while you have") and not lower:match("if you have") then
						for _, buff in ipairs(buffDetectPatterns) do
							if lower:match(buff.pat) then
								addBuffSource(detected, buff.name, getNodeSourceLabel(nodeId, node), statText)
							end
						end
					end
				end
			end
		end
		-- @leb-regression-guard:config-highlight-skill-loadout-scan
		-- Pass 2 (Phase 1.6, 2026-05-29): the active skill bar.
		-- Some buffs are not granted by passive nodes but are the buff itself
		-- equipped as an active skill — Profane Veil (Warlock) is the canonical
		-- case. Phase 1.5 registered the "profane veil" pattern in
		-- buffDetectPatterns as a dormant placeholder for exactly this Phase
		-- 1.6 pass to wake up. Same buffDetectPatterns table, plain
		-- substring match against `activeEffect.grantedEffect.name` lower-cased.
		-- The `while/if you have` exclusion filter intentionally does NOT
		-- apply here — a skill's display name (e.g. "Profane Veil") is the
		-- buff itself, not consumption phrasing about it. The two passes
		-- share `detected` set semantics so a buff present in both paths is
		-- still recorded exactly once. Spec:
		-- spec/System/TestConfigHighlightSkillLoadoutScan_spec.lua.
		if self.build.skillsTab and self.build.skillsTab.socketGroupList then
			for _, group in ipairs(self.build.skillsTab.socketGroupList) do
				if group.displaySkillList then
					for _, skill in ipairs(group.displaySkillList) do
						local skillName = skill.activeEffect
							and skill.activeEffect.grantedEffect
							and skill.activeEffect.grantedEffect.name
						if skillName then
							local lower = skillName:lower()
							for _, buff in ipairs(buffDetectPatterns) do
								if lower:match(buff.pat) then
									addBuffSource(detected, buff.name, "skill '" .. skillName .. "'", skillName)
								end
							end
						end
					end
				end
			end
		end
		-- @leb-regression-guard:config-highlight-item-modlist-scan
		-- Pass 3 (Phase 2, 2026-05-29): equipped items' explicit affix text.
		-- An equipped item bearing an affix that *mentions* a buff (whether
		-- the affix grants or consumes it) is itself evidence the build cares
		-- about that buff's Have-Buff config. Concrete examples: an item with
		-- "while you have Haste +40% Damage" affix means the build wants
		-- `conditionHaste` ON; an item with "(15-40)% Chance to Gain 30 Ward
		-- when Hit" — when it's a Frenzy / Haste etc grant — same signal.
		-- The `while/if you have` exclusion filter intentionally does NOT
		-- apply here, mirroring the Phase 1.6 skill-loadout pass logic: on
		-- items, consumption phrasing IS the relevance signal because the
		-- user obviously equipped the affix to scale with that state.
        --
		-- Slot iteration uses `build.itemsTab.orderedSlots[*].selItemId →
		-- items[id]` (the standard equipped-only path used by CalcSetup).
		-- Walking `items` directly would over-include inventory items the
		-- build is not actually wearing. `explicitModLines[*].line` is the
		-- raw human-readable affix text built by the import pipeline.
		-- Implicit lines and crafted-line metadata also live in modLines
		-- pulled into `explicitModLines`; we keep the single source.
		-- Spec: spec/System/TestConfigHighlightItemModListScan_spec.lua.
		if self.build.itemsTab and self.build.itemsTab.orderedSlots then
			for _, slot in pairs(self.build.itemsTab.orderedSlots) do
				local item = slot.selItemId and self.build.itemsTab.items[slot.selItemId]
				if item and item.explicitModLines then
					local itemName = item.title or item.name or item.baseName or "?"
					-- Phase 6: slot-specific kind ("ring '...'", "idol altar '...'") instead of generic "item '...'".
					local sourceLabel = getItemSourceKind(item, slot.slotName) .. " '" .. itemName .. "'"
					for _, modLine in ipairs(item.explicitModLines) do
						if modLine.line then
							local lower = modLine.line:lower()
							for _, buff in ipairs(buffDetectPatterns) do
								if lower:match(buff.pat) then
									addBuffSource(detected, buff.name, sourceLabel, modLine.line)
								end
							end
						end
					end
				end
			end
		end
		self.detectedBuffs = detected
		return detected
	end

	-- @leb-regression-guard:config-highlight-suggest-pattern
	-- @leb-regression-guard:config-highlight-item-modlist-scan (corpus extension)
	-- @leb-regression-guard:config-highlight-source-attribution (entry shape)
	-- Validation provenance is retained in maintainer notes.
	local function getAllocNodeTextCorpusLowered()
		if self.allocNodeTextCorpus then
			return self.allocNodeTextCorpus
		end
		local lines = {}
		-- Source A: passive tree allocated nodes (Phase 1 establishing).
		-- Phase 4 (2026-05-29): the same allocNodes table contains both
		-- player passive nodes and skill subtree nodes; getNodeSourceLabel
		-- routes the label to "skill subtree '<skill>' node 'X'" when the
		-- node id is treeId-prefixed.
		for nodeId, node in pairs(self.build.spec.allocNodes) do
			local sdList = node.sd or node.stats
			if sdList then
				local sourceLabel = getNodeSourceLabel(nodeId, node)
				for _, statText in ipairs(sdList) do
					t_insert(lines, {
						text = statText:lower(),
						line = statText,
						source = sourceLabel,
					})
				end
			end
		end
		-- Source B: equipped items' explicit affix lines (Phase 2 addition).
		if self.build.itemsTab and self.build.itemsTab.orderedSlots then
			for _, slot in pairs(self.build.itemsTab.orderedSlots) do
				local item = slot.selItemId and self.build.itemsTab.items[slot.selItemId]
				if item and item.explicitModLines then
					local itemName = item.title or item.name or item.baseName or "?"
					-- Phase 6: slot-specific kind instead of generic "item '...'".
					local sourceLabel = getItemSourceKind(item, slot.slotName) .. " '" .. itemName .. "'"
					for _, modLine in ipairs(item.explicitModLines) do
						if modLine.line then
							t_insert(lines, {
								text = modLine.line:lower(),
								line = modLine.line,
								source = sourceLabel,
							})
						end
					end
				end
			end
		end
		self.allocNodeTextCorpus = lines
		return lines
	end

	local function detectMatchingPattern(pattern)
		-- Phase 4 multi-source extension: collect ALL matching corpus entries
		-- across the full pattern list (OR semantics across patList, AND-of-
		-- scanning across the corpus). Returns nil on no match, or a record
		-- `{ source, line, sources }` where `source` / `line` mirror the
		-- canonical first hit (Phase 3 backward-compat) and `sources` is the
		-- full append-order array of `{source, line}` hits.
		local lines = getAllocNodeTextCorpusLowered()
		local patList = type(pattern) == "table" and pattern or { pattern }
		local result = nil
		for _, p in ipairs(patList) do
			local lp = tostring(p):lower()
			if lp ~= "" then
				for _, entry in ipairs(lines) do
					if entry.text:find(lp, 1, true) then
						if not result then
							result = { source = entry.source, line = entry.line, sources = {} }
						end
						t_insert(result.sources, { source = entry.source, line = entry.line })
					end
				end
			end
		end
		return result
	end

	local function listOrSingleIfOption(ifOption, ifFunc)
		return function()
			if type(ifOption) == "table" then
				for _, ifOpt in ipairs(ifOption) do
					if ifFunc(ifOpt) then
						return true
					end
				end
			end
			return ifFunc(ifOption)
		end
	end

	local function listOrSingleIfTooltip(ifOption, ifFunc)
		return function()
			if type(ifOption) == "table" then
				local out
				for _, ifOpt in ipairs(ifOption) do
					local curTooltipText = ifFunc(ifOpt)
					if curTooltipText then
						out = (out and out .. "\n" or "").. curTooltipText
					end
				end
				return out
			end
			return ifFunc(ifOption)
		end
	end

	-- @leb-regression-guard:config-highlight-autoshow
	-- A config that is currently "orange" (build-relevant) should be visible even
	-- when "Show All Configurations" is OFF -- otherwise the user must toggle Show
	-- All to find every highlighted option (user-requested 2026-06-09). Mirrors
	-- the three orange-label detections used by the labelControl.label closures:
	--   suggestBuff      -> detectGrantedBuffs()[buffName]
	--   suggestPattern   -> detectMatchingPattern(pattern)
	--   suggestCond/EnemyCond/Mult -> conditionsUsed/enemyConditionsUsed/multipliersUsed count > 0
	-- OR'd into control.shown alongside isShowAllConfig, so ONLY highlighted
	-- configs bypass their ifCond/ifMult/... gate (non-highlighted gated configs
	-- stay hidden until Show All). Display-only -- no calc/DPS/EHP impact.
	-- Spec: spec/System/TestConfigHighlightAutoShow_spec.lua
	local function isHighlighted(varData)
		if varData.suggestBuff and detectGrantedBuffs()[varData.suggestBuff] then return true end
		if varData.suggestPattern and detectMatchingPattern(varData.suggestPattern) then return true end
		-- modDB-signal: same tables countModDBUses() uses. No combined
		-- `if suggestCond or suggestEnemyCond or suggestMult` guard here -- tally
		-- already returns 0 for nil keys, and omitting it avoids duplicating the
		-- exact anchor string TestConfigHighlightModDBSignal greps for.
		local mainEnv = self.build.calcsTab and self.build.calcsTab.mainEnv
		if mainEnv then
			local function tally(tbl, keys)
				if not keys or not tbl then return 0 end
				local list = type(keys) == "table" and keys or { keys }
				local n = 0
				for _, k in ipairs(list) do
					local mods = tbl[k]
					if mods then n = n + #mods end
				end
				return n
			end
			if tally(mainEnv.conditionsUsed, varData.suggestCond)
				+ tally(mainEnv.enemyConditionsUsed, varData.suggestEnemyCond)
				+ tally(mainEnv.multipliersUsed, varData.suggestMult) > 0 then
				return true
			end
		end
		return false
	end

	-- @leb-regression-guard: config-label-fit
	-- Config labels sit to the LEFT of their control (right-anchored
	-- LabelControl, or the CheckBoxControl's own right-aligned label) and grow
	-- leftward toward the section box's inner border, ~228px away. Long
	-- LEB-specific labels (e.g. "# of Skeleton Warriors Absorbed by
	-- Abomination:" / "Apply Tyrant's Skull per-attribute Tyrannosaur block?")
	-- overflow that border. Rather than shrink the font (which made some
	-- labels too small to read), keep a UNIFORM font size and WRAP the label
	-- onto multiple lines, each fitting within the box. Returns the
	-- newline-joined label and the number of lines (used to grow the row so
	-- the wrapped lines don't overlap the next control). Constants are
	-- file-level (see top of file) so the Draw layout loop can reuse them.
	local function wrapLabel(label)
		if DrawStringWidth(CONFIG_LABEL_FONT, "VAR", label) <= CONFIG_LABEL_MAXWIDTH then
			return label, 1
		end
		local lines = {}
		local cur
		for word in label:gmatch("%S+") do
			local try = cur and (cur .. " " .. word) or word
			if cur and DrawStringWidth(CONFIG_LABEL_FONT, "VAR", try) > CONFIG_LABEL_MAXWIDTH then
				t_insert(lines, cur)
				cur = word
			else
				cur = try
			end
		end
		if cur then
			t_insert(lines, cur)
		end
		return table.concat(lines, "\n"), #lines
	end

	local lastSection
	for _, varData in ipairs(varList) do
		if varData.section then
			lastSection = new("SectionControl", {"TOPLEFT",self.controls.sectionAnchor,"TOPLEFT"}, 0, 0, 360, 0, varData.section)
			lastSection.varControlList = { }
			lastSection.col = varData.col
			lastSection.height = function(self)
				local height = 20
				for _, varControl in pairs(self.varControlList) do
					if varControl:IsShown() then
						local rowH = m_max(varControl.height, 16, (varControl.labelLineCount or 1) * CONFIG_LABEL_LINE_H)
						height = height + rowH + 4
					end
				end
				return m_max(height, 32)
			end
			t_insert(self.sectionList, lastSection)
			t_insert(self.controls, lastSection)
		else
			local control
			if varData.type == "check" then
				-- Wrap long checkbox labels onto multiple lines (uniform font);
				-- labelLineCount grows the row so wrapped lines don't overlap.
				local checkLabel, checkLines = wrapLabel(varData.label)
				control = new("CheckBoxControl", {"TOPLEFT",lastSection,"TOPLEFT"}, 234, 0, 18, checkLabel, function(state)
					self.input[varData.var] = state
					self:AddUndoState()
					self:BuildModList()
					self.build.buildFlag = true
				end)
				control.labelLineCount = checkLines
			elseif varData.type == "count" or varData.type == "integer" or varData.type == "countAllowZero" or varData.type == "float" then
				control = new("EditControl", {"TOPLEFT",lastSection,"TOPLEFT"}, 234, 0, 90, 18, "", nil, (varData.type == "integer" and "^%-%d") or (varData.type == "float" and "^%d.") or "%D", 7, function(buf, placeholder)
					if placeholder then
						self.placeholder[varData.var] = tonumber(buf)
					else
						self.input[varData.var] = tonumber(buf)
						self:AddUndoState()
						self:BuildModList()
					end
					self.build.buildFlag = true
				end)
			elseif varData.type == "list" then
				control = new("DropDownControl", {"TOPLEFT",lastSection,"TOPLEFT"}, 234, 0, 118, 16, varData.list, function(index, value)
					self.input[varData.var] = value.val
					self:AddUndoState()
					self:BuildModList()
					self.build.buildFlag = true
				end)
			elseif varData.type == "text" then
				control = new("EditControl", {"TOPLEFT",lastSection,"TOPLEFT"}, 8, 0, 344, 118, "", nil, "^%C\t\n", nil, function(buf, placeholder)
					if placeholder then
						self.placeholder[varData.var] = tostring(buf)
					else
						self.input[varData.var] = tostring(buf)
						self:AddUndoState()
						self:BuildModList()
					end
					self.build.buildFlag = true
				end, 16)
			else
				control = new("Control", {"TOPLEFT",lastSection,"TOPLEFT"}, 234, 0, 16, 16)
			end

			if varData.inactiveText then
				control.inactiveText = varData.inactiveText
			end

			local shownFuncs = {}
			control.shown = function()
				if not searchMatch(varData) then
					return false
				end

				-- @leb-regression-guard:config-highlight-autoshow
				-- Orange/highlighted (build-relevant) configs bypass their gate so
				-- they show even with "Show All Configurations" OFF.
				local highlighted = isHighlighted(varData)
				for _, shownFunc in ipairs(shownFuncs) do
					if not shownFunc() and not isShowAllConfig(varData) and not highlighted then
						return false
					end
				end
				return true
			end

			local tooltipFuncs = {}
			control.tooltipText = function()
				local out
				for i, tooltipFunc in ipairs(tooltipFuncs) do
					local curTooltipText = type(tooltipFunc) == "string" and tooltipFunc or tooltipFunc(self.modList, self.build)
					if curTooltipText then
						out = (out and out .. "\n" or "") .. curTooltipText
					end
				end
				return out
			end

			if varData.tooltip then
				t_insert(tooltipFuncs, varData.tooltip)
			end

			if varData.ifNode then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifNode, function(ifOption)
					if self.build.spec.allocNodes[ifOption] then
						return true
					end
					local node = self.build.spec.nodes[ifOption]
					if node and node.type == "Keystone" then
						return self.build.calcsTab.mainEnv.keystonesAdded[node.dn]
					end
				end))
				t_insert(tooltipFuncs, listOrSingleIfTooltip(varData.ifNode, function(ifOption)
					return "This option is specific to '"..self.build.spec.nodes[ifOption].dn.."'."
				end))
			end
			if varData.ifOption then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifOption, function(ifOption)
					return self.input[ifOption]
				end))
			end
			if varData.ifCond then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifCond, function(ifOption)
					if implyCond(varData) then
						return true
					end
					return self.build.calcsTab.mainEnv.conditionsUsed[ifOption]
				end))
				t_insert(tooltipFuncs, listOrSingleIfTooltip(varData.ifCond, function(ifOption)
					if not launch.devModeAlt then
						return
					end
					local out
					local mods = self.build.calcsTab.mainEnv.conditionsUsed[ifOption]
					if not mods then
						return out
					end
					for _, mod in ipairs(mods) do
						out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
					end
					return out
				end))
			end
			if varData.ifMinionCond then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifMinionCond, function(ifOption)
					if implyCond(varData) then
						return true
					end
					return self.build.calcsTab.mainEnv.minionConditionsUsed[ifOption]
				end))
				t_insert(tooltipFuncs, listOrSingleIfTooltip(varData.ifMinionCond, function(ifOption)
					if not launch.devModeAlt then
						return
					end
					local out
					local mods = self.build.calcsTab.mainEnv.minionConditionsUsed[ifOption]
					if not mods then
						return out
					end
					for _, mod in ipairs(mods) do
						out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
					end
					return out
				end))
			end
			if varData.ifEnemyCond then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifEnemyCond, function(ifOption)
					if implyCond(varData) then
						return true
					end
					return self.build.calcsTab.mainEnv.enemyConditionsUsed[ifOption]
				end))
				t_insert(tooltipFuncs, listOrSingleIfTooltip(varData.ifEnemyCond, function(ifOption)
					if not launch.devModeAlt then
						return
					end
					local out
					local mods = self.build.calcsTab.mainEnv.enemyConditionsUsed[ifOption]
					if not mods then
						return out
					end
					for _, mod in ipairs(mods) do
						out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
					end
					return out
				end))
			end
			if varData.ifMult then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifMult, function(ifOption)
					if implyCond(varData) then
						return true
					end
					return self.build.calcsTab.mainEnv.multipliersUsed[ifOption]
				end))
				t_insert(tooltipFuncs, listOrSingleIfTooltip(varData.ifMult, function(ifOption)
					if not launch.devModeAlt then
						return
					end
					local out
					local mods = self.build.calcsTab.mainEnv.multipliersUsed[ifOption]
					if not mods then
						return out
					end
					for _, mod in ipairs(mods) do
						out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
					end
					return out
				end))
			end
			if varData.ifEnemyMult then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifEnemyMult, function(ifOption)
					if implyCond(varData) then
						return true
					end
					return self.build.calcsTab.mainEnv.enemyMultipliersUsed[ifOption]
				end))
				t_insert(tooltipFuncs, listOrSingleIfTooltip(varData.ifEnemyMult, function(ifOption)
					if not launch.devModeAlt then
						return
					end
					local out
					local mods = self.build.calcsTab.mainEnv.enemyMultipliersUsed[ifOption]
					if not mods then
						return out
					end
					for _, mod in ipairs(mods) do
						out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
					end
					return out
				end))
			end
			if varData.ifStat then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifStat, function(ifOption)
					if implyCond(varData) then
						return true
					end
					return self.build.calcsTab.mainEnv.perStatsUsed[ifOption] or self.build.calcsTab.mainEnv.enemyMultipliersUsed[ifOption]
				end))
				t_insert(tooltipFuncs, listOrSingleIfTooltip(varData.ifStat, function(ifOption)
					if not launch.devModeAlt then
						return
					end
					local out
					local mods = self.build.calcsTab.mainEnv.perStatsUsed[ifOption]
					if mods then
						for _, mod in ipairs(mods) do
							out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
						end
					end
					local mods2 = self.build.calcsTab.mainEnv.enemyMultipliersUsed[ifOption]
					if mods2 then
						for _, mod in ipairs(mods2) do
							out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
						end
					end
					return out
				end))
			end
			if varData.ifEnemyStat then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifEnemyStat, function(ifOption)
					if implyCond(varData) then
						return true
					end
					return self.build.calcsTab.mainEnv.enemyPerStatsUsed[ifOption]
				end))
				t_insert(tooltipFuncs, listOrSingleIfTooltip(varData.ifEnemyStat, function(ifOption)
					if not launch.devModeAlt then
						return
					end
					local out
					local mods = self.build.calcsTab.mainEnv.enemyPerStatsUsed[ifOption]
					if not mods then
						return out
					end
					for _, mod in ipairs(mods) do
						out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
					end
					return out
				end))
			end
			if varData.ifTagType then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifTagType, function(ifOption)
					if implyCond(varData) then
						return true
					end
					return self.build.calcsTab.mainEnv.tagTypesUsed[ifOption]
				end))
				t_insert(tooltipFuncs, listOrSingleIfTooltip(varData.ifTagType, function(ifOption)
					if not launch.devModeAlt then
						return
					end
					local out
					local mods = self.build.calcsTab.mainEnv.tagTypesUsed[ifOption]
					if not mods then
						return out
					end
					for _, mod in ipairs(mods) do
						out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
					end
					return out
				end))
			end
			if varData.ifFlag then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifFlag, function(ifOption)
					local skillModList = self.build.calcsTab.mainEnv.player.mainSkill.skillModList
					local skillFlags = self.build.calcsTab.mainEnv.player.mainSkill.skillFlags
					-- Check both the skill mods for flags and flags that are set via calcPerform
					return skillFlags[ifOption] or skillModList:Flag(nil, ifOption)
				end))
			end
			if varData.ifMod then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifMod, function(ifOption)
					if implyCond(varData) then
						return true
					end
					return self.build.calcsTab.mainEnv.modsUsed[ifOption]
				end))
				t_insert(tooltipFuncs, listOrSingleIfTooltip(varData.ifMod, function(ifOption)
					if not launch.devModeAlt then
						return
					end
					local out
					local mods = self.build.calcsTab.mainEnv.modsUsed[ifOption]
					if not mods then
						return out
					end
					for _, mod in ipairs(mods) do
						out = (out and out.."\n" or "") .. modLib.formatMod(mod) .. "|" .. mod.source
					end
					return out
				end))
			end
			if varData.ifSkill then
				if varData.includeTransfigured then
					t_insert(shownFuncs, listOrSingleIfOption(varData.ifSkill, function(ifOption)
						if not calcLib.getGameIdFromGemName(ifOption, true) then
							return false
						end
						for skill,_ in pairs(self.build.calcsTab.mainEnv.skillsUsed) do
							if calcLib.isGemIdSame(skill, ifOption, true) then
								return true
							end
						end
						return false
					end))
				else
					t_insert(shownFuncs, listOrSingleIfOption(varData.ifSkill, function(ifOption)
						return self.build.calcsTab.mainEnv.skillsUsed[ifOption]
					end))
				end
			end
			if varData.ifSkillFlag then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifSkillFlag, function(ifOption)
					for _, activeSkill in ipairs(self.build.calcsTab.mainEnv.player.activeSkillList) do
						if activeSkill.skillFlags[ifOption] then
							return true
						end
					end
					return false
				end))
			end
			if varData.ifSkillData then
				t_insert(shownFuncs, listOrSingleIfOption(varData.ifSkillData, function(ifOption)
					for _, activeSkill in ipairs(self.build.calcsTab.mainEnv.player.activeSkillList) do
						if activeSkill.skillData[ifOption] then
							return true
						end
					end
					return false
				end))
			end

			if varData.tooltipFunc then
				control.tooltipFunc = varData.tooltipFunc
			end
			local labelControl = control
			if varData.label and varData.type ~= "check" then
				-- Wrap long labels onto multiple right-aligned lines (uniform
				-- font); labelLineCount (stored on the control) grows the row.
				local wrapped, wrapLines = wrapLabel(varData.label)
				-- Re-assert ^7 on every wrapped line (LabelControl:Draw issues one
				-- DrawString per line with no SetDrawColor, so a colour code only
				-- on line 1 would leave later lines using the ambient colour).
				labelControl = new("LabelControl", {"RIGHT",control,"LEFT"}, -4, 0, 0, CONFIG_LABEL_FONT, "^7"..(wrapped:gsub("\n", "\n^7")))
				labelControl.rightAlignLines = true
				control.labelLineCount = wrapLines
				t_insert(self.controls, labelControl)
			end
			if varData.var then
				self.input[varData.var] = varData.defaultState
				control.state = varData.defaultState
				self.varControls[varData.var] = control
				self.placeholder[varData.var] = varData.defaultPlaceholderState
				control.placeholder = varData.defaultPlaceholderState
				if varData.defaultIndex then
					self.input[varData.var] = varData.list[varData.defaultIndex].val
					control.selIndex = varData.defaultIndex
				end
				if varData.type == "check" then
					self.defaultState[varData.var] = varData.defaultState or false
				elseif varData.type == "count" or varData.type == "integer" or varData.type == "countAllowZero" or varData.type == "float" then
					self.defaultState[varData.var] = varData.defaultState or 0
				elseif varData.type == "list" then
					self.defaultState[varData.var] = varData.list[varData.defaultIndex or 1].val
				elseif varData.type == "text" then
					self.defaultState[varData.var] = varData.defaultState or ""
				else
					self.defaultState[varData.var] = varData.defaultState
				end
			end

			local innerShown = control.shown
			if not varData.doNotHighlight then
				control.borderFunc = function()
					local shown = type(innerShown) == "boolean" and innerShown or innerShown()
					local cur = self.input[varData.var]
					local def = self:GetDefaultState(varData.var, type(cur))
					if cur ~= nil and cur ~= def then
						if not shown then
							return 	0.753, 0.502, 0.502
						end
						return 	0.451, 0.576, 0.702
					end
					return 0.5, 0.5, 0.5
				end
			end

			if not varData.hideIfInvalid then
				control.shown = function()
					if not searchMatch(varData) then
						return false
					end
					local shown = type(innerShown) == "boolean" and innerShown or innerShown()
					local cur = self.input[varData.var]
					local def = self:GetDefaultState(varData.var, type(cur))
					return not shown and cur ~= nil and cur ~= def or shown
				end
				local innerLabel = labelControl.label
				labelControl.label = function()
					local shown = type(innerShown) == "boolean" and innerShown or innerShown()
					local cur = self.input[varData.var]
					local def = self:GetDefaultState(varData.var, type(cur))
					if not shown and cur ~= nil and cur ~= def then
						return colorCodes.NEGATIVE..StripEscapes(innerLabel)
					end
					return innerLabel
				end
				local innerTooltipFunc = control.tooltipFunc
				control.tooltipFunc = function (tooltip, ...)
					tooltip:Clear()
					-- @leb-regression-guard:config-highlight-tooltip-maxwidth
					-- Phase 6 (2026-05-29): the config tab never set a tooltip
					-- maxWidth, so TooltipClass:AddLine's wrap path (which only
					-- runs when self.maxWidth is set) was skipped and a long
					-- single line (e.g. the source-attribution trailer with a
					-- full item affix line, or a multi-source list) ran off the
					-- right edge of the screen. Set it here, mirroring the
					-- ItemsTab idiom (`if not tooltip.maxWidth then ... end`), so
					-- every config tooltip wraps. 480 keeps it readable without
					-- crowding the config column layout.
					-- Spec: spec/System/TestConfigHighlightItemSlotKind_spec.lua.
					if not tooltip.maxWidth then
						tooltip.maxWidth = 480
					end

					if innerTooltipFunc then
						innerTooltipFunc(tooltip, ...)
					else
						local tooltipText = control:GetProperty("tooltipText")
						if tooltipText and tooltipText ~= '' then
							tooltip:AddLine(14, tooltipText)
						end
					end

					local shown = type(innerShown) == "boolean" and innerShown or innerShown()
					local cur = self.input[varData.var]
					local def = self:GetDefaultState(varData.var, type(cur))
					if not shown and cur ~= nil and cur ~= def then
						tooltip:AddLine(14, colorCodes.NEGATIVE.."This config option is conditional with missing source and is invalid.")
					end
				end
			end

			if varData.suggestBuff then
				local innerSuggestLabel = labelControl.label
				local buffName = varData.suggestBuff
				local function isSuggestActive()
					if varData.type == "check" then
						return self.input[varData.var]
					end
					return (self.input[varData.var] or 0) > 0
				end
				labelControl.label = function()
					local label = type(innerSuggestLabel) == "function" and innerSuggestLabel() or innerSuggestLabel
					-- @leb-regression-guard:config-highlight-persistent
					-- Phase 7 (2026-05-30): highlight persists even when the
					-- config is already enabled. Previously gated on
					-- `and not isSuggestActive()`, so checking the box made the
					-- orange vanish — users read the orange as a transient
					-- "enable me" prompt that disappeared, losing the
					-- build-relevance signal. Now the orange means "this config
					-- is relevant to your build" and stays on regardless of the
					-- on/off state (user-requested 2026-05-30).
					if detectGrantedBuffs()[buffName] then
						return "^xFFAA00" .. StripEscapes(label)
					end
					return label
				end
				-- @leb-regression-guard:config-highlight-source-attribution
				-- @leb-regression-guard:config-highlight-multi-source
				-- Phase 3: when detectGrantedBuffs returned an attribution
				-- table (Pass 1/2/3 all do as of Phase 3), append a
				-- "Source: <kind> 'X' - '<line>'" trailer (ASCII hyphen — LEB
				-- tooltip font has no U+2014 glyph) so the user can see WHICH
				-- passive node / skill / item triggered the highlight.
				-- Phase 4 multi-source: when `attrib.sources` has > 1 entry,
				-- render a multi-line "Sources:" trailer with one line per
				-- contributor (e.g. two passive nodes + an item all granting
				-- Frenzy). Truthy check is preserved (table is truthy).
				-- @leb-regression-guard:config-highlight-persistent
				-- Phase 7: tooltip shows the source attribution whenever the
				-- buff is detected (regardless of on/off), since the highlight
				-- now persists. The "Consider enabling this option." call-to-
				-- action is appended only while the config is still OFF.
				t_insert(tooltipFuncs, function()
					local attrib = detectGrantedBuffs()[buffName]
					if attrib then
						local trailer = ""
						if type(attrib) == "table" and attrib.sources and #attrib.sources >= 2 then
							trailer = "\n^xFFAA00Sources:"
							for _, s in ipairs(attrib.sources) do
								trailer = trailer .. "\n^xFFAA00  - " .. s.source
								if s.line and s.line ~= "" then
									trailer = trailer .. ": '" .. s.line .. "'"
								end
							end
						elseif type(attrib) == "table" and attrib.source then
							trailer = "\n^xFFAA00Source: " .. attrib.source
							if attrib.line and attrib.line ~= "" then
								trailer = trailer .. " - '" .. attrib.line .. "'"
							end
						end
						local cta = isSuggestActive() and "" or " Consider enabling this option."
						return "^xFFAA00Your passive/skill tree can grant " .. buffName .. "." .. cta .. trailer
					end
				end)
			end

			-- @leb-regression-guard:config-highlight-suggest-pattern
			-- Sibling of the suggestBuff block above. Activates the same
			-- orange ^xFFAA00 label when the allocated tree text contains any
			-- pattern declared on the ConfigOptions entry. Read-only: this
			-- block never mutates self.input[varData.var]; the user always
			-- decides whether to toggle the config on.
			if varData.suggestPattern then
				local innerPatternLabel = labelControl.label
				local pattern = varData.suggestPattern
				local function isPatternSuggestActive()
					if varData.type == "check" then
						return self.input[varData.var]
					end
					return (self.input[varData.var] or 0) > 0
				end
				labelControl.label = function()
					local label = type(innerPatternLabel) == "function" and innerPatternLabel() or innerPatternLabel
					-- @leb-regression-guard:config-highlight-persistent
					-- Phase 7 (2026-05-30): persists when enabled (see the
					-- suggestBuff label note above).
					if detectMatchingPattern(pattern) then
						return "^xFFAA00" .. StripEscapes(label)
					end
					return label
				end
				-- @leb-regression-guard:config-highlight-source-attribution
				-- @leb-regression-guard:config-highlight-multi-source
				-- Phase 3: detectMatchingPattern now returns nil or
				-- `{ source, line, sources }` instead of a bare bool. The
				-- truthy check stays valid (table is truthy in Lua); the new
				-- attribution data populates the tooltip's Source trailer.
				-- Phase 4 multi-source: when the corpus had > 1 matching
				-- entry, render "Sources:" multi-line so the user sees every
				-- node / item that contributed.
				-- @leb-regression-guard:config-highlight-tooltip-maxwidth
				-- Phase 6 (2026-05-29): the message used to enumerate EVERY
				-- declared suggestPattern (`'a' / 'b' / 'c' / ...`) inline,
				-- producing one very long line that ran off-screen (e.g. the
				-- 7-phrase conditionEnemyLowLife entry). Now that Phase 3/4
				-- source attribution prints the ACTUAL matched line in the
				-- trailer, enumerating all declared patterns is redundant
				-- noise — dropped. The concise lead-in plus the wrapped
				-- (maxWidth) trailer is both shorter and more informative.
				-- @leb-regression-guard:config-highlight-persistent
				-- Phase 7: source attribution shown whenever matched (the
				-- highlight persists); the "Consider enabling" CTA is appended
				-- only while the config is still OFF.
				t_insert(tooltipFuncs, function()
					local attrib = detectMatchingPattern(pattern)
					if attrib then
						local trailer = ""
						if type(attrib) == "table" and attrib.sources and #attrib.sources >= 2 then
							trailer = "\n^xFFAA00Sources:"
							for _, s in ipairs(attrib.sources) do
								trailer = trailer .. "\n^xFFAA00  - " .. s.source
								if s.line and s.line ~= "" then
									trailer = trailer .. ": '" .. s.line .. "'"
								end
							end
						elseif type(attrib) == "table" and attrib.source then
							trailer = "\n^xFFAA00Source: " .. attrib.source
							if attrib.line and attrib.line ~= "" then
								trailer = trailer .. " - '" .. attrib.line .. "'"
							end
						end
						local cta = isPatternSuggestActive() and "" or " Consider enabling this option if your build actually relies on it."
						return "^xFFAA00Your build references this state." .. cta .. trailer
					end
				end)
			end

			-- @leb-regression-guard:config-highlight-moddb-signal
			-- D (2026-05-30): the modDB-signal highlight. A config may declare
			-- `suggestCond` / `suggestEnemyCond` / `suggestMult` — the parsed-
			-- modDB relevance key(s). Unlike suggestBuff / suggestPattern
			-- (which scan raw build TEXT and can false-positive on flavour
			-- wording), this fires on mainEnv.conditionsUsed /
			-- enemyConditionsUsed / multipliersUsed: the build's modifiers
			-- MECHANICALLY reference that condition / multiplier (a mod was
			-- actually parsed that scales with it). This is the precise signal
			-- PoB uses for config visibility; here it drives the orange
			-- highlight too, complementing the text signals (union: text OR
			-- modDB). The tooltip reports only the COUNT of contributing
			-- modifiers — NOT mod.source, which is a raw internal string gated
			-- behind devModeAlt elsewhere — so no internal info leaks
			-- (cf. config-tooltip-no-internal-info). Persistent like Phase 7.
			-- Keys must be real mod-tag vars (verified against ModParser, e.g.
			-- "Cursed" / "Haste" / "Frenzy"); add more incrementally during
			-- in-game verification. Spec: spec/System/TestConfigHighlightModDBSignal_spec.lua.
			if varData.suggestCond or varData.suggestEnemyCond or varData.suggestMult then
				local innerModDBLabel = labelControl.label
				local function isModDBSuggestActive()
					if varData.type == "check" then
						return self.input[varData.var]
					end
					return (self.input[varData.var] or 0) > 0
				end
				local function countModDBUses()
					local mainEnv = self.build.calcsTab and self.build.calcsTab.mainEnv
					if not mainEnv then return 0 end
					local total = 0
					local function tally(tbl, keys)
						if not keys or not tbl then return end
						local list = type(keys) == "table" and keys or { keys }
						for _, k in ipairs(list) do
							local mods = tbl[k]
							if mods then total = total + #mods end
						end
					end
					tally(mainEnv.conditionsUsed, varData.suggestCond)
					tally(mainEnv.enemyConditionsUsed, varData.suggestEnemyCond)
					tally(mainEnv.multipliersUsed, varData.suggestMult)
					return total
				end
				labelControl.label = function()
					local label = type(innerModDBLabel) == "function" and innerModDBLabel() or innerModDBLabel
					if countModDBUses() > 0 then
						return "^xFFAA00" .. StripEscapes(label)
					end
					return label
				end
				t_insert(tooltipFuncs, function()
					local n = countModDBUses()
					if n > 0 then
						local cta = isModDBSuggestActive() and "" or " Consider enabling this option if your build actually relies on that state."
						local plural = (n == 1) and "modifier" or "modifiers"
						return "^xFFAA00Your build has " .. n .. " " .. plural .. " that scale with this state." .. cta
					end
				end)
			end

			t_insert(self.controls, control)
			t_insert(lastSection.varControlList, control)
		end
	end
	self.controls.scrollBar = new("ScrollBarControl", {"TOPRIGHT",self,"TOPRIGHT"}, 0, 0, 18, 0, 50, "VERTICAL", true)

	-- blessingControls kept as empty table for legacy references
	self.blessingControls = {}
	self.controls.blessingAnchor = new("Control", {"TOPLEFT", self.controls.sectionAnchor, "TOPLEFT"}, 10, 0, 0, 0)
	self.controls.blessingPanelEnd = new("Control", {"TOPLEFT", self.controls.blessingAnchor, "TOPLEFT"}, 0, 0, 0, 0)
	t_insert(self.controls, self.controls.blessingPanelEnd)
end)

local function loadInputPlaceholderChild(self, node, targetInput, targetPlaceholder, fileName)
	if node.elem == "Input" then
		if not node.attrib.name then
			launch:ShowErrMsg("^1Error parsing '%s': 'Input' element missing name attribute", fileName)
			return true
		end
		if node.attrib.number then
			targetInput[node.attrib.name] = tonumber(node.attrib.number)
		elseif node.attrib.string then
			if node.attrib.name == "enemyIsBoss" then
				targetInput[node.attrib.name] = node.attrib.string:lower():gsub("(%l)(%w*)", function(a,b) return s_upper(a)..b end)
				:gsub("Uber Atziri", "Boss"):gsub("Shaper", "Pinnacle"):gsub("Sirus", "Pinnacle")
			elseif node.attrib.name == "presetBossSkills" then
				targetInput[node.attrib.name] = node.attrib.string:gsub("^Uber ", "")
			else
				targetInput[node.attrib.name] = node.attrib.string
			end
		elseif node.attrib.boolean then
			targetInput[node.attrib.name] = node.attrib.boolean == "true"
		else
			launch:ShowErrMsg("^1Error parsing '%s': 'Input' element missing number, string or boolean attribute", fileName)
			return true
		end
	elseif node.elem == "Placeholder" then
		if not node.attrib.name then
			launch:ShowErrMsg("^1Error parsing '%s': 'Placeholder' element missing name attribute", fileName)
			return true
		end
		if node.attrib.number then
			targetPlaceholder[node.attrib.name] = tonumber(node.attrib.number)
		elseif node.attrib.string then
			-- Historic LEB/PoB bug: string Placeholder values were written into input.
			-- Preserve to keep old saves loading the same way.
			targetInput[node.attrib.name] = node.attrib.string
		else
			launch:ShowErrMsg("^1Error parsing '%s': 'Placeholder' element missing number", fileName)
			return true
		end
	end
end

function ConfigTabClass:Load(xml, fileName)
	-- Detect format: if any child is <ConfigSet>, load as multi-set; otherwise treat
	-- the whole node as a single legacy set written directly into set 1.
	local hasConfigSets = false
	for _, node in ipairs(xml) do
		if type(node) == "table" and node.elem == "ConfigSet" then
			hasConfigSets = true
			break
		end
	end

	-- Reset to a clean single-set state so the loaded data fully replaces it.
	self.configSets = { }
	self.configSetOrderList = { }
	self.activeConfigSetId = 1
	self:NewConfigSet(1, "Default")

	if hasConfigSets then
		for index, node in ipairs(xml) do
			if type(node) == "table" and node.elem == "ConfigSet" then
				local id = tonumber(node.attrib.id) or index
				if not self.configSets[id] then
					self:NewConfigSet(id, node.attrib.title or "Default")
				else
					self.configSets[id].title = node.attrib.title or self.configSets[id].title
				end
				self.configSetOrderList[#self.configSetOrderList + 1] = id
				for _, child in ipairs(node) do
					if type(child) == "table" then
						local err = loadInputPlaceholderChild(self, child, self.configSets[id].input, self.configSets[id].placeholder, fileName)
						if err then return true end
					end
				end
			end
		end
		if #self.configSetOrderList == 0 then
			self.configSetOrderList[1] = 1
		end
		self:SetActiveConfigSet(tonumber(xml.attrib and xml.attrib.activeConfigSet) or self.configSetOrderList[1], true)
	else
		self.configSetOrderList[1] = 1
		for _, node in ipairs(xml) do
			if type(node) == "table" then
				local err = loadInputPlaceholderChild(self, node, self.configSets[1].input, self.configSets[1].placeholder, fileName)
				if err then return true end
			end
		end
		self:SetActiveConfigSet(1, true)
	end

	self:BuildModList()
	self:UpdateControls()
	self:ResetUndo()
end

function ConfigTabClass:GetDefaultState(var, varType)
	if self.placeholder[var] ~= nil then
		return self.placeholder[var]
	end

	if self.defaultState[var] ~= nil then
		return self.defaultState[var]
	end

	if varType == "number" then
		return 0
	elseif varType == "boolean" then
		return false
	elseif varType == "string" then
		return ""
	else
		return nil
	end
end

local function writeInputPlaceholder(xml, configSet, getDefault)
	for k, v in pairsSortByKey(configSet.input) do
		if v ~= getDefault(k, type(v), configSet) then
			local child = { elem = "Input", attrib = { name = k } }
			if type(v) == "number" then
				child.attrib.number = tostring(v)
			elseif type(v) == "boolean" then
				child.attrib.boolean = tostring(v)
			else
				child.attrib.string = tostring(v)
			end
			t_insert(xml, child)
		end
	end
	for k, v in pairsSortByKey(configSet.placeholder) do
		local child = { elem = "Placeholder", attrib = { name = k } }
		if type(v) == "number" then
			child.attrib.number = tostring(v)
		else
			child.attrib.string = tostring(v)
		end
		t_insert(xml, child)
	end
end

function ConfigTabClass:Save(xml)
	local function getDefault(var, varType, configSet)
		-- Mirror GetDefaultState but against a specific set's placeholder table.
		if configSet.placeholder[var] ~= nil then
			return configSet.placeholder[var]
		end
		if self.defaultState[var] ~= nil then
			return self.defaultState[var]
		end
		if varType == "number" then return 0 end
		if varType == "boolean" then return false end
		if varType == "string" then return "" end
		return nil
	end

	-- Single-set with default title and id 1: write legacy format so older LEB
	-- versions can still round-trip. Otherwise emit the multi-set format.
	local onlyId = self.configSetOrderList[1]
	local onlySet = self.configSets[onlyId]
	if #self.configSetOrderList == 1 and onlySet and (onlySet.title == "Default" or not onlySet.title) and onlyId == 1 then
		writeInputPlaceholder(xml, onlySet, getDefault)
		return
	end

	xml.attrib = xml.attrib or {}
	xml.attrib.activeConfigSet = tostring(self.activeConfigSetId)
	for _, configSetId in ipairs(self.configSetOrderList) do
		local configSet = self.configSets[configSetId]
		if configSet then
			local child = { elem = "ConfigSet", attrib = { id = tostring(configSetId), title = configSet.title or "Default" } }
			writeInputPlaceholder(child, configSet, getDefault)
			t_insert(xml, child)
		end
	end
end

function ConfigTabClass:NewConfigSet(configSetId, title)
	if not configSetId then
		configSetId = 1
		while self.configSets[configSetId] do
			configSetId = configSetId + 1
		end
	end
	local configSet = { id = configSetId, title = title or "Default", input = { }, placeholder = { } }
	-- Seed default placeholders/inputs so calc code (e.g. enemyLevel) always has values
	-- even before the user touches a control. The constructor's varControls loop only
	-- runs once, so a Load() that replaces configSets would otherwise leave fresh sets bare.
	for _, varData in ipairs(varList) do
		if varData.var then
			if varData.defaultPlaceholderState ~= nil then
				configSet.placeholder[varData.var] = varData.defaultPlaceholderState
			end
			if varData.defaultState ~= nil then
				configSet.input[varData.var] = varData.defaultState
			elseif varData.defaultIndex and varData.list then
				configSet.input[varData.var] = varData.list[varData.defaultIndex].val
			end
		end
	end
	self.configSets[configSetId] = configSet
	return configSet
end

function ConfigTabClass:SetActiveConfigSet(configSetId, init)
	if not self.configSets[configSetId] then
		configSetId = self.configSetOrderList[1] or 1
		if not self.configSets[configSetId] then
			self:NewConfigSet(configSetId, "Default")
		end
	end
	self.activeConfigSetId = configSetId
	-- Re-point the alias tables. External code keeps using self.input / self.placeholder.
	self.input = self.configSets[configSetId].input
	self.placeholder = self.configSets[configSetId].placeholder
	if not init then
		self:BuildModList()
		self:UpdateControls()
		self:ResetUndo()
		self.build.buildFlag = true
	end
end

function ConfigTabClass:UpdateControls()
	for var, control in pairs(self.varControls) do
		if control._className == "EditControl" then
			control:SetText(tostring(self.input[var] or ""))
			if self.placeholder[var] then
				control:SetPlaceholder(tostring(self.placeholder[var]))
			end
		elseif control._className == "CheckBoxControl" then
			control.state = self.input[var]
		elseif control._className == "DropDownControl" then
			control:SelByValue(self.input[var], "val")
		end
	end
end

-- @leb-regression-guard:config-sets-ui
-- Opens the manage-config-sets popup containing the ConfigSetListControl
-- (New / Copy / Rename / Delete / reorder) plus a Done button. The control
-- operates directly on this ConfigTab's config-set backend.
function ConfigTabClass:OpenConfigSetManagePopup()
	main:OpenPopup(370, 290, "Manage Config Sets", {
		new("ConfigSetListControl", nil, 0, 50, 350, 200, self),
		new("ButtonControl", nil, 0, 260, 90, 20, "Done", function()
			main:ClosePopup()
		end),
	})
end

function ConfigTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height

	for _, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then	
			if event.key == "z" and IsKeyDown("CTRL") then
				self:Undo()
				self.build.buildFlag = true
			elseif event.key == "y" and IsKeyDown("CTRL") then
				self:Redo()
				self.build.buildFlag = true
			elseif event.key == "f" and IsKeyDown("CTRL") then
				self:SelectControl(self.controls.search)
			end
		end
	end

	self:ProcessControlsInput(inputEvents, viewPort)
	for _, event in ipairs(inputEvents) do
		if event.type == "KeyUp" then
			if self.controls.scrollBar:IsScrollDownKey(event.key) then
				self.controls.scrollBar:Scroll(1)
			elseif self.controls.scrollBar:IsScrollUpKey(event.key) then
				self.controls.scrollBar:Scroll(-1)
			end
		end
	end

	local maxCol = m_floor((viewPort.width - 10) / 370)
	local maxColY = 0
	local colY = { 0 }
	for _, section in ipairs(self.sectionList) do
		local y = 14
		section.shown = true
		local doShow = false
		for _, varControl in ipairs(section.varControlList) do
			if varControl:IsShown() then
				doShow = true
				local width, height = varControl:GetSize()
				-- Grow the row for wrapped multi-line labels so they don't
				-- overlap the next control (labelLineCount set at build time).
				height = m_max(height, 16, (varControl.labelLineCount or 1) * CONFIG_LABEL_LINE_H)
				varControl.y = y + 2
				y = y + height + 4
			end
		end
		section.shown = doShow
		if doShow then
			local width, height = section:GetSize()
			local col
			if section.col and (colY[section.col] or 0) + height + 28 <= viewPort.height and 10 + section.col * 370 <= viewPort.width then
				col = section.col
			else
				col = 1
				for c = 2, maxCol do
					colY[c] = colY[c] or 0
					if colY[c] < colY[col] then
						col = c
					end
				end
			end
			colY[col] = colY[col] or 0
			section.x = 10 + (col - 1) * 370
			section.y = colY[col] + 18
			colY[col] = colY[col] + height + 18
			maxColY = m_max(maxColY, colY[col])
		end
	end

	-- Position the blessing panel below all config sections
	self.controls.blessingAnchor.y = maxColY + 28

	-- @leb-regression-guard:config-sets-ui
	-- Populate the config-set selector dropdown each frame: list titles in
	-- configSetOrderList order, and mark the active set's index as selected.
	local newSetList = { }
	for index, configSetId in ipairs(self.configSetOrderList) do
		local configSet = self.configSets[configSetId]
		t_insert(newSetList, (configSet and configSet.title) or "Default")
		if configSetId == self.activeConfigSetId then
			self.controls.setSelect.selIndex = index
		end
	end
	self.controls.setSelect:SetList(newSetList)

	-- Set anchor so GetPos() resolves correctly for content height calculation
	self.controls.sectionAnchor.y = 20 - self.controls.scrollBar.offset

	local blessEndY = select(2, self.controls.blessingPanelEnd:GetPos())
	local scrollContent = blessEndY - viewPort.y + self.controls.scrollBar.offset + 30

	self.controls.scrollBar.height = viewPort.height
	self.controls.scrollBar:SetContentDimension(scrollContent, viewPort.height)
	self.controls.sectionAnchor.y = 20 - self.controls.scrollBar.offset

	main:DrawBackground(viewPort)

	self:DrawControls(viewPort)
end

function ConfigTabClass:UpdateLevel()
	-- Validation provenance is retained in maintainer notes.
	local input = self.input
	if input.enemyLevel and input.enemyLevel > 0 then
		self.enemyLevel = input.enemyLevel
	elseif self.build and self.build.characterLevel then
		self.enemyLevel = self.build.characterLevel
	else
		self.enemyLevel = 100
	end
	self.enemyLevel = m_max(m_min(self.enemyLevel, 100), 1)
end

function ConfigTabClass:BuildModList()
	self.detectedBuffs = nil
	-- Phase 4: treeId→skillName lookup invalidates with the build state too.
	self.treeIdToSkillName = nil
	-- @leb-regression-guard:config-highlight-cache-invalidation
	-- Phase 7 (2026-05-30): the suggestPattern corpus cache MUST also be
	-- invalidated here. It was introduced (Phase 1/2) with a lazy
	-- `if self.allocNodeTextCorpus then return it` guard but was NEVER
	-- reset, so it froze to the FIRST build's passive-tree + item text.
	-- Re-importing a different build into the same file then left every
	-- suggestPattern highlight (Cursed / Low Life / Ward / Overload) stuck
	-- on the previous build's relevance (user-reported 2026-05-30).
	-- detectGrantedBuffs (suggestBuff) was already cleared above and so
	-- refreshed correctly; only the corpus leaked. BuildModList is the
	-- single rebuild chokepoint (called on every import / config change /
	-- skill or tree edit — see Build.lua), so clearing it here makes the
	-- corpus rebuild from the current build each cycle, exactly like
	-- detectedBuffs. Spec: spec/System/TestConfigHighlightCacheInvalidation_spec.lua.
	self.allocNodeTextCorpus = nil
	local modList = new("ModList")
	self.modList = modList
	local enemyModList = new("ModList")
	self.enemyModList = enemyModList
	local input = self.input
	local placeholder = self.placeholder
	self:UpdateLevel() -- enemy level handled here because it's needed to correctly set boss stats
	for _, varData in ipairs(varList) do
		if varData.apply then
			if varData.type == "check" then
				if input[varData.var] then
					varData.apply(true, modList, enemyModList, self.build)
				end
			elseif varData.type == "count" or varData.type == "integer" or varData.type == "countAllowZero" or varData.type == "float" then
				if input[varData.var] and (input[varData.var] ~= 0 or varData.type == "countAllowZero") then
					varData.apply(input[varData.var], modList, enemyModList, self.build)
				elseif placeholder[varData.var] and (placeholder[varData.var] ~= 0 or varData.type == "countAllowZero") then
					varData.apply(placeholder[varData.var], modList, enemyModList, self.build)
				end
			elseif varData.type == "list" then
				if input[varData.var] then
					varData.apply(input[varData.var], modList, enemyModList, self.build)
				end
			elseif varData.type == "text" then
				if input[varData.var] then
					varData.apply(input[varData.var], modList, enemyModList, self.build)
				end
			end
		end
	end
end

function ConfigTabClass:ImportCalcSettings()
	local input = self.input
	local calcsInput = self.build.calcsTab.input
	local function import(old, new)
		input[new] = calcsInput[old]
		calcsInput[old] = nil
	end
	import("Cond_LowLife", "conditionLowLife")
	import("Cond_FullLife", "conditionFullLife")
	import("Cond_LowMana", "conditionLowMana")
	import("Cond_FullMana", "conditionFullMana")
	import("buff_power", "usePowerCharges")
	import("buff_frenzy", "useFrenzyCharges")
	import("buff_endurance", "useEnduranceCharges")
	import("CondBuff_Onslaught", "buffOnslaught")
	import("CondBuff_Phasing", "buffPhasing")
	import("CondBuff_Fortify", "buffFortify")
	import("CondBuff_UsingFlask", "conditionUsingFlask")
	import("buff_pendulum", "usePendulum")
	import("CondEff_EnemyCursed", "conditionEnemyCursed")
	import("CondEff_EnemyBleeding", "conditionEnemyBleeding")
	import("CondEff_EnemyPoisoned", "conditionEnemyPoisoned")
	import("CondEff_EnemyBurning", "conditionEnemyBurning")
	import("CondEff_EnemyIgnited", "conditionEnemyIgnited")
	import("CondEff_EnemyChilled", "conditionEnemyChilled")
	import("CondEff_EnemyFrozen", "conditionEnemyFrozen")
	import("CondEff_EnemyShocked", "conditionEnemyShocked")
	import("effective_physicalRed", "enemyPhysicalReduction")
	import("effective_fireResist", "enemyFireResist")
	import("effective_coldResist", "enemyColdResist")
	import("effective_lightningResist", "enemyLightningResist")
	import("effective_chaosResist", "enemyChaosResist")
	import("effective_enemyIsBoss", "enemyIsBoss")
	self:BuildModList()
	self:UpdateControls()
end

function ConfigTabClass:CreateUndoState()
	return copyTable(self.input)
end

function ConfigTabClass:RestoreUndoState(state)
	wipeTable(self.input)
	for k, v in pairs(state) do
		self.input[k] = v
	end
	self:UpdateControls()
	self:BuildModList()
end
