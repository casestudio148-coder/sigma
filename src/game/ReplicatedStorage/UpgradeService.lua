-- ServerScriptService.UpgradeService (ModuleScript)
-- Безопасные улучшения башен: 4 тира. Решает только сервер:
--   • тир башни — атрибут Level; его меняет только сервер (изменения атрибутов с клиента на сервер не доходят);
--   • цена — только из TowerData на сервере, клиент присылает лишь саму башню;
--   • монеты — leaderstats.Coins на сервере; проверка и списание идут подряд, без пауз (yield),
--     поэтому два быстрых запроса не купят один тир дважды и не уведут баланс в минус;
--   • выше 4-го тира не поднять, чужую башню не улучшить, флуд режется лимитом.
--
--   local ok, result = UpgradeService.UpgradeTower(player, tower)
--     true,  тир       — улучшено (1..4)
--     false, "причина" — отказ, причину можно показать игроку
--     nil              — запрос проигнорирован (флуд, башню уже продали, мусор вместо башни)
--
--   UpgradeService.Upgraded:Connect(function(player, tower, tier, stats) end) — сигнал для других систем

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local UpgradeData = require(ReplicatedStorage:WaitForChild("UpgradeData"))
local Guard = require(ServerScriptService:WaitForChild("Guard"))

local towersFolder = workspace:WaitForChild("Towers")

local UpgradeService = {
	RatePerSecond = 5, -- запросов в секунду в среднем
	Burst = 8,         -- подряд без паузы
}

local upgradedSignal = Instance.new("BindableEvent")
UpgradeService.Upgraded = upgradedSignal.Event

UpgradeData.validate(TowerData) -- ошибка в таблице тиров сразу будет видна в Output

local function getCoins(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins and (coins:IsA("IntValue") or coins:IsA("NumberValue")) then
		return coins
	end
	return nil
end

-- текущий тир башни: всегда целое число 0..макс
function UpgradeService.GetTier(tower)
	local level = tonumber(tower:GetAttribute("Level"))
	if not level or level ~= level then
		return 0
	end
	return math.clamp(math.floor(level), 0, UpgradeData.maxFor(TowerData[tower.Name]))
end

-- характеристики текущего тира → атрибуты башни (их видят клиенты).
-- Атакует башня по серверной таблице UpgradeData.get, атрибуты нужны только для показа.
function UpgradeService.ApplyStats(tower)
	local stats = UpgradeData.get(TowerData, tower.Name, UpgradeService.GetTier(tower))
	if not stats then
		return nil
	end
	tower:SetAttribute("Damage", stats.Damage)
	tower:SetAttribute("Range", stats.Range)
	tower:SetAttribute("AttackCooldown", stats.AttackCooldown)
	tower:SetAttribute("Special", stats.Special) -- имя усиления 4-го тира (до него nil)
	return stats
end

function UpgradeService.UpgradeTower(player, tower)
	-- 1. кто прислал и что
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	if not Guard.check(player, "UpgradeTower", UpgradeService.RatePerSecond, UpgradeService.Burst) then
		return nil -- лишние быстрые клики отбрасываются; за настоящий флуд Guard сам даст штраф
	end
	if tower == nil then
		return nil -- башню только что продали, запрос опоздал — это не чит
	end
	if typeof(tower) ~= "Instance" or not tower:IsA("Model") then
		Guard.flag(player, "UpgradeTower: argument is not a tower", 3)
		return nil
	end
	if tower.Parent ~= towersFolder then
		if tower.Parent ~= nil then
			Guard.flag(player, "UpgradeTower: object is not a placed tower", 2)
		end
		return nil
	end
	if tower:GetAttribute("OwnerId") ~= player.UserId then
		Guard.flag(player, "UpgradeTower: someone else's tower", 4)
		return false, "Not your tower"
	end
	if workspace:GetAttribute("MatchOver") then
		return false, "Match is over"
	end
	local config = TowerData[tower.Name]
	if not config then
		return false, "Unknown tower"
	end

	-- 2. тир и цена — только из серверных данных
	local tier = UpgradeService.GetTier(tower)
	if tier >= UpgradeData.maxFor(config) then
		return false, "Already max tier"
	end
	local nextTier = tier + 1
	local cost = UpgradeData.getCost(config, nextTier)
	if cost == math.huge then
		warn(string.format("[Upgrades] у %s нет корректной цены тира %d", tower.Name, nextTier))
		return false, "Upgrade unavailable"
	end

	-- 3. деньги: проверка и списание подряд, без yield
	local coins = getCoins(player)
	if not coins then
		return false, "No coins"
	end
	if coins.Value < cost then
		return false, string.format("Need $%d more", math.ceil(cost - coins.Value))
	end
	coins.Value -= cost

	-- 4. новый тир: уровень, вложения (от них цена продажи) и характеристики
	tower:SetAttribute("Invested", (tower:GetAttribute("Invested") or config.Price or 0) + cost)
	tower:SetAttribute("Level", nextTier)
	local stats = UpgradeService.ApplyStats(tower)
	upgradedSignal:Fire(player, tower, nextTier, stats)
	return true, nextTier
end

-- каждой поставленной башне — атрибуты начального тира
local function onTowerAdded(tower)
	if TowerData[tower.Name] then
		UpgradeService.ApplyStats(tower)
	end
end
towersFolder.ChildAdded:Connect(onTowerAdded)
for _, tower in ipairs(towersFolder:GetChildren()) do
	onTowerAdded(tower)
end

return UpgradeService
