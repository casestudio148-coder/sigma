-- ServerScriptService.PlaytimeRewards (Script) — ОДИНАКОВЫЙ в хабе и в игре
-- Награды за время в игре. Защита от эксплойтов:
--   • время считает только сервер (клиенту не доверяем)
--   • номер награды проверяется: целое число, есть в таблице, ещё не забрано
--   • награду можно забрать, только когда серверное время >= нужного
--   • ограничение частоты запросов
-- Время и забранные награды сохраняются в данных игрока: переход хаб → матч → хаб их не сбрасывает.
-- Новый круг наград начинается, если игрока не было в игре дольше NEW_SESSION_AFTER.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Config = require(ReplicatedStorage:WaitForChild("PlaytimeConfig"))
local Guard = require(ServerScriptService:WaitForChild("Guard"))

local NEW_SESSION_AFTER = 15 * 60 -- секунд вне игры, после которых таймер начинается заново
local REMEMBER_EVERY = 5

local PlayerData = nil
do
	local mod = ServerScriptService:WaitForChild("PlayerData", 10)
	if mod then
		local ok, result = pcall(require, mod)
		if ok then PlayerData = result end
	end
	if not PlayerData then
		warn("[PlaytimeRewards] нет PlayerData — время наград не переносится между хабом и матчем")
	end
end

local function getOrCreateEvent(name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = ReplicatedStorage
	end
	return e
end

local claimEvent = getOrCreateEvent("ClaimPlaytimeReward")
local grantedEvent = getOrCreateEvent("PlaytimeRewardGranted")

local sessions = {} -- [player] = { start, claimed = { [index] = true }, ready, meta }

local function now()
	return workspace:GetServerTimeNow()
end

local function publishClaimed(player, s)
	local list = {}
	for index in pairs(s.claimed) do
		table.insert(list, index)
	end
	table.sort(list)
	player:SetAttribute("PlaytimeClaimed", table.concat(list, ","))
end

-- записать прогресс в данные игрока (сохранится вместе с ними)
local function remember(s)
	if not s.meta then return end
	local list = {}
	for index in pairs(s.claimed) do
		table.insert(list, index)
	end
	table.sort(list)
	s.meta.playtime = { active = math.max(0, now() - s.start), claimed = list, seen = now() }
end

local function onPlayerAdded(player)
	local s = { start = now(), claimed = {}, ready = PlayerData == nil }
	sessions[player] = s
	player:SetAttribute("SessionStart", s.start) -- только для таймеров на клиенте
	player:SetAttribute("PlaytimeClaimed", "")
	if not PlayerData then return end

	task.spawn(function()
		-- ждём, пока загрузятся данные (если загрузить не вышло, PlayerData сам кикнет игрока)
		local meta = nil
		while player.Parent and sessions[player] == s do
			meta = PlayerData.Meta(player)
			if meta then break end
			task.wait(0.25)
		end
		if sessions[player] ~= s then return end
		if meta then
			local saved = meta.playtime
			if type(saved) == "table" and type(saved.active) == "number" and type(saved.seen) == "number"
				and now() - saved.seen < NEW_SESSION_AFTER and saved.active >= 0 then
				-- продолжаем: время и забранные награды — с прошлого сервера
				s.start = now() - saved.active
				for _, index in ipairs(type(saved.claimed) == "table" and saved.claimed or {}) do
					if type(index) == "number" and Config.Rewards[index] then
						s.claimed[index] = true
					end
				end
				player:SetAttribute("SessionStart", s.start)
				publishClaimed(player, s)
			end
			s.meta = meta
			remember(s)
		end
		s.ready = true
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end

Players.PlayerRemoving:Connect(function(player)
	local s = sessions[player]
	if s then remember(s) end
	sessions[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(REMEMBER_EVERY)
		for _, s in pairs(sessions) do
			remember(s)
		end
	end
end)

claimEvent.OnServerEvent:Connect(function(player, index)
	local s = sessions[player]
	if not s or not s.ready then return end
	if player:GetAttribute("HubTeleporting") or player:GetAttribute("Teleporting") then return end

	if not Guard.check(player, "ClaimPlaytime", 3, 5) then return end

	if typeof(index) ~= "number" or index ~= index or index % 1 ~= 0 then
		Guard.flag(player, "ClaimPlaytime bad argument", 3)
		return
	end

	local reward = Config.Rewards[index]
	if not reward then
		Guard.flag(player, "ClaimPlaytime unknown reward", 3)
		return
	end
	if s.claimed[index] then return end

	local elapsed = now() - s.start
	local need = Config.getTime(index)
	if elapsed < need then
		-- кнопка на клиенте появляется только когда время вышло; раньше = подделанный запрос
		-- (небольшой запас на разницу часов разных серверов)
		if need - elapsed > 3 then
			Guard.flag(player, "ClaimPlaytime too early", need - elapsed > 8 and 5 or 1)
		end
		return
	end

	local data = player:FindFirstChild("Data")
	local value = data and data:FindFirstChild(reward.Type)
	if not value then return end

	s.claimed[index] = true
	value.Value += reward.Amount
	publishClaimed(player, s)
	remember(s)
	grantedEvent:FireClient(player, index)
end)
