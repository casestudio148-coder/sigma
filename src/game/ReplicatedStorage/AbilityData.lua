-- ReplicatedStorage.AbilityData (ModuleScript) — общая таблица (сервер + клиент)
-- АКТИВНЫЕ способности башен: кнопка в панели башни или клавиша Q.
--   UnlockLevel — с какого уровня улучшения способность доступна
--   Cooldown    — перезарядка в секундах
--   остальные поля — параметры, которые читает сервер (AbilityService)
-- Способность сама целится в самую плотную толпу / самого сильного врага в радиусе башни.
--
-- ПАССИВНЫЕ способности работают сами (TowerManeger + AbilityService) и задаются в TowerData:
--   Stun, SlowPercent, FreezeChance, PoisonDamage, BurnDPS — эффекты при попадании
--   CritChance, ExecuteHealthPercent, PercentMaxHpDamage, SoulBonus... — особые удары
--   MultiShot, Pierce, Splash, ChainTargets — несколько целей
--   BuffAuraPercent / HasteAuraPercent (+ AuraRange) — аура урона / скорости атаки союзных башен

local AbilityData = {}

AbilityData.Actives = {
	Archer = {
		Id = "ArrowRain", Name = "Arrow Rain", Icon = "🏹", Cooldown = 22, UnlockLevel = 2,
		Description = "3 volleys of arrows rain on the biggest crowd.",
		Radius = 10, Volleys = 3, Interval = 0.5, DamageMult = 1.2,
	},
	Mage = {
		Id = "Meteor", Name = "Meteor", Icon = "☄️", Cooldown = 28, UnlockLevel = 2,
		Description = "A meteor crashes into the crowd and sets everyone on fire.",
		Radius = 12, FallTime = 0.8, DamageMult = 3, BurnDPS = 6, BurnDuration = 4, BurnStacks = 2,
	},
	IceMage = {
		Id = "Blizzard", Name = "Blizzard", Icon = "🌨️", Cooldown = 25, UnlockLevel = 2,
		Description = "Freezes every enemy in a big area, then slows them.",
		Radius = 14, FreezeDuration = 2.5, SlowAfter = 0.5, SlowDuration = 2, DamageMult = 1.5,
	},
	DartSpitter = {
		Id = "ToxicCloud", Name = "Toxic Cloud", Icon = "☁️", Cooldown = 26, UnlockLevel = 2,
		Description = "A poison cloud that slows and poisons enemies for 6s.",
		Radius = 11, Duration = 6, PoisonDPS = 12, Slow = 0.3,
	},
	BomberTower = {
		Id = "CarpetBomb", Name = "Carpet Bomb", Icon = "💣", Cooldown = 32, UnlockLevel = 2,
		Description = "Drops 6 fire bombs on the front of the enemy line.",
		Bombs = 6, Radius = 8, DamageMult = 1.5, FallTime = 0.5, Step = 0.15, BurnDPS = 8, BurnDuration = 3,
	},
	Assassin = {
		Id = "MarkForDeath", Name = "Mark for Death", Icon = "🎯", Cooldown = 24, UnlockLevel = 2,
		Description = "Marks the strongest enemy: it takes +60% damage for 6s.",
		RangeBonus = 20, Vulnerable = 0.6, Duration = 6, StunDuration = 0.8, DamageMult = 3,
	},
	Necromancer = {
		Id = "Plague", Name = "Plague", Icon = "🦠", Cooldown = 30, UnlockLevel = 2,
		Description = "Curses up to 8 enemies: +35% damage taken and strong poison.",
		MaxTargets = 8, Vulnerable = 0.35, Duration = 6, PoisonDPS = 15,
	},
	CrossbowTower = {
		Id = "Ballista", Name = "Ballista Shot", Icon = "🔱", Cooldown = 26, UnlockLevel = 2,
		Description = "A giant bolt that pierces EVERY enemy in a long line.",
		LengthMult = 1.6, Width = 4, DamageMult = 4, StunDuration = 0.5,
	},
	Paladin = {
		Id = "Rally", Name = "Holy Rally", Icon = "📯", Cooldown = 40, UnlockLevel = 2,
		Description = "Towers nearby attack 50% faster and hit 25% harder for 8s.",
		Radius = 32, Duration = 8, AttackSpeed = 0.5, Damage = 0.25,
	},
	LightningMage = {
		Id = "Thunderstorm", Name = "Thunderstorm", Icon = "🌩️", Cooldown = 30, UnlockLevel = 2,
		Description = "6 lightning strikes from the sky, each chains to 3 more enemies.",
		Strikes = 6, Interval = 0.3, Jumps = 3, JumpRange = 16, Falloff = 0.85, DamageMult = 2, StunDuration = 0.4,
	},
	VoidLord = {
		Id = "BlackHole", Name = "Black Hole", Icon = "🕳️", Cooldown = 35, UnlockLevel = 1,
		Description = "Pulls enemies into a black hole for 3s, then it collapses.",
		Radius = 14, Duration = 3, PullSpeed = 10, Slow = 0.6, TickDamageMult = 0.4, CollapseMult = 3,
	},
	SoulReaper = {
		Id = "Reap", Name = "Reap", Icon = "💀", Cooldown = 30, UnlockLevel = 1,
		Description = "Slashes everyone in range. Non-boss enemies under 30% HP die instantly.",
		ExecutePercent = 0.3, DamageMult = 2.5,
	},
}

AbilityData.ById = {}
for towerName, def in pairs(AbilityData.Actives) do
	def.Tower = towerName
	AbilityData.ById[def.Id] = def
end

function AbilityData.Get(towerName)
	return AbilityData.Actives[towerName]
end

return AbilityData
