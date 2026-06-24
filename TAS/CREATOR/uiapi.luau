--[[ 
    FE2 TAS UI Library (Mobile-Ready Tabbed Edition)
    - 100% Backwards Compatible with legacy creator.luau
    - Replaced the text-only Keybind list with an interactive Tabbed Menu
    - Tabs: [ Controls ] [ Config ] [ Files ]
    - Fully clickable buttons for mobile/PC users
]]

local TAS_UI = {}
local TweenService = game:GetService("TweenService")

-- // Styling Constants //
local THEME = {
    Background = Color3.fromRGB(25, 25, 30),
    TabBg = Color3.fromRGB(35, 35, 40),
    Stroke = Color3.fromRGB(60, 60, 70),
    TextMain = Color3.fromRGB(240, 240, 240),
    TextDim = Color3.fromRGB(180, 180, 180),
    Accent = Color3.fromRGB(85, 170, 255),
    Alert = Color3.fromRGB(255, 200, 80),
    Button = Color3.fromRGB(45, 45, 55),
}

function TAS_UI.Create()
    local CoreGui = game:GetService("CoreGui")
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 5)

    -- // Clean up old UIs first //
    for _, v in pairs(CoreGui:GetChildren()) do
        if v.Name == "TAS_HUD" then v:Destroy() end
    end

    -- // GameGui & Alerts Handling //
    local GameGui = PlayerGui and PlayerGui:WaitForChild("GameGui", 5)
    local LocatorGui = PlayerGui and PlayerGui:WaitForChild("LocatorGui", 5)
    local AlertsFrame = GameGui and GameGui:FindFirstChild("Alerts")

    if AlertsFrame and LocatorGui then AlertsFrame.Parent = LocatorGui end
    if GameGui then GameGui.Enabled = false end

    -- // 1. ScreenGui //
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "TAS_HUD"
    ScreenGui.Parent = CoreGui
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.ResetOnSpawn = false

    ScreenGui.Destroying:Connect(function()
        if AlertsFrame and GameGui then AlertsFrame.Parent = GameGui end
        if GameGui then GameGui.Enabled = true end
    end)

    -- // 2. The Magic Container //
    local Container = Instance.new("Frame")
    Container.Name = "LayoutContainer"
    Container.Parent = ScreenGui
    Container.BackgroundTransparency = 1
    Container.AnchorPoint = Vector2.new(0.5, 1) 
    Container.Position = UDim2.new(0.5, 0, 0.95, 0)
    Container.Size = UDim2.new(0, 0, 0, 0)
    Container.AutomaticSize = Enum.AutomaticSize.XY 

    local Layout = Instance.new("UIListLayout")
    Layout.Parent = Container
    Layout.FillDirection = Enum.FillDirection.Horizontal 
    Layout.VerticalAlignment = Enum.VerticalAlignment.Bottom 
    Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center 
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    Layout.Padding = UDim.new(0, 15)

    -- // 3. Stats Panel (LEGACY COMPATIBLE) //
    local StatsPanel = Instance.new("Frame")
    StatsPanel.Name = "StatsPanel"
    StatsPanel.Parent = Container
    StatsPanel.BackgroundColor3 = THEME.Background
    StatsPanel.BackgroundTransparency = 0.15
    StatsPanel.LayoutOrder = 1 
    StatsPanel.Size = UDim2.new(0, 360, 0, 85)
    
    local PCorner = Instance.new("UICorner", StatsPanel)
    PCorner.CornerRadius = UDim.new(0, 12)
    local PStroke = Instance.new("UIStroke", StatsPanel)
    PStroke.Color = THEME.Stroke; PStroke.Thickness = 1.5

    local TimeText = Instance.new("TextLabel", StatsPanel)
    TimeText.BackgroundTransparency = 1
    TimeText.Position = UDim2.new(0.05, 0, 0.1, 0)
    TimeText.Size = UDim2.new(0.5, 0, 0.5, 0)
    TimeText.Font = Enum.Font.Highway
    TimeText.Text = "0:00.000"
    TimeText.TextColor3 = THEME.TextMain
    TimeText.TextScaled = true
    TimeText.TextXAlignment = Enum.TextXAlignment.Left

    local function CreateInfoLabel(name, posY)
        local L = Instance.new("TextLabel", StatsPanel)
        L.BackgroundTransparency = 1
        L.Position = UDim2.new(0.6, 0, posY, 0)
        L.Size = UDim2.new(0.35, 0, 0.2, 0)
        L.Font = Enum.Font.Highway
        L.Text = name
        L.TextColor3 = THEME.TextDim
        L.TextScaled = true
        L.TextXAlignment = Enum.TextXAlignment.Right
        return L
    end

    local SavestatesCount = CreateInfoLabel("Savestates 0", 0.15)
    local FrameCount = CreateInfoLabel("Frames 0", 0.38)

    local MenuToggleButton = Instance.new("TextButton", StatsPanel)
    MenuToggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    MenuToggleButton.Position = UDim2.new(0.6, 0, 0.65, 0)
    MenuToggleButton.Size = UDim2.new(0.35, 0, 0.25, 0)
    MenuToggleButton.Font = Enum.Font.GothamBold
    MenuToggleButton.Text = "Open Menu"
    MenuToggleButton.TextColor3 = THEME.TextMain
    MenuToggleButton.TextSize = 14
    Instance.new("UICorner", MenuToggleButton).CornerRadius = UDim.new(0, 6)
    local MBStroke = Instance.new("UIStroke", MenuToggleButton)
    MBStroke.Color = THEME.Stroke; MBStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local MapEventInfo = Instance.new("TextLabel", StatsPanel)
    MapEventInfo.BackgroundTransparency = 1
    MapEventInfo.Position = UDim2.new(0.05, 0, 0.65, 0)
    MapEventInfo.Size = UDim2.new(0.5, 0, 0.25, 0)
    MapEventInfo.Font = Enum.Font.GothamBold
    MapEventInfo.Text = "Map: Waiting..."
    MapEventInfo.TextColor3 = THEME.Accent
    MapEventInfo.TextScaled = true
    MapEventInfo.TextXAlignment = Enum.TextXAlignment.Left

    local StatusBadge = Instance.new("TextLabel", StatsPanel)
    StatusBadge.BackgroundTransparency = 1
    StatusBadge.Position = UDim2.new(0.4, 0, 0.15, 0) 
    StatusBadge.Size = UDim2.new(0.15, 0, 0.15, 0)
    StatusBadge.Font = Enum.Font.GothamMedium
    StatusBadge.Text = "PAUSED"
    StatusBadge.TextColor3 = THEME.Alert
    StatusBadge.TextScaled = true
    StatusBadge.TextXAlignment = Enum.TextXAlignment.Left

    -- // 4. Interactive Menu Window (Replaces KBFrame) //
    local MenuFrame = Instance.new("Frame", Container)
    MenuFrame.Name = "MenuFrame"
    MenuFrame.BackgroundColor3 = THEME.Background
    MenuFrame.BackgroundTransparency = 0.1
    MenuFrame.LayoutOrder = 2 
    MenuFrame.Size = UDim2.new(0, 280, 0, 420)
    MenuFrame.Visible = false 
    MenuFrame.ClipsDescendants = true
    Instance.new("UICorner", MenuFrame).CornerRadius = UDim.new(0, 10)
    local MFStroke = Instance.new("UIStroke", MenuFrame)
    MFStroke.Color = THEME.Accent; MFStroke.Transparency = 0.5; MFStroke.Thickness = 1

    -- // 5. Tab System //
    local TabBar = Instance.new("Frame", MenuFrame)
    TabBar.Size = UDim2.new(1, 0, 0, 40)
    TabBar.BackgroundColor3 = THEME.TabBg
    TabBar.BackgroundTransparency = 0.3
    local TabList = Instance.new("UIListLayout", TabBar)
    TabList.FillDirection = Enum.FillDirection.Horizontal
    TabList.SortOrder = Enum.SortOrder.LayoutOrder

    local PagesContainer = Instance.new("Frame", MenuFrame)
    PagesContainer.Position = UDim2.new(0, 0, 0, 40)
    PagesContainer.Size = UDim2.new(1, 0, 1, -40)
    PagesContainer.BackgroundTransparency = 1

    local Tabs = {}
    local Pages = {}

    local function CreateTab(name, order)
        local btn = Instance.new("TextButton", TabBar)
        btn.Size = UDim2.new(1/3, 0, 1, 0)
        btn.LayoutOrder = order
        btn.BackgroundColor3 = THEME.TabBg
        btn.BackgroundTransparency = 1
        btn.Text = name
        btn.Font = Enum.Font.GothamBold
        btn.TextColor3 = THEME.TextDim
        btn.TextSize = 13

        local page = Instance.new("ScrollingFrame", PagesContainer)
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.ScrollBarThickness = 4
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.CanvasSize = UDim2.new(0, 0, 0, 0)
        page.Visible = false

        local pList = Instance.new("UIListLayout", page)
        pList.SortOrder = Enum.SortOrder.LayoutOrder
        pList.Padding = UDim.new(0, 6)
        pList.HorizontalAlignment = Enum.HorizontalAlignment.Center
        
        local pPad = Instance.new("UIPadding", page)
        pPad.PaddingTop = UDim.new(0, 10)
        pPad.PaddingBottom = UDim.new(0, 10)

        Tabs[name] = btn
        Pages[name] = page

        btn.Activated:Connect(function()
            for k, p in pairs(Pages) do p.Visible = false; Tabs[k].TextColor3 = THEME.TextDim end
            page.Visible = true; btn.TextColor3 = THEME.Accent
        end)

        return page
    end

    local CtrlPage = CreateTab("Controls", 1)
    local ConfigPage = CreateTab("Config", 2)
    local FilePage = CreateTab("Files", 3)
    Pages["Controls"].Visible = true; Tabs["Controls"].TextColor3 = THEME.Accent

    -- // Button Generator //
    local ExportedButtons = {}
    local function AddBtn(parent, actionId, text, color)
        local b = Instance.new("TextButton", parent)
        b.Size = UDim2.new(0.9, 0, 0, 35)
        b.BackgroundColor3 = color or THEME.Button
        b.Text = text
        b.Font = Enum.Font.GothamBold
        b.TextColor3 = THEME.TextMain
        b.TextSize = 13
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        ExportedButtons[actionId] = b
        return b
    end

    -- // Populate Controls Tab //
    AddBtn(CtrlPage, "Pause", "Play / Pause (CapsLock)")
    AddBtn(CtrlPage, "AddState", "Add Savestate (1)", Color3.fromRGB(40, 90, 40))
    AddBtn(CtrlPage, "RemState", "Remove Savestate (2)", Color3.fromRGB(90, 40, 40))
    AddBtn(CtrlPage, "LoadState", "Load Last State (3)")
    AddBtn(CtrlPage, "StepBack", "Rewind Frame (4)")
    AddBtn(CtrlPage, "StepFwd", "Step Forward (5)")
    AddBtn(CtrlPage, "Resync", "Resync Visuals (F8)")
    AddBtn(CtrlPage, "PlayTAS", "Playback TAS (0)")
    AddBtn(CtrlPage, "Collision", "Toggle Collision (C)")
    AddBtn(CtrlPage, "Stop", "STOP CREATOR (Del)", Color3.fromRGB(150, 0, 0))

    -- // Populate Config Tab //
    AddBtn(ConfigPage, "DebugView", "Debug Hitboxes: OFF")
    AddBtn(ConfigPage, "SmoothMode", "Extreme Smoothing: OFF")
    AddBtn(ConfigPage, "PathTracing", "TAS Path Tracing: OFF")
    AddBtn(ConfigPage, "Trajectory", "Predictive Velocity: OFF")
    AddBtn(ConfigPage, "CamMode", "Camera Follow: OFF")
    AddBtn(ConfigPage, "EnvSync", "Auto-Reset Env: OFF")
    AddBtn(ConfigPage, "AutoSwim", "Auto-Swim: ON", Color3.fromRGB(0, 150, 100)) -- Added Auto-Swim Toggle (ON by default)

    -- // Populate Files Tab //
    local SaveBox = Instance.new("TextBox", FilePage)
    SaveBox.Size = UDim2.new(0.9, 0, 0, 35)
    SaveBox.BackgroundColor3 = THEME.Background
    SaveBox.Text = ""
    SaveBox.PlaceholderText = "Enter save filename..."
    SaveBox.Font = Enum.Font.Gotham
    SaveBox.TextColor3 = THEME.TextMain
    SaveBox.TextSize = 13
    Instance.new("UICorner", SaveBox).CornerRadius = UDim.new(0,6)
    Instance.new("UIStroke", SaveBox).Color = THEME.Stroke

    AddBtn(FilePage, "SaveRun", "SAVE RUN", THEME.Accent)
    AddBtn(FilePage, "RefreshList", "Refresh File List")

    local FileList = Instance.new("ScrollingFrame", FilePage)
    FileList.Size = UDim2.new(0.9, 0, 0, 160)
    FileList.BackgroundColor3 = THEME.Background
    FileList.ScrollBarThickness = 4
    FileList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    Instance.new("UICorner", FileList).CornerRadius = UDim.new(0,6)
    Instance.new("UIStroke", FileList).Color = THEME.Stroke
    
    local FListLayout = Instance.new("UIListLayout", FileList)
    FListLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local SelectedLabel = Instance.new("TextLabel", FilePage)
    SelectedLabel.Size = UDim2.new(0.9, 0, 0, 20)
    SelectedLabel.BackgroundTransparency = 1
    SelectedLabel.Text = "Selected: None"
    SelectedLabel.Font = Enum.Font.Gotham
    SelectedLabel.TextColor3 = THEME.TextDim
    SelectedLabel.TextSize = 12

    AddBtn(FilePage, "LoadRun", "LOAD SELECTED RUN", Color3.fromRGB(0, 150, 100))

    -- // Menu Toggle Animation Logic //
    local isMenuOpen = false
    MenuToggleButton.Activated:Connect(function()
        isMenuOpen = not isMenuOpen
        if isMenuOpen then
            MenuFrame.Visible = true
            MenuFrame.BackgroundTransparency = 1
            MFStroke.Transparency = 1
            TweenService:Create(MenuFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0.1}):Play()
            TweenService:Create(MFStroke, TweenInfo.new(0.3), {Transparency = 0.5}):Play()
            
            MenuToggleButton.Text = "Close Menu"
            MenuToggleButton.TextColor3 = THEME.Accent
        else
            local t = TweenService:Create(MenuFrame, TweenInfo.new(0.2), {BackgroundTransparency = 1})
            TweenService:Create(MFStroke, TweenInfo.new(0.2), {Transparency = 1}):Play()
            t:Play()
            t.Completed:Connect(function() if not isMenuOpen then MenuFrame.Visible = false end end)
            
            MenuToggleButton.Text = "Open Menu"
            MenuToggleButton.TextColor3 = THEME.TextMain
        end
    end)

    -- // RETURN TABLE //
    return {
        ScreenGui = ScreenGui,
        TimeText = TimeText,
        SavestatesCount = SavestatesCount,
        FrameCount = FrameCount,
        StatusText = StatusBadge,
        MapEventInfo = MapEventInfo,

        Buttons = ExportedButtons,
        SaveBox = SaveBox,
        FileList = FileList,
        SelectedLabel = SelectedLabel
    }
end

return TAS_UI