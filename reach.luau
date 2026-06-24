local MODE = "Record" 
local TARGET_MAP_NAME = "Sandswept Ruins" -- Exact Case-Sensitive Name
local TARGET_DIFFICULTY_NAME = "Crazy" 

-- ==============================================================================
-- [SINGLE INSTANCE / OVERRIDE LOGIC]
-- ==============================================================================
if getgenv().TomatoConnections then
    print("!!! OVERRIDING PREVIOUS SCRIPT INSTANCE !!!")
    for i, connection in pairs(getgenv().TomatoConnections) do
        if connection then
            pcall(function() connection:Disconnect() end)
        end
    end
    _G.LoopCancel = true
    getgenv().TomatoAutoFarm = false
    task.wait(0.2)
end

getgenv().TomatoConnections = {}
getgenv().IsResettingForDifficulty = false 

local function TrackConnection(connection)
    table.insert(getgenv().TomatoConnections, connection)
    return connection
end

-- ==============================================================================
-- [CONFIGURATION]
-- ==============================================================================

getgenv().TomatoAutoFarm = true

-- ==============================================================================
-- [LOGIC] MODE HANDLER (v4beta BRANCH)
-- ==============================================================================

local function LoadScript(url)
    local success, response = pcall(function() return game:HttpGet(url) end)
    if not success then
        warn("Failed to download script: " .. url)
        return
    end
    
    local func, err = loadstring(response)
    if not func then
        warn("Failed to compile script: " .. tostring(err))
        return
    end
    
    func()
end

local function ExecuteSecondaryScript()
    if MODE == "Record" then
        print("!!! TARGET MAP FOUND - MODE: RECORD - EXECUTING CREATOR SCRIPT !!!")
        LoadScript("https://raw.githubusercontent.com/tomatotxt/Flood-GUI/v4beta/TAS/CREATOR/creator.luau")
    elseif MODE == "Play" then
        print("!!! TARGET MAP FOUND - MODE: PLAY - EXECUTING PLAYER SCRIPT !!!")
        LoadScript("https://raw.githubusercontent.com/tomatotxt/Flood-GUI/v4beta/TAS/PLAYER/newtasplayer.luau")
    else
        warn("INVALID MODE SELECTED! Please set MODE to 'Record' or 'Play'.")
    end
end

-- ==============================================================================
-- [INTERNAL] SETUP & UTILS
-- ==============================================================================

local ALERTS_ENABLED = true
local CurrentlyFarming = false
local Escaped = false

local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = game:GetService("Players").LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Multiplayer = Workspace:WaitForChild("Multiplayer")
local Camera = Workspace.CurrentCamera

local DIFFICULTY_RANKS = {
    ["Easy"] = 1,
    ["Normal"] = 2,
    ["Hard"] = 3,
    ["Insane"] = 4,
    ["Crazy"] = 5,
    ["Crazy+"] = 6
}

-- Remotes
local RemoteFolder = ReplicatedStorage:WaitForChild("Remote")
local ReqPasskey = RemoteFolder:WaitForChild("ReqPasskey")
local NewMapVote = RemoteFolder:WaitForChild("NewMapVote")
local UpdMapVote = RemoteFolder:WaitForChild("UpdMapVote")
local AddedWaiting = RemoteFolder:WaitForChild("AddedWaiting")
local AlertRemote = RemoteFolder:WaitForChild("Alert")

-- Alert Listener (Detects Win via Remote)
TrackConnection(AlertRemote.OnClientEvent:Connect(function(msg)
    if type(msg) == "string" and msg:lower():match("escaped") then
        Escaped = true
    end
end))

-- Anti-AFK
TrackConnection(LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end))

-- Respawn & Rejoin Lift Handler (On Respawn - Specific for Diff Reset)
TrackConnection(LocalPlayer.CharacterAdded:Connect(function(char)
    if getgenv().IsResettingForDifficulty then
        char:WaitForChild("HumanoidRootPart", 10)
        task.wait(0.5) 
        print("Respawned. Attempting to rejoin Lift...")
        AddedWaiting:FireServer()
        getgenv().IsResettingForDifficulty = false
    end
end))

-- Alert System
local Colors = {
    System  = Color3.fromRGB(200, 200, 200), -- Grey/White
    Success = Color3.fromRGB(0, 255, 127),   -- Spring Green
    Warning = Color3.fromRGB(255, 170, 0),   -- Orange
    Error   = Color3.fromRGB(255, 60, 60),   -- Red
    Info    = Color3.fromRGB(0, 220, 255),   -- Cyan
    Item    = Color3.fromRGB(170, 85, 255)   -- Purple
}

local CLMAIN = LocalPlayer.PlayerScripts:WaitForChild("CL_MAIN_GameScript")
local CLMAINenv = getsenv(CLMAIN)
local Alert

if CLMAINenv and CLMAINenv.newAlert then
    Alert = function(Text, ColorType)
        if ALERTS_ENABLED then
            local SelectedColor = Colors[ColorType] or Colors.System
            local Output = tostring(Text)
            pcall(function() 
                CLMAINenv.newAlert(Output, SelectedColor, nil, nil) 
            end)
            print(Output)
        end
    end
else
    Alert = function(Text, ...) print("[CONSOLE] " .. tostring(Text)) end
end

function isRandomString(str)
    if #str == 0 then return false end
    for i = 1, #str do
        local ltr = str:sub(i, i)
        if ltr:lower() == ltr then return false end
    end
    return true
end

local function GetChar()
    return LocalPlayer.Character or (LocalPlayer.CharacterAdded:wait() and LocalPlayer.Character)
end

local function Noclip(Toggle)
    local char = GetChar()
    if char then
        for i, v in pairs(char:GetChildren()) do
            if v.ClassName == "Part" then v.CanCollide = not Toggle end
        end
    end
end

local function Check(Flag)
    local char = GetChar()
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if Flag == "InLift" then
        if hrp.Position.X < 50 and hrp.Position.Z > 70 then return true end
    elseif Flag == "InGame" then
        if hrp.Position.X > 50 then return true end
    end
    return false
end

local function GetRandomPointInPart(Part)
    local Size = Part.Size
    local CFramePos = Part.CFrame
    local Rx = (math.random() - 0.5) * (Size.X * 0.9)
    local Ry = (math.random() - 0.5) * (Size.Y * 0.9)
    local Rz = (math.random() - 0.5) * (Size.Z * 0.9)
    return CFramePos * CFrame.new(Rx, Ry, Rz)
end

local function GetCurrentDifficultyRank()
    local success, result = pcall(function()
        local diffLabel = Workspace.Lobby.GameInfo.SurfaceGui.Frame.Difficulty.Difficulty
        local text = diffLabel.Text
        local splitText = string.split(text, ":")
        local word = splitText[1]
        word = string.gsub(word, "^%s*(.-)%s*$", "%1")
        return word
    end)

    if success and result then
        local rank = DIFFICULTY_RANKS[result]
        return (rank or 0), result
    end
    return 0, "Unknown"
end

-- ==============================================================================
-- [MAIN LOGIC] MAP LOAD & FARM
-- ==============================================================================

local MapDetect
local ConnectMap

local function OnMapLoad(Map)
    CurrentlyFarming = true
    Escaped = false
    
    local HumanoidRootPart = GetChar():WaitForChild("HumanoidRootPart")
    local Humanoid = GetChar():WaitForChild("Humanoid")

    -- 1. DIFFICULTY CHECK LOGIC
    local currentRank, currentName = GetCurrentDifficultyRank()
    local targetRank = DIFFICULTY_RANKS[TARGET_DIFFICULTY_NAME] or 999
    
    print("-------------------------------------------------")
    print("DIFFICULTY CHECK:")
    print("Current: " .. currentName .. " ("..currentRank..")")
    print("Target:  " .. TARGET_DIFFICULTY_NAME .. " ("..targetRank..")")

    if currentRank > targetRank then
        Alert("Difficulty Too High ("..currentName.."). Resetting...", "Error")
        
        repeat task.wait()
            if not HumanoidRootPart or not Humanoid then break end
        until (not HumanoidRootPart.Anchored and Humanoid.WalkSpeed >= 20) or not getgenv().TomatoAutoFarm
        
        if HumanoidRootPart then HumanoidRootPart.CFrame = CFrame.new(1000, 1000, 1000) end
        task.wait(0.25)
        
        getgenv().IsResettingForDifficulty = true 
        Humanoid.Health = 0
        CurrentlyFarming = false
        return 
    elseif currentRank < targetRank then
        Alert("Difficulty Low ("..currentName.."). Farming.", "Warning")
    else
        Alert("Difficulty Correct ("..currentName.."). Farming.", "Success")
    end
    print("-------------------------------------------------")

    -- 2. MAP CONFIG
    local Settings = Map:WaitForChild("Settings", 10)
    if Settings then
        local MapName = Settings:GetAttribute("MapName")
        if MapName then Alert("Map Loaded: " .. MapName, "Info") end
    end

    if Check("InGame") == false then
        Alert("Outside game zone. Standing by...", "Warning")
    end

    local Buttons = {}
    for i, MapObject in pairs(Map:GetDescendants()) do
        if isRandomString(MapObject.Name) and MapObject.ClassName == "Model" then
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

    -- 3. ITEMS
    local LostPage = Map:FindFirstChild("_LostPage", true)
    local Rescue = Map:FindFirstChild("_Rescue", true)
    local OriginalCFrame = HumanoidRootPart.CFrame
    
    if LostPage then
        HumanoidRootPart.CFrame = LostPage.CFrame
        task.wait()
        HumanoidRootPart.CFrame = OriginalCFrame
        Alert("Hidden Page Acquired.", "Item")
    end
    if Rescue then
        HumanoidRootPart.CFrame = Rescue.Contact.CFrame
        task.wait()
        HumanoidRootPart.CFrame = OriginalCFrame
        Alert("Survivor Rescued.", "Item")
    end

    Alert("Sequence Initialized. Scanning...", "System")
    
    local GodMode = Humanoid:GetPropertyChangedSignal("Health"):Connect(function()
        Humanoid.Health = 1000
    end)
    TrackConnection(GodMode)
    
    Noclip(true)
    
    -- 4. FARM LOOP
    while RunService.Heartbeat:Wait() and Check("InGame") and getgenv().TomatoAutoFarm do
        if not CurrentlyFarming then break end 

        local ExitRegion = Map:FindFirstChild("ExitRegion", true)
        local HRP = GetChar():FindFirstChild("HumanoidRootPart")
        if not HRP then break end
        
        local FailedScan = true
        
        if not ExitRegion then
            -- == BUTTON PHASE ==
            if Camera.CameraSubject ~= Humanoid then Camera.CameraSubject = Humanoid end

            HRP.Anchored = true
            for i, Button in pairs(Buttons) do
                if not getgenv().TomatoAutoFarm then break end

                local ButtonHitbox = Button:FindFirstChild("Hitbox")
                if ButtonHitbox then
                    local TouchFound = Button:FindFirstChild("TouchInterest", true)
                    local GuiFound = Button:FindFirstChildWhichIsA("BillboardGui", true)
                    
                    if (TouchFound and GuiFound) then
                        FailedScan = false
                        HRP.Anchored = false
                        HRP.CFrame = CFrame.new(ButtonHitbox.Position - Vector3.new(math.random(), math.random(), math.random()))
                        Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                        task.wait(0.05)
                        Humanoid:ChangeState(Enum.HumanoidStateType.Running)
                        task.wait(0.05)
                    end
                end
            end
            if FailedScan == true then
                RunService.Heartbeat:Wait()
            end
        elseif ExitRegion then
            -- == EXIT PHASE ==
            Noclip(false)
            HRP.Anchored = false
            
            if Camera.CameraSubject ~= ExitRegion then Camera.CameraSubject = ExitRegion end

            if not Escaped then
                local TargetCFrame = GetRandomPointInPart(ExitRegion)
                HRP.CFrame = TargetCFrame
                HRP.Velocity = Vector3.zero
                Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            else
                Escaped = false
                Camera.CameraSubject = Humanoid
                Humanoid:ChangeState(Enum.HumanoidStateType.Dead)
                Alert("Escape Detected. Resetting...", "Success")
                break
            end
        end
    end
    
    if Camera.CameraSubject ~= Humanoid then Camera.CameraSubject = Humanoid end
    Noclip(false)
    Alert("Map Complete.", "System")
    if GodMode then GodMode:Disconnect() end
    
    Alert("Awaiting next match...", "System")
    CurrentlyFarming = false
end

ConnectMap = function()
    MapDetect = Multiplayer.ChildAdded:Connect(function(NewMap)
        NewMap:GetPropertyChangedSignal("Name"):Wait()
        
        if getgenv().TomatoAutoFarm == true then
            OnMapLoad(NewMap)
            Alert("Map Detected. Connecting...", "Info")
        end
    end)
    TrackConnection(MapDetect)
end

-- ==============================================================================
-- [INTEGRATION] VOTE LOGIC
-- ==============================================================================

local function GetSessionKey()
    local success, key = pcall(function() return ReqPasskey:InvokeServer() end)
    if success and key then return -key end
    return nil
end

local function CalculateCost(mapData, myVoteData)
    local currentVoteCount = 0
    local votedMapID = 0
    if myVoteData then
        currentVoteCount = myVoteData.voteCount or 0
        votedMapID = myVoteData.mapID or 0
    end
    if votedMapID == mapData.ID then
        local rawCost = mapData.extraVoteCost + (currentVoteCount - 1) * 10
        return math.clamp(rawCost, 0, 50)
    end
    if mapData.locked == true then return mapData.unlockCost end
    return 0
end

local VoteListener = NewMapVote.OnClientEvent:Connect(function(dataPacket)
    local maps = dataPacket.mapData
    local pVotes = dataPacket.pVotes or {}
    
    if not maps then return end
    local foundTarget = nil

    for _, map in pairs(maps) do
        if map.name == TARGET_MAP_NAME and map.displayMap == true then
            foundTarget = map
            break
        end
    end

    if foundTarget then
        -- 1. CRITICAL CLEANUP: Stop AutoFarm & Loops Immediately
        Alert("!!! TARGET MAP DETECTED !!!", "Success")
        print("Stopping AutoFarm to vote for: " .. TARGET_MAP_NAME)
        
        getgenv().TomatoAutoFarm = false
        CurrentlyFarming = false
        _G.LoopCancel = true -- Kill external loops
        
        -- Disconnect all connections (including this listener) to prevent double execution
        if getgenv().TomatoConnections then
             for i, connection in pairs(getgenv().TomatoConnections) do
                 if connection then pcall(function() connection:Disconnect() end) end
             end
             getgenv().TomatoConnections = {}
        end

        -- 2. VOTE LOGIC
        local remoteKey = GetSessionKey()
        if remoteKey then 
            local myUserId = tostring(LocalPlayer.UserId)
            local myVoteData = pVotes[myUserId]
            local cost = CalculateCost(foundTarget, myVoteData)

            UpdMapVote:FireServer(remoteKey, foundTarget.ID, cost)
            Alert("Vote Sent! Cost: " .. cost, "Success")
        else
            Alert("Vote Failed: No Key", "Error")
        end

        -- 3. LIFT LOGIC: Wait 1 second -> Fire Lift -> Load Script
        Alert("Wait 1s then Rejoin Lift...", "System")
        task.wait(1) 
        
        AddedWaiting:FireServer()
        Alert("Lift Signal Sent. Loading TAS...", "Info")
        
        task.spawn(ExecuteSecondaryScript)
    else
        print("Target map ("..TARGET_MAP_NAME..") not found or not displayed.")
    end
end)

TrackConnection(VoteListener)

-- ==============================================================================
-- [INTERNAL] MAIN LOOPS
-- ==============================================================================

if _G.LoopCancel ~= nil then
    _G.LoopCancel = true
    task.wait(.1)
end
_G.LoopCancel = false
Alert("Ready! Starting AutoFarm.", "Success")

-- Auto Lift Rejoin Logic
task.spawn(function()
    while task.wait(1) do
        if _G.LoopCancel == true then break end
        
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local inLift = Check("InLift")
            local inGame = Check("InGame")

            if not inLift and not inGame and getgenv().TomatoAutoFarm then
                AddedWaiting:FireServer()
            end
        end
    end
end)

-- Main Watchdog
task.spawn(function()
    while task.wait(0.5) do
        if _G.LoopCancel == true then
            -- Silent breakdown, no alert needed as this happens on success
            if MapDetect then MapDetect:Disconnect() end
            break
        end
        
        if not MapDetect then ConnectMap() end

        if getgenv().TomatoAutoFarm == false then
            -- If we are NOT cancelling loops (meaning user paused it manually, not the script winning)
            if _G.LoopCancel == false and CurrentlyFarming then 
                 Alert("Operation suspended by user.", "Warning")
                 repeat task.wait(0.5) until getgenv().TomatoAutoFarm == true or _G.LoopCancel == true
                 
                 if _G.LoopCancel == false then
                    Alert("Operation continued.", "Success")
                 end
            end
        end
    end
end)
