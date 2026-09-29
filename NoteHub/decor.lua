local CONFIG = {
    DecorFolders = {
        {workspace, "Baseplate", "Decor"},
        {workspace, "Map", "Stands"},
        {workspace, "AuctionStand"},
        {workspace, "ExplorerStand"},
        {workspace, "PilgrimStand"},
        {workspace, "NPCS"},
    },
}

local function resolvePath(t)
    local c = t[1]
    for i = 2, #t do
        if not c then return nil end
        c = c:FindFirstChild(t[i])
    end
    return c
end

local deletedCache = {}

local function saveObject(obj)
    local data = {
        className = obj.ClassName,
        name = obj.Name,
        properties = {},
        children = {},
    }

    if obj:IsA("BasePart") then
        data.properties.CFrame = obj.CFrame
        data.properties.Size = obj.Size
        data.properties.Color = obj.Color
        data.properties.Material = obj.Material
        data.properties.Transparency = obj.Transparency
        data.properties.Anchored = obj.Anchored
        data.properties.CanCollide = obj.CanCollide
        data.properties.CanTouch = obj.CanTouch
        if obj:IsA("Part") then
            data.properties.Shape = obj.Shape
        end
    elseif obj:IsA("Model") then
        data.properties.PrimaryPartName = obj.PrimaryPart and obj.PrimaryPart.Name or nil
    end

    for _, child in ipairs(obj:GetChildren()) do
        table.insert(data.children, saveObject(child))
    end

    return data
end

local function rebuildObject(data, parent)
    local ok, obj = pcall(function() return Instance.new(data.className) end)
    if not ok or not obj then return nil end

    obj.Name = data.name

    for prop, value in pairs(data.properties) do
        if prop ~= "PrimaryPartName" then
            pcall(function() obj[prop] = value end)
        end
    end

    for _, childData in ipairs(data.children) do
        rebuildObject(childData, obj)
    end

    if data.properties.PrimaryPartName then
        local pp = obj:FindFirstChild(data.properties.PrimaryPartName)
        if pp then obj.PrimaryPart = pp end
    end

    obj.Parent = parent
    return obj
end

local function deleteDecor()
    deletedCache = {}
    local total = 0

    for _, path in ipairs(CONFIG.DecorFolders) do
        local folder = resolvePath(path)
        if folder and folder.Parent then
            for _, obj in ipairs(folder:GetChildren()) do
                local data = saveObject(obj)
                data.parentPath = path
                table.insert(deletedCache, data)

                local ok = pcall(function() obj:Destroy() end)
                if ok then total = total + 1 end
            end
        end
    end
    return total
end

local function restoreDecor()
    if #deletedCache == 0 then return 0 end

    local restored = 0
    for _, data in ipairs(deletedCache) do
        local parent = resolvePath(data.parentPath)
        if parent then
            local newObj = rebuildObject(data, parent)
            if newObj then restored = restored + 1 end
        end
    end
    deletedCache = {}
    return restored
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "DecorManager"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game.CoreGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 150, 0, 84)
MainFrame.Position = UDim2.new(0, 20, 0.5, -42)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

local Padding = Instance.new("UIPadding", MainFrame)
Padding.PaddingTop = UDim.new(0, 6)
Padding.PaddingBottom = UDim.new(0, 6)
Padding.PaddingLeft = UDim.new(0, 6)
Padding.PaddingRight = UDim.new(0, 6)

local DeleteBtn = Instance.new("TextButton")
DeleteBtn.Size = UDim2.new(1, 0, 0, 32)
DeleteBtn.Position = UDim2.new(0, 0, 0, 0)
DeleteBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
DeleteBtn.Text = "💥 DELETE DECOR"
DeleteBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DeleteBtn.Font = Enum.Font.GothamBold
DeleteBtn.TextSize = 12
DeleteBtn.BorderSizePixel = 0
DeleteBtn.Parent = MainFrame
Instance.new("UICorner", DeleteBtn).CornerRadius = UDim.new(0, 6)

local RestoreBtn = Instance.new("TextButton")
RestoreBtn.Size = UDim2.new(1, 0, 0, 32)
RestoreBtn.Position = UDim2.new(0, 0, 0, 40)
RestoreBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 100)
RestoreBtn.Text = "♻️ RESTORE DECOR"
RestoreBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RestoreBtn.Font = Enum.Font.GothamBold
RestoreBtn.TextSize = 12
RestoreBtn.BorderSizePixel = 0
RestoreBtn.Parent = MainFrame
Instance.new("UICorner", RestoreBtn).CornerRadius = UDim.new(0, 6)

DeleteBtn.MouseButton1Click:Connect(function()
    DeleteBtn.Text = "⏳ Deleting..."
    DeleteBtn.BackgroundColor3 = Color3.fromRGB(150, 80, 50)
    task.wait(0.05)

    local total = deleteDecor()

    DeleteBtn.Text = "✅ Deleted " .. total
    DeleteBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 100)
    task.wait(1.5)
    DeleteBtn.Text = "💥 DELETE DECOR"
    DeleteBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
end)

RestoreBtn.MouseButton1Click:Connect(function()
    RestoreBtn.Text = "⏳ Restoring..."
    RestoreBtn.BackgroundColor3 = Color3.fromRGB(120, 140, 80)
    task.wait(0.05)

    local total = restoreDecor()

    RestoreBtn.Text = "✅ Restored " .. total
    RestoreBtn.BackgroundColor3 = Color3.fromRGB(60, 140, 80)
    task.wait(1.5)
    RestoreBtn.Text = "♻️ RESTORE DECOR"
    RestoreBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 100)
end)
