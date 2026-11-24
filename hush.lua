--[[
HUSH CONTROL CENTER V1
PC DESKTOP EDITION
Tabs:
  1. AUTO SNIPE MARKET
  2. AUTO BUY FROM NPC

Market features:
- Default + custom watchlist
- Per-item max price
- Market listing scan and optional auto-buy
- Priority item (one at a time)
- Market grid ID discovery
- Activity log and purchase toast report
- Persistent settings when executor file APIs exist

NPC features:
- Uses a local 15-minute countdown; does not depend on the game's restock label
- Displays the next automatic buy countdown clearly
- At 00:00, waits 3 seconds, then sends the 11 configured ammo requests
- Starts another 15-minute interval after each automatic batch

Use only where permitted by the game's rules.
]]

--==================================================
-- SERVICES / REMOTES
--==================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local HushNet = ReplicatedStorage:WaitForChild("HushNet")
local MenuGet = HushNet:WaitForChild("menu.get")
local MenuOp = HushNet:WaitForChild("menu.op")

--==================================================
-- CONFIG / STATE
--==================================================

local CONFIG = {
    ScanInterval = 1,
    RequestDelay = 1,
    AutoBuyCooldown = 1,
    NPCTriggerDelay = 3,
    NPCRequestDelay = 0.3,
    GridRefreshInterval = 2,
    SaveFile = "HushControlCenter_v1.json",
}

local COLORS = {
    bg = Color3.fromRGB(12, 15, 23),
    panel = Color3.fromRGB(20, 25, 37),
    panel2 = Color3.fromRGB(28, 35, 50),
    panel3 = Color3.fromRGB(36, 44, 62),
    border = Color3.fromRGB(53, 64, 86),
    text = Color3.fromRGB(235, 240, 250),
    muted = Color3.fromRGB(139, 152, 176),
    accent = Color3.fromRGB(111, 99, 255),
    green = Color3.fromRGB(56, 196, 129),
    red = Color3.fromRGB(226, 78, 91),
    orange = Color3.fromRGB(238, 171, 73),
    blue = Color3.fromRGB(75, 164, 235),
}

local defaultWatchlist = {
    {id="rifle_dm308_gold", name="DM-308 Gold", maxPrice=10000000, enabled=true, autoBuy=false},
    {id="mg_gm30_gold", name="GM-30 Gold", maxPrice=20000000, enabled=true, autoBuy=false},
    {id="mg_rv1_gold", name="RV-1 Gold", maxPrice=23000000, enabled=true, autoBuy=false},
    {id="att_scope_8x", name="8x Scope", maxPrice=2000000, enabled=true, autoBuy=false},
    {id="rifle_tr9_gold", name="TR-9 Gold", maxPrice=14000000, enabled=true, autoBuy=false},
    {id="rifle_sc7_gold", name="SC-7 Gold", maxPrice=2000000, enabled=true, autoBuy=false},
    {id="helmet_nvg_quad", name="Quad NVG", maxPrice=23000000, enabled=true, autoBuy=false},
}

local ammoList = {
    -- 12GA
    {offer="12ga_1", count=3, req=3},
    {offer="12ga_1_l3", count=1, req=4},
    {offer="12ga_1_l5", count=3, req=5},
    {offer="12ga_4_l5", count=2, req=6},
    {offer="12ga_4", count=1, req=7},
    -- .308
    {offer="308_l3", count=2, req=1},
    {offer="308_1_l2", count=2, req=2},
    {offer="308_1", count=2, req=3},
    {offer="308_3", count=1, req=4},
    {offer="308_3_l5", count=2, req=5},
    {offer="308_1_l5", count=3, req=6},
}

local Watchlist, Results = {}, {}
local DiscoveredIDs, DiscoveredSet = {}, {}
local ActivityLog, PurchaseRecords = {}, {}
local Monitoring, Scanning, GridScanning = false, false, false
local NPCMonitoring, NPCBuying, NPCWaitingReset = false, false, false
local AntiAFKEnabled = false
local ScanToken = 0
local TotalScans = 0
local TotalMarketRequests = 0
local TotalNPCRequests = 0
local TotalNPCCycles = 0
local PurchaseTotalSpent, PurchaseTotalUnits = 0, 0
local SeenPurchaseText = setmetatable({}, {__mode="k"})
local PurchaseConnections = {}
local AntiAFKConnection

--==================================================
-- PERSISTENCE
--==================================================

local function cloneTable(source)
    local out = {}
    for k,v in pairs(source) do
        out[k] = type(v) == "table" and cloneTable(v) or v
    end
    return out
end

local function loadState()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return nil end
    local ok, exists = pcall(isfile, CONFIG.SaveFile)
    if not ok or not exists then return nil end
    local readOK, raw = pcall(readfile, CONFIG.SaveFile)
    if not readOK then return nil end
    local decodeOK, data = pcall(function() return HttpService:JSONDecode(raw) end)
    if decodeOK and type(data) == "table" then return data end
    return nil
end

local SavedState = loadState()
local savedById = {}
if SavedState and type(SavedState.watchlist) == "table" then
    for _, item in ipairs(SavedState.watchlist) do
        if type(item) == "table" and type(item.id) == "string" then
            savedById[item.id] = item
        end
    end
end

for _, base in ipairs(defaultWatchlist) do
    local item = cloneTable(base)
    local saved = savedById[item.id]
    if saved then
        item.name = tostring(saved.name or item.name)
        item.maxPrice = tonumber(saved.maxPrice) or item.maxPrice
        item.enabled = saved.enabled == true
        item.autoBuy = saved.autoBuy == true
        item.priority = saved.priority == true
    end
    table.insert(Watchlist, item)
    savedById[item.id] = nil
end
for id, saved in pairs(savedById) do
    -- Golden Katana was explicitly removed from the requested watchlist.
    if id ~= "melee_katana_gold" then
        table.insert(Watchlist, {
            id=id, name=tostring(saved.name or id),
            maxPrice=tonumber(saved.maxPrice) or 1,
            enabled=saved.enabled == true,
            autoBuy=saved.autoBuy == true,
            priority=saved.priority == true,
            lastBuyAttempt=0,
        })
    end
end

-- Apply the explicitly requested prices even if an older save file has stale values.
for _, item in ipairs(Watchlist) do
    if item.id == "rifle_tr9_gold" then
        item.maxPrice = 14000000
    elseif item.id == "att_scope_8x" then
        item.maxPrice = 2000000
    end
end

if SavedState and type(SavedState.discoveredIDs) == "table" then
    for _, id in ipairs(SavedState.discoveredIDs) do
        if type(id) == "string" and id ~= "" and not DiscoveredSet[id] then
            DiscoveredSet[id] = true
            table.insert(DiscoveredIDs, id)
        end
    end
end
if SavedState and type(SavedState.purchases) == "table" then
    PurchaseRecords = SavedState.purchases
end
if SavedState and type(SavedState.requestDelay) == "number" then
    CONFIG.RequestDelay = math.clamp(SavedState.requestDelay, 0.1, 60)
end

local function saveState()
    if type(writefile) ~= "function" then return false end
    local state = {
        watchlist={}, discoveredIDs=DiscoveredIDs,
        purchases=PurchaseRecords, requestDelay=CONFIG.RequestDelay,
        antiAFK=AntiAFKEnabled,
    }
    for _, item in ipairs(Watchlist) do
        table.insert(state.watchlist, {
            id=item.id, name=item.name, maxPrice=item.maxPrice,
            enabled=item.enabled == true, autoBuy=item.autoBuy == true,
            priority=item.priority == true,
        })
    end
    local ok, raw = pcall(function() return HttpService:JSONEncode(state) end)
    if not ok then return false end
    return pcall(writefile, CONFIG.SaveFile, raw)
end

--==================================================
-- UTILITIES
--==================================================

local function formatNumber(value)
    local s = tostring(math.floor(tonumber(value) or 0))
    while true do
        local replaced, count = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        s = replaced
        if count == 0 then break end
    end
    return s
end

local function safeClipboard(value)
    local fn = setclipboard or toclipboard or (syn and syn.write_clipboard)
    if not fn then return false end
    return pcall(fn, value)
end

local function make(className, props, parent)
    local obj = Instance.new(className)
    for k,v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end

local function addCorner(obj, radius)
    make("UICorner", {CornerRadius=UDim.new(0, radius or 8)}, obj)
end

local function addStroke(obj, color, thickness)
    make("UIStroke", {Color=color or COLORS.border, Thickness=thickness or 1}, obj)
end

local function label(parent, text, size, color, bold)
    return make("TextLabel", {
        BackgroundTransparency=1, Text=text or "",
        TextColor3=color or COLORS.text, TextSize=size or 12,
        Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextYAlignment=Enum.TextYAlignment.Center,
        Size=UDim2.new(1,0,0,22),
    }, parent)
end

local function button(parent, text, callback, color, width, height)
    local b = make("TextButton", {
        BackgroundColor3=color or COLORS.panel2, Text=text,
        TextColor3=COLORS.text, TextSize=11,
        Font=Enum.Font.GothamBold, AutoButtonColor=true,
        Size=UDim2.fromOffset(width or 100, height or 30),
    }, parent)
    addCorner(b, 7)
    addStroke(b)
    b.Activated:Connect(callback)
    return b
end

local function textbox(parent, placeholder, width)
    local t = make("TextBox", {
        BackgroundColor3=COLORS.panel2, Text="",
        PlaceholderText=placeholder, PlaceholderColor3=COLORS.muted,
        TextColor3=COLORS.text, TextSize=11, Font=Enum.Font.Gotham,
        ClearTextOnFocus=false, TextEditable=true, Active=true,
        Size=UDim2.fromOffset(width, 32),
    }, parent)
    addCorner(t, 7)
    addStroke(t)
    return t
end

local function addLog(message, category)
    local entry = string.format("[%s] [%s] %s", os.date("%H:%M:%S"), category or "INFO", tostring(message))
    table.insert(ActivityLog, 1, entry)
    while #ActivityLog > 150 do table.remove(ActivityLog) end
    print("[HUSH CONTROL] " .. entry)
    if LogList then
        for _, child in ipairs(LogList:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end
        for i, line in ipairs(ActivityLog) do
            local row = label(LogList, line, 10, COLORS.muted, false)
            row.Size = UDim2.new(1,-8,0,18)
            row.LayoutOrder = i
        end
    end
end

local function findWatchItem(id)
    for i, item in ipairs(Watchlist) do
        if item.id == id then return item, i end
    end
end

local function validItemId(id)
    if type(id) ~= "string" then return false end
    id = id:gsub("^%s+", ""):gsub("%s+$", "")
    if id == "" or #id > 100 then return false end
    if id:lower() == "icon" or id:lower() == "card" then return false end
    -- Permit common game item-key characters while rejecting spaces/control chars.
    return id:match("^[%w_%-%.]+$") ~= nil
end

local function normalizeName(s)
    return tostring(s or ""):lower():gsub("[^%w]", "")
end

local function isWatchlistPurchase(name)
    local n = normalizeName(name)
    for _, item in ipairs(Watchlist) do
        if n == normalizeName(item.name) or n == normalizeName(item.id) then
            return true
        end
    end
    return false
end

--==================================================
-- MARKET GRID ID SCANNER
--==================================================

local function walkPath(root, path)
    local current = root
    for _, name in ipairs(path) do
        if not current then return nil end
        current = current:FindFirstChild(name)
    end
    return current
end

local function getMarketGrid()
    local paths = {
        {"HushMenu","Root","MenuShell","Pages","Page_market","Market","Content","Inner","Body","Sub_browse","Grid"},
        {"HushMenu","Root","Pages","Page_market","Market","Content","Inner","Body","Sub_browse","Grid"},
    }
    for _, path in ipairs(paths) do
        local grid = walkPath(PlayerGui, path)
        if grid and (grid:IsA("ScrollingFrame") or grid:IsA("Frame")) then
            return grid
        end
    end
end

local function scanMarketGrid()
    if GridScanning then return end
    GridScanning = true
    local ok, err = pcall(function()
        local grid = getMarketGrid()
        if not grid then
            if GridStatus then GridStatus.Text = "GRID NOT FOUND — OPEN MARKET" end
            return
        end
        local added, cards = 0, 0
        for _, card in ipairs(grid:GetChildren()) do
            if card:IsA("TextButton") then
                cards += 1
                local id = card:GetAttribute("ItemId")
                if type(id) ~= "string" or id == "" then
                    local outerIcon = card:FindFirstChild("Icon")
                    local viewport = outerIcon and outerIcon:FindFirstChild("Icon")
                    if viewport then
                        for _, preview in ipairs(viewport:GetChildren()) do
                            if preview:IsA("Model") then
                                id = preview:GetAttribute("ItemId")
                                if type(id) == "string" and id ~= "" then break end
                            end
                        end
                    end
                end
                if validItemId(id) and not DiscoveredSet[id] then
                    DiscoveredSet[id] = true
                    table.insert(DiscoveredIDs, id)
                    added += 1
                end
            end
        end
        table.sort(DiscoveredIDs)
        if GridStatus then
            GridStatus.Text = "GRID CONNECTED  •  " .. cards .. " CARDS  •  " .. #DiscoveredIDs .. " IDS"
            GridStatus.TextColor3 = COLORS.green
        end
        if added > 0 then
            saveState()
            addLog("Grid discovered " .. added .. " new IDs", "ID SCANNER")
            refreshIDList()
        end
    end)
    GridScanning = false
    if not ok then addLog("Grid scan error: " .. tostring(err), "ERROR") end
end

--==================================================
-- MARKET API / SCANNING
--==================================================

local function getMarketItem(itemId)
    local ok, response = pcall(function()
        return MenuGet:InvokeServer({offset=0, id=itemId, what="bmItem"})
    end)
    if not ok then return nil, tostring(response) end
    if type(response) ~= "table" then return nil, "Invalid response" end
    if response.ok ~= true then return nil, response.text or response.code or "Request rejected" end
    return response
end

local function getLowestListing(listings)
    local lowest
    if type(listings) ~= "table" then return nil end
    for _, listing in pairs(listings) do
        if type(listing) == "table" then
            local price = tonumber(listing.p) or tonumber(listing.u)
            if price and price > 0 and (not lowest or price < lowest.price) then
                lowest = {
                    price=price, unitPrice=tonumber(listing.u),
                    listingId=listing.lid, quantity=tonumber(listing.n),
                    own=listing.own,
                }
            end
        end
    end
    return lowest
end

local function autoBuyMarketItem(item, lowest)
    if not item.autoBuy or not lowest or lowest.price > item.maxPrice then return end
    local now = os.clock()
    if now - (item.lastBuyAttempt or 0) < CONFIG.AutoBuyCooldown then return end
    item.lastBuyAttempt = now
    local ok, err = pcall(function()
        MenuOp:FireServer({
            op="bmBuyBest", maxUnit=item.maxPrice, id=item.id,
            maxTotal=lowest.price, req=1,
        })
    end)
    if ok then
        TotalMarketRequests += 1
        addLog("AUTO BUY SENT: " .. item.name .. " @ $" .. formatNumber(lowest.price), "MARKET BUY")
    else
        addLog("Market buy error: " .. tostring(err), "ERROR")
    end
end

local function scanMarketItem(item)
    local response, err = getMarketItem(item.id)
    if not response then
        Results[item.id] = {success=false, error=err}
        addLog(item.id .. ": " .. tostring(err), "ERROR")
        return
    end
    local listings = response.listings or {}
    local lowest = getLowestListing(listings)
    Results[item.id] = {
        success=true, lowest=lowest and lowest.price or nil,
        count=tonumber(response.total) or #listings,
        timestamp=os.time(),
    }
    if lowest then
        autoBuyMarketItem(item, lowest)
        if lowest.price <= item.maxPrice then
            addLog(item.name .. " TARGET: $" .. formatNumber(lowest.price), "TARGET")
        else
            addLog(item.name .. " lowest $" .. formatNumber(lowest.price), "SCAN")
        end
    else
        addLog(item.name .. " has no active listing", "SCAN")
    end
end

local function buildScanOrder()
    local normal, priority = {}, {}
    for _, item in ipairs(Watchlist) do
        if item.enabled then
            table.insert(item.priority and priority or normal, item)
        end
    end
    if #normal == 0 then return priority end
    if #priority == 0 then return normal end
    local out = {}
    for _, item in ipairs(normal) do
        table.insert(out, item)
        for _, p in ipairs(priority) do table.insert(out, p) end
    end
    return out
end

local function performMarketScan()
    if Scanning then return end
    Scanning = true
    TotalScans += 1
    if MarketStatus then MarketStatus.Text = "SCANNING" end
    if ScanCount then ScanCount.Text = "SCANS  " .. TotalScans end
    local order = buildScanOrder()
    if #order == 0 then
        addLog("No enabled watchlist items", "WARNING")
    else
        for _, item in ipairs(order) do
            if not ScreenGui or not ScreenGui.Parent then break end
            scanMarketItem(item)
            refreshWatchlist()
            task.wait(CONFIG.RequestDelay)
        end
    end
    Scanning = false
    if MarketStatus then
        MarketStatus.Text = Monitoring and "MONITORING" or "IDLE"
        MarketStatus.TextColor3 = Monitoring and COLORS.green or COLORS.orange
    end
end

local function startMarketMonitor()
    if Monitoring then return end
    Monitoring = true
    ScanToken += 1
    local token = ScanToken
    MarketStatus.Text = "MONITORING"
    MarketStatus.TextColor3 = COLORS.green
    addLog("Market monitoring started", "SYSTEM")
    task.spawn(function()
        while Monitoring and ScanToken == token do
            if not Scanning then performMarketScan() end
            task.wait(CONFIG.ScanInterval)
        end
    end)
end

local function stopMarketMonitor()
    Monitoring = false
    ScanToken += 1
    if MarketStatus then
        MarketStatus.Text = "STOPPED"
        MarketStatus.TextColor3 = COLORS.orange
    end
    addLog("Market monitoring stopped", "SYSTEM")
end

--==================================================
-- PURCHASE TOAST REPORT
--==================================================

local function parsePurchaseToast(text)
    if type(text) ~= "string" then return nil end
    local clean = text:gsub("\n"," "):gsub("%s+"," ")
    local qty, item, priceText = clean:match("Bought:%s*(%d+)%s*x%s*(.-)%s+for%s+%$%s*([%d,]+)")
    if not qty or not item or not priceText then return nil end
    local cleanPrice = (priceText:gsub(",",""))
    local price = tonumber(cleanPrice)
    if not price then return nil end
    return {
        quantity=tonumber(qty), item=item:gsub("%s+$",""), price=price,
        raw=clean, time=os.date("%H:%M:%S"),
    }
end

local function inspectPurchaseText(obj)
    if not obj:IsA("TextLabel") and not obj:IsA("TextButton") then return end
    local function inspect()
        local text = obj.Text
        if type(text) ~= "string" or text == "" or SeenPurchaseText[obj] == text then return end
        SeenPurchaseText[obj] = text
        local record = parsePurchaseToast(text)
        if not record or not isWatchlistPurchase(record.item) then return end
        table.insert(PurchaseRecords, 1, record)
        PurchaseTotalSpent += record.price
        PurchaseTotalUnits += record.quantity
        saveState()
        addLog("Purchase confirmed: " .. record.quantity .. " x " .. record.item .. " for $" .. formatNumber(record.price), "PURCHASE")
    end
    inspect()
    table.insert(PurchaseConnections, obj:GetPropertyChangedSignal("Text"):Connect(inspect))
end

--==================================================
-- NPC RESTOCK TIMER SCANNER
--==================================================

local function getNPCText()
    local ok, toolbar = pcall(function()
        local menu = PlayerGui:FindFirstChild("HushMenu")
        local root = menu and menu:FindFirstChild("Root")
        local pages = root and root:FindFirstChild("Pages")
        local page = pages and pages:FindFirstChild("Page_traders")
        local traders = page and page:FindFirstChild("Traders")
        local content = traders and traders:FindFirstChild("Content")
        local right = content and content:FindFirstChild("Right")
        local body = right and right:FindFirstChild("Body")
        return body and body:FindFirstChild("Toolbar")
    end)
    if not ok or not toolbar then return nil, nil end

    for _, obj in ipairs(toolbar:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
            local text = tostring(obj.Text or "")
            local mm, ss = text:match("[Rr]estock%s+in%s+(%d+):(%d+)")
            if mm and ss then
                mm, ss = tonumber(mm), tonumber(ss)
                if mm and ss and ss < 60 then
                    return mm * 60 + ss, text
                end
            end
        end
    end
    return nil, nil
end

local function formatTime(seconds)
    return string.format("%02d:%02d", math.floor(seconds/60), seconds%60)
end

local function buyAllNPCAmmo(manual)
    manual = manual == true

    if NPCBuying then
        if NPCAction then
            NPCAction.Text = "A PURCHASE BATCH IS ALREADY RUNNING"
        end
        addLog("Buy All Now ignored: an NPC batch is already running", "WARNING")
        return false
    end

    if not manual and not NPCMonitoring then
        return false
    end

    NPCBuying = true
    local sent = 0
    local interrupted = false

    NPCAction.Text = (manual and "MANUAL BUY ALL" or "AUTO RESTOCK BUY")
        .. "  •  0 / " .. #ammoList
    addLog(manual and "Manual Buy All Now started" or "Automatic NPC batch started", "NPC")

    for i, ammo in ipairs(ammoList) do
        -- Manual batches are independent from the monitor state. Automatic batches
        -- still stop if the user disables the monitor while the batch is running.
        if not manual and not NPCMonitoring then
            interrupted = true
            break
        end

        NPCAction.Text = string.format(
            "%s  •  %d / %d  •  %s",
            manual and "MANUAL BUYING" or "AUTO BUYING",
            i, #ammoList, ammo.offer
        )

        -- Match the exact argument shape from the working RemoteEvent examples:
        -- args[1] is the payload table, then FireServer(unpack(args)).
        local args = {
            [1] = {
                ["trader"] = "gunner",
                ["op"] = "buy",
                ["count"] = ammo.count,
                ["offer"] = ammo.offer,
                ["req"] = ammo.req,
            }
        }

        local ok, err = pcall(function()
            if not MenuOp or not MenuOp:IsA("RemoteEvent") then
                error("HushNet.menu.op is missing or is not a RemoteEvent")
            end
            MenuOp:FireServer(unpack(args))
        end)

        if ok then
            sent += 1
            TotalNPCRequests += 1
            NPCRequests.Text = "REQUESTS FIRED  " .. TotalNPCRequests
            addLog(string.format(
                "%s request fired: %s | count=%d | req=%d",
                manual and "MANUAL" or "AUTO",
                ammo.offer, ammo.count, ammo.req
            ), "NPC")
        else
            addLog("NPC request failed " .. ammo.offer .. ": " .. tostring(err), "ERROR")
        end

        task.wait(CONFIG.NPCRequestDelay)
    end

    if sent > 0 then
        TotalNPCCycles += 1
        NPCCycles.Text = "BATCHES  " .. TotalNPCCycles .. "     •     AMMO TYPES  11"
    end

    if interrupted then
        NPCAction.Text = "AUTO BATCH INTERRUPTED  •  " .. sent .. " / " .. #ammoList
        addLog("Automatic NPC batch interrupted after " .. sent .. " requests", "WARNING")
    elseif manual then
        NPCAction.Text = NPCMonitoring
            and ("MANUAL BATCH COMPLETE  •  AUTO TIMER STILL RUNNING")
            or "MANUAL BATCH COMPLETE"
        addLog("Manual NPC batch finished: " .. sent .. " / " .. #ammoList .. " RemoteEvent calls fired (server purchase not confirmed)", "NPC")
    else
        NPCAction.Text = "AUTO BATCH SENT  •  NEXT RESTOCK CYCLE"
        addLog("Automatic NPC batch finished: " .. sent .. " / " .. #ammoList .. " RemoteEvent calls fired (server purchase not confirmed)", "NPC")
    end

    NPCBuying = false
    return true
end

-- NPC timer is stored as a deadline, not read repeatedly from a possibly
-- hidden/frozen trader TextLabel. GetServerTimeNow is synchronized to the server.
local NPCDeadline = nil
local NPCTriggerPending = false
local NPCCountdownThreadRunning = false
local NPCLastSyncedText = "Not synced"

local function npcClock()
    local ok, value = pcall(function()
        return workspace:GetServerTimeNow()
    end)
    if ok and type(value) == "number" then
        return value
    end
    return os.clock()
end

local function updateNPCCountdownDisplay(remaining)
    remaining = math.max(0, math.floor(remaining))
    if NPCTimer then
        NPCTimer.Text = "NEXT BUY IN  " .. formatTime(remaining)
    end
    if NPCSeconds then
        NPCSeconds.Text = tostring(remaining) .. " seconds remaining"
    end
end

syncNPCFromGameLabel = function()
    local remaining, raw = getNPCText()
    if remaining == nil then
        if NPCSource then
            NPCSource.Text = "SOURCE  Live timer not found — open NPC trader"
        end
        if NPCAction then
            NPCAction.Text = "WAITING FOR GAME TIMER"
        end
        return false
    end

    NPCDeadline = npcClock() + remaining
    NPCLastSyncedText = tostring(raw)
    NPCTriggerPending = false

    updateNPCCountdownDisplay(remaining)

    if NPCSource then
        NPCSource.Text = "SYNCED FROM GAME  •  " .. NPCLastSyncedText
    end
    if NPCAction then
        NPCAction.Text = "LOCAL 15-MINUTE TIMER"
    end

    addLog("NPC timer reference: " .. NPCLastSyncedText, "NPC")
    return true
end

local function startNPCMonitor()
    if NPCMonitoring then return end

    NPCMonitoring = true
    NPCStatus.Text = "MONITORING"
    NPCStatus.TextColor3 = COLORS.green
    addLog("NPC 15-minute auto-buy monitor started", "NPC")

    -- Always begin with a fresh local 15-minute interval.
    -- The in-game "Restock in" label is intentionally not used.
    NPCDeadline = npcClock() + 900
    NPCLastSyncedText = "Local 15:00 interval"
    updateNPCCountdownDisplay(900)
    if NPCSource then
        NPCSource.Text = "SOURCE  LOCAL 15-MINUTE INTERVAL"
    end
    NPCAction.Text = "NEXT AUTOMATIC BUY IN 15:00"

    if NPCCountdownThreadRunning then return end
    NPCCountdownThreadRunning = true

    task.spawn(function()
        while NPCMonitoring and ScreenGui and ScreenGui.Parent do
            if NPCDeadline then
                local remaining = math.max(0, math.ceil(NPCDeadline - npcClock()))
                updateNPCCountdownDisplay(remaining)

                if remaining <= 0 and not NPCTriggerPending and not NPCBuying then
                    NPCTriggerPending = true
                    NPCAction.Text = "RESTOCK ZERO  •  WAITING 3 SECONDS"

                    task.wait(CONFIG.NPCTriggerDelay)

                    if not NPCMonitoring then
                        NPCTriggerPending = false
                        break
                    end

                    -- Re-check the deadline after the 3-second grace period.
                    if NPCDeadline and npcClock() >= NPCDeadline then
                        local autoBatchStarted = buyAllNPCAmmo(false)

                        -- Reset only after the automatic batch actually ran.
                        -- If a manual batch was in progress, leave the expired deadline
                        -- intact so the monitor can retry as soon as the manual batch ends.
                        if autoBatchStarted and NPCMonitoring then
                            NPCDeadline = npcClock() + 900
                            NPCLastSyncedText = "Local 15:00 cycle"
                            updateNPCCountdownDisplay(900)
                            NPCAction.Text = "BATCH SENT  •  NEXT CYCLE 15:00"
                            NPCSource.Text = "SOURCE  LOCAL 15-MINUTE INTERVAL"
                        end
                    end

                    NPCTriggerPending = false
                end
            else
                NPCTimer.Text = "NEXT BUY IN  15:00"
                NPCSeconds.Text = "15-minute automatic purchase interval"
                NPCSource.Text = "SOURCE  LOCAL 15-MINUTE INTERVAL"
                NPCAction.Text = "WAITING FOR MONITOR"
            end

            task.wait(0.2)
        end

        NPCCountdownThreadRunning = false
    end)
end

local function stopNPCMonitor()
    NPCMonitoring = false
    NPCTriggerPending = false
    NPCStatus.Text = "STOPPED"
    NPCStatus.TextColor3 = COLORS.orange
    NPCAction.Text = "MONITOR STOPPED"
    addLog("NPC restock monitor stopped", "NPC")
end

--==================================================
-- GUI ROOT / DESKTOP LAYOUT
--==================================================

local old = PlayerGui:FindFirstChild("HushControlCenter")
if old then old:Destroy() end

ScreenGui = make("ScreenGui", {
    Name="HushControlCenter", ResetOnSpawn=false,
    IgnoreGuiInset=true, DisplayOrder=999999,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
}, PlayerGui)

local Main = make("Frame", {
    Name="Main", Size=UDim2.fromOffset(380, 58),
    Position=UDim2.new(0.5,-190,0.5,-29),
    BackgroundColor3=COLORS.bg, BorderSizePixel=0,
}, ScreenGui)
Main:SetAttribute("Minimized", true)
addCorner(Main, 14)
addStroke(Main, COLORS.border, 1)

-- Compact scaling for phones; desktop/tablet keeps the original dimensions.
local MobileScale = make("UIScale", {
    Scale = UserInputService.TouchEnabled and 0.78 or 1,
}, Main)

local Top = make("Frame", {
    Size=UDim2.new(1,0,0,58), BackgroundColor3=COLORS.panel,
    BorderSizePixel=0,
}, Main)
addCorner(Top, 14)

local Brand = label(Top, "HUSH CONTROL", 15, COLORS.text, true)
Brand.Position = UDim2.fromOffset(12, 5)
Brand.Size = UDim2.new(0, 220, 0, 24)

local BrandSub = label(Top, "MARKET  •  NPC AUTOMATION", 9, COLORS.muted, false)
BrandSub.Position = UDim2.fromOffset(13, 30)
BrandSub.Size = UDim2.new(0, 220, 0, 16)

local WindowStatus = label(Top, "● READY", 9, COLORS.green, true)
WindowStatus.Position = UDim2.new(1,-170,0,17)
WindowStatus.Size = UDim2.fromOffset(42,20)
WindowStatus.Text = "●"
WindowStatus.TextXAlignment = Enum.TextXAlignment.Right

local Body -- forward declaration for the minimize callback
local Minimize = button(Top, "+", function()
    local minimized = not Main:GetAttribute("Minimized")
    Main:SetAttribute("Minimized", minimized)
    Main.Size = minimized and UDim2.fromOffset(380,58) or UDim2.fromOffset(380,700)
    Body.Visible = not minimized
    Minimize.Text = minimized and "+" or "—"
end, COLORS.panel3, 34, 30)
Minimize.Position = UDim2.new(1,-42,0,14)

-- Drag title bar
local dragging, dragStart, startPos = false, nil, nil
Top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = Main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+delta.X, startPos.Y.Scale, startPos.Y.Offset+delta.Y)
    end
end)

Body = make("Frame", {
    BackgroundTransparency=1, Position=UDim2.fromOffset(8,66),
    Size=UDim2.new(1,-16,1,-74), Visible=false,
}, Main)

local Tabs = make("Frame", {
    BackgroundTransparency=1, Size=UDim2.new(1,0,0,38),
}, Body)

local function makeTab(text, x)
    local b = button(Tabs, text, function() end, COLORS.panel2, 178, 36)
    b.Position = UDim2.fromOffset(x,0)
    b.TextSize = 10
    return b
end

local MarketTab = makeTab("◈ MARKET SNIPER", 0)
local NPCTab = makeTab("◉ NPC AUTO BUY", 186)

local PageArea = make("Frame", {
    BackgroundTransparency=1, Position=UDim2.fromOffset(0,46),
    Size=UDim2.new(1,0,1,-46),
}, Body)

local MarketPage = make("ScrollingFrame", {
    BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=true,
    BorderSizePixel=0, ScrollBarThickness=4, ScrollBarImageColor3=COLORS.accent,
    AutomaticCanvasSize=Enum.AutomaticSize.Y, CanvasSize=UDim2.new(0,0,0,0),
}, PageArea)

local NPCPage = make("ScrollingFrame", {
    BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=false,
    BorderSizePixel=0, ScrollBarThickness=4, ScrollBarImageColor3=COLORS.accent,
    AutomaticCanvasSize=Enum.AutomaticSize.Y, CanvasSize=UDim2.new(0,0,0,0),
}, PageArea)

local syncNPCFromGameLabel -- assigned after NPC timer UI is created

local function showTab(which)
    local market = which == "MARKET"
    MarketPage.Visible = market
    NPCPage.Visible = not market
    MarketTab.BackgroundColor3 = market and COLORS.accent or COLORS.panel2
    NPCTab.BackgroundColor3 = market and COLORS.panel2 or COLORS.accent

    -- Fetch the game's current timer only when entering the NPC tab.
    if not market and syncNPCFromGameLabel then
        syncNPCFromGameLabel()
    end
end
MarketTab.Activated:Connect(function() showTab("MARKET") end)
NPCTab.Activated:Connect(function() showTab("NPC") end)

--==================================================
-- MARKET PAGE UI — MOBILE PORTRAIT
--==================================================

local MarketHeader = make("Frame", {
    BackgroundColor3=COLORS.panel, Size=UDim2.new(1,-4,0,112),
    Position=UDim2.fromOffset(2,2), BorderSizePixel=0,
}, MarketPage)
addCorner(MarketHeader, 10)

local MarketTitle = label(MarketHeader, "MARKET SNIPER", 14, COLORS.text, true)
MarketTitle.Position = UDim2.fromOffset(12,6)
MarketTitle.Size = UDim2.fromOffset(180,20)

MarketStatus = label(MarketHeader, "IDLE", 10, COLORS.orange, true)
MarketStatus.Position = UDim2.fromOffset(12,29)
MarketStatus.Size = UDim2.fromOffset(100,18)

ScanCount = label(MarketHeader, "SCANS  0", 9, COLORS.muted, true)
ScanCount.Position = UDim2.fromOffset(116,29)
ScanCount.Size = UDim2.fromOffset(90,18)

local ForceScan = button(MarketHeader, "SCAN NOW", function()
    task.spawn(performMarketScan)
end, COLORS.blue, 108, 30)
ForceScan.Position = UDim2.fromOffset(10,66)

local StartMarket = button(MarketHeader, "START", startMarketMonitor, COLORS.green, 104, 30)
StartMarket.Position = UDim2.fromOffset(126,66)

local StopMarket = button(MarketHeader, "STOP", stopMarketMonitor, COLORS.red, 104, 30)
StopMarket.Position = UDim2.fromOffset(238,66)

local Form = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(2,122),
    Size=UDim2.new(1,-4,0,208), BorderSizePixel=0,
}, MarketPage)
addCorner(Form, 9)

local IdBox = textbox(Form, "Item ID", 340)
IdBox.Position = UDim2.fromOffset(10,9)
IdBox.Size = UDim2.new(1,-20,0,32)

local NameBox = textbox(Form, "Display name (optional)", 340)
NameBox.Position = UDim2.fromOffset(10,48)
NameBox.Size = UDim2.new(1,-20,0,32)

local PriceBox = textbox(Form, "Max price", 340)
PriceBox.Position = UDim2.fromOffset(10,87)
PriceBox.Size = UDim2.new(1,-20,0,32)

local AddWatch = button(Form, "ADD / UPDATE ITEM", function()
    local ok, err = pcall(function()
        local id = tostring(IdBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local name = tostring(NameBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local priceText = tostring(PriceBox.Text or "")
        local cleanedPrice = (priceText:gsub("[%$,]", ""):gsub("%s+", ""))
        local price = tonumber(cleanedPrice)

        if id == "" then
            FormStatus.Text = "ERROR: Item ID required"
            FormStatus.TextColor3 = COLORS.red
            return
        end
        if not validItemId(id) then
            FormStatus.Text = "ERROR: Invalid Item ID"
            FormStatus.TextColor3 = COLORS.red
            return
        end
        if not price or price <= 0 or price == math.huge then
            FormStatus.Text = "ERROR: Enter a valid max price"
            FormStatus.TextColor3 = COLORS.red
            return
        end

        local item = findWatchItem(id)
        local action
        if item then
            item.name = name ~= "" and name or item.name
            item.maxPrice = price
            item.enabled = true
            action = "UPDATED"
        else
            table.insert(Watchlist, {
                id=id, name=name ~= "" and name or id, maxPrice=price,
                enabled=true, autoBuy=false, priority=false, lastBuyAttempt=0,
            })
            action = "ADDED"
        end

        Results[id] = nil
        saveState()
        refreshWatchlist()
        FormStatus.Text = action .. "  •  " .. id .. "  •  $" .. formatNumber(price)
        FormStatus.TextColor3 = COLORS.green
        IdBox.Text, NameBox.Text, PriceBox.Text = "", "", ""
        addLog(action .. " watchlist item: " .. id, "WATCHLIST")
    end)
    if not ok then
        FormStatus.Text = "ERROR: " .. tostring(err)
        FormStatus.TextColor3 = COLORS.red
        warn("[HUSH CONTROL] Add/Update failed: " .. tostring(err))
        addLog("Add/update callback error: " .. tostring(err), "ERROR")
    end
end, COLORS.accent, 160, 32)
AddWatch.Position = UDim2.fromOffset(10,126)

local DelayBox = textbox(Form, "Delay", 76)
DelayBox.Position = UDim2.new(1,-164,0,126)
DelayBox.Size = UDim2.fromOffset(70,32)
DelayBox.Text = tostring(CONFIG.RequestDelay)

local SaveDelay = button(Form, "SAVE", function()
    local n = tonumber(DelayBox.Text)
    if not n then addLog("Invalid scan delay", "WARNING"); return end
    CONFIG.RequestDelay = math.clamp(n,0.1,60)
    DelayBox.Text = tostring(CONFIG.RequestDelay)
    saveState()
    addLog("Scan delay set to " .. CONFIG.RequestDelay .. "s", "CONFIG")
end, COLORS.panel3, 72, 32)
SaveDelay.Position = UDim2.new(1,-84,0,126)

FormStatus = label(Form, "Add an item using ID and max price.", 9, COLORS.muted, false)
FormStatus.Position = UDim2.fromOffset(10,166)
FormStatus.Size = UDim2.new(1,-20,0,30)
FormStatus.TextWrapped = true

local WatchPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(2,338),
    Size=UDim2.new(1,-4,0,340), BorderSizePixel=0,
}, MarketPage)
addCorner(WatchPanel, 9)

local WatchHeading = label(WatchPanel, "WATCHLIST", 12, COLORS.text, true)
WatchHeading.Position = UDim2.fromOffset(12,7)
WatchHeading.Size = UDim2.new(1,-24,0,22)

local WatchScroll = make("ScrollingFrame", {
    BackgroundColor3=COLORS.bg, Position=UDim2.fromOffset(8,34),
    Size=UDim2.new(1,-16,1,-42), BorderSizePixel=0,
    ScrollBarThickness=4, ScrollBarImageColor3=COLORS.accent,
    AutomaticCanvasSize=Enum.AutomaticSize.Y, CanvasSize=UDim2.new(0,0,0,0),
}, WatchPanel)
addCorner(WatchScroll, 7)
make("UIListLayout", {Padding=UDim.new(0,5), SortOrder=Enum.SortOrder.LayoutOrder}, WatchScroll)
make("UIPadding", {PaddingTop=UDim.new(0,5),PaddingBottom=UDim.new(0,5),PaddingLeft=UDim.new(0,5),PaddingRight=UDim.new(0,5)}, WatchScroll)

local GridPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(2,686),
    Size=UDim2.new(1,-4,0,330), BorderSizePixel=0,
}, MarketPage)
addCorner(GridPanel, 9)

local GridHeading = label(GridPanel, "MARKET GRID ID SCANNER", 12, COLORS.text, true)
GridHeading.Position = UDim2.fromOffset(12,7)
GridHeading.Size = UDim2.new(1,-24,0,22)

GridStatus = label(GridPanel, "GRID WAITING — OPEN MARKET", 9, COLORS.orange, true)
GridStatus.Position = UDim2.fromOffset(12,30)
GridStatus.Size = UDim2.new(1,-24,0,18)

local ScanGrid = button(GridPanel, "SCAN GRID", function()
    scanMarketGrid()
    refreshIDList()
end, COLORS.blue, 112, 30)
ScanGrid.Position = UDim2.fromOffset(10,54)

local CopyIDs = button(GridPanel, "COPY ALL", function()
    if #DiscoveredIDs == 0 then addLog("No IDs discovered", "WARNING"); return end
    if safeClipboard(table.concat(DiscoveredIDs,"\n")) then
        addLog("Copied " .. #DiscoveredIDs .. " IDs", "ID SCANNER")
    else
        addLog("Clipboard unavailable", "ERROR")
    end
end, COLORS.panel3, 100, 30)
CopyIDs.Position = UDim2.new(1,-110,0,54)

local SearchID = textbox(GridPanel, "Filter discovered IDs...", 300)
SearchID.Position = UDim2.fromOffset(10,92)
SearchID.Size = UDim2.new(1,-20,0,32)

IDList = make("ScrollingFrame", {
    BackgroundColor3=COLORS.bg, Position=UDim2.fromOffset(8,132),
    Size=UDim2.new(1,-16,1,-140), BorderSizePixel=0,
    ScrollBarThickness=4, AutomaticCanvasSize=Enum.AutomaticSize.Y,
    CanvasSize=UDim2.new(0,0,0,0),
}, GridPanel)
addCorner(IDList, 6)
make("UIListLayout", {Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder}, IDList)
make("UIPadding", {PaddingTop=UDim.new(0,4),PaddingBottom=UDim.new(0,4),PaddingLeft=UDim.new(0,4),PaddingRight=UDim.new(0,4)}, IDList)

local LogPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(2,1024),
    Size=UDim2.new(1,-4,0,220), BorderSizePixel=0,
}, MarketPage)
addCorner(LogPanel, 9)

local LogHeading = label(LogPanel, "ACTIVITY LOG", 11, COLORS.text, true)
LogHeading.Position = UDim2.fromOffset(12,7)
LogHeading.Size = UDim2.new(1,-24,0,22)

LogList = make("ScrollingFrame", {
    BackgroundColor3=COLORS.bg, Position=UDim2.fromOffset(8,34),
    Size=UDim2.new(1,-16,1,-42), BorderSizePixel=0,
    ScrollBarThickness=4, AutomaticCanvasSize=Enum.AutomaticSize.Y,
    CanvasSize=UDim2.new(0,0,0,0),
}, LogPanel)
addCorner(LogList, 6)
make("UIListLayout", {Padding=UDim.new(0,2),SortOrder=Enum.SortOrder.LayoutOrder}, LogList)
make("UIPadding", {PaddingTop=UDim.new(0,4),PaddingBottom=UDim.new(0,4),PaddingLeft=UDim.new(0,5),PaddingRight=UDim.new(0,5)}, LogList)

-- MARKET UI REFRESH
--==================================================

function refreshWatchlist()
    if not WatchScroll then return end
    for _, child in ipairs(WatchScroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    for index, item in ipairs(Watchlist) do
        local result = Results[item.id] or {}
        local card = make("Frame", {
            BackgroundColor3=COLORS.panel2, Size=UDim2.new(1,-4,0,126),
            BorderSizePixel=0, LayoutOrder=index,
        }, WatchScroll)
        addCorner(card, 7)

        local name = label(card, item.name, 11, COLORS.text, true)
        name.Position=UDim2.fromOffset(9,5)
        name.Size=UDim2.new(1,-18,0,18)
        name.TextTruncate=Enum.TextTruncate.AtEnd

        local infoText = result.success and result.lowest
            and ("LOWEST $"..formatNumber(result.lowest).."  •  LISTINGS "..tostring(result.count or 0))
            or (result.success and "NO ACTIVE LISTINGS" or (result.error and "SCAN ERROR" or "WAITING FOR SCAN"))
        local info = label(card,infoText,9,
            result.success and result.lowest and result.lowest <= item.maxPrice and COLORS.green or COLORS.muted,true)
        info.Position=UDim2.fromOffset(9,26)
        info.Size=UDim2.new(1,-18,0,17)
        info.TextTruncate=Enum.TextTruncate.AtEnd

        local max = label(card,"MAX $"..formatNumber(item.maxPrice).."  •  "..item.id,9,COLORS.orange,true)
        max.Position=UDim2.fromOffset(9,45)
        max.Size=UDim2.new(1,-18,0,17)
        max.TextTruncate=Enum.TextTruncate.AtEnd

        local function small(text,x,y,w,color,fn)
            local b=button(card,text,fn,color,w,27)
            b.Position=UDim2.fromOffset(x,y)
            b.TextSize=8
            return b
        end

        small(item.priority and "★ PRIORITY" or "☆ PRIORITY",8,70,82,item.priority and COLORS.orange or COLORS.panel3,function()
            if item.priority then item.priority=false else
                for _,other in ipairs(Watchlist) do other.priority=false end
                item.priority=true
            end
            saveState(); refreshWatchlist()
        end)
        small(item.enabled and "ON" or "OFF",96,70,48,item.enabled and COLORS.green or COLORS.red,function()
            item.enabled=not item.enabled; saveState(); refreshWatchlist()
        end)
        small(item.autoBuy and "AUTO ON" or "AUTO OFF",150,70,72,item.autoBuy and COLORS.green or COLORS.panel3,function()
            item.autoBuy=not item.autoBuy; saveState(); refreshWatchlist()
        end)
        small("EDIT PRICE",228,70,78,COLORS.blue,function()
            IdBox.Text=item.id; NameBox.Text=item.name; PriceBox.Text=tostring(item.maxPrice)
            FormStatus.Text="Editing "..item.name.." — update price then tap ADD / UPDATE."
            FormStatus.TextColor3=COLORS.blue
            MarketPage.CanvasPosition=Vector2.new(0,0)
        end)
        small("DEL",312,70,38,COLORS.red,function()
            table.remove(Watchlist,index); Results[item.id]=nil
            saveState(); refreshWatchlist()
        end)
    end
end

function refreshIDList()
    if not IDList then return end
    for _, child in ipairs(IDList:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
    local q = (SearchID and SearchID.Text or ""):lower()
    for i,id in ipairs(DiscoveredIDs) do
        if q == "" or id:lower():find(q,1,true) then
            local row = make("Frame", {
                BackgroundColor3=COLORS.panel2, Size=UDim2.new(1,-3,0,38),
                BorderSizePixel=0, LayoutOrder=i,
            }, IDList)
            addCorner(row,5)
            local txt = label(row,id,9,COLORS.text,true)
            txt.Position=UDim2.fromOffset(7,0)
            txt.Size=UDim2.new(1,-92,1,0)
            local copy = button(row,"COPY",function()
                if safeClipboard(id) then addLog("Copied ID "..id,"ID SCANNER") end
            end,COLORS.panel3,40,24)
            copy.Position=UDim2.new(1,-82,0,7)
            local add = button(row,"USE",function()
                IdBox.Text=id
                NameBox.Text=id
            end,COLORS.accent,38,24)
            add.Position=UDim2.new(1,-40,0,7)
        end
    end
end

SearchID:GetPropertyChangedSignal("Text"):Connect(refreshIDList)

--==================================================
-- NPC PAGE UI — MOBILE PORTRAIT
--==================================================

local NPCHeader = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(2,2),
    Size=UDim2.new(1,-4,0,126), BorderSizePixel=0,
}, NPCPage)
addCorner(NPCHeader, 10)

local NPCTitle = label(NPCHeader, "NPC AUTO BUY  /  15 MIN", 13, COLORS.text, true)
NPCTitle.Position=UDim2.fromOffset(12,7)
NPCTitle.Size=UDim2.new(1,-24,0,22)

NPCStatus = label(NPCHeader, "STOPPED", 9, COLORS.orange, true)
NPCStatus.Position=UDim2.fromOffset(12,32)
NPCStatus.Size=UDim2.fromOffset(120,18)

NPCTimer = label(NPCHeader, "NEXT BUY IN  15:00", 25, COLORS.text, true)
NPCTimer.Position=UDim2.fromOffset(12,54)
NPCTimer.Size=UDim2.new(1,-24,0,36)

NPCSeconds = label(NPCHeader, "15-minute automatic purchase interval", 9, COLORS.blue, true)
NPCSeconds.Position=UDim2.fromOffset(12,94)
NPCSeconds.Size=UDim2.new(1,-24,0,20)

local NPCButtons = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(2,138),
    Size=UDim2.new(1,-4,0,112), BorderSizePixel=0,
}, NPCPage)
addCorner(NPCButtons, 9)

local NPCStart = button(NPCButtons,"START MONITOR",startNPCMonitor,COLORS.green,166,34)
NPCStart.Position=UDim2.fromOffset(9,8)

local NPCStop = button(NPCButtons,"STOP",stopNPCMonitor,COLORS.red,76,34)
NPCStop.Position=UDim2.fromOffset(183,8)

local NPCBuyAll = button(NPCButtons,"BUY ALL NOW",function()
    task.spawn(function() buyAllNPCAmmo(true) end)
end,COLORS.blue,350,34)
NPCBuyAll.Position=UDim2.fromOffset(9,50)
NPCBuyAll.Size=UDim2.new(1,-18,0,34)

NPCRequests = label(NPCButtons,"REQUESTS FIRED  0",9,COLORS.muted,true)
NPCRequests.Position=UDim2.fromOffset(10,88)
NPCRequests.Size=UDim2.fromOffset(150,17)

NPCCycles = label(NPCButtons,"BATCHES  0  •  11 AMMO TYPES",9,COLORS.muted,true)
NPCCycles.Position=UDim2.new(1,-190,0,88)
NPCCycles.Size=UDim2.fromOffset(180,17)
NPCCycles.TextXAlignment=Enum.TextXAlignment.Right

local AmmoPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(2,260),
    Size=UDim2.new(1,-4,0,444), BorderSizePixel=0,
}, NPCPage)
addCorner(AmmoPanel,9)

local AmmoHeading = label(AmmoPanel,"PURCHASE QUEUE  /  11 AMMO TYPES",11,COLORS.text,true)
AmmoHeading.Position=UDim2.fromOffset(12,8)
AmmoHeading.Size=UDim2.new(1,-24,0,22)

local AmmoScroll = make("ScrollingFrame", {
    BackgroundColor3=COLORS.bg, Position=UDim2.fromOffset(8,36),
    Size=UDim2.new(1,-16,1,-44), BorderSizePixel=0,
    ScrollBarThickness=4, AutomaticCanvasSize=Enum.AutomaticSize.Y,
    CanvasSize=UDim2.new(0,0,0,0),
}, AmmoPanel)
addCorner(AmmoScroll,7)
make("UIListLayout",{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder},AmmoScroll)
make("UIPadding",{PaddingTop=UDim.new(0,5),PaddingBottom=UDim.new(0,5),PaddingLeft=UDim.new(0,5),PaddingRight=UDim.new(0,5)},AmmoScroll)

for i,ammo in ipairs(ammoList) do
    local row=make("Frame",{
        BackgroundColor3=COLORS.panel2,Size=UDim2.new(1,-4,0,34),
        BorderSizePixel=0,LayoutOrder=i,
    },AmmoScroll)
    addCorner(row,5)
    local group=i<=5 and "12GA" or ".308"
    local t=label(row,string.format("%02d  %s  •  %s",i,group,ammo.offer),9,COLORS.text,true)
    t.Position=UDim2.fromOffset(8,0)
    t.Size=UDim2.new(1,-125,1,0)
    local detail=label(row,"x"..ammo.count.." / "..ammo.req,9,COLORS.muted,true)
    detail.Position=UDim2.new(1,-112,0,0)
    detail.Size=UDim2.fromOffset(102,34)
    detail.TextXAlignment=Enum.TextXAlignment.Right
end

local NPCInfo = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(2,714),
    Size=UDim2.new(1,-4,0,190), BorderSizePixel=0,
}, NPCPage)
addCorner(NPCInfo,9)

local InfoHeading = label(NPCInfo,"MONITOR DETAILS",11,COLORS.text,true)
InfoHeading.Position=UDim2.fromOffset(12,8)
InfoHeading.Size=UDim2.new(1,-24,0,22)

NPCAction = label(NPCInfo,"ACTION  IDLE",10,COLORS.orange,true)
NPCAction.Position=UDim2.fromOffset(12,36)
NPCAction.Size=UDim2.new(1,-24,0,30)
NPCAction.TextWrapped=true

NPCSource = label(NPCInfo,"SOURCE  Toolbar descendants",9,COLORS.muted,false)
NPCSource.Position=UDim2.fromOffset(12,72)
NPCSource.Size=UDim2.new(1,-24,0,42)
NPCSource.TextWrapped=true

local DelayInfo = label(NPCInfo,"TRIGGER  3 SEC  •  RESET  15:00",9,COLORS.blue,true)
DelayInfo.Position=UDim2.fromOffset(12,122)
DelayInfo.Size=UDim2.new(1,-24,0,20)

local NPCNote = label(NPCInfo,"Timer keeps running while you switch tabs. Opening this tab syncs it with the live NPC timer.",9,COLORS.muted,false)
NPCNote.Position=UDim2.fromOffset(12,146)
NPCNote.Size=UDim2.new(1,-24,0,36)
NPCNote.TextWrapped=true

--==================================================
-- ANTI-AFK TOGGLE (TOP BAR)
--==================================================

local AntiAFKButton
AntiAFKButton = button(Top,"ANTI-AFK OFF",function()
    AntiAFKEnabled = not AntiAFKEnabled
    if AntiAFKConnection then
        AntiAFKConnection:Disconnect()
        AntiAFKConnection=nil
    end
    if AntiAFKEnabled then
        AntiAFKConnection = Player.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0,0))
            end)
        end)
        AntiAFKButton.Text="ANTI-AFK ON"
        AntiAFKButton.BackgroundColor3=COLORS.green
    else
        AntiAFKButton.Text="ANTI-AFK OFF"
        AntiAFKButton.BackgroundColor3=COLORS.panel3
    end
    saveState()
end,COLORS.panel3,105,30)
AntiAFKButton.Size=UDim2.fromOffset(86,26)
AntiAFKButton.Position=UDim2.new(1,-132,0,16)

--==================================================
-- PURCHASE REPORT INITIALIZATION / TOAST WATCHER
--==================================================

local function refreshPurchaseTotals()
    PurchaseTotalSpent, PurchaseTotalUnits = 0,0
    for _, r in ipairs(PurchaseRecords) do
        PurchaseTotalSpent += tonumber(r.price) or 0
        PurchaseTotalUnits += tonumber(r.quantity) or 0
    end
end
refreshPurchaseTotals()

local function watchPurchaseContainer(container)
    for _, obj in ipairs(container:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            inspectPurchaseText(obj)
        end
    end
    table.insert(PurchaseConnections,container.DescendantAdded:Connect(function(obj)
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then inspectPurchaseText(obj) end
    end))
end

watchPurchaseContainer(PlayerGui)

--==================================================
-- STARTUP / AUTO REFRESH
--==================================================

refreshWatchlist()
refreshIDList()
saveState()
showTab("MARKET")
addLog("Hush Control Center initialized", "SYSTEM")
addLog("Market API: menu.get / bmItem; buy op: bmBuyBest", "SYSTEM")
addLog("NPC queue loaded: 5x 12GA + 6x .308", "SYSTEM")

task.spawn(function()
    task.wait(2)
    scanMarketGrid()
    refreshIDList()
end)

task.spawn(function()
    while ScreenGui and ScreenGui.Parent do
        task.wait(CONFIG.GridRefreshInterval)
        if not GridScanning then
            local before = #DiscoveredIDs
            scanMarketGrid()
            if #DiscoveredIDs ~= before then refreshIDList() end
        end
    end
end)

ScreenGui.Destroying:Connect(function()
    stopMarketMonitor()
    stopNPCMonitor()
    AntiAFKEnabled=false
    if AntiAFKConnection then AntiAFKConnection:Disconnect() end
    for _, connection in ipairs(PurchaseConnections) do
        pcall(function() connection:Disconnect() end)
    end
    saveState()
end)
