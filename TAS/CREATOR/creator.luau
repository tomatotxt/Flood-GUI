--[[
    FE2 TAS Creator (Ultimate Edition)
    - FEATURES: Debug View, Extreme Smoothing, Camera Toggle, 
      In-Game Loading, TAS Path Tracing, Predictive Trajectory.
    - Full Mobile/PC UI Integration.
]]

getgenv().TAS_Active = true 

local UI_API_URL = "https://raw.githubusercontent.com/tomatotxt/Flood-GUI/refs/heads/testing/TAS/CREATOR/uiapi.luau"
print("FE2 Ultimate TAS Creator Loaded")

-- // CONFIGURATIONS //
getgenv().ExtremeSmoothing = false
getgenv().TargetSmoothingFPS = 24
getgenv().ShowTASPathDuringPlayback = false
getgenv().PlaybackCamera = false
getgenv().ShowVelocityPredictor = true

-- // SERVICES //
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

pcall(function() ReplicatedStorage.Remote.ReqPasskey:InvokeServer() end)

-- // VARIABLES //
local CurrentAnim, Savestates, Frames = {}, {}, {}
local TimeOffset, PreviewOffset = 0, 0
local IsPaused, EnvPaused = true, false
local PauseStart, RunStart, SavedVelocity
local Connections = {} 

local IsAdvancingFrame, IsRewinding, IsViewingTAS = false, false, false
local MapEvents, MapRecorderCache, ClonedMap = {}, {}, nil
local MapOffset, MapPos, MapX, MapY, MapZ = CFrame.new(), Vector3.zero, 0, 0, 0
local MapUUIDs = {} 

local RecordAccumulator = 0
local TARGET_FPS = 60
local RECORD_INTERVAL = 1 / TARGET_FPS

local TotalButtons, ButtonRegistry = {}, {}
getgenv().IsSwimming = false
local WaterParts = {}

-- // VISUALIZER GLOBALS //
local OriginalVisuals = setmetatable({}, { __mode = "k" })
local DebugActive = false
local TrajectoryFolder = Instance.new("Folder", workspace)
TrajectoryFolder.Name = "TAS_Trajectory"
local TrajectoryLines = {}
local PathLines = {}
local SelectedFileToLoad = ""

-- // DATA PACKING //
local PACK_FORMAT = "d" .. string.rep("f", 28) .. "s"
local function PackFrame(Time, Vel, CF, CamCF, Anim)
    local anm = Anim[1] or "idle"
    local asp = Anim[2] or 0
    local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = CF:GetComponents()
    local cx, cy, cz, cR00, cR01, cR02, cR10, cR11, cR12, cR20, cR21, cR22 = CamCF:GetComponents()
    return string.pack(PACK_FORMAT, Time, Vel.X, Vel.Y, Vel.Z, x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22, cx, cy, cz, cR00, cR01, cR02, cR10, cR11, cR12, cR20, cR21, cR22, asp, anm)
end

local function UnpackFrame(data)
    local t, vx, vy, vz, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, cm1, cm2, cm3, cm4, cm5, cm6, cm7, cm8, cm9, cm10, cm11, cm12, asp, anm = string.unpack(PACK_FORMAT, data)
    return {
        Time = t, Velocity = Vector3.new(vx, vy, vz),
        CFrame = CFrame.new(c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12),
        CameraCFrame = CFrame.new(cm1, cm2, cm3, cm4, cm5, cm6, cm7, cm8, cm9, cm10, cm11, cm12),
        Animation = {anm, asp}
    }
end

-- // HELPER FUNCTIONS //
local function AddConnection(con) table.insert(Connections, con); return con end

local function GetPlayerCFrame()
    local Root = LocalPlayer.Character.HumanoidRootPart
    local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = Root.CFrame:GetComponents()
    return CFrame.new(x - MapX, y - MapY + 1000, z - MapZ, R00, R01, R02, R10, R11, R12, R20, R21, R22)
end

local function CaptureFrameData()
    return PackFrame(tick() - RunStart - TimeOffset, LocalPlayer.Character.HumanoidRootPart.Velocity, GetPlayerCFrame(), workspace.CurrentCamera.CFrame, CurrentAnim)
end

-- // UI API LOADING & MAPPING //
local TAS_UI = loadstring(game:HttpGet(UI_API_URL))()
local UI = TAS_UI.Create()

local function UpdateTimeDisplay(DisplayTime)
    if not UI.TimeText then return end
    local m = math.floor(DisplayTime / 60)
    local s = math.floor(DisplayTime % 60)
    local ms = math.floor(DisplayTime * 1000 % 1000)
    UI.TimeText.Text = string.format("%d:%02d.%03d", m, s, ms)
end

-- // TAS CORE LOGIC //
local function TogglePause()
    IsPaused = not IsPaused
    local Root = LocalPlayer.Character.HumanoidRootPart
    if IsPaused then
        SavedVelocity = Root.Velocity; Root.Anchored = true; PauseStart = tick()
        UI.StatusText.Text = "PAUSED"; UI.StatusText.TextColor3 = Color3.fromRGB(255, 170, 0)
    else
        Root.Anchored = false; Root.Velocity = SavedVelocity
        TimeOffset = TimeOffset + tick() - PauseStart
        UI.StatusText.Text = "PLAYING"; UI.StatusText.TextColor3 = Color3.fromRGB(0, 255, 100)
        RecordAccumulator = 0
    end
end

local function LoadLastSavestate()
    local LastState = Savestates[#Savestates]
    if LastState and LastState[#LastState] then
        local Frame = UnpackFrame(LastState[#LastState])
        Frames = {}; IsPaused = true; PreviewOffset = 0
        local Root = LocalPlayer.Character.HumanoidRootPart
        Root.Anchored = true
        Root.CFrame = Frame.CFrame + Vector3.new(MapX, MapY - 1000, MapZ)
        Root.Velocity = Frame.Velocity; SavedVelocity = Frame.Velocity
        workspace.CurrentCamera.CFrame = Frame.CameraCFrame
        PauseStart = tick(); RunStart = tick() - Frame.Time; TimeOffset = 0
        UpdateTimeDisplay(Frame.Time)
    end
end

local function AddSavestate() table.insert(Savestates, Frames); Frames = {} end
local function RemoveSavestate()
    if #Savestates > 1 then table.remove(Savestates); LoadLastSavestate() end
end

local function StepForward()
    if not IsPaused then return end 
    local InitialFrames = #Frames; TogglePause(); RecordAccumulator = RECORD_INTERVAL + 0.1 
    repeat RunService.Heartbeat:Wait() until #Frames > InitialFrames or IsRewinding
    if not IsPaused then TogglePause() end
end

local function RewindFrame()
    local FramePacked = Frames[#Frames - 1]
    if not FramePacked and #Savestates > 0 then FramePacked = Savestates[#Savestates][#Savestates[#Savestates] - 1] end
    if FramePacked then
        local Frame = UnpackFrame(FramePacked)
        if not IsPaused then TogglePause() end
        local Root = LocalPlayer.Character.HumanoidRootPart
        Root.CFrame = Frame.CFrame + Vector3.new(MapX, MapY - 1000, MapZ)
        Root.Velocity = Frame.Velocity; SavedVelocity = Frame.Velocity
        workspace.CurrentCamera.CFrame = Frame.CameraCFrame
        PauseStart = tick(); RunStart = tick() - Frame.Time; TimeOffset = 0
        Frames[#Frames] = nil
    end
end

-- // NEW: DEBUG VIEW //
local function ToggleDebugView()
    DebugActive = not DebugActive
    if DebugActive then
        if ClonedMap then
            for _, v in pairs(ClonedMap:GetDescendants()) do
                if v:IsA("BasePart") then
                    OriginalVisuals[v] = {Color = v.Color, Transparency = v.Transparency}
                    if v.Name == "Hitbox" or v.Name:find("_Water") then
                        v.Color = Color3.fromHSV(math.random(), 1, 1)
                        v.Transparency = 0.2
                    else
                        v.Color = Color3.new(0.4, 0.4, 0.4)
                        if v.Transparency == 1 then v.Transparency = 0.8 end
                    end
                end
            end
        end
        UI.Buttons.DebugView.Text = "Toggle Debug Hitboxes: ON"
        UI.Buttons.DebugView.BackgroundColor3 = Color3.fromRGB(0, 150, 100)
    else
        for part, props in pairs(OriginalVisuals) do
            if part and part.Parent then part.Color = props.Color; part.Transparency = props.Transparency end
        end
        OriginalVisuals = setmetatable({}, { __mode = "k" })
        UI.Buttons.DebugView.Text = "Toggle Debug Hitboxes: OFF"
        UI.Buttons.DebugView.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    end
end

-- // DATA EXPORT & PLAYBACK //
local function GetCompiledData()
    local Data = {}
    local function AddList(list)
        for j = 1, #list do
            if type(list[j]) == "string" then
                local F = UnpackFrame(list[j])
                local rx, ry, rz = F.CFrame:ToEulerAnglesXYZ()
                local cx, cy, cz = F.CameraCFrame.X - MapX, F.CameraCFrame.Y - (MapY - 1000), F.CameraCFrame.Z - MapZ
                local crx, cry, crz = F.CameraCFrame:ToEulerAnglesXYZ()
                table.insert(Data, {
                    time = F.Time, AAnimation = F.Animation or {"walk", 0.1}, AAnimationChanged = F.Animation[2],
                    VVelocity = {F.Velocity.X, F.Velocity.Y, F.Velocity.Z},
                    CCFrame = {F.CFrame.X, F.CFrame.Y, F.CFrame.Z, rx, ry, rz},
                    CCameraCFrame = {cx, cy, cz, crx, cry, crz}
                })
            end
        end
    end
    for i = 1, #Savestates do AddList(Savestates[i]) end
    AddList(Frames)
    return Data
end

-- // NEW: TAS PLAYBACK (WITH SMOOTHING, CAMERA, & TRACING) //
local function PlaybackTAS(ExternalData)
    if IsViewingTAS then return end
    IsViewingTAS = true
    
    local Data = ExternalData or GetCompiledData()
    if #Data == 0 then IsViewingTAS = false; return end

    -- Extreme Smoothing Logic
    if getgenv().ExtremeSmoothing then
        local smoothed = {}
        local interval = 1 / getgenv().TargetSmoothingFPS
        local nextT = 0
        for i, frame in ipairs(Data) do
            if frame.time >= nextT or i == 1 or i == #Data then
                table.insert(smoothed, frame); nextT = frame.time + interval
            end
        end
        Data = smoothed
    end

    local Root = LocalPlayer.Character.HumanoidRootPart
    local Cam = workspace.CurrentCamera
    local Offset = ClonedMap and (ClonedMap.PrimaryPart.Position - Vector3.new(0, 1000, 0)) or Vector3.zero
    
    local PlayStart = tick()
    local OldFrame = 1
    local NewC, AngC, NewV = CFrame.new, CFrame.fromEulerAnglesXYZ, Vector3.new

    -- Path Tracing
    if getgenv().ShowTASPathDuringPlayback then
        for i, line in ipairs(PathLines) do line:Destroy() end; PathLines = {}
        for i = 1, #Data - 1, (getgenv().ExtremeSmoothing and 1 or 5) do
            local p1 = NewV(Data[i].CCFrame[1], Data[i].CCFrame[2], Data[i].CCFrame[3]) + Offset
            local p2 = NewV(Data[i+1].CCFrame[1], Data[i+1].CCFrame[2], Data[i+1].CCFrame[3]) + Offset
            local dist = (p2 - p1).Magnitude
            if dist > 0.05 then
                local line = Instance.new("CylinderHandleAdornment")
                line.Radius = 0.1; line.Color3 = Color3.fromRGB(0, 200, 255); line.Transparency = 0.2
                line.Height = dist; line.CFrame = CFrame.lookAt(p1 + (p2 - p1)/2, p2)
                line.Adornee = workspace.Terrain; line.Parent = TrajectoryFolder
                table.insert(PathLines, line)
            end
        end
    end

    local Con
    Con = RunService.Heartbeat:Connect(function()
        if not IsViewingTAS then Con:Disconnect(); Root.Anchored = true; return end
        Root.Anchored = true
        local Elapsed = tick() - PlayStart
        
        while OldFrame < #Data and Data[OldFrame + 1].time <= Elapsed do OldFrame = OldFrame + 1 end
        if OldFrame >= #Data then IsViewingTAS = false; Con:Disconnect(); return end
        
        local FA = Data[OldFrame]
        local FB = Data[OldFrame + 1] or FA
        local Dur = FB.time - FA.time
        local Alpha = (Dur > 0) and math.clamp((Elapsed - FA.time) / Dur, 0, 1) or 0
        
        local cfA = NewC(unpack(FA.CCFrame, 1, 3)) * AngC(unpack(FA.CCFrame, 4, 6))
        local cfB = NewC(unpack(FB.CCFrame, 1, 3)) * AngC(unpack(FB.CCFrame, 4, 6))
        Root.CFrame = cfA:Lerp(cfB, Alpha) + Offset
        
        -- Toggleable Camera Playback
        if getgenv().PlaybackCamera then
            local camA = NewC(unpack(FA.CCameraCFrame, 1, 3)) * AngC(unpack(FA.CCameraCFrame, 4, 6))
            local camB = NewC(unpack(FB.CCameraCFrame, 1, 3)) * AngC(unpack(FB.CCameraCFrame, 4, 6))
            Cam.CFrame = camA:Lerp(camB, Alpha) + Offset
        end
    end)
end

-- // NEW: FILE MANAGEMENT (SAVE & LOAD) //
local function RefreshFileList()
    for _, child in ipairs(UI.FileList:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
    if not listfiles or not isfolder then return end
    pcall(function()
        if not isfolder("Flood-GUI/TAS FILES") then makefolder("Flood-GUI/TAS FILES") end
        for _, file in ipairs(listfiles("Flood-GUI/TAS FILES")) do
            if file:match("%.json$") then
                local filename = file:match("([^/\\]+)$")
                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, -10, 0, 30); btn.BackgroundColor3 = Color3.fromRGB(40,40,45)
                btn.Text = filename; btn.TextColor3 = Color3.new(1,1,1); btn.Font = Enum.Font.Gotham
                btn.Parent = UI.FileList
                btn.Activated:Connect(function()
                    SelectedFileToLoad = filename
                    UI.SelectedLabel.Text = "Selected: " .. filename
                end)
            end
        end
    end)
end

local function SaveRun()
    local name = UI.SaveBox.Text ~= "" and UI.SaveBox.Text or (ClonedMap and ClonedMap.Settings:GetAttribute("MapName") or "MyRun")
    local Export = GetCompiledData()
    if not isfolder("Flood-GUI/TAS FILES") then makefolder("Flood-GUI/TAS FILES") end
    writefile("Flood-GUI/TAS FILES/" .. name .. ".json", HttpService:JSONEncode(Export))
    RefreshFileList()
end

local function LoadRun()
    if SelectedFileToLoad == "" then return end
    pcall(function()
        local content = readfile("Flood-GUI/TAS FILES/" .. SelectedFileToLoad)
        local LoadedData = HttpService:JSONDecode(content)
        PlaybackTAS(LoadedData)
    end)
end

-- // PREDICTIVE TRAJECTORY VISUALIZER //
local LastUpdate = 0
AddConnection(RunService.RenderStepped:Connect(function()
    if not getgenv().TAS_Active or not getgenv().ShowVelocityPredictor or IsViewingTAS then
        for _, l in ipairs(TrajectoryLines) do l.Visible = false end
        return 
    end
    
    local now = os.clock()
    if now - LastUpdate < 1/15 then return end
    LastUpdate = now

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root and root.Velocity.Magnitude > 0.5 then
        local p = root.Position
        local v = root.Velocity
        local dt = 1/60
        -- Adjust physics if in FE2 Water
        local grav = getgenv().IsSwimming and Vector3.new(0, -20, 0) or Vector3.new(0, -workspace.Gravity, 0)
        
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {char}
        
        local points, vels = {p}, {v}
        for frame = 1, 60 do
            if getgenv().IsSwimming then v = v * 0.95 end -- Water drag simulation
            v = v + (grav * dt)
            local stepVec = v * dt
            
            local hit = workspace:Raycast(p, stepVec, rayParams)
            if hit then p = hit.Position; table.insert(points, p); table.insert(vels, v); break end
            p = p + stepVec
            table.insert(points, p); table.insert(vels, v)
        end
        
        for i = 1, #points - 1 do
            local line = TrajectoryLines[i]
            if not line then
                line = Instance.new("CylinderHandleAdornment")
                line.Radius = 0.1; line.Adornee = workspace.Terrain; line.Parent = TrajectoryFolder
                TrajectoryLines[i] = line
            end
            local p1, p2 = points[i], points[i+1]
            line.Height = (p2 - p1).Magnitude
            line.CFrame = CFrame.lookAt(p1 + (p2 - p1)/2, p2)
            local speed = vels[i].Magnitude
            line.Color3 = speed > 30 and Color3.new(1,0,0) or Color3.new(0,1,0)
            line.Visible = true
        end
        for i = #points, #TrajectoryLines do TrajectoryLines[i].Visible = false end
    else
        for _, l in ipairs(TrajectoryLines) do l.Visible = false end
    end
end))

-- // UI BUTTON BINDINGS //
UI.Buttons.Pause.Activated:Connect(TogglePause)
UI.Buttons.StepFwd.Activated:Connect(StepForward)
UI.Buttons.StepBack.Activated:Connect(RewindFrame)
UI.Buttons.AddState.Activated:Connect(AddSavestate)
UI.Buttons.LoadState.Activated:Connect(LoadLastSavestate)
UI.Buttons.RemState.Activated:Connect(RemoveSavestate)
UI.Buttons.Resync.Activated:Connect(function() PreviewOffset = 0 end)
UI.Buttons.Stop.Activated:Connect(function() getgenv().TAS_Active = false; UI.ScreenGui:Destroy() end)
UI.Buttons.Save.Activated:Connect(SaveRun)
UI.Buttons.Refresh.Activated:Connect(RefreshFileList)
UI.Buttons.Load.Activated:Connect(LoadRun)
UI.Buttons.PlaySelected.Activated:Connect(function() if not IsViewingTAS then PlaybackTAS() end end)
UI.Buttons.DebugView.Activated:Connect(ToggleDebugView)

UI.Buttons.SmoothMode.Activated:Connect(function()
    getgenv().ExtremeSmoothing = not getgenv().ExtremeSmoothing
    UI.Buttons.SmoothMode.Text = "Extreme Smoothing: " .. (getgenv().ExtremeSmoothing and "ON" or "OFF")
    UI.Buttons.SmoothMode.BackgroundColor3 = getgenv().ExtremeSmoothing and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(45, 45, 55)
end)
UI.Buttons.PathTracing.Activated:Connect(function()
    getgenv().ShowTASPathDuringPlayback = not getgenv().ShowTASPathDuringPlayback
    UI.Buttons.PathTracing.Text = "TAS Path Tracing: " .. (getgenv().ShowTASPathDuringPlayback and "ON" or "OFF")
    UI.Buttons.PathTracing.BackgroundColor3 = getgenv().ShowTASPathDuringPlayback and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(45, 45, 55)
end)
UI.Buttons.Trajectory.Activated:Connect(function()
    getgenv().ShowVelocityPredictor = not getgenv().ShowVelocityPredictor
    UI.Buttons.Trajectory.Text = "Predictive Velocity: " .. (getgenv().ShowVelocityPredictor and "ON" or "OFF")
    UI.Buttons.Trajectory.BackgroundColor3 = getgenv().ShowVelocityPredictor and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(45, 45, 55)
end)
UI.Buttons.CamMode.Activated:Connect(function()
    getgenv().PlaybackCamera = not getgenv().PlaybackCamera
    UI.Buttons.CamMode.Text = "Playback Camera Follow: " .. (getgenv().PlaybackCamera and "ON" or "OFF")
    UI.Buttons.CamMode.BackgroundColor3 = getgenv().PlaybackCamera and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(45, 45, 55)
end)

-- Initialize File List
RefreshFileList()

-- // RECORDING LOOP //
AddConnection(RunService.Heartbeat:Connect(function(dt)
    if not getgenv().TAS_Active or not RunStart then return end
    if IsViewingTAS or IsRewinding or IsAdvancingFrame then return end

    if not IsPaused then
        RecordAccumulator = RecordAccumulator + dt
        if RecordAccumulator >= RECORD_INTERVAL then
            RecordAccumulator = RecordAccumulator - RECORD_INTERVAL
            table.insert(Frames, CaptureFrameData())
        end
    end
end))

-- Wait for map load and prepare character...
game.Workspace.Multiplayer:WaitForChild("Map", 9e99)
ClonedMap = game.Workspace.Multiplayer:FindFirstChild("Map")
RunStart = tick()
