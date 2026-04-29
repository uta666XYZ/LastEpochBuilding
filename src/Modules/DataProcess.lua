-- Last Epoch Building
--
-- Module: DataProcess
-- Process static data used by other modules
--

local t_insert = table.insert

local function processMod(grantedEffect, mod)
    mod.source = grantedEffect.modSource
    if type(mod.value) == "table" and mod.value.mod then
        mod.value.mod.source = "Skill:"..grantedEffect.id
    end
    for _, tag in ipairs(mod) do
        if tag.type == "GlobalEffect" then
            grantedEffect.hasGlobalEffect = true
            break
        end
    end
end

data.skillStatMapMeta = {
    __index = function(t, key)
        local map = data.skillStatMap[key]
        if map then
            map = copyTable(map)
            t[key] = map
            for _, mod in ipairs(map) do
                processMod(t._grantedEffect, mod)
            end
            return map
        end
    end
}

for skillId, grantedEffect in pairs(data.skills) do
    grantedEffect.id = skillId
    grantedEffect.modSource = "Skill:"..skillId
    -- Process base mods that are given as mod lines
    if grantedEffect.baseMods then
        local baseMods = grantedEffect.baseMods
        grantedEffect.baseMods = {}
        for i, mod in ipairs(baseMods) do
            local modList, extra = modLib.parseMod(mod)
            for _, mod in ipairs(modList) do
                t_insert(grantedEffect.baseMods, mod)
            end
        end
    end
    -- Add sources for skill mods, and check for global effects
    for _, list in pairs({grantedEffect.baseMods, grantedEffect.qualityMods, grantedEffect.levelMods}) do
        for _, mod in pairs(list) do
            if mod.name then
                processMod(grantedEffect, mod)
            else
                for _, mod in ipairs(mod) do
                    processMod(grantedEffect, mod)
                end
            end
        end
    end
    -- Install stat map metatable
    grantedEffect.statMap = grantedEffect.statMap or { }
    setmetatable(grantedEffect.statMap, data.skillStatMapMeta)
    grantedEffect.statMap._grantedEffect = grantedEffect
    for _, map in pairs(grantedEffect.statMap) do
        -- Some mods need different scalars for different stats, but the same value.  Putting them in a group allows this
        for _, modOrGroup in ipairs(map) do
            if modOrGroup.name then
                processMod(grantedEffect, modOrGroup)
            else
                for _, mod in ipairs(modOrGroup) do
                    processMod(grantedEffect, mod)
                end
            end
        end
    end
    --- Compute skill types
    -- Use full-mask match (band == type) so composite SkillType values like
    -- Attack (= Melee|Throwing|Bow = 1664) only flag when ALL their bits are
    -- present. Without this, a skill carrying only one of the bits (e.g.
    -- Enchant Weapon with bit128 = Elemental) gets falsely tagged as Attack
    -- and downstream mod matching adds bogus "+1 to Melee Skills" hits.
    grantedEffect.skillTypes = {}
    for name, type in pairs(SkillType) do
        if type ~= 0 and bit.band(grantedEffect.skillTypeTags, type) == type then
            grantedEffect.skillTypes[type] = true
        end
    end
    -- skills.json's skillTypeTags often omits category bits (e.g. summon skills with
    -- baseFlags.minion=true but skillTypeTags=0). Mirror baseFlags into skillTypes so
    -- mods tagged with SkillType=Minion/Spell/Melee/etc. apply when summing for cap
    -- calculations and skillCfg-tagged mods.
    if grantedEffect.baseFlags then
        -- NOTE: baseFlags.minion is intentionally NOT mirrored. baseFlags.minion
        -- means "this skill summons a minion" (mechanics), which is broader than
        -- "this skill is a Minion Skill" (affix matching). Skills like Decoy and
        -- Vale Spirit have baseFlags.minion=true but the cast itself is not a
        -- Minion Skill — in-game, "+to Minion Skills" affixes do NOT apply to
        -- their level. Genuine Minion Skills (Summon X, Falconry, etc.) carry
        -- the Minion bit in fakeTags, which is mirrored below.
        local flagToType = {
            spell = SkillType.Spell,
            melee = SkillType.Melee,
            throwing = SkillType.Throwing,
            bow = SkillType.Bow,
            totem = SkillType.Totem,
            channelling = SkillType.Channelling,
            buff = SkillType.Buff,
            transform = SkillType.Transform,
            curse = SkillType.Curse,
            ailment = SkillType.Ailment,
        }
        for flag, skillType in pairs(flagToType) do
            if grantedEffect.baseFlags[flag] and skillType ~= SkillType.Unsupported then
                grantedEffect.skillTypes[skillType] = true
            end
        end
        -- Most summon skills cast as spells (Summon Skeleton/Skeletal Mage/Volatile
        -- Zombie etc.) but skills.json only carries baseFlags.minion. Without a Spell
        -- bit, mods like "+N to Spell Minion Skills" cannot match the parent summon
        -- skill. If a minion skill has a cast time and isn't a melee/ranged/totem/
        -- transform skill, treat it as a spell as well.
        -- Also check skillTypeTags|fakeTags for delivery-type bits (Decoy has
        -- baseFlags.projectile+attack with skillTypeTags Throwing bit but no
        -- baseFlags.throwing — without this check it would be wrongly tagged
        -- Spell despite being a Throwing skill).
        local existingTags = bit.bor(grantedEffect.skillTypeTags or 0, grantedEffect.fakeTags or 0)
        local hasDeliveryTag = bit.band(existingTags,
            bit.bor(SkillType.Spell, SkillType.Melee, SkillType.Bow, SkillType.Throwing,
                    SkillType.Totem, SkillType.Transform)) ~= 0
        if grantedEffect.baseFlags.minion and grantedEffect.castTime
           and not grantedEffect.baseFlags.melee
           and not grantedEffect.baseFlags.bow
           and not grantedEffect.baseFlags.throwing
           and not grantedEffect.baseFlags.totem
           and not grantedEffect.baseFlags.transform
           and not hasDeliveryTag then
            grantedEffect.skillTypes[SkillType.Spell] = true
        end
    end
    -- LE's `fakeTags` field tags a skill with categories it doesn't carry in its
    -- raw skillTypeTags (e.g. Judgement is mechanically Melee but is also tagged
    -- as a Spell for affix matching and tooltip display). Merge these into
    -- skillTypes so both Scaling Tags display and SkillLevel cap-summing pick
    -- them up (e.g. "+1 to Elemental Spell Skills" on Judgement).
    if grantedEffect.fakeTags and grantedEffect.fakeTags ~= 0 then
        for name, skillType in pairs(SkillType) do
            if skillType ~= 0 and skillType ~= SkillType.Unsupported
               and bit.band(grantedEffect.fakeTags, skillType) == skillType then
                grantedEffect.skillTypes[skillType] = true
            end
        end
    end
    -- Also expose a keywordFlags bitmap for skillCfg consumers that filter mods by
    -- the skill's category (Spell/Melee/Minion/elemental). Built from skillTypes so
    -- baseFlags-derived and fakeTags-derived bits are included.
    grantedEffect.keywordFlags = bit.bor(grantedEffect.skillTypeTags or 0, grantedEffect.fakeTags or 0)
    for skillType in pairs(grantedEffect.skillTypes) do
        if type(skillType) == "number" then
            grantedEffect.keywordFlags = bit.bor(grantedEffect.keywordFlags, skillType)
        end
    end
    -- Attribute scalings used by the "+N to <Attribute> Skills" SkillAttribute
    -- mod tag. Mirrors LE's ScalesWithAttribute() which returns true iff the
    -- requested attribute is in `Ability.getAttributeScaling()`. Empirically
    -- confirmed via Smoke Bomb (class=Rogue, attributeScalings=[]): Traitor's
    -- Tongue "+1 to Dex Skills" does NOT apply in LETools — i.e. there is no
    -- class-primary fallback at runtime. Use the static field verbatim.
    grantedEffect.skillAttributes = {}
    if grantedEffect.attributeScalings then
        for _, attr in ipairs(grantedEffect.attributeScalings) do
            grantedEffect.skillAttributes[attr] = true
        end
    end
end
