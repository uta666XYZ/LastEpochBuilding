-- @leb-regression-guard:anurok-damage-per-character-level
-- Locks the Summon Anurok skill's intrinsic damage scaling = "6% increased Minion
-- Damage per (character) level" (= 600% at character level 100).
--
-- Ground truth (in-game tooltip, authority, 2026-06-30): the Summon Anurok skill
-- ("Summons Anuroks to fill your unused companion slots"; the Primal Anurok "does
-- NOT count as a companion") scales its damage PER CHARACTER LEVEL (6%/level), NOT
-- per Strength. Its per-Strength grant is Physical PENETRATION; per-Att = Crit
-- Chance; per-Dex = Crit Multiplier (all already in skills.json). The companions
-- (Wolf/Bear/Storm Crow) instead carry "4% increased Minion Damage per player
-- Strength" on their OWN summon skills (correctly minion-scoped, unchanged).
--
-- Why this replaced the GlobalMinionDamageScaling broadcast (<see git log>, reverted):
-- the auto-summoned Anurok was -44% under because LEB had NO damage scaling for it
-- (only Pen/Crit). The broadcast wrongly gave it the COMPANIONS' per-Str (which
-- only COINCIDENTALLY matched blank Deluyi, where 4*Str~=600~=per-char-level, and
-- OVER-shot spec'd ToBee by +8.6%). Engine MinionStatDumper cross-check
-- (minion_runtime_stats_20260630_141431, ToBee_LEB): Anurok generic Damage INC 951
-- = ~351 shared global item/tree INC + 600 (per char level); Wolf 1139 = 351 + 788
-- (its own per-Str). With this fix the Anurok lands -3.2% (Deluyi 14373 vs 14845)
-- / -3.9% (ToBee 10639 vs 11075) -- IN-LINE with the companions' shared ~-4% state
-- residual (monster MORE 6.20 vs engine 6.448), no longer an Anurok-specific gap.
-- See memory project_anurok_minion_damage_gap (2026-06-30) and REGRESSION_GUARDS.md.

describe("Anurok damage per character level #minions", function()
    local PER_LEVEL = "6% increased Minion Damage per level"

    -- Raw skills.json text span for the Summon Anurok skill (cwd is src/ under .busted).
    local function anurokSkillBlock()
        local f = assert(io.open("Data/skills.json", "r"))
        local body = f:read("*a"); f:close()
        local keyPos = body:find('"Summon AncientOasis01 Primordial Minion"', 1, true)
        assert(keyPos, "Summon Anurok skill key must exist in skills.json")
        -- the block runs up to its minionList: PrimalAnurok marker
        local endPos = body:find("PrimalAnurok", keyPos, true) or (keyPos + 4000)
        return body:sub(keyPos, endPos)
    end

    it("skills.json Summon Anurok carries the per-level Increased Damage baseMod", function()
        local block = anurokSkillBlock()
        assert.is_truthy(block:find(PER_LEVEL, 1, true),
            "Summon Anurok baseMods must include: " .. PER_LEVEL)
    end)

    it("does NOT scale Anurok damage per Strength (per-Str is Physical Penetration only)", function()
        local block = anurokSkillBlock()
        assert.is_falsy(block:lower():find("increased minion damage per player strength", 1, true),
            "Anurok must NOT carry a per-Strength Increased Damage grant (that is companion-only)")
        -- sanity: it DOES keep the per-Str Physical Penetration
        assert.is_truthy(block:find("Minion Physical Penetration per player Strength", 1, true),
            "Anurok must keep its per-Strength Physical Penetration grant")
    end)

    it("parses to a global MinionModifier wrapping Damage INC tagged Multiplier:Level", function()
        local mods = modLib.parseMod(PER_LEVEL)
        assert.is_not_nil(mods)
        assert.are.equals("MinionModifier", mods[1].name)
        local inner = mods[1].value and mods[1].value.mod
        assert.is_not_nil(inner, "MinionModifier must wrap an inner mod")
        assert.are.equals("Damage", inner.name)
        assert.are.equals("INC", inner.type)
        assert.are.equals(6, inner.value)
        local hasLevel = false
        for _, t in ipairs(inner) do
            if t.type == "Multiplier" and t.var == "Level" then hasLevel = true end
        end
        assert.is_true(hasLevel, "inner Damage INC must carry Multiplier:Level (per character level)")
    end)
end)
