-- ReplicatedStorage. (ModuleScript)
-- Сложности: количество волн, сила мобов, стартовые монеты, HP базы и награда за матч.
-- Монет за матч (на каждого игрока): Easy ~7 900, Normal ~9 900, Hard ~13 500, Nightmare ~17 300.
-- StartCoins для теста не завышай: режим разработчика даёт юнитов, а не монеты.
-- Награда за матч (постоянная валюта Cash / Gems из DataService):
--   Cash = CashPerWave * пройденные волны + VictoryCash при победе
--   Gems = VictoryGems только при победе

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local DifficultyData = {
	Order = { "Easy", "Normal", "Hard", "Nightmare" },
	Default = "Normal",

	Easy = {
		Name = "Easy", Icon = "🌱", Color = rgb(80, 200, 95),
		Waves = 15, HealthMult = 0.75, SpeedMult = 0.9,
		BaseHP = 300, StartCoins = 600,
		KillRewardMult = 2.6, WaveRewardMult = 3.0,
		CashPerWave = 8, VictoryCash = 100, VictoryGems = 0,
	},
	Normal = {
		Name = "Normal", Icon = "⚔️", Color = rgb(70, 140, 255),
		Waves = 20, HealthMult = 1.15, SpeedMult = 1,
		BaseHP = 200, StartCoins = 450,
		KillRewardMult = 2.0, WaveRewardMult = 2.6,
		CashPerWave = 12, VictoryCash = 250, VictoryGems = 3,
	},
	Hard = {
		Name = "Hard", Icon = "🔥", Color = rgb(240, 120, 40),
		Waves = 25, HealthMult = 1.8, SpeedMult = 1.1,
		BaseHP = 150, StartCoins = 350,
		KillRewardMult = 1.8, WaveRewardMult = 2.4,
		CashPerWave = 20, VictoryCash = 600, VictoryGems = 8,
	},
	Nightmare = {
		Name = "Nightmare", Icon = "💀", Color = rgb(170, 50, 230),
		Waves = 30, HealthMult = 2.8, SpeedMult = 1.2,
		BaseHP = 100, StartCoins = 300,
		KillRewardMult = 1.6, WaveRewardMult = 2.3,
		CashPerWave = 35, VictoryCash = 1400, VictoryGems = 20,
	},
}

return DifficultyData
