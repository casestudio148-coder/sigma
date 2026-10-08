-- ServerScriptService.MatchLink (Script) — ТОЛЬКО В МЕСТЕ С МАТЧЕМ
-- Связь матча с хабом:
--   • отряд пришёл через портал → карту строит MapService, сложность игроки выбирают голосованием
--   • конец матча → кнопки PLAY AGAIN (ещё раз той же командой на той же карте) и LOBBY;
--     через PlaceConfig.ReturnDelay секунд всех, кто не выбрал PLAY AGAIN, вернёт в хаб
--   • игрок зашёл сюда напрямую с сайта (обычный сервер) → сразу отправляем его в хаб
-- В Studio телепорты не работают — там играешь карту из MapConfig.StudioMap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")

local PlaceConfig = require(ReplicatedStorage:WaitForChild("PlaceConfig"))
local MapConfig = require(ReplicatedStorage:WaitForChild("MapConfig"))
local Guard = require(ServerScriptService:WaitForChild("Guard"))

-- защита: это место-хаб (там свои порталы) — тут MatchLink не нужен
if workspace:FindFirstChild("Hub") or (PlaceConfig.HubPlaceId ~= 0 and game.PlaceId == PlaceConfig.HubPlaceId) then
	warn("[MatchLink] это место-хаб — MatchLink нужен только в месте с картой матча!")
	return
end

local PlayerData = nil
do
	local mod = ServerScriptService:WaitForChild("PlayerData", 10)
	if mod then
		local ok, result = pcall(require, mod)
		if ok then PlayerData = result end
	end
end

local function makeRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local voteRemote = makeRemote("MatchVote")   -- клиент → сервер: "lobby" / "replay"
local notifyRemote = makeRemote("HubNotify") -- сервер → клиент: подсказка

local function notify(player, text, kind)
	if player.Parent then
		notifyRemote:FireClient(player, text, kind or "info")
	end
end

-- какой это сервер
local isReserved = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 -- отряд из хаба
local isPublic = game.PrivateServerId == ""                                   -- обычный сервер (зашли с сайта)
local canTeleport = not RunService:IsStudio() and (PlaceConfig.HubPlaceId or 0) ~= 0
workspace:SetAttribute("CanReturn", canTeleport)

local matchMap = nil
pcall(function()
	matchMap = MemoryStoreService:GetSortedMap("HubMatches")
end)

-- карта этого матча (её выбрал портал в хабе, построил MapService)
local function currentMap()
	local id = workspace:GetAttribute("MapId")
	if MapConfig.get(id) then return id end
	return MapConfig.Default
end

---------------------------------------------------------------- телепорты

-- сохранить всех перед телепортом. Вернёт тех, чей прогресс точно сохранён
local function saveAll(list)
	if not PlayerData then return list end
	local saved = {}
	local left = #list
	for _, player in ipairs(list) do
		task.spawn(function()
			local ok, result = pcall(PlayerData.SaveBeforeTeleport, player)
			if ok and result then table.insert(saved, player) end
			left -= 1
		end)
	end
	local started = os.clock()
	while left > 0 and os.clock() - started < 20 do
		task.wait(0.1)
	end
	return saved
end

local teleporting = {} -- [player] = true

-- кого не удалось сохранить — оставляем здесь и просим нажать ещё раз
local function keepUnsaved(list, saved)
	local set = {}
	for _, player in ipairs(saved) do set[player] = true end
	for _, player in ipairs(list) do
		if not set[player] then
			teleporting[player] = nil
			if player.Parent then
				player:SetAttribute("Teleporting", nil)
				notify(player, "Couldn't save your progress. Press the button again!", "error")
			end
		end
	end
end

local function teleportWithRetry(placeId, list, options, what)
	local ok, err = false, nil
	for attempt = 1, 3 do
		local still = {}
		for _, player in ipairs(list) do
			if player.Parent then table.insert(still, player) end
		end
		if #still == 0 then return true end
		ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, still, options)
		end)
		if ok then return true end
		warn(string.format("[MatchLink] %s, попытка %d: %s", what, attempt, tostring(err)))
		task.wait(attempt)
	end
	return false
end

local function sendToHub(list, data, kind)
	local out = {}
	for _, player in ipairs(list) do
		if player.Parent and not teleporting[player] then
			teleporting[player] = true
			player:SetAttribute("Teleporting", kind or "lobby")
			table.insert(out, player)
		end
	end
	if #out == 0 then return end
	local saved = saveAll(out)
	keepUnsaved(out, saved)
	out = saved
	if #out == 0 then return end
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData(data or { fromMatch = true })
	if not teleportWithRetry(PlaceConfig.HubPlaceId, out, options, "в хаб") then
		for _, player in ipairs(out) do
			teleporting[player] = nil
			if player.Parent then
				player:SetAttribute("Teleporting", nil)
				notify(player, "Couldn't reach the lobby. Try again!", "error")
			end
		end
	end
end

local function startReplay(list, map)
	local out = {}
	for _, player in ipairs(list) do
		if player.Parent and not teleporting[player] then
			teleporting[player] = true
			player:SetAttribute("Teleporting", "replay")
			table.insert(out, player)
		end
	end
	if #out == 0 then return end
	local saved = saveAll(out)
	keepUnsaved(out, saved)
	out = saved
	if #out == 0 then return end
	local ok = pcall(function()
		local code, privateId = TeleportService:ReserveServer(game.PlaceId)
		if matchMap and privateId then
			pcall(function()
				matchMap:SetAsync(privateId, map, 3600)
			end)
		end
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData({ map = map, fromHub = true, party = #out })
		if not teleportWithRetry(game.PlaceId, out, options, "новый матч") then
			error("teleport failed")
		end
	end)
	if not ok then
		-- не вышло начать заново — отправляем в хаб
		for _, player in ipairs(out) do
			teleporting[player] = nil
			if player.Parent then player:SetAttribute("Teleporting", nil) end
		end
		sendToHub(out)
	end
end

TeleportService.TeleportInitFailed:Connect(function(player, result, message)
	if teleporting[player] then
		teleporting[player] = nil
		player:SetAttribute("Teleporting", nil)
		notify(player, "Teleport failed. Press the button again!", "error")
		warn(string.format("[MatchLink] TeleportInitFailed %s: %s %s", player.Name, tostring(result), tostring(message)))
	end
end)

---------------------------------------------------------------- 2. кто зашёл

local function onJoin(player)
	local join = player:GetJoinData()
	local td = join and join.TeleportData
	-- отряд из хаба: сколько игроков ждать (LoadoutService не начнёт выбор без них, максимум 15 секунд)
	if type(td) == "table" and isReserved and type(td.party) == "number" then
		local n = math.clamp(math.floor(td.party), 1, 12)
		if n > (workspace:GetAttribute("ExpectedPlayers") or 0) then
			workspace:SetAttribute("ExpectedPlayers", n)
		end
	end

	-- 3. зашёл напрямую с сайта → в хаб
	if isPublic and PlaceConfig.RedirectToHub and canTeleport then
		task.wait(1)
		if player.Parent then
			notify(player, "Going to the lobby...", "info")
			sendToHub({ player }, { redirected = true }, "redirect")
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(onJoin, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onJoin, player)
end

---------------------------------------------------------------- 4. конец матча: PLAY AGAIN или LOBBY

local returnAt = nil
local wantsReplay = {} -- [player] = true

local function publishVotes()
	local n = 0
	for player in pairs(wantsReplay) do
		if player.Parent then n += 1 end
	end
	workspace:SetAttribute("ReplayVotes", n)
	workspace:SetAttribute("ReplayTotal", #Players:GetPlayers())
end

local finished = false
local function finish()
	if finished then return end
	finished = true
	local map = currentMap()
	local replay, lobby = {}, {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not teleporting[player] then
			table.insert(wantsReplay[player] and replay or lobby, player)
		end
	end
	if not canTeleport then
		for _, player in ipairs(Players:GetPlayers()) do
			notify(player, "In Studio there is no lobby: publish the game to test portals", "info")
		end
		return
	end
	if #replay > 0 then task.spawn(startReplay, replay, map) end
	if #lobby > 0 then task.spawn(sendToHub, lobby) end
	-- кто остался (телепорт или сохранение не удались) — пробуем снова каждые 15 секунд
	task.spawn(function()
		while true do
			task.wait(15)
			local left = {}
			for _, player in ipairs(Players:GetPlayers()) do
				if not teleporting[player] then table.insert(left, player) end
			end
			if #left > 0 then sendToHub(left) end
		end
	end)
end

local function allChose()
	local players = Players:GetPlayers()
	if #players == 0 then return false end
	for _, player in ipairs(players) do
		if not wantsReplay[player] and not teleporting[player] then return false end
	end
	return true
end

workspace:GetAttributeChangedSignal("MatchOver"):Connect(function()
	if workspace:GetAttribute("MatchOver") ~= true or returnAt then return end
	returnAt = workspace:GetServerTimeNow() + PlaceConfig.ReturnDelay
	workspace:SetAttribute("ReturnAt", returnAt)
	publishVotes()
	task.spawn(function()
		while workspace:GetServerTimeNow() < returnAt do
			if allChose() then
				task.wait(1) -- все выбрали PLAY AGAIN — не ждём таймер
				break
			end
			task.wait(0.25)
		end
		finish()
	end)
end)

voteRemote.OnServerEvent:Connect(function(player, choice)
	if not Guard.check(player, "MatchVote", 2, 4) then return end
	if choice ~= "lobby" and choice ~= "replay" then
		Guard.flag(player, "MatchVote bad argument", 2)
		return
	end
	if not returnAt or teleporting[player] then return end
	if not canTeleport then
		notify(player, "Teleports work only in the published game (not in Studio)", "info")
		return
	end
	if choice == "lobby" or finished then
		wantsReplay[player] = nil
		publishVotes()
		task.spawn(sendToHub, { player })
	else
		wantsReplay[player] = not wantsReplay[player] or nil -- повторное нажатие отменяет
		player:SetAttribute("WantsReplay", wantsReplay[player] == true)
		publishVotes()
	end
end)

Players.PlayerRemoving:Connect(function(player)
	wantsReplay[player] = nil
	teleporting[player] = nil
	if returnAt then publishVotes() end
end)

print("[MatchLink] запущен" .. (isReserved and " (матч из хаба)" or isPublic and " (обычный сервер)" or " (VIP-сервер)"))
