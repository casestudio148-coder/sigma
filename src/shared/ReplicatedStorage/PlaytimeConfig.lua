-- ReplicatedStorage. (ModuleScript)
-- Общая таблица наград за время сессии. Её читают и сервер (проверка), и клиент (таймеры).
-- Сетка в окне 3x3: строки по времени, столбцы Cash / Gems / Cases.

local PlaytimeConfig = {}

-- Для теста в Studio поставьте 60: минуты превратятся в секунды. В релизе строго 1.
PlaytimeConfig.TestSpeed = 1

-- все 9 наград собираются за 40 минут игры
PlaytimeConfig.Rewards = {
	{ Time = 2 * 60,  Type = "Cash",  Amount = 200 },  -- быстрый первый крючок
	{ Time = 4 * 60,  Type = "Gems",  Amount = 5 },
	{ Time = 6 * 60,  Type = "Cases", Amount = 1 },
	{ Time = 10 * 60, Type = "Cash",  Amount = 600 },
	{ Time = 14 * 60, Type = "Gems",  Amount = 10 },
	{ Time = 18 * 60, Type = "Cases", Amount = 1 },
	{ Time = 25 * 60, Type = "Cash",  Amount = 1500 },
	{ Time = 32 * 60, Type = "Gems",  Amount = 25 },
	{ Time = 40 * 60, Type = "Cases", Amount = 2 },
}

function PlaytimeConfig.getTime(index)
	local r = PlaytimeConfig.Rewards[index]
	return r and (r.Time / PlaytimeConfig.TestSpeed) or math.huge
end

-- 125 -> "02:05", 7385 -> "02:03:05"
function PlaytimeConfig.format(seconds)
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%02d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

return PlaytimeConfig
