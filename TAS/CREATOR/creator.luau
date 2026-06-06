--- START OF FILE creator.luau (7).txt ---

--[[
    FE2 TAS Creator (Jump Farm Edition)
    - UPDATE: Switched to .Changed event for smarter property tracking.
    - ADDED: Support for Material, Reflectance, Texture offsets, and more.
    - FIXED: Timer & Visuals Offset applied correctly during rewind.
    - PREVIOUS: Decal support, Rewind Lag Fix, Binary Optimization.
]]

getgenv().TAS_Active = true 

local UI_API_URL = "https://raw.githubusercontent.com/tomatotxt/Flood-GUI/refs/heads/testing/TAS/CREATOR/uiapi.luau"

print("TAS Creator: Smart .Changed Recorder Loaded")

local Keybinds = {
    AddSavestate = "One",
    RemoveSavestate = "Two",
    BackSavestate = "Three",
    GoFrameBack = "Four", 
    GoFrameForward = "Five", 
    SaveRun = "Six",
    UserPause = "CapsLock",
    CollisionToggler = "C",
    ResetToNormal = "Delete",
    ViewTAS = "Zero",
    Resync = "F8",
    EnvPause = "Equals",
    ToggleTimeReset = "Seven"
}

-- // SERVICES //
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- // ALERT SYSTEM //
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
    if NewAlert then
        pcall(function() NewAlert(msg, color, 1.5, nil) end)
    else
        local GameScript = LocalPlayer.PlayerScripts:FindFirstChild("CL_MAIN_GameScript")
        if GameScript then
            local s, e = pcall(getsenv, GameScript)
            if s and e and e.newAlert then
                NewAlert = e.newAlert
                pcall(function() NewAlert(msg, color, 1.5, nil) end)
            end
        end
    end
end

SendAlert("TAS Creator Initialized", Color3.fromRGB(183, 0, 255))

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
local CurrentAnim = {}
local Savestates = {}
local Frames = {} 
local TimeOffset = 0
local PreviewOffset = 0
local IsPaused = true
local EnvPaused = false
local PauseStart
local OriginalPlayAnim
local AnimEnv
local RunStart
local SavedVelocity = Vector3.new(0, 0, 0)
local Connections = {} 

-- Flags
local IsPreviewingForward = false
local IsPreviewingBackward = false
local IsAdvancingFrame = false 
local IsRewinding = false
local IsViewingTAS = false
local AutoSaved = false
local AutoResetEnv = false 

-- Recorder & Map
local MapEvents = {} 
local PlaybackIndex = 1
local MapRecorderCache = {}
local ClonedMap
local RopeTable
local MapOffset, MapPos, MapX, MapY, MapZ
local MapUUIDs = {} 

-- Button Order Tracking
local RecordedButtonSequence = {} 
local OrderedButtonRegistry = {}  

-- Lighting Storage
local SavedLighting = {
    Props = {},
    Children = {}
}
local LightingCaptured = false

-- Recording Cap
local RecordAccumulator = 0
local TARGET_FPS = 60
local RECORD_INTERVAL = 1 / TARGET_FPS

-- Auto-Swim
getgenv().IsSwimming = false
local WaterParts = {}

-- Button Tracking
local TotalButtons = {}
local ButtonRegistry = {} 

-- UI Variables
local TAS_UI = loadstring(game:HttpGet(UI_API_URL))()
local UI_Elements = nil
local TimeText, FrameCountLabel, StatusLabel, MapEventLabel

-- // DATA PACKING (OPTIMIZATION) //
local PACK_FORMAT = "d" .. string.rep("f", 28) .. "s"

local function PackFrame(Time, Vel, CF, CamCF, Anim)
    local animName = Anim[1] or "idle"
    local animSpeed = Anim[2] or 0
    local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = CF:GetComponents()
    local cx, cy, cz, cR00, cR01, cR02, cR10, cR11, cR12, cR20, cR21, cR22 = CamCF:GetComponents()
    return string.pack(PACK_FORMAT, Time, Vel.X, Vel.Y, Vel.Z, x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22, cx, cy, cz, cR00, cR01, cR02, cR10, cR11, cR12, cR20, cR21, cR22, animSpeed, animName)
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

local function AddConnection(con)
    table.insert(Connections, con)
    return con
end

local function isRandomString(str)
    if #str == 0 then return false end
    for i = 1, #str do
        local ltr = str:sub(i, i)
        if ltr:lower() == ltr then return false end
    end
    return true
end

local function GetUUID(part)
    if not part then return nil end
    local id = part:GetAttribute("TAS_UUID")
    if not id then
        id = HttpService:GenerateGUID(false)
        part:SetAttribute("TAS_UUID", id)
    end
    return id
end

local function DeepCopy(orig)
    local copy = {}
    if type(orig) == 'table' then
        for k, v in pairs(orig) do copy[k] = v end
    else
        copy = orig
    end
    return copy
end

local function ToggleCollision()
    local mouse = LocalPlayer:GetMouse()
    if mouse and mouse.Target then
        local target = mouse.Target
        target.CanCollide = not target.CanCollide
        SendAlert("Collision " .. (target.CanCollide and "Enabled" or "Disabled"), Color3.fromRGB(255, 255, 0))
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
    return PackFrame(
        tick() - RunStart - TimeOffset,
        LocalPlayer.Character.HumanoidRootPart.Velocity,
        GetPlayerCFrame(),
        workspace.CurrentCamera.CFrame,
        CurrentAnim
    )
end

-- [[ UI API LOADING ]] --
local function LoadUI(MapName)
    if UI_Elements and UI_Elements.ScreenGui and UI_Elements.ScreenGui.Parent then return end
    UI_Elements = TAS_UI.Create()
    TimeText = UI_Elements.TimeText
    FrameCountLabel = UI_Elements.FrameCount
    StatusLabel = UI_Elements.StatusText
    MapEventLabel = UI_Elements.MapEventInfo
    
    if MapName and MapEventLabel then MapEventLabel.Text = MapName end
end

local function UpdateTimeDisplay(DisplayTime)
    if not TimeText then return end
    local m = math.floor(DisplayTime / 60)
    local s = math.floor(DisplayTime % 60)
    local ms = math.floor(DisplayTime * 1000 % 1000)
    TimeText.Text = string.format("%d:%02d.%03d", m, s, ms)
end

-- // LIGHTING MANAGER //
local function CaptureLighting()
    SavedLighting.Props = {
        Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime, FogColor = Lighting.FogColor, FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart, GlobalShadows = Lighting.GlobalShadows,
        ExposureCompensation = Lighting.ExposureCompensation, TimeOfDay = Lighting.TimeOfDay
    }
    SavedLighting.Children = {}
    for _, child in ipairs(Lighting:GetChildren()) do table.insert(SavedLighting.Children, child:Clone()) end
    LightingCaptured = true
    SendAlert("Lighting Captured", Color3.fromRGB(255, 255, 0))
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

-- // MAP MONITOR //
local MonitorCon = workspace.Multiplayer.ChildAdded:Connect(function(child)
    if not getgenv().TAS_Active then return end
    if ClonedMap and (child.Name == "Map" or child.Name == "NewMap") then
        task.wait()
        child:Destroy()
    end
end)
AddConnection(MonitorCon)

-- // MAP PLAYBACK ENGINE //
local function UpdateMapState(TargetTime)
    if EnvPaused then return end
    
    while PlaybackIndex <= #MapEvents and MapEvents[PlaybackIndex].Time <= TargetTime do
        local Event = MapEvents[PlaybackIndex]
        if Event.Instance then
            if Event.Prop == "Destroyed" then
                Event.Instance.Transparency = 1
                if Event.Instance:IsA("BasePart") then
                    Event.Instance.CanCollide = false
                    Event.Instance.Anchored = true
                    if Event.ChildrenUUIDs then
                        for _, childUUID in ipairs(Event.ChildrenUUIDs) do
                            local child = MapUUIDs[childUUID]
                            if child then child.Transparency = 1 end
                        end
                    end
                end
            elseif Event.Prop == "Anchored" then
                if Event.NewVal == false and Event.Instance:IsA("BasePart") and Event.Instance.CanCollide == false then
                    Event.Instance.Anchored = true
                    Event.Instance.Transparency = 1
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
                        Event.Instance.CanCollide = s.CanCollide
                        Event.Instance.CFrame = s.CFrame
                        Event.Instance.Anchored = s.Anchored
                        Event.Instance.Color = s.Color
                        Event.Instance.Size = s.Size
                        Event.Instance.Material = s.Material
                        Event.Instance.Reflectance = s.Reflectance
                    end
                    if Event.Instance:IsA("Decal") or Event.Instance:IsA("Texture") then
                         Event.Instance.Color3 = s.Color3
                         Event.Instance.Texture = s.Texture
                    end
                    
                    if Event.Children and Event.ChildrenUUIDs then
                        for _, childUUID in ipairs(Event.ChildrenUUIDs) do
                            local child = MapUUIDs[childUUID]
                            local childState = Event.Children[childUUID]
                            if child and childState then
                                child.Transparency = childState.Transparency
                                child.Color3 = childState.Color3
                            end
                        end
                    end
                else
                    Event.Instance.Transparency = 0
                    if Event.Instance:IsA("BasePart") then Event.Instance.CanCollide = true end
                end
            elseif Event.Prop == "Anchored" then
                Event.Instance.Anchored = Event.OldVal
                if Event.OldVal == true and Event.StoredCFrame then
                    Event.Instance.CFrame = Event.StoredCFrame
                    Event.Instance.CanCollide = Event.StoredCanCollide
                    Event.Instance.Transparency = 0
                    Event.Instance.Velocity = Vector3.new(0,0,0)
                    Event.Instance.RotVelocity = Vector3.new(0,0,0)
                end
            else
                Event.Instance[Event.Prop] = Event.OldVal
            end
        end
    end
end

-- // BUTTON SYNC LOGIC //
local function SyncButtonState(VisualTime, RealTime)
    for part, data in pairs(ButtonRegistry) do
        if data.IsPressed and data.TruePressTime > RealTime then
            data.IsPressed = false
            data.PressTime = nil
        end
    end
    
    local NextIndex = 1
    for i = 1, #RecordedButtonSequence do
        local btnData = OrderedButtonRegistry[i]
        if btnData and not btnData.IsPressed then
            NextIndex = i
            break
        end
        if i == #RecordedButtonSequence then NextIndex = i + 1 end
    end
    
    for part, data in pairs(ButtonRegistry) do
        local isVisuallyPressed = (data.TruePressTime and data.TruePressTime <= VisualTime)
        
        if isVisuallyPressed then
            data.SelectionBox.Color3 = Color3.fromRGB(0, 255, 0)
        elseif data.Order ~= 999 then
            if data.Order == NextIndex then
                data.SelectionBox.Color3 = Color3.fromRGB(255, 255, 0)
            elseif data.Order > NextIndex then
                data.SelectionBox.Color3 = Color3.fromRGB(255, 0, 0)
            else
                data.SelectionBox.Color3 = Color3.fromRGB(0, 255, 0) 
            end
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
        if not IsPaused then
            CurrentAnim = {anim, speed}
            OriginalPlayAnim(CurrentAnim[1], CurrentAnim[2], LocalPlayer.Character.Humanoid)
        end
    end
end

-- // CLEANUP //
local function ResetToNormal()
    getgenv().TAS_Active = false
    for _, con in pairs(Connections) do con:Disconnect() end
    Connections = {}
    
    TotalButtons = {}
    ButtonRegistry = {}
    OrderedButtonRegistry = {}
    RecordedButtonSequence = {}
    MapEvents = {}
    MapUUIDs = {}
    SavedLighting = {}
    LightingCaptured = false
    AutoSaved = false
    
    if ClonedMap then ClonedMap:Destroy(); ClonedMap = nil end
    if UI_Elements and UI_Elements.ScreenGui then UI_Elements.ScreenGui:Destroy() end
    UI_Elements = nil
    
    LocalPlayer.Character:BreakJoints() -- Hard Reset
    SendAlert("TAS Creator Stopped", Color3.fromRGB(255, 0, 0))
end

-- // CORE LOGIC //
local function TogglePause()
    local pause = task.spawn(function()
        IsPaused = not IsPaused
        local Root = LocalPlayer.Character.HumanoidRootPart
        if IsPaused then
            SavedVelocity = Root.Velocity
            Root.Anchored = true
            PauseStart = tick()
            if StatusLabel then 
                StatusLabel.Text = "PAUSED"
                StatusLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
            end
            SendAlert("Paused", Color3.fromRGB(255, 255, 0))
        else
            Root.Anchored = false
            Root.Velocity = SavedVelocity
            TimeOffset = TimeOffset + tick() - PauseStart
            if StatusLabel then 
                StatusLabel.Text = "PLAYING"
                StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            end
            RecordAccumulator = 0
            SendAlert("Unpaused", Color3.fromRGB(0, 255, 0))
        end
    end)
end

local function LoadLastSavestate()
    local LastState = Savestates[#Savestates]
    if LastState then
        local FramePacked = LastState[#LastState]
        if not FramePacked then return end
        
        local Frame = UnpackFrame(FramePacked)
        
        Frames = {}
        IsPaused = true
        PreviewOffset = 0
        
        local Root = LocalPlayer.Character.HumanoidRootPart
        Root.Anchored = true
        
        Root.CFrame = Frame.CFrame + Vector3.new(MapX, MapY - 1000, MapZ)
        Root.Velocity = Frame.Velocity
        SavedVelocity = Frame.Velocity
        
        workspace.CurrentCamera.CFrame = Frame.CameraCFrame
        PauseStart = tick()
        RunStart = tick() - Frame.Time
        TimeOffset = 0
        
        SyncButtonState(Frame.Time, Frame.Time)
        UpdateMapState(Frame.Time)
        
        OriginalPlayAnim(Frame.Animation[1], Frame.Animation[2], LocalPlayer.Character.Humanoid)
        if Frame.Animation[1] == "walk" then AnimEnv.setAnimationSpeed(0.76) end
        
        task.spawn(function() UpdateTimeDisplay(Frame.Time) end)
        SendAlert("Savestate Loaded", Color3.fromRGB(0, 255, 255))
    end
end

local function AddSavestate()
    table.insert(Savestates, Frames)
    Frames = {}
    SendAlert("Savestate Added (" .. #Savestates .. ")", Color3.fromRGB(0, 255, 0))
end

local RemoveConfirm = false
local RemoveConfirmTime = 0
local function RemoveSavestate()
    if not RemoveConfirm or (tick() - RemoveConfirmTime > 2) then
        RemoveConfirm = true
        RemoveConfirmTime = tick()
        SendAlert("Press again to remove last state", Color3.fromRGB(255, 170, 0))
        return
    end
    RemoveConfirm = false
    
    if #Savestates > 1 then
        table.remove(Savestates)
        task.spawn(LoadLastSavestate)
        SendAlert("Savestate Removed", Color3.fromRGB(255, 0, 0))
    else
        SendAlert("Cannot remove initial state", Color3.fromRGB(255, 0, 0))
    end
end

local function Noclip(Toggle)
    local char = LocalPlayer.Character
    if char then
        for i, v in char:GetChildren() do
            if v:IsA("BasePart") then
                v.CanCollide = not Toggle
            end
        end
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
        local target = nil
        local connections = {}
        for _, child in ipairs(LiveMap:GetChildren()) do
            if child.Name == "Part" and child.Size.Y < 5 then
                table.insert(connections, child:GetPropertyChangedSignal("Rotation"):Connect(function()
                    target = child
                    for _, con in ipairs(connections) do con:Disconnect() end
                end))
            end
        end
        repeat task.wait() until target
        LiveMap.PrimaryPart = target
    else
        LiveMap.PrimaryPart = Spawn
    end
    
    CaptureLighting()
    
    for _, desc in ipairs(LiveMap:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then GetUUID(desc) end
    end
    
    LiveMap.Archivable = true
    for _, d in pairs(LiveMap:GetDescendants()) do d.Archivable = true end
    
    ClonedMap = LiveMap:Clone()
    ClonedMap.Parent = nil 
    
    local Char = LocalPlayer.Character
    local Root = Char:WaitForChild("HumanoidRootPart")
    local Hum = Char:WaitForChild("Humanoid")
    
    local Recording = true
    local StartTime = os.clock()
    local Recorders = {}
    
    -- [[ SMART WHITELIST FOR .CHANGED ]] --
    local PropWhitelist = {
        BasePart = {
            ["CFrame"] = true, ["Transparency"] = true, ["CanCollide"] = true,
            ["Color"] = true, ["Size"] = true, ["Anchored"] = true,
            ["Material"] = true, ["Reflectance"] = true
        },
        Decal = {
            ["Transparency"] = true, ["Color3"] = true, ["Texture"] = true
        },
        Texture = {
            ["Transparency"] = true, ["Color3"] = true, ["Texture"] = true,
            ["OffsetStudsU"] = true, ["OffsetStudsV"] = true,
            ["StudsPerTileU"] = true, ["StudsPerTileV"] = true
        }
    }
    
    local function TrackPart(Part)
        local id = GetUUID(Part)
        if not id then return end
        
        -- Determine Type and Whitelist
        local MyWhitelist = nil
        if Part:IsA("BasePart") then MyWhitelist = PropWhitelist.BasePart
        elseif Part:IsA("Decal") then MyWhitelist = PropWhitelist.Decal
        elseif Part:IsA("Texture") then MyWhitelist = PropWhitelist.Texture end
        
        if not MyWhitelist then return end
        
        -- [[ INIT CACHE for Whitelisted Properties ]] --
        MapRecorderCache[Part] = {}
        for prop, _ in pairs(MyWhitelist) do
            -- Safety check if property exists
            local s, val = pcall(function() return Part[prop] end)
            if s then MapRecorderCache[Part][prop] = val end
        end
        
        local function OnChange(Prop)
            if not Recording then return end
            if not MyWhitelist[Prop] then return end -- Whitelist Check
            
            local NewVal = Part[Prop]
            local OldVal = MapRecorderCache[Part][Prop]
            
            -- Simple inequality check (vector/color/cframe aware)
            if NewVal ~= OldVal then
                local EventData = {
                    Time = os.clock() - StartTime,
                    UUID = id,
                    Prop = Prop,
                    OldVal = OldVal,
                    NewVal = NewVal
                }
                
                if Prop == "Anchored" and Part:IsA("BasePart") then
                    EventData.StoredCFrame = Part.CFrame
                    EventData.StoredCanCollide = Part.CanCollide
                end
                
                table.insert(MapEvents, EventData)
                MapRecorderCache[Part][Prop] = NewVal
            end
        end
        
        -- [[ SINGLE CONNECTION: .Changed ]] --
        table.insert(Recorders, Part.Changed:Connect(OnChange))
        
        table.insert(Recorders, Part.Destroying:Connect(function()
            if not Recording then return end
            -- [[ DEEP COPY STATE ]] --
            local State = DeepCopy(MapRecorderCache[Part])
            
            -- [[ CAPTURE CHILDREN STATE ]] --
            local ChildrenUUIDs = {}
            local ChildrenStates = {}
            if Part:IsA("BasePart") then
                for _, child in ipairs(Part:GetChildren()) do
                    if (child:IsA("Decal") or child:IsA("Texture")) and MapRecorderCache[child] then
                        local childID = GetUUID(child)
                        table.insert(ChildrenUUIDs, childID)
                        ChildrenStates[childID] = DeepCopy(MapRecorderCache[child])
                    end
                end
            end
            
            table.insert(MapEvents, {
                Time = os.clock() - StartTime,
                UUID = id,
                Prop = "Destroyed",
                OldVal = State,
                Children = ChildrenStates,
                ChildrenUUIDs = ChildrenUUIDs,
                NewVal = true
            })
        end))
    end

    for _, Object in ipairs(LiveMap:GetDescendants()) do
        if Object:IsA("BasePart") or Object:IsA("Decal") or Object:IsA("Texture") then TrackPart(Object) end
    end
    table.insert(Recorders, LiveMap.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then TrackPart(d) end
    end))

    SendAlert("Scanning for Buttons...", Color3.fromRGB(255, 170, 0))
    Hum.Health = 99999 -- God Mode
    
    local Buttons = {}
    for i, MapObject in pairs(LiveMap:GetDescendants()) do
        if isRandomString(MapObject.Name) and MapObject:IsA("Model") then
            local Hitbox
            for i, Candidate in pairs(MapObject:GetChildren()) do
                if Candidate:IsA("BasePart") and tostring(Candidate.BrickColor) ~= "Medium stone grey" then
                    Hitbox = Candidate
                    break
                end
            end
            if Hitbox and isRandomString(Hitbox.Name) then
                Hitbox.Name = "Hitbox" 
                table.insert(Buttons, MapObject)
            end
        end
    end
    
    SendAlert("Autofarm: Found " .. #Buttons .. " Buttons", Color3.fromRGB(0, 255, 0))
    SendAlert("Commencing Auto Farm", Color3.fromRGB(255, 170, 0))

    Noclip(true)
    
    -- [GODMODE: RENDERSTEPPED LOOP]
    local GodModeCon = RunService.RenderStepped:Connect(function()
        if Hum then Hum.Health = 99999 end
    end)
    
    local LastSafePos = CFrame.new(0, 1000, 0)
    local LiveExitRegion = nil 
    local LastTargetButton = nil -- TRACKER FOR PREVIOUS BUTTON
    RecordedButtonSequence = {}
    ButtonPressTimings = {} 
    
    while Recording and LiveMap.Parent and Hum.Health > 0 do
        Hum.Jump = true
        
        if not LiveExitRegion then
            LiveExitRegion = LiveMap:FindFirstChild("ExitRegion", true)
        end
        
        local FailedScan = true
        Root.Anchored = true
        
        for i, Button in pairs(Buttons) do
            local ButtonHitbox = Button:FindFirstChild("Hitbox")
            if ButtonHitbox then
                local TouchFound = Button:FindFirstChild("TouchInterest", true)
                local GuiFound = Button:FindFirstChildWhichIsA("BillboardGui", true)
                
                if (TouchFound and GuiFound) then
                    FailedScan = false
                    Root.Anchored = false
                    
                    -- [[ AUTOFARM LOGIC ]] --
                    if Button ~= LastTargetButton then
                        local uuid = GetUUID(ButtonHitbox)
                        if uuid and not table.find(RecordedButtonSequence, uuid) then
                            table.insert(RecordedButtonSequence, uuid)
                            local Ping = LocalPlayer:GetNetworkPing()
                            ButtonPressTimings[uuid] = (os.clock() - StartTime) + Ping
                        end

                        if LastTargetButton ~= nil then
                            task.wait(0.1) 
                        end
                        LastTargetButton = Button
                    else
                        local uuid = GetUUID(ButtonHitbox)
                        if uuid and not table.find(RecordedButtonSequence, uuid) then
                            table.insert(RecordedButtonSequence, uuid)
                            local Ping = LocalPlayer:GetNetworkPing()
                            ButtonPressTimings[uuid] = (os.clock() - StartTime) + Ping
                        end
                    end
                    
                    Root.CFrame = CFrame.new(ButtonHitbox.Position)
                    Root.Velocity = Vector3.new(0, 0, 0)
                    Hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    task.wait(0.255/15) -- KEEP FAST LOOP FOR PRESSING
                end
            end
        end
        
        if FailedScan then
            if LiveExitRegion then
                Root.CFrame = LiveExitRegion.CFrame + Vector3.new(0, 100, 0)
                Root.Velocity = Vector3.new(0,0,0)
            else
                Root.CFrame = LastSafePos + Vector3.new(0, 10, 0)
                Root.Velocity = Vector3.new(0,0,0)
            end
        else
            LastSafePos = Root.CFrame
        end
        
        RunService.Heartbeat:Wait()
    end
    
    Recording = false
    if GodModeCon then GodModeCon:Disconnect() end -- [CLEANUP GODMODE]
    SendAlert("Recording Finished", Color3.fromRGB(255, 0, 0))
    
    Noclip(false)
    for _, r in ipairs(Recorders) do r:Disconnect() end
    
    CaptureLighting()
    
    SendAlert("Processing Map...", Color3.fromRGB(0, 200, 255))
    if LiveMap then LiveMap.Archivable = true; LiveMap:Destroy() end
    
    ClonedMap.Parent = workspace
    
    MapUUIDs = {}
    for _, desc in ipairs(ClonedMap:GetDescendants()) do
        local id = desc:GetAttribute("TAS_UUID")
        if id then MapUUIDs[id] = desc end
    end
    
    for _, Event in ipairs(MapEvents) do
        Event.Instance = MapUUIDs[Event.UUID]
    end

    for i = #MapEvents, 1, -1 do
        local Event = MapEvents[i]
        if Event.Instance then
            if Event.Prop ~= "Destroyed" then
                Event.Instance[Event.Prop] = Event.OldVal 
            end
        end
    end
    
    if not ClonedMap.PrimaryPart then
         local LiveName = LiveMap.PrimaryPart.Name
         ClonedMap.PrimaryPart = ClonedMap:FindFirstChild(LiveName, true)
    end
    
    MapPos = ClonedMap.PrimaryPart.Position
    MapX, MapY, MapZ = MapPos.X, MapPos.Y, MapPos.Z
    MapOffset = CFrame.new(MapX, MapY, MapZ)
    
    LocalPlayer.Character:BreakJoints()
    SendAlert("Respawning...", Color3.fromRGB(255, 255, 0))
    LocalPlayer.CharacterAdded:Wait()
    Char = LocalPlayer.Character
    task.wait(1)
    
    game:GetService("ReplicatedStorage"):WaitForChild("Remote"):WaitForChild("RemoveWaiting"):FireServer()
    
    local FE2Env = getsenv(Char:WaitForChild("FE2_Character"))
    local startZipline = FE2Env.startZipline
    if RopeTable and #RopeTable >= 1 then
        SendAlert("Zipline Data Restored", Color3.fromRGB(0, 255, 255))
        task.spawn(function()
            while Char and Char.Humanoid.Health >= 1 do
                setupvalue(startZipline, 2, RopeTable)
                task.wait()
            end
        end)
    end
    
    Root = Char:WaitForChild("HumanoidRootPart")
    Hum = Char:WaitForChild("Humanoid")
    Hum.WalkSpeed = 0
    Hum.JumpPower = 0
    task.wait(0.5)
    Hum.WalkSpeed = 0
    Hum.JumpPower = 0
    
    Root.CFrame = CFrame.new(ClonedMap.PrimaryPart.Position) + Vector3.new(0, ClonedMap.PrimaryPart.Size.Y/2, 0) + Vector3.new(0, Root.Size.Y/2, 0) + Vector3.new(0, Char["Left Leg"].Size.Y, 0)
    
    task.wait(0.5)
    Root.Anchored = true
    Hum.WalkSpeed = 20
    Hum.JumpPower = 50
    
    table.insert(Savestates, {
        PackFrame(0, Vector3.new(0,0,0), GetPlayerCFrame(), workspace.CurrentCamera.CFrame, {"idle", 0})
    })
    
    PauseStart = tick()
    RunStart = tick()
    HookAnimations()
    
    AddConnection(LocalPlayer.CharacterAdded:Connect(function(c)
        local anim = c:WaitForChild("Animate")
        if anim.Enabled then HookAnimations() end
    end))
    
    LoadUI(MapName)
    
    WaterParts = {}
    TotalButtons = {}
    ButtonRegistry = {}
    OrderedButtonRegistry = {}
    local CheckedButtonParts = {}

    local function RegisterButton(btn)
        if not btn or CheckedButtonParts[btn] then return end
        CheckedButtonParts[btn] = true
        table.insert(TotalButtons, btn)
        
        local sel = Instance.new("SelectionBox", btn)
        sel.Adornee = btn
        sel.Color3 = Color3.fromRGB(255, 140, 0)
        sel.SurfaceTransparency = 0.8
        btn.CanTouch = true
        
        local uuid = GetUUID(btn)
        local order = table.find(RecordedButtonSequence, uuid) or 999
        local recTime = ButtonPressTimings[uuid] 
        
        local bData = {
            IsPressed = false,
            PressTime = nil,
            SelectionBox = sel,
            Order = order,
            RecordedTime = recTime
        }
        
        ButtonRegistry[btn] = bData
        OrderedButtonRegistry[order] = bData
        
        AddConnection(btn.Touched:Connect(function(hit)
            if hit.Parent == LocalPlayer.Character and not bData.IsPressed then
                if not RunStart then return end
                
                if bData.Order and bData.Order > 1 then
                    local prevBtn = OrderedButtonRegistry[bData.Order - 1]
                    if prevBtn and not prevBtn.IsPressed then
                        SendAlert("WRONG ORDER! Press Button #" .. (bData.Order - 1) .. " first!", Color3.fromRGB(255, 0, 0))
                        return
                    end
                end
                
                if AutoResetEnv and bData.RecordedTime then
                    local RealTime = tick() - RunStart - TimeOffset
                    PreviewOffset = bData.RecordedTime - RealTime
                    SendAlert("Synced to " .. string.format("%.2fs", bData.RecordedTime), Color3.fromRGB(0, 255, 255))
                end
                
                local RealTime = tick() - RunStart - TimeOffset
                bData.IsPressed = true
                bData.PressTime = RealTime
                bData.TruePressTime = RealTime 
                sel.Color3 = Color3.fromRGB(0, 255, 0)
                SendAlert("Button " .. (order ~= 999 and "#"..order or "") .. " Pressed!", Color3.fromRGB(0, 255, 0))
            end
        end))
    end

    for _, obj in ipairs(ClonedMap:GetDescendants()) do
        if obj:IsA("BasePart") then
             if obj.Name:find("_Water") then table.insert(WaterParts, obj) end
        end

        if obj.Name == "ButtonIcon" then
            local ButtonPart = nil
            if obj.Parent and obj.Parent.Parent and obj.Parent.Parent:IsA("BasePart") then
                ButtonPart = obj.Parent.Parent
            elseif obj.Parent and obj.Parent.Parent and obj.Parent.Parent:IsA("Model") then
                ButtonPart = obj.Parent.Parent:FindFirstChildOfClass("BasePart")
            end
            RegisterButton(ButtonPart)
        end
        
        if isRandomString(obj.Name) and obj:IsA("Model") then
            if obj.Name == "NPC" or obj:FindFirstAncestor("_Rescue") then
            else
                local hp = obj:FindFirstChild("Hitbox") 
                if not hp then
                    for _, c in ipairs(obj:GetChildren()) do
                        if c:IsA("BasePart") and tostring(c.BrickColor) ~= "Medium stone grey" then
                             hp = c; break
                        end
                    end
                end
                RegisterButton(hp)
            end
        end
    end

    SendAlert("Map Ready & Linked", Color3.fromRGB(0, 255, 0))
end

-- // FAST FORWARD / REWIND PLAYER //
local function StepForward()
    if not IsPaused then return end 
    local InitialFrames = #Frames
    TogglePause() 
    RecordAccumulator = RECORD_INTERVAL + 0.1 
    repeat 
        RunService.Heartbeat:Wait()
        if IsRewinding then break end
    until #Frames > InitialFrames
    if not IsPaused then TogglePause() end
end

local function FrameAdvanceLoop()
    if IsRewinding then return end
    if IsAdvancingFrame then return end
    IsAdvancingFrame = true
    SendAlert("Step Forward", Color3.fromRGB(0, 255, 0))
    while IsAdvancingFrame do 
        if IsRewinding then IsAdvancingFrame = false; break end
        StepForward()
    end
end

local function RewindFrame()
    if LocalPlayer.Character then
        local FramePacked = Frames[#Frames - 1]
        if not FramePacked and #Savestates > 0 then 
            local PrevState = Savestates[#Savestates]
            FramePacked = PrevState[#PrevState - 1] 
        end
        
        if FramePacked then
            local Frame = UnpackFrame(FramePacked)
            
            if not IsPaused then TogglePause() end
            local Root = LocalPlayer.Character.HumanoidRootPart
            Root.CFrame = Frame.CFrame + Vector3.new(MapX, MapY - 1000, MapZ)
            Root.Velocity = Frame.Velocity
            SavedVelocity = Frame.Velocity
            workspace.CurrentCamera.CFrame = Frame.CameraCFrame
            PauseStart = tick()
            RunStart = tick() - Frame.Time
            TimeOffset = 0
            
            -- [[ APPLIED FIX: Timer & Visuals Offset applied during rewind ]] --
            local VisualTime = Frame.Time + PreviewOffset
            
            SyncButtonState(VisualTime, Frame.Time)
            UpdateMapState(VisualTime)
            
            if Frame.Animation[1] then OriginalPlayAnim(Frame.Animation[1], Frame.Animation[2], LocalPlayer.Character.Humanoid) end
            if Frame.Animation[1] == "walk" then AnimEnv.setAnimationSpeed(0.76) end
            
            task.spawn(function() UpdateTimeDisplay(VisualTime) end)
            Frames[#Frames] = nil
        end
    end
end

local function RewindLoop()
    if IsAdvancingFrame then return end
    IsRewinding = true
    SendAlert("Rewinding...", Color3.fromRGB(255, 0, 0))
    RewindFrame()
    while task.wait(0.05) and IsRewinding do RewindFrame() end
end

-- // VIEW TAS (IMPROVED PLAYER LOGIC) //
local IsTASSliding = false
local function ToggleTASSlide(val)
    if not LocalPlayer.Character then return end
    if val then
        if LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.Size = Vector3.new(2, 1, 1)
        end
        if LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.HipHeight = -1.5
        end
    else
        if LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.Size = Vector3.new(2, 2, 1)
        end
        if LocalPlayer.Character:FindFirstChild("Humanoid") then
            LocalPlayer.Character.Humanoid.HipHeight = 0
        end
    end
end

local LastTASAnim = nil
local function ActivateTASAnimation(AnimData)
    if not AnimData then OriginalPlayAnim("idle", 0.1, LocalPlayer.Character.Humanoid); return end
    if not LocalPlayer.Character then return end
    local n = AnimData[1]
    local animTime = AnimData[2] or 0.1
    if LocalPlayer.Character.Humanoid:GetState() == Enum.HumanoidStateType.Physics then n = "swing" end
    if n == "idle" then
        local vel = LocalPlayer.Character.HumanoidRootPart.Velocity
        if vel.Magnitude > 1 then
            if LocalPlayer.Character.Humanoid.FloorMaterial ~= Enum.Material.Air then n = "walk"; animTime = 0.1 else n = "fall"; animTime = 0.3 end
        end
    end
    if n == "fall" and LocalPlayer.Character.HumanoidRootPart.Velocity.Magnitude < 0.1 then n = "swing" end
    if n == "slide" then
        if not IsTASSliding then ToggleTASSlide(true); IsTASSliding = true end
    else
        if IsTASSliding then ToggleTASSlide(false); IsTASSliding = false end
    end
    if n and (n == "swing" or n == "zipline" or n ~= LastTASAnim) then
        OriginalPlayAnim(n, animTime, LocalPlayer.Character.Humanoid)
        if n == "walk" then AnimEnv.setAnimationSpeed(0.76) end
        LastTASAnim = n
    end
end

local function PlaybackTAS(Data)
    IsViewingTAS = true
    SendAlert("Viewing TAS Preview", Color3.fromRGB(183, 0, 255))
    
    local Root = LocalPlayer.Character.HumanoidRootPart
    local Cam = workspace.CurrentCamera
    local Offset = ClonedMap.PrimaryPart.Position - Vector3.new(0, 1000, 0)
    
    local OldFrame = 1
    local PlayStart = tick()
    IsTASSliding = false
    LastTASAnim = nil
    
    local NewC, AngC, NewV = CFrame.new, CFrame.fromEulerAnglesXYZ, Vector3.new

    local Con
    Con = RunService.Heartbeat:Connect(function()
        if not IsViewingTAS then 
            Con:Disconnect()
            Root.Anchored = true
            ToggleTASSlide(false)
            return 
        end
        Root.Anchored = true
        
        local Elapsed = tick() - PlayStart
        UpdateMapState(Elapsed)
        SyncButtonState(Elapsed, Elapsed)
        
        while OldFrame < #Data and Data[OldFrame + 1].time <= Elapsed do 
            OldFrame = OldFrame + 1 
        end
        
        if OldFrame >= #Data then
            IsViewingTAS = false
            Con:Disconnect()
            Root.Anchored = true
            ToggleTASSlide(false)
            SendAlert("TAS Preview Finished", Color3.fromRGB(0, 255, 0))
            if not IsPaused then TogglePause() end
            return
        end
        
        local FA = Data[OldFrame]
        local FB = Data[OldFrame + 1] or FA
        local Dur = FB.time - FA.time
        local Alpha = (Dur > 0) and math.clamp((Elapsed - FA.time) / Dur, 0, 1) or 0
        
        local cfA = NewC(unpack(FA.CCFrame, 1, 3)) * AngC(unpack(FA.CCFrame, 4, 6))
        local cfB = NewC(unpack(FB.CCFrame, 1, 3)) * AngC(unpack(FB.CCFrame, 4, 6))
        
        local camA = NewC(unpack(FA.CCameraCFrame, 1, 3)) * AngC(unpack(FA.CCameraCFrame, 4, 6))
        local camB = NewC(unpack(FB.CCameraCFrame, 1, 3)) * AngC(unpack(FB.CCameraCFrame, 4, 6))
        
        local vA = NewV(unpack(FA.VVelocity))
        local vB = NewV(unpack(FB.VVelocity))
        
        Root.CFrame = cfA:Lerp(cfB, Alpha) + Offset
        Root.Velocity = vA:Lerp(vB, Alpha)
        Cam.CFrame = camA:Lerp(camB, Alpha) + Offset
        
        ActivateTASAnimation(FA.AAnimation)
    end)
    AddConnection(Con)
end

-- // SAVE RUN //
local function SaveRun()
    local PressedCount = 0
    for _, data in pairs(ButtonRegistry) do if data.IsPressed then PressedCount = PressedCount + 1 end end
    if PressedCount < #TotalButtons then SendAlert("Warning: Missing Buttons!", Color3.fromRGB(255, 255, 0)) end
    
    local function Round(n) return math.floor(n * 1000 + 0.5) / 1000 end
    local Export = {}
    
    local function ProcessFrameList(list)
        for j = 1, #list do
            local FramePacked = list[j]
            if type(FramePacked) == "string" then
                local F = UnpackFrame(FramePacked)
                local Entry = {}
                Entry.time = Round(F.Time)
                Entry.AAnimation = F.Animation or {"walk", 0.1}
                Entry.AAnimationChanged = F.Animation[2] 
                Entry.VVelocity = {Round(F.Velocity.X), Round(F.Velocity.Y), Round(F.Velocity.Z)}
                local rx, ry, rz = F.CFrame:ToEulerAnglesXYZ()
                Entry.CCFrame = {Round(F.CFrame.X), Round(F.CFrame.Y), Round(F.CFrame.Z), Round(rx), Round(ry), Round(rz)}
                local cx, cy, cz = F.CameraCFrame.X, F.CameraCFrame.Y, F.CameraCFrame.Z
                local crx, cry, crz = F.CameraCFrame:ToEulerAnglesXYZ()
                cx = cx - MapX
                cy = cy - (MapY - 1000)
                cz = cz - MapZ
                Entry.CCameraCFrame = {Round(cx), Round(cy), Round(cz), Round(crx), Round(cry), Round(crz)}
                table.insert(Export, Entry)
            end
        end
    end

    for i = 1, #Savestates do ProcessFrameList(Savestates[i]) end
    ProcessFrameList(Frames)
    
    if not isfolder("Flood-GUI/TAS FILES") then makefolder("Flood-GUI/TAS FILES") end
    writefile("Flood-GUI/TAS FILES/" .. ClonedMap.Settings:GetAttribute("MapName") .. ".json", game:GetService("HttpService"):JSONEncode(Export))
    SendAlert("Run Saved to Workspace", Color3.fromRGB(0, 255, 0))
end

-- // MAIN EXECUTION //
task.spawn(function()
    local RopeEvent = game:GetService("ReplicatedStorage"):WaitForChild("Remote"):WaitForChild("UpdRopeData")
    if RopeEvent then
        RopeEvent.OnClientEvent:Connect(function(val)
            if type(val) == "table" and not ClonedMap then RopeTable = val end
        end)
    end
end)

game.Workspace.Multiplayer:WaitForChild("NewMap", 9e99)
game.Workspace.Multiplayer:WaitForChild("Map", 9e99)
repeat task.wait() until LocalPlayer.Character.HumanoidRootPart.Anchored == false
SetupMap()

-- // HEARTBEAT LOOP //
local LastHeartbeat = tick()
local HBCon = RunService.Heartbeat:Connect(function(dt)
    if not getgenv().TAS_Active then return end
    if not UI_Elements or not UI_Elements.ScreenGui or not UI_Elements.ScreenGui.Parent then return end
    EnforceLighting()

    if not RunStart then return end
    -- [[ FIXED: LAG WHEN REWINDING WITH OFFSET ]] --
    if IsViewingTAS or IsRewinding or IsAdvancingFrame then return end

    if IsPreviewingForward then PreviewOffset = PreviewOffset + (dt * 5) end
    if IsPreviewingBackward then PreviewOffset = PreviewOffset - (dt * 5) end

    local RealTime = 0
    if not IsPaused then RealTime = tick() - RunStart - TimeOffset
    else RealTime = (PauseStart or tick()) - RunStart - TimeOffset end
    
    local VisualTime = RealTime + PreviewOffset
    if VisualTime < 0 then VisualTime = 0 end
    
    UpdateMapState(VisualTime)
    SyncButtonState(VisualTime, RealTime)
    UpdateTimeDisplay(VisualTime)
    
    if UI_Elements.SavestatesCount then UI_Elements.SavestatesCount.Text = "States: " .. tostring(#Savestates) end
    if UI_Elements.FrameCount then UI_Elements.FrameCount.Text = "Frames: " .. tostring(#Frames) end
    
    if PreviewOffset > 0.1 then TimeText.TextColor3 = Color3.fromRGB(0, 255, 0)
    elseif PreviewOffset < -0.1 then TimeText.TextColor3 = Color3.fromRGB(255, 0, 0)
    else 
        if IsPaused then TimeText.TextColor3 = Color3.fromRGB(255, 255, 0)
        else TimeText.TextColor3 = Color3.fromRGB(255, 255, 255) end
    end

    if not IsPaused then
        RecordAccumulator = RecordAccumulator + dt
        if RecordAccumulator >= RECORD_INTERVAL then
            RecordAccumulator = RecordAccumulator - RECORD_INTERVAL
            if RecordAccumulator > RECORD_INTERVAL then RecordAccumulator = 0 end
            table.insert(Frames, CaptureFrameData())
        end
        if tick() - LastHeartbeat >= 2 then LastHeartbeat = tick() end
        
        if ClonedMap then
            local ExitRegion = ClonedMap:FindFirstChild("ExitRegion", true)
            if ExitRegion and not AutoSaved then
                if IsPointInPart(ExitRegion, LocalPlayer.Character.HumanoidRootPart.Position) then
                    AutoSaved = true
                    SendAlert("Reached Exit - Auto Saving...", Color3.fromRGB(0, 255, 0))
                    SaveRun()
                end
            end
        end
    else 
        LastHeartbeat = tick() 
    end
    
    local PlayerPos = LocalPlayer.Character.HumanoidRootPart.Position
    local InWater = false
    local IsSliding = (CurrentAnim and CurrentAnim[1] == "slide")
    
    if not IsSliding then
        for _, waterPart in ipairs(WaterParts) do
            if IsPointInPart(waterPart, PlayerPos) then
                InWater = true
                break
            end
        end
    end
    getgenv().IsSwimming = InWater
end)
AddConnection(HBCon)

-- // INPUTS //
local InputCon = UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe then
        local k = input.KeyCode.Name
        if k == Keybinds.UserPause then TogglePause()
        elseif k == Keybinds.AddSavestate then AddSavestate()
        elseif k == Keybinds.RemoveSavestate then RemoveSavestate()
        elseif k == Keybinds.BackSavestate then task.spawn(LoadLastSavestate)
        elseif k == Keybinds.CollisionToggler then ToggleCollision()
        elseif k == Keybinds.SaveRun then SaveRun()
        elseif k == Keybinds.GoFrameForward then
            if IsRewinding then return end
            if not IsAdvancingFrame then task.spawn(FrameAdvanceLoop) end
        elseif k == Keybinds.GoFrameBack then 
            if IsAdvancingFrame then IsAdvancingFrame = false; task.wait() end
            task.spawn(RewindLoop)
        elseif k == "Up" then IsPreviewingForward = true
        elseif k == "Down" then IsPreviewingBackward = true
        elseif k == Keybinds.ResetToNormal then task.spawn(ResetToNormal)
        elseif k == Keybinds.EnvPause then 
            EnvPaused = not EnvPaused
            SendAlert("Map Updates " .. (EnvPaused and "Paused" or "Active"), Color3.fromRGB(255, 255, 0))
        elseif k == Keybinds.ToggleTimeReset then
            AutoResetEnv = not AutoResetEnv
            SendAlert("Smart Env Sync: " .. (AutoResetEnv and "ON" or "OFF"), Color3.fromRGB(0, 255, 255))
        elseif k == Keybinds.Resync then
            IsPreviewingForward = false
            IsPreviewingBackward = false
            PreviewOffset = 0
            SendAlert("Visuals Resynced", Color3.fromRGB(0, 255, 255))
        elseif k == Keybinds.ViewTAS then
            if not IsViewingTAS then
                local Data = {}
                local function AddList(list)
                     for j = 1, #list do
                        local FramePacked = list[j]
                        if type(FramePacked) == "string" then
                            local F = UnpackFrame(FramePacked)
                            local rx, ry, rz = F.CFrame:ToEulerAnglesXYZ()
                            local crx, cry, crz = F.CameraCFrame:ToEulerAnglesXYZ()
                            table.insert(Data, {
                                AAnimationChanged = F.Animation[2],
                                CCameraCFrame = {F.CameraCFrame.X, F.CameraCFrame.Y, F.CameraCFrame.Z, crx, cry, crz},
                                CCFrame = {F.CFrame.X, F.CFrame.Y, F.CFrame.Z, rx, ry, rz},
                                VVelocity = {F.Velocity.X, F.Velocity.Y, F.Velocity.Z},
                                AAnimation = F.Animation or {"walk", 0.1},
                                time = F.Time
                            })
                        end
                     end
                end
                for i = 1, #Savestates do AddList(Savestates[i]) end
                AddList(Frames)
                PlaybackTAS(Data)
            end
        end
    end
end)
AddConnection(InputCon)

local InputEndCon = UserInputService.InputEnded:Connect(function(input, gpe)
    if not gpe then
        if input.KeyCode.Name == Keybinds.GoFrameBack then IsRewinding = false end
        if input.KeyCode.Name == Keybinds.GoFrameForward then IsAdvancingFrame = false end
        if input.KeyCode.Name == "Up" then IsPreviewingForward = false end
        if input.KeyCode.Name == "Down" then IsPreviewingBackward = false end
    end
end)
AddConnection(InputEndCon)

local DiedCon = LocalPlayer.Character.Humanoid.Died:Connect(function()
    task.wait(0.1)
    if not IsPaused then TogglePause() end
    LocalPlayer.CharacterAdded:Wait()
    task.wait(0.1)
    if ClonedMap and ClonedMap.Parent then LoadLastSavestate() end
end)
AddConnection(DiedCon)
