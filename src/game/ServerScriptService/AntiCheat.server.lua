-- ServerScriptService.AntiCheat (Script)
-- Защита, работающая сама по себе:
--   1. Мобы: сервер всегда владеет физикой мобов. Если кто-то перехватил управление — возвращаем и штрафуем.
--   2. Башни: позиция и закрепление (Anchored) сверяются с сервером, подмены откатываются.
--   3. Персонажи: телепорт / спидхак / полёт → откат на последнюю честную позицию + штраф.
--   4. Все RemoteEvent: общий лимит запросов; попытка вызвать событие «только для клиента» = штраф.
--   5. Приманка: фейковое событие AdminGiveCoins. Его вызывает только чит → кик.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Guard = require(game:GetService("ServerScriptService"):WaitForChild("Guard"))
local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))

local mobsFolder = workspace:WaitForChild("Mobs")
local towersFolder = workspace:WaitForChild("Towers")

---------------------------------------------------------------- 1-2. мобы и башни

local towerPivots = setmetatable({}, { __mode = "k" })

task.spawn(function()
	while true do
		task.wait(1)

		for _, mob in ipairs(mobsFolder:GetChildren()) do
			local root = mob.PrimaryPart or mob:FindFirstChild("HumanoidRootPart")
			if root and not root.Anchored then
				local ok, owner = pcall(function()
					return root:GetNetworkOwner()
				end)
				if ok and owner ~= nil then
					pcall(function() root:SetNetworkOwner(nil) end)
					Guard.flag(owner, "took control of mob " .. mob.Name, 3)
				end
			end
		end

		for _, tower in ipairs(towersFolder:GetChildren()) do
			if not TowerData[tower.Name] or tower:GetAttribute("OwnerId") == nil then
				tower:Destroy() -- башню мог создать только сервер с OwnerId
			elseif tower:GetAttribute("Ready") then
				local saved = towerPivots[tower]
				if not saved then
					towerPivots[tower] = tower:GetPivot()
				elseif (tower:GetPivot().Position - saved.Position).Magnitude > 0.5 then
					tower:PivotTo(saved)
				end
				-- корень башни всегда закреплён (конечности держатся за него суставами)
				local root = tower:FindFirstChild("HumanoidRootPart") or tower.PrimaryPart
				if root and not root.Anchored then
					root.Anchored = true
				end
			end
		end
	end
end)

---------------------------------------------------------------- 3. движение персонажей

local CHECK = 0.5
local states = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function resetState(player, graceSeconds)
	states[player] = { grace = os.clock() + (graceSeconds or 4), air = 0 }
end

Players.PlayerAdded:Connect(function(player)
	resetState(player)
	player.CharacterAdded:Connect(function()
		resetState(player, 4)
	end)
end)
for _, p in ipairs(Players:GetPlayers()) do
	resetState(p)
	p.CharacterAdded:Connect(function() resetState(p, 4) end)
end
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(CHECK)
		local now = os.clock()

		for _, player in ipairs(Players:GetPlayers()) do
			local s = states[player]
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")

			if s and hrp and hum and hum.Health > 0 then
				local pos = hrp.Position

				if s.lastPos and now > s.grace and not hum.Sit then
					local dt = now - s.lastTime
					local flatDist = Vector3.new(pos.X - s.lastPos.X, 0, pos.Z - s.lastPos.Z).Magnitude
					-- запас на пинг: лагающий игрок может «догнать» сразу ~1 секунду движения
					local allowed = (hum.WalkSpeed * 1.5 + 8) * math.max(dt, 1) + 10

					if flatDist > allowed then
						hrp.CFrame = CFrame.new(s.lastPos) * hrp.CFrame.Rotation
						hrp.AssemblyLinearVelocity = Vector3.zero
						Guard.flag(player, string.format("speed/teleport (%.0f studs in %.1fs)", flatDist, dt), flatDist > 80 and 5 or 2)
						s.lastTime = now
						continue
					end

					rayParams.FilterDescendantsInstances = { char, mobsFolder }
					local hit = workspace:Raycast(pos, Vector3.new(0, -14, 0), rayParams)
					if hit then
						s.air = 0
						s.lastGround = pos
					elseif hrp.AssemblyLinearVelocity.Y > -2 then
						s.air += dt
						if s.air > 3 then
							Guard.flag(player, "fly", 3)
							if s.lastGround then
								hrp.CFrame = CFrame.new(s.lastGround) * hrp.CFrame.Rotation
								hrp.AssemblyLinearVelocity = Vector3.zero
							end
							s.air = 0
						end
					else
						s.air = math.max(0, s.air - dt)
					end
				end

				s.lastPos = hrp.Position
				s.lastTime = now
			end
		end
	end
end)

---------------------------------------------------------------- 4. все RemoteEvent

-- эти события сервер шлёт клиенту; клиент вызывать их не должен
local SERVER_TO_CLIENT = {
	TowerFX = true,
	AbilityFX = true,
	PlaytimeRewardGranted = true,
	MatchResult = true,
}

local function hookRemote(r)
	if not r:IsA("RemoteEvent") then return end
	r.OnServerEvent:Connect(function(player)
		if SERVER_TO_CLIENT[r.Name] then
			Guard.flag(player, "fired server-only remote " .. r.Name, 10)
			return
		end
		Guard.check(player, "*any remote", 25, 50)
	end)
end

for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
	hookRemote(d)
end
ReplicatedStorage.DescendantAdded:Connect(hookRemote)

---------------------------------------------------------------- 5. приманка

local bait = Instance.new("RemoteEvent")
bait.Name = "AdminGiveCoins"
bait.Parent = ReplicatedStorage
bait.OnServerEvent:Connect(function(player)
	Guard.flag(player, "honeypot AdminGiveCoins", 100)
end)
