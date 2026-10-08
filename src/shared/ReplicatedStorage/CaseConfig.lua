-- ReplicatedStorage. (ModuleScript) — общая таблица кейсов (сервер + клиент)
--   Currency / Price           — чем и сколько платить: "Cash" или "Gems" (папка Data). ЦЕНЫ ВРЕМЕННЫЕ
--   TokenCurrency / TokenPrice — можно открыть за сундучок из наград за время игры (Cases), тратится первым
--   Rates    — шансы редкостей (веса; сумма не обязана быть 100)
--   Pity     — гарантия: столько открытий подряд без этой редкости → следующая точно она
--   Cashback — дубликат: вернуть долю цены кейса в его валюте (0.3 = 30%)
--   Art      — картинка сундука из UIAtlasArt (chestHero / chestMythic)
--   Theme    — цвета карточки в окне: { верх, низ }, Accent — цвет лучей и свечения

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

local CaseConfig = {
	StarterUnits = { "Scout", "Archer" }, -- есть у каждого нового игрока
	Order = { "CoinCase", "GemCase" },     -- порядок в окне
}

CaseConfig.Cases = {
	-- за Cash: Common – Epic
	CoinCase = {
		Name = "Hero Chest",
		Currency = "Cash", Price = 500,
		TokenCurrency = "Cases", TokenPrice = 1,
		Rates = {
			{ Rarity = "Common", Weight = 55 },
			{ Rarity = "Rare", Weight = 35 },
			{ Rarity = "Epic", Weight = 10 },
		},
		Pity = { Epic = 20 },
		Cashback = { Common = 0.2, Rare = 0.35, Epic = 0.6 },
		Art = "chestHero",
		Theme = { rgb(255, 215, 110), rgb(235, 110, 30) },
		Accent = rgb(255, 225, 120),
		Button = "green",
	},
	-- за Gems: Epic – Mythic
	GemCase = {
		Name = "Mythic Chest",
		Currency = "Gems", Price = 60,
		Rates = {
			{ Rarity = "Epic", Weight = 80 },
			{ Rarity = "Legendary", Weight = 17 },
			{ Rarity = "Mythic", Weight = 3 },
		},
		Pity = { Legendary = 10, Mythic = 50 },
		Cashback = { Epic = 0.3, Legendary = 0.5, Mythic = 1 },
		Art = "chestMythic",
		Theme = { rgb(230, 150, 255), rgb(110, 35, 210) },
		Accent = rgb(240, 150, 255),
		Button = "pink",
	},
}

-- шанс редкости в процентах
function CaseConfig.Chance(def, rarity)
	local total, weight = 0, 0
	for _, e in ipairs(def.Rates) do
		total += e.Weight
		if e.Rarity == rarity then
			weight = e.Weight
		end
	end
	return total > 0 and weight / total * 100 or 0
end

return CaseConfig
