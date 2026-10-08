-- ServerScriptService.Guard (ModuleScript)
-- Ядро античита: лимиты запросов, штрафные очки, кик.
-- Используется всеми серверными скриптами, которые принимают RemoteEvent.

local Players = game:GetService("Players")

local Guard = {}

local KICK_AT = 30         -- очков до кика
local DECAY_PER_MINUTE = 8 -- столько очков прощается каждую минуту

local buckets = {} -- [player][key] = { tokens, last }
local strikes = {} -- [player] = number

function Guard.flag(player, reason, weight)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	weight = weight or 1
	strikes[player] = (strikes[player] or 0) + weight
	warn(string.format("[AntiCheat] %s (%d): %s  +%d  (всего %d/%d)",
		player.Name, player.UserId, reason, weight, strikes[player], KICK_AT))
	if strikes[player] >= KICK_AT then
		player:Kick("Removed by anti-cheat. If this was a mistake, rejoin.")
	end
end

-- лимит запросов (token bucket): perSecond в среднем, burst подряд
function Guard.check(player, key, perSecond, burst)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
	local now = os.clock()
	burst = burst or perSecond * 2

	local pb = buckets[player]
	if not pb then
		pb = {}
		buckets[player] = pb
	end
	local b = pb[key]
	if not b then
		b = { tokens = burst, last = now }
		pb[key] = b
	end

	b.tokens = math.min(burst, b.tokens + (now - b.last) * perSecond)
	b.last = now

	if b.tokens < 1 then
		-- быстрые клики честного игрока просто отбрасываются;
		-- штраф только за настоящий флуд (каждый 15-й лишний запрос)
		b.drops = (b.drops or 0) + 1
		if b.drops % 15 == 0 then
			Guard.flag(player, "spam: " .. key, 1)
		end
		return false
	end
	b.tokens -= 1
	return true
end

function Guard.isNumber(n)
	return typeof(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function Guard.isVector(v, limit)
	limit = limit or 1e5
	return typeof(v) == "Vector3"
		and Guard.isNumber(v.X) and Guard.isNumber(v.Y) and Guard.isNumber(v.Z)
		and math.abs(v.X) < limit and math.abs(v.Y) < limit and math.abs(v.Z) < limit
end

function Guard.getStrikes(player)
	return strikes[player] or 0
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
	strikes[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(60)
		for player, s in pairs(strikes) do
			strikes[player] = math.max(0, s - DECAY_PER_MINUTE)
		end
	end
end)

return Guard
