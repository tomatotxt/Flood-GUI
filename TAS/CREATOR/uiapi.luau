--- START OF FILE uiapi.luau ---
--[[ 
    FE2 TAS UI Library (Mobile-Ready & Tabbed Edition)
    - Fully interactable buttons for every action (Mobile Support)
    - File Explorer Tab (Save, Load, Refresh List)
    - Configs Tab (Debug, Smoothing, Tracing, Predictor)
]]

local TAS_UI = {}
local TweenService = game:GetService("TweenService")

local THEME = {
    Bg = Color3.fromRGB(20, 20, 25),
    TabBg = Color3.fromRGB(30, 30, 35),
    Stroke = Color3.fromRGB(60, 60, 70),
    TextMain = Color3.fromRGB(240, 240, 240),
    TextDim = Color3.fromRGB(150, 150, 150),
    Accent = Color3.fromRGB(0, 170, 255),
    Alert = Color3.fromRGB(255, 170, 0),
    Button = Color3.fromRGB(45, 45, 55),
    ButtonHover = Color3.fromRGB(65, 65, 75)
}

local function CreateUIElement(className, props)
    local el = Instance.new(className)
    for k, v in pairs(props) do el[k] = v end
    return el
end

function TAS_UI.Create()
    local CoreGui = game:GetService("CoreGui")
    for _, v in pairs(CoreGui:GetChildren()) do if v.Name == "FE2_TAS_HUB" then v:Destroy() end end

    local ScreenGui = CreateUIElement("ScreenGui", {Name = "FE2_TAS_HUB", Parent = CoreGui, ResetOnSpawn = false})
    
    -- // MAIN DRAGGABLE FRAME //
    local MainFrame = CreateUIElement("Frame", {
        Parent = ScreenGui, Size = UDim2.new(0, 350, 0, 450), Position = UDim2.new(0.5, -175, 0.5, -225),
        BackgroundColor3 = THEME.Bg, Active = true, Draggable = true, ClipsDescendants = true
    })
    CreateUIElement("UICorner", {Parent = MainFrame, CornerRadius = UDim.new(0, 8)})
    CreateUIElement("UIStroke", {Parent = MainFrame, Color = THEME.Stroke, Thickness = 2})

    -- // TOP BAR //
    local TopBar = CreateUIElement("Frame", {Parent = MainFrame, Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = THEME.TabBg})
    CreateUIElement("UICorner", {Parent = TopBar, CornerRadius = UDim.new(0, 8)})
    local Title = CreateUIElement("TextLabel", {
        Parent = TopBar, Size = UDim2.new(1, -10, 0.5, 0), Position = UDim2.new(0, 10, 0, 0),
        BackgroundTransparency = 1, Text = "FE2 TAS CREATOR", Font = Enum.Font.GothamBold,
        TextColor3 = THEME.Accent, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left
    })
    local TimeText = CreateUIElement("TextLabel", {
        Parent = TopBar, Size = UDim2.new(1, -10, 0.5, 0), Position = UDim2.new(0, 10, 0.5, 0),
        BackgroundTransparency = 1, Text = "0:00.000", Font = Enum.Font.RobotoMono,
        TextColor3 = THEME.TextMain, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left
    })
    local StatusText = CreateUIElement("TextLabel", {
        Parent = TopBar, Size = UDim2.new(0.5, -10, 1, 0), Position = UDim2.new(0.5, 0, 0, 0),
        BackgroundTransparency = 1, Text = "PAUSED", Font = Enum.Font.GothamBold,
        TextColor3 = THEME.Alert, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Right
    })

    -- // TAB BUTTONS //
    local TabContainer = CreateUIElement("Frame", {Parent = MainFrame, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 0, 50), BackgroundTransparency = 1})
    CreateUIElement("UIListLayout", {Parent = TabContainer, FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder})
    
    local Tabs = {}
    local Panels = {}
    local function CreateTab(name, order)
        local btn = CreateUIElement("TextButton", {
            Parent = TabContainer, Size = UDim2.new(1/3, 0, 1, 0), LayoutOrder = order,
            BackgroundColor3 = THEME.Button, Text = name, Font = Enum.Font.GothamBold, TextColor3 = THEME.TextDim, TextSize = 12
        })
        local panel = CreateUIElement("ScrollingFrame", {
            Parent = MainFrame, Size = UDim2.new(1, -20, 1, -90), Position = UDim2.new(0, 10, 0, 85),
            BackgroundTransparency = 1, Visible = false, ScrollBarThickness = 4, CanvasSize = UDim2.new(0,0,0,0), AutomaticCanvasSize = Enum.AutomaticSize.Y
        })
        CreateUIElement("UIListLayout", {Parent = panel, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5)})
        Tabs[name] = btn; Panels[name] = panel
        
        btn.Activated:Connect(function()
            for k, p in pairs(Panels) do p.Visible = false; Tabs[k].BackgroundColor3 = THEME.Button; Tabs[k].TextColor3 = THEME.TextDim end
            panel.Visible = true; btn.BackgroundColor3 = THEME.Accent; btn.TextColor3 = Color3.new(1,1,1)
        end)
        return panel
    end

    local CtrlPanel = CreateTab("Controls", 1)
    local VisPanel = CreateTab("Config", 2)
    local FilePanel = CreateTab("Files", 3)
    Panels["Controls"].Visible = true; Tabs["Controls"].BackgroundColor3 = THEME.Accent; Tabs["Controls"].TextColor3 = Color3.new(1,1,1)

    -- // BUTTON GENERATOR //
    local Buttons = {}
    local function AddBtn(parent, name, text, color)
        local b = CreateUIElement("TextButton", {
            Parent = parent, Size = UDim2.new(1, 0, 0, 35), BackgroundColor3 = color or THEME.Button,
            Text = text, Font = Enum.Font.GothamBold, TextColor3 = THEME.TextMain, TextSize = 14
        })
        CreateUIElement("UICorner", {Parent = b, CornerRadius = UDim.new(0, 6)})
        Buttons[name] = b
        return b
    end

    -- // CONTROLS TAB //
    AddBtn(CtrlPanel, "Pause", "Play / Pause (CapsLock)")
    AddBtn(CtrlPanel, "StepFwd", "Step Forward (5)")
    AddBtn(CtrlPanel, "StepBack", "Rewind Frame (4)")
    AddBtn(CtrlPanel, "AddState", "Add Savestate (1)", Color3.fromRGB(40, 90, 40))
    AddBtn(CtrlPanel, "LoadState", "Load Last State (3)")
    AddBtn(CtrlPanel, "RemState", "Remove State (2)", Color3.fromRGB(90, 40, 40))
    AddBtn(CtrlPanel, "Resync", "Resync Visuals (F8)")
    AddBtn(CtrlPanel, "Stop", "STOP TAS CREATOR (Del)", Color3.fromRGB(150, 0, 0))

    -- // CONFIG TAB //
    AddBtn(VisPanel, "DebugView", "Toggle Debug Hitboxes (V)")
    AddBtn(VisPanel, "SmoothMode", "Extreme Smoothing: OFF")
    AddBtn(VisPanel, "PathTracing", "TAS Path Tracing: OFF")
    AddBtn(VisPanel, "Trajectory", "Predictive Velocity: ON")
    AddBtn(VisPanel, "CamMode", "Playback Camera Follow: OFF")
    AddBtn(VisPanel, "Collision", "Toggle Collision (C)")

    -- // FILES TAB //
    local SaveBox = CreateUIElement("TextBox", {
        Parent = FilePanel, Size = UDim2.new(1, 0, 0, 35), BackgroundColor3 = THEME.Bg,
        Text = "", PlaceholderText = "Enter filename to save...", Font = Enum.Font.Gotham, TextColor3 = THEME.TextMain, TextSize = 14
    })
    CreateUIElement("UICorner", {Parent = SaveBox, CornerRadius = UDim.new(0,6)})
    CreateUIElement("UIStroke", {Parent = SaveBox, Color = THEME.Stroke, Thickness = 1})
    
    AddBtn(FilePanel, "Save", "SAVE RUN", THEME.Accent)
    AddBtn(FilePanel, "Refresh", "REFRESH FILE LIST")
    
    local FileList = CreateUIElement("ScrollingFrame", {
        Parent = FilePanel, Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = THEME.Bg,
        ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y
    })
    CreateUIElement("UIListLayout", {Parent = FileList, SortOrder = Enum.SortOrder.LayoutOrder})
    CreateUIElement("UICorner", {Parent = FileList, CornerRadius = UDim.new(0,6)})
    CreateUIElement("UIStroke", {Parent = FileList, Color = THEME.Stroke, Thickness = 1})

    local SelectedLabel = CreateUIElement("TextLabel", {
        Parent = FilePanel, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
        Text = "Selected: None", Font = Enum.Font.Gotham, TextColor3 = THEME.TextDim, TextSize = 12
    })
    
    AddBtn(FilePanel, "Load", "LOAD SELECTED RUN", Color3.fromRGB(0, 150, 100))
    AddBtn(FilePanel, "PlaySelected", "PLAYBACK TAS (0)")

    -- Return API
    return {
        ScreenGui = ScreenGui, TimeText = TimeText, StatusText = StatusText,
        Buttons = Buttons, SaveBox = SaveBox, FileList = FileList, SelectedLabel = SelectedLabel
    }
end

return TAS_UI
