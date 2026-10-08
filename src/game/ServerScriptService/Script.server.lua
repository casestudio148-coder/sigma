-- ServerScriptService.Script — ЗАМЕНИТЕ старый код целиком (версия для карт с любым числом поворотов)
-- Матч: сложность, генератор волн, мобы и их способности, голосование за пропуск,
-- база, монеты матча, награда за прохождение (Cash / Gems) и экран результатов.
-- Интерфейс рисуют клиентские скрипты HUD / SkipUI по атрибутам workspace.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local DifficultyData = require(ReplicatedStorage:WaitForChild("DifficultyData"))
local MapConfig = require(ReplicatedStorage:WaitForChild("MapConfig"))
-- уровень текущей карты (Easy / Normal / Hard / Insane): множители мобов и наград
local function mapTier()
	return MapConfig.tier(workspace:GetAttribute("MapId"))
end
local Guard = require(game:GetService("ServerScriptService"):WaitForChild("Guard"))
-- новая боевая система: босс-фазы и статус-эффекты (CombatService создаёт папку workspace.Mobs)
local BossController = require(game:GetService("ServerScriptService"):WaitForChild("BossController"))
local ReplicatedMobs = ReplicatedStorage:WaitForChild("Mobs")

local mobFolder = workspace:FindFirstChild("Mobs")
if not mobFolder then
	mobFolder = Instance.new("Folder")
	mobFolder.Name = "Mobs"
	mobFolder.Parent = workspace
end

pcall(function()
	PhysicsService:RegisterCollisionGroup("Mobs")
	PhysicsService:RegisterCollisionGroup("Players")
	PhysicsService:CollisionGroupSetCollidable("Mobs", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Mobs", "Mobs", false)
end)

local function getOrCreateEvent(name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = ReplicatedStorage
	end
	return e
end

local resultEvent = getOrCreateEvent("MatchResult")

---------------------------------------------------------------- состояние матча

local difficulty = DifficultyData[DifficultyData.Default]
local MAX_BASE_HEALTH = difficulty.BaseHP
local currentBaseHealth = MAX_BASE_HEALTH
local currentWave = 1
local waveStatusText = ""
local Waves = {}
local matchStarted = false
local joinedAtWave = {}

local function setupPlayerCharacter(character)
	for _, child in ipairs(character:GetDescendants()) do
		if child:IsA("BasePart") then child.CollisionGroup = "Players" end
	end
end

local function onPlayerAdded(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = matchStarted and difficulty.StartCoins or 0
	coins.Parent = leaderstats

	joinedAtWave[player] = matchStarted and currentWave or 1

	player.CharacterAdded:Connect(setupPlayerCharacter)
	if player.Character then setupPlayerCharacter(player.Character) end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end
Players.PlayerRemoving:Connect(function(player)
	joinedAtWave[player] = nil
end)

---------------------------------------------------------------- путь мобов: P1 → P2 → ... → Pn
-- Точки ставит MapService, когда построит карту (сколько угодно поворотов).
-- Если MapService нет — берутся точки P1 / P2 / P3..., стоящие на карте в Workspace (как раньше).

local pathPoints = {}

local function loadPath()
	-- карта ещё строится — ждём (не дольше минуты)
	local waited = 0
	while workspace:GetAttribute("MapReady") == false and waited < 60 do
		waited += task.wait(0.25)
	end
	if not workspace:FindFirstChild("P1") then
		workspace:WaitForChild("P1", 10)
	end
	local list = {}
	local i = 1
	while true do
		local point = workspace:FindFirstChild("P" .. i)
		if not point then break end
		table.insert(list, point)
		i += 1
	end
	if #list < 2 then
		return false
	end
	for _, point in ipairs(list) do
		if point:IsA("BasePart") then
			point.Anchored = true
			point.CanCollide = false
		end
	end
	pathPoints = list
	return true
end

---------------------------------------------------------------- генератор волн

-- { моб, стоимость в очках бюджета, с какой волны появляется }
local ROSTER = {
	{ "Normal", 1, 1 },
	{ "Fast", 1, 3 },
	{ "Swarm", 0.5, 4 },
	{ "Slow", 2, 5 },
	{ "Shielded", 3, 7 },
	{ "Flying", 3, 9 },
	{ "Regen", 5, 11 },
	{ "Healer", 4, 12 },
	{ "Ghost", 4, 14 },
	{ "Necromancer", 7, 16 },
	{ "Berserker", 9, 18 },
	{ "VoidHound", 8, 20 },
	{ "ArmoredTank", 15, 22 },
}

local function mobExists(name)
	local cfg = MobData[name]
	return cfg ~= nil and ReplicatedMobs:FindFirstChild(cfg.Model or name) ~= nil
end

local function buildWaves(diff)
	local waves = {}
	local total = diff.Waves

	for w = 1, total do
		local rng = Random.new(w * 7919 + total * 31)
		local budget = 3 + w * 2.5 + 0.5 * w ^ 1.6

		local pool = {}
		for _, e in ipairs(ROSTER) do
			if w >= e[3] and mobExists(e[1]) then
				table.insert(pool, e)
			end
		end
		if #pool == 0 then
			pool = { { "Normal", 1, 1 } }
		end

		local list = {}
		while budget > 0.4 and #list < 150 do
			-- новые мобы выпадают чаще (вес = позиция в списке)
			local totalWeight = #pool * (#pool + 1) / 2
			local r = rng:NextNumber() * totalWeight
			local pick = pool[1]
			for i, e in ipairs(pool) do
				r -= i
				if r <= 0 then
					pick = e
					break
				end
			end
			if pick[2] > budget then pick = pool[1] end
			table.insert(list, pick[1])
			budget -= pick[2]
		end

		if w % 10 == 0 and w < total and mobExists("MiniBoss") then
			for _ = 1, math.floor(w / 10) do
				table.insert(list, "MiniBoss")
			end
		end
		if w == total and mobExists("MapBoss") then
			table.insert(list, "MapBoss")
		end

		waves[w] = {
			Mobs = list,
			Delay = math.clamp(0.9 - w * 0.022, 0.25, 0.9),
			WaveReward = math.floor((60 + w * 10) * diff.WaveRewardMult * 0.5),
		}
	end

	return waves
end

---------------------------------------------------------------- интерфейс (атрибуты для клиентов)

local function updateHealthUI()
	workspace:SetAttribute("BaseHP", currentBaseHealth)
	workspace:SetAttribute("MaxBaseHP", MAX_BASE_HEALTH)
	workspace:SetAttribute("Wave", math.min(currentWave, math.max(#Waves, 1)))
	workspace:SetAttribute("MaxWaves", #Waves > 0 and #Waves or difficulty.Waves)
	workspace:SetAttribute("DifficultyName", difficulty.Name)

	local showStatus = string.find(waveStatusText, "in %d") ~= nil or string.find(waveStatusText, "VICTORY") ~= nil
	workspace:SetAttribute("StatusText", showStatus and waveStatusText or "")
end

updateHealthUI()

local function takeBaseDamage(amount)
	if currentBaseHealth <= 0 then return end
	currentBaseHealth = math.max(0, currentBaseHealth - amount)
	updateHealthUI()
	if currentBaseHealth <= 0 then
		mobFolder:ClearAllChildren()
	end
end

local function addCoinsToPlayers(amount)
	for _, player in ipairs(Players:GetPlayers()) do
		local stats = player:FindFirstChild("leaderstats")
		if stats and stats:FindFirstChild("Coins") then
			stats.Coins.Value += amount
		end
	end
end

---------------------------------------------------------------- голосование за пропуск ожидания

local INTERMISSION_FIRST = 20
local INTERMISSION = 10
local VOTE_TIME = 8
local VOTE_COOLDOWN = 10

local skipEvent = getOrCreateEvent("SkipVote")

workspace:SetAttribute("CanSkip", false)
workspace:SetAttribute("SkipVoteActive", false)
workspace:SetAttribute("SkipVoteTime", VOTE_TIME)

local canSkip = false
local skipNow = false
local vote = nil

local function countVotes()
	local yes, no = 0, 0
	for _, v in pairs(vote.votes) do
		if v then yes += 1 else no += 1 end
	end
	return yes, no
end

local function publishVote()
	if not vote then
		workspace:SetAttribute("SkipVoteActive", false)
		return
	end
	local yes, no = countVotes()
	workspace:SetAttribute("SkipYes", yes)
	workspace:SetAttribute("SkipNo", no)
	workspace:SetAttribute("SkipTotal", #Players:GetPlayers())
	workspace:SetAttribute("SkipVoteEndsAt", vote.endsAt)
	workspace:SetAttribute("SkipVoteStarter", vote.starter.UserId)
	workspace:SetAttribute("SkipVoteActive", true)
end

local function endVote(passed, withCooldown)
	vote = nil
	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("SkipChoice", nil)
	end
	publishVote()
	if passed then
		skipNow = true
	elseif withCooldown then
		workspace:SetAttribute("SkipCooldownUntil", workspace:GetServerTimeNow() + VOTE_COOLDOWN)
	end
end

local function evaluateVote()
	if not vote then return end
	local yes, no = countVotes()
	local total = #Players:GetPlayers()
	if yes > total / 2 then
		endVote(true)
	elseif total - no <= total / 2 then
		endVote(false, true)
	end
end

skipEvent.OnServerEvent:Connect(function(player, action)
	if not Guard.check(player, "SkipVote", 3, 5) then return end
	if typeof(action) ~= "string" then
		Guard.flag(player, "SkipVote bad argument", 2)
		return
	end
	if not canSkip then return end

	if action == "start" then
		if vote then return end
		if workspace:GetServerTimeNow() < (workspace:GetAttribute("SkipCooldownUntil") or 0) then return end

		if #Players:GetPlayers() <= 1 then
			skipNow = true
			return
		end

		vote = {
			votes = { [player] = true },
			endsAt = workspace:GetServerTimeNow() + VOTE_TIME,
			starter = player,
		}
		player:SetAttribute("SkipChoice", "yes")
		publishVote()
		evaluateVote()

	elseif (action == "yes" or action == "no") and vote and vote.votes[player] == nil then
		vote.votes[player] = (action == "yes")
		player:SetAttribute("SkipChoice", action)
		publishVote()
		evaluateVote()
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if not vote then return end
	if vote.starter == player then
		endVote(false, false)
	else
		vote.votes[player] = nil
		task.delay(0.2, function()
			publishVote()
			evaluateVote()
		end)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		if vote and workspace:GetServerTimeNow() >= vote.endsAt then
			endVote(false, true)
		end
	end
end)

---------------------------------------------------------------- движение и спавн мобов

local ARRIVE_DISTANCE = 3

local function moveToPoint(humanoid, rootPart, targetPosition)
	local lastPos = rootPart.Position
	local lastCheck = os.clock()
	local stuck = false
	local halted = false -- моб стоял под станом / заморозкой — это не «застрял»

	while true do
		if not humanoid.Parent or not rootPart.Parent
			or humanoid.Health <= 0 or currentBaseHealth <= 0 then
			return false
		end

		local pos = rootPart.Position
		local offset = Vector3.new(targetPosition.X - pos.X, 0, targetPosition.Z - pos.Z)
		if offset.Magnitude <= ARRIVE_DISTANCE then
			return true
		end

		humanoid:MoveTo(targetPosition)

		if stuck and humanoid.WalkSpeed > 0 then
			local step = math.min(humanoid.WalkSpeed * 0.1, offset.Magnitude)
			rootPart.CFrame = rootPart.CFrame + offset.Unit * step
		end

		task.wait(0.1)
		if humanoid.WalkSpeed <= 0 then halted = true end

		if os.clock() - lastCheck >= 0.5 then
			local now = rootPart.Position
			local moved = Vector3.new(now.X - lastPos.X, 0, now.Z - lastPos.Z).Magnitude
			stuck = not halted and humanoid.WalkSpeed > 0 and moved < humanoid.WalkSpeed * 0.5 * 0.2
			halted = false
			lastPos = now
			lastCheck = os.clock()
		end
	end
end

-- opts: position (Vector3), waypoint (1 = идёт к P2, 2 = к P3, ...), noReward, healthMult
local function spawnMob(mobName, opts)
	if currentBaseHealth <= 0 then return end
	opts = opts or {}

	local config = MobData[mobName]
	-- миньоны могут брать чужую модель (поле Model в MobData)
	local template = config and ReplicatedMobs:FindFirstChild(config.Model or mobName)
	if not template or not config then
		warn("[Mob] Нет модели или записи MobData: " .. tostring(mobName))
		return
	end

	local mob = template:Clone()
	mob.Name = mobName -- имя должно совпадать с MobData (по нему работают теги, награды и эффекты)
	local humanoid = mob:FindFirstChildOfClass("Humanoid")
	local rootPart = mob:FindFirstChild("HumanoidRootPart") or mob.PrimaryPart or mob:FindFirstChild("Torso")
	if not humanoid or not rootPart then
		warn("[Mob] У модели " .. mobName .. " нет Humanoid или корневой части")
		mob:Destroy()
		return
	end
	if not mob.PrimaryPart then
		mob.PrimaryPart = rootPart
	end

	for _, part in ipairs(mob:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Mobs"
			part.Anchored = false
		end
	end

	-- окраска уникальных миньонов (поле Tint в MobData)
	if config.Tint then
		local bodyColors = mob:FindFirstChildOfClass("BodyColors")
		if bodyColors then bodyColors:Destroy() end
		for _, part in ipairs(mob:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 1 then
				part.Color = part.Color:Lerp(config.Tint, 0.65)
			end
		end
	end

	local tierCfg = mapTier()
	local hpScale = (1 + 0.12 * (currentWave - 1)) * difficulty.HealthMult * tierCfg.HealthMult * (opts.healthMult or 1)
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	humanoid.MaxHealth = math.max(1, (config.Health or 100) * hpScale)
	humanoid.Health = humanoid.MaxHealth
	local baseSpeed = (config.Speed or 10) * difficulty.SpeedMult * tierCfg.SpeedMult
	humanoid.WalkSpeed = baseSpeed
	mob:SetAttribute("BaseSpeed", baseSpeed) -- от неё StatusEffectManager считает замедления и ускорения

	if config.Special and config.Special.ShieldHP then
		local shield = config.Special.ShieldHP * hpScale
		mob:SetAttribute("Shield", shield)
		mob:SetAttribute("MaxShield", shield)
	end

	local reward = opts.noReward and 0 or math.max(1, math.floor((config.RewardGold or 3) * difficulty.KillRewardMult + 0.5))
	mob:SetAttribute("Reward", reward)

	local lastPoint = #pathPoints
	local waypoint = math.clamp(opts.waypoint or 1, 1, lastPoint - 1)
	mob:SetAttribute("Waypoint", waypoint)
	mob.Parent = mobFolder

	local startPos = opts.position or (pathPoints[1].Position + Vector3.new(0, 3, 0))
	local firstTarget = pathPoints[waypoint + 1].Position
	mob:PivotTo(CFrame.lookAt(startPos, Vector3.new(firstTarget.X, startPos.Y, firstTarget.Z)))

	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	-- босс: фазы на 50% / 20%, призыв миньонов, навыки (BossData)
	if BossController.IsBoss(mobName) then
		BossController.Attach(mob, mobName)
	end

	-- награда ровно один раз: из Died или из потока движения
	-- (Died приходит на следующем шаге физики; если моба уже удалили — не придёт вовсе)
	local coinAwarded = false
	local function awardKill()
		if coinAwarded then return end
		coinAwarded = true
		if reward > 0 then addCoinsToPlayers(reward) end
	end
	humanoid.Died:Connect(function()
		awardKill()
		task.delay(0.8, function()
			if mob.Parent then mob:Destroy() end
		end)
	end)

	task.spawn(function()
		local alive = true
		for k = waypoint, lastPoint - 1 do
			alive = moveToPoint(humanoid, rootPart, pathPoints[k + 1].Position) and mob.Parent ~= nil
			if not alive then break end
			if k + 1 < lastPoint then
				mob:SetAttribute("Waypoint", k + 1)
			end
		end

		if alive and mob.Parent then
			takeBaseDamage(config.LeakDamage or 5)
		elseif mob.Parent and humanoid.Health <= 0 then
			awardKill()
			task.wait(0.8) -- даём проиграться эффекту смерти
		end

		if mob.Parent then
			mob:Destroy()
		end
	end)

	return mob
end

-- боссы призывают миньонов через эту же функцию
BossController.Init({ SpawnMob = spawnMob })

---------------------------------------------------------------- способности мобов

local timers = setmetatable({}, { __mode = "k" })
local summonCount = setmetatable({}, { __mode = "k" })

task.spawn(function()
	while true do
		task.wait(0.5)
		local now = os.clock()

		for _, mob in ipairs(mobFolder:GetChildren()) do
			local config = MobData[mob.Name]
			local sp = config and config.Special
			local hum = mob:FindFirstChildOfClass("Humanoid")
			local root = mob.PrimaryPart

			if sp and hum and hum.Health > 0 and root then
				local t = timers[mob]
				if not t then
					t = { born = now }
					timers[mob] = t
				end

				-- Troll: восстанавливает долю здоровья
				if sp.RegenAmount and now - (t.regen or 0) >= (sp.RegenInterval or 1) then
					t.regen = now
					local amount = hum.MaxHealth * (sp.RegenAmount / (config.Health or 100))
					hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
				end

				-- Shaman: лечит соседей
				if sp.HealAmount and now - (t.heal or 0) >= (sp.HealInterval or 2) then
					t.heal = now
					local radius = math.max(sp.HealRadius or 5, 10)
					for _, other in ipairs(mobFolder:GetChildren()) do
						local oh = other:FindFirstChildOfClass("Humanoid")
						local orp = other.PrimaryPart
						if other ~= mob and oh and oh.Health > 0 and orp and (orp.Position - root.Position).Magnitude <= radius then
							oh.Health = math.min(oh.MaxHealth, oh.Health + oh.MaxHealth * 0.04)
						end
					end
				end

				-- Necromancer: призывает мобов (без награды, максимум 5 живых)
				if sp.SummonEnemyID and now - (t.summon or t.born) >= (sp.SummonInterval or 3) then
					t.summon = now
					local list = summonCount[mob] or {}
					for i = #list, 1, -1 do
						if not list[i].Parent then table.remove(list, i) end
					end
					if #list < 5 then
						local summoned = spawnMob(sp.SummonEnemyID, {
							position = root.Position + Vector3.new(math.random(-2, 2), 0, math.random(-2, 2)),
							waypoint = mob:GetAttribute("Waypoint") or 1,
							noReward = true,
							healthMult = 0.6,
						})
						if summoned then table.insert(list, summoned) end
					end
					summonCount[mob] = list
				end

				-- навыки боссов (отключение башен, боевой клич, регенерация) — в BossController / BossData
			end
		end
	end
end)

---------------------------------------------------------------- итоги матча

local function finishMatch(victory)
	workspace:SetAttribute("MatchOver", true)
	workspace:SetAttribute("CanSkip", false)

	local cleared = victory and #Waves or math.max(0, currentWave - 1)
	local rewardMult = mapTier().RewardMult or 1
	local baseCash = math.floor((difficulty.CashPerWave * cleared + (victory and difficulty.VictoryCash or 0)) * rewardMult + 0.5)
	local gems = math.floor((victory and difficulty.VictoryGems or 0) * rewardMult + 0.5)

	for _, player in ipairs(Players:GetPlayers()) do
		-- зашедшие посреди матча получают долю за волны, которые застали
		local joined = joinedAtWave[player] or 1
		local share = cleared > 0 and math.clamp((cleared - joined + 1) / cleared, 0, 1) or 0
		local cash = math.floor(baseCash * share)
		local myGems = share >= 0.5 and gems or 0

		local data = player:FindFirstChild("Data")
		if data then
			local c = data:FindFirstChild("Cash")
			local g = data:FindFirstChild("Gems")
			if c then c.Value += cash end
			if g then g.Value += myGems end
		end

		resultEvent:FireClient(player, {
			victory = victory,
			wave = cleared,
			total = #Waves,
			cash = cash,
			gems = myGems,
			difficulty = difficulty.Name,
		})
	end
end

---------------------------------------------------------------- ОСНОВНОЙ ЦИКЛ

while workspace:GetAttribute("Phase") ~= "Playing" do
	task.wait(0.25)
end

if not loadPath() then
	warn("[Match] Нет точек пути P1, P2... — добавь MapService (строит карты) или поставь точки P1, P2, P3 на карту")
	return
end

difficulty = DifficultyData[workspace:GetAttribute("Difficulty") or ""] or DifficultyData[DifficultyData.Default]
MAX_BASE_HEALTH = difficulty.BaseHP
currentBaseHealth = MAX_BASE_HEALTH
Waves = buildWaves(difficulty)
matchStarted = true

for _, player in ipairs(Players:GetPlayers()) do
	local stats = player:FindFirstChild("leaderstats")
	if stats and stats:FindFirstChild("Coins") then
		stats.Coins.Value = difficulty.StartCoins
	end
end

updateHealthUI()
task.wait(1)

while currentBaseHealth > 0 and currentWave <= #Waves do
	skipNow = false
	canSkip = true
	workspace:SetAttribute("CanSkip", true)

	local remaining = currentWave == 1 and INTERMISSION_FIRST or INTERMISSION
	while remaining > 0 and not skipNow do
		waveStatusText = "Wave " .. currentWave .. " in " .. math.ceil(remaining) .. "s..."
		updateHealthUI()
		task.wait(0.25)
		remaining -= 0.25
	end

	canSkip = false
	workspace:SetAttribute("CanSkip", false)
	if vote then endVote(false, false) end

	waveStatusText = "WAVE " .. currentWave .. " / " .. #Waves
	updateHealthUI()

	local waveData = Waves[currentWave]
	for _, mobName in ipairs(waveData.Mobs) do
		if currentBaseHealth <= 0 then break end
		spawnMob(mobName)
		task.wait(waveData.Delay)
	end

	while #mobFolder:GetChildren() > 0 and currentBaseHealth > 0 do
		task.wait(0.5)
	end

	if currentBaseHealth > 0 then
		addCoinsToPlayers(waveData.WaveReward)
		currentWave += 1
	end
end

if currentBaseHealth > 0 then
	waveStatusText = "VICTORY! ALL WAVES CLEARED!"
	updateHealthUI()
	finishMatch(true)
else
	finishMatch(false)
end
