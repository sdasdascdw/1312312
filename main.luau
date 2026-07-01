--[[
	=========================================================
	 BLOCKY UI LIBRARY
	=========================================================
	A self-contained Roblox UI library with:
	  - Blocky theme (sharp corners, thick borders, bold colors)
	  - Smooth animations (tweened open/close, hover, ripple, sliders, dropdowns)
	  - Tabs, Sections, Labels, Paragraphs
	  - Button, Toggle, Slider, Dropdown (single/multi), Input, Keybind, ColorPicker
	  - Notification system
	  - Config save/load system (works on exploit executors with
	    writefile/readfile/isfile/isfolder/makefolder/listfiles)
	  - Draggable window + UI toggle keybind

	USAGE (as a ModuleScript):
		local Library = require(path.to.BlockyUILib)

	USAGE (loadstring, e.g. from a raw file host):
		local Library = loadstring(game:HttpGet("URL_TO_THIS_FILE"))()

	See the accompanying Example_UsageScript.lua for a full demo
	of every feature.
	=========================================================
]]

local TweenService     = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Players           = game:GetService("Players")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local Library = {}
Library.__index = Library
Library.Flags = {}        -- Flag -> current value
Library.Elements = {}      -- Flag -> {Set = function(value, silent) end}
Library.Version = "1.0.0"

------------------------------------------------------------
-- THEME (blocky / bold style: small corner radius, thick strokes)
------------------------------------------------------------
Library.Theme = {
	Background   = Color3.fromRGB(28, 28, 32),
	Panel        = Color3.fromRGB(36, 36, 42),
	Elevated     = Color3.fromRGB(46, 46, 54),
	Accent       = Color3.fromRGB(90, 130, 255),
	AccentDark   = Color3.fromRGB(64, 96, 210),
	Text         = Color3.fromRGB(240, 240, 245),
	SubText      = Color3.fromRGB(165, 165, 178),
	Stroke       = Color3.fromRGB(12, 12, 16),
	Success      = Color3.fromRGB(85, 205, 130),
	Error        = Color3.fromRGB(230, 90, 90),
	Font         = Enum.Font.GothamBold,
	FontRegular  = Enum.Font.GothamMedium,
	Corner       = 6,   -- small radius = still reads as "blocky"
	Stroke_Thick = 2,
}

------------------------------------------------------------
-- UTILITIES
------------------------------------------------------------
local function New(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function Tween(inst, props, duration, style, dir)
	style = style or Enum.EasingStyle.Quad
	dir = dir or Enum.EasingDirection.Out
	local tw = TweenService:Create(inst, TweenInfo.new(duration or 0.22, style, dir), props)
	tw:Play()
	return tw
end

local function AddCorner(inst, radius)
	return New("UICorner", { CornerRadius = UDim.new(0, radius or Library.Theme.Corner), Parent = inst })
end

local function AddStroke(inst, color, thickness)
	return New("UIStroke", {
		Color = color or Library.Theme.Stroke,
		Thickness = thickness or Library.Theme.Stroke_Thick,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end

local function AddPadding(inst, l, t, r, b)
	return New("UIPadding", {
		PaddingLeft = UDim.new(0, l or 8),
		PaddingTop = UDim.new(0, t or 8),
		PaddingRight = UDim.new(0, r or 8),
		PaddingBottom = UDim.new(0, b or 8),
		Parent = inst,
	})
end

local function MakeDraggable(frame, handle)
	handle = handle or frame
	local dragging, dragInput, dragStart, startPos

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			local conn
			conn = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					conn:Disconnect()
				end
			end)
		end
	end)

	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

-- Square "blocky" ripple effect on click
local function Ripple(button)
	button.ClipsDescendants = true
	button.MouseButton1Down:Connect(function(x, y)
		local absPos = button.AbsolutePosition
		local relX = x - absPos.X
		local relY = y - absPos.Y

		local rip = New("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.65,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(0, 0),
			Position = UDim2.fromOffset(relX, relY),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = button.ZIndex + 1,
			Parent = button,
		})

		local maxSize = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 1.8
		Tween(rip, { Size = UDim2.fromOffset(maxSize, maxSize), BackgroundTransparency = 1 }, 0.45)
		task.delay(0.45, function()
			rip:Destroy()
		end)
	end)
end

local function HoverEffect(inst, stroke, normalColor, hoverColor)
	inst.MouseEnter:Connect(function()
		Tween(stroke, { Color = hoverColor }, 0.15)
	end)
	inst.MouseLeave:Connect(function()
		Tween(stroke, { Color = normalColor }, 0.15)
	end)
end

------------------------------------------------------------
-- NOTIFICATIONS
------------------------------------------------------------
local NotificationHolder

local function EnsureNotificationHolder(screenGui)
	if NotificationHolder and NotificationHolder.Parent then return end
	NotificationHolder = New("Frame", {
		Name = "Notifications",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(300, 500),
		Parent = screenGui,
	})
	New("UIListLayout", {
		Parent = NotificationHolder,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Library:Notify(opts)
	opts = opts or {}
	local theme = Library.Theme
	local title = opts.Title or "Notification"
	local content = opts.Content or ""
	local duration = opts.Duration or 4
	local ntype = opts.Type or "Info" -- Info | Success | Error

	local accent = theme.Accent
	if ntype == "Success" then accent = theme.Success end
	if ntype == "Error" then accent = theme.Error end

	if not NotificationHolder then return end

	local card = New("Frame", {
		BackgroundColor3 = theme.Panel,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = NotificationHolder,
	})
	AddCorner(card, theme.Corner)
	local stroke = AddStroke(card, accent, 2)

	local bar = New("Frame", {
		BackgroundColor3 = accent,
		Size = UDim2.new(0, 4, 1, 0),
		BorderSizePixel = 0,
		Parent = card,
	})
	AddCorner(bar, 2)

	AddPadding(card, 14, 10, 10, 10)
	local layout = New("UIListLayout", {
		Parent = card,
		Padding = UDim.new(0, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	New("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 20),
		Font = theme.Font,
		Text = title,
		TextColor3 = theme.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	New("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = theme.FontRegular,
		Text = content,
		TextColor3 = theme.SubText,
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	-- animate in
	card.BackgroundTransparency = 1
	stroke.Transparency = 1
	card.Position = UDim2.new(0, 40, 0, 0)
	Tween(card, { BackgroundTransparency = 0, Position = UDim2.new(0, 0, 0, 0) }, 0.3, Enum.EasingStyle.Back)
	Tween(stroke, { Transparency = 0 }, 0.3)

	task.delay(duration, function()
		if not card or not card.Parent then return end
		local out = Tween(card, { BackgroundTransparency = 1, Position = UDim2.new(0, 40, 0, 0) }, 0.25)
		Tween(stroke, { Transparency = 1 }, 0.25)
		out.Completed:Connect(function()
			card:Destroy()
		end)
	end)
end

------------------------------------------------------------
-- CONFIG SYSTEM
------------------------------------------------------------
local ConfigFolderName = "BlockyUI"

local function SafeCall(fn, ...)
	local ok, res = pcall(fn, ...)
	if ok then return res end
	return nil
end

local function EnsureConfigFolder()
	if not isfolder or not makefolder then return false end
	if not isfolder(ConfigFolderName) then
		makefolder(ConfigFolderName)
	end
	return true
end

function Library:SetConfigFolder(name)
	ConfigFolderName = name
end

function Library:SaveConfig(name)
	if not writefile then
		Library:Notify({ Title = "Config", Content = "writefile is not supported by your executor.", Type = "Error" })
		return false
	end
	SafeCall(EnsureConfigFolder)
	local data = HttpService:JSONEncode(Library.Flags)
	local ok = SafeCall(writefile, ConfigFolderName .. "/" .. name .. ".json", data)
	if ok ~= nil or ok == nil then
		Library:Notify({ Title = "Config Saved", Content = "Saved configuration as \"" .. name .. "\".", Type = "Success" })
		return true
	end
	return false
end

function Library:LoadConfig(name)
	if not readfile or not isfile then
		Library:Notify({ Title = "Config", Content = "readfile is not supported by your executor.", Type = "Error" })
		return false
	end
	local path = ConfigFolderName .. "/" .. name .. ".json"
	if not SafeCall(isfile, path) then
		Library:Notify({ Title = "Config", Content = "No config named \"" .. name .. "\" was found.", Type = "Error" })
		return false
	end
	local raw = SafeCall(readfile, path)
	if not raw then return false end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
	if not ok or type(decoded) ~= "table" then return false end

	for flag, value in pairs(decoded) do
		Library.Flags[flag] = value
		local element = Library.Elements[flag]
		if element and element.Set then
			element.Set(value, true) -- silent = true, don't refire notify spam
		end
	end
	Library:Notify({ Title = "Config Loaded", Content = "Loaded configuration \"" .. name .. "\".", Type = "Success" })
	return true
end

function Library:ListConfigs()
	if not listfiles or not isfolder then return {} end
	if not isfolder(ConfigFolderName) then return {} end
	local files = SafeCall(listfiles, ConfigFolderName) or {}
	local names = {}
	for _, path in ipairs(files) do
		local fname = path:match("([^/\\]+)%.json$")
		if fname then
			table.insert(names, fname)
		end
	end
	return names
end

------------------------------------------------------------
-- WINDOW
------------------------------------------------------------
function Library:CreateWindow(config)
	config = config or {}
	local theme = Library.Theme
	local WindowTitle = config.Name or "Blocky UI"
	local SubTitle = config.SubTitle or ""
	local WindowSize = config.Size or UDim2.fromOffset(580, 400)
	local ToggleKey = config.ToggleKey or Enum.KeyCode.RightControl

	if config.ConfigFolder then
		Library:SetConfigFolder(config.ConfigFolder)
	end

	-- ScreenGui
	local screenGui = New("ScreenGui", {
		Name = "BlockyUI_" .. WindowTitle,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = PlayerGui,
	})
	SafeCall(function()
		screenGui.IgnoreGuiInset = false
	end)

	EnsureNotificationHolder(screenGui)

	-- Main frame
	local main = New("Frame", {
		Name = "Main",
		BackgroundColor3 = theme.Background,
		Size = UDim2.fromOffset(0, 0),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Parent = screenGui,
	})
	AddCorner(main, theme.Corner + 2)
	AddStroke(main, theme.Accent, 3)
	main.ClipsDescendants = true

	-- TopBar
	local topBar = New("Frame", {
		Name = "TopBar",
		BackgroundColor3 = theme.Panel,
		Size = UDim2.new(1, 0, 0, 42),
		Parent = main,
	})
	AddCorner(topBar, theme.Corner + 2)
	New("Frame", { -- mask the bottom corners of the topbar so it looks square-bottomed
		BackgroundColor3 = theme.Panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.new(0, 0, 1, -10),
		Parent = topBar,
	})

	New("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 14, 0, 0),
		Size = UDim2.new(1, -100, 1, 0),
		Font = theme.Font,
		Text = WindowTitle .. (SubTitle ~= "" and ("  " ) or ""),
		TextColor3 = theme.Text,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = topBar,
	})

	if SubTitle ~= "" then
		New("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 14, 0, 22),
			Size = UDim2.new(1, -100, 0, 16),
			Font = theme.FontRegular,
			Text = SubTitle,
			TextColor3 = theme.SubText,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = topBar,
		})
	end

	local closeBtn = New("TextButton", {
		BackgroundColor3 = theme.Error,
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -36, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = theme.Font,
		Text = "X",
		TextColor3 = Color3.new(1, 1, 1),
		TextSize = 14,
		AutoButtonColor = false,
		Parent = topBar,
	})
	AddCorner(closeBtn, 4)
	Ripple(closeBtn)

	local minBtn = New("TextButton", {
		BackgroundColor3 = theme.Elevated,
		Size = UDim2.fromOffset(26, 26),
		Position = UDim2.new(1, -68, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Font = theme.Font,
		Text = "_",
		TextColor3 = theme.Text,
		TextSize = 14,
		AutoButtonColor = false,
		Parent = topBar,
	})
	AddCorner(minBtn, 4)
	Ripple(minBtn)

	MakeDraggable(main, topBar)

	-- Tab list (left)
	local tabList = New("Frame", {
		Name = "TabList",
		BackgroundColor3 = theme.Panel,
		Position = UDim2.new(0, 0, 0, 42),
		Size = UDim2.new(0, 140, 1, -42),
		Parent = main,
	})
	local tabScroll = New("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticCanvasSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = theme.Accent,
		BorderSizePixel = 0,
		Parent = tabList,
	})
	AddPadding(tabScroll, 8, 8, 8, 8)
	New("UIListLayout", {
		Parent = tabScroll,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	-- Page container (right)
	local pageContainer = New("Frame", {
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 140, 0, 42),
		Size = UDim2.new(1, -140, 1, -42),
		Parent = main,
	})

	local Window = {}
	Window.Tabs = {}
	Window._currentTab = nil

	-- open animation
	main.Size = UDim2.fromOffset(0, 0)
	Tween(main, { Size = WindowSize }, 0.35, Enum.EasingStyle.Back)

	local visible = true
	local function ToggleWindow()
		visible = not visible
		if visible then
			main.Visible = true
			main.Size = UDim2.fromOffset(WindowSize.X.Offset, 0)
			Tween(main, { Size = WindowSize }, 0.3, Enum.EasingStyle.Back)
		else
			local tw = Tween(main, { Size = UDim2.fromOffset(WindowSize.X.Offset, 0) }, 0.22, Enum.EasingStyle.Quad)
			tw.Completed:Connect(function()
				if not visible then main.Visible = false end
			end)
		end
	end

	closeBtn.MouseButton1Click:Connect(function()
		local tw = Tween(main, { Size = UDim2.fromOffset(0, 0) }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		tw.Completed:Connect(function()
			screenGui:Destroy()
		end)
	end)

	local minimized = false
	minBtn.MouseButton1Click:Connect(function()
		minimized = not minimized
		if minimized then
			Tween(main, { Size = UDim2.fromOffset(WindowSize.X.Offset, 42) }, 0.25)
			tabList.Visible = false
			pageContainer.Visible = false
		else
			Tween(main, { Size = WindowSize }, 0.25)
			task.delay(0.1, function()
				tabList.Visible = true
				pageContainer.Visible = true
			end)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == ToggleKey then
			ToggleWindow()
		end
	end)

	function Window:Toggle()
		ToggleWindow()
	end

	function Window:Destroy()
		screenGui:Destroy()
	end

	----------------------------------------------------
	-- TAB
	----------------------------------------------------
	function Window:CreateTab(name, icon)
		local theme = Library.Theme
		local isFirst = (#Window.Tabs == 0)

		local tabBtn = New("TextButton", {
			BackgroundColor3 = isFirst and theme.Accent or theme.Elevated,
			Size = UDim2.new(1, 0, 0, 34),
			Font = theme.Font,
			Text = "   " .. name,
			TextColor3 = theme.Text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutoButtonColor = false,
			Parent = tabScroll,
		})
		AddCorner(tabBtn, 5)
		local tabStroke = AddStroke(tabBtn, theme.Stroke, 1)

		local page = New("ScrollingFrame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticCanvasSize.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = theme.Accent,
			BorderSizePixel = 0,
			Visible = isFirst,
			Parent = pageContainer,
		})
		AddPadding(page, 14, 14, 14, 14)
		New("UIListLayout", {
			Parent = page,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})

		local Tab = {}
		Tab._page = page
		Tab._button = tabBtn

		table.insert(Window.Tabs, Tab)
		if isFirst then Window._currentTab = Tab end

		tabBtn.MouseButton1Click:Connect(function()
			for _, t in ipairs(Window.Tabs) do
				t._page.Visible = false
				Tween(t._button, { BackgroundColor3 = theme.Elevated }, 0.15)
			end
			page.Visible = true
			Tween(tabBtn, { BackgroundColor3 = theme.Accent }, 0.15)
			Window._currentTab = Tab
		end)
		Ripple(tabBtn)

		----------------------------------------------------
		-- SECTION / LABEL / PARAGRAPH
		----------------------------------------------------
		function Tab:CreateSection(name)
			local holder = New("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 24),
				Parent = page,
			})
			New("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 18),
				Font = theme.Font,
				Text = name,
				TextColor3 = theme.Accent,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = holder,
			})
			New("Frame", {
				BackgroundColor3 = theme.Accent,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, 2),
				Position = UDim2.new(0, 0, 1, -2),
				Parent = holder,
			})
			return holder
		end

		function Tab:CreateLabel(text)
			local lbl = New("TextLabel", {
				BackgroundColor3 = theme.Panel,
				Size = UDim2.new(1, 0, 0, 30),
				Font = theme.FontRegular,
				Text = text,
				TextColor3 = theme.Text,
				TextSize = 13,
				Parent = page,
			})
			AddCorner(lbl, theme.Corner)
			AddPadding(lbl, 10, 0, 10, 0)
			return lbl
		end

		function Tab:CreateParagraph(title, content)
			local box = New("Frame", {
				BackgroundColor3 = theme.Panel,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = page,
			})
			AddCorner(box, theme.Corner)
			AddPadding(box, 12, 10, 12, 10)
			New("UIListLayout", { Parent = box, Padding = UDim.new(0, 4) })
			New("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 18),
				Font = theme.Font,
				Text = title,
				TextColor3 = theme.Text,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = box,
			})
			New("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Font = theme.FontRegular,
				Text = content,
				TextColor3 = theme.SubText,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = box,
			})
			return box
		end

		----------------------------------------------------
		-- BUTTON
		----------------------------------------------------
		function Tab:CreateButton(opts)
			opts = opts or {}
			local name = opts.Name or "Button"
			local callback = opts.Callback or function() end

			local btn = New("TextButton", {
				BackgroundColor3 = theme.Elevated,
				Size = UDim2.new(1, 0, 0, 36),
				Font = theme.Font,
				Text = name,
				TextColor3 = theme.Text,
				TextSize = 13,
				AutoButtonColor = false,
				Parent = page,
			})
			AddCorner(btn, theme.Corner)
			local stroke = AddStroke(btn, theme.Stroke, 2)
			HoverEffect(btn, stroke, theme.Stroke, theme.Accent)
			Ripple(btn)

			btn.MouseButton1Click:Connect(function()
				Tween(btn, { BackgroundColor3 = theme.AccentDark }, 0.1)
				task.delay(0.12, function()
					Tween(btn, { BackgroundColor3 = theme.Elevated }, 0.25)
				end)
				callback()
			end)

			return btn
		end

		----------------------------------------------------
		-- TOGGLE
		----------------------------------------------------
		function Tab:CreateToggle(opts)
			opts = opts or {}
			local name = opts.Name or "Toggle"
			local default = opts.Default or false
			local flag = opts.Flag
			local callback = opts.Callback or function() end

			local holder = New("TextButton", {
				BackgroundColor3 = theme.Panel,
				Size = UDim2.new(1, 0, 0, 36),
				Text = "",
				AutoButtonColor = false,
				Parent = page,
			})
			AddCorner(holder, theme.Corner)
			AddPadding(holder, 10, 0, 10, 0)

			New("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -50, 1, 0),
				Font = theme.FontRegular,
				Text = name,
				TextColor3 = theme.Text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = holder,
			})

			local switch = New("Frame", {
				BackgroundColor3 = default and theme.Accent or theme.Elevated,
				Size = UDim2.fromOffset(40, 20),
				Position = UDim2.new(1, -40, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Parent = holder,
			})
			AddCorner(switch, 4)
			AddStroke(switch, theme.Stroke, 1)

			local knob = New("Frame", {
				BackgroundColor3 = Color3.new(1, 1, 1),
				Size = UDim2.fromOffset(14, 14),
				Position = default and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Parent = switch,
			})
			AddCorner(knob, 3)

			local state = default
			local function setState(v, silent)
				state = v
				Tween(switch, { BackgroundColor3 = state and theme.Accent or theme.Elevated }, 0.18)
				Tween(knob, { Position = state and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, 0.18, Enum.EasingStyle.Back)
				if flag then Library.Flags[flag] = state end
				if not silent then callback(state) end
			end

			if flag then
				Library.Flags[flag] = default
				Library.Elements[flag] = { Set = setState }
			end

			holder.MouseButton1Click:Connect(function()
				setState(not state)
			end)

			return { Set = setState, Get = function() return state end }
		end

		----------------------------------------------------
		-- SLIDER
		----------------------------------------------------
		function Tab:CreateSlider(opts)
			opts = opts or {}
			local name = opts.Name or "Slider"
			local min = opts.Min or 0
			local max = opts.Max or 100
			local default = opts.Default or min
			local increment = opts.Increment or 1
			local flag = opts.Flag
			local callback = opts.Callback or function() end

			local holder = New("Frame", {
				BackgroundColor3 = theme.Panel,
				Size = UDim2.new(1, 0, 0, 50),
				Parent = page,
			})
			AddCorner(holder, theme.Corner)
			AddPadding(holder, 10, 8, 10, 8)

			local label = New("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -50, 0, 16),
				Font = theme.FontRegular,
				Text = name,
				TextColor3 = theme.Text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = holder,
			})

			local valueLabel = New("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(0, 50, 0, 16),
				Position = UDim2.new(1, -50, 0, 0),
				Font = theme.Font,
				Text = tostring(default),
				TextColor3 = theme.Accent,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = holder,
			})

			local track = New("Frame", {
				BackgroundColor3 = theme.Elevated,
				Size = UDim2.new(1, 0, 0, 10),
				Position = UDim2.new(0, 0, 1, -12),
				Parent = holder,
			})
			AddCorner(track, 3)
			AddStroke(track, theme.Stroke, 1)

			local fraction = (default - min) / (max - min)
			local fill = New("Frame", {
				BackgroundColor3 = theme.Accent,
				Size = UDim2.new(fraction, 0, 1, 0),
				Parent = track,
			})
			AddCorner(fill, 3)

			local dragging = false
			local currentValue = default

			local function setFromFraction(frac, silent)
				frac = math.clamp(frac, 0, 1)
				local raw = min + (max - min) * frac
				raw = math.floor(raw / increment + 0.5) * increment
				raw = math.clamp(raw, min, max)
				currentValue = raw
				local f = (raw - min) / (max - min)
				Tween(fill, { Size = UDim2.new(f, 0, 1, 0) }, 0.05)
				valueLabel.Text = tostring(raw)
				if flag then Library.Flags[flag] = raw end
				if not silent then callback(raw) end
			end

			local function setValue(v, silent)
				local f = (v - min) / (max - min)
				setFromFraction(f, silent)
			end

			if flag then
				Library.Flags[flag] = default
				Library.Elements[flag] = { Set = setValue }
			end

			track.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = true
					local frac = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
					setFromFraction(frac)
				end
			end)
			UserInputService.InputChanged:Connect(function(input)
				if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
					local frac = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
					setFromFraction(frac)
				end
			end)
			UserInputService.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					dragging = false
				end
			end)

			return { Set = setValue, Get = function() return currentValue end }
		end

		----------------------------------------------------
		-- DROPDOWN (single or multi select)
		----------------------------------------------------
		function Tab:CreateDropdown(opts)
			opts = opts or {}
			local name = opts.Name or "Dropdown"
			local options = opts.Options or {}
			local multi = opts.Multi or false
			local default = opts.Default
			local flag = opts.Flag
			local callback = opts.Callback or function() end

			local selected = {}
			if multi then
				if type(default) == "table" then
					for _, v in ipairs(default) do selected[v] = true end
				end
			else
				selected = default
			end

			local holder = New("Frame", {
				BackgroundColor3 = theme.Panel,
				Size = UDim2.new(1, 0, 0, 36),
				ClipsDescendants = true,
				ZIndex = 5,
				Parent = page,
			})
			AddCorner(holder, theme.Corner)
			local hStroke = AddStroke(holder, theme.Stroke, 2)

			local head = New("TextButton", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 36),
				Text = "",
				AutoButtonColor = false,
				ZIndex = 6,
				Parent = holder,
			})

			local label = New("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.new(1, -40, 0, 36),
				Font = theme.FontRegular,
				Text = name,
				TextColor3 = theme.Text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 6,
				Parent = holder,
			})

			local selectedLabel = New("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 10, 0, 18),
				Size = UDim2.new(1, -40, 0, 14),
				Font = theme.FontRegular,
				Text = "",
				TextColor3 = theme.Accent,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 6,
				Parent = holder,
			})

			local arrow = New("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(20, 20),
				Position = UDim2.new(1, -28, 0, 8),
				Font = theme.Font,
				Text = "v",
				TextColor3 = theme.SubText,
				TextSize = 13,
				ZIndex = 6,
				Parent = holder,
			})

			local list = New("Frame", {
				BackgroundColor3 = theme.Elevated,
				Position = UDim2.new(0, 4, 0, 40),
				Size = UDim2.new(1, -8, 0, 0),
				ZIndex = 6,
				Parent = holder,
			})
			AddCorner(list, 4)
			AddStroke(list, theme.Stroke, 1)
			New("UIListLayout", { Parent = list, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
			AddPadding(list, 4, 4, 4, 4)

			local open = false
			local optionButtons = {}

			local function refreshLabel()
				if multi then
					local names = {}
					for opt in pairs(selected) do table.insert(names, opt) end
					selectedLabel.Text = #names > 0 and table.concat(names, ", ") or "None selected"
				else
					selectedLabel.Text = selected and tostring(selected) or "None selected"
				end
			end
			refreshLabel()

			local function select(optName, silent)
				if multi then
					selected[optName] = not selected[optName]
					optionButtons[optName].BackgroundColor3 = selected[optName] and theme.Accent or theme.Panel
				else
					selected = optName
					for n, b in pairs(optionButtons) do
						b.BackgroundColor3 = (n == optName) and theme.Accent or theme.Panel
					end
				end
				refreshLabel()
				if flag then Library.Flags[flag] = selected end
				if not silent then callback(selected) end
			end

			local function build()
				for _, c in ipairs(list:GetChildren()) do
					if c:IsA("TextButton") then c:Destroy() end
				end
				optionButtons = {}
				for i, opt in ipairs(options) do
					local isSel = multi and selected[opt] or (not multi and selected == opt)
					local optBtn = New("TextButton", {
						BackgroundColor3 = isSel and theme.Accent or theme.Panel,
						Size = UDim2.new(1, 0, 0, 26),
						Font = theme.FontRegular,
						Text = opt,
						TextColor3 = theme.Text,
						TextSize = 12,
						AutoButtonColor = false,
						ZIndex = 7,
						LayoutOrder = i,
						Parent = list,
					})
					AddCorner(optBtn, 3)
					optionButtons[opt] = optBtn
					optBtn.MouseButton1Click:Connect(function()
						select(opt)
						if not multi then
							open = false
							Tween(list, { Size = UDim2.new(1, -8, 0, 0) }, 0.2)
							Tween(holder, { Size = UDim2.new(1, 0, 0, 36) }, 0.2)
							Tween(arrow, { Rotation = 0 }, 0.2)
						end
					end)
				end
			end
			build()

			local function toggleOpen()
				open = not open
				local listHeight = math.min(#options * 28 + 8, 160)
				if open then
					Tween(holder, { Size = UDim2.new(1, 0, 0, 44 + listHeight) }, 0.25, Enum.EasingStyle.Quad)
					Tween(list, { Size = UDim2.new(1, -8, 0, listHeight) }, 0.25, Enum.EasingStyle.Quad)
					Tween(arrow, { Rotation = 180 }, 0.25)
					list.ScrollingEnabled = true
				else
					Tween(holder, { Size = UDim2.new(1, 0, 0, 36) }, 0.2)
					Tween(list, { Size = UDim2.new(1, -8, 0, 0) }, 0.2)
					Tween(arrow, { Rotation = 0 }, 0.2)
				end
			end

			head.MouseButton1Click:Connect(toggleOpen)
			HoverEffect(head, hStroke, theme.Stroke, theme.Accent)

			local function setSelected(value, silent)
				if multi then
					selected = {}
					if type(value) == "table" then
						for _, v in ipairs(value) do selected[v] = true end
					end
					for n, b in pairs(optionButtons) do
						b.BackgroundColor3 = selected[n] and theme.Accent or theme.Panel
					end
				else
					selected = value
					for n, b in pairs(optionButtons) do
						b.BackgroundColor3 = (n == value) and theme.Accent or theme.Panel
					end
				end
				refreshLabel()
				if flag then Library.Flags[flag] = selected end
				if not silent then callback(selected) end
			end

			if flag then
				Library.Flags[flag] = selected
				Library.Elements[flag] = { Set = setSelected }
			end

			return {
				Set = setSelected,
				Get = function() return selected end,
				Refresh = function(newOptions)
					options = newOptions
					build()
				end,
			}
		end

		----------------------------------------------------
		-- INPUT (TextBox)
		----------------------------------------------------
		function Tab:CreateInput(opts)
			opts = opts or {}
			local name = opts.Name or "Input"
			local placeholder = opts.PlaceholderText or "Enter text..."
			local default = opts.Default or ""
			local flag = opts.Flag
			local callback = opts.Callback or function() end

			local holder = New("Frame", {
				BackgroundColor3 = theme.Panel,
				Size = UDim2.new(1, 0, 0, 36),
				Parent = page,
			})
			AddCorner(holder, theme.Corner)
			local stroke = AddStroke(holder, theme.Stroke, 2)

			New("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.new(0.4, 0, 1, 0),
				Font = theme.FontRegular,
				Text = name,
				TextColor3 = theme.Text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = holder,
			})

			local box = New("TextBox", {
				BackgroundColor3 = theme.Elevated,
				Position = UDim2.new(0.42, 0, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Size = UDim2.new(0.56, -10, 0, 26),
				Font = theme.FontRegular,
				PlaceholderText = placeholder,
				Text = default,
				TextColor3 = theme.Text,
				TextSize = 12,
				ClearTextOnFocus = false,
				Parent = holder,
			})
			AddCorner(box, 4)
			AddPadding(box, 8, 0, 8, 0)

			HoverEffect(box, stroke, theme.Stroke, theme.Accent)

			local function setValue(v, silent)
				box.Text = tostring(v)
				if flag then Library.Flags[flag] = v end
				if not silent then callback(v) end
			end

			if flag then
				Library.Flags[flag] = default
				Library.Elements[flag] = { Set = setValue }
			end

			box.FocusLost:Connect(function(enterPressed)
				if flag then Library.Flags[flag] = box.Text end
				callback(box.Text)
			end)

			return { Set = setValue, Get = function() return box.Text end }
		end

		----------------------------------------------------
		-- KEYBIND
		----------------------------------------------------
		function Tab:CreateKeybind(opts)
			opts = opts or {}
			local name = opts.Name or "Keybind"
			local default = opts.Default or Enum.KeyCode.F
			local flag = opts.Flag
			local callback = opts.Callback or function() end

			local holder = New("Frame", {
				BackgroundColor3 = theme.Panel,
				Size = UDim2.new(1, 0, 0, 36),
				Parent = page,
			})
			AddCorner(holder, theme.Corner)
			AddPadding(holder, 10, 0, 10, 0)

			New("TextLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -100, 1, 0),
				Font = theme.FontRegular,
				Text = name,
				TextColor3 = theme.Text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = holder,
			})

			local keyBtn = New("TextButton", {
				BackgroundColor3 = theme.Elevated,
				Size = UDim2.fromOffset(90, 24),
				Position = UDim2.new(1, -90, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				Font = theme.Font,
				Text = default.Name,
				TextColor3 = theme.Accent,
				TextSize = 12,
				AutoButtonColor = false,
				Parent = holder,
			})
			AddCorner(keyBtn, 4)
			AddStroke(keyBtn, theme.Stroke, 1)

			local currentKey = default
			local listening = false

			keyBtn.MouseButton1Click:Connect(function()
				listening = true
				keyBtn.Text = "..."
				Tween(keyBtn, { BackgroundColor3 = theme.Accent }, 0.15)
			end)

			local function setKey(key, silent)
				currentKey = key
				keyBtn.Text = key.Name
				if flag then Library.Flags[flag] = key.Name end
				if not silent then callback(key) end
			end

			if flag then
				Library.Flags[flag] = default.Name
				Library.Elements[flag] = {
					Set = function(v, silent)
						local kc = Enum.KeyCode[v]
						if kc then setKey(kc, silent) end
					end,
				}
			end

			UserInputService.InputBegan:Connect(function(input, gpe)
				if listening and input.UserInputType == Enum.UserInputType.Keyboard then
					listening = false
					Tween(keyBtn, { BackgroundColor3 = theme.Elevated }, 0.15)
					setKey(input.KeyCode)
				elseif not gpe and input.KeyCode == currentKey then
					callback(currentKey)
				end
			end)

			return { Set = setKey, Get = function() return currentKey end }
		end

		----------------------------------------------------
		-- COLOR PICKER (simple RGB sliders + preview)
		----------------------------------------------------
		function Tab:CreateColorPicker(opts)
			opts = opts or {}
			local name = opts.Name or "Color"
			local default = opts.Default or Color3.fromRGB(255, 255, 255)
			local flag = opts.Flag
			local callback = opts.Callback or function() end

			local holder = New("Frame", {
				BackgroundColor3 = theme.Panel,
				Size = UDim2.new(1, 0, 0, 36),
				ClipsDescendants = true,
				Parent = page,
			})
			AddCorner(holder, theme.Corner)
			AddStroke(holder, theme.Stroke, 2)

			New("TextLabel", {
				BackgroundTransparency = 1,
				Position = UDim2.new(0, 10, 0, 0),
				Size = UDim2.new(1, -60, 0, 36),
				Font = theme.FontRegular,
				Text = name,
				TextColor3 = theme.Text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = holder,
			})

			local preview = New("TextButton", {
				BackgroundColor3 = default,
				Size = UDim2.fromOffset(28, 20),
				Position = UDim2.new(1, -38, 0, 8),
				Text = "",
				AutoButtonColor = false,
				Parent = holder,
			})
			AddCorner(preview, 4)
			AddStroke(preview, theme.Stroke, 1)

			local panel = New("Frame", {
				BackgroundColor3 = theme.Elevated,
				Position = UDim2.new(0, 4, 0, 40),
				Size = UDim2.new(1, -8, 0, 110),
				Parent = holder,
			})
			AddCorner(panel, 4)
			AddPadding(panel, 10, 8, 10, 8)
			New("UIListLayout", { Parent = panel, Padding = UDim.new(0, 6) })

			local r, g, b = default.R * 255, default.G * 255, default.B * 255
			local sliderRefs = {}

			local function updateColor()
				local color = Color3.fromRGB(r, g, b)
				preview.BackgroundColor3 = color
				if flag then Library.Flags[flag] = { color.R, color.G, color.B } end
				callback(color)
			end

			local function makeChannel(label, value, setter)
				local row = New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), Parent = panel })
				New("TextLabel", {
					BackgroundTransparency = 1,
					Size = UDim2.new(0, 16, 1, 0),
					Font = theme.Font,
					Text = label,
					TextColor3 = theme.SubText,
					TextSize = 12,
					Parent = row,
				})
				local track = New("Frame", {
					BackgroundColor3 = theme.Panel,
					Position = UDim2.new(0, 20, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					Size = UDim2.new(1, -20, 0, 8),
					Parent = row,
				})
				AddCorner(track, 3)
				local fill = New("Frame", {
					BackgroundColor3 = theme.Accent,
					Size = UDim2.new(value / 255, 0, 1, 0),
					Parent = track,
				})
				AddCorner(fill, 3)
				local dragging = false
				local function set(frac)
					frac = math.clamp(frac, 0, 1)
					local v = math.floor(frac * 255)
					fill.Size = UDim2.new(frac, 0, 1, 0)
					setter(v)
					updateColor()
				end
				track.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = true
						set((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
					end
				end)
				UserInputService.InputChanged:Connect(function(input)
					if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
						set((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
					end
				end)
				UserInputService.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						dragging = false
					end
				end)
				return fill
			end

			makeChannel("R", r, function(v) r = v end)
			makeChannel("G", g, function(v) g = v end)
			makeChannel("B", b, function(v) b = v end)

			local open = false
			preview.MouseButton1Click:Connect(function()
				open = not open
				if open then
					Tween(holder, { Size = UDim2.new(1, 0, 0, 46 + 110) }, 0.25)
				else
					Tween(holder, { Size = UDim2.new(1, 0, 0, 36) }, 0.2)
				end
			end)

			local function setValue(color, silent)
				r, g, b = color.R * 255, color.G * 255, color.B * 255
				preview.BackgroundColor3 = color
				if flag then Library.Flags[flag] = { color.R, color.G, color.B } end
				if not silent then callback(color) end
			end

			if flag then
				Library.Flags[flag] = { default.R, default.G, default.B }
				Library.Elements[flag] = {
					Set = function(v, silent)
						if type(v) == "table" then
							setValue(Color3.new(v[1], v[2], v[3]), silent)
						end
					end,
				}
			end

			return { Set = setValue, Get = function() return preview.BackgroundColor3 end }
		end

		return Tab
	end

	return Window
end

return Library
