-- @leb-regression-guard:minion-melee-keyword-no-bundle
-- See REGRESSION_GUARDS.md "minion-melee-keyword-no-bundle".
-- Validation provenance is retained in maintainer notes.

describe("MinionMeleeKeywordNoBundle #minions #skills", function()
    local band = bit.band
    local Melee, Throwing, Bow = 512, 1024, 2048

    local function readSource(relPath)
        local f = io.open(relPath, "r") or io.open("src/" .. relPath, "r") or io.open("../src/" .. relPath, "r")
        assert.is_not_nil(f, "must be able to open " .. relPath)
        local text = f:read("*a"); f:close()
        return text
    end

    -- 1. Skill DATA shape: a melee minion skill is Melee-typed (no Bow bit); the
    --    genuine bow minion skill is Bow-typed (no Melee bit). The Bow bit on a
    --    melee minion can therefore only ever be added at runtime (the bundle).
    describe("skill data shape (runtime data.skills)", function()
        it("PrimalWolf / PrimalBear melee skills are Melee-typed, NOT Bow", function()
            for _, id in ipairs({ "PrimalWolf 01 melee", "PrimalBear 01 melee attack" }) do
                local sk = data.skills[id]
                assert.is_table(sk, id .. " must exist in skills.json")
                assert.are_not.equal(0, band(sk.skillTypeTags, Melee), id .. " must be Melee-typed")
                assert.are.equal(0, band(sk.skillTypeTags, Bow), id .. " must NOT be Bow-typed in data")
                assert.are.equal(0, band(sk.skillTypeTags, Throwing), id .. " must NOT be Throwing-typed in data")
            end
        end)

        it("RogueBallista's BallistaBolt is genuinely Bow-typed, NOT Melee", function()
            local sk = data.skills["BallistaBolt"]
            assert.is_table(sk, "BallistaBolt must exist in skills.json")
            assert.are_not.equal(0, band(sk.skillTypeTags, Bow), "BallistaBolt must keep its Bow type")
            assert.are.equal(0, band(sk.skillTypeTags, Melee),
                "BallistaBolt is not melee, so the Melee-block fix can never touch it")
        end)

        it("RogueBallista is the only in-game-validated weapon-attack minion", function()
            assert.is_table(LE_WEAPON_ATTACK_MINIONS.RogueBallista,
                "RogueBallista must stay whitelisted so its bow scaling is preserved")
            assert.are.equal("Bow", LE_WEAPON_ATTACK_MINIONS.RogueBallista.weapon)
        end)
    end)

    -- 2. Keyword-matching SEMANTICS via the real MatchKeywordFlags: this is the
    --    mechanism the fix relies on. Proves the leak (bundle matches a Bow-only
    --    mod) and the fix (Melee-only does not), while generic Attack-scoped
    --    mods still match and a genuine Bow cfg still matches.
    describe("keyword matching semantics (MatchKeywordFlags any-of)", function()
        local bowOnlyMod   = Bow            -- "+Minion Bow Damage" affix scope
        local throwOnlyMod = Throwing       -- "+Minion Throwing Damage" affix scope
        local attackScoped = KeywordFlag.Attack  -- generic "Minion Attack Damage"

        it("the OLD bundle (Melee|Throwing|Bow) LEAKS a Bow-only / Throwing-only mod", function()
            assert.are.equal(Melee + Throwing + Bow, KeywordFlag.Attack)
            assert.is_true(MatchKeywordFlags(KeywordFlag.Attack, bowOnlyMod),
                "bundle has the Bow bit -> Bow-only mod matches (the leak)")
            assert.is_true(MatchKeywordFlags(KeywordFlag.Attack, throwOnlyMod))
        end)

        it("a Melee-ONLY minion cfg does NOT match a Bow-only / Throwing-only mod", function()
            assert.is_false(MatchKeywordFlags(KeywordFlag.Melee, bowOnlyMod),
                "fixed minion melee has no Bow bit -> Bow-only mod cannot apply")
            assert.is_false(MatchKeywordFlags(KeywordFlag.Melee, throwOnlyMod))
        end)

        it("a Melee-ONLY minion cfg STILL matches generic Attack-scoped mods", function()
            assert.is_true(MatchKeywordFlags(KeywordFlag.Melee, attackScoped),
                "Attack-scoped mod carries the Melee bit -> matches via any-of overlap")
            assert.is_true(MatchKeywordFlags(KeywordFlag.Melee, KeywordFlag.Melee))
        end)

        it("a genuine Bow minion cfg STILL matches a Bow mod (RogueBallista preserved)", function()
            local ballistaCfg = KeywordFlag.Bow
            assert.is_true(MatchKeywordFlags(ballistaCfg, bowOnlyMod),
                "BallistaBolt keeps its Bow keyword -> bow-damage scaling works")
        end)
    end)

    -- 3. Source contract: the fix is minion-scoped (keys off actor.minionData,
    --    gives Melee), the player path keeps the Attack bundle, and the genuine
    --    bow-minion weapon path is untouched.
    describe("source contract (CalcActiveSkill.lua)", function()
        local src
        setup(function() src = readSource("Modules/CalcActiveSkill.lua") end)

        it("a minion melee skill takes KeywordFlag.Melee (not the Attack bundle)", function()
            assert.is_truthy(src:find("elseif activeSkill.actor and activeSkill.actor.minionData then", 1, true),
                "the minion case must key off the actor.minionData idiom")
            assert.is_truthy(src:find("@leb-regression-guard:minion-melee-keyword-no-bundle", 1, true))
        end)

        it("the player (non-finisher) path still takes the full Attack bundle", function()
            assert.is_truthy(src:find("skillKeywordFlags = bor(skillKeywordFlags, KeywordFlag.Attack)", 1, true),
                "player melee must keep Melee|Throwing|Bow so generic Attack affixes match")
        end)

        it("the genuine bow-minion weapon path (BallistaBolt's Bow) is untouched", function()
            assert.is_truthy(src:find("band(activeSkill.weapon1Flags, ModFlag.Bow)", 1, true),
                "weapon1Attack+Bow grants Bow independently of the Melee block")
        end)
    end)
end)
