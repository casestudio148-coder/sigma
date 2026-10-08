-- ServerScriptService. (Script)
-- Открытие кейсов. Всё решает сервер: цена, списание, шанс, гарантия, выдача юнита и кэшбэк за дубликат.
-- Клиент присылает только id кейса и получает результат — по нему CaseUI проигрывает анимацию.
--   OpenCase:InvokeServer("CoinCase") → { ok, unit, rarity, new, copies, cashback, cashbackCurrency, ... }
-- Legendary и Mythic видит весь сервер: событие CaseAnnounce уходит всем, когда у игрока закончилась рулетка.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local CaseConfig = require(ReplicatedStorage:WaitForChild("CaseConfig"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local Guard = require(ServerScriptService:WaitForChild("Guard"))

local RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
local rng = Random.new()

local remote = ReplicatedStorage:FindFirstChild("OpenCase")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "OpenCase"
	remote.Parent = ReplicatedStorage
end

local announce = ReplicatedStorage:FindFirstChild("CaseAnnounce")
if not announce then
	announce = Instance.new("RemoteEvent")
	announce.Name = "CaseAnnounce"
	announce.Parent = ReplicatedStorage
end
local ANNOUNCE_DELAY = 12 -- секунд: примерно столько идёт рулетка и праздник у Legendary / Mythic

-- юниты по редкостям (из TowerData)
local pools = {}
for name, cfg in pairs(TowerData) do
	local rarity = cfg.Rarity or "Common"
	pools[rarity] = pools[rarity] or {}
	table.insert(pools[rarity], name)
end
for _, list in pairs(pools) do
	table.sort(list)
end

for caseId, def in pairs(CaseConfig.Cases) do
	for _, e in ipairs(def.Rates) do
		if not pools[e.Rarity] then
			warn(string.format("[Cases] %s: нет юнитов редкости %s — выпадет ближайшая ниже", caseId, e.Rarity))
		end
	end
end

-- редкость с учётом гарантии. pity — копия счётчиков, возвращается обновлённой
local function rollRarity(def, pity)
	for rarity in pairs(def.Pity or {}) do
		pity[rarity] = (pity[rarity] or 0) + 1
	end

	local total = 0
	for _, e in ipairs(def.Rates) do
		total += e.Weight
	end
	local x = rng:NextNumber() * total
	local rarity = def.Rates[#def.Rates].Rarity
	for _, e in ipairs(def.Rates) do
		x -= e.Weight
		if x <= 0 then
			rarity = e.Rarity
			break
		end
	end

	-- гарантия: давно не было редкости → она выпадает точно (берётся самая высокая из готовых)
	for r, need in pairs(def.Pity or {}) do
		if pity[r] >= need and RANK[r] > RANK[rarity] then
			rarity = r
		end
	end
	-- выпала редкость → её счётчик и счётчики ниже обнуляются
	for r in pairs(def.Pity or {}) do
		if RANK[rarity] >= RANK[r] then
			pity[r] = 0
		end
	end
	return rarity, pity
end

-- случайный юнит редкости; если таких нет — ближайшая редкость ниже из этого кейса
local function pickUnit(def, rarity)
	local r = rarity
	while r do
		local pool = pools[r]
		if pool and #pool > 0 then
			return pool[rng:NextInteger(1, #pool)], r
		end
		local lower = nil
		for _, e in ipairs(def.Rates) do
			if RANK[e.Rarity] < RANK[r] and (not lower or RANK[e.Rarity] > RANK[lower]) then
				lower = e.Rarity
			end
		end
		r = lower
	end
	return nil, nil
end

local function fail(reason)
	return { ok = false, reason = reason }
end

remote.OnServerInvoke = function(player, caseId)
	if not Guard.check(player, "OpenCase", 1, 3) then
		return fail("Slow down!")
	end
	if typeof(caseId) ~= "string" then
		Guard.flag(player, "OpenCase bad argument", 3)
		return fail("Bad request")
	end
	local def = CaseConfig.Cases[caseId]
	if not def then
		Guard.flag(player, "OpenCase unknown case", 3)
		return fail("Unknown case")
	end
	if not PlayerData.Get(player) then
		return fail("Your data is still loading...")
	end

	-- оплата: сначала жетон 🎁 (если кейс его принимает), иначе валюта кейса
	local payWith, cost = def.Currency, def.Price
	local token = def.TokenCurrency and PlayerData.Wallet(player, def.TokenCurrency)
	if token and token.Value >= (def.TokenPrice or 1) then
		payWith, cost = def.TokenCurrency, def.TokenPrice or 1
	end
	local wallet = PlayerData.Wallet(player, payWith)
	if not wallet or wallet.Value < cost then
		return fail("Not enough " .. payWith .. "!")
	end

	local rarity, pity = rollRarity(def, PlayerData.GetPity(player, caseId))
	local unit, finalRarity = pickUnit(def, rarity)
	if not unit then
		return fail("This case is empty")
	end

	-- дальше без пауз (yield): списание, выдача и кэшбэк идут одним куском, двойного открытия не будет
	wallet.Value -= cost
	PlayerData.SetPity(player, caseId, pity)
	local copies, isNew = PlayerData.AddUnit(player, unit)

	-- КЭШБЭК: дубликат возвращает долю цены кейса (Cashback в CaseConfig) в валюте кейса
	local cashback = 0
	if not isNew then
		local share = (def.Cashback and def.Cashback[finalRarity]) or 0
		cashback = math.floor(def.Price * share + 0.5)
		local back = PlayerData.Wallet(player, def.Currency)
		if cashback > 0 and back then
			back.Value += cashback
		end
	end

	-- объявление на весь сервер, когда игрок досмотрит рулетку
	if (RANK[finalRarity] or 0) >= 4 then
		task.delay(ANNOUNCE_DELAY, function()
			announce:FireAllClients({
				name = player.DisplayName,
				userId = player.UserId,
				unit = unit,
				rarity = finalRarity,
				case = caseId,
			})
		end)
	end

	return {
		ok = true,
		case = caseId,
		unit = unit,
		rarity = finalRarity,
		new = isNew,
		copies = copies,
		cashback = cashback,
		cashbackCurrency = def.Currency,
		paidWith = payWith,
		cost = cost,
	}
end
