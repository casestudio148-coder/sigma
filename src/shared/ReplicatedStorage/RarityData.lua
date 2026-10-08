-- ReplicatedStorage. (ModuleScript)
-- Шансы гачи, цвета редкостей и функция крутки.
-- Roll вызывать ТОЛЬКО на сервере; pity хранить в DataStore игрока.

local RarityData = {
	Order = { "Common", "Rare", "Epic", "Legendary", "Mythic" },

	Common    = { Rate = 55,  Color = Color3.fromRGB(190, 190, 190) },
	Rare      = { Rate = 28,  Color = Color3.fromRGB(70, 140, 255) },
	Epic      = { Rate = 12,  Color = Color3.fromRGB(170, 80, 255) },
	Legendary = { Rate = 4.5, Color = Color3.fromRGB(255, 170, 30) },
	Mythic    = { Rate = 0.5, Color = Color3.fromRGB(255, 50, 90) },

	-- гарантия: на какой крутке без дропа выпадет редкость не ниже указанной
	Pity = { Epic = 10, Legendary = 60, Mythic = 250 },
}

local RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }

-- pity = { Epic = n, Legendary = n, Mythic = n } (счётчики, функция их обновляет)
-- возвращает: название юнита, редкость
function RarityData.Roll(TowerData, pity)
	pity = pity or {}
	pity.Epic = (pity.Epic or 0) + 1
	pity.Legendary = (pity.Legendary or 0) + 1
	pity.Mythic = (pity.Mythic or 0) + 1

	local total = 0
	for _, r in ipairs(RarityData.Order) do
		total += RarityData[r].Rate
	end

	local roll = math.random() * total
	local rarity = "Common"
	for _, r in ipairs(RarityData.Order) do
		roll -= RarityData[r].Rate
		if roll <= 0 then
			rarity = r
			break
		end
	end

	if pity.Mythic >= RarityData.Pity.Mythic then
		rarity = "Mythic"
	elseif pity.Legendary >= RarityData.Pity.Legendary and RANK[rarity] < 4 then
		rarity = "Legendary"
	elseif pity.Epic >= RarityData.Pity.Epic and RANK[rarity] < 3 then
		rarity = "Epic"
	end

	if RANK[rarity] >= 3 then pity.Epic = 0 end
	if RANK[rarity] >= 4 then pity.Legendary = 0 end
	if RANK[rarity] >= 5 then pity.Mythic = 0 end

	local pool = {}
	for name, cfg in pairs(TowerData) do
		if cfg.Rarity == rarity then
			table.insert(pool, name)
		end
	end
	if #pool == 0 then return nil, rarity end

	return pool[math.random(1, #pool)], rarity
end

return RarityData
