-- ReplicatedStorage.UIKit (ModuleScript)
-- Общий стиль всего интерфейса: яркие цвета, толстая обводка, глянец, свечение, блики, искры.
-- Все картинки берутся из двух атласов (по одной картинке 1024x1024 на всё):
--   UIAtlasIcons.png — 64 иконки (монета, гем, кнопки меню, способности, статусы...)
--   UIAtlasArt.png   — сундуки, лучи, свечение, бейдж, искра, кольцо
--
-- КАК ПОДКЛЮЧИТЬ КАРТИНКИ (один раз):
--   1. Studio → View → Asset Manager → кнопка Bulk Import → выбери UIAtlasIcons.png и UIAtlasArt.png
--   2. В Asset Manager → Images: правый клик по картинке → Copy ID to Clipboard
--   3. Вставь ID ниже вместо 0 (оставь rbxassetid://)

local ICON_ATLAS = "rbxassetid://99710214565874" -- UIAtlasIcons.png
local ART_ATLAS = "rbxassetid://127342330705365"  -- UIAtlasArt.png

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local UIKit = {}

UIKit.Rank = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
UIKit.rgb = rgb

local WHITE = Color3.new(1, 1, 1)
local INK = rgb(36, 19, 58) -- тёмная мультяшная обводка

UIKit.Font = {
	Title = Enum.Font.LuckiestGuy, -- заголовки, большие числа
	Body = Enum.Font.FredokaOne,   -- всё остальное
}

UIKit.C = {
	Ink = INK,
	White = WHITE,
	Gold = rgb(255, 214, 64),
	Green = rgb(110, 240, 120),
	Red = rgb(255, 95, 110),
	Gem = rgb(225, 150, 255),
	Muted = rgb(205, 210, 240),
	Night = rgb(28, 22, 60),
}

-- палитры кнопок и плашек: верх градиента, низ градиента, «бортик» снизу
UIKit.Palette = {
	green = { rgb(150, 255, 110), rgb(25, 190, 70), rgb(10, 105, 40) },
	yellow = { rgb(255, 242, 110), rgb(255, 165, 15), rgb(170, 85, 0) },
	orange = { rgb(255, 214, 110), rgb(255, 115, 25), rgb(160, 55, 0) },
	red = { rgb(255, 150, 140), rgb(240, 45, 70), rgb(135, 10, 35) },
	pink = { rgb(255, 170, 230), rgb(255, 60, 175), rgb(150, 20, 100) },
	purple = { rgb(220, 160, 255), rgb(135, 55, 255), rgb(70, 15, 155) },
	blue = { rgb(130, 220, 255), rgb(35, 115, 255), rgb(15, 50, 155) },
	cyan = { rgb(160, 255, 245), rgb(20, 195, 220), rgb(5, 100, 125) },
	grey = { rgb(200, 200, 220), rgb(120, 122, 148), rgb(60, 60, 85) },
	night = { rgb(85, 70, 160), rgb(40, 30, 95), rgb(20, 14, 50) },
}

---------------------------------------------------------------- атласы

local ICONS = {
	coin = { 0, 0 }, gem = { 128, 0 }, chest = { 256, 0 }, moneybag = { 384, 0 }, backpack = { 512, 0 },
	summon = { 640, 0 }, gift = { 768, 0 }, calendar = { 896, 0 }, shop = { 0, 128 }, scroll = { 128, 128 },
	trade = { 256, 128 }, shield = { 384, 128 }, ticket = { 512, 128 }, gear = { 640, 128 }, lock = { 768, 128 },
	close = { 896, 128 }, check = { 0, 256 }, arrowLeft = { 128, 256 }, arrowRight = { 256, 256 }, star = { 384, 256 },
	starEmpty = { 512, 256 }, upgrade = { 640, 256 }, sell = { 768, 256 }, target = { 896, 256 }, lightning = { 0, 384 },
	heart = { 128, 384 }, flag = { 256, 384 }, skull = { 384, 384 }, crown = { 512, 384 }, trophy = { 640, 384 },
	stopwatch = { 768, 384 }, hourglass = { 896, 384 }, skip = { 0, 512 }, swords = { 128, 512 }, range = { 256, 512 },
	speed = { 384, 512 }, warning = { 512, 512 }, enemy = { 640, 512 }, first = { 768, 512 }, strong = { 896, 512 },
	snail = { 0, 640 }, pin = { 128, 640 }, arrows = { 256, 640 }, meteor = { 384, 640 }, snowflake = { 512, 640 },
	poison = { 640, 640 }, bomb = { 768, 640 }, virus = { 896, 640 }, trident = { 0, 768 }, horn = { 128, 768 },
	storm = { 256, 768 }, blackhole = { 384, 768 }, scythe = { 512, 768 }, sprout = { 640, 768 }, fire = { 768, 768 },
	dizzy = { 896, 768 }, icecube = { 0, 896 }, wind = { 128, 896 }, brokenHeart = { 256, 896 }, chains = { 384, 896 },
	sparkle = { 512, 896 }, hand = { 640, 896 }, demon = { 768, 896 }, explosion = { 896, 896 },
}

local ART = {
	chestHero = { 0, 0, 512, 512 },
	chestMythic = { 512, 0, 512, 512 },
	rays = { 0, 512, 512, 512 },
	glow = { 512, 512, 256, 256 },
	burst = { 768, 512, 256, 256 },
	sparkle = { 512, 768, 256, 256 },
	ring = { 768, 768, 256, 256 },
}

local function assetSet(id)
	return typeof(id) == "string" and id ~= "" and id ~= "rbxassetid://0"
end
UIKit.IconsReady = assetSet(ICON_ATLAS)
UIKit.ArtReady = assetSet(ART_ATLAS)
if not (UIKit.IconsReady and UIKit.ArtReady) and RunService:IsClient() then
	warn("[UIKit] Картинки интерфейса не подключены: загрузи UIAtlasIcons.png и UIAtlasArt.png (Asset Manager → Bulk Import) и вставь их ID в начало UIKit")
end

-- иконки способностей, сложностей и статусов (вместо смайликов из таблиц данных)
UIKit.AbilityIcon = {
	ArrowRain = "arrows", Meteor = "meteor", Blizzard = "snowflake", ToxicCloud = "poison",
	CarpetBomb = "bomb", MarkForDeath = "target", Plague = "virus", Ballista = "trident",
	Rally = "horn", Thunderstorm = "storm", BlackHole = "blackhole", Reap = "scythe",
}
UIKit.DifficultyIcon = { Easy = "sprout", Normal = "swords", Hard = "fire", Nightmare = "skull" }
UIKit.StatusIcon = {
	Stun = "dizzy", Freeze = "icecube", Slow = "snail", Haste = "wind", Burn = "fire", Poison = "poison",
	Armor = "shield", Vulnerable = "brokenHeart", AttackHaste = "lightning", Empower = "swords",
	Disabled = "chains", Invulnerable = "sparkle", Transform = "sparkle",
}
UIKit.CurrencyIcon = { Cash = "coin", Coins = "coin", Gems = "gem", Cases = "chest" }

---------------------------------------------------------------- базовые помощники (старое API сохранено)

function UIKit.new(className, props, parent)
	local obj = Instance.new(className)
	for k, v in pairs(props or {}) do
		obj[k] = v
	end
	obj.Parent = parent
	return obj
end
local new = UIKit.new

function UIKit.corner(obj, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) }, obj)
end
local corner = UIKit.corner

function UIKit.stroke(obj, color, thickness, transparency)
	return new("UIStroke", {
		Color = color,
		Thickness = thickness or 1.5,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, obj)
end
local stroke = UIKit.stroke

function UIKit.label(parent, props)
	local p = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = UIKit.Font.Body,
		TextColor3 = WHITE,
		TextSize = 14,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return new("TextLabel", p, parent)
end

function UIKit.tween(obj, time, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
local tween = UIKit.tween

function UIKit.shake(obj)
	task.spawn(function()
		for _, r in ipairs({ -6, 6, -4, 4, -2, 0 }) do
			UIKit.tween(obj, 0.045, { Rotation = r })
			task.wait(0.045)
		end
	end)
end

-- подпрыгивание через UIScale (создаётся сам, если нет)
function UIKit.pop(obj, from, time)
	local sc = obj:FindFirstChild("PopScale")
	if not sc then
		sc = new("UIScale", { Name = "PopScale" }, obj)
	end
	sc.Scale = from or 1.2
	TweenService:Create(sc, TweenInfo.new(time or 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	return sc
end

-- бесконечное «дыхание» (вернёт твин; :Cancel() — остановить)
function UIKit.pulse(scaleObj, to, time)
	local tw = TweenService:Create(scaleObj,
		TweenInfo.new(time or 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = to or 1.06 })
	tw:Play()
	return tw
end

-- покачивание наклоном
function UIKit.wobble(obj, degrees, time)
	obj.Rotation = -(degrees or 3)
	local tw = TweenService:Create(obj,
		TweenInfo.new(time or 1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = degrees or 3 })
	tw:Play()
	return tw
end

-- подгонка размера под экран (телефон / планшет / ПК)
function UIKit.fitScale(scaleObj, refHeight, minS, maxS)
	local function update()
		local cam = workspace.CurrentCamera
		if cam then
			scaleObj.Scale = math.clamp(cam.ViewportSize.Y / (refHeight or 760), minS or 0.6, maxS or 1)
		end
	end
	update()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scaleObj
end

function UIKit.fit(refHeight, minS, maxS)
	local cam = workspace.CurrentCamera
	return cam and math.clamp(cam.ViewportSize.Y / (refHeight or 760), minS or 0.6, maxS or 1) or 1
end

-- 1234567 -> "1.2M", 12345 -> "12.3K"
function UIKit.short(n)
	n = tonumber(n) or 0
	if n >= 1e6 then return (string.format("%.1fM", n / 1e6):gsub("%.0M", "M")) end
	if n >= 1e4 then return (string.format("%.1fK", n / 1e3):gsub("%.0K", "K")) end
	return tostring(math.floor(n))
end

-- 672610 -> "672,610"
function UIKit.commas(n)
	local s = tostring(math.floor(tonumber(n) or 0))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then out = string.sub(out, 2) end
	return out
end

---------------------------------------------------------------- текст

local function strokeFor(size)
	if size >= 44 then return 4.5 end
	if size >= 28 then return 3.5 end
	if size >= 18 then return 2.5 end
	return 2
end

-- текст с толстой обводкой. Доп. поля: StrokeColor, StrokeThickness
function UIKit.text(parent, props)
	local strokeColor, thickness = props.StrokeColor, props.StrokeThickness
	props.StrokeColor, props.StrokeThickness = nil, nil
	props.Font = props.Font or UIKit.Font.Body
	local l = UIKit.label(parent, props)
	new("UIStroke", {
		Color = strokeColor or INK,
		Thickness = thickness or strokeFor(props.TextSize or 14),
		LineJoinMode = Enum.LineJoinMode.Round,
	}, l)
	return l
end

-- большой заголовок: шрифт Title, градиент по буквам. Доп. поле: Colors = { верх, низ }
function UIKit.title(parent, props)
	local colors = props.Colors or { rgb(255, 250, 170), rgb(255, 180, 30) }
	props.Colors = nil
	props.Font = props.Font or UIKit.Font.Title
	local l = UIKit.text(parent, props)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(colors[1], colors[2]) }, l)
	return l
end

---------------------------------------------------------------- картинки

function UIKit.setIcon(img, name)
	local off = name and ICONS[name]
	if off and UIKit.IconsReady then
		img.Image = ICON_ATLAS
		img.ImageRectOffset = Vector2.new(off[1], off[2])
		img.ImageRectSize = Vector2.new(128, 128)
	else
		img.Image = ""
	end
end

function UIKit.icon(parent, name, props)
	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = UDim2.fromOffset(32, 32)
	for k, v in pairs(props or {}) do
		img[k] = v
	end
	UIKit.setIcon(img, name)
	img.Parent = parent
	return img
end

function UIKit.setArt(img, name)
	local r = name and ART[name]
	if r and UIKit.ArtReady then
		img.Image = ART_ATLAS
		img.ImageRectOffset = Vector2.new(r[1], r[2])
		img.ImageRectSize = Vector2.new(r[3], r[4])
	else
		img.Image = ""
	end
end

function UIKit.art(parent, name, props)
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.BorderSizePixel = 0
	img.ScaleType = Enum.ScaleType.Fit
	for k, v in pairs(props or {}) do
		img[k] = v
	end
	UIKit.setArt(img, name)
	img.Parent = parent
	return img
end

-- мягкое свечение за элементом (по центру, на слой ниже)
function UIKit.glow(parent, color, size, props)
	local p = {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = typeof(size) == "UDim2" and size or UDim2.fromOffset(size or 120, size or 120),
		ImageColor3 = color or WHITE,
		ImageTransparency = 0.15,
		ZIndex = 0,
	}
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	return UIKit.art(parent, "glow", p)
end

---------------------------------------------------------------- живые эффекты (один общий цикл)

local function isShown(obj)
	local o = obj
	while o do
		if o:IsA("GuiObject") then
			if not o.Visible then return false end
		elseif o:IsA("LayerCollector") then
			return o.Enabled and o:IsDescendantOf(game)
		end
		o = o.Parent
	end
	return false
end
UIKit.isShown = isShown

local spinners = setmetatable({}, { __mode = "k" }) -- [img] = градусов в секунду
local shines = setmetatable({}, { __mode = "k" })   -- [gradient] = { period, seed }
local sparklers = setmetatable({}, { __mode = "k" }) -- [frame] = { color, rate, acc, z }

-- вращающиеся лучи за наградой / сундуком
function UIKit.rays(parent, color, size, speed, props)
	local p = {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = typeof(size) == "UDim2" and size or UDim2.fromOffset(size or 300, size or 300),
		ImageColor3 = color or WHITE,
		ImageTransparency = 0.25,
		ZIndex = 0,
	}
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	local img = UIKit.art(parent, "rays", p)
	spinners[img] = speed or 25
	return img
end

function UIKit.spin(obj, speed)
	spinners[obj] = speed
end

-- пробегающий блик по кнопке / плашке
function UIKit.shine(obj, radius, period)
	local overlay = new("Frame", {
		Name = "Shine",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = obj.ZIndex,
	}, obj)
	corner(overlay, radius or 14)
	local g = new("UIGradient", {
		Rotation = 25,
		Offset = Vector2.new(-1, 0),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, overlay)
	shines[g] = { period = period or 3.2, seed = math.random() * 3 }
	return overlay
end

-- искорки, которые сами появляются внутри рамки, пока она видна
function UIKit.sparkles(frame, color, rate, zindex)
	sparklers[frame] = { color = color or WHITE, rate = rate or 4, acc = 0, z = zindex or 20 }
end

function UIKit.stopSparkles(frame)
	sparklers[frame] = nil
end

local function spawnSparkle(frame, info)
	local size = frame.AbsoluteSize
	if size.X < 4 or size.Y < 4 then return end
	local s = math.random(10, 24)
	local img = UIKit.art(frame, "sparkle", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(math.random(), math.random()),
		Size = UDim2.fromOffset(s, s),
		ImageColor3 = info.color,
		ZIndex = info.z,
		Rotation = math.random(0, 90),
	})
	local sc = new("UIScale", { Scale = 0 }, img)
	local t = 0.5 + math.random() * 0.5
	TweenService:Create(sc, TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), { Scale = 1 }):Play()
	TweenService:Create(img, TweenInfo.new(t * 2, Enum.EasingStyle.Linear), { Rotation = img.Rotation + 120 }):Play()
	Debris:AddItem(img, t * 2 + 0.05)
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for img, speed in pairs(spinners) do
		if img.Parent and isShown(img) then
			img.Rotation = (img.Rotation + speed * dt) % 360
		end
	end
	for g, info in pairs(shines) do
		local parent = g.Parent
		if parent and parent.Parent and isShown(parent) then
			local phase = ((now + info.seed) % info.period) / 0.75
			g.Offset = Vector2.new(phase < 1 and (-1 + 2 * phase) or 1, 0)
		end
	end
	local lp = game:GetService("Players").LocalPlayer
	if UIKit.ArtReady and not (lp and lp:GetAttribute("Set_Sparkles") == false) then
		for frame, info in pairs(sparklers) do
			if frame.Parent and isShown(frame) then
				info.acc += dt * info.rate
				while info.acc >= 1 do
					info.acc -= 1
					spawnSparkle(frame, info)
				end
			end
		end
	end
end)

---------------------------------------------------------------- плашки и окна

-- цветная плашка: градиент, толстая обводка, белый внутренний ободок, глянец сверху
function UIKit.panel(parent, props, top, bottom, opts)
	opts = opts or {}
	local radius = opts.Radius or 18
	props.BackgroundColor3 = WHITE
	props.BorderSizePixel = 0
	local f = new("Frame", props, parent)
	corner(f, radius)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(top, bottom) }, f)
	stroke(f, opts.Outline or INK, opts.OutlineThickness or 4)
	if opts.Rim ~= false then
		local rim = new("Frame", {
			Name = "Rim",
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -8),
			BackgroundTransparency = 1,
			ZIndex = f.ZIndex,
		}, f)
		corner(rim, math.max(radius - 4, 2))
		stroke(rim, WHITE, 2, opts.RimTransparency or 0.55)
	end
	if opts.Gloss ~= false then
		local gloss = new("Frame", {
			Name = "Gloss",
			Position = UDim2.fromOffset(6, 5),
			Size = UDim2.new(1, -12, 0, math.min(opts.GlossHeight or 26, 60)),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = f.ZIndex,
		}, f)
		corner(gloss, math.max(radius - 6, 2))
		new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.72, 1) }, gloss)
	end
	return f
end

-- тёмное «углубление» внутри плашки (под списки, сетки, текст)
function UIKit.well(parent, props, radius)
	props.BackgroundColor3 = props.BackgroundColor3 or rgb(20, 14, 52)
	props.BackgroundTransparency = props.BackgroundTransparency or 0.45
	props.BorderSizePixel = 0
	local f = new("Frame", props, parent)
	corner(f, radius or 14)
	return f
end

-- полоска прогресса с глянцем. Вернёт api: set(ratio), setColors(top, bottom), Label, Track
function UIKit.bar(parent, props, top, bottom)
	props.BackgroundColor3 = props.BackgroundColor3 or rgb(40, 28, 70)
	props.BorderSizePixel = 0
	local track = new("Frame", props, parent)
	local h = track.Size.Y.Offset > 0 and track.Size.Y.Offset or 18
	corner(track, math.floor(h / 2))
	stroke(track, INK, 3)
	local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, track)
	corner(fill, math.floor(h / 2))
	local grad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(top or rgb(150, 255, 110), bottom or rgb(25, 190, 70)) }, fill)
	local gloss = new("Frame", {
		Position = UDim2.new(0, 4, 0, 2),
		Size = UDim2.new(1, -8, 0.4, 0),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
	}, fill)
	corner(gloss, math.floor(h / 4))
	local lbl = UIKit.text(track, { Size = UDim2.fromScale(1, 1), TextSize = math.max(12, h - 4), Text = "", ZIndex = track.ZIndex + 2 })
	local api = { Track = track, Fill = fill, Label = lbl }
	function api.set(ratio, time)
		ratio = math.clamp(ratio or 0, 0, 1)
		fill.Visible = ratio > 0.001
		tween(fill, time or 0.25, { Size = UDim2.fromScale(ratio, 1) })
	end
	function api.setColors(a, b)
		grad.Color = ColorSequence.new(a, b)
	end
	return api
end

-- объёмная кнопка: бортик снизу, градиент, глянец, бегущий блик, иконка + текст, «нажатие».
-- o: Size, Position, AnchorPoint, LayoutOrder, ZIndex, Color (имя палитры), Text, TextSize, Icon, IconSize,
--    Radius, Depth, Font, Shine (false — без блика), Name
-- Вернёт api: Button, Face, Label, Icon, setColor(name), setText(t), setIcon(name)
function UIKit.button(parent, o)
	local pal = UIKit.Palette[o.Color or "green"] or UIKit.Palette.green
	local depth = o.Depth or 5
	local radius = o.Radius or 14
	local b = new("TextButton", {
		Name = o.Name or "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = o.Size or UDim2.fromOffset(160, 56),
		Position = o.Position or UDim2.new(),
		AnchorPoint = o.AnchorPoint or Vector2.zero,
		LayoutOrder = o.LayoutOrder or 0,
		ZIndex = o.ZIndex or 1,
		Visible = o.Visible ~= false,
	}, parent)
	local z = b.ZIndex
	local edge = new("Frame", {
		Name = "Edge",
		Position = UDim2.fromOffset(0, depth),
		Size = UDim2.new(1, 0, 1, -depth),
		BackgroundColor3 = pal[3],
		BorderSizePixel = 0,
		ZIndex = z,
	}, b)
	corner(edge, radius)
	stroke(edge, INK, 3)
	local face = new("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, -depth),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = z,
	}, b)
	corner(face, radius)
	local grad = new("UIGradient", { Rotation = 90, Color = ColorSequence.new(pal[1], pal[2]) }, face)
	stroke(face, INK, 3)
	local gloss = new("Frame", {
		Name = "Gloss",
		Position = UDim2.new(0, 5, 0, 3),
		Size = UDim2.new(1, -10, 0.45, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = z,
	}, face)
	corner(gloss, math.max(radius - 4, 2))
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 1) }, gloss)
	if o.Shine ~= false then
		UIKit.shine(face, radius)
	end

	local content = new("Frame", { Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z }, face)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, content)

	local api = { Button = b, Face = face, Edge = edge, Content = content }
	local iconSize = o.IconSize or math.floor((b.Size.Y.Offset > 0 and b.Size.Y.Offset or 50) * 0.62)
	api.Icon = UIKit.icon(content, o.Icon, {
		Size = UDim2.fromOffset(iconSize, iconSize),
		LayoutOrder = 1,
		ZIndex = z,
		Visible = o.Icon ~= nil and UIKit.IconsReady,
	})
	api.Label = UIKit.text(content, {
		Name = "Label",
		Text = o.Text or "",
		Font = o.Font or UIKit.Font.Body,
		TextSize = o.TextSize or 22,
		RichText = true,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		ZIndex = z,
		Visible = (o.Text or "") ~= "",
	})

	function api.setColor(name)
		local p = UIKit.Palette[name] or UIKit.Palette.green
		grad.Color = ColorSequence.new(p[1], p[2])
		edge.BackgroundColor3 = p[3]
	end
	function api.setText(t)
		api.Label.Text = t or ""
		api.Label.Visible = (t or "") ~= ""
	end
	function api.setIcon(name)
		UIKit.setIcon(api.Icon, name)
		api.Icon.Visible = name ~= nil and UIKit.IconsReady
	end

	-- отклик на мышь и тач
	local sc = new("UIScale", {}, b)
	local function press(down)
		tween(face, 0.07, { Position = UDim2.fromOffset(0, down and depth - 1 or 0) })
	end
	b.MouseEnter:Connect(function() tween(sc, 0.12, { Scale = 1.05 }) end)
	b.MouseLeave:Connect(function()
		tween(sc, 0.12, { Scale = 1 })
		press(false)
	end)
	b.MouseButton1Down:Connect(function() press(true) end)
	b.MouseButton1Up:Connect(function() press(false) end)
	return api
end

-- маленькая круглая красная кнопка «X»
function UIKit.closeButton(parent, props)
	local api = UIKit.button(parent, {
		Size = props.Size or UDim2.fromOffset(48, 50),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5),
		ZIndex = props.ZIndex or 6,
		Color = "red",
		Text = "X",
		Font = UIKit.Font.Title,
		TextSize = props.TextSize or 26,
		Radius = 24,
		Depth = 4,
		Shine = false,
	})
	return api
end

-- окно: лента-заголовок с иконкой, плашка, кнопка закрытия, искры по краям
-- o: Title, Icon, Width, Height, Theme (пара цветов {верх, низ}), Ribbon (имя палитры)
-- Вернёт: { Root, Inner, Panel, Content, Close (api кнопки), Title }
function UIKit.window(parentGui, o)
	local w, h = o.Width or 520, o.Height or 380
	local theme = o.Theme or { rgb(120, 205, 255), rgb(60, 95, 235) }
	local ribbon = UIKit.Palette[o.Ribbon or "yellow"] or UIKit.Palette.yellow

	local root = new("Frame", {
		Name = o.Name or (o.Title or "Window"),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromOffset(w, h + 40),
		BackgroundTransparency = 1,
		Visible = false,
	}, parentGui)
	UIKit.fitScale(new("UIScale", {}, root), (h + 40) * 1.28, 0.5, 1)

	local inner = new("Frame", { Name = "Inner", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, root)
	local pop = new("UIScale", { Name = "Pop" }, inner)

	local panel = UIKit.panel(inner, {
		Name = "Panel",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
	}, theme[1], theme[2], { Radius = 22, OutlineThickness = 5, GlossHeight = 40 })

	local content = new("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(18, 44),
		Size = UDim2.new(1, -36, 1, -60),
		BackgroundTransparency = 1,
	}, panel)

	-- лента с названием
	local rib = new("Frame", {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(math.min(w - 90, 360), 62),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, inner)
	corner(rib, 20)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(ribbon[1], ribbon[2]) }, rib)
	stroke(rib, INK, 4)
	UIKit.shine(rib, 20, 4)
	local ribEdge = new("Frame", {
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = ribbon[3],
		BorderSizePixel = 0,
		ZIndex = 2,
	}, rib)
	corner(ribEdge, 20)
	stroke(ribEdge, INK, 4)

	local titleRow = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4 }, rib)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, titleRow)
	local icon = UIKit.icon(titleRow, o.Icon, {
		Size = UDim2.fromOffset(52, 52),
		LayoutOrder = 1,
		ZIndex = 5,
		Visible = o.Icon ~= nil and UIKit.IconsReady,
	})
	local title = UIKit.text(titleRow, {
		Text = string.upper(o.Title or ""),
		Font = UIKit.Font.Title,
		TextSize = 34,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 1, 0),
		LayoutOrder = 2,
		ZIndex = 5,
	})

	local close = UIKit.closeButton(inner, { Position = UDim2.new(1, -8, 0, 46) })

	UIKit.sparkles(panel, WHITE, 2.5, 8)

	local win = { Root = root, Inner = inner, Panel = panel, Content = content, Close = close, Title = title, Icon = icon, Pop = pop }
	function win.show()
		root.Visible = true
		pop.Scale = 0.6
		TweenService:Create(pop, TweenInfo.new(0.32, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		UIKit.pop(icon, 1.5, 0.45)
	end
	function win.hide()
		root.Visible = false
	end
	return win
end

-- всплывающее сообщение сверху по центру (одно на ScreenGui). opts: Color, Icon, Y
local toasts = setmetatable({}, { __mode = "k" })
function UIKit.toast(gui, text, opts)
	opts = opts or {}
	local t = toasts[gui]
	if not t then
		local holder = new("Frame", {
			Name = "Toast",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, opts.Y or 120),
			Size = UDim2.fromOffset(0, 50),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = rgb(30, 20, 70),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 40,
		}, gui)
		corner(holder, 25)
		stroke(holder, WHITE, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 20) }, holder)
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, holder)
		local icon = UIKit.icon(holder, nil, { Size = UDim2.fromOffset(40, 40), LayoutOrder = 1, ZIndex = 41 })
		local lbl = UIKit.text(holder, {
			Text = "",
			TextSize = 24,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 1, 0),
			LayoutOrder = 2,
			ZIndex = 41,
		})
		t = { holder = holder, icon = icon, label = lbl, token = 0 }
		toasts[gui] = t
	end
	t.token += 1
	local token = t.token
	t.label.Text = text
	t.label.TextColor3 = opts.Color or WHITE
	UIKit.setIcon(t.icon, opts.Icon)
	t.icon.Visible = opts.Icon ~= nil and UIKit.IconsReady
	t.holder.Visible = true
	UIKit.pop(t.holder, 0.5, 0.3)
	task.delay(opts.Time or 1.8, function()
		if token == t.token then
			t.holder.Visible = false
		end
	end)
end

---------------------------------------------------------------- юниты

-- имена башен: сначала редкие, внутри редкости по цене
function UIKit.sortedTowerNames(TowerData)
	local names = {}
	for name in pairs(TowerData) do
		table.insert(names, name)
	end
	table.sort(names, function(a, b)
		local ra = UIKit.Rank[TowerData[a].Rarity] or 0
		local rb = UIKit.Rank[TowerData[b].Rarity] or 0
		if ra ~= rb then return ra > rb end
		return TowerData[a].Price < TowerData[b].Price
	end)
	return names
end

-- 3D-иконка башни (ViewportFrame с копией модели из ReplicatedStorage.Towers).
-- Иконки строятся по очереди, по одной за кадр, чтобы при входе игра не зависала.
local function buildIcon(parent, towerName)
	local templates = ReplicatedStorage:FindFirstChild("Towers")
	local template = templates and templates:FindFirstChild(towerName)
	if not template then return end

	pcall(function()
		local vp = new("ViewportFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Ambient = rgb(200, 200, 215),
			LightColor = WHITE,
			LightDirection = Vector3.new(-0.4, -1, -0.6),
			ZIndex = parent.ZIndex,
		}, parent)

		local model = template:Clone()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("LuaSourceContainer") then
				d:Destroy()
			end
		end
		local rules = ReplicatedStorage:FindFirstChild("PlacementRules")
		if rules then
			require(rules).prepareRig(model)
		else
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then d.Anchored = true end
			end
		end
		-- WorldModel: внутри него работают суставы, поэтому иконка собирается так же, как башня в игре
		local world = Instance.new("WorldModel")
		world.Parent = vp
		model.Parent = world
		RunService.Heartbeat:Wait()

		local cam = Instance.new("Camera")
		cam.FieldOfView = 40
		cam.Parent = vp
		vp.CurrentCamera = cam

		-- рамка только по ВИДИМЫМ деталям (невидимые хитбоксы раньше делали иконку крошечной)
		local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p.Transparency < 0.95 then
				local half = p.Size / 2
				for _, sx in ipairs({ -1, 1 }) do
					for _, sy in ipairs({ -1, 1 }) do
						for _, sz in ipairs({ -1, 1 }) do
							local c = (p.CFrame * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position
							minV = minV:Min(c)
							maxV = maxV:Max(c)
						end
					end
				end
			end
		end
		if minV.X == math.huge then
			local cf, size = model:GetBoundingBox()
			minV, maxV = cf.Position - size / 2, cf.Position + size / 2
		end

		local center = (minV + maxV) / 2
		local extent = maxV - minV
		local radius = math.max(extent.X, extent.Y, extent.Z) / 2
		local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 1.15 + 0.5

		-- смотрим на модель спереди и чуть сбоку
		local pivot = model:GetPivot()
		local dir = (pivot.LookVector + pivot.RightVector * 0.45 + Vector3.new(0, 0.25, 0)).Unit
		cam.CFrame = CFrame.lookAt(center + dir * dist, center)
	end)
end

local iconQueue = {}
local queueRunning = false

local function processQueue()
	queueRunning = true
	while #iconQueue > 0 do
		local job = table.remove(iconQueue, 1)
		if job.parent and job.parent.Parent then
			buildIcon(job.parent, job.name)
			RunService.Heartbeat:Wait()
		end
	end
	queueRunning = false
end

function UIKit.makeIcon(parent, towerName)
	table.insert(iconQueue, { parent = parent, name = towerName })
	if not queueRunning then
		task.spawn(processQueue)
	end
end

-- карточка-подложка юнита цвета редкости со свечением (для инвентаря, выбора команды, хотбара)
function UIKit.rarityBack(parent, color, props)
	local p = props or {}
	p.Size = p.Size or UDim2.fromScale(1, 1)
	local f = UIKit.panel(parent, p, color:Lerp(WHITE, 0.25), color:Lerp(rgb(20, 10, 45), 0.55), { Radius = 16, OutlineThickness = 3, GlossHeight = 18 })
	UIKit.glow(f, color:Lerp(WHITE, 0.4), UDim2.fromScale(1.1, 0.9), { Position = UDim2.fromScale(0.5, 0.42), ImageTransparency = 0.35 })
	return f
end

return UIKit
