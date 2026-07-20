-- @leb-regression-guard:handoffs-not-in-repo
-- See REGRESSION_GUARDS.md "handoffs-not-in-repo".
-- Validation provenance is retained in maintainer notes.

describe("HandoffsNotInRepo", function()
	-- .busted sets `directory = "src"`, so specs run with src/ as the cwd (that is
	-- why its ROOT is "../spec"). Resolve the repo root rather than assuming it.
	local function openGitignore()
		for _, p in ipairs({ "../.gitignore", ".gitignore" }) do
			local f = io.open(p, "r")
			if f then return f end
		end
		return nil
	end

	local function gitignoreLines()
		local f = assert(openGitignore(), ".gitignore must be readable (looked in ../ and ./)")
		local lines = {}
		for line in f:lines() do
			-- strip CR so the spec passes under Windows checkouts (core.autocrlf)
			table.insert(lines, (line:gsub("\r$", "")))
		end
		f:close()
		return lines
	end

	it("ignores General/ so local notes cannot be committed", function()
		local found, negated = false, false
		for _, line in ipairs(gitignoreLines()) do
			if line == "/General/" or line == "General/" then
				found = true
			elseif line == "!/General/" or line == "!General/" then
				negated = true
			end
		end
		assert.is_true(found,
			".gitignore must carry a /General/ rule so local notes are not staged by `git add -A`")
		assert.is_false(negated,
			"a negation re-exposes General/; repository documentation belongs in docs/")
	end)

	it("keeps the General/ rule root-anchored", function()
		local anchored = false
		for _, line in ipairs(gitignoreLines()) do
			if line == "/General/" then
				anchored = true
			end
		end
		assert.is_true(anchored,
			"the rule must be /General/, not General/: only the repo-root directory is meant, " ..
			"and the unanchored form reads as if it also targeted the tracked " ..
			"src/Data/LEToolsImport/**/tab_gen_General___*.json files")
	end)
end)
