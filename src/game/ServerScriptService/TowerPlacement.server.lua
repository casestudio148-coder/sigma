-- ServerScriptService.TowerPlacement — ЗАМЕНИТЕ старый код целиком
-- Постановка башен с защитой:
--   лимит запросов, проверка типов и NaN, только юниты из своего набора, только во время игры,
--   не на дорожке и не впритык к другим башням, под точкой должна быть земля.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local PlacementRules = require(ReplicatedStorage:WaitForChild("PlacementRules"))
local Guard = require(game:GetService("ServerScriptService"):WaitForChild("Guard"))
local PlaceTowerEvent = ReplicatedStorage:FindFirstChild("PlaceTower")
if not PlaceTowerEvent then
	PlaceTowerEvent = Instance.new("RemoteEvent")
	PlaceTowerEvent.Name = "PlaceTower"
	PlaceTowerEvent.Parent = ReplicatedStorage
end

for _, name in ipairs({ "Towers", "Players", "Mobs" }) do
	pcall(function() PhysicsService:RegisterCollisionGroup(name) end)
end
pcall(function() PhysicsService:CollisionGroupSetCollidable("Towers", "Players", false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Towers", "Mobs", false) end)
pcall(function() PhysicsService:CollisionGroupSetCollidable("Towers", "Towers", false) end)

local towersWorkspaceFolder = workspace:FindFirstChild("Towers")
if not towersWorkspaceFolder then
	towersWorkspaceFolder = Instance.new("Folder")
	towersWorkspaceFolder.Name = "Towers"
	towersWorkspaceFolder.Parent = workspace
end

local replicatedTowers = ReplicatedStorage:WaitForChild("Towers")

local function getBottomY(model)
	local lowest = math.huge
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			local cf, size = part.CFrame, part.Size
			local halfY = 0.5 * (
				math.abs(cf.RightVector.Y) * size.X
					+ math.abs(cf.UpVector.Y) * size.Y
					+ math.abs(cf.LookVector.Y) * size.Z
			)
			lowest = math.min(lowest, cf.Position.Y - halfY)
		end
	end
	return lowest
end

local function countPlayerTowers(player, towerName)
	local count = 0
	for _, tower in ipairs(towersWorkspaceFolder:GetChildren()) do
		if tower.Name == towerName and tower:GetAttribute("OwnerId") == player.UserId then
			count += 1
		end
	end
	return count
end

local function inLoadout(player, towerName)
	local attr = player:GetAttribute("Loadout")
	if typeof(attr) ~= "string" then return false end
	return table.find(string.split(attr, ","), towerName) ~= nil
end

-- под точкой должна быть настоящая земля (не воздух, не мобы, не персонажи)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function hasGround(position)
	local ignore = { towersWorkspaceFolder }
	local mobs = workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -6, 0), rayParams)
	return hit ~= nil
end

PlaceTowerEvent.OnServerEvent:Connect(function(player, towerName, position)
	if not Guard.check(player, "PlaceTower", 4, 6) then return end

	if typeof(towerName) ~= "string" or not Guard.isVector(position) then
		Guard.flag(player, "PlaceTower bad arguments", 5)
		return
	end
	if workspace:GetAttribute("Phase") ~= "Playing" or workspace:GetAttribute("MatchOver") then return end

	local config = TowerData[towerName]
	if not config then
		Guard.flag(player, "PlaceTower unknown unit " .. towerName, 5)
		return
	end
	if not inLoadout(player, towerName) then
		Guard.flag(player, "PlaceTower unit not in loadout", 3)
		return
	end

	if config.Limit and countPlayerTowers(player, towerName) >= config.Limit then return end
	if not PlacementRules.check(position, towersWorkspaceFolder) then return end
	if not hasGround(position) then
		return -- клик пришёлся на модель или край карты: просто не ставим
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if not coins or coins.Value < config.Price then return end

	local template = replicatedTowers:FindFirstChild(towerName)
	if not template then return end

	coins.Value -= config.Price

	local tower = template:Clone()
	tower:SetAttribute("OwnerId", player.UserId)
	tower:SetAttribute("Level", 0)
	tower:SetAttribute("Invested", config.Price)

	for _, d in ipairs(tower:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Towers"
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy() -- скрипты из модели (например, Animate) башне не нужны
		end
	end

	-- корень закреплён, конечности и шапки держатся суставами (фикс «разъехавшихся» моделей)
	PlacementRules.prepareRig(tower)

	local pivot = tower:GetPivot()
	tower:PivotTo(CFrame.new(position) * pivot.Rotation)

	local bottomY = getBottomY(tower)
	if bottomY ~= math.huge then
		tower:PivotTo(tower:GetPivot() + Vector3.new(0, position.Y - bottomY, 0))
	end

	tower.Parent = towersWorkspaceFolder

	-- после попадания в workspace суставы ставят части на места; ещё раз ровняем ноги по земле
	task.wait()
	if tower.Parent then
		local settledBottom = getBottomY(tower)
		if settledBottom ~= math.huge then
			tower:PivotTo(tower:GetPivot() + Vector3.new(0, position.Y - settledBottom, 0))
		end
		tower:SetAttribute("Ready", true)
	end
end)
