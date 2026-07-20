-- @leb-regression-guard: passive-tree-progress-indicator-layer
-- Drives TreeTab:Draw and records the draw layer of every `passive-slider-bar`
-- image. The vertical progress indicator must be drawn BEHIND the tree (main
-- layer 0, sublayer below the connectors at 20), while the on-bar progress
-- marker diamond must be drawn in FRONT (skill-bar main layer 1). If the fix is
-- collapsed back to a single layer the slider covers the passive nodes again.
-- Unit tests on the controls never call Draw, so only this end-to-end drive
-- observes the layering.
--
-- busted insulates each spec file, so the app modules (loaded by the headless
-- helper) read the REAL global table while a plain `DrawImage = ...` in the spec
-- only shadows it. getfenv(newBuild) is that real table -- override there so the
-- module's own draw calls route through the probe.

describe("PassiveTreeProgressIndicatorLayer", function()
	before_each(function()
		newBuild()
	end)

	it("draws the vertical indicator behind the tree and the marker on the bar", function()
		local G = getfenv(newBuild)
		local treeTab = build.treeTab
		local sliderHandle = treeTab:GetSpriteHandle("passive-slider-bar")
		assert.is_not_nil(sliderHandle)

		local origSetLayer = G.SetDrawLayer
		local origDrawImage = G.DrawImage
		local curLayer, curSub = 0, 0
		local draws = {}
		G.SetDrawLayer = function(layer, subLayer)
			if layer ~= nil then
				curLayer = layer
				-- single-arg form (subLayer omitted) resets the sublayer
				curSub = subLayer or 0
			elseif subLayer ~= nil then
				curSub = subLayer
			end
		end
		G.DrawImage = function(handle, left, top, width, height, tcLeft, tcTop, tcRight, tcBottom)
			if handle == sliderHandle then
				draws[#draws + 1] = { layer = curLayer, sub = curSub, tcBottom = tcBottom }
			end
		end

		local ok, err = pcall(function()
			treeTab:Draw({ x = 0, y = 0, width = 1920, height = 1080 }, {})
		end)

		G.SetDrawLayer = origSetLayer
		G.DrawImage = origDrawImage

		assert(ok, "treeTab:Draw errored: " .. tostring(err))
		assert.is_true(#draws > 0, "the slider asset was never drawn")

		-- Connectors draw at main layer 0 / sublayer 20 and nodes at 25; the vertical
		-- indicator must sit behind them (main layer 0, sublayer < 20).
		local behind = false
		-- The on-bar marker is the slider draw at the skill-bar layer (1) carrying the
		-- top-diamond tex slice (tcBottom ~ 0.05); the drop lines pass no tex coords
		-- (tcBottom == nil), so this distinguishes the marker from them.
		local markerOnBar = false
		for _, d in ipairs(draws) do
			if d.layer == 0 and d.sub < 20 then
				behind = true
			end
			if d.layer == 1 and d.tcBottom ~= nil and d.tcBottom < 0.5 then
				markerOnBar = true
			end
		end

		assert.is_true(behind,
			"vertical progress indicator must draw behind the tree (main layer 0, sublayer < 20)")
		assert.is_true(markerOnBar,
			"progress marker diamond must draw on the bar in front (main layer 1, top-diamond tex slice)")
	end)
end)
