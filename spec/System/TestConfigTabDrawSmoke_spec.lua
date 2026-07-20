-- @leb-regression-guard: config-label-fit
-- Smoke test: the Config tab must actually RENDER without erroring. The
-- label-wrapping fix sizes rows in TWO places -- the section `height` closure
-- (constructor scope) AND the per-frame layout loop inside ConfigTabClass:Draw
-- (a separate method). Both reference the wrapping constants; if those live in
-- constructor scope they are nil inside Draw and every frame throws
-- (nil arithmetic), giving a black screen. Unit tests on the controls never
-- call Draw, so they miss this. This test drives Draw end-to-end.

describe("ConfigTabDrawSmoke", function()
	before_each(function()
		newBuild()
	end)

	it("renders the Config tab (Draw) without erroring, with Show All on", function()
		local cfg = build.configTab
		-- Show All Configurations forces every option (incl. the longest,
		-- wrap-triggering labels) to be shown, so the layout loop runs over them.
		cfg.toggleConfigs = true
		local viewPort = { x = 0, y = 0, width = 1920, height = 1080 }
		assert.has_no.errors(function()
			cfg:Draw(viewPort, {})
		end)
	end)

	it("computes section heights without erroring", function()
		local cfg = build.configTab
		cfg.toggleConfigs = true
		assert.has_no.errors(function()
			for _, section in ipairs(cfg.sectionList) do
				section:GetProperty("height")
			end
		end)
	end)
end)
