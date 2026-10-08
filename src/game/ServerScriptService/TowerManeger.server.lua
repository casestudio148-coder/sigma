-- ServerScriptService.TowerManeger (Script) — ЗАМЕНИТЕ старый код целиком
-- Атаки башен. Вся тяжёлая работа вынесена в общие модули:
--   CombatService       — цели, урон, области, цепь (мобы кэшируются один раз за тик)
--   StatusEffectManager — стан, замедление, заморозка, яд, горение, бафы скорости атаки и урона
-- Клиенту после атаки уходит событие TowerFX (его рисует TowerVFX), формат прежний.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TowerData = require(ReplicatedStorage:WaitForChild("TowerData"))
local UpgradeData = require(ReplicatedStorage:WaitForChild("UpgradeData"))
local Combat = require(ServerScriptService:WaitForChild("CombatService"))
local SEM = require(ServerScriptService:WaitForChild("StatusEffectManager"))

local towersFolder = Combat.TowersFolder

local fxEvent = ReplicatedStorage:FindFirstChild("TowerFX")
if not fxEvent then
	fxEvent = Instance.new("RemoteEvent")
	fxEvent.Name = "TowerFX"
	fxEvent.Parent = ReplicatedStorage
end

local TICK = 0.1

-- время последней атаки хранится в таблице, а не в атрибуте: атрибут каждый выстрел
-- отправлялся бы всем игрокам по сети
local lastAttack = {}
towersFolder.ChildRemoved:Connect(function(tower)
	lastAttack[tower] = nil
end)

-- характеристики башни на текущем тире (0..4) — из серверной таблицы, а не из атрибутов
local function getStats(tower)
	if not TowerData[tower.Name] then return nil end
	return UpgradeData.get(TowerData, tower.Name, tower:GetAttribute("Level") or 0)
end

---------------------------------------------------------------- пассивные эффекты при попадании

local function applyOnHit(stats, mob, tower)
	if stats.Stun then
		SEM.Apply(mob, "Stun", { Duration = stats.Stun, Source = tower })
	end
	if stats.SlowPercent then
		SEM.Apply(mob, "Slow", { Magnitude = stats.SlowPercent, Duration = stats.SlowDuration or 2, Source = tower })
	end
	if stats.FreezeChance and math.random() < stats.FreezeChance then
		SEM.Apply(mob, "Freeze", { Duration = stats.FreezeDuration or 1, Source = tower })
	end
	if stats.PoisonDamage then
		SEM.Apply(mob, "Poison", { Magnitude = stats.PoisonDamage, Duration = stats.PoisonDuration or 3, Source = tower })
	end
	if stats.VulnerablePercent then
		-- враг получает больше урона от всех башен (Mage на 4-м тире)
		SEM.Apply(mob, "Vulnerable", { Magnitude = stats.VulnerablePercent, Duration = stats.VulnerableDuration or 3, Source = tower })
	end
	if stats.BurnDPS then
		SEM.Apply(mob, "Burn", {
			Magnitude = stats.BurnDPS,
			Duration = stats.BurnDuration or 3,
			MaxStacks = stats.BurnMaxStacks or 3,
			Source = tower,
		})
	end
end

---------------------------------------------------------------- атака

local function attack(tower, stats, mode)
	local towerPos = Combat.GetTowerPos(tower)
	local opts = { melee = stats.Melee, detector = stats.Detector }
	local targets = Combat.GetTargets(towerPos, stats.Range or 20, mode, 1 + (stats.MultiShot or 0), opts)
	if #targets == 0 then return false end

	local origin = towerPos + Vector3.new(0, 1.5, 0)
	local dtype = stats.DamageType or "Physical"

	-- аура Паладина и Rally приходят как эффект Empower на башне
	local mult = SEM.Multiplier(tower, "Damage")
	local isCrit = false
	if stats.CritChance and math.random() < stats.CritChance then
		mult *= stats.CritMultiplier or 2
		isCrit = true
	end

	local kills = tower:GetAttribute("Kills") or 0
	local soulBonus = math.min((stats.SoulBonusDamagePerKill or 0) * kills, stats.SoulBonusCap or math.huge)
	local damage = ((stats.Damage or 0) + soulBonus) * mult

	-- данные для клиентских эффектов (TowerVFX)
	local fx = {
		tower = tower,
		name = tower.Name,
		origin = origin,
		hits = {},
		pierceHits = {},
		chain = {},
		executes = {},
		kills = {},
		crit = isCrit,
		splash = stats.Splash,
	}

	local hitSet = {}

	local function strike(e, dmg)
		local mob = e.mob
		if hitSet[mob] then return end
		hitSet[mob] = true
		if not e.alive then return end

		local hum = e.humanoid
		if hum.Health <= 0 then return end
		local mpos = e.pos
		local killed

		if stats.ExecuteHealthPercent and not e.boss
			and hum.Health <= hum.MaxHealth * stats.ExecuteHealthPercent then
			killed = Combat.Execute(mob, tower)
			if killed then table.insert(fx.executes, mpos) end
		else
			local total = dmg
			if stats.PercentMaxHpDamage then
				local p = math.min(hum.MaxHealth * stats.PercentMaxHpDamage, stats.PercentCap or math.huge)
				total += e.boss and p * 0.35 or p
			end
			killed = Combat.Damage(mob, total, dtype, tower)
		end

		if killed then
			table.insert(fx.kills, mpos)
			return
		end
		applyOnHit(stats, mob, tower)
	end

	-- сначала прямые попадания по всем целям: сплеш первой стрелы не должен «съесть» цель второй
	for _, e in ipairs(targets) do
		table.insert(fx.hits, e.pos)
		strike(e, damage)
	end

	for _, e in ipairs(targets) do
		local pos = e.pos

		-- взрыв по области (SplashPercent — доля урона по соседям, например 0.5 у взрывных стрел)
		if stats.Splash then
			local splashDamage = damage * (stats.SplashPercent or 1)
			Combat.ForEachMobInRadius(pos, stats.Splash, function(o)
				strike(o, splashDamage)
			end)
		end

		-- пронзание по линии башня -> цель
		if stats.Pierce then
			local dir = Vector3.new(pos.X - towerPos.X, 0, pos.Z - towerPos.Z)
			if dir.Magnitude > 0.01 then
				dir = dir.Unit
				fx.pierceEnd = pos + dir * 6
				local range = stats.Range or 20
				local line = {}
				Combat.ForEachMob(function(o)
					if not hitSet[o.mob] and not (stats.Melee and o.tags.Flying) then
						local rel = Vector3.new(o.pos.X - towerPos.X, 0, o.pos.Z - towerPos.Z)
						local along = rel:Dot(dir)
						if along > 0 and along <= range and (rel - dir * along).Magnitude <= 3.5 then
							table.insert(line, { e = o, along = along })
						end
					end
				end)
				table.sort(line, function(a, b) return a.along < b.along end)
				local n = math.min(stats.Pierce, #line)
				for i = 1, n do
					table.insert(fx.pierceHits, line[i].e.pos)
					strike(line[i].e, damage)
				end
				if n > 0 then
					fx.pierceEnd = line[n].e.pos + dir * 4
				end
			end
		end

		-- цепная молния
		if stats.ChainTargets then
			local points = Combat.Chain(e, stats.ChainTargets, stats.ChainRange or 14, damage,
				stats.ChainFalloff or 0.8, dtype, tower, hitSet, strike)
			for _, p in ipairs(points) do
				table.insert(fx.chain, p)
			end
		end
	end

	fxEvent:FireAllClients(fx)
	return true
end

---------------------------------------------------------------- главный цикл

task.spawn(function()
	while true do
		task.wait(TICK)
		Combat.UpdateMobCache()
		if Combat.AliveCount() > 0 then
			local now = os.clock()
			for _, tower in ipairs(towersFolder:GetChildren()) do
				-- башня атакует, только когда окончательно встала и её не отключил босс
				if tower:GetAttribute("Ready") and not SEM.Has(tower, "Disabled") then
					local stats = getStats(tower)
					if stats then
						local cooldown = (stats.AttackCooldown or stats.Cooldown or 1) / SEM.Multiplier(tower, "AttackSpeed")
						local last = lastAttack[tower] or 0
						if now - last >= cooldown then
							local mode = tower:GetAttribute("TargetMode") or stats.TargetMode or "First"
							local ok, result = pcall(attack, tower, stats, mode)
							if not ok then
								warn("[Tower] " .. tower.Name .. ": " .. tostring(result))
								lastAttack[tower] = now
							elseif result then
								-- точный темп для быстрых башен: перезарядка меньше тика не «округляется» вверх
								-- (иначе 0.125 с превращалось бы в 0.2 с). Догоняем не больше одного тика.
								if now - last < cooldown + TICK then
									lastAttack[tower] = last + cooldown
								else
									lastAttack[tower] = now
								end
							end
						end
					end
				end
			end
		end
	end
end)
