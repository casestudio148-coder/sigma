-- ReplicatedStorage.TowerData (ModuleScript) — ЗАМЕНИТЕ старый код целиком
-- Rarity: Common / Rare / Epic / Legendary / Mythic (используется гачей, см. RarityData)
-- DamageType: "Physical" | "Magic" (мобы с резистами режут нужный тип)
-- Detector = true: видит мобов с тегом Stealth. Melee-башни не бьют летающих (тег Flying).
--
-- УЛУЧШЕНИЯ: 4 тира. Поля самой башни — тир 0 (начальный спавн).
-- Tiers[N] — переход на тир N:
--   Cost           — цена перехода (сервер берёт её только отсюда)
--   Damage         — урон на этом тире
--   Range          — радиус атаки
--   AttackCooldown — секунд между атаками (меньше = быстрее)
--   любые другие поля (Detector, MultiShot, SlowPercent...) — новые значения способностей
--   SpecialEffect  — только на 4-м тире: { Name, Description, Stats = { ... } }
-- Тир N получает всё из тиров 1..N по порядку. Числа можно менять прямо здесь.

local TowerData = {

	---------------------------------------------------------------- COMMON
	["Scout"] = {
		Name = "Scout",
		Rarity = "Common",
		Ability = "Quick Hands",
		Description = "Fast melee hits, 10% crit, brief stun.",
		Price = 75,
		-- тир 0 (начальный спавн)
		Damage = 12,
		Range = 14,
		AttackCooldown = 0.7,
		Melee = true,
		Stun = 0.15,
		CritChance = 0.1,
		CritMultiplier = 2,
		DamageType = "Physical",
		Limit = 8,
		TargetMode = "First",
		Tiers = {
			[1] = { Cost = 45, Damage = 15, Range = 15, AttackCooldown = 0.7 },
			[2] = { Cost = 75, Damage = 15, Range = 16, AttackCooldown = 0.62, Detector = true },
			[3] = { Cost = 120, Damage = 20, Range = 16, AttackCooldown = 0.62, CritChance = 0.15, Stun = 0.25 },
			[4] = { Cost = 210, Damage = 29, Range = 17, AttackCooldown = 0.54,
				SpecialEffect = {
					Name = "Flurry",
					Description = "25% crit for x2.5 damage",
					Stats = { CritChance = 0.25, CritMultiplier = 2.5 },
				},
			},
		},
	},
	-- ★ «Базовый Стрелок»: на 4-м тире сплеш-урон по области
	["Archer"] = {
		Name = "Archer",
		Rarity = "Common",
		Ability = "Volley",
		Description = "Shoots 2 targets at once.",
		Price = 100,
		-- тир 0 (начальный спавн)
		Damage = 12,
		Range = 38,
		AttackCooldown = 1.2,
		MultiShot = 1,  -- +1 дополнительная цель
		DamageType = "Physical",
		Limit = 8,
		TargetMode = "First",
		Tiers = {
			[1] = { Cost = 60, Damage = 15, Range = 40, AttackCooldown = 1.2 },
			[2] = { Cost = 100, Damage = 15, Range = 44, AttackCooldown = 1.06, Detector = true },
			[3] = { Cost = 160, Damage = 20, Range = 44, AttackCooldown = 1.06, MultiShot = 2 },
			[4] = { Cost = 280, Damage = 29, Range = 46, AttackCooldown = 0.92,
				SpecialEffect = {
					Name = "Explosive Arrows",
					Description = "50% splash damage in 6 studs",
					Stats = { Splash = 6, SplashPercent = 0.5 },
				},
			},
		},
	},
	["Spearman"] = {
		Name = "Spearman",
		Rarity = "Common",
		Ability = "Impale",
		Description = "Thrust pierces 2 extra enemies in a line and stuns.",
		Price = 150,
		-- тир 0 (начальный спавн)
		Damage = 24,
		Range = 17,
		AttackCooldown = 1.1,
		Melee = true,
		Pierce = 2,
		Stun = 0.35,
		DamageType = "Physical",
		Limit = 6,
		TargetMode = "First",
		Tiers = {
			[1] = { Cost = 90, Damage = 30, Range = 18, AttackCooldown = 1.1 },
			[2] = { Cost = 150, Damage = 30, Range = 20, AttackCooldown = 0.97, Detector = true },
			[3] = { Cost = 240, Damage = 40, Range = 20, AttackCooldown = 0.97, Pierce = 3 },
			[4] = { Cost = 420, Damage = 59, Range = 21, AttackCooldown = 0.84,
				SpecialEffect = {
					Name = "Skewer",
					Description = "Pierces 5 enemies, stuns 0.6s",
					Stats = { Pierce = 5, Stun = 0.6 },
				},
			},
		},
	},

	---------------------------------------------------------------- RARE
	["Mage"] = {
		Name = "Mage",
		Rarity = "Rare",
		Ability = "Arcane Blast",
		Description = "Magic explosion damages groups. Sees stealth.",
		Price = 250,
		-- тир 0 (начальный спавн)
		Damage = 22,
		Range = 30,
		AttackCooldown = 1.4,
		Splash = 7,
		DamageType = "Magic",
		Detector = true,
		Limit = 4,
		TargetMode = "First",
		Tiers = {
			[1] = { Cost = 150, Damage = 27, Range = 32, AttackCooldown = 1.4 },
			[2] = { Cost = 250, Damage = 27, Range = 35, AttackCooldown = 1.23 },
			[3] = { Cost = 400, Damage = 37, Range = 35, AttackCooldown = 1.23, Splash = 8.5 },
			[4] = { Cost = 700, Damage = 54, Range = 36, AttackCooldown = 1.07,
				SpecialEffect = {
					Name = "Arcane Overload",
					Description = "Bigger blast, +15% damage taken",
					Stats = { Splash = 11, VulnerablePercent = 0.15, VulnerableDuration = 3 },
				},
			},
		},
	},
	-- ★ «Замораживающая Башня»: на 4-м тире усиленное замедление и заморозка
	["IceMage"] = {
		Name = "IceMage",
		Rarity = "Rare",
		Ability = "Deep Freeze",
		Description = "Slows 40%; 10% chance to freeze for 1s.",
		Price = 300,
		-- тир 0 (начальный спавн)
		Damage = 14,
		Range = 30,
		AttackCooldown = 1.2,
		SlowPercent = 0.4,
		SlowDuration = 2.5,
		FreezeChance = 0.1,
		FreezeDuration = 1,
		DamageType = "Magic",
		Limit = 4,
		TargetMode = "First",
		Tiers = {
			[1] = { Cost = 180, Damage = 18, Range = 32, AttackCooldown = 1.2, SlowPercent = 0.45 },
			[2] = { Cost = 300, Damage = 18, Range = 35, AttackCooldown = 1.06, Detector = true },
			[3] = { Cost = 480, Damage = 24, Range = 35, AttackCooldown = 1.06, SlowPercent = 0.5, FreezeChance = 0.15 },
			[4] = { Cost = 840, Damage = 34, Range = 36, AttackCooldown = 0.92,
				SpecialEffect = {
					Name = "Absolute Zero",
					Description = "Slow 65%, 25% freeze for 1.5s",
					Stats = { SlowPercent = 0.65, SlowDuration = 3, FreezeChance = 0.25, FreezeDuration = 1.5 },
				},
			},
		},
	},
	["DartSpitter"] = {
		Name = "DartSpitter",
		Rarity = "Rare",
		Ability = "Toxic Darts",
		Description = "Fast darts apply poison (12 dmg/sec for 4s).",
		Price = 250,
		-- тир 0 (начальный спавн)
		Damage = 8,
		Range = 26,
		AttackCooldown = 0.6,
		PoisonDamage = 12,
		PoisonDuration = 4,
		DamageType = "Physical",
		Limit = 6,
		TargetMode = "First",
		Tiers = {
			[1] = { Cost = 150, Damage = 10, Range = 27, AttackCooldown = 0.6, PoisonDamage = 15 },
			[2] = { Cost = 250, Damage = 10, Range = 30, AttackCooldown = 0.53, Detector = true },
			[3] = { Cost = 400, Damage = 13, Range = 30, AttackCooldown = 0.53, PoisonDamage = 20 },
			[4] = { Cost = 700, Damage = 19, Range = 32, AttackCooldown = 0.46,
				SpecialEffect = {
					Name = "Neurotoxin",
					Description = "Poison 30/s for 5s, slow 25%",
					Stats = { PoisonDamage = 30, PoisonDuration = 5, SlowPercent = 0.25, SlowDuration = 2 },
				},
			},
		},
	},
	["BomberTower"] = {
		Name = "BomberTower",
		Rarity = "Rare",
		Ability = "Fire Bomb",
		Description = "Big bombs with a huge blast that set enemies on fire (burn stacks up to 3).",
		Price = 350,
		-- тир 0 (начальный спавн)
		Damage = 60,
		Range = 34,
		AttackCooldown = 2.2,
		Splash = 9,
		BurnDPS = 5,  -- урон горения в секунду за 1 стак
		BurnDuration = 3,
		BurnMaxStacks = 3,
		DamageType = "Physical",
		Limit = 4,
		TargetMode = "First",
		Tiers = {
			[1] = { Cost = 210, Damage = 75, Range = 36, AttackCooldown = 2.2 },
			[2] = { Cost = 350, Damage = 75, Range = 39, AttackCooldown = 1.94, Detector = true },
			[3] = { Cost = 560, Damage = 101, Range = 39, AttackCooldown = 1.94, Splash = 10.5, BurnDPS = 7 },
			[4] = { Cost = 980, Damage = 147, Range = 41, AttackCooldown = 1.68,
				SpecialEffect = {
					Name = "Napalm",
					Description = "Huge blast, burn stacks up to 5",
					Stats = { Splash = 13, BurnDPS = 10, BurnDuration = 4, BurnMaxStacks = 5 },
				},
			},
		},
	},

	---------------------------------------------------------------- EPIC
	["Assassin"] = {
		Name = "Assassin",
		Rarity = "Epic",
		Ability = "Execution",
		Description = "30% crit x3. Instantly kills non-boss enemies under 10% HP.",
		Price = 600,
		-- тир 0 (начальный спавн)
		Damage = 70,
		Range = 13,
		AttackCooldown = 0.8,
		Melee = true,
		CritChance = 0.3,
		CritMultiplier = 3,
		ExecuteHealthPercent = 0.1,
		DamageType = "Physical",
		Limit = 3,
		TargetMode = "Strongest",
		Tiers = {
			[1] = { Cost = 360, Damage = 88, Range = 14, AttackCooldown = 0.8 },
			[2] = { Cost = 600, Damage = 88, Range = 15, AttackCooldown = 0.7, Detector = true },
			[3] = { Cost = 960, Damage = 118, Range = 15, AttackCooldown = 0.7, CritChance = 0.35, ExecuteHealthPercent = 0.13 },
			[4] = { Cost = 1680, Damage = 171, Range = 16, AttackCooldown = 0.61,
				SpecialEffect = {
					Name = "Shadow Strike",
					Description = "45% crit x3.5, execute <18% HP",
					Stats = { CritChance = 0.45, CritMultiplier = 3.5, ExecuteHealthPercent = 0.18 },
				},
			},
		},
	},
	["Necromancer"] = {
		Name = "Necromancer",
		Rarity = "Epic",
		Ability = "Death Curse",
		Description = "Curses 3 enemies: extra damage = 6% of their max HP (weak vs bosses).",
		Price = 650,
		-- тир 0 (начальный спавн)
		Damage = 10,
		Range = 40,
		AttackCooldown = 2,
		MultiShot = 2,
		PercentMaxHpDamage = 0.06,
		PercentCap = 120,
		DamageType = "Magic",
		Limit = 2,
		TargetMode = "Strongest",
		Tiers = {
			[1] = { Cost = 390, Damage = 12, Range = 42, AttackCooldown = 2 },
			[2] = { Cost = 650, Damage = 12, Range = 46, AttackCooldown = 1.76, Detector = true },
			[3] = { Cost = 1040, Damage = 17, Range = 46, AttackCooldown = 1.76, MultiShot = 3, PercentMaxHpDamage = 0.07 },
			[4] = { Cost = 1820, Damage = 24, Range = 49, AttackCooldown = 1.53,
				SpecialEffect = {
					Name = "Plague Lord",
					Description = "Curses 6 enemies for 9% max HP",
					Stats = { MultiShot = 5, PercentMaxHpDamage = 0.09, PercentCap = 220 },
				},
			},
		},
	},
	-- ★ «Скорострел»: очень быстрые слабые болты, на 4-м тире ослабляет врагов
	["CrossbowTower"] = {
		Name = "CrossbowTower",
		Rarity = "Epic",
		Ability = "Rapid Fire",
		Description = "Very fast bolts with low damage. Each bolt pierces 1 extra enemy.",
		Price = 750,
		-- тир 0 (начальный спавн): 8 выстрелов в секунду
		Damage = 14,
		Range = 40,
		AttackCooldown = 0.125,
		Pierce = 1,
		DamageType = "Physical",
		Detector = true,
		Limit = 2,
		TargetMode = "First",
		Tiers = {
			[1] = { Cost = 450, Damage = 17, Range = 42, AttackCooldown = 0.125 },
			[2] = { Cost = 750, Damage = 17, Range = 45, AttackCooldown = 0.11 },
			[3] = { Cost = 1200, Damage = 23, Range = 45, AttackCooldown = 0.11, Pierce = 2 },
			[4] = { Cost = 2100, Damage = 31, Range = 48, AttackCooldown = 0.1,
				SpecialEffect = {
					Name = "Bolt Storm",
					Description = "10 bolts/sec, hit enemies take +20% damage",
					Stats = { Pierce = 3, VulnerablePercent = 0.2, VulnerableDuration = 2 },
				},
			},
		},
	},
	["Paladin"] = {
		Name = "Paladin",
		Rarity = "Epic",
		Ability = "Holy Aura",
		Description = "Towers within 28 studs deal +20% damage and attack 15% faster (doesn't stack).",
		Price = 900,
		-- тир 0 (начальный спавн)
		Damage = 55,
		Range = 18,
		AttackCooldown = 1.1,
		Melee = true,
		Stun = 0.3,
		BuffAuraPercent = 0.2,  -- аура урона союзных башен
		HasteAuraPercent = 0.15,  -- аура скорости атаки союзных башен
		AuraRange = 28,
		DamageType = "Magic",
		Detector = true,
		Limit = 2,
		TargetMode = "First",
		Tiers = {
			[1] = { Cost = 540, Damage = 69, Range = 19, AttackCooldown = 1.1 },
			[2] = { Cost = 900, Damage = 69, Range = 21, AttackCooldown = 0.97, AuraRange = 31 },
			[3] = { Cost = 1440, Damage = 93, Range = 21, AttackCooldown = 0.97, BuffAuraPercent = 0.25, HasteAuraPercent = 0.2 },
			[4] = { Cost = 2520, Damage = 135, Range = 22, AttackCooldown = 0.84,
				SpecialEffect = {
					Name = "Divine Banner",
					Description = "Aura +35% damage, +25% speed",
					Stats = { BuffAuraPercent = 0.35, HasteAuraPercent = 0.25, AuraRange = 36, Stun = 0.45 },
				},
			},
		},
	},

	---------------------------------------------------------------- LEGENDARY
	["LightningMage"] = {
		Name = "LightningMage",
		Rarity = "Legendary",
		Ability = "Chain Lightning",
		Description = "Lightning jumps to 4 more enemies (-15% per jump).",
		Price = 1200,
		-- тир 0 (начальный спавн)
		Damage = 70,
		Range = 34,
		AttackCooldown = 0.9,
		ChainTargets = 4,
		ChainRange = 14,
		ChainFalloff = 0.85,
		DamageType = "Magic",
		Detector = true,
		Limit = 2,
		TargetMode = "First",
		Tiers = {
			[1] = { Cost = 720, Damage = 88, Range = 36, AttackCooldown = 0.9 },
			[2] = { Cost = 1200, Damage = 88, Range = 39, AttackCooldown = 0.79, ChainRange = 16 },
			[3] = { Cost = 1920, Damage = 118, Range = 39, AttackCooldown = 0.79, ChainTargets = 5 },
			[4] = { Cost = 3360, Damage = 171, Range = 41, AttackCooldown = 0.69,
				SpecialEffect = {
					Name = "Storm Conduit",
					Description = "Chains to 8 enemies, mini-stun",
					Stats = { ChainTargets = 8, ChainFalloff = 0.92, Stun = 0.12 },
				},
			},
		},
	},
	["VoidLord"] = {
		Name = "VoidLord",
		Rarity = "Legendary",
		Ability = "Void Collapse",
		Description = "Massive blast. Executes non-boss enemies under 15% HP.",
		Price = 1500,
		-- тир 0 (начальный спавн)
		Damage = 190,
		Range = 40,
		AttackCooldown = 1.8,
		Splash = 11,
		ExecuteHealthPercent = 0.15,
		DamageType = "Magic",
		Limit = 1,
		TargetMode = "Strongest",
		Tiers = {
			[1] = { Cost = 900, Damage = 235, Range = 42, AttackCooldown = 1.8 },
			[2] = { Cost = 1500, Damage = 235, Range = 46, AttackCooldown = 1.58, Detector = true },
			[3] = { Cost = 2400, Damage = 320, Range = 46, AttackCooldown = 1.58, Splash = 12.5, ExecuteHealthPercent = 0.18 },
			[4] = { Cost = 4200, Damage = 465, Range = 49, AttackCooldown = 1.38,
				SpecialEffect = {
					Name = "Event Horizon",
					Description = "Bigger blast, slow 30%, execute <22%",
					Stats = { Splash = 15, ExecuteHealthPercent = 0.22, SlowPercent = 0.3, SlowDuration = 1.5 },
				},
			},
		},
	},

	---------------------------------------------------------------- MYTHIC
	["SoulReaper"] = {
		Name = "SoulReaper",
		Rarity = "Mythic",
		Ability = "Soul Harvest",
		Description = "Every kill adds +1.5 damage permanently (up to +400). Sweeping blows.",
		Price = 1900,
		-- тир 0 (начальный спавн)
		Damage = 115,
		Range = 22,
		AttackCooldown = 0.8,
		Melee = true,
		Splash = 6,
		SoulBonusDamagePerKill = 1.5,
		SoulBonusCap = 400,
		DamageType = "Physical",
		Limit = 1,
		TargetMode = "Strongest",
		Tiers = {
			[1] = { Cost = 1140, Damage = 145, Range = 23, AttackCooldown = 0.8 },
			[2] = { Cost = 1900, Damage = 145, Range = 25, AttackCooldown = 0.7, Detector = true },
			[3] = { Cost = 3040, Damage = 195, Range = 25, AttackCooldown = 0.7, Splash = 7, SoulBonusCap = 550 },
			[4] = { Cost = 5320, Damage = 285, Range = 27, AttackCooldown = 0.61,
				SpecialEffect = {
					Name = "Grim Harvest",
					Description = "+3 damage per kill (up to +1000)",
					Stats = { SoulBonusDamagePerKill = 3, SoulBonusCap = 1000, Splash = 9 },
				},
			},
		},
	},
}

-- совместимость: часть старого кода (инвентарь в лобби) читает поле Cooldown
for _, cfg in pairs(TowerData) do
	cfg.Cooldown = cfg.AttackCooldown
end

return TowerData
