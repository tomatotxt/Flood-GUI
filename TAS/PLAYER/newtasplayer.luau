local INPUT = loadstring(game:HttpGet("https://raw.githubusercontent.com/tomatotxt/-/refs/heads/main/input.luau"))()

local UserInputService = game:GetService("UserInputService")
local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local TimeModifier = 1 -- [CONTROL SPEED HERE] (1 = Normal, 0.5 = 2x Speed, 2 = Slow Motion)
local DynamicTimeScale = 1 -- [MAP EVENT MODIFIER] Dynamically scales speed mid-game
local SwimSmoothness = 0.04 -- [SWIMMING ROTATION SMOOTHING] Lower = Smoother, Higher = Snappier (0.01 - 0.1 recommended)

print("Welcome to the TAS Player! (V65) - Auto-Queue Active")

-- // GLOBAL CLEANUP //
if getgenv().TAS_RestoreAnim then
    pcall(getgenv().TAS_RestoreAnim)
    getgenv().TAS_RestoreAnim = nil
end

if getgenv().TASConnections then
    for _, connection in pairs(getgenv().TASConnections) do
        if connection then connection:Disconnect() end
    end
end
getgenv().TASConnections = {}

local function AddConnection(conn)
    table.insert(getgenv().TASConnections, conn)
    return conn
end

-- // CONFIGURATION //
local SkipMirroredMaps = {
    ["Retro Coast"] = true, ["Zemblanity"] = true, ["Northern Mill"] = true,
    ["Mysterium"] = true, ["Decaying Silo"] = true, ["Active Volcanic Mines"] = true,
    ["Snowy Stronghold"] = true, ["Classic Canyon"] = true
}
local State = getgenv().State
if State and State().HighlightOnlyMaps then
    for _,v in ipairs(State().HighlightOnlyMaps) do SkipMirroredMaps[v] = true end
end

local Mirrored = false
local NewV = Vector3.new
local NewC = CFrame.new
local AngC = CFrame.fromEulerAnglesXYZ
local LP = game.Players.LocalPlayer
local Multi = workspace.Multiplayer
local RS = game:GetService('RunService')
local HttpService = game:GetService("HttpService")

-- // PROFESSIONAL ALERT SYSTEM //
local CLMAIN = getsenv(LP.PlayerScripts:WaitForChild("CL_MAIN_GameScript", 10))

local Theme = {
    System = Color3.fromRGB(150, 150, 255), 
    Info = Color3.fromRGB(220, 220, 220),   
    Success = Color3.fromRGB(80, 220, 120), 
    Warning = Color3.fromRGB(255, 170, 0),  
    Error = Color3.fromRGB(255, 60, 60),    
    Highlight = Color3.fromRGB(0, 200, 255) 
}

local function Log(msg, category)
    local color = Theme[category] or Theme.Info
    local text = "[TAS] " .. msg
    print(text)
    if CLMAIN and type(CLMAIN.newAlert) == "function" then
        CLMAIN.newAlert(text, color)
    end
end

-- // MAP EVENT LISTENER INTEGRATION //
task.spawn(function()
    local PlayerGui = LP:WaitForChild("PlayerGui", 10)
    local GameGui = PlayerGui and PlayerGui:WaitForChild("GameGui", 10)
    local HUD = GameGui and GameGui:WaitForChild("HUD", 10)
    local MapEventInfo = HUD and HUD:WaitForChild("MapEventInfo", 10)

    if MapEventInfo then
        AddConnection(MapEventInfo:GetPropertyChangedSignal("Text"):Connect(function()
            local currentText = MapEventInfo.Text
            local Events = {}
            for rawEventName in string.gmatch(currentText, ">(.-)</font>") do
                local formattedEventName = string.lower(rawEventName):gsub("%s+", "")
                table.insert(Events, formattedEventName)
            end
            
            if #Events > 0 then
                DynamicTimeScale = 1 -- Reset base modifier before recalculating
                for _, eventName in ipairs(Events) do
                    if eventName == "speedup" then
                        DynamicTimeScale = DynamicTimeScale * (1 / 1.1225)
                    elseif eventName == "slowdown" then
                        DynamicTimeScale = DynamicTimeScale * (1 / (1 - 0.1091))
                    end
                end
                
                local speedMultiplier = 1 / DynamicTimeScale
                Log(string.format("Map event! Game speed adjusted to %.2fx", speedMultiplier), "Highlight")
            end
        end))
    end
end)

if not getgenv().alreadystarted then
    Log("Welcome to the TAS Engine! (v65)", "System")
    task.wait(0.1)
    Log("TAS Engine initialized.", "System")
    task.wait(0.1)
    Log("Current speed set to: " .. TimeModifier .. "x", "Highlight")
    getgenv().alreadystarted = true
else
    Log("TAS Engine reloaded! (v65)", "System")
    task.wait(0.15)
    Log("Current speed set to: " .. TimeModifier .. "x", "Highlight")
end

-- // FE2 WATER DETECTION SYSTEM //
local WaterParts = {}

local function CacheWaterParts(MapFolder)
    WaterParts = {}
    local attempts = 0
    repeat
        for _, v in pairs(MapFolder:GetDescendants()) do
            if v:IsA("BasePart") and (string.find(v.Name, "_Water") or v.Parent.Name == "Waters") then
                if not table.find(WaterParts, v) then
                    table.insert(WaterParts, v)
                end
            end
        end
        if #WaterParts == 0 then 
            attempts = attempts + 1
            task.wait(0.5) 
        end
    until #WaterParts > 0 or attempts > 10
    
    if #WaterParts > 0 then
        Log("Found " .. #WaterParts .. " water areas for swimming.", "Success")
    else
        Log("Couldn't find any water areas on this map.", "Error")
    end
end

local function IsInWater(Position)
    for _, water in pairs(WaterParts) do
        local halfSize = water.Size * 0.5
        local objSpace = water.CFrame:PointToObjectSpace(Position)
        if math.abs(objSpace.Y) <= halfSize.Y and math.abs(objSpace.X) <= halfSize.X and math.abs(objSpace.Z) <= halfSize.Z then
            local waterState = water:FindFirstChild("WaterState")
            if not waterState or waterState:GetAttribute("NoSwim") ~= true then
                return true
            end
        end
    end
    return false
end

-- // ANIMATION HELPERS //
if not LP.Character or not LP.Character:FindFirstChild("Animate") then
    LP.CharacterAdded:Wait()
    LP.Character:WaitForChild("Animate", 10)
end

local Animate, OriginalPlayAnim
local SuccessHook, Err = pcall(function()
    local AnimateScript = LP.Character.Animate
    Animate = getsenv(AnimateScript)
    OriginalPlayAnim = Animate.playAnimation
    
    -- Cache function globally so re-executions can restore it BEFORE capturing the empty dummy function
    getgenv().TAS_RestoreAnim = function()
        if Animate and OriginalPlayAnim then
            Animate.playAnimation = OriginalPlayAnim
        end
    end
end)

if not SuccessHook or not Animate then
    Log("Warning: Could not connect to the game's animation system.", "Warning")
    Animate = { setAnimationSpeed = function() end, playAnimation = function() end }
    OriginalPlayAnim = function() end
end

local function toggleSlide(newValue)
    if not LP.Character then return end
    if newValue == true then
        if LP.Character:FindFirstChild("HumanoidRootPart") then LP.Character.HumanoidRootPart.Size = NewV(2, 1, 1) end
        if LP.Character:FindFirstChild("FE2_Hitbox") then LP.Character.FE2_Hitbox.Size = NewV(2, 1, 1) end
        if LP.Character:FindFirstChild("Humanoid") then LP.Character.Humanoid.HipHeight = -1.5 end
    else
        if LP.Character:FindFirstChild("HumanoidRootPart") then LP.Character.HumanoidRootPart.Size = NewV(2, 2, 1) end
        if LP.Character:FindFirstChild("FE2_Hitbox") then LP.Character.FE2_Hitbox.Size = NewV(2, 2, 1) end
        if LP.Character:FindFirstChild("Humanoid") then LP.Character.Humanoid.HipHeight = 0 end
    end
    if LP.Character and LP.Character:FindFirstChild("Animate") and LP.Character.Animate:FindFirstChild("Sliding") then
        LP.Character.Animate.Sliding:Fire(newValue)
    end
end

getgenv().IsTASPlaying = true 
getgenv().TASCurrentMoveDir = Vector3.new(0,0,0) 

-- Prevent multi-execution HookMetamethod lag leaks
if not getgenv().TASHookApplied then
    getgenv().TASHookApplied = true
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", function(self, key)
        if getgenv().IsTASPlaying and key == "MoveDirection" then
            if self:IsA("Humanoid") and self.Parent == LP.Character then
                return getgenv().TASCurrentMoveDir
            end
        end
        return oldIndex(self, key)
    end)
end

-- // SLIDING & ZIPLINE CONFIGURATION //
local LastPlayedAnim = nil
local IsSliding = false
local SlideStartTime = 0
local LastSlideEndTime = -3.0
local SLIDE_DEBOUNCE = 3.0
local IsCurrentlySwimming = false
local IsCurrentlyZiplining = false

-- Manual Key Holding Overrides
local IsManualZipline = false
local IsManualSlide = false

-- // CLEANUP & AUTO-QUEUE //
local LiftCheckPos = Vector3.new(-25, -144, 139)
local CleanedUp = false
local function Cleanup(resetCharacter)
    if CleanedUp then return end
    CleanedUp = true
    getgenv().IsTASPlaying = false
    
    -- Reset state variables on cleanup
    IsSliding = false
    SlideStartTime = 0
    LastSlideEndTime = -3.0
    IsCurrentlyZiplining = false
    IsManualZipline = false
    IsManualSlide = false

    -- Clean up GUI
    local playerGui = LP:FindFirstChild("PlayerGui")
    if playerGui then
        local oldGui = playerGui:FindFirstChild("TAS_GUI")
        if oldGui then oldGui:Destroy() end
    end
    
    if getgenv().TASConnections then
        for _, connection in pairs(getgenv().TASConnections) do
            if connection then connection:Disconnect() end
        end
        getgenv().TASConnections = {}
    end

    if getgenv().TAS_RestoreAnim then
        pcall(getgenv().TAS_RestoreAnim)
        getgenv().TAS_RestoreAnim = nil
    end

    if LP.Character then
        if LP.Character:FindFirstChild("Animate") and LP.Character.Animate:FindFirstChild("ToggleSwim") then
            pcall(function() LP.Character.Animate.ToggleSwim:Fire(false) end)
        end
        if LP.Character:FindFirstChild("Humanoid") then LP.Character.Humanoid.AutoRotate = true end
        toggleSlide(false)
    end

    if resetCharacter and LP.Character and LP.Character:FindFirstChild("Humanoid") then
        Log("You reset or died. Halting the run and re-queuing...", "Error")
        LP.Character.Humanoid.Health = 0
        
        task.spawn(function()
            local newChar = LP.CharacterAdded:Wait()
            local newRoot = newChar:WaitForChild("HumanoidRootPart", 10)
            local Remote = game:GetService("ReplicatedStorage"):WaitForChild("Remote"):WaitForChild("AddedWaiting")
            
            while newChar and newChar.Parent and newRoot do
                local dist = (newRoot.Position - LiftCheckPos).Magnitude
                if dist <= 30 then
                    print("[TAS] Entered lift. Waiting for map to load...")
                    break
                end
                
                Remote:FireServer()
                task.wait(0.5)
            end
        end)
    end
end

-- // RESET & REMOVAL SAFETY INJECTION //
if LP.Character and LP.Character:FindFirstChild("Humanoid") then
    AddConnection(LP.Character.Humanoid.Died:Connect(function() Cleanup(false) end))
end
AddConnection(LP.CharacterRemoving:Connect(function() Cleanup(false) end))


-- // SMART START LOGIC //
local Map = nil

while not Map and not CleanedUp do
    local ConditionsMet = false
    Log("Waiting for you to step into the lift...", "Warning")
    
    -- Loop 1: Wait for you to step inside
    repeat
        task.wait(0.2)
        local Root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if Root then
            local Dist = (Root.Position - LiftCheckPos).Magnitude
            if Dist <= 30 or Dist > 800 then ConditionsMet = true end
        end
    until ConditionsMet or CleanedUp
    
    if CleanedUp then return end
    Log("Lift entered! Waiting for the map to load.", "System")
    
    -- Loop 2: Wait for map, BUT constantly check if you leave the lift
    while ConditionsMet and not Map and not CleanedUp do
        task.wait(0.1)
        
        local FoundMap = Multi:FindFirstChild("NewMap")
        if FoundMap then 
            Map = FoundMap
            break 
        end
        
        -- Check distance again to see if you left
        local Root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if Root then
            local Dist = (Root.Position - LiftCheckPos).Magnitude
            -- If you are farther than 30 studs, but NOT teleported to a map (>800)
            if Dist > 30 and Dist < 800 then
                Log("You left the lift! Pausing until you return.", "Warning")
                ConditionsMet = false -- This breaks the loop and goes back to "Waiting..."
            end
        end
    end
end

if CleanedUp or not Map then return end

-- // TAS EXECUTION //
local realMapName = Map:WaitForChild('Settings'):GetAttribute("MapName")
local mapName = HttpService:UrlEncode(realMapName)

local success, path
if isfolder("Flood-GUI") and isfolder("Flood-GUI/TAS FILES") then
    local TargetTASPath = "Flood-GUI/TAS FILES/" .. realMapName .. ".json"
    if isfile(TargetTASPath) then path = readfile(TargetTASPath); success = true end
end

if not path then
    success, path = pcall(function()
        return game:HttpGet("https://raw.githubusercontent.com/tomatotxt/Flood-GUI/refs/heads/testing/TAS%20FILES/".. mapName .. ".json")
    end)
end

if not success or #path < 50 then
    Log("Oops! We don't have a TAS file for '".. realMapName .."'.", "Error")
    Cleanup(true)
    return
end

local TAS
local DecodeSuccess, _ = pcall(function() TAS = HttpService:JSONDecode(path) end)
if not TAS or not DecodeSuccess then
    Log("Uh oh, the TAS file for this map seems corrupted.", "Error")
    Cleanup(true)
    return
end

local OriginalFrameCount = #TAS
Log("Loaded run for " .. realMapName .. " (" .. OriginalFrameCount .. " frames).", "Info")
repeat task.wait() until Map.Name == "Map" or CleanedUp
if CleanedUp then return end

local SpawnPoint = nil
for _,v in ipairs(Map:GetChildren()) do
    if v.Name == "Part" then
        local c; c = v:GetPropertyChangedSignal("Rotation"):Connect(function() c:Disconnect(); SpawnPoint = v end)
    end
end

local t = 0
repeat task.wait(0.1); t=t+0.1; if not SpawnPoint then SpawnPoint = Map:FindFirstChild("Spawn", true) end
until SpawnPoint or t > 10 or CleanedUp

if not SpawnPoint then Log("Hmm, couldn't find where to spawn on this map.", "Error") Cleanup(true) return end

-- // MAP PRE-PROCESSING & BUTTON HITBOX EXPANDER //
CacheWaterParts(Map)

for _, v in ipairs(Map:GetDescendants()) do
    if v.Name == 'ButtonIcon' then
        pcall(function()
            local btnModel = v:FindFirstAncestorOfClass("Model") or v.Parent
            if btnModel then
                for _, p in ipairs(btnModel:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.Size = NewV(8, 8, 8)
                        p.Transparency = 1
                    end
                end
            end
        end)
    end
end
Log("Map buttons and elements processed.", "Success")

task.wait(0.1)
Log("Starting the run! Sit back and relax.", "Success")

local RootPart = LP.Character:WaitForChild("HumanoidRootPart", 10)
local Humanoid = LP.Character:WaitForChild("Humanoid", 10)

while (RootPart.Anchored == true) or (Humanoid.WalkSpeed <= 0) do
    if CleanedUp then return end
    task.wait()
end

if LP.Character and LP.Character:FindFirstChild("Humanoid") then
    LP.Character.Humanoid.AutoRotate = false
end

Animate.playAnimation = function() end

local function activateAnimation(AnimData, Elapsed)
    local character = LP.Character
    if not character or not character.Parent then return end
    local head = character:FindFirstChild("Head")
    local humanoid = character:FindFirstChild("Humanoid")
    if not head or not humanoid or not RootPart then return end

    -- Safe fallbacks for missing/nil AnimData values
    local n = AnimData and AnimData[1] or nil
    local animTime = AnimData and AnimData[2] or 0.1
    Elapsed = Elapsed or 0

    local checkSubmerged = IsInWater(RootPart.Position + Vector3.new(0, 1, 0))

    -- Native-Derived Scaling Slide Duration
    local gameSpeedMultiplier = TimeModifier * DynamicTimeScale
    local nativeSlideDuration = 0.5 / gameSpeedMultiplier

    -- MANUAL KEY OVERRIDES (Z = Zipline/Swing, S = Slide)
    if IsManualZipline then
        n = "swing"
        IsCurrentlyZiplining = true
        if IsSliding then
            toggleSlide(false)
            IsSliding = false
        end
    elseif IsManualSlide then
        n = "slide"
        IsSliding = true
    end

    -- Zipline/Swing Priority State Manager (Highest Priority, Overrides Slide)
    if n == "zipline" or n == "swing" then
        n = "swing" -- Normalise animation name to FE2's "swing"
        IsCurrentlyZiplining = true
        if IsSliding then
            toggleSlide(false)
            IsSliding = false
            LastSlideEndTime = Elapsed
        end
    end

    -- Exit zipline state strictly when landing on solid ground (unless manual zipline key held)
    if humanoid.FloorMaterial ~= Enum.Material.Air and not IsManualZipline then
        IsCurrentlyZiplining = false
    end

    -- 1. ABSOLUTE PRIORITY SLIDE LOCK (Guarantees exactly nativeSlideDuration, unless overridden by Zipline or Manual Slide)
    if IsSliding then
        if not IsManualSlide and (Elapsed - SlideStartTime >= nativeSlideDuration) then
            toggleSlide(false)
            IsSliding = false
            LastSlideEndTime = Elapsed
            -- Safely transition to correct post-slide state
            if checkSubmerged then
                IsCurrentlySwimming = true
                if character.Animate:FindFirstChild("ToggleSwim") then
                    pcall(function() character.Animate.ToggleSwim:Fire(true) end)
                end
                if RootPart.Velocity.Magnitude > 1.5 then n = "swim" else n = "swimidle" end
            else
                IsCurrentlySwimming = false
                if character.Animate:FindFirstChild("ToggleSwim") then
                    pcall(function() character.Animate.ToggleSwim:Fire(false) end)
                end
                if humanoid.FloorMaterial == Enum.Material.Air then
                    n = "fall"
                elseif RootPart.Velocity.Magnitude > 1 then
                    n = "walk"
                else
                    n = "idle"
                end
            end
        else
            n = "slide"
        end
    else
        -- 2. NORMAL ENVIRONMENT & PHYSICS STATES (When not sliding)
        if checkSubmerged then
            IsCurrentlySwimming = true
            if RootPart.Velocity.Magnitude > 1.5 then n = "swim" else n = "swimidle" end
            if character.Animate:FindFirstChild("ToggleSwim") then
                pcall(function() character.Animate.ToggleSwim:Fire(true) end)
            end
        else
            IsCurrentlySwimming = false
            if character.Animate:FindFirstChild("ToggleSwim") then
                pcall(function() character.Animate.ToggleSwim:Fire(false) end)
            end

            if not IsCurrentlyZiplining then
                if n == "slide" then
                    -- Only allow slide initiation if debounce is cleared, Y velocity is stable, AND grounded (or manually forced)
                    local absYVel = math.abs(RootPart.Velocity.Y)
                    if IsManualSlide or (Elapsed - LastSlideEndTime >= SLIDE_DEBOUNCE and absYVel <= 3 and humanoid.FloorMaterial ~= Enum.Material.Air) then
                        toggleSlide(true)
                        IsSliding = true
                        SlideStartTime = Elapsed
                        n = "slide"
                    else
                        -- Debounce active, vertical velocity outside limits, or in air; fallback
                        if humanoid.FloorMaterial == Enum.Material.Air then
                            n = "fall"
                        elseif RootPart.Velocity.Magnitude > 1 then
                            n = "walk"
                        else
                            n = "idle"
                        end
                    end
                end
            end

            -- PASSIVE EXIT: If there is no new animation data and we are NOT sliding, do not override
            if not AnimData and not IsSliding and not IsManualZipline and not IsManualSlide then
                return
            end

            -- General physics/movement fallbacks
            if not IsSliding and not IsCurrentlyZiplining then
                if humanoid:GetState() == Enum.HumanoidStateType.Physics then n = "swing" end
                if n == "idle" or not n then
                    if RootPart.Velocity.Magnitude > 1 then
                        if humanoid.FloorMaterial ~= Enum.Material.Air then n = "walk" else n = "fall" end
                    else
                        n = "idle"
                    end
                end
                if n == "fall" and RootPart.Velocity.Magnitude < 0.1 then n = "swing" end
            end
        end
    end

    if n and (n ~= LastPlayedAnim) then
        Animate.playAnimation = function() end
        pcall(function() OriginalPlayAnim(n, animTime, humanoid) end)
        if n == "walk" then pcall(function() Animate.setAnimationSpeed(.76) end) end
        LastPlayedAnim = n
    end
end

local Offset = SpawnPoint.Position - NewV(0, 1000, 0)
local OldFrame = 3
local RenderedFrames = 0
local FinishedRun = false

-- // SLIDING TRACKING VARIABLES //
local SmoothSwimDirection = nil

-- // PHYSICS LOOP SETUP //
local VisualElapsed = 0
local LastClock = os.clock()

local PAUSED = false

-- // SPEED CONTROL & PAUSE SYSTEM //
local function AdjustSpeed(step)
    TimeModifier = math.clamp(math.round((TimeModifier + step) * 100) / 100, 0.05, 10)
    
    local baseSpeed = math.round((1 / TimeModifier) * 100) / 100
    local totalSpeed = math.round((1 / (TimeModifier * DynamicTimeScale)) * 100) / 100
    
    local actionText = (step < 0) and "Increased" or "Decreased"
    local category = (step < 0) and "Success" or "Warning"
    
    Log(string.format("Speed %s! Base: %.2fx | Total: %.2fx (Modifier: %.2f)", 
        actionText, baseSpeed, totalSpeed, TimeModifier), category)
end

-- Key bindings via INPUT library
local upKey = INPUT["Up"]
if upKey and upKey.Pressed then
    AddConnection(upKey.Pressed:Connect(function()
        AdjustSpeed(-0.05) -- UP Arrow: Speeds up playback
    end))
end

local downKey = INPUT["Down"]
if downKey and downKey.Pressed then
    AddConnection(downKey.Pressed:Connect(function()
        AdjustSpeed(0.05) -- DOWN Arrow: Slows down playback
    end))
end

-- MANUAL HOLD CONTROL: Key Z (Zipline / Swing)
local zKey = INPUT["Z"]
if zKey then
    AddConnection(zKey.Pressed:Connect(function()
        IsManualZipline = true
        IsCurrentlyZiplining = true
        toggleSlide(false)
        IsSliding = false
        LastPlayedAnim = nil -- Instantly triggers swing animation
    end))
    AddConnection(zKey.Released:Connect(function()
        IsManualZipline = false
        IsCurrentlyZiplining = false
        LastPlayedAnim = nil
    end))
end

-- MANUAL HOLD CONTROL: Key S (Slide)
local sKey = INPUT["S"]
if sKey then
    AddConnection(sKey.Pressed:Connect(function()
        IsManualSlide = true
        toggleSlide(true)
        IsSliding = true
        LastPlayedAnim = nil
    end))
    AddConnection(sKey.Released:Connect(function()
        IsManualSlide = false
        toggleSlide(false)
        IsSliding = false
        LastPlayedAnim = nil
    end))
end

local function TriggerPauseToggle()
    task.spawn(function()
        repeat task.wait() until Humanoid and Humanoid.FloorMaterial ~= Enum.Material.Air
        PAUSED = not PAUSED
        if PAUSED then
            pcall(function() OriginalPlayAnim("idle", 0.1, Humanoid) end)
            LastPlayedAnim = "idle"
            Log("TAS Paused (Grounded)", "Warning")
        else
            LastClock = os.clock()
            Log("TAS Resumed", "Success")
        end
    end)
end

local function HandlePause()
    TriggerPauseToggle()
    INPUT["P"].Pressed:Once(HandlePause)
end
INPUT["P"].Pressed:Once(HandlePause)

-- // DYNAMIC GUI (MOBILE TOUCH CONTROLS & PC KEYBIND GUIDE) //
local function SetupGUI()
    local PlayerGui = LP:WaitForChild("PlayerGui", 10)
    if not PlayerGui then return end

    local oldGui = PlayerGui:FindFirstChild("TAS_GUI")
    if oldGui then oldGui:Destroy() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "TAS_GUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = PlayerGui

    if IsMobile then
        -- MOBILE CONTROLS FRAME
        local MobileFrame = Instance.new("Frame")
        MobileFrame.Name = "MobileControls"
        MobileFrame.Size = UDim2.new(0, 160, 0, 160)
        MobileFrame.Position = UDim2.new(0.02, 0, 0.35, 0)
        MobileFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
        MobileFrame.BackgroundTransparency = 0.35
        MobileFrame.BorderSizePixel = 0
        MobileFrame.Parent = ScreenGui

        local UICorner = Instance.new("UICorner", MobileFrame)
        UICorner.CornerRadius = UDim.new(0, 10)

        local UIListLayout = Instance.new("UIListLayout", MobileFrame)
        UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        UIListLayout.Padding = UDim.new(0, 8)
        UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center

        local function CreateMobileButton(name, text, color)
            local btn = Instance.new("TextButton")
            btn.Name = name
            btn.Size = UDim2.new(0.88, 0, 0, 40)
            btn.BackgroundColor3 = color
            btn.Text = text
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Font = Enum.Font.SourceSansBold
            btn.TextSize = 15
            btn.AutoButtonColor = true
            btn.Parent = MobileFrame

            local btnCorner = Instance.new("UICorner", btn)
            btnCorner.CornerRadius = UDim.new(0, 8)
            return btn
        end

        local pauseBtn = CreateMobileButton("PauseBtn", "Pause / Resume", Color3.fromRGB(210, 130, 30))
        local ziplineBtn = CreateMobileButton("ZiplineBtn", "Hold: Zipline", Color3.fromRGB(0, 150, 220))
        local slideBtn = CreateMobileButton("SlideBtn", "Hold: Slide", Color3.fromRGB(60, 170, 90))

        -- Pause Button Trigger
        pauseBtn.MouseButton1Click:Connect(function()
            TriggerPauseToggle()
        end)

        -- Zipline Button Touch Events
        ziplineBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                IsManualZipline = true
                IsCurrentlyZiplining = true
                toggleSlide(false)
                IsSliding = false
                LastPlayedAnim = nil
                ziplineBtn.BackgroundColor3 = Color3.fromRGB(0, 210, 255)
            end
        end)
        ziplineBtn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                IsManualZipline = false
                IsCurrentlyZiplining = false
                LastPlayedAnim = nil
                ziplineBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 220)
            end
        end)

        -- Slide Button Touch Events
        slideBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                IsManualSlide = true
                toggleSlide(true)
                IsSliding = true
                LastPlayedAnim = nil
                slideBtn.BackgroundColor3 = Color3.fromRGB(90, 220, 110)
            end
        end)
        slideBtn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                IsManualSlide = false
                toggleSlide(false)
                IsSliding = false
                LastPlayedAnim = nil
                slideBtn.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
            end
        end)
    else
        -- PC KEYBIND GUIDE FRAME
        local GuideFrame = Instance.new("Frame")
        GuideFrame.Name = "PCGuide"
        GuideFrame.Size = UDim2.new(0, 220, 0, 150)
        GuideFrame.Position = UDim2.new(0.015, 0, 0.35, 0)
        GuideFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
        GuideFrame.BackgroundTransparency = 0.25
        GuideFrame.BorderSizePixel = 0
        GuideFrame.Parent = ScreenGui

        local UICorner = Instance.new("UICorner", GuideFrame)
        UICorner.CornerRadius = UDim.new(0, 8)

        local Title = Instance.new("TextLabel")
        Title.Size = UDim2.new(1, 0, 0, 28)
        Title.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
        Title.BackgroundTransparency = 0.2
        Title.Text = "  TAS Keybind Controls"
        Title.TextColor3 = Color3.fromRGB(0, 200, 255)
        Title.Font = Enum.Font.SourceSansBold
        Title.TextSize = 15
        Title.TextXAlignment = Enum.TextXAlignment.Left
        Title.Parent = GuideFrame

        local TitleCorner = Instance.new("UICorner", Title)
        TitleCorner.CornerRadius = UDim.new(0, 8)

        local GuideText = Instance.new("TextLabel")
        GuideText.Size = UDim2.new(0.9, 0, 0.75, 0)
        GuideText.Position = UDim2.new(0.05, 0, 0.23, 0)
        GuideText.BackgroundTransparency = 1
        GuideText.Text = "[P] - Pause / Resume (Grounded)\n[Up Arrow] - Speed Up (+0.05)\n[Down Arrow] - Speed Down (-0.05)\n[Z] (Hold) - Force Zipline / Swing\n[S] (Hold) - Force Slide"
        GuideText.TextColor3 = Color3.fromRGB(220, 220, 220)
        GuideText.Font = Enum.Font.SourceSans
        GuideText.TextSize = 14
        GuideText.TextYAlignment = Enum.TextYAlignment.Top
        GuideText.TextXAlignment = Enum.TextXAlignment.Left
        GuideText.Parent = GuideFrame
    end
end

SetupGUI()

local MainLoop
MainLoop = RS.Heartbeat:Connect(function()
    if not RootPart or not RootPart.Parent or not Humanoid or not Humanoid.Parent or CleanedUp then 
        if MainLoop then MainLoop:Disconnect() end
        if not CleanedUp then
            Log("Player removed from game. Halting the run.", "Warning")
            Cleanup(false) 
        end
        return 
    end

    -- Keep LastClock updated continuously even while paused
    local CurrentClock = os.clock()
    local Delta = CurrentClock - LastClock
    LastClock = CurrentClock

    -- WHILE PAUSED: Keep velocity strictly at Vector3.zero without anchoring
    if PAUSED == true then
        RootPart.Velocity = Vector3.zero
        RootPart.AssemblyLinearVelocity = Vector3.zero
        RootPart.AssemblyAngularVelocity = Vector3.zero
        return
    end

    -- PLAYBACK ACTIVE: Guarantee player is UNANCHORED
    RootPart.Anchored = false

    RenderedFrames = RenderedFrames + 1
    
    VisualElapsed = VisualElapsed + (Delta * (1 / (TimeModifier * DynamicTimeScale)))
    
    local liveWeld = RootPart:FindFirstChild("WalljumpWeld_Live")
    if liveWeld then liveWeld:Destroy() end
    local serverWeld = RootPart:FindFirstChild("WalljumpWeld_Server")
    if serverWeld then serverWeld:Destroy() end

    Humanoid.Health = 99999
    
    while OldFrame < #TAS and TAS[OldFrame + 1].time <= VisualElapsed do OldFrame = OldFrame + 1 end
    
    if OldFrame >= #TAS then
        if not FinishedRun then
            FinishedRun = true
            Log("Run completed successfully! Awesome.", "Success")
            if getgenv().TAS_RestoreAnim then 
                pcall(getgenv().TAS_RestoreAnim)
                getgenv().TAS_RestoreAnim = nil
            end
            pcall(function() OriginalPlayAnim("idle", 0.1, Humanoid) end)
            Cleanup(false) 
        end
        return
    end

    local FA = TAS[OldFrame]
    local FB = TAS[OldFrame + 1] or FA
    
    local Dur = FB.time - FA.time
    local Alpha = (Dur > 0) and math.clamp((VisualElapsed - FA.time) / Dur, 0, 1) or 0

    local cfA = NewC(FA.CCFrame[1], FA.CCFrame[2], FA.CCFrame[3]) * AngC(FA.CCFrame[4], FA.CCFrame[5], FA.CCFrame[6])
    local cfB = NewC(FB.CCFrame[1], FB.CCFrame[2], FB.CCFrame[3]) * AngC(FB.CCFrame[4], FB.CCFrame[5], FB.CCFrame[6])
    
    local vA = NewV(FA.VVelocity[1], FA.VVelocity[2], FA.VVelocity[3])
    local vB = NewV(FB.VVelocity[1], FB.VVelocity[2], FB.VVelocity[3])

    -- High frame rate interpolation between frames
    local TargetVelocity = vA:Lerp(vB, Alpha)
    getgenv().TASCurrentMoveDir = TargetVelocity.Magnitude > 0 and TargetVelocity.Unit or Vector3.zero

    local TargetCFrame = cfA:Lerp(cfB, Alpha) + Offset
    
    -- Lax Physical "Legs in ground" Detection (Head-Level Cast)
    local OverrideToSlide = false
    local startPos = TargetCFrame.Position + Vector3.new(0, 1.5, 0) -- Starts exactly at head level to clear floor geometry and avoid roof hits
    local direction = Vector3.new(0, -4.5, 0) -- Projects downward past the feet
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = { LP.Character }
    
    local result = workspace:Raycast(startPos, direction, raycastParams)
    if result then
        local hitY = result.Position.Y
        local gap = TargetCFrame.Position.Y - hitY
        
        -- High-sensitivity gap threshold. Trigger only if legs are sinking and character is grounded (not in mid-air).
        if gap < 1.7 and Humanoid.FloorMaterial ~= Enum.Material.Air then
            -- Verify vertical velocity corresponds with sliding physics.
            if TargetVelocity.Y <= 3 then
                OverrideToSlide = true
            end
        end
    end

    -- Swimming Rotation Smoothing vs Raw Foot Movement application
    if IsCurrentlySwimming and TargetVelocity.Magnitude > 0.5 then
        if not SmoothSwimDirection then
            SmoothSwimDirection = TargetVelocity.Unit
        else
            SmoothSwimDirection = SmoothSwimDirection:Lerp(TargetVelocity.Unit, SwimSmoothness).Unit
        end
        RootPart.CFrame = NewC(TargetCFrame.Position, TargetCFrame.Position + SmoothSwimDirection)
    else
        SmoothSwimDirection = nil -- Reset when not swimming or stationary
        RootPart.CFrame = TargetCFrame
    end
    
    RootPart.Velocity = TargetVelocity

    local AnimData = FA.AAnimation
    -- Block heuristic slide overrides if we are currently ziplining or if the animation is explicitly a zipline/swing
    if OverrideToSlide and not IsCurrentlyZiplining and (not AnimData or (AnimData[1] ~= "zipline" and AnimData[1] ~= "swing")) then
        AnimData = { "slide", 0.1 }
    end

    pcall(activateAnimation, AnimData, VisualElapsed)
end)
AddConnection(MainLoop)
