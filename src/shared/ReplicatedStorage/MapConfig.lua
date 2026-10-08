-- ReplicatedStorage.MapConfig (ModuleScript) — ОДИНАКОВЫЙ в хабе и в игре
-- Список карт. Порталы в хабе = карты, сложность игроки выбирают голосованием в начале матча.
-- Карты строит скрипт MapService в месте с матчем.

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local MapConfig = {
	-- порядок = порталы слева направо и список в кнопке PLAY (от лёгких к трудным)
	Order = { "Valley", "Candy", "Canyon", "Frozen", "Pirate", "Graveyard", "Volcano", "Space" },
	Default = "Valley",

	-- тест в Studio (в Studio телепорта из хаба нет): какую карту строить.
	-- Впиши любую из списка выше или "Random" — случайная.
	StudioMap = "Volcano",

	-- где строится карта. Далеко от середины мира, чтобы не мешала старая карта, если она осталась.
	Origin = Vector3.new(0, 0, 3000),

	-- уровни карт. Действуют ВМЕСТЕ со сложностью, которую выбирают голосованием в матче.
	--   HealthMult — во сколько раз крепче мобы, SpeedMult — быстрее,
	--   RewardMult — во сколько раз больше Cash и Gems в конце матча.
	TierOrder = { "Easy", "Normal", "Hard", "Insane" },
	Tiers = {
		Easy = { Name = "EASY", Color = rgb(90, 215, 100), HealthMult = 1, SpeedMult = 1, RewardMult = 1 },
		Normal = { Name = "NORMAL", Color = rgb(80, 165, 255), HealthMult = 1.25, SpeedMult = 1, RewardMult = 1.3 },
		Hard = { Name = "HARD", Color = rgb(255, 145, 50), HealthMult = 1.6, SpeedMult = 1.05, RewardMult = 1.7 },
		Insane = { Name = "INSANE", Color = rgb(235, 60, 95), HealthMult = 2.1, SpeedMult = 1.1, RewardMult = 2.3 },
	},
}

MapConfig.Valley = {
	Tier = "Easy",
	Name = "Sunny Valley", Tagline = "Green hills, river and a castle",
	Color = rgb(110, 210, 90), Icon = "sprout", Button = "green",
}
MapConfig.Canyon = {
	Tier = "Normal",
	Name = "Desert Canyon", Tagline = "Hot sands and ancient ruins",
	Color = rgb(240, 160, 70), Icon = "hourglass", Button = "orange",
}
MapConfig.Frozen = {
	Tier = "Normal",
	Name = "Frozen Fortress", Tagline = "Snow, ice and frozen lakes",
	Color = rgb(120, 200, 255), Icon = "snowflake", Button = "cyan",
}
MapConfig.Volcano = {
	Tier = "Insane",
	Name = "Lava Volcano", Tagline = "Rivers of lava under a red sky",
	Color = rgb(255, 90, 40), Icon = "fire", Button = "red",
}
MapConfig.Graveyard = {
	Tier = "Hard",
	Name = "Haunted Graveyard", Tagline = "Fog, tombs and glowing pumpkins",
	Color = rgb(150, 110, 220), Icon = "skull", Button = "purple",
}
MapConfig.Pirate = {
	Tier = "Hard",
	Name = "Pirate Cove", Tagline = "Palm trees, treasure and a ship",
	Color = rgb(60, 180, 200), Icon = "trident", Button = "blue",
}
MapConfig.Candy = {
	Tier = "Easy",
	Name = "Candy Land", Tagline = "Sweets, cakes and a chocolate river",
	Color = rgb(255, 130, 200), Icon = "heart", Button = "pink",
}
MapConfig.Space = {
	Tier = "Insane",
	Name = "Space Station", Tagline = "Neon base among the stars",
	Color = rgb(150, 110, 255), Icon = "blackhole", Button = "night",
}

-- уровень карты (таблица из Tiers); если не указан — Easy
function MapConfig.tier(id)
	local m = MapConfig.get(id)
	return MapConfig.Tiers[(m and m.Tier) or "Easy"] or MapConfig.Tiers.Easy
end

function MapConfig.get(id)
	if typeof(id) == "string" and MapConfig[id] and table.find(MapConfig.Order, id) then
		return MapConfig[id]
	end
	return nil
end

return MapConfig
