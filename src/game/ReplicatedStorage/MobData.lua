-- ReplicatedStorage.MobData — ЗАМЕНИТЕ старый код целиком
-- RewardGold — монеты за убийство, LeakDamage — урон базе, если моб дошёл до конца.
-- Tags: Boss (босс: контроль слабее, есть фазы — см. BossData), Flying, Stealth,
--       ImmuneToSlow, ImmuneToStun, ImmuneToBurn, ImmuneToPoison, Minion.
-- Model — какую модель из ReplicatedStorage.Mobs взять (для миньонов: свои статы, чужая модель)
-- Tint  — перекрасить модель в этот цвет (чтобы миньоны отличались)

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local EnemyData = {
	["Normal"] = {
		ID = "Normal", Name = "Orc Warrior",
		Health = 25, Speed = 14, RewardGold = 3, LeakDamage = 2,
		Tags = {}, Special = {}
	},
	["Fast"] = {
		ID = "Fast", Name = "Goblin Runner",
		Health = 15, Speed = 22, RewardGold = 2, LeakDamage = 2,
		Tags = {}, Special = {}
	},
	["Slow"] = {
		ID = "Slow", Name = "Slow",
		Health = 70, Speed = 8, RewardGold = 4, LeakDamage = 4,
		Tags = {}, Special = {}
	},
	["Heavy"] = {
		ID = "Heavy", Name = "Armored Orc",
		Health = 100, Speed = 8, RewardGold = 8, LeakDamage = 5,
		Tags = {}, Special = {}
	},
	["Swarm"] = {
		ID = "Swarm", Name = "Spider",
		Health = 10, Speed = 14, RewardGold = 1, LeakDamage = 1,
		Tags = {}, Special = {}
	},
	["Flying"] = {
		ID = "Flying", Name = "Harpy",
		Health = 40, Speed = 16, RewardGold = 5, LeakDamage = 3,
		Tags = {"Flying"}, Special = {}
	},
	["Shielded"] = {
		ID = "Shielded", Name = "Shield Knight",
		Health = 30, Speed = 10, RewardGold = 6, LeakDamage = 4,
		Tags = {"Shielded"}, Special = { ShieldHP = 30 }
	},
	["Regen"] = {
		ID = "Regen", Name = "Troll",
		Health = 150, Speed = 12, RewardGold = 10, LeakDamage = 6,
		Tags = {}, Special = { RegenAmount = 5, RegenInterval = 1 }
	},
	["Healer"] = {
		ID = "Healer", Name = "Shaman",
		Health = 30, Speed = 12, RewardGold = 9, LeakDamage = 4,
		Tags = {}, Special = { HealRadius = 5, HealAmount = 3, HealInterval = 2 }
	},
	["Ghost"] = {
		ID = "Ghost", Name = "Ghost",
		Health = 60, Speed = 14, RewardGold = 8, LeakDamage = 5,
		Tags = {"PhysicalResist", "ImmuneToPoison"}, Special = { PhysicalDamageReduction = 0.7 }
	},
	["Necromancer"] = {
		ID = "Necromancer", Name = "Necromancer",
		Health = 120, Speed = 9, RewardGold = 12, LeakDamage = 6,
		Tags = {}, Special = { SummonEnemyID = "Normal", SummonInterval = 3 }
	},
	["Berserker"] = {
		ID = "Berserker", Name = "Berserker",
		Health = 300, Speed = 18, RewardGold = 18, LeakDamage = 10,
		Tags = {"ImmuneToSlow", "ImmuneToStun"}, Special = {}
	},
	["ArmoredTank"] = {
		ID = "ArmoredTank", Name = "Mecha Golem",
		Health = 800, Speed = 6, RewardGold = 30, LeakDamage = 15,
		Tags = {"MagicResist", "ImmuneToBurn"}, Special = { MagicDamageReduction = 0.5 }
	},
	["VoidHound"] = {
		ID = "VoidHound", Name = "Void Hound",
		Health = 200, Speed = 24, RewardGold = 20, LeakDamage = 8,
		Tags = {"Stealth"}, Special = {}
	},

	---------------------------------------------------------------- боссы (фазы и навыки — в BossData)
	["MiniBoss"] = {
		ID = "MiniBoss", Name = "Mutant Ogre",
		Health = 2000, Speed = 5, RewardGold = 90, LeakDamage = 40,
		Tags = {"Boss"}, Special = {}
	},
	["MapBoss"] = {
		ID = "MapBoss", Name = "Demon Lord",
		Health = 10000, Speed = 4, RewardGold = 300, LeakDamage = 100,
		Tags = {"Boss"}, Special = {}
	},

	---------------------------------------------------------------- миньоны боссов (свои статы, чужая модель)
	["Ogreling"] = {
		ID = "Ogreling", Name = "Ogreling", Model = "Normal", Tint = rgb(110, 200, 80),
		Health = 90, Speed = 13, RewardGold = 2, LeakDamage = 4,
		Tags = {"Minion"}, Special = { ShieldHP = 30 }
	},
	["Imp"] = {
		ID = "Imp", Name = "Imp", Model = "Fast", Tint = rgb(255, 70, 50),
		Health = 45, Speed = 24, RewardGold = 1, LeakDamage = 3,
		Tags = {"Minion", "ImmuneToBurn"}, Special = {}
	},
	["Hellhound"] = {
		ID = "Hellhound", Name = "Hellhound", Model = "VoidHound", Tint = rgb(255, 130, 30),
		Health = 220, Speed = 26, RewardGold = 3, LeakDamage = 6,
		Tags = {"Minion", "ImmuneToSlow", "ImmuneToBurn"}, Special = {}
	},
}

return EnemyData
