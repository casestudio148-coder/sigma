-- ServerScriptService.LoadoutService (Script)
-- Фаза выбора перед матчем: набор из 6 юнитов + голосование за сложность.
-- Брать можно ТОЛЬКО своих юнитов (выбитых из кейсов + стартовых). Проверка на сервере.
-- Победившая сложность записывается в workspace.Difficulty до старта матча.
-- Карту выбрал портал в хабе (её строит MapService) — матч начнётся, только когда карта готова.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local DifficultyData = require(ReplicatedStorage:WaitForChild("DifficultyData"))
local CaseConfig = require(ReplicatedStorage:WaitForChild("CaseConfig"))
local Guard = require(ServerScriptService:WaitForChild("Guard"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))

local SELECTION_TIME = 30 -- секунд на выбор
local MAX_UNITS = 6

local function makeEvent(name)
	local e = ReplicatedStorage:FindFirstChild(name) or Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = ReplicatedStorage
	return e
end

local submit = makeEvent("SubmitLoadout")
local voteEvent = makeEvent("VoteDifficulty")

workspace:SetAttribute("Phase", "Selection")
workspace:SetAttribute("MaxUnits", MAX_UNITS)

local state = {}     -- [player] = { list = {...}, ready = bool }
local diffVotes = {} -- [player] = id сложности

-- свой ли юнит (данные ещё грузятся → разрешаем только стартовых)
local function owns(player, name)
	if PlayerData.Get(player) then
		return PlayerData.Owns(player, name)
	end
	return table.find(CaseConfig.StarterUnits, name) ~= nil
end

local function sanitize(player, list)
	local out, seen = {}, {}
	if typeof(list) ~= "table" then return out end
	for _, name in ipairs(list) do
		if #out >= MAX_UNITS then break end
		if typeof(name) == "string" and TowerData[name] and not seen[name] and owns(player, name) then
			seen[name] = true
			table.insert(out, name)
		end
	end
	return out
end

-- если игрок ничего не выбрал: до 6 самых дешёвых СВОИХ юнитов
local function defaultLoadout(player)
	local names = {}
	for name in pairs(TowerData) do
		if owns(player, name) then
			table.insert(names, name)
		end
	end
	table.sort(names, function(a, b) return TowerData[a].Price < TowerData[b].Price end)
	local out = {}
	for i = 1, math.min(MAX_UNITS, #names) do
		out[i] = names[i]
	end
	return out
end

local function setLoadout(player, list)
	player:SetAttribute("Loadout", table.concat(list, ","))
end

local function allReady()
	local players = Players:GetPlayers()
	if #players == 0 then return false end
	for _, p in ipairs(players) do
		local s = state[p]
		if not s or not s.ready or #s.list == 0 then
			return false
		end
	end
	return true
end

-- считает голоса и публикует их; при ничьей побеждает более лёгкая сложность
local function publishVotes()
	local counts = {}
	for _, id in ipairs(DifficultyData.Order) do counts[id] = 0 end
	for p, id in pairs(diffVotes) do
		if p.Parent and counts[id] then counts[id] += 1 end
	end

	local leader, best = DifficultyData.Default, 0
	for _, id in ipairs(DifficultyData.Order) do
		workspace:SetAttribute("DiffVotes_" .. id, counts[id])
		if counts[id] > best then
			best = counts[id]
			leader = id
		end
	end
	workspace:SetAttribute("DiffLeader", leader)
	return leader
end

submit.OnServerEvent:Connect(function(player, list, ready)
	if not Guard.check(player, "SubmitLoadout", 8, 12) then return end
	if workspace:GetAttribute("Phase") ~= "Selection" then return end
	if typeof(list) ~= "table" then
		Guard.flag(player, "SubmitLoadout bad argument", 2)
		return
	end
	local clean = sanitize(player, list)
	state[player] = { list = clean, ready = (ready == true) }
	setLoadout(player, clean)
end)

voteEvent.OnServerEvent:Connect(function(player, id)
	if not Guard.check(player, "VoteDifficulty", 4, 6) then return end
	if workspace:GetAttribute("Phase") ~= "Selection" then return end
	if typeof(id) ~= "string" or not table.find(DifficultyData.Order, id) then
		Guard.flag(player, "VoteDifficulty bad argument", 2)
		return
	end
	diffVotes[player] = id
	player:SetAttribute("DiffVote", id)
	publishVotes()
end)

-- зашёл посреди матча: свой набор, когда загрузятся данные
Players.PlayerAdded:Connect(function(player)
	if workspace:GetAttribute("Phase") == "Playing" then
		local waited = 0
		while player.Parent and not PlayerData.Get(player) and waited < 15 do
			waited += task.wait(0.25)
		end
		if player.Parent then
			setLoadout(player, defaultLoadout(player))
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	state[player] = nil
	diffVotes[player] = nil
	if workspace:GetAttribute("Phase") == "Selection" then
		publishVotes()
	end
end)

publishVotes()

-- таймер стартует, когда зашёл первый игрок
if #Players:GetPlayers() == 0 then
	Players.PlayerAdded:Wait()
end
-- отряд из хаба: ждём, пока долетят остальные (не дольше 15 секунд)
local function partySize()
	local n = workspace:GetAttribute("ExpectedPlayers") or 1
	for _, p in ipairs(Players:GetPlayers()) do
		local ok, join = pcall(function() return p:GetJoinData() end)
		local td = ok and type(join) == "table" and join.TeleportData or nil
		if type(td) == "table" and type(td.party) == "number" then
			n = math.max(n, math.floor(td.party))
		end
	end
	return math.clamp(n, 1, 12)
end
local waitStart = os.clock()
while os.clock() - waitStart < 15 do
	if #Players:GetPlayers() >= partySize() then break end
	task.wait(0.25)
end

local endsAt = workspace:GetServerTimeNow() + SELECTION_TIME
workspace:SetAttribute("SelectionEndsAt", endsAt)

while workspace:GetServerTimeNow() < endsAt and not allReady() do
	task.wait(0.25)
end

for _, p in ipairs(Players:GetPlayers()) do
	local s = state[p]
	if not s or #s.list == 0 then
		setLoadout(p, defaultLoadout(p))
	end
end

-- карта ещё строится (MapService) — ждём её, но не дольше минуты
do
	local t0 = os.clock()
	while workspace:GetAttribute("MapReady") == false and os.clock() - t0 < 60 do
		task.wait(0.1)
	end
end

workspace:SetAttribute("Difficulty", publishVotes())
workspace:SetAttribute("Phase", "Playing")
