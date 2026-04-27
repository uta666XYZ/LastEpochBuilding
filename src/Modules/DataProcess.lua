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
    grantedEffect.skillTypes = {}
    for name, type in pairs(SkillType) do
        if bit.band(grantedEffect.skillTypeTags, type) > 0 then
            grantedEffect.skillTypes[type] = true
        end
    end
    -- skills.json's skillTypeTags often omits category bits (e.g. summon skills with
    -- baseFlags.minion=true but skillTypeTags=0). Mirror baseFlags into skillTypes so
    -- mods tagged with SkillType=Minion/Spell/Melee/etc. apply when summing for cap
    -- calculations and skillCfg-tagged mods.
    if grantedEffect.baseFlags then
        local flagToType = {
            minion = SkillType.Minion,
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
        if grantedEffect.baseFlags.minion and grantedEffect.castTime
           and not grantedEffect.baseFlags.melee
           and not grantedEffect.baseFlags.bow
           and not grantedEffect.baseFlags.throwing
           and not grantedEffect.baseFlags.totem
           and not grantedEffect.baseFlags.transform then
            grantedEffect.skillTypes[SkillType.Spell] = true
        end
    end
    -- Also expose a keywordFlags bitmap for skillCfg consumers that filter mods by
    -- the skill's category (Spell/Melee/Minion/elemental). Built from skillTypes so
    -- baseFlags-derived bits are included.
    grantedEffect.keywordFlags = grantedEffect.skillTypeTags or 0
    for skillType in pairs(grantedEffect.skillTypes) do
        if type(skillType) == "number" then
            grantedEffect.keywordFlags = bit.bor(grantedEffect.keywordFlags, skillType)
        end
    end
end
