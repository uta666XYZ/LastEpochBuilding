-- @leb-regression-guard:run-specs-no-vacuous-green
-- scripts/run-specs.sh must refuse the two ways this repo produces a GREEN THAT
-- TESTED NOTHING:
--   1. naming a tag-excluded spec (`run-specs.sh ../spec/System/TestBuilds_spec.lua`)
--      -- .busted excludes `builds`, so busted skips every corpus test, reports the
--      file's few untagged successes and exits 0 in ~5s;
--   2. asking for the builds tag where spec/TestBuilds/ does not exist (every
--      worktree and CI -- it is gitignored, main-repo only) -- zero builds are
--      enumerated and the suite passes vacuously (~100s instead of ~900s).
-- Both were hit for real on 2026-07-17/18 by separate sessions, and both were already
-- documented in three hand-offs first. Prose did not stop them; a fail-closed check
-- does. See REGRESSION_GUARDS.md "run-specs-no-vacuous-green".
--
-- This asserts the script's TEXT, not its behaviour: the script is bash, busted is
-- lua, and driving it for real would either take ~900s or need the corpus that is
-- absent here by definition. The behavioural proof lives in the establishing commit
-- (all four cases run by hand: refuse / refuse / allow / allow-with-corpus).

describe("RunSpecsNoVacuousGreen", function()
	local function readFile(path)
		for _, p in ipairs({ "../" .. path, path }) do
			local f = io.open(p, "r")
			if f then local s = f:read("*a"); f:close(); return s end
		end
		return nil
	end

	local script = readFile("scripts/run-specs.sh")
	local busted = readFile(".busted")

	it("reads .busted's exclude-tags in the form .busted actually writes", function()
		assert.is_not_nil(busted, ".busted must be readable")
		-- The guard greps exclude-tags out of .busted. If .busted's spelling changes,
		-- the grep yields "" and the check silently stops guarding -- so pin the shape
		-- here rather than let it fail open.
		local tags = busted:match('%["exclude%-tags"%]%s*=%s*"([^"]*)"')
		assert.is_not_nil(tags,
			'.busted must declare ["exclude-tags"] = "..." -- scripts/run-specs.sh parses '
			.. 'exactly this form to know which tags produce a vacuous green')
		assert.is_truthy(tags:find("builds", 1, true),
			"the builds tag must still be excluded by default; if that changed, the "
			.. "vacuous-green trap is gone and this guard should be re-thought, not deleted")
	end)

	it("still knows the corpus spec by its tag", function()
		local corpusSpec = readFile("spec/System/TestBuilds_spec.lua")
		assert.is_not_nil(corpusSpec, "spec/System/TestBuilds_spec.lua must be readable")
		assert.is_truthy(corpusSpec:find("#builds", 1, true),
			"TestBuilds_spec must carry the #builds tag -- run-specs.sh greps for '#<tag>' "
			.. "to detect that naming this file would test nothing")
	end)

	-- Pin the EXECUTABLE path, never the prose around it. Asserting on a phrase that
	-- also appears in a comment passes while the refusal itself is gone -- measured:
	-- deleting the corpus-absent refusal message left this spec green until these
	-- assertions were rewritten to look at the condition and the exit.
	local function codeLines()
		local out = {}
		for line in script:gmatch("[^\n]+") do
			if not line:match("^%s*#") then table.insert(out, line) end
		end
		return table.concat(out, "\n")
	end

	it("refuses a tag-excluded spec instead of reporting a fast green", function()
		assert.is_not_nil(script, "scripts/run-specs.sh must be readable")
		local code = codeLines()
		assert.is_truthy(code:find('EXCLUDE_TAGS="%$%(sed') and code:find("%.busted"),
			"run-specs.sh must read exclude-tags out of .busted (not hardcode a tag list): "
			.. "a hardcoded list drifts silently the moment .busted changes")
		assert.is_truthy(code:find("is tagged #"),
			"run-specs.sh must refuse when a named spec carries an excluded tag")
		assert.is_truthy(code:find("exit 3"),
			"the refusal must exit non-zero -- a warning that still runs is the vacuous "
			.. "green it is meant to stop")
	end)

	it("only counts a tag inside a busted block title, not any mention of it", function()
		local code = codeLines()
		assert.is_truthy(code:find("describe|it|expose", 1, true),
			"the tag scan must be anchored to describe/it/expose titles: a bare '#builds' "
			.. "match flags every file that merely MENTIONS the tag (this spec does), and "
			.. "a false refusal trains people to route around the check")
	end)

	it("refuses the builds tag where the corpus is absent", function()
		local code = codeLines()
		-- Pin the WHOLE condition. `[ ! -d "spec/TestBuilds" ]` alone also appears in
		-- the pre-existing post-run environmental note at the bottom of the script, so
		-- asserting on it passed while this refusal was disabled -- measured.
		assert.is_truthy(
			code:find('[ "$asked_for_tags" = "1" ] && [ ! -d "spec/TestBuilds" ]', 1, true),
			"run-specs.sh must refuse BEFORE running when a tag was asked for and "
			.. "spec/TestBuilds/ is absent because it is an optional local artifact, so "
			.. "the suite would enumerate zero builds and pass vacuously (~100s, not ~900s)")
	end)

	it("warns rather than failing open if it cannot parse .busted", function()
		assert.is_truthy(script:find("vacuous%-green check is NOT active"),
			"if exclude-tags cannot be parsed the script must say so loudly -- a guard "
			.. "that silently stops guarding is worse than no guard")
	end)
end)
