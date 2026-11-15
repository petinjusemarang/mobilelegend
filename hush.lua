--[[
    HUSH MARKET WATCHER v2.5.1
    MARKET ID SCANNER + PRICE WATCHER

    FEATURES:
    - Draggable / Minimize GUI
    - Automatic Market Grid ID scanner
    - Unique ID detection
    - Auto refresh when Grid changes
    - Copy all discovered IDs
    - Add discovered ID to Watchlist
    - Manual item ID input
    - Multi-item Watchlist
    - Per-item maximum price
    - bmItem market scanner
    - Lowest listing detection
    - Listing count
    - Target price detection
    - Force Scan
    - Start / Stop Monitor
    - Activity Log
    - Purchase Success Report
    - Copy / Clear Purchase Report
    - Anti-AFK
    - Per-item Auto Buy
]]

--==================================================
-- SERVICES
--==================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--==================================================
-- CONFIG
--==================================================

local CONFIG = {
    ScanInterval = 8,
    GridRefreshInterval = 2,
    RequestDelay = 0.4,
    AutoBuyCooldown = 5,

    DefaultWatchlist = {
        {
            id = "pistol_g17",
            name = "P17 Pistol",
            maxPrice = 5000,
            enabled = true,
            autoBuy = false,
            lastBuyAttempt = 0
        },
        {
            id = "key_a_infirmary",
            name = "Key A Infirmary",
            maxPrice = 40000,
            enabled = true,
            autoBuy = false,
            lastBuyAttempt = 0
        },
        {
            id = "rifle_ot5_gold",
            name = "Golden OT-5",
            maxPrice = 6000000,
            enabled = true,
            autoBuy = false,
            lastBuyAttempt = 0
        }
    }
}

--==================================================
-- REMOTES
--==================================================

local HushNet = ReplicatedStorage:WaitForChild("HushNet")
local MenuGet = HushNet:WaitForChild("menu.get")
local MenuOp = HushNet:WaitForChild("menu.op")

--==================================================
-- STATE
--==================================================

local Watchlist = {}
local Results = {}

local DiscoveredIDs = {}
local DiscoveredSet = {}

local Monitoring = false
local AntiAFKEnabled = false
local AntiAFKConnection = nil
local Scanning = false
local GridScanning = false

local ScanToken = 0
local TotalScans = 0

local ActivityLog = {}

local ScreenGui
local Main
local Content
local StatusText
local ScanCountText

local WatchlistFrame
local IDFrame
local LogFrame

local ItemIdBox
local ItemNameBox
local MaxPriceBox

local IDCountText
local GridStatusText
local IDSearchBox

local function cloneTable(source)
    local result = {}
    for k, v in pairs(source) do
        if type(v) == "table" then result[k] = cloneTable(v) else result[k] = v end
    end
    return result
end

-- Executor-backed persistence. If file APIs are unavailable, the script still runs normally.
local SAVE_FILE = "HushMarketWatcher_v25_save.json"
local SavedState = nil
local SavedPurchaseRecords = {}
local PurchaseRecords -- forward declaration for persistence callbacks
local function loadSavedState()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return nil end
    local ok, exists = pcall(isfile, SAVE_FILE)
    if not ok or not exists then return nil end
    local readOK, raw = pcall(readfile, SAVE_FILE)
    if not readOK or type(raw) ~= "string" then return nil end
    local decodeOK, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if decodeOK and type(data) == "table" then return data end
    return nil
end

local function savePersistentState()
    if type(writefile) ~= "function" then return false end
    local state = {
        version = 1,
        watchlist = {},
        discoveredIDs = DiscoveredIDs,
        antiAFK = AntiAFKEnabled,
        purchases = PurchaseRecords or SavedPurchaseRecords or {}
    }
    for _, item in ipairs(Watchlist) do
        table.insert(state.watchlist, {
            id = item.id, name = item.name, maxPrice = item.maxPrice,
            enabled = item.enabled == true, autoBuy = item.autoBuy == true
        })
    end
    local ok, encoded = pcall(function() return HttpService:JSONEncode(state) end)
    if not ok then return false end
    return pcall(writefile, SAVE_FILE, encoded)
end

SavedState = loadSavedState()
if SavedState and type(SavedState.watchlist) == "table" then
    for _, item in ipairs(SavedState.watchlist) do
        if type(item) == "table" and type(item.id) == "string" and item.id ~= "" then
            table.insert(Watchlist, {
                id = item.id, name = tostring(item.name or item.id),
                maxPrice = tonumber(item.maxPrice) or 1,
                enabled = item.enabled == true, autoBuy = item.autoBuy == true,
                lastBuyAttempt = 0
            })
        end
    end
else
    for _, item in ipairs(CONFIG.DefaultWatchlist) do table.insert(Watchlist, cloneTable(item)) end
end
if SavedState and type(SavedState.discoveredIDs) == "table" then
    for _, id in ipairs(SavedState.discoveredIDs) do
        if type(id) == "string" and id ~= "" and not DiscoveredSet[id] then
            DiscoveredSet[id] = true
            table.insert(DiscoveredIDs, id)
        end
    end
    table.sort(DiscoveredIDs)
end
if SavedState and type(SavedState.purchases) == "table" then
    SavedPurchaseRecords = SavedState.purchases
end

--==================================================
-- COLORS
--==================================================

local COLORS = {
    Background = Color3.fromRGB(13, 15, 23),
    Panel = Color3.fromRGB(21, 24, 35),
    Panel2 = Color3.fromRGB(29, 33, 47),
    Border = Color3.fromRGB(54, 61, 82),

    Text = Color3.fromRGB(235, 238, 248),
    Muted = Color3.fromRGB(142, 151, 175),

    Accent = Color3.fromRGB(119, 91, 255),
    Green = Color3.fromRGB(68, 205, 133),
    Red = Color3.fromRGB(235, 83, 96),
    Orange = Color3.fromRGB(242, 172, 70)
}

--==================================================
-- UTILITIES
--==================================================

local function formatNumber(number)
    number = tonumber(number)

    if not number then
        return "N/A"
    end

    local result = tostring(math.floor(number))

    while true do
        local replaced, count = result:gsub(
            "^(-?%d+)(%d%d%d)",
            "%1,%2"
        )

        result = replaced

        if count == 0 then
            break
        end
    end

    return result
end

local function safeClipboard(value)
    local clipboard =
        setclipboard
        or toclipboard
        or (syn and syn.write_clipboard)

    if not clipboard then
        return false
    end

    return pcall(function()
        clipboard(value)
    end)
end

local function create(className, properties, parent)
    local object = Instance.new(className)

    for property, value in pairs(properties or {}) do
        object[property] = value
    end

    object.Parent = parent

    return object
end

local function corner(parent, radius)
    create("UICorner", {
        CornerRadius = UDim.new(0, radius or 7)
    }, parent)
end

local function stroke(parent, color, thickness)
    create("UIStroke", {
        Color = color or COLORS.Border,
        Thickness = thickness or 1
    }, parent)
end

local function makeLabel(parent, text, size, color, bold)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        Text = text or "",
        TextColor3 = color or COLORS.Text,
        TextSize = size or 12,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Size = UDim2.new(1, 0, 0, 22)
    }, parent)
end

local function makeButton(parent, text, callback, color, width)
    local button = create("TextButton", {
        BackgroundColor3 = color or COLORS.Panel2,
        Text = text,
        TextColor3 = COLORS.Text,
        TextSize = 11,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true,
        Size = UDim2.fromOffset(width or 100, 30)
    }, parent)

    corner(button, 6)
    stroke(button)

    button.MouseButton1Click:Connect(callback)

    return button
end

local function makeTextBox(parent, placeholder, width)
    local box = create("TextBox", {
        BackgroundColor3 = COLORS.Panel2,
        Text = "",
        PlaceholderText = placeholder,
        PlaceholderColor3 = COLORS.Muted,
        TextColor3 = COLORS.Text,
        TextSize = 11,
        Font = Enum.Font.Gotham,
        ClearTextOnFocus = false,
        Size = UDim2.fromOffset(width, 30)
    }, parent)

    corner(box, 6)
    stroke(box)

    return box
end

--==================================================
-- LOGGING
--==================================================

local function refreshLog()
    if not LogFrame then
        return
    end

    for _, child in ipairs(LogFrame:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    for index, entry in ipairs(ActivityLog) do
        create("TextLabel", {
            BackgroundTransparency = 1,
            Text = entry,
            TextColor3 = COLORS.Muted,
            TextSize = 9,
            Font = Enum.Font.Code,
            TextXAlignment = Enum.TextXAlignment.Left,
            Size = UDim2.new(1, -5, 0, 17),
            LayoutOrder = index
        }, LogFrame)
    end
end

local function log(message, category)
    local entry = string.format(
        "[%s] [%s] %s",
        os.date("%H:%M:%S"),
        category or "INFO",
        tostring(message)
    )

    table.insert(ActivityLog, 1, entry)

    while #ActivityLog > 150 do
        table.remove(ActivityLog)
    end

    print("[HUSH WATCHER] " .. entry)

    refreshLog()
end

--==================================================
-- WATCHLIST UTILITIES
--==================================================

local function findItem(itemId)
    for index, item in ipairs(Watchlist) do
        if item.id == itemId then
            return item, index
        end
    end

    return nil
end

local function addWatchlistItem(itemId, itemName, maxPrice)
    itemId = tostring(itemId or ""):gsub("^%s+", ""):gsub("%s+$", "")
    itemName = tostring(itemName or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if itemId == "" then
        return false, "Item ID is empty"
    end

    -- Accept 50000, 50,000, or $50,000
    if type(maxPrice) == "string" then
        maxPrice = maxPrice:gsub("[%$,]", ""):gsub("%s+", "")
    end
    maxPrice = tonumber(maxPrice)

    if not maxPrice or maxPrice <= 0 then
        return false, "Enter a valid maximum price"
    end

    local existing = findItem(itemId)
    if existing then
        existing.name = itemName ~= "" and itemName or existing.name or itemId
        existing.maxPrice = maxPrice
        existing.enabled = true
        Results[itemId] = nil
        savePersistentState()
        return true, "Updated existing Watchlist item"
    end

    table.insert(Watchlist, {
        id = itemId,
        name = itemName ~= "" and itemName or itemId,
        maxPrice = maxPrice,
        enabled = true,
        autoBuy = false,
        lastBuyAttempt = 0
    })

    savePersistentState()
    return true, "Added to Watchlist"
end

--==================================================
-- MARKET GRID ID SCANNER
--==================================================

local function getMarketGrid()
    local success, grid = pcall(function()
        return PlayerGui
            :WaitForChild("HushMenu", 5)
            .Root
            .Pages
            .Page_market
            .Market
            .Content
            .Inner
            .Body
            .Sub_browse
            .Grid
    end)

    if success then
        return grid
    end

    return nil
end

local function isValidItemID(value)
    if type(value) ~= "string" then
        return false
    end

    if value == "" then
        return false
    end

    -- Exclude obvious UI names
    if value:lower() == "icon" then
        return false
    end

    if value:lower() == "card" then
        return false
    end

    -- Item IDs commonly use letters, numbers and underscores
    return value:match("^[%w_%-]+$") ~= nil
end

local function addDiscoveredID(itemId)
    if not isValidItemID(itemId) then
        return false
    end

    if DiscoveredSet[itemId] then
        return false
    end

    DiscoveredSet[itemId] = true
    table.insert(DiscoveredIDs, itemId)

    return true
end

local function scanMarketGrid()
    if GridScanning then
        return
    end

    GridScanning = true

    local grid = getMarketGrid()

    if not grid then
        GridStatusText.Text = "GRID: NOT FOUND"
        GridStatusText.TextColor3 = COLORS.Red
        GridScanning = false
        return
    end

    local before = #DiscoveredIDs
    local foundThisScan = 0

    for _, card in ipairs(grid:GetChildren()) do
        -- Card structure observed:
        -- Grid > Card > Icon > Icon > item_id
        local outerIcon = card:FindFirstChild("Icon")

        if outerIcon then
            local innerIcon = outerIcon:FindFirstChild("Icon")

            if innerIcon then
                -- The detector also found ItemId attributes on cards.
                local attributeID = card:GetAttribute("ItemId")

                if attributeID then
                    if addDiscoveredID(tostring(attributeID)) then
                        foundThisScan = foundThisScan + 1
                    end
                end

                -- Item IDs are also represented by child instance names.
                for _, itemObject in ipairs(innerIcon:GetChildren()) do
                    if addDiscoveredID(itemObject.Name) then
                        foundThisScan = foundThisScan + 1
                    end
                end
            end
        end
    end

    table.sort(DiscoveredIDs)

    local added = #DiscoveredIDs - before

    IDCountText.Text = "DISCOVERED IDS: " .. tostring(#DiscoveredIDs)

    GridStatusText.Text = "GRID: CONNECTED"
    GridStatusText.TextColor3 = COLORS.Green

    if added > 0 then
        savePersistentState()
        log(
            "Market Grid updated: +" .. tostring(added) ..
            " new IDs (" .. tostring(#DiscoveredIDs) .. " total)",
            "ID SCANNER"
        )
    end

    GridScanning = false

    return foundThisScan
end

--==================================================
-- ID LIST UI
--==================================================

local function refreshIDList()
    if not IDFrame then
        return
    end

    for _, child in ipairs(IDFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    local query = IDSearchBox and IDSearchBox.Text or ""
    query = string.lower(tostring(query)):gsub("^%s+", ""):gsub("%s+$", "")

    local visibleIDs = {}
    for _, itemId in ipairs(DiscoveredIDs) do
        if query == "" or string.find(string.lower(itemId), query, 1, true) then
            table.insert(visibleIDs, itemId)
        end
    end

    IDCountText.Text = "SHOWING: " .. tostring(#visibleIDs) .. " / " .. tostring(#DiscoveredIDs)

    for index, itemId in ipairs(visibleIDs) do
        local row = create("Frame", {
            BackgroundColor3 = COLORS.Panel2,
            Size = UDim2.new(1, -6, 0, 34),
            BorderSizePixel = 0,
            LayoutOrder = index
        }, IDFrame)

        corner(row, 5)

        local label = makeLabel(
            row,
            itemId,
            10,
            COLORS.Text,
            true
        )

        label.Position = UDim2.fromOffset(8, 0)
        label.Size = UDim2.new(1, -105, 1, 0)

        local copyButton = makeButton(
            row,
            "COPY",
            function()
                if safeClipboard(itemId) then
                    log("Copied ID: " .. itemId, "ID SCANNER")
                else
                    log("Clipboard unavailable", "ERROR")
                end
            end,
            COLORS.Panel,
            42
        )

        copyButton.Position = UDim2.new(1, -96, 0, 2)

        local addButton = makeButton(
            row,
            "ADD",
            function()
                ItemIdBox.Text = itemId
                ItemNameBox.Text = itemId

                log("Selected ID: " .. itemId, "ID SCANNER")
            end,
            COLORS.Accent,
            42
        )

        addButton.Position = UDim2.new(1, -48, 0, 2)
    end
end

local function copyAllIDs()
    if #DiscoveredIDs == 0 then
        log("No IDs discovered yet", "WARNING")
        return
    end

    local output = table.concat(DiscoveredIDs, "\n")

    if safeClipboard(output) then
        log(
            "Copied " .. tostring(#DiscoveredIDs) .. " unique IDs",
            "ID SCANNER"
        )
    else
        log("Clipboard API unavailable", "ERROR")
    end
end

--==================================================
-- MARKET API
--==================================================

local function GetItem(itemId)
    if type(itemId) ~= "string" or itemId == "" then
        return nil, "Invalid item ID"
    end

    local success, response = pcall(function()
        return MenuGet:InvokeServer({
            offset = 0,
            id = itemId,
            what = "bmItem"
        })
    end)

    if not success then
        return nil, tostring(response)
    end

    if type(response) ~= "table" then
        return nil, "Response is not a table"
    end

    if response.ok ~= true then
        return nil, response.text or response.code or "Request rejected"
    end

    return response
end

local function autoBuyItem(item, lowest)
    if not item.autoBuy or not lowest then
        return false
    end

    if lowest.price > item.maxPrice then
        return false
    end

    local now = os.clock()
    if now - (item.lastBuyAttempt or 0) < CONFIG.AutoBuyCooldown then
        return false
    end
    item.lastBuyAttempt = now

    local payload = {
        op = "bmBuyBest",
        maxUnit = item.maxPrice,
        id = item.id,
        maxTotal = lowest.price,
        req = 1
    }

    local ok, err = pcall(function()
        MenuOp:FireServer(payload)
    end)

    if ok then
        log(
            "AUTO BUY SENT: " .. item.name ..
            " | ID: " .. item.id ..
            " | LIMIT: $" .. formatNumber(item.maxPrice) ..
            " | MAX TOTAL: $" .. formatNumber(lowest.price),
            "AUTO BUY"
        )
        return true
    end

    log("AUTO BUY ERROR: " .. item.id .. " | " .. tostring(err), "ERROR")
    return false
end

local function getLowestListing(listings)
    if type(listings) ~= "table" then
        return nil
    end

    local lowest

    for _, listing in pairs(listings) do
        if type(listing) == "table" then
            local price = tonumber(listing.p)

            if not price then
                price = tonumber(listing.u)
            end

            if price and price > 0 then
                if not lowest or price < lowest.price then
                    lowest = {
                        price = price,
                        unitPrice = tonumber(listing.u),
                        listingId = listing.lid,
                        quantity = tonumber(listing.n),
                        own = listing.own
                    }
                end
            end
        end
    end

    return lowest
end

--==================================================
-- WATCHLIST UI
--==================================================

local function refreshItems()
    if not WatchlistFrame then
        return
    end

    for _, child in ipairs(WatchlistFrame:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    for index, item in ipairs(Watchlist) do
        local result = Results[item.id] or {}

        local card = create("Frame", {
            BackgroundColor3 = COLORS.Panel2,
            Size = UDim2.new(1, -6, 0, 94),
            BorderSizePixel = 0,
            LayoutOrder = index
        }, WatchlistFrame)

        corner(card, 6)

        local nameLabel = makeLabel(
            card,
            item.name .. "  /  " .. item.id,
            10,
            COLORS.Text,
            true
        )

        nameLabel.Position = UDim2.fromOffset(8, 3)
        nameLabel.Size = UDim2.new(1, -300, 0, 18)

        local lowestText = "LOWEST: --"
        local countText = "LISTINGS: --"
        local targetText = "WAITING FOR SCAN"
        local targetColor = COLORS.Muted

        if result.success then
            countText = "LISTINGS: " .. tostring(result.count or 0)

            if result.lowest then
                lowestText = "LOWEST: $" .. formatNumber(result.lowest)

                if result.lowest <= item.maxPrice then
                    targetText = "TARGET REACHED"
                    targetColor = COLORS.Green
                else
                    targetText = "ABOVE MAX PRICE"
                    targetColor = COLORS.Orange
                end
            else
                lowestText = "LOWEST: NO LISTING"
                targetText = "NO ACTIVE LISTINGS"
            end
        elseif result.error then
            targetText = "ERROR: " .. tostring(result.error)
            targetColor = COLORS.Red
        end

        local lowestLabel = makeLabel(
            card,
            lowestText .. "   |   " .. countText,
            9,
            COLORS.Green,
            true
        )

        lowestLabel.Position = UDim2.fromOffset(8, 24)
        lowestLabel.Size = UDim2.new(1, -300, 0, 17)

        local targetLabel = makeLabel(
            card,
            targetText .. "   |   MAX: $" .. formatNumber(item.maxPrice),
            9,
            targetColor,
            true
        )

        targetLabel.Position = UDim2.fromOffset(8, 45)
        targetLabel.Size = UDim2.new(1, -300, 0, 17)

        local enabledButton = makeButton(
            card,
            item.enabled and "ON" or "OFF",
            function()
                item.enabled = not item.enabled
                savePersistentState()
                refreshItems()
            end,
            item.enabled and COLORS.Green or COLORS.Red,
            38
        )

        enabledButton.Position = UDim2.new(1, -250, 0, 5)

        local editButton = makeButton(
            card,
            "EDIT",
            function()
                ItemIdBox.Text = item.id
                ItemNameBox.Text = item.name
                MaxPriceBox.Text = tostring(item.maxPrice)
            end,
            COLORS.Accent,
            38
        )

        editButton.Position = UDim2.new(1, -206, 0, 5)

        local deleteButton = makeButton(
            card,
            "DEL",
            function()
                table.remove(Watchlist, index)
                Results[item.id] = nil
                savePersistentState()
                refreshItems()
                log("Removed " .. item.id, "WATCHLIST")
            end,
            COLORS.Red,
            38
        )

        deleteButton.Position = UDim2.new(1, -162, 0, 5)

        local autoBuyButton = makeButton(
            card,
            item.autoBuy and "AUTO BUY ON" or "AUTO BUY OFF",
            function()
                item.autoBuy = not item.autoBuy
                savePersistentState()
                log(
                    (item.autoBuy and "Auto-buy enabled: " or "Auto-buy disabled: ") .. item.id,
                    "AUTO BUY"
                )
                refreshItems()
            end,
            item.autoBuy and COLORS.Green or COLORS.Panel,
            112
        )

        autoBuyButton.Position = UDim2.new(1, -126, 0, 5)

        local priceButton = makeButton(
            card,
            "MAX $" .. formatNumber(item.maxPrice),
            function()
                ItemIdBox.Text = item.id
                ItemNameBox.Text = item.name
                MaxPriceBox.Text = tostring(item.maxPrice)
            end,
            COLORS.Panel,
            118
        )

        priceButton.Position = UDim2.new(1, -126, 0, 41)
    end
end

--==================================================
-- SCANNER
--==================================================

local function scanItem(item)
    local response, errorMessage = GetItem(item.id)

    if not response then
        Results[item.id] = {
            success = false,
            error = errorMessage
        }

        log(item.id .. ": " .. tostring(errorMessage), "ERROR")
        return
    end

    local listings = response.listings or {}
    local lowest = getLowestListing(listings)

    local count = tonumber(response.total) or #listings

    Results[item.id] = {
        success = true,
        lowest = lowest and lowest.price or nil,
        listing = lowest,
        count = count,
        timestamp = os.time()
    }

    if lowest then
        autoBuyItem(item, lowest)

        if lowest.price <= item.maxPrice then
            log(
                "TARGET REACHED: " .. item.name ..
                " | $" .. formatNumber(lowest.price),
                "TARGET"
            )
        else
            log(
                item.name ..
                " | Lowest: $" .. formatNumber(lowest.price),
                "SCAN"
            )
        end
    else
        log(item.name .. " | No listing", "SCAN")
    end
end

local function performScan()
    if Scanning then
        return
    end

    Scanning = true

    StatusText.Text = "STATUS: SCANNING"
    StatusText.TextColor3 = COLORS.Orange

    TotalScans = TotalScans + 1
    ScanCountText.Text = "SCANS: " .. tostring(TotalScans)

    local enabledCount = 0

    for _, item in ipairs(Watchlist) do
        if item.enabled then
            enabledCount = enabledCount + 1
        end
    end

    if enabledCount == 0 then
        log("No enabled items in Watchlist", "WARNING")
        Scanning = false
        StatusText.Text = "STATUS: IDLE"
        return
    end

    log("Market scan started", "SYSTEM")

    for _, item in ipairs(Watchlist) do
        if not ScreenGui.Parent then
            break
        end

        if item.enabled then
            scanItem(item)
            refreshItems()
            task.wait(CONFIG.RequestDelay)
        end
    end

    Scanning = false

    if Monitoring then
        StatusText.Text = "STATUS: MONITORING"
        StatusText.TextColor3 = COLORS.Green
    else
        StatusText.Text = "STATUS: IDLE"
        StatusText.TextColor3 = COLORS.Orange
    end

    log("Market scan completed", "SYSTEM")
    refreshItems()
end

--==================================================
-- MONITOR LOOP
--==================================================

local function startMonitor()
    local currentToken = ScanToken

    task.spawn(function()
        while Monitoring and ScanToken == currentToken do
            if not Scanning then
                performScan()
            end

            for _ = 1, CONFIG.ScanInterval do
                if not Monitoring or ScanToken ~= currentToken then
                    break
                end

                task.wait(1)
            end
        end
    end)
end

--==================================================
-- REMOVE OLD GUI
--==================================================

local oldGui = PlayerGui:FindFirstChild("HushAutoSniper")

if oldGui then
    oldGui:Destroy()
end

--==================================================
-- MAIN GUI
--==================================================

ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HushAutoSniper"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.DisplayOrder = 999999
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

Main = create("Frame", {
    Name = "Main",
    BackgroundColor3 = COLORS.Background,
    Size = UDim2.fromOffset(1120, 800),
    Position = UDim2.new(0.5, -560, 0.5, -400),
    BorderSizePixel = 0
}, ScreenGui)

corner(Main, 12)
stroke(Main, COLORS.Border, 1)

--==================================================
-- TITLE BAR / DRAG
--==================================================

local TitleBar = create("Frame", {
    BackgroundColor3 = COLORS.Panel,
    Size = UDim2.new(1, 0, 0, 48),
    BorderSizePixel = 0
}, Main)

corner(TitleBar, 12)

local Title = makeLabel(
    TitleBar,
    "HUSH MARKET WATCHER",
    15,
    COLORS.Text,
    true
)

Title.Position = UDim2.fromOffset(16, 4)
Title.Size = UDim2.new(1, -150, 0, 22)

local Subtitle = makeLabel(
    TitleBar,
    "MARKET ID SCANNER  /  PRICE MONITOR  /  AUTO BUY  /  ANTI-AFK  /  PURCHASE REPORT  /  V2.5.2 MOBILE",
    9,
    COLORS.Muted,
    false
)

Subtitle.Position = UDim2.fromOffset(17, 25)

Content = create("ScrollingFrame", {
    Name = "Content",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(12, 58),
    Size = UDim2.new(1, -24, 1, -70),
    BorderSizePixel = 0,
    ScrollBarThickness = 5,
    ScrollBarImageColor3 = COLORS.Accent,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    CanvasSize = UDim2.new(0, 0, 0, 0)
}, Main)

local Viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
local IsMobilePortrait = Viewport.X < 850 and Viewport.Y >= Viewport.X
local ExpandedMainSize = IsMobilePortrait
    and UDim2.fromOffset(math.max(300, Viewport.X - 16), math.max(420, Viewport.Y - 48))
    or UDim2.fromOffset(1120, 800)

Main.Size = ExpandedMainSize
if IsMobilePortrait then
    Main.Position = UDim2.new(0.5, 0, 0.5, 0)
    Main.AnchorPoint = Vector2.new(0.5, 0.5)
end

local MinimizeButton = makeButton(
    TitleBar,
    "MINIMIZE",
    function()
        local minimized = Main:GetAttribute("Minimized")

        if minimized then
            Main:SetAttribute("Minimized", false)
            Main.Size = ExpandedMainSize
            Content.Visible = true
        else
            Main:SetAttribute("Minimized", true)
            Main.Size = UDim2.new(1, 0, 0, 48)
            Content.Visible = false
        end
    end,
    COLORS.Accent,
    85
)

MinimizeButton.Position = UDim2.new(1, -98, 0, 9)

local dragging = false
local dragStart
local startPosition

TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true
        dragStart = input.Position
        startPosition = Main.Position

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

        Main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

--==================================================
-- STATUS BAR
--==================================================

local StatusBar = create("Frame", {
    BackgroundColor3 = COLORS.Panel,
    Size = UDim2.new(1, 0, 0, 34),
    BorderSizePixel = 0
}, Content)

corner(StatusBar, 6)

StatusText = makeLabel(
    StatusBar,
    "STATUS: READY",
    10,
    COLORS.Green,
    true
)

StatusText.Position = UDim2.fromOffset(10, 0)
StatusText.Size = UDim2.new(0.5, -10, 1, 0)

ScanCountText = makeLabel(
    StatusBar,
    "SCANS: 0",
    10,
    COLORS.Muted,
    true
)

ScanCountText.Position = UDim2.new(0.5, 0, 0, 0)
ScanCountText.Size = UDim2.new(0.5, -10, 1, 0)
ScanCountText.TextXAlignment = Enum.TextXAlignment.Right

--==================================================
-- CONTROL PANEL
--==================================================

local ControlPanel = create("Frame", {
    BackgroundColor3 = COLORS.Panel,
    Position = UDim2.fromOffset(0, 42),
    Size = UDim2.new(1, 0, 0, 78),
    BorderSizePixel = 0
}, Content)

corner(ControlPanel, 7)

ItemIdBox = makeTextBox(
    ControlPanel,
    "Item ID",
    180
)

ItemIdBox.Position = UDim2.fromOffset(9, 8)

ItemNameBox = makeTextBox(
    ControlPanel,
    "Display name",
    145
)

ItemNameBox.Position = UDim2.fromOffset(195, 8)

MaxPriceBox = makeTextBox(
    ControlPanel,
    "Max price",
    100
)

MaxPriceBox.Position = UDim2.fromOffset(346, 8)

local AddButton = makeButton(
    ControlPanel,
    "ADD WATCH",
    function()
        local id = ItemIdBox.Text
        local name = ItemNameBox.Text
        local price = MaxPriceBox.Text

        local success, message = addWatchlistItem(id, name, price)

        if not success then
            log(message .. " | ID: " .. tostring(id) ..
                " | PRICE: " .. tostring(price), "WARNING")
            StatusText.Text = "STATUS: " .. string.upper(message)
            StatusText.TextColor3 = COLORS.Red
            return
        end

        ItemIdBox.Text = ""
        ItemNameBox.Text = ""
        MaxPriceBox.Text = ""

        Results[id:gsub("^%s+", ""):gsub("%s+$", "")] = nil
        log(message .. ": " .. id, "WATCHLIST")
        StatusText.Text = "STATUS: " .. string.upper(message)
        StatusText.TextColor3 = COLORS.Green
        refreshItems()
    end,
    COLORS.Accent,
    100
)

AddButton.Position = UDim2.fromOffset(454, 8)

local ForceScanButton = makeButton(
    ControlPanel,
    "FORCE SCAN",
    function()
        task.spawn(performScan)
    end,
    COLORS.Green,
    95
)

ForceScanButton.Position = UDim2.fromOffset(9, 43)

local StartButton = makeButton(
    ControlPanel,
    "START MONITOR",
    function()
        if Monitoring then
            return
        end

        Monitoring = true
        ScanToken = ScanToken + 1

        StatusText.Text = "STATUS: MONITORING"
        StatusText.TextColor3 = COLORS.Green

        log("Automatic monitoring started", "SYSTEM")
        startMonitor()
    end,
    COLORS.Accent,
    110
)

StartButton.Position = UDim2.fromOffset(112, 43)

local StopButton = makeButton(
    ControlPanel,
    "STOP MONITOR",
    function()
        Monitoring = false
        ScanToken = ScanToken + 1

        StatusText.Text = "STATUS: IDLE"
        StatusText.TextColor3 = COLORS.Orange

        log("Monitoring stopped", "SYSTEM")
    end,
    COLORS.Red,
    100
)

StopButton.Position = UDim2.fromOffset(230, 43)

local CopyLogButton = makeButton(
    ControlPanel,
    "COPY LOG",
    function()
        if safeClipboard(table.concat(ActivityLog, "\n")) then
            log("Activity log copied", "SYSTEM")
        else
            log("Clipboard unavailable", "ERROR")
        end
    end,
    COLORS.Panel2,
    85
)

CopyLogButton.Position = UDim2.fromOffset(338, 43)

local ClearLogButton = makeButton(
    ControlPanel,
    "CLEAR LOG",
    function()
        table.clear(ActivityLog)
        refreshLog()
        log("Log cleared", "SYSTEM")
    end,
    COLORS.Panel2,
    85
)

ClearLogButton.Position = UDim2.fromOffset(431, 43)

--==================================================
-- ANTI-AFK
--==================================================

local AntiAFKButton

local function setAntiAFK(enabled)
    AntiAFKEnabled = enabled
    savePersistentState()

    if AntiAFKConnection then
        AntiAFKConnection:Disconnect()
        AntiAFKConnection = nil
    end

    if AntiAFKEnabled then
        AntiAFKConnection = Player.Idled:Connect(function()
            if not AntiAFKEnabled then
                return
            end

            local success, err = pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)

            if not success then
                log("Anti-AFK input failed: " .. tostring(err), "ERROR")
            else
                log("Idle event prevented", "ANTI-AFK")
            end
        end)

        -- Small periodic mouse movement, matching the supplied anti-AFK logic.
        -- Runs only while the integrated toggle is ON.
        task.spawn(function()
            while AntiAFKEnabled and ScreenGui and ScreenGui.Parent do
                task.wait(15)
                if not AntiAFKEnabled or not (ScreenGui and ScreenGui.Parent) then
                    break
                end

                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:MouseMove(Vector2.new(math.random(-10, 10), math.random(-10, 10)))
                end)
            end
        end)

        AntiAFKButton.Text = "ANTI-AFK: ON"
        AntiAFKButton.BackgroundColor3 = COLORS.Green
        log("Anti-AFK enabled", "SYSTEM")
    else
        AntiAFKButton.Text = "ANTI-AFK: OFF"
        AntiAFKButton.BackgroundColor3 = COLORS.Panel2
        log("Anti-AFK disabled", "SYSTEM")
    end
end

AntiAFKButton = makeButton(
    ControlPanel,
    "ANTI-AFK: OFF",
    function()
        setAntiAFK(not AntiAFKEnabled)
    end,
    COLORS.Panel2,
    105
)

AntiAFKButton.Position = UDim2.fromOffset(526, 43)

-- Restore the saved Anti-AFK preference. Monitoring/Auto Buy do not auto-start for safety.
if SavedState and SavedState.antiAFK == true then
    task.defer(function()
        if ScreenGui and ScreenGui.Parent then setAntiAFK(true) end
    end)
end

--==================================================
-- GRID SCANNER PANEL
--==================================================

local IDPanel = create("Frame", {
    BackgroundColor3 = COLORS.Panel,
    Position = UDim2.fromOffset(0, 130),
    Size = UDim2.new(0.48, -5, 0, 365),
    BorderSizePixel = 0
}, Content)

corner(IDPanel, 8)

local IDTitle = makeLabel(
    IDPanel,
    "MARKET GRID / DISCOVERED IDS",
    11,
    COLORS.Text,
    true
)

IDTitle.Position = UDim2.fromOffset(9, 5)

IDCountText = makeLabel(
    IDPanel,
    "DISCOVERED IDS: 0",
    9,
    COLORS.Green,
    true
)

IDCountText.Position = UDim2.fromOffset(9, 26)

GridStatusText = makeLabel(
    IDPanel,
    "GRID: WAITING",
    9,
    COLORS.Orange,
    true
)

GridStatusText.Position = UDim2.fromOffset(9, 44)

local ScanGridButton = makeButton(
    IDPanel,
    "SCAN GRID",
    function()
        scanMarketGrid()
        refreshIDList()
    end,
    COLORS.Accent,
    85
)

ScanGridButton.Position = UDim2.new(1, -183, 0, 8)

local CopyIDsButton = makeButton(
    IDPanel,
    "COPY ALL",
    copyAllIDs,
    COLORS.Green,
    85
)

CopyIDsButton.Position = UDim2.new(1, -91, 0, 8)

IDSearchBox = makeTextBox(IDPanel, "Search item ID...", 180)
IDSearchBox.Position = UDim2.fromOffset(9, 64)
IDSearchBox.Size = UDim2.new(1, -18, 0, 28)
IDSearchBox.TextXAlignment = Enum.TextXAlignment.Left
IDSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    refreshIDList()
end)

IDFrame = create("ScrollingFrame", {
    BackgroundColor3 = COLORS.Background,
    Position = UDim2.fromOffset(8, 98),
    Size = UDim2.new(1, -16, 1, -106),
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = COLORS.Accent,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(0, 0, 0, 0)
}, IDPanel)

corner(IDFrame, 6)

create("UIListLayout", {
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder
}, IDFrame)

create("UIPadding", {
    PaddingTop = UDim.new(0, 5),
    PaddingBottom = UDim.new(0, 5),
    PaddingLeft = UDim.new(0, 5),
    PaddingRight = UDim.new(0, 5)
}, IDFrame)

--==================================================
-- WATCHLIST PANEL
--==================================================

local WatchPanel = create("Frame", {
    BackgroundColor3 = COLORS.Panel,
    Position = UDim2.new(0.48, 5, 0, 130),
    Size = UDim2.new(0.52, -5, 0, 365),
    BorderSizePixel = 0
}, Content)

corner(WatchPanel, 8)

local WatchTitle = makeLabel(
    WatchPanel,
    "WATCHLIST / MARKET RESULTS",
    11,
    COLORS.Text,
    true
)

WatchTitle.Position = UDim2.fromOffset(9, 5)

WatchlistFrame = create("ScrollingFrame", {
    BackgroundColor3 = COLORS.Background,
    Position = UDim2.fromOffset(8, 30),
    Size = UDim2.new(1, -16, 1, -38),
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = COLORS.Accent,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(0, 0, 0, 0)
}, WatchPanel)

corner(WatchlistFrame, 6)

create("UIListLayout", {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder
}, WatchlistFrame)

create("UIPadding", {
    PaddingTop = UDim.new(0, 5),
    PaddingBottom = UDim.new(0, 5),
    PaddingLeft = UDim.new(0, 5),
    PaddingRight = UDim.new(0, 5)
}, WatchlistFrame)

--==================================================
-- ACTIVITY LOG / PURCHASE REPORT TABS
--==================================================

local ActivityTab, PurchaseTab, PurchasePanel

ActivityTab = makeButton(
    Content,
    "ACTIVITY LOG",
    function()
        LogFrame.Visible = true
        PurchasePanel.Visible = false
        ActivityTab.BackgroundColor3 = COLORS.Accent
        PurchaseTab.BackgroundColor3 = COLORS.Panel2
    end,
    COLORS.Accent,
    115
)
ActivityTab.Position = UDim2.fromOffset(0, 498)

PurchaseTab = makeButton(
    Content,
    "PURCHASE REPORT",
    function()
        LogFrame.Visible = false
        PurchasePanel.Visible = true
        ActivityTab.BackgroundColor3 = COLORS.Panel2
        PurchaseTab.BackgroundColor3 = COLORS.Accent
    end,
    COLORS.Panel2,
    145
)
PurchaseTab.Position = UDim2.fromOffset(122, 498)

LogFrame = create("ScrollingFrame", {
    BackgroundColor3 = COLORS.Panel,
    Position = UDim2.fromOffset(0, 535),
    Size = UDim2.new(1, 0, 1, -535),
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = COLORS.Accent,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(0, 0, 0, 0)
}, Content)

corner(LogFrame, 7)

create("UIListLayout", {
    Padding = UDim.new(0, 2),
    SortOrder = Enum.SortOrder.LayoutOrder
}, LogFrame)

create("UIPadding", {
    PaddingTop = UDim.new(0, 5),
    PaddingBottom = UDim.new(0, 5),
    PaddingLeft = UDim.new(0, 8),
    PaddingRight = UDim.new(0, 8)
}, LogFrame)

-- Purchase report panel (shares the lower panel area with Activity Log)
PurchasePanel = create("Frame", {
    BackgroundColor3 = COLORS.Panel,
    Position = UDim2.fromOffset(0, 535),
    Size = UDim2.new(1, 0, 1, -535),
    BorderSizePixel = 0,
    Visible = false
}, Content)
corner(PurchasePanel, 7)

local PurchaseStatus = makeLabel(PurchasePanel, "STATUS: LISTENING FOR PURCHASES", 10, COLORS.Green, true)
PurchaseStatus.Position = UDim2.fromOffset(10, 4)
PurchaseStatus.Size = UDim2.new(0.7, -10, 0, 22)

local PurchaseCount = makeLabel(PurchasePanel, "PURCHASES: 0", 10, COLORS.Muted, true)
PurchaseCount.Position = UDim2.new(0.7, 0, 0, 4)
PurchaseCount.Size = UDim2.new(0.3, -10, 0, 22)
PurchaseCount.TextXAlignment = Enum.TextXAlignment.Right

local PurchaseSummary = create("Frame", {
    BackgroundColor3 = COLORS.Background,
    Position = UDim2.fromOffset(8, 30),
    Size = UDim2.new(1, -16, 0, 58),
    BorderSizePixel = 0
}, PurchasePanel)
corner(PurchaseSummary, 6)

local function reportStat(labelText, xScale, widthScale)
    local holder = create("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.new(xScale, 0, 0, 3),
        Size = UDim2.new(widthScale, 0, 1, -6)
    }, PurchaseSummary)
    local label = makeLabel(holder, labelText, 9, COLORS.Muted, true)
    label.Position = UDim2.fromOffset(5, 0)
    label.Size = UDim2.new(1, -5, 0, 17)
    local value = makeLabel(holder, "0", 17, COLORS.Text, true)
    value.Position = UDim2.fromOffset(5, 20)
    value.Size = UDim2.new(1, -5, 0, 27)
    return value
end

local ReportItemsValue = reportStat("ITEMS BOUGHT", 0.01, 0.30)
local ReportUnitsValue = reportStat("TOTAL UNITS", 0.35, 0.28)
local ReportSpentValue = reportStat("TOTAL SPENT", 0.68, 0.30)

local ReportActions = create("Frame", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(8, 96),
    Size = UDim2.new(1, -16, 0, 32)
}, PurchasePanel)

local PurchaseList = create("ScrollingFrame", {
    BackgroundColor3 = COLORS.Background,
    Position = UDim2.fromOffset(8, 134),
    Size = UDim2.new(1, -16, 1, -142),
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = COLORS.Accent,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(0, 0, 0, 0)
}, PurchasePanel)
corner(PurchaseList, 6)
create("UIListLayout", {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder
}, PurchaseList)
create("UIPadding", {
    PaddingTop = UDim.new(0, 6),
    PaddingBottom = UDim.new(0, 6),
    PaddingLeft = UDim.new(0, 6),
    PaddingRight = UDim.new(0, 6)
}, PurchaseList)

--==================================================
-- RESPONSIVE MOBILE PORTRAIT LAYOUT
--==================================================

if IsMobilePortrait then
    local mobileWidth = math.max(280, Viewport.X - 40)
    local y = 0

    -- Keep the whole interface in one vertical, touch-friendly column.
    Content.Position = UDim2.fromOffset(8, 54)
    Content.Size = UDim2.new(1, -16, 1, -62)
    Content.ScrollBarThickness = 5
    Content.CanvasSize = UDim2.new(0, 0, 0, 1260)

    StatusBar.Position = UDim2.fromOffset(0, 0)
    StatusBar.Size = UDim2.new(1, 0, 0, 34)

    ControlPanel.Position = UDim2.fromOffset(0, 42)
    ControlPanel.Size = UDim2.new(1, 0, 0, 126)

    local fieldGap = 6
    local fieldWidth = (mobileWidth - 3 * fieldGap - 16) / 3
    ItemIdBox.Position = UDim2.fromOffset(8, 8)
    ItemIdBox.Size = UDim2.new(0.34, -8, 0, 30)
    ItemNameBox.Position = UDim2.new(0.34, 2, 0, 8)
    ItemNameBox.Size = UDim2.new(0.34, -8, 0, 30)
    MaxPriceBox.Position = UDim2.new(0.68, 2, 0, 8)
    MaxPriceBox.Size = UDim2.new(0.17, -4, 0, 30)
    AddButton.Position = UDim2.new(0.85, 2, 0, 8)
    AddButton.Size = UDim2.new(0.15, -10, 0, 30)

    local actionGap = 5
    local actionWidth = (mobileWidth - 16 - actionGap * 2) / 3
    ForceScanButton.Position = UDim2.fromOffset(8, 46)
    ForceScanButton.Size = UDim2.new(0.33, -8, 0, 30)
    StartButton.Position = UDim2.new(0.33, 1, 0, 46)
    StartButton.Size = UDim2.new(0.34, -8, 0, 30)
    StopButton.Position = UDim2.new(0.67, 2, 0, 46)
    StopButton.Size = UDim2.new(0.33, -10, 0, 30)

    CopyLogButton.Position = UDim2.fromOffset(8, 84)
    CopyLogButton.Size = UDim2.new(0.27, -6, 0, 30)
    ClearLogButton.Position = UDim2.new(0.27, 1, 0, 84)
    ClearLogButton.Size = UDim2.new(0.27, -6, 0, 30)
    AntiAFKButton.Position = UDim2.new(0.54, 2, 0, 84)
    AntiAFKButton.Size = UDim2.new(0.46, -10, 0, 30)

    IDPanel.Position = UDim2.fromOffset(0, 176)
    IDPanel.Size = UDim2.new(1, 0, 0, 270)
    ScanGridButton.Position = UDim2.new(1, -183, 0, 8)
    CopyIDsButton.Position = UDim2.new(1, -91, 0, 8)
    IDSearchBox.Position = UDim2.fromOffset(9, 64)
    IDSearchBox.Size = UDim2.new(1, -18, 0, 28)
    IDFrame.Position = UDim2.fromOffset(8, 98)
    IDFrame.Size = UDim2.new(1, -16, 1, -106)

    WatchPanel.Position = UDim2.fromOffset(0, 454)
    WatchPanel.Size = UDim2.new(1, 0, 0, 300)
    WatchlistFrame.Position = UDim2.fromOffset(8, 30)
    WatchlistFrame.Size = UDim2.new(1, -16, 1, -38)

    ActivityTab.Position = UDim2.fromOffset(0, 764)
    PurchaseTab.Position = UDim2.fromOffset(122, 764)

    LogFrame.Position = UDim2.fromOffset(0, 802)
    LogFrame.Size = UDim2.new(1, 0, 0, 360)
    PurchasePanel.Position = UDim2.fromOffset(0, 802)
    PurchasePanel.Size = UDim2.new(1, 0, 0, 360)
    PurchaseList.Size = UDim2.new(1, -16, 1, -142)

    Title.TextSize = 13
    Subtitle.TextSize = 7
    MinimizeButton.Text = "MIN"
    MinimizeButton.Size = UDim2.fromOffset(48, 30)
    MinimizeButton.Position = UDim2.new(1, -56, 0, 9)

    -- Keep all controls inside the available portrait width.
    local function updateMobileCanvas()
        Content.CanvasSize = UDim2.new(0, 0, 0, 1170)
    end
    updateMobileCanvas()
end

PurchaseRecords = SavedPurchaseRecords or {}
local PurchaseTotalSpent = 0
local PurchaseTotalUnits = 0
for _, savedRecord in ipairs(PurchaseRecords) do
    PurchaseTotalSpent = PurchaseTotalSpent + (tonumber(savedRecord.price) or 0)
    PurchaseTotalUnits = PurchaseTotalUnits + (tonumber(savedRecord.quantity) or 0)
end
local SeenPurchaseText = setmetatable({}, { __mode = "k" })
local PurchaseConnections = {}
local PurchaseDetectorRunning = true

local function reportFormatNumber(value)
    local result = tostring(math.floor(tonumber(value) or 0))
    while true do
        local replaced, count = result:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        result = replaced
        if count == 0 then break end
    end
    return result
end

local function parsePurchaseToast(message)
    if type(message) ~= "string" then return nil end
    local clean = message:gsub("\n", " "):gsub("%s+", " ")
    local quantity, itemName, priceText = clean:match("Bought:%s*(%d+)%s*x%s*(.-)%s+for%s+%$%s*([%d,]+)")
    if not quantity or not itemName or not priceText then return nil end
    itemName = itemName:gsub("%s+$", "")
    local price = tonumber((priceText:gsub(",", "")))
    if itemName == "" or not price then return nil end
    return {
        quantity = tonumber(quantity),
        item = itemName,
        price = price,
        raw = clean,
        time = os.date("%H:%M:%S"),
        timestamp = os.time()
    }
end

local function makePurchaseReportText()
    local lines = {
        "HUSH PURCHASE REPORT",
        "Generated: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "Purchases: " .. tostring(#PurchaseRecords),
        "Total units: " .. tostring(PurchaseTotalUnits),
        "Total spent: $" .. reportFormatNumber(PurchaseTotalSpent),
        ""
    }
    for index, record in ipairs(PurchaseRecords) do
        table.insert(lines, string.format("%02d. [%s] %d x %s - $%s", index, record.time, record.quantity, record.item, reportFormatNumber(record.price)))
        table.insert(lines, "    " .. record.raw)
    end
    return table.concat(lines, "\n")
end

local function refreshPurchaseReport()
    PurchaseCount.Text = "PURCHASES: " .. tostring(#PurchaseRecords)
    ReportItemsValue.Text = tostring(#PurchaseRecords)
    ReportUnitsValue.Text = tostring(PurchaseTotalUnits)
    ReportSpentValue.Text = "$" .. reportFormatNumber(PurchaseTotalSpent)

    for _, child in ipairs(PurchaseList:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    for index, record in ipairs(PurchaseRecords) do
        local row = create("Frame", {
            BackgroundColor3 = COLORS.Panel2,
            Size = UDim2.new(1, -5, 0, 58),
            BorderSizePixel = 0,
            LayoutOrder = index
        }, PurchaseList)
        corner(row, 6)
        local title = makeLabel(row,
            tostring(record.quantity) .. " x " .. record.item .. "  |  $" .. reportFormatNumber(record.price),
            11, COLORS.Text, true)
        title.Position = UDim2.fromOffset(9, 4)
        title.Size = UDim2.new(1, -18, 0, 21)
        local detail = makeLabel(row,
            record.time .. "  |  TOTAL: $" .. reportFormatNumber(record.price),
            9, COLORS.Muted, false)
        detail.Position = UDim2.fromOffset(9, 27)
        detail.Size = UDim2.new(1, -18, 0, 18)
    end
end

local function addReportButton(text, x, width, color, callback)
    local button = create("TextButton", {
        Position = UDim2.fromOffset(x, 0),
        Size = UDim2.fromOffset(width, 29),
        BackgroundColor3 = color,
        Text = text,
        TextColor3 = COLORS.Text,
        TextSize = 10,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true
    }, ReportActions)
    corner(button, 6)
    stroke(button)
    button.MouseButton1Click:Connect(callback)
    return button
end

addReportButton("COPY REPORT", 0, 112, COLORS.Accent, function()
    if #PurchaseRecords == 0 then
        PurchaseStatus.Text = "STATUS: NO PURCHASES TO COPY"
        return
    end
    if safeClipboard(makePurchaseReportText()) then
        PurchaseStatus.Text = "STATUS: REPORT COPIED"
        PurchaseStatus.TextColor3 = COLORS.Green
    else
        PurchaseStatus.Text = "STATUS: CLIPBOARD UNAVAILABLE"
        PurchaseStatus.TextColor3 = COLORS.Red
    end
end)

addReportButton("CLEAR REPORT", 120, 112, COLORS.Red, function()
    table.clear(PurchaseRecords)
    PurchaseTotalSpent = 0
    PurchaseTotalUnits = 0
    refreshPurchaseReport()
    savePersistentState()
    PurchaseStatus.Text = "STATUS: REPORT CLEARED"
    PurchaseStatus.TextColor3 = COLORS.Muted
end)

addReportButton("COPY LAST", 240, 100, COLORS.Panel2, function()
    local record = PurchaseRecords[1]
    if not record then return end
    local line = string.format("%s | %d x %s | $%s", record.time, record.quantity, record.item, reportFormatNumber(record.price))
    if safeClipboard(line) then
        PurchaseStatus.Text = "STATUS: LAST PURCHASE COPIED"
        PurchaseStatus.TextColor3 = COLORS.Green
    end
end)

local function inspectPurchaseText(object)
    if not PurchaseDetectorRunning then return end
    if not object:IsA("TextLabel") and not object:IsA("TextButton") then return end

    local function inspect()
        if not PurchaseDetectorRunning then return end
        local textValue = object.Text
        if type(textValue) ~= "string" or textValue == "" then return end
        if SeenPurchaseText[object] == textValue then return end
        SeenPurchaseText[object] = textValue

        local record = parsePurchaseToast(textValue)
        if not record then return end

        table.insert(PurchaseRecords, 1, record)
        savePersistentState()
        PurchaseTotalSpent = PurchaseTotalSpent + record.price
        PurchaseTotalUnits = PurchaseTotalUnits + record.quantity
        refreshPurchaseReport()
        PurchaseStatus.Text = "STATUS: PURCHASE DETECTED - " .. record.item
        PurchaseStatus.TextColor3 = COLORS.Green
        log("Purchase confirmed: " .. tostring(record.quantity) .. " x " .. record.item .. " for $" .. reportFormatNumber(record.price), "PURCHASE")
    end

    inspect()
    table.insert(PurchaseConnections, object:GetPropertyChangedSignal("Text"):Connect(inspect))
end

local function watchPurchaseContainer(container)
    for _, object in ipairs(container:GetDescendants()) do
        inspectPurchaseText(object)
    end
    table.insert(PurchaseConnections, container.DescendantAdded:Connect(inspectPurchaseText))
end

watchPurchaseContainer(PlayerGui)
pcall(function() watchPurchaseContainer(game:GetService("CoreGui")) end)

--==================================================
-- INITIALIZE
--==================================================

refreshItems()
refreshIDList()
refreshPurchaseReport()
savePersistentState()

log("HUSH MARKET WATCHER v2.5.2 MOBILE initialized", "SYSTEM")
if type(writefile) == "function" and SavedState then
    log("Saved settings restored from " .. SAVE_FILE, "SAVE")
elseif type(writefile) == "function" then
    log("Auto-save enabled; new settings will be saved", "SAVE")
else
    log("Executor file APIs unavailable; settings cannot persist", "WARNING")
end
log("Market Grid ID scanner initialized", "SYSTEM")
log("API: HushNet.menu.get / bmItem + menu.op / bmBuyBest", "SYSTEM")
log("Auto-buy is OFF by default; enable it per item", "INFO")

-- Initial grid scan
task.spawn(function()
    task.wait(2)
    scanMarketGrid()
    refreshIDList()
end)

-- Automatic Grid refresh
task.spawn(function()
    while ScreenGui and ScreenGui.Parent do
        task.wait(CONFIG.GridRefreshInterval)

        if not GridScanning then
            local before = #DiscoveredIDs

            scanMarketGrid()

            if #DiscoveredIDs ~= before then
                refreshIDList()
            end
        end
    end
end)

--==================================================
-- CLEANUP
--==================================================

ScreenGui.Destroying:Connect(function()
    savePersistentState()
    Monitoring = false
    Scanning = false
    GridScanning = false
    AntiAFKEnabled = false
    PurchaseDetectorRunning = false
    for _, connection in ipairs(PurchaseConnections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(PurchaseConnections)

    if AntiAFKConnection then
        AntiAFKConnection:Disconnect()
        AntiAFKConnection = nil
    end

    ScanToken = ScanToken + 1

    _G.HushWatcherRefreshItems = nil
    _G.HushWatcherRefreshLog = nil
    _G.HushWatcherScan = nil
    _G.HushWatcherStart = nil
end)

-- Compatibility globals
_G.HushWatcherRefreshItems = refreshItems
_G.HushWatcherRefreshLog = refreshLog
_G.HushWatcherScan = performScan
_G.HushWatcherStart = startMonitor
_G.HushWatcherScanGrid = scanMarketGrid
