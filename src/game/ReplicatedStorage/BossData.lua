-- ReplicatedStorage.BossData (ModuleScript) — общая таблица (сервер + клиент)
-- Мультифазовые боссы. Ключ = имя моба в MobData.
--
-- Фаза включается, когда HP падает до At (1 = 100%, 0.5 = 50%, 0.2 = 20%). Фазы идут только вперёд.
--   SpeedMult  — множитель скорости босса
--   Armor      — броня (0.3 = получает на 30% меньше урона)
--   AnimSpeed  — ускорение анимаций (походка становится «злее»)
--   Animation  — (необязательно) "rbxassetid://ID" своей анимации для этой фазы
--   Announce   — надпись на весь экран при входе в фазу
--   Summon     — разовый призыв миньонов при входе в фазу
--   Cleanse    — снять с босса все замедления / станы / яд / горение
-- TransitionTime — сколько секунд босс превращается: стоит на месте и неуязвим
-- Summon (общий) — периодический призыв: каждые Interval секунд, ExtraPerPhase = +миньонов за каждую фазу
-- MaxMinions — не больше стольких живых миньонов от одного босса (защита от лагов)
-- Skills — навыки: работают с фазы FromPhase

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local BossData = {
	MiniBoss = {
		DisplayName = "Mutant Ogre",
		Color = rgb(120, 220, 90),
		TransitionTime = 1.2,
		MaxMinions = 8,
		Summon = { Mob = "Ogreling", Count = 2, Interval = 14, ExtraPerPhase = 1 },
		Phases = {
			{ Name = "Hungry", At = 1, SpeedMult = 1, Armor = 0, AnimSpeed = 1, Color = rgb(120, 220, 90) },
			{
				Name = "Furious", At = 0.5, SpeedMult = 1.3, Armor = 0.2, AnimSpeed = 1.3, Color = rgb(255, 170, 40),
				Announce = "THE OGRE IS FURIOUS!", Summon = { Mob = "Ogreling", Count = 3 }, Cleanse = true,
			},
			{
				Name = "Berserk", At = 0.2, SpeedMult = 1.6, Armor = 0.35, AnimSpeed = 1.6, Color = rgb(255, 60, 60),
				Announce = "THE OGRE GOES BERSERK!", Summon = { Mob = "Ogreling", Count = 5 }, Cleanse = true,
			},
		},
		Skills = {
			Regenerate = { Interval = 8, Percent = 0.04, FromPhase = 2 }, -- лечит 4% HP
		},
	},

	MapBoss = {
		DisplayName = "Demon Lord",
		Color = rgb(170, 40, 230),
		TransitionTime = 1.5,
		MaxMinions = 10,
		Summon = { Mob = "Imp", Count = 3, Interval = 12, ExtraPerPhase = 1 },
		Phases = {
			{ Name = "Wrath", At = 1, SpeedMult = 1, Armor = 0.1, AnimSpeed = 1, Color = rgb(170, 40, 230) },
			{
				Name = "Hellfire", At = 0.5, SpeedMult = 1.25, Armor = 0.3, AnimSpeed = 1.25, Color = rgb(255, 110, 30),
				Announce = "THE DEMON LORD IS ENRAGED!", Summon = { Mob = "Imp", Count = 6 }, Cleanse = true,
			},
			{
				Name = "Apocalypse", At = 0.2, SpeedMult = 1.5, Armor = 0.5, AnimSpeed = 1.5, Color = rgb(255, 40, 40),
				Announce = "APOCALYPSE!", Summon = { Mob = "Hellhound", Count = 3 }, Cleanse = true,
			},
		},
		Skills = {
			-- отключает 3 ближайшие башни на 3 с
			DisableTowers = { Interval = 10, Duration = 3, Radius = 45, Count = 3, FromPhase = 1 },
			-- боевой клич: ускоряет мобов рядом на 35%
			WarCry = { Interval = 8, Radius = 26, Haste = 0.35, Duration = 4, FromPhase = 3 },
		},
	},
}

return BossData
