-- ServerScriptService.MetaService (Script)
-- Всё «вокруг матча»: ежедневные награды, промокоды, магазин, ежедневные квесты, кланы, настройки.
-- Всё решает сервер. Данные игрока хранятся в PlayerData.Meta (сохраняются вместе с валютой).
-- Квесты считаются сами, другие скрипты менять не нужно: сервер следит за мобами, башнями, волнами и кейсами.
--
-- Клиент: RemoteFunction "Meta" — Meta:InvokeServer(действие, ...) → { ok, msg, state }
--         RemoteEvent "MetaPush" — сервер присылает обновлённое состояние (например, прогресс квестов)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local MetaConfig = require(ReplicatedStorage:WaitForChild("MetaConfig"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local Guard = require(ServerScriptService:WaitForChild("Guard"))

---------------------------------------------------------------- ПРОМОКОДЫ (только здесь, игроки их не видят)
-- Регистр не важен. Каждый код игрок может ввести один раз.
local CODES = {
	RELEASE = { Gems = 50 },
	TOWERS = { Cash = 1000 },
	CHEST = { Cases = 2 },
}

---------------------------------------------------------------- remotes

local function remote(class, name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new(class)
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local metaRemote = remote("RemoteFunction", "Meta")
local pushEvent = remote("RemoteEvent", "MetaPush")
print("[MetaService] запущен, меню работает")

---------------------------------------------------------------- помощники

local function give(player, bundle)
	for currency, amount in pairs(bundle or {}) do
		PlayerData.Give(player, currency, amount)
	end
end

local function canPay(player, cost)
	for currency, amount in pairs(cost or {}) do
		local w = PlayerData.Wallet(player, currency)
		if not w or w.Value < amount then
			return false, currency
		end
	end
	return true
end

local function pay(player, cost)
	for currency, amount in pairs(cost or {}) do
		local w = PlayerData.Wallet(player, currency)
		w.Value -= amount
	end
end

local function today()
	return MetaConfig.day(os.time())
end

---------------------------------------------------------------- квесты

local function thisWeek()
	return MetaConfig.week(os.time())
end

-- список квестов на период: новый период — новый набор (у каждого игрока свой).
-- Если квестов в списке меньше, чем нужно (например, добавили новые), список дополняется.
local function questList(player, meta, key, period, defs, count, salt)
	local box = meta[key]
	if type(box) ~= "table" or box.period ~= period or type(box.list) ~= "table" then
		box = { period = period, list = {} }
		meta[key] = box
	end
	-- убираем квесты, которых больше нет в MetaConfig
	for i = #box.list, 1, -1 do
		if not MetaConfig.findQuest(box.list[i].id) then
			table.remove(box.list, i)
		end
	end
	if #box.list < count then
		local have = {}
		for _, q in ipairs(box.list) do have[q.id] = true end
		local pool = {}
		for _, q in ipairs(defs) do
			if not have[q.Id] then table.insert(pool, q.Id) end
		end
		local rng = Random.new(period * 7919 + salt + (player.UserId % 100000))
		while #box.list < count and #pool > 0 do
			local id = table.remove(pool, rng:NextInteger(1, #pool))
			table.insert(box.list, { id = id, progress = 0, claimed = false })
		end
	end
	return box.list
end

local function questsFor(player, meta)
	return questList(player, meta, "quests2", today(), MetaConfig.Quests, MetaConfig.QuestsPerDay, 0)
end

local function weeklyFor(player, meta)
	return questList(player, meta, "weekly", thisWeek(), MetaConfig.WeeklyQuests, MetaConfig.WeeklyPerWeek, 31337)
end

-- все текущие квесты игрока (ежедневные + недельные)
local function eachQuest(player, meta, f)
	for _, q in ipairs(questsFor(player, meta)) do f(q) end
	for _, q in ipairs(weeklyFor(player, meta)) do f(q) end
end

---------------------------------------------------------------- состояние для клиента

local function stateFor(player)
	local meta = PlayerData.Meta(player)
	if not meta then return nil end
	local d = today()
	meta.daily = type(meta.daily) == "table" and meta.daily or { last = -1, streak = 0 }
	local daily = meta.daily
	local claimedToday = daily.last == d
	local nextStreak = (daily.last == d - 1) and (daily.streak % #MetaConfig.Daily) + 1 or 1
	if claimedToday then nextStreak = daily.streak end

	local function pack(list)
		local out = {}
		for _, q in ipairs(list) do
			local def = MetaConfig.findQuest(q.id)
			if def then
				table.insert(out, { id = q.id, progress = q.progress, goal = def.Goal, claimed = q.claimed })
			end
		end
		return out
	end
	local quests = pack(questsFor(player, meta))
	local weekly = pack(weeklyFor(player, meta))

	return {
		day = d,
		nextDayAt = (d + 1) * 86400,
		daily = { streak = daily.streak or 0, claimedToday = claimedToday, nextIndex = nextStreak },
		quests = quests,
		weekly = weekly,
		nextWeekAt = MetaConfig.weekEndsAt(thisWeek()),
		clan = meta.clan,
		settings = type(meta.settings) == "table" and meta.settings or {},
	}
end

local pushQueued = {}
local function push(player)
	if pushQueued[player] then return end
	pushQueued[player] = true
	task.delay(0.5, function()
		pushQueued[player] = nil
		if player.Parent then
			local st = stateFor(player)
			if st then pushEvent:FireClient(player, st) end
		end
	end)
end

local function bump(player, stat, amount)
	local meta = PlayerData.Meta(player)
	if not meta then return end
	local changed = false
	eachQuest(player, meta, function(q)
		local def = MetaConfig.findQuest(q.id)
		if def and def.Stat == stat and not q.claimed and q.progress < def.Goal then
			q.progress = math.min(def.Goal, q.progress + (amount or 1))
			changed = true
		end
	end)
	if changed then push(player) end
end

local function bumpAll(stat, amount)
	for _, p in ipairs(Players:GetPlayers()) do
		bump(p, stat, amount)
	end
end

---------------------------------------------------------------- кланы
-- Хранятся в своём DataStore. В Studio без доступа к API — в памяти сервера (для теста).

local clanStore = nil
pcall(function()
	clanStore = DataStoreService:GetDataStore("Clans_v1")
end)
local memoryClans = {}
-- в Studio кланы живут только в памяти (как и прогресс игрока в тестовом режиме)
local useMemory = RunService:IsStudio()

-- маленькие буквы и для русских имён (string.lower понимает только латиницу)
local function lowerName(name)
	local out = {}
	for _, code in utf8.codes(name) do
		if code >= 0x410 and code <= 0x42F then
			code += 0x20
		elseif code == 0x401 then
			code = 0x451
		elseif code >= 65 and code <= 90 then
			code += 32
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

local function clanKey(name)
	return "c_" .. lowerName(name)
end

-- f(old) → new (или nil, чтобы не менять); вернёт ok, результат
local function updateClan(name, f)
	if not useMemory and clanStore then
		local ok, result = pcall(function()
			return clanStore:UpdateAsync(clanKey(name), function(old)
				return f(old)
			end)
		end)
		if ok then return true, result end
		warn("[MetaService] кланы, DataStore: " .. tostring(result))
		return false, nil
	end
	local new = f(memoryClans[clanKey(name)])
	if new ~= nil then memoryClans[clanKey(name)] = new end
	return true, memoryClans[clanKey(name)]
end

local function readClan(name)
	local snapshot
	local ok = updateClan(name, function(old)
		snapshot = old
		return nil
	end)
	return ok, snapshot
end

local CLAN_MAX = 12 -- самое длинное имя клана (символов)

-- имя клана: латиница, русские буквы, цифры, пробел, _ и -
local function validName(name)
	if typeof(name) ~= "string" or #name > 100 then return nil end
	name = string.gsub(name, "^%s+", "")
	name = string.gsub(name, "%s+$", "")
	name = string.gsub(name, "%s+", " ")
	local len = utf8.len(name)
	local cfg = MetaConfig.Clan
	if not len or len < cfg.MinName or len > math.min(cfg.MaxName or 12, CLAN_MAX) then return nil end
	for _, code in utf8.codes(name) do
		local ok = (code < 128 and string.match(string.char(code), "[%w _%-]") ~= nil)
			or (code >= 0x400 and code <= 0x4FF) -- кириллица
			or (code >= 0xC0 and code <= 0x24F) -- латиница с точками и чёрточками
		if not ok then return nil end
	end
	return name
end

-- фильтр Roblox: имя клана видят другие игроки, поэтому плохие слова не пропускаем
local function filterOk(player, name)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(name, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		return RunService:IsStudio() -- в Studio фильтр иногда недоступен — пропускаем
	end
	return result == name
end

local function clanInfo(name)
	local ok, clan = readClan(name)
	if not ok or type(clan) ~= "table" then return nil end
	local members = {}
	for _, m in pairs(clan.members or {}) do
		table.insert(members, m)
	end
	table.sort(members)
	return { name = clan.name, owner = clan.ownerName, members = members, max = MetaConfig.Clan.MaxMembers }
end

-- тег клана над головой: «[MOGG] Ivan»
local function applyNameTag(player)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local clan = player:GetAttribute("Clan")
	hum.DisplayName = (typeof(clan) == "string" and clan ~= "") and ("[" .. clan .. "] " .. player.DisplayName) or player.DisplayName
end

local function setClanTag(player, name)
	player:SetAttribute("Clan", name)
	applyNameTag(player)
end

---------------------------------------------------------------- действия

local ACTIONS = {}

function ACTIONS.state(player)
	return { ok = true }
end

function ACTIONS.daily(player)
	local meta = PlayerData.Meta(player)
	local d = today()
	local daily = meta.daily or { last = -1, streak = 0 }
	if daily.last == d then
		return { ok = false, msg = "Come back tomorrow!" }
	end
	local streak = (daily.last == d - 1) and (daily.streak % #MetaConfig.Daily) + 1 or 1
	meta.daily = { last = d, streak = streak }
	give(player, MetaConfig.Daily[streak])
	bump(player, "Daily", 1)
	return { ok = true, msg = "Day " .. streak .. " reward!", reward = MetaConfig.Daily[streak] }
end

function ACTIONS.redeem(player, code)
	if typeof(code) ~= "string" or #code > 30 then
		return { ok = false, msg = "Wrong code" }
	end
	code = string.upper((string.gsub(code, "%s", "")))
	local reward = CODES[code]
	if not reward then
		return { ok = false, msg = "Wrong code" }
	end
	local meta = PlayerData.Meta(player)
	meta.codes = type(meta.codes) == "table" and meta.codes or {}
	if meta.codes[code] then
		return { ok = false, msg = "Already used!" }
	end
	meta.codes[code] = true
	give(player, reward)
	return { ok = true, msg = "Code activated!", reward = reward }
end

function ACTIONS.buy(player, id)
	local item = typeof(id) == "string" and MetaConfig.findShop(id)
	if not item or not item.Cost then
		return { ok = false, msg = "Not for sale" }
	end
	local ok, missing = canPay(player, item.Cost)
	if not ok then
		return { ok = false, msg = "Not enough " .. tostring(missing) .. "!" }
	end
	pay(player, item.Cost)
	give(player, item.Give)
	return { ok = true, msg = "Bought " .. item.Title .. "!", reward = item.Give }
end

function ACTIONS.quest(player, id)
	local meta = PlayerData.Meta(player)
	local found = nil
	eachQuest(player, meta, function(q)
		if q.id == id then found = q end
	end)
	if not found then return { ok = false, msg = "No such quest" } end
	local def = MetaConfig.findQuest(id)
	if found.claimed then return { ok = false, msg = "Already claimed" } end
	if not def or found.progress < def.Goal then return { ok = false, msg = "Not done yet" } end
	found.claimed = true
	give(player, def.Reward)
	return { ok = true, msg = "Quest complete!", reward = def.Reward }
end

function ACTIONS.settings(player, values)
	if typeof(values) ~= "table" then return { ok = false } end
	local meta = PlayerData.Meta(player)
	local clean = {}
	for _, s in ipairs(MetaConfig.Settings) do
		if typeof(values[s.Id]) == "boolean" then
			clean[s.Id] = values[s.Id]
		end
	end
	meta.settings = clean
	return { ok = true }
end

function ACTIONS.clanInfo(player)
	local meta = PlayerData.Meta(player)
	if not meta.clan then return { ok = true, clan = nil } end
	local info = clanInfo(meta.clan)
	if not info then
		meta.clan = nil
		setClanTag(player, nil)
	end
	return { ok = true, clan = info }
end

function ACTIONS.clanCreate(player, rawName)
	local meta = PlayerData.Meta(player)
	if meta.clan then return { ok = false, msg = "Leave your clan first" } end
	local name = validName(rawName)
	if not name then
		return { ok = false, msg = string.format("Name: %d-%d letters or numbers", MetaConfig.Clan.MinName, math.min(MetaConfig.Clan.MaxName or 12, CLAN_MAX)) }
	end
	local ok, missing = canPay(player, MetaConfig.Clan.CreateCost)
	if not ok then return { ok = false, msg = "Not enough " .. tostring(missing) .. "!" } end
	if not filterOk(player, name) then return { ok = false, msg = "This name is not allowed" } end

	local taken = false
	local done = updateClan(name, function(old)
		if old ~= nil then
			taken = true
			return nil
		end
		return {
			name = name,
			owner = player.UserId,
			ownerName = player.DisplayName,
			members = { [tostring(player.UserId)] = player.DisplayName },
			created = os.time(),
		}
	end)
	if not done then return { ok = false, msg = "Server busy, try again" } end
	if taken then return { ok = false, msg = "This name is taken" } end
	pay(player, MetaConfig.Clan.CreateCost)
	meta.clan = name
	setClanTag(player, name)
	return { ok = true, msg = "Clan created!", clan = clanInfo(name) }
end

function ACTIONS.clanJoin(player, rawName)
	local meta = PlayerData.Meta(player)
	if meta.clan then return { ok = false, msg = "Leave your clan first" } end
	local name = validName(rawName)
	if not name then return { ok = false, msg = "Clan not found" } end
	local status = "missing"
	local done = updateClan(name, function(old)
		if type(old) ~= "table" then return nil end
		local count = 0
		for _ in pairs(old.members or {}) do count += 1 end
		if count >= MetaConfig.Clan.MaxMembers then
			status = "full"
			return nil
		end
		old.members = old.members or {}
		old.members[tostring(player.UserId)] = player.DisplayName
		status = "ok"
		return old
	end)
	if not done then return { ok = false, msg = "Server busy, try again" } end
	if status == "missing" then return { ok = false, msg = "Clan not found" } end
	if status == "full" then return { ok = false, msg = "Clan is full" } end
	local info = clanInfo(name)
	meta.clan = info and info.name or name
	setClanTag(player, meta.clan)
	return { ok = true, msg = "Welcome to " .. meta.clan .. "!", clan = info }
end

function ACTIONS.clanLeave(player)
	local meta = PlayerData.Meta(player)
	local name = meta.clan
	if not name then return { ok = false, msg = "You are not in a clan" } end
	updateClan(name, function(old)
		if type(old) ~= "table" then return nil end
		old.members = old.members or {}
		old.members[tostring(player.UserId)] = nil
		if old.owner == player.UserId then
			-- лидерство переходит к любому оставшемуся
			old.owner, old.ownerName = nil, nil
			for id, n in pairs(old.members) do
				old.owner, old.ownerName = tonumber(id), n
				break
			end
		end
		return old
	end)
	meta.clan = nil
	setClanTag(player, nil)
	return { ok = true, msg = "You left the clan" }
end

metaRemote.OnServerInvoke = function(player, action, ...)
	if not Guard.check(player, "Meta", 3, 6) then
		return { ok = false, msg = "Slow down!" }
	end
	if typeof(action) ~= "string" or not ACTIONS[action] then
		Guard.flag(player, "Meta bad action", 2)
		return { ok = false, msg = "Bad request" }
	end
	if not PlayerData.Meta(player) then
		return { ok = false, msg = "Loading..." }
	end
	if player:GetAttribute("HubTeleporting") or player:GetAttribute("Teleporting") then
		return { ok = false, msg = "Teleporting..." }
	end
	local ok, result = pcall(ACTIONS[action], player, ...)
	if not ok then
		warn("[MetaService] " .. action .. ": " .. tostring(result))
		result = { ok = false, msg = "Something went wrong" }
	end
	result.state = stateFor(player)
	return result
end

---------------------------------------------------------------- покупки за Robux

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or not PlayerData.Meta(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- игрок улетает в другое место: покупку выдаст следующий сервер (Roblox пришлёт её снова)
	if player:GetAttribute("HubTeleporting") or player:GetAttribute("Teleporting") then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local meta = PlayerData.Meta(player)
	meta.receipts = type(meta.receipts) == "table" and meta.receipts or {}
	if meta.receipts[receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	for _, pack in ipairs(MetaConfig.GemPacks) do
		if pack.ProductId and pack.ProductId ~= 0 and pack.ProductId == receipt.ProductId then
			give(player, { Gems = pack.Gems })
			meta.receipts[receipt.PurchaseId] = true
			PlayerData.Save(player)
			push(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

---------------------------------------------------------------- счётчики квестов (без правок других скриптов)

-- папка в Workspace: в матче она есть, в хабе её нет — тогда этот счётчик просто не нужен
local function whenFolder(name, fn)
	local f = workspace:FindFirstChild(name)
	if f then
		fn(f)
		return
	end
	local conn
	conn = workspace.ChildAdded:Connect(function(child)
		if child.Name == name then
			conn:Disconnect()
			fn(child)
		end
	end)
end

-- враги: любой убитый моб засчитывается всем игрокам (игра кооперативная)
whenFolder("Mobs", function(mobs) mobs.ChildAdded:Connect(function(mob)
		local hum = mob:WaitForChild("Humanoid", 5)
		if hum then
			hum.Died:Once(function()
				bumpAll("Kills", 1)
				if mob:GetAttribute("BossId") then
					bumpAll("BossKills", 1)
				end
			end)
		end
	end) end)

-- поставленные и улучшенные юниты
whenFolder("Towers", function(towers) towers.ChildAdded:Connect(function(tower)
		task.wait()
		local owner = Players:GetPlayerByUserId(tower:GetAttribute("OwnerId") or 0)
		if not owner then return end
		bump(owner, "Placed", 1)
		local last = tower:GetAttribute("Level") or 0
		tower:GetAttributeChangedSignal("Level"):Connect(function()
			local lv = tower:GetAttribute("Level") or 0
			if lv > last then
				bump(owner, "Upgrades", lv - last)
			end
			last = lv
		end)
		-- способность: время готовности сдвинулось вперёд
		local readyAt = tower:GetAttribute("AbilityReadyAt") or 0
		tower:GetAttributeChangedSignal("AbilityReadyAt"):Connect(function()
			local now = tower:GetAttribute("AbilityReadyAt") or 0
			if now > readyAt then
				bump(owner, "Abilities", 1)
			end
			readyAt = now
		end)
	end) end)

-- начало матча
workspace:GetAttributeChangedSignal("Phase"):Connect(function()
	if workspace:GetAttribute("Phase") == "Playing" then
		bumpAll("Matches", 1)
	end
end)

-- минуты в игре
task.spawn(function()
	while true do
		task.wait(60)
		bumpAll("Minutes", 1)
	end
end)

-- волны и победа
local lastWave = workspace:GetAttribute("Wave") or 0
workspace:GetAttributeChangedSignal("Wave"):Connect(function()
	local w = workspace:GetAttribute("Wave") or 0
	if workspace:GetAttribute("Phase") == "Playing" and w > lastWave and lastWave > 0 then
		bumpAll("Waves", w - lastWave)
	end
	lastWave = w
end)
workspace:GetAttributeChangedSignal("MatchOver"):Connect(function()
	if workspace:GetAttribute("MatchOver") ~= true then return end
	task.wait(0.5)
	local status = workspace:GetAttribute("StatusText") or ""
	local hp = workspace:GetAttribute("BaseHP") or 0
	if string.find(status, "VICTORY") or hp > 0 then
		bumpAll("Waves", 1) -- последняя волна
		bumpAll("Wins", 1)
		local diff = workspace:GetAttribute("Difficulty")
		if diff == "Hard" or diff == "Nightmare" then
			bumpAll("HardWins", 1)
		end
	end
end)

-- юниты из кейсов: растёт общее число копий в Data.Units
local function watchSummons(player)
	task.spawn(function()
		local data = player:WaitForChild("Data", 60)
		-- заработанный Cash (только прибавка)
		local cash = data and data:WaitForChild("Cash", 10)
		if cash then
			local lastCash = cash.Value
			cash.Changed:Connect(function()
				if cash.Value > lastCash then
					bump(player, "CashEarned", cash.Value - lastCash)
				end
				lastCash = cash.Value
			end)
		end
		local units = data and data:WaitForChild("Units", 10)
		if not units then return end
		local function total()
			local n = 0
			for _, v in ipairs(units:GetChildren()) do
				if v:IsA("IntValue") then n += v.Value end
			end
			return n
		end
		local last = total()
		local function check()
			local now = total()
			if now > last then
				bump(player, "Summons", now - last)
			end
			last = now
		end
		local function hook(v)
			if v:IsA("IntValue") then v.Changed:Connect(check) end
		end
		for _, v in ipairs(units:GetChildren()) do hook(v) end
		units.ChildAdded:Connect(function(v)
			hook(v)
			check()
		end)
	end)
end

---------------------------------------------------------------- геймпасс Instant Open (пропуск анимации сундуков)
-- Сервер ставит игроку атрибут SkipPass = true, если пасс куплен. CaseUI по нему показывает рабочую кнопку SKIP.

local function skipPassId()
	local p = MetaConfig.SkipPass
	return (typeof(p) == "table" and tonumber(p.Id)) or 0
end

-- есть ли пасс (Roblox иногда не отвечает с первого раза — пробуем 3 раза)
local function ownsSkipPass(player, id)
	for attempt = 1, 3 do
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
		end)
		if ok then return owns == true end
		if not player.Parent then return false end
		task.wait(attempt * 2)
	end
	return false
end

local function checkSkipPass(player)
	local p = MetaConfig.SkipPass
	if typeof(p) ~= "table" then return end
	if RunService:IsStudio() and p.TestInStudio then
		player:SetAttribute("SkipPass", true)
		return
	end
	local id = skipPassId()
	if id == 0 then return end
	if ownsSkipPass(player, id) and player.Parent then
		player:SetAttribute("SkipPass", true)
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
	local id = skipPassId()
	if id == 0 or passId ~= id or player:GetAttribute("SkipPass") then return end
	-- купил сейчас, или пасс уже был (окно покупки пишет «уже куплено»)
	if bought or ownsSkipPass(player, id) then
		player:SetAttribute("SkipPass", true)
	end
end)

-- при входе: геймпасс, тег клана и первое состояние
local function onPlayer(player)
	task.spawn(checkSkipPass, player)
	player.CharacterAdded:Connect(function(ch)
		ch:WaitForChild("Humanoid", 10)
		applyNameTag(player)
	end)
	if player.Character then task.spawn(applyNameTag, player) end
	watchSummons(player)
	task.spawn(function()
		local waited = 0
		while player.Parent and not PlayerData.Meta(player) and waited < 30 do
			waited += task.wait(0.25)
		end
		local meta = PlayerData.Meta(player)
		if meta and meta.clan then
			setClanTag(player, meta.clan)
		end
		push(player)
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayer(p)
end
