-- ServerScriptService.AbilityService (Script)
-- Способности башен на сервере:
--   • АКТИВНЫЕ (кнопка / клавиша Q): проверка владельца, уровня, перезарядки → эффект → AbilityFX всем
--   • АУРЫ (пассивные): каждые 0.5 с Паладин обновляет союзным башням короткий бафф урона и скорости.
--     Паладина продали или отключили → бафф сам истечёт через долю секунды. Ничего не нужно «снимать».
-- Все длительные способности (облако, чёрная дыра, гроза) живут в Janitor, привязанном к башне:
-- башню продали — способность корректно останавливается, потоки не висят.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local UpgradeData = require(ReplicatedStorage:WaitForChild("UpgradeData"))
local AbilityData = require(ReplicatedStorage:WaitForChild("AbilityData"))
local Janitor = require(ReplicatedStorage:WaitForChild("Janitor"))
local Guard = require(ServerScriptService:WaitForChild("Guard"))
local SEM = require(ServerScriptService:WaitForChild("StatusEffectManager"))
local Combat = require(ServerScriptService:WaitForChild("CombatService"))

local towersFolder = Combat.TowersFolder

local function getOrCreateEvent(name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = ReplicatedStorage
	end
	return e
end

local useEvent = getOrCreateEvent("UseAbility") -- клиент -> сервер (и ответ "ok"/"fail")
local fxEvent = getOrCreateEvent("AbilityFX")   -- сервер -> все клиенты (эффекты)

local AURA_TICK = 0.5

local function getStats(tower)
	if not TowerData[tower.Name] then return nil end
	return UpgradeData.get(TowerData, tower.Name, tower:GetAttribute("Level") or 0)
end

local function matchRunning()
	return workspace:GetAttribute("Phase") == "Playing" and not workspace:GetAttribute("MatchOver")
end

-- повторять onTick каждые interval секунд в течение duration; затем onEnd.
-- Остановится сам, если башню убрали или матч закончился.
local function runTimed(tower, duration, interval, onTick, onEnd)
	local j = Janitor.new()
	j:LinkToInstance(tower)
	j:Add(task.spawn(function()
		local elapsed, ticks = 0, 0
		while elapsed < duration - 1e-3 do
			if not matchRunning() then
				j:Destroy()
				return
			end
			ticks += 1
			local ok, err = pcall(onTick, ticks, elapsed)
			if not ok then warn("[Ability] " .. tostring(err)) end
			task.wait(interval)
			elapsed += interval
		end
		if onEnd and matchRunning() then
			local ok, err = pcall(onEnd)
			if not ok then warn("[Ability] " .. tostring(err)) end
		end
		j:Destroy()
	end))
	return j
end

local function afterDelay(seconds, fn)
	task.delay(seconds, function()
		if not matchRunning() then return end
		local ok, err = pcall(fn)
		if not ok then warn("[Ability] " .. tostring(err)) end
	end)
end

---------------------------------------------------------------- ОБРАБОТЧИКИ СПОСОБНОСТЕЙ
-- ctx: tower, player, def, stats, level, pos (центр башни), origin, range, detector
-- вернуть таблицу для эффектов (AbilityFX) или nil, "причина отказа"

local Handlers = {}

-- 🏹 Archer: 3 залпа стрел по самой плотной толпе
Handlers.ArrowRain = function(ctx)
	local def, tower = ctx.def, ctx.tower
	local center = Combat.BestCluster(ctx.pos, ctx.range, def.Radius, ctx)
	if not center then return nil, "No enemies in range" end
	local dmg = (ctx.stats.Damage or 0) * def.DamageMult
	runTimed(tower, def.Volleys * def.Interval, def.Interval, function()
		fxEvent:FireAllClients({ id = "ArrowVolley", center = center, radius = def.Radius })
		Combat.ForEachMobInRadius(center, def.Radius, function(e)
			Combat.Damage(e.mob, dmg, "Physical", tower)
		end)
	end)
	return { center = center, radius = def.Radius }
end

-- ☄️ Mage: метеор + горение
Handlers.Meteor = function(ctx)
	local def, tower = ctx.def, ctx.tower
	local center = Combat.BestCluster(ctx.pos, ctx.range, def.Radius, ctx)
	if not center then return nil, "No enemies in range" end
	local dmg = (ctx.stats.Damage or 0) * def.DamageMult
	afterDelay(def.FallTime, function()
		Combat.ForEachMobInRadius(center, def.Radius, function(e)
			local killed = Combat.Damage(e.mob, dmg, "Magic", tower)
			if not killed then
				SEM.Apply(e.mob, "Burn", {
					Magnitude = def.BurnDPS, Duration = def.BurnDuration,
					Stacks = def.BurnStacks, MaxStacks = 5, Source = tower,
				})
			end
		end)
	end)
	return { center = center, radius = def.Radius, fall = def.FallTime }
end

-- 🌨️ IceMage: заморозка области, после неё замедление
Handlers.Blizzard = function(ctx)
	local def, tower = ctx.def, ctx.tower
	local center = Combat.BestCluster(ctx.pos, ctx.range, def.Radius, ctx)
	if not center then return nil, "No enemies in range" end
	local dmg = (ctx.stats.Damage or 0) * def.DamageMult
	Combat.ForEachMobInRadius(center, def.Radius, function(e)
		local killed = Combat.Damage(e.mob, dmg, "Magic", tower)
		if not killed then
			SEM.Apply(e.mob, "Freeze", { Duration = def.FreezeDuration, Source = tower })
			SEM.Apply(e.mob, "Slow", {
				Magnitude = def.SlowAfter, Duration = def.FreezeDuration + def.SlowDuration, Key = "Blizzard",
			})
		end
	end)
	return { center = center, radius = def.Radius, duration = def.FreezeDuration }
end

-- ☁️ DartSpitter: ядовитое облако
Handlers.ToxicCloud = function(ctx)
	local def, tower = ctx.def, ctx.tower
	local center = Combat.BestCluster(ctx.pos, ctx.range, def.Radius, ctx)
	if not center then return nil, "No enemies in range" end
	runTimed(tower, def.Duration, 0.5, function()
		Combat.ForEachMobInRadius(center, def.Radius, function(e)
			SEM.Apply(e.mob, "Poison", { Magnitude = def.PoisonDPS, Duration = 1.5, Source = tower })
			SEM.Apply(e.mob, "Slow", { Magnitude = def.Slow, Duration = 0.7, Key = "ToxicCloud" })
		end)
	end)
	return { center = center, radius = def.Radius, duration = def.Duration }
end

-- 💣 BomberTower: ковровая бомбардировка по передним врагам
Handlers.CarpetBomb = function(ctx)
	local def, tower = ctx.def, ctx.tower
	local targets = Combat.GetTargets(ctx.pos, ctx.range, "First", def.Bombs, ctx)
	if #targets == 0 then return nil, "No enemies in range" end
	local points = {}
	for i = 1, def.Bombs do
		local e = targets[((i - 1) % #targets) + 1]
		local jitter = i > #targets and Vector3.new(math.random(-5, 5), 0, math.random(-5, 5)) or Vector3.zero
		points[i] = e.pos + jitter
	end
	local dmg = (ctx.stats.Damage or 0) * def.DamageMult
	for i, p in ipairs(points) do
		afterDelay(def.FallTime + (i - 1) * def.Step, function()
			Combat.ForEachMobInRadius(p, def.Radius, function(e)
				local killed = Combat.Damage(e.mob, dmg, "Physical", tower)
				if not killed then
					SEM.Apply(e.mob, "Burn", { Magnitude = def.BurnDPS, Duration = def.BurnDuration, MaxStacks = 3, Source = tower })
				end
			end)
		end)
	end
	return { points = points, fall = def.FallTime, step = def.Step, radius = def.Radius }
end

-- 🎯 Assassin: метка смерти на самого сильного
Handlers.MarkForDeath = function(ctx)
	local def, tower = ctx.def, ctx.tower
	local t = Combat.GetTargets(ctx.pos, ctx.range, "Strongest", 1, { detector = true })[1]
	if not t then return nil, "No enemies in range" end
	SEM.Apply(t.mob, "Vulnerable", { Magnitude = def.Vulnerable, Duration = def.Duration, Key = "Mark" })
	SEM.Apply(t.mob, "Stun", { Duration = def.StunDuration, Source = tower })
	Combat.Damage(t.mob, (ctx.stats.Damage or 0) * def.DamageMult, "Physical", tower)
	return { target = t.pos, duration = def.Duration }
end

-- 🦠 Necromancer: чума (уязвимость + яд)
Handlers.Plague = function(ctx)
	local def, tower = ctx.def, ctx.tower
	local targets = Combat.GetTargets(ctx.pos, ctx.range, "Strongest", def.MaxTargets, { detector = true })
	if #targets == 0 then return nil, "No enemies in range" end
	local pts = {}
	for _, e in ipairs(targets) do
		SEM.Apply(e.mob, "Vulnerable", { Magnitude = def.Vulnerable, Duration = def.Duration, Key = "Plague" })
		SEM.Apply(e.mob, "Poison", { Magnitude = def.PoisonDPS, Duration = def.Duration, Source = tower })
		table.insert(pts, e.pos)
	end
	return { points = pts }
end

-- 🔱 CrossbowTower: болт насквозь через всю линию
Handlers.Ballista = function(ctx)
	local def, tower = ctx.def, ctx.tower
	local first = Combat.GetTargets(ctx.pos, ctx.range, "First", 1, { detector = true })[1]
	if not first then return nil, "No enemies in range" end
	local dir = Vector3.new(first.pos.X - ctx.pos.X, 0, first.pos.Z - ctx.pos.Z)
	if dir.Magnitude < 0.01 then dir = Vector3.new(0, 0, -1) end
	dir = dir.Unit
	local length = ctx.range * def.LengthMult
	local dmg = (ctx.stats.Damage or 0) * def.DamageMult
	local hits = {}
	Combat.ForEachMob(function(e)
		local rel = Vector3.new(e.pos.X - ctx.pos.X, 0, e.pos.Z - ctx.pos.Z)
		local along = rel:Dot(dir)
		if along > 0 and along <= length and (rel - dir * along).Magnitude <= def.Width then
			local killed = Combat.Damage(e.mob, dmg, "Physical", tower)
			if not killed then
				SEM.Apply(e.mob, "Stun", { Duration = def.StunDuration, Source = tower })
			end
			table.insert(hits, e.pos)
		end
	end)
	return { endPos = ctx.origin + dir * length, hits = hits }
end

-- 📯 Paladin: союзные башни рядом быстрее и сильнее
Handlers.Rally = function(ctx)
	local def = ctx.def
	local buffed = {}
	for _, other in ipairs(towersFolder:GetChildren()) do
		if other:GetAttribute("Ready") then
			local p = Combat.GetTowerPos(other)
			if Combat.FlatDistance(p, ctx.pos) <= def.Radius then
				SEM.Apply(other, "AttackHaste", { Magnitude = def.AttackSpeed, Duration = def.Duration, Key = "Rally" })
				SEM.Apply(other, "Empower", { Magnitude = def.Damage, Duration = def.Duration, Key = "Rally" })
				table.insert(buffed, p)
			end
		end
	end
	return { center = ctx.pos, radius = def.Radius, towers = buffed, duration = def.Duration }
end

-- 🌩️ LightningMage: молнии с неба, каждая бьёт цепью
Handlers.Thunderstorm = function(ctx)
	local def, tower = ctx.def, ctx.tower
	if not Combat.RandomInRange(ctx.pos, ctx.range, ctx) then return nil, "No enemies in range" end
	local dmg = (ctx.stats.Damage or 0) * def.DamageMult
	runTimed(tower, def.Strikes * def.Interval, def.Interval, function()
		local first = Combat.RandomInRange(ctx.pos, ctx.range, ctx)
		if not first then return end
		local startPos = first.pos
		local hitSet = { [first.mob] = true }
		local killed = Combat.Damage(first.mob, dmg, "Magic", tower)
		if not killed then
			SEM.Apply(first.mob, "Stun", { Duration = def.StunDuration, Source = tower })
		end
		local points = Combat.Chain(first, def.Jumps, def.JumpRange, dmg, def.Falloff, "Magic", tower, hitSet)
		table.insert(points, 1, startPos)
		fxEvent:FireAllClients({ id = "ThunderStrike", points = points })
	end)
	return { strikes = def.Strikes, interval = def.Interval }
end

-- 🕳️ VoidLord: чёрная дыра затягивает врагов, потом схлопывается
Handlers.BlackHole = function(ctx)
	local def, tower = ctx.def, ctx.tower
	local center = Combat.BestCluster(ctx.pos, ctx.range, def.Radius, ctx)
	if not center then return nil, "No enemies in range" end
	local base = ctx.stats.Damage or 0
	local pullPerTick = def.PullSpeed * 0.1
	runTimed(tower, def.Duration, 0.1, function(ticks)
		Combat.ForEachMobInRadius(center, def.Radius, function(e)
			SEM.Apply(e.mob, "Slow", { Magnitude = def.Slow, Duration = 0.3, Key = "BlackHole" })
			if not e.boss and e.root.Parent then
				local offset = Vector3.new(center.X - e.pos.X, 0, center.Z - e.pos.Z)
				local dist = offset.Magnitude
				if dist > 1.5 then
					e.root.CFrame += offset.Unit * math.min(pullPerTick, dist - 1.5)
				end
			end
			if ticks % 5 == 0 then
				Combat.Damage(e.mob, base * def.TickDamageMult, "Magic", tower)
			end
		end)
	end, function()
		Combat.ForEachMobInRadius(center, def.Radius, function(e)
			Combat.Damage(e.mob, base * def.CollapseMult, "Magic", tower)
		end)
		fxEvent:FireAllClients({ id = "BlackHoleCollapse", center = center, radius = def.Radius })
	end)
	return { center = center, radius = def.Radius, duration = def.Duration }
end

-- 💀 SoulReaper: удар по всем в радиусе, слабых казнит
Handlers.Reap = function(ctx)
	local def, tower = ctx.def, ctx.tower
	local dmg = (ctx.stats.Damage or 0) * def.DamageMult
	local any = false
	local kills, hits = {}, {}
	Combat.ForEachMobInRadius(ctx.pos, ctx.range, function(e)
		any = true
		local hum = e.humanoid
		if not e.boss and hum.Health <= hum.MaxHealth * def.ExecutePercent then
			if Combat.Execute(e.mob, tower) then
				table.insert(kills, e.pos)
			end
		else
			local killed = Combat.Damage(e.mob, dmg, "Physical", tower)
			table.insert(killed and kills or hits, e.pos)
		end
	end)
	if not any then return nil, "No enemies in range" end
	return { center = ctx.pos, radius = ctx.range, kills = kills, hits = hits }
end

---------------------------------------------------------------- запрос от игрока

useEvent.OnServerEvent:Connect(function(player, tower)
	if not Guard.check(player, "UseAbility", 3, 5) then return end
	if tower == nil then return end -- башню только что продали
	if typeof(tower) ~= "Instance" then
		Guard.flag(player, "UseAbility bad argument", 3)
		return
	end
	if tower.Parent ~= towersFolder then return end
	if tower:GetAttribute("OwnerId") ~= player.UserId then
		Guard.flag(player, "UseAbility on someone else's tower", 4)
		return
	end
	if not tower:GetAttribute("Ready") or not matchRunning() then return end

	local def = AbilityData.Get(tower.Name)
	local handler = def and Handlers[def.Id]
	if not handler then return end

	local level = tower:GetAttribute("Level") or 0
	if level < (def.UnlockLevel or 0) then
		useEvent:FireClient(player, "fail", "Unlocks at level " .. tostring(def.UnlockLevel))
		return
	end
	local now = workspace:GetServerTimeNow()
	if now < (tower:GetAttribute("AbilityReadyAt") or 0) then return end -- кнопка ещё на перезарядке
	if SEM.Has(tower, "Disabled") then
		useEvent:FireClient(player, "fail", "Tower is disabled!")
		return
	end

	local stats = getStats(tower)
	if not stats then return end
	Combat.UpdateMobCache()
	local pos = Combat.GetTowerPos(tower)
	local ctx = {
		tower = tower,
		player = player,
		def = def,
		stats = stats,
		level = level,
		pos = pos,
		origin = pos + Vector3.new(0, 1.5, 0),
		range = (stats.Range or 20) + (def.RangeBonus or 0),
		detector = stats.Detector == true,
	}

	local ok, payload, reason = pcall(handler, ctx)
	if not ok then
		warn("[Ability] " .. def.Id .. ": " .. tostring(payload))
		return
	end
	if not payload then
		useEvent:FireClient(player, "fail", reason or "Can't use now")
		return
	end

	tower:SetAttribute("AbilityReadyAt", now + def.Cooldown)
	payload.id = def.Id
	payload.tower = tower
	payload.name = def.Name
	payload.icon = def.Icon
	payload.origin = payload.origin or ctx.origin
	fxEvent:FireAllClients(payload)
	useEvent:FireClient(player, "ok", def.Id)
end)

---------------------------------------------------------------- пассивные ауры

task.spawn(function()
	while true do
		task.wait(AURA_TICK)
		local towers = towersFolder:GetChildren()
		for _, src in ipairs(towers) do
			if src:GetAttribute("Ready") and not SEM.Has(src, "Disabled") then
				local stats = getStats(src)
				if stats and (stats.BuffAuraPercent or stats.HasteAuraPercent) then
					local p = Combat.GetTowerPos(src)
					local r = stats.AuraRange or 25
					for _, dst in ipairs(towers) do
						if dst ~= src and dst:GetAttribute("Ready")
							and Combat.FlatDistance(Combat.GetTowerPos(dst), p) <= r then
							-- ключ = сам паладин: от разных паладинов берётся сильнейшая аура
							if stats.BuffAuraPercent then
								SEM.Apply(dst, "Empower", { Magnitude = stats.BuffAuraPercent, Duration = AURA_TICK + 0.4, Key = src })
							end
							if stats.HasteAuraPercent then
								SEM.Apply(dst, "AttackHaste", { Magnitude = stats.HasteAuraPercent, Duration = AURA_TICK + 0.4, Key = src })
							end
						end
					end
				end
			end
		end
	end
end)
