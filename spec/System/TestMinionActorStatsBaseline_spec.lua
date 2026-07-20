-- @leb-regression-guard:minion-actorstats-baseline
-- Locks the per-minion ActorStats baselines baked into src/Data/minions.json
-- (sweep follow-up to the PrimalBear bear fix <see git log>). Each value is the
-- minion prefab's intrinsic ActorStats.stats entry from
-- actors_player_specific_gameplay_assets_all.bundle (extracted by
-- datamined game source), mapped:
--   property 0  -> Damage      (MORE; tags: type bit -> <Type>Damage name,
--                               Melee 512 -> flags, Minion 8192 stripped)
--   property 2  -> Speed        (flags ModFlag.Attack 3584)
--   property 3  -> Speed        (flags ModFlag.Cast 256)  [caster minions]
--   property 6  -> DamageTaken
--   property 9  -> MovementSpeed
--   property 17 -> LifeRegen     (BASE, flat)
-- Only non-identity stats are baked, all tagged source "MinionBase:ActorStats".
-- Defensive props (Dodge/StunAvoidance/StunImmunity), prop-0 flat-added typing
-- (ClawTotem) and the Bloodthirst companion extension are intentionally NOT
-- baked. See REGRESSION_GUARDS.md "minion-actorstats-baseline".

describe("MinionActorStatsBaseline #minions", function()
	local function mods(key)
		assert.is_table(data.minions[key], key .. " must exist in minions.json")
		return data.minions[key].modList or {}
	end

	-- find a mod by name (+optional type/flags) among the MinionBase:ActorStats mods
	local function find(key, name, typ, flags)
		for _, m in ipairs(mods(key)) do
			if m.name == name and (typ == nil or m.type == typ)
				and (flags == nil or m.flags == flags) then
				return m
			end
		end
		return nil
	end

	it("PrimalBear's landed bake is preserved unchanged (5 mods)", function()
		local ml = mods("PrimalBear")
		assert.are.equal(5, #ml)
		assert.are.equal(75, find("PrimalBear", "Damage", "MORE", 0).value)
		assert.are.equal(-22, find("PrimalBear", "Speed", "MORE", 3584).value)
		assert.are.equal(-50, find("PrimalBear", "DamageTaken", "MORE", 0).value)
		assert.are.equal(24, find("PrimalBear", "LifeRegen", "BASE", 0).value)
		assert.are.equal(20, find("PrimalBear", "MovementSpeed", "INC", 0).value)
	end)

	it("companion baselines: wolf hits softer but faster, sabertooth/raptor attack faster", function()
		-- PrimalWolf: Damage MORE -12, Attack Speed MORE +30
		assert.are.equal(-12, find("PrimalWolf", "Damage", "MORE", 0).value)
		assert.are.equal(30, find("PrimalWolf", "Speed", "MORE", 3584).value)
		-- PrimalSabertooth: Attack Speed MORE +30
		assert.are.equal(30, find("PrimalSabertooth", "Speed", "MORE", 3584).value)
		-- PrimalRaptor: Damage MORE +25, Attack Speed MORE +10
		assert.are.equal(25, find("Summon_Raptor", "Damage", "MORE", 0).value)
		assert.are.equal(10, find("Summon_Raptor", "Speed", "MORE", 3584).value)
	end)

	it("swarm/summon baselines: bees hit for half, wraith hits hard", function()
		assert.are.equal(-50, find("Bee", "Damage", "MORE", 0).value)
		assert.are.equal(-50, find("FireBee", "Damage", "MORE", 0).value)
		assert.are.equal(152, find("SummonedWraith", "Damage", "MORE", 0).value)
	end)

	it("golems: generic + Melee-scoped Damage MORE both baked (tags faithfully mapped)", function()
		-- SummonedBoneGolem prop0 tags=0 more 0.4 (generic) + tags=512 more 0.6 (melee)
		assert.are.equal(40, find("SummonedBoneGolem", "Damage", "MORE", 0).value)
		assert.are.equal(60, find("SummonedBoneGolem", "Damage", "MORE", 512).value, -- ModFlag.Melee
			"the Melee-tagged damage MORE must carry flags=ModFlag.Melee, not generic")
	end)

	it("caster minions: cast-speed reduction baked as Speed MORE flags=ModFlag.Cast", function()
		-- MirrorImage prop3 (cast speed) more -0.25 -> Speed MORE -25 flags=256
		assert.are.equal(-25, find("MirrorImage", "Speed", "MORE", 256).value)
		assert.are.equal(-25, find("ShadowClone", "Speed", "MORE", 256).value)
	end)

	it("no fabrication: every baked mod is tagged MinionBase:ActorStats with a sane name", function()
		local allowed = { Damage = true, PhysicalDamage = true, FireDamage = true,
			ColdDamage = true, LightningDamage = true, VoidDamage = true,
			NecroticDamage = true, PoisonDamage = true, Speed = true,
			DamageTaken = true, MovementSpeed = true, LifeRegen = true }
		for key, m in pairs(data.minions) do
			for _, mod in ipairs(m.modList or {}) do
				if mod.source == "MinionBase:ActorStats" then
					assert.is_truthy(allowed[mod.name],
						key .. " baked an unexpected stat name: " .. tostring(mod.name))
					-- defensive/unidentified props must NOT be baked
					assert.are_not.equal("Dodge", mod.name)
					assert.are_not.equal("StunAvoidance", mod.name)
				end
			end
		end
	end)

	it("datamine blockers stay empty (name-mismatch / not in player_specific), not fabricated", function()
		for _, key in ipairs({ "SummonedSoulWisp", "RiftBeast", "ChillyBee", "PrimalAnurok" }) do
			assert.are.equal(0, #mods(key),
				key .. " is an unmatched datamine blocker and must stay stubbed (no fabrication)")
		end
	end)
end)
