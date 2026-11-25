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
- Reads the actual "Restock in MM:SS" TextLabel under Toolbar
- Displays MM:SS and total seconds
- Waits 3 seconds after 00:00, then sends only enabled ammo requests
- Waits for the next restock cycle before triggering again

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
    {offer="12ga_1", count=3, req=3, enabled=true, required=true},
    {offer="12ga_1_l3", count=1, req=4, enabled=true, required=true},
    {offer="12ga_1_l5", count=3, req=5, enabled=true, required=true},
    {offer="12ga_4_l5", count=2, req=6, enabled=false},
    {offer="12ga_4", count=1, req=7, enabled=false},
    -- .308
    {offer="308_l3", count=2, req=1, enabled=true},
    {offer="308_1_l2", count=2, req=2, enabled=true},
    {offer="308_1", count=2, req=3, enabled=true},
    {offer="308_3", count=1, req=4, enabled=true},
    {offer="308_3_l5", count=2, req=5, enabled=true},
    {offer="308_1_l5", count=3, req=6, enabled=true},
    -- Optional scrapper item
    {offer="cola", count=4, req=2, trader="scrapper", enabled=false},
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

-- Auto Sell UI references / view state
local AutoSellStatus, AutoSellList, AutoSellListLayout
local AutoSellSearch, AutoSellScanTab, AutoSellWatchTab
local AutoSellCurrentView = "SCAN"
local scanSellInventory, renderAutoSellList, setAutoSellView
local setAutoSellEnabled
local AutoSellEnabled = false

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
local AMMO_PRESET_VERSION = 2

-- Preset auto-load settings (persisted in the same config file).
local AutoLoadPresetEnabled = SavedState and SavedState.autoLoadPresetEnabled == true or false
local SelectedPreset = SavedState and SavedState.selectedPreset == "new_map" and "new_map" or "overture"
local AutoStartMarket = not SavedState or SavedState.autoStartMarket ~= false
local AutoStartNPC = not SavedState or SavedState.autoStartNPC ~= false
local BuyAllOnExecute = not SavedState or SavedState.buyAllOnExecute ~= false
local PresetLoadBusy = false
local LastPresetMapState = false

-- First run of this preset: 3 required 12GA buck types ON, remaining 12GA OFF,
-- and every .308 type ON. Later launches restore the user's saved toggles.
if not SavedState or SavedState.ammoPresetVersion ~= AMMO_PRESET_VERSION then
    for _, ammo in ipairs(ammoList) do
        if ammo.required then
            ammo.enabled = true
        elseif string.sub(ammo.offer, 1, 4) == "12ga" then
            ammo.enabled = false
        elseif string.sub(ammo.offer, 1, 3) == "308" then
            ammo.enabled = true
        end
    end
else
    if type(SavedState.ammoEnabled) == "table" then
        for _, ammo in ipairs(ammoList) do
            local savedEnabled = SavedState.ammoEnabled[ammo.offer]
            if type(savedEnabled) == "boolean" then
                ammo.enabled = ammo.required and true or savedEnabled
            end
        end
    end
end
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
        antiAFK=AntiAFKEnabled, ammoEnabled={}, ammoPresetVersion=2,
        autoLoadPresetEnabled=AutoLoadPresetEnabled,
        selectedPreset=SelectedPreset,
        autoStartMarket=AutoStartMarket,
        autoStartNPC=AutoStartNPC,
        buyAllOnExecute=BuyAllOnExecute,
    }
    for _, ammo in ipairs(ammoList) do
        state.ammoEnabled[ammo.offer] = ammo.enabled == true
    end
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
    if HomeRecentText then
        local recent = {}
        for i = 1, math.min(5, #ActivityLog) do table.insert(recent, ActivityLog[i]) end
        HomeRecentText.Text = #recent > 0 and table.concat(recent, "\\n") or "No activity yet."
    end
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
    local price = tonumber(priceText:gsub(",",""))
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

local AmmoHeading -- forward declaration for the queue summary UI

local function getEnabledAmmoList()
    local enabled = {}
    for _, ammo in ipairs(ammoList) do
        if ammo.enabled == true then
            table.insert(enabled, ammo)
        end
    end
    return enabled
end

local function getEnabledAmmoCount()
    local count = 0
    for _, ammo in ipairs(ammoList) do
        if ammo.enabled == true then count += 1 end
    end
    return count
end

local function refreshAmmoSelectionUI()
    if AmmoHeading then
        AmmoHeading.Text = "PURCHASE QUEUE  /  " .. getEnabledAmmoCount() .. " OF " .. #ammoList .. " ENABLED"
    end
    if NPCCycles then
        NPCCycles.Text = "BATCHES  " .. TotalNPCCycles .. "     •     AMMO TYPES  " .. getEnabledAmmoCount()
    end
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

    local purchaseQueue = getEnabledAmmoList()
    if #purchaseQueue == 0 then
        NPCAction.Text = "NO AMMO ENABLED  •  TURN ON AT LEAST ONE TYPE"
        addLog("NPC batch skipped: all ammo types are OFF", "WARNING")
        return false
    end

    NPCBuying = true
    local sent = 0
    local interrupted = false

    NPCAction.Text = (manual and "MANUAL BUY SELECTED" or "AUTO RESTOCK BUY")
        .. "  •  0 / " .. #purchaseQueue
    addLog(manual and "Manual Buy All Now started" or "Automatic NPC batch started", "NPC")

    for i, ammo in ipairs(purchaseQueue) do
        -- Manual batches are independent from the monitor state. Automatic batches
        -- still stop if the user disables the monitor while the batch is running.
        if not manual and not NPCMonitoring then
            interrupted = true
            break
        end

        NPCAction.Text = string.format(
            "%s  •  %d / %d  •  %s",
            manual and "MANUAL BUYING" or "AUTO BUYING",
            i, #purchaseQueue, ammo.offer
        )

        -- Match the exact argument shape from the working RemoteEvent examples:
        -- args[1] is the payload table, then FireServer(unpack(args)).
        local args = {
            [1] = {
                ["trader"] = ammo.trader or "gunner",
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
        NPCCycles.Text = "BATCHES  " .. TotalNPCCycles .. "     •     AMMO TYPES  " .. getEnabledAmmoCount()
    end

    if interrupted then
        NPCAction.Text = "AUTO BATCH INTERRUPTED  •  " .. sent .. " / " .. #purchaseQueue
        addLog("Automatic NPC batch interrupted after " .. sent .. " requests", "WARNING")
    elseif manual then
        NPCAction.Text = NPCMonitoring
            and ("MANUAL BATCH COMPLETE  •  AUTO TIMER STILL RUNNING")
            or "MANUAL BATCH COMPLETE"
        addLog("Manual NPC batch finished: " .. sent .. " / " .. #purchaseQueue .. " selected RemoteEvent calls fired (server purchase not confirmed)", "NPC")
    else
        NPCAction.Text = "SELECTED AMMO SENT  •  NEXT RESTOCK CYCLE"
        addLog("Automatic NPC batch finished: " .. sent .. " / " .. #purchaseQueue .. " selected RemoteEvent calls fired (server purchase not confirmed)", "NPC")
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
    -- os.clock is monotonic for this client session and is ideal for elapsed intervals.
    return os.clock()
end

local function updateNPCCountdownDisplay(remaining)
    remaining = math.max(0, math.floor(remaining))
    if NPCTimer then
        NPCTimer.Text = "RESTOCK IN  " .. formatTime(remaining)
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
        NPCAction.Text = "LIVE TIMER SYNCED"
    end

    addLog("NPC timer synced: " .. NPCLastSyncedText, "NPC")
    return true
end

local function startNPCMonitor()
    if NPCMonitoring then return end

    NPCMonitoring = true
    NPCStatus.Text = "MONITORING"
    NPCStatus.TextColor3 = COLORS.green
    addLog("NPC 15-minute monitor started", "NPC")

    NPCDeadline = npcClock() + 900
    NPCTriggerPending = false
    NPCLastSyncedText = "Local 15-minute interval"
    updateNPCCountdownDisplay(900)
    if NPCSource then
        NPCSource.Text = "SOURCE  LOCAL 15-MINUTE TIMER"
    end
    NPCAction.Text = "NEXT AUTOMATIC BUY IN 15:00"

    if NPCCountdownThreadRunning then return end
    NPCCountdownThreadRunning = true

    task.spawn(function()
        local loopOK, loopErr = pcall(function()
            while NPCMonitoring and ScreenGui and ScreenGui.Parent do
                if not NPCDeadline then
                    NPCDeadline = npcClock() + 900
                    addLog("Timer deadline was missing; initialized a new 15-minute interval", "WARNING")
                end

                local remaining = math.max(0, math.ceil(NPCDeadline - npcClock()))
                updateNPCCountdownDisplay(remaining)

                if remaining <= 0 and not NPCTriggerPending and not NPCBuying then
                    NPCTriggerPending = true
                    NPCAction.Text = "00:00  •  STARTING AUTO BUY"
                    addLog("15-minute timer reached zero; automatic batch trigger queued", "NPC")

                    task.spawn(function()
                        local triggerOK, triggerErr = pcall(function()
                            task.wait(CONFIG.NPCTriggerDelay)

                            if not NPCMonitoring then
                                addLog("Auto-buy cancelled because monitor was stopped", "WARNING")
                                return
                            end

                            if NPCBuying then
                                addLog("Auto-buy deferred: another NPC batch is running", "WARNING")
                                return
                            end

                            -- Run the batch independently so a request error cannot kill the countdown worker.
                            local batchStarted = buyAllNPCAmmo(false)
                            if batchStarted and NPCMonitoring then
                                NPCDeadline = npcClock() + 900
                                NPCLastSyncedText = "Local 15:00 cycle"
                                updateNPCCountdownDisplay(900)
                                NPCAction.Text = "BATCH SENT  •  NEXT CYCLE 15:00"
                                NPCSource.Text = "SOURCE  LOCAL 15-MINUTE TIMER"
                                addLog("Automatic batch finished; next 15-minute interval started", "NPC")
                            elseif NPCMonitoring then
                                -- Avoid getting stuck at zero. Retry in 30 seconds if no batch could start.
                                NPCDeadline = npcClock() + 30
                                updateNPCCountdownDisplay(30)
                                NPCAction.Text = "AUTO BUY DID NOT START  •  RETRY IN 00:30"
                                addLog("Automatic batch did not start; retry scheduled in 30 seconds", "WARNING")
                            end
                        end)

                        if not triggerOK then
                            addLog("Auto-buy trigger error: " .. tostring(triggerErr), "ERROR")
                            if NPCMonitoring then
                                NPCDeadline = npcClock() + 30
                                updateNPCCountdownDisplay(30)
                                NPCAction.Text = "TRIGGER ERROR  •  RETRY IN 00:30"
                            end
                        end
                        NPCTriggerPending = false
                    end)
                end

                task.wait(0.2)
            end
        end)

        if not loopOK then
            addLog("NPC countdown worker error: " .. tostring(loopErr), "ERROR")
            if NPCMonitoring then
                NPCAction.Text = "TIMER ERROR  •  CHECK ACTIVITY LOG"
            end
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
-- PRESET AUTO-LOAD
--==================================================

local PresetDefinitions = {
    overture = {label="OVERTURE", row=2, req="preset_load_2"},
    new_map = {label="NEW MAP", row=1, req="preset_load_3"},
}

local function loadSelectedPreset(source)
    if PresetLoadBusy then
        addLog("Preset load skipped: another preset request is running", "PRESET")
        return false
    end

    local preset = PresetDefinitions[SelectedPreset]
    if not preset then
        addLog("Preset load failed: unknown preset selection", "ERROR")
        return false
    end

    PresetLoadBusy = true
    local ok, err = pcall(function()
        if not MenuOp or not MenuOp:IsA("RemoteEvent") then
            error("HushNet.menu.op is missing or is not a RemoteEvent")
        end
        local args = {
            [1] = {
                ["back"] = true,
                ["op"] = "presetLoad",
                ["row"] = preset.row,
                ["req"] = preset.req
            }
        }
        MenuOp:FireServer(unpack(args))
    end)
    PresetLoadBusy = false

    if ok then
        addLog(preset.label .. " preset request fired (" .. tostring(source or "manual") .. ")", "PRESET")
        return true
    end

    addLog("Preset load request failed: " .. tostring(err), "ERROR")
    return false
end

local function setSelectedPreset(key)
    if not PresetDefinitions[key] then return end
    SelectedPreset = key
    saveState()
    if PresetSelectionStatus then
        PresetSelectionStatus.Text = "SELECTED  •  " .. PresetDefinitions[key].label
    end
    addLog("Preset selection saved: " .. PresetDefinitions[key].label, "PRESET")
end

local function setAutoLoadPreset(enabled)
    AutoLoadPresetEnabled = enabled == true
    saveState()
    if AutoLoadToggle then
        AutoLoadToggle.Text = AutoLoadPresetEnabled and "AUTOLOAD ON" or "AUTOLOAD OFF"
        AutoLoadToggle.BackgroundColor3 = AutoLoadPresetEnabled and COLORS.green or COLORS.panel3
    end
    addLog("Preset auto-load " .. (AutoLoadPresetEnabled and "enabled" or "disabled"), "PRESET")
end

local function isInGameMap()
    -- HushLocal is the in-map runtime folder used by the Hush game.
    return workspace:FindFirstChild("HushLocal") ~= nil
end

task.spawn(function()
    while true do
        task.wait(1)
        local inMap = isInGameMap()
        if inMap and not LastPresetMapState and AutoLoadPresetEnabled then
            task.wait(1.5) -- allow the map/trader remotes to finish initializing
            if AutoLoadPresetEnabled and isInGameMap() then
                loadSelectedPreset("map entry")
            end
        end
        LastPresetMapState = inMap
    end
end)

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
    Name="Main", Size=UDim2.fromOffset(1120, 760),
    Position=UDim2.new(0.5,-560,0.5,-380),
    BackgroundColor3=COLORS.bg, BorderSizePixel=0,
}, ScreenGui)
addCorner(Main, 14)
addStroke(Main, COLORS.border, 1)

local Top = make("Frame", {
    Size=UDim2.new(1,0,0,66), BackgroundColor3=COLORS.panel,
    BorderSizePixel=0,
}, Main)
addCorner(Top, 14)

local Brand = label(Top, "HUSH  /  CONTROL CENTER", 18, COLORS.text, true)
Brand.Position = UDim2.fromOffset(24, 8)
Brand.Size = UDim2.new(0, 420, 0, 28)

local BrandSub = label(Top, "MARKET INTELLIGENCE  •  NPC AUTO BUY  •  SCRAPPER AUTO SELL", 10, COLORS.muted, false)
BrandSub.Position = UDim2.fromOffset(25, 36)
BrandSub.Size = UDim2.new(0, 500, 0, 18)

local WindowStatus = label(Top, "● SYSTEM READY", 10, COLORS.green, true)
WindowStatus.Position = UDim2.new(1,-220,0,22)
WindowStatus.Size = UDim2.fromOffset(150,22)
WindowStatus.TextXAlignment = Enum.TextXAlignment.Right

local Body -- forward declaration for the minimize callback
local Minimize = button(Top, "—", function()
    Main:SetAttribute("Minimized", not Main:GetAttribute("Minimized"))
    local minimized = Main:GetAttribute("Minimized")
    Main.Size = minimized and UDim2.fromOffset(1120,66) or UDim2.fromOffset(1120,760)
    Body.Visible = not minimized
end, COLORS.panel3, 34, 30)
Minimize.Position = UDim2.new(1,-58,0,18)

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
    BackgroundTransparency=1, Position=UDim2.fromOffset(18,82),
    Size=UDim2.new(1,-36,1,-100),
}, Main)

local Tabs = make("Frame", {
    BackgroundTransparency=1, Size=UDim2.new(1,0,0,42),
}, Body)

local function makeTab(text, x)
    local b = button(Tabs, text, function() end, COLORS.panel2, 204, 38)
    b.Position = UDim2.fromOffset(x,0)
    return b
end

local HomeTab = makeTab("⌂  HOME", 0)
local MarketTab = makeTab("◈  AUTO SNIPE MARKET", 220)
local NPCTab = makeTab("◉  AUTO BUY FROM NPC", 440)
local SettingsTab = makeTab("⚙  SETTINGS", 660)
local AutoSellTab = makeTab("♻  AUTO SELL", 880)

local PageArea = make("Frame", {
    BackgroundTransparency=1, Position=UDim2.fromOffset(0,54),
    Size=UDim2.new(1,0,1,-54),
}, Body)

local HomePage = make("Frame", {
    BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=true,
}, PageArea)

local MarketPage = make("Frame", {
    BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=false,
}, PageArea)

local NPCPage = make("Frame", {
    BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=false,
}, PageArea)

local SettingsPage = make("Frame", {
    BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=false,
}, PageArea)

local AutoSellPage = make("Frame", {
    BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=false,
}, PageArea)

local syncNPCFromGameLabel -- assigned after NPC timer UI is created
local requestSellAllFromHome -- assigned in AUTO SELL module; invoked by HOME button

local function showTab(which)
    local home = which == "HOME"
    local market = which == "MARKET"
    local npc = which == "NPC"
    local settings = which == "SETTINGS"
    local autoSell = which == "AUTOSELL"
    HomePage.Visible = home
    MarketPage.Visible = market
    NPCPage.Visible = npc
    SettingsPage.Visible = settings
    AutoSellPage.Visible = autoSell
    HomeTab.BackgroundColor3 = home and COLORS.accent or COLORS.panel2
    MarketTab.BackgroundColor3 = market and COLORS.accent or COLORS.panel2
    NPCTab.BackgroundColor3 = npc and COLORS.accent or COLORS.panel2
    SettingsTab.BackgroundColor3 = settings and COLORS.accent or COLORS.panel2
    AutoSellTab.BackgroundColor3 = autoSell and COLORS.accent or COLORS.panel2

    -- Do not resync the NPC timer when switching tabs; its deadline stays stable.
end
HomeTab.Activated:Connect(function() showTab("HOME") end)
MarketTab.Activated:Connect(function() showTab("MARKET") end)
NPCTab.Activated:Connect(function() showTab("NPC") end)
SettingsTab.Activated:Connect(function() showTab("SETTINGS") end)
AutoSellTab.Activated:Connect(function() showTab("AUTOSELL") end)

--==================================================
-- AUTO SELL PAGE UI
--==================================================

local AutoSellHeader = make("Frame", {
    BackgroundColor3=COLORS.panel, Size=UDim2.new(1,0,0,72),
    BorderSizePixel=0,
}, AutoSellPage)
addCorner(AutoSellHeader, 9)

local AutoSellTitle = label(AutoSellHeader, "SCRAPPER AUTO SELL", 16, COLORS.text, true)
AutoSellTitle.Position = UDim2.fromOffset(16,9)
AutoSellTitle.Size = UDim2.new(0.55,0,0,24)

AutoSellStatus = label(AutoSellHeader, "AUTO SELL  STARTING...", 10, COLORS.orange, true)
AutoSellStatus.Position = UDim2.fromOffset(16,39)
AutoSellStatus.Size = UDim2.new(1,-32,0,20)

AutoSellSearch = textbox(AutoSellPage, "Search scanned items / sell list...", 430)
AutoSellSearch.Position = UDim2.fromOffset(0,84)
AutoSellSearch.Size = UDim2.fromOffset(430,34)

local AutoSellScanNow = button(AutoSellPage, "SCAN NOW", function()
    scanSellInventory()
    renderAutoSellList()
end, COLORS.blue, 110, 34)
AutoSellScanNow.Position = UDim2.fromOffset(442,84)

AutoSellScanTab = button(AutoSellPage, "SCAN RESULTS", function()
    setAutoSellView("SCAN")
end, COLORS.accent, 150, 34)
AutoSellScanTab.Position = UDim2.fromOffset(562,84)

AutoSellWatchTab = button(AutoSellPage, "SELL LIST", function()
    setAutoSellView("SELL LIST")
end, COLORS.panel2, 130, 34)
AutoSellWatchTab.Position = UDim2.fromOffset(722,84)

AutoSellList = make("ScrollingFrame", {
    Position=UDim2.fromOffset(0,128),
    Size=UDim2.new(1,0,1,-128),
    BackgroundColor3=COLORS.panel,
    BorderSizePixel=0,
    ScrollBarThickness=5,
    ScrollBarImageColor3=COLORS.accent,
    CanvasSize=UDim2.new(0,0,0,0),
    AutomaticCanvasSize=Enum.AutomaticSize.None,
}, AutoSellPage)
addCorner(AutoSellList, 9)

AutoSellListLayout = make("UIListLayout", {
    Padding=UDim.new(0,5),
    SortOrder=Enum.SortOrder.LayoutOrder,
}, AutoSellList)
make("UIPadding", {
    PaddingTop=UDim.new(0,7),
    PaddingBottom=UDim.new(0,7),
    PaddingLeft=UDim.new(0,7),
    PaddingRight=UDim.new(0,7),
}, AutoSellList)

AutoSellSearch:GetPropertyChangedSignal("Text"):Connect(function()
    renderAutoSellList()
end)

--==================================================
-- HOME PAGE UI
--==================================================

local HomeIntro = make("Frame", {
    BackgroundColor3=COLORS.panel, Size=UDim2.new(1,0,0,82),
    BorderSizePixel=0,
}, HomePage)
addCorner(HomeIntro, 10)

local HomeTitle = label(HomeIntro, "HUSH CONTROL CENTER", 18, COLORS.text, true)
HomeTitle.Position = UDim2.fromOffset(18,10)
HomeTitle.Size = UDim2.new(1,-36,0,28)

local HomeSubtitle = label(HomeIntro, "OVERVIEW  •  MARKET WATCH  •  NPC RESTOCK  •  PRESET MANAGER", 10, COLORS.muted, false)
HomeSubtitle.Position = UDim2.fromOffset(19,43)
HomeSubtitle.Size = UDim2.new(1,-38,0,20)

local HomeSellAllButton = button(HomeIntro, "SELL ALL", function()
    if requestSellAllFromHome then
        requestSellAllFromHome()
    else
        addLog("Sell All is not ready yet.", "SELL")
    end
end, COLORS.orange, 118, 34)
HomeSellAllButton.Position = UDim2.new(1,-136,0,23)

local HomeStats = make("Frame", {
    BackgroundTransparency=1, Position=UDim2.fromOffset(0,94),
    Size=UDim2.new(1,0,0,116),
}, HomePage)

local function homeStatCard(parent, titleText, xScale, widthScale)
    local card = make("Frame", {
        BackgroundColor3=COLORS.panel, Position=UDim2.new(xScale,0,0,0),
        Size=UDim2.new(widthScale,-8,1,0), BorderSizePixel=0,
    }, parent)
    addCorner(card, 9)
    local heading = label(card, titleText, 10, COLORS.muted, true)
    heading.Position = UDim2.fromOffset(12,10)
    heading.Size = UDim2.new(1,-24,0,18)
    local value = label(card, "--", 21, COLORS.text, true)
    value.Position = UDim2.fromOffset(12,36)
    value.Size = UDim2.new(1,-24,0,32)
    local detail = label(card, "", 9, COLORS.muted, false)
    detail.Position = UDim2.fromOffset(12,73)
    detail.Size = UDim2.new(1,-24,0,22)
    return value, detail
end

local HomeMarketValue, HomeMarketDetail = homeStatCard(HomeStats, "MARKET MONITOR", 0, 0.25)
local HomeWatchValue, HomeWatchDetail = homeStatCard(HomeStats, "WATCHLIST", 0.25, 0.25)
local HomeNPCValue, HomeNPCDetail = homeStatCard(HomeStats, "NPC AUTO BUY", 0.50, 0.25)
local HomePurchaseValue, HomePurchaseDetail = homeStatCard(HomeStats, "CONFIRMED PURCHASES", 0.75, 0.25)

local PresetPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(0,222),
    Size=UDim2.new(0.58,-7,1,-222), BorderSizePixel=0,
}, HomePage)
addCorner(PresetPanel, 9)

local PresetHeading = label(PresetPanel, "MAP PRESET AUTO-LOAD", 13, COLORS.text, true)
PresetHeading.Position = UDim2.fromOffset(15,12)
PresetHeading.Size = UDim2.new(1,-30,0,24)

local PresetDescription = label(PresetPanel, "Choose which saved in-game preset should load automatically when HushLocal appears (map entry).", 10, COLORS.muted, false)
PresetDescription.Position = UDim2.fromOffset(15,42)
PresetDescription.Size = UDim2.new(1,-30,0,42)
PresetDescription.TextWrapped = true
PresetDescription.TextYAlignment = Enum.TextYAlignment.Top

local OvertureButton = button(PresetPanel, "OVERTURE  •  ROW 2", function()
    setSelectedPreset("overture")
end, SelectedPreset == "overture" and COLORS.accent or COLORS.panel3, 180, 34)
OvertureButton.Position = UDim2.fromOffset(15,98)

local NewMapButton = button(PresetPanel, "NEW MAP  •  ROW 1", function()
    setSelectedPreset("new_map")
end, SelectedPreset == "new_map" and COLORS.accent or COLORS.panel3, 180, 34)
NewMapButton.Position = UDim2.fromOffset(205,98)

PresetSelectionStatus = label(PresetPanel, "SELECTED  •  " .. PresetDefinitions[SelectedPreset].label, 10, COLORS.blue, true)
PresetSelectionStatus.Position = UDim2.fromOffset(15,145)
PresetSelectionStatus.Size = UDim2.new(1,-30,0,20)

AutoLoadToggle = button(PresetPanel, AutoLoadPresetEnabled and "AUTOLOAD ON" or "AUTOLOAD OFF", function()
    setAutoLoadPreset(not AutoLoadPresetEnabled)
end, AutoLoadPresetEnabled and COLORS.green or COLORS.panel3, 130, 34)
AutoLoadToggle.Position = UDim2.fromOffset(15,180)

local LoadPresetNow = button(PresetPanel, "LOAD SELECTED NOW", function()
    loadSelectedPreset("manual button")
end, COLORS.blue, 160, 34)
LoadPresetNow.Position = UDim2.fromOffset(155,180)

local PresetFootnote = label(PresetPanel, "Settings are stored in the Hush Control Center config file when executor file APIs are available.", 9, COLORS.muted, false)
PresetFootnote.Position = UDim2.fromOffset(15,226)
PresetFootnote.Size = UDim2.new(1,-30,0,34)
PresetFootnote.TextWrapped = true

local HomeRight = make("Frame", {
    BackgroundTransparency=1, Position=UDim2.new(0.58,7,0,222),
    Size=UDim2.new(0.42,-7,1,-222),
}, HomePage)

local HomeStatusPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Size=UDim2.new(1,0,0,132),
    BorderSizePixel=0,
}, HomeRight)
addCorner(HomeStatusPanel, 9)

local HomeStatusHeading = label(HomeStatusPanel, "SYSTEM STATUS", 12, COLORS.text, true)
HomeStatusHeading.Position = UDim2.fromOffset(14,10)
HomeStatusHeading.Size = UDim2.new(1,-28,0,22)

HomeStatusText = label(HomeStatusPanel, "READY", 10, COLORS.green, true)
HomeStatusText.Position = UDim2.fromOffset(14,40)
HomeStatusText.Size = UDim2.new(1,-28,0,20)

HomeMapText = label(HomeStatusPanel, "MAP  •  CHECKING...", 10, COLORS.muted, false)
HomeMapText.Position = UDim2.fromOffset(14,68)
HomeMapText.Size = UDim2.new(1,-28,0,20)

HomePresetText = label(HomeStatusPanel, "PRESET AUTOLOAD  •  OFF", 10, COLORS.muted, false)
HomePresetText.Position = UDim2.fromOffset(14,94)
HomePresetText.Size = UDim2.new(1,-28,0,20)

local HomeRecentPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.new(0,0,0,142),
    Size=UDim2.new(1,0,1,-142), BorderSizePixel=0,
}, HomeRight)
addCorner(HomeRecentPanel, 9)

local HomeRecentHeading = label(HomeRecentPanel, "LATEST ACTIVITY", 11, COLORS.text, true)
HomeRecentHeading.Position = UDim2.fromOffset(14,9)
HomeRecentHeading.Size = UDim2.new(1,-28,0,22)

HomeRecentText = label(HomeRecentPanel, "No activity yet.", 9, COLORS.muted, false)
HomeRecentText.Position = UDim2.fromOffset(14,38)
HomeRecentText.Size = UDim2.new(1,-28,1,-48)
HomeRecentText.TextWrapped = true
HomeRecentText.TextYAlignment = Enum.TextYAlignment.Top

local function refreshHomePage()
    if not HomeMarketValue then return end
    HomeMarketValue.Text = Monitoring and "ACTIVE" or "IDLE"
    HomeMarketValue.TextColor3 = Monitoring and COLORS.green or COLORS.orange
    HomeMarketDetail.Text = "Scans: " .. tostring(TotalScans)

    local enabledWatch = 0
    for _, item in ipairs(Watchlist) do
        if item.enabled then enabledWatch += 1 end
    end
    HomeWatchValue.Text = tostring(enabledWatch) .. " / " .. tostring(#Watchlist)
    HomeWatchDetail.Text = "Enabled items"

    HomeNPCValue.Text = NPCMonitoring and "ACTIVE" or "IDLE"
    HomeNPCValue.TextColor3 = NPCMonitoring and COLORS.green or COLORS.orange
    HomeNPCDetail.Text = "Types: " .. tostring(getEnabledAmmoCount())

    HomePurchaseValue.Text = tostring(#PurchaseRecords)
    HomePurchaseDetail.Text = "Units: " .. tostring(PurchaseTotalUnits) .. "  •  $" .. formatNumber(PurchaseTotalSpent)

    HomeStatusText.Text = "SYSTEM  •  " .. ((Monitoring or NPCMonitoring) and "RUNNING" or "READY")
    HomeStatusText.TextColor3 = (Monitoring or NPCMonitoring) and COLORS.green or COLORS.orange
    HomeMapText.Text = isInGameMap() and "MAP  •  IN GAME" or "MAP  •  LOBBY / WAITING"
    HomePresetText.Text = "PRESET AUTOLOAD  •  " .. (AutoLoadPresetEnabled and PresetDefinitions[SelectedPreset].label or "OFF")

    local recent = {}
    for i = 1, math.min(5, #ActivityLog) do
        table.insert(recent, ActivityLog[i])
    end
    HomeRecentText.Text = #recent > 0 and table.concat(recent, "\\n") or "No activity yet."

    OvertureButton.BackgroundColor3 = SelectedPreset == "overture" and COLORS.accent or COLORS.panel3
    NewMapButton.BackgroundColor3 = SelectedPreset == "new_map" and COLORS.accent or COLORS.panel3
end

task.spawn(function()
    while ScreenGui and ScreenGui.Parent do
        refreshHomePage()
        task.wait(1)
    end
end)

--==================================================
-- MARKET PAGE UI
--==================================================

local MarketHeader = make("Frame", {
    BackgroundColor3=COLORS.panel, Size=UDim2.new(1,0,0,88),
    BorderSizePixel=0,
}, MarketPage)
addCorner(MarketHeader, 10)

local MarketTitle = label(MarketHeader, "MARKET SNIPER", 15, COLORS.text, true)
MarketTitle.Position = UDim2.fromOffset(16,7)
MarketTitle.Size = UDim2.fromOffset(220,22)

MarketStatus = label(MarketHeader, "IDLE", 10, COLORS.orange, true)
MarketStatus.Position = UDim2.fromOffset(16,36)
MarketStatus.Size = UDim2.fromOffset(130,20)

ScanCount = label(MarketHeader, "SCANS  0", 10, COLORS.muted, true)
ScanCount.Position = UDim2.fromOffset(150,36)
ScanCount.Size = UDim2.fromOffset(100,20)

local marketButtons = {}
local ForceScan = button(MarketHeader, "FORCE SCAN", function()
    task.spawn(performMarketScan)
end, COLORS.blue, 110, 32)
ForceScan.AnchorPoint = Vector2.new(1,0)
ForceScan.Position = UDim2.new(1,-278,0,27)

local StartMarket = button(MarketHeader, "START MONITOR", startMarketMonitor, COLORS.green, 120, 32)
StartMarket.AnchorPoint = Vector2.new(1,0)
StartMarket.Position = UDim2.new(1,-150,0,27)

local StopMarket = button(MarketHeader, "STOP", stopMarketMonitor, COLORS.red, 90, 32)
StopMarket.AnchorPoint = Vector2.new(1,0)
StopMarket.Position = UDim2.new(1,-12,0,27)

local Form = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(0,100),
    Size=UDim2.new(1,0,0,62), BorderSizePixel=0,
}, MarketPage)
addCorner(Form, 9)

local IdBox = textbox(Form, "Item ID", 240)
IdBox.Position = UDim2.fromOffset(12,8)
local NameBox = textbox(Form, "Display name", 220)
NameBox.Position = UDim2.fromOffset(262,8)
local PriceBox = textbox(Form, "Max price", 150)
PriceBox.Position = UDim2.fromOffset(492,8)

local FormStatus = label(Form, "Enter an item ID, display name (optional), and max price.", 9, COLORS.muted, false)
FormStatus.Position = UDim2.fromOffset(12, 43)
FormStatus.Size = UDim2.new(1, -24, 0, 16)
FormStatus.TextTruncate = Enum.TextTruncate.AtEnd

local AddWatch = button(Form, "ADD / UPDATE", function()
    local ok, err = pcall(function()
        local id = tostring(IdBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local name = tostring(NameBox.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        local priceText = tostring(PriceBox.Text or "")
        local cleanedPrice = priceText:gsub("[%$,]", ""):gsub("%s+", "")
        local price = tonumber(cleanedPrice)

        if id == "" then
            FormStatus.Text = "ERROR: Item ID is required."
            FormStatus.TextColor3 = COLORS.red
            IdBox:CaptureFocus()
            addLog("Add/update rejected: missing Item ID", "WARNING")
            return
        end

        if not validItemId(id) then
            FormStatus.Text = "ERROR: ID must use letters, numbers, _, - or . only."
            FormStatus.TextColor3 = COLORS.red
            IdBox:CaptureFocus()
            addLog("Add/update rejected: invalid item ID '" .. id .. "'", "WARNING")
            return
        end

        if not price or price <= 0 or price == math.huge then
            FormStatus.Text = "ERROR: Max price must be a number greater than zero."
            FormStatus.TextColor3 = COLORS.red
            PriceBox:CaptureFocus()
            addLog("Add/update rejected: invalid max price '" .. priceText .. "'", "WARNING")
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
                id = id,
                name = name ~= "" and name or id,
                maxPrice = price,
                enabled = true,
                autoBuy = false,
                priority = false,
                lastBuyAttempt = 0,
            })
            action = "ADDED"
        end

        Results[id] = nil
        saveState()
        refreshWatchlist()

        FormStatus.Text = action .. ": " .. id .. "  •  MAX $" .. formatNumber(price)
        FormStatus.TextColor3 = COLORS.green

        IdBox.Text = ""
        NameBox.Text = ""
        PriceBox.Text = ""

        addLog(action .. " watchlist item: " .. id .. " @ $" .. formatNumber(price), "WATCHLIST")
    end)

    if not ok then
        FormStatus.Text = "ERROR: " .. tostring(err)
        FormStatus.TextColor3 = COLORS.red
        warn("[HUSH CONTROL] Add/Update failed: " .. tostring(err))
        addLog("Add/update callback error: " .. tostring(err), "ERROR")
    end
end, COLORS.accent, 120, 32)
AddWatch.Position = UDim2.fromOffset(652, 8)

local DelayBox = textbox(Form, "Scan delay", 100)
DelayBox.Position = UDim2.fromOffset(782,8)
DelayBox.Text = tostring(CONFIG.RequestDelay)
local SaveDelay = button(Form, "SAVE DELAY", function()
    local n = tonumber(DelayBox.Text)
    if not n then addLog("Invalid scan delay", "WARNING"); return end
    CONFIG.RequestDelay = math.clamp(n,0.1,60)
    DelayBox.Text = tostring(CONFIG.RequestDelay)
    saveState()
    addLog("Scan delay set to " .. CONFIG.RequestDelay .. "s", "CONFIG")
end, COLORS.panel3, 100, 32)
SaveDelay.Position = UDim2.fromOffset(892,8)

local MarketColumns = make("Frame", {
    BackgroundTransparency=1, Position=UDim2.fromOffset(0,170),
    Size=UDim2.new(1,0,1,-170),
}, MarketPage)

local WatchPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Size=UDim2.new(0.58,-7,1,0),
    BorderSizePixel=0,
}, MarketColumns)
addCorner(WatchPanel, 9)

local WatchHeading = label(WatchPanel, "WATCHLIST  /  LIVE LISTINGS", 12, COLORS.text, true)
WatchHeading.Position = UDim2.fromOffset(14,8)
WatchHeading.Size = UDim2.new(1,-28,0,24)

local WatchScroll = make("ScrollingFrame", {
    BackgroundColor3=COLORS.bg, Position=UDim2.fromOffset(10,40),
    Size=UDim2.new(1,-20,1,-50), BorderSizePixel=0,
    ScrollBarThickness=5, ScrollBarImageColor3=COLORS.accent,
    AutomaticCanvasSize=Enum.AutomaticSize.Y, CanvasSize=UDim2.new(0,0,0,0),
}, WatchPanel)
addCorner(WatchScroll, 7)
make("UIListLayout", {Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder}, WatchScroll)
make("UIPadding", {PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,6),PaddingLeft=UDim.new(0,6),PaddingRight=UDim.new(0,6)}, WatchScroll)

local RightMarket = make("Frame", {
    BackgroundTransparency=1, Position=UDim2.new(0.58,7,0,0),
    Size=UDim2.new(0.42,-7,1,0),
}, MarketColumns)

local GridPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Size=UDim2.new(1,0,0.70,-5),
    BorderSizePixel=0,
}, RightMarket)
addCorner(GridPanel, 9)

local GridHeading = label(GridPanel, "MARKET GRID ID SCANNER", 13, COLORS.text, true)
GridHeading.Position = UDim2.fromOffset(12,8)
GridHeading.Size = UDim2.new(1,-24,0,22)

GridStatus = label(GridPanel, "GRID WAITING — OPEN MARKET", 10, COLORS.orange, true)
GridStatus.Position = UDim2.fromOffset(12,31)
GridStatus.Size = UDim2.new(1,-24,0,18)

local ScanGrid = button(GridPanel, "SCAN GRID", function()
    scanMarketGrid()
    refreshIDList()
end, COLORS.blue, 120, 32)
ScanGrid.Position = UDim2.fromOffset(12,55)

local CopyIDs = button(GridPanel, "COPY ALL IDS", function()
    if #DiscoveredIDs == 0 then addLog("No IDs discovered", "WARNING"); return end
    if safeClipboard(table.concat(DiscoveredIDs,"\n")) then
        addLog("Copied " .. #DiscoveredIDs .. " IDs", "ID SCANNER")
    else
        addLog("Clipboard unavailable", "ERROR")
    end
end, COLORS.panel3, 130, 32)
CopyIDs.AnchorPoint = Vector2.new(1,0)
CopyIDs.Position = UDim2.new(1,-12,0,55)

local SearchID = textbox(GridPanel, "Filter discovered IDs...", 200)
SearchID.Position = UDim2.fromOffset(12,96)
SearchID.Size = UDim2.new(1,-24,0,34)

IDList = make("ScrollingFrame", {
    BackgroundColor3=COLORS.bg, Position=UDim2.fromOffset(10,138),
    Size=UDim2.new(1,-20,1,-148), BorderSizePixel=0,
    ScrollBarThickness=4, AutomaticCanvasSize=Enum.AutomaticSize.Y,
    CanvasSize=UDim2.new(0,0,0,0),
}, GridPanel)
addCorner(IDList, 6)
make("UIListLayout", {Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder}, IDList)
make("UIPadding", {PaddingTop=UDim.new(0,4),PaddingBottom=UDim.new(0,4),PaddingLeft=UDim.new(0,4),PaddingRight=UDim.new(0,4)}, IDList)

local LogPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.new(0,0,0.70,5),
    Size=UDim2.new(1,0,0.30,-5), BorderSizePixel=0,
}, RightMarket)
addCorner(LogPanel, 9)

local LogHeading = label(LogPanel, "ACTIVITY LOG  /  PURCHASE CONFIRMATIONS", 10, COLORS.text, true)
LogHeading.Position = UDim2.fromOffset(12,7)
LogHeading.Size = UDim2.new(1,-24,0,22)

LogList = make("ScrollingFrame", {
    BackgroundColor3=COLORS.bg, Position=UDim2.fromOffset(10,34),
    Size=UDim2.new(1,-20,1,-44), BorderSizePixel=0,
    ScrollBarThickness=4, AutomaticCanvasSize=Enum.AutomaticSize.Y,
    CanvasSize=UDim2.new(0,0,0,0),
}, LogPanel)
addCorner(LogList, 6)
make("UIListLayout", {Padding=UDim.new(0,2),SortOrder=Enum.SortOrder.LayoutOrder}, LogList)
make("UIPadding", {PaddingTop=UDim.new(0,4),PaddingBottom=UDim.new(0,4),PaddingLeft=UDim.new(0,5),PaddingRight=UDim.new(0,5)}, LogList)

--==================================================
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
            BackgroundColor3=COLORS.panel2,
            Size=UDim2.new(1,-4,0,86),
            BorderSizePixel=0,
            LayoutOrder=index,
        }, WatchScroll)
        addCorner(card, 7)

        -- Text area occupies the left side; controls live in a separate right rail.
        local name = label(card, item.name .. "   •   " .. item.id, 11, COLORS.text, true)
        name.Position = UDim2.fromOffset(10,7)
        name.Size = UDim2.new(1,-405,0,20)
        name.TextTruncate = Enum.TextTruncate.AtEnd

        local lowestText = result.success and result.lowest
            and ("LOWEST  $" .. formatNumber(result.lowest))
            or (result.success and "NO ACTIVE LISTINGS"
            or (result.error and "SCAN ERROR" or "WAITING FOR SCAN"))
        local countText = result.success
            and ("LISTINGS  " .. tostring(result.count or 0))
            or "LISTINGS  --"

        local price = label(
            card,
            lowestText .. "     •     " .. countText,
            10,
            result.success and result.lowest and result.lowest <= item.maxPrice
                and COLORS.green or COLORS.muted,
            true
        )
        price.Position = UDim2.fromOffset(10,32)
        price.Size = UDim2.new(1,-405,0,18)
        price.TextTruncate = Enum.TextTruncate.AtEnd

        local max = label(card, "MAX  $" .. formatNumber(item.maxPrice), 10, COLORS.orange, true)
        max.Position = UDim2.fromOffset(10,57)
        max.Size = UDim2.new(1,-405,0,18)

        local function actionButton(text, rightOffset, width, color, callback)
            local b = button(card, text, callback, color, width, 28)
            b.AnchorPoint = Vector2.new(1,0)
            b.Position = UDim2.new(1,-rightOffset,0,29)
            b.TextSize = 9
            return b
        end

        -- Non-overlapping rail: priority | enabled | auto-buy | edit price | delete.
        actionButton(item.priority and "★ PRIORITY" or "☆ PRIORITY", 382, 82,
            item.priority and COLORS.orange or COLORS.panel3, function()
                if item.priority then
                    item.priority = false
                else
                    for _, other in ipairs(Watchlist) do other.priority = false end
                    item.priority = true
                end
                saveState()
                refreshWatchlist()
            end)

        actionButton(item.enabled and "ENABLED" or "DISABLED", 292, 82,
            item.enabled and COLORS.green or COLORS.red, function()
                item.enabled = not item.enabled
                saveState()
                refreshWatchlist()
            end)

        actionButton(item.autoBuy and "AUTO BUY ON" or "AUTO BUY OFF", 202, 82,
            item.autoBuy and COLORS.green or COLORS.panel3, function()
                item.autoBuy = not item.autoBuy
                saveState()
                refreshWatchlist()
            end)

        actionButton("EDIT PRICE", 112, 82, COLORS.blue, function()
            IdBox.Text = item.id
            NameBox.Text = item.name
            PriceBox.Text = tostring(item.maxPrice)
            PriceBox:CaptureFocus()
            FormStatus.Text = "EDITING PRICE: " .. item.name .. " — change Max Price, then ADD / UPDATE."
            FormStatus.TextColor3 = COLORS.blue
            addLog("Edit max price for " .. item.name .. "; change Max Price and press ADD / UPDATE", "WATCHLIST")
        end)

        actionButton("DEL", 8, 44, COLORS.red, function()
            table.remove(Watchlist, index)
            Results[item.id] = nil
            saveState()
            refreshWatchlist()
        end)

        -- A separate compact EDIT action on the first line is not needed:
        -- EDIT PRICE fills all fields, and ADD / UPDATE commits the new max price.
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
            txt.Size=UDim2.new(1,-95,1,0)
            local copy = button(row,"COPY",function()
                if safeClipboard(id) then addLog("Copied ID "..id,"ID SCANNER") end
            end,COLORS.panel3,40,24)
            copy.Position=UDim2.new(1,-86,0,7)
            local add = button(row,"USE",function()
                IdBox.Text=id
                NameBox.Text=id
            end,COLORS.accent,38,24)
            add.Position=UDim2.new(1,-43,0,7)
        end
    end
end

SearchID:GetPropertyChangedSignal("Text"):Connect(refreshIDList)

--==================================================
-- NPC PAGE UI
--==================================================

local NPCHeader = make("Frame", {
    BackgroundColor3=COLORS.panel, Size=UDim2.new(1,0,0,112),
    BorderSizePixel=0,
}, NPCPage)
addCorner(NPCHeader, 10)

local NPCTitle = label(NPCHeader, "NPC AUTO BUY  /  15-MINUTE CYCLE", 15, COLORS.text, true)
NPCTitle.Position=UDim2.fromOffset(18,10)
NPCTitle.Size=UDim2.new(1,-36,0,24)

NPCStatus = label(NPCHeader, "STOPPED", 10, COLORS.orange, true)
NPCStatus.Position=UDim2.fromOffset(18,40)
NPCStatus.Size=UDim2.fromOffset(150,20)

NPCTimer = label(NPCHeader, "NEXT BUY IN  15:00", 24, COLORS.text, true)
NPCTimer.Position=UDim2.fromOffset(18,62)
NPCTimer.Size=UDim2.fromOffset(300,34)

NPCSeconds = label(NPCHeader, "Local 15-minute countdown", 11, COLORS.blue, true)
NPCSeconds.Position=UDim2.fromOffset(330,69)
NPCSeconds.Size=UDim2.fromOffset(250,24)

local NPCButtons = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.fromOffset(0,124),
    Size=UDim2.new(1,0,0,70), BorderSizePixel=0,
}, NPCPage)
addCorner(NPCButtons, 9)

local NPCStart = button(NPCButtons,"START RESTOCK MONITOR",startNPCMonitor,COLORS.green,190,36)
NPCStart.Position=UDim2.fromOffset(14,17)

local NPCStop = button(NPCButtons,"STOP",stopNPCMonitor,COLORS.red,90,36)
NPCStop.Position=UDim2.fromOffset(214,17)

local NPCBuyAll = button(NPCButtons,"BUY ALL NOW",function()
    -- Manual purchase does not start/stop the monitor and does not reset its timer.
    task.spawn(function()
        buyAllNPCAmmo(true)
    end)
end,COLORS.blue,140,36)
NPCBuyAll.Position=UDim2.fromOffset(314,17)

NPCRequests = label(NPCButtons,"REQUESTS SENT  0",10,COLORS.muted,true)
NPCRequests.Position=UDim2.fromOffset(474,13)
NPCRequests.Size=UDim2.fromOffset(220,20)

NPCCycles = label(NPCButtons,"BATCHES  0     •     AMMO TYPES  " .. getEnabledAmmoCount(),10,COLORS.muted,true)
NPCCycles.Position=UDim2.fromOffset(474,35)
NPCCycles.Size=UDim2.fromOffset(300,20)

local NPCBottom = make("Frame", {
    BackgroundTransparency=1, Position=UDim2.fromOffset(0,208),
    Size=UDim2.new(1,0,1,-208),
}, NPCPage)

local AmmoPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Size=UDim2.new(0.58,-7,1,0),
    BorderSizePixel=0,
}, NPCBottom)
addCorner(AmmoPanel,9)

AmmoHeading = label(AmmoPanel,"PURCHASE QUEUE  /  SELECT AMMO",12,COLORS.text,true)
AmmoHeading.Position=UDim2.fromOffset(14,8)
AmmoHeading.Size=UDim2.new(1,-250,0,24)

local AmmoAllOn = button(AmmoPanel,"ALL ON",function()
    for _, ammo in ipairs(ammoList) do ammo.enabled = true end
    saveState()
    refreshAmmoSelectionUI()
    refreshAmmoRows()
    addLog("All ammo types enabled", "NPC CONFIG")
end,COLORS.green,72,26)
AmmoAllOn.Position=UDim2.new(1,-164,0,7)

local AmmoAllOff = button(AmmoPanel,"OPTIONAL OFF",function()
    for _, ammo in ipairs(ammoList) do ammo.enabled = ammo.required == true end
    saveState()
    refreshAmmoSelectionUI()
    refreshAmmoRows()
    addLog("Optional ammo disabled; required 12GA remains ON", "NPC CONFIG")
end,COLORS.red,72,26)
AmmoAllOff.Position=UDim2.new(1,-84,0,7)

local AmmoScroll = make("ScrollingFrame", {
    BackgroundColor3=COLORS.bg, Position=UDim2.fromOffset(10,40),
    Size=UDim2.new(1,-20,1,-50), BorderSizePixel=0,
    ScrollBarThickness=5, AutomaticCanvasSize=Enum.AutomaticSize.Y,
    CanvasSize=UDim2.new(0,0,0,0),
}, AmmoPanel)
addCorner(AmmoScroll,7)
make("UIListLayout",{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder},AmmoScroll)
make("UIPadding",{PaddingTop=UDim.new(0,5),PaddingBottom=UDim.new(0,5),PaddingLeft=UDim.new(0,5),PaddingRight=UDim.new(0,5)},AmmoScroll)

local AmmoRows = {}

function refreshAmmoRows()
    for i, ammo in ipairs(ammoList) do
        local row = AmmoRows[ammo.offer]
        if row and row.Parent then
            local toggle = row:FindFirstChild("Toggle")
            local itemLabel = row:FindFirstChild("AmmoName")
            if toggle then
                toggle.Text = ammo.required and "WAJIB" or (ammo.enabled and "ON" or "OFF")
                toggle.BackgroundColor3 = ammo.required and COLORS.orange or (ammo.enabled and COLORS.green or COLORS.red)
            end
            if itemLabel then
                itemLabel.TextColor3 = ammo.enabled and COLORS.text or COLORS.muted
            end
            row.BackgroundColor3 = ammo.enabled and COLORS.panel2 or COLORS.panel
        end
    end
end

for i, ammo in ipairs(ammoList) do
    local row = make("Frame", {
        BackgroundColor3=COLORS.panel2, Size=UDim2.new(1,-4,0,34),
        BorderSizePixel=0, LayoutOrder=i,
    }, AmmoScroll)
    addCorner(row,5)
    AmmoRows[ammo.offer] = row

    local group = ammo.offer == "cola" and "SCRAPPER" or (i <= 5 and "12GA" or ".308")
    local t = label(row,string.format("%02d   %s   •   %s",i,group,ammo.offer),10,COLORS.text,true)
    t.Name = "AmmoName"
    t.Position=UDim2.fromOffset(9,0)
    t.Size=UDim2.new(1,-235,1,0)

    local detailText = "COUNT "..ammo.count.."   /   REQ "..ammo.req
    if ammo.required then
        detailText = detailText .. "   •   WAJIB DIBELI"
    elseif ammo.offer == "cola" then
        detailText = detailText .. "   •   OPTIONAL"
    end
    local detail = label(row,detailText,9,ammo.required and COLORS.orange or COLORS.muted,true)
    detail.Position=UDim2.new(1,-265,0,0)
    detail.Size=UDim2.fromOffset(170,34)
    detail.TextXAlignment=Enum.TextXAlignment.Right

    local toggle = button(row,ammo.required and "WAJIB" or (ammo.enabled and "ON" or "OFF"),function()
        if ammo.required then
            addLog(ammo.offer .. " is mandatory and cannot be disabled", "NPC CONFIG")
            return
        end
        ammo.enabled = not ammo.enabled
        saveState()
        refreshAmmoSelectionUI()
        refreshAmmoRows()
        addLog(ammo.offer .. " set to " .. (ammo.enabled and "ON" or "OFF"), "NPC CONFIG")
    end,ammo.required and COLORS.orange or (ammo.enabled and COLORS.green or COLORS.red),72,26)
    toggle.Name = "Toggle"
    toggle.AnchorPoint = Vector2.new(1,0.5)
    toggle.Position = UDim2.new(1,-7,0.5,0)
end

refreshAmmoSelectionUI()
refreshAmmoRows()

local NPCInfo = make("Frame", {
    BackgroundColor3=COLORS.panel, Position=UDim2.new(0.58,7,0,0),
    Size=UDim2.new(0.42,-7,1,0), BorderSizePixel=0,
}, NPCBottom)
addCorner(NPCInfo,9)

local InfoHeading = label(NPCInfo,"MONITOR DETAILS",12,COLORS.text,true)
InfoHeading.Position=UDim2.fromOffset(14,10)
InfoHeading.Size=UDim2.new(1,-28,0,24)

NPCAction = label(NPCInfo,"ACTION  IDLE",11,COLORS.orange,true)
NPCAction.Position=UDim2.fromOffset(14,46)
NPCAction.Size=UDim2.new(1,-28,0,28)

NPCSource = label(NPCInfo,"SOURCE  Local 15-minute timer",10,COLORS.muted,false)
NPCSource.Position=UDim2.fromOffset(14,82)
NPCSource.Size=UDim2.new(1,-28,0,44)
NPCSource.TextWrapped=true

local DelayInfo = label(NPCInfo,"TRIGGER DELAY  3 SECONDS",10,COLORS.blue,true)
DelayInfo.Position=UDim2.fromOffset(14,140)
DelayInfo.Size=UDim2.new(1,-28,0,22)

local NPCNote = label(NPCInfo,"The local 15-minute timer counts down independently. At 00:00, it waits 3 seconds and sends the selected ammo requests, then starts the next 15-minute cycle.",10,COLORS.muted,false)
NPCNote.Position=UDim2.fromOffset(14,174)
NPCNote.Size=UDim2.new(1,-28,0,90)
NPCNote.TextWrapped=true
NPCNote.TextYAlignment=Enum.TextYAlignment.Top

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
AntiAFKButton.Position=UDim2.new(1,-340,0,18)

--==================================================
-- PURCHASE REPORT INITIALIZATION / TOAST WATCHER
--==================================================

--==================================================
-- SETTINGS PAGE
--==================================================

local SettingsPanel = make("Frame", {
    BackgroundColor3=COLORS.panel, Size=UDim2.new(1,0,0,470),
    BorderSizePixel=0,
}, SettingsPage)
addCorner(SettingsPanel, 10)

local SettingsTitle = label(SettingsPanel, "AUTOMATION SETTINGS", 16, COLORS.text, true)
SettingsTitle.Position = UDim2.fromOffset(18,14)
SettingsTitle.Size = UDim2.new(1,-36,0,28)

local SettingsSubtitle = label(SettingsPanel,
    "Choose which automation should run automatically when this script is executed.",
    10, COLORS.muted, false)
SettingsSubtitle.Position = UDim2.fromOffset(18,45)
SettingsSubtitle.Size = UDim2.new(1,-36,0,22)

local function makeSettingRow(y, titleText, description, getter, setter)
    local row = make("Frame", {
        BackgroundColor3=COLORS.panel2,
        Position=UDim2.fromOffset(16,y),
        Size=UDim2.new(1,-32,0,76),
        BorderSizePixel=0,
    }, SettingsPanel)
    addCorner(row, 8)

    local heading = label(row, titleText, 12, COLORS.text, true)
    heading.Position = UDim2.fromOffset(13,9)
    heading.Size = UDim2.new(1,-170,0,22)

    local detail = label(row, description, 9, COLORS.muted, false)
    detail.Position = UDim2.fromOffset(13,34)
    detail.Size = UDim2.new(1,-175,0,28)
    detail.TextWrapped = true
    detail.TextYAlignment = Enum.TextYAlignment.Top

    local toggle
    toggle = button(row, getter() and "ON" or "OFF", function()
        setter(not getter())
        toggle.Text = getter() and "ON" or "OFF"
        toggle.BackgroundColor3 = getter() and COLORS.green or COLORS.panel3
        saveState()
        addLog(titleText .. " set to " .. (getter() and "ON" or "OFF"), "SETTINGS")
    end, getter() and COLORS.green or COLORS.panel3, 92, 34)
    toggle.AnchorPoint = Vector2.new(1,0.5)
    toggle.Position = UDim2.new(1,-14,0.5,0)
    return toggle
end

makeSettingRow(82,
    "AUTO SNIPE MARKET",
    "Automatically start the market watchlist scanner after execution.",
    function() return AutoStartMarket end,
    function(value) AutoStartMarket = value end
)

makeSettingRow(168,
    "AUTO RESTOCK BUY",
    "Automatically start the NPC restock monitor and buy enabled queue items on each cycle.",
    function() return AutoStartNPC end,
    function(value) AutoStartNPC = value end
)

makeSettingRow(254,
    "BUY ALL ON EXECUTE",
    "Send one initial BUY ALL NOW batch when the script is first executed.",
    function() return BuyAllOnExecute end,
    function(value) BuyAllOnExecute = value end
)

local AutoSellSettingToggle = makeSettingRow(340,
    "AUTO SELL ITEMS IN SELL LIST",
    "When ON, automatically sends sell requests for scanned items added to SELL LIST. When OFF, scanning continues but no items are sold.",
    function() return AutoSellEnabled end,
    function(value)
        if setAutoSellEnabled then
            setAutoSellEnabled(value)
        else
            AutoSellEnabled = value == true
        end
    end
)

local SettingsFootnote = label(SettingsPanel,
    "Settings are saved automatically when executor file APIs are available. Manual START / STOP buttons remain available.",
    9, COLORS.muted, false)
SettingsFootnote.Position = UDim2.fromOffset(18,426)
SettingsFootnote.Size = UDim2.new(1,-36,0,32)
SettingsFootnote.TextWrapped = true
SettingsFootnote.TextYAlignment = Enum.TextYAlignment.Top

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
-- AUTO SELL MODULE (MERGED)
--==================================================

local AutoSellConfig = {
    ScanInterval = 1,
    SellDelay = 0.15,
    FileName = "HushAutoSell_Watchlist.json",
    ReqMap = {
        -- Confirmed full item names from the original HUSH AUTO SELL v1.0.
        ["Gold Coin Collection"] = 2,
        ["Motherboard"] = 2,
        ["Jewelry Box"] = 6,

        -- Inventory UI labels shown in the current scanner.
        -- These are aliases for the same three confirmed item types above.
        ["GOLD COINS"] = 2, -- Gold Coin Collection
        ["BOARD"] = 2,      -- Motherboard
        ["JEWELRY"] = 6,    -- Jewelry Box
    },
}

local AutoSellSellAllBusy = false

local AutoSellState = {
    Running = false,
    Scanning = false,
    Selling = false,
    Items = {},
    Watchlist = {},
    Search = "",
    Logs = {},
}

local function saveAutoSellWatchlist()
    if type(writefile) ~= "function" then return end
    pcall(function()
        local payload = {
            watchlist = AutoSellState.Watchlist,
            autoSellEnabled = AutoSellEnabled == true,
        }
        writefile(AutoSellConfig.FileName, HttpService:JSONEncode(payload))
    end)
end

local function loadAutoSellWatchlist()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
    local ok, data = pcall(function()
        if not isfile(AutoSellConfig.FileName) then return {} end
        return HttpService:JSONDecode(readfile(AutoSellConfig.FileName))
    end)
    if ok and type(data) == "table" then
        -- New format stores both the list and the master auto-sell switch.
        if type(data.watchlist) == "table" then
            AutoSellState.Watchlist = data.watchlist
            AutoSellEnabled = data.autoSellEnabled == true
        else
            -- Backward compatibility with the previous file format (name=true).
            AutoSellState.Watchlist = data
            AutoSellEnabled = false
        end
    end
end
loadAutoSellWatchlist()
if AutoSellSettingToggle then
    AutoSellSettingToggle.Text = AutoSellEnabled and "ON" or "OFF"
    AutoSellSettingToggle.BackgroundColor3 = AutoSellEnabled and COLORS.green or COLORS.panel3
end

local autoSellLog
setAutoSellEnabled = function(enabled)
    AutoSellEnabled = enabled == true
    saveAutoSellWatchlist()
    if AutoSellSettingToggle then
        AutoSellSettingToggle.Text = AutoSellEnabled and "ON" or "OFF"
        AutoSellSettingToggle.BackgroundColor3 = AutoSellEnabled and COLORS.green or COLORS.panel3
    end
    autoSellLog("Auto Sell " .. (AutoSellEnabled and "ENABLED" or "DISABLED"))
end

autoSellLog = function(message)
    local line = "[" .. os.date("%H:%M:%S") .. "] " .. tostring(message)
    table.insert(AutoSellState.Logs, 1, line)
    while #AutoSellState.Logs > 40 do table.remove(AutoSellState.Logs) end
    addLog(message, "AUTO SELL")
end

local function getSellMenu()
    local ok, result = pcall(function()
        local scripts = Player:WaitForChild("PlayerScripts", 20)
        local client = scripts and scripts:WaitForChild("HushClient", 20)
        local controllers = client and client:WaitForChild("Controllers", 20)
        local module = controllers and controllers:WaitForChild("Menu", 20)
        if not module then error("Menu module not ready") end
        return require(module)
    end)
    if ok then return result end
    autoSellLog("Menu module not ready: " .. tostring(result))
    return nil
end

local SellMenu = nil

local function waitForCharacterTab(timeout)
    local started = os.clock()
    while os.clock() - started < (timeout or 60) do
        local hush = PlayerGui:FindFirstChild("HushMenu")
        local root = hush and hush:FindFirstChild("Root")
        local top = root and root:FindFirstChild("TopBar")
        local tabs = top and top:FindFirstChild("Tabs")
        local characterTab = tabs and tabs:FindFirstChild("Tab_character")
        if characterTab then return true end
        task.wait(0.25)
    end
    return false
end

local function openCharacterInventory()
    if not SellMenu then SellMenu = getSellMenu() end
    if not SellMenu or type(SellMenu.openStash) ~= "function" then
        autoSellLog("Menu.openStash unavailable")
        return false
    end
    local ok, result = pcall(function()
        return SellMenu.openStash()
    end)
    if ok and result == true then
        autoSellLog("Character inventory opened")
        return true
    end
    autoSellLog("openStash did not confirm success: " .. tostring(result))
    return false
end

local function findSellInventoryCells()
    local hushMenu = PlayerGui:FindFirstChild("HushMenu")
    local root = hushMenu and hushMenu:FindFirstChild("Root")
    local pages = root and root:FindFirstChild("Pages")
    local characterPage = pages and pages:FindFirstChild("Page_character")
    local area = characterPage and characterPage:FindFirstChild("Area")
    local body = area and area:FindFirstChild("Body")
    local inventory = body and body:FindFirstChild("Inventory")
    local inventoryUI = inventory and inventory:FindFirstChild("HushInventoryUI")
    local uiBody = inventoryUI and inventoryUI:FindFirstChild("Body")
    local columns = uiBody and uiBody:FindFirstChild("Columns")
    local loot = columns and columns:FindFirstChild("Loot")
    local content = loot and loot:FindFirstChild("Content")
    local scroll = content and content:FindFirstChild("Scroll")
    local stash = scroll and scroll:FindFirstChild("Section_stash")
    local grid = stash and stash:FindFirstChild("Grid_stash")
    return grid and grid:FindFirstChild("Cells")
end

local function getSellItemName(item)
    local direct = item:FindFirstChild("Name", true)
        or item:FindFirstChild("ItemName", true)
        or item:FindFirstChild("Short", true)
    if direct and (direct:IsA("TextLabel") or direct:IsA("TextButton"))
        and direct.Text and direct.Text ~= "" then
        return direct.Text
    end

    for _, attributeName in ipairs({"ItemName", "DisplayName", "Name"}) do
        local value = item:GetAttribute(attributeName)
        if type(value) == "string" and value ~= "" then return value end
    end

    for _, obj in ipairs(item:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            if type(obj.Text) == "string" and obj.Text ~= "" then return obj.Text end
        end
    end
    return nil
end

local function getSellUID(item)
    local uid = item.Name:match("^Item_(.+)$")
    if uid then return uid end
    local attributeUID = item:GetAttribute("UID")
    if type(attributeUID) == "string" and attributeUID ~= "" then return attributeUID end
    return nil
end

scanSellInventory = function()
    if AutoSellState.Scanning then return false end
    AutoSellState.Scanning = true

    local ok, groupedOrError = pcall(function()
        local cells = findSellInventoryCells()
        if not cells then error("Character inventory cells not mounted") end

        local grouped = {}
        for _, item in ipairs(cells:GetChildren()) do
            local uid = getSellUID(item)
            local name = getSellItemName(item)
            if uid and name then
                if not grouped[name] then
                    grouped[name] = {Name=name, UIDs={}, Count=0}
                end
                table.insert(grouped[name].UIDs, uid)
                grouped[name].Count += 1
            end
        end
        return grouped
    end)

    if ok and type(groupedOrError) == "table" then
        AutoSellState.Items = groupedOrError
        if AutoSellStatus then
            local total = 0
            for _, item in pairs(groupedOrError) do total += item.Count end
            AutoSellStatus.Text = "AUTO SELL  ON  •  " .. total .. " ITEMS SCANNED"
            AutoSellStatus.TextColor3 = COLORS.green
        end
    else
        autoSellLog("Inventory scan: " .. tostring(groupedOrError))
        if AutoSellStatus then
            AutoSellStatus.Text = "WAITING FOR CHARACTER INVENTORY"
            AutoSellStatus.TextColor3 = COLORS.orange
        end
    end

    AutoSellState.Scanning = false
    return ok
end

local function addSellWatch(name)
    AutoSellState.Watchlist[name] = true
    saveAutoSellWatchlist()
    autoSellLog("Added to sell list: " .. name .. (AutoSellEnabled and " (auto sell ON)" or " (auto sell currently OFF)"))
end

local function removeSellWatch(name)
    AutoSellState.Watchlist[name] = nil
    saveAutoSellWatchlist()
    autoSellLog("Removed from sell list: " .. name)
end

local function sellWatchedGroup(itemName, manual)
    if AutoSellState.Selling then return false end
    local item = AutoSellState.Items[itemName]
    if not item or #item.UIDs == 0 then return false end

    local req = AutoSellConfig.ReqMap[itemName]
    if not req then
        autoSellLog("Skipped " .. itemName .. " — req mapping is not confirmed")
        return false
    end

    AutoSellState.Selling = true
    local sent, failed = 0, 0

    for _, uid in ipairs(item.UIDs) do
        if not manual and (not AutoSellState.Running or not AutoSellEnabled) then break end
        local ok, err = pcall(function()
            MenuOp:FireServer({
                trader="scrapper",
                uids={uid},
                op="sell",
                req=req,
            })
        end)
        if ok then
            sent += 1
        else
            failed += 1
            warn("[HushAutoSell] Sell request failed:", uid, err)
        end
        task.wait(AutoSellConfig.SellDelay)
    end

    AutoSellState.Selling = false
    autoSellLog(itemName .. " | Requests: " .. sent .. " | Failed: " .. failed)
    task.wait(0.2)
    scanSellInventory()
    return true
end

requestSellAllFromHome = function()
    if AutoSellState.Selling or AutoSellSellAllBusy then
        autoSellLog("Sell All is already running.")
        return
    end

    AutoSellSellAllBusy = true
    HomeSellAllButton.Text = "PREPARING..."
    HomeSellAllButton.Active = false
    HomeSellAllButton.AutoButtonColor = false

    task.spawn(function()
        autoSellLog("Manual SELL ALL started.")
        local opened = false

        -- Navigate to Character inventory and retry briefly in case the game
        -- is still transitioning between menus.
        for attempt = 1, 6 do
            if not ScreenGui or not ScreenGui.Parent then break end
            if openCharacterInventory() then
                opened = true
                break
            end
            task.wait(1)
        end

        if not opened then
            autoSellLog("SELL ALL stopped: could not open Character inventory.")
            AutoSellSellAllBusy = false
            HomeSellAllButton.Text = "SELL ALL"
            HomeSellAllButton.Active = true
            HomeSellAllButton.AutoButtonColor = true
            return
        end

        task.wait(1)
        local scanOk = scanSellInventory()
        if not scanOk then
            autoSellLog("SELL ALL stopped: inventory scan failed.")
        else
            local names = {}
            for name, enabled in pairs(AutoSellState.Watchlist) do
                if enabled == true then
                    table.insert(names, name)
                end
            end
            table.sort(names)

            if #names == 0 then
                autoSellLog("SELL ALL: Sell List is empty.")
            else
                local soldGroups, skippedGroups = 0, 0
                for _, itemName in ipairs(names) do
                    local item = AutoSellState.Items[itemName]
                    if item and item.Count > 0 then
                        local req = AutoSellConfig.ReqMap[itemName]
                        if req then
                            local ok = sellWatchedGroup(itemName, true)
                            if ok then soldGroups += 1 else skippedGroups += 1 end
                            task.wait(0.3)
                        else
                            skippedGroups += 1
                            autoSellLog("SELL ALL skipped " .. itemName .. ": req mapping unavailable.")
                        end
                    end
                end
                autoSellLog("SELL ALL finished | groups sent: " .. soldGroups .. " | skipped: " .. skippedGroups)
            end
        end

        AutoSellSellAllBusy = false
        HomeSellAllButton.Text = "SELL ALL"
        HomeSellAllButton.Active = true
        HomeSellAllButton.AutoButtonColor = true
        renderAutoSellList()
    end)
end

local function startAutoSell()
    if AutoSellState.Running then return end
    AutoSellState.Running = true
    autoSellLog("Auto Sell enabled")

    task.spawn(function()
        while AutoSellState.Running and ScreenGui and ScreenGui.Parent do
            scanSellInventory()

            if AutoSellStatus then
                local total = 0
                for _, scanned in pairs(AutoSellState.Items) do
                    total += scanned.Count or 0
                end
                AutoSellStatus.Text = AutoSellEnabled
                    and ("AUTO SELL  ON  •  " .. total .. " ITEMS SCANNED")
                    or ("SCANNING  •  AUTO SELL OFF  •  " .. total .. " ITEMS")
                AutoSellStatus.TextColor3 = AutoSellEnabled and COLORS.green or COLORS.orange
            end

            -- Inventory scanning remains active, but actual sell requests are
            -- strictly gated by the master switch in Settings.
            if AutoSellState.Running and AutoSellEnabled then
                local names = {}
                for name, enabled in pairs(AutoSellState.Watchlist) do
                    if enabled == true then table.insert(names, name) end
                end
                table.sort(names)

                for _, itemName in ipairs(names) do
                    if not AutoSellState.Running or not AutoSellEnabled then break end
                    local item = AutoSellState.Items[itemName]
                    if item and item.Count > 0 then
                        sellWatchedGroup(itemName)
                        task.wait(0.25)
                    end
                end
            end

            task.wait(AutoSellConfig.ScanInterval)
        end
    end)
end

renderAutoSellList = function()
    if not AutoSellList then return end
    for _, child in ipairs(AutoSellList:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local source = AutoSellCurrentView == "SELL LIST"
        and AutoSellState.Watchlist or AutoSellState.Items
    local names = {}
    for name, value in pairs(source) do
        local include = AutoSellCurrentView == "SELL LIST"
            and value == true
            or AutoSellCurrentView == "SCAN" and type(value) == "table"
        if include and (AutoSellSearch.Text == ""
            or string.find(string.lower(name), string.lower(AutoSellSearch.Text), 1, true)) then
            table.insert(names, name)
        end
    end
    table.sort(names)

    for index, name in ipairs(names) do
        local scanned = AutoSellState.Items[name]
        local count = scanned and scanned.Count or 0
        local row = make("Frame", {
            BackgroundColor3=COLORS.panel2,
            Size=UDim2.new(1,-8,0,52),
            LayoutOrder=index,
            BorderSizePixel=0,
        }, AutoSellList)
        addCorner(row, 7)

        local title = label(row, name, 11, COLORS.text, true)
        title.Position = UDim2.fromOffset(10,5)
        title.Size = UDim2.new(1,-150,0,20)

        local detail = label(row, "SCANNED COUNT  " .. count
            .. (AutoSellConfig.ReqMap[name] and "  •  REQ " .. AutoSellConfig.ReqMap[name]
                or "  •  REQ NOT MAPPED"), 9, COLORS.muted, false)
        detail.Position = UDim2.fromOffset(10,27)
        detail.Size = UDim2.new(1,-150,0,17)

        local watched = AutoSellState.Watchlist[name] == true
        local action = button(row,
            AutoSellCurrentView == "SELL LIST" and "REMOVE" or (watched and "IN SELL LIST" or "ADD TO SELL"),
            function()
                if AutoSellCurrentView == "SELL LIST" or watched then
                    removeSellWatch(name)
                else
                    addSellWatch(name)
                end
                renderAutoSellList()
            end,
            watched and COLORS.red or COLORS.green, 118, 30)
        action.Position = UDim2.new(1,-128,0.5,-15)
    end

    if #names == 0 then
        local empty = label(AutoSellList,
            AutoSellCurrentView == "SELL LIST" and "Sell list is empty — add items from SCAN."
                or "No scanned items. Press SCAN NOW.",
            11, COLORS.muted, false)
        empty.Position = UDim2.fromOffset(10,10)
        empty.Size = UDim2.new(1,-20,0,28)
    end

    AutoSellList.CanvasSize = UDim2.new(0,0,0,AutoSellListLayout.AbsoluteContentSize.Y + 12)
end

setAutoSellView = function(view)
    AutoSellCurrentView = view
    AutoSellScanTab.BackgroundColor3 = view == "SCAN" and COLORS.accent or COLORS.panel2
    AutoSellWatchTab.BackgroundColor3 = view == "SELL LIST" and COLORS.accent or COLORS.panel2
    renderAutoSellList()
end


--==================================================
-- STARTUP / AUTO REFRESH
--==================================================

refreshWatchlist()
refreshIDList()
saveState()
showTab("HOME")
addLog("Hush Control Center initialized", "SYSTEM")
addLog("Market API: menu.get / bmItem; buy op: bmBuyBest", "SYSTEM")
addLog("NPC queue loaded: 5x 12GA + 6x .308", "SYSTEM")

-- Startup automation:
-- Every execution (whether currently in lobby or in a map):
-- 1) Run one initial BUY ALL NOW batch.
-- 2) Start Market Monitor automatically.
-- 3) Start NPC Restock Monitor automatically.
-- Map/lobby transitions do not restart the initial batch or duplicate monitor loops.

local InitialStartupDone = false
local StartupAutomationActive = false

local function runInitialStartup()
    if InitialStartupDone or StartupAutomationActive then return end
    StartupAutomationActive = true
    InitialStartupDone = true

    task.spawn(function()
        -- Give the GUI and all status labels time to finish initializing.
        task.wait(1.5)

        if not ScreenGui or not ScreenGui.Parent then
            StartupAutomationActive = false
            return
        end

        if BuyAllOnExecute then
            addLog("First execution: running initial BUY ALL NOW batch", "STARTUP")
            buyAllNPCAmmo(true)
            task.wait(0.5)
        else
            addLog("Initial BUY ALL NOW skipped (disabled in Settings)", "STARTUP")
        end

        if not ScreenGui or not ScreenGui.Parent then
            StartupAutomationActive = false
            return
        end

        if AutoStartMarket and not Monitoring then
            startMarketMonitor()
            addLog("Startup auto-start: Market Monitor ON", "STARTUP")
        elseif not AutoStartMarket then
            addLog("Market Monitor auto-start disabled in Settings", "STARTUP")
        end

        if AutoStartNPC and not NPCMonitoring then
            startNPCMonitor()
            addLog("Startup auto-start: NPC Restock Monitor ON", "STARTUP")
        elseif not AutoStartNPC then
            addLog("NPC Restock Monitor auto-start disabled in Settings", "STARTUP")
        end

        StartupAutomationActive = false
        addLog("Startup automation completed", "STARTUP")
    end)
end

-- Start once after the complete interface has been created.
runInitialStartup()

-- Auto Sell always starts on execution. Wait for the actual Character tab first
-- so the inventory module is ready before opening and scanning it.
task.spawn(function()
    while ScreenGui and ScreenGui.Parent and not AutoSellState.Running do
        local ready = waitForCharacterTab(8)
        if ready and openCharacterInventory() then
            task.wait(1.5)
            scanSellInventory()
            renderAutoSellList()
            startAutoSell()
            break
        end
        task.wait(2)
    end
end)

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
    AutoSellState.Running = false
    stopMarketMonitor()
    stopNPCMonitor()
    AntiAFKEnabled=false
    if AntiAFKConnection then AntiAFKConnection:Disconnect() end
    for _, connection in ipairs(PurchaseConnections) do
        pcall(function() connection:Disconnect() end)
    end
    saveState()
end)
