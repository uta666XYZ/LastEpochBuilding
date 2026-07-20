-- @leb-regression-guard: notes-codeblock-verbatim-monospace
-- Fenced code blocks in Notes render in the fixed-width CODE_FONT and their body
-- lines are captured VERBATIM -- never routed through inline markdown
-- tokenization. This is what lets template ASCII art (the Showcase "LAST EPOCH
-- BUILDING" owl banner) keep its columns aligned. Parsing code bodies through
-- tokenizeInline (which strips **bold** etc.) or drawing them in a proportional
-- font silently breaks every ASCII-art banner.
--
-- See REGRESSION_GUARDS.md "notes-codeblock-verbatim-monospace".

describe("NotesCodeBlockVerbatim", function()
	local MarkdownRender = LoadModule("Modules/MarkdownRender")

	local function readFile(path)
		local f = io.open(path, "r")
		if not f then return nil end
		local s = f:read("*a")
		f:close()
		return s
	end

	local function firstCodeNode(nodes)
		for _, n in ipairs(nodes) do
			if n.kind == "code" then return n end
		end
		return nil
	end

	-- ===== Behavioral: code bodies are verbatim, never markdown-tokenized =====
	describe("code block parsing (behavior)", function()
		it("captures body lines verbatim, keeping ** and leading spaces", function()
			local code = firstCodeNode(MarkdownRender.parse("```\n**not bold** here\n  spaced  \n```"))
			assert.is_not_nil(code, "fenced block must parse to a code node")
			assert.are.equal("**not bold** here", code.lines[1])
			assert.are.equal("  spaced  ", code.lines[2])
		end)

		it("does not tokenize links or inline code inside a code block", function()
			local code = firstCodeNode(MarkdownRender.parse("```\n[label](url) `inline`\n```"))
			assert.is_not_nil(code)
			assert.are.equal("[label](url) `inline`", code.lines[1])
		end)
	end)

	-- ===== Structural: the renderer draws code in the fixed-width font =====
	describe("renderer uses monospace CODE_FONT (source)", function()
		local src = readFile("Modules/MarkdownRender.lua")

		it("has MarkdownRender source available", function()
			assert.is_not_nil(src, "src/Modules/MarkdownRender.lua must be readable")
		end)

		it("defines CODE_FONT as the fixed-width FIXED font", function()
			assert.is_not_nil(src:match('CODE_FONT%s*=%s*"FIXED"'),
				"code blocks must render in the fixed-width FIXED font")
		end)

		it("draws code lines in CODE_FONT", function()
			assert.is_not_nil(src:match("CODE_FONT,%s*CODE_TEXT_COLOR%s*%.%.%s*codeLine"),
				"code node lines must be drawn with CODE_FONT")
		end)
	end)

	-- ===== Data: the Showcase owl banner stays well-formed ASCII art =====
	describe("Showcase template owl banner (data)", function()
		local src = readFile("Data/NotesTemplates/Showcase.md")

		-- Return the lines of the fenced code block that contains the owl banner.
		local function bannerBlock(text)
			local lines = {}
			for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
				lines[#lines + 1] = line
			end
			local inFence, block, found = false, {}, nil
			for _, l in ipairs(lines) do
				if l:match("^```") then
					if inFence then
						for _, bl in ipairs(block) do
							if bl:find("(c).-.(c)", 1, true) then found = block end
						end
						inFence, block = false, {}
					else
						inFence, block = true, {}
					end
				elseif inFence then
					block[#block + 1] = l
				end
			end
			return found
		end

		local block = bannerBlock(src)

		it("has the Showcase template", function()
			assert.is_not_nil(src, "src/Data/NotesTemplates/Showcase.md must be readable")
		end)

		it("keeps the owl banner inside a fenced code block", function()
			assert.is_not_nil(block, "owl banner must live inside a ``` code block so it renders monospace")
		end)

		it("has no ** markdown markers in the banner", function()
			for _, l in ipairs(block or {}) do
				assert.is_nil(l:find("**", 1, true),
					"banner line must not contain stray ** markers: " .. l)
			end
		end)

		it("spells LAST EPOCH BUILDING in the letter row", function()
			local letters
			for _, l in ipairs(block or {}) do
				local acc = {}
				for ch in l:gmatch("||%s*(%a)%s*||") do acc[#acc + 1] = ch end
				if #acc > 0 then letters = table.concat(acc) end
			end
			assert.are.equal("LASTEPOCHBUILDING", letters)
		end)
	end)
end)
