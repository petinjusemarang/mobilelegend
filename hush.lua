repeat task.wait() until game:IsLoaded()
task.spawn(function()
repeat task.wait() until game:IsLoaded()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Player = Players.LocalPlayer
local Columns = Player.PlayerGui
    :WaitForChild("HushInventory")
    :WaitForChild("Root")
    :WaitForChild("HushInventoryUI")
    :WaitForChild("Body")
    :WaitForChild("Columns")
local Remote = ReplicatedStorage
    :WaitForChild("HushNet")
    :WaitForChild("inv.op")
local CFG = {
    FileName = "HushAutoLoot_Config.json",
    InitialSequence = 1,
    MoveDelay = 0.10,
    VerifyDelay = 0.15,
    RetryDelay = 0.10,
    MaxVerifyAttempts = 3,
    AutoRotate = true,
    Containers = {
        pockets = {4, 1},
        vest = {5, 3},
        bag = {6, 7},
        secure = {3, 4},
    },
    Priority = {"pockets", "vest", "bag", "secure"},
}
local sequence = CFG.InitialSequence
local running = false
local scanResults = {}
local whitelist = {}
local movedCount = 0
local lastPlan = {}
local lastInvalid = {}
local function log(message)
    print("[HUSH AUTO LOOT] " .. tostring(message))
end
local function upper(value)
    return string.upper(tostring(value or ""))
end
local function countKeys(tbl)
    local n = 0
    for _ in pairs(tbl) do n += 1 end
    return n
end
local function destroyOldGui()
    pcall(function()
        local old = CoreGui:FindFirstChild("HushAutoLootV17")
        if old then old:Destroy() end
    end)
    pcall(function()
        if gethui then
            local old = gethui():FindFirstChild("HushAutoLootV17")
            if old then old:Destroy() end
        end
    end)
end
local function saveConfig()
    if type(writefile) ~= "function" then
        return false
    end
    local data = {
        version = 4,
        whitelist = whitelist,
        savedAt = os.date("%Y-%m-%d %H:%M:%S"),
    }
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if not ok then return false end
    return pcall(function()
        writefile(CFG.FileName, encoded)
    end)
end
local function loadConfig()
    if type(isfile) ~= "function"
        or type(readfile) ~= "function" then
        return
    end
    local exists = false
    pcall(function()
        exists = isfile(CFG.FileName)
    end)
    if not exists then return end
    local ok, content = pcall(readfile, CFG.FileName)
    if not ok or type(content) ~= "string" then return end
    local decoded, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if decoded and type(data) == "table"
        and type(data.whitelist) == "table" then
        whitelist = data.whitelist
    end
end
loadConfig()
local function normalizeContainer(sectionName)
    local name = string.lower(tostring(sectionName or ""))
    name = name:gsub("^section_", "")
    name = name:gsub("[%s_%-]", "")
    local aliases = {
        pockets = "pockets",
        pocket = "pockets",
        rig = "vest",
        vest = "vest",
        assaultcarrier = "vest",
        bag = "bag",
        backpack = "bag",
        raidpack = "bag",
        secure = "secure",
        securecase = "secure",
    }
    return aliases[name]
end
local function getUID(item)
    return item.Name:match("^Item_(.+)$")
end
local function getName(item)
    local label = item:FindFirstChild("Short", true)
    if label and label:IsA("TextLabel") then
        return label.Text
    end
    return item.Name
end
local function getCount(item)
    local label = item:FindFirstChild("Count", true)
    if label and label:IsA("TextLabel") then
        return tonumber(label.Text:match("%d+")) or 1
    end
    return 1
end
local function getRect(item)
    local rect = item:GetAttribute("PxRect")
    if typeof(rect) ~= "Rect" then return nil end
    local min = rect.Min
    local max = rect.Max
    local x1 = math.floor(min.X + 0.001)
    local y1 = math.floor(min.Y + 0.001)
    local x2 = math.floor(max.X + 0.001)
    local y2 = math.floor(max.Y + 0.001)
    if x2 <= x1 or y2 <= y1 then return nil end
    return {
        x = x1,
        y = y1,
        w = x2 - x1,
        h = y2 - y1,
    }
end
local function getSections(column)
    local result = {}
    if not column then return result end
    local content = column:FindFirstChild("Content")
    local scroll = content and content:FindFirstChild("Scroll")
    if not scroll then return result end
    for _, section in ipairs(scroll:GetChildren()) do
        if section.Name:match("^Section_") then
            table.insert(result, section)
        end
    end
    return result
end
local function getFrames(section)
    local result = {}
    if not section then return result end
    for _, obj in ipairs(section:GetDescendants()) do
        if obj:IsA("Frame") and obj.Name:match("^Item_") then
            table.insert(result, obj)
        end
    end
    return result
end
local function scanLoot()
    local lootColumn = Columns:FindFirstChild("Loot")
    local results, seen = {}, {}
    if not lootColumn then
        scanResults = {}
        return results
    end
    for _, section in ipairs(getSections(lootColumn)) do
        for _, item in ipairs(getFrames(section)) do
            local uid = getUID(item)
            local rect = getRect(item)
            if uid and rect and not seen[uid] then
                seen[uid] = true
                table.insert(results, {
                    uid = uid,
                    name = getName(item),
                    count = getCount(item),
                    w = rect.w,
                    h = rect.h,
                    item = item,
                    section = section.Name,
                })
            end
        end
    end
    scanResults = results
    return results
end
local function getGearItems()
    local gearColumn = Columns:FindFirstChild("Gear")
    local result = {}
    if not gearColumn then return result end
    for _, section in ipairs(getSections(gearColumn)) do
        local container = normalizeContainer(section.Name)
        for _, item in ipairs(getFrames(section)) do
            local rect = getRect(item)
            if rect then
                table.insert(result, {
                    uid = getUID(item),
                    name = getName(item),
                    container = container,
                    section = section.Name,
                    rect = rect,
                })
            end
        end
    end
    return result
end
local function newGrid(width, height)
    local grid = {}
    for y = 0, height - 1 do
        grid[y] = {}
        for x = 0, width - 1 do
            grid[y][x] = false
        end
    end
    return grid
end
local function canFit(grid, x, y, iw, ih, width, height)
    if x < 0 or y < 0
        or x + iw > width
        or y + ih > height then
        return false
    end
    for yy = y, y + ih - 1 do
        for xx = x, x + iw - 1 do
            if not grid[yy] or grid[yy][xx] then
                return false
            end
        end
    end
    return true
end
local function markRect(grid, rect, width, height)
    if not rect then return false end
    if rect.x < 0 or rect.y < 0
        or rect.x + rect.w > width
        or rect.y + rect.h > height then
        return false
    end
    for y = rect.y, rect.y + rect.h - 1 do
        for x = rect.x, rect.x + rect.w - 1 do
            grid[y][x] = true
        end
    end
    return true
end
local function buildGrids(gearItems)
    local grids = {}
    local invalid = {}
    for name, dimensions in pairs(CFG.Containers) do
        grids[name] = newGrid(dimensions[1], dimensions[2])
    end
    for _, item in ipairs(gearItems) do
        if not item.container then
            table.insert(invalid, {
                name = item.name,
                reason = "Unmapped section: " .. tostring(item.section),
            })
        else
            local dimensions = CFG.Containers[item.container]
            local grid = grids[item.container]
            if not dimensions or not grid then
                table.insert(invalid, {
                    name = item.name,
                    reason = "Unknown container: " .. tostring(item.container),
                })
            elseif not markRect(
                grid, item.rect, dimensions[1], dimensions[2]
            ) then
                table.insert(invalid, {
                    name = item.name,
                    reason = "PxRect outside " .. item.container,
                })
            end
        end
    end
    lastInvalid = invalid
    return grids, invalid
end
local function freeCells(grid, width, height)
    local free = 0
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            if not grid[y][x] then free += 1 end
        end
    end
    return free
end
local function placementScore(grid, x, y, iw, ih, width, height)
    local edges = 0
    for xx = x, x + iw - 1 do
        if y > 0 and not grid[y - 1][xx] then edges += 1 end
        if y + ih < height and not grid[y + ih][xx] then edges += 1 end
    end
    for yy = y, y + ih - 1 do
        if x > 0 and not grid[yy][x - 1] then edges += 1 end
        if x + iw < width and not grid[yy][x + iw] then edges += 1 end
    end
    return edges
end
local function findBestSpot(grid, iw, ih, width, height)
    local orientations = {
        {w = iw, h = ih, rotated = false},
    }
    if CFG.AutoRotate and iw ~= ih then
        table.insert(orientations, {
            w = ih,
            h = iw,
            rotated = true,
        })
    end
    local best
    for _, orientation in ipairs(orientations) do
        for y = 0, height - orientation.h do
            for x = 0, width - orientation.w do
                if canFit(
                    grid, x, y,
                    orientation.w, orientation.h,
                    width, height
                ) then
                    local score = placementScore(
                        grid, x, y,
                        orientation.w, orientation.h,
                        width, height
                    )
                    if not best or score < best.score then
                        best = {
                            x = x,
                            y = y,
                            w = orientation.w,
                            h = orientation.h,
                            rotated = orientation.rotated,
                            score = score,
                        }
                    end
                end
            end
        end
    end
    return best
end
local function containerAllowsItem(container, itemW, itemH)
    if container == "pockets" or container == "vest" then
        return itemW == 1 and itemH == 1
    end
    if container == "bag" or container == "secure" then
        return true
    end
    return false
end
local function solveInventory(lootItems)
    local gearItems = getGearItems()
    local grids, invalid = buildGrids(gearItems)
    local candidates = {}
    for _, item in ipairs(lootItems) do
        if whitelist[upper(item.name)] then
            table.insert(candidates, item)
        end
    end
    table.sort(candidates, function(a, b)
        local areaA = a.w * a.h
        local areaB = b.w * b.h
        if areaA == areaB then
            return math.max(a.w, a.h) > math.max(b.w, b.h)
        end
        return areaA > areaB
    end)
    local plan, failures = {}, {}
    for _, item in ipairs(candidates) do
        local placement
        for _, container in ipairs(CFG.Priority) do
            if containerAllowsItem(container, item.w, item.h) then
                local dimensions = CFG.Containers[container]
                local spot = findBestSpot(
                    grids[container],
                    item.w,
                    item.h,
                    dimensions[1],
                    dimensions[2]
                )
                if spot then
                    placement = {
                        container = container,
                        x = spot.x,
                        y = spot.y,
                        rotated = spot.rotated,
                        w = spot.w,
                        h = spot.h,
                    }
                    markRect(
                        grids[container],
                        {
                            x = spot.x,
                            y = spot.y,
                            w = spot.w,
                            h = spot.h,
                        },
                        dimensions[1],
                        dimensions[2]
                    )
                    break
                end
            end
        end
        if placement then
            table.insert(plan, {
                item = item,
                destination = placement,
            })
        else
            table.insert(failures, item)
        end
    end
    lastPlan = plan
    return {
        grids = grids,
        plan = plan,
        failures = failures,
        invalid = invalid,
        gearItems = gearItems,
    }
end
local function isInGear(uid)
    for _, item in ipairs(getGearItems()) do
        if item.uid == uid then return true end
    end
    return false
end
local function itemStillInLoot(uid, snapshot)
    for _, item in ipairs(snapshot or {}) do
        if item.uid == uid then
            local lootColumn = Columns:FindFirstChild("Loot")
            if lootColumn and item.item and item.item:IsDescendantOf(lootColumn) then
                return item
            end
            return nil
        end
    end
    return nil
end
local function getFreshDestination(item)
    local gearItems = getGearItems()
    local grids, invalid = buildGrids(gearItems)
    if #invalid > 0 then
        return nil, "Unmapped section or invalid PxRect"
    end
    for _, container in ipairs(CFG.Priority) do
        if containerAllowsItem(container, item.w, item.h) then
            local dimensions = CFG.Containers[container]
            local spot = findBestSpot(
                grids[container],
                item.w,
                item.h,
                dimensions[1],
                dimensions[2]
            )
            if spot then
                return {
                    container = container,
                    x = spot.x,
                    y = spot.y,
                    rotated = spot.rotated,
                }
            end
        end
    end
    return nil, "No allowed container has a valid placement"
end
local function pickItem(item)
    local destination, reason = getFreshDestination(item)
    if not destination then
        log("SKIP " .. item.name .. ": " .. tostring(reason))
        return false
    end
    local payload = {
        y = destination.y,
        op = "move",
        to = destination.container,
        r = destination.rotated,
        uid = item.uid,
        seq = sequence,
        x = destination.x,
    }
    local ok, err = pcall(function()
        Remote:FireServer(payload)
    end)
    if not ok then
        log("Remote call error: " .. tostring(err))
        return false
    end
    sequence += 1
    task.wait(CFG.VerifyDelay)
    for _ = 1, CFG.MaxVerifyAttempts do
        if isInGear(item.uid) then
            movedCount += 1
            log("PICKED " .. item.name .. " -> " .. destination.container)
            return true
        end
        task.wait(CFG.RetryDelay)
    end
    log("MOVE NOT VERIFIED: " .. item.name)
    return false
end
local function startAutoPick()
    if running then return end
    running = true
    log("Auto Pick started")
    task.spawn(function()
        while running do
            local current = scanLoot()
            local candidates = {}
            for _, item in ipairs(current) do
                if whitelist[upper(item.name)] then
                    table.insert(candidates, item)
                end
            end
            if #candidates == 0 then
                task.wait(0.75)
            else
                local solution = solveInventory(candidates)
                if #solution.plan == 0 then
                    log("No valid placement for current whitelist items")
                    task.wait(0.75)
                else
                    for _, planned in ipairs(solution.plan) do
                        if not running then break end
                        local fresh = itemStillInLoot(planned.item.uid, current)
                        if fresh and whitelist[upper(fresh.name)] then
                            pickItem(fresh)
                            task.wait(CFG.MoveDelay)
                        end
                    end
                end
            end
        end
        log("Auto Pick stopped")
    end)
end
local function stopAutoPick()
    running = false
    log("Stop requested")
end
destroyOldGui()
local gui = Instance.new("ScreenGui")
gui.Name = "HushAutoLootV17"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local guiParent = CoreGui
pcall(function()
    if gethui then guiParent = gethui() end
end)
gui.Parent = guiParent
local main = Instance.new("Frame")
main.Name = "Main"
main.Size = UDim2.fromOffset(350, 470)
main.Position = UDim2.new(1, -365, 0.5, -235) -- pindah ke sisi kanan, tidak menutupi tengah layar
main.BackgroundColor3 = Color3.fromRGB(18, 21, 29)
main.BackgroundTransparency = 0.22
local autoLootScale = Instance.new("UIScale")
autoLootScale.Scale = 0.78
autoLootScale.Parent = main
main.BorderSizePixel = 0
main.Active = true
main.Parent = gui
local mainCorner = Instance.new("UICorner")
mainCorner.CornerRadius = UDim.new(0, 10)
mainCorner.Parent = main
local outline = Instance.new("UIStroke")
outline.Color = Color3.fromRGB(55, 75, 105)
outline.Parent = main
local function label(parent, text, x, y, w, h, size, color)
    local obj = Instance.new("TextLabel")
    obj.BackgroundTransparency = 1
    obj.Position = UDim2.fromOffset(x, y)
    obj.Size = UDim2.fromOffset(w, h)
    obj.Font = Enum.Font.Gotham
    obj.Text = text
    obj.TextSize = size or 10
    obj.TextColor3 = color or Color3.fromRGB(230, 235, 245)
    obj.TextXAlignment = Enum.TextXAlignment.Left
    obj.TextYAlignment = Enum.TextYAlignment.Center
    obj.Parent = parent
    return obj
end
local function button(parent, text, x, y, w, h, color)
    local obj = Instance.new("TextButton")
    obj.Position = UDim2.fromOffset(x, y)
    obj.Size = UDim2.fromOffset(w, h)
    obj.BackgroundColor3 = color or Color3.fromRGB(47, 75, 110)
    obj.Text = text
    obj.TextColor3 = Color3.fromRGB(245, 248, 255)
    obj.Font = Enum.Font.GothamBold
    obj.TextSize = 10
    obj.BorderSizePixel = 0
    obj.Parent = parent
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 5)
    c.Parent = obj
    return obj
end
label(
    main, "HUSH AUTO LOOT  v1.7",
    12, 8, 270, 24, 14,
    Color3.fromRGB(105, 185, 255)
)
local status = label(main, "STATUS: IDLE", 12, 32, 250, 16, 10)
local stats = label(
    main, "Scanned: 0 | Saved: 0 | Moved: 0",
    12, 49, 325, 16, 9
)
local tabs = Instance.new("Frame")
tabs.Position = UDim2.fromOffset(10, 73)
tabs.Size = UDim2.fromOffset(330, 30)
tabs.BackgroundTransparency = 1
tabs.Parent = main
local pages = {}
local tabButtons = {}
local tabNames = {"SCAN", "ITEMS", "SOLVER", "AUTO"}
local function makePage(name)
    local page = Instance.new("Frame")
    page.Name = name
    page.Position = UDim2.fromOffset(10, 110)
    page.Size = UDim2.fromOffset(330, 350)
    page.BackgroundColor3 = Color3.fromRGB(25, 29, 39)
    page.BorderSizePixel = 0
    page.Visible = false
    page.Parent = main
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = page
    pages[name] = page
    return page
end
local function showPage(name)
    for pageName, page in pairs(pages) do
        page.Visible = pageName == name
    end
    for tabName, b in pairs(tabButtons) do
        b.BackgroundColor3 = tabName == name
            and Color3.fromRGB(55, 105, 155)
            or Color3.fromRGB(39, 48, 62)
    end
end
for i, name in ipairs(tabNames) do
    local b = button(
        tabs, name, (i - 1) * 82, 0, 77, 28,
        Color3.fromRGB(39, 48, 62)
    )
    tabButtons[name] = b
    b.MouseButton1Click:Connect(function()
        showPage(name)
    end)
end
local scanPage = makePage("SCAN")
local itemsPage = makePage("ITEMS")
local solverPage = makePage("SOLVER")
local autoPage = makePage("AUTO")
label(scanPage, "LOOT DETECTION", 10, 8, 280, 18, 11,
    Color3.fromRGB(120, 190, 255))
local scanInfo = label(scanPage, "No scan yet", 10, 32, 300, 45, 10)
local scanNow = button(scanPage, "SCAN NOW", 10, 88, 310, 34,
    Color3.fromRGB(45, 100, 155))
local addAll = button(scanPage, "ADD ALL SCANNED TO WHITELIST",
    10, 131, 310, 34, Color3.fromRGB(50, 105, 75))
local clearScan = button(scanPage, "CLEAR SCAN RESULTS",
    10, 174, 310, 30, Color3.fromRGB(105, 65, 65))
label(scanPage,
    "Scan reads Loot only. It does not move items.",
    10, 218, 300, 30, 9, Color3.fromRGB(165, 175, 190))
label(itemsPage, "WHITELIST ITEMS", 10, 8, 280, 18, 11,
    Color3.fromRGB(120, 190, 255))
local itemScroll = Instance.new("ScrollingFrame")
itemScroll.Position = UDim2.fromOffset(8, 31)
itemScroll.Size = UDim2.fromOffset(314, 255)
itemScroll.BackgroundColor3 = Color3.fromRGB(18, 21, 28)
itemScroll.BorderSizePixel = 0
itemScroll.ScrollBarThickness = 4
itemScroll.CanvasSize = UDim2.new()
itemScroll.Parent = itemsPage
local itemLayout = Instance.new("UIListLayout")
itemLayout.Padding = UDim.new(0, 3)
itemLayout.Parent = itemScroll
local saveButton = button(itemsPage, "SAVE PERMANENT",
    8, 304, 150, 32, Color3.fromRGB(45, 110, 80))
local clearList = button(itemsPage, "CLEAR LIST",
    166, 304, 156, 32, Color3.fromRGB(115, 60, 65))
label(solverPage, "INVENTORY SPACE SOLVER", 10, 8, 290, 18, 11,
    Color3.fromRGB(120, 190, 255))
local solverInfo = label(solverPage,
    "Press CALCULATE to inspect containers.", 10, 29, 310, 30, 9)
local solverScroll = Instance.new("ScrollingFrame")
solverScroll.Position = UDim2.fromOffset(8, 63)
solverScroll.Size = UDim2.fromOffset(314, 235)
solverScroll.BackgroundColor3 = Color3.fromRGB(18, 21, 28)
solverScroll.BorderSizePixel = 0
solverScroll.ScrollBarThickness = 4
solverScroll.CanvasSize = UDim2.new()
solverScroll.Parent = solverPage
local solverLayout = Instance.new("UIListLayout")
solverLayout.Padding = UDim.new(0, 8)
solverLayout.Parent = solverScroll
local calculateButton = button(solverPage, "CALCULATE SPACE",
    8, 306, 150, 32, Color3.fromRGB(45, 100, 155))
local refreshButton = button(solverPage, "REFRESH GRID",
    166, 306, 156, 32, Color3.fromRGB(55, 75, 110))
label(autoPage, "AUTOMATIC PICKUP", 10, 8, 280, 18, 11,
    Color3.fromRGB(120, 190, 255))
local autoInfo = label(autoPage,
    "Only enabled whitelist items will be picked.",
    10, 34, 305, 55, 10)
local startButton = button(autoPage, "START AUTO PICK",
    10, 100, 310, 38, Color3.fromRGB(40, 125, 80))
local stopButton = button(autoPage, "STOP",
    10, 148, 310, 34, Color3.fromRGB(145, 55, 60))
local saveAuto = button(autoPage, "SAVE CONFIG",
    10, 193, 310, 30, Color3.fromRGB(55, 75, 110))
local sequenceInfo = label(autoPage,
    "Sequence: " .. tostring(sequence),
    10, 238, 305, 40, 9, Color3.fromRGB(180, 180, 190))
local function updateStats()
    stats.Text = string.format(
        "Scanned: %d | Saved: %d | Moved: %d",
        #scanResults, countKeys(whitelist), movedCount
    )
    scanInfo.Text = string.format(
        "Items found: %d\nWhitelist entries: %d",
        #scanResults, countKeys(whitelist)
    )
    autoInfo.Text = string.format(
        "Whitelist: %d items\nMoved this session: %d\nMove delay: %.2fs",
        countKeys(whitelist), movedCount, CFG.MoveDelay
    )
    status.Text = running and "STATUS: RUNNING" or "STATUS: IDLE"
    sequenceInfo.Text = "Sequence: " .. tostring(sequence)
        .. " | Verify valid session sequence"
end
local function renderList()
    for _, child in ipairs(itemScroll:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    local names = {}
    for _, item in ipairs(scanResults) do
        names[upper(item.name)] = item.name
    end
    for key in pairs(whitelist) do
        names[key] = names[key] or key
    end
    local sorted = {}
    for key, name in pairs(names) do
        table.insert(sorted, {key = key, name = name})
    end
    table.sort(sorted, function(a, b)
        return a.name < b.name
    end)
    for _, entry in ipairs(sorted) do
        local selected = whitelist[entry.key] == true
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -6, 0, 28)
        b.BackgroundColor3 = selected
            and Color3.fromRGB(38, 95, 68)
            or Color3.fromRGB(39, 45, 57)
        b.BorderSizePixel = 0
        b.Text = (selected and "[ON]  " or "[OFF]  ") .. entry.name
        b.TextColor3 = Color3.fromRGB(235, 240, 245)
        b.TextSize = 10
        b.Font = Enum.Font.Gotham
        b.Parent = itemScroll
        b.MouseButton1Click:Connect(function()
            if whitelist[entry.key] then
                whitelist[entry.key] = nil
            else
                whitelist[entry.key] = true
            end
            renderList()
            updateStats()
        end)
    end
    task.defer(function()
        itemScroll.CanvasSize = UDim2.fromOffset(
            0, itemLayout.AbsoluteContentSize.Y + 5
        )
    end)
    updateStats()
end
local function clearSolverVisual()
    for _, child in ipairs(solverScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
end
local function renderContainer(container, grid)
    local dimensions = CFG.Containers[container]
    local width, height = dimensions[1], dimensions[2]
    local cellSize, gap = 18, 2
    local wrapper = Instance.new("Frame")
    wrapper.Size = UDim2.new(1, -6, 0, height * (cellSize + gap) + 34)
    wrapper.BackgroundColor3 = Color3.fromRGB(27, 33, 44)
    wrapper.BorderSizePixel = 0
    wrapper.Parent = solverScroll
    label(wrapper,
        string.upper(container) .. " | FREE "
            .. freeCells(grid, width, height) .. "/" .. (width * height),
        7, 2, 290, 17, 9, Color3.fromRGB(190, 205, 225))
    local totalWidth = width * (cellSize + gap)
    local holder = Instance.new("Frame")
    holder.Position = UDim2.fromOffset(
        math.max(7, math.floor((314 - totalWidth) / 2)), 23
    )
    holder.Size = UDim2.fromOffset(
        totalWidth, height * (cellSize + gap)
    )
    holder.BackgroundTransparency = 1
    holder.Parent = wrapper
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local cell = Instance.new("Frame")
            cell.Position = UDim2.fromOffset(
                x * (cellSize + gap), y * (cellSize + gap)
            )
            cell.Size = UDim2.fromOffset(cellSize, cellSize)
            cell.BorderSizePixel = 1
            cell.BorderColor3 = Color3.fromRGB(75, 90, 110)
            cell.BackgroundColor3 = grid[y][x]
                and Color3.fromRGB(48, 83, 115)
                or Color3.fromRGB(38, 91, 65)
            cell.Parent = holder
        end
    end
end
local function calculateAndRender()
    local loot = scanLoot()
    local solution = solveInventory(loot)
    clearSolverVisual()
    for _, container in ipairs(CFG.Priority) do
        renderContainer(container, solution.grids[container])
    end
    solverInfo.Text = string.format(
        "Planned: %d | No fit: %d | Warnings: %d",
        #solution.plan, #solution.failures, #solution.invalid
    )
    for _, entry in ipairs(solution.invalid) do
        log("GRID WARNING: " .. entry.name .. " | " .. entry.reason)
    end
    task.defer(function()
        solverScroll.CanvasSize = UDim2.fromOffset(
            0, solverLayout.AbsoluteContentSize.Y + 8
        )
    end)
    updateStats()
end
local function debugInventory()
    print("========== HUSH INVENTORY DEBUG ==========")
    local gear = getGearItems()
    local counts = {
        pockets = 0,
        vest = 0,
        bag = 0,
        secure = 0,
        unmapped = 0,
    }
    for _, item in ipairs(gear) do
        if item.container and counts[item.container] ~= nil then
            counts[item.container] += 1
        else
            counts.unmapped += 1
        end
        local r = item.rect
        print(
            "SECTION:", item.section,
            "MAP:", tostring(item.container),
            "ITEM:", item.name,
            "UID:", tostring(item.uid),
            "RECT:", r.x, r.y, r.w, r.h
        )
    end
    print(
        "COUNTS:",
        "POCKETS", counts.pockets,
        "VEST", counts.vest,
        "BAG", counts.bag,
        "SECURE", counts.secure,
        "UNMAPPED", counts.unmapped
    )
    print("==========================================")
end
scanNow.MouseButton1Click:Connect(function()
    scanLoot()
    renderList()
    updateStats()
    log("Scan completed")
end)
addAll.MouseButton1Click:Connect(function()
    for _, item in ipairs(scanResults) do
        whitelist[upper(item.name)] = true
    end
    renderList()
    saveConfig()
    log("All scanned items added to whitelist")
end)
clearScan.MouseButton1Click:Connect(function()
    scanResults = {}
    renderList()
    updateStats()
end)
saveButton.MouseButton1Click:Connect(function()
    log(saveConfig() and "Whitelist saved locally" or "Save failed")
end)
clearList.MouseButton1Click:Connect(function()
    whitelist = {}
    saveConfig()
    renderList()
    log("Whitelist cleared")
end)
calculateButton.MouseButton1Click:Connect(calculateAndRender)
refreshButton.MouseButton1Click:Connect(calculateAndRender)
startButton.MouseButton1Click:Connect(function()
    startAutoPick()
    updateStats()
end)
stopButton.MouseButton1Click:Connect(function()
    stopAutoPick()
    updateStats()
end)
saveAuto.MouseButton1Click:Connect(function()
    log(saveConfig() and "Config saved locally" or "Save failed")
end)
local dragging = false
local dragStart
local startPosition
main.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (
        input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
    ) then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)
scanLoot()
renderList()
showPage("SCAN")
updateStats()
debugInventory()
task.defer(function()
    if gui and gui.Parent then
        startAutoPick()
        updateStats()
        log("Auto Pick AUTO-START enabled")
    end
end)
log("HUSH AUTO LOOT v1.7 loaded")
end)
do
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
if _G.OvertureHelperStop then
    pcall(_G.OvertureHelperStop)
end
local previousGui = PlayerGui:FindFirstChild("OvertureMapHelper")
if previousGui then
    previousGui:Destroy()
end
local previousWaypointGui = PlayerGui:FindFirstChild("OvertureLocalWaypoint")
if previousWaypointGui then
    previousWaypointGui:Destroy()
end
local ZoomEnabled = true
local ZoomDistance = 300
local SavedZoomOriginal = nil
local CameraZoomController = nil
local forceDayNoSnowEnabled = true
local atmosphereController = nil
local running = true
local connections = {}
local function getCameraController()
    if CameraZoomController
        and type(CameraZoomController.ZOOM_LEVELS) == "table" then
        return CameraZoomController
    end
    local playerScripts = Player:FindFirstChild("PlayerScripts")
    local hushClient = playerScripts
        and playerScripts:FindFirstChild("HushClient")
    local controllers = hushClient
        and hushClient:FindFirstChild("Controllers")
    local cameraModule = controllers
        and controllers:FindFirstChild("Camera")
    if not cameraModule then
        return nil
    end
    local ok, result = pcall(require, cameraModule)
    if ok and type(result) == "table"
        and type(result.ZOOM_LEVELS) == "table" then
        CameraZoomController = result
        return result
    end
    return nil
end
local function applyCameraZoom()
    if not ZoomEnabled then
        return false
    end
    local controller = getCameraController()
    local levels = controller and controller.ZOOM_LEVELS
    if type(levels) ~= "table" or #levels == 0 then
        return false
    end
    local finalLevel = levels[#levels]
    if type(finalLevel) ~= "table"
        or type(finalLevel.dist) ~= "number" then
        return false
    end
    if SavedZoomOriginal == nil then
        SavedZoomOriginal = finalLevel.dist
    end
    finalLevel.dist = ZoomDistance
    return true
end
local function restoreCameraZoom()
    local controller = getCameraController()
    local levels = controller and controller.ZOOM_LEVELS
    local finalLevel = type(levels) == "table" and levels[#levels]
    if type(finalLevel) == "table"
        and SavedZoomOriginal ~= nil then
        finalLevel.dist = SavedZoomOriginal
    end
end
local function findAtmosphereController()
    if atmosphereController
        and type(atmosphereController.setOverride) == "function"
        and type(atmosphereController.clearOverride) == "function" then
        return atmosphereController
    end
    if type(getgc) ~= "function" then
        return nil, "GETGC UNAVAILABLE"
    end
    local ok, objects = pcall(getgc, true)
    if not ok or type(objects) ~= "table" then
        return nil, "CANNOT READ CLIENT OBJECTS"
    end
    for _, object in ipairs(objects) do
        if type(object) == "table"
            and object.name == "Atmosphere"
            and type(object.setOverride) == "function"
            and type(object.clearOverride) == "function" then
            atmosphereController = object
            return object
        end
    end
    return nil, "WAITING FOR ATMOSPHERE"
end
local function applyDayNoSnow()
    local controller, reason = findAtmosphereController()
    if not controller then
        return false, tostring(reason)
    end
    local ok, result = pcall(function()
        controller.setOverride("Raid", "Day", "Clear", 0)
    end)
    if ok then
        return true, "FORCE DAY + NO SNOW ACTIVE"
    end
    warn("[OVERTURE] Force Day / No Snow failed: " .. tostring(result))
    return false, "OVERRIDE FAILED"
end
local function restoreEnvironment()
    local controller = atmosphereController
    if not controller then
        controller = findAtmosphereController()
    end
    if not controller then
        return false, "CONTROLLER NOT FOUND"
    end
    local ok, result = pcall(function()
        controller.clearOverride(0)
    end)
    if ok then
        return true, "GAME DEFAULT RESTORED"
    end
    warn("[OVERTURE] Environment restore failed: " .. tostring(result))
    return false, "RESTORE FAILED"
end
local Theme = {
    Background = Color3.fromRGB(17, 20, 26),
    Surface = Color3.fromRGB(28, 33, 41),
    Accent = Color3.fromRGB(40, 190, 153),
    Text = Color3.fromRGB(242, 244, 247),
    Muted = Color3.fromRGB(145, 152, 164),
    Border = Color3.fromRGB(48, 55, 65),
    Red = Color3.fromRGB(205, 75, 80)
}
local function create(className, props, parent)
    local object = Instance.new(className)
    for key, value in pairs(props or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end
local function round(object, radius)
    create("UICorner", {
        CornerRadius = UDim.new(0, radius or 7)
    }, object)
end
local function track(connection)
    table.insert(connections, connection)
    return connection
end
local gui = create("ScreenGui", {
    Name = "OvertureMapHelper",
    ResetOnSpawn = false,
    DisplayOrder = 999,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, PlayerGui)
local main = create("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(270, 225),
    Position = UDim2.new(0, 22, 0.35, 0),
    BackgroundColor3 = Theme.Background,
    BackgroundTransparency = 0.22,
    BorderSizePixel = 0
}, gui)
local overtureScale = Instance.new("UIScale")
overtureScale.Scale = 0.82
overtureScale.Parent = main
round(main, 10)
create("UIStroke", {
    Color = Theme.Border,
    Thickness = 1,
    Transparency = 0.15
}, main)
local header = create("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundTransparency = 1,
    BorderSizePixel = 0
}, main)
local title = create("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(13, 0),
    Size = UDim2.new(1, -60, 1, 0),
    Font = Enum.Font.GothamBold,
    Text = "OVERTURE MAP HELPER",
    TextSize = 12,
    TextColor3 = Theme.Accent,
    TextXAlignment = Enum.TextXAlignment.Left
}, header)
local closeButton = create("TextButton", {
    Position = UDim2.new(1, -31, 0, 7),
    Size = UDim2.fromOffset(23, 23),
    BackgroundColor3 = Theme.Red,
    BorderSizePixel = 0,
    Text = "×",
    TextColor3 = Theme.Text,
    Font = Enum.Font.GothamBold,
    TextSize = 16
}, header)
round(closeButton, 5)
create("Frame", {
    Position = UDim2.new(0, 10, 0, 38),
    Size = UDim2.new(1, -20, 0, 1),
    BackgroundColor3 = Theme.Border,
    BorderSizePixel = 0
}, main)
local function makeRow(y, labelText, initialText)
    local label = create("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(13, y),
        Size = UDim2.new(1, -115, 0, 25),
        Font = Enum.Font.GothamSemibold,
        Text = labelText,
        TextSize = 11,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left
    }, main)
    local toggle = create("TextButton", {
        Position = UDim2.new(1, -88, 0, y - 1),
        Size = UDim2.fromOffset(75, 27),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Text = initialText,
        TextColor3 = Theme.Text,
        Font = Enum.Font.GothamBold,
        TextSize = 10
    }, main)
    round(toggle, 6)
    return label, toggle
end
local _, environmentToggle = makeRow(49, "FORCE DAY + NO SNOW", "ON")
local environmentStatus = create("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(13, 77),
    Size = UDim2.new(1, -26, 0, 17),
    Font = Enum.Font.Gotham,
    Text = "STATUS: WAITING...",
    TextSize = 9,
    TextColor3 = Theme.Muted,
    TextXAlignment = Enum.TextXAlignment.Left
}, main)
local _, zoomToggle = makeRow(101, "CAMERA ZOOM OUT", "ON")
local zoomInput = create("TextBox", {
    Position = UDim2.fromOffset(13, 134),
    Size = UDim2.fromOffset(100, 29),
    BackgroundColor3 = Theme.Surface,
    BorderSizePixel = 0,
    Text = tostring(ZoomDistance),
    PlaceholderText = "300",
    TextColor3 = Theme.Text,
    PlaceholderColor3 = Theme.Muted,
    Font = Enum.Font.Gotham,
    TextSize = 11,
    ClearTextOnFocus = false
}, main)
round(zoomInput, 5)
local zoomHint = create("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(122, 134),
    Size = UDim2.new(1, -135, 0, 29),
    Font = Enum.Font.Gotham,
    Text = "Zoom distance (1–1000)",
    TextSize = 9,
    TextColor3 = Theme.Muted,
    TextXAlignment = Enum.TextXAlignment.Left
}, main)
local zoomStatus = create("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(13, 169),
    Size = UDim2.new(1, -26, 0, 17),
    Font = Enum.Font.Gotham,
    Text = "STATUS: WAITING...",
    TextSize = 9,
    TextColor3 = Theme.Muted,
    TextXAlignment = Enum.TextXAlignment.Left
}, main)
local waypointStatus = create("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(13, 190),
    Size = UDim2.new(1, -26, 0, 17),
    Font = Enum.Font.Gotham,
    Text = "WAYPOINT: WAITING...",
    TextSize = 9,
    TextColor3 = Theme.Muted,
    TextXAlignment = Enum.TextXAlignment.Left
}, main)
local function updateToggle(toggle, enabled, onText, offText)
    toggle.Text = enabled and onText or offText
    toggle.BackgroundColor3 = enabled and Theme.Accent or Theme.Border
end
local dragging = false
local dragInput
local dragStart
local startPosition
track(header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragInput = input
        dragStart = input.Position
        startPosition = main.Position
    end
end))
track(UserInputService.InputChanged:Connect(function(input)
    local valid = input == dragInput
        or (dragInput
            and dragInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement)
    if dragging and valid then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end))
track(UserInputService.InputEnded:Connect(function(input)
    if input == dragInput
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
        dragInput = nil
    end
end))
local function setEnvironmentStatus(message, active)
    environmentStatus.Text = "STATUS: " .. message
    environmentStatus.TextColor3 = active and Theme.Accent or Theme.Muted
end
local function setZoomStatus(message, active)
    zoomStatus.Text = "STATUS: " .. message
    zoomStatus.TextColor3 = active and Theme.Accent or Theme.Muted
end
local WAYPOINT_POSITION = Vector3.new(
    97.73350524902344,
    12.699987411499023,
    -226.89431762695312
)
local waypointHudGui = nil
local waypointHolder = nil
local waypointCap = nil
local waypointArrow = nil
local waypointPing = nil
local waypointTextLabels = {}
local waypointFallback = nil
local waypointRenderConnection = nil
local function findGuiObject(root, name)
    if not root then return nil end
    local found = root:FindFirstChild(name)
    if found and found:IsA("GuiObject") then
        return found
    end
    return nil
end
local function setGuiText(object, value)
    if not object then return end
    if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
        object.Text = value
    end
    for _, descendant in ipairs(object:GetDescendants()) do
        if descendant:IsA("TextLabel")
            or descendant:IsA("TextButton")
            or descendant:IsA("TextBox") then
            descendant.Text = value
        end
    end
end
local function getObjectSize(object, fallbackX, fallbackY)
    if object then
        local size = object.AbsoluteSize
        if size.X > 0 and size.Y > 0 then
            return size.X, size.Y
        end
    end
    return fallbackX, fallbackY
end
local function makeFallbackWaypoint(parent)
    local fallback = create("Frame", {
        Name = "FallbackWaypoint",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(210, 34),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 20
    }, parent)
    local arrow = create("TextLabel", {
        Name = "Arrow",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundTransparency = 1,
        Text = "➤",
        TextColor3 = Color3.fromRGB(116, 190, 255),
        TextStrokeTransparency = 0.35,
        Font = Enum.Font.GothamBold,
        TextSize = 25,
        Rotation = 0,
        ZIndex = 21
    }, fallback)
    local label = create("TextLabel", {
        Name = "Label",
        Position = UDim2.fromOffset(34, 0),
        Size = UDim2.fromOffset(176, 30),
        BackgroundTransparency = 1,
        Text = "YOUR WAYPOINT  0 m",
        TextColor3 = Color3.fromRGB(165, 205, 255),
        TextStrokeTransparency = 0.45,
        Font = Enum.Font.Code,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 21
    }, fallback)
    return fallback, arrow, label
end
local function createLocalWaypoint()
    local sourceGui = PlayerGui:FindFirstChild("HushPings")
    local sourceRoot = sourceGui and sourceGui:FindFirstChild("Root")
    local sourceCap = findGuiObject(sourceRoot, "Cap_waypoint")
    local sourceArrow = findGuiObject(sourceRoot, "Arrow_waypoint")
    local sourcePing = findGuiObject(sourceRoot, "Ping_waypoint")
    waypointHudGui = create("ScreenGui", {
        Name = "OvertureLocalWaypoint",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 10000,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    }, PlayerGui)
    waypointHolder = create("Frame", {
        Name = "WaypointHolder",
        Size = UDim2.fromOffset(1, 1),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false
    }, waypointHudGui)
    if sourceCap and sourceArrow and sourcePing then
        local capW, capH = getObjectSize(sourceCap, 18, 18)
        local arrowW, arrowH = getObjectSize(sourceArrow, 22, 22)
        local pingW, pingH = getObjectSize(sourcePing, 150, 22)
        waypointCap = sourceCap:Clone()
        waypointCap.Name = "Local_Cap_waypoint"
        waypointCap.Visible = true
        waypointCap.AnchorPoint = Vector2.new(0.5, 0.5)
        waypointCap.Size = UDim2.fromOffset(capW, capH)
        waypointCap.Position = UDim2.fromOffset(-pingW * 0.5 - 10, 0)
        waypointCap.Parent = waypointHolder
        waypointArrow = sourceArrow:Clone()
        waypointArrow.Name = "Local_Arrow_waypoint"
        waypointArrow.Visible = true
        waypointArrow.AnchorPoint = Vector2.new(0.5, 0.5)
        waypointArrow.Size = UDim2.fromOffset(arrowW, arrowH)
        waypointArrow.Position = UDim2.fromOffset(-pingW * 0.5 - 10, 0)
        waypointArrow.Parent = waypointHolder
        waypointPing = sourcePing:Clone()
        waypointPing.Name = "Local_Ping_waypoint"
        waypointPing.Visible = true
        waypointPing.AnchorPoint = Vector2.new(0, 0.5)
        waypointPing.Size = UDim2.fromOffset(pingW, pingH)
        waypointPing.Position = UDim2.fromOffset(-pingW * 0.5 + 8, 0)
        waypointPing.Parent = waypointHolder
        setGuiText(waypointPing, "YOUR WAYPOINT  0 m")
    else
        waypointFallback, waypointArrow, waypointPing = makeFallbackWaypoint(waypointHolder)
        waypointFallback.Visible = true
        waypointHolder.Size = UDim2.fromOffset(210, 34)
        waypointFallback.Position = UDim2.fromOffset(0, 0)
        waypointStatus.Text = "WAYPOINT: USING FALLBACK HUD"
        waypointStatus.TextColor3 = Theme.Muted
    end
    return true
end
local function updateLocalWaypoint()
    if not running or not waypointHudGui or not waypointHudGui.Parent then
        return
    end
    local camera = workspace.CurrentCamera
    local character = Player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not camera or not rootPart then
        waypointHolder.Visible = false
        return
    end
    local screenPoint, onScreen = camera:WorldToViewportPoint(WAYPOINT_POSITION)
    local viewport = camera.ViewportSize
    local screenCenter = Vector2.new(viewport.X * 0.5, viewport.Y * 0.5)
    local targetPoint = Vector2.new(screenPoint.X, screenPoint.Y)
    local direction = targetPoint - screenCenter
    if screenPoint.Z < 0 then
        direction = -direction
    end
    if direction.Magnitude < 0.001 then
        direction = Vector2.new(0, -1)
    else
        direction = direction.Unit
    end
    local marginX, marginY = 48, 48
    local maxX = math.max(marginX, viewport.X - marginX)
    local maxY = math.max(marginY, viewport.Y - marginY)
    local markerPoint
    if onScreen then
        markerPoint = Vector2.new(
            math.clamp(screenPoint.X, marginX, maxX),
            math.clamp(screenPoint.Y, marginY, maxY)
        )
    else
        local halfW = math.max(1, viewport.X * 0.5 - marginX)
        local halfH = math.max(1, viewport.Y * 0.5 - marginY)
        local scaleX = direction.X == 0 and math.huge or halfW / math.abs(direction.X)
        local scaleY = direction.Y == 0 and math.huge or halfH / math.abs(direction.Y)
        local scale = math.min(scaleX, scaleY)
        markerPoint = screenCenter + direction * scale
    end
    waypointHolder.Position = UDim2.fromOffset(markerPoint.X, markerPoint.Y)
    waypointHolder.Visible = true
    local distance = (WAYPOINT_POSITION - rootPart.Position).Magnitude
    local distanceText = string.format("YOUR WAYPOINT  %d m", math.floor(distance + 0.5))
    if waypointFallback then
        local label = waypointFallback:FindFirstChild("Label")
        if label and label:IsA("TextLabel") then
            label.Text = distanceText
        end
        local arrowLabel = waypointFallback:FindFirstChild("Arrow")
        if arrowLabel then
            arrowLabel.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
        end
    else
        setGuiText(waypointPing, distanceText)
        if waypointArrow then
            waypointArrow.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90
        end
    end
end
local function startLocalWaypoint()
    waypointStatus.Text = "WAYPOINT: CREATING LOCAL HUD..."
    waypointStatus.TextColor3 = Theme.Muted
    local ok, err = pcall(createLocalWaypoint)
    if not ok then
        waypointStatus.Text = "WAYPOINT: HUD ERROR"
        waypointStatus.TextColor3 = Theme.Red
        warn("[OVERTURE HELPER] Local waypoint creation failed: " .. tostring(err))
        return
    end
    if waypointRenderConnection then
        waypointRenderConnection:Disconnect()
    end
    waypointRenderConnection = RunService.RenderStepped:Connect(updateLocalWaypoint)
    table.insert(connections, waypointRenderConnection)
    waypointStatus.Text = "WAYPOINT: LOCAL HUD ACTIVE"
    waypointStatus.TextColor3 = Theme.Accent
    print("[OVERTURE HELPER] Local waypoint HUD active (no server ping)")
end
track(environmentToggle.MouseButton1Click:Connect(function()
    forceDayNoSnowEnabled = not forceDayNoSnowEnabled
    updateToggle(environmentToggle, forceDayNoSnowEnabled, "ON", "OFF")
    if forceDayNoSnowEnabled then
        local ok, message = applyDayNoSnow()
        setEnvironmentStatus(message, ok)
    else
        local ok, message = restoreEnvironment()
        setEnvironmentStatus(message, false)
    end
end))
track(zoomToggle.MouseButton1Click:Connect(function()
    ZoomEnabled = not ZoomEnabled
    updateToggle(zoomToggle, ZoomEnabled, "ON", "OFF")
    if ZoomEnabled then
        local ok = applyCameraZoom()
        setZoomStatus(ok and "CAMERA ZOOM PATCHED" or "WAITING FOR CAMERA", ok)
    else
        restoreCameraZoom()
        setZoomStatus("ZOOM DISABLED", false)
    end
end))
track(zoomInput.FocusLost:Connect(function()
    local value = tonumber(zoomInput.Text)
    if not value then
        zoomInput.Text = tostring(ZoomDistance)
        return
    end
    ZoomDistance = math.clamp(math.floor(value), 1, 1000)
    zoomInput.Text = tostring(ZoomDistance)
    if ZoomEnabled then
        local ok = applyCameraZoom()
        setZoomStatus(
            ok and ("DISTANCE SET TO " .. ZoomDistance) or "WAITING FOR CAMERA",
            ok
        )
    end
end))

--==================================================
-- OVERTURE INTEGRATED HEAD LOCK
-- RMB HOLD | HEAD PRIORITY | STICKY TARGET
-- NO EXTRA GUI
--==================================================
local AimConfig = {
    Enabled = true,
    FOV = 80,
    MaxDistance = 1000,
    AimPart = "Head",
    LockMouse = true,
    ShowFOV = true,
    CorpseFilter = true,
    StickyLock = true,
    OffsetX = 30,
    OffsetY = 65,
    ZoomScale = 1,
    ReferenceZoom = 159.32,
    Debug = false
}

local AimZombies = workspace:WaitForChild("HushLocal"):WaitForChild("Zombies")
local AimHoldingRMB = false
local AimLockedZombie = nil
local AimLockedHead = nil
local AimCircle = nil

local AimMoveMouse = (typeof(mousemoveabs) == "function" and mousemoveabs)
    or (typeof(getgenv) == "function"
        and typeof(getgenv().mousemoveabs) == "function"
        and getgenv().mousemoveabs)
    or nil

local AimGuiService = game:GetService("GuiService")

local function aimGetZoomDistance(camera)
    if not camera then return 0 end
    local character = Player.Character
    local root = character and (
        character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("Head")
    )
    if root and root:IsA("BasePart") then
        return (camera.CFrame.Position - root.Position).Magnitude
    end
    if AimLockedHead and AimLockedHead.Parent then
        return (camera.CFrame.Position - AimLockedHead.Position).Magnitude
    end
    return 0
end

local function aimGetEffectiveOffset(camera)
    local zoomDistance = aimGetZoomDistance(camera)
    local factor = 1
    if AimConfig.ZoomScale ~= 1
        and AimConfig.ReferenceZoom > 0
        and zoomDistance > 0 then
        local ratio = zoomDistance / AimConfig.ReferenceZoom
        factor = 1 + (ratio - 1) * (AimConfig.ZoomScale - 1)
    end
    return Vector2.new(
        AimConfig.OffsetX * factor,
        AimConfig.OffsetY * factor
    )
end

local function aimGetScreenCenter(camera)
    if not camera then return Vector2.zero end
    local inset = AimGuiService:GetGuiInset()
    if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
        return Vector2.new(
            camera.ViewportSize.X * 0.5 + inset.X,
            camera.ViewportSize.Y * 0.5 + inset.Y
        )
    end
    return UserInputService:GetMouseLocation()
end

local function aimGetHeadScreenPosition(head, camera)
    if not camera or not head or not head.Parent then return nil end
    local position, visible = camera:WorldToScreenPoint(head.Position)
    if not visible or position.Z <= 0 then return nil end
    local offset = aimGetEffectiveOffset(camera)
    return Vector2.new(position.X + offset.X, position.Y + offset.Y)
end

local function aimMoveMouse(screenPosition)
    if not AimConfig.LockMouse or not AimMoveMouse or not screenPosition then
        return
    end
    pcall(function()
        AimMoveMouse(math.round(screenPosition.X), math.round(screenPosition.Y))
    end)
end

local function aimGetHead(zombie)
    if not zombie or not zombie.Parent then return nil end
    local head = zombie:FindFirstChild(AimConfig.AimPart)
    if head and head:IsA("BasePart") then return head end
    return nil
end

local function aimIsAlive(zombie)
    if not zombie or not zombie.Parent then return false end
    if AimConfig.CorpseFilter and zombie:GetAttribute("Corpse") == true then
        return false
    end
    local humanoid = zombie:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    if humanoid:GetState() == Enum.HumanoidStateType.Dead then return false end
    return aimGetHead(zombie) ~= nil
end

local function aimAcquireTarget(aimPosition, camera)
    if not camera then return nil, nil end
    local bestZombie, bestHead = nil, nil
    local bestDistance = AimConfig.FOV

    for _, zombie in ipairs(AimZombies:GetChildren()) do
        if aimIsAlive(zombie) then
            local head = aimGetHead(zombie)
            if head then
                local worldDistance =
                    (head.Position - camera.CFrame.Position).Magnitude
                if worldDistance <= AimConfig.MaxDistance then
                    local screenPosition =
                        aimGetHeadScreenPosition(head, camera)
                    if screenPosition then
                        local distance = (screenPosition - aimPosition).Magnitude
                        if distance < bestDistance then
                            bestDistance = distance
                            bestZombie = zombie
                            bestHead = head
                        end
                    end
                end
            end
        end
    end
    return bestZombie, bestHead
end

local function aimIsTargetValid(camera)
    if not AimLockedZombie or not AimLockedHead or not camera then
        return false
    end
    if not aimIsAlive(AimLockedZombie) then return false end
    if aimGetHead(AimLockedZombie) ~= AimLockedHead then return false end
    return (AimLockedHead.Position - camera.CFrame.Position).Magnitude
        <= AimConfig.MaxDistance
end

local function aimReleaseTarget(reason)
    if AimLockedZombie and AimConfig.Debug then
        print("[OVERTURE AIM] RELEASE:", reason)
    end
    AimLockedZombie = nil
    AimLockedHead = nil
end

local function aimLockTarget(zombie, head)
    AimLockedZombie = zombie
    AimLockedHead = head
    if AimConfig.Debug then
        print("[OVERTURE AIM] LOCKED:", zombie.Name)
    end
end

if Drawing and Drawing.new and AimConfig.ShowFOV then
    pcall(function()
        AimCircle = Drawing.new("Circle")
        AimCircle.Visible = false
        AimCircle.Radius = AimConfig.FOV
        AimCircle.Thickness = 1.5
        AimCircle.NumSides = 64
        AimCircle.Filled = false
        AimCircle.Color = Color3.fromRGB(255, 255, 255)
        AimCircle.Transparency = 1
    end)
end

track(UserInputService.InputBegan:Connect(function(input, processed)
    if processed or not running or not AimConfig.Enabled then return end
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        AimHoldingRMB = true
        local camera = workspace.CurrentCamera
        local aimPosition = aimGetScreenCenter(camera)
        local zombie, head = aimAcquireTarget(aimPosition, camera)
        if zombie and head then
            aimLockTarget(zombie, head)
        else
            aimReleaseTarget("NO TARGET IN FOV")
        end
    end
end))

track(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        AimHoldingRMB = false
        aimReleaseTarget("RMB RELEASED")
    end
end))

track(RunService.RenderStepped:Connect(function()
    if not running then return end
    local camera = workspace.CurrentCamera
    if not camera then return end

    local aimPosition = aimGetScreenCenter(camera)
    if AimCircle then
        AimCircle.Position = aimPosition
        AimCircle.Radius = AimConfig.FOV
        AimCircle.Visible = AimConfig.Enabled and AimConfig.ShowFOV
    end

    if not AimConfig.Enabled or not AimHoldingRMB then return end

    if not AimConfig.StickyLock or not aimIsTargetValid(camera) then
        local zombie, head = aimAcquireTarget(aimPosition, camera)
        if zombie and head then
            aimLockTarget(zombie, head)
        else
            aimReleaseTarget("TARGET LOST")
            return
        end
    end

    local lockPosition = aimGetHeadScreenPosition(AimLockedHead, camera)
    if lockPosition then
        aimMoveMouse(lockPosition)
    end
end))

print("[OVERTURE AIM] Integrated head lock loaded | Hold RMB")

local function cleanup()
    if not running then return end
    running = false
    AimHoldingRMB = false
    aimReleaseTarget("OVERTURE UNLOADED")
    if AimCircle then
        pcall(function() AimCircle:Remove() end)
        AimCircle = nil
    end
    if forceDayNoSnowEnabled then
        restoreEnvironment()
    end
    restoreCameraZoom()
    if waypointHudGui and waypointHudGui.Parent then
        waypointHudGui:Destroy()
    end
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    if gui and gui.Parent then
        gui:Destroy()
    end
end
_G.OvertureHelperStop = cleanup
track(closeButton.MouseButton1Click:Connect(cleanup))
updateToggle(environmentToggle, forceDayNoSnowEnabled, "ON", "OFF")
updateToggle(zoomToggle, ZoomEnabled, "ON", "OFF")
startLocalWaypoint()
task.spawn(function()
    while running and gui.Parent and forceDayNoSnowEnabled do
        local ok, message = applyDayNoSnow()
        setEnvironmentStatus(message, ok)
        if ok then
            break
        end
        task.wait(1)
    end
end)
task.spawn(function()
    while running and gui.Parent and ZoomEnabled do
        local ok = applyCameraZoom()
        if ok then
            setZoomStatus("CAMERA ZOOM PATCHED", true)
            break
        end
        setZoomStatus("WAITING FOR CAMERA", false)
        task.wait(1)
    end
end)
print("[OVERTURE HELPER] Force Day + No Snow: AUTO ON")
print("[OVERTURE HELPER] Hush Camera Zoom: AUTO ON")
print("[OVERTURE HELPER] Local Waypoint HUD: AUTO ON")
print("[OVERTURE HELPER] Loaded")
end
task.spawn(function()
    local Players = game:GetService("Players")
    local CoreGui = game:GetService("CoreGui")
    local UIS = game:GetService("UserInputService")
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local function findLootGui()
        local root = (gethui and gethui()) or CoreGui
        return root:FindFirstChild("HushAutoLootV17", true)
            or CoreGui:FindFirstChild("HushAutoLootV17", true)
    end
    local function findOvertureGui()
        return playerGui:FindFirstChild("OvertureMapHelper")
    end
    local old = playerGui:FindFirstChild("HushUltimateHub")
    if old then old:Destroy() end
    local lootGui, overtureGui
    for _ = 1, 1200 do -- wait up to 5 minutes for inventory UI
        lootGui = findLootGui()
        overtureGui = findOvertureGui()
        if lootGui and overtureGui then break end
        task.wait(0.25)
    end
    if not lootGui or not overtureGui then
        warn("[HUSH ULTIMATE HUB] Could not locate both module GUIs")
        return
    end
    local lootMain = lootGui:FindFirstChild("Main", true)
    local overtureMain = overtureGui:FindFirstChild("Main", true)
    if not lootMain or not overtureMain then
        warn("[HUSH ULTIMATE HUB] Could not locate module panels")
        return
    end
    local hubGui = Instance.new("ScreenGui")
    hubGui.Name = "HushUltimateHub"
    hubGui.ResetOnSpawn = false
    hubGui.DisplayOrder = 1000000
    hubGui.IgnoreGuiInset = true
    hubGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hubGui.Parent = playerGui
    local window = Instance.new("Frame")
    window.Name = "Window"
    window.Size = UDim2.fromOffset(250, 370)
    window.Position = UDim2.new(0, 12, 0, 80)
    window.BackgroundColor3 = Color3.fromRGB(16, 19, 26)
    window.BackgroundTransparency = 0.12
    window.BorderSizePixel = 0
    window.ClipsDescendants = true
    window.Active = true
    window.Parent = hubGui
    Instance.new("UICorner", window).CornerRadius = UDim.new(0, 10)
    local outline = Instance.new("UIStroke", window)
    outline.Color = Color3.fromRGB(57, 75, 96)
    outline.Transparency = 0.2
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundColor3 = Color3.fromRGB(22, 27, 36)
    header.BackgroundTransparency = 0.08
    header.BorderSizePixel = 0
    header.Parent = window
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.fromOffset(12, 0)
    title.Size = UDim2.new(1, -24, 1, 0)
    title.Font = Enum.Font.GothamBold
    title.Text = "HUSH ULTIMATE HUB"
    title.TextColor3 = Color3.fromRGB(75, 210, 174)
    title.TextSize = 10
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header
    local nav = Instance.new("Frame")
    nav.Position = UDim2.fromOffset(8, 48)
    nav.Size = UDim2.new(1, -16, 0, 34)
    nav.BackgroundColor3 = Color3.fromRGB(26, 32, 42)
    nav.BackgroundTransparency = 0.05
    nav.BorderSizePixel = 0
    nav.Parent = window
    Instance.new("UICorner", nav).CornerRadius = UDim.new(0, 7)
    local function makeTab(text, x)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(0.5, -3, 1, -6)
        b.Position = UDim2.fromOffset(x, 3)
        b.BackgroundColor3 = Color3.fromRGB(40, 190, 153)
        b.BackgroundTransparency = 0.05
        b.BorderSizePixel = 0
        b.Text = text
        b.TextColor3 = Color3.fromRGB(245, 247, 250)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 10
        b.Parent = nav
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        return b
    end
    local lootTab = makeTab("AUTO LOOT", 3)
    local overtureTab = makeTab("OVERTURE",  (nav.AbsoluteSize.X / 2) + 1)
    overtureTab.Position = UDim2.new(0.5, 0, 0, 3)
    local pages = Instance.new("Frame")
    pages.Position = UDim2.fromOffset(3, 78)
    pages.Size = UDim2.new(1, -6, 1, -81)
    pages.BackgroundTransparency = 1
    pages.ClipsDescendants = true
    pages.Parent = window
    local lootPage = Instance.new("Frame")
    lootPage.Name = "AutoLootPage"
    lootPage.Size = UDim2.fromScale(1, 1)
    lootPage.BackgroundTransparency = 1
    lootPage.ClipsDescendants = true
    lootPage.Parent = pages
    local overturePage = Instance.new("Frame")
    overturePage.Name = "OverturePage"
    overturePage.Size = UDim2.fromScale(1, 1)
    overturePage.BackgroundTransparency = 1
    overturePage.ClipsDescendants = true
    overturePage.Visible = false
    overturePage.Parent = pages
    local lootScale = Instance.new("UIScale")
    lootScale.Scale = 0.68
    lootScale.Parent = lootMain
    lootMain.Parent = lootPage
    lootMain.Position = UDim2.fromOffset(0, 0)
    lootMain.AnchorPoint = Vector2.new(0, 0)
    lootMain.BackgroundTransparency = 1
    lootMain.Active = true
    local overturePanelScale = Instance.new("UIScale")
    overturePanelScale.Scale = 0.78
    overturePanelScale.Parent = overtureMain
    overtureMain.Parent = overturePage
    overtureMain.Position = UDim2.fromOffset(2, 4)
    overtureMain.AnchorPoint = Vector2.new(0, 0)
    overtureMain.BackgroundTransparency = 0.35
    overtureMain.Active = true
    lootGui.Enabled = false
    overtureGui.Enabled = false
    local function showPage(which)
        local isLoot = which == "LOOT"
        lootPage.Visible = isLoot
        overturePage.Visible = not isLoot
        lootTab.BackgroundColor3 = isLoot and Color3.fromRGB(40, 190, 153) or Color3.fromRGB(43, 51, 64)
        overtureTab.BackgroundColor3 = (not isLoot) and Color3.fromRGB(40, 190, 153) or Color3.fromRGB(43, 51, 64)
    end
    lootTab.MouseButton1Click:Connect(function() showPage("LOOT") end)
    overtureTab.MouseButton1Click:Connect(function() showPage("OVERTURE") end)
    showPage("LOOT")
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragInput = input
            dragStart = input.Position
            startPos = window.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input == dragInput
            or (dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1
                and input.UserInputType == Enum.UserInputType.MouseMovement)) then
            local delta = input.Position - dragStart
            window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            dragInput = nil
        end
    end)
end)
print("[HUSH ULTIMATE HUB] Single-window two-page UI loaded")
