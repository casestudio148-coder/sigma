-- ServerScriptService.HubService (Script) — ТОЛЬКО В МЕСТЕ-ХАБЕ
-- Порталы карт (8 штук, список в ReplicatedStorage.MapConfig):
--   • встал в светящийся круг перед порталом → попал в отряд (до PlaceConfig.MaxParty игроков)
--   • идёт отсчёт PlaceConfig.QueueTime секунд (отряд собрался полностью → PlaceConfig.FullTime)
--   • первый в отряде (лидер) может нажать START — старт через 3 секунды
--   • время вышло → прогресс всех сохраняется → весь отряд летит в место с картой
--     на ОТДЕЛЬНЫЙ сервер только для них, там строится выбранная карта (сложность — голосованием в матче)
-- В Studio телепорт не работает (так устроен Roblox) — покажем подсказку, очередь всё равно можно проверить.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")

local PlaceConfig = require(ReplicatedStorage:WaitForChild("PlaceConfig"))
local MapConfig = require(ReplicatedStorage:WaitForChild("MapConfig"))
local Guard = require(ServerScriptService:WaitForChild("Guard"))

-- PlayerData нужен, чтобы сохранить прогресс перед телепортом (если его нет — просто не сохраняем заранее)
local PlayerData = nil
do
	local mod = ServerScriptService:WaitForChild("PlayerData", 10)
	if mod then
		local ok, result = pcall(require, mod)
		if ok then
			PlayerData = result
		else
			warn("[HubService] PlayerData с ошибкой: " .. tostring(result))
		end
	else
		warn("[HubService] нет ServerScriptService.PlayerData — прогресс не будет сохраняться перед телепортом")
	end
end

local START_DELAY = 3 -- кнопка START лидера: старт через столько секунд
local TICK = 0.2

local function makeRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end
local actionRemote = makeRemote("HubAction") -- клиент → сервер: "leave" / "start"
local notifyRemote = makeRemote("HubNotify") -- сервер → клиент: текст подсказки

-- хаб строит HubBuilder; если хаба нет — это не то место (например, карта матча)
local hub = workspace:WaitForChild("Hub", 60)
if not hub then
	warn("[HubService] нет workspace.Hub: HubService нужен только в месте-хабе вместе с HubBuilder")
	return
end

-- в хабе меню (Units, Shop, Quests...) видно всегда
workspace:SetAttribute("Phase", "Lobby")
workspace:SetAttribute("IsHub", true)

local function notify(player, text, kind)
	if player.Parent then
		notifyRemote:FireClient(player, text, kind or "info")
	end
end

-- запись «какая карта у этого сервера» — матч прочитает её у себя (надёжнее данных телепорта)
local matchMap = nil
pcall(function()
	matchMap = MemoryStoreService:GetSortedMap("HubMatches")
end)

---------------------------------------------------------------- порталы

local portals = {} -- [id] = { id, model, pad, radius, list = {игроки}, endsAt, state, labels }
local queueOf = {} -- [player] = портал
local busy = {}    -- [player] = время, когда начался телепорт (стоять в очереди нельзя)
local fullWarned = {}

local function canTeleport()
	return not RunService:IsStudio() and (PlaceConfig.GamePlaceId or 0) ~= 0
end

local function findLabel(model, name)
	local l = model:FindFirstChild(name, true)
	return (l and l:IsA("TextLabel")) and l or nil
end

local function register(model)
	local id = model.Name
	if portals[id] or not MapConfig.get(id) then return end
	local pad = model:FindFirstChild("Pad")
	if not (pad and pad:IsA("BasePart")) then return end
	portals[id] = {
		id = id,
		model = model,
		pad = pad,
		radius = pad:GetAttribute("Radius") or 7.5,
		list = {},
		endsAt = 0,
		state = "idle",
		count = findLabel(model, "Count"),
		timer = findLabel(model, "Timer"),
		shown = {},
	}
	model:SetAttribute("Max", PlaceConfig.MaxParty)
end

-- порталы строит HubBuilder; если хаб сохранён вручную — они уже в Workspace
task.spawn(function()
	local folder = hub:WaitForChild("Portals", 30)
	if not folder then return end
	for _, m in ipairs(folder:GetChildren()) do register(m) end
	folder.ChildAdded:Connect(register)
end)

local function setText(p, which, text)
	local label = p[which]
	if label and p.shown[which] ~= text then
		p.shown[which] = text
		label.Text = text
	end
end

local function publish(p)
	local now = workspace:GetServerTimeNow()
	local n = #p.list
	local leader = p.list[1]
	p.model:SetAttribute("Count", n)
	p.model:SetAttribute("EndsAt", p.endsAt)
	p.model:SetAttribute("State", p.state)
	p.model:SetAttribute("Leader", leader and leader.UserId or 0)
	setText(p, "count", n .. " / " .. PlaceConfig.MaxParty)
	if p.state == "teleporting" then
		setText(p, "timer", "TELEPORTING...")
	elseif n == 0 then
		setText(p, "timer", "STAND HERE TO PLAY")
	else
		setText(p, "timer", "STARTING IN " .. math.max(0, math.ceil(p.endsAt - now)))
	end
end

local function removeFrom(p, player)
	local i = table.find(p.list, player)
	if i then
		table.remove(p.list, i)
		queueOf[player] = nil
		if player.Parent then player:SetAttribute("HubQueue", nil) end
		if #p.list == 0 and p.state ~= "teleporting" then
			p.endsAt = 0
			p.state = "idle"
		end
	end
end

local function addTo(p, player)
	if #p.list >= PlaceConfig.MaxParty then return false end
	table.insert(p.list, player)
	queueOf[player] = p
	player:SetAttribute("HubQueue", p.id)
	local now = workspace:GetServerTimeNow()
	if #p.list == 1 then
		p.endsAt = now + PlaceConfig.QueueTime
		p.state = "waiting"
	end
	if #p.list >= PlaceConfig.MaxParty then
		p.endsAt = math.min(p.endsAt, now + PlaceConfig.FullTime)
	end
	return true
end

-- сохранить всех перед телепортом (параллельно). Вернёт тех, чей прогресс точно сохранён:
-- кого не удалось сохранить, НЕ телепортируем (иначе в матче загрузятся старые данные)
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

-- телепорт группы игроков на НОВЫЙ сервер с картой mapId.
-- Вернёт: "ok" | "studio" (в Studio или не настроено) | "fail". tag — что писать в HubTeleporting.
local function teleportGroup(list, mapId, tag)
	local party = {}
	for _, player in ipairs(list) do
		if player.Parent and not busy[player] then table.insert(party, player) end
	end
	if #party == 0 then return "fail" end

	if not canTeleport() then
		local why = RunService:IsStudio()
			and "Portals work only in the real game: publish it and play from Roblox!"
			or "Portals are not set up yet (GamePlaceId in PlaceConfig)"
		for _, player in ipairs(party) do notify(player, why, "error") end
		if not RunService:IsStudio() then
			warn("[HubService] впиши GamePlaceId в ReplicatedStorage.PlaceConfig")
		end
		return "studio"
	end

	for _, player in ipairs(party) do
		busy[player] = os.clock()
		local q = queueOf[player]
		if q then removeFrom(q, player) end
		player:SetAttribute("HubTeleporting", tag or mapId)
	end

	local saved = saveAll(party)
	local savedSet = {}
	for _, player in ipairs(saved) do savedSet[player] = true end
	for _, player in ipairs(party) do
		if not savedSet[player] then
			busy[player] = nil
			if player.Parent then
				player:SetAttribute("HubTeleporting", nil)
				notify(player, "Couldn't save your progress. Try again in a moment!", "error")
			end
		else
			busy[player] = os.clock()
		end
	end
	party = saved

	local ok, err = true, nil
	for attempt = 1, (#party > 0) and 3 or 0 do
		ok, err = pcall(function()
			local code, privateId = TeleportService:ReserveServer(PlaceConfig.GamePlaceId)
			if matchMap and privateId then
				pcall(function()
					matchMap:SetAsync(privateId, mapId, 3600)
				end)
			end
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = code
			options:SetTeleportData({ map = mapId, fromHub = true, party = #party })
			local still = {}
			for _, player in ipairs(party) do
				if player.Parent then table.insert(still, player) end
			end
			if #still > 0 then
				TeleportService:TeleportAsync(PlaceConfig.GamePlaceId, still, options)
			end
			for _, player in ipairs(still) do busy[player] = os.clock() end
		end)
		if ok then break end
		warn(string.format("[HubService] телепорт %s, попытка %d: %s", mapId, attempt, tostring(err)))
		task.wait(attempt)
	end

	if not ok or #party == 0 then
		for _, player in ipairs(party) do
			busy[player] = nil
			if player.Parent then
				player:SetAttribute("HubTeleporting", nil)
				notify(player, "Teleport failed. Try again!", "error")
			end
		end
		return "fail"
	end
	return "ok"
end

local function launch(p)
	local party = {}
	for _, player in ipairs(p.list) do
		if player.Parent then table.insert(party, player) end
	end
	if #party == 0 then
		p.state = "idle"
		p.endsAt = 0
		return
	end
	if not canTeleport() then
		teleportGroup(party, p.id, p.id) -- покажет подсказку
		-- очередь начинается заново, пока игроки стоят в круге
		p.endsAt = workspace:GetServerTimeNow() + PlaceConfig.QueueTime
		return
	end

	p.state = "teleporting"
	publish(p)
	local result = teleportGroup(party, p.id, p.id)
	-- портал снова свободен для следующего отряда
	task.delay(result == "ok" and 2 or 0, function()
		p.state = (#p.list > 0) and "waiting" or "idle"
		if #p.list > 0 and p.endsAt == 0 then
			p.endsAt = workspace:GetServerTimeNow() + PlaceConfig.QueueTime
		end
	end)
end

-- телепорт не удался уже у игрока (плохая сеть и т.п.) — он снова может играть
TeleportService.TeleportInitFailed:Connect(function(player, result, message)
	if busy[player] then
		busy[player] = nil
		player:SetAttribute("HubTeleporting", nil)
		notify(player, "Teleport failed. Step into the portal again!", "error")
		warn(string.format("[HubService] TeleportInitFailed %s: %s %s", player.Name, tostring(result), tostring(message)))
	end
end)

---------------------------------------------------------------- кто стоит в кругах

local function rootOf(player)
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root and hum and hum.Health > 0 then return root end
	return nil
end

local function onPad(p, root)
	local d = root.Position - p.pad.Position
	return Vector3.new(d.X, 0, d.Z).Magnitude <= p.radius and d.Y > -3 and d.Y < 10
end

local function step()
	local now = workspace:GetServerTimeNow()
	-- телепорт завис дольше минуты — снимаем блокировку
	for player, t in pairs(busy) do
		if not player.Parent then
			busy[player] = nil
		elseif os.clock() - t > 60 then
			busy[player] = nil
			player:SetAttribute("HubTeleporting", nil)
		end
	end

	for _, p in pairs(portals) do
		if p.state ~= "teleporting" then
			-- ушёл из круга или из игры → из отряда
			for i = #p.list, 1, -1 do
				local player = p.list[i]
				local root = player.Parent and rootOf(player)
				if not root or not onPad(p, root) then
					removeFrom(p, player)
				end
			end
			-- новые в круге
			for _, player in ipairs(Players:GetPlayers()) do
				if not queueOf[player] and not busy[player] then
					local root = rootOf(player)
					if root and onPad(p, root) then
						if not addTo(p, player) then
							if not fullWarned[player] or os.clock() - fullWarned[player] > 4 then
								fullWarned[player] = os.clock()
								notify(player, "This portal is full! Try another one.", "error")
							end
						end
					end
				end
			end
			-- время вышло → в бой
			if #p.list > 0 and p.endsAt > 0 and now >= p.endsAt then
				task.spawn(launch, p)
			end
		end
		publish(p)
	end
end

task.spawn(function()
	while true do
		local ok, err = pcall(step)
		if not ok then warn("[HubService] " .. tostring(err)) end
		task.wait(TICK)
	end
end)

---------------------------------------------------------------- отряды (party): играть с друзьями без портала
-- Лидер приглашает игроков из списка, они принимают приглашение. Потом лидер жмёт PLAY → карта,
-- и весь отряд летит на свой сервер. Без отряда PLAY → карта отправляет игрока одного.

local partyRemote = makeRemote("HubParty") -- клиент ↔ сервер: invite / accept / decline / leave / kick
local INVITE_TIME = 30
local partyOf = {} -- [player] = { leader = player, members = { player, ... } }
local invites = {} -- [кого] = { [кто пригласил] = os.clock() }

local function partyState(party)
	if not party then return nil end
	local members = {}
	for _, m in ipairs(party.members) do
		table.insert(members, { id = m.UserId, name = m.DisplayName, user = m.Name })
	end
	return { leader = party.leader.UserId, members = members, max = PlaceConfig.MaxParty }
end

local function pushParty(party)
	local state = partyState(party)
	for _, m in ipairs(party.members) do
		if m.Parent then
			m:SetAttribute("PartyLeader", party.leader.UserId)
			partyRemote:FireClient(m, "state", state)
		end
	end
end

local function clearParty(player)
	partyOf[player] = nil
	if player.Parent then
		player:SetAttribute("PartyLeader", nil)
		partyRemote:FireClient(player, "state", nil)
	end
end

local function leaveParty(player, quiet)
	local party = partyOf[player]
	if not party then return end
	local i = table.find(party.members, player)
	if i then table.remove(party.members, i) end
	clearParty(player)
	if #party.members <= 1 then
		-- остался один — отряда больше нет
		for _, m in ipairs(party.members) do
			clearParty(m)
			if not quiet then notify(m, "Your party was disbanded", "info") end
		end
		party.members = {}
		return
	end
	if party.leader == player then
		party.leader = party.members[1]
		notify(party.leader, "You are the party leader now!", "info")
	end
	for _, m in ipairs(party.members) do
		if not quiet then notify(m, player.DisplayName .. " left the party", "info") end
	end
	pushParty(party)
end

local function byUserId(id)
	return typeof(id) == "number" and Players:GetPlayerByUserId(id) or nil
end

local PARTY = {}

function PARTY.invite(player, targetId)
	local target = byUserId(targetId)
	if not target or target == player then return end
	local party = partyOf[player]
	if party and party.leader ~= player then
		notify(player, "Only the party leader can invite", "error")
		return
	end
	if party and #party.members >= PlaceConfig.MaxParty then
		notify(player, "Your party is full!", "error")
		return
	end
	if partyOf[target] then
		notify(player, target.DisplayName .. " is already in a party", "error")
		return
	end
	invites[target] = invites[target] or {}
	local last = invites[target][player]
	if last and os.clock() - last < 5 then return end -- не спамим
	invites[target][player] = os.clock()
	partyRemote:FireClient(target, "invite", { id = player.UserId, name = player.DisplayName, time = INVITE_TIME })
	notify(player, "Invite sent to " .. target.DisplayName, "info")
end

function PARTY.accept(player, fromId)
	local from = byUserId(fromId)
	local list = invites[player]
	local at = list and from and list[from]
	if list and from then list[from] = nil end
	if not from or not at or os.clock() - at > INVITE_TIME then
		notify(player, "This invite has expired", "error")
		return
	end
	if busy[player] or busy[from] then return end
	local party = partyOf[from]
	if party and party.leader ~= from then
		notify(player, "This invite has expired", "error")
		return
	end
	if party and #party.members >= PlaceConfig.MaxParty then
		notify(player, "That party is full!", "error")
		return
	end
	if partyOf[player] then leaveParty(player, true) end
	if not party then
		party = { leader = from, members = { from } }
		partyOf[from] = party
	end
	table.insert(party.members, player)
	partyOf[player] = party
	invites[player] = nil
	for _, m in ipairs(party.members) do
		notify(m, player.DisplayName .. " joined the party!", "info")
	end
	pushParty(party)
end

function PARTY.decline(player, fromId)
	local from = byUserId(fromId)
	if invites[player] and from then
		invites[player][from] = nil
		notify(from, player.DisplayName .. " declined your invite", "info")
	end
end

function PARTY.leave(player)
	if partyOf[player] then
		leaveParty(player)
		notify(player, "You left the party", "info")
	end
end

function PARTY.kick(player, targetId)
	local party = partyOf[player]
	local target = byUserId(targetId)
	if not party or party.leader ~= player or not target or target == player or partyOf[target] ~= party then return end
	leaveParty(target)
	notify(target, "You were removed from the party", "error")
end

function PARTY.sync(player)
	partyRemote:FireClient(player, "state", partyState(partyOf[player]))
end

partyRemote.OnServerEvent:Connect(function(player, action, arg)
	if not Guard.check(player, "HubParty", 4, 8) then return end
	local f = typeof(action) == "string" and PARTY[action]
	if not f then
		Guard.flag(player, "HubParty bad action", 2)
		return
	end
	f(player, arg)
end)

-- PLAY → карта: сразу в бой (с отрядом, если он есть)
local function playNow(player, mapId)
	if not MapConfig.get(mapId) or busy[player] then return end
	local party = partyOf[player]
	local group = { player }
	if party then
		if party.leader ~= player then
			notify(player, "Only the party leader can start the game", "error")
			return
		end
		group = {}
		for _, m in ipairs(party.members) do
			if m.Parent and not busy[m] then table.insert(group, m) end
		end
	end
	for _, m in ipairs(group) do
		if m ~= player then notify(m, player.DisplayName .. " started " .. MapConfig.get(mapId).Name .. "!", "info") end
	end
	task.spawn(teleportGroup, group, mapId, mapId)
end

---------------------------------------------------------------- кнопки игрока

actionRemote.OnServerEvent:Connect(function(player, action, arg)
	if not Guard.check(player, "HubAction", 3, 6) then return end
	if action ~= "leave" and action ~= "start" and action ~= "go" and action ~= "play" then
		Guard.flag(player, "HubAction bad argument", 2)
		return
	end

	-- PLAY → выбрал карту: сразу в бой (один или с отрядом)
	if action == "play" then
		if typeof(arg) == "string" and not queueOf[player] then playNow(player, arg) end
		return
	end

	-- старый способ: перенести в круг портала
	if action == "go" then
		local target = typeof(arg) == "string" and portals[arg]
		if not target or queueOf[player] or busy[player] then return end
		local root = rootOf(player)
		if not root then return end
		local padPos = target.pad.Position
		local a = math.random() * math.pi * 2
		local r = math.random() * math.min(3, target.radius - 2)
		local pos = padPos + Vector3.new(math.cos(a) * r, 3.5, math.sin(a) * r)
		local out = Vector3.new(padPos.X, 0, padPos.Z)
		out = out.Magnitude > 0 and out.Unit or Vector3.new(0, 0, -1)
		player.Character:PivotTo(CFrame.lookAt(pos, pos + out))
		return
	end

	local p = queueOf[player]
	if not p or p.state == "teleporting" then return end

	if action == "start" then
		if p.list[1] ~= player then return end -- только лидер
		p.endsAt = math.min(p.endsAt, workspace:GetServerTimeNow() + START_DELAY)
		publish(p)
		return
	end

	-- leave: выходим из отряда и шагаем из круга в сторону площади
	removeFrom(p, player)
	publish(p)
	local root = rootOf(player)
	if root then
		local padPos = p.pad.Position
		local toCenter = Vector3.new(-padPos.X, 0, -padPos.Z)
		if toCenter.Magnitude > 0 then
			local dir = toCenter.Unit
			local target = Vector3.new(padPos.X, padPos.Y + 3.5, padPos.Z) + dir * (p.radius + 6)
			player.Character:PivotTo(CFrame.lookAt(target, target + dir))
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local p = queueOf[player]
	if p then removeFrom(p, player) end
	if partyOf[player] then leaveParty(player) end
	invites[player] = nil
	for _, list in pairs(invites) do list[player] = nil end
	busy[player] = nil
	fullWarned[player] = nil
end)

print("[HubService] запущен")
