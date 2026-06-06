--- START OF FILE uiapi.luau ---

--[[ 
    FE2 TAS UI Library (Auto-Layout Edition)
    - Uses UIListLayout to automatically position the Keybind menu
    - Zero overlap, zero manual pixel measuring
    - Auto GameGui Toggle included
    - *MODIFIED*: Map Name integrated into lower panel, Status Badge moved up.
]]

local TAS_UI = {}
local TweenService = game:GetService("TweenService")

-- // Styling Constants //
local THEME = {
    Background = Color3.fromRGB(25, 25, 30),
    Stroke = Color3.fromRGB(60, 60, 70),
    TextMain = Color3.fromRGB(240, 240, 240),
    TextDim = Color3.fromRGB(180, 180, 180),
    Accent = Color3.fromRGB(85, 170, 255),
    Alert = Color3.fromRGB(255, 200, 80),
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

    -- Move Alerts to LocatorGui (which stays enabled) so we can see them
    if AlertsFrame and LocatorGui then
        AlertsFrame.Parent = LocatorGui
    end

    -- Disable the main GameGui to hide clutter
    if GameGui then 
        GameGui.Enabled = false 
    end

    -- // 1. ScreenGui //
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "TAS_HUD"
    ScreenGui.Parent = CoreGui
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.ResetOnSpawn = false

    -- // Cleanup Logic //
    ScreenGui.Destroying:Connect(function()
        -- Restore Alerts back to GameGui
        if AlertsFrame and GameGui then
            AlertsFrame.Parent = GameGui
        end
        -- Re-enable GameGui
        if GameGui then 
            GameGui.Enabled = true 
        end
    end)

    -- // 2. The Magic Container (Holds both menus) //
    local Container = Instance.new("Frame")
    Container.Name = "LayoutContainer"
    Container.Parent = ScreenGui
    Container.BackgroundTransparency = 1
    -- Centered at the bottom of the screen
    Container.AnchorPoint = Vector2.new(0.5, 1) 
    Container.Position = UDim2.new(0.5, 0, 0.95, 0)
    Container.Size = UDim2.new(0, 0, 0, 0) -- Starts at 0
    -- THIS makes the container expand to fit both menus automatically
    Container.AutomaticSize = Enum.AutomaticSize.XY 

    -- // 3. The Layout Instance //
    local Layout = Instance.new("UIListLayout")
    Layout.Parent = Container
    Layout.FillDirection = Enum.FillDirection.Horizontal -- Places items side-by-side
    Layout.VerticalAlignment = Enum.VerticalAlignment.Bottom -- Aligns them to the bottom
    Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center -- Keeps group centered
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    Layout.Padding = UDim.new(0, 15) -- 15px Gap between Main Menu and Keybinds

    -- // 4. Stats Panel (Main Menu) //
    local StatsPanel = Instance.new("Frame")
    StatsPanel.Name = "StatsPanel"
    StatsPanel.Parent = Container
    StatsPanel.BackgroundColor3 = THEME.Background
    StatsPanel.BackgroundTransparency = 0.15
    StatsPanel.LayoutOrder = 1 -- Forces this to be on the LEFT
    StatsPanel.Size = UDim2.new(0, 360, 0, 85)
    
    local PCorner = Instance.new("UICorner")
    PCorner.CornerRadius = UDim.new(0, 12)
    PCorner.Parent = StatsPanel
    
    local PStroke = Instance.new("UIStroke")
    PStroke.Color = THEME.Stroke
    PStroke.Thickness = 1.5
    PStroke.Parent = StatsPanel

    -- // 5. Keybind Window //
    local KBFrame = Instance.new("Frame")
    KBFrame.Name = "KeybindFrame"
    KBFrame.Parent = Container
    KBFrame.BackgroundColor3 = THEME.Background
    KBFrame.BackgroundTransparency = 0.1
    KBFrame.LayoutOrder = 2 -- Forces this to be on the RIGHT
    KBFrame.Size = UDim2.new(0, 240, 0, 390) -- Increased height for extra keybind
    KBFrame.Visible = false -- Hidden by default
    KBFrame.ClipsDescendants = true

    local KBFCorner = Instance.new("UICorner")
    KBFCorner.CornerRadius = UDim.new(0, 10)
    KBFCorner.Parent = KBFrame

    local KBFStroke = Instance.new("UIStroke")
    KBFStroke.Color = THEME.Accent
    KBFStroke.Transparency = 0.5
    KBFStroke.Thickness = 1
    KBFStroke.Parent = KBFrame

    -- // Stats Panel Contents //
    local TimeText = Instance.new("TextLabel")
    TimeText.Name = "TimeText"
    TimeText.Parent = StatsPanel
    TimeText.BackgroundTransparency = 1
    TimeText.Position = UDim2.new(0.05, 0, 0.1, 0)
    TimeText.Size = UDim2.new(0.5, 0, 0.5, 0)
    TimeText.Font = Enum.Font.Highway
    TimeText.Text = "0:00.000"
    TimeText.TextColor3 = THEME.TextMain
    TimeText.TextScaled = true
    TimeText.TextXAlignment = Enum.TextXAlignment.Left

    local function CreateInfoLabel(name, posY)
        local L = Instance.new("TextLabel")
        L.Parent = StatsPanel
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

    -- Toggle Button
    local KeybindButton = Instance.new("TextButton")
    KeybindButton.Parent = StatsPanel
    KeybindButton.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    KeybindButton.Position = UDim2.new(0.6, 0, 0.65, 0)
    KeybindButton.Size = UDim2.new(0.35, 0, 0.25, 0)
    KeybindButton.Font = Enum.Font.GothamBold
    KeybindButton.Text = "Controls"
    KeybindButton.TextColor3 = THEME.TextMain
    KeybindButton.TextSize = 14
    KeybindButton.AutoButtonColor = false

    local KBCorner = Instance.new("UICorner")
    KBCorner.CornerRadius = UDim.new(0, 6)
    KBCorner.Parent = KeybindButton
    
    local KBStroke = Instance.new("UIStroke")
    KBStroke.Color = THEME.Stroke
    KBStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    KBStroke.Parent = KeybindButton

    -- MOVED: Map Name is now in the lower panel (Replacing old Status Pos)
    local MapEventInfo = Instance.new("TextLabel")
    MapEventInfo.Parent = StatsPanel
    MapEventInfo.BackgroundTransparency = 1
    MapEventInfo.Position = UDim2.new(0.05, 0, 0.65, 0)
    MapEventInfo.Size = UDim2.new(0.5, 0, 0.25, 0)
    MapEventInfo.Font = Enum.Font.GothamBold
    MapEventInfo.Text = "Map: Waiting..."
    MapEventInfo.TextColor3 = THEME.Accent
    MapEventInfo.TextScaled = true
    MapEventInfo.TextXAlignment = Enum.TextXAlignment.Left

    -- MOVED: Status Badge moved to top right corner of Time area
    local StatusBadge = Instance.new("TextLabel")
    StatusBadge.Parent = StatsPanel
    StatusBadge.BackgroundTransparency = 1
    StatusBadge.Position = UDim2.new(0.4, 0, 0.15, 0) -- Adjusted position
    StatusBadge.Size = UDim2.new(0.15, 0, 0.15, 0)
    StatusBadge.Font = Enum.Font.GothamMedium
    StatusBadge.Text = "PAUSED"
    StatusBadge.TextColor3 = THEME.Alert
    StatusBadge.TextScaled = true
    StatusBadge.TextXAlignment = Enum.TextXAlignment.Left

    -- // Keybind List Logic //
    local KBList = Instance.new("UIListLayout")
    KBList.Parent = KBFrame
    KBList.SortOrder = Enum.SortOrder.LayoutOrder
    KBList.Padding = UDim.new(0, 4)
    KBList.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local KBPadding = Instance.new("UIPadding")
    KBPadding.Parent = KBFrame
    KBPadding.PaddingTop = UDim.new(0, 10)
    KBPadding.PaddingBottom = UDim.new(0, 10)
    KBPadding.PaddingLeft = UDim.new(0, 10)
    KBPadding.PaddingRight = UDim.new(0, 10)

    local function AddKeybindRow(keyText, actionText, order)
        local Row = Instance.new("Frame")
        Row.BackgroundTransparency = 1
        Row.Size = UDim2.new(1, 0, 0, 20)
        Row.LayoutOrder = order
        Row.Parent = KBFrame

        local Key = Instance.new("TextLabel")
        Key.Parent = Row
        Key.BackgroundTransparency = 1
        Key.Size = UDim2.new(0.4, 0, 1, 0)
        Key.Font = Enum.Font.GothamBold
        Key.Text = keyText
        Key.TextColor3 = THEME.Accent
        Key.TextXAlignment = Enum.TextXAlignment.Left
        Key.TextSize = 12

        local Action = Instance.new("TextLabel")
        Action.Parent = Row
        Action.BackgroundTransparency = 1
        Action.Position = UDim2.new(0.4, 0, 0, 0)
        Action.Size = UDim2.new(0.6, 0, 1, 0)
        Action.Font = Enum.Font.Gotham
        Action.Text = actionText
        Action.TextColor3 = THEME.TextMain
        Action.TextXAlignment = Enum.TextXAlignment.Right
        Action.TextSize = 12
    end

    AddKeybindRow("CAPSLOCK", "Pause / Unpause", 1)
    AddKeybindRow("1", "Add Savestate", 2)
    AddKeybindRow("2", "Remove Savestate", 3)
    AddKeybindRow("3", "Load Last State", 4)
    AddKeybindRow("4 / 5", "Frame Step", 5)
    AddKeybindRow("6", "Save Run (JSON)", 6)
    AddKeybindRow("0", "Playback TAS", 7)
    AddKeybindRow("7", "Auto-Reset Env", 8) -- NEW
    AddKeybindRow("C", "Toggle Collision", 9)
    AddKeybindRow("UP / DOWN", "Visual Time Travel", 10)
    AddKeybindRow("F8", "Resync Visuals", 11)
    AddKeybindRow("EQUALS (=)", "Freeze Map Updates", 12)
    AddKeybindRow("DELETE", "DESTROY UI", 13)

    -- // Button Events //
    KeybindButton.MouseEnter:Connect(function()
        TweenService:Create(KeybindButton, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(60, 60, 70)}):Play()
    end)
    KeybindButton.MouseLeave:Connect(function()
        TweenService:Create(KeybindButton, TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(40, 40, 45)}):Play()
    end)

    local isKBOpen = false
    KeybindButton.Activated:Connect(function()
        isKBOpen = not isKBOpen
        if isKBOpen then
            KBFrame.Visible = true
            -- Animating Opacity for effect
            KBFrame.BackgroundTransparency = 1
            KBFStroke.Transparency = 1
            TweenService:Create(KBFrame, TweenInfo.new(0.3), {BackgroundTransparency = 0.1}):Play()
            TweenService:Create(KBFStroke, TweenInfo.new(0.3), {Transparency = 0.5}):Play()
            
            KeybindButton.Text = "Hide Controls"
            KeybindButton.TextColor3 = THEME.Accent
        else
            local t = TweenService:Create(KBFrame, TweenInfo.new(0.2), {BackgroundTransparency = 1})
            TweenService:Create(KBFStroke, TweenInfo.new(0.2), {Transparency = 1}):Play()
            t:Play()
            t.Completed:Connect(function()
                if not isKBOpen then KBFrame.Visible = false end
            end)
            KeybindButton.Text = "Controls"
            KeybindButton.TextColor3 = THEME.TextMain
        end
    end)

    return {
        ScreenGui = ScreenGui,
        TimeText = TimeText,
        SavestatesCount = SavestatesCount,
        FrameCount = FrameCount,
        StatusText = StatusBadge,
        MapEventInfo = MapEventInfo -- Now located in StatsPanel
    }
end

return TAS_UI
