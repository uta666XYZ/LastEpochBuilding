-- @leb-regression-guard: notes-preview-scroll-covers-render
-- The Notes preview scrollbar extent must cover the height the renderer actually
-- draws, not just the cached measure(). measure() is cached and can lag the live
-- render (async image growth, plus a few px of measure/render drift on identical
-- content), so trusting the shorter measure left the bottom section (References)
-- unreachable until a reload. DrawPreview uses max(contentH, lastRenderedH).
--
-- See REGRESSION_GUARDS.md "notes-preview-scroll-covers-render".

describe("NotesPreviewScrollExtent", function()
	local MarkdownRender = LoadModule("Modules/MarkdownRender")

	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a")
		f:close()
		return s
	end

	-- ===== Behavioral: render() reports a real, cumulative content height =====
	describe("MarkdownRender.render height (behavior)", function()
		it("returns a positive numeric total height", function()
			local nodes = MarkdownRender.parse("# H\n\npara\n\n## Tail\n- item")
			local h = MarkdownRender.render(nodes, 0, 0, 400, 0, 1.0, 0)
			assert.is_true(type(h) == "number", "render must return a numeric height")
			assert.is_true(h > 0, "render height must be positive for non-empty content")
		end)

		it("grows with more content (height is cumulative)", function()
			local short = MarkdownRender.render(MarkdownRender.parse("# H\n\npara"), 0, 0, 400, 0, 1.0, 0)
			local long = MarkdownRender.render(
				MarkdownRender.parse("# H\n\npara\n\n```\na\nb\nc\n```\n\n## Tail\n- x\n- y"), 0, 0, 400, 0, 1.0, 0)
			assert.is_true(long > short, "adding sections must increase the rendered height")
		end)
	end)

	-- ===== Structural: DrawPreview drives the scrollbar with max(measure,render) =====
	describe("DrawPreview scroll extent (source)", function()
		local src = readFile("Classes/NotesTab.lua")

		it("has NotesTab source available", function()
			assert.is_not_nil(src, "src/Classes/NotesTab.lua must be readable")
		end)

		it("captures the renderer's actual height", function()
			assert.is_not_nil(src:match("self%.lastPreviewRenderedH%s*=%s*renderedH"),
				"DrawPreview must store the renderer's returned height")
		end)

		it("uses the larger of measure and rendered height for the extent", function()
			assert.is_not_nil(src:match("math%.max%(contentH,%s*self%.lastPreviewRenderedH"),
				"scroll extent must be max(contentH, lastPreviewRenderedH)")
			assert.is_not_nil(src:match("previewScrollBar:SetContentDimension%(scrollH"),
				"the vertical scrollbar must be sized with scrollH, not raw contentH")
		end)

		it("drops the stale rendered height when the content changes", function()
			assert.is_not_nil(src:match("self%.lastPreviewRenderedH%s*=%s*nil"),
				"a content/scale change must reset lastPreviewRenderedH so a taller old doc can't over-extend a shorter new one")
		end)
	end)
end)
