-- Decor Cleaner + Auto Farm Wild Pet v7.0 (Minimalist GUI)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

-- Configuration
local CONFIG = {
    DestroyFolders = {
        {workspace, "Baseplate", "Decor"},
    },
    DisableCollideFolders = {
        {workspace, "Map", "Stands"},
        {workspace, "AuctionStand"},
        {workspace, "ExplorerStand"},
        {workspace, "PilgrimStand"},
        {workspace, "NPCS"},
    },
    WildPetSpawnsPath = {workspace, "Map", "WildPetSpawns"},
    ScanInterval = 0.5,
    IdleWaitInterval = 1.0,
    ArriveDistance = 6,
    PromptRange = 15,
    PromptSpamDelay = 0.12,
    PromptSpamMax = 8,
    MaxTimeToReach = 15,
    InstantFire = true,
    AntiAfkEnabled = true,
    AntiAfkMinWait = 5 * 60,
    AntiAfkMaxWait = 10 * 60,
    DefaultWalkSpeed = 20,
    MinWalkSpeed = 8,
    MaxWalkSpeed = 200,
    WatchdogIdleThreshold = 2.5,
    WatchdogStallThreshold = 6,
    WatchdogForceSkipAfter = 12,
    FireConfirmWait = 0.5,
    FireConfirmMoveMin = 2,
    PriorityMode = "Points",
    PriorityDistanceWeight = 0.5,
    HighValueThreshold = 25,
    MaxChaseDistance = 400,
    BlacklistUnknown = true,
}

-- Pet rarity data
local PET_RARITY = {
    ["Dog"] = {rarity = "Uncommon", points = 10},
    ["Hedgehog"] = {rarity = "Rare", points = 15},
    ["Turkey"] = {rarity = "Rare", points = 15},
    ["Squirrel"] = {rarity = "Legendary", points = 25},
    ["Swan"] = {rarity = "Legendary", points = 25},
    ["Wolf"] = {rarity = "Mythic", points = 40},
    ["Fox"] = {rarity = "Mythic", points = 40},
    ["Shadow Dragon"] = {rarity = "Super", points = 500},
}

local RARITY_COLORS = {
    Common = Color3.fromRGB(180, 180, 180),
    Uncommon = Color3.fromRGB(120, 220, 120),
    Rare = Color3.fromRGB(100, 180, 255),
    Legendary = Color3.fromRGB(255, 180, 80),
    Mythic = Color3.fromRGB(220, 100, 220),
    Super = Color3.fromRGB(255, 80, 80),
    Unknown = Color3.fromRGB(150, 150, 150),
}

local RARITY_ORDER = {
    Super = 1,
    Mythic = 2,
    Legendary = 3,
    Rare = 4,
    Uncommon = 5,
    Common = 6,
    Unknown = 7,
}

-- Helper functions
local function resolvePath(t)
    local c = t[1]
    for i = 2, #t do
        if not c then return nil end
        c = c:FindFirstChild(t[i])
    end
    return c
end

local function deleteFolders()
    local total = 0
    for _, path in ipairs(CONFIG.DestroyFolders) do
        local folder = resolvePath(path)
        if folder and folder.Parent then
            for _, obj in ipairs(folder:GetChildren()) do
                local ok = pcall(function() obj:Destroy() end)
                if ok then total = total + 1 end
            end
        end
    end
    return total
end

local function disableColliders()
    local total = 0
    for _, path in ipairs(CONFIG.DisableCollideFolders) do
        local folder = resolvePath(path)
        if folder and folder.Parent then
            for _, obj in ipairs(folder:GetDescendants()) do
                if obj:IsA("BasePart") then
                    if obj.CanCollide then
                        obj.CanCollide = false
                        total = total + 1
                    end
                    obj.CanTouch = false
                end
            end
        end
    end
    return total
end

deleteFolders()
disableColliders()

local function extractPetName(fullName)
    local parts = {}
    for segment in string.gmatch(fullName, "[^_]+") do
        table.insert(parts, segment)
    end
    local firstIdx, secondIdx = nil, nil
    for i, p in ipairs(parts) do
        if p == "WildPet" then
            if not firstIdx then
                firstIdx = i
            elseif not secondIdx then
                secondIdx = i
                break
            end
        end
    end
    if firstIdx and secondIdx and secondIdx > firstIdx + 1 then
        local nameParts = {}
        for i = firstIdx + 1, secondIdx - 1 do
            table.insert(nameParts, parts[i])
        end
        return table.concat(nameParts, " ")
    end
    if #parts >= 2 then return parts[2] end
    return fullName
end

local function getPetInfo(petName)
    if PET_RARITY[petName] then return PET_RARITY[petName] end
    local normalized = petName:lower():gsub("[_%s]", "")
    for name, info in pairs(PET_RARITY) do
        local nameNorm = name:lower():gsub("[_%s]", "")
        if nameNorm == normalized then return info end
    end
    return {rarity = "Unknown", points = 0}
end

-- State
local running = true
local firedCount = 0
local boughtCount = 0
local totalPoints = 0
local ignoredPets = {}
local currentWalkSpeed = CONFIG.DefaultWalkSpeed
local petInventory = {}
local inventoryOrder = {}
local skippedUnknownCount = 0

local watchdog = {
    lastPos = Vector3.zero,
    lastMoveTime = tick(),
    lastStatusChangeTime = tick(),
    lastStatus = "",
    forceSkipFlag = false,
}

local function isIgnored(entry) return ignoredPets[entry] == true end
local function markIgnored(entry) if entry then ignoredPets[entry] = true end end

local function cleanIgnored()
    for entry, _ in pairs(ignoredPets) do
        if not entry.Parent then ignoredPets[entry] = nil end
    end
end

-- ============ GUI (Minimalist) ============
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WildPetFarmer"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game.CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 240, 0, 370)
MainFrame.Position = UDim2.new(0.5, -120, 0.5, -185)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -60, 0, 26)
Title.Position = UDim2.new(0, 8, 0, 4)
Title.BackgroundTransparency = 1
Title.Text = "🐾 Wild Pet Farmer"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 12
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local MinimizeBtn = Instance.new("TextButton")
MinimizeBtn.Size = UDim2.new(0, 20, 0, 20)
MinimizeBtn.Position = UDim2.new(1, -48, 0, 6)
MinimizeBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
MinimizeBtn.Text = "—"
MinimizeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinimizeBtn.Font = Enum.Font.GothamBold
MinimizeBtn.TextSize = 12
MinimizeBtn.BorderSizePixel = 0
MinimizeBtn.Parent = MainFrame
Instance.new("UICorner", MinimizeBtn).CornerRadius = UDim.new(0, 5)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 20, 0, 20)
CloseBtn.Position = UDim2.new(1, -24, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 11
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = MainFrame
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5)

local ContentFrame = Instance.new("Frame")
ContentFrame.Size = UDim2.new(1, 0, 1, -30)
ContentFrame.Position = UDim2.new(0, 0, 0, 30)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = MainFrame

-- Panel daftar pet (hanya yang didapat)
local InvFrame = Instance.new("ScrollingFrame")
InvFrame.Size = UDim2.new(1, -16, 1, -126)
InvFrame.Position = UDim2.new(0, 8, 0, 0)
InvFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
InvFrame.BorderSizePixel = 0
InvFrame.ScrollBarThickness = 4
InvFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
InvFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
InvFrame.Parent = ContentFrame
Instance.new("UICorner", InvFrame).CornerRadius = UDim.new(0, 5)

local InvList = Instance.new("UIListLayout", InvFrame)
InvList.Padding = UDim.new(0, 2)
InvList.SortOrder = Enum.SortOrder.LayoutOrder

local InvPadding = Instance.new("UIPadding", InvFrame)
InvPadding.PaddingTop = UDim.new(0, 4)
InvPadding.PaddingLeft = UDim.new(0, 6)
InvPadding.PaddingRight = UDim.new(0, 6)
InvPadding.PaddingBottom = UDim.new(0, 4)

-- Empty state label
local EmptyLabel = Instance.new("TextLabel")
EmptyLabel.Size = UDim2.new(1, -12, 1, -8)
EmptyLabel.Position = UDim2.new(0, 6, 0, 4)
EmptyLabel.BackgroundTransparency = 1
EmptyLabel.Text = "Belum ada pet yang didapat"
EmptyLabel.TextColor3 = Color3.fromRGB(100, 100, 110)
EmptyLabel.Font = Enum.Font.Gotham
EmptyLabel.TextSize = 11
EmptyLabel.TextWrapped = true
EmptyLabel.Parent = InvFrame

-- Panel PTS
local PointsPanel = Instance.new("Frame")
PointsPanel.Size = UDim2.new(1, -16, 0, 30)
PointsPanel.Position = UDim2.new(0, 8, 1, -116)
PointsPanel.BackgroundColor3 = Color3.fromRGB(30, 40, 55)
PointsPanel.BorderSizePixel = 0
PointsPanel.Parent = ContentFrame
Instance.new("UICorner", PointsPanel).CornerRadius = UDim.new(0, 6)

local PointsStroke = Instance.new("UIStroke")
PointsStroke.Color = Color3.fromRGB(80, 180, 255)
PointsStroke.Thickness = 1
PointsStroke.Transparency = 0.5
PointsStroke.Parent = PointsPanel

local PointsIcon = Instance.new("TextLabel")
PointsIcon.Size = UDim2.new(0, 26, 1, 0)
PointsIcon.Position = UDim2.new(0, 4, 0, 0)
PointsIcon.BackgroundTransparency = 1
PointsIcon.Text = "⭐"
PointsIcon.TextColor3 = Color3.fromRGB(255, 220, 100)
PointsIcon.Font = Enum.Font.GothamBold
PointsIcon.TextSize = 14
PointsIcon.Parent = PointsPanel

local PointsValue = Instance.new("TextLabel")
PointsValue.Size = UDim2.new(1, -34, 1, 0)
PointsValue.Position = UDim2.new(0, 32, 0, 0)
PointsValue.BackgroundTransparency = 1
PointsValue.Text = "0 PTS"
PointsValue.TextColor3 = Color3.fromRGB(120, 255, 180)
PointsValue.Font = Enum.Font.GothamBold
PointsValue.TextSize = 14
PointsValue.TextXAlignment = Enum.TextXAlignment.Left
PointsValue.Parent = PointsPanel

-- Panel Speed (2 tombol: 20 & 25)
local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(1, -16, 0, 14)
SpeedLabel.Position = UDim2.new(0, 8, 1, -82)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Text = "⚡ SPEED"
SpeedLabel.TextColor3 = Color3.fromRGB(160, 200, 240)
SpeedLabel.Font = Enum.Font.GothamBold
SpeedLabel.TextSize = 9
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
SpeedLabel.Parent = ContentFrame

local Speed20Btn = Instance.new("TextButton")
Speed20Btn.Size = UDim2.new(0.5, -12, 0, 26)
Speed20Btn.Position = UDim2.new(0, 8, 1, -66)
Speed20Btn.BackgroundColor3 = Color3.fromRGB(0, 170, 100)
Speed20Btn.Text = "20"
Speed20Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
Speed20Btn.Font = Enum.Font.GothamBold
Speed20Btn.TextSize = 12
Speed20Btn.BorderSizePixel = 0
Speed20Btn.Parent = ContentFrame
Instance.new("UICorner", Speed20Btn).CornerRadius = UDim.new(0, 5)

local Speed25Btn = Instance.new("TextButton")
Speed25Btn.Size = UDim2.new(0.5, -12, 0, 26)
Speed25Btn.Position = UDim2.new(0.5, 4, 1, -66)
Speed25Btn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
Speed25Btn.Text = "25"
Speed25Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
Speed25Btn.Font = Enum.Font.GothamBold
Speed25Btn.TextSize = 12
Speed25Btn.BorderSizePixel = 0
Speed25Btn.Parent = ContentFrame
Instance.new("UICorner", Speed25Btn).CornerRadius = UDim.new(0, 5)

-- Tombol START/STOP
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, -16, 0, 30)
ToggleBtn.Position = UDim2.new(0, 8, 1, -34)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
ToggleBtn.Text = "⏹ STOP"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 12
ToggleBtn.BorderSizePixel = 0
ToggleBtn.Parent = ContentFrame
Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 6)

-- ============ UI functions ============
local function updatePoints()
    PointsValue.Text = tostring(totalPoints) .. " PTS"
    if totalPoints >= 1000 then
        PointsValue.TextColor3 = Color3.fromRGB(255, 100, 100)
    elseif totalPoints >= 500 then
        PointsValue.TextColor3 = Color3.fromRGB(255, 180, 80)
    elseif totalPoints >= 100 then
        PointsValue.TextColor3 = Color3.fromRGB(255, 220, 120)
    else
        PointsValue.TextColor3 = Color3.fromRGB(120, 255, 180)
    end
end

local function updateSpeedButtons()
    if currentWalkSpeed == 20 then
        Speed20Btn.BackgroundColor3 = Color3.fromRGB(0, 170, 100)
        Speed25Btn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
    else
        Speed20Btn.BackgroundColor3 = Color3.fromRGB(80, 80, 100)
        Speed25Btn.BackgroundColor3 = Color3.fromRGB(0, 170, 100)
    end
end

-- Inventory UI (hanya pet yang didapat)
local petRows = {}

local function createPetRow(petName)
    local info = getPetInfo(petName)
    local rarityColor = RARITY_COLORS[info.rarity] or RARITY_COLORS.Unknown

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -4, 0, 20)
    row.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
    row.BorderSizePixel = 0
    row.Parent = InvFrame
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local strip = Instance.new("Frame")
    strip.Size = UDim2.new(0, 3, 0.8, 0)
    strip.Position = UDim2.new(0, 2, 0.1, 0)
    strip.BackgroundColor3 = rarityColor
    strip.BorderSizePixel = 0
    strip.Parent = row
    Instance.new("UICorner", strip).CornerRadius = UDim.new(1, 0)

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -60, 1, 0)
    nameLabel.Position = UDim2.new(0, 10, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = petName
    nameLabel.TextColor3 = rarityColor
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextSize = 11
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = row

    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(0, 42, 1, 0)
    countLabel.Position = UDim2.new(1, -44, 0, 0)
    countLabel.BackgroundTransparency = 1
    countLabel.Text = "x0"
    countLabel.TextColor3 = Color3.fromRGB(120, 255, 160)
    countLabel.Font = Enum.Font.GothamBold
    countLabel.TextSize = 11
    countLabel.TextXAlignment = Enum.TextXAlignment.Right
    countLabel.Parent = row

    petRows[petName] = {frame = row, nameLabel = nameLabel, countLabel = countLabel}
end

local function refreshInventoryUI()
    table.sort(inventoryOrder, function(a, b)
        local infoA = getPetInfo(a)
        local infoB = getPetInfo(b)
        local orderA = RARITY_ORDER[infoA.rarity] or 99
        local orderB = RARITY_ORDER[infoB.rarity] or 99
        if orderA ~= orderB then
            return orderA < orderB
        end
        return a < b
    end)

    for i, petName in ipairs(inventoryOrder) do
        if not petRows[petName] then createPetRow(petName) end
        local row = petRows[petName]
        if row then
            row.countLabel.Text = "x" .. (petInventory[petName] or 0)
            row.frame.LayoutOrder = i
        end
    end

    EmptyLabel.Visible = (#inventoryOrder == 0)
end

local function incrementPet(petName)
    if not petInventory[petName] then
        petInventory[petName] = 0
        table.insert(inventoryOrder, petName)
    end
    petInventory[petName] = petInventory[petName] + 1
    local info = getPetInfo(petName)
    totalPoints = totalPoints + info.points
end

-- Helper functions
local function getRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
end

local function getHumanoid()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function getPart(entry)
    if not entry or not entry.Parent then return nil end
    if entry:IsA("BasePart") then return entry end
    if entry:IsA("Model") then
        return entry.PrimaryPart or entry:FindFirstChildWhichIsA("BasePart")
    end
    for _, d in ipairs(entry:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end
    return nil
end

local function getPrompt(entry)
    if not entry or not entry.Parent then return nil end
    if entry:IsA("ProximityPrompt") then return entry end
    local p = entry:FindFirstChildOfClass("ProximityPrompt")
    if p then return p end
    for _, d in ipairs(entry:GetDescendants()) do
        if d:IsA("ProximityPrompt") then return d end
    end
    return nil
end

local function petExists(entry)
    return entry and entry.Parent ~= nil
end

local function stopMoving()
    local h = getHumanoid()
    if h then h:Move(Vector3.zero, false) end
end

local function applyWalkSpeed(spd)
    local char = LocalPlayer.Character
    if not char then return end
    local h = char:FindFirstChildOfClass("Humanoid")
    if h then h.WalkSpeed = spd end
end

LocalPlayer.CharacterAdded:Connect(function(char)
    char:WaitForChild("Humanoid", 5)
    task.wait(0.3)
    applyWalkSpeed(currentWalkSpeed)
end)

-- Anti-AFK (selalu ON)
local function antiAfkPulse()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
    local char = LocalPlayer.Character
    if char then
        local h = char:FindFirstChildOfClass("Humanoid")
        if h then
            h.Jump = true
            task.wait(0.1)
        end
    end
    pcall(function()
        local cam = workspace.CurrentCamera
        if cam then
            local oldCF = cam.CFrame
            cam.CFrame = oldCF * CFrame.Angles(0, math.rad(0.5), 0)
            task.wait(0.05)
            cam.CFrame = oldCF
        end
    end)
end

local function antiAfkLoop()
    while running do
        local waitTime = CONFIG.AntiAfkMinWait + math.random() * (CONFIG.AntiAfkMaxWait - CONFIG.AntiAfkMinWait)
        local endTime = tick() + waitTime
        while running and tick() < endTime do
            task.wait(1)
        end
        if running then antiAfkPulse() end
    end
end

-- Instant fire
local function instantFire(prompt)
    if not prompt then return false end
    local oldHold = prompt.HoldDuration
    local oldEnabled = prompt.Enabled

    prompt.HoldDuration = 0
    prompt.Enabled = true

    local ok = pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt)
        else
            prompt:InputHoldBegin()
            task.wait(0.01)
            prompt:InputHoldEnd()
        end
    end)

    task.wait(0.02)
    pcall(function()
        prompt.HoldDuration = oldHold
        prompt.Enabled = oldEnabled
    end)

    return ok
end

local function validateFireSuccess(entry, partBefore, posBefore)
    if not petExists(entry) then return true end
    local prompt = getPrompt(entry)
    if not prompt then return true end
    local partAfter = getPart(entry)
    if partAfter then
        local moved = (partAfter.Position - posBefore).Magnitude
        if moved > CONFIG.FireConfirmMoveMin then
            return true
        end
    end
    return false
end

local function moveToTarget(targetPosGetter, entry, maxTime)
    local humanoid = getHumanoid()
    local root = getRoot()
    if not humanoid or not root then return false end

    local maxTime = maxTime or CONFIG.MaxTimeToReach
    local startTime = tick()
    local lastPos = root.Position
    local lastMoveTime = tick()

    watchdog.forceSkipFlag = false

    while running and tick() - startTime < maxTime do
        if watchdog.forceSkipFlag then
            watchdog.forceSkipFlag = false
            stopMoving()
            return false
        end

        if not petExists(entry) or isIgnored(entry) then
            stopMoving()
            return false
        end

        humanoid = getHumanoid()
        root = getRoot()
        if not humanoid or not root then return false end

        if humanoid.WalkSpeed ~= currentWalkSpeed then
            humanoid.WalkSpeed = currentWalkSpeed
        end

        local targetPos = targetPosGetter()
        if not targetPos then return false end

        local dist = (root.Position - targetPos).Magnitude
        if dist <= CONFIG.ArriveDistance then
            stopMoving()
            return true
        end

        humanoid:MoveTo(targetPos)

        local moved = (root.Position - lastPos).Magnitude
        if moved > 0.5 then lastMoveTime = tick() end
        lastPos = root.Position

        if tick() - lastMoveTime > 1.5 then
            humanoid.Jump = true
            lastMoveTime = tick()
        end

        task.wait(0.08)
    end

    stopMoving()
    return false
end

local function watchdogLoop()
    while running do
        task.wait(1)
        if not running then break end

        local root = getRoot()
        if not root then
            watchdog.lastPos = Vector3.zero
            watchdog.lastMoveTime = tick()
            continue
        end

        local currentPos = root.Position
        if (currentPos - watchdog.lastPos).Magnitude > 1 then
            watchdog.lastPos = currentPos
            watchdog.lastMoveTime = tick()
        else
            local idleTime = tick() - watchdog.lastMoveTime
            local stallTime = tick() - watchdog.lastStatusChangeTime

            if idleTime > CONFIG.WatchdogIdleThreshold then
                local h = getHumanoid()
                if h then
                    pcall(function()
                        h.Jump = true
                        h:MoveTo(currentPos + Vector3.new(math.random(-5,5), 0, math.random(-5,5)))
                    end)
                end
                watchdog.lastMoveTime = tick()
            end

            if stallTime > CONFIG.WatchdogStallThreshold then
                watchdog.forceSkipFlag = true
                watchdog.lastStatusChangeTime = tick()
            end
        end
    end
end

local function firePromptOnce(entry)
    local root = getRoot()
    if not root then return false end
    local part = getPart(entry)
    if not part then return false end
    local dist = (root.Position - part.Position).Magnitude
    if dist > CONFIG.PromptRange then return false end

    local prompt = getPrompt(entry)
    if not prompt then return false end

    local ok = instantFire(prompt)
    if ok then
        firedCount = firedCount + 1
        return true
    end
    return false
end

local function firePromptUntilDone(entry, petName)
    for i = 1, CONFIG.PromptSpamMax do
        if not running then return false, "stopped" end
        if not petExists(entry) then
            return true, "disappeared"
        end

        local partBefore = getPart(entry)
        local posBefore = partBefore and partBefore.Position or Vector3.zero

        if firePromptOnce(entry) then
            task.wait(CONFIG.FireConfirmWait)
            if validateFireSuccess(entry, partBefore, posBefore) then
                return true, "validated"
            end
        end

        task.wait(CONFIG.PromptSpamDelay)
    end

    if not petExists(entry) then
        return true, "disappeared_late"
    end

    return false, "failed"
end

local function scanPets()
    local results = {}
    local wildFolder = resolvePath(CONFIG.WildPetSpawnsPath)
    if not wildFolder or not wildFolder.Parent then return results end
    local root = getRoot()
    if not root then return results end
    local myPos = root.Position

    for _, entry in ipairs(wildFolder:GetChildren()) do
        if not isIgnored(entry) then
            local part = getPart(entry)
            if part then
                local dist = (part.Position - myPos).Magnitude
                if dist <= CONFIG.MaxChaseDistance then
                    local petName = extractPetName(entry.Name)
                    local info = getPetInfo(petName)
                    
                    if CONFIG.BlacklistUnknown and info.rarity == "Unknown" then
                        skippedUnknownCount = skippedUnknownCount + 1
                    else
                        table.insert(results, {
                            entry = entry,
                            dist = dist,
                            name = entry.Name,
                            petName = petName,
                            points = info.points,
                            rarity = info.rarity,
                        })
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b)
        if a.points ~= b.points then
            return a.points > b.points
        end
        return a.dist < b.dist
    end)

    return results
end

local function hasHigherPriorityPet(currentPet)
    local wildFolder = resolvePath(CONFIG.WildPetSpawnsPath)
    if not wildFolder or not wildFolder.Parent then return false end
    local root = getRoot()
    if not root then return false end
    local myPos = root.Position

    for _, entry in ipairs(wildFolder:GetChildren()) do
        if entry ~= currentPet.entry and not isIgnored(entry) then
            local part = getPart(entry)
            if part then
                local dist = (part.Position - myPos).Magnitude
                if dist <= CONFIG.MaxChaseDistance then
                    local petName = extractPetName(entry.Name)
                    local info = getPetInfo(petName)
                    if info.points > currentPet.points and dist < CONFIG.MaxChaseDistance * 0.8 then
                        return true, petName, info.points
                    end
                end
            end
        end
    end
    return false
end

local function mainLoop()
    local wildFolder = resolvePath(CONFIG.WildPetSpawnsPath)
    if not wildFolder then
        return
    end

    while running do
        if not getRoot() then
            stopMoving()
            task.wait(1)
            continue
        end

        cleanIgnored()
        local pets = scanPets()

        if #pets == 0 then
            stopMoving()
            task.wait(CONFIG.IdleWaitInterval)
            continue
        end

        for _, pet in ipairs(pets) do
            if not running then break end
            if isIgnored(pet.entry) or not petExists(pet.entry) then
                continue
            end

            local higherExists, higherName, higherPts = hasHigherPriorityPet(pet)
            if higherExists and pet.points < CONFIG.HighValueThreshold then
                continue
            end

            watchdog.forceSkipFlag = false
            watchdog.lastStatusChangeTime = tick()
            local petStartTime = tick()

            local function getTargetPos()
                local p = getPart(pet.entry)
                return p and p.Position or nil
            end

            local targetPos = getTargetPos()
            if not targetPos then continue end

            local root = getRoot()
            if not root then break end
            local dist = (root.Position - targetPos).Magnitude

            if dist > CONFIG.ArriveDistance then
                moveToTarget(getTargetPos, pet.entry, CONFIG.MaxTimeToReach)
            end

            if tick() - petStartTime > CONFIG.WatchdogForceSkipAfter then
                task.wait(0.3)
                continue
            end

            if not running then break end
            if isIgnored(pet.entry) then continue end
            if not petExists(pet.entry) then continue end

            local root2 = getRoot()
            local part2 = getPart(pet.entry)
            if root2 and part2 and (root2.Position - part2.Position).Magnitude <= CONFIG.PromptRange then
                local success, reason = firePromptUntilDone(pet.entry, pet.petName)

                if success then
                    markIgnored(pet.entry)
                    boughtCount = boughtCount + 1
                    incrementPet(pet.petName)
                    refreshInventoryUI()
                    updatePoints()
                    stopMoving()
                    watchdog.lastStatusChangeTime = tick()
                    watchdog.lastMoveTime = tick()

                    task.wait(0.3)
                    local newPets = scanPets()
                    if #newPets > 0 and newPets[1].points > pet.points then
                        break
                    end
                end
            end

            task.wait(0.15)
        end

        task.wait(CONFIG.ScanInterval)
    end

    stopMoving()
end

-- Speed buttons
Speed20Btn.MouseButton1Click:Connect(function()
    currentWalkSpeed = 20
    updateSpeedButtons()
    applyWalkSpeed(20)
end)

Speed25Btn.MouseButton1Click:Connect(function()
    currentWalkSpeed = 25
    updateSpeedButtons()
    applyWalkSpeed(25)
end)

-- Start/Stop
ToggleBtn.MouseButton1Click:Connect(function()
    if running then
        running = false
        ToggleBtn.Text = "▶ START"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 170, 100)
        stopMoving()
    else
        running = true
        ToggleBtn.Text = "⏹ STOP"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        task.spawn(mainLoop)
        task.spawn(watchdogLoop)
    end
end)

-- Minimize
local minimized = false
MinimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    ContentFrame.Visible = not minimized
    if minimized then
        MainFrame.Size = UDim2.new(0, 240, 0, 30)
    else
        MainFrame.Size = UDim2.new(0, 240, 0, 370)
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    running = false
    stopMoving()
    ScreenGui:Destroy()
end)

-- Auto start
local wildFolder = resolvePath(CONFIG.WildPetSpawnsPath)
if wildFolder then
    updatePoints()
    updateSpeedButtons()
    task.spawn(mainLoop)
    task.spawn(antiAfkLoop)
    task.spawn(watchdogLoop)

    task.wait(0.5)
    applyWalkSpeed(currentWalkSpeed)
end
