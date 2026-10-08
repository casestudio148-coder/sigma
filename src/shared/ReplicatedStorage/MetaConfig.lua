-- ReplicatedStorage. (ModuleScript) — общие таблицы меню (сервер + клиент)
-- Здесь меняются награды, цены магазина, квесты и настройки. Промокоды — на сервере, в MetaService.

local MetaConfig = {}

-- ежедневные награды: 7 дней подряд, потом круг заново. Пропустил день — серия с начала
MetaConfig.Daily = {
	{ Cash = 200 },
	{ Gems = 5 },
	{ Cash = 400 },
	{ Cases = 1 },
	{ Gems = 15 },
	{ Cash = 1000 },
	{ Gems = 40, Cases = 2 },
}

-- МАГАЗИН (окно Shop: сверху сундуки, ниже гемы за Robux, ниже Cash за гемы)

-- Картинка Robux на кнопках цены. Сделаешь свою иконку — загрузи её и вставь ID сюда: "rbxassetid://123..."
MetaConfig.RobuxIcon = "rbxasset://textures/ui/common/robux.png"

-- Гемы за Robux. Чтобы покупка заработала:
-- Creator Hub → твоя игра → Monetization → Developer Products → Create
-- (цену ставь как в Robux ниже) → скопируй ID товара и вставь в ProductId.
-- Пока ProductId = 0, при нажатии будет подсказка вместо покупки.
-- Size — сколько кристаллов нарисовано на карточке (1-6)
MetaConfig.GemPacks = {
	{ Id = "Gems40",   Title = "40 Gems",    Gems = 40,   Robux = 25,  ProductId = 0, Size = 1 },
	{ Id = "Gems100",  Title = "100 Gems",   Gems = 100,  Robux = 49,  ProductId = 0, Size = 2 },
	{ Id = "Gems250",  Title = "250 Gems",   Gems = 250,  Robux = 99,  ProductId = 0, Size = 3, Tag = "POPULAR" },
	{ Id = "Gems700",  Title = "700 Gems",   Gems = 700,  Robux = 249, ProductId = 0, Size = 4, Tag = "+40%" },
	{ Id = "Gems1500", Title = "1,500 Gems", Gems = 1500, Robux = 499, ProductId = 0, Size = 5, Tag = "+50%" },
	{ Id = "Gems3500", Title = "3,500 Gems", Gems = 3500, Robux = 999, ProductId = 0, Size = 6, Tag = "BEST VALUE" },
}

-- Геймпасс «Instant Open» — пропуск анимации сундуков (кнопка SKIP при открытии).
-- Как включить: Creator Hub → твоя игра → Monetization → Passes → Create a Pass →
-- открой пасс → Sales → включи продажу, цена 40 → скопируй ID пасса и вставь в Id.
-- TestInStudio = true — в Studio пасс как будто куплен (проверить SKIP без покупки).
MetaConfig.SkipPass = { Id = 0, Robux = 40, TestInStudio = false }

-- Cash за гемы
MetaConfig.Shop = {
	{ Id = "Cash1", Title = "1,000 Cash", Icon = "coin", Give = { Cash = 1000 }, Cost = { Gems = 10 } },
	{ Id = "Cash6", Title = "6,000 Cash", Icon = "moneybag", Give = { Cash = 6000 }, Cost = { Gems = 50 }, Tag = "+20%" },
}

-- КВЕСТЫ
-- Stat — что считается:
--   Kills (враги), BossKills (боссы), Placed (поставил юнитов), Upgrades (улучшения), Abilities (способности),
--   Waves (волны), Matches (сыграл матчей), Wins (победы), HardWins (победы на Hard и Nightmare),
--   Summons (юниты из сундуков), Minutes (минут в игре), CashEarned (заработал Cash), Daily (забрал Daily)

-- ежедневные: каждый день у игрока QuestsPerDay штук из этого списка
MetaConfig.QuestsPerDay = 6
MetaConfig.Quests = {
	{ Id = "Kill50", Text = "Defeat 50 enemies", Stat = "Kills", Goal = 50, Reward = { Cash = 300 }, Icon = "skull" },
	{ Id = "Kill150", Text = "Defeat 150 enemies", Stat = "Kills", Goal = 150, Reward = { Cash = 700 }, Icon = "swords" },
	{ Id = "Kill300", Text = "Defeat 300 enemies", Stat = "Kills", Goal = 300, Reward = { Gems = 10 }, Icon = "explosion" },
	{ Id = "Boss1", Text = "Defeat a boss", Stat = "BossKills", Goal = 1, Reward = { Gems = 8 }, Icon = "demon" },
	{ Id = "Place10", Text = "Place 10 units", Stat = "Placed", Goal = 10, Reward = { Cash = 250 }, Icon = "flag" },
	{ Id = "Place25", Text = "Place 25 units", Stat = "Placed", Goal = 25, Reward = { Cash = 600 }, Icon = "pin" },
	{ Id = "Upgrade5", Text = "Upgrade units 5 times", Stat = "Upgrades", Goal = 5, Reward = { Cash = 300 }, Icon = "upgrade" },
	{ Id = "Upgrade15", Text = "Upgrade units 15 times", Stat = "Upgrades", Goal = 15, Reward = { Gems = 6 }, Icon = "upgrade" },
	{ Id = "Ability3", Text = "Use 3 abilities", Stat = "Abilities", Goal = 3, Reward = { Cash = 350 }, Icon = "lightning" },
	{ Id = "Ability10", Text = "Use 10 abilities", Stat = "Abilities", Goal = 10, Reward = { Gems = 8 }, Icon = "meteor" },
	{ Id = "Waves10", Text = "Clear 10 waves", Stat = "Waves", Goal = 10, Reward = { Cash = 400 }, Icon = "stopwatch" },
	{ Id = "Waves25", Text = "Clear 25 waves", Stat = "Waves", Goal = 25, Reward = { Gems = 8 }, Icon = "hourglass" },
	{ Id = "Play1", Text = "Play a match", Stat = "Matches", Goal = 1, Reward = { Cash = 200 }, Icon = "first" },
	{ Id = "Play3", Text = "Play 3 matches", Stat = "Matches", Goal = 3, Reward = { Cash = 600 }, Icon = "flag" },
	{ Id = "Win1", Text = "Win a match", Stat = "Wins", Goal = 1, Reward = { Gems = 15 }, Icon = "trophy" },
	{ Id = "Win2", Text = "Win 2 matches", Stat = "Wins", Goal = 2, Reward = { Cases = 1 }, Icon = "crown" },
	{ Id = "HardWin1", Text = "Win on Hard or Nightmare", Stat = "HardWins", Goal = 1, Reward = { Gems = 25 }, Icon = "strong" },
	{ Id = "Summon3", Text = "Get 3 units from chests", Stat = "Summons", Goal = 3, Reward = { Cases = 1 }, Icon = "summon" },
	{ Id = "Summon5", Text = "Get 5 units from chests", Stat = "Summons", Goal = 5, Reward = { Gems = 10 }, Icon = "chest" },
	{ Id = "Minutes15", Text = "Play for 15 minutes", Stat = "Minutes", Goal = 15, Reward = { Cash = 300 }, Icon = "stopwatch" },
	{ Id = "Minutes30", Text = "Play for 30 minutes", Stat = "Minutes", Goal = 30, Reward = { Gems = 8 }, Icon = "hourglass" },
	{ Id = "Cash1000", Text = "Earn 1,000 Cash", Stat = "CashEarned", Goal = 1000, Reward = { Gems = 5 }, Icon = "moneybag" },
	{ Id = "Daily1", Text = "Claim your Daily reward", Stat = "Daily", Goal = 1, Reward = { Cash = 200 }, Icon = "calendar" },
}

-- еженедельные: каждую неделю WeeklyPerWeek штук, задания больше — награды тоже
MetaConfig.WeeklyPerWeek = 4
MetaConfig.WeeklyQuests = {
	{ Id = "W_Kill2000", Text = "Defeat 2,000 enemies", Stat = "Kills", Goal = 2000, Reward = { Gems = 40 }, Icon = "skull" },
	{ Id = "W_Boss10", Text = "Defeat 10 bosses", Stat = "BossKills", Goal = 10, Reward = { Gems = 50 }, Icon = "demon" },
	{ Id = "W_Place150", Text = "Place 150 units", Stat = "Placed", Goal = 150, Reward = { Cash = 4000 }, Icon = "flag" },
	{ Id = "W_Upgrade80", Text = "Upgrade units 80 times", Stat = "Upgrades", Goal = 80, Reward = { Cases = 3 }, Icon = "upgrade" },
	{ Id = "W_Ability50", Text = "Use 50 abilities", Stat = "Abilities", Goal = 50, Reward = { Gems = 40 }, Icon = "lightning" },
	{ Id = "W_Waves150", Text = "Clear 150 waves", Stat = "Waves", Goal = 150, Reward = { Gems = 45 }, Icon = "hourglass" },
	{ Id = "W_Play15", Text = "Play 15 matches", Stat = "Matches", Goal = 15, Reward = { Cases = 3 }, Icon = "first" },
	{ Id = "W_Win8", Text = "Win 8 matches", Stat = "Wins", Goal = 8, Reward = { Gems = 60 }, Icon = "trophy" },
	{ Id = "W_HardWin3", Text = "Win 3 times on Hard or Nightmare", Stat = "HardWins", Goal = 3, Reward = { Gems = 80 }, Icon = "crown" },
	{ Id = "W_Summon20", Text = "Get 20 units from chests", Stat = "Summons", Goal = 20, Reward = { Gems = 50 }, Icon = "summon" },
	{ Id = "W_Minutes180", Text = "Play for 3 hours in total", Stat = "Minutes", Goal = 180, Reward = { Cases = 4 }, Icon = "stopwatch" },
	{ Id = "W_Daily5", Text = "Claim Daily reward 5 days", Stat = "Daily", Goal = 5, Reward = { Gems = 50 }, Icon = "calendar" },
	{ Id = "W_Cash15000", Text = "Earn 15,000 Cash", Stat = "CashEarned", Goal = 15000, Reward = { Gems = 40 }, Icon = "moneybag" },
}

-- кланы
MetaConfig.Clan = {
	MinName = 3,
	MaxName = 16,
	MaxMembers = 20,
	CreateCost = { Cash = 1000 },
}

-- настройки (true = включено)
MetaConfig.Settings = {
	{ Id = "Effects", Text = "Full effects", Hint = "Turn off if the game lags", Icon = "fire", Default = true },
	{ Id = "Shake", Text = "Camera shake", Hint = "Screen shakes on big hits", Icon = "explosion", Default = true },
	{ Id = "Sparkles", Text = "Menu sparkles", Hint = "Little stars in windows", Icon = "sparkle", Default = true },
	{ Id = "Music", Text = "Sounds", Hint = "Game sounds and music", Icon = "horn", Default = true },
}

function MetaConfig.findShop(id)
	for _, item in ipairs(MetaConfig.Shop) do
		if item.Id == id then return item end
	end
	return nil
end

function MetaConfig.findQuest(id)
	for _, q in ipairs(MetaConfig.Quests) do
		if q.Id == id then return q end
	end
	for _, q in ipairs(MetaConfig.WeeklyQuests) do
		if q.Id == id then return q end
	end
	return nil
end

function MetaConfig.findGemPack(id)
	for _, p in ipairs(MetaConfig.GemPacks) do
		if p.Id == id then return p end
	end
	return nil
end

-- номер дня (UTC) — общий для сервера и клиента
function MetaConfig.day(now)
	return math.floor((now or os.time()) / 86400)
end

-- номер недели (UTC), новая неделя начинается в понедельник
function MetaConfig.week(now)
	return math.floor(((now or os.time()) / 86400 + 3) / 7)
end
function MetaConfig.weekEndsAt(week)
	return (week + 1) * 7 * 86400 - 3 * 86400
end

return MetaConfig
