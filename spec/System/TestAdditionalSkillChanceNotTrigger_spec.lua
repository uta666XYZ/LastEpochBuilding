-- @leb-regression-guard:additional-skill-chance-not-trigger
-- "<N>% Additional <skill> Chance" is a PROJECTILE-QUANTITY affix (a chance to throw
-- +N extra projectiles), NOT a "chance to cast <skill>" trigger. The only such entry in
-- current game data is the Shurikens tree node "Flip of a Coin": "50% Additional Shurikens
-- Chance". Before the fix, ModParser's "N% additional" form (formList) consumed the
-- discriminating "additional", then the generic "<skill> chance" -> ChanceToTriggerOnHit
-- rule misread the remainder as a 50%-chance full-skill SELF-recast. On StarSeaVnV that
-- over-modeled a "Shurikens (from Shurikens)" Full DPS copy worth ~39k that does NOT exist
-- in-game (the real 142,136-vs-121,470 gap is unmodeled additional-projectile damage --
-- a -7% per-hit gap + a -8% single-target spread-landing gap; base projectile count is
-- datamine-blocked -- not a trigger). Fix: a specialModList interceptor (scanned before the
-- form + the trigger rule) returns {} (no mod) when the middle capture names a real
-- non-minion, non-ailment skill, and declines (nil -> generic parse) otherwise so unrelated
-- affixes and the genuine "<skill> Chance" triggers (which have no "additional") are
-- untouched. See REGRESSION_GUARDS.md "additional-skill-chance-not-trigger".

describe("Additional <skill> Chance is not a trigger (parser)", function()
	-- Bypass the ModCache so the LIVE parser logic is exercised (locks the fix even if
	-- ModCache is later regenerated), then RESTORE the original cache entry: parseMod
	-- re-caches its result, and leaving the live entry in place would shadow the baked
	-- Data/ModCache row for every later spec in this suite process (latent order
	-- dependency). The returned values are the live parse either way (copyTable'd
	-- before restoration).
	local function reparse(line)
		local saved = modLib.parseModCache[line]
		modLib.parseModCache[line] = nil
		local mods, extra = modLib.parseMod(line)
		modLib.parseModCache[line] = saved
		return mods, extra
	end

	it("'50% Additional Shurikens Chance' produces NO trigger (it is a +projectiles affix)", function()
		local mods, extra = reparse("50% Additional Shurikens Chance")
		assert.is_not_nil(mods, "interceptor must return an empty mod list, not nil")
		assert.are.equals(0, #mods, "must produce no mod, like the typo'd '+4 Additonal Shurikens'")
		assert.is_nil(extra, "no residue -- a truthy extra would set node.extra and churn the regenerated ModCache row")
	end)

	it("the '%' is optional: '50 Additional Shurikens Chance' is also blocked", function()
		local mods, extra = reparse("50 Additional Shurikens Chance")
		assert.is_not_nil(mods)
		assert.are.equals(0, #mods)
		assert.is_nil(extra)
	end)

	it("the legit '<skill> Chance' trigger (NO 'additional') still fires", function()
		local mods, extra = reparse("50% Shurikens Chance")
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		assert.is_nil(extra)
		assert.are.equals("ChanceToTriggerOnHit_Shurikens", mods[1].name)
		assert.are.equals(50, mods[1].value)
	end)

	it("other genuine '<skill> Chance' triggers are untouched", function()
		local cases = {
			{ "5% Glacier Chance",       "ChanceToTriggerOnHit_Glacier",       5 },
			{ "5% Maelstrom Chance",     "ChanceToTriggerOnHit_Maelstrom",     5 },
			{ "+34% Lightning Blast Chance", "ChanceToTriggerOnHit_LightningBlast", 34 },
			{ "+10% Multishot Chance",   "ChanceToTriggerOnHit_RogueMultishot", 10 },
		}
		for _, c in ipairs(cases) do
			local mods, extra = reparse(c[1])
			assert.is_not_nil(mods, c[1])
			assert.are.equals(1, #mods, c[1])
			assert.is_nil(extra, c[1])
			assert.are.equals(c[2], mods[1].name, c[1])
			assert.are.equals(c[3], mods[1].value, c[1])
		end
	end)

	it("the 'Chance to cast <skill> on hit' bridge is NOT shadowed for the same skill", function()
		-- The S2 on-hit bridge wording must keep producing the functional trigger for
		-- Shurikens itself (the interceptor requires the 'additional ... chance$' shape).
		local mods, extra = reparse("8% Chance to cast Shurikens on hit")
		assert.is_not_nil(mods)
		assert.are.equals(1, #mods)
		assert.is_nil(extra)
		assert.are.equals("ChanceToTriggerOnHit_Shurikens", mods[1].name)
		assert.are.equals(8, mods[1].value)
	end)

	it("the typo'd quantity form '+4 Additonal Shurikens' still parses to no mods (the analogy the guard leans on)", function()
		local mods = reparse("+4 Additonal Shurikens")
		assert.is_true(not mods or #mods == 0, "the (sic) quantity stat is structurally unmodeled")
	end)

	it("a non-skill 'additional X chance' is declined (scoped to real skills, not force-ignored)", function()
		-- "Foobar" is not a skill name -> the interceptor returns nil -> generic parse.
		-- The only invariant: it must NOT emit a ChanceToTriggerOnHit_ mod.
		local mods = reparse("50% Additional Foobar Chance")
		if mods then
			for _, m in ipairs(mods) do
				assert.is_falsy(m.name and m.name:find("ChanceToTriggerOnHit_", 1, true),
					"a non-skill must not become a trigger")
			end
		end
	end)

	it("real-data decline: '25% Additional Storm Stack Chance' parses exactly as before", function()
		-- The ONLY other game-data string of this exact form (tree_0 Gathering Storm
		-- tree node ga2st-20 "Island Cleaver"). "Storm Stack" is a buff, not a skill
		-- name, so the interceptor declines and the generic chain yields the SAME
		-- silent-residue parse that is baked in ModCache (`{{}," Storm Stack Chance "}`):
		-- no mods + that residue. Locks zero parser/ModCache drift outside the targeted
		-- Shurikens entry.
		local mods, extra = reparse("25% Additional Storm Stack Chance")
		assert.is_true(not mods or #mods == 0, "must still produce no mods")
		assert.are.equals(" Storm Stack Chance ", extra, "residue must be byte-identical to the ModCache row")
	end)
end)

describe("Additional <skill> Chance ModCache", function()
	it("the cached '50% Additional Shurikens Chance' row is a no-op (no trigger)", function()
		local f = assert(io.open("Data/ModCache.lua", "r"))
		local body = f:read("*a"); f:close()
		assert.is_truthy(body:find('c["50% Additional Shurikens Chance"]={{},nil}', 1, true),
			"the stale ChanceToTriggerOnHit_Shurikens cache row must be a no-op")
		-- Row-scoped negative check (NOT file-wide: a future legit non-'additional'
		-- Shurikens trigger affix would legitimately bake ChanceToTriggerOnHit_Shurikens
		-- under its own key).
		local rowStart = assert(body:find('c["50% Additional Shurikens Chance"]=', 1, true))
		local rowEnd = body:find("\n", rowStart, true) or #body
		local row = body:sub(rowStart, rowEnd)
		assert.is_nil(row:find("ChanceToTriggerOnHit", 1, true),
			"the trigger misparse must not be cached under the Additional key")
	end)
end)

describe("Additional <skill> Chance source invariant", function()
	it("ModParser carries the specialModList interceptor + inline guard marker", function()
		local f = assert(io.open("Modules/ModParser.lua", "r"))
		local text = f:read("*a"); f:close()
		assert.is_truthy(text:find("@leb%-regression%-guard:additional%-skill%-chance%-not%-trigger"),
			"inline regression-guard marker must be present")
		-- The full anchored pattern: dropping the trailing ' chance$' anchor would make
		-- the interceptor swallow bare quantity forms like '+4 Additional Shurikens'.
		assert.is_truthy(text:find("additional (.+) chance$", 1, true),
			"the ANCHORED specialModList interceptor pattern must be present")
	end)
end)
