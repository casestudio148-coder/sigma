-- ReplicatedStorage. (ModuleScript)
-- Общие правила постановки башен: клиент красит «призрак» в красный, сервер отклоняет.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementRules = {
	MIN_DISTANCE = 6,     -- минимум между башнями
	PATH_CLEARANCE = 4.5, -- нельзя ставить ближе к центру дорожки (P1 -> P2 -> ... -> Pn)
}

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function distToSegment(p, a, b)
	local ab = b - a
	local lenSq = ab:Dot(ab)
	local t = lenSq > 0 and math.clamp((p - a):Dot(ab) / lenSq, 0, 1) or 0
	return (p - (a + ab * t)).Magnitude
end

-- путь строкой из MapService (ReplicatedStorage.MapPath = "x,z;x,z;...") — есть всегда, даже если
-- точки P1..Pn у игрока ещё не подгрузились
local pathSrc, pathPts = nil, nil
local function mapPath()
	local v = ReplicatedStorage:FindFirstChild("MapPath")
	local src = (v and v:IsA("StringValue")) and v.Value or ""
	if src ~= pathSrc then
		pathSrc = src
		local list = {}
		for _, item in ipairs(string.split(src, ";")) do
			local f = string.split(item, ",")
			local x, z = tonumber(f[1]), tonumber(f[2])
			if x and z then table.insert(list, Vector3.new(x, 0, z)) end
		end
		pathPts = (#list >= 2) and list or nil
	end
	return pathPts
end

-- путь P1 -> P2 -> ... -> Pn (сколько угодно точек)
function PlacementRules.onPath(position)
	local p = flat(position)
	local pts = mapPath()
	if pts then
		for i = 1, #pts - 1 do
			if distToSegment(p, pts[i], pts[i + 1]) < PlacementRules.PATH_CLEARANCE then
				return true
			end
		end
		return false
	end
	-- карты от MapService нет — точки P1, P2, ... в Workspace (как раньше)
	local prev = workspace:FindFirstChild("P1")
	if not prev then return false end
	local i = 2
	while true do
		local nxt = workspace:FindFirstChild("P" .. i)
		if not nxt then break end
		if distToSegment(p, flat(prev.Position), flat(nxt.Position)) < PlacementRules.PATH_CLEARANCE then
			return true
		end
		prev = nxt
		i += 1
	end
	return false
end

-- места, где ставить нельзя: вода, лава, дома, база (их пишет MapService в ReplicatedStorage.NoBuildZones)
-- формат: "c,x,z,r;r,x1,z1,x2,z2;..."
local zonesSrc, zones = nil, {}
local function noBuildZones()
	local v = ReplicatedStorage:FindFirstChild("NoBuildZones")
	local src = (v and v:IsA("StringValue")) and v.Value or ""
	if src ~= zonesSrc then
		zonesSrc = src
		zones = {}
		for _, item in ipairs(string.split(src, ";")) do
			local f = string.split(item, ",")
			local a, b, c, d = tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
			if f[1] == "c" and a and b and c then
				table.insert(zones, { true, a, b, c * c })
			elseif f[1] == "r" and a and b and c and d then
				table.insert(zones, { false, a, b, c, d })
			end
		end
	end
	return zones
end

function PlacementRules.blocked(position)
	local x, z = position.X, position.Z
	for _, zn in ipairs(noBuildZones()) do
		if zn[1] then
			if (x - zn[2]) ^ 2 + (z - zn[3]) ^ 2 < zn[4] then return true end
		elseif x > zn[2] and x < zn[4] and z > zn[3] and z < zn[5] then
			return true
		end
	end
	return false
end

-- в воде ставить нельзя (клик проходит сквозь воду до дна)
local waterRay = RaycastParams.new()
waterRay.FilterType = Enum.RaycastFilterType.Include
waterRay.IgnoreWater = false
function PlacementRules.inWater(position)
	waterRay.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -40, 0), waterRay)
	return hit ~= nil and hit.Material == Enum.Material.Water
end

function PlacementRules.tooClose(position, towersFolder)
	for _, other in ipairs(towersFolder:GetChildren()) do
		local cf = other:GetBoundingBox()
		if flat(cf.Position - position).Magnitude < PlacementRules.MIN_DISTANCE then
			return true
		end
	end
	return false
end

-- возвращает ok, причина
function PlacementRules.check(position, towersFolder)
	if PlacementRules.tooClose(position, towersFolder) then
		return false, "Too close to another unit"
	end
	if PlacementRules.onPath(position) then
		return false, "Can't place on the path"
	end
	if PlacementRules.blocked(position) then
		return false, "Can't place here"
	end
	if PlacementRules.inWater(position) then
		return false, "Can't place in water"
	end
	return true
end

-- Подготовка модели башни (рига) к постановке. Вызывать ДО того, как модель попадёт в workspace.
-- Корень (HumanoidRootPart) закреплён, а руки / ноги / голова / шапки держатся за него суставами
-- (Motor6D, Weld). Поэтому они всегда встают на свои места, даже если в шаблоне части «разъехались».
-- Части, не связанные с корнем суставами, просто закрепляются на месте.
function PlacementRules.prepareRig(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutomaticScalingEnabled = false
		humanoid.EvaluateStateMachine = false
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid.PlatformStand = true
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end

	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart

	-- какие части связаны с корнем суставами
	local held = {}
	if root then
		local links = {}
		local function link(a, b)
			if a and b then
				links[a] = links[a] or {}
				links[b] = links[b] or {}
				table.insert(links[a], b)
				table.insert(links[b], a)
			end
		end
		for _, j in ipairs(model:GetDescendants()) do
			if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
				link(j.Part0, j.Part1)
			end
		end
		held[root] = true
		local queue = { root }
		while #queue > 0 do
			local p = table.remove(queue)
			for _, q in ipairs(links[p] or {}) do
				if not held[q] then
					held[q] = true
					table.insert(queue, q)
				end
			end
		end
	end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.Massless = true
			part.Anchored = (part == root) or not held[part]
		end
	end

	return root
end

return PlacementRules
