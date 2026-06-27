--[[
    Atrium UI Library (v2)
    Restyled to match a reference layout:
      - Top row of tab buttons, each with a thin accent-colored border
      - Side-by-side bordered "Section" boxes
      - Checkbox-style toggles (small square + label)
      - Dropdown rendered as a permanently-visible accent-colored bar with
        an options list underneath
      - Slider with an accent-colored fill
      - Keybind shown as a small "..." box + label
      - Paragraph component (bordered, wrapping, multi-line text)
      - Top-left notification panel

    The accent color (purple in the reference image) is fully user
    configurable - see Library:SetAccentColor() or the auto-built
    Settings tab when Library.ConfigSystem = true.

    FEATURES
    - Windows, Tabs, Sections, TabIntoTab (nested tabs + runtime tab creator)
    - Components: Button, Toggle, Slider, Dropdown, MultiDropdown, Keybind,
      Label, Paragraph, Divider, TextBox
    - Notify: stacked notification panel, top-left, fixed position
    - Animations: centralized tween helper used by every component
    - ConfigSystem: Library.ConfigSystem = true + Library.Tab = "name" then
      Window:Finalize() builds a Settings tab with Unload, Theme, Accent
      Color picker, and full Config save/load/create/delete.
]]

local Library = {}
Library.__index = Library

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================================
-- THEME
-- ============================================================================

Library.Themes = {
    Dark = {
        Background  = Color3.fromRGB(24, 24, 24),
        Panel       = Color3.fromRGB(30, 30, 30),
        PanelLight  = Color3.fromRGB(42, 42, 42),
        Border      = Color3.fromRGB(55, 55, 55),
        Text        = Color3.fromRGB(235, 235, 235),
        SubText     = Color3.fromRGB(165, 165, 165),
        Disabled    = Color3.fromRGB(90, 90, 90),
    },
    Light = {
        Background  = Color3.fromRGB(240, 240, 240),
        Panel       = Color3.fromRGB(250, 250, 250),
        PanelLight  = Color3.fromRGB(225, 225, 225),
        Border      = Color3.fromRGB(205, 205, 205),
        Text        = Color3.fromRGB(25, 25, 25),
        SubText     = Color3.fromRGB(95, 95, 95),
        Disabled    = Color3.fromRGB(170, 170, 170),
    },
    Gray = {
        Background  = Color3.fromRGB(45, 45, 48),
        Panel       = Color3.fromRGB(53, 53, 56),
        PanelLight  = Color3.fromRGB(64, 64, 68),
        Border      = Color3.fromRGB(78, 78, 83),
        Text        = Color3.fromRGB(230, 230, 230),
        SubText     = Color3.fromRGB(175, 175, 180),
        Disabled    = Color3.fromRGB(100, 100, 105),
    },
}

Library.CurrentTheme = "Dark"
Library.Theme = Library.Themes.Dark
Library.AccentColor = Color3.fromRGB(125, 35, 200) -- the "purple" from the reference image, fully changeable
Library.Flags = {}
Library.ConfigSystem = false
Library.Tab = "Settings"
Library.ConfigFolder = "AtriumUI"
Library.FlagSetters = {}

local Registry = {}      -- theme-driven instances: { inst, key, prop }
local AccentRegistry = {} -- accent-driven instances: { inst, prop }

local function Register(inst, themeKey, prop)
    table.insert(Registry, { inst = inst, key = themeKey, prop = prop or "BackgroundColor3" })
end

local function RegisterAccent(inst, prop)
    table.insert(AccentRegistry, { inst = inst, prop = prop or "BackgroundColor3" })
end

local function ApplyThemeToRegistry()
    local theme = Library.Theme
    for _, e in ipairs(Registry) do
        if e.inst and e.inst.Parent then
            pcall(function() e.inst[e.prop] = theme[e.key] end)
        end
    end
end

local function ApplyAccentToRegistry()
    local accent = Library.AccentColor
    for _, e in ipairs(AccentRegistry) do
        if e.inst and e.inst.Parent then
            pcall(function() e.inst[e.prop] = accent end)
        end
    end
end

-- ============================================================================
-- HELPERS
-- ============================================================================

local function Create(class, props, children)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = inst end
    return inst
end

local function Stroke(parent, color, thickness)
    return Create("UIStroke", {
        Parent = parent,
        Color = color or Library.Theme.Border,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    })
end

local function AccentStroke(parent, thickness)
    local s = Stroke(parent, Library.AccentColor, thickness or 1)
    RegisterAccent(s, "Color")
    return s
end

local function Corner(parent, radius)
    return Create("UICorner", { Parent = parent, CornerRadius = UDim.new(0, radius or 3) })
end

local Animations = {}
Library.Animations = Animations

function Animations.Tween(inst, props, duration, style, direction)
    local info = TweenInfo.new(duration or 0.15, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
    local t = TweenService:Create(inst, info, props)
    t:Play()
    return t
end

function Animations.Hover(button, idleColor, hoverColor)
    button.MouseEnter:Connect(function() Animations.Tween(button, { BackgroundColor3 = hoverColor }, 0.1) end)
    button.MouseLeave:Connect(function() Animations.Tween(button, { BackgroundColor3 = idleColor }, 0.1) end)
end

function Animations.Press(button, callback)
    button.MouseButton1Click:Connect(function()
        local original = button.Size
        Animations.Tween(button, { Size = original - UDim2.fromOffset(0, 2) }, 0.04)
        task.delay(0.04, function()
            if button and button.Parent then Animations.Tween(button, { Size = original }, 0.07) end
        end)
        if callback then callback() end
    end)
end

local function HexToColor3(hex)
    hex = hex:gsub("#", "")
    if #hex ~= 6 then return nil end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not (r and g and b) then return nil end
    return Color3.fromRGB(r, g, b)
end

local function Color3ToHex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- ============================================================================
-- ROOT GUI
-- ============================================================================

local ScreenGui = Create("ScreenGui", {
    Name = "AtriumUI",
    Parent = PlayerGui,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    ResetOnSpawn = false,
})

pcall(function()
    if gethui then
        ScreenGui.Parent = gethui()
    elseif syn and syn.protect_gui then
        syn.protect_gui(ScreenGui)
        ScreenGui.Parent = game:GetService("CoreGui")
    end
end)

-- ============================================================================
-- NOTIFICATIONS (top-left, stacked, fixed position)
-- ============================================================================

local NotifyHolder = Create("Frame", {
    Name = "Notifications",
    Parent = ScreenGui,
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.fromOffset(320, 500),
}, {
    Create("UIListLayout", {
        Padding = UDim.new(0, 2),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }),
})

function Library:Notify(opts)
    opts = opts or {}
    local theme = Library.Theme
    local title = opts.Title or "Notification"
    local content = opts.Content
    local duration = opts.Duration or 4

    local frame = Create("Frame", {
        Parent = NotifyHolder,
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.new(0, 0, 0, 36),
        AutomaticSize = Enum.AutomaticSize.X,
    })
    Register(frame, "PanelLight")

    Create("UIPadding", {
        Parent = frame,
        PaddingLeft = UDim.new(0, 14),
        PaddingRight = UDim.new(0, 14),
    })

    Create("UIListLayout", {
        Parent = frame,
        FillDirection = Enum.FillDirection.Vertical,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local titleLbl = Create("TextLabel", {
        Parent = frame,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 0, 0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        Font = Enum.Font.SourceSansBold,
        Text = title,
        TextSize = 18,
        TextColor3 = theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    Register(titleLbl, "Text", "TextColor3")

    local contentLbl
    if content and content ~= "" then
        contentLbl = Create("TextLabel", {
            Parent = frame,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 0, 0, 16),
            AutomaticSize = Enum.AutomaticSize.X,
            Font = Enum.Font.SourceSans,
            Text = content,
            TextSize = 14,
            TextColor3 = theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        Register(contentLbl, "SubText", "TextColor3")
        frame.Size = UDim2.new(0, 0, 0, 50)
    end

    task.delay(duration, function()
        if not frame or not frame.Parent then return end
        Animations.Tween(frame, { BackgroundTransparency = 1 }, 0.25)
        Animations.Tween(titleLbl, { TextTransparency = 1 }, 0.25)
        if contentLbl then Animations.Tween(contentLbl, { TextTransparency = 1 }, 0.25) end
        task.delay(0.25, function() if frame then frame:Destroy() end end)
    end)

    return frame
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local Window = {}
Window.__index = Window

function Library:CreateWindow(opts)
    opts = opts or {}
    local theme = Library.Theme
    local name = opts.Name or "Atrium"
    local sizeX = opts.SizeX or 600
    local sizeY = opts.SizeY or 480

    local self = setmetatable({}, Window)
    self.Tabs = {}

    self.Main = Create("Frame", {
        Name = "Window",
        Parent = ScreenGui,
        BackgroundColor3 = theme.Background,
        Position = UDim2.new(0.5, -sizeX / 2, 0.5, -sizeY / 2),
        Size = UDim2.fromOffset(sizeX, sizeY),
        ClipsDescendants = true,
    })
    Register(self.Main, "Background")
    Corner(self.Main, 4)
    AccentStroke(self.Main, 2)

    -- Drag handle: thin invisible strip across the top, since this layout
    -- has no traditional title bar (matches the reference image, which
    -- jumps straight into tab buttons).
    local dragStrip = Create("Frame", {
        Parent = self.Main,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 14),
    })
    do
        local dragging, dragStart, startPos
        dragStrip.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = self.Main.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)
        dragStrip.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local delta = input.Position - dragStart
                self.Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end)
    end

    -- Tab strip (top row of accent-bordered buttons)
    self.TabStrip = Create("Frame", {
        Parent = self.Main,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 10),
        Size = UDim2.new(1, -20, 0, 30),
    }, {
        Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        }),
    })

    -- Content area below the tab strip
    self.ContentArea = Create("Frame", {
        Parent = self.Main,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 46),
        Size = UDim2.new(1, -20, 1, -56),
    })

    self.Library = Library
    return self
end

-- ============================================================================
-- TAB
-- ============================================================================

local Tab = {}
Tab.__index = Tab

function Window:CreateTab(name)
    local theme = Library.Theme
    local windowSelf = self

    local tabObj = setmetatable({}, Tab)
    tabObj.Name = name
    tabObj.Window = windowSelf
    tabObj.Sections = {}

    local order = #windowSelf.Tabs + 1

    local btn = Create("TextButton", {
        Parent = windowSelf.TabStrip,
        AutoButtonColor = false,
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.fromOffset(math.max(70, #name * 8 + 24), 30),
        Font = Enum.Font.SourceSans,
        Text = name,
        TextSize = 18,
        TextColor3 = theme.Text,
        LayoutOrder = order,
    })
    Register(btn, "PanelLight")
    Corner(btn, 3)
    AccentStroke(btn, 1)
    Animations.Hover(btn, theme.PanelLight, theme.Border)

    -- Sections lay out horizontally, side by side, like the reference image
    local page = Create("Frame", {
        Parent = windowSelf.ContentArea,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 1, 0),
        Visible = false,
    }, {
        Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 10),
            SortOrder = Enum.SortOrder.LayoutOrder,
            VerticalAlignment = Enum.VerticalAlignment.Top,
        }),
    })

    tabObj.Button = btn
    tabObj.Page = page

    local function selectTab()
        for _, t in ipairs(windowSelf.Tabs) do
            t.Page.Visible = false
            Animations.Tween(t.Button, { BackgroundColor3 = theme.PanelLight }, 0.1)
        end
        page.Visible = true
        Animations.Tween(btn, { BackgroundColor3 = theme.Border }, 0.1)
        windowSelf.ActiveTab = tabObj
    end

    btn.MouseButton1Click:Connect(selectTab)
    table.insert(windowSelf.Tabs, tabObj)
    if #windowSelf.Tabs == 1 then selectTab() end

    return tabObj
end

-- ============================================================================
-- SECTION (bordered box, centered title, fixed width column like reference)
-- ============================================================================

local Section = {}
Section.__index = Section

function Tab:CreateSection(name, widthPx)
    local theme = Library.Theme

    local container = Create("Frame", {
        Parent = self.Page,
        BackgroundColor3 = theme.Panel,
        Size = UDim2.new(0, widthPx or 190, 1, 0),
        LayoutOrder = #self.Sections + 1,
    })
    Register(container, "Panel")
    Corner(container, 3)
    AccentStroke(container, 1)

    local titleLbl = Create("TextLabel", {
        Parent = container,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 26),
        Font = Enum.Font.SourceSans,
        Text = name,
        TextSize = 18,
        TextColor3 = theme.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    Register(titleLbl, "Text", "TextColor3")

    local body = Create("ScrollingFrame", {
        Parent = container,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 28),
        Size = UDim2.new(1, 0, 1, -34),
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = theme.Border,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticCanvasSize.Y,
    }, {
        Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
        Create("UIPadding", {
            PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
            PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8),
        }),
    })

    local sectionObj = setmetatable({}, Section)
    sectionObj.Container = container
    sectionObj.Body = body
    sectionObj.Tab = self
    table.insert(self.Sections, sectionObj)
    return sectionObj
end

-- ============================================================================
-- LABEL / PARAGRAPH / DIVIDER
-- ============================================================================

function Section:CreateLabel(text)
    local theme = Library.Theme
    local lbl = Create("TextLabel", {
        Parent = self.Body,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Font = Enum.Font.SourceSans,
        Text = text,
        TextWrapped = true,
        TextSize = 16,
        TextColor3 = theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    Register(lbl, "SubText", "TextColor3")
    return lbl
end

-- Bordered block of wrapping body text, matching the "Pharagraf" box in the
-- reference image.
function Section:CreateParagraph(opts)
    opts = opts or {}
    local theme = Library.Theme
    local text = opts.Content or opts.Text or ""

    local box = Create("Frame", {
        Parent = self.Body,
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    })
    Register(box, "PanelLight")
    Corner(box, 3)
    Stroke(box, theme.Border, 1)
    Create("UIPadding", { Parent = box, PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })

    local lbl = Create("TextLabel", {
        Parent = box,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Font = Enum.Font.SourceSans,
        Text = text,
        TextWrapped = true,
        TextSize = 16,
        TextColor3 = theme.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    Register(lbl, "Text", "TextColor3")

    return { SetText = function(_, t) lbl.Text = t end }
end

function Section:CreateDivider()
    local theme = Library.Theme
    local div = Create("Frame", { Parent = self.Body, BackgroundColor3 = theme.Border, Size = UDim2.new(1, 0, 0, 1) })
    Register(div, "Border")
    return div
end

-- ============================================================================
-- BUTTON
-- ============================================================================

function Section:CreateButton(opts)
    opts = opts or {}
    local theme = Library.Theme
    local name = opts.Name or "Button"
    local callback = opts.Callback or function() end

    local btn = Create("TextButton", {
        Parent = self.Body,
        AutoButtonColor = false,
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.new(1, 0, 0, 28),
        Font = Enum.Font.SourceSans,
        Text = name,
        TextSize = 18,
        TextColor3 = theme.Text,
    })
    Register(btn, "PanelLight")
    Corner(btn, 3)
    Stroke(btn, theme.Border, 1)
    Animations.Hover(btn, theme.PanelLight, theme.Border)
    Animations.Press(btn, callback)

    return { Instance = btn, SetText = function(_, t) btn.Text = t end }
end

-- ============================================================================
-- TOGGLE (checkbox square + label, matching reference image)
-- ============================================================================

function Section:CreateToggle(opts)
    opts = opts or {}
    local theme = Library.Theme
    local name = opts.Name or "Toggle"
    local default = opts.Default or false
    local flag = opts.Flag or name
    local callback = opts.Callback or function() end

    local state = default

    local row = Create("Frame", { Parent = self.Body, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20) })

    local box = Create("Frame", {
        Parent = row,
        BackgroundColor3 = theme.PanelLight,
        Position = UDim2.fromOffset(0, 1),
        Size = UDim2.fromOffset(18, 18),
    })
    Register(box, "PanelLight")
    Stroke(box, theme.Border, 1)

    local fill = Create("Frame", {
        Parent = box,
        BackgroundColor3 = theme.Text,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = state and UDim2.new(1, -6, 1, -6) or UDim2.fromOffset(0, 0),
    })
    Register(fill, "Text")

    local lbl = Create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(26, 0),
        Size = UDim2.new(1, -26, 1, 0),
        Font = Enum.Font.SourceSans,
        Text = name,
        TextSize = 16,
        TextColor3 = theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    Register(lbl, "SubText", "TextColor3")

    local click = Create("TextButton", { Parent = row, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "" })

    local function setState(v, fire)
        state = v
        Animations.Tween(fill, { Size = state and UDim2.new(1, -6, 1, -6) or UDim2.fromOffset(0, 0) }, 0.12)
        lbl.TextColor3 = state and theme.Text or theme.SubText
        Library.Flags[flag] = state
        if fire ~= false then callback(state) end
    end

    click.MouseButton1Click:Connect(function() setState(not state) end)
    Library.FlagSetters[flag] = function(v) setState(v, false) end
    Library.Flags[flag] = state
    setState(default, false)

    return { Set = function(_, v) setState(v) end, Get = function() return state end }
end

-- ============================================================================
-- SLIDER (accent-colored fill)
-- ============================================================================

function Section:CreateSlider(opts)
    opts = opts or {}
    local theme = Library.Theme
    local name = opts.Name or "Slider"
    local min = opts.Min or 0
    local max = opts.Max or 100
    local default = math.clamp(opts.Default or min, min, max)
    local flag = opts.Flag or name
    local decimals = opts.Decimals or 0
    local callback = opts.Callback or function() end

    local value = default

    local row = Create("Frame", { Parent = self.Body, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34) })

    local lbl = Create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -40, 0, 16),
        Font = Enum.Font.SourceSans,
        Text = name,
        TextSize = 16,
        TextColor3 = theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    Register(lbl, "SubText", "TextColor3")

    local valLbl = Create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(40, 16),
        Font = Enum.Font.SourceSans,
        Text = tostring(value),
        TextSize = 14,
        TextColor3 = theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    Register(valLbl, "SubText", "TextColor3")

    local track = Create("Frame", {
        Parent = row,
        Position = UDim2.fromOffset(0, 22),
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.new(1, 0, 0, 8),
    })
    Register(track, "PanelLight")
    Stroke(track, theme.Border, 1)

    local fill = Create("Frame", {
        Parent = track,
        BackgroundColor3 = Library.AccentColor,
        Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
    })
    RegisterAccent(fill)

    local handle = Create("Frame", {
        Parent = track,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new((default - min) / (max - min), 0, 0.5, 0),
        Size = UDim2.fromOffset(4, 16),
        BackgroundColor3 = Library.AccentColor,
        ZIndex = 2,
    })
    RegisterAccent(handle)

    local dragger = Create("TextButton", { Parent = row, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 16), Text = "" })

    local function round(n)
        local mult = 10 ^ decimals
        return math.floor(n * mult + 0.5) / mult
    end

    local function setFromAlpha(alpha, fire)
        alpha = math.clamp(alpha, 0, 1)
        value = round(min + (max - min) * alpha)
        local a = (value - min) / (max - min)
        fill.Size = UDim2.new(a, 0, 1, 0)
        handle.Position = UDim2.new(a, 0, 0.5, 0)
        valLbl.Text = tostring(value)
        Library.Flags[flag] = value
        if fire ~= false then callback(value) end
    end

    local dragging = false
    dragger.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromAlpha((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromAlpha((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X)
        end
    end)

    Library.FlagSetters[flag] = function(v) setFromAlpha((math.clamp(v, min, max) - min) / (max - min), false) end
    Library.Flags[flag] = value

    return {
        Set = function(_, v) setFromAlpha((math.clamp(v, min, max) - min) / (max - min)) end,
        Get = function() return value end,
    }
end

-- ============================================================================
-- DROPDOWN (always-visible accent bar + permanent options list, like reference)
-- ============================================================================

function Section:CreateDropdown(opts)
    opts = opts or {}
    local theme = Library.Theme
    local name = opts.Name or "Dropdown"
    local options = opts.Options or {}
    local default = opts.Default or options[1]
    local flag = opts.Flag or name
    local callback = opts.Callback or function() end
    local visibleRows = opts.VisibleRows or 3

    local selected = default
    local open = true -- reference image shows the list permanently expanded

    local row = Create("Frame", { Parent = self.Body, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })

    local lbl = Create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 16),
        Font = Enum.Font.SourceSans,
        Text = name,
        TextSize = 16,
        TextColor3 = theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    Register(lbl, "SubText", "TextColor3")

    local bar = Create("Frame", {
        Parent = row,
        Position = UDim2.fromOffset(0, 18),
        BackgroundColor3 = Library.AccentColor,
        Size = UDim2.new(1, -16, 0, 18),
    })
    RegisterAccent(bar)

    local arrow = Create("TextLabel", {
        Parent = row,
        Position = UDim2.new(1, -14, 0, 18),
        Size = UDim2.fromOffset(14, 18),
        BackgroundTransparency = 1,
        Font = Enum.Font.SourceSansBold,
        Text = "v",
        TextSize = 14,
        TextColor3 = theme.Text,
    })
    Register(arrow, "Text", "TextColor3")

    local barClick = Create("TextButton", { Parent = bar, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 1, 0), Text = "" })

    local list = Create("Frame", {
        Parent = row,
        Position = UDim2.fromOffset(0, 40),
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.new(1, 0, 0, visibleRows * 24),
        ClipsDescendants = true,
    })
    Register(list, "PanelLight")
    Stroke(list, theme.Border, 1)
    Create("UIListLayout", { Parent = list, SortOrder = Enum.SortOrder.LayoutOrder })

    local function rebuildList()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        for i, opt in ipairs(options) do
            local optBtn = Create("TextButton", {
                Parent = list,
                AutoButtonColor = false,
                BackgroundColor3 = theme.PanelLight,
                Size = UDim2.new(1, 0, 0, 24),
                Font = Enum.Font.SourceSans,
                Text = tostring(opt),
                TextSize = 16,
                TextColor3 = (opt == selected) and theme.Text or theme.SubText,
                LayoutOrder = i,
            })
            Animations.Hover(optBtn, theme.PanelLight, theme.Border)
            optBtn.MouseButton1Click:Connect(function()
                selected = opt
                Library.Flags[flag] = selected
                callback(selected)
                rebuildList()
            end)
        end
    end
    rebuildList()

    row.Size = UDim2.new(1, 0, 0, 40 + visibleRows * 24)

    barClick.MouseButton1Click:Connect(function()
        open = not open
        list.Visible = open
        row.Size = open and UDim2.new(1, 0, 0, 40 + visibleRows * 24) or UDim2.new(1, 0, 0, 40)
    end)

    Library.FlagSetters[flag] = function(v)
        selected = v
        rebuildList()
    end
    Library.Flags[flag] = selected

    return {
        Set = function(_, v) selected = v; Library.Flags[flag] = v; rebuildList(); callback(v) end,
        Get = function() return selected end,
        Refresh = function(_, newOptions, keepSelection)
            options = newOptions
            if not keepSelection then selected = options[1] end
            rebuildList()
        end,
    }
end

-- ============================================================================
-- MULTI DROPDOWN (same visual language as the single dropdown, multi-select)
-- ============================================================================

function Section:CreateMultiDropdown(opts)
    opts = opts or {}
    local theme = Library.Theme
    local name = opts.Name or "MultiDropdown"
    local options = opts.Options or {}
    local default = opts.Default or {}
    local flag = opts.Flag or name
    local callback = opts.Callback or function() end
    local visibleRows = opts.VisibleRows or 3

    local selected = {}
    for _, v in ipairs(default) do selected[v] = true end

    local row = Create("Frame", { Parent = self.Body, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40 + visibleRows * 24) })

    local lbl = Create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 16),
        Font = Enum.Font.SourceSans,
        Text = name,
        TextSize = 16,
        TextColor3 = theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    Register(lbl, "SubText", "TextColor3")

    local bar = Create("Frame", {
        Parent = row,
        Position = UDim2.fromOffset(0, 18),
        BackgroundColor3 = Library.AccentColor,
        Size = UDim2.new(1, 0, 0, 18),
    })
    RegisterAccent(bar)

    local list = Create("Frame", {
        Parent = row,
        Position = UDim2.fromOffset(0, 40),
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.new(1, 0, 0, visibleRows * 24),
        ClipsDescendants = true,
    })
    Register(list, "PanelLight")
    Stroke(list, theme.Border, 1)
    Create("UIListLayout", { Parent = list, SortOrder = Enum.SortOrder.LayoutOrder })

    local function fireUpdate()
        local arr = {}
        for opt in pairs(selected) do table.insert(arr, opt) end
        Library.Flags[flag] = arr
        callback(arr)
    end

    local function rebuildList()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        for i, opt in ipairs(options) do
            local isOn = selected[opt] == true
            local optBtn = Create("TextButton", {
                Parent = list,
                AutoButtonColor = false,
                BackgroundColor3 = isOn and theme.Border or theme.PanelLight,
                Size = UDim2.new(1, 0, 0, 24),
                Font = Enum.Font.SourceSans,
                Text = (isOn and "[x] " or "[ ] ") .. tostring(opt),
                TextSize = 16,
                TextColor3 = isOn and theme.Text or theme.SubText,
                LayoutOrder = i,
            })
            optBtn.MouseButton1Click:Connect(function()
                selected[opt] = not selected[opt] or nil
                fireUpdate()
                rebuildList()
            end)
        end
    end
    rebuildList()
    fireUpdate()

    Library.FlagSetters[flag] = function(arr)
        selected = {}
        for _, v in ipairs(arr) do selected[v] = true end
        rebuildList()
    end

    return {
        Get = function()
            local arr = {}
            for opt in pairs(selected) do table.insert(arr, opt) end
            return arr
        end,
        Set = function(_, arr)
            selected = {}
            for _, v in ipairs(arr) do selected[v] = true end
            fireUpdate(); rebuildList()
        end,
    }
end

-- ============================================================================
-- KEYBIND ("..." box + label, matching reference image)
-- ============================================================================

function Section:CreateKeybind(opts)
    opts = opts or {}
    local theme = Library.Theme
    local name = opts.Name or "Keybind"
    local default = opts.Default or "..."
    local flag = opts.Flag or name
    local callback = opts.Callback or function() end
    local changedCallback = opts.OnChanged or function() end

    local currentKey = default
    local listening = false

    local row = Create("Frame", { Parent = self.Body, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 20) })

    local keyBtn = Create("TextButton", {
        Parent = row,
        AutoButtonColor = false,
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.fromOffset(34, 18),
        Font = Enum.Font.SourceSans,
        Text = currentKey,
        TextSize = 14,
        TextColor3 = theme.Text,
    })
    Register(keyBtn, "PanelLight")
    Stroke(keyBtn, theme.Border, 1)

    local lbl = Create("TextLabel", {
        Parent = row,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(42, 0),
        Size = UDim2.new(1, -42, 1, 0),
        Font = Enum.Font.SourceSans,
        Text = name,
        TextSize = 16,
        TextColor3 = theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
    Register(lbl, "SubText", "TextColor3")

    keyBtn.MouseButton1Click:Connect(function()
        listening = true
        keyBtn.Text = "..."
    end)

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if listening and input.UserInputType == Enum.UserInputType.Keyboard then
            currentKey = input.KeyCode.Name
            keyBtn.Text = currentKey
            listening = false
            Library.Flags[flag] = currentKey
            changedCallback(currentKey)
            return
        end
        if not listening and not gameProcessed and input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode.Name == currentKey then callback() end
        end
    end)

    Library.FlagSetters[flag] = function(v) currentKey = v; keyBtn.Text = v end
    Library.Flags[flag] = currentKey

    return { Set = function(_, k) currentKey = k; keyBtn.Text = k; Library.Flags[flag] = k end, Get = function() return currentKey end }
end

-- ============================================================================
-- TEXTBOX
-- ============================================================================

function Section:CreateTextBox(opts)
    opts = opts or {}
    local theme = Library.Theme
    local name = opts.Name or "Input"
    local placeholder = opts.Placeholder or ""
    local flag = opts.Flag or name
    local callback = opts.Callback or function() end

    local row = Create("Frame", { Parent = self.Body, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40) })

    local lbl
    if name ~= "" then
        lbl = Create("TextLabel", {
            Parent = row,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 16),
            Font = Enum.Font.SourceSans,
            Text = name,
            TextSize = 16,
            TextColor3 = theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        Register(lbl, "SubText", "TextColor3")
    end

    local box = Create("TextBox", {
        Parent = row,
        Position = UDim2.fromOffset(0, name ~= "" and 18 or 0),
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.new(1, 0, 0, 22),
        Font = Enum.Font.SourceSans,
        PlaceholderText = placeholder,
        Text = opts.Default or "",
        TextSize = 16,
        TextColor3 = theme.Text,
        PlaceholderColor3 = theme.SubText,
        ClearTextOnFocus = false,
    })
    Register(box, "PanelLight")
    Stroke(box, theme.Border, 1)
    Create("UIPadding", { Parent = box, PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })

    box.FocusLost:Connect(function(enter)
        Library.Flags[flag] = box.Text
        callback(box.Text, enter)
    end)

    Library.FlagSetters[flag] = function(v) box.Text = v end
    Library.Flags[flag] = box.Text

    return { Set = function(_, v) box.Text = v; Library.Flags[flag] = v end, Get = function() return box.Text end }
end

-- ============================================================================
-- TAB INTO TAB (matches reference's small "Tab Into Tab / Tab 1" button)
-- ============================================================================

function Tab:CreateTabIntoTab(name)
    local theme = Library.Theme
    local windowSelf = self.Window

    -- Rendered as its own small accent-bordered button row beneath the main
    -- tab strip (mirrors the reference image's "Tab Into Tab / Tab 1" pill),
    -- which reveals a horizontal sub-tab strip + sections when active.
    local holderRow = Create("Frame", {
        Parent = windowSelf.Main,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 44),
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Visible = false,
        ZIndex = 5,
    })

    local nested = { SubTabs = {} }

    local subStrip = Create("Frame", {
        Parent = holderRow,
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 26),
    }, {
        Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
    })

    local subPageHolder = Create("Frame", {
        Parent = holderRow,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 30),
        Size = UDim2.new(1, 0, 1, -30),
    })

    local function addSubTab(subName)
        local order = #nested.SubTabs + 1

        local btn = Create("TextButton", {
            Parent = subStrip,
            AutoButtonColor = false,
            BackgroundColor3 = theme.PanelLight,
            Size = UDim2.fromOffset(math.max(50, #subName * 7 + 16), 22),
            Font = Enum.Font.SourceSans,
            Text = subName,
            TextSize = 14,
            TextColor3 = theme.Text,
            LayoutOrder = order,
        })
        Register(btn, "PanelLight")
        AccentStroke(btn, 1)
        Animations.Hover(btn, theme.PanelLight, theme.Border)

        local subPage = Create("Frame", {
            Parent = subPageHolder,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Visible = false,
        }, {
            Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
        })

        local subTabObj = { Name = subName, Button = btn, Page = subPage, Sections = {} }
        subTabObj.CreateSection = Tab.CreateSection -- reuse the same bordered-box section renderer

        btn.MouseButton1Click:Connect(function()
            for _, st in ipairs(nested.SubTabs) do st.Page.Visible = false end
            subPage.Visible = true
        end)

        table.insert(nested.SubTabs, subTabObj)
        if #nested.SubTabs == 1 then subPage.Visible = true end

        return subTabObj
    end

    -- runtime "add a tab" row, lets the END USER create more sub-tabs live
    local creatorRow = Create("Frame", { Parent = holderRow, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24) })
    local nameBox = Create("TextBox", {
        Parent = creatorRow,
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.new(0, 160, 1, 0),
        Font = Enum.Font.SourceSans,
        PlaceholderText = "New tab name...",
        Text = "",
        TextSize = 14,
        TextColor3 = theme.Text,
        PlaceholderColor3 = theme.SubText,
    })
    Register(nameBox, "PanelLight")
    Stroke(nameBox, theme.Border, 1)
    Create("UIPadding", { Parent = nameBox, PaddingLeft = UDim.new(0, 6) })

    local addBtn = Create("TextButton", {
        Parent = creatorRow,
        AutoButtonColor = false,
        Position = UDim2.fromOffset(166, 0),
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.fromOffset(56, 24),
        Font = Enum.Font.SourceSans,
        Text = "+ Tab",
        TextSize = 14,
        TextColor3 = theme.Text,
    })
    Register(addBtn, "PanelLight")
    AccentStroke(addBtn, 1)
    Animations.Hover(addBtn, theme.PanelLight, theme.Border)
    addBtn.MouseButton1Click:Connect(function()
        if nameBox.Text ~= "" then addSubTab(nameBox.Text); nameBox.Text = "" end
    end)

    -- The pill button shown on the main tab strip that reveals this whole
    -- nested-tab block (visually matching the reference's small button).
    local revealBtn = Create("TextButton", {
        Parent = windowSelf.TabStrip,
        AutoButtonColor = false,
        BackgroundColor3 = theme.PanelLight,
        Size = UDim2.fromOffset(90, 30),
        Font = Enum.Font.SourceSans,
        Text = "Tab Into Tab\n" .. name,
        TextSize = 11,
        TextWrapped = true,
        TextColor3 = theme.Text,
    })
    Register(revealBtn, "PanelLight")
    AccentStroke(revealBtn, 1)
    Animations.Hover(revealBtn, theme.PanelLight, theme.Border)
    revealBtn.MouseButton1Click:Connect(function()
        for _, t in ipairs(windowSelf.Tabs) do t.Page.Visible = false end
        holderRow.Visible = not holderRow.Visible
    end)

    nested.AddSubTab = addSubTab
    return nested
end

-- ============================================================================
-- CONFIG SYSTEM (built by Window:Finalize when Library.ConfigSystem = true)
-- Includes: Unload, Theme picker, Accent Color picker, Save/Load/Delete.
-- ============================================================================

local function safeIsFolder(path) return (typeof(isfolder) == "function") and isfolder(path) end

local function ensureConfigFolder()
    if typeof(makefolder) ~= "function" then return false end
    if not safeIsFolder(Library.ConfigFolder) then pcall(makefolder, Library.ConfigFolder) end
    return true
end

local function listConfigs()
    local results = {}
    if typeof(listfiles) ~= "function" then return results end
    local ok, files = pcall(listfiles, Library.ConfigFolder)
    if not ok or not files then return results end
    for _, path in ipairs(files) do
        local fname = path:match("[^/\\]+$")
        if fname and fname:match("%.json$") then table.insert(results, fname:gsub("%.json$", "")) end
    end
    return results
end

local function saveConfig(configName)
    if not ensureConfigFolder() then return false, "writefile not supported in this environment" end
    local payload = {
        Flags = Library.Flags,
        Theme = Library.CurrentTheme,
        Accent = Color3ToHex(Library.AccentColor),
    }
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
    if not ok then return false, "failed to encode config" end
    local path = Library.ConfigFolder .. "/" .. configName .. ".json"
    return pcall(writefile, path, encoded)
end

local function loadConfig(configName)
    if typeof(readfile) ~= "function" then return false, "readfile not supported" end
    local path = Library.ConfigFolder .. "/" .. configName .. ".json"
    local ok, contents = pcall(readfile, path)
    if not ok then return false, "could not read config" end
    local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, contents)
    if not decodeOk then return false, "could not decode config" end

    if decoded.Theme and Library.Themes[decoded.Theme] then
        Library.CurrentTheme = decoded.Theme
        Library.Theme = Library.Themes[decoded.Theme]
        ApplyThemeToRegistry()
    end
    if decoded.Accent then
        local c = HexToColor3(decoded.Accent)
        if c then Library.AccentColor = c; ApplyAccentToRegistry() end
    end
    if decoded.Flags then
        for flag, value in pairs(decoded.Flags) do
            Library.Flags[flag] = value
            if Library.FlagSetters[flag] then pcall(Library.FlagSetters[flag], value) end
        end
    end
    return true
end

local function deleteConfig(configName)
    if typeof(delfile) ~= "function" then return false, "delfile not supported" end
    return pcall(delfile, Library.ConfigFolder .. "/" .. configName .. ".json")
end

function Library:SetTheme(name)
    if not Library.Themes[name] then return end
    Library.CurrentTheme = name
    Library.Theme = Library.Themes[name]
    ApplyThemeToRegistry()
end

function Library:SetAccentColor(color)
    Library.AccentColor = color
    ApplyAccentToRegistry()
end

function Window:Finalize()
    if not Library.ConfigSystem then return end
    local theme = Library.Theme
    local tabName = Library.Tab or "Settings"
    local settingsTab = self:CreateTab(tabName)

    -- Session
    local sessionSection = settingsTab:CreateSection("Session")
    sessionSection:CreateButton({ Name = "Unload UI", Callback = function() ScreenGui:Destroy() end })

    -- Theme
    local themeSection = settingsTab:CreateSection("Theme")
    local themeNames = {}
    for k in pairs(Library.Themes) do table.insert(themeNames, k) end
    table.sort(themeNames)
    themeSection:CreateDropdown({
        Name = "Theme",
        Options = themeNames,
        Default = Library.CurrentTheme,
        VisibleRows = #themeNames,
        Callback = function(choice) Library:SetTheme(choice) end,
    })

    -- Accent color: presets + custom hex input, since this is the
    -- "purple in the image" the user wants to be able to change.
    local accentSection = settingsTab:CreateSection("Accent Color", 210)
    accentSection:CreateLabel("Presets:")

    local presets = {
        { "Purple", Color3.fromRGB(125, 35, 200) },
        { "Blue",   Color3.fromRGB(45, 110, 220) },
        { "Red",    Color3.fromRGB(200, 50, 50) },
        { "Green",  Color3.fromRGB(60, 170, 90) },
        { "Gray",   Color3.fromRGB(140, 140, 140) },
    }
    local swatchRow = Create("Frame", { Parent = accentSection.Body, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22) }, {
        Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
    })
    for _, preset in ipairs(presets) do
        local swatch = Create("TextButton", {
            Parent = swatchRow,
            AutoButtonColor = false,
            BackgroundColor3 = preset[2],
            Size = UDim2.fromOffset(22, 22),
            Text = "",
        })
        Stroke(swatch, theme.Border, 1)
        swatch.MouseButton1Click:Connect(function() Library:SetAccentColor(preset[2]) end)
    end

    accentSection:CreateLabel("Custom hex (e.g. #7D23C8):")
    accentSection:CreateTextBox({
        Name = "",
        Placeholder = "#7D23C8",
        Default = Color3ToHex(Library.AccentColor),
        Callback = function(text)
            local c = HexToColor3(text)
            if c then Library:SetAccentColor(c) end
        end,
    })

    -- Config save/load
    local configSection = settingsTab:CreateSection("Config")
    local statusLbl = configSection:CreateLabel("")

    local nameBox = configSection:CreateTextBox({ Name = "Config Name", Placeholder = "e.g. main" })
    local existing = listConfigs()
    local loadDropdown = configSection:CreateDropdown({ Name = "Saved Configs", Options = existing, Default = existing[1], VisibleRows = 3 })

    configSection:CreateButton({
        Name = "Save Config",
        Callback = function()
            local nm = nameBox:Get()
            if not nm or nm == "" then statusLbl.Text = "Enter a config name first."; return end
            local ok, err = saveConfig(nm)
            statusLbl.Text = ok and ("Saved '" .. nm .. "'.") or ("Save failed: " .. tostring(err))
            loadDropdown:Refresh(listConfigs(), true)
        end,
    })
    configSection:CreateButton({
        Name = "Load Selected Config",
        Callback = function()
            local nm = loadDropdown:Get()
            if not nm then statusLbl.Text = "No config selected."; return end
            local ok, err = loadConfig(nm)
            statusLbl.Text = ok and ("Loaded '" .. nm .. "'.") or ("Load failed: " .. tostring(err))
        end,
    })
    configSection:CreateButton({
        Name = "Delete Selected Config",
        Callback = function()
            local nm = loadDropdown:Get()
            if not nm then statusLbl.Text = "No config selected."; return end
            local ok = deleteConfig(nm)
            statusLbl.Text = ok and ("Deleted '" .. nm .. "'.") or "Delete failed."
            loadDropdown:Refresh(listConfigs(), false)
        end,
    })
end

return Library

--[[
    FULL EXAMPLE
    ------------------------------------------------------------------------
    local Library = require(path.to.this)

    local Window = Library:CreateWindow({ Name = "Atrium Example", SizeX = 620, SizeY = 460 })

    local Tab1 = Window:CreateTab("Tab 1")
    local Section1 = Tab1:CreateSection("Section 1")
    Section1:CreateToggle({ Name = "Dezactivated Toggle", Default = false })
    Section1:CreateToggle({ Name = "Activated Toggle", Default = true })
    Section1:CreateButton({ Name = "Button", Callback = function() end })
    Section1:CreateParagraph({ Content = "Pharagraf, this is not a label, this is a pharagraf. The text will NOT run out." })

    local Section2 = Tab1:CreateSection("Section 2")
    Section2:CreateDropdown({ Name = "Dropdown 1", Options = {"1","2","3"}, Default = "1" })
    Section2:CreateSlider({ Name = "Slider 1", Min = 0, Max = 100, Default = 40 })
    Section2:CreateKeybind({ Name = "Keybind 1", Default = "..." })

    Window:CreateTab("Tab 2")
    Window:CreateTab("Tab 3")

    local nested = Tab1:CreateTabIntoTab("Tab 1")
    nested.AddSubTab("Sub A")

    Library.ConfigSystem = true
    Library.Tab = "Settings"
    Window:Finalize()

    Library:Notify({ Title = "Notification" })
]]
