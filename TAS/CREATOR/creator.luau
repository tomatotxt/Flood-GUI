--[[
    FE2 TAS Creator (Ultimate FE2 Edition)
    - INCLUDES: Original Map Recorder, Autofarm, Button Sync, Zipline Fixes.
    - NEW: Mobile UI, Debug View, Smoothing, Path Tracing, Trajectory, File Loading.
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

local Keybinds = {
    AddSavestate = "One", RemoveSavestate = "Two", BackSavestate = "Three",
    GoFrameBack = "Four", GoFrameForward = "Five", SaveRun = "Six",
    UserPause = "CapsLock", CollisionToggler = "C", ResetToNormal = "Delete",
    ViewTAS = "Zero", Resync = "F8", EnvPause = "Equals", ToggleTimeReset = "Seven",
    DebugToggler = "V", LoadRun = "Minus"
}

-- // SERVICES & ALERT SYSTEM //
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local NewAlert = nil
local function SetupAlerts()
    local GameScript = LocalPlayer.PlayerScripts:WaitForChild("CL_MAIN_GameScript", 5)
    if GameScript then
        local success, env = pcall(getsenv, GameScript)
        if success and env.newAlert then NewAlert = env.newAlert end
    end
end
SetupAlerts()

local function SendAlert(msg, color)
    if NewAlert then pcall(function() NewAlert(msg, color, 1.5, nil) end) end
end
SendAlert("Ultimate TAS Creator Initialized", Color3.fromRGB(183, 0, 255))

-- // BYPASSES //
local OldIndex
OldIndex = hookmetamethod(game, "__index", function(self, key)
    if not checkcaller() then
        if key == "Archivable" then return false end
        if getgenv().IsSwimming and key == "Position" and self.Name == "HumanoidRootPart" then
            return Vector3.new(-23, -153, 0)
        end
    end
    return OldIndex(self, key)
end)
pcall(function() ReplicatedStorage.Remote.ReqPasskey:InvokeServer() end)

-- // VARIABLES //
local CurrentAnim, Savestates, Frames = {}, {}, {}
local TimeOffset, PreviewOffset = 0, 0
local IsPaused, EnvPaused = true, false
local PauseStart, OriginalPlayAnim, AnimEnv, RunStart, SavedVelocity
local Connections = {} 

local IsPreviewingForward, IsPreviewingBackward = false, false
local IsAdvancingFrame, IsRewinding, IsViewingTAS = false, false, false
local AutoSaved, AutoResetEnv = false, false 

local MapEvents, PlaybackIndex, MapRecorderCache, ClonedMap, RopeTable = {}, 1, {}, nil, nil
local MapOffset, MapPos, MapX, MapY, MapZ
local MapUUIDs = {} 
local RecordedButtonSequence, OrderedButtonRegistry, ButtonRegistry, TotalButtons = {}, {}, {}, {}

local SavedLighting = {Props = {}, Children = {}}; local LightingCaptured = false
local RecordAccumulator = 0; local TARGET_FPS = 60; local RECORD_INTERVAL = 1 / TARGET_FPS
getgenv().IsSwimming = false; local WaterParts = {}

-- // NEW VISUALIZER VARIABLES //
local OriginalVisuals = setmetatable({}, { __mode = "k" })
local DebugActive = false
local TrajectoryFolder = Instance.new("Folder", workspace)
TrajectoryFolder.Name = "TAS_Trajectory"
local TrajectoryLines, PathLines = {}, {}
local SelectedFileToLoad = ""

-- // DATA PACKING //
local PACK_FORMAT = "d" .. string.rep("f", 28) .. "s"
local function PackFrame(Time, Vel, CF, CamCF, Anim)
    local anm = Anim[1] or "idle"; local asp = Anim[2] or 0
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
local function isRandomString(str)
    if #str == 0 then return false end
    for i = 1, #str do local ltr = str:sub(i, i); if ltr:lower() == ltr then return false end end
    return true
end
local function GetUUID(part)
    if not part then return nil end
    local id = part:GetAttribute("TAS_UUID")
    if not id then id = HttpService:GenerateGUID(false); part:SetAttribute("TAS_UUID", id) end
    return id
end
local function DeepCopy(orig)
    local copy = {}
    if type(orig) == 'table' then for k, v in pairs(orig) do copy[k] = v end else copy = orig end
    return copy
end

local function ToggleCollision()
    local mouse = LocalPlayer:GetMouse()
    if mouse and mouse.Target then
        mouse.Target.CanCollide = not mouse.Target.CanCollide
        SendAlert("Collision " .. (mouse.Target.CanCollide and "Enabled" or "Disabled"), Color3.fromRGB(255, 255, 0))
    end
end

local function IsPointInPart(part, point)
    local rel = part.CFrame:PointToObjectSpace(point)
    local halfSize = part.Size / 2
    return math.abs(rel.X) <= halfSize.X and math.abs(rel.Y) <= halfSize.Y and math.abs(rel.Z) <= halfSize.Z
end

local function GetPlayerCFrame()
    local Root = LocalPlayer.Character.HumanoidRootPart
    local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = Root.CFrame:GetComponents()
    return CFrame.new(x - MapX, y - MapY + 1000, z - MapZ, R00, R01, R02, R10, R11, R12, R20, R21, R22)
end

local function CaptureFrameData()
    return PackFrame(tick() - RunStart - TimeOffset, LocalPlayer.Character.HumanoidRootPart.Velocity, GetPlayerCFrame(), workspace.CurrentCamera.CFrame, CurrentAnim)
end

-- // UI INTEGRATION //
local TAS_UI = loadstring(game:HttpGet(UI_API_URL))()
local UI = TAS_UI.Create()

local function UpdateTimeDisplay(DisplayTime)
    if not UI.TimeText then return end
    local m = math.floor(DisplayTime / 60)
    local s = math.floor(DisplayTime % 60)
    local ms = math.floor(DisplayTime * 1000 % 1000)
    UI.TimeText.Text = string.format("%d:%02d.%03d", m, s, ms)
end

-- // NEW: FILE MANAGEMENT & EXPORT LOGIC //
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

local function SaveRun()
    local name = UI.SaveBox.Text ~= "" and UI.SaveBox.Text or (ClonedMap and ClonedMap.Settings:GetAttribute("MapName") or "MyRun")
    local Export = GetCompiledData()
    if not isfolder("Flood-GUI/TAS FILES") then makefolder("Flood-GUI/TAS FILES") end
    writefile("Flood-GUI/TAS FILES/" .. name .. ".json", HttpService:JSONEncode(Export))
    SendAlert("Run Saved!", Color3.fromRGB(0, 255, 0))
    RefreshFileList()
end

-- // LIGHTING MANAGER //
local function CaptureLighting()
    SavedLighting.Props = {Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, FogColor = Lighting.FogColor, FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart, GlobalShadows = Lighting.GlobalShadows, ExposureCompensation = Lighting.ExposureCompensation, TimeOfDay = Lighting.TimeOfDay}
    SavedLighting.Children = {}
    for _, child in ipairs(Lighting:GetChildren()) do table.insert(SavedLighting.Children, child:Clone()) end
    LightingCaptured = true
end

local function EnforceLighting()
    if not LightingCaptured then return end
    for prop, val in pairs(SavedLighting.Props) do if Lighting[prop] ~= val then Lighting[prop] = val end end
    local CurrentChildren = Lighting:GetChildren()
    if #CurrentChildren ~= #SavedLighting.Children then
        Lighting:ClearAllChildren()
        for _, c in ipairs(SavedLighting.Children) do c:Clone().Parent = Lighting end
    end
end

-- // MAP MONITOR & ENGINE //
AddConnection(workspace.Multiplayer.ChildAdded:Connect(function(child)
    if not getgenv().TAS_Active then return end
    if ClonedMap and (child.Name == "Map" or child.Name == "NewMap") then task.wait(); child:Destroy() end
end))

local function UpdateMapState(TargetTime)
    if EnvPaused then return end
    while PlaybackIndex <= #MapEvents and MapEvents[PlaybackIndex].Time <= TargetTime do
        local Event = MapEvents[PlaybackIndex]
        if Event.Instance then
            if Event.Prop == "Destroyed" then
                Event.Instance.Transparency = 1
                if Event.Instance:IsA("BasePart") then Event.Instance.CanCollide = false; Event.Instance.Anchored = true end
                if Event.ChildrenUUIDs then
                    for _, childUUID in ipairs(Event.ChildrenUUIDs) do
                        local child = MapUUIDs[childUUID]
                        if child then child.Transparency = 1 end
                    end
                end
            elseif Event.Prop == "Anchored" then
                if Event.NewVal == false and Event.Instance:IsA("BasePart") and Event.Instance.CanCollide == false then
                    Event.Instance.Anchored = true; Event.Instance.Transparency = 1
                else
                    Event.Instance.Anchored = Event.NewVal
                end
            else
                Event.Instance[Event.Prop] = Event.NewVal
            end
        end
        PlaybackIndex = PlaybackIndex + 1
    end
    
    while PlaybackIndex > 1 and MapEvents[PlaybackIndex - 1].Time > TargetTime do
        PlaybackIndex = PlaybackIndex - 1
        local Event = MapEvents[PlaybackIndex]
        if Event.Instance then
            if Event.Prop == "Destroyed" then
                if type(Event.OldVal) == "table" then
                    local s = Event.OldVal
                    Event.Instance.Transparency = s.Transparency
                    if Event.Instance:IsA("BasePart") then
                        Event.Instance.CanCollide = s.CanCollide; Event.Instance.CFrame = s.CFrame
                        Event.Instance.Anchored = s.Anchored; Event.Instance.Color = s.Color; Event.Instance.Size = s.Size
                    end
                    if Event.Children and Event.ChildrenUUIDs then
                        for _, childUUID in ipairs(Event.ChildrenUUIDs) do
                            local child = MapUUIDs[childUUID]; local childState = Event.Children[childUUID]
                            if child and childState then child.Transparency = childState.Transparency; child.Color3 = childState.Color3 end
                        end
                    end
                else
                    Event.Instance.Transparency = 0
                    if Event.Instance:IsA("BasePart") then Event.Instance.CanCollide = true end
                end
            elseif Event.Prop == "Anchored" then
                Event.Instance.Anchored = Event.OldVal
                if Event.OldVal == true and Event.StoredCFrame then
                    Event.Instance.CFrame = Event.StoredCFrame; Event.Instance.CanCollide = Event.StoredCanCollide
                    Event.Instance.Transparency = 0; Event.Instance.Velocity = Vector3.new(); Event.Instance.RotVelocity = Vector3.new()
                end
            else
                Event.Instance[Event.Prop] = Event.OldVal
            end
        end
    end
end

-- // BUTTON SYNC //
local function SyncButtonState(VisualTime, RealTime)
    for part, data in pairs(ButtonRegistry) do
        if data.IsPressed and data.TruePressTime > RealTime then data.IsPressed = false; data.PressTime = nil end
    end
    local NextIndex = 1
    for i = 1, #RecordedButtonSequence do
        local btnData = OrderedButtonRegistry[i]
        if btnData and not btnData.IsPressed then NextIndex = i; break end
        if i == #RecordedButtonSequence then NextIndex = i + 1 end
    end
    for part, data in pairs(ButtonRegistry) do
        local isVisuallyPressed = (data.TruePressTime and data.TruePressTime <= VisualTime)
        if isVisuallyPressed then data.SelectionBox.Color3 = Color3.fromRGB(0, 255, 0)
        elseif data.Order ~= 999 then
            if data.Order == NextIndex then data.SelectionBox.Color3 = Color3.fromRGB(255, 255, 0)
            elseif data.Order > NextIndex then data.SelectionBox.Color3 = Color3.fromRGB(255, 0, 0)
            else data.SelectionBox.Color3 = Color3.fromRGB(0, 255, 0) end
        else
            data.SelectionBox.Color3 = Color3.fromRGB(255, 140, 0)
        end
    end
end

local function HookAnimations()
    repeat
        local script = LocalPlayer.Character:WaitForChild("Animate")
        AnimEnv = getsenv(script)
        task.wait()
    until AnimEnv.playAnimation ~= nil
    OriginalPlayAnim = AnimEnv.playAnimation
    AnimEnv.playAnimation = function(anim, speed)
        if not IsPaused then CurrentAnim = {anim, speed}; OriginalPlayAnim(CurrentAnim[1], CurrentAnim[2], LocalPlayer.Character.Humanoid) end
    end
end

-- // CORE LOGIC //
local function TogglePause()
    IsPaused = not IsPaused
    local Root = LocalPlayer.Character.HumanoidRootPart
    if IsPaused then
        SavedVelocity = Root.Velocity; Root.Anchored = true; PauseStart = tick()
        UI.StatusText.Text = "PAUSED"; UI.StatusText.TextColor3 = THEME.Alert
        SendAlert("Paused", Color3.fromRGB(255, 255, 0))
    else
        Root.Anchored = false; Root.Velocity = SavedVelocity; TimeOffset = TimeOffset + tick() - PauseStart
        UI.StatusText.Text = "PLAYING"; UI.StatusText.TextColor3 = Color3.fromRGB(0, 255, 100)
        RecordAccumulator = 0
        SendAlert("Unpaused", Color3.fromRGB(0, 255, 0))
    end
end

local function LoadLastSavestate()
    local LastState = Savestates[#Savestates]
    if LastState and LastState[#LastState] then
        local Frame = UnpackFrame(LastState[#LastState])
        Frames = {}; IsPaused = true; PreviewOffset = 0
        local Root = LocalPlayer.Character.HumanoidRootPart
        Root.Anchored = true; Root.CFrame = Frame.CFrame + Vector3.new(MapX, MapY - 1000, MapZ)
        Root.Velocity = Frame.Velocity; SavedVelocity = Frame.Velocity
        workspace.CurrentCamera.CFrame = Frame.CameraCFrame
        PauseStart = tick(); RunStart = tick() - Frame.Time; TimeOffset = 0
        SyncButtonState(Frame.Time, Frame.Time); UpdateMapState(Frame.Time)
        OriginalPlayAnim(Frame.Animation[1], Frame.Animation[2], LocalPlayer.Character.Humanoid)
        UpdateTimeDisplay(Frame.Time)
    end
end

local function AddSavestate() table.insert(Savestates, Frames); Frames = {}; SendAlert("Savestate Added", Color3.fromRGB(0,255,0)) end
local function RemoveSavestate() if #Savestates > 1 then table.remove(Savestates); LoadLastSavestate(); SendAlert("Savestate Removed", Color3.fromRGB(255,0,0)) end end

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
        local VisualTime = Frame.Time + PreviewOffset
        SyncButtonState(VisualTime, Frame.Time); UpdateMapState(VisualTime)
        if Frame.Animation[1] then OriginalPlayAnim(Frame.Animation[1], Frame.Animation[2], LocalPlayer.Character.Humanoid) end
        UpdateTimeDisplay(VisualTime); Frames[#Frames] = nil
    end
end

-- // ADVANCED MAP RECORDER //
local function SetupMap()
    local MP = game.Workspace.Multiplayer
    local LiveMap = MP:WaitForChild("Map", 9e9)
    local Settings = LiveMap:FindFirstChild("Settings")
    local MapName = Settings and Settings:GetAttribute("MapName") or "Unknown Map"
    SendAlert("Map Detected: " .. MapName, Color3.fromRGB(0, 255, 255))
    
    local Spawn = LiveMap:FindFirstChild("Spawn", true)
    if not Spawn then
        local target = nil; local connections = {}
        for _, child in ipairs(LiveMap:GetChildren()) do
            if child.Name == "Part" and child.Size.Y < 5 then
                table.insert(connections, child:GetPropertyChangedSignal("Rotation"):Connect(function() target = child; for _, con in ipairs(connections) do con:Disconnect() end end))
            end
        end
        repeat task.wait() until target; LiveMap.PrimaryPart = target
    else LiveMap.PrimaryPart = Spawn end
    
    CaptureLighting()
    for _, desc in ipairs(LiveMap:GetDescendants()) do if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then GetUUID(desc) end end
    
    LiveMap.Archivable = true
    for _, d in pairs(LiveMap:GetDescendants()) do d.Archivable = true end
    ClonedMap = LiveMap:Clone(); ClonedMap.Parent = nil 
    
    local Char = LocalPlayer.Character
    local Root = Char:WaitForChild("HumanoidRootPart")
    local Hum = Char:WaitForChild("Humanoid")
    
    local Recording = true; local StartTime = os.clock(); local Recorders = {}
    local PropWhitelist = {
        BasePart = {["CFrame"]=true, ["Transparency"]=true, ["CanCollide"]=true, ["Color"]=true, ["Size"]=true, ["Anchored"]=true, ["Material"]=true, ["Reflectance"]=true},
        Decal = {["Transparency"]=true, ["Color3"]=true, ["Texture"]=true},
        Texture = {["Transparency"]=true, ["Color3"]=true, ["Texture"]=true, ["OffsetStudsU"]=true, ["OffsetStudsV"]=true, ["StudsPerTileU"]=true, ["StudsPerTileV"]=true}
    }
    
    local function TrackPart(Part)
        local id = GetUUID(Part)
        if not id then return end
        local MyWhitelist = nil
        if Part:IsA("BasePart") then MyWhitelist = PropWhitelist.BasePart elseif Part:IsA("Decal") then MyWhitelist = PropWhitelist.Decal elseif Part:IsA("Texture") then MyWhitelist = PropWhitelist.Texture end
        if not MyWhitelist then return end
        
        MapRecorderCache[Part] = {}
        for prop, _ in pairs(MyWhitelist) do local s, val = pcall(function() return Part[prop] end); if s then MapRecorderCache[Part][prop] = val end end
        
        table.insert(Recorders, Part.Changed:Connect(function(Prop)
            if not Recording or not MyWhitelist[Prop] then return end
            local NewVal = Part[Prop]; local OldVal = MapRecorderCache[Part][Prop]
            if NewVal ~= OldVal then
                local EventData = {Time = os.clock() - StartTime, UUID = id, Prop = Prop, OldVal = OldVal, NewVal = NewVal}
                if Prop == "Anchored" and Part:IsA("BasePart") then EventData.StoredCFrame = Part.CFrame; EventData.StoredCanCollide = Part.CanCollide end
                table.insert(MapEvents, EventData); MapRecorderCache[Part][Prop] = NewVal
            end
        end))
        
        table.insert(Recorders, Part.Destroying:Connect(function()
            if not Recording then return end
            local State = DeepCopy(MapRecorderCache[Part])
            local ChildrenUUIDs, ChildrenStates = {}, {}
            if Part:IsA("BasePart") then
                for _, child in ipairs(Part:GetChildren()) do
                    if (child:IsA("Decal") or child:IsA("Texture")) and MapRecorderCache[child] then
                        local childID = GetUUID(child)
                        table.insert(ChildrenUUIDs, childID); ChildrenStates[childID] = DeepCopy(MapRecorderCache[child])
                    end
                end
            end
            table.insert(MapEvents, {Time = os.clock() - StartTime, UUID = id, Prop = "Destroyed", OldVal = State, Children = ChildrenStates, ChildrenUUIDs = ChildrenUUIDs, NewVal = true})
        end))
    end

    for _, Object in ipairs(LiveMap:GetDescendants()) do if Object:IsA("BasePart") or Object:IsA("Decal") or Object:IsA("Texture") then TrackPart(Object) end end
    table.insert(Recorders, LiveMap.DescendantAdded:Connect(function(d) if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then TrackPart(d) end end))

    SendAlert("Scanning for Buttons...", Color3.fromRGB(255, 170, 0))
    Hum.Health = 99999
    
    local Buttons = {}
    for i, MapObject in pairs(LiveMap:GetDescendants()) do
        if isRandomString(MapObject.Name) and MapObject:IsA("Model") then
            local Hitbox
            for i, Candidate in pairs(MapObject:GetChildren()) do
                if Candidate:IsA("BasePart") and tostring(Candidate.BrickColor) ~= "Medium stone grey" then Hitbox = Candidate; break end
            end
            if Hitbox and isRandomString(Hitbox.Name) then Hitbox.Name = "Hitbox"; table.insert(Buttons, MapObject) end
        end
    end
    SendAlert("Autofarm: Found " .. #Buttons .. " Buttons", Color3.fromRGB(0, 255, 0))

    for i, v in Char:GetChildren() do if v:IsA("BasePart") then v.CanCollide = false end end
    local GodModeCon = RunService.RenderStepped:Connect(function() if Hum then Hum.Health = 99999 end end)
    
    local LastSafePos = CFrame.new(0, 1000, 0); local LiveExitRegion = nil; local LastTargetButton = nil
    RecordedButtonSequence = {}; local ButtonPressTimings = {} 
    
    while Recording and LiveMap.Parent and Hum.Health > 0 do
        Hum.Jump = true
        if not LiveExitRegion then LiveExitRegion = LiveMap:FindFirstChild("ExitRegion", true) end
        local FailedScan = true; Root.Anchored = true
        
        for i, Button in pairs(Buttons) do
            local ButtonHitbox = Button:FindFirstChild("Hitbox")
            if ButtonHitbox and Button:FindFirstChild("TouchInterest", true) and Button:FindFirstChildWhichIsA("BillboardGui", true) then
                FailedScan = false; Root.Anchored = false
                if Button ~= LastTargetButton then
                    local uuid = GetUUID(ButtonHitbox)
                    if uuid and not table.find(RecordedButtonSequence, uuid) then
                        table.insert(RecordedButtonSequence, uuid)
                        ButtonPressTimings[uuid] = (os.clock() - StartTime) + LocalPlayer:GetNetworkPing()
                    end
                    if LastTargetButton ~= nil then task.wait(0.1) end
                    LastTargetButton = Button
                else
                    local uuid = GetUUID(ButtonHitbox)
                    if uuid and not table.find(RecordedButtonSequence, uuid) then
                        table.insert(RecordedButtonSequence, uuid)
                        ButtonPressTimings[uuid] = (os.clock() - StartTime) + LocalPlayer:GetNetworkPing()
                    end
                end
                Root.CFrame = CFrame.new(ButtonHitbox.Position); Root.Velocity = Vector3.new(0, 0, 0)
                Hum:ChangeState(Enum.HumanoidStateType.Jumping); task.wait(0.255/15)
            end
        end
        if FailedScan then
            if LiveExitRegion then Root.CFrame = LiveExitRegion.CFrame + Vector3.new(0, 100, 0); Root.Velocity = Vector3.new()
            else Root.CFrame = LastSafePos + Vector3.new(0, 10, 0); Root.Velocity = Vector3.new() end
        else LastSafePos = Root.CFrame end
        RunService.Heartbeat:Wait()
    end
    
    Recording = false; GodModeCon:Disconnect()
    for i, v in Char:GetChildren() do if v:IsA("BasePart") then v.CanCollide = true end end
    for _, r in ipairs(Recorders) do r:Disconnect() end
    CaptureLighting(); SendAlert("Processing Map...", Color3.fromRGB(0, 200, 255))
    if LiveMap then LiveMap.Archivable = true; LiveMap:Destroy() end
    
    ClonedMap.Parent = workspace
    MapUUIDs = {}
    for _, desc in ipairs(ClonedMap:GetDescendants()) do
        local id = desc:GetAttribute("TAS_UUID")
        if id then MapUUIDs[id] = desc end
    end
    for _, Event in ipairs(MapEvents) do Event.Instance = MapUUIDs[Event.UUID] end
    for i = #MapEvents, 1, -1 do
        local Event = MapEvents[i]
        if Event.Instance and Event.Prop ~= "Destroyed" then Event.Instance[Event.Prop] = Event.OldVal end
    end
    if not ClonedMap.PrimaryPart then ClonedMap.PrimaryPart = ClonedMap:FindFirstChild(LiveMap.PrimaryPart.Name, true) end
    MapPos = ClonedMap.PrimaryPart.Position; MapX, MapY, MapZ = MapPos.X, MapPos.Y, MapPos.Z
    
    LocalPlayer.Character:BreakJoints()
    LocalPlayer.CharacterAdded:Wait(); Char = LocalPlayer.Character; task.wait(1)
    game:GetService("ReplicatedStorage"):WaitForChild("Remote"):WaitForChild("RemoveWaiting"):FireServer()
    
    local FE2Env = getsenv(Char:WaitForChild("FE2_Character"))
    local startZipline = FE2Env.startZipline
    if RopeTable and #RopeTable >= 1 then
        task.spawn(function() while Char and Char.Humanoid.Health >= 1 do setupvalue(startZipline, 2, RopeTable); task.wait() end end)
    end
    
    Root = Char:WaitForChild("HumanoidRootPart"); Hum = Char:WaitForChild("Humanoid")
    Hum.WalkSpeed = 0; Hum.JumpPower = 0; task.wait(0.5)
    Root.CFrame = CFrame.new(ClonedMap.PrimaryPart.Position) + Vector3.new(0, ClonedMap.PrimaryPart.Size.Y/2, 0) + Vector3.new(0, Root.Size.Y/2, 0) + Vector3.new(0, Char["Left Leg"].Size.Y, 0)
    task.wait(0.5); Root.Anchored = true; Hum.WalkSpeed = 20; Hum.JumpPower = 50
    table.insert(Savestates, {PackFrame(0, Vector3.new(), GetPlayerCFrame(), workspace.CurrentCamera.CFrame, {"idle", 0})})
    
    PauseStart = tick(); RunStart = tick(); HookAnimations()
    AddConnection(LocalPlayer.CharacterAdded:Connect(function(c) local anim = c:WaitForChild("Animate"); if anim.Enabled then HookAnimations() end end))
    
    WaterParts = {}; TotalButtons = {}; ButtonRegistry = {}; OrderedButtonRegistry = {}; local CheckedButtonParts = {}

    local function RegisterButton(btn)
        if not btn or CheckedButtonParts[btn] then return end
        CheckedButtonParts[btn] = true; table.insert(TotalButtons, btn)
        local sel = Instance.new("SelectionBox", btn); sel.Adornee = btn; sel.Color3 = Color3.fromRGB(255, 140, 0); sel.SurfaceTransparency = 0.8
        btn.CanTouch = true
        local uuid = GetUUID(btn)
        local order = table.find(RecordedButtonSequence, uuid) or 999
        local bData = {IsPressed = false, PressTime = nil, SelectionBox = sel, Order = order, RecordedTime = ButtonPressTimings[uuid]}
        ButtonRegistry[btn] = bData; OrderedButtonRegistry[order] = bData
        
        AddConnection(btn.Touched:Connect(function(hit)
            if hit.Parent == LocalPlayer.Character and not bData.IsPressed and RunStart then
                if bData.Order > 1 then
                    local prevBtn = OrderedButtonRegistry[bData.Order - 1]
                    if prevBtn and not prevBtn.IsPressed then SendAlert("WRONG ORDER!", Color3.fromRGB(255, 0, 0)); return end
                end
                local RealTime = tick() - RunStart - TimeOffset
                if AutoResetEnv and bData.RecordedTime then
                    PreviewOffset = bData.RecordedTime - RealTime
                    SendAlert("Synced to " .. string.format("%.2fs", bData.RecordedTime), Color3.fromRGB(0, 255, 255))
                end
                bData.IsPressed = true; bData.TruePressTime = RealTime; sel.Color3 = Color3.fromRGB(0, 255, 0)
                SendAlert("Button Pressed!", Color3.fromRGB(0, 255, 0))
            end
        end))
    end

    for _, obj in ipairs(ClonedMap:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name:find("_Water") then table.insert(WaterParts, obj) end
        if obj.Name == "ButtonIcon" then
            local ButtonPart = obj.Parent and obj.Parent.Parent
            if ButtonPart:IsA("Model") then ButtonPart = ButtonPart:FindFirstChildOfClass("BasePart") end
            RegisterButton(ButtonPart)
        end
        if isRandomString(obj.Name) and obj:IsA("Model") and not obj:FindFirstAncestor("_Rescue") then
            local hp = obj:FindFirstChild("Hitbox") 
            if not hp then for _, c in ipairs(obj:GetChildren()) do if c:IsA("BasePart") and tostring(c.BrickColor) ~= "Medium stone grey" then hp = c; break end end end
            RegisterButton(hp)
        end
    end
    SendAlert("Map Ready & Linked", Color3.fromRGB(0, 255, 0))
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
                        v.Color = Color3.fromHSV(math.random(), 1, 1); v.Transparency = 0.2
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
        for part, props in pairs(OriginalVisuals) do if part and part.Parent then part.Color = props.Color; part.Transparency = props.Transparency end end
        OriginalVisuals = setmetatable({}, { __mode = "k" })
        UI.Buttons.DebugView.Text = "Toggle Debug Hitboxes: OFF"
        UI.Buttons.DebugView.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    end
end

-- // TAS PLAYBACK ENGINE //
local IsTASSliding, LastTASAnim = false, nil
local function ToggleTASSlide(val)
    local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local Hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid")
    if not Root or not Hum then return end
    if val then Root.Size = Vector3.new(2, 1, 1); Hum.HipHeight = -1.5 else Root.Size = Vector3.new(2, 2, 1); Hum.HipHeight = 0 end
end

local function ActivateTASAnimation(AnimData)
    if not AnimData or not LocalPlayer.Character then return end
    local n = AnimData[1]; local animTime = AnimData[2] or 0.1
    if LocalPlayer.Character.Humanoid:GetState() == Enum.HumanoidStateType.Physics then n = "swing" end
    if n == "idle" and LocalPlayer.Character.HumanoidRootPart.Velocity.Magnitude > 1 then
        if LocalPlayer.Character.Humanoid.FloorMaterial ~= Enum.Material.Air then n = "walk"; animTime = 0.1 else n = "fall"; animTime = 0.3 end
    end
    if n == "slide" then if not IsTASSliding then ToggleTASSlide(true); IsTASSliding = true end else if IsTASSliding then ToggleTASSlide(false); IsTASSliding = false end end
    if n and n ~= LastTASAnim then
        OriginalPlayAnim(n, animTime, LocalPlayer.Character.Humanoid)
        if n == "walk" then AnimEnv.setAnimationSpeed(0.76) end
        LastTASAnim = n
    end
end

local function PlaybackTAS(ExternalData)
    if IsViewingTAS then return end
    local Data = ExternalData or GetCompiledData()
    if #Data == 0 then return end

    if getgenv().ExtremeSmoothing then
        local smoothed = {}; local interval = 1 / getgenv().TargetSmoothingFPS; local nextT = 0
        for i, frame in ipairs(Data) do
            if frame.time >= nextT or i == 1 or i == #Data then table.insert(smoothed, frame); nextT = frame.time + interval end
        end
        Data = smoothed
    end

    IsViewingTAS = true
    local Root = LocalPlayer.Character.HumanoidRootPart; local Cam = workspace.CurrentCamera
    local Offset = ClonedMap.PrimaryPart.Position - Vector3.new(0, 1000, 0)
    local PlayStart = tick(); local OldFrame = 1
    local NewC, AngC, NewV = CFrame.new, CFrame.fromEulerAnglesXYZ, Vector3.new

    if getgenv().ShowTASPathDuringPlayback then
        for i, line in ipairs(PathLines) do line:Destroy() end; PathLines = {}
        for i = 1, #Data - 1, (getgenv().ExtremeSmoothing and 1 or 5) do
            local p1 = NewV(Data[i].CCFrame[1], Data[i].CCFrame[2], Data[i].CCFrame[3]) + Offset
            local p2 = NewV(Data[i+1].CCFrame[1], Data[i+1].CCFrame[2], Data[i+1].CCFrame[3]) + Offset
            local dist = (p2 - p1).Magnitude
            if dist > 0.05 then
                local line = Instance.new("CylinderHandleAdornment"); line.Radius = 0.1; line.Color3 = Color3.fromRGB(0, 200, 255); line.Transparency = 0.2
                line.Height = dist; line.CFrame = CFrame.lookAt(p1 + (p2 - p1)/2, p2); line.Adornee = workspace.Terrain; line.Parent = TrajectoryFolder
                table.insert(PathLines, line)
            end
        end
    end

    local Con
    Con = RunService.Heartbeat:Connect(function()
        if not IsViewingTAS then Con:Disconnect(); Root.Anchored = true; ToggleTASSlide(false); return end
        Root.Anchored = true
        local Elapsed = tick() - PlayStart
        UpdateMapState(Elapsed); SyncButtonState(Elapsed, Elapsed)
        
        while OldFrame < #Data and Data[OldFrame + 1].time <= Elapsed do OldFrame = OldFrame + 1 end
        if OldFrame >= #Data then IsViewingTAS = false; Con:Disconnect(); Root.Anchored = true; ToggleTASSlide(false); return end
        
        local FA = Data[OldFrame]; local FB = Data[OldFrame + 1] or FA
        local Dur = FB.time - FA.time; local Alpha = (Dur > 0) and math.clamp((Elapsed - FA.time) / Dur, 0, 1) or 0
        
        local cfA = NewC(unpack(FA.CCFrame, 1, 3)) * AngC(unpack(FA.CCFrame, 4, 6))
        local cfB = NewC(unpack(FB.CCFrame, 1, 3)) * AngC(unpack(FB.CCFrame, 4, 6))
        Root.CFrame = cfA:Lerp(cfB, Alpha) + Offset
        Root.Velocity = NewV(unpack(FA.VVelocity)):Lerp(NewV(unpack(FB.VVelocity)), Alpha)
        
        if getgenv().PlaybackCamera then
            local camA = NewC(unpack(FA.CCameraCFrame, 1, 3)) * AngC(unpack(FA.CCameraCFrame, 4, 6))
            local camB = NewC(unpack(FB.CCameraCFrame, 1, 3)) * AngC(unpack(FB.CCameraCFrame, 4, 6))
            Cam.CFrame = camA:Lerp(camB, Alpha) + Offset
        end
        ActivateTASAnimation(FA.AAnimation)
    end)
end

local function LoadRun()
    if SelectedFileToLoad == "" then return end
    pcall(function() PlaybackTAS(HttpService:JSONDecode(readfile("Flood-GUI/TAS FILES/" .. SelectedFileToLoad))) end)
end

-- // PREDICTIVE TRAJECTORY VISUALIZER //
local LastUpdate = 0
AddConnection(RunService.RenderStepped:Connect(function()
    if not getgenv().TAS_Active or not getgenv().ShowVelocityPredictor or IsViewingTAS then for _, l in ipairs(TrajectoryLines) do l.Visible = false end return end
    local now = os.clock()
    if now - LastUpdate < 1/15 then return end; LastUpdate = now

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root and root.Velocity.Magnitude > 0.5 then
        local p, v = root.Position, root.Velocity
        local dt = 1/60
        local grav = getgenv().IsSwimming and Vector3.new(0, -20, 0) or Vector3.new(0, -workspace.Gravity, 0)
        local rayParams = RaycastParams.new(); rayParams.FilterDescendantsInstances = {char}
        
        local points, vels = {p}, {v}
        for frame = 1, 60 do
            if getgenv().IsSwimming then v = v * 0.95 end
            v = v + (grav * dt); local stepVec = v * dt
            local hit = workspace:Raycast(p, stepVec, rayParams)
            if hit then p = hit.Position; table.insert(points, p); table.insert(vels, v); break end
            p = p + stepVec; table.insert(points, p); table.insert(vels, v)
        end
        
        for i = 1, #points - 1 do
            local line = TrajectoryLines[i]
            if not line then line = Instance.new("CylinderHandleAdornment"); line.Radius = 0.1; line.Adornee = workspace.Terrain; line.Parent = TrajectoryFolder; TrajectoryLines[i] = line end
            local p1, p2 = points[i], points[i+1]
            line.Height = (p2 - p1).Magnitude; line.CFrame = CFrame.lookAt(p1 + (p2 - p1)/2, p2)
            line.Color3 = vels[i].Magnitude > 30 and Color3.new(1,0,0) or Color3.new(0,1,0); line.Visible = true
        end
        for i = #points, #TrajectoryLines do TrajectoryLines[i].Visible = false end
    else
        for _, l in ipairs(TrajectoryLines) do l.Visible = false end
    end
end))

-- // HEARTBEAT LOOP //
AddConnection(RunService.Heartbeat:Connect(function(dt)
    if not getgenv().TAS_Active or not RunStart then return end
    EnforceLighting()
    if IsViewingTAS or IsRewinding or IsAdvancingFrame then return end

    if IsPreviewingForward then PreviewOffset = PreviewOffset + (dt * 5) end
    if IsPreviewingBackward then PreviewOffset = PreviewOffset - (dt * 5) end

    local RealTime = (IsPaused and (PauseStart or tick()) or tick()) - RunStart - TimeOffset
    local VisualTime = RealTime + PreviewOffset; if VisualTime < 0 then VisualTime = 0 end
    
    UpdateMapState(VisualTime); SyncButtonState(VisualTime, RealTime); UpdateTimeDisplay(VisualTime)

    if not IsPaused then
        RecordAccumulator = RecordAccumulator + dt
        if RecordAccumulator >= RECORD_INTERVAL then
            RecordAccumulator = RecordAccumulator - RECORD_INTERVAL
            table.insert(Frames, CaptureFrameData())
        end
        if ClonedMap then
            local ExitRegion = ClonedMap:FindFirstChild("ExitRegion", true)
            if ExitRegion and not AutoSaved and IsPointInPart(ExitRegion, LocalPlayer.Character.HumanoidRootPart.Position) then
                AutoSaved = true; SaveRun()
            end
        end
    end
    
    local PlayerPos = LocalPlayer.Character.HumanoidRootPart.Position; local InWater = false
    if not (CurrentAnim and CurrentAnim[1] == "slide") then
        for _, w in ipairs(WaterParts) do if IsPointInPart(w, PlayerPos) then InWater = true; break end end
    end
    getgenv().IsSwimming = InWater
end))

-- // INPUT BINDINGS (Keyboard) //
AddConnection(UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    local k = input.KeyCode.Name
    if k == Keybinds.UserPause then TogglePause()
    elseif k == Keybinds.AddSavestate then AddSavestate()
    elseif k == Keybinds.RemoveSavestate then RemoveSavestate()
    elseif k == Keybinds.BackSavestate then task.spawn(LoadLastSavestate)
    elseif k == Keybinds.CollisionToggler then ToggleCollision()
    elseif k == Keybinds.SaveRun then SaveRun()
    elseif k == Keybinds.GoFrameForward then if not IsRewinding and not IsAdvancingFrame then IsAdvancingFrame = true; while IsAdvancingFrame do StepForward() end end
    elseif k == Keybinds.GoFrameBack then IsAdvancingFrame = false; task.wait(); IsRewinding = true; while IsRewinding do RewindFrame(); task.wait(0.05) end
    elseif k == "Up" then IsPreviewingForward = true
    elseif k == "Down" then IsPreviewingBackward = true
    elseif k == Keybinds.EnvPause then EnvPaused = not EnvPaused
    elseif k == Keybinds.ToggleTimeReset then AutoResetEnv = not AutoResetEnv
    elseif k == Keybinds.Resync then IsPreviewingForward = false; IsPreviewingBackward = false; PreviewOffset = 0
    elseif k == Keybinds.ViewTAS then PlaybackTAS()
    elseif k == Keybinds.LoadRun then LoadRun()
    elseif k == Keybinds.DebugToggler then ToggleDebugView()
    elseif k == Keybinds.ResetToNormal then getgenv().TAS_Active = false; UI.ScreenGui:Destroy() end
end))

AddConnection(UserInputService.InputEnded:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode.Name == Keybinds.GoFrameBack then IsRewinding = false end
    if input.KeyCode.Name == Keybinds.GoFrameForward then IsAdvancingFrame = false end
    if input.KeyCode.Name == "Up" then IsPreviewingForward = false end
    if input.KeyCode.Name == "Down" then IsPreviewingBackward = false end
end))

AddConnection(LocalPlayer.Character.Humanoid.Died:Connect(function()
    task.wait(0.1); if not IsPaused then TogglePause() end
    LocalPlayer.CharacterAdded:Wait(); task.wait(0.1)
    if ClonedMap and ClonedMap.Parent then LoadLastSavestate() end
end))

-- // UI BUTTON BINDINGS (Mobile) //
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

-- Initialize Setup
task.spawn(function()
    local RopeEvent = game:GetService("ReplicatedStorage"):WaitForChild("Remote"):WaitForChild("UpdRopeData")
    if RopeEvent then RopeEvent.OnClientEvent:Connect(function(val) if type(val) == "table" and not ClonedMap then RopeTable = val end end) end
end)

game.Workspace.Multiplayer:WaitForChild("NewMap", 9e99)
game.Workspace.Multiplayer:WaitForChild("Map", 9e99)
repeat task.wait() until LocalPlayer.Character.HumanoidRootPart.Anchored == false
SetupMap()
