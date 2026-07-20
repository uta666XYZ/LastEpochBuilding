-- @leb-regression-guard:minionlist-resolves
-- Every `minionList` entry in skills.json must be a real key in minions.json.
-- The engine indexes minions by that exact token:
--   CalcActiveSkill.lua  minion.minionData = env.data.minions[minionType]
-- so a dangling entry yields `nil` minionData -- a SILENT failure: the summon
-- skill contributes no minion stats/damage with no error.
--
-- Caught case (2026-06-15): "SwarmOfBees" (Swarm of Bees, granted by the unique
-- Keeper's Gloves -- "10% chance to summon a swarm of bees on melee hit") had
-- minionList=["SummonedBee"], but minions.json has no "SummonedBee" key. The
-- bee minion is keyed "Bee". The "SummonedBee" token is the raw in-game PREFAB
-- name, not the LEB minions.json key. (Same trap as "SummonBee", already fixed
-- on dev by the auto-summon framework merge.)
--
-- Datamine ground truth (no fabrication, READ-ONLY):
--   * AbilityManager.abilities[63] "SwarmOfBees" / "Swarm of Bees" is a real
--     ability; its abilityPrefab is the GameObject "SummonBees".
--   * "SummonBees" carries a SummonEntityOnDeath whose ActorReference resolves
--     to an ActorData with m_Name="SummonedBee", actorName="Bee", actorType=3
--     (Heavy) -- i.e. the worker bee.
--   * datamined game source mapping[47] maps the
--     in-game prefab "SummonedBee" -> LEB minions.json key "Bee" (confidence
--     high, life 60 == minions.json "Bee".life). The cold/fire/lightning
--     variants map SummonedColdBee->ChillyBee, SummonedFireBee->FireBee,
--     SummonedLightningBee->LightningBee; the boss bee SummonedQueenBee->QueenBee.
-- So Swarm of Bees summons the same worker prefab that minions.json keys as
-- "Bee", and minionList=["Bee"] is the correct, resolving link.
--
-- KNOWN_DANGLING is a ratchet allow-list of pre-existing dangling entries that
-- have NOT yet been datamine-verified (each needs the same prefab-name ->
-- minions.json-key confirmation that SwarmOfBees got here -- do NOT guess). The
-- corpus-wide check below fails on any dangling entry NOT in this set, so a NEW
-- regression (or a re-extraction that re-introduces a raw prefab name) trips the
-- spec instead of silently dropping a minion. The set should SHRINK as entries
-- are verified and fixed; never grow it without a datamine note. (The
-- auto-summon Phase B targets Anurok / T_Rex / Tolmat were datamine-verified +
-- fixed -- minionList now PrimalAnurok / PrimalTyrannosaur / TolmatMinionDivine
-- with their primary attack skills encoded in skills.json -- so they are removed
-- from this set.)
--
-- See REGRESSION_GUARDS.md "minionlist-resolves".

describe("MinionListResolves #minionData", function()

    -- skillId -> { [danglingMinionEntry] = true }. Pre-existing, unverified.
    -- (SummonBee's SummonedBee->Bee was fixed on dev by the auto-summon merge,
    -- so it is NO LONGER in this set.)
    --
    -- The set is now EMPTY: every previously-allow-listed dangling entry has been
    -- datamine-verified and its minionList corrected to the resolving minions.json
    -- key, so the corpus-wide invariant below now enforces ALL 40 minionList
    -- entries with no exceptions.
    --   * PontifexCremate  SummonedBurningSkeleton -> BurningSkeleton  (<see git log>)
    --   * SummonIllusoryTree "Illusory Tree"        -> IllusoryTree     (<see git log>)
    --   * SummonMercenary    "Summoned Mercenary"    -> Mercenary        (<see git log>)
    -- These three are re-asserted positively in the resolution test below so a
    -- re-extraction that re-introduces the raw prefab/display name trips the spec
    -- instead of being silently re-admitted. Do NOT re-add an entry here without a
    -- datamine note (prefab-name -> minions.json-key confirmation); the set may
    -- only SHRINK.
    -- (Anurok / Giant T_Rex / Tolmat were also here; auto-summon Phase B
    --  datamine-verified + fixed their minionList -- see the Phase B test below.)
    local KNOWN_DANGLING = {}

    it("data tables are loaded", function()
        assert.is_table(data.skills, "data.skills must be loaded")
        assert.is_table(data.minions, "data.minions must be loaded")
    end)

    it("SwarmOfBees summons the worker Bee (datamine: ActorData SummonedBee -> minions.json 'Bee')", function()
        local sk = data.skills.SwarmOfBees
        assert.is_table(sk, "SwarmOfBees must exist in data.skills")
        assert.is_table(sk.minionList, "SwarmOfBees.minionList must be a table")
        assert.are.equal("Bee", sk.minionList[1],
            "SwarmOfBees must summon the 'Bee' minions.json key, not the raw prefab name")
        assert.is_table(data.minions["Bee"], "minions.json must have key 'Bee'")
    end)

    it("SummonBee resolves (auto-summon framework already fixed it on dev)", function()
        local sk = data.skills.SummonBee
        assert.is_table(sk, "SummonBee must exist in data.skills")
        assert.are.equal("Bee", sk.minionList[1],
            "SummonBee.minionList must be the resolving 'Bee' key (regression check for the auto-summon merge)")
    end)

    it("auto-summon Phase B summon skills resolve to their real minions.json keys", function()
        -- These were KNOWN_DANGLING raw prefab names until Phase B datamine-verified
        -- the prefab -> minions.json-key mapping (leb_minion_mapping_v4.json) and
        -- fixed the minionList. Each minion's primary attack skill is now encoded.
        local cases = {
            ["Summon AncientOasis01 Primordial Minion"] = { key = "PrimalAnurok",       attack = "AncientOasis01 04 TongueSlap" },
            ["Summon Giant T_Rex Minion"]               = { key = "PrimalTyrannosaur",  attack = "Giant T_Rex 01 Bite" },
            ["Summon Tolmat Minion"]                    = { key = "TolmatMinionDivine", attack = "RahyehFactionSwarmer 01 Melee" },
        }
        for skillId, c in pairs(cases) do
            local sk = data.skills[skillId]
            assert.is_table(sk, skillId .. " must exist in data.skills")
            assert.are.equal(c.key, sk.minionList[1],
                skillId .. ".minionList[1] must be the resolving minions.json key")
            assert.is_table(data.minions[c.key], "minions.json must have key " .. c.key)
            -- the encoded primary attack must exist so the summon is not 0-DPS
            assert.is_table(data.skills[c.attack],
                c.attack .. " (primary attack) must be encoded in skills.json")
        end
    end)

    it("namespace-gap summon skills resolve to their minions.json keys (were KNOWN_DANGLING)", function()
        -- Each was a raw in-game prefab/display name that is absent from minions.json,
        -- so createMinionSkills (CalcActiveSkill.lua ~1346
        -- `minion.minionData = env.data.minions[minionType]`) resolved nil and CRASHED
        -- at ~1476 for ANY build enabling the skill as an active skill. Datamine
        -- confirmed each prefab/display name and its minions.json key are the SAME minion.
        local cases = {
            ["PontifexCremate"]    = "BurningSkeleton",
            ["SummonIllusoryTree"] = "IllusoryTree",
            ["SummonMercenary"]    = "Mercenary",
        }
        for skillId, key in pairs(cases) do
            local sk = data.skills[skillId]
            assert.is_table(sk, skillId .. " must exist in data.skills")
            assert.is_table(sk.minionList, skillId .. ".minionList must be a table")
            assert.are.equal(key, sk.minionList[1],
                skillId .. ".minionList[1] must be the resolving minions.json key '" .. key .. "'")
            assert.is_table(data.minions[key], "minions.json must have key " .. key)
        end
    end)

    it("every skills.json minionList entry resolves to a real minions.json key (except KNOWN_DANGLING)", function()
        local offenders = {}
        for skillId, skill in pairs(data.skills) do
            if type(skill) == "table" and type(skill.minionList) == "table" then
                for _, minionKey in ipairs(skill.minionList) do
                    if not data.minions[minionKey] then
                        local allowed = KNOWN_DANGLING[skillId] and KNOWN_DANGLING[skillId][minionKey]
                        if not allowed then
                            table.insert(offenders, string.format(
                                "skill=%q minionList entry %q has no minions.json key",
                                tostring(skillId), tostring(minionKey)))
                        end
                    end
                end
            end
        end
        assert.are.equal(0, #offenders,
            "dangling minionList -> minions.json links (raw prefab name instead of LEB key?):\n  "
            .. table.concat(offenders, "\n  "))
    end)

end)
