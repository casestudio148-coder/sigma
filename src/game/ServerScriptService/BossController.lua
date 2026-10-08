-- ServerScriptService.BossController (ModuleScript)
-- Мультифазовые боссы (настройки в ReplicatedStorage.BossData):
--   • на 50% и 20% HP босс меняет скорость, броню и анимацию, очищается от дебафов,
--     на время превращения стоит и неуязвим, призывает миньонов;
--   • периодически призывает уникальных миньонов (не больше MaxMinions живых);
--   • навыки: отключение башен, боевой клич, регенерация.
-- Всё (соединения, поток навыков, анимация) лежит в одном Janitor босса:
-- босс умер или удалён — всё останавливается и убирается само.
--
-- Script вызывает:
--   BossController.Init({ SpawnMob = spawnMob })   -- один раз
--   BossController.Attach(mob, mobName)             -- после mob.Parent = workspace.Mobs

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BossData = require(ReplicatedStorage:WaitForChild("BossData"))
local Janitor = require(ReplicatedStorage:WaitForChild("Janitor"))
local SEM = require(ServerScriptService:WaitForChild("StatusEffectManager"))
local Combat = require(ServerScriptService:WaitForChild("CombatService"))

local BossController = {}

local deps = {}

local fxEvent = ReplicatedStorage:FindFirstChild("AbilityFX")
if not fxEvent then
	fxEvent = Instance.new("RemoteEvent")
	fxEvent.Name = "AbilityFX"
	fxEvent.Parent = ReplicatedStorage
end

function BossController.Init(dependencies)
	deps = dependencies or {}
end

function BossController.IsBoss(mobName)
	return BossData[mobName] ~= nil
end

---------------------------------------------------------------- навыки

local Skills = {}

-- отключает ближайшие башни
Skills.DisableTowers = function(mob, sk)
	local root = mob.PrimaryPart
	if not root then return end
	local near = {}
	for _, tower in ipairs(Combat.TowersFolder:GetChildren()) do
		if tower:GetAttribute("Ready") then
			local p = Combat.GetTowerPos(tower)
			local d = Combat.FlatDistance(p, root.Position)
			if d <= sk.Radius then
				table.insert(near, { tower = tower, d = d, pos = p })
			end
		end
	end
	if #near == 0 then return end
	table.sort(near, function(a, b) return a.d < b.d end)
	local hit = {}
	for i = 1, math.min(sk.Count, #near) do
		SEM.Apply(near[i].tower, "Disabled", { Duration = sk.Duration })
		table.insert(hit, near[i].pos)
	end
	fxEvent:FireAllClients({ id = "BossDisable", center = root.Position, towers = hit, boss = mob })
end

-- ускоряет мобов вокруг
Skills.WarCry = function(mob, sk)
	local root = mob.PrimaryPart
	if not root then return end
	Combat.ForEachMobInRadius(root.Position, sk.Radius, function(e)
		if e.mob ~= mob then
			SEM.Apply(e.mob, "Haste", { Magnitude = sk.Haste, Duration = sk.Duration, Key = "WarCry" })
		end
	end)
	fxEvent:FireAllClients({ id = "BossWarCry", center = root.Position, radius = sk.Radius, boss = mob })
end

-- лечит себя
Skills.Regenerate = function(mob, sk)
	local hum = mob:FindFirstChildOfClass("Humanoid")
	local root = mob.PrimaryPart
	if not hum or hum.Health <= 0 or not root then return end
	hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * sk.Percent)
	fxEvent:FireAllClients({ id = "BossRegenerate", center = root.Position, boss = mob })
end

---------------------------------------------------------------- подключение босса

function BossController.Attach(mob, bossId)
	local def = BossData[bossId]
	local hum = mob:FindFirstChildOfClass("Humanoid")
	if not def or not hum then return end

	local j = Janitor.new()
	j:LinkToInstance(mob)

	local state = { phase = 0, alive = true, minions = {}, track = nil }
	local baseSpeed = mob:GetAttribute("BaseSpeed") or hum.WalkSpeed
	local animator = hum:FindFirstChildOfClass("Animator")

	mob:SetAttribute("BossId", bossId)

	local function stopTrack()
		if state.track then
			state.track:Stop(0.3)
			state.track:Destroy()
			state.track = nil
		end
	end
	j:Add(stopTrack)

	-- анимация фазы
	local function playPhaseAnimation(ph)
		stopTrack()
		if ph.Animation and ph.Animation ~= "" then
			if not animator then
				animator = Instance.new("Animator")
				animator.Parent = hum
			end
			local anim = Instance.new("Animation")
			anim.AnimationId = ph.Animation
			local ok, track = pcall(function()
				return animator:LoadAnimation(anim)
			end)
			anim:Destroy()
			if ok and track then
				track.Looped = true
				track.Priority = Enum.AnimationPriority.Movement
				track:Play(0.3)
				state.track = track
			else
				warn("[Boss] не удалось загрузить анимацию " .. tostring(ph.Animation))
			end
		end
		-- ускоряем то, что уже играет (походка становится быстрее и «злее»)
		if animator and ph.AnimSpeed then
			for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
				t:AdjustSpeed(ph.AnimSpeed)
			end
		end
	end

	-- призыв миньонов вокруг босса
	local function summon(mobName, count)
		local spawnMob = deps.SpawnMob
		local root = mob.PrimaryPart
		if not spawnMob or not root or count <= 0 then return end
		for i = #state.minions, 1, -1 do
			if not state.minions[i].Parent then
				table.remove(state.minions, i)
			end
		end
		local room = (def.MaxMinions or 8) - #state.minions
		local n = math.min(count, room)
		if n <= 0 then return end
		for k = 1, n do
			local ang = k / n * math.pi * 2
			local pos = root.Position + Vector3.new(math.cos(ang) * 4, 0, math.sin(ang) * 4)
			local m = spawnMob(mobName, {
				position = pos,
				waypoint = mob:GetAttribute("Waypoint") or 1,
				healthMult = def.MinionHealthMult or 1,
			})
			if m then table.insert(state.minions, m) end
		end
		fxEvent:FireAllClients({ id = "BossSummon", center = root.Position, boss = mob })
	end

	local function applyPhase(index)
		local ph = def.Phases[index]
		if not ph then return end
		state.phase = index
		mob:SetAttribute("BossPhase", index)
		mob:SetAttribute("BossPhaseName", ph.Name)

		-- скорость: меняем базу, текущие замедления/ускорения считаются от неё
		mob:SetAttribute("BaseSpeed", baseSpeed * (ph.SpeedMult or 1))

		-- броня фазы (один ключ "BossPhase" — новая фаза заменяет старую)
		if ph.Armor and ph.Armor > 0 then
			SEM.Apply(mob, "Armor", { Magnitude = ph.Armor, Duration = math.huge, Key = "BossPhase" })
		else
			SEM.Remove(mob, "Armor", "BossPhase")
		end

		if index > 1 then
			if ph.Cleanse then SEM.Cleanse(mob) end
			local tt = def.TransitionTime or 0
			if tt > 0 then
				SEM.Apply(mob, "Invulnerable", { Duration = tt })
				SEM.Apply(mob, "Transform", { Duration = tt })
			end
			if ph.Summon then
				summon(ph.Summon.Mob, ph.Summon.Count)
			end
		end

		SEM.RefreshSpeed(mob)
		playPhaseAnimation(ph)
	end

	applyPhase(1)

	-- смена фаз по здоровью (только вперёд; сильный удар может перескочить сразу в последнюю)
	j:Connect(hum.HealthChanged, function()
		-- берём текущее здоровье, а не аргумент: при отложенных сигналах (Deferred) аргумент может быть устаревшим
		local health = hum.Health
		if not state.alive or health <= 0 then return end -- добили одним ударом: фаз и призыва уже не будет
		local ratio = health / math.max(hum.MaxHealth, 1)
		local target = state.phase
		for i = state.phase + 1, #def.Phases do
			if ratio <= def.Phases[i].At then
				target = i
			end
		end
		if target > state.phase then
			applyPhase(target)
		end
	end)

	j:Connect(hum.Died, function()
		state.alive = false
		j:Cleanup() -- остановить призыв и навыки сразу, не дожидаясь удаления модели
	end)

	-- периодический призыв и навыки
	j:Add(task.spawn(function()
		local born = os.clock()
		local timers = {}
		while state.alive and mob.Parent do
			task.wait(0.5)
			if not state.alive or hum.Health <= 0 or not mob.Parent or workspace:GetAttribute("MatchOver") then break end
			local now = os.clock()

			local s = def.Summon
			if s and now - (timers.summon or born) >= s.Interval then
				timers.summon = now
				summon(s.Mob, s.Count + (s.ExtraPerPhase or 0) * (state.phase - 1))
			end

			for name, sk in pairs(def.Skills or {}) do
				if state.phase >= (sk.FromPhase or 1) and now - (timers[name] or born) >= sk.Interval then
					timers[name] = now
					local fn = Skills[name]
					if fn then
						local ok, err = pcall(fn, mob, sk)
						if not ok then warn("[Boss] " .. name .. ": " .. tostring(err)) end
					end
				end
			end
		end
	end))
end

return BossController
