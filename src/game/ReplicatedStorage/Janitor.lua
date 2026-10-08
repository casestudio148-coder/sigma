-- ReplicatedStorage.Janitor (ModuleScript) — для сервера и клиента
-- «Уборщик»: запоминает всё, что потом нужно убрать, и убирает одним вызовом.
-- Главная защита от утечек памяти: ни одно соединение, поток или объект не «повиснет».
--
--   local j = Janitor.new()
--   j:Connect(humanoid.Died, onDied)        -- соединение отключится при уборке
--   j:Delay(3, fn)                          -- task.delay, который отменится при уборке
--   j:Add(part)                             -- объект удалится при уборке
--   j:Add(function() ... end)               -- функция выполнится при уборке
--   j:LinkToInstance(model)                 -- уборка автоматически, когда model удалят
--   j:Cleanup()   -- убрать всё (Janitor можно использовать дальше)
--   j:Destroy()   -- убрать всё навсегда (всё добавленное позже убирается сразу)

local Janitor = {}
Janitor.__index = Janitor

function Janitor.new()
	return setmetatable({ _tasks = {}, _destroyed = false }, Janitor)
end

local function clean(item)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "thread" then
		-- отменяем только ждущий поток (текущий, работающий поток отменить нельзя)
		if coroutine.status(item) == "suspended" then
			task.cancel(item)
		end
	elseif kind == "function" then
		item()
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			item:Destroy()
		elseif type(item.Disconnect) == "function" then
			item:Disconnect()
		elseif type(item.Cleanup) == "function" then
			item:Cleanup()
		end
	end
end

function Janitor:Add(item)
	if item == nil then return nil end
	if self._destroyed then
		-- уборщик уже уничтожен: сразу убираем, чтобы ничего не повисло
		local ok, err = pcall(clean, item)
		if not ok then warn("[Janitor] " .. tostring(err)) end
		return item
	end
	table.insert(self._tasks, item)
	return item
end

function Janitor:Connect(signal, fn)
	return self:Add(signal:Connect(fn))
end

function Janitor:Delay(seconds, fn, ...)
	return self:Add(task.delay(seconds, fn, ...))
end

-- уборка, когда объект удалят (Destroy)
function Janitor:LinkToInstance(instance)
	self:Add(instance.Destroying:Connect(function()
		self:Cleanup()
	end))
	return self
end

function Janitor:Cleanup()
	local tasks = self._tasks
	self._tasks = {}
	-- в обратном порядке: сначала то, что добавили последним
	for i = #tasks, 1, -1 do
		local ok, err = pcall(clean, tasks[i])
		if not ok then warn("[Janitor] " .. tostring(err)) end
	end
end

function Janitor:Destroy()
	self._destroyed = true
	self:Cleanup()
end

return Janitor
