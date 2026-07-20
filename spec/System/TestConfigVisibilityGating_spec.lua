-- @leb-regression-guard:config-visibility-gating
-- E batch 1 (2026-06-01). Previously-always-shown "while you have <buff>" /
-- "per <stack>" state configs are now gated with ifCond/ifMult = the SAME
-- Condition/Multiplier their apply sets, so they appear only when the build
-- has a modifier referencing that state (mainEnv.conditionsUsed[key] /
-- multipliersUsed[key] non-empty) instead of cluttering every build's
-- Config tab. (The class-FORM configs were already gated; this batch adds
-- the buff/stack ones.)
--
-- THE TRAP this spec guards against: a gate key that the mod parser never
-- emits would make the config PERMANENTLY hidden (conditionsUsed[key]
-- always empty -> shown-predicate always false). conditionHaveFlameWard /
-- conditionHaveEterrasBlessing and the four *Overload configs set a
-- Condition their apply alone produces but NO parsed mod ever references
-- (mods use the generic HaveAilmentOverload / Multiplier:ActiveOverload),
-- so they are intentionally NOT gated. Base-calc configs (Full/Low Life,
-- Full/Low Mana, High Health) also stay gateless: they affect EHP/resource
-- even without a conditional mod, so gating would over-hide.
--
-- See REGRESSION_GUARDS.md "config-visibility-gating".

describe("ConfigVisibilityGating", function()
    local function readFile(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local s = f:read("*a"); f:close()
        return s
    end

    local cfgOptsSrc, modParserSrc
    setup(function()
        cfgOptsSrc = readFile("Modules/ConfigOptions.lua")
        modParserSrc = readFile("Modules/ModParser.lua")
        assert.is_not_nil(cfgOptsSrc, "must read Modules/ConfigOptions.lua")
        assert.is_not_nil(modParserSrc, "must read Modules/ModParser.lua")
    end)

    -- The configs gated so far: var -> { gate, key }. gate is one of
    -- ifCond / ifMult (player-side, keyed to conditionsUsed/multipliersUsed)
    -- or ifEnemyCond / ifEnemyMult (enemy-side, keyed to
    -- enemyConditionsUsed/enemyMultipliersUsed). The Condition/Multiplier the
    -- apply sets (the "Tag:Key" string) is the same regardless of side.
    local GATED = {
        -- E batch 1 (player buff/stack state)
        { var = "conditionTransformed",        gate = "ifCond", key = "Transformed" },
        { var = "conditionHaveWard",           gate = "ifCond", key = "HaveWard" },
        { var = "conditionHaveLightningAegis", gate = "ifCond", key = "HaveLightningAegis" },
        { var = "conditionOnConsecratedGround", gate = "ifCond", key = "OnConsecratedGround" },
        { var = "conditionHaveCompanion",      gate = "ifCond", key = "HaveCompanion" },
        { var = "multiplierCompanion",         gate = "ifMult", key = "Companion" },
        { var = "conditionFrenzy",             gate = "ifCond", key = "Frenzy" },
        { var = "conditionHaste",              gate = "ifCond", key = "Haste" },
        { var = "conditionConcentration",      gate = "ifCond", key = "Concentration" },
        { var = "multiplierArcaneShieldStack", gate = "ifMult", key = "ArcaneShieldStack" },
        -- E batch 2 (mastery-stack + enemy-ailment state)
        { var = "multiplierDuskShroudStacks",  gate = "ifMult",      key = "DuskShroudStacks" },
        { var = "multiplierActiveSymbols",     gate = "ifMult",      key = "ActiveSymbol" },
        { var = "conditionEnemyChilled",       gate = "ifEnemyCond", key = "Chilled" },
        { var = "conditionEnemyShocked",       gate = "ifEnemyCond", key = "Shocked" },
        { var = "multiplierEnemyBleedStacks",  gate = "ifEnemyMult", key = "BleedStack" },
        { var = "multiplierEnemyIgniteStacks", gate = "ifEnemyMult", key = "IgniteStack" },
        { var = "multiplierEnemyShockStacks",  gate = "ifEnemyMult", key = "ShockStack" },
    }

    local function entryHead(var)
        local m = cfgOptsSrc:match('{ var = "' .. var .. '".-apply = function')
        return m
    end

    it("carries the config-visibility-gating guard marker", function()
        assert.is_truthy(cfgOptsSrc:find("@leb%-regression%-guard:config%-visibility%-gating", 1, false),
            "ConfigOptions.lua must carry the config-visibility-gating guard marker")
    end)

    it("each gated config declares the expected ifCond/ifMult key", function()
        for _, g in ipairs(GATED) do
            local head = entryHead(g.var)
            assert.is_not_nil(head, "entry for " .. g.var .. " must be locatable")
            assert.is_truthy(head:find(g.gate .. ' = "' .. g.key .. '"', 1, true),
                g.var .. " must declare " .. g.gate .. ' = "' .. g.key .. '"')
        end
    end)

    it("each gated config's gate key matches the Condition/Multiplier its apply sets", function()
        for _, g in ipairs(GATED) do
            -- Bounded window from the entry start. Some entries carry a very
            -- long tooltip before the apply body (e.g. multiplierDuskShroudStacks
            -- puts Multiplier:DuskShroudStacks ~690 chars in), so the window is
            -- 900. The specific "Tag:Key" we check for is unique to this config,
            -- so a wider window spilling into the next entry can't false-match.
            local st = cfgOptsSrc:find('{ var = "' .. g.var .. '"', 1, true)
            assert.is_not_nil(st, "full entry for " .. g.var .. " must be locatable")
            local body = cfgOptsSrc:sub(st, st + 900)
            local tag = (g.gate == "ifCond" or g.gate == "ifEnemyCond") and "Condition" or "Multiplier"
            assert.is_truthy(body:find(tag .. ":" .. g.key, 1, true),
                g.var .. " apply must set " .. tag .. ":" .. g.key .. " (gate key must match what the config sets)")
        end
    end)

    it("ANTI-UNREACHABLE: every gate key is emitted by ModParser (so conditionsUsed[key] can populate)", function()
        for _, g in ipairs(GATED) do
            assert.is_truthy(modParserSrc:find('var = "' .. g.key .. '"', 1, true),
                "gate key '" .. g.key .. "' (" .. g.var .. ") MUST be emitted by ModParser as var = \"" .. g.key
                    .. "\" — otherwise the config is permanently hidden (conditionsUsed[key] never populates)")
        end
    end)

    it("configs whose Condition var ModParser never emits stay GATELESS (no unreachable gating)", function()
        -- These set a Condition only their own apply produces; no parsed mod
        -- references it, so gating them would make them permanently hidden.
        for _, var in ipairs({ "conditionHaveFlameWard", "conditionHaveEterrasBlessing",
                               "conditionBleedOverload", "conditionIgniteOverload",
                               "conditionPoisonOverload", "conditionDamnedOverload" }) do
            local head = entryHead(var)
            assert.is_not_nil(head, "entry for " .. var .. " must exist")
            assert.falsy(head:find("ifCond", 1, true),
                var .. " must remain gateless — its Condition var is not emitted by ModParser, so an ifCond gate would hide it permanently")
        end
    end)

    it("E batch 2: stat-only stack configs stay GATELESS (no conditional tag var to gate on)", function()
        -- These stack configs apply their effect as DIRECT stat mods with NO
        -- Multiplier/Condition tag var (e.g. Contempt sets Armour MORE +
        -- resists; Void Essence sets VoidDamage/Damage MORE; the Infusions set
        -- flat added damage). There is no per-stack key a parsed mod references,
        -- so there is nothing to gate on — gating would require inventing a key
        -- ModParser never emits (permanent-hide trap). They stay gateless.
        for _, var in ipairs({ "multiplierVoidEssenceStacks", "multiplierContemptStacks",
                               "multiplierMoltenInfusionStacks", "multiplierStormInfusionStacks" }) do
            local head = entryHead(var)
            assert.is_not_nil(head, "entry for " .. var .. " must exist")
            assert.falsy(head:find("ifMult", 1, true),
                var .. " must remain gateless — its apply sets no Multiplier tag var, so an ifMult gate would have no ModParser key to populate it")
            assert.falsy(head:find("ifCond", 1, true),
                var .. " must remain gateless — its apply sets no Condition tag var")
        end
    end)

    -- (Note: the Full/Low Life and Full/Low Mana configs are ALREADY gated by
    -- pre-existing code with ifCond = "FullLife"/"LowLife"/etc. — this batch
    -- does not touch them. Whether low-life gating over-hides EHP relevance
    -- is tracked separately under the Fa-11 Low-Life→EHP investigation.)
end)
