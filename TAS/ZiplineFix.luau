-- Helper references for executors
local getupvalue = debug.getupvalue or getupvalue
local setupvalue = debug.setupvalue or setupvalue

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Global debounce state
local ziplineActive = false

-- Helper to calculate the two world-space endpoints of any part along its longest axis
local function getEndpoints(part)
    local size = part.Size
    local cf = part.CFrame
    
    local halfLength = math.max(size.X, size.Y, size.Z) / 2
    local axis
    if size.X >= size.Y and size.X >= size.Z then
        axis = cf.RightVector
    elseif size.Y >= size.X and size.Y >= size.Z then
        axis = cf.UpVector
    else
        axis = cf.LookVector
    end
    
    local p1 = cf.Position + axis * halfLength
    local p2 = cf.Position - axis * halfLength
    return p1, p2
end

-- Helper to subdivide the chain of nodes into a dense, smooth path for the game's engine
local function subdividePath(nodes, totalSubdivisions)
    totalSubdivisions = totalSubdivisions or 150
    local path = {}
    
    local totalDistance = 0
    local segmentLengths = {}
    for i = 1, #nodes - 1 do
        local dist = (nodes[i+1] - nodes[i]).Magnitude
        segmentLengths[i] = dist
        totalDistance = totalDistance + dist
    end
    
    for i = 0, totalSubdivisions do
        local targetDistance = (i / totalSubdivisions) * totalDistance
        local accumulatedDistance = 0
        local point = nodes[#nodes]
        
        for j = 1, #nodes - 1 do
            local segLength = segmentLengths[j]
            if accumulatedDistance + segLength >= targetDistance then
                local segmentRatio = (targetDistance - accumulatedDistance) / segLength
                point = nodes[j]:Lerp(nodes[j+1], segmentRatio)
                break
            end
            accumulatedDistance = accumulatedDistance + segLength
        end
        table.insert(path, point)
    end
    
    return path, totalDistance
end

-- Safely searches up the workspace tree to find if a touched part belongs to a RopeModel
local function findRopeModel(part)
    local current = part
    while current and current ~= workspace do
        if current:IsA("Model") then
            if current.Name == "RopeModel" or (current:FindFirstChild("RopeStart") and current:FindFirstChild("Visual")) then
                return current
            end
        end
        current = current.Parent
    end
    return nil
end

local function ZiplineTo(RopeModel)
    -- Enforce immediate synchronous debounce check
    if ziplineActive then return end
    ziplineActive = true
    
    -- Reset debounce after exactly 0.1 seconds
    task.delay(0.1, function()
        ziplineActive = false
    end)
    
    -- 1. Validation checks
    if not RopeModel or not RopeModel:IsA("Model") then
        return
    end
    
    local ropeStart = RopeModel:FindFirstChild("RopeStart")
    local visualFolder = RopeModel:FindFirstChild("Visual")
    if not ropeStart or not visualFolder then
        warn("RopeModel is missing 'RopeStart' or 'Visual' container.")
        return
    end
    
    -- 2. Trace and sort the unnamed segments geometrically
    local origin = ropeStart.Position
    local unvisited = {}
    for _, child in ipairs(visualFolder:GetChildren()) do
        if child:IsA("BasePart") then
            table.insert(unvisited, child)
        end
    end
    
    local nodes = { origin }
    local currentPoint = origin
    
    while #unvisited > 0 do
        local closestPart = nil
        local minDistance = math.huge
        local closestIdx = nil
        
        for i, part in ipairs(unvisited) do
            local dist = (part.Position - currentPoint).Magnitude
            if dist < minDistance then
                minDistance = dist
                closestPart = part
                closestIdx = i
            end
        end
        
        if not closestPart then break end
        table.remove(unvisited, closestIdx)
        
        local p1, p2 = getEndpoints(closestPart)
        local dist1 = (p1 - currentPoint).Magnitude
        local dist2 = (p2 - currentPoint).Magnitude
        local farPoint = dist1 < dist2 and p2 or p1
        
        table.insert(nodes, farPoint)
        currentPoint = farPoint
    end
    
    if #nodes < 2 then
        warn("No visual segments found inside RopeModel.Visual.")
        return
    end
    
    local densePositions, totalDistance = subdividePath(nodes, 150)

    -- 3. Extract attributes from the RopeModel (with standard fallbacks)
    local speed = RopeModel:GetAttribute("RopeSpeed") or 120
    local velocityInheritance = RopeModel:GetAttribute("VelocityInheritance") or 0
    local inheritanceDuration = RopeModel:GetAttribute("InheritanceDuration") or 0.5

    -- 4. Locate player character environment and startZipline
    local Character = LocalPlayer.Character
    if not Character then return end
    
    local FE2_Character = Character:FindFirstChild("FE2_Character")
    if not FE2_Character then return end
    
    local FE2Env = getsenv(FE2_Character)
    local startZipline = FE2Env.startZipline
    if not startZipline then return end

    -- Check if player is already ziplining (v15 is the first upvalue of startZipline)
    local activeCheckSuccess, activeCheckName, isCurrentlyZiplining = pcall(getupvalue, startZipline, 1)
    if activeCheckSuccess and isCurrentlyZiplining == true then
        return -- Already actively riding, cancel setup to prevent duplicate models
    end

    -- 5. Locate ropes table (upvalue "v16") safely
    local ropeTableIndex = nil
    for i = 1, 50 do
        local success, name, val = pcall(getupvalue, startZipline, i)
        if not success then break end
        if name == "v16" then
            ropeTableIndex = i
            break
        end
    end
    ropeTableIndex = ropeTableIndex or 2

    local success, name, ropesTable = pcall(getupvalue, startZipline, ropeTableIndex)
    if not success then return end

    if ropesTable == nil then
        ropesTable = {}
        pcall(setupvalue, startZipline, ropeTableIndex, ropesTable)
    end

    -- 6. Inject the custom path
    local mockRope = {
        positions = densePositions,
        length = totalDistance
    }
    table.insert(ropesTable, mockRope)
    pcall(setupvalue, startZipline, ropeTableIndex, ropesTable)

    -- 7. Create temporary simulation components matching RopeModel's configurations
    local tempModel = Instance.new("Model")
    tempModel.Name = "TempZiplineModel"
    tempModel:SetAttribute("RopeSpeed", speed)
    tempModel:SetAttribute("VelocityInheritance", velocityInheritance)
    tempModel:SetAttribute("InheritanceDuration", inheritanceDuration)
    tempModel.Parent = workspace

    local tempPart = Instance.new("Part")
    tempPart.Name = "RopeStart"
    tempPart.Anchored = true
    tempPart.CanCollide = false
    tempPart.Transparency = 1
    tempPart.Position = origin
    tempPart.Parent = tempModel

    -- 8. Run the zipline playback
    task.spawn(function()
        startZipline(tempPart)
    end)

    -- 9. Scheduled clean-up (Runs independently of the debounce)
    local travelDuration = (totalDistance / speed) + 2.0
    task.delay(travelDuration, function()
        if tempModel then 
            tempModel:Destroy() 
        end
        for i, rope in ipairs(ropesTable) do
            if rope == mockRope then
                table.remove(ropesTable, i)
                pcall(setupvalue, startZipline, ropeTableIndex, ropesTable)
                break
            end
        end
    end)
end

-- ==========================================================
-- AUTOMATIC COLLISION DETECTION & RESPAWN MONITOR
-- ==========================================================
local activeConnections = {}

local function setupCharacterTouchDetection(character)
    for _, conn in ipairs(activeConnections) do
        conn:Disconnect()
    end
    activeConnections = {}
    
    ziplineActive = false
    
    local humanoid = character:WaitForChild("Humanoid", 5)
    if humanoid then
        local deathConn = humanoid.Died:Connect(function()
            ziplineActive = false
        end)
        table.insert(activeConnections, deathConn)
    end

    local function bindPart(part)
        if part:IsA("BasePart") then
            local touchConn = part.Touched:Connect(function(hit)
                if ziplineActive then return end
                
                local ropeModel = findRopeModel(hit)
                if ropeModel then
                    ZiplineTo(ropeModel)
                end
            end)
            table.insert(activeConnections, touchConn)
        end
    end

    for _, child in ipairs(character:GetChildren()) do
        bindPart(child)
    end
    
    local descConn = character.DescendantAdded:Connect(bindPart)
    table.insert(activeConnections, descConn)
end

if LocalPlayer.Character then
    setupCharacterTouchDetection(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(setupCharacterTouchDetection)