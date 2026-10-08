-- ServerScriptService.TowerControl — ЗАМЕНИТЕ старый код целиком
-- Управление своими башнями: режим цели, продажа, улучшение (4 тира — вся логика в UpgradeService).
-- Чужими башнями управлять нельзя: каждое действие проверяет владельца.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local Guard = require(game:GetService("ServerScriptService"):WaitForChild("Guard"))
-- UpgradeService ищем и в ServerScriptService, и в ReplicatedStorage (раньше скрипт зависал, если модуль лежал не там)
local UpgradeService = require(game:GetService("ServerScriptService"):FindFirstChild("UpgradeService")
	or ReplicatedStorage:WaitForChild("UpgradeService"))
local towersFolder = workspace:WaitForChild("Towers")

local SELL_PERCENT = 0.6

local function getOrCreateEvent(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = ReplicatedStorage
	end
	return event
end

local setTargetEvent = getOrCreateEvent("SetTargetMode")
local sellEvent = getOrCreateEvent("SellTower")
local upgradeEvent = getOrCreateEvent("UpgradeTower") -- клиент -> сервер; ответ сервера: "ok", тир | "fail", причина

local ValidModes = { First = true, Strongest = true, Last = true, Closest = true }

local function getCoins(player)
	local stats = player:FindFirstChild("leaderstats")
	return stats and stats:FindFirstChild("Coins")
end

-- true, если tower — существующая башня этого игрока
local function ownsTower(player, tower)
	if tower == nil then
		return false -- башню только что продали / удалили: запрос пришёл с опозданием, это не чит
	end
	if typeof(tower) ~= "Instance" then
		Guard.flag(player, "tower arg is not an Instance", 3)
		return false
	end
	if tower.Parent ~= towersFolder then return false end -- башню могли уже продать
	if tower:GetAttribute("OwnerId") ~= player.UserId then
		Guard.flag(player, "tried to control someone else's tower", 4)
		return false
	end
	return true
end

setTargetEvent.OnServerEvent:Connect(function(player, tower, mode)
	if not Guard.check(player, "SetTargetMode", 6, 10) then return end
	if not ownsTower(player, tower) then return end
	if typeof(mode) ~= "string" or not ValidModes[mode] then
		Guard.flag(player, "bad target mode", 2)
		return
	end
	tower:SetAttribute("TargetMode", mode)
end)

sellEvent.OnServerEvent:Connect(function(player, tower)
	if not Guard.check(player, "SellTower", 4, 6) then return end
	if not ownsTower(player, tower) then return end

	local config = TowerData[tower.Name]
	local invested = tower:GetAttribute("Invested") or (config and config.Price) or 0
	local coins = getCoins(player)
	if coins then
		coins.Value += math.floor(invested * SELL_PERCENT)
	end
	tower:Destroy()
end)

upgradeEvent.OnServerEvent:Connect(function(player, tower)
	local ok, result = UpgradeService.UpgradeTower(player, tower)
	if ok == true then
		upgradeEvent:FireClient(player, "ok", result)
	elseif ok == false then
		upgradeEvent:FireClient(player, "fail", result)
	end
	-- ok == nil: запрос проигнорирован (флуд / опоздал) — не отвечаем, чтобы флуд не порождал ответный флуд
end)
